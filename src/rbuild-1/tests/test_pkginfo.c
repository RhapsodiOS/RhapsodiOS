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
#include <fcntl.h>
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

static int block_is_zero(const unsigned char *block) {
    size_t i;
    for (i = 0; i < 512; i++) if (block[i] != 0) return 0;
    return 1;
}

static unsigned long tar_octal(const unsigned char *text, size_t length) {
    unsigned long value = 0;
    size_t i;
    for (i = 0; i < length && (text[i] == ' ' || text[i] == '\0'); i++) { }
    for (; i < length && text[i] >= '0' && text[i] <= '7'; i++)
        value = value * 8 + (unsigned long)(text[i] - '0');
    return value;
}

static int gzip_decompress(const char *gzip, const char *apk,
                           const char *raw) {
    pid_t pid = fork();
    int status;
    if (pid < 0) return 1;
    if (pid == 0) {
        int fd = open(raw, O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd < 0 || dup2(fd, STDOUT_FILENO) < 0) _exit(127);
        close(fd);
        execl(gzip, gzip, "-dc", apk, (char *)0);
        _exit(127);
    }
    return waitpid(pid, &status, 0) != pid || !WIFEXITED(status) ||
           WEXITSTATUS(status) != 0;
}

static int strict_ustar_types(const char *raw) {
    unsigned char block[512];
    FILE *fp = fopen(raw, "rb");
    size_t count;
    if (fp == 0) return 1;
    while ((count = fread(block, 1, sizeof(block), fp)) != 0) {
        unsigned char type;
        unsigned long size;
        unsigned long skip;
        char name[101];
        if (count != sizeof(block)) {
            fclose(fp);
            return 1;
        }
        if (block_is_zero(block)) break;
        type = block[156];
        if (!(type == '\0' || (type >= '0' && type <= '5'))) {
            fclose(fp);
            return 1;
        }
        memcpy(name, block, 100);
        name[100] = '\0';
        if (strcmp(name, "././@LongLink") == 0) {
            fclose(fp);
            return 1;
        }
        size = tar_octal(block + 124, 12);
        skip = ((size + 511) / 512) * 512;
        if (skip != 0 && fseek(fp, (long)skip, SEEK_CUR) != 0) {
            fclose(fp);
            return 1;
        }
    }
    fclose(fp);
    return 0;
}

static int physical_directory(const char *path, char *physical,
                              size_t capacity) {
    char saved[512];
    int result = 1;
    if (getcwd(saved, sizeof(saved)) == 0) return 1;
    if (chdir(path) != 0) return 1;
    if (getcwd(physical, capacity) != 0) result = 0;
    if (chdir(saved) != 0) return 1;
    return result;
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
    package_set(&p.license, "unknown");
    package_set(&p.url, "http://example.com/make");
    CHECK_INT(pkginfo_write(&p, "/tmp/rbtest.PKGINFO"), 0);
    out = slurp("/tmp/rbtest.PKGINFO");
    CHECK(out != 0);
    CHECK(strstr(out, "pkgname = gnumake\n") != 0);
    CHECK(strstr(out, "pkgver = 3.79\n") != 0);
    CHECK(strstr(out, "arch = universal-apple-rhapsody\n") != 0);
    CHECK(strstr(out, "makedepends = cc gnumake\n") != 0);
    CHECK(strstr(out, "license = unknown\n") != 0);
    CHECK(strstr(out, "url = http://example.com/make\n") != 0);
    CHECK(strstr(out, "builddepends =") == 0);
    CHECK(strstr(out, "pkgrel") == 0);

    package_set(&p.license, 0);
    CHECK_INT(pkginfo_write(&p, "/tmp/rbtest.PKGINFO"), 0);
    out = slurp("/tmp/rbtest.PKGINFO");
    CHECK(out != 0);
    CHECK(strstr(out, "license = unknown\n") != 0);
    package_free(&p);
    remove("/tmp/rbtest.PKGINFO");
}

