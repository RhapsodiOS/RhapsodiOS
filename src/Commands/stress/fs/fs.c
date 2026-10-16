/* stress-fs: file system tests. Data written must read back exactly, holes
 * as zeros; O_APPEND writers must not lose, duplicate or tear lines; the
 * name space must stay consistent under rename/mkdir/rmdir churn; a full
 * file system must give ENOSPC and give its blocks back.
 *
 * fill writes the file system holding -d until it is full: only point it at
 * a scratch file system, so it runs only when named on the command line.
 * fsync proves that fsync returns and that two descriptors agree on the data;
 * it does not prove the data is durable on disk. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "stress.h"

#define EXT	(1024UL * 1024)		/* rw: every write lies inside this */
#define LINE	100			/* append: bytes per line */
#define CHUNK	65536UL			/* fill: bytes per write */
#define MAXFILES 4096			/* fill: 4 GB of 1 MB files */
#define WAIT	30			/* seconds to wait for worker 0 */
#define STALL	120			/* seconds of no progress from peers */

static char base[300];		/* this worker's (or the shared) directory */
static char own[300];		/* removed by cleanup(): what this worker made */

static unsigned long
key3(unsigned long a, unsigned long b, unsigned long d)
{
	return st_mix(st_mix(st_opt.seed ^ a) + b * 0x9e3779b1UL + d) & ST_MASK;
}

static void
rmrf(const char *path)
{
	char cmd[400];

	sprintf(cmd, "rm -rf '%s'", path);
	system(cmd);
}

static void
cleanup(void)
{
	if (own[0] != '\0')
		rmrf(own);
	own[0] = '\0';
}

static void
failf(struct st_ctx *c, const char *fmt, ...)
{
	va_list ap;
	char buf[400];

	va_start(ap, fmt);
	vsprintf(buf, fmt, ap);
	va_end(ap);
	cleanup();
	st_fail(c, "%s", buf);
}

static void markdone(struct st_ctx *c);

/* HFS refuses to remove or replace an object something has open (EBUSY);
 * that is the file system's limit, so the test ends UNSUP there. */
static int
on_hfs(const char *dir)
{
	struct statfs sf;

	return statfs(dir, &sf) == 0 && strcmp(sf.f_fstypename, "hfs") == 0;
}

static void
failerr(struct st_ctx *c, const char *call)
{
	int e = errno;

	cleanup();
	if (e == EBUSY && (strcmp(call, "rmdir") == 0 || strcmp(call, "rename") == 0 ||
	    strcmp(call, "unlink") == 0) && on_hfs(st_opt.dir)) {
		markdone(c);	/* workers waiting on the shared tree must not stall */
		st_unsup(c, "reason=\"EBUSY: in-use object\"");
	}
	errno = e;
	st_fail_errno(c, call);
}

/* Each worker's own directory. */
static void
mkown(struct st_ctx *c, const char *test)
{
	if (strlen(st_opt.dir) + strlen(test) + 40 > sizeof base)
		st_fail(c, "reason=path-too-long");
	sprintf(base, "%s/stress.fs.%s.%ld.%d", st_opt.dir, test, (long)getppid(), c->idx);
	rmrf(base);			/* left by a killed run with this pid */
	if (mkdir(base, 0700) < 0)
		failerr(c, "mkdir");
	strcpy(own, base);
}

/* One directory for all workers: worker 0 makes it fresh and the others
 * wait for it, and tell it from a stale one by its mtime. */
static void
mkshared(struct st_ctx *c, const char *test)
{
	struct stat sb;
	time_t end = time(NULL) + WAIT;

	if (strlen(st_opt.dir) + strlen(test) + 40 > sizeof base)
		st_fail(c, "reason=path-too-long");
	sprintf(base, "%s/stress.fs.%s.%ld", st_opt.dir, test, (long)getppid());
	if (c->idx == 0) {
		rmrf(base);
		if (mkdir(base, 0700) < 0)
			failerr(c, "mkdir");
		strcpy(own, base);
		return;
	}
	while (stat(base, &sb) < 0 || sb.st_mtime < c->t_start - 1) {
		if (time(NULL) > end)
			st_fail(c, "reason=no-shared-dir");
		usleep(10000);
	}
}

static void
markdone(struct st_ctx *c)
{
	char p[400];
	int fd;

	sprintf(p, "%s/done.%d", base, c->idx);
	fd = open(p, O_CREAT | O_WRONLY, 0600);
	if (fd < 0 && errno == ENOENT)
		_exit(0);		/* worker 0 failed and removed the directory: its FAIL is the cause */
	if (fd < 0)
		failerr(c, "open");
	close(fd);
}

/* Worker 0: waits for every worker's marker. Growth of the file watch (if
 * any) or a new marker counts as progress; STALL seconds without any fails. */
