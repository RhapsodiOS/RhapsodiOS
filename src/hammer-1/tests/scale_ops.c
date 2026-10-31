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
 * scale_ops STAGE ROOT: workloads that split and empty B-Tree nodes.
 *
 *	dir-fill	ROOT/big gets 20,000 files, then every other one goes
 *	dir-half	the 10,000 that remain are listed and checked
 *	dir-empty	the rest go, and ROOT/big is removed
 *	gone		ROOT is empty (after dir-empty or file-delete)
 *	file-write	ROOT/big512 gets 512 MiB in 64 KB writes
 *	file-check	ROOT/big512 reads back intact
 *	file-delete	ROOT/big512 is removed
 *	churn		1,000 rounds of create, write, rename and unlink over
 *			50 directories
 *	churn-check	what churn leaves, checked
 *
 * Every mismatch prints a FAIL line; the exit status is 1 if there was
 * any.  The same source builds on DragonFly (C89 and POSIX).
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define NFILES	20000
#define MIB	(1024L * 1024L)
#define BIGSIZE	(512 * MIB)
#define CHUNK	65536
#define NDIRS	50
#define ROUNDS	1000

static const char *root;
static int failures;
static char buf[CHUNK];

static void
fail(const char *what)
{
	printf("FAIL %s (errno %d)\n", what, errno);
	failures++;
}

/* ROOT/fmt; four rotating buffers, so one call can take two paths. */
static const char *
p(const char *fmt, int a, int b)
{
	static char path[4][1024];
	static int n;
	char rel[256];

	n = (n + 1) % 4;
	sprintf(rel, fmt, a, b);
	sprintf(path[n], "%s/%s", root, rel);
	return path[n];
}

static int
mkfile(const char *path, const char *data, int n)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0644);

	if (fd == -1)
		return -1;
	if (n && write(fd, data, n) != n) {
		close(fd);
		return -1;
	}
	return close(fd);
}

/* Entries in DIR other than . and .., and how many match name%05d. */
static int
count(const char *dir, int *odd)
{
	DIR *d = opendir(dir);
	struct dirent *de;
	int n = 0, k;

	*odd = 0;
	if (d == NULL) {
		fail(dir);
		return -1;
	}
	while ((de = readdir(d)) != NULL) {
		if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
			continue;
		n++;
		if (sscanf(de->d_name, "f%05d", &k) == 1 && (k & 1))
			(*odd)++;
	}
	closedir(d);
	return n;
}

static void
dir_fill(void)
{
	int i;

	if (mkdir(p("big", 0, 0), 0755) != 0)
		fail("mkdir big");
	for (i = 0; i < NFILES; i++)
		if (mkfile(p("big/f%05d", i, 0), (char *)&i, sizeof(i)) != 0) {
			fail(p("big/f%05d", i, 0));
			return;
		}
	for (i = 0; i < NFILES; i += 2)
		if (unlink(p("big/f%05d", i, 0)) != 0) {
			fail(p("big/f%05d", i, 0));
			return;
		}
}

static void
dir_half(void)
{
	struct stat st;
	int n, odd, i, v, fd;

	n = count(p("big", 0, 0), &odd);
	if (n != NFILES / 2 || odd != NFILES / 2) {
		printf("FAIL big: %d entries, %d odd; want %d\n", n, odd,
		       NFILES / 2);
		failures++;
	}
	for (i = 1; i < NFILES; i += 2) {
		if ((fd = open(p("big/f%05d", i, 0), O_RDONLY)) == -1 ||
		    read(fd, (char *)&v, sizeof(v)) != sizeof(v) || v != i) {
			fail(p("big/f%05d", i, 0));
			if (fd != -1)
				close(fd);
			return;
		}
		close(fd);
	}
	if (lstat(p("big/f%05d", 0, 0), &st) == 0)
		fail("big/f00000 came back");
}

static void
dir_empty(void)
{
	int i;

	for (i = 1; i < NFILES; i += 2)
		if (unlink(p("big/f%05d", i, 0)) != 0) {
			fail(p("big/f%05d", i, 0));
			return;
		}
	if (rmdir(p("big", 0, 0)) != 0)
		fail("rmdir big");
}

static void
gone(void)
{
	int n, odd;

	n = count(root, &odd);
	if (n != 0) {
		printf("FAIL %s still has %d entries\n", root, n);
		failures++;
	}
}

static int
pat(long off)
{
	return (int)((off * 13 + off / 65521) & 0xff);
}

static void
file_write(void)
{
	long off;
	int fd, i;

	if ((fd = open(p("big512", 0, 0), O_WRONLY | O_CREAT | O_EXCL, 0644)) == -1) {
		fail("create big512");
		return;
	}
	for (off = 0; off < BIGSIZE; off += CHUNK) {
		for (i = 0; i < CHUNK; i++)
			buf[i] = (char)pat(off + i);
		if (write(fd, buf, CHUNK) != CHUNK) {
			fail("write big512");
			break;
		}
	}
	if (close(fd) != 0)
		fail("close big512");
}

