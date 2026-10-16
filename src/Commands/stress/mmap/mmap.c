/* stress-mmap: memory-mapped file tests. Data written through a mapping must
 * be seen by read() and by other mappings, and the other way round. */
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "stress.h"

#define RW (PROT_READ | PROT_WRITE)

static char scratch[256];		/* removed by cleanup() */
static pid_t kid;			/* killed and reaped by cleanup() */
static volatile unsigned long *abortp;	/* shared: set when a worker fails */

static unsigned long
pagesz(void)
{
	return (unsigned long)getpagesize();
}

/* A key from the seed and three numbers, the same in every process. */
static unsigned long
key3(unsigned long a, unsigned long b, unsigned long d)
{
	return st_mix(st_mix(st_opt.seed ^ a) + b * 0x9e3779b1UL + d) & ST_MASK;
}

/* Everything a failing test must undo before st_fail takes the process. */
static void
cleanup(void)
{
	if (kid > 0) {
		kill(kid, SIGKILL);
		while (waitpid(kid, NULL, 0) < 0 && errno == EINTR)
			;
		kid = 0;
	}
	if (scratch[0] != '\0')
		unlink(scratch);
	if (abortp != NULL)
		*abortp = 1;
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

static void
chkmem(struct st_ctx *c, const char *what, const unsigned char *p, unsigned long len,
       unsigned long key, unsigned long off)
{
	long bad = st_check(p, len, key, off);

	if (bad >= 0) {
		cleanup();
		st_fail_data(c, what, p, len, key, off, bad);
	}
}

static void
mkscratch(struct st_ctx *c, const char *test, int id)
{
	if (strlen(st_opt.dir) + strlen(test) + 32 > sizeof scratch)
		st_fail(c, "reason=path-too-long");
	sprintf(scratch, "%s/stress.mmap.%s.map.%d", st_opt.dir, test, id);
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

static unsigned char *
mapfile(struct st_ctx *c, int fd, unsigned long len, int flags)
{
	void *p = mmap(NULL, len, RW, flags, fd, 0);

	if (p == (void *)-1)
		failerr(c, "mmap");
	return p;
}

static int
openfile(struct st_ctx *c, int flags)
{
	int fd = open(scratch, flags, 0600);

	if (fd < 0)
		failerr(c, "open");
	return fd;
}

/* shared: every worker maps one file, owns a region of it, and checks all
 * regions through the map and through read(). Page 0 holds two arrays of
 * words: ctr[w] is the passes whose data worker w has written, done[w] the
 * passes it has finished checking. A worker rewrites only when every done
 * has caught up, and checks only when every ctr has. */
#define MAXW 256
#define DONE MAXW

static void
waitall(volatile unsigned long *a, int n, unsigned long want)
{
	int j;

	for (j = 0; j < n; j++) {
		while (a[j] < want) {
			if (*abortp)
				_exit(1);
			usleep(10000);
		}
	}
}

static void
t_shared(struct st_ctx *c)
{
	unsigned long ps = pagesz(), fp, rp, rsz, size, base, key, pass;
	volatile unsigned long *ctr;
	unsigned char *map, *buf;
	unsigned long ready;
	struct stat sb;
	int fd, j;

	if (c->nprocs > MAXW)
		st_fail(c, "reason=too-many-procs");
	fp = c->nprocs <= 15 ? 16 : c->nprocs + 1;
	rp = (fp - 1) / c->nprocs;
	rsz = rp * ps;
	size = fp * ps;
	mkscratch(c, "shared", (int)getppid());
	ready = key3(9, 0, 0) | 1;
	if (c->idx == 0) {
		/* a file left by a killed run with this pid is replaced, and the
		 * marker goes in last so nobody uses it half made */
		unlink(scratch);
		fd = openfile(c, O_RDWR | O_CREAT | O_EXCL);
		if (ftruncate(fd, (off_t)size) < 0)
			failerr(c, "ftruncate");
		map = mapfile(c, fd, size, MAP_SHARED);
		ctr = (volatile unsigned long *)map;
		ctr[ps / sizeof *ctr - 2] = ready;
	} else {
		for (;;) {
			fd = open(scratch, O_RDWR);
			if (fd < 0 && errno != ENOENT)
				failerr(c, "open");
			if (fd >= 0) {
				if (fstat(fd, &sb) < 0)
					failerr(c, "fstat");
				/* a stale file has an old mtime, whatever its marker */
				if ((unsigned long)sb.st_size == size && sb.st_mtime >= c->t_start - 1) {
					map = mapfile(c, fd, size, MAP_SHARED);
					ctr = (volatile unsigned long *)map;
					if (ctr[ps / sizeof *ctr - 2] == ready)
						break;
					munmap(map, size);
				}
				close(fd);
			}
			usleep(10000);
		}
	}
	abortp = ctr + ps / sizeof *ctr - 1;
	buf = malloc(rsz);
	if (buf == NULL)
		failerr(c, "malloc");
	for (pass = 0; st_more(c, pass); pass++) {
		st_op_begin(c);
		waitall(ctr + DONE, c->nprocs, pass);
		base = ps + c->idx * rsz;
		st_fill(map + base, rsz, key3(1, pass, c->idx), base);
		if (c->selfcheck && pass == 0)
			map[base + st_range(&c->rng, 0, rsz - 1)] ^= 0x01;
		ctr[c->idx] = pass + 1;
		waitall(ctr, c->nprocs, pass + 1);
		for (j = 0; j < c->nprocs; j++) {
			base = ps + j * rsz;
			key = key3(1, pass, j);
			chkmem(c, "map", map + base, rsz, key, base);
			readfull(c, fd, buf, rsz, base);
			chkmem(c, "read", buf, rsz, key, base);
		}
		ctr[DONE + c->idx] = pass + 1;
		st_op_end(c, c->nprocs * rp);
	}
	waitall(ctr + DONE, c->nprocs, pass);
	if (c->idx == 0)
		unlink(scratch);
	scratch[0] = '\0';
	free(buf);
}

/* mixed: one process writes blocks with write() while the other, which has
 * the file mapped, checks each block as it is announced on a pipe; then the
 * roles swap. A block is 1 or 2 pages at a random page. */
static int
getbyte(int fd)
{
	unsigned char b;
	int r;

	while ((r = read(fd, &b, 1)) < 0 && errno == EINTR)
		;
	return r == 1 ? b : -1;
}

static void
putbyte(int fd, int v)
{
	unsigned char b = v;

	write(fd, &b, 1);		/* a dead reader shows as EOF the other way */
}

static unsigned long
blen(unsigned long n, unsigned long ps)
{
	return (1 + (n & 1)) * ps;
}

static void
mixed_b(struct st_ctx *c, int rd, int wr, unsigned long fsize)
{
	unsigned long ps = pagesz(), n, len, p;
	unsigned char *map;
	int fd;

	fd = openfile(c, O_RDWR);
	map = mapfile(c, fd, fsize, MAP_SHARED);
	putbyte(wr, 0);
	for (n = 0; n < (unsigned long)c->iters; n++) {
		p = getbyte(rd);
		if (p > 255)
			_exit(1);
		len = blen(n, ps);
		chkmem(c, "map", map + p * ps, len, key3(2, n, 0), p * ps);
		putbyte(wr, 0);
	}
	for (n = 0; n < (unsigned long)c->iters; n++) {
		len = blen(n, ps);
		p = st_range(&c->rng, 0, fsize / ps - len / ps);
		st_fill(map + p * ps, len, key3(2, n, 1), p * ps);
		putbyte(wr, p);
		if (getbyte(rd) < 0)
			_exit(1);
	}
	_exit(0);
}

static void
reap(struct st_ctx *c, int *status)
{
	pid_t r;

	while ((r = waitpid(kid, status, 0)) < 0 && errno == EINTR)
		;
	if (r < 0)
		failerr(c, "waitpid");
	kid = 0;
}

static void
badstatus(struct st_ctx *c, int status)
{
	failf(c, "reason=\"child: status=0x%x\"", status);
}

static void
kidfail(struct st_ctx *c)
{
	int status;

	reap(c, &status);
	badstatus(c, status);
}

static void
t_mixed(struct st_ctx *c)
{
	unsigned long ps = pagesz(), size = 16 * ps, n, len, p, off;
	int a2b[2], b2a[2], fd, status = 0, v;
	unsigned char *buf;

	signal(SIGPIPE, SIG_IGN);
	mkscratch(c, "mixed", (int)getpid());
	fd = openfile(c, O_RDWR | O_CREAT | O_TRUNC);
	if (ftruncate(fd, (off_t)size) < 0)
		failerr(c, "ftruncate");
	buf = malloc(2 * ps);
	if (buf == NULL || pipe(a2b) < 0 || pipe(b2a) < 0)
		failerr(c, "pipe");
	kid = fork();
	if (kid < 0) {
		kid = 0;
		failerr(c, "fork");
	}
	if (kid == 0) {
		close(a2b[1]);
		close(b2a[0]);
		mixed_b(c, a2b[0], b2a[1], size);
	}
	close(a2b[0]);
	close(b2a[1]);
	if (getbyte(b2a[0]) < 0)
		kidfail(c);
	for (n = 0; n < (unsigned long)c->iters; n++) {
		st_op_begin(c);
		len = blen(n, ps);
		p = st_range(&c->rng, 0, size / ps - len / ps);
		st_fill(buf, len, key3(2, n, 0), p * ps);
		writefull(c, fd, buf, len, p * ps);
		if (c->selfcheck && n == 0) {
			off = st_range(&c->rng, 0, len - 1);
			buf[off] ^= 0x01;
			writefull(c, fd, buf + off, 1, p * ps + off);
		}
		putbyte(a2b[1], p);
		if (getbyte(b2a[0]) < 0)
			kidfail(c);
		st_op_end(c, 1);
	}
	for (n = 0; n < (unsigned long)c->iters; n++) {
		st_op_begin(c);
		v = getbyte(b2a[0]);
		if (v < 0)
			kidfail(c);
		len = blen(n, ps);
		readfull(c, fd, buf, len, v * ps);
		chkmem(c, "read", buf, len, key3(2, n, 1), v * ps);
		putbyte(a2b[1], 0);
		st_op_end(c, 1);
	}
	close(a2b[1]);
	close(b2a[0]);
	reap(c, &status);
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
		badstatus(c, status);
	close(fd);
	unlink(scratch);
	scratch[0] = '\0';
	free(buf);
}

/* private: a MAP_PRIVATE map takes writes in memory only. */
static void
t_private(struct st_ctx *c)
{
	unsigned long ps = pagesz(), size = 16 * ps, k1, k2, p;
	unsigned char *buf, *map, *map2;
	int fd, fd2, status = 0;
	long i;

	st_path(c, scratch, sizeof scratch, "map");
	buf = malloc(size);
	if (buf == NULL)
		failerr(c, "malloc");
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		k1 = key3(3, i, c->idx);
		k2 = key3(4, i, c->idx);
		fd = openfile(c, O_RDWR | O_CREAT | O_TRUNC);
		st_fill(buf, size, k1, 0);
		writefull(c, fd, buf, size, 0);
		map = mapfile(c, fd, size, MAP_PRIVATE);
		for (p = 0; p < 16; p += 2)
			st_fill(map + p * ps, ps, k2, p * ps);
		if (c->selfcheck && i == 0)
			map[2 * st_range(&c->rng, 0, 7) * ps + st_range(&c->rng, 0, ps - 1)] ^= 0x01;
		readfull(c, fd, buf, size, 0);
		chkmem(c, "read", buf, size, k1, 0);
		kid = fork();
		if (kid < 0) {
			kid = 0;
			failerr(c, "fork");
		}
		if (kid == 0) {
			fd2 = openfile(c, O_RDWR);
			map2 = mapfile(c, fd2, size, MAP_PRIVATE);
			chkmem(c, "child-map", map2, size, k1, 0);
			_exit(0);
		}
		reap(c, &status);
		if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
			badstatus(c, status);
		for (p = 0; p < 16; p++)
			chkmem(c, "map", map + p * ps, ps, p % 2 ? k1 : k2, p * ps);
		munmap(map, size);
		close(fd);
		st_op_end(c, 16);
	}
	unlink(scratch);
	scratch[0] = '\0';
	free(buf);
}

/* trunc and anon expect a fault; the handler jumps back to touch(). BSD
 * setjmp saves and restores the signal mask. */
static jmp_buf jb;
static volatile int gotsig;
static volatile unsigned char sink;

static void
onsig(int sig)
{
	gotsig = sig;
	longjmp(jb, 1);
}

static void
trap(void)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = onsig;
	sigaction(SIGBUS, &sa, NULL);
	sigaction(SIGSEGV, &sa, NULL);
}

