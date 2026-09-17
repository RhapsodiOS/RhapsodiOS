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

static void replace_required_with_code(void) {
    unlink(replay_artifact);
    rename(replay_target, replay_artifact);
}

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
    unsigned char code[28];

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
    sprintf(replay_artifact, "%s/foo-hdrs-1.0-ppc.apk", repo);
    sprintf(replay_target, "%s/outside.apk", scratch);
    sprintf(state_file, "%s/projects/foo-1.0-ppc-headers.done", state);
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
              "arch = ppc-apple-rhapsody\n", f);
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
    tc.target_arch = xstrdup("ppc");
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
    /* A regular replacement with matching metadata still needs payload checks. */
    unlink(replay_artifact);
    sprintf(command,"(cd %s && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > %s",content,replay_artifact);
    CHECK_INT(system(command),0);
    memset(code,0,sizeof(code));code[0]=0xfe;code[1]=0xed;code[2]=0xfa;code[3]=0xce;code[7]=7;code[15]=1;
    sprintf(control,"%s/tool",content);
    f=fopen(control,"wb");CHECK(f!=0);
    if(f){fwrite(code,1,sizeof(code),f);fclose(f);}
    sprintf(command,"(cd %s && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > %s",content,replay_target);
    CHECK_INT(system(command),0);
    runner_test_set_before_replay_hook(replace_required_with_code);
    CHECK(runner_manifest(manifest,repo,repo,&opt)!=0);
    runner_test_set_before_replay_hook(0);
    CHECK(access(state_file,F_OK)!=0);
    CHECK(access(root,F_OK)!=0);
    /* With no state record, validated seed artifacts can establish new state. */
    unlink(control); /* The mismatched code member from the replay race. */
    sprintf(command, "(cd %s && /usr/bin/gnutar --posix -cf - .) | "
            "/usr/bin/gzip -9 > %s", content, replay_artifact);
    CHECK_INT(system(command), 0);
    CHECK_INT(runner_manifest(manifest, repo, repo, &opt), 0);
    f = fopen(state_file, "r");
    CHECK(f != 0);
    if (f) {
        char saved[2048], current[2048];
        size_t n = fread(saved, 1, sizeof(saved)-1, f);
        saved[n] = 0; fclose(f);
        CHECK(strstr(saved, "format=3\n") != 0);
        CHECK(strstr(saved, "architecture_policy=1\n") != 0);
        CHECK(strstr(saved, "effective_architecture=ppc-apple-rhapsody\n") != 0);
        sprintf(control, "%s/dpkg/control", source);
        f = fopen(control, "a"); CHECK(f != 0);
        if (f) { fputs("Architecture: ppc\n", f); fclose(f); }
        /* Default universal source and explicit ppc resolve to the same
         * canonical bootstrap architecture, so no rebuild is needed. */
        CHECK_INT(runner_manifest(manifest, repo, repo, &opt), 0);
        f = fopen(state_file, "r"); CHECK(f != 0);
        if (f) {
            n = fread(current, 1, sizeof(current)-1, f);
            current[n] = 0; fclose(f);
            CHECK_STR(current, saved);
        }
        f = fopen(control, "w"); CHECK(f != 0);
        if (f) {
            fputs("Package: foo\nVersion: 1.0\nArchitecture: i386\n", f);
            fclose(f);
        }
        CHECK(runner_manifest(manifest, repo, repo, &opt) != 0);
        CHECK(access(replay_artifact, F_OK) == 0);
        sprintf(control, "%s.invalid", replay_artifact);
        CHECK(access(control, F_OK) != 0);
        f = fopen(state_file, "r"); CHECK(f != 0);
        if (f) {
            n = fread(current, 1, sizeof(current)-1, f);
            current[n] = 0; fclose(f);
            CHECK_STR(current, saved);
        }
    }
    toolchain_free(&tc);
    sprintf(command, "rm -rf %s", scratch);
    system(command);
}

