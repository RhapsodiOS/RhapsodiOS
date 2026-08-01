#include "pkginfo.h"
#include "apk.h"
#include "exec.h"
#include "package.h"
#include "test.h"
#include "toolchain.h"
#include <errno.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

static char *slurp(const char *path) {
    FILE *f = fopen(path, "r");
    static char buf[4096];
    size_t n;
    if (!f) return 0;
    n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = '\0';
    fclose(f);
    return buf;
}

static void make_scratch(char *path, size_t capacity) {
    int attempt;
    for (attempt = 0; attempt < 100; attempt++) {
        sprintf(path, "/tmp/rbuild-pkginfo-test-%ld-%ld-%d",
                (long)getpid(), (long)time(0), attempt);
        CHECK(strlen(path) + 1 <= capacity);
        if (mkdir(path, 0700) == 0) return;
        if (errno != EEXIST) break;
    }
    CHECK(0);
}

TEST(test_pkginfo_write) {
    Package p;
    char *out;
    package_init(&p);
    package_set(&p.package, "gnumake");
    package_set(&p.version, "3.79");
    package_set(&p.architecture, "universal-apple-rhapsody");
    package_set(&p.description, "GNU make");
    package_set(&p.maintainer, "M <m@x>");
    package_set(&p.source, "gnumake");
    strlist_push(&p.build_depends, "cc");
    strlist_push(&p.build_depends, "gnumake");
    p.has_build_depends = 1;

    CHECK_INT(pkginfo_write(&p, "/tmp/rbtest.PKGINFO"), 0);
    out = slurp("/tmp/rbtest.PKGINFO");
    CHECK(out != 0);
    CHECK(strstr(out, "pkgname = gnumake\n") != 0);
    CHECK(strstr(out, "pkgver = 3.79\n") != 0);
    CHECK(strstr(out, "arch = universal-apple-rhapsody\n") != 0);
    CHECK(strstr(out, "builddepends = cc gnumake\n") != 0);
    package_free(&p);
    remove("/tmp/rbtest.PKGINFO");
}