static void
file_check(void)
{
	struct stat st;
	long off;
	int fd, i;

	if ((fd = open(p("big512", 0, 0), O_RDONLY)) == -1 ||
	    fstat(fd, &st) != 0) {
		fail("open big512");
		return;
	}
	if ((long)st.st_size != BIGSIZE) {
		printf("FAIL big512: size %ld\n", (long)st.st_size);
		failures++;
	}
	for (off = 0; off < BIGSIZE; off += CHUNK) {
		if (read(fd, buf, CHUNK) != CHUNK) {
			fail("read big512");
			break;
		}
		for (i = 0; i < CHUNK; i++)
			if ((buf[i] & 0xff) != pat(off + i)) {
				printf("FAIL big512: byte %ld\n", off + i);
				failures++;
				close(fd);
				return;
			}
	}
	close(fd);
}

/*
 * Round r touches directory r % 50: it creates t<r>, writes r into it,
 * renames it to k<r>, and unlinks k<r - 100> (a name made 100 rounds
 * earlier in another directory).  What is left is k<r> for the last 100
 * rounds, each holding its round number.
 */
static void
churn(void)
{
	int d, r, fd;

	for (d = 0; d < NDIRS; d++)
		if (mkdir(p("c%02d", d, 0), 0755) != 0)
			fail(p("c%02d", d, 0));
	for (r = 0; r < ROUNDS; r++) {
		if ((fd = open(p("c%02d/t%04d", r % NDIRS, r),
			       O_WRONLY | O_CREAT | O_EXCL, 0644)) == -1 ||
		    write(fd, (char *)&r, sizeof(r)) != sizeof(r) ||
		    close(fd) != 0) {
			fail(p("c%02d/t%04d", r % NDIRS, r));
			return;
		}
		if (rename(p("c%02d/t%04d", r % NDIRS, r),
			   p("c%02d/k%04d", r % NDIRS, r)) != 0) {
			fail("rename");
			return;
		}
		if (r >= 100 && unlink(p("c%02d/k%04d", (r - 100) % NDIRS,
					 r - 100)) != 0) {
			struct stat st;
			int odd, rc = lstat(p("c%02d/k%04d", (r - 100) % NDIRS,
					       r - 100), &st);

			printf("FAIL round %d: unlink %s (errno %d); lstat %d, "
			       "%d entries in its directory\n", r,
			       p("c%02d/k%04d", (r - 100) % NDIRS, r - 100),
			       errno, rc, count(p("c%02d", r % NDIRS, 0), &odd));
			failures++;
			return;
		}
	}
}

static void
churn_check(void)
{
	struct stat st;
	int d, r, v, fd, n, odd, total = 0;

	for (d = 0; d < NDIRS; d++) {
		n = count(p("c%02d", d, 0), &odd);
		total += n;
	}
	if (total != 100) {
		printf("FAIL churn left %d files, want 100\n", total);
		failures++;
	}
	for (r = ROUNDS - 100; r < ROUNDS; r++) {
		if ((fd = open(p("c%02d/k%04d", r % NDIRS, r), O_RDONLY)) == -1 ||
		    read(fd, (char *)&v, sizeof(v)) != sizeof(v) || v != r) {
			fail(p("c%02d/k%04d", r % NDIRS, r));
			if (fd != -1)
				close(fd);
			continue;
		}
		close(fd);
	}
	if (lstat(p("c%02d/k%04d", 0, 0), &st) == 0)
		fail("k0000 came back");
}

int
main(int argc, char **argv)
{
	static const struct {
		const char *name;
		void (*fn)(void);
	} stages[] = {
		{ "dir-fill", dir_fill }, { "dir-half", dir_half },
		{ "dir-empty", dir_empty }, { "gone", gone },
		{ "file-write", file_write }, { "file-check", file_check },
		{ "file-delete", 0 }, { "churn", churn },
		{ "churn-check", churn_check }, { 0, 0 }
	};
	int i;

	if (argc != 3) {
		fprintf(stderr, "usage: scale_ops STAGE ROOT\n");
		return 2;
	}
	root = argv[2];
	umask(022);
	for (i = 0; stages[i].name; i++)
		if (strcmp(argv[1], stages[i].name) == 0)
			break;
	if (stages[i].name == 0)
		return 2;
	if (stages[i].fn)
		stages[i].fn();
	else if (unlink(p("big512", 0, 0)) != 0)
		fail("unlink big512");
	if (failures) {
		printf("%d failures\n", failures);
		return 1;
	}
	printf("SCALE_OK %s\n", argv[1]);
	return 0;
}
