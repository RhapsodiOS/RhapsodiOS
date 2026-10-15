/* stress-misc: system services (file locks, timers, limits, fifos,
 * descriptors, process groups). Waits are bounded; the cleanup hook kills
 * what a test forked and removes its scratch files. usleep is not used: it
 * is built on ITIMER_REAL here and would cancel an armed timer. */
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "stress.h"

#define PATHLEN	256
#define FLEN	21		/* flock file: "%010lu %010lu" counter, done */
#define FIFOLEN	262144
#define FIFOSECS 120
#define WAIT	5

static char g_path[PATHLEN];
static pid_t g_kid, g_pg;

static void
nap(long us)
{
	struct timeval tv;

	tv.tv_sec = us / 1000000;
	tv.tv_usec = us % 1000000;
	select(0, NULL, NULL, NULL, &tv);
}

static void
hook(struct st_ctx *c)
{
	int st;

	alarm(0);
	if (g_kid > 0) {
		kill(g_kid, SIGKILL);
		while (waitpid(g_kid, &st, 0) < 0 && errno == EINTR)
			;
		g_kid = 0;
	}
	if (g_pg > 0)
		killpg(g_pg, SIGKILL);
	if (g_path[0])
		unlink(g_path);
}

static void
setup(struct st_ctx *c)
{
	g_path[0] = '\0';
	g_kid = g_pg = 0;
	st_set_cleanup(c, hook);
}

/* Shared file name: the leader's pid (our parent) is the same for every worker. */
static void
sharedpath(struct st_ctx *c, const char *tag)
{
	if (strlen(st_opt.dir) + strlen(tag) + 32 > PATHLEN)
		st_fail(c, "reason=path-too-long tag=%s", tag);
	sprintf(g_path, "%s/stress.misc.%s.%d", st_opt.dir, tag, (int)getppid());
}

/* Worker 0 creates the file with its initial contents in one write; the
 * others wait (30 s) for a file of that size modified since the test began. */
static void
sharedfile(struct st_ctx *c, const char *init, int len)
{
	struct stat sb;
	time_t t0;
	int fd;

	if (c->idx == 0) {
		unlink(g_path);
		fd = open(g_path, O_RDWR | O_CREAT | O_TRUNC, 0600);
		if (fd < 0)
			st_fail_errno(c, "open");
		if (st_writefull(fd, init, len) != len)
			st_fail_errno(c, "write");
		close(fd);
		return;
	}
	t0 = time(NULL);
	for (;; nap(2000)) {
		fd = open(g_path, O_RDWR);
		if (fd >= 0) {
			if (fstat(fd, &sb) == 0 && sb.st_size == len && sb.st_mtime >= c->t_start - 1) {
				close(fd);
				return;
			}
			close(fd);
		}
		if (time(NULL) - t0 > 30)
			st_fail(c, "reason=timeout what=sharedfile");
	}
}

/* A missing file means a peer failed and unlinked it; its FAIL line is on the way and the leader kills us, so wait for that before reporting ENOENT. */
static int
openshared(struct st_ctx *c)
{
	int fd, i;

	for (i = 0; i < 100; i++) {
		fd = open(g_path, O_RDWR);
		if (fd >= 0 || errno != ENOENT)
			break;
		nap(50000);
	}
	if (fd < 0)
		st_fail_errno(c, "open");
	return fd;
}

static unsigned long
rdnum(struct st_ctx *c, int fd, long off, int n)
{
	char b[16];

	if (lseek(fd, off, SEEK_SET) < 0 || st_readfull(fd, b, n) != n)
		st_fail_errno(c, "read");
	b[n] = '\0';
	return strtoul(b, NULL, 10);
}

static void
wrnum(struct st_ctx *c, int fd, long off, int n, unsigned long v)
{
	char b[24];

	sprintf(b, "%0*lu", n, v);
	if (lseek(fd, off, SEEK_SET) < 0 || st_writefull(fd, b, n) != n)
		st_fail_errno(c, "write");
}

