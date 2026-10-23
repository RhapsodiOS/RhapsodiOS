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
 *	mount-rw DEV POINT		read-write mount(2) succeeds
 *	unmount POINT			unmount(2) succeeds
 *	readdir-small DIR COUNT		512-byte getdirentries sees COUNT unique
 *					names, each d_fileno equal to lstat st_ino
 *	readdir-eio DIR			listing DIR fails with EIO
 *	times DIR			DIR/old has mtime 0, DIR/future 0x7fffffff
 *	erofs DIR			every change under DIR fails with EROFS;
 *					statfs says "hammer"
 *	holes FILE			sparse-file reads (see holes())
 *	mmap FILE			mmap matches read, tail past EOF is zero
 *	readeio FILE			reading FILE fails with EIO
 *	readok FILE			FILE reads to EOF without error
 *	negread FILE			a read at a negative offset fails with EINVAL
 *	lookupeio PATH			looking PATH up fails with EIO
 *	dotdot DIR			DIR/.. (DIR its own parent) fails with EIO
 */
#include <sys/types.h>
#include <sys/mman.h>
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
domount(char *dev, const char *point, int flags)
{
	struct hammer_args args;

	args.fspec = dev;
	CHECK(mount("hammer", point, flags, &args) == 0);
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

/* Rhapsody's libc has no pread(2). */
static ssize_t
pread(int fd, void *buf, size_t n, off_t off)
{
	if (lseek(fd, off, SEEK_SET) == -1)
		return -1;
	return read(fd, buf, n);
}

static int
allzero(const char *p, int n)
{
	while (n-- > 0)
		if (*p++)
			return 0;
	return 1;
}

/*
 * The 512 MiB sparse file has data at 0, at 256 MiB and in its last byte.
 * Holes read as zeros; each data spot read on its own matches the same
 * bytes inside a larger read that straddles an 8 KB block boundary.
 */
static int
holes(const char *path)
{
	static char big[16384];
	char b[16];
	struct stat st;
	off_t mib = 1024 * 1024, end;
	int fd;

	CHECK((fd = open(path, O_RDONLY)) >= 0);
	CHECK(fstat(fd, &st) == 0);
	end = st.st_size;
	CHECK(end == 512 * mib);
	CHECK(pread(fd, b, 16, 0) == 16 && !allzero(b, 16));
	CHECK(pread(fd, big, 16384, 0) == 16384 && bcmp(big, b, 16) == 0);
	CHECK(pread(fd, b, 16, mib) == 16 && allzero(b, 16));
	CHECK(pread(fd, b, 1, 256 * mib - 1) == 1 && b[0] == 0);
	CHECK(pread(fd, b, 16, 256 * mib) == 16 && !allzero(b, 16));
	CHECK(pread(fd, big, 16384, 256 * mib - 8192) == 16384 &&
	      allzero(big, 8192) && bcmp(big + 8192, b, 16) == 0);
	CHECK(pread(fd, big, 8192, end - 8192) == 8192 &&
	      pread(fd, b, 1, end - 1) == 1 && big[8191] == b[0]);
	CHECK(pread(fd, b, 16, end) == 0);
	CHECK(pread(fd, b, 16, end - 4) == 4);
	close(fd);
	printf("%s: holes zero, data consistent, EOF short reads\n", path);
	return 0;
}

/* mmap matches read(), and the last page reads zero past EOF. */
static int
mapcheck(const char *path)
{
	static char buf[65536];
	struct stat st;
	char *m;
	long pg = getpagesize(), len;
	int fd;

	CHECK((fd = open(path, O_RDONLY)) >= 0);
	CHECK(fstat(fd, &st) == 0 && st.st_size < sizeof(buf));
	CHECK(read(fd, buf, sizeof(buf)) == st.st_size);
	len = (st.st_size + pg - 1) / pg * pg;
	m = mmap(0, len, PROT_READ, MAP_SHARED, fd, 0);
	CHECK(m != (char *)-1);
	CHECK(bcmp(m, buf, st.st_size) == 0);
	CHECK(allzero(m + st.st_size, len - st.st_size));
	munmap(m, len);
	close(fd);
	printf("%s: mmap matches read, tail zero\n", path);
	return 0;
}

/* Read a whole file; WANT is 0 for success or the errno read must fail with. */
static int
readall(const char *path, int want)
{
	static char buf[65536];
	int fd, n;

	CHECK((fd = open(path, O_RDONLY)) >= 0);
	while ((n = read(fd, buf, sizeof(buf))) > 0)
		;
	if (want)
		CHECK(n == -1 && errno == want);
	else
		CHECK(n == 0);
	close(fd);
	printf("%s: read %s\n", path, want ? "fails as expected" : "ok");
	return 0;
}

/* A read at a negative offset is refused, not served from before the buffer. */
static int
negread(const char *path)
{
	static char buf[65536];
	int fd;

	CHECK((fd = open(path, O_RDONLY)) >= 0);
	CHECK(lseek(fd, (off_t)-8191, SEEK_SET) == (off_t)-8191);
	errno = 0;
	CHECK(read(fd, buf, sizeof(buf)) == -1 && errno == EINVAL);
	close(fd);
	printf("%s: negative-offset read fails with EINVAL\n", path);
	return 0;
}

/* Looking PATH up fails with EIO (damaged metadata), with no panic. */
static int
lookupeio(const char *path)
{
	struct stat st;

	errno = 0;
	CHECK(lstat(path, &st) == -1 && errno == EIO);
	printf("%s: lookup fails with EIO\n", path);
	return 0;
}

/*
 * DIR claims itself as its parent: "DIR/.." is EIO, and asking to remove it
 * fails rather than relocking DIR.
 */
static int
dotdot(const char *dir)
{
	char path[1024];
	struct stat st;

	sprintf(path, "%s/..", dir);
	errno = 0;
	CHECK(lstat(path, &st) == -1 && errno == EIO);
	CHECK(rmdir(path) == -1);
	printf("%s: .. to itself fails with EIO\n", dir);
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
		return domount(av[2], av[3], MNT_RDONLY);
	if (ac == 4 && strcmp(av[1], "mount-rw") == 0)
		return domount(av[2], av[3], 0);
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
	if (ac == 3 && strcmp(av[1], "holes") == 0)
		return holes(av[2]);
	if (ac == 3 && strcmp(av[1], "mmap") == 0)
		return mapcheck(av[2]);
	if (ac == 3 && strcmp(av[1], "readeio") == 0)
		return readall(av[2], EIO);
	if (ac == 3 && strcmp(av[1], "readok") == 0)
		return readall(av[2], 0);
	if (ac == 3 && strcmp(av[1], "negread") == 0)
		return negread(av[2]);
	if (ac == 3 && strcmp(av[1], "lookupeio") == 0)
		return lookupeio(av[2]);
	if (ac == 3 && strcmp(av[1], "dotdot") == 0)
		return dotdot(av[2]);
	fprintf(stderr, "usage: hammer_io CHECK ARGS (see source)\n");
	return 2;
}
