/* stress-thread: cthreads tests. st_fail and the st_op calls belong to the
 * worker's main thread only: threads record the first error in g_msg under
 * g_mu and the main thread reports it after waiting. Waits are bounded
 * (WAITSECS) and never join a thread that may be stuck; the worker's _exit
 * ends any left over. At most 32 threads are alive in a test. */
#include <sys/types.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <mach/cthreads.h>
#include "stress.h"

#define WAITSECS 60
#define NMUTEX	8
#define INCS	10000
#define RECLEN	64
#define NPROD	4
#define NCONS	4
#define NITEMS	2000
#define QCAP	16
#define NSTACK	16
#define STKLEN	32768

static mutex_t g_mu;
static int g_done;
static int g_bad;
static char g_msg[160];
static pid_t g_kid;

/* usleep arms ITIMER_REAL and sigsuspends here; with other threads running
 * its SIGALRM can land elsewhere and the sleeper never wakes. select is safe. */
static void
nap(long us)
{
	struct timeval tv;

	tv.tv_sec = 0;
	tv.tv_usec = us;
	select(0, NULL, NULL, NULL, &tv);
}

/* Threads: record the first error. */
static void
thr_err(const char *fmt, unsigned long b, unsigned long d)
{
	mutex_lock(g_mu);
	if (!g_bad) {
		g_bad = 1;
		sprintf(g_msg, fmt, b, d);
	}
	mutex_unlock(g_mu);
}

static void
thr_done(void)
{
	mutex_lock(g_mu);
	g_done++;
	mutex_unlock(g_mu);
}

static void
hook(struct st_ctx *c)
{
	int st;

	if (g_kid > 0) {
		kill(g_kid, SIGKILL);
		while (waitpid(g_kid, &st, 0) < 0 && errno == EINTR)
			;
		g_kid = 0;
	}
}

static void
setup(struct st_ctx *c)
{
	if (g_mu == NULL)
		g_mu = mutex_alloc();
	g_done = g_bad = 0;
	g_kid = 0;
	st_set_cleanup(c, hook);
}

static void
failmsg(struct st_ctx *c)
{
	st_fail(c, "%s", g_msg);
}

/* Wait until n threads have called thr_done, or one recorded an error. */
static void
waitdone(struct st_ctx *c, int n)
{
	time_t t0 = time(NULL);
	int d, b;

	for (;;) {
		mutex_lock(g_mu);
		d = g_done;
		b = g_bad;
		mutex_unlock(g_mu);
		if (b)
			failmsg(c);
		if (d >= n)
			return;
		if (time(NULL) - t0 > WAITSECS)
			st_fail(c, "reason=timeout what=threads done=%d want=%d", d, n);
		nap(2000);
	}
}

static cthread_t
fork1(struct st_ctx *c, cthread_fn_t fn, void *arg)
{
	cthread_t t = cthread_fork(fn, arg);

	if (t == NO_CTHREAD)
		st_fail(c, "reason=cthread_fork-failed");
	return t;
}

/* create: each thread returns st_mix(key + idx). */
static any_t
create_fn(any_t arg)
{
	return (any_t)st_mix((unsigned long)arg);
}

static void
t_create(struct st_ctx *c)
{
	cthread_t t[32];
	unsigned long key, got;
	int i, k, n;

	setup(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		n = (int)st_range(&c->rng, 1, 32);
		key = st_rand(&c->rng);
		for (k = 0; k < n; k++)
			t[k] = fork1(c, create_fn, (any_t)((key + k) & ST_MASK));
		for (k = 0; k < n; k++) {
			got = (unsigned long)cthread_join(t[k]) & ST_MASK;
			if (got != st_mix((key + k) & ST_MASK))
				st_fail(c, "reason=join-result thread=%d got=0x%lx want=0x%lx",
					k, got, st_mix((key + k) & ST_MASK));
		}
		st_op_end(c, n);
	}
}

/* mutex: a shared counter and per-thread patterned records. */
static long g_count;
static unsigned long g_rkey[NMUTEX];
static unsigned char g_rec[NMUTEX][RECLEN];
static int g_skip;