/* flock: one decimal counter and a done count in one file. */
static void
t_flock(struct st_ctx *c)
{
	char init[FLEN + 1];
	unsigned long v, d;
	int fd, i;

	setup(c);
	sharedpath(c, "flock");
	sprintf(init, "%010lu %010lu", 0UL, 0UL);
	sharedfile(c, init, FLEN);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		fd = openshared(c);
		if (flock(fd, LOCK_EX) < 0)
			st_fail_errno(c, "flock");
		v = rdnum(c, fd, 0, 10);
		if (!(c->selfcheck && c->idx == 0 && i == 0))
			v++;
		wrnum(c, fd, 0, 10, v);
		flock(fd, LOCK_UN);
		close(fd);
		st_op_end(c, 1);
	}
	fd = openshared(c);
	if (flock(fd, LOCK_EX) < 0)
		st_fail_errno(c, "flock");
	v = rdnum(c, fd, 0, 10);
	d = rdnum(c, fd, 11, 10) + 1;
	wrnum(c, fd, 11, 10, d);
	flock(fd, LOCK_UN);
	close(fd);
	if (d == (unsigned long)c->nprocs) {
		if (v != (unsigned long)c->nprocs * (unsigned long)c->iters)
			st_fail(c, "what=counter want=%lu got=%lu",
				(unsigned long)c->nprocs * (unsigned long)c->iters, v);
		unlink(g_path);
	}
}

static void
rlock(struct st_ctx *c, int fd, long off, int type)
{
	struct flock fl;

	memset(&fl, 0, sizeof fl);
	fl.l_type = type;
	fl.l_whence = SEEK_SET;
	fl.l_start = off;
	fl.l_len = 8;
	while (fcntl(fd, F_SETLKW, &fl) < 0)
		if (errno != EINTR)
			st_fail_errno(c, "fcntl");
}

/* fcntl: record 0 counts finished workers; pair r has a counter at 8+16r
 * and its done count at 16+16r, each an 8-digit record. */
static void
t_fcntl(struct st_ctx *c)
{
	char *init;
	unsigned long v, d, want;
	long cnt, dn, len;
	int fd, i, pair, psize;

	setup(c);
	sharedpath(c, "fcntl");
	pair = c->idx / 2;
	cnt = 8 + 16L * pair;
	dn = cnt + 8;
	len = 8 + 16L * ((c->nprocs + 1) / 2);
	init = malloc(len);
	if (init == NULL)
		st_fail(c, "reason=\"malloc: ENOMEM\"");
	memset(init, '0', len);
	sharedfile(c, init, len);
	free(init);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		fd = openshared(c);
		rlock(c, fd, cnt, F_WRLCK);
		v = rdnum(c, fd, cnt, 8);
		if (!(c->selfcheck && c->idx == 0 && i == 0))
			v++;
		wrnum(c, fd, cnt, 8, v);
		rlock(c, fd, cnt, F_UNLCK);
		close(fd);
		st_op_end(c, 1);
	}
	fd = openshared(c);
	rlock(c, fd, dn, F_WRLCK);
	d = rdnum(c, fd, dn, 8) + 1;
	wrnum(c, fd, dn, 8, d);
	rlock(c, fd, dn, F_UNLCK);
	psize = 2 * pair + 1 < c->nprocs ? 2 : 1;
	if (d == (unsigned long)psize) {
		v = rdnum(c, fd, cnt, 8);
		want = (unsigned long)psize * (unsigned long)c->iters;
		if (v != want)
			st_fail(c, "what=counter pair=%d want=%lu got=%lu", pair, want, v);
	}
	rlock(c, fd, 0, F_WRLCK);
	d = rdnum(c, fd, 0, 8) + 1;
	wrnum(c, fd, 0, 8, d);
	rlock(c, fd, 0, F_UNLCK);
	close(fd);
	if (d == (unsigned long)c->nprocs)
		unlink(g_path);
}

/* timer: the measured interval is at least the requested one minus 1 ms.
 * A negative interval is a clock step (the library counts those), not an
 * early firing. -x checks against 1000 ms more than was requested. */
static volatile int g_alrm;
static struct timeval g_t1;

static void
on_alrm(int s)
{
	gettimeofday(&g_t1, NULL);
	g_alrm = 1;
}

