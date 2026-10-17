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
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <dev/disk.h>
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include "compat.h"

/* Older exported headers lack the partition query added for ext2. */
#ifndef DKIOCGPARTINFO
struct disk_partition_info {
	u_int32_t block_size;
	u_int32_t block_count;
};
#define DKIOCGPARTINFO	_IOR('d', 29, struct disk_partition_info)
#endif

/* The tools are single-threaded, so seek-then-transfer is safe. */
ssize_t
pread(int fd, void *buf, size_t nbytes, off_t offset)
{
	if (lseek(fd, offset, SEEK_SET) == -1)
		return (-1);
	return (read(fd, buf, nbytes));
}

ssize_t
pwrite(int fd, const void *buf, size_t nbytes, off_t offset)
{
	if (lseek(fd, offset, SEEK_SET) == -1)
		return (-1);
	return (write(fd, buf, nbytes));
}

void
hexdump(const void *ptr, int length, const char *hdr, int flags)
{
	const unsigned char *p = ptr;
	int i, j;

	(void)flags;
	for (i = 0; i < length; i += 16) {
		printf("%s%04x  ", hdr ? hdr : "", i);
		for (j = 0; j < 16; ++j) {
			if (i + j < length)
				printf("%02x ", p[i + j]);
			else
				printf("   ");
		}
		printf(" |");
		for (j = 0; j < 16 && i + j < length; ++j)
			putchar(isprint(p[i + j]) ? p[i + j] : '.');
		printf("|\n");
	}
}

int
hammer_device_size(int fd, u_int64_t *bytes)
{
	struct disk_partition_info part;
	struct stat st;

	if (fstat(fd, &st) < 0)
		return (-1);
	if (S_ISREG(st.st_mode)) {
		*bytes = st.st_size;
		return (0);
	}
	if (!S_ISCHR(st.st_mode) && !S_ISBLK(st.st_mode)) {
		errno = ENODEV;
		return (-1);
	}
	if (ioctl(fd, DKIOCGPARTINFO, &part) < 0)
		return (-1);
	if (part.block_size == 0 || part.block_count == 0) {
		errno = EINVAL;
		return (-1);
	}
	*bytes = (u_int64_t)part.block_size * part.block_count;
	return (0);
}