static void
waitdone(struct st_ctx *c, const char *watch)
{
	char p[400];
	struct stat sb;
	long last = -1, now;
	int j, n;
	time_t t = time(NULL);

	for (;;) {
		n = 0;
		for (j = 0; j < c->nprocs; j++) {
			sprintf(p, "%s/done.%d", base, j);
			if (stat(p, &sb) == 0)
				n++;
		}
		if (n == c->nprocs)
			return;
		now = n;
		if (watch != NULL && stat(watch, &sb) == 0)
			now += (long)sb.st_size;
		if (now != last) {
			last = now;
			t = time(NULL);
		} else if (time(NULL) - t > STALL) {
			failf(c, "reason=stall done=%d/%d", n, c->nprocs);
		}
		usleep(50000);
	}
}

static void
writefull(struct st_ctx *c, int fd, const unsigned char *buf, unsigned long len, unsigned long off)
{
	long r;

	if (lseek(fd, (off_t)off, SEEK_SET) < 0)
		failerr(c, "lseek");
	while (len > 0) {
		r = write(fd, buf, len);
		if (r < 0 && errno == EINTR)
			continue;
		if (r <= 0)
			failerr(c, "write");
		buf += r;
		len -= r;
	}
}

static void
readfull(struct st_ctx *c, int fd, unsigned char *buf, unsigned long len, unsigned long off)
{
	long r;

	if (lseek(fd, (off_t)off, SEEK_SET) < 0)
		failerr(c, "lseek");
	while (len > 0) {
		r = read(fd, buf, len);
		if (r < 0 && errno == EINTR)
			continue;
		if (r < 0)
			failerr(c, "read");
		if (r == 0)
			failf(c, "reason=short-read off=0x%lx", off);
		buf += r;
		len -= r;
		off += r;
	}
}

static int
openat_(struct st_ctx *c, const char *path, int flags)
{
	int fd = open(path, flags, 0600);

	if (fd < 0)
		failerr(c, "open");
	return fd;
}

/* rw: write 1-32 random extents of 1 B-64 KB inside 1 MB of a new file, all
 * from one pattern by absolute offset, then read it all back. Bytes never
 * written must be zero (wr marks the written ones, so a half written 512 B
 * block is checked byte by byte) and the size must be the highest end. */
static void
t_rw(struct st_ctx *c)
{
	unsigned char *pat, *wr, *got, b;
	unsigned long key, ext, off, len, w0off = 0, w0len = 1, pos, j, want;
	char path[400];
	struct stat sb;
	long i, w, nw;
	int fd;

	pat = malloc(EXT);
	wr = malloc(EXT);
	got = malloc(EXT);
	if (pat == NULL || wr == NULL || got == NULL)
		st_fail_errno(c, "malloc");
	mkown(c, "rw");
	sprintf(path, "%s/f", base);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		fd = openat_(c, path, O_RDWR | O_CREAT | O_TRUNC);
		key = key3(c->idx, i, 1);
		st_fill(pat, EXT, key, 0);
		memset(wr, 0, EXT);
		ext = 0;
		nw = st_range(&c->rng, 1, 32);
		for (w = 0; w < nw; w++) {
			len = st_range(&c->rng, 1, 1UL << st_range(&c->rng, 0, 16));
			off = st_range(&c->rng, 0, EXT - len);
			writefull(c, fd, pat + off, len, off);
			memset(wr + off, 1, len);
			if (off + len > ext)
				ext = off + len;
			if (w == 0) {
				w0off = off;
				w0len = len;
			}
		}
		if (c->selfcheck && i == 0) {
			pos = w0off + st_range(&c->rng, 0, w0len - 1);
			b = pat[pos] ^ 1;
			writefull(c, fd, &b, 1, pos);
		}
		if (fstat(fd, &sb) < 0)
			failerr(c, "fstat");
		if ((unsigned long)sb.st_size != ext)
			failf(c, "what=size got=0x%lx want=0x%lx", (unsigned long)sb.st_size, ext);
		readfull(c, fd, got, ext, 0);
		for (j = 0; j < ext; j++) {
			want = wr[j] ? pat[j] : 0;
			if (got[j] != want)
				failf(c, "what=%s off=0x%lx want=%02lx got=%02x",
				      wr[j] ? "data" : "hole", j, want, got[j]);
		}
		close(fd);
		if (unlink(path) < 0)
			failerr(c, "unlink");
		st_op_end(c, ext);
	}
	cleanup();
	free(pat);
	free(wr);
	free(got);
}

/* append: every worker appends numbered lines to one O_APPEND file, each in
 * one write(); then worker 0 checks the whole file. A line is LINE bytes:
 * "<idx> <seq> <16 hex> " dotted out to a newline. */
static void
mkline(char *buf, unsigned long idx, unsigned long seq)
{
	unsigned long h = st_mix((idx ^ (seq * 0x9e3779b9UL)) & ST_MASK);
	int n = sprintf(buf, "%lu %lu %08lx%08lx ", idx, seq, h, st_mix(h));

	memset(buf + n, '.', LINE - 1 - n);
	buf[LINE - 1] = '\n';
}

static void
putline(struct st_ctx *c, int fd, const char *line)
{
	long r;

	while ((r = write(fd, line, LINE)) < 0 && errno == EINTR)
		;
	if (r < 0)
		failerr(c, "write");
	if (r != LINE)
		failf(c, "reason=short-write got=%ld", r);
}

