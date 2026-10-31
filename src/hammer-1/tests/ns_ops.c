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
 * ns_ops ROOT: a fixed namespace workload under ROOT, run on a freshly
 * made volume.  Every call is checked against the errno POSIX gives it;
 * the first mismatch prints and exits 1.  The resulting tree is compared
 * (hammer_walk -n) with the tree the same program leaves on DragonFly.
 *
 * Plain C89 and POSIX: the same source builds on DragonFly and Rhapsody.
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *root;
static int failures;

static const char *
p(const char *rel)
{
	static char buf[4][1024];
	static int n;

	n = (n + 1) % 4;
	sprintf(buf[n], "%s/%s", root, rel);
	return buf[n];
}

/* RC is the call's result; WANT 0 means success, else the errno wanted. */
static void
expect(const char *what, int rc, int want)
{
	int got = rc == -1 ? errno : 0;

	if (got != want) {
		printf("FAIL %s: errno %d, want %d\n", what, got, want);
		failures++;
	}
}

/* Either of two errnos (rename over a non-empty directory). */
static void
expect2(const char *what, int rc, int want1, int want2)
{
	int got = rc == -1 ? errno : 0;

	if (got != want1 && got != want2) {
		printf("FAIL %s: errno %d, want %d or %d\n", what, got, want1, want2);
		failures++;
	}
}

static int
mkfile(const char *rel)
{
	int fd = open(p(rel), O_WRONLY | O_CREAT | O_EXCL, 0644);

	if (fd == -1)
		return -1;
	return close(fd);
}

static int
exists(const char *rel)
{
	struct stat st;

	return lstat(p(rel), &st) == 0;
}

int
main(int argc, char **argv)
{
	char name[64], target[256];
	struct stat a, b;
	int i;

	if (argc != 2) {
		fprintf(stderr, "usage: ns_ops ROOT\n");
		return 2;
	}
	root = argv[1];
	umask(022);

	/* mkdir -p a/b/c */
	expect("mkdir a", mkdir(p("a"), 0755), 0);
	expect("mkdir a/b", mkdir(p("a/b"), 0755), 0);
	expect("mkdir a/b/c", mkdir(p("a/b/c"), 0755), 0);
	expect("mkdir a again", mkdir(p("a"), 0755), EEXIST);

	/* 50 files */
	for (i = 0; i < 50; i++) {
		sprintf(name, "a/f%02d", i);
		expect(name, mkfile(name), 0);
	}
	expect("create a/f00 again", mkfile("a/f00"), EEXIST);

	/* symlinks: 24 bytes fits in the inode, 200 needs a record */
	memset(target, 'x', sizeof(target));
	memcpy(target, "0123456789abcdefghijklmn", 24);
	target[24] = 0;
	expect("symlink s24", symlink(target, p("a/s24")), 0);
	memset(target, 'y', 200);
	target[200] = 0;
	expect("symlink s200", symlink(target, p("a/s200")), 0);

	/* a file with three names */
	expect("create a/h1", mkfile("a/h1"), 0);
	expect("link h2", link(p("a/h1"), p("a/h2")), 0);
	expect("link b/h3", link(p("a/h1"), p("a/b/h3")), 0);
	expect("link a/b (directory)", link(p("a/b"), p("a/hb")), EPERM);

	/* rmdir and rm */
	expect("mkdir a/gone", mkdir(p("a/gone"), 0755), 0);
	expect("rmdir a/gone", rmdir(p("a/gone")), 0);
	expect("rmdir a (not empty)", rmdir(p("a")), ENOTEMPTY);
	expect("rmdir a/f20 (file)", rmdir(p("a/f20")), ENOTDIR);
	for (i = 0; i < 10; i++) {
		sprintf(name, "a/f%02d", i);
		expect(name, unlink(p(name)), 0);
	}
	expect("unlink a/f00 again", unlink(p("a/f00")), ENOENT);

	/* rename matrix */
	expect("create r1", mkfile("a/r1"), 0);
	expect("create r2", mkfile("a/r2"), 0);
	expect("rename r1 over r2", rename(p("a/r1"), p("a/r2")), 0);
	if (exists("a/r1")) {
		printf("FAIL r1 still exists\n");
		failures++;
	}
	expect("mkdir d1", mkdir(p("a/d1"), 0755), 0);
	expect("mkdir d2", mkdir(p("a/d2"), 0755), 0);
	expect("rename d1 over empty d2", rename(p("a/d1"), p("a/d2")), 0);
	expect("mkdir d3", mkdir(p("a/d3"), 0755), 0);
	expect("mkdir d4", mkdir(p("a/d4"), 0755), 0);
	expect("create d4/x", mkfile("a/d4/x"), 0);
	expect2("rename d3 over non-empty d4", rename(p("a/d3"), p("a/d4")),
		ENOTEMPTY, EEXIST);
	expect("rename a/b into its own subtree",
	       rename(p("a/b"), p("a/b/c/b")), EINVAL);
	expect("rename f10 across directories",
	       rename(p("a/f10"), p("a/b/f10")), 0);
	expect("mkdir m", mkdir(p("a/m"), 0755), 0);
	expect("rename directory m across", rename(p("a/m"), p("a/b/c/m")), 0);
	expect("stat c/m/..", lstat(p("a/b/c/m/.."), &a), 0);
	expect("stat c", lstat(p("a/b/c"), &b), 0);
	if (a.st_ino != b.st_ino) {
		printf("FAIL moved directory's .. is %lu, want %lu\n",
		       (unsigned long)a.st_ino, (unsigned long)b.st_ino);
		failures++;
	}
	expect("rename f11 onto itself", rename(p("a/f11"), p("a/f11")), 0);
	if (!exists("a/f11")) {
		printf("FAIL a/f11 vanished\n");
		failures++;
	}
	/*
	 * Two links to one file: POSIX makes the rename a no-op.  DragonFly
	 * removes the source name instead, so this pair is scratch, removed
	 * again, and the no-op is only checked elsewhere.
	 */
	expect("create l1", mkfile("a/l1"), 0);
	expect("link l2", link(p("a/l1"), p("a/l2")), 0);
	expect("rename l1 onto its own link l2", rename(p("a/l1"), p("a/l2")), 0);
#ifndef __DragonFly__
	if (!exists("a/l1") || !exists("a/l2")) {
		printf("FAIL rename between links removed a name\n");
		failures++;
	}
#endif
	if (exists("a/l1"))
		expect("unlink l1", unlink(p("a/l1")), 0);
	expect("unlink l2", unlink(p("a/l2")), 0);
	expect("rename file over directory", rename(p("a/f12"), p("a/d2")), EISDIR);
	expect("rename directory over file", rename(p("a/d2"), p("a/f13")), ENOTDIR);
	expect("rename missing", rename(p("a/nope"), p("a/nope2")), ENOENT);

	if (failures) {
		printf("%d failures\n", failures);
		return 1;
	}
	printf("NS_OPS_OK\n");
	return 0;
}
