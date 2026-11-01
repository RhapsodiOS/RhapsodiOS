/* stress_main: options, then for each test a leader process (its own
 * process group) that runs the workers and prints the one result line,
 * watched by the top-level process with the -t watchdog. */
#include <sys/types.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <dirent.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "stress.h"

/* Initialized, so it is not a common symbol: ld only pulls archive
 * members for defined ones. */
struct st_opts st_opt = { 4, 0, 600, 0, "/tmp" };

static volatile int alarmed;

/* Leader state: what the workers reported. */
static long start_sec;		/* leader's start time, copied to st_ctx.t_start */
static char unsup[512];		/* a worker's st_unsup fields, if no FAIL */
static char fail[512];		/* the first failure: a FAIL line's fields, a signal or an exit */
static unsigned long units, maxlat_us, clockback;
static struct st_leak leak_before, leak_after;	/* static: ~20 KB each */
static char inbuf[1024];
static int inlen, eof;

static void
on_alarm(int sig)
{
	alarmed = 1;
}

static void
on_chld(int sig)
{
}

static volatile pid_t leader_pid;	/* the running leader, 0 if none */
static sigset_t oldmask;		/* the mask before run() blocked stops */

/* TERM first so a test can undo what it changed (settime), up to 200 ms for
 * the group to go (killpg skips zombies), then KILL whatever is left. */
static void
stop_group(pid_t pg)
{
	int i;

	killpg(pg, SIGTERM);
	for (i = 0; i < 20 && killpg(pg, 0) == 0; i++)
		usleep(10000);
	killpg(pg, SIGKILL);
}

/* SIGINT/SIGTERM/SIGHUP in the top level: the leader is in its own group
 * and would outlive us, so take its group down first. */
static void
on_stop(int sig)
{
	if (leader_pid > 0) {
		stop_group(leader_pid);
		waitpid(leader_pid, NULL, 0);
	}
	_exit(128 + sig);
}

/* No SA_RESTART: the handler interrupts select and waitpid. */
static void
catch(int sig, void (*fn)(int))
{
	struct sigaction sa;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = fn;
	sigemptyset(&sa.sa_mask);
	sigaction(sig, &sa, NULL);
}

static double
since(struct timeval *t0)
{
	struct timeval t;

	gettimeofday(&t, NULL);
	return (t.tv_sec - t0->tv_sec) + (t.tv_usec - t0->tv_usec) / 1e6;
}

void
st_op_begin(struct st_ctx *c)
{
	struct timeval t;

	gettimeofday(&t, NULL);
	c->t0_sec = t.tv_sec;
	c->t0_usec = t.tv_usec;
}

void
st_op_end(struct st_ctx *c, unsigned long n)
{
	struct timeval t;
	long us;

	gettimeofday(&t, NULL);
	us = (t.tv_sec - c->t0_sec) * 1000000L + (t.tv_usec - c->t0_usec);
	if (us < 0) {
		us = 0;		/* the clock stepped back */
		c->clockback++;
	}
	if (us > c->maxlat_us)
		c->maxlat_us = us;
	c->units += n;
}

int
st_more(struct st_ctx *c, long i)
{
	c->iter = i;
	if (st_opt.budget > 0 && time(NULL) - c->t_start >= st_opt.budget)
		return 0;
	return i < c->iters;
}

static void
worker(const struct st_test *t, const char *cat, int idx, int n, int fd)
{
	struct st_ctx c;
	char line[64];

	memset(&c, 0, sizeof c);
	c.cat = cat;
	c.test = t->name;
	c.idx = idx;
	c.nprocs = n;
	c.iters = st_opt.iters > 0 ? st_opt.iters : t->def_iters;
	st_rng_init(&c.rng, st_opt.seed, t->name, idx);
	c.selfcheck = st_opt.selfcheck;
	c.t_start = start_sec;
	c.fd = fd;
	t->body(&c);
	sprintf(line, "STAT %lu %lu %lu\n", c.units, c.maxlat_us, c.clockback);
	write(fd, line, strlen(line));
	_exit(0);
}

static void
take(char *s)
{
	unsigned long u, l, b;

	if (strncmp(s, "STAT ", 5) == 0 && sscanf(s + 5, "%lu %lu %lu", &u, &l, &b) == 3) {
		units += u;
		clockback += b;
		if (l > maxlat_us)
			maxlat_us = l;
	} else if (strncmp(s, "FAIL ", 5) == 0 && fail[0] == '\0') {
		strncpy(fail, s + 5, sizeof fail - 1);
	} else if (strncmp(s, "UNSUP ", 6) == 0 && unsup[0] == '\0') {
		strncpy(unsup, s + 6, sizeof unsup - 1);
	}
}

