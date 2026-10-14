/* stress-tmain: a demo table whose tests pass, fail, crash, hang, refuse,
 * corrupt and fork-bomb, so make check can verify the supervision. */
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <errno.h>
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

static void
t_crash(struct st_ctx *c)
{
	struct rlimit rl;

	rl.rlim_cur = rl.rlim_max = 0;		/* no core file */
	setrlimit(RLIMIT_CORE, &rl);
	kill(getpid(), SIGSEGV);
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
 * before reporting, so the process table frees at once. */
static void
t_forkbomb(struct st_ctx *c)
{
	int n = 0, i, err;
	pid_t pid;

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
	{ "crash", 1, 0, NULL, t_crash },
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