static void
t_timer(struct st_ctx *c)
{
	struct sigaction sa;
	struct itimerval it;
	struct timeval t0, tv;
	long ms, us, want;
	int i, itimer;

	setup(c);
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_alrm;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGALRM, &sa, NULL);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		itimer = (int)(st_rand(&c->rng) & 1);
		ms = itimer ? (long)st_range(&c->rng, 10, 200) : (long)st_range(&c->rng, 10, 500);
		g_alrm = 0;
		gettimeofday(&t0, NULL);
		if (itimer) {
			memset(&it, 0, sizeof it);
			it.it_value.tv_sec = ms / 1000;
			it.it_value.tv_usec = (ms % 1000) * 1000;
			if (setitimer(ITIMER_REAL, &it, NULL) < 0)
				st_fail_errno(c, "setitimer");
			tv.tv_sec = ms / 1000 + 5;
			tv.tv_usec = 0;
			if (!g_alrm)
				select(0, NULL, NULL, NULL, &tv);
			if (!g_alrm)
				st_fail(c, "reason=no-signal want=%ld", ms);
		} else {
			tv.tv_sec = ms / 1000;
			tv.tv_usec = (ms % 1000) * 1000;
			select(0, NULL, NULL, NULL, &tv);
			gettimeofday(&g_t1, NULL);
		}
		us = (g_t1.tv_sec - t0.tv_sec) * 1000000L + (g_t1.tv_usec - t0.tv_usec);
		want = c->selfcheck ? ms + 1000 : ms;
		if (us >= 0 && us < (want - 1) * 1000)
			st_fail(c, "what=early want=%ld got=%ld kind=%s", want, us / 1000,
				itimer ? "itimer" : "select");
		st_op_end(c, 1);
	}
}

/* eintr: SIGALRM (20 ms one-shot) against read, select, waitpid and flock,
 * with sa_flags 0 and then SA_RESTART. With SA_RESTART read, waitpid and
 * flock must not return EINTR; BSD select does either way. A timer that
 * fired before the call started (a tick before the call, or an early timer)
 * gives a round that proves nothing: it is retried, then skipped. Over the
 * whole test each worker must see read, waitpid and flock return EINTR at
 * least once without SA_RESTART. */
#define STREAM	64		/* read: 4 bursts of 16 bytes, 50 ms apart */
#define BURST	16
#define TRIES	5

static volatile int g_tick;
static long g_nintr[4];		/* EINTR returns without SA_RESTART, per call */

static void
on_tick(int s)
{
	g_tick++;
}

static void
disarm(void)
{
	struct itimerval it;

	memset(&it, 0, sizeof it);
	setitimer(ITIMER_REAL, &it, NULL);
}

/* Arms the 20 ms timer; returns the tick count to compare before the call. */
static int
arm(struct st_ctx *c, int restart)
{
	struct sigaction sa;
	struct itimerval it;
	int seen = g_tick;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_tick;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = restart ? SA_RESTART : 0;
	if (sigaction(SIGALRM, &sa, NULL) < 0)
		st_fail_errno(c, "sigaction");
	memset(&it, 0, sizeof it);
	it.it_value.tv_usec = 20000;
	if (setitimer(ITIMER_REAL, &it, NULL) < 0)
		st_fail_errno(c, "setitimer");
	return seen;
}

static void
reap(void)
{
	int st;

	if (g_kid > 0) {
		kill(g_kid, SIGKILL);
		while (waitpid(g_kid, &st, 0) < 0 && errno == EINTR)
			;
		g_kid = 0;
	}
}

static int
kid(struct st_ctx *c)
{
	pid_t pid = fork();

	if (pid < 0)
		st_fail_errno(c, "fork");
	return (int)pid;
}