static any_t
mutex_fn(any_t arg)
{
	int k = (int)arg, n, nb;
	unsigned long key;
	long bad;

	for (n = 0; n < INCS; n++) {
		mutex_lock(g_mu);
		if (!(g_skip && k == 0 && n == 0))
			g_count++;
		key = st_mix(((unsigned long)k << 16) ^ (unsigned long)n);
		g_rkey[k] = key;
		st_fill(g_rec[k], RECLEN, key, 0);
		if ((n & 15) == 0) {
			nb = (k + 1) % NMUTEX;
			bad = g_rkey[nb] ? st_check(g_rec[nb], RECLEN, g_rkey[nb], 0) : -1;
			if (bad >= 0 && !g_bad) {
				g_bad = 1;
				sprintf(g_msg, "what=record thread=%d off=0x%lx", nb, (unsigned long)bad);
			}
		}
		mutex_unlock(g_mu);
	}
	thr_done();
	return NULL;
}

static void
t_mutex(struct st_ctx *c)
{
	cthread_t t[NMUTEX];
	long bad;
	int i, k;

	setup(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		g_count = 0;
		memset(g_rkey, 0, sizeof g_rkey);
		g_done = 0;
		g_skip = c->selfcheck;
		for (k = 0; k < NMUTEX; k++)
			t[k] = fork1(c, mutex_fn, (any_t)k);
		waitdone(c, NMUTEX);
		for (k = 0; k < NMUTEX; k++)
			cthread_join(t[k]);
		if (g_count != (long)NMUTEX * INCS)
			st_fail(c, "reason=counter want=%d got=%ld", NMUTEX * INCS, g_count);
		for (k = 0; k < NMUTEX; k++) {
			bad = st_check(g_rec[k], RECLEN, g_rkey[k], 0);
			if (bad >= 0)
				st_fail_data(c, "record", g_rec[k], RECLEN, g_rkey[k], 0, bad);
		}
		st_op_end(c, NMUTEX * INCS);
	}
}

/* cond: producers and consumers pass (producer, seq) through a ring. */
static condition_t g_notfull, g_notempty;
static unsigned long g_q[QCAP];
static int g_qh, g_qn;
static int g_seq[NPROD], g_got[NPROD];
static int g_proddone, g_drop;

static any_t
prod_fn(any_t arg)
{
	int p = (int)arg, s, per = NITEMS / NPROD;

	for (s = 0; s < per; s++) {
		mutex_lock(g_mu);
		while (g_qn == QCAP && !g_bad)
			condition_wait(g_notfull, g_mu);
		if (g_bad) {
			mutex_unlock(g_mu);
			break;
		}
		if (!(g_drop && p == 0 && s == 7)) {
			g_q[(g_qh + g_qn) % QCAP] = ((unsigned long)p << 16) | (unsigned long)s;
			g_qn++;
			condition_signal(g_notempty);
		}
		mutex_unlock(g_mu);
	}
	mutex_lock(g_mu);
	g_proddone++;
	condition_broadcast(g_notempty);
	mutex_unlock(g_mu);
	thr_done();
	return NULL;
}

static any_t
cons_fn(any_t arg)
{
	unsigned long it;
	int p, s;

	for (;;) {
		mutex_lock(g_mu);
		while (g_qn == 0 && g_proddone < NPROD && !g_bad)
			condition_wait(g_notempty, g_mu);
		if (g_qn == 0 || g_bad) {
			mutex_unlock(g_mu);
			break;
		}
		it = g_q[g_qh];
		g_qh = (g_qh + 1) % QCAP;
		g_qn--;
		condition_signal(g_notfull);
		p = (int)(it >> 16);
		s = (int)(it & 0xffff);
		if (p >= NPROD || s != g_seq[p]) {
			if (!g_bad) {
				g_bad = 1;
				sprintf(g_msg, "what=order producer=%d seq=%d want=%d", p, s,
					p < NPROD ? g_seq[p] : -1);
			}
		} else {
			g_seq[p]++;
			g_got[p]++;
		}
		mutex_unlock(g_mu);
	}
	thr_done();
	return NULL;
}

