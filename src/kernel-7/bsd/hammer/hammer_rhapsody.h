/*
 * Copyright (c) 2026 RhapsodiOS.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 * 3. Neither the name of the copyright holder nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific, prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
 * OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * Kernel glue: the DragonFly kernel interfaces HAMMER is written against,
 * expressed with Rhapsody's.  See PORTING.md for why each is safe.
 *
 * Rhapsody's BSD side runs on a uniprocessor kernel that never preempts
 * kernel-mode code (interrupt returns take ASTs only on the way back to
 * user mode: machdep/i386/catch.c, machdep/ppc/hw_exception.s).  A thread
 * gives up the CPU only when it sleeps, which is exactly when DragonFly
 * releases LWKT tokens, so tokens are no-ops and the atomic operations are
 * plain memory operations.  HAMMER's own locks still sleep and wake.
 */
#ifndef VFS_HAMMER_RHAPSODY_H_
#define VFS_HAMMER_RHAPSODY_H_

#include <sys/param.h>
#include <sys/systm.h>
#include <sys/kernel.h>
#include <sys/malloc.h>
#include <sys/proc.h>
#include <sys/time.h>
#include <sys/vm.h>
#include <stdarg.h>
#include <miscfs/specfs/specdev.h>
#include "hammer_port.h"

typedef long long		intmax_t;
typedef unsigned long long	uintmax_t;

/*
 * DragonFly's no-history file flags.  They are stored in the inode's
 * uflags on disk, so the values must match DragonFly's.
 */
#ifndef UF_NOHISTORY
#define UF_NOHISTORY	0x00000040
#endif
#ifndef SF_NOHISTORY
#define SF_NOHISTORY	0x00400000
#endif

