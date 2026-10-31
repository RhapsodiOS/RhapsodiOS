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
 * enospc_ops STAGE ROOT: running a HAMMER volume out of space.
 *
 *	fill	ROOT/full (no-history, so removal frees space) fills with
 *		1 MiB files until ENOSPC; then create, mkdir, write, rename
 *		and link are tried at the edge.  Each either works or fails
 *		with ENOSPC and leaves nothing half made: no name without an
 *		object, no object without its name, no short file claiming
 *		full length.
 *	check	every complete file reads back intact (after a remount)
 *	empty	everything under ROOT/full is removed
 *	refill	after the flusher has run, the freed space takes new files
 *
 * Every mismatch prints a FAIL line; the exit status is 1 if there was
 * any.
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

#define MIB		(1024L * 1024L)
#define UF_NOHISTORY	0x00000040	/* DragonFly's, inherited by new files */

static const char *root;
static int failures;
static char buf[65536];

static void
fail(const char *what)
{
	printf("FAIL %s (errno %d)\n", what, errno);
	failures++;
}

/* ROOT/fmt; four rotating buffers, so one call can take two paths. */
static const char *
p(const char *fmt, int n)
{
	static char path[4][1024];
	static int k;
	char rel[256];

	k = (k + 1) % 4;
	sprintf(rel, fmt, n);
	sprintf(path[k], "%s/%s", root, rel);
	return path[k];
}

static int
pat(int file, long off)
{
	return (int)((off * 3 + file * 11 + off / 997) & 0xff);
}

/*
 * Write a 1 MiB file; 0, or the errno that stopped it.  A file that did
 * not complete is removed again.
 */
static int
mkmib(const char *path, int n)
{
	long off;
	int fd, i, error = 0;

	if ((fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0644)) == -1)
		return errno;
	for (off = 0; off < MIB && error == 0; off += sizeof(buf)) {
		for (i = 0; i < (int)sizeof(buf); i++)
			buf[i] = (char)pat(n, off + i);
		if (write(fd, buf, sizeof(buf)) != (int)sizeof(buf))
			error = errno ? errno : EIO;
	}
	if (fsync(fd) != 0 && error == 0)
		error = errno;
	close(fd);
	if (error)
		unlink(path);
	return error;
}

/* A file is either complete and intact or absent. */
static void
check_file(const char *path, int n)
{
	struct stat st;
	long off;
	int fd, i, k;

	if (lstat(path, &st) != 0) {
		if (errno != ENOENT)
			fail(path);
		return;
	}
	if ((long)st.st_size != MIB) {
		printf("FAIL %s: size %ld\n", path, (long)st.st_size);
		failures++;
		return;
	}
	if ((fd = open(path, O_RDONLY)) == -1) {
		fail(path);
		return;
	}
	for (off = 0; off < MIB; off += k) {
		if ((k = read(fd, buf, sizeof(buf))) <= 0) {
			fail(path);
			break;
		}
		for (i = 0; i < k; i++)
			if ((buf[i] & 0xff) != pat(n, off + i)) {
				printf("FAIL %s: byte %ld\n", path, off + i);
				failures++;
				close(fd);
				return;
			}
	}
	close(fd);
}

static void
want_enospc_or_ok(const char *what, int rc)
{
	if (rc == -1 && errno != ENOSPC)
		fail(what);
}