static void
t_cond(struct st_ctx *c)
{
	cthread_t t[NPROD + NCONS];
	int i, k, total;

	setup(c);
	g_notfull = condition_alloc();
	g_notempty = condition_alloc();
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		g_qh = g_qn = g_proddone = 0;
		memset(g_seq, 0, sizeof g_seq);
		memset(g_got, 0, sizeof g_got);
		g_drop = c->selfcheck;
		for (k = 0; k < NCONS; k++)
			t[NPROD + k] = fork1(c, cons_fn, NULL);
		for (k = 0; k < NPROD; k++)
			t[k] = fork1(c, prod_fn, (any_t)k);
		waitdone(c, NPROD + NCONS);
		for (k = 0; k < NPROD + NCONS; k++)
			cthread_join(t[k]);
		total = g_got[0] + g_got[1] + g_got[2] + g_got[3];
		if (total != NITEMS)
			st_fail(c, "reason=items want=%d got=%d", NITEMS, total);
		st_op_end(c, NITEMS);
	}
}

/* stack: every thread keeps a patterned local array across yields. */
static volatile int g_filled;

static any_t
stack_fn(any_t arg)
{
	unsigned char buf[STKLEN];
	unsigned long key = (unsigned long)arg;
	long bad;
	int y;

	st_fill(buf, STKLEN, key, 0);
	mutex_lock(g_mu);
	if (g_skip == 1) {
		g_skip = 2;	/* one flip, by whichever thread gets here first */
		buf[1000] ^= 0xff;
	}
	g_filled++;
	mutex_unlock(g_mu);
	/* all arrays are live at once; main's waitdone bounds a stuck wait */
	while (g_filled < NSTACK)
		cthread_yield();
	for (y = 0; y < 10; y++)
		cthread_yield();
	bad = st_check(buf, STKLEN, key, 0);
	if (bad >= 0)
		thr_err("what=stack key=0x%lx off=0x%lx", key, (unsigned long)bad);
	thr_done();
	return NULL;
}

static void
t_stack(struct st_ctx *c)
{
	cthread_t t[NSTACK];
	int i, k;

	setup(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		g_done = 0;
		g_filled = 0;
		g_skip = c->selfcheck;
		for (k = 0; k < NSTACK; k++)
			t[k] = fork1(c, stack_fn, (any_t)st_mix(((unsigned long)k << 8) ^ (unsigned long)i ^ ((unsigned long)c->idx << 20)));
		waitdone(c, NSTACK);
		for (k = 0; k < NSTACK; k++)
			cthread_join(t[k]);
		st_op_end(c, NSTACK);
	}
}

/* fork: the main thread forks while threads hammer a mutex. */
static volatile int g_stop;
static long g_local[4];

static any_t
spin_fn(any_t arg)
{
	int k = (int)arg;

	while (!g_stop) {
		mutex_lock(g_mu);
		g_count++;
		mutex_unlock(g_mu);
		g_local[k]++;
	}
	thr_done();
	return NULL;
}

static void
child_body(unsigned long key)
{
	unsigned char *p = malloc(1 << 20);

	if (p == NULL)
		_exit(2);
	st_fill(p, 1 << 20, key, 0);
	if (st_check(p, 1 << 20, key, 0) >= 0)
		_exit(3);
	_exit(0);
}

static void
t_fork(struct st_ctx *c)
{
	cthread_t t[4];
	time_t t0;
	long cnt, sum;
	unsigned long key;
	pid_t pid, r;
	int i, k, st;

	setup(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		g_count = 0;
		g_stop = 0;
		g_done = 0;
		memset(g_local, 0, sizeof g_local);
		for (k = 0; k < 4; k++)
			t[k] = fork1(c, spin_fn, (any_t)k);
		for (t0 = time(NULL); ; nap(1000)) {
			mutex_lock(g_mu);
			cnt = g_count;
			mutex_unlock(g_mu);
			if (cnt > 0)
				break;
			if (time(NULL) - t0 > WAITSECS)
				st_fail(c, "reason=timeout what=spinners");
		}
		key = st_mix((unsigned long)i ^ ((unsigned long)c->idx << 20));
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0)
			child_body(key);
		g_kid = pid;
		for (t0 = time(NULL); ; nap(5000)) {
			r = waitpid(pid, &st, WNOHANG);
			if (r == pid)
				break;
			if (r < 0 && errno != EINTR)
				st_fail_errno(c, "waitpid");
			if (time(NULL) - t0 > 10)
				st_fail(c, "reason=child-hang");
		}
		g_kid = 0;
		g_stop = 1;
		waitdone(c, 4);
		for (k = 0; k < 4; k++)
			cthread_join(t[k]);
		if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
			st_fail(c, "reason=child-status status=0x%x", st);
		sum = g_local[0] + g_local[1] + g_local[2] + g_local[3];
		if (sum != g_count)
			st_fail(c, "reason=counter want=%ld got=%ld", sum, g_count);
		st_op_end(c, 1);
	}
}