TEST(test_kernel_architecture_controls_build_commands) {
    static const char *projects[] = {
        "driverkit-3", "driverTools-1", "kernload-1",
        "drivers-i386/bus/drvPExpert", "kernel-7", "drvBPF", 0
    };
    char path[256], command[512], output[65536];
    FILE *f;
    int i, drivers, saved_stdout, rc;
    size_t n;
    CHECK_INT(system("mkdir -p /tmp/rbuild-kernel-policy/repo /tmp/rbuild-kernel-policy/rbuild-1"), 0);
    f = fopen("/tmp/rbuild-kernel-policy/rbuild-1/kernel-drivers-blacklist.json", "w");
    CHECK(f != 0);
    if (!f) return;
    fputs("{\"skip\": []}\n", f); fclose(f);
    for (i = 0; projects[i]; i++) {
        sprintf(command, "mkdir -p /tmp/rbuild-kernel-policy/%s/dpkg", projects[i]);
        CHECK_INT(system(command), 0);
        sprintf(path, "/tmp/rbuild-kernel-policy/%s/dpkg/control", projects[i]);
        f = fopen(path, "w");
        CHECK(f != 0);
        if (!f) return;
        fprintf(f, "Package: policy%d\nVersion: 1.0\nDescription: policy\nBuild-Depends:\n", i);
        fclose(f);
    }
    for (drivers = 0; drivers < 2; drivers++) {
        f = tmpfile();
        CHECK(f != 0);
        if (!f) return;
        fflush(stdout); saved_stdout = dup(1); dup2(fileno(f), 1);
        exec_dry_run = 1;
        rc = drivers ? runner_kerneldrivers("/tmp/rbuild-kernel-policy",
                           "/tmp/rbuild-kernel-policy/repo",
                           "/tmp/rbuild-kernel-policy/repo", "i386", 0) :
             runner_kernel("/tmp/rbuild-kernel-policy", "/tmp/rbuild-kernel-policy/repo",
                           "/tmp/rbuild-kernel-policy/repo", "i386", 0);
        fflush(stdout); dup2(saved_stdout, 1); close(saved_stdout);
        rewind(f); n = fread(output, 1, sizeof(output)-1, f); output[n] = '\0'; fclose(f);
        CHECK_INT(rc, 0);
        CHECK(strstr(output, "RC_ARCHS=i386") != 0);
        CHECK(strstr(output, "RC_ppc= ") != 0);
        CHECK(strstr(output, "-arch ppc") == 0);
        sprintf(path, "/tmp/rbuild-kernel-policy/%s/dpkg/control",
                drivers ? "drvBPF" : "driverkit-3");
        f = fopen(path, "a"); CHECK(f != 0);
        if (f) { fputs("Architecture: ppc\n", f); fclose(f); }
        f = tmpfile(); CHECK(f != 0);
        if (!f) return;
        fflush(stdout); saved_stdout = dup(1); dup2(fileno(f), 1);
        rc = drivers ? runner_kerneldrivers("/tmp/rbuild-kernel-policy",
                           "/tmp/rbuild-kernel-policy/repo",
                           "/tmp/rbuild-kernel-policy/repo", "i386", 0) :
             runner_kernel("/tmp/rbuild-kernel-policy", "/tmp/rbuild-kernel-policy/repo",
                           "/tmp/rbuild-kernel-policy/repo", "i386", 0);
        fflush(stdout); dup2(saved_stdout, 1); close(saved_stdout);
        rewind(f); n = fread(output, 1, sizeof(output)-1, f); output[n] = '\0'; fclose(f);
        CHECK(rc != 0);
        CHECK(strstr(output, "RC_ARCHS=") == 0);
    }
    exec_dry_run = 0;
    system("rm -rf /tmp/rbuild-kernel-policy");
}

TEST(test_kernel_skips_missing_core_source) {
    static const char *projects[] = {
        "driverkit-3", "driverTools-1", "kernload-1", "kernel-7", 0
    };
    char path[256], command[512], output[65536];
    FILE *f;
    int i, saved_stdout, rc;
    size_t n;
    CHECK_INT(system("mkdir -p /tmp/rbuild-kernel-skip/repo /tmp/rbuild-kernel-skip/rbuild-1"), 0);
    for (i = 0; projects[i]; i++) {
        sprintf(command, "mkdir -p /tmp/rbuild-kernel-skip/%s/dpkg", projects[i]);
        CHECK_INT(system(command), 0);
        sprintf(path, "/tmp/rbuild-kernel-skip/%s/dpkg/control", projects[i]);
        f = fopen(path, "w");
        CHECK(f != 0);
        if (!f) return;
        fprintf(f, "Package: skip%d\nVersion: 1.0\nDescription: skip\nBuild-Depends:\n", i);
        fclose(f);
    }
    f = tmpfile();
    CHECK(f != 0);
    if (!f) return;
    fflush(stdout); saved_stdout = dup(1); dup2(fileno(f), 1);
    exec_dry_run = 1;
    rc = runner_kernel("/tmp/rbuild-kernel-skip", "/tmp/rbuild-kernel-skip/repo",
                       "/tmp/rbuild-kernel-skip/repo", "i386", 0);
    fflush(stdout); dup2(saved_stdout, 1); close(saved_stdout);
    rewind(f); n = fread(output, 1, sizeof(output)-1, f); output[n] = '\0'; fclose(f);
    exec_dry_run = 0;
    CHECK_INT(rc, 0);
    CHECK(strstr(output, "skip missing kernel source drivers-i386/bus/drvPExpert") != 0);
    CHECK(strstr(output, "rbuild: kernel complete") != 0);
    system("rm -rf /tmp/rbuild-kernel-skip");
}

static void run_all(void) {
    RUN(test_kernel_architecture_controls_build_commands);
    RUN(test_kernel_skips_missing_core_source);
    RUN(test_buildpackage_scan_failure_clears_log);
    RUN(test_replay_rejects_required_artifact_replaced_by_symlink);
}

TEST_MAIN()
