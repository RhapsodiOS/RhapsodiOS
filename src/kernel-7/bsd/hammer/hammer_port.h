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
 * Portability layer shared by the HAMMER kernel code and its tools.
 *
 * HAMMER stores every multi-byte on-disk field little-endian.  On-disk
 * structures declare those fields with the wrapper types below, so any
 * access that bypasses hget*() / hmk*() fails to compile on every CPU.
 */
#ifndef VFS_HAMMER_PORT_H_
#define VFS_HAMMER_PORT_H_

#include <sys/types.h>

#ifdef HAMMER_PORTABLE_TEST
#include <stdint.h>
#include <stddef.h>
#include <endian.h>
#else
#include <machine/endian.h>

/* Rhapsody's <sys/types.h> has intN_t and u_intN_t but no uintN_t. */
#ifndef HAMMER_HAVE_UINTN
#define HAMMER_HAVE_UINTN
typedef u_int8_t	uint8_t;
typedef u_int16_t	uint16_t;
typedef u_int32_t	uint32_t;
typedef u_int64_t	uint64_t;
typedef unsigned long	uintptr_t;
#endif
#endif /* HAMMER_PORTABLE_TEST */

#ifndef rounddown
#define rounddown(x, y)	(((x) / (y)) * (y))
#endif

/* 4.4BSD-Lite <sys/queue.h> predates the accessor and iterator macros. */
#include <sys/queue.h>
#ifndef TAILQ_HEAD_INITIALIZER
#define TAILQ_HEAD_INITIALIZER(head)	{ NULL, &(head).tqh_first }
#endif
#ifndef TAILQ_FIRST
#define TAILQ_FIRST(head)		((head)->tqh_first)
#endif
#ifndef TAILQ_NEXT
#define TAILQ_NEXT(elm, field)		((elm)->field.tqe_next)
#endif
#ifndef TAILQ_EMPTY
#define TAILQ_EMPTY(head)		((head)->tqh_first == NULL)
#endif
#ifndef TAILQ_FOREACH
#define TAILQ_FOREACH(var, head, field)					\
	for ((var) = TAILQ_FIRST(head); (var); (var) = TAILQ_NEXT(var, field))
#endif

#ifndef __cplusplus
#ifndef HAMMER_HAVE_BOOL
#define HAMMER_HAVE_BOOL
typedef int bool;
#define true	1
#define false	0
#endif
#endif

#ifndef offsetof
#define offsetof(type, member)	((size_t)(&((type *)0)->member))
#endif

#ifndef __packed
#define __packed	__attribute__((__packed__))
#endif
#ifndef __unused
#define __unused
#endif
#ifndef __always_inline
#define __always_inline	__inline
#endif
#ifndef __noinline
#define __noinline
#endif
#ifndef __debugvar
#define __debugvar
#endif
#ifndef __dead2
#define __dead2		__attribute__((__noreturn__))
#endif

typedef struct { uint16_t le_; } hle16_t;
typedef struct { uint32_t le_; } hle32_t;
typedef struct { uint64_t le_; } hle64_t;

#if BYTE_ORDER == LITTLE_ENDIAN && !defined(HAMMER_TEST_SWAP)
#define HAMMER_SWAP16(x)	(x)
#define HAMMER_SWAP32(x)	(x)
#define HAMMER_SWAP64(x)	(x)
#else
#define HAMMER_SWAP16(x)	((uint16_t)((((x) & 0xff) << 8) | (((x) >> 8) & 0xff)))
#define HAMMER_SWAP32(x)						\
	((uint32_t)((((x) & 0xff) << 24) | (((x) & 0xff00) << 8) |	\
		    (((x) >> 8) & 0xff00) | (((x) >> 24) & 0xff)))
#define HAMMER_SWAP64(x)						\
	(((uint64_t)HAMMER_SWAP32((uint32_t)(x)) << 32) |		\
	 (uint64_t)HAMMER_SWAP32((uint32_t)((x) >> 32)))
#endif

static __inline uint16_t hget16(hle16_t v) { return HAMMER_SWAP16(v.le_); }
static __inline uint32_t hget32(hle32_t v) { return HAMMER_SWAP32(v.le_); }
static __inline uint64_t hget64(hle64_t v) { return HAMMER_SWAP64(v.le_); }

static __inline hle16_t
hmk16(uint16_t x)
{
	hle16_t v;

	v.le_ = HAMMER_SWAP16(x);
	return v;
}

static __inline hle32_t
hmk32(uint32_t x)
{
	hle32_t v;

	v.le_ = HAMMER_SWAP32(x);
	return v;
}

static __inline hle64_t
hmk64(uint64_t x)
{
	hle64_t v;

	v.le_ = HAMMER_SWAP64(x);
	return v;
}

/* On-disk UUID: RFC 4122 fields, integer members little-endian. */
typedef struct hammer_uuid {
	hle32_t		time_low;
	hle16_t		time_mid;
	hle16_t		time_hi_and_version;
	uint8_t		clock_seq_hi_and_reserved;
	uint8_t		clock_seq_low;
	uint8_t		node[6];
} hammer_uuid_t;

#endif /* !VFS_HAMMER_PORT_H_ */