TEST(test_build_apk_is_posix_ustar_and_extracts) {
    char scratch[128];
    char root[160];
    char output[160];
    char extracted[160];
    char wrapper[160];
    char log[160];
    char metadata[192];
    char payload[192];
    char extracted_payload[192];
    char expected[512];
    char real_tar[256];
    char closed_stdin_output[192];
    char closed_stdout_output[192];
    FILE *fp;
    Toolchain tc;
    pid_t pid;
    int status;

    make_scratch(scratch, sizeof(scratch));
    sprintf(root, "%s/root", scratch);
    sprintf(output, "%s/out.apk", scratch);
    sprintf(extracted, "%s/extracted", scratch);
    sprintf(wrapper, "%s/gnutar", scratch);
    sprintf(log, "%s/tar.log", scratch);
    sprintf(metadata, "%s/.PKGINFO", root);
    sprintf(payload, "%s/payload", root);
    sprintf(extracted_payload, "%s/payload", extracted);
    sprintf(closed_stdin_output, "%s/closed-stdin.apk", scratch);
    sprintf(closed_stdout_output, "%s/closed-stdout.apk", scratch);
    CHECK_INT(mkdir(root, 0700), 0);
    toolchain_init(&tc);
    CHECK_INT(toolchain_load(&tc, "toolchains/gcc-darwin.conf"), 0);
    CHECK_INT(toolchain_validate(&tc), 0);
    strcpy(real_tar, tc.tar);
    fp = fopen(wrapper, "w");
    CHECK(fp != 0);
    if (fp != 0) {
        fprintf(fp, "#!/bin/sh\nfor arg in \"$@\"; do echo \"$arg\"; done >> %s\n",
                log);
        fprintf(fp, "exec %s \"$@\"\n", real_tar);
        fclose(fp);
    }
    fp = fopen(metadata, "w");
    CHECK(fp != 0);
    if (fp != 0) { fputs("pkgname = integration\n", fp); fclose(fp); }
    fp = fopen(payload, "w");
    CHECK(fp != 0);
    if (fp != 0) { fputs("payload", fp); fclose(fp); }
    CHECK_INT(chmod(wrapper, 0755), 0);
    free(tc.tar);
    tc.tar = xstrdup(wrapper);
    free(tc.tar_create_flags);
    tc.tar_create_flags = xstrdup("--posix --numeric-owner");
    CHECK_INT(pkginfo_build_apk(root, output, &tc), 0);
    sprintf(expected, "--posix\n--numeric-owner\n-C\n%s\n-cf\n-\n.\n",
            root);
    CHECK_STR(slurp(log), expected);
    free(tc.tar);
    tc.tar = xstrdup(real_tar);
    CHECK_INT(apk_validate(output, &tc), 0);
    CHECK_INT(apk_extract(output, extracted, &tc), 0);
    CHECK_STR(slurp(extracted_payload), "payload");

    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(STDIN_FILENO);
        _exit(pkginfo_build_apk(root, closed_stdin_output, &tc));
    }
    CHECK(waitpid(pid, &status, 0) == pid && status == 0);
    CHECK_INT(apk_validate(closed_stdin_output, &tc), 0);

    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(STDOUT_FILENO);
        _exit(pkginfo_build_apk(root, closed_stdout_output, &tc));
    }
    CHECK(waitpid(pid, &status, 0) == pid && status == 0);
    CHECK_INT(apk_validate(closed_stdout_output, &tc), 0);

    free(tc.tar_create_flags);
    tc.tar_create_flags = 0;
    CHECK_INT(pkginfo_build_apk(root, output, &tc), 1);
    tc.tar_create_flags = xstrdup("   ");
    CHECK_INT(pkginfo_build_apk(root, output, &tc), 1);
    toolchain_free(&tc);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_build_apk_without_toolchain_uses_legacy_generic_argv) {
    char scratch[128];
    char root[160];
    char output[160];
    char tar_wrapper[160];
    char gzip_wrapper[160];
    char tar_log[160];
    char metadata[192];
    char expected[512];
    char path_value[512];
    char *saved_path;
    FILE *fp;
    struct stat st;
    Toolchain configured;

    make_scratch(scratch, sizeof(scratch));
    sprintf(root, "%s/root", scratch);
    sprintf(output, "%s/legacy.apk", scratch);
    sprintf(tar_wrapper, "%s/tar", scratch);
    sprintf(gzip_wrapper, "%s/gzip", scratch);
    sprintf(tar_log, "%s/tar.log", scratch);
    sprintf(metadata, "%s/.PKGINFO", root);
    CHECK_INT(mkdir(root, 0700), 0);
    toolchain_init(&configured);
    CHECK_INT(toolchain_load(&configured, "toolchains/gcc-darwin.conf"), 0);
    fp = fopen(tar_wrapper, "w");
    CHECK(fp != 0);
    if (fp != 0) {
        fprintf(fp, "#!/bin/sh\nfor arg in \"$@\"; do echo \"$arg\"; done >> %s\n",
                tar_log);
        fprintf(fp, "exec %s \"$@\"\n", configured.tar);
        fclose(fp);
    }
    fp = fopen(gzip_wrapper, "w");
    CHECK(fp != 0);
    if (fp != 0) {
        fprintf(fp, "#!/bin/sh\nexec %s \"$@\"\n", configured.gzip);
        fclose(fp);
    }
    CHECK_INT(chmod(tar_wrapper, 0755), 0);
    CHECK_INT(chmod(gzip_wrapper, 0755), 0);
    fp = fopen(metadata, "w");
    CHECK(fp != 0);
    if (fp != 0) { fputs("pkgname = legacy\n", fp); fclose(fp); }
    saved_path = xstrdup(getenv("PATH") != 0 ? getenv("PATH") : "");
    sprintf(path_value, "%s:%s", scratch, saved_path);
    CHECK_INT(setenv("PATH", path_value, 1), 0);
    CHECK_INT(pkginfo_build_apk(root, output, 0), 0);
    CHECK_INT(setenv("PATH", saved_path, 1), 0);
    free(saved_path);
    sprintf(expected, "-C\n%s\n-cf\n-\n.\n", root);
    CHECK_STR(slurp(tar_log), expected);
    CHECK(lstat(output, &st) == 0 && st.st_size > 0);
    toolchain_free(&configured);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

static void run_all(void) {
    RUN(test_pkginfo_write);
    RUN(test_build_apk_is_posix_ustar_and_extracts);
    RUN(test_build_apk_without_toolchain_uses_legacy_generic_argv);
}

TEST_MAIN()