/* Any fault outside touch() must kill the worker, not jump into a dead frame. */
static void
untrap(void)
{
	signal(SIGBUS, SIG_DFL);
	signal(SIGSEGV, SIG_DFL);
}

/* Reads or writes one byte; returns the signal it took, else 0. */
static int
touch(volatile unsigned char *p, int wr)
{
	trap();
	gotsig = 0;
	if (setjmp(jb) == 0) {
		if (wr)
			*p = 1;
		else
			sink = *p;
	}
	untrap();
	return gotsig;
}

static void
t_trunc(struct st_ctx *c)
{
	unsigned long ps = pagesz(), size = 16 * ps, key, j;
	unsigned char *map;
	long i;
	int fd, sig, nbus = 0, nsegv = 0;

	st_path(c, scratch, sizeof scratch, "map");
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		key = key3(5, i, c->idx);
		fd = openfile(c, O_RDWR | O_CREAT | O_TRUNC);
		if (ftruncate(fd, (off_t)size) < 0)
			failerr(c, "ftruncate");
		map = mapfile(c, fd, size, MAP_SHARED);
		st_fill(map, size, key, 0);
		if (c->selfcheck && i == 0)
			map[st_range(&c->rng, 0, 5 * ps - 1)] ^= 0x01;
		if (ftruncate(fd, (off_t)(5 * ps)) < 0)
			failerr(c, "ftruncate");
		sig = touch(map + 7 * ps, 0);
		if (sig == 0)
			failf(c, "reason=no-sigbus");
		if (sig == SIGBUS)
			nbus++;
		else
			nsegv++;
		chkmem(c, "kept", map, 5 * ps, key, 0);
		if (ftruncate(fd, (off_t)size) < 0)
			failerr(c, "ftruncate");
		for (j = 5 * ps; j < size; j++)
			if (map[j] != 0)
				failf(c, "what=regrow off=0x%lx want=00 got=%02x", j, map[j]);
		munmap(map, size);
		close(fd);
		st_op_end(c, 16);
	}
	if (st_opt.verbose)
		fprintf(stderr, "stress-mmap: trunc worker %d: sigbus=%d sigsegv=%d\n",
			c->idx, nbus, nsegv);
	unlink(scratch);
	scratch[0] = '\0';
}

