/* stress-proc: process and signal tests. fork/exit/wait status, exec of a
 * helper, signals delivered while the interrupted code is inside dyld (the
 * 1998 dyld dies with "dead lock", exit 68), a deep stack, a pipe chain, and a
 * pty open/echo/close cycle. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include "stress.h"

#define MB	(1024UL * 1024)
#define FRAME	576UL			/* stack: a frame's 512-byte array plus overhead */
#define SIGLOOP	20000			/* signal: dyld calls per loop */
#define PIPEBUF	65536

static const char *argv0 = "";

static unsigned long
key3(unsigned long a, unsigned long b)
{
	return st_mix(st_mix(st_opt.seed ^ a) + b * 0x9e3779b1UL) & ST_MASK;
}

static pid_t
waitfor(pid_t pid, int *status)
{
	pid_t r;

	while ((r = waitpid(pid, status, 0)) < 0 && errno == EINTR)
		;
	return r;
}

static void
killkids(pid_t *k, int n)
{
	int i, st;

	for (i = 0; i < n; i++)
		kill(k[i], SIGKILL);
	for (i = 0; i < n; i++)
		waitfor(k[i], &st);
}

/* fork: the child exits with a chosen status, which waitpid must report. */
static void
t_fork(struct st_ctx *c)
{
	unsigned long want;
	long i, bad;
	pid_t pid;
	int status;

	bad = st_range(&c->rng, 0, c->iters - 1);
	for (i = 0; st_more(c, i); i++) {
		want = st_range(&c->rng, 0, 250);
		st_op_begin(c);
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0)
			_exit(c->selfcheck && i == bad ? want + 1 : want);
		if (waitfor(pid, &status) != pid)
			st_fail_errno(c, "waitpid");
		if (!WIFEXITED(status) || WEXITSTATUS(status) != want)
			st_fail(c, "what=status iter=%ld want=%lu got=0x%x", i, want, status);
		st_op_end(c, 1);
	}
}

/* Next to the running binary, else ./ or the install directory. */
static const char *
childpath(char *buf, int len)
{
	char *s;

	if (strchr(argv0, '/') != NULL && strlen(argv0) + 20 < len) {
		strcpy(buf, argv0);
		s = strrchr(buf, '/');
		strcpy(s + 1, "stress-exec-child");
		return buf;
	}
	if (access("./stress-exec-child", X_OK) == 0)
		return "./stress-exec-child";
	return "/usr/local/stress/proc/stress-exec-child";
}

/* exec: the child prints st_mix(N) and exits N & 0x7f; the parent checks both. */
static void
t_exec(struct st_ctx *c)
{
	char path[300], arg[16], out[64], *end;
	unsigned long n, got;
	long i, bad;
	int pfd[2], status, len, r;
	pid_t pid;

	childpath(path, sizeof path);
	bad = st_range(&c->rng, 0, c->iters - 1);
	for (i = 0; st_more(c, i); i++) {
		n = st_range(&c->rng, 0, 65535);
		if (pipe(pfd) < 0)
			st_fail_errno(c, "pipe");
		st_op_begin(c);
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0) {
			close(pfd[0]);
			dup2(pfd[1], 1);
			close(pfd[1]);
			sprintf(arg, "%lu", n);
			/* a NULL third argument ends the list early */
			execl(path, "stress-exec-child", arg,
			      c->selfcheck && i == bad ? "bad" : (char *)0, (char *)0);
			_exit(127);
		}
		close(pfd[1]);
		len = 0;
		while (len < sizeof out - 1) {
			r = read(pfd[0], out + len, sizeof out - 1 - len);
			if (r < 0 && errno == EINTR)
				continue;
			if (r <= 0)
				break;
			len += r;
		}
		out[len] = '\0';
		close(pfd[0]);
		if (waitfor(pid, &status) != pid)
			st_fail_errno(c, "waitpid");
		if (!WIFEXITED(status) || WEXITSTATUS(status) != (n & 0x7f))
			st_fail(c, "what=exit n=%lu want=%lu got=0x%x", n, n & 0x7f, status);
		got = strtoul(out, &end, 16);
		if (got != (st_mix(n) & ST_MASK))
			st_fail(c, "what=output n=%lu want=%lx got=%lx", n, st_mix(n) & ST_MASK, got);
		st_op_end(c, 1);
	}
}

static volatile unsigned long n_alrm, n_usr1;

/* The point of the test: a handler that enters dyld. */
static void
on_sig(int sig)
{
	NSIsSymbolNameDefined("_printf");
	getpid();
	if (sig == SIGALRM)
		n_alrm++;
	else
		n_usr1++;
}

