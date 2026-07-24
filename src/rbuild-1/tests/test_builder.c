#include "builder.h"
#include "test.h"
#include "exec.h"
#include <stdio.h>
#include <stdlib.h>

TEST(test_dir2name) {
    char *base = 0, *name = 0, *rev = 0;
    builder_dir2name("/some/path/gnumake-3.79", &base, &name, &rev);
    CHECK_STR(base, "gnumake");
    CHECK_STR(name, "gnumake");
    CHECK_STR(rev, "3.79");
    free(base); free(name); free(rev);

    base = name = rev = 0;
    builder_dir2name("foo_bar", &base, &name, &rev);
    CHECK_STR(base, "foo_bar");
    CHECK_STR(name, "foo-bar");   /* pkgname lowercases + _->- */
    CHECK(rev == 0);
    free(base); free(name); free(rev);
}

TEST(test_pkgname) {
    char *a = builder_pkgname("Foo_Bar", 0);
    char *b = builder_pkgname("appkit", 0);
    char *c = builder_pkgname("ssh", "1.2");
    char *d = builder_pkgname("ssh", "2.0");
    CHECK_STR(a, "foo-bar");
    CHECK_STR(b, "appkit-old");
    CHECK_STR(c, "ssh1");
    CHECK_STR(d, "ssh2");
    free(a); free(b); free(c); free(d);
}

TEST(test_match_pkgfile) {
    CHECK_INT(builder_match_pkgfile("foo-1.0.apk", "foo"), 1);
    CHECK_INT(builder_match_pkgfile("foo-hdrs-1.0.apk", "foo"), 0);
    CHECK_INT(builder_match_pkgfile("foo-hdrs-1.0.apk", "foo-hdrs"), 1);
    CHECK_INT(builder_match_pkgfile("foo.apk", "foo"), 0);
    CHECK_INT(builder_match_pkgfile("foo-1.0.deb", "foo"), 0);
    CHECK_INT(builder_match_pkgfile("foobar-1.0.apk", "foo"), 0);
}

TEST(test_resolve_and_exists) {
    /* Build a temp dir with a couple of .apk files. */
    Package p;
    strlist repo;
    char *r, *e;
    system("rm -rf /tmp/rbtest_repo && mkdir -p /tmp/rbtest_repo");
    system("touch /tmp/rbtest_repo/gnumake-3.79.apk");
    system("touch /tmp/rbtest_repo/gnumake-hdrs-3.79.apk");

    strlist_init(&repo);
    strlist_push(&repo, "/tmp/rbtest_repo");
    r = builder_resolve_dependency("gnumake", &repo);
    CHECK_STR(r, "/tmp/rbtest_repo/gnumake-3.79.apk");
    free(r);
    strlist_free(&repo);

    package_init(&p);
    package_set(&p.package, "gnumake");
    e = builder_exists(&p, "any", "/tmp/rbtest_repo");
    CHECK_STR(e, "/tmp/rbtest_repo/gnumake-3.79.apk");
    free(e);
    package_free(&p);
    system("rm -rf /tmp/rbtest_repo");
}

