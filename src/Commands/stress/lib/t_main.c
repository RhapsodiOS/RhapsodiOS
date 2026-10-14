/* stress-tmain: a demo table whose tests pass, fail, crash, hang, refuse,
 * corrupt and fork-bomb, so make check can verify the supervision. */
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>
#include "stress.h"

#define MAXKIDS 8192

static pid_t kids[MAXKIDS];

static void
t_pass(struct st_ctx *c)
{
	long i;

	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		st_op_end(c, 1);
	}
}

static void
t_fail(struct st_ctx *c)
{
	st_fail(c, "reason=planned");
}

/* The cleanup hook leaves a marker keyed to the leader's pid (our parent). */
static void
hook_fn(struct st_ctx *c)
{
	char p[64];
	int fd;

	sprintf(p, "/tmp/stress.tmain.hook.%d", (int)getppid());
	fd = open(p, O_CREAT | O_WRONLY, 0600);
	if (fd >= 0)
		close(fd);
}

static void
t_hook(struct st_ctx *c)
{
	st_set_cleanup(c, hook_fn);
	st_fail(c, "reason=planned");
}

static void
t_crash(struct st_ctx *c)
{
	struct rlimit rl;

	rl.rlim_cur = rl.rlim_max = 0;		/* no core file */
	setrlimit(RLIMIT_CORE, &rl);
	kill(getpid(), SIGSEGV);
}

/* Worker 0 crashes while the rest wait forever: the crash must be
 * reported at once, not as a timeout. */
static void
t_crashwait(struct st_ctx *c)
{
	if (c->idx == 0)
		t_crash(c);
	for (;;)
		pause();
}

static void
t_hang(struct st_ctx *c)
{
	int i;
	pid_t pid;

	for (i = 0; i < 3; i++) {
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0) {
			sleep(1000);
			_exit(0);
		}
	}
	for (;;)
		pause();
}

static int
p_unsup(char *why, int len)
{
	sprintf(why, "msync: %s", st_errname(ENOSYS));
	return 1;
}

static void
t_unsup(struct st_ctx *c)
{
}

static void
t_data(struct st_ctx *c)
{
	unsigned char b[64];
	long bad;

	st_fill(b, sizeof b, 5, 0);
	b[17] ^= 0x01;
	bad = st_check(b, sizeof b, 5, 0);
	if (bad < 0)
		st_fail(c, "reason=check-missed");
	st_fail_data(c, "buf", b, sizeof b, 5, 0, bad);
}

/* Forks pausing children until fork fails, then kills and reaps them all
 * before reporting, so the process table frees at once. It runs under a
 * 64-process limit (root drops to nobody, which root would bypass): the
 * system-wide limit is above what Mach can hold, and reaching it panics in
 * ipc_task_init. */
static void
t_forkbomb(struct st_ctx *c)
{
	struct rlimit rl;
	int n = 0, i, err;
	pid_t pid;

	rl.rlim_cur = rl.rlim_max = 64;
	if (setrlimit(RLIMIT_NPROC, &rl) < 0)
		st_fail_errno(c, "setrlimit");
	if (getuid() == 0 && setuid(-2) < 0)
		st_fail_errno(c, "setuid");
	for (;;) {
		if (n == MAXKIDS) {
			err = 0;
			break;
		}
		pid = fork();
		if (pid < 0) {
			err = errno;
			break;
		}
		if (pid == 0)
			for (;;)
				pause();
		kids[n++] = pid;
	}
	for (i = 0; i < n; i++)
		kill(kids[i], SIGKILL);
	for (i = 0; i < n; i++)
		while (waitpid(kids[i], NULL, 0) < 0 && errno == EINTR)
			;
	if (err == 0)
		st_fail(c, "reason=no-fork-limit kids=%d", n);
	errno = err;
	st_fail_errno(c, "fork");
}

static const struct st_test tests[] = {
	{ "pass", 10, 0, NULL, t_pass },
	{ "fail", 1, 0, NULL, t_fail },
	{ "hook", 1, 0, NULL, t_hook },
	{ "crash", 1, 0, NULL, t_crash },
	{ "crashwait", 1, 0, NULL, t_crashwait },
	{ "hang", 1, 0, NULL, t_hang },
	{ "unsup", 1, 0, p_unsup, t_unsup },
	{ "data", 1, 0, NULL, t_data },
	{ "forkbomb", 1, 1, NULL, t_forkbomb },
	{ NULL }
};

int
main(int argc, char **argv)
{
	return stress_main(argc, argv, "tmain", tests);
}
