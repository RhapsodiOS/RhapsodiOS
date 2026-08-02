#include "exec.h"
#include "strutil.h"
#include <stdio.h>
#include <stdarg.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

int exec_dry_run = 0;
static int exec_log_fd = -1;

int exec_set_log(const char *path) {
    int fd;
    int safe_fd;

    exec_clear_log();
    fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) {
        fprintf(stderr, "rbuild: cannot open log \"%s\"\n", path);
        return 1;
    }
    if (fd < 3) {
        safe_fd = fcntl(fd, F_DUPFD, 3);
        close(fd);
        if (safe_fd < 0) {
            fprintf(stderr, "rbuild: cannot reserve log descriptor\n");
            return 1;
        }
        fd = safe_fd;
    }
    exec_log_fd = fd;
    return 0;
}

void exec_clear_log(void) {
    if (exec_log_fd >= 0) close(exec_log_fd);
    exec_log_fd = -1;
}

static int has_space(const char *s) {
    for (; *s; s++)
        if (*s == ' ' || *s == '\t' || *s == '\n' ||
            *s == '\r' || *s == '\f') return 1;
    return 0;
}

void exec_printcmd(char *const argv[]) {
    int i;
    for (i = 0; argv[i]; i++) {
        if (has_space(argv[i])) printf("\"%s\" ", argv[i]);
        else printf("%s ", argv[i]);
    }
    printf("\n");
    fflush(stdout);
}

