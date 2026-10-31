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
 * Rhapsody implementations of the kernel services HAMMER expects.
 */
#include <sys/param.h>
#include <sys/systm.h>
#include <sys/buf.h>
#include <sys/vnode.h>
#include <sys/ucred.h>
#include <vm/vm_kern.h>
#include <mach/vm_param.h>
#include <kern/thread.h>
#include <kern/task.h>
#include "hammer.h"

/*
 * Each block starts with an 8-byte header holding its size (8 keeps the
 * 64-bit on-disk fields aligned).  Page-sized and larger blocks (the
 * 16/64 KB buffers) come from kmem_alloc with their own VM object: under
 * HAMMER's alloc/free churn, kalloc's kernel_object path for large blocks
 * (kmem_alloc_wired/kmem_free) panics in pmap_remove_all on a page that is
 * still wired.  None of HAMMER's callers pass M_NOWAIT for such sizes.
 */
#define HAMMER_KHDR	8

void *
hammer_kmalloc(size_t size, int flags)
{
	vm_offset_t a;
	char *ptr;

	if (size + HAMMER_KHDR >= PAGE_SIZE) {
		if (kmem_alloc(kernel_map, &a,
			       round_page(size + HAMMER_KHDR)) != KERN_SUCCESS)
			return NULL;
		ptr = (char *)a;
	} else {
		ptr = _MALLOC(size + HAMMER_KHDR, M_HAMMER, flags & M_NOWAIT);
		if (ptr == NULL)
			return NULL;
	}
	*(size_t *)ptr = size;
	ptr += HAMMER_KHDR;
	if (flags & M_ZERO)
		bzero(ptr, size);
	return ptr;
}

void
hammer_kfree(void *ptr)
{
	char *base = (char *)ptr - HAMMER_KHDR;
	size_t size;

	if (ptr == NULL)
		return;
	size = *(size_t *)base;
	if (size + HAMMER_KHDR >= PAGE_SIZE)
		kmem_free(kernel_map, (vm_offset_t)base,
			  round_page(size + HAMMER_KHDR));
	else
		_FREE(base, M_HAMMER);
}

char *
hammer_kstrdup(const char *str)
{
	size_t len = strlen(str) + 1;
	char *copy = hammer_kmalloc(len, M_WAITOK);

	bcopy(str, copy, len);
	return copy;
}

/*
 * strtouq for bases 0, 8, 10 and 16, with an optional sign; a leading
 * '-' negates the result, as in libc.  No overflow detection.
 */
u_quad_t
hammer_strtouq(const char *str, char **endp, int base)
{
	const char *s = str;
	u_quad_t v = 0;
	int neg = 0, any = 0, d;

	while (*s == ' ' || *s == '\t')
		s++;
	if (*s == '-' || *s == '+')
		neg = (*s++ == '-');
	if ((base == 0 || base == 16) && s[0] == '0' && (s[1] | 0x20) == 'x') {
		s += 2;
		base = 16;
	} else if (base == 0) {
		base = (*s == '0') ? 8 : 10;
	}
	for (;; s++) {
		if (*s >= '0' && *s <= '9')
			d = *s - '0';
		else if ((*s | 0x20) >= 'a' && (*s | 0x20) <= 'f')
			d = (*s | 0x20) - 'a' + 10;
		else
			break;
		if (d >= base)
			break;
		v = v * base + d;
		any = 1;
	}
	if (endp)
		*endp = (char *)(any ? s : str);
	return neg ? -v : v;
}

/*
 * A small vsnprintf: flags '-' and '0', width, precision for %s, length
 * modifiers h, l, ll, q, j, z and t, and conversions d i u o x X c s p %.
 * 64-bit conversions are what the kernel printf lacks.
 */
static void
put(char **out, char *end, int c, int *count)
{
	if (*out < end)
		*(*out)++ = c;
	(*count)++;
}