#define ANONSIZE (64 * 1024)

/* the guest's libc has no madvise or mincore stubs, so they are raw syscalls (75, 78) */
static int
madv(void *p, size_t len, int advice)
{
	return syscall(75, p, len, advice);
}

static int
minc(void *p, size_t len, char *vec)
{
	return syscall(78, p, len, vec);
}

/* libc has no mprotect stub on this system; vm_protect is the same call. */
static int
protect(unsigned char *p, int prot)
{
	return vm_protect(task_self(), (vm_address_t)p, ANONSIZE, FALSE, prot) == KERN_SUCCESS ? 0 : -1;
}

/* Older kernels refuse MAP_ANON with EINVAL ("not supported"), so EINVAL means UNSUP. */
static int
p_anon(char *why, int len)
{
	void *p = mmap(NULL, pagesz(), RW, MAP_ANON | MAP_PRIVATE, -1, 0);
	int e = errno;

	if (p != (void *)-1) {
		munmap(p, pagesz());
		return 0;
	}
	if (e != ENOSYS && e != EINVAL && e != EOPNOTSUPP)
		return 0;
	sprintf(why, "mmap: %s", st_errname(e));
	return 1;
}

static void
t_anon(struct st_ctx *c)
{
	unsigned char *p;
	unsigned long key;
	char vec[ANONSIZE / 512];
	long i;
	int sig, j;

	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		key = key3(6, i, c->idx);
		p = mmap(NULL, ANONSIZE, RW, MAP_ANON | MAP_PRIVATE, -1, 0);
		if (p == (unsigned char *)-1)
			failerr(c, "mmap");
		st_fill(p, ANONSIZE, key, 0);
		if (minc(p, ANONSIZE, vec) < 0)
			failerr(c, "mincore");
		for (j = 0; j < ANONSIZE / pagesz(); j++)
			if (vec[j] == 0)
				failf(c, "reason=\"mincore: page %d not resident\"", j);
		for (j = MADV_NORMAL; j <= MADV_DONTNEED; j++)
			if (madv(p, ANONSIZE, j) < 0)
				failerr(c, "madvise");
		if (madv(p, ANONSIZE, 99) == 0 || errno != EINVAL)
			failf(c, "reason=\"madvise: bad advice not EINVAL\"");
		if (c->selfcheck && i == 0)
			p[st_range(&c->rng, 0, ANONSIZE - 1)] ^= 0x01;
		if (protect(p, VM_PROT_READ) < 0)
			failf(c, "reason=\"vm_protect: failed\"");
		sig = touch(p, 1);
		/* touch() catches only SIGSEGV and SIGBUS; Mach reports a write to
		 * a read-only page as SIGBUS, so either is the expected fault. */
		if (sig == 0)
			failf(c, "reason=no-sigsegv");
		if (protect(p, VM_PROT_READ | VM_PROT_WRITE) < 0)
			failf(c, "reason=\"vm_protect: failed\"");
		chkmem(c, "anon", p, ANONSIZE, key, 0);
		if (munmap((caddr_t)p, ANONSIZE) < 0)
			failerr(c, "munmap");
		st_op_end(c, ANONSIZE / 1024);
	}
}