/* Child writes the stream (minus one byte if drop); worker reads to EOF. */
static int
round_read(struct st_ctx *c, int restart, int drop)
{
	unsigned char stream[STREAM], buf[STREAM + BURST];
	int fds[2], seen, n, tot = 0, i;
	long r, bad;

	if (pipe(fds) < 0)
		st_fail_errno(c, "pipe");
	st_fill(stream, STREAM, 0x65696e74UL, 0);
	g_kid = kid(c);
	if (g_kid == 0) {
		close(fds[0]);
		n = STREAM;
		if (drop) {
			memmove(stream + 3, stream + 4, STREAM - 4);
			n--;
		}
		for (i = 0; i < n; i += BURST) {
			nap(50000);
			if (write(fds[1], stream + i, n - i < BURST ? n - i : BURST) < 0)
				_exit(1);
		}
		_exit(0);
	}
	close(fds[1]);
	seen = arm(c, restart);
	if (g_tick != seen) {
		disarm();
		close(fds[0]);
		reap();
		return 0;
	}
	for (;;) {
		r = read(fds[0], buf + tot, sizeof buf - tot);
		if (r < 0 && errno == EINTR && !restart) {
			g_nintr[0]++;
			continue;
		}
		if (r < 0)
			st_fail_errno(c, restart ? "read-restart" : "read");
		if (r == 0)
			break;
		tot += r;
		if (tot > STREAM)
			break;
	}
	disarm();
	close(fds[0]);
	reap();
	if (tot != STREAM)
		st_fail(c, "what=stream want=%d got=%d restart=%d", STREAM, tot, restart);
	bad = st_check(buf, STREAM, 0x65696e74UL, 0);
	if (bad >= 0)
		st_fail_data(c, "stream", buf, STREAM, 0x65696e74UL, 0, bad);
	return 1;
}

/* Child waits 50 ms then writes; select on the pipe, EINTR is fine. */
static int
round_select(struct st_ctx *c, int restart)
{
	fd_set rd;
	int fds[2], seen, r;

	if (pipe(fds) < 0)
		st_fail_errno(c, "pipe");
	g_kid = kid(c);
	if (g_kid == 0) {
		close(fds[0]);
		nap(50000);
		write(fds[1], "x", 1);
		_exit(0);
	}
	close(fds[1]);
	FD_ZERO(&rd);
	FD_SET(fds[0], &rd);
	seen = arm(c, restart);
	if (g_tick != seen) {
		disarm();
		close(fds[0]);
		reap();
		return 0;
	}
	r = select(fds[0] + 1, &rd, NULL, NULL, NULL);
	disarm();
	if (r < 0 && errno != EINTR)
		st_fail_errno(c, "select");
	close(fds[0]);
	reap();
	return 1;
}

static int
round_wait(struct st_ctx *c, int restart)
{
	int seen, st;
	pid_t r;

	g_kid = kid(c);
	if (g_kid == 0) {
		nap(100000);
		_exit(0);
	}
	seen = arm(c, restart);
	if (g_tick != seen) {
		disarm();
		reap();
		return 0;
	}
	for (;;) {
		r = waitpid(g_kid, &st, 0);
		if (r < 0 && errno == EINTR && !restart) {
			g_nintr[2]++;
			continue;
		}
		break;
	}
	disarm();
	if (r < 0)
		st_fail_errno(c, restart ? "waitpid-restart" : "waitpid");
	if (r != g_kid || !WIFEXITED(st) || WEXITSTATUS(st) != 0)
		st_fail(c, "what=waitpid pid=%ld want=%ld status=%d", (long)r, (long)g_kid, st);
	g_kid = 0;
	return 1;
}

/* Child locks the file and tells us, holds it 100 ms, exits. */
static int
round_flock(struct st_ctx *c, int restart)
{
	char b;
	int fds[2], fd, seen, r;

	if (pipe(fds) < 0)
		st_fail_errno(c, "pipe");
	g_kid = kid(c);
	if (g_kid == 0) {
		close(fds[0]);
		fd = open(g_path, O_RDWR);
		if (fd < 0 || flock(fd, LOCK_EX) < 0 || write(fds[1], "x", 1) != 1)
			_exit(1);
		nap(100000);
		_exit(0);
	}
	close(fds[1]);
	if (st_readfull(fds[0], &b, 1) != 1)
		st_fail(c, "reason=flock-child-failed");
	close(fds[0]);
	fd = open(g_path, O_RDWR);
	if (fd < 0)
		st_fail_errno(c, "open");
	seen = arm(c, restart);
	if (g_tick != seen) {
		disarm();
		close(fd);
		reap();
		return 0;
	}
	for (;;) {
		r = flock(fd, LOCK_EX);
		if (r < 0 && errno == EINTR && !restart) {
			g_nintr[3]++;
			continue;
		}
		break;
	}
	disarm();
	if (r < 0)
		st_fail_errno(c, restart ? "flock-restart" : "flock");
	close(fd);
	reap();
	return 1;
}

