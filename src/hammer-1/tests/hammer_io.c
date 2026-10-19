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
 * hammer_io CHECK ARGS...: native syscall checks against the HAMMER kernel
 * filesystem, run on a Rhapsody guest by run-native.sh.
 *
 *	mounterr DEV POINT RDONLY ERRNO	mount(2) fails with ERRNO
 */
#include <sys/types.h>
#include <sys/mount.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hammer_mount.h"

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "%s:%d: %s (errno %d)\n", \
	__FILE__, __LINE__, #x, errno); return 1; } } while (0)

static int
mounterr(char *dev, const char *point, int rdonly, int want)
{
	struct hammer_args args;
	int rc;

	args.fspec = dev;
	errno = 0;
	rc = mount("hammer", point, rdonly ? MNT_RDONLY : 0, &args);
	if (rc == 0)
		unmount(point, 0);
	CHECK(rc == -1);
	CHECK(errno == want);
	printf("mount %s %s: errno %d as expected\n", dev,
	       rdonly ? "ro" : "rw", errno);
	return 0;
}

int
main(int ac, char **av)
{
	if (ac == 6 && strcmp(av[1], "mounterr") == 0)
		return mounterr(av[2], av[3], atoi(av[4]), atoi(av[5]));
	fprintf(stderr, "usage: hammer_io mounterr DEV POINT RDONLY ERRNO\n");
	return 2;
}