/* Parent and forked child each fill half of the shared map p and check the
 * other's half, in lockstep over two pipes; the child exits 0 when it is happy. */
static void
sharedpair(struct st_ctx *c, unsigned char *p, unsigned long key, int first)
{
	unsigned long half = ANONSIZE / 2;
	int a2b[2], b2a[2], status = 0;

	signal(SIGPIPE, SIG_IGN);
	if (pipe(a2b) < 0 || pipe(b2a) < 0)
		failerr(c, "pipe");
	kid = fork();
	if (kid < 0) {
		kid = 0;
		failerr(c, "fork");
	}
	if (kid == 0) {
		close(a2b[1]);
		close(b2a[0]);
		st_fill(p + half, half, key ^ 1, half);
		putbyte(b2a[1], 0);
		if (getbyte(a2b[0]) < 0)
			_exit(1);
		chkmem(c, "child-map", p, half, key, 0);
		_exit(0);
	}
	close(a2b[0]);
	close(b2a[1]);
	st_fill(p, half, key, 0);
	if (getbyte(b2a[0]) < 0)
		kidfail(c);
	if (c->selfcheck && first)
		p[half + st_range(&c->rng, 0, half - 1)] ^= 0x01;
	putbyte(a2b[1], 0);
	chkmem(c, "map", p + half, half, key ^ 1, half);
	close(a2b[1]);
	close(b2a[0]);
	reap(c, &status);
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
		badstatus(c, status);
}

