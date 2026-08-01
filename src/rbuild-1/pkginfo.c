#include "pkginfo.h"
#include "strutil.h"
#include "exec.h"
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static void emit(FILE *f, const char *key, const char *value) {
    if (value) fprintf(f, "%s = %s\n", key, value);
}

int pkginfo_write(const Package *p, const char *path) {
    FILE *f = fopen(path, "w");
    char *ver;
    if (!f) {
        fprintf(stderr, "rbuild: unable to open %s for writing\n", path);
        return 1;
    }
    ver = package_canon_version(p);
    emit(f, "pkgname", p->package);
    emit(f, "pkgver", ver);
    emit(f, "arch", p->architecture);
    emit(f, "pkgdesc", p->description);
    emit(f, "maintainer", p->maintainer);
    emit(f, "origin", p->source);
    emit(f, "provides", p->provides);
    emit(f, "replaces", p->replaces);
    if (p->has_build_depends) {
        sbuf s;
        char *joined;
        size_t i;
        sbuf_init(&s);
        for (i = 0; i < p->build_depends.count; i++) {
            if (i) sbuf_putc(&s, ' ');
            sbuf_puts(&s, p->build_depends.items[i]);
        }
        joined = sbuf_steal(&s);
        emit(f, "builddepends", joined);
        free(joined);
        sbuf_free(&s);
    }
    free(ver);
    fclose(f);
    return 0;
}

static int wait_for_child(pid_t pid) {
    int status;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return 1;
    }
    return !WIFEXITED(status) || WEXITSTATUS(status) != 0;
}

static int normalize_fd(int fd) {
    int replacement;
    if (fd > STDERR_FILENO) return fd;
    replacement = fcntl(fd, F_DUPFD, STDERR_FILENO + 1);
    if (replacement < 0) return -1;
    close(fd);
    return replacement;
}

static int run_apk_pipeline(const char *out_apk, const char *gzip_program,
                            char **tar_argv) {
    int fds[2];
    int output_fd;
    pid_t tar_pid;
    pid_t gzip_pid;
    int result;
    if (exec_dry_run) {
        char *gzip_argv[3];
        gzip_argv[0] = (char *)gzip_program;
        gzip_argv[1] = "-9";
        gzip_argv[2] = 0;
        exec_printcmd(tar_argv);
        exec_printcmd(gzip_argv);
        return 0;
    }
    output_fd = open(out_apk, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (output_fd < 0) return 1;
    output_fd = normalize_fd(output_fd);
    if (output_fd < 0) {
        unlink(out_apk);
        return 1;
    }
    if (pipe(fds) != 0) {
        close(output_fd);
        unlink(out_apk);
        return 1;
    }
    fds[0] = normalize_fd(fds[0]);
    if (fds[0] < 0) {
        close(fds[1]); close(output_fd); unlink(out_apk);
        return 1;
    }
    fds[1] = normalize_fd(fds[1]);
    if (fds[1] < 0) {
        close(fds[0]); close(output_fd); unlink(out_apk);
        return 1;
    }
    tar_pid = fork();
    if (tar_pid < 0) {
        close(fds[0]); close(fds[1]); close(output_fd); unlink(out_apk);
        return 1;
    }
    if (tar_pid == 0) {
        close(fds[0]);
        if (dup2(fds[1], STDOUT_FILENO) < 0) _exit(127);
        close(fds[1]);
        close(output_fd);
        execvp(tar_argv[0], tar_argv);
        _exit(127);
    }
    gzip_pid = fork();
    if (gzip_pid < 0) {
        close(fds[0]); close(fds[1]); close(output_fd);
        wait_for_child(tar_pid);
        unlink(out_apk);
        return 1;
    }
    if (gzip_pid == 0) {
        char *argv[3];
        close(fds[1]);
        if (dup2(fds[0], STDIN_FILENO) < 0 ||
            dup2(output_fd, STDOUT_FILENO) < 0) _exit(127);
        close(fds[0]);
        close(output_fd);
        argv[0] = (char *)gzip_program;
        argv[1] = "-9";
        argv[2] = 0;
        execvp(argv[0], argv);
        _exit(127);
    }
    close(fds[0]);
    close(fds[1]);
    result = close(output_fd) != 0;
    if (wait_for_child(tar_pid) != 0) result = 1;
    if (wait_for_child(gzip_pid) != 0) result = 1;
    if (result != 0) unlink(out_apk);
    return result;
}

int pkginfo_build_apk(const char *root_dir, const char *out_apk,
                      const Toolchain *tc) {
    strlist tar_args;
    char **tar_argv;
    size_t i;
    int result;
    const char *tar_program;
    const char *gzip_program;

    if (root_dir == 0 || out_apk == 0) return 1;
    if (tc != 0 && (tc->tar == 0 || tc->gzip == 0 ||
                    tc->tar_create_flags == 0 ||
                    tc->tar_create_flags[0] == '\0')) {
        fprintf(stderr, "rbuild: missing configured APK archive-create "
                "capability\n");
        return 1;
    }
    tar_program = tc == 0 ? "tar" : tc->tar;
    gzip_program = tc == 0 ? "gzip" : tc->gzip;
    strlist_init(&tar_args);
    strlist_push(&tar_args, tar_program);
    if (tc != 0)
        toolchain_expand_words(tc->tar_create_flags, "", &tar_args);
    if (tc != 0 && tar_args.count == 1) {
        fprintf(stderr, "rbuild: empty configured APK archive-create flags\n");
        strlist_free(&tar_args);
        return 1;
    }
    strlist_push(&tar_args, "-C");
    strlist_push(&tar_args, root_dir);
    strlist_push(&tar_args, "-cf");
    strlist_push(&tar_args, "-");
    strlist_push(&tar_args, ".");
    tar_argv = (char **)xmalloc((tar_args.count + 1) * sizeof(char *));
    for (i = 0; i < tar_args.count; i++) tar_argv[i] = tar_args.items[i];
    tar_argv[tar_args.count] = 0;
    result = run_apk_pipeline(out_apk, gzip_program, tar_argv);
    free(tar_argv);
    strlist_free(&tar_args);
    return result;
}
