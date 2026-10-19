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
 *	mount DEV POINT			read-only mount(2) succeeds
 *	unmount POINT			unmount(2) succeeds
 *	readdir-small DIR COUNT		512-byte getdirentries sees COUNT unique
 *					names, each d_fileno equal to lstat st_ino
 *	readdir-eio DIR			listing DIR fails with EIO
 *	times DIR			DIR/old has mtime 0, DIR/future 0x7fffffff
 *	erofs DIR			every change under DIR fails with EROFS;
 *					statfs says "hammer"
 */
#include <sys/types.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
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

static int
domount(char *dev, const char *point)
{
	struct hammer_args args;

	args.fspec = dev;
	CHECK(mount("hammer", point, MNT_RDONLY, &args) == 0);
	return 0;
}

static int
cmpname(const void *a, const void *b)
{
	return strcmp(*(char * const *)a, *(char * const *)b);
}

static int
readdir_small(const char *dir, int want)
{
	char buf[512], path[1024], **names;
	struct stat st;
	struct dirent *dp;
	long base;
	int fd, n, i, count = 0;

	names = malloc(want * sizeof(*names));
	CHECK(names != NULL);
	CHECK((fd = open(dir, O_RDONLY)) >= 0);
	while ((n = getdirentries(fd, buf, sizeof(buf), &base)) > 0) {
		for (i = 0; i < n; i += dp->d_reclen) {
			dp = (struct dirent *)(buf + i);
			CHECK(dp->d_reclen > 0);
			if (dp->d_fileno == 0)
				continue;
			CHECK(count < want);
			sprintf(path, "%s/%s", dir, dp->d_name);
			CHECK(lstat(path, &st) == 0);
			if (st.st_ino != dp->d_fileno) {
				fprintf(stderr, "%s: d_fileno %lu, st_ino %lu\n", path,
				    (unsigned long)dp->d_fileno, (unsigned long)st.st_ino);
				return 1;
			}
			names[count++] = strdup(dp->d_name);
		}
	}
	CHECK(n == 0);
	close(fd);
	CHECK(count == want);
	qsort(names, count, sizeof(*names), cmpname);
	for (i = 1; i < count; i++)
		CHECK(strcmp(names[i - 1], names[i]) != 0);
	printf("%s: %d unique names, d_fileno == st_ino\n", dir, count);
	return 0;
}

static int
readdir_eio(const char *dir)
{
	char buf[4096];
	long base;
	int fd, n;

	CHECK((fd = open(dir, O_RDONLY)) >= 0);
	while ((n = getdirentries(fd, buf, sizeof(buf), &base)) > 0)
		;
	CHECK(n == -1 && errno == EIO);
	close(fd);
	printf("%s: listing fails with EIO\n", dir);
	return 0;
}

static int
times(const char *dir)
{
	char path[1024];
	struct stat st;

	sprintf(path, "%s/old", dir);
	CHECK(lstat(path, &st) == 0);
	CHECK(st.st_mtime == 0);
	sprintf(path, "%s/future", dir);
	CHECK(lstat(path, &st) == 0);
	CHECK(st.st_mtime == 0x7fffffff);
	printf("mtimes 0 and 0x7fffffff\n");
	return 0;
}

#define EROFS_CHECK(x) do { errno = 0; CHECK((x) == -1 && errno == EROFS); } while (0)

static int
erofs(const char *dir)
{
	char a[1024], b[1024];
	struct statfs sf;

	sprintf(a, "%s/new", dir);
	EROFS_CHECK(open(a, O_CREAT | O_WRONLY, 0644));
	EROFS_CHECK(mkdir(a, 0755));
	sprintf(a, "%s/a", dir);
	sprintf(b, "%s/b", dir);
	EROFS_CHECK(unlink(a));
	EROFS_CHECK(rename(a, b));
	EROFS_CHECK(chmod(a, 0600));
	CHECK(statfs(dir, &sf) == 0);
	CHECK(strcmp(sf.f_fstypename, "hammer") == 0);
	printf("changes fail with EROFS; f_fstypename hammer\n");
	return 0;
}

int
main(int ac, char **av)
{
	if (ac == 6 && strcmp(av[1], "mounterr") == 0)
		return mounterr(av[2], av[3], atoi(av[4]), atoi(av[5]));
	if (ac == 4 && strcmp(av[1], "mount") == 0)
		return domount(av[2], av[3]);
	if (ac == 3 && strcmp(av[1], "unmount") == 0) {
		CHECK(unmount(av[2], 0) == 0);
		return 0;
	}
	if (ac == 4 && strcmp(av[1], "readdir-small") == 0)
		return readdir_small(av[2], atoi(av[3]));
	if (ac == 3 && strcmp(av[1], "readdir-eio") == 0)
		return readdir_eio(av[2]);
	if (ac == 3 && strcmp(av[1], "times") == 0)
		return times(av[2]);
	if (ac == 3 && strcmp(av[1], "erofs") == 0)
		return erofs(av[2]);
	fprintf(stderr, "usage: hammer_io CHECK ARGS (see source)\n");
	return 2;
}