static void
append_check(struct st_ctx *c, const char *path)
{
	unsigned char *buf, *seen;
	unsigned long size, n, k, idx, seq, total = (unsigned long)c->nprocs * c->iters;
	char exp[LINE], tmp[LINE], *e;
	struct stat sb;
	int fd;

	fd = openat_(c, path, O_RDONLY);
	if (fstat(fd, &sb) < 0)
		failerr(c, "fstat");
	size = sb.st_size;
	buf = malloc(size + 1);
	seen = calloc(total + 1, 1);
	if (buf == NULL || seen == NULL)
		failerr(c, "malloc");
	readfull(c, fd, buf, size, 0);
	close(fd);
	for (k = 0; k < size; k++)
		if (buf[k] == '\0')
			failf(c, "what=nul off=0x%lx", k);
	if (size % LINE != 0)
		failf(c, "what=size off=0x%lx", size);
	for (n = 0; n < size / LINE; n++) {
		memcpy(tmp, buf + n * LINE, LINE);
		tmp[LINE - 1] = '\0';
		idx = strtoul(tmp, &e, 10);
		if (e == tmp || *e != ' ')
			failf(c, "what=line off=0x%lx", n * LINE);
		seq = strtoul(e + 1, &e, 10);
		if (*e != ' ')
			failf(c, "what=line off=0x%lx", n * LINE);
		mkline(exp, idx, seq);
		tmp[LINE - 1] = '\n';
		if (memcmp(exp, tmp, LINE) != 0)
			failf(c, "what=sum off=0x%lx", n * LINE);
		if (idx >= (unsigned long)c->nprocs || seq >= (unsigned long)c->iters)
			failf(c, "what=range off=0x%lx idx=%lu seq=%lu", n * LINE, idx, seq);
		if (seen[idx * c->iters + seq]++)
			failf(c, "what=dup off=0x%lx idx=%lu seq=%lu", n * LINE, idx, seq);
	}
	for (k = 0; k < total; k++)
		if (!seen[k])
			failf(c, "what=missing idx=%lu seq=%lu", k / c->iters, k % c->iters);
	free(buf);
	free(seen);
}

static void
t_append(struct st_ctx *c)
{
	char path[400], line[LINE];
	time_t end = time(NULL) + WAIT;
	long i;
	int fd;

	mkshared(c, "append");
	sprintf(path, "%s/log", base);
	if (c->idx == 0) {
		fd = openat_(c, path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND);
	} else {
		while ((fd = open(path, O_WRONLY | O_APPEND)) < 0) {
			if (errno != ENOENT)
				failerr(c, "open");
			if (time(NULL) > end)
				st_fail(c, "reason=no-shared-file");
			usleep(10000);
		}
	}
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		mkline(line, c->idx, i);
		putline(c, fd, line);
		st_op_end(c, 1);
	}
	if (c->selfcheck && c->idx == 0) {
		mkline(line, 0, c->iters);
		line[12] = line[12] == '0' ? '1' : '0';	/* inside the hash */
		putline(c, fd, line);
	}
	close(fd);
	markdone(c);
	if (c->idx == 0) {
		waitdone(c, path);
		append_check(c, path);
		cleanup();
	}
}

/* tree: churn names d<a>/d<b>/f<c> in one tree; every call may lose a race,
 * so ENOENT, EEXIST, ENOTEMPTY and ENOTDIR are fine. Afterwards worker 0
 * walks the tree: every entry stats, "." and ".." point where they should and
 * no name is listed twice. */
static void
tname(char *buf, int lvl, struct st_ctx *c)
{
	int a = st_range(&c->rng, 0, 7), b = st_range(&c->rng, 0, 7), f = st_range(&c->rng, 0, 7);

	if (lvl == 1)
		sprintf(buf, "%s/t/d%d", base, a);
	else if (lvl == 2)
		sprintf(buf, "%s/t/d%d/d%d", base, a, b);
	else
		sprintf(buf, "%s/t/d%d/d%d/f%d", base, a, b, f);
}

static void
okerr(struct st_ctx *c, int r, const char *call)
{
	if (r < 0 && errno != ENOENT && errno != EEXIST && errno != ENOTEMPTY && errno != ENOTDIR)
		failerr(c, call);
}

/* BSD gives EINVAL for a directory renamed onto itself or while another
 * rename holds it; both are races here. */
static int
dirrename(const char *a, const char *b)
{
	int r = rename(a, b);

	if (r < 0 && errno == EINVAL)
		r = 0;
	return r;
}

#define MAXNAMES 64

