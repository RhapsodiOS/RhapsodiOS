/* stress-disk: raw device I/O on the -D device, which it overwrites. The
 * probe refuses (FAIL reason=unsafe-device) unless the device is a raw disk
 * node whose block twin is neither mounted nor on the root disk; each worker
 * repeats the checks right before it opens the device for writing. Writes
 * stay within the first -m bytes. Buffers come from valloc (page aligned). */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <dev/disk.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "stress.h"

#define SECT	512
#define BLK	65536
#define RMAX	131072		/* largest rand/verify transfer */
#define DEFMEM	(64UL * 1024 * 1024)
#define NREG	16		/* verify regions */
#define NREAD	3		/* verify readers */

/* The drive a disk node names: driverkit minors are unit * 8 + partition,
 * plus 128 for the _hfs_ nodes (IO_DISK_UNIT, MAKEDEV). */
#define UNIT(d)		((minor(d) & 0x7f) >> 3)
#define DRIVE(d)	((major(d) << 8) | UNIT(d))

static int
refuse(char *why, const char *detail)
{
	sprintf(why, "reason=unsafe-device detail=%s", detail);
	return -1;
}

/* 1 when /dev holds a raw node of major rmaj whose twin (the name without
 * its leading r) is a block node of major bmaj with the same minor: the
 * system's own raw/block pairing, so a node made elsewhere cannot pair a raw
 * device with another drive's block device. */
static int
paired(int rmaj, int bmaj)
{
	struct dirent *e;
	struct stat c, b;
	char p[MAXPATHLEN];
	DIR *d;
	int ok = 0;

	if ((d = opendir("/dev")) == NULL)
		return 0;
	while (!ok && (e = readdir(d)) != NULL) {
		if (e->d_name[0] != 'r' || strlen(e->d_name) + 6 > sizeof p)
			continue;
		sprintf(p, "/dev/%s", e->d_name);
		if (lstat(p, &c) < 0 || !S_ISCHR(c.st_mode) || major(c.st_rdev) != rmaj)
			continue;
		sprintf(p, "/dev/%s", e->d_name + 1);
		ok = lstat(p, &b) == 0 && S_ISBLK(b.st_mode) && major(b.st_rdev) == bmaj &&
		     minor(b.st_rdev) == minor(c.st_rdev);
	}
	closedir(d);
	return ok;
}

/* 0 when st_opt.dev may be written, else -1 with the FAIL fields in why.
 * g_raw is the device it approved, for the check after open. */
static dev_t g_raw = 0;

static int
safe(char *why)
{
	const char *dev = st_opt.dev, *base;
	struct stat raw, blk, root, sb;
	struct statfs *mnt;
	char twin[MAXPATHLEN];
	int i, n;

	base = strrchr(dev, '/');
	base = base != NULL ? base + 1 : dev;
	if (strlen(dev) >= sizeof twin)
		return refuse(why, "no-block-twin");
	sprintf(twin, "%.*s%s", (int)(base - dev), dev, *base == 'r' ? base + 1 : base);
	if ((lstat(dev, &sb) == 0 && S_ISLNK(sb.st_mode)) ||
	    (lstat(twin, &sb) == 0 && S_ISLNK(sb.st_mode)))
		return refuse(why, "symlink");
	if (lstat(dev, &raw) < 0 || !S_ISCHR(raw.st_mode))
		return refuse(why, "not-raw");
	if (*base != 'r' || lstat(twin, &blk) < 0 || !S_ISBLK(blk.st_mode) ||
	    minor(blk.st_rdev) != minor(raw.st_rdev) ||
	    !paired(major(raw.st_rdev), major(blk.st_rdev)))
		return refuse(why, "no-block-twin");
	if (stat("/", &root) < 0)
		return refuse(why, "stat-root");
	if (blk.st_rdev == root.st_dev)
		return refuse(why, "root-device");
	if (DRIVE(blk.st_rdev) == DRIVE(root.st_dev) ||
	    (UNIT(raw.st_rdev) == UNIT(root.st_dev) && paired(major(raw.st_rdev), major(root.st_dev))))
		return refuse(why, "root-disk");
	n = getmntinfo(&mnt, MNT_NOWAIT);
	if (n <= 0)
		return refuse(why, "getmntinfo");
	for (i = 0; i < n; i++) {
		if (strcmp(mnt[i].f_mntfromname, dev) == 0 || strcmp(mnt[i].f_mntfromname, twin) == 0)
			return refuse(why, "mounted");
		/* another partition of the same drive may overlap ours */
		if (stat(mnt[i].f_mntfromname, &sb) == 0 && S_ISBLK(sb.st_mode) &&
		    DRIVE(sb.st_rdev) == DRIVE(blk.st_rdev))
			return refuse(why, "mounted-disk");
	}
	g_raw = raw.st_rdev;
	return 0;
}