/* Waits up to secs for pipe input (or a signal) and consumes whole lines.
 * Returns 0 when nothing arrived. */
static int
input(int fd, int secs)
{
	fd_set rd;
	struct timeval tv;
	char *nl;
	int r;

	FD_ZERO(&rd);
	if (!eof)
		FD_SET(fd, &rd);
	tv.tv_sec = secs;
	tv.tv_usec = 0;
	if (select(fd + 1, &rd, NULL, NULL, &tv) <= 0 || eof)
		return 0;
	r = read(fd, inbuf + inlen, sizeof inbuf - 1 - inlen);
	if (r <= 0) {
		eof = 1;
		return 0;
	}
	inlen += r;
	inbuf[inlen] = '\0';
	while ((nl = strchr(inbuf, '\n')) != NULL) {
		*nl = '\0';
		take(inbuf);
		inlen -= nl + 1 - inbuf;
		memmove(inbuf, nl + 1, inlen + 1);
	}
	if (inlen == sizeof inbuf - 1)
		inlen = 0;		/* overlong line: drop it */
	return 1;
}

/* Remove the scratch files ("<dir>/stress.<cat>.<test>.<tag>.<pid>", see
 * st_path) of workers the leader killed, and its own: their cleanup never ran. */
static void
sweep(const char *cat, const char *test, const pid_t *wpids, int n)
{
	char pre[256], path[1024], *dot;
	struct dirent *e;
	DIR *d;
	long id;
	int i, plen;

	if (strlen(cat) + strlen(test) + 9 > sizeof pre)
		return;
	plen = sprintf(pre, "stress.%s.%s.", cat, test);
	if ((d = opendir(st_opt.dir)) == NULL)
		return;
	while ((e = readdir(d)) != NULL) {
		if (strncmp(e->d_name, pre, plen) != 0 || (dot = strrchr(e->d_name, '.')) == NULL)
			continue;
		id = atol(dot + 1);
		for (i = 0; i < n && wpids[i] != id; i++)
			;
		if ((i < n || id == (long)getpid()) &&
		    strlen(st_opt.dir) + strlen(e->d_name) + 2 <= sizeof path) {
			sprintf(path, "%s/%s", st_opt.dir, e->d_name);
			unlink(path);
		}
	}
	closedir(d);
}

/* Runs in its own process group; exits 0 on PASS, 1 on FAIL. */
static void
leader(const struct st_test *t, const char *cat)
{
	int fds[2], n, i, live, status, e, stopped;
	pid_t *pids, *wpids, pid;
	struct timeval t0;
	double secs;
	long iters;
	char what[1024], lk[512], *p;

	setpgid(0, 0);
	catch(SIGALRM, SIG_DFL);
	catch(SIGINT, SIG_DFL);
	catch(SIGTERM, SIG_DFL);
	catch(SIGHUP, SIG_DFL);
	sigprocmask(SIG_SETMASK, &oldmask, NULL);
	catch(SIGCHLD, on_chld);
	n = t->solo ? 1 : st_opt.procs;
	pids = malloc(n * sizeof *pids);
	wpids = malloc(n * sizeof *wpids);	/* pids[] is zeroed as workers are reaped */
	if (pids == NULL || wpids == NULL || pipe(fds) < 0) {
		sprintf(what, "FAIL reason=\"%s: %s\"", pids && wpids ? "pipe" : "malloc", st_errname(errno));
		st_line(cat, t->name, what, 1);
		exit(1);
	}
	gettimeofday(&t0, NULL);
	start_sec = t0.tv_sec;
	for (i = 0; i < n; i++) {
		pid = fork();
		if (pid < 0) {
			e = errno;
			while (--i >= 0)
				kill(pids[i], SIGKILL);
			while (wait(NULL) > 0 || errno == EINTR)
				;
			sprintf(what, "FAIL reason=\"fork: %s\"", st_errname(e));
			st_line(cat, t->name, what, 1);
			exit(1);
		}
		if (pid == 0) {
			close(fds[0]);
			catch(SIGCHLD, SIG_DFL);
			worker(t, cat, i, n, fds[1]);
		}
		pids[i] = wpids[i] = pid;
	}
	close(fds[1]);
	/* Read while reaping: children a test forked may hold the pipe open,
	 * so the workers' exits, not EOF, end the test. The first failure
	 * kills the other workers, which may be waiting on the failed one. */
	live = n;
	stopped = 0;
	while (live > 0) {
		while (live > 0 && (pid = waitpid(-1, &status, WNOHANG)) > 0) {
			for (i = 0; i < n && pids[i] != pid; i++)
				;
			if (i == n)
				continue;
			pids[i] = 0;
			live--;
			if (fail[0] != '\0' || (WIFEXITED(status) && WEXITSTATUS(status) == 0))
				continue;
			/* a FAIL line the worker wrote before it died came first */
			while (input(fds[0], 0))
				;
			if (fail[0] != '\0')
				continue;
			if (WIFSIGNALED(status))
				sprintf(fail, "signal=%d worker=%d", WTERMSIG(status), i);
			else
				sprintf(fail, "exit=%d worker=%d", WEXITSTATUS(status), i);
		}
		if (pid < 0 && fail[0] == '\0' && st_lost(live, errno)) {
			sprintf(fail, "reason=lost-child live=%d", live);
			live = 0;	/* nothing left to reap */
		}
		if (fail[0] != '\0' && !stopped) {
			for (i = 0; i < n; i++)
				if (pids[i] > 0)
					kill(pids[i], SIGKILL);
			stopped = 1;
		}
		if (live > 0)
			input(fds[0], 1);
	}
	secs = since(&t0);
	while (input(fds[0], 0))
		;
	if (stopped)
		sweep(cat, t->name, wpids, n);
	lk[0] = '\0';
	if (!st_opt.noleak) {
		st_leak_snap(&leak_after);
		st_leak_diff(&leak_before, &leak_after, lk, sizeof lk);
	}
	if (fail[0] != '\0') {
		sprintf(what, "FAIL %s%s", fail, lk);
		st_line(cat, t->name, what, 1);
		exit(1);
	}
	if (unsup[0] != '\0') {
		sprintf(what, "UNSUP %s", unsup);
		st_line(cat, t->name, what, 1);
		exit(0);
	}
	if (secs < 1e-6)
		secs = 1e-6;
	if (st_opt.leakfail && lk[0] != '\0') {
		sprintf(what, "FAIL reason=leak%s", lk);
		st_line(cat, t->name, what, 1);
		exit(1);
	}
	iters = st_opt.iters > 0 ? st_opt.iters : t->def_iters;
	p = what + sprintf(what, "PASS iters=%ld procs=%d secs=%.1f ops=%lu/s maxlat=%lums",
		iters, n, secs, (unsigned long)(units / secs), maxlat_us / 1000);
	if (clockback)
		p += sprintf(p, " clockback=%lu", clockback);
	strcpy(p, lk);
	st_line(cat, t->name, what, 1);
	exit(0);
}

