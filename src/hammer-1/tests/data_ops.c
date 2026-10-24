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
 * data_ops MODE ROOT: file data workloads for HAMMER.
 *
 *	write		make the data-ops files under ROOT (a fresh volume)
 *	verify		check every byte, size, mode, owner and time that
 *			"write" left
 *	verify-remount	the same after a remount (see remounted below)
 *	unlinked	an open file is unlinked: it stays readable and
 *			writable through its descriptor, the name is gone,
 *			and the inode goes at the last close
 *	durable		write and fsync a file, then keep writing (the caller
 *			crashes the system)
 *	durable-check	the fsynced part of that file is intact
 *
 * Every mismatch prints a FAIL line; the exit status is 1 if there was
 * any.  The same source builds on DragonFly (C89 and POSIX, plus mmap).
 */
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MIB	(1024L * 1024L)

static const char *root;
static int failures;
/*
 * verify-remount: the volume was unmounted since "write".  Stores through
 * a MAP_SHARED mapping need not have reached the file then: Rhapsody has
 * no msync(), and its VM writes such pages back only if the pageout
 * daemon cleans them, for every filesystem.
 */
static int remounted;
static char buf[65536];

static const char *
p(const char *rel)
{
	static char path[1024];

	sprintf(path, "%s/%s", root, rel);
	return path;
}

static void
fail(const char *what)
{
	printf("FAIL %s (errno %d)\n", what, errno);
	failures++;
}

/* The pattern byte of file SEED at offset OFF. */
static int
pat(int seed, long off)
{
	return (int)((off * 7 + off / 4093 + seed * 31) & 0xff);
}

static void
fill(int seed, long off, char *dst, int n)
{
	int i;

	for (i = 0; i < n; i++)
		dst[i] = (char)pat(seed, off + i);
}

/* Write LEN pattern bytes at OFF through FD, in chunks of CHUNK. */
static int
put(int fd, int seed, long off, long len, int chunk)
{
	int n;

	if (lseek(fd, (off_t)off, SEEK_SET) == -1)
		return -1;
	while (len > 0) {
		n = len > chunk ? chunk : (int)len;
		fill(seed, off, buf, n);
		if (write(fd, buf, n) != n)
			return -1;
		off += n;
		len -= n;
	}
	return 0;
}

static void
mkpattern(const char *name, int seed, long size, int chunk)
{
	int fd = open(p(name), O_WRONLY | O_CREAT | O_TRUNC, 0644);

	if (fd == -1 || put(fd, seed, 0, size, chunk) != 0 || close(fd) != 0)
		fail(name);
}

/*
 * Expected byte of each file at OFF: -1 past EOF.  The layout here is
 * the single description of what "write" makes.
 */
struct file {
	const char	*name;
	long		size;
	int		seed;
};

static struct file files[] = {
	{ "s0", 0, 1 }, { "s1", 1, 2 }, { "s16383", 16383, 3 },
	{ "s16385", 16385, 4 }, { "s1048577", 1048577, 5 },
	{ "s64m", 64 * MIB, 6 }, { "app", 15000, 7 }, { "mid", 100000, 8 },
	{ "hole", 3 * MIB + 6, 9 }, { "trunc", 40000, 10 },
	{ "tail", 30001, 11 }, { "trunc2", 1536 * 1024 + 1, 12 },
	{ "map", 20000, 13 }, { 0, 0, 0 }
};

static int
expect_byte(const struct file *f, long off)
{
	if (off >= f->size)
		return -1;
	if (strcmp(f->name, "mid") == 0 && off >= 50000 && off < 53000)
		return 0xAB;
	if (strcmp(f->name, "hole") == 0)
		return off == 3 * MIB + 5 ? pat(f->seed, 0) : 0;
	if (strcmp(f->name, "trunc") == 0 && off >= 20001)
		return 0;
	if (strcmp(f->name, "trunc2") == 0) {
		if (off == 1536 * 1024)
			return pat(f->seed, 1);
		if (off >= MIB + 12345)
			return 0;
	}
	if (strcmp(f->name, "map") == 0 && off >= 100 && off < 200)
		return remounted ? -2 : 'M';
	return pat(f->seed, off);
}