/* signal: SIGALRM every 2 ms and SIGUSR1 from two children, with handlers
 * and the interrupted main loop both calling into dyld. With the -i loops
 * done (or 5 s, without -i) it also waits for the counts to be reached. */
static void
t_signal(struct st_ctx *c)
{
	struct sigaction sa;
	struct itimerval it;
	pid_t kids[2], parent = getpid();
	unsigned long last = 0, now;
	time_t t0 = time(NULL);
	long i, j;
	int k, ok, limit;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_sig;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGALRM, &sa, NULL);
	sigaction(SIGUSR1, &sa, NULL);
	for (k = 0; k < 2; k++) {
		kids[k] = fork();
		if (kids[k] < 0) {
			int e = errno;

			killkids(kids, k);
			errno = e;
			st_fail_errno(c, "fork");
		}
		if (kids[k] == 0) {
			for (j = 0; j < 2000; j++) {
				if (kill(parent, SIGUSR1) < 0)
					break;
				usleep(1000);
			}
			_exit(0);
		}
	}
	it.it_interval.tv_sec = it.it_value.tv_sec = 0;
	it.it_interval.tv_usec = it.it_value.tv_usec = 2000;
	setitimer(ITIMER_REAL, &it, NULL);
	for (i = 0; ; i++) {
		ok = n_alrm >= 50 && n_usr1 >= 1;
		limit = st_opt.iters > 0 ? !st_more(c, i) : time(NULL) - t0 >= 5;
		if ((ok && limit) || time(NULL) - t0 > 30)
			break;
		st_op_begin(c);
		for (j = 0; j < SIGLOOP; j++)
			NSIsSymbolNameDefined("_strlen");
		now = n_alrm + n_usr1;
		st_op_end(c, now - last);
		last = now;
	}
	it.it_value.tv_usec = it.it_interval.tv_usec = 0;
	setitimer(ITIMER_REAL, &it, NULL);
	killkids(kids, 2);
	if (n_alrm < 50 || n_usr1 < 1)
		st_fail(c, "what=signals alrm=%lu usr1=%lu", n_alrm, n_usr1);
}

static struct st_ctx *sc;
static unsigned long skey;
static int spfd[2];
static long sbad;

/* getpid, stat and write from the deepest frame. */
static void
bottom(const unsigned char *a)
{
	struct stat sb;

	if (getpid() <= 0)
		st_fail(sc, "what=getpid");
	if (stat("/", &sb) < 0 || !S_ISDIR(sb.st_mode))
		st_fail(sc, "what=stat");
	if (write(spfd[1], a, 512) != 512)
		st_fail_errno(sc, "write");
}

static void
rec(long depth, long max)
{
	unsigned char a[512];
	long bad;

	st_fill(a, sizeof a, skey, depth * 512UL);
	if (depth == sbad)
		a[st_range(&sc->rng, 0, 511)] ^= 1;
	if (depth + 1 < max)
		rec(depth + 1, max);
	else
		bottom(a);
	bad = st_check(a, sizeof a, skey, depth * 512UL);
	if (bad >= 0)
		st_fail_data(sc, "frame", a, sizeof a, skey, depth * 512UL, bad);
}

/* stack: 2 MB of patterned frames (at most half the stack limit), checked on unwind. */
static void
t_stack(struct st_ctx *c)
{
	struct rlimit rl;
	unsigned char back[512];
	unsigned long lim = 4 * MB, depth = 2 * MB / FRAME;
	long i, bad;
	int n;

	if (getrlimit(RLIMIT_STACK, &rl) == 0 && rl.rlim_cur != RLIM_INFINITY)
		lim = (unsigned long)rl.rlim_cur;
	if (lim / 2 / FRAME < depth)
		depth = lim / 2 / FRAME;
	if (depth < 1)
		depth = 1;
	if (st_opt.verbose)
		fprintf(stderr, "stress-proc stack: limit=%lu depth=%lu%s\n", lim, depth,
			lim < 65536 ? " (limit below 64 KB)" : "");
	sc = c;
	if (pipe(spfd) < 0)
		st_fail_errno(c, "pipe");
	for (i = 0; st_more(c, i); i++) {
		skey = key3(c->idx, i);
		sbad = c->selfcheck ? (long)st_range(&c->rng, 0, depth - 1) : -1;
		st_op_begin(c);
		rec(0, depth);
		for (n = 0; n < 512; ) {
			int r = read(spfd[0], back + n, 512 - n);

			if (r < 0 && errno == EINTR)
				continue;
			if (r <= 0)
				st_fail(c, "what=pipe-read");
			n += r;
		}
		bad = st_check(back, sizeof back, skey, (depth - 1) * 512UL);
		if (bad >= 0)
			st_fail_data(c, "frame-pipe", back, sizeof back, skey, (depth - 1) * 512UL, bad);
		st_op_end(c, depth);
	}
}