/* signal: SIGALRM from an interval timer and SIGUSR1 from a child reach a
 * task whose threads are spinning. */
static volatile long g_alrm, g_usr1, g_spin[8];

static void
on_alrm(int s)
{
	g_alrm++;
}

static void
on_usr1(int s)
{
	g_usr1++;
}

static any_t
sigspin_fn(any_t arg)
{
	int k = (int)arg;

	while (!g_stop)
		g_spin[k]++;
	thr_done();
	return NULL;
}

static void
t_signal(struct st_ctx *c)
{
	cthread_t t[8];
	struct itimerval it;
	struct timeval nap;
	long snap[8];
	time_t t0;
	pid_t pid, parent;
	int i, k, n, ok, st;

	setup(c);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		g_alrm = g_usr1 = 0;
		g_stop = 0;
		g_done = 0;
		signal(SIGALRM, on_alrm);
		signal(SIGUSR1, on_usr1);
		for (k = 0; k < 8; k++)
			t[k] = fork1(c, sigspin_fn, (any_t)k);
		parent = getpid();
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0) {
			for (n = 0; n < 200; n++) {
				usleep(5000);
				if (kill(parent, SIGUSR1) < 0)
					break;
			}
			_exit(0);
		}
		g_kid = pid;
		nap.tv_sec = 0;
		nap.tv_usec = 5000;
		for (k = 0; k < 8; k++)
			snap[k] = g_spin[k];
		memset(&it, 0, sizeof it);
		it.it_interval.tv_usec = it.it_value.tv_usec = 2000;
		if (setitimer(ITIMER_REAL, &it, NULL) < 0)
			st_fail_errno(c, "setitimer");
		/* usleep is built on ITIMER_REAL here and would cancel the timer,
		 * so the poll sleeps in select. */
		for (t0 = time(NULL); ; nap.tv_usec = 5000, select(0, NULL, NULL, NULL, &nap)) {
			ok = g_alrm >= 50 && g_usr1 >= 1;
			for (k = 0; k < 8; k++)
				if (g_spin[k] == snap[k])
					ok = 0;
			if (ok)
				break;
			if (time(NULL) - t0 > 30)
				st_fail(c, "reason=timeout alrm=%ld usr1=%ld", g_alrm, g_usr1);
		}
		memset(&it, 0, sizeof it);
		setitimer(ITIMER_REAL, &it, NULL);
		signal(SIGALRM, SIG_IGN);
		signal(SIGUSR1, SIG_IGN);
		g_stop = 1;
		waitdone(c, 8);
		for (k = 0; k < 8; k++)
			cthread_join(t[k]);
		kill(pid, SIGKILL);
		while (waitpid(pid, &st, 0) < 0)
			if (errno != EINTR)
				st_fail_errno(c, "waitpid");
		g_kid = 0;
		st_op_end(c, 1);
	}
}

static const struct st_test tests[] = {
	{ "create", 200, 0, NULL, t_create },
	{ "mutex", 20, 0, NULL, t_mutex },
	{ "cond", 20, 0, NULL, t_cond },
	{ "stack", 50, 0, NULL, t_stack },
	{ "fork", 20, 0, NULL, t_fork },
	{ "signal", 5, 0, NULL, t_signal },
	{ NULL, 0, 0, NULL, NULL }
};

int
main(int argc, char **argv)
{
	return stress_main(argc, argv, "thread", tests);
}
