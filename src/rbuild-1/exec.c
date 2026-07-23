#include "exec.h"
#include "strutil.h"
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

int exec_dry_run = 0;

static int has_space(const char *s) {
    for (; *s; s++)
        if (*s == ' ' || *s == '\t' || *s == '\n') return 1;
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

int exec_run(char *const argv[]) {
    pid_t pid;
    int status;

    if (exec_dry_run) {
        exec_printcmd(argv);
        return 0;
    }

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