static void
walk(struct st_ctx *c, const char *path, unsigned long parent_ino, int depth)
{
	char names[MAXNAMES][16], child[500];
	struct stat sb, sd, sc;
	struct dirent *de;
	int n = 0, i, j, dot = 0, dotdot = 0;
	DIR *d;

	if (stat(path, &sb) < 0)
		failerr(c, "stat");
	sprintf(child, "%s/.", path);
	if (stat(child, &sd) < 0)
		failerr(c, "stat");
	if (sd.st_ino != sb.st_ino || sd.st_dev != sb.st_dev)
		failf(c, "what=dot path=%s", path);
	sprintf(child, "%s/..", path);
	if (stat(child, &sd) < 0)
		failerr(c, "stat");
	if ((unsigned long)sd.st_ino != parent_ino)
		failf(c, "what=dotdot path=%s", path);
	d = opendir(path);
	if (d == NULL)
		failerr(c, "opendir");
	while ((de = readdir(d)) != NULL) {
		if (n == MAXNAMES || strlen(de->d_name) >= 16)
			failf(c, "what=badname path=%s", path);
		strcpy(names[n++], de->d_name);
	}
	closedir(d);
	for (i = 0; i < n; i++) {
		for (j = 0; j < i; j++)
			if (strcmp(names[i], names[j]) == 0)
				failf(c, "what=dupname name=%s path=%s", names[i], path);
		if (strcmp(names[i], ".") == 0) {
			dot++;
			continue;
		}
		if (strcmp(names[i], "..") == 0) {
			dotdot++;
			continue;
		}
		sprintf(child, "%s/%s", path, names[i]);
		if (lstat(child, &sc) < 0)
			failerr(c, "lstat");
		if (S_ISDIR(sc.st_mode)) {
			if (depth >= 3)
				failf(c, "what=toodeep path=%s", child);
			walk(c, child, (unsigned long)sb.st_ino, depth + 1);
		}
	}
	if (dot != 1 || dotdot != 1)
		failf(c, "what=dots path=%s", path);
}

static void
t_tree(struct st_ctx *c)
{
	char a[500], b[500], root[400];
	struct stat sb;
	long i;
	int r;

	mkshared(c, "tree");
	sprintf(root, "%s/t", base);
	if (c->idx == 0 && mkdir(root, 0700) < 0)
		failerr(c, "mkdir");
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		switch (st_range(&c->rng, 0, 9)) {
		case 0:
			tname(a, 1, c);
			okerr(c, mkdir(a, 0700), "mkdir");
			break;
		case 1:
			tname(a, 2, c);
			okerr(c, mkdir(a, 0700), "mkdir");
			break;
		case 2:
		case 3:
			tname(a, 3, c);
			r = open(a, O_WRONLY | O_CREAT, 0600);
			okerr(c, r, "open");
			if (r >= 0)
				close(r);
			break;
		case 4:
			tname(a, 3, c);
			okerr(c, unlink(a), "unlink");
			break;
		case 5:
			tname(a, 2, c);
			okerr(c, rmdir(a), "rmdir");
			break;
		case 6:
			tname(a, 1, c);
			okerr(c, rmdir(a), "rmdir");
			break;
		case 7:
			tname(a, 3, c);
			tname(b, 3, c);
			okerr(c, rename(a, b), "rename");
			break;
		case 8:
			tname(a, 2, c);
			tname(b, 2, c);
			okerr(c, dirrename(a, b), "rename");
			break;
		default:
			tname(a, 1, c);
			tname(b, 1, c);
			okerr(c, dirrename(a, b), "rename");
			break;
		}
		st_op_end(c, 1);
	}
	markdone(c);
	if (c->idx == 0) {
		waitdone(c, NULL);
		if (stat(base, &sb) < 0)
			failerr(c, "stat");
		walk(c, root, (unsigned long)sb.st_ino, 1);
		cleanup();
	}
}

/* fill: write 1 MB patterned files until the file system says ENOSPC, check
 * them all, delete them, and do it again. */