int
hammer_vsnprintf(char *buf, size_t size, const char *fmt, va_list ap)
{
	char *out = buf, *end = size ? buf + size - 1 : buf;
	char digits[24], *s;
	int count = 0, left, zero, width, prec, longs, base, upper, neg, n;
	unsigned long long uv;
	long long sv;

	for (; *fmt; ++fmt) {
		if (*fmt != '%') {
			put(&out, end, *fmt, &count);
			continue;
		}
		left = zero = width = longs = 0;
		prec = -1;
		for (++fmt; *fmt == '-' || *fmt == '0'; ++fmt) {
			if (*fmt == '-')
				left = 1;
			else
				zero = 1;
		}
		for (; *fmt >= '0' && *fmt <= '9'; ++fmt)
			width = width * 10 + (*fmt - '0');
		if (*fmt == '.') {
			prec = 0;
			for (++fmt; *fmt >= '0' && *fmt <= '9'; ++fmt)
				prec = prec * 10 + (*fmt - '0');
		}
		for (;; ++fmt) {
			if (*fmt == 'l')
				++longs;
			else if (*fmt == 'q' || *fmt == 'j')
				longs = 2;
			else if (*fmt != 'h' && *fmt != 'z' && *fmt != 't')
				break;
		}
		base = 10;
		upper = neg = 0;
		switch (*fmt) {
		case 'c':
			put(&out, end, va_arg(ap, int), &count);
			continue;
		case 's':
			s = va_arg(ap, char *);
			if (s == NULL)
				s = "(null)";
			n = strlen(s);
			if (prec >= 0 && n > prec)
				n = prec;
			width -= n;
			while (!left && width-- > 0)
				put(&out, end, ' ', &count);
			while (n-- > 0)
				put(&out, end, *s++, &count);
			while (left && width-- > 0)
				put(&out, end, ' ', &count);
			continue;
		case '%':
			put(&out, end, '%', &count);
			continue;
		case 'p':
			uv = (unsigned long)va_arg(ap, void *);
			base = 16;
			put(&out, end, '0', &count);
			put(&out, end, 'x', &count);
			goto number;
		case 'd':
		case 'i':
			sv = longs >= 2 ? va_arg(ap, long long) :
			     longs ? va_arg(ap, long) : va_arg(ap, int);
			if (sv < 0) {
				neg = 1;
				uv = -(unsigned long long)sv;
			} else {
				uv = sv;
			}
			goto number;
		case 'o':
			base = 8;
			goto unsign;
		case 'X':
			upper = 1;
			/* FALLTHROUGH */
		case 'x':
			base = 16;
			/* FALLTHROUGH */
		case 'u':
		unsign:
			uv = longs >= 2 ? va_arg(ap, unsigned long long) :
			     longs ? va_arg(ap, unsigned long) :
			     va_arg(ap, unsigned int);
		number:
			n = 0;
			do {
				int d = uv % base;

				digits[n++] = d < 10 ? '0' + d :
					(upper ? 'A' : 'a') + d - 10;
				uv /= base;
			} while (uv);
			if (neg)
				--width;
			if (neg && zero)
				put(&out, end, '-', &count);
			while (!left && width-- > n)
				put(&out, end, zero ? '0' : ' ', &count);
			if (neg && !zero)
				put(&out, end, '-', &count);
			while (n > 0)
				put(&out, end, digits[--n], &count);
			while (left && width-- > 0)
				put(&out, end, ' ', &count);
			continue;
		default:
			put(&out, end, '%', &count);
			if (*fmt)
				put(&out, end, *fmt, &count);
			else
				--fmt;
			continue;
		}
	}
	if (size)
		*out = 0;
	return count;
}

int
hammer_ksnprintf(char *buf, size_t size, const char *fmt, ...)
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = hammer_vsnprintf(buf, size, fmt, ap);
	va_end(ap);
	return n;
}