static void
t_eintr(struct st_ctx *c)
{
	static const char *name[4] = { "read", "select", "waitpid", "flock" };
	int fd, i, call, restart, t, ok;
	long skipped = 0;

	setup(c);
	st_path(c, g_path, sizeof g_path, "eintr");
	fd = open(g_path, O_RDWR | O_CREAT | O_TRUNC, 0600);
	if (fd < 0)
		st_fail_errno(c, "open");
	close(fd);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		for (call = 0; call < 4; call++)
			for (restart = 0; restart < 2; restart++) {
				for (t = 0, ok = 0; t < TRIES && !ok; t++)
					switch (call) {
					case 0:
						ok = round_read(c, restart, c->selfcheck && c->idx == 0 && i == 0 && !restart && t == 0);
						break;
					case 1:
						ok = round_select(c, restart);
						break;
					case 2:
						ok = round_wait(c, restart);
						break;
					default:
						ok = round_flock(c, restart);
					}
				if (!ok)
					skipped++;
			}
		st_op_end(c, 1);
	}
	unlink(g_path);
	for (call = 0; call < 4; call++)
		if (call != 1 && g_nintr[call] == 0)	/* select may restart */
			st_fail(c, "reason=no-eintr call=%s skipped=%ld", name[call], skipped);
}

/* rlimit: each limit is set in a forked child, which reports a failure as
 * "key=value ..." through a pipe. */
static volatile int g_xfsz;

static void
on_xfsz(int s)
{
	g_xfsz = 1;
}

static int
rlfail(char *msg, const char *what, const char *call)
{
	sprintf(msg, "what=%s reason=\"%s: %s\"", what, call, st_errname(errno));
	return 1;
}

static int
child_nofile(char *msg)
{
	struct rlimit rl;
	int fd, n = 0, maxfd = -1;

	rl.rlim_cur = rl.rlim_max = 16;
	if (setrlimit(RLIMIT_NOFILE, &rl) < 0)
		return rlfail(msg, "nofile", "setrlimit");
	while ((fd = open("/dev/null", O_RDONLY)) >= 0) {
		if (fd > maxfd)
			maxfd = fd;
		if (++n > 100) {
			sprintf(msg, "what=nofile reason=no-limit opened=%d", n);
			return 1;
		}
	}
	if (errno != EMFILE)
		return rlfail(msg, "nofile", "open");
	if (maxfd >= 16) {
		sprintf(msg, "what=nofile reason=over-limit maxfd=%d", maxfd);
		return 1;
	}
	return 0;
}