int
st_lost(int live, int err)
{
	return live > 0 && err == ECHILD;
}

/* Returns 1 on FAIL. */
static int
run(const struct st_test *t, const char *cat)
{
	char why[256], what[320];
	sigset_t stop;
	pid_t pid, r;
	int status, p, secs;

	if (t->probe != NULL) {
		why[0] = '\0';
		p = t->probe(why, sizeof why);
		if (p < 0) {
			sprintf(what, "FAIL %s", why);
			st_line(cat, t->name, what, 1);
			return 1;
		}
		if (p > 0) {
			sprintf(what, "UNSUP reason=\"%s\"", why);
			st_line(cat, t->name, what, 0);
			return 0;
		}
	}
	fflush(stdout);
	if (!st_opt.noleak)
		st_leak_snap(&leak_before);	/* the leader inherits it */
	/* blocked until leader_pid is set, so on_stop never misses the leader */
	sigemptyset(&stop);
	sigaddset(&stop, SIGINT);
	sigaddset(&stop, SIGTERM);
	sigaddset(&stop, SIGHUP);
	sigprocmask(SIG_BLOCK, &stop, &oldmask);
	pid = fork();
	if (pid < 0) {
		sigprocmask(SIG_SETMASK, &oldmask, NULL);
		sprintf(what, "FAIL reason=\"fork: %s\"", st_errname(errno));
		st_line(cat, t->name, what, 1);
		return 1;
	}
	if (pid == 0) {
		setpgid(0, 0);
		leader(t, cat);
	}
	setpgid(pid, pid);		/* both sides, so killpg never misses */
	leader_pid = pid;
	sigprocmask(SIG_SETMASK, &oldmask, NULL);
	alarmed = 0;
	secs = st_opt.secs * (t->scale != NULL ? t->scale() : 1);
	alarm(secs);
	while ((r = waitpid(pid, &status, 0)) != pid) {
		if (r < 0 && errno != EINTR)
			break;
		if (alarmed) {
			stop_group(pid);
			while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
				;
			leader_pid = 0;
			sprintf(what, "FAIL reason=timeout secs=%d", secs);
			st_line(cat, t->name, what, 1);
			return 1;
		}
	}
	alarm(0);
	killpg(pid, SIGKILL);		/* anything the test left behind */
	leader_pid = 0;
	if (r != pid) {
		sprintf(what, "FAIL reason=\"waitpid: %s\"", st_errname(errno));
		st_line(cat, t->name, what, 1);
		return 1;
	}
	if (WIFEXITED(status) && WEXITSTATUS(status) <= 1)
		return WEXITSTATUS(status);	/* the leader printed the line */
	if (WIFSIGNALED(status))
		sprintf(what, "FAIL signal=%d worker=leader", WTERMSIG(status));
	else
		sprintf(what, "FAIL exit=%d worker=leader", WEXITSTATUS(status));
	st_line(cat, t->name, what, 1);
	return 1;
}

