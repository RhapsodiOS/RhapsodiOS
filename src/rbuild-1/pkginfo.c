#include "pkginfo.h"
#include "architecture.h"
#include "strutil.h"
#include "exec.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static char *slurp_file(const char *path) {
    FILE *f = fopen(path, "r");
    sbuf s;
    char buf[1024];
    size_t n;
    char *out;
    if (!f) return 0;
    sbuf_init(&s);
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) sbuf_putn(&s, buf, n);
    fclose(f);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}

int pkginfo_read(Package *p, const char *path) {
    char *data;
    char *cursor;
    unsigned mask;
    data = slurp_file(path);
    if (!data) return 1;
    cursor = data;
    while (*cursor) {
        char *line = cursor;
        char *nl = strchr(cursor, '\n');
        char *eq;
        char *key;
        char *val;
        if (nl) { *nl = '\0'; cursor = nl + 1; }
        else cursor += strlen(cursor);
        line = str_trim(line);
        if (line[0] == '\0' || line[0] == '#') continue;
        eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        key = str_trim(line);
        val = str_trim(eq + 1);
        if (strcmp(key, "pkgname") == 0) package_set(&p->package, val);
        else if (strcmp(key, "pkgver") == 0) package_set(&p->version, val);
        else if (strcmp(key, "arch") == 0) package_set(&p->architecture, val);
        else if (strcmp(key, "pkgdesc") == 0) package_set(&p->description, val);
        else if (strcmp(key, "url") == 0) package_set(&p->url, val);
        else if (strcmp(key, "maintainer") == 0) package_set(&p->maintainer, val);
        else if (strcmp(key, "license") == 0) package_set(&p->license, val);
        else if (strcmp(key, "origin") == 0) package_set(&p->source, val);
        else if (strcmp(key, "provides") == 0) package_set(&p->provides, val);
        else if (strcmp(key, "replaces") == 0) package_set(&p->replaces, val);
        else if (strcmp(key, "makedepends") == 0 ||
                 strcmp(key, "depend") == 0) {
            if (strcmp(key, "makedepends") == 0) {
                strlist_free(&p->build_depends);
                strlist_init(&p->build_depends);
                str_split_chars(val, " ,", &p->build_depends);
                p->has_build_depends = 1;
            }
            /* depend: accept (do not error); do not treat as makedepends */
        }
        /* unknown keys ignored */
    }
    free(data);
    if (!p->package) {
        fprintf(stderr, "error: package file does not contain 'pkgname' entry\n");
        return 2;
    }
    if (!p->version) {
        fprintf(stderr, "error: package file does not contain 'pkgver' entry\n");
        return 2;
    }
    if (architecture_parse(p->architecture, &mask) != 0) {
        fprintf(stderr, "rbuild: %s: invalid arch: '%s'\n",
                path, p->architecture);
        return 2;
    }
    return 0;
}

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
                            const char *archive_cwd, char **archive_argv) {
    int fds[2];
    int output_fd;
    pid_t archive_pid;
    pid_t gzip_pid;
    int result;
    if (exec_dry_run) {
        char *gzip_argv[3];
        gzip_argv[0] = (char *)gzip_program;
        gzip_argv[1] = "-9";
        gzip_argv[2] = 0;
        exec_printcmd(archive_argv);
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
    archive_pid = fork();
    if (archive_pid < 0) {
        close(fds[0]); close(fds[1]); close(output_fd); unlink(out_apk);
        return 1;
    }
    if (archive_pid == 0) {
        close(fds[0]);
        if (dup2(fds[1], STDOUT_FILENO) < 0) _exit(127);
        close(fds[1]);
        close(output_fd);
        if (archive_cwd != 0 && chdir(archive_cwd) != 0) _exit(127);
        execvp(archive_argv[0], archive_argv);
        _exit(127);
    }
    gzip_pid = fork();
    if (gzip_pid < 0) {
        close(fds[0]); close(fds[1]); close(output_fd);
        wait_for_child(archive_pid);
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
    if (wait_for_child(archive_pid) != 0) result = 1;
    if (wait_for_child(gzip_pid) != 0) result = 1;
    if (result != 0) unlink(out_apk);
    return result;
}

int pkginfo_build_apk(const char *root_dir, const char *out_apk,
                      const Toolchain *tc) {
    strlist archive_args;
    char **archive_argv;
    size_t i;
    int result;
    const char *archive_program;
    const char *archive_cwd;
    const char *gzip_program;

    if (root_dir == 0 || out_apk == 0) return 1;
    if (tc != 0 && (tc->archive_create == 0 ||
                    tc->archive_create[0] == '\0' || tc->gzip == 0 ||
                    tc->archive_create_flags == 0 ||
                    tc->archive_create_flags[0] == '\0')) {
        fprintf(stderr, "rbuild: missing configured APK archive-create "
                "capability\n");
        return 1;
    }
    archive_program = tc == 0 ? "tar" : tc->archive_create;
    archive_cwd = tc == 0 ? 0 : root_dir;
    gzip_program = tc == 0 ? "gzip" : tc->gzip;
    strlist_init(&archive_args);
    strlist_push(&archive_args, archive_program);
    if (tc != 0)
        toolchain_expand_words(tc->archive_create_flags, "", &archive_args);
    if (tc != 0 && archive_args.count == 1) {
        fprintf(stderr, "rbuild: empty configured APK archive-create flags\n");
        strlist_free(&archive_args);
        return 1;
    }
    if (tc == 0) {
        strlist_push(&archive_args, "-C");
        strlist_push(&archive_args, root_dir);
        strlist_push(&archive_args, "-cf");
        strlist_push(&archive_args, "-");
    }
    strlist_push(&archive_args, ".");
    archive_argv = (char **)xmalloc((archive_args.count + 1) * sizeof(char *));
    for (i = 0; i < archive_args.count; i++)
        archive_argv[i] = archive_args.items[i];
    archive_argv[archive_args.count] = 0;
    result = run_apk_pipeline(out_apk, gzip_program, archive_cwd,
                              archive_argv);
    free(archive_argv);
    strlist_free(&archive_args);
    return result;
}