static int
writeall(int fd, const unsigned char *b, long n)
{
	long w;

	while (n > 0) {
		w = write(fd, b, n);
		if (w < 0 && errno == EINTR)
			continue;
		if (w < 0)
			return -1;
		b += w;
		n -= w;
	}
	return 0;
}

static unsigned char pbuf[PIPEBUF];

/* One stage of the chain; in is -1 for the head. Never returns. */
static void
stage(int k, int p[3][2], unsigned long key, long i, long bad)
{
	struct st_rng r;
	unsigned long off, n;
	int in = k == 0 ? -1 : p[k - 1][0], out = p[k][1], a, e, got;

	for (a = 0; a < 3; a++)
		for (e = 0; e < 2; e++)
			if (p[a][e] != in && p[a][e] != out)
				close(p[a][e]);
	if (k == 0) {
		st_rng_init(&r, key, "pipe", (int)i);
		for (off = 0; off < MB; off += n) {
			n = st_range(&r, 1, PIPEBUF);
			if (n > MB - off)
				n = MB - off;
			st_fill(pbuf, n, key, off);
			if (bad >= (long)off && bad < (long)(off + n))
				pbuf[bad - off] ^= 1;
			if (writeall(out, pbuf, n) < 0)
				_exit(1);
		}
		_exit(0);
	}
	for (;;) {
		got = read(in, pbuf, PIPEBUF);
		if (got < 0 && errno == EINTR)
			continue;
		if (got < 0)
			_exit(1);
		if (got == 0)
			_exit(0);
		if (writeall(out, pbuf, got) < 0)
			_exit(1);
	}
}

/* pipe: head -> mid -> mid -> this process, 1 MB per iteration, random write sizes. */
static void
t_pipe(struct st_ctx *c)
{
	int p[3][2], k, e, status, got;
	pid_t kids[3];
	unsigned long key, off;
	long i, bad, w;

	for (i = 0; st_more(c, i); i++) {
		key = key3(c->idx, i);
		bad = c->selfcheck ? (long)st_range(&c->rng, 0, MB - 1) : -1;
		st_op_begin(c);
		for (k = 0; k < 3; k++)
			if (pipe(p[k]) < 0)
				st_fail_errno(c, "pipe");
		for (k = 0; k < 3; k++) {
			kids[k] = fork();
			if (kids[k] < 0) {
				e = errno;
				killkids(kids, k);
				errno = e;
				st_fail_errno(c, "fork");
			}
			if (kids[k] == 0)
				stage(k, p, key, i, bad);
		}
		for (k = 0; k < 2; k++) {
			close(p[k][0]);
			close(p[k][1]);
		}
		close(p[2][1]);
		off = 0;
		for (;;) {
			got = read(p[2][0], pbuf, PIPEBUF);
			if (got < 0 && errno == EINTR)
				continue;
			if (got < 0) {
				e = errno;
				killkids(kids, 3);
				errno = e;
				st_fail_errno(c, "read");
			}
			if (got == 0)
				break;
			if (off + got > MB) {
				killkids(kids, 3);
				st_fail(c, "what=overrun off=0x%lx", off);
			}
			w = st_check(pbuf, got, key, off);
			if (w >= 0) {
				killkids(kids, 3);
				st_fail_data(c, "pipe", pbuf, got, key, off, w);
			}
			off += got;
		}
		close(p[2][0]);
		if (off != MB) {
			killkids(kids, 3);
			st_fail(c, "what=short got=0x%lx", off);
		}
		for (k = 0; k < 3; k++)
			if (waitfor(kids[k], &status) != kids[k] || status != 0)
				st_fail(c, "what=stage k=%d status=0x%x", k, status);
		st_op_end(c, MB);
	}
}

#define MAXPTY	64
#define PTYCHUNK 128			/* pty: bytes in flight; the tty queues are small */

/* Opens the first free master /dev/ptyXY; the slave name is the same with t.
 * EBUSY, EIO and the like mean taken (by sshd or a concurrent run). */