/* Assertions */
#define KKASSERT(exp)							\
	do {								\
		if (!(exp))						\
			panic("hammer: assertion \"%s\" failed at %s:%d",\
			      #exp, __FILE__, __LINE__);		\
	} while (0)
#ifndef KASSERT
#define KASSERT(exp, msg)	KKASSERT(exp)
#endif

/* Console output: the kernel printf has no 64-bit or snprintf support. */
struct krate {
	int	freq;
	int	ticks;
	int	count;
};
int	hammer_vsnprintf(char *buf, size_t size, const char *fmt, va_list ap);
int	hammer_ksnprintf(char *buf, size_t size, const char *fmt, ...);
void	hammer_kprintf(const char *fmt, ...);
void	hammer_krateprintf(struct krate *rate, const char *fmt, ...);
#define kprintf		hammer_kprintf
#define ksnprintf	hammer_ksnprintf
#define krateprintf	hammer_krateprintf

/* Memory: one malloc type; _MALLOC does not zero, so M_ZERO is ours. */
#ifndef M_ZERO
#define M_ZERO		0x0100
#endif
#define M_USE_RESERVE	0		/* no reserve pool to dip into */
struct malloc_type;
void	*hammer_kmalloc(size_t size, int flags);
void	hammer_kfree(void *ptr);
char	*hammer_kstrdup(const char *str);
#define kmalloc(size, type, flags)	hammer_kmalloc((size), (flags))
#define kfree(ptr, type)		hammer_kfree(ptr)
#define kstrdup(str, type)		hammer_kstrdup(str)

/* The kernel has no strtouq; hammer_str_to_tid parses "0x..." and "-1". */
u_quad_t hammer_strtouq(const char *str, char **endp, int base);
#define strtouq(str, endp, base)	hammer_strtouq((str), (endp), (base))

/* Upstream drops into ddb and carries on; report and carry on instead. */
#define Debugger(msg)	printf("hammer: %s\n", (msg))
#define kmalloc_create(typep, name)	(*(typep) = NULL)
#define kmalloc_destroy(typep)		(*(typep) = NULL)
#define kmalloc_raise_limit(type, bytes) ((void)0)
#define MALLOC_DECLARE(type)
#define MALLOC_DEFINE(type, shortdesc, longdesc)

/* LWKT tokens and critical sections: no-ops (see above). */
struct lwkt_token {
	int	unused;
};
#define lwkt_token_init(tok, desc)	((void)0)
#define lwkt_token_uninit(tok)		((void)0)
#define lwkt_gettoken(tok)		((void)0)
#define lwkt_reltoken(tok)		((void)0)
#define crit_enter()			((void)0)
#define crit_exit()			((void)0)
/* Long B-tree scans yield to user processes on DragonFly; nothing to do here. */
#define lwkt_user_yield()		((void)0)
/*
 * DragonFly's free-page tests (the allocator and the inode flush).  The
 * dirty-buffer limit (hammer_rhapsody_limits) bounds HAMMER's own memory.
 */
#define vm_paging_min_dnc(pages)	0
#define vm_paging_severe()		0

/* Threads */
#define curthread	current_thread()

/*
 * Kernel threads (the flusher): a Mach kernel thread in kernel_task.
 * hammer_kthread_exit() does not return.
 */
void	hammer_kthread_create(void (*func)(void *), void *arg, thread_t *tdp);
void	hammer_kthread_exit(void);
#define lwkt_exit()	hammer_kthread_exit()

/* Dirty-buffer and inode limits, scaled to physical memory at init. */
void	hammer_rhapsody_limits(long *dirtybufspace, int *inodes);

/* Atomics: plain operations on a non-preemptive uniprocessor. */
static __inline int
atomic_cmpset_int(volatile u_int *p, u_int expect, u_int value)
{
	if (*p != expect)
		return 0;
	*p = value;
	return 1;
}

static __inline u_int
atomic_fetchadd_int(volatile u_int *p, u_int v)
{
	u_int old = *p;

	*p = old + v;
	return old;
}

#define atomic_add_int(p, v)		(*(p) += (v))
#define atomic_subtract_int(p, v)	(*(p) -= (v))
#define atomic_set_int(p, v)		(*(p) |= (v))
#define atomic_clear_int(p, v)		(*(p) &= ~(v))
#define atomic_add_long(p, v)		(*(p) += (v))
#define cpu_ccfence()			((void)0)
#define cpu_lfence()			((void)0)
#define cpu_sfence()			((void)0)
#define cpu_mfence()			((void)0)
#define cpu_pause()			((void)0)

/* Sleeping: nothing runs between a check and the sleep that follows it. */
#ifndef PINTERLOCKED
#define PINTERLOCKED	0x0400
#endif
int	hammer_tsleep(void *ident, int flags, const char *wmesg, int timo);
#define tsleep(ident, flags, wmesg, timo) \
	hammer_tsleep((ident), (flags), (wmesg), (timo))
#define tsleep_interlock(ident, flags)	((void)0)

/* Time */
#define time_uptime	((long)time.tv_sec)
#define time_second	((long)time.tv_sec)
/* DragonFly's ticks; Rhapsody keeps only the time of day. */
#define hammer_ticks()	((int)(time.tv_sec * hz + time.tv_usec / (1000000 / hz)))
#define getmicrotime(tvp)	microtime(tvp)
void	hammer_vfs_timestamp(struct timespec *ts);
#define vfs_timestamp(ts)	hammer_vfs_timestamp(ts)

/* UUIDs on disk are compared bytewise. */
#define kuuid_compare(a, b)	bcmp((a), (b), sizeof(*(a)))

/* Device reads in MAXBSIZE chunks; offset and bytes are DEV_BSIZE multiples. */
struct vnode;
int	hammer_dev_read(struct vnode *devvp, int64_t offset, void *dst, int bytes);
int	hammer_io_write_sync(struct vnode *devvp, int64_t offset,
			     const void *src, int bytes);

#endif /* !VFS_HAMMER_RHAPSODY_H_ */