static void
do_fill(void)
{
	struct stat st, st2;
	int n, error, fd, rc;

	if (mkdir(p("full", 0), 0755) != 0)
		fail("mkdir full");
	if (chflags(p("full", 0), UF_NOHISTORY) != 0)
		fail("chflags full");
	for (n = 0;; n++) {
		error = mkmib(p("full/f%05d", n), n);
		if (error == ENOSPC)
			break;
		if (error) {
			errno = error;
			fail(p("full/f%05d", n));
			return;
		}
	}
	printf("filled %d MiB\n", n);
	if (n < 10) {
		printf("FAIL only %d files before ENOSPC\n", n);
		failures++;
	}

	/* create */
	rc = open(p("full/new", 0), O_WRONLY | O_CREAT | O_EXCL, 0644);
	want_enospc_or_ok("create", rc);
	if (rc != -1)
		close(rc);
	else if (lstat(p("full/new", 0), &st) == 0)
		fail("create failed but the name exists");

	/* mkdir */
	rc = mkdir(p("full/newdir", 0), 0755);
	want_enospc_or_ok("mkdir", rc);
	if (rc == -1 && lstat(p("full/newdir", 0), &st) == 0)
		fail("mkdir failed but the name exists");

	/* write: appending to a complete file */
	if ((fd = open(p("full/f%05d", 0), O_WRONLY | O_APPEND)) == -1)
		fail("open f00000");
	memset(buf, 'X', sizeof(buf));
	rc = write(fd, buf, sizeof(buf));
	if (rc == -1 && errno != ENOSPC)
		fail("append");
	close(fd);
	if (lstat(p("full/f%05d", 0), &st) != 0)
		fail("stat f00000");
	else if (rc == -1 && (long)st.st_size != MIB)
		printf("FAIL failed append changed the size to %ld\n",
		       (long)st.st_size), failures++;
	if (rc != -1 && truncate(p("full/f%05d", 0), MIB) != 0)
		fail("truncate the append back");

	/* rename */
	rc = rename(p("full/f%05d", 1), p("full/moved", 0));
	want_enospc_or_ok("rename", rc);
	if (rc == -1) {
		if (lstat(p("full/f%05d", 1), &st) != 0)
			fail("rename failed and the source is gone");
		if (lstat(p("full/moved", 0), &st) == 0)
			fail("rename failed and the target exists");
	} else if (rename(p("full/moved", 0), p("full/f%05d", 1)) != 0) {
		fail("rename back");
	}

	/* link */
	if (lstat(p("full/f%05d", 2), &st) != 0)
		fail("stat f00002");
	rc = link(p("full/f%05d", 2), p("full/linked", 0));
	want_enospc_or_ok("link", rc);
	if (lstat(p("full/f%05d", 2), &st2) != 0)
		fail("stat f00002 after link");
	else if (rc == -1 && (st2.st_nlink != st.st_nlink ||
		 lstat(p("full/linked", 0), &st) == 0))
		fail("link failed but left a name or a link count");
	else if (rc != -1 && unlink(p("full/linked", 0)) != 0)
		fail("unlink the link");
}

/* Files f00000.. while they exist; the count found. */
static int
check_all(void)
{
	struct stat st;
	int n;

	for (n = 0; lstat(p("full/f%05d", n), &st) == 0; n++)
		check_file(p("full/f%05d", n), n);
	if (n < 10) {
		printf("FAIL only %d files found\n", n);
		failures++;
	}
	check_file(p("full/f%05d", n), n);	/* the partial one is gone */
	printf("%d complete files\n", n);
	return n;
}

static void
do_empty(void)
{
	DIR *d;
	struct dirent *de;
	char path[1024];

	if ((d = opendir(p("full", 0))) == NULL) {
		fail("opendir full");
		return;
	}
	while ((de = readdir(d)) != NULL) {
		if (de->d_name[0] == '.')
			continue;
		sprintf(path, "%s/full/%s", root, de->d_name);
		if (unlink(path) != 0 && rmdir(path) != 0)
			fail(path);
	}
	closedir(d);
	sync();
}

static void
do_refill(void)
{
	int n, error;

	for (n = 0; n < 10; n++) {
		error = mkmib(p("full/r%05d", n), n);
		if (error) {
			errno = error;
			fail(p("full/r%05d", n));
			return;
		}
	}
	for (n = 0; n < 10; n++)
		check_file(p("full/r%05d", n), n);
}

int
main(int argc, char **argv)
{
	if (argc != 3) {
		fprintf(stderr, "usage: enospc_ops fill|check|empty|refill ROOT\n");
		return 2;
	}
	root = argv[2];
	umask(022);
	if (strcmp(argv[1], "fill") == 0)
		do_fill();
	else if (strcmp(argv[1], "check") == 0)
		check_all();
	else if (strcmp(argv[1], "empty") == 0)
		do_empty();
	else if (strcmp(argv[1], "refill") == 0)
		do_refill();
	else
		return 2;
	if (failures) {
		printf("%d failures\n", failures);
		return 1;
	}
	printf("ENOSPC_OK %s\n", argv[1]);
	return 0;
}