TEST(test_getparams_defaults) {
    Params p;
    /* Ensure no env overrides interfere. */
    unsetenv("BUILDIT_DIR"); unsetenv("BUILDROOT"); unsetenv("SRCROOT");
    unsetenv("OBJROOT"); unsetenv("SYMROOT"); unsetenv("DSTROOT");
    unsetenv("HDRROOT"); unsetenv("LIBCOBJROOT"); unsetenv("LOGFILE");
    unsetenv("SUBLIBROOTS"); unsetenv("PACKAGEROOT");
    params_init(&p);
    builder_getparams("foo-1.0", &p);
    CHECK_STR(p.BUILDROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0.root");
    CHECK_STR(p.SRCROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0");
    CHECK_STR(p.OBJROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0.obj");
    CHECK_STR(p.DSTROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0.dst");
    CHECK_STR(p.HDRROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0.hdr");
    CHECK_STR(p.SUBLIBROOTS, "/usr/local/lib/objs");
    params_free(&p);
}

TEST(test_canonparams) {
    Params p;
    params_init(&p);
    p.SRCROOT = xstrdup("relative/src");
    p.OBJROOT = xstrdup("/already/abs");
    builder_canonparams(&p, "/cwd");
    CHECK_STR(p.SRCROOT, "/cwd/relative/src");
    CHECK_STR(p.OBJROOT, "/already/abs");
    params_free(&p);
}

TEST(test_chrootparams) {
    Params in, out;
    params_init(&in); params_init(&out);
    in.SRCROOT = xstrdup("/a/src");
    in.DSTROOT = xstrdup("/a/dst");
    builder_chrootparams(&in, "/build/", &out);
    CHECK_STR(out.SRCROOT, "/build/a/src");
    CHECK_STR(out.DSTROOT, "/build/a/dst");
    CHECK_STR(out.BUILDROOT, "/build");
    params_free(&in); params_free(&out);
}

static int list_has(const strlist *l, const char *s) {
    size_t i;
    for (i = 0; i < l->count; i++) if (strcmp(l->items[i], s) == 0) return 1;
    return 0;
}

TEST(test_buildflags) {
    Params p;
    strlist f;
    params_init(&p);
    p.SRCROOT = xstrdup("/s"); p.OBJROOT = xstrdup("/o");
    p.SYMROOT = xstrdup("/y"); p.DSTROOT = xstrdup("/d");
    p.HDRROOT = xstrdup("/h"); p.SUBLIBROOTS = xstrdup("/objs");
    strlist_init(&f);
    builder_buildflags(&p, "install", &f);
    CHECK(list_has(&f, "SRCROOT=/s"));
    CHECK(list_has(&f, "DSTROOT=/d"));
    CHECK(list_has(&f, "RC_ARCHS=i386 ppc"));
    CHECK(list_has(&f, "RC_i386=YES"));
    strlist_free(&f);

    strlist_init(&f);
    builder_buildflags(&p, "installhdrs", &f);
    CHECK(list_has(&f, "DSTROOT=/h"));   /* headers target uses HDRROOT */
    strlist_free(&f);
    params_free(&p);
}

TEST(test_buildcmd_native) {
    Params cp, bp;
    strlist cmd;
    params_init(&cp); params_init(&bp);
    cp.BUILDROOT = xstrdup("/br");
    bp.SRCROOT = xstrdup("/s"); bp.OBJROOT = xstrdup("/o");
    bp.SYMROOT = xstrdup("/y"); bp.DSTROOT = xstrdup("/d");
    bp.HDRROOT = xstrdup("/h"); bp.SUBLIBROOTS = xstrdup("/objs");

    /* native: no chroot wrapper, make is first token, -C uses SRCROOT */
    strlist_init(&cmd);
    builder_buildcmd(&cp, &bp, "install", &cmd, 1);
    CHECK_STR(cmd.items[0], "make");
    CHECK(!list_has(&cmd, "chroot"));
    CHECK(!list_has(&cmd, "/br"));
    CHECK(list_has(&cmd, "/s"));         /* -C <SRCROOT> */
    strlist_free(&cmd);

    /* non-native: chroot wrapper present */
    strlist_init(&cmd);
    builder_buildcmd(&cp, &bp, "install", &cmd, 0);
    CHECK_STR(cmd.items[0], "chroot");
    CHECK_STR(cmd.items[1], "/br");
    CHECK_STR(cmd.items[2], "make");
    strlist_free(&cmd);

    params_free(&cp); params_free(&bp);
}

TEST(test_setupdirs_native_skips_makeroot) {
    Package pkg;
    Params p;
    strlist repo;               /* empty repository */
    int rc_native, rc_normal;

    exec_dry_run = 1;           /* mkdir/rsync become no-ops */
    package_init(&pkg);         /* no build_depends -> basedeps fallback */
    strlist_init(&repo);        /* nothing resolves */

    params_init(&p);
    p.BUILDROOT = xstrdup("/tmp/rb_nat/br");
    p.OBJROOT = xstrdup("/tmp/rb_nat/obj");
    p.SYMROOT = xstrdup("/tmp/rb_nat/sym");
    p.DSTROOT = xstrdup("/tmp/rb_nat/dst");
    p.HDRROOT = xstrdup("/tmp/rb_nat/hdr");
    p.PACKAGEROOT = xstrdup("/tmp/rb_nat/pkg");
    p.SRCROOT = xstrdup("/tmp/rb_nat/src");
    p.SRCDIR = xstrdup("/tmp/rb_nat/srcdir");

    /* native: makeroot skipped -> empty repo is fine -> success */
    rc_native = builder_setupdirs(&pkg, &p, "foo", "dir", &repo, 1);
    CHECK_INT(rc_native, 0);

    /* non-native: makeroot runs -> cannot resolve "cc" in empty repo -> fail */
    rc_normal = builder_setupdirs(&pkg, &p, "foo", "dir", &repo, 0);
    CHECK_INT(rc_normal, 1);

    exec_dry_run = 0;
    params_free(&p);
    strlist_free(&repo);
    package_free(&pkg);
}

TEST(test_scan_dir) {
    Package pkg;
    Params params;
    int rc;
    system("rm -rf /tmp/rbtest_src && mkdir -p /tmp/rbtest_src/objc4-174/dpkg");
    {
        FILE *f = fopen("/tmp/rbtest_src/objc4-174/dpkg/control", "w");
        fputs("Package: objc4\nVersion: 174\n"
              "Description: Objective-C runtime\n"
              "Build-Depends: build-base\n", f);
        fclose(f);
    }
    package_init(&pkg);
    params_init(&params);
    rc = builder_scan_dir("/tmp/rbtest_src/objc4-174", &pkg, &params);
    CHECK_INT(rc, 0);
    CHECK_STR(pkg.package, "objc4");
    CHECK_STR(pkg.version, "174-174");   /* base version + "-" + revision */
    CHECK_STR(pkg.source, "objc4");
    CHECK(params.SRCROOT != 0);
    package_free(&pkg);
    params_free(&params);
    system("rm -rf /tmp/rbtest_src");
}

static void run_all(void) {
    RUN(test_dir2name);
    RUN(test_pkgname);
    RUN(test_match_pkgfile);
    RUN(test_resolve_and_exists);
    RUN(test_getparams_defaults);
    RUN(test_canonparams);
    RUN(test_chrootparams);
    RUN(test_buildflags);
    RUN(test_buildcmd_native);
    RUN(test_setupdirs_native_skips_makeroot);
    RUN(test_scan_dir);
}

TEST_MAIN()