/* anonshared: MAP_SHARED anonymous memory is shared with a forked child. */
static void
t_anonshared(struct st_ctx *c)
{
	unsigned char *p;
	long i;

	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		p = mmap(NULL, ANONSIZE, RW, MAP_ANON | MAP_SHARED, -1, 0);
		if (p == (unsigned char *)-1)
			failerr(c, "mmap");
		sharedpair(c, p, key3(8, i, c->idx), i == 0);
		munmap((caddr_t)p, ANONSIZE);
		st_op_end(c, ANONSIZE / 1024);
	}
}

/* zero: /dev/zero reads as zeros, swallows writes, and maps as anonymous memory. */
static int
p_zero(char *why, int len)
{
	struct stat sb;
	void *p;
	int fd, e;

	if (stat("/dev/zero", &sb) < 0 || !S_ISCHR(sb.st_mode)) {
		sprintf(why, "/dev/zero: absent");
		return 1;
	}
	fd = open("/dev/zero", O_RDWR);
	if (fd < 0)
		return 0;
	p = mmap(NULL, pagesz(), RW, MAP_PRIVATE, fd, 0);
	e = errno;
	close(fd);
	if (p != (void *)-1) {
		munmap(p, pagesz());
		return 0;
	}
	if (e != EOPNOTSUPP && e != ENODEV && e != EINVAL)
		return 0;
	sprintf(why, "mmap: %s", st_errname(e));
	return 1;
}

static void
chkzero(struct st_ctx *c, const char *what, const unsigned char *p, unsigned long len)
{
	unsigned long j;

	for (j = 0; j < len; j++)
		if (p[j] != 0)
			failf(c, "what=%s off=0x%lx want=00 got=%02x", what, j, p[j]);
}

