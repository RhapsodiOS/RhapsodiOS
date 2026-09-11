#include "runner.h"
#include "exec.h"
#include "test.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char replay_artifact[256];
static char replay_target[256];

static void replace_required_artifact(void) {
    unlink(replay_artifact);
    symlink(replay_target, replay_artifact);
}

TEST(test_buildpackage_scan_failure_clears_log) {
    char path[128];
    char *cmd[] = { "/bin/sh", "-c", "printf after-failure", 0 };
    FILE *f;

    sprintf(path, "/tmp/rbuild-runner-log-%ld", (long)getpid());
    remove(path);
    CHECK_INT(exec_set_log(path), 0);
    CHECK(runner_buildpackage("invalid", "/no/such/source", "/tmp",
                              "all", "/tmp/rbuild-runner-output",
                              "/tmp/rbuild-state", 0) != 0);
    CHECK_INT(exec_run(cmd), 0);
    f = fopen(path, "r");
    CHECK(f != 0);
    CHECK_INT(fgetc(f), EOF);
    fclose(f);
    remove(path);
}

TEST(test_replay_rejects_required_artifact_replaced_by_symlink) {
    char scratch[160];
    char source[192];
    char content[192];
    char repo[192];
    char root[192];
    char state[192];
    char manifest[224];
    char profile[224];
    char control[256];
    char pkginfo[256];
    char state_file[256];
    char command[1024];
    FILE *f;
    Toolchain tc;
    RunnerOptions opt;

    sprintf(scratch, "/tmp/rbuild-runner-replay-%ld", (long)getpid());
    sprintf(source, "%s/foo", scratch);
    sprintf(content, "%s/content", scratch);
    sprintf(repo, "%s/repo", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(state, "%s/state", scratch);
    sprintf(manifest, "%s/Manifest", scratch);
    sprintf(profile, "%s/toolchain.conf", scratch);
    sprintf(control, "%s/dpkg/control", source);
    sprintf(pkginfo, "%s/.PKGINFO", content);
    sprintf(replay_artifact, "%s/foo-hdrs-1.0.apk", repo);
    sprintf(replay_target, "%s/outside.apk", scratch);
    sprintf(state_file, "%s/projects/foo-1.0-headers.done", state);
    sprintf(command, "rm -rf %s && mkdir -p %s/dpkg %s %s", scratch,
            source, content, repo);
    CHECK_INT(system(command), 0);
    f = fopen(control, "w");
    CHECK(f != 0);
    if (f != 0) {
        fputs("Package: foo\nVersion: 1.0\nDescription: replay race\n", f);
        fclose(f);
    }
    f = fopen(pkginfo, "w");
    CHECK(f != 0);
    if (f != 0) {
        fputs("pkgname = foo-hdrs\npkgver = 1.0\n"
              "arch = universal-apple-rhapsody\n", f);
        fclose(f);
    }
    sprintf(command,
            "(cd %s && /usr/bin/gnutar --posix -cf - .) | "
            "/usr/bin/gzip -9 > %s",
            content, replay_artifact);
    CHECK_INT(system(command), 0);
    f = fopen(replay_target, "w");
    CHECK(f != 0);
    if (f != 0) { fputs("outside-target", f); fclose(f); }
    f = fopen(manifest, "w");
    CHECK(f != 0);
    if (f != 0) { fprintf(f, "dir %s headers\n", source); fclose(f); }
    f = fopen(profile, "w");
    CHECK(f != 0);
    if (f != 0) { fputs("profile fixture\n", f); fclose(f); }

    toolchain_init(&tc);
    tc.profile = xstrdup("runner-test");
    tc.tar = xstrdup("/usr/bin/gnutar");
    tc.gzip = xstrdup("/usr/bin/gzip");
    memset(&opt, 0, sizeof(opt));
    opt.bootstrap = 1;
    opt.sysroot = root;
    opt.state_dir = state;
    opt.toolchain = &tc;
    opt.toolchain_file = profile;
    runner_test_set_before_replay_hook(replace_required_artifact);
    CHECK(runner_manifest(manifest, repo, repo, &opt) != 0);
    runner_test_set_before_replay_hook(0);
    CHECK(access(state_file, F_OK) != 0);
    CHECK(access(root, F_OK) != 0);
    f = fopen(replay_target, "r");
    CHECK(f != 0);
    if (f != 0) {
        char text[32];
        text[0] = '\0'; fgets(text, sizeof(text), f); fclose(f);
        CHECK_STR(text, "outside-target");
    }
    toolchain_free(&tc);
    sprintf(command, "rm -rf %s", scratch);
    system(command);
}

static void run_all(void) {
    RUN(test_buildpackage_scan_failure_clears_log);
    RUN(test_replay_rejects_required_artifact_replaced_by_symlink);
}

TEST_MAIN()