static unsigned long
memsize(void)
{
	return (st_opt.mem ? st_opt.mem : DEFMEM) & ~(unsigned long)(SECT - 1);
}

static int
probe(char *why, int len)
{
	int fd, nblk, bsize;

	if (st_opt.dev == NULL) {
		strcpy(why, "no device");
		return 1;
	}
	if (safe(why) < 0)
		return -1;
	fd = open(st_opt.dev, O_RDONLY);
	if (fd < 0) {
		sprintf(why, "reason=\"open: %s\"", st_errname(errno));
		return -1;
	}
	/* the drive's size bounds -m; without the ioctls, -m is trusted */
	if (ioctl(fd, DKIOCBLKSIZE, &bsize) == 0 && ioctl(fd, DKIOCNUMBLKS, &nblk) == 0) {
		if (bsize != SECT) {
			close(fd);
			sprintf(why, "reason=sector-size bytes=%d", bsize);
			return -1;
		}
		if ((unsigned long)nblk < memsize() / SECT) {
			close(fd);
			sprintf(why, "reason=mem-too-large mem=%lu sectors=%d", memsize(), nblk);
			return -1;
		}
	}
	close(fd);
	return 0;
}

static int
opendev(struct st_ctx *c)
{
	struct stat sb;
	char why[128];
	int fd;

	if (safe(why) < 0)
		st_fail(c, "%s", why);
	fd = open(st_opt.dev, O_RDWR);
	if (fd < 0)
		st_fail_errno(c, "open");
	/* the node may have been swapped since safe() looked */
	if (fstat(fd, &sb) < 0 || !S_ISCHR(sb.st_mode) || sb.st_rdev != g_raw) {
		close(fd);
		st_fail(c, "reason=unsafe-device detail=changed");
	}
	return fd;
}

/* Reads clear buf first, so a read that moved nothing cannot pass. */
static void
dio(struct st_ctx *c, int fd, int wr, unsigned char *buf, unsigned long len, unsigned long off)
{
	long r;

	if (!wr)
		memset(buf, 0, len);
	if (lseek(fd, (off_t)off, SEEK_SET) < 0)
		st_fail_errno(c, "lseek");
	r = wr ? st_writefull(fd, buf, len) : st_readfull(fd, buf, len);
	if (r < 0)
		st_fail(c, "reason=\"%s: %s\" off=0x%lx len=%lu", wr ? "write" : "read",
			st_errname(errno), off, len);
	if (r != (long)len)
		st_fail(c, "reason=short-%s off=0x%lx len=%lu got=%ld", wr ? "write" : "read",
			off, len, r);
}

static unsigned char *
getbuf(struct st_ctx *c, unsigned long len)
{
	unsigned char *b = valloc(len);

	if (b == NULL)
		st_fail_errno(c, "valloc");
	return b;
}

/* Each worker owns an equal aligned slice of [0, -m). */
static void
slice(struct st_ctx *c, unsigned long *lo, unsigned long *len)
{
	*len = (memsize() / c->nprocs) & ~(unsigned long)(SECT - 1);
	if (*len < BLK)
		st_fail(c, "reason=mem-too-small mem=%lu", memsize());
	*lo = *len * c->idx;
}

static void
seq(struct st_ctx *c)
{
	unsigned long lo, len, o, n, key;
	unsigned char *buf = getbuf(c, BLK);
	int fd = opendev(c);
	long i, bad;

	slice(c, &lo, &len);
	for (i = 0; st_more(c, i); i++) {
		key = st_mix(st_rand(&c->rng));
		st_op_begin(c);
		for (o = lo; o < lo + len; o += n) {
			n = lo + len - o < BLK ? lo + len - o : BLK;
			st_fill(buf, n, key, o);
			if (c->selfcheck && o == lo)	/* the slice's second sector gets the wrong key */
				st_fill(buf + SECT, SECT, key ^ 1, o + SECT);
			dio(c, fd, 1, buf, n, o);
		}
		for (o = lo; o < lo + len; o += n) {
			n = lo + len - o < BLK ? lo + len - o : BLK;
			dio(c, fd, 0, buf, n, o);
			if ((bad = st_check(buf, n, key, o)) >= 0)
				st_fail_data(c, "disk", buf, n, key, o, bad);
		}
		st_op_end(c, len / SECT);
	}
	close(fd);
}