static void
t_zero(struct st_ctx *c)
{
	unsigned char *buf, *p, *p2;
	unsigned long key;
	long i;
	int fd;

	buf = malloc(ANONSIZE);
	if (buf == NULL)
		failerr(c, "malloc");
	fd = open("/dev/zero", O_RDWR);
	if (fd < 0)
		failerr(c, "open");
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		key = key3(9, i, c->idx);
		st_fill(buf, ANONSIZE, key, 0);
		if (read(fd, buf, ANONSIZE) != ANONSIZE)
			failerr(c, "read");
		chkzero(c, "read", buf, ANONSIZE);
		st_fill(buf, ANONSIZE, key, 0);
		if (write(fd, buf, ANONSIZE) != ANONSIZE)
			failerr(c, "write");
		p = mapfile(c, fd, ANONSIZE, MAP_PRIVATE);
		chkzero(c, "map", p, ANONSIZE);
		st_fill(p, ANONSIZE, key, 0);
		p2 = mapfile(c, fd, ANONSIZE, MAP_PRIVATE);
		chkzero(c, "map2", p2, ANONSIZE);
		chkmem(c, "filled", p, ANONSIZE, key, 0);
		munmap((caddr_t)p2, ANONSIZE);
		munmap((caddr_t)p, ANONSIZE);
		p = mapfile(c, fd, ANONSIZE, MAP_SHARED);
		sharedpair(c, p, key, i == 0);
		munmap((caddr_t)p, ANONSIZE);
		st_op_end(c, ANONSIZE / 1024);
	}
	close(fd);
	free(buf);
}

/* libc may have no msync stub, so the call is bound through dyld like mlock
 * in stress-vm; it takes just an address and a length here. */
static int (*syncfn)(void *, size_t);

static int
bindsync(void)
{
	if (syncfn == NULL && NSIsSymbolNameDefined("_msync"))
		syncfn = (int (*)(void *, size_t))NSAddressOfSymbol(NSLookupAndBindSymbol("_msync"));
	return syncfn != NULL;
}

static int
p_sync(char *why, int len)
{
	unsigned long ps = pagesz();
	char path[256];
	void *p;
	int fd, r, e;

	if (!bindsync()) {
		sprintf(why, "msync: %s", st_errname(ENOSYS));
		return 1;
	}
	sprintf(path, "%s/stress.mmap.sync.probe.%d", st_opt.dir, (int)getpid());
	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
	if (fd < 0)
		return 0;
	unlink(path);
	r = -1;
	e = 0;
	if (ftruncate(fd, (off_t)ps) == 0 &&
	    (p = mmap(NULL, ps, RW, MAP_SHARED, fd, 0)) != (void *)-1) {
		r = syncfn(p, ps);
		e = errno;
		munmap(p, ps);
	}
	close(fd);
	if (r == 0 || (e != ENOSYS && e != EINVAL && e != EOPNOTSUPP))
		return 0;
	sprintf(why, "msync: %s", st_errname(e));
	return 1;
}

static void
t_sync(struct st_ctx *c)
{
	unsigned long ps = pagesz(), size = 16 * ps, key;
	unsigned char *map, *buf;
	long i;
	int fd, fd2;

	bindsync();
	st_path(c, scratch, sizeof scratch, "map");
	buf = malloc(size);
	if (buf == NULL)
		failerr(c, "malloc");
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		key = key3(7, i, c->idx);
		fd = openfile(c, O_RDWR | O_CREAT | O_TRUNC);
		if (ftruncate(fd, (off_t)size) < 0)
			failerr(c, "ftruncate");
		map = mapfile(c, fd, size, MAP_SHARED);
		st_fill(map, size, key, 0);
		if (c->selfcheck && i == 0)
			map[st_range(&c->rng, 0, size - 1)] ^= 0x01;
		if (syncfn(map, size) < 0)
			failerr(c, "msync");
		fd2 = openfile(c, O_RDONLY);
		readfull(c, fd2, buf, size, 0);
		chkmem(c, "read", buf, size, key, 0);
		close(fd2);
		munmap(map, size);
		close(fd);
		st_op_end(c, 16);
	}
	unlink(scratch);
	scratch[0] = '\0';
	free(buf);
}

static const struct st_test tests[] = {
	{ "shared", 50, 0, NULL, t_shared },
	{ "mixed", 100, 1, NULL, t_mixed },
	{ "private", 50, 0, NULL, t_private },
	{ "trunc", 30, 0, NULL, t_trunc },
	{ "anon", 200, 0, p_anon, t_anon },
	{ "sync", 20, 0, p_sync, t_sync },
	{ "anonshared", 100, 0, p_anon, t_anonshared },
	{ "zero", 100, 0, p_zero, t_zero },
	{ NULL }
};

int
main(int argc, char **argv)
{
	return stress_main(argc, argv, "mmap", tests);
}
