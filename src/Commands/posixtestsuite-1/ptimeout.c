/*
 * ptimeout secs cmd [args...]
 *
 * Run cmd in its own process group and kill the group after secs seconds.
 * Unlike upstream's t0, the alarm is in this process, so a test that
 * catches SIGALRM cannot defeat it.  The group is also killed after a
 * normal exit, so children a test leaves behind do not pile up.
 *
 * Exit status: cmd's exit status; 128+n if it died by signal n; 124 on
 * timeout; 127 on bad usage or if cmd could not be started.
 */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

static volatile sig_atomic_t expired;

static void
on_alarm(int sig)
{
	expired = 1;
}

int
main(int argc, char *argv[])
{
	struct sigaction sa;
	int secs, status;
	pid_t pid;

	if (argc < 3 || (secs = atoi(argv[1])) < 1) {
		fprintf(stderr, "usage: ptimeout secs cmd [args...]\n");
		return 127;
	}
	pid = fork();
	if (pid < 0) {
		perror("ptimeout: fork");
		return 127;
	}
	if (pid == 0) {
		setpgid(0, 0);
		execvp(argv[2], argv + 2);
		fprintf(stderr, "ptimeout: %s: %s\n", argv[2], strerror(errno));
		_exit(127);
	}
	setpgid(pid, pid);	/* whichever of us runs first sets it */

	/* No SA_RESTART: waitpid must return EINTR when the alarm fires. */
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_alarm;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGALRM, &sa, NULL);
	alarm(secs);

	while (waitpid(pid, &status, 0) < 0) {
		if (errno != EINTR) {
			perror("ptimeout: waitpid");
			return 127;
		}
		if (expired) {
			killpg(pid, SIGKILL);
			while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
				;
			return 124;
		}
	}
	alarm(0);
	killpg(pid, SIGKILL);	/* stragglers; ESRCH when there are none */
	if (WIFSIGNALED(status))
		return 128 + WTERMSIG(status);
	return WEXITSTATUS(status);
}