TEST(test_build_apk_is_posix_ustar_and_extracts) {
    char scratch[128];
    char root[160];
    char root_alias[160];
    char output[160];
    char extracted[160];
    char wrapper[160];
    char log[160];
    char metadata[192];
    char payload[192];
    char extracted_payload[192];
    char extracted_long_payload[560];
    char expected[512];
    char real_archive_create[256];
    char raw_archive[192];
    char long_dir[512];
    char long_payload[560];
    char physical_root[512];
    char closed_stdin_output[192];
    char closed_stdout_output[192];
    FILE *fp;
    Toolchain tc;
    pid_t pid;
    int status;

    make_scratch(scratch, sizeof(scratch));
    sprintf(root, "%s/root", scratch);
    sprintf(root_alias, "%s/root-alias", scratch);
    sprintf(output, "%s/out.apk", scratch);
    sprintf(extracted, "%s/extracted", scratch);
    sprintf(wrapper, "%s/gnutar", scratch);
    sprintf(log, "%s/tar.log", scratch);
    sprintf(metadata, "%s/.PKGINFO", root);
    sprintf(payload, "%s/payload", root);
    sprintf(extracted_payload, "%s/payload", extracted);
    sprintf(closed_stdin_output, "%s/closed-stdin.apk", scratch);
    sprintf(closed_stdout_output, "%s/closed-stdout.apk", scratch);
    sprintf(raw_archive, "%s/out.tar", scratch);
    CHECK_INT(mkdir(root, 0700), 0);
    CHECK_INT(symlink(root, root_alias), 0);
    toolchain_init(&tc);
    CHECK_INT(toolchain_load(&tc, "toolchains/gcc-darwin-ppc.conf"), 0);
    CHECK_INT(toolchain_validate(&tc), 0);
    strcpy(real_archive_create, tc.archive_create);
    fp = fopen(wrapper, "w");
    CHECK(fp != 0);
    if (fp != 0) {
        fprintf(fp, "#!/bin/sh\npwd > %s\nfor arg in \"$@\"; do echo \"$arg\"; done >> %s\n",
                log, log);
        fprintf(fp, "exec %s \"$@\"\n", real_archive_create);
        fclose(fp);
    }
    fp = fopen(metadata, "w");
    CHECK(fp != 0);
    if (fp != 0) { fputs("pkgname = integration\n", fp); fclose(fp); }
    fp = fopen(payload, "w");
    CHECK(fp != 0);
    if (fp != 0) { fputs("payload", fp); fclose(fp); }
    sprintf(long_dir, "%s/usr/local/share/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", root);
    CHECK_INT(exec_runv("/bin/mkdir", "-p", long_dir, (char *)0), 0);
    sprintf(long_payload, "%s/long-path-payload", long_dir);
    CHECK(strlen(long_payload + strlen(root) + 1) > 100);
    fp = fopen(long_payload, "w");
    CHECK(fp != 0);
    if (fp != 0) { fputs("long payload", fp); fclose(fp); }
    CHECK_INT(chmod(wrapper, 0755), 0);
    free(tc.archive_create);
    tc.archive_create = xstrdup(wrapper);
    free(tc.archive_create_flags);
    tc.archive_create_flags = xstrdup("-w -x ustar");
    CHECK_INT(pkginfo_build_apk(root_alias, output, &tc), 0);
    CHECK_INT(physical_directory(root_alias, physical_root,
                                 sizeof(physical_root)), 0);
    sprintf(expected, "%s\n-w\n-x\nustar\n.\n", physical_root);
    CHECK_STR(slurp(log), expected);
    free(tc.archive_create);
    tc.archive_create = xstrdup(real_archive_create);
    CHECK_INT(gzip_decompress(tc.gzip, output, raw_archive), 0);
    CHECK_INT(strict_ustar_types(raw_archive), 0);
    CHECK_INT(apk_validate(output, &tc), 0);
    CHECK_INT(apk_extract(output, extracted, &tc), 0);
    CHECK_STR(slurp(extracted_payload), "payload");
    sprintf(extracted_long_payload,
            "%s/usr/local/share/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/long-path-payload",
            extracted);
    CHECK_STR(slurp(extracted_long_payload), "long payload");

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

    free(tc.archive_create);
    tc.archive_create = 0;
    CHECK_INT(pkginfo_build_apk(root, output, &tc), 1);
    tc.archive_create = xstrdup(real_archive_create);
    free(tc.archive_create_flags);
    tc.archive_create_flags = 0;
    CHECK_INT(pkginfo_build_apk(root, output, &tc), 1);
    tc.archive_create_flags = xstrdup("   ");
    CHECK_INT(pkginfo_build_apk(root, output, &tc), 1);
    toolchain_free(&tc);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

/* Without a toolchain the APK must still pass rbuild's own validator. A bare
   tar may be GNU tar, as on the DR2 build guest, whose "ustar  " headers
   apk_validate refuses, so it sits first on PATH here. */
TEST(test_build_apk_without_toolchain_passes_validation) {
    char scratch[128];
    char root[160];
    char output[160];
    char tar_wrapper[160];
    char metadata[192];
    char path_value[512];
    char *saved_path;
    FILE *fp;
    Toolchain fallback;

    make_scratch(scratch, sizeof(scratch));
    sprintf(root, "%s/root", scratch);
    sprintf(output, "%s/legacy.apk", scratch);
    sprintf(tar_wrapper, "%s/tar", scratch);
    sprintf(metadata, "%s/.PKGINFO", root);
    CHECK_INT(mkdir(root, 0700), 0);
    fp = fopen(tar_wrapper, "w");
    CHECK(fp != 0);
    if (fp != 0) {
        fputs("#!/bin/sh\nexec /usr/bin/gnutar \"$@\"\n", fp);
        fclose(fp);
    }
    CHECK_INT(chmod(tar_wrapper, 0755), 0);
    fp = fopen(metadata, "w");
    CHECK(fp != 0);
    if (fp != 0) { fputs("pkgname = legacy\n", fp); fclose(fp); }
    saved_path = xstrdup(getenv("PATH") != 0 ? getenv("PATH") : "");
    sprintf(path_value, "%s:%s", scratch, saved_path);
    CHECK_INT(setenv("PATH", path_value, 1), 0);
    CHECK_INT(pkginfo_build_apk(root, output, 0), 0);
    CHECK_INT(setenv("PATH", saved_path, 1), 0);
    free(saved_path);
    toolchain_init(&fallback);
    fallback.tar = xstrdup("pax");
    fallback.gzip = xstrdup("gzip");
    CHECK_INT(apk_validate(output, &fallback), 0);
    toolchain_free(&fallback);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

static void write_file(const char *path, const char *body) {
    FILE *f = fopen(path, "w");
    CHECK(f != 0);
    if (f) { fputs(body, f); fclose(f); }
}

TEST(test_pkginfo_read_basic) {
    Package p;
    mkdir("/tmp/rb-pkginfo-read", 0700);
    write_file("/tmp/rb-pkginfo-read/pkginfo",
        "pkgname = grep\n"
        "pkgver = 2.1\n"
        "pkgdesc = Get-Regular-Expression-and-Print tool\n"
        "maintainer = Darwin Developers <d@x>\n"
        "license = unknown\n"
        "url = http://example.com/grep\n"
        "makedepends = build-base, libstreams-hdrs architecture-hdrs\n"
        "# comment\n"
        "\n"
        "vendor = ignored\n");
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/pkginfo"), 0);
    CHECK_STR(p.package, "grep");
    CHECK_STR(p.version, "2.1");
    CHECK_STR(p.description, "Get-Regular-Expression-and-Print tool");
    CHECK_STR(p.maintainer, "Darwin Developers <d@x>");
    CHECK_STR(p.license, "unknown");
    CHECK_STR(p.url, "http://example.com/grep");
    CHECK_INT(p.has_build_depends, 1);
    CHECK_INT(p.build_depends.count, 3);
    CHECK_STR(p.build_depends.items[0], "build-base");
    CHECK_STR(p.build_depends.items[2], "architecture-hdrs");
    CHECK(p.architecture == 0 || p.architecture[0] == '\0');
    package_free(&p);
}

TEST(test_pkginfo_read_arch_makedepends) {
    Package p;
    mkdir("/tmp/rb-pkginfo-read", 0700);
    write_file("/tmp/rb-pkginfo-read/archdeps",
        "pkgname = kernel\n"
        "pkgver = 1\n"
        "makedepends = build-base, driverkit\n"
        "makedepends_ppc = drvpexpert\n"
        "makedepends_i386 = foo, bar\n");
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/archdeps"), 0);
    CHECK_INT(p.build_depends.count, 2);
    CHECK_INT(p.build_depends_ppc.count, 1);
    if (p.build_depends_ppc.count == 1)
        CHECK_STR(p.build_depends_ppc.items[0], "drvpexpert");
    CHECK_INT(p.build_depends_i386.count, 2);
    if (p.build_depends_i386.count == 2)
        CHECK_STR(p.build_depends_i386.items[1], "bar");
    package_free(&p);
}

TEST(test_pkginfo_write_arch_makedepends) {
    Package p;
    char *out;
    package_init(&p);
    package_set(&p.package, "kernel");
    package_set(&p.version, "1");
    strlist_push(&p.build_depends_ppc, "drvpexpert");
    CHECK_INT(pkginfo_write(&p, "/tmp/rbtest.PKGINFO"), 0);
    out = slurp("/tmp/rbtest.PKGINFO");
    CHECK(out != 0);
    if (out) {
        CHECK(strstr(out, "makedepends_ppc = drvpexpert\n") != 0);
        CHECK(strstr(out, "makedepends_i386") == 0);
    }
    package_free(&p);
}

TEST(test_pkginfo_read_missing_file) {
    Package p;
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/no-such"), 1);
    package_free(&p);
}

TEST(test_pkginfo_read_missing_pkgname) {
    Package p;
    write_file("/tmp/rb-pkginfo-read/nopkg", "pkgver = 1\n");
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/nopkg"), 2);
    package_free(&p);
}

TEST(test_pkginfo_read_invalid_arch) {
    Package p;
    write_file("/tmp/rb-pkginfo-read/badarch",
        "pkgname = bad\npkgver = 1\narch = m68k\n");
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/badarch"), 2);
    package_free(&p);
}

static void run_all(void) {
    RUN(test_pkginfo_write);
    RUN(test_pkginfo_read_basic);
    RUN(test_pkginfo_read_arch_makedepends);
    RUN(test_pkginfo_write_arch_makedepends);
    RUN(test_pkginfo_read_missing_file);
    RUN(test_pkginfo_read_missing_pkgname);
    RUN(test_pkginfo_read_invalid_arch);
    RUN(test_build_apk_is_posix_ustar_and_extracts);
    RUN(test_build_apk_without_toolchain_passes_validation);
}

TEST_MAIN()
