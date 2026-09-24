#include "vendor.h"
#include "exec.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>

static void write_file(const char *path, const char *text) {
    FILE *f = fopen(path, "w");
    fputs(text, f);
    fclose(f);
}

static int file_is(const char *path, const char *want) {
    FILE *f = fopen(path, "r");
    char buf[256];
    size_t n;
    if (!f) return 0;
    n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = '\0';
    fclose(f);
    return strcmp(buf, want) == 0;
}

/* /tmp/rbtest_va/src: a project dir holding widget-1.0.tar.gz (top-level
   widget-1.0/ with hello.txt = "top\norig\n" and gone.txt = "bye\n");
   /tmp/rbtest_va/root: an empty SRCROOT. */
static void make_widget_project(void) {
    system("rm -rf /tmp/rbtest_va && "
           "mkdir -p /tmp/rbtest_va/src/patches /tmp/rbtest_va/root "
           "/tmp/rbtest_va/stage/widget-1.0 && "
           "printf 'top\\norig\\n' > /tmp/rbtest_va/stage/widget-1.0/hello.txt && "
           "echo bye > /tmp/rbtest_va/stage/widget-1.0/gone.txt && "
           "cd /tmp/rbtest_va/stage && /bin/pax -w -x ustar widget-1.0 | "
           "/usr/bin/gzip -c > /tmp/rbtest_va/src/widget-1.0.tar.gz");
}

static void widget_vendor(Vendor *v) {
    vendor_init(v);
    v->tarball = xstrdup("widget-1.0.tar.gz");
    v->directory = xstrdup("widget");
    v->patches = xstrdup("patches");
}

TEST(test_vendor_read_full) {
    Vendor v;
    system("rm -rf /tmp/rbtest_vd && mkdir -p /tmp/rbtest_vd/apk");
    write_file("/tmp/rbtest_vd/apk/vendor",
        "# upstream zlib\n"
        "tarball = zlib-1.1.3.tar.gz\n"
        "directory = zlib\n"
        "patches = series\n"
        "patchlevel = 2\n"
        "url = ignored\n");

    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 0);
    CHECK_STR(v.tarball, "zlib-1.1.3.tar.gz");
    CHECK_STR(v.directory, "zlib");
    CHECK_STR(v.patches, "series");
    CHECK_INT(v.patchlevel, 2);
    CHECK_INT(v.patches_explicit, 1);
    vendor_free(&v);
}

TEST(test_vendor_read_defaults) {
    Vendor v;
    write_file("/tmp/rbtest_vd/apk/vendor",
        "tarball = zlib-1.1.3.tar.gz\ndirectory = zlib\n");

    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 0);
    CHECK_STR(v.patches, "patches");
    CHECK_INT(v.patchlevel, 1);
    CHECK_INT(v.patches_explicit, 0);
    vendor_free(&v);
}

TEST(test_vendor_read_errors) {
    Vendor v;

    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/nope"), 1);
    vendor_free(&v);

    write_file("/tmp/rbtest_vd/apk/vendor", "directory = zlib\n");
    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 1);
    vendor_free(&v);

    write_file("/tmp/rbtest_vd/apk/vendor", "tarball = z.tar.gz\n");
    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 1);
    vendor_free(&v);
}

TEST(test_vendor_path) {
    char *p;
    write_file("/tmp/rbtest_vd/apk/vendor", "tarball = z.tar.gz\ndirectory = z\n");
    p = vendor_path("/tmp/rbtest_vd");
    CHECK_STR(p, "/tmp/rbtest_vd/apk/vendor");
    free(p);
    CHECK(vendor_path("/tmp/rbtest_vd/apk") == 0);
}

TEST(test_vendor_list_patches_sorted) {
    Vendor v;
    strlist out;

    /* created out of order on purpose */
    system("mkdir -p /tmp/rbtest_vd/patches && "
           "touch /tmp/rbtest_vd/patches/0002-second.patch "
           "/tmp/rbtest_vd/patches/0001-first.patch "
           "/tmp/rbtest_vd/patches/README");

    vendor_init(&v);
    v.tarball = xstrdup("z.tar.gz");
    v.directory = xstrdup("z");
    v.patches = xstrdup("patches");
    strlist_init(&out);
    CHECK_INT(vendor_list_patches(&v, "/tmp/rbtest_vd", &out), 0);
    CHECK_INT(out.count, 2);   /* README is not a .patch */
    CHECK_STR(out.items[0], "/tmp/rbtest_vd/patches/0001-first.patch");
    CHECK_STR(out.items[1], "/tmp/rbtest_vd/patches/0002-second.patch");
    strlist_free(&out);
    vendor_free(&v);
}