static int
usage(const char *cat, const struct st_test *tests)
{
	fprintf(stderr, "usage: stress-%s [-n procs] [-i iters] [-t secs] [-T secs] [-s seed] "
		"[-d dir] [-m bytes[k|m]] [-D rawdev] [-v] [-l] [-L] [-N] [test ...]\ntests:", cat);
	for (; tests->name != NULL; tests++)
		fprintf(stderr, " %s", tests->name);
	fprintf(stderr, "\n");
	return 2;
}

/* Decimal, with an optional k or m suffix when sfx is set. */
static int
number(const char *s, unsigned long *v, int sfx)
{
	char *end;

	*v = strtoul(s, &end, 10);
	if (end == s)
		return -1;
	if (sfx && (*end == 'k' || *end == 'K')) {
		*v *= 1024;
		end++;
	} else if (sfx && (*end == 'm' || *end == 'M')) {
		*v *= 1024 * 1024;
		end++;
	}
	return *end == '\0' ? 0 : -1;
}

static int
named(const char *name, int argc, char **argv)
{
	int i;

	for (i = 0; i < argc; i++)
		if (strcmp(argv[i], name) == 0)
			return 1;
	return 0;
}

int
stress_main(int argc, char **argv, const char *cat, const struct st_test *tests)
{
	const struct st_test *t;
	unsigned long v;
	const char *v_env;
	int ch, i, list = 0, failed = 0;

	st_opt.seed = ((unsigned long)time(NULL) ^ (unsigned long)getpid()) & ST_MASK;
	if ((v_env = getenv("STRESS_LEAK")) != NULL && strcmp(v_env, "fail") == 0)
		st_opt.leakfail = 1;
	while ((ch = getopt(argc, argv, "n:i:t:T:s:d:m:D:vxlLN")) != -1) {
		switch (ch) {
		case 'n':
			if (number(optarg, &v, 0) < 0 || v < 1)
				return usage(cat, tests);
			st_opt.procs = v;
			break;
		case 'i':
			if (number(optarg, &v, 0) < 0 || v < 1)
				return usage(cat, tests);
			st_opt.iters = v;
			break;
		case 't':
			if (number(optarg, &v, 0) < 0 || v < 1)
				return usage(cat, tests);
			st_opt.secs = v;
			break;
		case 'T':
			if (number(optarg, &v, 0) < 0 || v < 1)
				return usage(cat, tests);
			st_opt.budget = v;
			break;
		case 's':
			if (number(optarg, &v, 0) < 0)
				return usage(cat, tests);
			st_opt.seed = v & ST_MASK;
			break;
		case 'd':
			st_opt.dir = optarg;
			break;
		case 'm':
			if (number(optarg, &v, 1) < 0)
				return usage(cat, tests);
			st_opt.mem = v;
			break;
		case 'D':
			st_opt.dev = optarg;
			break;
		case 'v':
			st_opt.verbose = 1;
			break;
		case 'x':
			st_opt.selfcheck = 1;
			break;
		case 'l':
			list = 1;
			break;
		case 'N':
			st_opt.noleak = 1;
			break;
		case 'L':
			st_opt.leakfail = 1;
			break;
		default:
			return usage(cat, tests);
		}
	}
	argc -= optind;
	argv += optind;
	for (i = 0; i < argc; i++) {
		for (t = tests; t->name != NULL && strcmp(t->name, argv[i]) != 0; t++)
			;
		if (t->name == NULL)
			return usage(cat, tests);
	}
	if (list) {
		for (t = tests; t->name != NULL; t++)
			if (!t->named_only)
				printf("%s\n", t->name);
		return 0;
	}
	fprintf(stderr, "stress-%s: seed=%lu\n", cat, st_opt.seed);
	catch(SIGALRM, on_alarm);
	catch(SIGINT, on_stop);
	catch(SIGTERM, on_stop);
	catch(SIGHUP, on_stop);
	for (t = tests; t->name != NULL; t++)
		if (argc == 0 ? !t->named_only : named(t->name, argc, argv))
			failed |= run(t, cat);
	return failed;
}