void
hammer_kprintf(const char *fmt, ...)
{
	char buf[256];
	va_list ap;

	va_start(ap, fmt);
	hammer_vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	printf("%s", buf);
}

/* Rate limit: at most rate->freq messages per second after a burst. */
void
hammer_krateprintf(struct krate *rate, const char *fmt, ...)
{
	char buf[256];
	va_list ap;

	if (rate->ticks != (int)time.tv_sec) {
		rate->ticks = time.tv_sec;
		if (rate->count > 0)
			rate->count = 0;
	}
	if (rate->count++ >= rate->freq)
		return;
	va_start(ap, fmt);
	hammer_vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	printf("%s", buf);
}

/*
 * The hkprintf family (variadic macros upstream).  prefix is printed
 * before the caller's message.
 */
static void
hammer_vprefixed(struct krate *rate, const char *prefix, const char *fmt,
		 va_list ap)
{
	char buf[256];
	int n;

	n = hammer_ksnprintf(buf, sizeof(buf), "%s", prefix);
	if (n < (int)sizeof(buf))
		hammer_vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
	if (rate)
		hammer_krateprintf(rate, "%s", buf);
	else
		printf("%s", buf);
}

void
hkprintf(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	hammer_vprefixed(NULL, "HAMMER: ", fmt, ap);
	va_end(ap);
}

void
hvkprintf(hammer_volume_t vol, const char *fmt, ...)
{
	char prefix[96];
	va_list ap;

	hammer_ksnprintf(prefix, sizeof(prefix), "HAMMER(%s) ",
			 vol->ondisk ? vol->ondisk->vol_label : "?");
	va_start(ap, fmt);
	hammer_vprefixed(NULL, prefix, fmt, ap);
	va_end(ap);
}

void
hmkprintf(hammer_mount_t hmp, const char *fmt, ...)
{
	char prefix[96];
	va_list ap;

	hammer_ksnprintf(prefix, sizeof(prefix), "HAMMER(%s) ",
			 hmp->mp ? hmp->mp->mnt_stat.f_mntfromname : "?");
	va_start(ap, fmt);
	hammer_vprefixed(NULL, prefix, fmt, ap);
	va_end(ap);
}

void
hkrateprintf(struct krate *rate, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	hammer_vprefixed(rate, "HAMMER: ", fmt, ap);
	va_end(ap);
}

void
hvkrateprintf(struct krate *rate, hammer_volume_t vol, const char *fmt, ...)
{
	char prefix[96];
	va_list ap;

	hammer_ksnprintf(prefix, sizeof(prefix), "HAMMER(%s) ",
			 vol->ondisk ? vol->ondisk->vol_label : "?");
	va_start(ap, fmt);
	hammer_vprefixed(rate, prefix, fmt, ap);
	va_end(ap);
}

void
hmkrateprintf(struct krate *rate, hammer_mount_t hmp, const char *fmt, ...)
{
	char prefix[96];
	va_list ap;

	hammer_ksnprintf(prefix, sizeof(prefix), "HAMMER(%s) ",
			 hmp->mp ? hmp->mp->mnt_stat.f_mntfromname : "?");
	va_start(ap, fmt);
	hammer_vprefixed(rate, prefix, fmt, ap);
	va_end(ap);
}

void
hpanic(const char *fmt, ...)
{
	static char buf[256];
	va_list ap;

	va_start(ap, fmt);
	hammer_vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	panic("hammer: %s", buf);
}

void
hammer_vfs_timestamp(struct timespec *ts)
{
	struct timeval tv;

	microtime(&tv);
	ts->tv_sec = tv.tv_sec;
	ts->tv_nsec = tv.tv_usec * 1000;
}

#undef tsleep	/* the kernel's own, not hammer_rhapsody.h's mapping */

