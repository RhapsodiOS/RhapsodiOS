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
 * Rhapsody libc gaps the HAMMER tools need.  Rhapsody's printf takes %q
 * for 64-bit conversions; %ll and %j are not supported.
 */
#ifndef HAMMER_COMPAT_H_
#define HAMMER_COMPAT_H_

#include <sys/types.h>

typedef long long		intmax_t;
typedef unsigned long long	uintmax_t;

#ifndef ULLONG_MAX
#define ULLONG_MAX	0xFFFFFFFFFFFFFFFFULL
#endif
#ifndef LLONG_MAX
#define LLONG_MAX	0x7FFFFFFFFFFFFFFFLL
#endif
#ifndef LLONG_MIN
#define LLONG_MIN	(-LLONG_MAX - 1LL)
#endif

#define strtoull	strtouq
#define strtoll		strtoq

ssize_t	pread(int fd, void *buf, size_t nbytes, off_t offset);
ssize_t	pwrite(int fd, const void *buf, size_t nbytes, off_t offset);

/*
 * Size in bytes of a regular file or of the disk partition behind a
 * device (DKIOCNUMBLKS x DKIOCBLKSIZE).  Returns 0, or -1 with errno set.
 */
int	hammer_device_size(int fd, u_int64_t *bytes);

/* libutil hexdump(3) with flags 0: offset, 16 hex bytes, ASCII. */
void	hexdump(const void *ptr, int length, const char *hdr, int flags);

#endif /* !HAMMER_COMPAT_H_ */
