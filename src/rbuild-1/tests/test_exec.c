#include "exec.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

TEST(test_checkret_strings) {
    char *a = exec_checkret(0);
    char *b = exec_checkret(2 << 8);      /* exit status 2 */
    CHECK_STR(a, "exited successfully");
    CHECK_STR(b, "failed with status 2");
    free(a); free(b);
}

TEST(test_run_true_false) {
    char *ok[] = { "true", 0 };
    char *bad[] = { "false", 0 };
    CHECK_INT(exec_run(ok), 0);
    CHECK(exec_run(bad) != 0);
}

TEST(test_dry_run) {
    char *cmd[] = { "false", 0 };
    exec_dry_run = 1;
    CHECK_INT(exec_run(cmd), 0);   /* not actually run */
    exec_dry_run = 0;
}

TEST(test_run_tees_output_to_log) {
    char path[128];
    char data[128];
    char *cmd[] = { "/bin/sh", "-c", "printf logged-output", 0 };
    FILE *f;
    size_t n;

    sprintf(path, "/tmp/rbuild-exec-%ld.log", (long)getpid());
    remove(path);
    CHECK_INT(exec_set_log(path), 0);
    CHECK_INT(exec_run(cmd), 0);
    exec_clear_log();
    f = fopen(path, "r");
    CHECK(f != 0);
    n = fread(data, 1, sizeof(data) - 1, f);
    data[n] = '\0';
    fclose(f);
    CHECK(strstr(data, "command: /bin/sh -c \"printf logged-output\"") != 0);
    CHECK(strstr(data, "logged-output") != 0);
    CHECK(strstr(data, "status: exited successfully") != 0);
    remove(path);
}

TEST(test_log_setup_failure_and_clear) {
    char path[128];
    char *cmd[] = { "/bin/sh", "-c", "printf not-logged", 0 };

    CHECK_INT(exec_set_log("/no/such/rbuild/directory/log"), 1);
    sprintf(path, "/tmp/rbuild-exec-clear-%ld.log", (long)getpid());
    remove(path);
    CHECK_INT(exec_set_log(path), 0);
    exec_clear_log();
    CHECK_INT(exec_run(cmd), 0);
    {
        FILE *f = fopen(path, "r");
        CHECK(f != 0);
        CHECK_INT(fgetc(f), EOF);
        fclose(f);
    }
    remove(path);
}

TEST(test_logged_child_failure_is_preserved) {
    char path[128];
    char *cmd[] = { "/bin/sh", "-c", "printf child-failed; exit 7", 0 };
    sprintf(path, "/tmp/rbuild-exec-fail-%ld.log", (long)getpid());
    remove(path);
    CHECK_INT(exec_set_log(path), 0);
    CHECK(exec_run(cmd) != 0);
    exec_clear_log();
    {
        char data[256];
        FILE *f = fopen(path, "r");
        size_t n;
        CHECK(f != 0);
        n = fread(data, 1, sizeof(data) - 1, f);
        data[n] = '\0';
        fclose(f);
        CHECK(strstr(data, "child-failed") != 0);
        CHECK(strstr(data, "status: failed with status 7") != 0);
    }
    remove(path);
}

TEST(test_logging_with_closed_standard_descriptors) {
    char path[128];
    char *cmd[] = { "/bin/sh", "-c", "printf low-fd-output", 0 };
    int saved[3];
    int i;
    FILE *f;
    char data[256];
    size_t n;

    sprintf(path, "/tmp/rbuild-exec-lowfd-%ld.log", (long)getpid());
    remove(path);
    for (i = 0; i < 3; i++) saved[i] = dup(i);
    for (i = 0; i < 3; i++) close(i);
    CHECK_INT(exec_set_log(path), 0);
    CHECK_INT(exec_run(cmd), 0);
    exec_clear_log();
    for (i = 0; i < 3; i++) {
        if (saved[i] >= 0) { dup2(saved[i], i); close(saved[i]); }
    }
    f = fopen(path, "r");
    CHECK(f != 0);
    n = fread(data, 1, sizeof(data) - 1, f);
    data[n] = '\0';
    fclose(f);
    CHECK(strstr(data, "low-fd-output") != 0);
    remove(path);
}

TEST(test_broken_parent_stdout_still_finishes_log) {
    char path[128];
    int fds[2];
    pid_t pid;
    int status;
    FILE *f;
    char data[256];
    size_t n;

    sprintf(path, "/tmp/rbuild-exec-epipe-%ld.log", (long)getpid());
    remove(path);
    CHECK_INT(pipe(fds), 0);
    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        char *cmd[] = { "/bin/sh", "-c", "printf survives-epipe", 0 };
        close(fds[0]);
        dup2(fds[1], STDOUT_FILENO);
        close(fds[1]);
        if (exec_set_log(path) != 0) _exit(10);
        if (exec_run(cmd) != 0) _exit(11);
        exec_clear_log();
        _exit(0);
    }
    close(fds[0]); close(fds[1]);
    waitpid(pid, &status, 0);
    CHECK(WIFEXITED(status));
    CHECK_INT(WEXITSTATUS(status), 0);
    f = fopen(path, "r");
    CHECK(f != 0);
    n = fread(data, 1, sizeof(data) - 1, f);
    data[n] = '\0';
    fclose(f);
    CHECK(strstr(data, "survives-epipe") != 0);
    remove(path);
}

static void run_all(void) {
    RUN(test_checkret_strings);
    RUN(test_run_true_false);
    RUN(test_dry_run);
    RUN(test_run_tees_output_to_log);
    RUN(test_log_setup_failure_and_clear);
    RUN(test_logged_child_failure_is_preserved);
    RUN(test_logging_with_closed_standard_descriptors);
    RUN(test_broken_parent_stdout_still_finishes_log);
}

TEST_MAIN()