TEST(test_vendor_list_patches_missing_dir) {
    Vendor v;
    strlist out;

    vendor_init(&v);
    v.tarball = xstrdup("z.tar.gz");
    v.directory = xstrdup("z");
    v.patches = xstrdup("nosuchdir");

    /* absent DEFAULT patch dir: fine, no patches */
    strlist_init(&out);
    CHECK_INT(vendor_list_patches(&v, "/tmp/rbtest_vd", &out), 0);
    CHECK_INT(out.count, 0);
    strlist_free(&out);

    /* absent EXPLICIT patch dir: error */
    v.patches_explicit = 1;
    strlist_init(&out);
    CHECK_INT(vendor_list_patches(&v, "/tmp/rbtest_vd", &out), 1);
    strlist_free(&out);
    vendor_free(&v);
    system("rm -rf /tmp/rbtest_vd");
}

TEST(test_vendor_apply) {
    Vendor v;
    struct stat st;

    make_widget_project();
    /* 0001: "@@ -1" but "orig" is on line 2, so it applies at offset 1.
       Plain patch 2.5 would leave hello.txt.orig behind. */
    write_file("/tmp/rbtest_va/src/patches/0001-change.patch",
        "--- widget-1.0/hello.txt\n"
        "+++ widget/hello.txt\n"
        "@@ -1 +1 @@\n"
        "-orig\n"
        "+patched\n");
    /* 0002: empties gone.txt; -E must delete it */
    write_file("/tmp/rbtest_va/src/patches/0002-remove.patch",
        "--- widget-1.0/gone.txt\n"
        "+++ widget/gone.txt\n"
        "@@ -1 +0,0 @@\n"
        "-bye\n");

    widget_vendor(&v);
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 0);
    CHECK(file_is("/tmp/rbtest_va/root/widget/hello.txt", "top\npatched\n"));
    CHECK(stat("/tmp/rbtest_va/root/widget/gone.txt", &st) != 0);
    CHECK(stat("/tmp/rbtest_va/root/widget/hello.txt.orig", &st) != 0);
    CHECK(stat("/tmp/rbtest_va/root/.vendor-tmp", &st) != 0);
    vendor_free(&v);
}

TEST(test_vendor_apply_refuses_existing_tree) {
    Vendor v;
    /* left over from test_vendor_apply: root/widget exists, which is what a
       project with both apk/vendor and an expanded tree looks like */
    widget_vendor(&v);
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_missing_tarball) {
    Vendor v;
    widget_vendor(&v);
    free(v.tarball);
    v.tarball = xstrdup("nosuch.tar.gz");
    system("rm -rf /tmp/rbtest_va/root/widget");
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_rejects_tarbomb) {
    Vendor v;
    system("rm -rf /tmp/rbtest_va/root && mkdir -p /tmp/rbtest_va/root "
           "/tmp/rbtest_va/bomb && echo a > /tmp/rbtest_va/bomb/a.txt && "
           "echo b > /tmp/rbtest_va/bomb/b.txt && cd /tmp/rbtest_va/bomb && "
           "/bin/pax -w -x ustar a.txt b.txt | /usr/bin/gzip -c "
           "> /tmp/rbtest_va/src/bomb.tar.gz");
    widget_vendor(&v);
    free(v.tarball);
    v.tarball = xstrdup("bomb.tar.gz");
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_bad_patch_fails) {
    Vendor v;
    make_widget_project();
    write_file("/tmp/rbtest_va/src/patches/0001-bad.patch",
        "--- widget-1.0/hello.txt\n"
        "+++ widget/hello.txt\n"
        "@@ -1 +1 @@\n"
        "-something else entirely\n"
        "+patched\n");
    widget_vendor(&v);
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_dry_run) {
    Vendor v;
    struct stat st;
    make_widget_project();
    widget_vendor(&v);
    exec_dry_run = 1;
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 0);
    exec_dry_run = 0;
    CHECK(stat("/tmp/rbtest_va/root/widget", &st) != 0);
    vendor_free(&v);
    system("rm -rf /tmp/rbtest_va");
}

static void run_all(void) {
    RUN(test_vendor_read_full);
    RUN(test_vendor_read_defaults);
    RUN(test_vendor_read_errors);
    RUN(test_vendor_path);
    RUN(test_vendor_list_patches_sorted);
    RUN(test_vendor_list_patches_missing_dir);
    RUN(test_vendor_apply);
    RUN(test_vendor_apply_refuses_existing_tree);
    RUN(test_vendor_apply_missing_tarball);
    RUN(test_vendor_apply_rejects_tarbomb);
    RUN(test_vendor_apply_bad_patch_fails);
    RUN(test_vendor_apply_dry_run);
}

TEST_MAIN()