static void
rnd(struct st_ctx *c)
{
	unsigned long lo, len, off, n, key;
	unsigned char *buf = getbuf(c, RMAX), *nb = getbuf(c, 2 * SECT);
	int fd = opendev(c);
	long i, bad;

	slice(c, &lo, &len);
	for (i = 0; st_more(c, i); i++) {
		n = st_range(&c->rng, 1, (len < RMAX ? len : RMAX) / SECT) * SECT;
		off = lo + st_range(&c->rng, 0, (len - n) / SECT) * SECT;
		key = st_mix(st_rand(&c->rng));
		st_op_begin(c);
		/* the sector below must survive: a write that lands early fails here */
		if (off > lo)
			dio(c, fd, 0, nb, SECT, off - SECT);
		st_fill(buf, n, key, off);
		if (c->selfcheck && i == 0)
			st_fill(buf, SECT, key ^ 1, off);
		dio(c, fd, 1, buf, n, off);
		dio(c, fd, 0, buf, n, off);
		if ((bad = st_check(buf, n, key, off)) >= 0)
			st_fail_data(c, "disk", buf, n, key, off, bad);
		if (off > lo) {
			dio(c, fd, 0, nb + SECT, SECT, off - SECT);
			if (memcmp(nb, nb + SECT, SECT) != 0)
				st_fail(c, "what=neighbour off=0x%lx len=%lu", off - SECT, n);
		}
		st_op_end(c, n / SECT);
	}
	close(fd);
}

/* verify: a writer child rewrites whole regions; before each it sends
 * (BEGIN, region) to every reader and after it (END, region, key). Readers
 * read regions not marked busy and drain their pipe again afterwards: any
 * record for that region means the writer may have overlapped the read, so
 * the read is not checked (the BEGIN went into the pipe before the write). */
#define R_BEGIN	1
#define R_END	2
#define R_QUIT	3

struct rec {
	unsigned long type, reg, key;
};

static pid_t g_kids[NREAD + 1];
static int g_nkids;

static void
hook(struct st_ctx *c)
{
	int i, st;

	for (i = 0; i < g_nkids; i++)
		if (g_kids[i] > 0)
			kill(g_kids[i], SIGKILL);
	for (i = 0; i < g_nkids; i++)
		while (g_kids[i] > 0 && waitpid(g_kids[i], &st, 0) < 0 && errno == EINTR)
			;
	g_nkids = 0;
}

/* Applies the records waiting in fd; returns a bit per region they named.
 * Sets *quit at R_QUIT or EOF. Records are written whole (< PIPE_BUF). */
static int
drain(struct st_ctx *c, int fd, unsigned long *keys, int *busy, int *quit)
{
	struct rec r[64];
	int n, i, hit = 0;

	for (;;) {
		n = read(fd, r, sizeof r);
		if (n < 0 && errno == EINTR)
			continue;
		if (n < 0 && errno == EAGAIN)
			return hit;
		if (n < 0)
			st_fail_errno(c, "read");
		if (n == 0) {
			*quit = 1;
			return hit;
		}
		for (i = 0; i < n / (int)sizeof r[0]; i++) {
			if (r[i].type == R_QUIT) {
				*quit = 1;
				continue;
			}
			hit |= 1 << r[i].reg;
			busy[r[i].reg] = r[i].type == R_BEGIN;
			if (r[i].type == R_END)
				keys[r[i].reg] = r[i].key;
		}
	}
}

static void
reader(struct st_ctx *c, int dfd, int pfd, unsigned long rs, unsigned long *keys)
{
	unsigned char *buf = getbuf(c, RMAX);
	unsigned long off, n, key;
	int busy[NREG], quit = 0, reg;
	long bad;

	memset(busy, 0, sizeof busy);
	if (fcntl(pfd, F_SETFL, O_NONBLOCK) < 0)
		st_fail_errno(c, "fcntl");
	for (;;) {
		drain(c, pfd, keys, busy, &quit);
		if (quit)
			break;
		reg = st_range(&c->rng, 0, NREG - 1);
		if (busy[reg])
			continue;
		n = st_range(&c->rng, 1, (rs < RMAX ? rs : RMAX) / SECT) * SECT;
		off = reg * rs + st_range(&c->rng, 0, (rs - n) / SECT) * SECT;
		key = keys[reg];
		dio(c, dfd, 0, buf, n, off);
		if (drain(c, pfd, keys, busy, &quit) & (1 << reg))
			continue;
		if ((bad = st_check(buf, n, key, off)) >= 0)
			st_fail_data(c, "disk", buf, n, key, off, bad);
	}
	_exit(0);
}