static int
ptyopen(char *master, char *slave)
{
	static const char xs[] = "pqrs", ys[] = "0123456789abcdef";
	int x, y, fd;

	for (x = 0; x < 4; x++)
		for (y = 0; y < 16; y++) {
			sprintf(master, "/dev/pty%c%c", xs[x], ys[y]);
			fd = open(master, O_RDWR | O_NOCTTY);
			if (fd >= 0) {
				sprintf(slave, "/dev/tty%c%c", xs[x], ys[y]);
				return fd;
			}
		}
	return -1;
}

static int
pty_probe(char *why, int len)
{
	char m[32], s[32];
	int fd = ptyopen(m, s);

	if (fd < 0) {
		strcpy(why, "no free pty");
		return 1;
	}
	close(fd);
	return 0;
}

/* pty: open a master/slave pair, push a patterned block through a child that
 * echoes the raw slave, check it, close the pair in a random order, reap. */
static void
t_pty(struct st_ctx *c)
{
	char names[MAXPTY][32], m[32], s[32];
	unsigned char buf[4096];
	struct termios t;
	unsigned long key, n, o, k;
	long i, bad;
	int mfd, sfd, nused = 0, u, status;
	time_t t0;
	pid_t pid;

	for (i = 0; st_more(c, i); i++) {
		t0 = time(NULL);
		while ((mfd = ptyopen(m, s)) < 0) {
			if (time(NULL) - t0 >= 5) {
				if (nused > 0)
					st_fail(c, "what=pty-exhausted used=%d", nused);
				st_fail(c, "reason=\"no free pty\"");
			}
			usleep(100000);
		}
		for (u = 0; u < nused && strcmp(names[u], m) != 0; u++)
			;
		if (u == nused && nused < MAXPTY)
			strcpy(names[nused++], m);
		sfd = open(s, O_RDWR | O_NOCTTY);
		if (sfd < 0)
			st_fail_errno(c, "open slave");
		if (tcgetattr(sfd, &t) < 0)
			st_fail_errno(c, "tcgetattr");
		t.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
		t.c_oflag &= ~OPOST;
		t.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
		t.c_cflag &= ~(CSIZE | PARENB);
		t.c_cflag |= CS8;
		t.c_cc[VMIN] = 1;
		t.c_cc[VTIME] = 0;
		if (tcsetattr(sfd, TCSANOW, &t) < 0)
			st_fail_errno(c, "tcsetattr");
		st_op_begin(c);
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0) {
			close(mfd);
			setsid();
			ioctl(sfd, TIOCSCTTY, 0);
			while ((n = read(sfd, buf, sizeof buf)) > 0)
				if (st_writefull(sfd, buf, n) < 0)
					break;
			_exit(0);
		}
		key = key3(c->idx, i);
		n = st_range(&c->rng, 1024, 4096);
		bad = c->selfcheck ? (long)st_range(&c->rng, 0, n - 1) : -1;
		st_fill(buf, n, key, 0);
		for (o = 0; o < n; o += k) {
			k = n - o < PTYCHUNK ? n - o : PTYCHUNK;
			if (st_writefull(mfd, buf + o, k) != k)
				st_fail_errno(c, "write");
			if (st_readfull(mfd, buf + o, k) != k)
				st_fail_errno(c, "read");
		}
		if (bad >= 0)
			buf[bad] ^= 1;
		bad = st_check(buf, n, key, 0);
		if (bad >= 0)
			st_fail_data(c, "pty", buf, n, key, 0, bad);
		/* The child's exit hangs up its controlling tty; reap it before the
		 * pair is released, or it revokes the slave of whoever reopens it. */
		kill(pid, SIGKILL);
		if (waitfor(pid, &status) != pid)
			st_fail_errno(c, "waitpid");
		if (st_range(&c->rng, 0, 1)) {
			close(mfd);
			close(sfd);
		} else {
			close(sfd);
			close(mfd);
		}
		st_op_end(c, n);
	}
	for (u = 0; u < nused; u++) {
		mfd = open(names[u], O_RDWR | O_NOCTTY);
		if (mfd >= 0)
			close(mfd);
	}
}

static const struct st_test tests[] = {
	{ "fork", 500, 0, NULL, t_fork },
	{ "exec", 200, 0, NULL, t_exec },
	{ "signal", 250, 1, NULL, t_signal },
	{ "stack", 20, 0, NULL, t_stack },
	{ "pipe", 50, 0, NULL, t_pipe },
	{ "pty", 50, 0, pty_probe, t_pty },
	{ NULL, 0, 0, NULL, NULL }
};

int
main(int argc, char **argv)
{
	argv0 = argv[0];
	return stress_main(argc, argv, "proc", tests);
}
