#include "toolchain.h"
#include "test.h"

#include <stdio.h>

static void write_profile(const char *path, int include_target_cc) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fputs("profile=test-gcc\n", fp);
    fputs("build_cc=/usr/bin/cc\n", fp);
    if (include_target_cc) fputs("target_cc=/opt/cross/bin/gcc\n", fp);
    fputs("target_ar=/opt/cross/bin/ar\n", fp);
    fputs("target_ranlib=/opt/cross/bin/ranlib\n", fp);
    fputs("make=/usr/bin/make\n", fp);
    fputs("shell=/bin/sh\n", fp);
    fputs("tar=/usr/bin/tar\n", fp);
    fputs("gzip=/usr/bin/gzip\n", fp);
    fputs("rsync=/usr/bin/rsync\n", fp);
    fputs("path=/opt/cross/bin:/usr/bin:/bin\n", fp);
    fputs("arch_flags=-arch ppc\n", fp);
    fputs("cpp_flags=-nostdinc -I@SYSROOT@/System/Headers\n", fp);
    fputs("ld_flags=-Wl,-syslibroot,@SYSROOT@\n", fp);
    fputs("ln=/bin/ln\n", fp);
    fclose(fp);
}

static void write_text(const char *path, const char *text) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fputs(text, fp);
    fclose(fp);
}

TEST(test_loads_and_expands_profile) {
    const char *path = "/tmp/rbuild-toolchain.conf";
    Toolchain tc;
    strlist words;

    write_profile(path, 1);
    toolchain_init(&tc);
    CHECK_INT(toolchain_load(&tc, path), 0);
    CHECK_INT(toolchain_validate(&tc), 0);
    CHECK_STR(tc.target_cc, "/opt/cross/bin/gcc");

    strlist_init(&words);
    toolchain_expand_words("-nostdinc -I@SYSROOT@/System/Headers",
                           "/target", &words);
    CHECK_INT(words.count, 2);
    CHECK_STR(words.items[0], "-nostdinc");
    CHECK_STR(words.items[1], "-I/target/System/Headers");
    strlist_free(&words);
    toolchain_free(&tc);
    remove(path);
}

TEST(test_validation_rejects_missing_target_cc) {
    const char *path = "/tmp/rbuild-toolchain.conf";
    Toolchain tc;

    write_profile(path, 0);
    toolchain_init(&tc);
    CHECK_INT(toolchain_load(&tc, path), 0);
    CHECK_INT(toolchain_validate(&tc), 1);
    toolchain_free(&tc);
    remove(path);
}

TEST(test_expand_null_value_is_empty) {
    strlist words;

    strlist_init(&words);
    toolchain_expand_words(0, "/target", &words);
    CHECK_INT(words.count, 0);
    strlist_free(&words);
}

TEST(test_malformed_line_fails) {
    const char *path = "/tmp/rbuild-toolchain.conf";
    Toolchain tc;

    write_text(path, "malformed line\n");
    toolchain_init(&tc);
    CHECK_INT(toolchain_load(&tc, path), 1);
    toolchain_free(&tc);
    remove(path);
}

TEST(test_unknown_key_fails) {
    const char *path = "/tmp/rbuild-toolchain.conf";
    Toolchain tc;

    write_text(path, "unknown_key=value\n");
    toolchain_init(&tc);
    CHECK_INT(toolchain_load(&tc, path), 1);
    toolchain_free(&tc);
    remove(path);
}

TEST(test_duplicate_key_fails) {
    const char *path = "/tmp/rbuild-toolchain.conf";
    Toolchain tc;

    write_text(path, "profile=first\nprofile=second\n");
    toolchain_init(&tc);
    CHECK_INT(toolchain_load(&tc, path), 1);
    toolchain_free(&tc);
    remove(path);
}

static void run_all(void) {
    RUN(test_loads_and_expands_profile);
    RUN(test_validation_rejects_missing_target_cc);
    RUN(test_expand_null_value_is_empty);
    RUN(test_malformed_line_fails);
    RUN(test_unknown_key_fails);
    RUN(test_duplicate_key_fails);
}

TEST_MAIN()