static void
tellall(struct st_ctx *c, int *pfd, unsigned long type, unsigned long reg, unsigned long key)
{
	struct rec r;
	int i;

	r.type = type;
	r.reg = reg;
	r.key = key;
	for (i = 0; i < NREAD; i++)
		if (st_writefull(pfd[i], &r, sizeof r) != sizeof r)
			st_fail_errno(c, "write");
}

static void
fillreg(struct st_ctx *c, int fd, unsigned char *buf, unsigned long lo, unsigned long len,
	unsigned long key)
{
	unsigned long o, n;

	for (o = lo; o < lo + len; o += n) {
		n = lo + len - o < BLK ? lo + len - o : BLK;
		st_fill(buf, n, key, o);
		dio(c, fd, 1, buf, n, o);
	}
}

static void
verify(struct st_ctx *c)
{
	unsigned long rs = (memsize() / NREG) & ~(unsigned long)(SECT - 1);
	unsigned long keys[NREG], base, key;
	unsigned char *buf = getbuf(c, BLK);
	int fd = opendev(c), p[NREAD][2], wfd[NREAD], i, j, st, failed = 0;
	long it;
	pid_t pid;

	if (rs < BLK)
		st_fail(c, "reason=mem-too-small mem=%lu", memsize());
	g_nkids = 0;
	st_set_cleanup(c, hook);
	st_op_begin(c);
	base = st_rand(&c->rng);
	for (i = 0; i < NREG; i++) {
		keys[i] = st_mix((base + i) & ST_MASK);
		fillreg(c, fd, buf, i * rs, rs, keys[i]);
	}
	for (i = 0; i < NREAD; i++)
		if (pipe(p[i]) < 0)
			st_fail_errno(c, "pipe");
	for (i = 0; i <= NREAD; i++) {
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0) {
			g_nkids = 0;	/* the hook is the coordinator's */
			close(fd);	/* a shared descriptor shares its offset */
			fd = opendev(c);
			for (j = 0; j < NREAD; j++) {
				if (i < NREAD)
					close(p[j][1]);
				if (j != i)
					close(p[j][0]);
			}
			if (i < NREAD) {
				st_rng_init(&c->rng, st_opt.seed, "verify-reader", i);
				reader(c, fd, p[i][0], rs, keys);
			}
			for (j = 0; j < NREAD; j++)
				wfd[j] = p[j][1];
			for (it = 0; st_more(c, it); it++) {
				j = st_range(&c->rng, 0, NREG - 1);
				key = st_mix(st_rand(&c->rng));
				tellall(c, wfd, R_BEGIN, j, 0);
				fillreg(c, fd, buf, j * rs, rs, key);
				tellall(c, wfd, R_END, j, key);
			}
			tellall(c, wfd, R_QUIT, 0, 0);
			_exit(0);
		}
		g_kids[g_nkids++] = pid;
	}
	for (i = 0; i < NREAD; i++) {
		close(p[i][0]);
		close(p[i][1]);
	}
	/* a child's FAIL line reaches the leader before its exit does */
	for (i = 0; i < g_nkids; i++) {
		while ((pid = waitpid(g_kids[i], &st, 0)) < 0 && errno == EINTR)
			;
		if (pid < 0)
			st_fail_errno(c, "waitpid");
		g_kids[i] = 0;
		if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
			failed = 1;
		if (failed)
			break;
	}
	if (failed)
		st_fail(c, "reason=child-failed child=%d status=0x%x", i, st);
	g_nkids = 0;
	st_op_end(c, c->iters);
	close(fd);
}

static const struct st_test tests[] = {
	{ "seq", 1, 0, probe, seq },
	{ "rand", 500, 0, probe, rnd },
	{ "verify", 200, 1, probe, verify },
	{ 0 }
};

int
main(int argc, char **argv)
{
	return stress_main(argc, argv, "disk", tests);
}
