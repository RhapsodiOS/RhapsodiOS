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

static void
failerr(struct st_ctx *c, const char *call)
{
	int e = errno;

	cleanup();
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

static const struct st_test tests[] = {
	{ "rw",     200,  0, NULL, t_rw },
	{ "append", 2000, 0, NULL, t_append },
	{ "tree",   500,  0, NULL, t_tree },
	{ "fsync",  200,  0, NULL, t_fsync },
	{ "fill",   2,    1, NULL, t_fill },
	{ NULL }
};

/* Without a named test the table loses its last entry, fill. Option
 * values (the word after -d, say) are not test names. */
static int
named_any(int argc, char **argv)
{
	const struct st_test *t;
	const char *p;
	int i;

	for (i = 1; i < argc; i++) {
		if (argv[i][0] == '-') {
			for (p = argv[i] + 1; *p != '\0' && strchr("nitsdm", *p) == NULL; p++)
				;
			if (*p != '\0' && p[1] == '\0')
				i++;
			continue;
		}
		for (t = tests; t->name != NULL; t++)
			if (strcmp(argv[i], t->name) == 0)
				return 1;
	}
	return 0;
}

int
main(int argc, char **argv)
{
	static struct st_test safe[sizeof tests / sizeof tests[0] - 1];

	if (!named_any(argc, argv)) {
		memcpy(safe, tests, sizeof safe);
		safe[sizeof safe / sizeof safe[0] - 1].name = NULL;
		return stress_main(argc, argv, "fs", safe);
	}
	return stress_main(argc, argv, "fs", tests);
}
