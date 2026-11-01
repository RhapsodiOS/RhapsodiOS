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
 * hammer_walk [-n] ROOT: print a sorted manifest of a directory tree.
 *
 * One line per object, sorted by path relative to ROOT:
 *	path TAB type TAB mode TAB uid TAB gid TAB nlink TAB size TAB mtime TAB extra
 * extra is the POSIX cksum CRC of a regular file (or '-' with -n), the
 * target of a symlink, or '-'.  Non-directories with nlink > 1 get a
 * further TAB '=' and the smallest path sharing their (st_dev, st_ino).
 * atime and ctime are never printed.  mtime is clamped to the 32-bit
 * signed range so DragonFly (64-bit time_t) and Rhapsody (32-bit) agree.
 *
 * Plain C89 and POSIX: the same source builds on DragonFly and Rhapsody.
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct ent {
	char		*path;
	struct stat	st;
	char		*extra;
	char		*link;		/* smallest path with the same inode */
};

static struct ent *ents;
static size_t nents, maxents;
static int nocrc;

static unsigned long crctab[256];

static void
crcinit(void)
{
	unsigned long c;
	int i, j;

	for (i = 0; i < 256; ++i) {
		c = (unsigned long)i << 24;
		for (j = 0; j < 8; ++j)
			c = (c & 0x80000000UL) ? ((c << 1) ^ 0x04C11DB7UL) : (c << 1);
		crctab[i] = c & 0xFFFFFFFFUL;
	}
}

/* POSIX cksum(1) CRC of a file's contents. */
static unsigned long
cksum(const char *path)
{
	unsigned char buf[8192];
	unsigned long crc = 0, len = 0, l;
	int fd, n, i;

	fd = open(path, O_RDONLY);
	if (fd < 0) {
		perror(path);
		exit(1);
	}
	while ((n = read(fd, buf, sizeof(buf))) > 0) {
		for (i = 0; i < n; ++i)
			crc = ((crc << 8) ^ crctab[((crc >> 24) ^ buf[i]) & 0xFF]) & 0xFFFFFFFFUL;
		len += n;
	}
	if (n < 0) {
		perror(path);
		exit(1);
	}
	close(fd);
	for (l = len; l; l >>= 8)
		crc = ((crc << 8) ^ crctab[((crc >> 24) ^ l) & 0xFF]) & 0xFFFFFFFFUL;
	return (~crc & 0xFFFFFFFFUL);
}

static char *
xstrdup(const char *s)
{
	char *p = malloc(strlen(s) + 1);

	if (p == NULL) {
		perror("malloc");
		exit(1);
	}
	return (strcpy(p, s));
}

static void
add(const char *full, const char *rel)
{
	struct ent *e;
	char buf[1100];
	int n;

	if (nents == maxents) {
		maxents = maxents ? maxents * 2 : 1024;
		ents = realloc(ents, maxents * sizeof(*ents));
		if (ents == NULL) {
			perror("realloc");
			exit(1);
		}
	}
	e = &ents[nents++];
	e->path = xstrdup(rel);
	e->link = NULL;
	if (lstat(full, &e->st) < 0) {
		perror(full);
		exit(1);
	}
	if (S_ISREG(e->st.st_mode) && !nocrc) {
		sprintf(buf, "%lu", cksum(full));
		e->extra = xstrdup(buf);
	} else if (S_ISLNK(e->st.st_mode)) {
		n = readlink(full, buf, sizeof(buf) - 1);
		if (n < 0) {
			perror(full);
			exit(1);
		}
		buf[n] = 0;
		e->extra = xstrdup(buf);
	} else {
		e->extra = "-";
	}
}

static void
walk(const char *full, const char *rel)
{
	DIR *d;
	struct dirent *de;
	char *f, *r;

	d = opendir(full);
	if (d == NULL) {
		perror(full);
		exit(1);
	}
	while ((de = readdir(d)) != NULL) {
		if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
			continue;
		f = malloc(strlen(full) + strlen(de->d_name) + 2);
		r = malloc(strlen(rel) + strlen(de->d_name) + 2);
		if (f == NULL || r == NULL) {
			perror("malloc");
			exit(1);
		}
		sprintf(f, "%s/%s", full, de->d_name);
		sprintf(r, "%s/%s", rel, de->d_name);
		add(f, r);
		if (S_ISDIR(ents[nents - 1].st.st_mode))
			walk(f, r);
		free(f);
		free(r);
	}
	closedir(d);
}

static int
bypath(const void *a, const void *b)
{
	return (strcmp(((const struct ent *)a)->path, ((const struct ent *)b)->path));
}

static int
byino(const void *a, const void *b)
{
	const struct ent *x = *(const struct ent * const *)a;
	const struct ent *y = *(const struct ent * const *)b;

	if (x->st.st_dev != y->st.st_dev)
		return (x->st.st_dev < y->st.st_dev ? -1 : 1);
	if (x->st.st_ino != y->st.st_ino)
		return (x->st.st_ino < y->st.st_ino ? -1 : 1);
	return (strcmp(x->path, y->path));
}

static char
typechar(mode_t m)
{
	if (S_ISDIR(m)) return ('d');
	if (S_ISREG(m)) return ('f');
	if (S_ISLNK(m)) return ('l');
	if (S_ISFIFO(m)) return ('p');
	if (S_ISCHR(m)) return ('c');
	if (S_ISBLK(m)) return ('b');
	return ('s');
}

int
main(int ac, char **av)
{
	struct ent **links;
	size_t i, j, nl;
	long mt;

	if (ac == 3 && strcmp(av[1], "-n") == 0) {
		nocrc = 1;
		++av;
		--ac;
	}
	if (ac != 2) {
		fprintf(stderr, "usage: hammer_walk [-n] ROOT\n");
		return (2);
	}
	crcinit();
	add(av[1], ".");
	walk(av[1], ".");

	/* Group hard links: every member points at the smallest path. */
	links = malloc(nents * sizeof(*links));
	for (i = nl = 0; i < nents; ++i)
		if (!S_ISDIR(ents[i].st.st_mode) && ents[i].st.st_nlink > 1)
			links[nl++] = &ents[i];
	qsort(links, nl, sizeof(*links), byino);
	for (i = 0; i < nl; i = j) {
		for (j = i; j < nl &&
		     links[j]->st.st_ino == links[i]->st.st_ino &&
		     links[j]->st.st_dev == links[i]->st.st_dev; ++j)
			links[j]->link = links[i]->path;
	}

	qsort(ents, nents, sizeof(*ents), bypath);
	for (i = 0; i < nents; ++i) {
		struct ent *e = &ents[i];

		mt = e->st.st_mtime > 0x7FFFFFFFL ? 0x7FFFFFFFL :
		     e->st.st_mtime < -0x7FFFFFFFL - 1 ? -0x7FFFFFFFL - 1 :
		     (long)e->st.st_mtime;
		printf("%s\t%c\t%o\t%lu\t%lu\t%lu\t%lu\t%ld\t%s",
		       e->path, typechar(e->st.st_mode),
		       (unsigned)(e->st.st_mode & 07777),
		       (unsigned long)e->st.st_uid, (unsigned long)e->st.st_gid,
		       (unsigned long)e->st.st_nlink,
		       (unsigned long)e->st.st_size, mt, e->extra);
		if (e->link)
			printf("\t=%s", e->link);
		printf("\n");
	}
	return (0);
}