static int write_all(int fd, const char *buf, size_t count) {
    size_t done = 0;
    ssize_t n;
    while (done < count) {
        n = write(fd, buf + done, count - done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 1;
        done += (size_t)n;
    }
    return 0;
}

static int normalize_fd(int fd) {
    int replacement;
    if (fd > STDERR_FILENO) return fd;
    replacement = fcntl(fd, F_DUPFD, STDERR_FILENO + 1);
    if (replacement < 0) return -1;
    close(fd);
    return replacement;
}

static int log_command(char *const argv[]) {
    int i;
    static const char prefix[] = "command: ";
    if (write_all(exec_log_fd, prefix, sizeof(prefix) - 1) != 0) return 1;
    for (i = 0; argv[i] != 0; i++) {
        if (i != 0 && write_all(exec_log_fd, " ", 1) != 0) return 1;
        if (has_space(argv[i]) && write_all(exec_log_fd, "\"", 1) != 0)
            return 1;
        if (write_all(exec_log_fd, argv[i], strlen(argv[i])) != 0) return 1;
        if (has_space(argv[i]) && write_all(exec_log_fd, "\"", 1) != 0)
            return 1;
    }
    return write_all(exec_log_fd, "\n", 1);
}

static int log_status(int status) {
    char *message = exec_checkret(status);
    int result = 0;
    if (write_all(exec_log_fd, "status: ", 8) != 0 ||
        write_all(exec_log_fd, message, strlen(message)) != 0 ||
        write_all(exec_log_fd, "\n", 1) != 0) result = 1;
    free(message);
    return result;
}

static int exec_run_logged(char *const argv[]) {
    int fds[2];
    pid_t pid;
    int status;
    int io_failed = 0;
    int stdout_broken = 0;
    char buf[4096];
    ssize_t n;
    void (*old_sigpipe)(int);

    if (log_command(argv) != 0) return -1;
    if (pipe(fds) < 0) {
        fprintf(stderr, "rbuild: pipe failed\n");
        return -1;
    }
    fds[0] = normalize_fd(fds[0]);
    if (fds[0] < 0) { close(fds[1]); return -1; }
    fds[1] = normalize_fd(fds[1]);
    if (fds[1] < 0) { close(fds[0]); return -1; }
    pid = fork();
    if (pid < 0) {
        close(fds[0]); close(fds[1]);
        fprintf(stderr, "rbuild: fork failed\n");
        return -1;
    }
    if (pid == 0) {
        close(fds[0]);
        if (fds[1] != STDOUT_FILENO && dup2(fds[1], STDOUT_FILENO) < 0)
            _exit(126);
        if (fds[1] != STDERR_FILENO && dup2(fds[1], STDERR_FILENO) < 0)
            _exit(126);
        if (fds[1] != STDOUT_FILENO && fds[1] != STDERR_FILENO) close(fds[1]);
        close(exec_log_fd);
        execvp(argv[0], argv);
        fprintf(stderr, "rbuild: exec \"%s\" failed\n", argv[0]);
        _exit(127);
    }
    close(fds[1]);
    old_sigpipe = signal(SIGPIPE, SIG_IGN);
    for (;;) {
        n = read(fds[0], buf, sizeof(buf));
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { io_failed = 1; break; }
        if (n == 0) break;
        if (!stdout_broken &&
            write_all(STDOUT_FILENO, buf, (size_t)n) != 0) {
            stdout_broken = 1;
        }
        if (write_all(exec_log_fd, buf, (size_t)n) != 0) io_failed = 1;
    }
    close(fds[0]);
    while (waitpid(pid, &status, 0) < 0) {
        if (errno == EINTR) continue;
        if (old_sigpipe != SIG_ERR) signal(SIGPIPE, old_sigpipe);
        return -1;
    }
    if (log_status(status) != 0) io_failed = 1;
    if (old_sigpipe != SIG_ERR) signal(SIGPIPE, old_sigpipe);
    if (io_failed) return -1;
    return status;
}

int exec_run(char *const argv[]) {
    pid_t pid;
    int status;

    if (exec_dry_run) {
        exec_printcmd(argv);
        return 0;
    }

    if (exec_log_fd >= 0) return exec_run_logged(argv);

    pid = fork();
    if (pid < 0) {
        fprintf(stderr, "rbuild: fork failed\n");
        return -1;
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        fprintf(stderr, "rbuild: exec \"%s\" failed\n", argv[0]);
        _exit(127);
    }
    if (waitpid(pid, &status, 0) < 0) return -1;
    return status;   /* raw wait status word */
}

int exec_runv(const char *arg0, ...) {
    strlist args;
    va_list ap;
    const char *a;
    int rc;
    char **argv;
    size_t i;

    strlist_init(&args);
    strlist_push(&args, arg0);
    va_start(ap, arg0);
    while ((a = va_arg(ap, const char *)) != 0) strlist_push(&args, a);
    va_end(ap);

    argv = (char **) xmalloc((args.count + 1) * sizeof(char *));
    for (i = 0; i < args.count; i++) argv[i] = args.items[i];
    argv[args.count] = 0;

    rc = exec_run(argv);
    free(argv);
    strlist_free(&args);
    return rc;
}

char *exec_checkret(int status) {
    int lowbyte, signal, exitstatus;
    char buf[64];

    if (status == 0) return xstrdup("exited successfully");

    lowbyte = status & 0xff;
    if (lowbyte == 0x7f) return xstrdup("stopped");

    signal = lowbyte & 0177;
    if (signal != 0) {
        sbuf s; char *out;
        sbuf_init(&s);
        sprintf(buf, "terminated by signal %d", signal);
        sbuf_puts(&s, buf);
        if (lowbyte & 0200) sbuf_puts(&s, " (core dumped)");
        out = sbuf_steal(&s);
        sbuf_free(&s);
        return out;
    }

    exitstatus = (status >> 8) & 0xff;
    sprintf(buf, "failed with status %d", exitstatus);
    return xstrdup(buf);
}

int exec_check(int status) {
    if (status == 0) return 0;
    {
        char *msg = exec_checkret(status);
        fprintf(stderr, "rbuild: %s\n", msg);
        free(msg);
    }
    return 1;
}

int exec_run_checked(char *const argv[]) {
    return exec_check(exec_run(argv));
}