static void
t_fill(struct st_ctx *c)
{
	unsigned long sizes[MAXFILES], limit, key, off, sz;
	unsigned char *buf, b;
	char path[400];
	long round, n, nfiles, k, r, bad;
	unsigned long first = 0;
	int fd, hit;

	buf = malloc(CHUNK);
	if (buf == NULL)
		st_fail_errno(c, "malloc");
	limit = st_opt.mem ? st_opt.mem >> 20 : MAXFILES;
	if (limit > MAXFILES)
		limit = MAXFILES;
	/* a killed run leaves its files, which would make the file system look empty */
	sprintf(path, "rm -rf '%s'/stress.fs.fill.*", st_opt.dir);
	system(path);
	mkown(c, "fill");
	for (round = 0; st_more(c, round); round++) {
		st_op_begin(c);
		hit = 0;
		for (n = 0; !hit; n++) {
			if ((unsigned long)n >= limit)
				failf(c, "reason=no-enospc files=%ld", n);
			sprintf(path, "%s/f%ld", base, n);
			fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
			if (fd < 0 && errno == ENOSPC)
				break;
			if (fd < 0)
				failerr(c, "open");
			key = key3(round, n, 2);
			sz = 0;
			for (off = 0; off < EXT; off += CHUNK) {
				st_fill(buf, CHUNK, key, off);
				while ((r = write(fd, buf, CHUNK)) < 0 && errno == EINTR)
					;
				if (r < 0 && errno != ENOSPC)
					failerr(c, "write");
				if (r > 0)
					sz += r;
				if (r < (long)CHUNK) {
					hit = 1;
					break;
				}
			}
			if (hit && ftruncate(fd, (off_t)sz) < 0)
				failerr(c, "ftruncate");
			close(fd);
			sizes[n] = sz;
		}
		nfiles = n;
		if (c->selfcheck && round == 0 && nfiles > 0 && sizes[0] > 0) {
			off = st_range(&c->rng, 0, sizes[0] - 1);
			sprintf(path, "%s/f0", base);
			fd = openat_(c, path, O_RDWR);
			readfull(c, fd, &b, 1, off);
			b ^= 1;
			writefull(c, fd, &b, 1, off);
			close(fd);
		}
		for (k = 0; k < nfiles; k++) {
			struct stat sb;

			sprintf(path, "%s/f%ld", base, k);
			fd = openat_(c, path, O_RDONLY);
			if (fstat(fd, &sb) < 0)
				failerr(c, "fstat");
			if ((unsigned long)sb.st_size != sizes[k])
				failf(c, "what=size file=%ld got=0x%lx want=0x%lx", k,
				      (unsigned long)sb.st_size, sizes[k]);
			key = key3(round, k, 2);
			for (off = 0; off < sizes[k]; off += CHUNK) {
				sz = sizes[k] - off < CHUNK ? sizes[k] - off : CHUNK;
				readfull(c, fd, buf, sz, off);
				bad = st_check(buf, sz, key, off);
				if (bad >= 0) {
					cleanup();
					st_fail_data(c, "file", buf, sz, key, off, bad);
				}
			}
			close(fd);
		}
		sz = 0;
		for (k = 0; k < nfiles; k++) {
			sprintf(path, "%s/f%ld", base, k);
			if (unlink(path) < 0)
				failerr(c, "unlink");
			sz += sizes[k];
		}
		if (round == 0)
			first = sz;
		else if (sz < first / 2)
			failf(c, "reason=shrunk round=%ld got=%luMB first=%luMB", round, sz >> 20, first >> 20);
		st_op_end(c, sz >> 20);
	}
	cleanup();
	free(buf);
}

/* fsync: the descriptor opened before the write must see the block once
 * fsync has returned on the writing one. */
static void
t_fsync(struct st_ctx *c)
{
	unsigned char *buf, *got;
	unsigned long key, len;
	char path[400];
	long i, bad;
	int fd, fd2;

	buf = malloc(CHUNK);
	got = malloc(CHUNK);
	if (buf == NULL || got == NULL)
		st_fail_errno(c, "malloc");
	mkown(c, "fsync");
	sprintf(path, "%s/f", base);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		fd = openat_(c, path, O_RDWR | O_CREAT | O_TRUNC);
		fd2 = openat_(c, path, O_RDONLY);
		key = key3(c->idx, i, 3);
		len = st_range(&c->rng, 1, CHUNK);
		st_fill(buf, len, key, 0);
		writefull(c, fd, buf, len, 0);
		if (fsync(fd) < 0)
			failerr(c, "fsync");
		readfull(c, fd2, got, len, 0);
		bad = st_check(got, len, key, 0);
		if (bad >= 0) {
			cleanup();
			st_fail_data(c, "block", got, len, key, 0, bad);
		}
		close(fd);
		close(fd2);
		if (unlink(path) < 0)
			failerr(c, "unlink");
		st_op_end(c, 1);
	}
	cleanup();
	free(buf);
	free(got);
}

/* rename and link: each worker owns the names w<idx>.* in shared directories
 * and records every file it makes, so it knows exactly what must be there.
 * rename also reads other workers' files while they move. Each worker checks
 * its own records once its loop ends; worker 0 then removes the tree. */
#define NDIR	8
#define MAXF	32
#define MAXS	8
#define MAXL	16
#define MAXNN	4			/* link: names per file */
#define IDSPAN	1000000UL
#define FSIZE	64
#define MOVED	500000000L		/* serials of moved names start here */

struct rfile {
	unsigned long id;
	int dir;
	long ser;
};

static struct rfile rf[MAXF], rs[MAXS];	/* files; subdirectories holding a file "f" */
static int nrf, nrs;

static void
mkdirs(struct st_ctx *c, const char *test)
{
	char p[400];
	int k;

	mkshared(c, test);
	for (k = 0; k < NDIR; k++) {
		sprintf(p, "%s/d%d", base, k);
		if (mkdir(p, 0700) < 0 && errno != EEXIST)
			failerr(c, "mkdir");
	}
}

static void
fpath(char *buf, int dir, int idx, int kind, long ser)
{
	sprintf(buf, "%s/d%d/w%d.%c%ld", base, dir, idx, kind, ser);
}

static void
mkfile(struct st_ctx *c, const char *path, unsigned long id)
{
	unsigned char buf[FSIZE];
	int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);

	if (fd < 0)
		failerr(c, "open");
	st_fill(buf, FSIZE, id, 0);
	writefull(c, fd, buf, FSIZE, 0);
	close(fd);
}

static void
chkfile(struct st_ctx *c, const char *path, unsigned long id)
{
	unsigned char buf[FSIZE];
	long bad;
	int fd = open(path, O_RDONLY);

	if (fd < 0)
		failerr(c, "open");
	readfull(c, fd, buf, FSIZE, 0);
	close(fd);
	bad = st_check(buf, FSIZE, id, 0);
	if (bad >= 0) {
		cleanup();
		st_fail_data(c, "file", buf, FSIZE, id, 0, bad);
	}
}