static int
child_fsize(char *msg)
{
	static char buf[4096];
	struct rlimit rl;
	struct stat sb;
	unsigned long total = 0;
	long r = 0;
	int fd, i, e = 0;

	signal(SIGXFSZ, on_xfsz);
	rl.rlim_cur = rl.rlim_max = 65536;
	if (setrlimit(RLIMIT_FSIZE, &rl) < 0)
		return rlfail(msg, "fsize", "setrlimit");
	fd = open(g_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (fd < 0)
		return rlfail(msg, "fsize", "open");
	for (i = 0; i < 64; i++) {
		r = write(fd, buf, sizeof buf);
		if (r <= 0) {
			e = errno;
			break;
		}
		total += r;
	}
	if (!g_xfsz && !(r < 0 && e == EFBIG)) {
		sprintf(msg, "what=fsize reason=no-limit written=%lu", total);
		return 1;
	}
	if (fstat(fd, &sb) < 0 || sb.st_size > 65536) {
		sprintf(msg, "what=fsize reason=too-big size=%ld", (long)sb.st_size);
		return 1;
	}
	return 0;
}

/* RLIMIT_DATA is not tested: this kernel accepts it but never enforces it
 * (Mach malloc uses vm_allocate); t_rlimit says so under -v. */

/* A grandchild crashes with the core limit 0; this kernel writes cores to
 * /cores/core.<pid>, and none may appear. */
static int
child_core(char *msg)
{
	struct rlimit rl;
	char core[64];
	pid_t g;
	int st;

	rl.rlim_cur = rl.rlim_max = 0;
	if (setrlimit(RLIMIT_CORE, &rl) < 0)
		return rlfail(msg, "core", "setrlimit");
	g = fork();
	if (g < 0)
		return rlfail(msg, "core", "fork");
	if (g == 0) {
		kill(getpid(), SIGSEGV);
		_exit(0);
	}
	while (waitpid(g, &st, 0) < 0)
		if (errno != EINTR)
			return rlfail(msg, "core", "waitpid");
	if (!WIFSIGNALED(st)) {
		sprintf(msg, "what=core reason=no-crash status=0x%x", st);
		return 1;
	}
	sprintf(core, "/cores/core.%d", (int)g);
	if (WCOREDUMP(st) || access(core, F_OK) == 0) {
		unlink(core);
		sprintf(msg, "what=core reason=core-written status=0x%x", st);
		return 1;
	}
	return 0;
}

/* Runs fn in a child and fails the test with its message. */
static void
runchild(struct st_ctx *c, const char *name, int (*fn)(char *))
{
	char msg[200];
	fd_set rd;
	struct timeval tv;
	time_t t0;
	pid_t r;
	int p[2], st, n;

	if (pipe(p) < 0)
		st_fail_errno(c, "pipe");
	g_kid = fork();
	if (g_kid < 0)
		st_fail_errno(c, "fork");
	if (g_kid == 0) {
		close(p[0]);
		msg[0] = '\0';
		if (fn(msg)) {
			write(p[1], msg, strlen(msg));
			_exit(1);
		}
		_exit(0);
	}
	close(p[1]);
	for (t0 = time(NULL); (r = waitpid(g_kid, &st, WNOHANG)) == 0 ||
	    (r < 0 && errno == EINTR); nap(5000))
		if (time(NULL) - t0 > 30)
			st_fail(c, "what=%s reason=child-hang", name);
	if (r < 0)
		st_fail_errno(c, "waitpid");
	g_kid = 0;
	msg[0] = '\0';
	FD_ZERO(&rd);
	FD_SET(p[0], &rd);
	tv.tv_sec = tv.tv_usec = 0;
	n = 0;
	if (select(p[0] + 1, &rd, NULL, NULL, &tv) > 0)
		n = read(p[0], msg, sizeof msg - 1);
	close(p[0]);
	msg[n > 0 ? n : 0] = '\0';
	if (WIFSIGNALED(st))
		st_fail(c, "what=%s signal=%d", name, WTERMSIG(st));
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
		st_fail(c, "%s", msg[0] ? msg : "reason=child-failed");
}

static void
t_rlimit(struct st_ctx *c)
{
	int i;

	setup(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		runchild(c, "nofile", child_nofile);
		st_path(c, g_path, sizeof g_path, "fsize");
		runchild(c, "fsize", child_fsize);
		unlink(g_path);
		g_path[0] = '\0';
		if (st_opt.verbose && i == 0)
			fprintf(stderr, "RLIMIT_DATA not enforced (Mach malloc uses vm_allocate)\n");
		runchild(c, "core", child_core);
		st_op_end(c, 3);
	}
}

/* fifo: a writer child sends FIFOLEN patterned bytes in random sizes. The
 * alarm kills the worker if the pair stalls. */
static void
fifo_writer(struct st_ctx *c, unsigned long key)
{
	unsigned char buf[8192];
	struct st_rng r;
	unsigned long off = 0, len;
	int fd;

	st_rng_init(&r, key, "fifo", 0);
	fd = open(g_path, O_WRONLY);
	if (fd < 0)
		_exit(2);
	while (off < FIFOLEN) {
		len = st_range(&r, 1, sizeof buf);
		if (len > FIFOLEN - off)
			len = FIFOLEN - off;
		st_fill(buf, len, key, off);
		if (c->selfcheck && off <= 100000 && 100000 < off + len)
			buf[100000 - off] ^= 0xff;
		if (st_writefull(fd, buf, len) != (long)len)
			_exit(3);
		off += len;
	}
	_exit(0);
}

static void
t_fifo(struct st_ctx *c)
{
	unsigned char buf[8192];
	unsigned long key, total;
	long r, bad;
	int i, fd, st;

	setup(c);
	st_path(c, g_path, sizeof g_path, "fifo");
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		unlink(g_path);
		if (mkfifo(g_path, 0600) < 0)
			st_fail_errno(c, "mkfifo");
		key = st_rand(&c->rng);
		g_kid = fork();
		if (g_kid < 0)
			st_fail_errno(c, "fork");
		if (g_kid == 0)
			fifo_writer(c, key);
		alarm(FIFOSECS);
		fd = open(g_path, O_RDONLY);
		if (fd < 0)
			st_fail_errno(c, "open");
		unlink(g_path);		/* both ends are open, so nothing is left if the leader kills us */
		total = 0;
		while ((r = read(fd, buf, sizeof buf)) != 0) {
			if (r < 0) {
				if (errno == EINTR)
					continue;
				st_fail_errno(c, "read");
			}
			if (total + r > FIFOLEN)
				st_fail(c, "reason=extra off=0x%lx", total);
			bad = st_check(buf, r, key, total);
			if (bad >= 0)
				st_fail_data(c, "fifo", buf, r, key, total, bad);
			total += r;
		}
		close(fd);
		if (total != FIFOLEN)
			st_fail(c, "reason=short got=%lu want=%d", total, FIFOLEN);
		while (waitpid(g_kid, &st, 0) < 0)
			if (errno != EINTR)
				st_fail_errno(c, "waitpid");
		g_kid = 0;
		alarm(0);
		if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
			st_fail(c, "reason=writer-status status=0x%x", st);
		st_op_end(c, FIFOLEN);
	}
}