static int
do_write(void)
{
	struct timeval tv[2];
	char *m;
	int fd;

	mkpattern("s0", 1, 0, 8192);
	mkpattern("s1", 2, 1, 8192);
	mkpattern("s16383", 3, 16383, 8192);
	mkpattern("s16385", 4, 16385, 5000);
	mkpattern("s1048577", 5, 1048577, 65536);
	mkpattern("s64m", 6, 64 * MIB, 65536);

	/* append */
	mkpattern("app", 7, 10000, 8192);
	if ((fd = open(p("app"), O_WRONLY | O_APPEND)) == -1)
		fail("open app");
	fill(7, 10000, buf, 5000);
	if (write(fd, buf, 5000) != 5000 || close(fd) != 0)
		fail("append app");

	/* overwrite in the middle */
	mkpattern("mid", 8, 100000, 8192);
	if ((fd = open(p("mid"), O_WRONLY)) == -1)
		fail("open mid");
	memset(buf, 0xAB, 3000);
	if (lseek(fd, 50000L, SEEK_SET) == -1 || write(fd, buf, 3000) != 3000 ||
	    close(fd) != 0)
		fail("overwrite mid");

	/* a write past EOF leaves a hole */
	if ((fd = open(p("hole"), O_WRONLY | O_CREAT, 0644)) == -1 ||
	    put(fd, 9, 0, 0, 1) != 0)
		fail("open hole");
	buf[0] = (char)pat(9, 0);
	if (lseek(fd, 3 * MIB + 5, SEEK_SET) == -1 || write(fd, buf, 1) != 1 ||
	    close(fd) != 0)
		fail("write hole");

	/* truncate into the middle of a block, then grow again */
	mkpattern("trunc", 10, 40000, 8192);
	if (truncate(p("trunc"), 20001) != 0 || truncate(p("trunc"), 40000) != 0)
		fail("truncate trunc");

	/* a partial last block */
	mkpattern("tail", 11, 30001, 7000);

	/* the same in the 64 KB block range, then a byte past EOF */
	mkpattern("trunc2", 12, 2 * MIB, 65536);
	if (truncate(p("trunc2"), MIB + 12345) != 0)
		fail("truncate trunc2");
	if ((fd = open(p("trunc2"), O_WRONLY)) == -1)
		fail("open trunc2");
	buf[0] = (char)pat(12, 1);
	if (lseek(fd, 1536L * 1024, SEEK_SET) == -1 || write(fd, buf, 1) != 1 ||
	    close(fd) != 0)
		fail("write trunc2");

	/* attributes */
	if (chmod(p("s1"), 0600) != 0)
		fail("chmod s1");
	if (chown(p("s16383"), 123, 45) != 0)
		fail("chown s16383");
	tv[0].tv_sec = 1000000000;
	tv[0].tv_usec = 0;
	tv[1].tv_sec = 1200000000;
	tv[1].tv_usec = 0;
	if (utimes(p("s16385"), tv) != 0)
		fail("utimes s16385");

	/* a shared mapping, written and synced */
	mkpattern("map", 13, 20000, 8192);
	if ((fd = open(p("map"), O_RDWR)) == -1)
		fail("open map");
	m = mmap(0, 20000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (m == (char *)-1) {
		fail("mmap map");
	} else {
		memset(m + 100, 'M', 100);
		/*
		 * Rhapsody's libc has no msync(); its fsync() writes a
		 * mapped file's dirty pages first, as DragonFly's does.
		 */
		if (fsync(fd) != 0)
			fail("fsync map");
		munmap(m, 20000);
	}
	close(fd);
	return 0;
}

static void
verify_file(const struct file *f)
{
	struct stat st;
	long off;
	int fd, n, i, want;
	char what[128];

	if (lstat(p(f->name), &st) != 0) {
		fail(f->name);
		return;
	}
	if ((long)st.st_size != f->size) {
		printf("FAIL %s: size %ld, want %ld\n", f->name,
		       (long)st.st_size, f->size);
		failures++;
	}
	if ((fd = open(p(f->name), O_RDONLY)) == -1) {
		fail(f->name);
		return;
	}
	for (off = 0;; off += n) {
		n = read(fd, buf, sizeof(buf));
		if (n <= 0)
			break;
		for (i = 0; i < n; i++) {
			want = expect_byte(f, off + i);
			if (want == -2 && ((buf[i] & 0xff) == 'M' ||
			    (buf[i] & 0xff) == pat(f->seed, off + i)))
				continue;
			if (want != (buf[i] & 0xff)) {
				sprintf(what, "%s: byte %ld is %d, want %d",
					f->name, off + i, buf[i] & 0xff, want);
				printf("FAIL %s\n", what);
				failures++;
				close(fd);
				return;
			}
		}
	}
	if (n < 0)
		fail(f->name);
	close(fd);
}

static int
do_verify(void)
{
	struct stat st;
	int i;

	for (i = 0; files[i].name; i++)
		verify_file(&files[i]);
	if (lstat(p("s1"), &st) != 0 || (st.st_mode & 07777) != 0600)
		fail("mode of s1");
	if (lstat(p("s16383"), &st) != 0 || st.st_uid != 123 || st.st_gid != 45)
		fail("owner of s16383");
	if (lstat(p("s16385"), &st) != 0 || st.st_mtime != 1200000000)
		fail("mtime of s16385");
	return 0;
}

/*
 * The volume's inode count (statfs f_files) once a flush has settled:
 * sync(2) only starts one, so poll until the count holds still.
 */
static long
inodes(void)
{
	struct statfs sf;
	long last = -1;
	int tries;

	for (tries = 0; tries < 10; tries++) {
		sync();
		sleep(2);
		if (statfs(root, &sf) != 0) {
			fail("statfs");
			return -1;
		}
		if ((long)sf.f_files == last)
			break;
		last = (long)sf.f_files;
	}
	return last;
}

/*
 * Open, unlink, write and read back through the descriptor, close.  The
 * inode stays on the volume while the file is open and goes at the last
 * close.  (Its data stays as history until pruning, so free space does
 * not change.)
 */
static int
do_unlinked(void)
{
	long before, during, open_unlinked, after;
	int fd;

	before = inodes();
	if ((fd = open(p("gone"), O_RDWR | O_CREAT | O_EXCL, 0644)) == -1)
		fail("create gone");
	if (put(fd, 20, 0, 16 * MIB, 65536) != 0)
		fail("write gone");
	during = inodes();
	if (unlink(p("gone")) != 0)
		fail("unlink gone");
	if (access(p("gone"), F_OK) == 0)
		fail("name gone still visible");
	if (put(fd, 21, 16 * MIB, MIB, 65536) != 0)
		fail("write after unlink");
	open_unlinked = inodes();
	if (lseek(fd, 16 * MIB, SEEK_SET) == -1 || read(fd, buf, 4096) != 4096)
		fail("read after unlink");
	else if ((buf[100] & 0xff) != pat(21, 16 * MIB + 100))
		fail("data after unlink");
	if (lseek(fd, 1000L, SEEK_SET) == -1 || read(fd, buf, 16) != 16 ||
	    (buf[0] & 0xff) != pat(20, 1000))
		fail("old data after unlink");
	if (close(fd) != 0)
		fail("close gone");
	after = inodes();
	if (during != before + 1 || open_unlinked != during || after != before) {
		printf("FAIL inode counts %ld created %ld open-unlinked %ld "
		       "closed %ld\n", before, during, open_unlinked, after);
		failures++;
	}
	return 0;
}

#define DURABLE	(2 * MIB)

/*
 * fsync makes a file durable: the caller crashes the system after this
 * (no unmount), and "durable-check" after the reboot finds the data.
 * Bytes appended after the fsync may or may not survive.
 */
static int
do_durable(void)
{
	int fd = open(p("durable"), O_RDWR | O_CREAT | O_TRUNC, 0644);

	if (fd == -1 || put(fd, 30, 0, DURABLE, 65536) != 0 || fsync(fd) != 0)
		fail("durable");
	printf("DURABLE_FSYNCED\n");
	fflush(stdout);
	if (put(fd, 30, DURABLE, MIB, 65536) != 0)
		fail("durable tail");
	return 0;
}

static int
do_durable_check(void)
{
	struct stat st;
	long off;
	int fd, n, i;

	if ((fd = open(p("durable"), O_RDONLY)) == -1 || fstat(fd, &st) != 0) {
		fail("durable missing");
		return 0;
	}
	if ((long)st.st_size < DURABLE) {
		printf("FAIL durable: size %ld, want at least %ld\n",
		       (long)st.st_size, DURABLE);
		failures++;
	}
	for (off = 0; off < DURABLE; off += n) {
		n = read(fd, buf, sizeof(buf));
		if (n <= 0) {
			fail("read durable");
			break;
		}
		for (i = 0; i < n && off + i < DURABLE; i++)
			if ((buf[i] & 0xff) != pat(30, off + i)) {
				printf("FAIL durable: byte %ld\n", off + i);
				failures++;
				close(fd);
				return 0;
			}
	}
	close(fd);
	return 0;
}

int
main(int argc, char **argv)
{
	if (argc != 3) {
		fprintf(stderr, "usage: data_ops write|verify|unlinked|durable|"
			"durable-check ROOT\n");
		return 2;
	}
	root = argv[2];
	umask(022);
	if (strcmp(argv[1], "write") == 0)
		do_write();
	else if (strcmp(argv[1], "verify") == 0)
		do_verify();
	else if (strcmp(argv[1], "verify-remount") == 0) {
		remounted = 1;
		do_verify();
	}
	else if (strcmp(argv[1], "unlinked") == 0)
		do_unlinked();
	else if (strcmp(argv[1], "durable") == 0)
		do_durable();
	else if (strcmp(argv[1], "durable-check") == 0)
		do_durable_check();
	else
		return 2;
	if (failures) {
		printf("%d failures\n", failures);
		return 1;
	}
	printf("DATA_OPS_OK %s\n", argv[1]);
	return 0;
}