/* The number of entries named w<idx>.* in d0..d7. */
static int
countown(struct st_ctx *c)
{
	char p[400], pre[16];
	struct dirent *de;
	DIR *d;
	int k, n = 0;

	sprintf(pre, "w%d.", c->idx);
	for (k = 0; k < NDIR; k++) {
		sprintf(p, "%s/d%d", base, k);
		d = opendir(p);
		if (d == NULL)
			failerr(c, "opendir");
		while ((de = readdir(d)) != NULL)
			if (strncmp(de->d_name, pre, strlen(pre)) == 0)
				n++;
		closedir(d);
	}
	return n;
}

/* A file of another worker, if one turns up: it may vanish at any point
 * (ENOENT), but what is read must be an id that worker could have written. */
static void
readforeign(struct st_ctx *c)
{
	char p[500], name[300];
	unsigned char buf[FSIZE];
	struct dirent *de;
	DIR *d;
	unsigned long w, n;
	long r;
	int fd, found = 0;

	sprintf(p, "%s/d%d", base, (int)st_range(&c->rng, 0, NDIR - 1));
	d = opendir(p);
	if (d == NULL)
		failerr(c, "opendir");
	while ((de = readdir(d)) != NULL) {
		if (de->d_name[0] == 'w' && atoi(de->d_name + 1) != c->idx && strstr(de->d_name, ".f") != NULL) {
			strcpy(name, de->d_name);
			found = 1;
			if (st_range(&c->rng, 0, 3) == 0)
				break;
		}
	}
	closedir(d);
	if (!found)
		return;
	strcat(p, "/");
	strcat(p, name);
	fd = open(p, O_RDONLY);
	if (fd < 0 && errno == ENOENT)
		return;
	if (fd < 0)
		failerr(c, "open");
	r = st_readfull(fd, buf, FSIZE);
	close(fd);
	if (r != FSIZE)
		failf(c, "reason=short-read name=%s got=%ld", name, r);
	w = (unsigned long)atoi(name + 1);
	for (n = 0; n <= (unsigned long)c->iters + 1; n++)
		if (st_check(buf, FSIZE, w * IDSPAN + n, 0) < 0)
			return;
	cleanup();
	st_fail_data(c, "file", buf, FSIZE, w * IDSPAN, 0, st_check(buf, FSIZE, w * IDSPAN, 0));
}

/* rename: moves a worker's files and subdirectories between d0..d7, renames
 * one of its files over another (retiring that id), and checks its records. */
static void
newfile(struct st_ctx *c, unsigned long *n)
{
	char tmp[500], a[500];
	unsigned long id = c->idx * IDSPAN + (*n)++;

	sprintf(tmp, "%s/d%d/w%d.tmp", base, (int)st_range(&c->rng, 0, NDIR - 1), c->idx);
	mkfile(c, tmp, id);			/* readers never see it half written */
	rf[nrf].id = id;
	rf[nrf].dir = st_range(&c->rng, 0, NDIR - 1);
	rf[nrf].ser = (long)id;
	fpath(a, rf[nrf].dir, c->idx, 'f', rf[nrf].ser);
	if (rename(tmp, a) < 0)
		failerr(c, "rename");
	nrf++;
}

static void
verify_rename(struct st_ctx *c)
{
	char a[500];
	int x;

	for (x = 0; x < nrf; x++) {
		fpath(a, rf[x].dir, c->idx, 'f', rf[x].ser);
		chkfile(c, a, rf[x].id);
	}
	for (x = 0; x < nrs; x++) {
		fpath(a, rs[x].dir, c->idx, 's', rs[x].ser);
		strcat(a, "/f");
		chkfile(c, a, rs[x].id);
	}
	if ((x = countown(c)) != nrf + nrs)
		failf(c, "reason=names got=%d want=%d", x, nrf + nrs);
}