/* fds: open /dev/null until EMFILE, close them all. */
static int
countfds(void)
{
	int fd, n = 0, max = getdtablesize();

	for (fd = 0; fd < max; fd++)
		if (fcntl(fd, F_GETFD) >= 0)
			n++;
	return n;
}

static void
t_fds(struct st_ctx *c)
{
	int *fds;
	int i, k, n, max, before, after;

	setup(c);
	max = getdtablesize();
	fds = malloc((max + 16) * sizeof *fds);
	if (fds == NULL)
		st_fail(c, "reason=\"malloc: ENOMEM\"");
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		before = countfds();
		for (n = 0; n < max + 16; n++) {
			fds[n] = open("/dev/null", O_RDONLY);
			if (fds[n] < 0)
				break;
		}
		if (n == max + 16)
			st_fail(c, "reason=no-limit opened=%d max=%d", n, max);
		if (errno != EMFILE)
			st_fail_errno(c, "open");
		for (k = 0; k < n; k++)
			close(fds[k]);
		after = countfds();
		if (after != before)
			st_fail(c, "reason=fdleak before=%d after=%d", before, after);
		st_op_end(c, n);
	}
	free(fds);
}

/* pgrp: child C does setsid and forks G, which stops itself. When C exits G
 * is in an orphaned group with a stopped member and must get SIGHUP and
 * SIGCONT; its handlers report H and C through a pipe. Both are pending when
 * G resumes, so the handler order is unspecified: HC or CH. */
static int g_pw;

static void
on_hup(int s)
{
	write(g_pw, "H", 1);
}

static void
on_cont(int s)
{
	write(g_pw, "C", 1);
}

static void
pg_child(int pw)
{
	char line[16];
	pid_t g;
	int st;

	g_pw = pw;
	setsid();
	g = fork();
	if (g < 0)
		_exit(2);
	if (g == 0) {
		/* own group in C's session, so its parent C is what keeps the group from being orphaned */
		setpgid(0, 0);
		signal(SIGHUP, on_hup);
		signal(SIGCONT, on_cont);
		kill(getpid(), SIGSTOP);
		nap(1000000);
		_exit(0);
	}
	while (waitpid(g, &st, WUNTRACED) < 0)
		if (errno != EINTR)
			_exit(3);
	if (!WIFSTOPPED(st))
		_exit(4);
	sprintf(line, "%d\n", (int)g);	/* G's group, for the parent to kill */
	write(pw, line, strlen(line));
	_exit(0);
}