int
hammer_tsleep(void *ident, int flags, const char *wmesg, int timo)
{
	int pri = PRIBIO;

	if (flags & PCATCH)
		pri |= PCATCH;
	return tsleep(ident, pri, (char *)wmesg, timo);
}

/*
 * Read bytes at offset from a block device into dst, MAXBSIZE at a time.
 * The chunks are released normally, so the device's buffer cache can
 * serve repeated reads of the same blocks.
 */
int
hammer_dev_read(struct vnode *devvp, int64_t offset, void *dst, int bytes)
{
	struct buf *bp;
	int chunk, error, bsize = devvp->v_specsize;
	char *p = dst;

	if (bsize <= 0 || (offset % bsize) || (bytes % bsize))
		return EINVAL;
	while (bytes > 0) {
		chunk = bytes > MAXBSIZE ? MAXBSIZE : bytes;
		bp = NULL;
		error = bread(devvp, (daddr_t)(offset / bsize), chunk, NOCRED, &bp);
		if (error == 0 && bp->b_resid)
			error = EIO;
		if (error == 0)
			bcopy(bp->b_data, p, chunk);
		if (bp)
			brelse(bp);
		if (error)
			return error;
		offset += chunk;
		p += chunk;
		bytes -= chunk;
	}
	return 0;
}

/*
 * Write bytes from src to a block device at offset, MAXBSIZE at a time,
 * waiting for each chunk.  The chunking matches hammer_dev_read, so the
 * device buffer cache never holds two differently sized buffers for the
 * same block.
 * shortcut: synchronous 8 KB writes; move to async VOP_STRATEGY with
 * completion ordering when throughput matters.
 */
int
hammer_io_write_sync(struct vnode *devvp, int64_t offset, const void *src,
		     int bytes)
{
	struct buf *bp;
	int chunk, error, bsize = devvp->v_specsize;
	const char *p = src;

	if (bsize <= 0 || (offset % bsize) || (bytes % bsize))
		return EINVAL;
	while (bytes > 0) {
		chunk = bytes > MAXBSIZE ? MAXBSIZE : bytes;
		bp = getblk(devvp, (daddr_t)(offset / bsize), chunk, 0, 0);
		bcopy(p, bp->b_data, chunk);
		if ((error = bwrite(bp)) != 0)
			return error;
		offset += chunk;
		p += chunk;
		bytes -= chunk;
	}
	return 0;
}

/*
 * Kernel threads.  kernel_thread() starts a continuation with no
 * argument, so the function and its argument ride in ith_other.
 */
struct hammer_kthread_start {
	void	(*func)(void *);
	void	*arg;
};

static void
hammer_kthread_trampoline(void)
{
	struct hammer_kthread_start *ks = current_thread()->ith_other;
	void (*func)(void *) = ks->func;
	void *arg = ks->arg;

	hammer_kfree(ks);
	func(arg);
	hammer_kthread_exit();
}

void
hammer_kthread_create(void (*func)(void *), void *arg, thread_t *tdp)
{
	struct hammer_kthread_start *ks;

	ks = hammer_kmalloc(sizeof(*ks), M_WAITOK);
	ks->func = func;
	ks->arg = arg;
	*tdp = kernel_thread(kernel_task, hammer_kthread_trampoline, ks);
}

void
hammer_kthread_exit(void)
{
	(void) thread_terminate(current_thread());
	thread_halt_self();
	/* NOTREACHED */
}

/*
 * hammer_limit_dirtybufspace = min(mem/16, 32 MB) and
 * hammer_limit_inodes = max(mem/65536, 256): 8 MB and 2048 on 128 MB.
 */
void
hammer_rhapsody_limits(long *dirtybufspace, int *inodes)
{
	*dirtybufspace = mem_size / 16;
	if (*dirtybufspace > 32 * 1024 * 1024)
		*dirtybufspace = 32 * 1024 * 1024;
	*inodes = mem_size / 65536;
	if (*inodes < 256)
		*inodes = 256;
}