static void
t_rename(struct st_ctx *c)
{
	char a[500], b[500];
	unsigned long n = 0, id;
	long i, ser = MOVED;
	int op, x, y, d;

	mkdirs(c, "rename");
	own[0] = '\0';		/* a FAIL must not remove the tree while others use it */
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		op = st_range(&c->rng, 0, 9);
		if (nrf < 2 && op >= 2 && op <= 5)
			op = 0;
		if (nrf == 0 && op == 9)
			op = 0;
		if (nrf == MAXF && op <= 1)
			op = 9;
		if (nrs == 0 && op == 7)
			op = 6;
		if (nrs == MAXS && op == 6)
			op = 7;
		switch (op) {
		case 0:
		case 1:
			newfile(c, &n);
			break;
		case 2:
		case 3:
		case 4:
			x = st_range(&c->rng, 0, nrf - 1);
			d = st_range(&c->rng, 0, NDIR - 1);
			fpath(a, rf[x].dir, c->idx, 'f', rf[x].ser);
			fpath(b, d, c->idx, 'f', ++ser);
			if (rename(a, b) < 0)
				failerr(c, "rename");
			rf[x].dir = d;
			rf[x].ser = ser;
			break;
		case 5:
			x = st_range(&c->rng, 0, nrf - 1);
			y = st_range(&c->rng, 0, nrf - 1);
			if (x == y)
				y = (y + 1) % nrf;
			fpath(a, rf[x].dir, c->idx, 'f', rf[x].ser);
			fpath(b, rf[y].dir, c->idx, 'f', rf[y].ser);
			if (rename(a, b) < 0)
				failerr(c, "rename");
			rf[y].id = rf[x].id;
			rf[x] = rf[--nrf];
			break;
		case 6:
			id = c->idx * IDSPAN + n++;
			rs[nrs].id = id;
			rs[nrs].dir = st_range(&c->rng, 0, NDIR - 1);
			rs[nrs].ser = (long)id;
			fpath(a, rs[nrs].dir, c->idx, 's', rs[nrs].ser);
			if (mkdir(a, 0700) < 0)
				failerr(c, "mkdir");
			strcat(a, "/f");
			mkfile(c, a, id);
			nrs++;
			break;
		case 7:
			x = st_range(&c->rng, 0, nrs - 1);
			d = st_range(&c->rng, 0, NDIR - 2);
			if (d >= rs[x].dir)
				d++;		/* never into its own directory */
			fpath(a, rs[x].dir, c->idx, 's', rs[x].ser);
			fpath(b, d, c->idx, 's', ++ser);
			if (rename(a, b) < 0)
				failerr(c, "rename");
			rs[x].dir = d;
			rs[x].ser = ser;
			break;
		case 8:
			readforeign(c);
			break;
		default:
			x = st_range(&c->rng, 0, nrf - 1);
			fpath(a, rf[x].dir, c->idx, 'f', rf[x].ser);
			if (unlink(a) < 0)
				failerr(c, "unlink");
			rf[x] = rf[--nrf];
			break;
		}
		st_op_end(c, 1);
	}
	verify_rename(c);
	markdone(c);
	if (c->idx == 0) {
		waitdone(c, NULL);
		strcpy(own, base);		/* nobody else is running: remove it */
		if (c->selfcheck) {		/* corrupt one file */
			unsigned char ch;

			if (nrf == 0)
				newfile(c, &n);
			fpath(a, rf[0].dir, c->idx, 'f', rf[0].ser);
			x = open(a, O_RDWR);
			if (x < 0)
				failerr(c, "open");
			readfull(c, x, &ch, 1, 0);
			ch = ~ch;
			writefull(c, x, &ch, 1, 0);
			close(x);
			verify_rename(c);
		}
		cleanup();
	}
}

/* link: files with 1 to 4 hard links in random directories, and symlinks to
 * them; st_nlink and readlink must agree with the records. */
struct lfile {
	unsigned long id;
	int nn;
	int dir[MAXNN + 1];
	long ser[MAXNN + 1];
};

struct lsym {
	int dir;
	long ser;
	char target[500];
};

static struct lfile lf[MAXF];
static struct lsym ls[MAXL];
static int nlf, nls;

static void
lnew(struct st_ctx *c, unsigned long *n, long *ser)
{
	char a[500];
	struct lfile *f = &lf[nlf];

	f->id = c->idx * IDSPAN + (*n)++;
	f->nn = 1;
	f->dir[0] = st_range(&c->rng, 0, NDIR - 1);
	f->ser[0] = ++*ser;
	fpath(a, f->dir[0], c->idx, 'f', f->ser[0]);
	mkfile(c, a, f->id);
	nlf++;
}

static void
chklink(struct st_ctx *c, const struct lsym *s)
{
	char a[500], got[500];
	long r;

	fpath(a, s->dir, c->idx, 's', s->ser);
	r = readlink(a, got, sizeof got - 1);
	if (r < 0)
		failerr(c, "readlink");
	got[r] = '\0';
	if (strcmp(got, s->target) != 0)
		failf(c, "reason=readlink path=%s got=%s", a, got);
}

static void
chknlink(struct st_ctx *c, const char *path, int want, struct stat *sb)
{
	if (stat(path, sb) < 0)
		failerr(c, "stat");
	if (sb->st_nlink != want)
		failf(c, "reason=nlink path=%s got=%d want=%d", path, (int)sb->st_nlink, want);
}

static void
verify_link(struct st_ctx *c)
{
	char a[500], b[500];
	struct stat sb, sn;
	int x, y, nn;

	for (x = 0; x < nlf; x++) {
		fpath(a, lf[x].dir[0], c->idx, 'f', lf[x].ser[0]);
		chknlink(c, a, lf[x].nn, &sb);
		chkfile(c, a, lf[x].id);
		for (y = 1; y < lf[x].nn; y++) {
			fpath(b, lf[x].dir[y], c->idx, 'f', lf[x].ser[y]);
			if (stat(b, &sn) < 0)
				failerr(c, "stat");
			if (sn.st_ino != sb.st_ino || sn.st_dev != sb.st_dev)
				failf(c, "reason=linkino path=%s", b);
		}
	}
	for (x = 0; x < nls; x++)
		chklink(c, &ls[x]);
	for (nn = 0, x = 0; x < nlf; x++)
		nn += lf[x].nn;
	if ((x = countown(c)) != nn + nls)
		failf(c, "reason=names got=%d want=%d", x, nn + nls);
}