static void
t_pgrp(struct st_ctx *c)
{
	char got[32], *nl;
	fd_set rd;
	struct timeval tv;
	time_t t0;
	pid_t r;
	int i, p[2], st, n;

	setup(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		if (pipe(p) < 0)
			st_fail_errno(c, "pipe");
		g_kid = fork();
		if (g_kid < 0)
			st_fail_errno(c, "fork");
		if (g_kid == 0) {
			close(p[0]);
			pg_child(p[1]);
		}
		close(p[1]);
		for (t0 = time(NULL); (r = waitpid(g_kid, &st, WNOHANG)) == 0 ||
		    (r < 0 && errno == EINTR); nap(5000))
			if (time(NULL) - t0 > WAIT)
				st_fail(c, "reason=timeout what=stop");
		if (r < 0)
			st_fail_errno(c, "waitpid");
		g_kid = 0;
		if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
			st_fail(c, "reason=child-status status=0x%x", st);
		/* "<pgid>\n" from C, then one letter per signal G caught */
		n = 0;
		got[0] = '\0';
		for (t0 = time(NULL); time(NULL) - t0 <= WAIT; ) {
			nl = strchr(got, '\n');
			if (nl != NULL && strlen(nl + 1) >= 2)
				break;
			FD_ZERO(&rd);
			FD_SET(p[0], &rd);
			tv.tv_sec = 0;
			tv.tv_usec = 100000;
			if (select(p[0] + 1, &rd, NULL, NULL, &tv) > 0) {
				r = read(p[0], got + n, sizeof got - 1 - n);
				if (r <= 0)
					break;
				n += r;
				got[n] = '\0';
			}
		}
		nl = strchr(got, '\n');
		if (nl != NULL)
			g_pg = atoi(got);
		if (g_pg > 1)
			killpg(g_pg, SIGKILL);
		g_pg = 0;
		close(p[0]);
		if (nl == NULL || (strcmp(nl + 1, "HC") != 0 && strcmp(nl + 1, "CH") != 0))
			st_fail(c, "what=pgrp reason=signals got=%s want=HC|CH",
				nl != NULL && nl[1] ? nl + 1 : "none");
		st_op_end(c, 1);
	}
}

static int
probe_file(char *why, int len, const char *call, int kind)
{
	char path[PATHLEN];
	struct flock fl;
	int fd, r = 0;

	sprintf(path, "%s/stress.misc.probe.%d", st_opt.dir, (int)getpid());
	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
	if (fd < 0)
		return 0;		/* a bad -d is the body's FAIL */
	if (kind == 0)
		r = flock(fd, LOCK_EX);
	else {
		memset(&fl, 0, sizeof fl);
		fl.l_type = F_WRLCK;
		fl.l_len = 8;
		r = fcntl(fd, F_SETLK, &fl);
	}
	close(fd);
	unlink(path);
	if (r < 0 && (errno == ENOSYS || errno == EOPNOTSUPP)) {
		sprintf(why, "%s: %s", call, st_errname(errno));
		return 1;
	}
	return 0;
}

static int
probe_flock(char *why, int len)
{
	return probe_file(why, len, "flock", 0);
}

static int
probe_fcntl(char *why, int len)
{
	return probe_file(why, len, "fcntl", 1);
}

static int
probe_fifo(char *why, int len)
{
	char path[PATHLEN];

	sprintf(path, "%s/stress.misc.probe.%d", st_opt.dir, (int)getpid());
	if (mkfifo(path, 0600) < 0 && (errno == ENOSYS || errno == EOPNOTSUPP)) {
		sprintf(why, "mkfifo: %s", st_errname(errno));
		return 1;
	}
	unlink(path);
	return 0;
}

static const struct st_test tests[] = {
	{ "flock", 2000, 0, probe_flock, t_flock },
	{ "fcntl", 2000, 0, probe_fcntl, t_fcntl },
	{ "timer", 50, 0, NULL, t_timer },
	{ "eintr", 20, 0, NULL, t_eintr },
	{ "rlimit", 1, 1, NULL, t_rlimit },
	{ "fifo", 50, 0, probe_fifo, t_fifo },
	{ "fds", 50, 0, NULL, t_fds },
	{ "pgrp", 20, 1, NULL, t_pgrp },
	{ NULL, 0, 0, NULL, NULL }
};

int
main(int argc, char **argv)
{
	return stress_main(argc, argv, "misc", tests);
}