/* UNSUP where the file system under -d has no hard links or symlinks
 * (msdosfs, HFS); any other error leaves it to the test. */
static int
p_link(char *why, int len)
{
	char d[400], f[420], l[420];
	const char *call = NULL;
	int fd, e = 0;

	if (strlen(st_opt.dir) + 40 > sizeof d)
		return 0;
	sprintf(d, "%s/stress.fs.lprobe.%ld", st_opt.dir, (long)getpid());
	rmrf(d);
	if (mkdir(d, 0700) < 0)
		return 0;
	sprintf(f, "%s/f", d);
	fd = open(f, O_CREAT | O_WRONLY, 0600);
	if (fd >= 0) {
		close(fd);
		sprintf(l, "%s/l", d);
		if (link(f, l) < 0) {
			call = "link";
			e = errno;
		} else {
			sprintf(l, "%s/s", d);
			if (symlink(f, l) < 0) {
				call = "symlink";
				e = errno;
			}
		}
	}
	rmrf(d);
	/* EPERM counts only for link(): some file systems use it for "not supported" */
	if (call == NULL || (e != EOPNOTSUPP && e != ENOSYS && (e != EPERM || call[0] != 'l')))
		return 0;
	sprintf(why, "%s: %s", call, st_errname(e));
	return 1;
}

static void
t_link(struct st_ctx *c)
{
	char a[500], b[500];
	struct stat sb;
	unsigned long n = 0;
	long i, ser = 0;
	int op, x, y, nn;

	mkdirs(c, "link");
	own[0] = '\0';		/* a FAIL must not remove the tree while others use it */
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		op = st_range(&c->rng, 0, 9);
		if (nlf == 0)
			op = 0;
		if (nlf == MAXF && op <= 2)
			op = 5;
		if (nls == MAXL && op == 7)
			op = 8;
		switch (op) {
		case 0:
		case 1:
		case 2:
			lnew(c, &n, &ser);
			break;
		case 3:
		case 4:
		case 9:
			x = st_range(&c->rng, 0, nlf - 1);
			nn = lf[x].nn;
			if (nn == MAXNN)
				break;
			fpath(a, lf[x].dir[0], c->idx, 'f', lf[x].ser[0]);
			lf[x].dir[nn] = st_range(&c->rng, 0, NDIR - 1);
			lf[x].ser[nn] = ++ser;
			fpath(b, lf[x].dir[nn], c->idx, 'f', lf[x].ser[nn]);
			if (link(a, b) < 0)
				failerr(c, "link");
			lf[x].nn++;
			break;
		case 5:
		case 6:
			x = st_range(&c->rng, 0, nlf - 1);
			y = st_range(&c->rng, 0, lf[x].nn - 1);
			fpath(a, lf[x].dir[y], c->idx, 'f', lf[x].ser[y]);
			if (unlink(a) < 0)
				failerr(c, "unlink");
			if (--lf[x].nn == 0) {
				lf[x] = lf[--nlf];
			} else {
				lf[x].dir[y] = lf[x].dir[lf[x].nn];
				lf[x].ser[y] = lf[x].ser[lf[x].nn];
			}
			break;
		case 7:
			x = st_range(&c->rng, 0, nlf - 1);
			ls[nls].dir = st_range(&c->rng, 0, NDIR - 1);
			ls[nls].ser = ++ser;
			fpath(ls[nls].target, lf[x].dir[0], c->idx, 'f', lf[x].ser[0]);
			fpath(a, ls[nls].dir, c->idx, 's', ls[nls].ser);
			if (symlink(ls[nls].target, a) < 0)
				failerr(c, "symlink");
			chklink(c, &ls[nls]);
			nls++;
			break;
		default:
			x = st_range(&c->rng, 0, nlf - 1);
			fpath(a, lf[x].dir[0], c->idx, 'f', lf[x].ser[0]);
			chknlink(c, a, lf[x].nn, &sb);
			break;
		}
		st_op_end(c, 1);
	}
	verify_link(c);
	markdone(c);
	if (c->idx == 0) {
		waitdone(c, NULL);
		strcpy(own, base);
		if (c->selfcheck) {
			if (nlf == 0)
				lnew(c, &n, &ser);
			lf[0].nn++;		/* one name too many */
			verify_link(c);
		}
		cleanup();
	}
}

static const struct st_test tests[] = {
	{ "rw",     200,  0, NULL, t_rw },
	{ "append", 2000, 0, NULL, t_append },
	{ "tree",   500,  0, NULL, t_tree },
	{ "fsync",  200,  0, NULL, t_fsync },
	{ "rename", 500,  0, NULL, t_rename },
	{ "link",   500,  0, p_link, t_link },
	{ "fill",   2,    1, NULL, t_fill, 1 },
	{ NULL }
};

int
main(int argc, char **argv)
{
	return stress_main(argc, argv, "fs", tests);
}
