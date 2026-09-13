#include "builder.h"
#include "architecture.h"
#include "test.h"
#include "exec.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

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
    CHECK(e == 0); /* A zero-byte filename is not a reusable APK. */
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

static const char *list_has_prefix(const strlist *l, const char *prefix) {
    size_t i;
    for (i = 0; i < l->count; i++)
        if (str_has_prefix(l->items[i], prefix)) return l->items[i];
    return 0;
}

static void toolchain_fixture(Toolchain *tc) {
    memset(tc, 0, sizeof(*tc));
    tc->target_arch = "ppc";
    tc->target_cc = "/tools/target-cc";
    tc->target_ar = "/tools/target-ar";
    tc->target_ranlib = "/tools/target-ranlib";
    tc->make = "/tools/make";
    tc->make_flags = "MAKEFILEDIR=@SYSROOT@/System/Developer/Makefiles/project MAKEFILEPATH=@SYSROOT@/System/Developer/Makefiles";
    tc->shell = "/bin/sh";
    tc->tar = "/tools/tar";
    tc->archive_create = "/bin/pax";
    tc->archive_create_flags = "-w -x ustar";
    tc->gzip = "/tools/gzip";
    tc->rsync = "/tools/rsync";
    tc->path = "/tools:/usr/bin:/bin";
    tc->arch_flags = "-arch ppc";
    tc->cpp_flags = "-nostdinc -I@SYSROOT@/System/Headers";
    tc->ld_flags = "-Wl,-syslibroot,@SYSROOT@";
    tc->ln = "/tools/ln";
}

TEST(test_bootstrap_flags_use_target_sysroot) {
    static const char *defines[] = {
        "-Dunix", "-D__unix", "-D__unix__",
        "-DNX_COMPILER_RELEASE_3_0=300", "-DNX_COMPILER_RELEASE_3_1=310",
        "-DNX_COMPILER_RELEASE_3_2=320", "-DNX_COMPILER_RELEASE_3_3=330",
        "-DNX_CURRENT_COMPILER_RELEASE=520",
        "-DNS_TARGET=52", "-DNS_TARGET_MAJOR=5", "-DNS_TARGET_MINOR=2",
        "-DNeXT", "-D__NeXT", "-D__NeXT__", "-D_NEXT_SOURCE", 0
    };
    Params p;
    BuildOptions opt;
    Toolchain tc;
    strlist f;
    const char *rc_cflags;
    int i;

    params_init(&p);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    opt.bootstrap = 1;
    opt.sysroot = "/target";
    opt.toolchain = &tc;
    p.SRCROOT = xstrdup("/s"); p.OBJROOT = xstrdup("/o");
    p.SYMROOT = xstrdup("/y"); p.DSTROOT = xstrdup("/d");
    p.HDRROOT = xstrdup("/h"); p.SUBLIBROOTS = xstrdup("/objs");

    strlist_init(&f);
    builder_buildflags(&p, "install", &f, &opt);
    CHECK(list_has(&f, "NEXT_ROOT=/target"));
    CHECK(list_has(&f, "CC=/tools/target-cc"));
    CHECK(list_has(&f, "AR=/tools/target-ar"));
    CHECK(list_has(&f, "RANLIB=/tools/target-ranlib"));
    CHECK(list_has(&f, "LN=/tools/ln -s"));
    CHECK(!list_has(&f, "LN=/tools/ln"));
    CHECK(list_has(&f, "RC_ARCHS=ppc"));
    CHECK(list_has(&f, "RC_ppc=YES"));
    CHECK(list_has(&f, "RC_i386="));
    CHECK(list_has(&f, "TARGETS=ppc"));
    CHECK(!list_has_prefix(&f, "CoreOSMakefiles="));
    CHECK(list_has(&f, "MKDIRS=/bin/mkdir -p"));
    CHECK(list_has(&f, "SFILE_DIR=/y/derived_src"));
    CHECK(list_has(&f, "HDRROOT=/target"));
    CHECK(list_has(&f, "SUBLIBROOTS=/target/usr/local/lib/objs"));
    CHECK(!list_has(&f, "SUBLIBROOTS=/objs"));
    rc_cflags = list_has_prefix(&f, "RC_CFLAGS=");
    CHECK(rc_cflags != 0);
    CHECK(str_has_prefix(rc_cflags,
          "RC_CFLAGS=-arch ppc -nostdinc"));
    CHECK(strstr(rc_cflags, "-I/") == 0);
    CHECK(list_has(&f, "LOCAL_CFLAGS=-I/target/System/Headers"));
    for (i = 0; defines[i]; i++) CHECK(strstr(rc_cflags, defines[i]) != 0);
    CHECK(list_has(&f, "OTHER_LDFLAGS=-F/target/System/Library/Frameworks -L/target/usr/lib"));
    CHECK(!list_has_prefix(&f, "INDR="));
    CHECK(!list_has_prefix(&f, "BOOTSTRAP_SKIP_DYLD="));
    strlist_free(&f);

    params_free(&p);
}

TEST(test_buildflags) {
    Params p;
    BuildOptions opt;
    strlist f;
    params_init(&p);
    build_options_init(&opt);
    p.SRCROOT = xstrdup("/s"); p.OBJROOT = xstrdup("/o");
    p.SYMROOT = xstrdup("/y"); p.DSTROOT = xstrdup("/d");
    p.HDRROOT = xstrdup("/h"); p.SUBLIBROOTS = xstrdup("/objs");
    strlist_init(&f);
    builder_buildflags(&p, "install", &f, &opt);
    CHECK(list_has(&f, "SRCROOT=/s"));
    CHECK(list_has(&f, "DSTROOT=/d"));
    CHECK(list_has(&f, "RC_ARCHS=i386 ppc"));
    CHECK(list_has(&f, "RC_i386=YES"));
    CHECK(list_has(&f, "RC_ppc=YES"));
    CHECK(!list_has_prefix(&f, "TARGETS="));
    CHECK(str_has_prefix(list_has_prefix(&f, "RC_CFLAGS="),
                         "RC_CFLAGS=-arch i386 -arch ppc  -Dunix"));
    strlist_free(&f);

    strlist_init(&f);
    builder_buildflags(&p, "installhdrs", &f, &opt);
    CHECK(list_has(&f, "DSTROOT=/h"));   /* headers target uses HDRROOT */
    strlist_free(&f);

    /* A bootstrap without a profile gets no implicit host-tool fallback. */
    strlist_init(&f);
    opt.bootstrap = 1;
    builder_buildflags(&p, "install", &f, &opt);
    CHECK(list_has(&f, "RC_ARCHS=i386 ppc"));
    CHECK(!list_has_prefix(&f, "LN="));
    strlist_free(&f);
    params_free(&p);
}

TEST(test_bootstrap_harvest_stays_in_private_object_root) {
    Package pkg;
    Params params, bparams;
    BuildOptions opt;
    char base[128];
    char command[1024];
    char *private_obj;
    char *live_obj;

    sprintf(base, "/tmp/rb-harvest-%ld", (long)getpid());
    sprintf(command,
            "rm -rf %s && mkdir -p %s/obj/fixture %s/private %s/live && "
            ": > %s/obj/fixture/dynamic_obj",
            base, base, base, base, base);
    CHECK_INT(system(command), 0);

    package_init(&pkg);
    package_set(&pkg.source, "foo");
    params_init(&params);
    params_init(&bparams);
    build_options_init(&opt);
    opt.bootstrap = 1;
    params.OBJROOT = str_cats(base, "/obj", (char *)0);
    params.LIBCOBJROOT = str_cats(base, "/private", (char *)0);
    params.SUBLIBROOTS = str_cats(base, "/live", (char *)0);
    params.BUILDROOT = str_cats(base, "/root", (char *)0);
    bparams.OBJROOT = xstrdup(params.OBJROOT);
    bparams.LIBCOBJROOT = xstrdup(params.LIBCOBJROOT);

    CHECK_INT(builder_harvest_objects(&pkg, &params, &bparams, &opt), 0);
    private_obj = str_cats(params.LIBCOBJROOT,
        "/usr/local/lib/objs/foo/fixture/dynamic_obj", (char *)0);
    live_obj = str_cats(params.SUBLIBROOTS,
        "/foo/fixture/dynamic_obj", (char *)0);
    CHECK(access(private_obj, F_OK) == 0);
    CHECK(access(live_obj, F_OK) != 0);

    free(private_obj);
    free(live_obj);
    params_free(&params);
    params_free(&bparams);
    package_free(&pkg);
    sprintf(command, "rm -rf %s", base);
    system(command);
}

TEST(test_buildcmd_bootstrap) {
    Params cp, bp;
    BuildOptions opt;
    Toolchain tc;
    strlist cmd;
    params_init(&cp); params_init(&bp);
    build_options_init(&opt);
    cp.BUILDROOT = xstrdup("/br");
    bp.SRCROOT = xstrdup("/s"); bp.OBJROOT = xstrdup("/o");
    bp.SYMROOT = xstrdup("/y"); bp.DSTROOT = xstrdup("/d");
    bp.HDRROOT = xstrdup("/h"); bp.SUBLIBROOTS = xstrdup("/objs");

    /* bootstrap: no chroot wrapper, make is first token, -C uses SRCROOT */
    strlist_init(&cmd);
    opt.bootstrap = 1;
    builder_buildcmd(&cp, &bp, "install", &cmd, &opt);
    CHECK_STR(cmd.items[0], "make");
    CHECK(!list_has(&cmd, "chroot"));
    CHECK(!list_has(&cmd, "/br"));
    CHECK(list_has(&cmd, "/s"));         /* -C <SRCROOT> */
    strlist_free(&cmd);

    /* non-bootstrap: chroot wrapper present */
    strlist_init(&cmd);
    opt.bootstrap = 0;
    builder_buildcmd(&cp, &bp, "install", &cmd, &opt);
    CHECK_STR(cmd.items[0], "chroot");
    CHECK_STR(cmd.items[1], "/br");
    CHECK_STR(cmd.items[2], "make");
    strlist_free(&cmd);

    toolchain_fixture(&tc);
    opt.bootstrap = 1;
    opt.sysroot = "/target";
    opt.toolchain = &tc;
    strlist_init(&cmd);
    builder_buildcmd(&cp, &bp, "install", &cmd, &opt);
    CHECK_STR(cmd.items[0], "/tools/make");
    CHECK(!list_has(&cmd, "chroot"));
    CHECK(!list_has_prefix(&cmd, "MAKEFILEDIR="));
    CHECK(list_has(&cmd,
          "MAKEFILEPATH=/target/System/Developer/Makefiles"));
    strlist_free(&cmd);

    opt.bootstrap = 0;
    strlist_init(&cmd);
    builder_buildcmd(&cp, &bp, "install", &cmd, &opt);
    CHECK(!list_has_prefix(&cmd, "MAKEFILEDIR="));
    CHECK(!list_has_prefix(&cmd, "MAKEFILEPATH="));
    strlist_free(&cmd);

    params_free(&cp); params_free(&bp);
}

TEST(test_bootstrap_make_flags_wait_for_ready_path) {
    Params cp, bp;
    BuildOptions opt;
    Toolchain tc;
    strlist cmd;
    char base[128];
    char ready[160];
    char shell_cmd[256];
    char expected_makefiledir[256];
    char expected_makefilepath[256];
    FILE *fp;

    sprintf(base, "/tmp/rb-make-flags-%ld", (long)getpid());
    sprintf(ready, "%s/ready/platform.make", base);
    sprintf(expected_makefiledir,
            "MAKEFILEDIR=%s/System/Developer/Makefiles/project", base);
    sprintf(expected_makefilepath,
            "MAKEFILEPATH=%s/System/Developer/Makefiles", base);
    sprintf(shell_cmd, "rm -rf %s && mkdir -p %s/ready", base, base);
    CHECK_INT(system(shell_cmd), 0);
    params_init(&cp); params_init(&bp);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    tc.make_flags_ready = "@SYSROOT@/ready/platform.make";
    opt.bootstrap = 1;
    opt.sysroot = base;
    opt.toolchain = &tc;
    cp.BUILDROOT = xstrdup("/br");
    bp.SRCROOT = xstrdup("/s"); bp.OBJROOT = xstrdup("/o");
    bp.SYMROOT = xstrdup("/y"); bp.DSTROOT = xstrdup("/d");
    bp.HDRROOT = xstrdup("/h"); bp.SUBLIBROOTS = xstrdup("/objs");

    strlist_init(&cmd);
    builder_buildcmd(&cp, &bp, "install", &cmd, &opt);
    CHECK(!list_has_prefix(&cmd, "MAKEFILEDIR="));
    CHECK(!list_has_prefix(&cmd, "MAKEFILEPATH="));
    strlist_free(&cmd);

    fp = fopen(ready, "w");
    CHECK(fp != 0);
    if (fp) fclose(fp);
    strlist_init(&cmd);
    builder_buildcmd(&cp, &bp, "install", &cmd, &opt);
    CHECK(!list_has(&cmd, expected_makefiledir));
    CHECK(list_has(&cmd, expected_makefilepath));
    strlist_free(&cmd);

    params_free(&cp); params_free(&bp);
    sprintf(shell_cmd, "rm -rf %s", base);
    CHECK_INT(system(shell_cmd), 0);
}

TEST(test_bootstrap_coreos_makefiles_wait_for_sysroot) {
    Params p;
    BuildOptions opt;
    Toolchain tc;
    strlist flags;
    char base[128];
    char common[256];
    char shell_cmd[256];
    char expected[256];
    FILE *fp;

    sprintf(base, "/tmp/rb-coreos-makefiles-%ld", (long)getpid());
    sprintf(common,
            "%s/System/Developer/Makefiles/CoreOS/ReleaseControl/Common.make",
            base);
    sprintf(expected,
            "CoreOSMakefiles=%s/System/Developer/Makefiles/CoreOS", base);
    sprintf(shell_cmd,
            "rm -rf %s && mkdir -p %s/System/Developer/Makefiles/CoreOS/ReleaseControl",
            base, base);
    CHECK_INT(system(shell_cmd), 0);
    params_init(&p);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    opt.bootstrap = 1;
    opt.sysroot = base;
    opt.toolchain = &tc;
    p.SRCROOT = xstrdup("/s"); p.OBJROOT = xstrdup("/o");
    p.SYMROOT = xstrdup("/y"); p.DSTROOT = xstrdup("/d");
    p.HDRROOT = xstrdup("/h"); p.SUBLIBROOTS = xstrdup("/objs");

    strlist_init(&flags);
    builder_buildflags(&p, "install", &flags, &opt);
    CHECK(!list_has_prefix(&flags, "CoreOSMakefiles="));
    CHECK(list_has(&flags, "MKDIRS=/bin/mkdir -p"));
    strlist_free(&flags);

    fp = fopen(common, "w");
    CHECK(fp != 0);
    if (fp) fclose(fp);
    strlist_init(&flags);
    builder_buildflags(&p, "install", &flags, &opt);
    CHECK(list_has(&flags, expected));
    CHECK(list_has(&flags, "MKDIRS=/bin/mkdir -p"));
    strlist_free(&flags);

    params_free(&p);
    sprintf(shell_cmd, "rm -rf %s", base);
    CHECK_INT(system(shell_cmd), 0);
}

TEST(test_bootstrap_ld_flags_wait_for_ready_path) {
    Params p;
    BuildOptions opt;
    Toolchain tc;
    strlist flags;
    char base[128];
    char ready[180];
    char shell_cmd[256];
    char expected[256];
    char expected_root[256];
    FILE *fp;

    sprintf(base, "/tmp/rb-ld-flags-%ld", (long)getpid());
    sprintf(ready, "%s/ready/System", base);
    sprintf(expected, "OTHER_LDFLAGS=-F%s/System/Library/Frameworks -L%s/usr/lib",
            base, base);
    sprintf(expected_root, "NEXT_ROOT=%s", base);
    sprintf(shell_cmd, "rm -rf %s && mkdir -p %s/ready", base, base);
    CHECK_INT(system(shell_cmd), 0);
    params_init(&p);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    tc.ld_flags_ready = "@SYSROOT@/ready/System";
    opt.bootstrap = 1;
    opt.sysroot = base;
    opt.toolchain = &tc;
    p.SRCROOT = xstrdup("/s"); p.OBJROOT = xstrdup("/o");
    p.SYMROOT = xstrdup("/y"); p.DSTROOT = xstrdup("/d");
    p.HDRROOT = xstrdup("/h"); p.SUBLIBROOTS = xstrdup("/objs");

    strlist_init(&flags);
    builder_buildflags(&p, "install", &flags, &opt);
    CHECK(!list_has_prefix(&flags, "NEXT_ROOT="));
    CHECK(list_has(&flags, "OTHER_LDFLAGS="));
    CHECK(!list_has(&flags, expected));
    strlist_free(&flags);

    fp = fopen(ready, "w");
    CHECK(fp != 0);
    if (fp) fclose(fp);
    strlist_init(&flags);
    builder_buildflags(&p, "install", &flags, &opt);
    CHECK(list_has(&flags, expected));
    CHECK(list_has(&flags, expected_root));
    strlist_free(&flags);

    params_free(&p);
    sprintf(shell_cmd, "rm -rf %s", base);
    CHECK_INT(system(shell_cmd), 0);
}

TEST(test_bootstrap_cpp_flags_wait_for_ready_path) {
    Params p;
    BuildOptions opt;
    Toolchain tc;
    strlist flags;
    char base[128];
    char ready[180];
    char expected_other[256];
    char shell_cmd[256];
    const char *rc_cflags;
    FILE *fp;

    sprintf(base, "/tmp/rb-cpp-flags-%ld", (long)getpid());
    sprintf(ready, "%s/ready/stdarg.h", base);
    sprintf(expected_other, "LOCAL_CFLAGS=-I%s/System/Headers", base);
    sprintf(shell_cmd, "rm -rf %s && mkdir -p %s/ready", base, base);
    CHECK_INT(system(shell_cmd), 0);
    params_init(&p);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    tc.cpp_flags_ready = "@SYSROOT@/ready/stdarg.h";
    opt.bootstrap = 1;
    opt.sysroot = base;
    opt.toolchain = &tc;
    p.SRCROOT = xstrdup("/s"); p.OBJROOT = xstrdup("/o");
    p.SYMROOT = xstrdup("/y"); p.DSTROOT = xstrdup("/d");
    p.HDRROOT = xstrdup("/h"); p.SUBLIBROOTS = xstrdup("/objs");

    strlist_init(&flags);
    builder_buildflags(&p, "install", &flags, &opt);
    rc_cflags = list_has_prefix(&flags, "RC_CFLAGS=");
    CHECK(rc_cflags != 0);
    CHECK(strstr(rc_cflags, "-nostdinc") == 0);
    CHECK(strstr(rc_cflags, "/System/Headers") == 0);
    CHECK(list_has(&flags, expected_other));
    strlist_free(&flags);

    fp = fopen(ready, "w");
    CHECK(fp != 0);
    if (fp) fclose(fp);
    strlist_init(&flags);
    builder_buildflags(&p, "install", &flags, &opt);
    rc_cflags = list_has_prefix(&flags, "RC_CFLAGS=");
    CHECK(rc_cflags != 0);
    CHECK(strstr(rc_cflags, "-nostdinc") != 0);
    CHECK(strstr(rc_cflags, "/System/Headers") == 0);
    CHECK(list_has(&flags, expected_other));
    strlist_free(&flags);

    params_free(&p);
    sprintf(shell_cmd, "rm -rf %s", base);
    CHECK_INT(system(shell_cmd), 0);
}

TEST(test_bootstrap_indr_from_sysroot) {
    Params p;
    BuildOptions opt;
    Toolchain tc;
    strlist flags;
    char base[128];
    char expected[192];
    char shell_cmd[256];

    sprintf(base, "/tmp/rb-indr-%ld", (long)getpid());
    sprintf(expected, "INDR=%s/usr/local/bin/indr", base);
    sprintf(shell_cmd,
            "rm -rf %s && mkdir -p %s/usr/local/bin && "
            "touch %s/usr/local/bin/indr && chmod +x %s/usr/local/bin/indr",
            base, base, base, base);
    CHECK_INT(system(shell_cmd), 0);
    params_init(&p);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    opt.bootstrap = 1;
    opt.sysroot = base;
    opt.toolchain = &tc;
    p.SRCROOT = xstrdup("/s"); p.OBJROOT = xstrdup("/o");
    p.SYMROOT = xstrdup("/y"); p.DSTROOT = xstrdup("/d");
    p.HDRROOT = xstrdup("/h"); p.SUBLIBROOTS = xstrdup("/objs");

    strlist_init(&flags);
    builder_buildflags(&p, "install", &flags, &opt);
    CHECK(list_has(&flags, expected));
    strlist_free(&flags);

    params_free(&p);
    sprintf(shell_cmd, "rm -rf %s", base);
    CHECK_INT(system(shell_cmd), 0);
}

TEST(test_setupdirs_bootstrap_skips_makeroot) {
    Package pkg;
    Params p;
    strlist repo;               /* empty repository */
    int rc_bootstrap, rc_normal;
    BuildOptions opt;

    exec_dry_run = 1;           /* mkdir/rsync become no-ops */
    package_init(&pkg);         /* no build_depends -> basedeps fallback */
    strlist_init(&repo);        /* nothing resolves */

    params_init(&p);
    build_options_init(&opt);
    p.BUILDROOT = xstrdup("/tmp/rb_nat/br");
    p.OBJROOT = xstrdup("/tmp/rb_nat/obj");
    p.SYMROOT = xstrdup("/tmp/rb_nat/sym");
    p.DSTROOT = xstrdup("/tmp/rb_nat/dst");
    p.HDRROOT = xstrdup("/tmp/rb_nat/hdr");
    p.PACKAGEROOT = xstrdup("/tmp/rb_nat/pkg");
    p.SRCROOT = xstrdup("/tmp/rb_nat/src");
    p.SRCDIR = xstrdup("/tmp/rb_nat/srcdir");

    /* bootstrap: makeroot skipped -> empty repo is fine -> success */
    opt.bootstrap = 1;
    rc_bootstrap = builder_setupdirs(&pkg, &p, "foo", "dir", &repo, &opt);
    CHECK_INT(rc_bootstrap, 0);

    /* Dry-run reports required dependencies without staging any archives. */
    opt.bootstrap = 0;
    rc_normal = builder_setupdirs(&pkg, &p, "foo", "dir", &repo, &opt);
    CHECK_INT(rc_normal, 0);

    exec_dry_run = 0;
    params_free(&p);
    strlist_free(&repo);
    package_free(&pkg);
}

TEST(test_makeroot_dry_run_preserves_package_list) {
    Package pkg;
    strlist repo;
    char root[128];
    char path[192];
    char command[256];
    char line[64];
    FILE *f;

    sprintf(root, "/tmp/rb-makeroot-dry-%ld", (long)getpid());
    sprintf(path, "%s/var/adm/package-list", root);
    sprintf(command, "rm -rf %s && mkdir -p %s/var/adm", root, root);
    CHECK_INT(system(command), 0);
    f = fopen(path, "w");
    CHECK(f != 0);
    if (f != 0) { fputs("sentinel-package\n", f); fclose(f); }

    package_init(&pkg);
    pkg.has_build_depends = 1; /* Explicitly empty: no APK extraction. */
    strlist_init(&repo);
    exec_dry_run = 1;
    CHECK_INT(builder_makeroot(&pkg, root, &repo), 0);
    exec_dry_run = 0;

    f = fopen(path, "r");
    CHECK(f != 0);
    line[0] = '\0';
    if (f != 0) { fgets(line, sizeof(line), f); fclose(f); }
    CHECK_STR(line, "sentinel-package\n");

    strlist_free(&repo);
    package_free(&pkg);
    sprintf(command, "rm -rf %s", root);
    system(command);
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

TEST(test_relativize_absolute_symlinks_inside_dstroot) {
    char root[128];
    char at_path[192];
    char atq_path[192];
    char surge_path[192];
    char alias_path[192];
    char outside_path[192];
    char tz_path[192];
    char localtime_path[192];
    char command[256];
    char target[1024];
    int n;
    FILE *f;

    sprintf(root, "/tmp/rb-relsymlink-%ld", (long)getpid());
    sprintf(command,
            "rm -rf %s && mkdir -p %s/usr/bin %s/usr/share/nvram "
            "%s/usr/share/zoneinfo/US %s/private/etc",
            root, root, root, root, root);
    CHECK_INT(system(command), 0);
    sprintf(at_path, "%s/usr/bin/at", root);
    sprintf(atq_path, "%s/usr/bin/atq", root);
    sprintf(surge_path, "%s/usr/share/nvram/PowerSurge", root);
    sprintf(alias_path, "%s/usr/share/nvram/7300", root);
    sprintf(outside_path, "%s/usr/bin/outside", root);
    sprintf(tz_path, "%s/usr/share/zoneinfo/US/Pacific", root);
    sprintf(localtime_path, "%s/private/etc/localtime", root);
    f = fopen(at_path, "w");
    CHECK(f != 0);
    if (f != 0) { fputs("at\n", f); fclose(f); }
    f = fopen(surge_path, "w");
    CHECK(f != 0);
    if (f != 0) { fputs("nvram\n", f); fclose(f); }
    f = fopen(tz_path, "w");
    CHECK(f != 0);
    if (f != 0) { fputs("tz\n", f); fclose(f); }
    CHECK_INT(symlink(at_path, atq_path), 0);
    CHECK_INT(symlink("PowerSurge", alias_path), 0);
    CHECK_INT(symlink("/etc/passwd", outside_path), 0);
    CHECK_INT(symlink("/usr/share/zoneinfo/US/Pacific", localtime_path), 0);
    CHECK_INT(builder_relativize_symlinks(root), 0);
    n = readlink(atq_path, target, sizeof(target) - 1);
    CHECK(n > 0);
    if (n > 0) target[n] = '\0';
    CHECK_STR(target, "at");
    n = readlink(alias_path, target, sizeof(target) - 1);
    CHECK(n > 0);
    if (n > 0) target[n] = '\0';
    CHECK_STR(target, "PowerSurge");
    n = readlink(outside_path, target, sizeof(target) - 1);
    CHECK(n > 0);
    if (n > 0) target[n] = '\0';
    CHECK_STR(target, "/etc/passwd");
    n = readlink(localtime_path, target, sizeof(target) - 1);
    CHECK(n > 0);
    if (n > 0) target[n] = '\0';
    CHECK_STR(target, "../../usr/share/zoneinfo/US/Pacific");
    sprintf(command, "rm -rf %s", root);
    system(command);
}


/* Each fixture is a real source control file consumed through builder_scan. */
TEST(test_scan_architecture_labels) {
    static const char *labels[] = { "i386", "ppc", "i386-apple-rhapsody",
        "ppc-apple-rhapsody", "universal-apple-rhapsody", 0 };
    char root[128], control[160], command[256];
    unsigned i;
    sprintf(root, "/tmp/rb-scan-arch-%ld", (long)getpid());
    sprintf(control, "%s/dpkg/control", root);
    sprintf(command, "mkdir -p %s/dpkg", root);
    CHECK_INT(system(command), 0);
    for (i = 0; i < sizeof(labels) / sizeof(labels[0]); i++) {
        Package pkg;
        Params params;
        FILE *f = fopen(control, "w");
        CHECK(f != 0);
        if (!f) continue;
        fputs("Package: fixture\nVersion: 1\n", f);
        if (labels[i]) fprintf(f, "Architecture: %s\n", labels[i]);
        fclose(f);
        package_init(&pkg);
        params_init(&params);
        CHECK_INT(builder_scan("dir", root, &pkg, &params), 0);
        CHECK_STR(pkg.architecture, labels[i] ? labels[i] :
                  "universal-apple-rhapsody");
        package_free(&pkg);
        params_free(&params);
    }
    CHECK_INT(unlink(control), 0);
    {
        Package pkg;
        Params params;
        package_init(&pkg);
        params_init(&params);
        CHECK_INT(builder_scan("dir", root, &pkg, &params), 0);
        CHECK_STR(pkg.architecture, "universal-apple-rhapsody");
        package_free(&pkg);
        params_free(&params);
    }
    sprintf(command, "rm -rf %s", root);
    CHECK_INT(system(command), 0);
}

TEST(test_scan_rejects_invalid_architecture) {
    static const char *labels[] = { "", "arm64", "universal", "i386 ppc" };
    char root[128], control[160], command[256];
    unsigned i;
    sprintf(root, "/tmp/rb-scan-bad-arch-%ld", (long)getpid());
    sprintf(control, "%s/dpkg/control", root);
    sprintf(command, "mkdir -p %s/dpkg", root);
    CHECK_INT(system(command), 0);
    for (i = 0; i < sizeof(labels) / sizeof(labels[0]); i++) {
        Package pkg;
        Params params;
        FILE *f = fopen(control, "w");
        CHECK(f != 0);
        if (!f) continue;
        /* Also omit Package/Version once: fallback must not hide a bad arch. */
        if (i != 3) fputs("Package: fixture\nVersion: 1\n", f);
        fprintf(f, "Architecture: %s\n", labels[i]);
        fclose(f);
        package_init(&pkg);
        params_init(&params);
        CHECK(builder_scan("dir", root, &pkg, &params) != 0);
        CHECK_STR(pkg.architecture, labels[i]);
        CHECK(params.SRCROOT == 0);
        package_free(&pkg);
        params_free(&params);
    }
    sprintf(command, "rm -rf %s", root);
    CHECK_INT(system(command), 0);
}

TEST(test_resolved_thin_flags) {
    Package pkg;
    Params params;
    BuildOptions opt;
    Toolchain tc;
    strlist flags;
    package_init(&pkg);
    params_init(&params);
    build_options_init(&opt);
    package_set(&pkg.architecture, "i386");
    CHECK_INT(builder_resolve_architecture(&pkg, &opt), 0);
    CHECK_STR(pkg.architecture, "i386-apple-rhapsody");
    CHECK_INT(opt.effective_arch, RB_ARCH_I386);
    CHECK_INT(opt.operation_arch, 0);
    strlist_init(&flags);
    builder_buildflags(&params, "install", &flags, &opt);
    CHECK(list_has(&flags, "RC_ARCHS=i386"));
    CHECK(list_has(&flags, "RC_i386=YES"));
    CHECK(list_has(&flags, "RC_ppc="));
    CHECK(str_has_prefix(list_has_prefix(&flags, "RC_CFLAGS="),
                         "RC_CFLAGS=-arch i386  -Dunix"));
    CHECK(!list_has_prefix(&flags, "TARGETS="));
    strlist_free(&flags);
    package_set(&pkg.architecture, "ppc");
    CHECK_INT(builder_resolve_architecture(&pkg, &opt), 0);
    CHECK_STR(pkg.architecture, "ppc-apple-rhapsody");
    strlist_init(&flags);
    builder_buildflags(&params, "install", &flags, &opt);
    CHECK(list_has(&flags, "RC_ARCHS=ppc"));
    CHECK(list_has(&flags, "RC_i386="));
    CHECK(list_has(&flags, "RC_ppc=YES"));
    CHECK(str_has_prefix(list_has_prefix(&flags, "RC_CFLAGS="),
                         "RC_CFLAGS=-arch ppc  -Dunix"));
    strlist_free(&flags);
    opt.operation_arch = RB_ARCH_I386;
    CHECK(builder_resolve_architecture(&pkg, &opt) != 0);
    toolchain_fixture(&tc);
    opt.bootstrap = 1;
    opt.toolchain = &tc;
    CHECK(builder_resolve_architecture(&pkg, &opt) != 0);
    opt.operation_arch = 0;
    tc.target_arch = "universal-apple-rhapsody";
    CHECK(builder_resolve_architecture(&pkg, &opt) != 0);
    tc.target_arch = 0;
    CHECK(builder_resolve_architecture(&pkg, &opt) != 0);
    package_free(&pkg);
    params_free(&params);
}

TEST(test_bootstrap_universal_resolve) {
    Package pkg;
    BuildOptions opt;
    Toolchain tc;
    package_init(&pkg);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    opt.bootstrap = 1;
    opt.toolchain = &tc;
    opt.operation_arch = RB_ARCH_UNIVERSAL;
    CHECK_INT(builder_resolve_architecture(&pkg, &opt), 0);
    CHECK_STR(pkg.architecture, "universal-apple-rhapsody");
    CHECK_INT(opt.effective_arch, RB_ARCH_UNIVERSAL);
    CHECK_INT(opt.operation_arch, RB_ARCH_UNIVERSAL);
    package_set(&pkg.architecture, "i386");
    opt.operation_arch = RB_ARCH_UNIVERSAL;
    CHECK(builder_resolve_architecture(&pkg, &opt) != 0);
    package_set(&pkg.architecture, "ppc");
    opt.operation_arch = RB_ARCH_UNIVERSAL;
    CHECK(builder_resolve_architecture(&pkg, &opt) != 0);
    package_set(&pkg.architecture, 0);
    opt.operation_arch = 0;
    CHECK_INT(builder_resolve_architecture(&pkg, &opt), 0);
    CHECK_STR(pkg.architecture, "ppc-apple-rhapsody");
    CHECK_INT(opt.effective_arch, RB_ARCH_PPC);
    package_free(&pkg);
}

TEST(test_build_rejects_unsupported_bootstrap_architecture) {
    BuildOptions opt;
    Toolchain tc;
    strlist repo;
    FILE *f;
    CHECK_INT(system("mkdir -p /tmp/rbuild-policy-source/dpkg /tmp/rbuild-policy-output"), 0);
    f = fopen("/tmp/rbuild-policy-source/dpkg/control", "w");
    CHECK(f != 0);
    if (!f) return;
    fputs("Package: policy\nVersion: 1.0\nDescription: policy\n", f);
    fclose(f);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    tc.target_arch = "m68k";
    opt.bootstrap = 1;
    opt.toolchain = &tc;
    strlist_init(&repo);
    exec_dry_run = 1;
    CHECK(builder_build("dir", "/tmp/rbuild-policy-source", &repo,
                        "all", "/tmp/rbuild-policy-output", &opt) != 0);
    tc.target_arch = "ppc";
    CHECK_INT(builder_build("dir", "/tmp/rbuild-policy-source", &repo,
                            "objs", "/tmp/rbuild-policy-output", &opt), 0);
    CHECK_INT(opt.operation_arch, 0);
    CHECK_INT(opt.effective_arch, 0);
    exec_dry_run = 0;
    strlist_free(&repo);
    system("rm -rf /tmp/rbuild-policy-source /tmp/rbuild-policy-output");
}

TEST(test_packaging_rejects_wrong_products) {
    Package pkg;
    Params params;
    BuildOptions opt;
    Toolchain tc;
    unsigned char code[28];
    FILE *f;
    int i;
    static const char *targets[] = { "binary", "headers", "objects", "local", 0 };
    system("rm -rf /tmp/rb-package-products && mkdir -p /tmp/rb-package-products/root /tmp/rb-package-products/apks");
    memset(code,0,sizeof(code));
    code[0]=0xfe; code[1]=0xed; code[2]=0xfa; code[3]=0xce;
    code[7]=7; code[15]=1;
    f=fopen("/tmp/rb-package-products/root/tool","wb");
    CHECK(f!=0);
    if (!f) return;
    CHECK_INT(fwrite(code,1,sizeof(code),f),sizeof(code)); fclose(f);
    package_init(&pkg); params_init(&params); build_options_init(&opt);
    toolchain_fixture(&tc);
    tc.archive_create="/usr/bin/false"; tc.gzip="/usr/bin/false";
    opt.toolchain=&tc;
    package_set(&pkg.package,"products");
    package_set(&pkg.version,"1");
    package_set(&pkg.architecture,"universal-apple-rhapsody");
    params.DSTROOT=xstrdup("/tmp/rb-package-products/root");
    params.HDRROOT=xstrdup(params.DSTROOT);
    params.LIBCOBJROOT=xstrdup(params.DSTROOT);
    params.PACKAGEDIR=xstrdup("/tmp/rb-package-products/apks");
    for(i=0;targets[i];i++) {
        unlink("/tmp/rb-package-products/root/.PKGINFO");
        CHECK_INT(builder_buildpackage(&pkg,&params,targets[i],&opt),1);
        CHECK(access("/tmp/rb-package-products/root/.PKGINFO",F_OK)!=0);
    }
    package_set(&pkg.architecture,"ppc");
    CHECK_INT(builder_buildpackage(&pkg,&params,"local",&opt),1);
    package_set(&pkg.architecture,"i386");
    CHECK_INT(builder_buildpackage(&pkg,&params,"local",&opt),0);
    package_set(&pkg.architecture,"universal-apple-rhapsody");
    opt.operation_arch=1;
    CHECK_INT(builder_buildpackage(&pkg,&params,"local",&opt),0);
    CHECK_STR(pkg.architecture,"universal-apple-rhapsody");
    CHECK_INT(opt.effective_arch,0);
    opt.operation_arch=0;
    exec_dry_run=1;
    CHECK_INT(builder_buildpackage(&pkg,&params,"local",&opt),0);
    CHECK(access("/tmp/rb-package-products/root/.PKGINFO",F_OK)!=0);
    for(i=0;targets[i];i++)
        CHECK_INT(builder_buildpackage(&pkg,&params,targets[i],&opt),0);
    exec_dry_run=0;
    CHECK_INT(system("mkdir -p /tmp/rb-package-products/source/dpkg && "
                     "mv /tmp/rb-package-products/root/tool "
                     "/tmp/rb-package-products/source/dpkg/postinst"), 0);
    params.SRCDIR = xstrdup("/tmp/rb-package-products/source");
    CHECK_INT(builder_buildpackage(&pkg, &params, "binary", &opt), 1);
    CHECK(access("/tmp/rb-package-products/root/.PKGINFO", F_OK) != 0);
    CHECK(access("/tmp/rb-package-products/root/postinst", F_OK) == 0);
    unlink("/tmp/rb-package-products/root/.PKGINFO");
    unlink("/tmp/rb-package-products/root/postinst");
    rmdir("/tmp/rb-package-products/root");
    CHECK_INT(builder_buildpackage(&pkg,&params,"objects",&opt),0);
    CHECK_INT(builder_buildpackage(&pkg,&params,"headers",&opt),0);
    CHECK_INT(builder_buildpackage(&pkg,&params,"local",&opt),1);
    f = fopen("/tmp/rb-package-products/source/dpkg/postinst", "w");
    CHECK(f != 0);
    if (f) { fputs("#!/bin/sh\nexit 0\n", f); fclose(f); }
    CHECK_INT(builder_buildpackage(&pkg, &params, "binary", &opt), 1);
    CHECK(access(params.DSTROOT, F_OK) != 0);
    params_free(&params); package_free(&pkg);
    system("rm -rf /tmp/rb-package-products");
}

TEST(test_build_validates_all_roots_before_packaging) {
    BuildOptions opt;
    Toolchain tc;
    strlist repo;
    FILE *f;
    unsigned char code[28];
    static const char *envs[] = {"BUILDROOT","SRCROOT","OBJROOT","SYMROOT",
        "DSTROOT","HDRROOT","LIBCOBJROOT","PACKAGEROOT",0};
    static const char *dirs[] = {"build","src","obj","sym","dst","hdr","objs","pkg"};
    int i;
    char path[256];
    system("rm -rf /tmp/rb-products-build && mkdir -p /tmp/rb-products-build/source/dpkg /tmp/rb-products-build/apks");
    f=fopen("/tmp/rb-products-build/source/dpkg/control","w");
    CHECK(f!=0); if (!f) return;
    fputs("Package: products\nVersion: 1\nDescription: products\n",f); fclose(f);
    memset(code,0,sizeof(code));
    code[0]=0xfe; code[1]=0xed; code[2]=0xfa; code[3]=0xce;
    code[7]=18; code[15]=1;
    f=fopen("/tmp/rb-products-build/wrong","wb");
    CHECK(f!=0); if (!f) return;
    fwrite(code,1,sizeof(code),f); fclose(f);
    code[7]=7;
    f=fopen("/tmp/rb-products-build/correct","wb"); CHECK(f!=0);
    if(f){fwrite(code,1,sizeof(code),f);fclose(f);}
    code[7]=18;
    f=fopen("/tmp/rb-products-build/make","w");
    CHECK(f!=0); if (!f) return;
    fputs("#!/bin/sh\nprevious=\nfor arg do\n"
          "test \"$previous\" != -C || dir=$arg\n"
          "case $arg in probe.o|probe) cp /tmp/rb-products-build/correct \"$dir/$arg\"; exit $?;; esac\n"
          "previous=$arg\ndone\n"
          "cp /tmp/rb-products-build/wrong /tmp/rb-products-build/dst/tool\n"
          "echo header > /tmp/rb-products-build/hdr/header.h\n",f);
    fclose(f); chmod("/tmp/rb-products-build/make",0755);
    for(i=0;envs[i];i++) {
        sprintf(path,"/tmp/rb-products-build/%s",dirs[i]);
        setenv(envs[i],path,1);
    }
    build_options_init(&opt); memset(&tc,0,sizeof(tc));
    tc.target_arch="i386"; tc.make="/tmp/rb-products-build/make";
    tc.rsync="/usr/bin/true";
    tc.archive_create="/usr/bin/false"; tc.gzip="/usr/bin/false";
    opt.bootstrap=1; opt.toolchain=&tc;
    strlist_init(&repo);
    CHECK_INT(builder_build("dir","/tmp/rb-products-build/source",&repo,
                            "all","/tmp/rb-products-build/apks",&opt),1);
    CHECK(access("/tmp/rb-products-build/hdr/.PKGINFO",F_OK)!=0);
    CHECK(access("/tmp/rb-products-build/dst/.PKGINFO",F_OK)!=0);
    /* The installed tool now matches, but an ancillary postinst is wrong. */
    CHECK_INT(system("cp /tmp/rb-products-build/wrong "
                     "/tmp/rb-products-build/source/dpkg/postinst"), 0);
    code[7] = 7;
    f = fopen("/tmp/rb-products-build/wrong", "wb");
    CHECK(f != 0);
    if (f) { fwrite(code, 1, sizeof(code), f); fclose(f); }
    CHECK_INT(builder_build("dir", "/tmp/rb-products-build/source", &repo,
                            "all", "/tmp/rb-products-build/apks", &opt), 1);
    CHECK(access("/tmp/rb-products-build/hdr/.PKGINFO", F_OK) != 0);
    CHECK(access("/tmp/rb-products-build/dst/.PKGINFO", F_OK) != 0);
    CHECK(access("/tmp/rb-products-build/dst/postinst", F_OK) == 0);
    for(i=0;envs[i];i++) unsetenv(envs[i]);
    strlist_free(&repo);
    system("rm -rf /tmp/rb-products-build");
}

TEST(test_packaging_dry_run_keeps_command_trace) {
    Package pkg;
    Params params;
    FILE *capture;
    int saved, result;
    size_t n;
    char trace[4096];
    package_init(&pkg);
    params_init(&params);
    package_set(&pkg.package, "dry-products");
    package_set(&pkg.version, "1");
    package_set(&pkg.architecture, "universal-apple-rhapsody");
    params.DSTROOT = xstrdup("/tmp/rb-products-dry-missing");
    params.PACKAGEDIR = xstrdup("/tmp/rb-products-dry-apks");
    system("rm -rf /tmp/rb-products-dry-missing /tmp/rb-products-dry-apks");
    capture = tmpfile();
    CHECK(capture != 0);
    if (!capture) { params_free(&params); package_free(&pkg); return; }
    fflush(stdout);
    saved = dup(STDOUT_FILENO);
    CHECK(saved >= 0);
    if (saved < 0) {
        fclose(capture); params_free(&params); package_free(&pkg); return;
    }
    CHECK(dup2(fileno(capture), STDOUT_FILENO) >= 0);
    exec_dry_run = 1;
    result = builder_buildpackage(&pkg, &params, "binary", 0);
    exec_dry_run = 0;
    fflush(stdout);
    dup2(saved, STDOUT_FILENO);
    close(saved);
    rewind(capture);
    n = fread(trace, 1, sizeof(trace)-1, capture);
    trace[n] = 0;
    fclose(capture);
    CHECK_INT(result, 0);
    CHECK(strstr(trace, "validate products in /tmp/rb-products-dry-missing") != 0);
    CHECK(strstr(trace, "mkdir -p /tmp/rb-products-dry-missing") != 0);
    CHECK(strstr(trace, "tar -C /tmp/rb-products-dry-missing -cf - .") != 0);
    CHECK(strstr(trace, "gzip -9") != 0);
    CHECK(access(params.DSTROOT, F_OK) != 0);
    CHECK(access(params.PACKAGEDIR, F_OK) != 0);
    params_free(&params);
    package_free(&pkg);
}

TEST(test_cache_checks_payload_architecture) {
    Package pkg;
    FILE *f;
    char *found;
    unsigned char code[28];
    CHECK_INT(system("rm -rf /tmp/rb-cache-policy && mkdir -p /tmp/rb-cache-policy/content /tmp/rb-cache-policy/repo"),0);
    f=fopen("/tmp/rb-cache-policy/content/.PKGINFO","w"); CHECK(f!=0);
    if (!f) return;
    fputs("pkgname = cache\npkgver = 1\narch = universal-apple-rhapsody\n",f); fclose(f);
    memset(code,0,sizeof(code)); code[0]=0xfe; code[1]=0xed; code[2]=0xfa; code[3]=0xce; code[7]=7; code[15]=1;
    f=fopen("/tmp/rb-cache-policy/content/tool","wb"); CHECK(f!=0);
    if (!f) return;
    fwrite(code,1,sizeof(code),f); fclose(f);
    CHECK_INT(system("(cd /tmp/rb-cache-policy/content && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > /tmp/rb-cache-policy/repo/cache-1.apk"),0);
    package_init(&pkg); package_set(&pkg.package,"cache"); package_set(&pkg.version,"1");
    package_set(&pkg.architecture,"universal-apple-rhapsody");
    found=builder_exists(&pkg,"any","/tmp/rb-cache-policy/repo");
    CHECK(found==0); free(found);
    CHECK(access("/tmp/rb-cache-policy/repo/cache-1.apk",F_OK)==0);
    CHECK(access("/tmp/rb-cache-policy/repo/cache-1.apk.invalid",F_OK)!=0);
    unlink("/tmp/rb-cache-policy/content/tool");
    CHECK_INT(system("(cd /tmp/rb-cache-policy/content && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > /tmp/rb-cache-policy/repo/cache-2.apk"),0);
    found=builder_exists(&pkg,"exact","/tmp/rb-cache-policy/repo");
    CHECK(found==0);free(found);
    found=builder_exists(&pkg,"any","/tmp/rb-cache-policy/repo");
    CHECK(found!=0);free(found);
    package_free(&pkg); system("rm -rf /tmp/rb-cache-policy");
}

static void cache_fixture(const char *repo, const char *name, const char *version,
                          const char *arch, int cpu) {
    char command[1024], path[256];
    FILE *f;
    unsigned char code[28];
    CHECK_INT(system("mkdir -p /tmp/rb-cache-fixture"),0);
    f=fopen("/tmp/rb-cache-fixture/.PKGINFO","w"); CHECK(f!=0); if(!f)return;
    fprintf(f,"pkgname = %s\npkgver = %s\narch = %s\n",name,version,arch); fclose(f);
    f=fopen("/tmp/rb-cache-fixture/tool","wb"); CHECK(f!=0); if(!f)return;
    if(cpu) {
        memset(code,0,sizeof(code)); code[0]=0xfe;code[1]=0xed;code[2]=0xfa;code[3]=0xce;code[7]=cpu;code[15]=1;
        fwrite(code,1,sizeof(code),f);
    } else fputs("data fixture",f);
    fclose(f);
    sprintf(path,"%s/%s-%s.apk",repo,name,version);
    sprintf(command,"(cd /tmp/rb-cache-fixture && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > %s",path);
    CHECK_INT(system(command),0);
}
TEST(test_dependency_fallback_and_reinstallation) {
    Package pkg;
    strlist repo;
    FILE *f;
    char data[32];
    CHECK_INT(system("rm -rf /tmp/rb-dep-policy && mkdir -p /tmp/rb-dep-policy/first /tmp/rb-dep-policy/second /tmp/rb-dep-policy/root/var/adm"),0);
    cache_fixture("/tmp/rb-dep-policy/first","dep","1","ppc",18);
    cache_fixture("/tmp/rb-dep-policy/first","dep","2","i386",7);
    package_init(&pkg); package_set(&pkg.architecture,"i386");
    pkg.has_build_depends=1; strlist_push(&pkg.build_depends,"dep");
    strlist_init(&repo); strlist_push(&repo,"/tmp/rb-dep-policy/first"); strlist_push(&repo,"/tmp/rb-dep-policy/second");
    f=fopen("/tmp/rb-dep-policy/root/var/adm/package-list","w");CHECK(f!=0);
    if(f){fputs("dep-2\n",f);fclose(f);}
    CHECK_INT(builder_makeroot(&pkg,"/tmp/rb-dep-policy/root",&repo),0);
    CHECK(access("/tmp/rb-dep-policy/root/tool",F_OK)==0);
    unlink("/tmp/rb-dep-policy/first/dep-2.apk");
    cache_fixture("/tmp/rb-dep-policy/second","dep","3","i386",7);
    CHECK_INT(builder_makeroot(&pkg,"/tmp/rb-dep-policy/root",&repo),0);
    package_set(&pkg.architecture,"universal-apple-rhapsody");
    f=fopen("/tmp/rb-dep-policy/root/tool","w"); CHECK(f!=0);
    if(f){fputs("untouched",f);fclose(f);}
    CHECK(builder_makeroot(&pkg,"/tmp/rb-dep-policy/root",&repo)!=0);
    f=fopen("/tmp/rb-dep-policy/root/tool","r"); CHECK(f!=0);
    if(f){data[0]=0;fgets(data,sizeof(data),f);fclose(f);CHECK_STR(data,"untouched");}
    cache_fixture("/tmp/rb-dep-policy/second","dep","3","ppc",0);
    CHECK_INT(builder_makeroot(&pkg,"/tmp/rb-dep-policy/root",&repo),0);
    package_free(&pkg);strlist_free(&repo);
    system("rm -rf /tmp/rb-dep-policy /tmp/rb-cache-fixture");
}
TEST(test_direct_publication_quarantines_collision) {
    Package pkg;
    Params params;
    BuildOptions opt;
    CHECK_INT(system("rm -rf /tmp/rb-publish-policy && mkdir -p /tmp/rb-publish-policy/root /tmp/rb-publish-policy/repo"),0);
    cache_fixture("/tmp/rb-publish-policy/repo","collision","1","universal-apple-rhapsody",7);
    package_init(&pkg);params_init(&params);build_options_init(&opt);
    package_set(&pkg.package,"collision");package_set(&pkg.version,"1");
    package_set(&pkg.architecture,"universal-apple-rhapsody");
    params.DSTROOT=xstrdup("/tmp/rb-publish-policy/root");
    params.PACKAGEDIR=xstrdup("/tmp/rb-publish-policy/repo");
    opt.force=1;
    CHECK_INT(builder_buildpackage(&pkg,&params,"binary",&opt),0);
    CHECK(access("/tmp/rb-publish-policy/repo/collision-1.apk.invalid",F_OK)==0);
    unlink("/tmp/rb-publish-policy/repo/collision-1.apk");
    CHECK_INT(symlink("/tmp/rb-publish-policy/outside","/tmp/rb-publish-policy/repo/collision-1.apk"),0);
    CHECK_INT(builder_buildpackage(&pkg,&params,"binary",&opt),0);
    CHECK(access("/tmp/rb-publish-policy/outside",F_OK)!=0);
    params_free(&params);package_free(&pkg);
    system("rm -rf /tmp/rb-publish-policy /tmp/rb-cache-fixture");
}

TEST(test_base_cache_does_not_hide_incompatible_companions) {
    BuildOptions opt;
    Toolchain tc;
    strlist repo;
    FILE *f;
    static const char *envs[]={"BUILDROOT","SRCROOT","OBJROOT","SYMROOT","DSTROOT","HDRROOT","LIBCOBJROOT","PACKAGEROOT",0};
    static const char *dirs[]={"build","src","obj","sym","dst","hdr","objs","pkg"};
    char path[256];int i;
    CHECK_INT(system("rm -rf /tmp/rb-companions && mkdir -p /tmp/rb-companions/source/dpkg /tmp/rb-companions/repo"),0);
    f=fopen("/tmp/rb-companions/source/dpkg/control","w");CHECK(f!=0);if(!f)return;
    fputs("Package: companions\nVersion: 1\nBuild-Depends:\n",f);fclose(f);
    cache_fixture("/tmp/rb-companions/repo","companions","1","universal-apple-rhapsody",0);
    cache_fixture("/tmp/rb-companions/repo","companions-obj","1","universal-apple-rhapsody",7);
    for(i=0;envs[i];i++){sprintf(path,"/tmp/rb-companions/%s",dirs[i]);setenv(envs[i],path,1);}
    build_options_init(&opt);toolchain_init(&tc);tc.make="/usr/bin/false";tc.rsync="/usr/bin/true";opt.toolchain=&tc;
    tc.tar="tar";tc.gzip="gzip";
    strlist_init(&repo);
    CHECK(builder_build("dir","/tmp/rb-companions/source",&repo,"all","/tmp/rb-companions/repo",&opt)!=0);
    CHECK(access("/tmp/rb-companions/repo/companions-obj-1.apk.invalid",F_OK)==0);
    /* Absent companions are optional and do not invalidate a valid base. */
    CHECK_INT(builder_build("dir","/tmp/rb-companions/source",&repo,"all","/tmp/rb-companions/repo",&opt),0);
    cache_fixture("/tmp/rb-companions/repo","companions-hdrs","1","universal-apple-rhapsody",7);
    CHECK(builder_build("dir","/tmp/rb-companions/source",&repo,"headers","/tmp/rb-companions/repo",&opt)!=0);
    CHECK(access("/tmp/rb-companions/repo/companions-hdrs-1.apk.invalid",F_OK)==0);
    cache_fixture("/tmp/rb-companions/repo","companions","1","universal-apple-rhapsody",7);
    f=fopen("/tmp/rb-companions/repo/companions-1.apk.invalid","w");CHECK(f!=0);
    if(f){fputs("preserve old quarantine",f);fclose(f);}
    CHECK(builder_build("dir","/tmp/rb-companions/source",&repo,"binary","/tmp/rb-companions/repo",&opt)!=0);
    CHECK(access("/tmp/rb-companions/repo/companions-1.apk",F_OK)==0);
    for(i=0;envs[i];i++)unsetenv(envs[i]);
    strlist_free(&repo);system("rm -rf /tmp/rb-companions /tmp/rb-cache-fixture");
}

/* The compiler shim emits on-disk code, never a host executable. */
static void probe_fixture(void) {
    FILE *f;
    unsigned char code[28];
    int i;
    CHECK_INT(system("rm -rf /tmp/rb-probe-tools && mkdir -p /tmp/rb-probe-tools/bin /tmp/rb-probe-tools/obj"),0);
    for (i=0;i<2;i++) {
        memset(code,0,sizeof(code)); code[0]=0xfe;code[1]=0xed;code[2]=0xfa;code[3]=0xce;
        code[7]=i ? 18 : 7; code[15]=1;
        f=fopen(i ? "/tmp/rb-probe-tools/ppc" : "/tmp/rb-probe-tools/i386","wb");
        CHECK(f!=0); if(f){fwrite(code,1,sizeof(code),f);fclose(f);}
    }
    f=fopen("/tmp/rb-probe-tools/bin/cc","w"); CHECK(f!=0); if(!f)return;
    fputs("#!/bin/sh\narch=none\nout=\nstage=link\n"
          "echo \"$*\" >> /tmp/rb-probe-tools/args\n"
          "while test $# -gt 0; do\ncase \"$1\" in\n"
          "-arch) shift; arch=$1;;\n-o) shift; out=$1;;\n-c) stage=compile;;\nesac\nshift\ndone\n"
          "echo $arch-$stage >> /tmp/rb-probe-tools/calls\n"
          "case $RB_PROBE_MODE in\nextra) touch probe.d;;\nnoop) exit 0;;\nwrong) arch=ppc;;\n"
          "wronglink) test $stage != link || arch=ppc;;\n"
          "second) test $arch != ppc || exit 1;;\nlink) test $stage != link || exit 1;;\nesac\n"
          "cp /tmp/rb-probe-tools/$arch \"$out\"\n",f);
    fclose(f); chmod("/tmp/rb-probe-tools/bin/cc",0755);
    f=fopen("/tmp/rb-probe-tools/bin/chroot","w"); CHECK(f!=0); if(!f)return;
    fputs("#!/bin/sh\necho chroot >> /tmp/rb-probe-tools/chroots\nshift\nexec \"$@\"\n",f);
    fclose(f); chmod("/tmp/rb-probe-tools/bin/chroot",0755);
}
static int probe_text_has(const char *file, const char *needle) {
    FILE *f=fopen(file,"r");
    char data[8192]; size_t n;
    if(!f)return 0;
    n=fread(data,1,sizeof(data)-1,f);data[n]=0;fclose(f);
    return strstr(data,needle)!=0;
}
static void write_macho(const char *path, unsigned char cputype) {
    unsigned char code[28];
    FILE *f;
    memset(code, 0, sizeof(code));
    code[0] = 0xfe; code[1] = 0xed; code[2] = 0xfa; code[3] = 0xce;
    code[7] = cputype;
    code[15] = 1;
    f = fopen(path, "wb");
    CHECK(f != 0);
    if (!f) return;
    CHECK_INT(fwrite(code, 1, sizeof(code), f), sizeof(code));
    fclose(f);
}
TEST(test_toolchain_probes) {
    Params p;
    BuildOptions opt;
    Toolchain tc;
    FILE *f;
    static const char *modes[]={"wrong","wronglink","second","link","noop",0};
    int i;
    probe_fixture(); params_init(&p); build_options_init(&opt); toolchain_init(&tc);
    p.OBJROOT="/tmp/rb-probe-tools/obj";p.BUILDROOT="/unused-probe-root";
    p.SYMROOT=p.OBJROOT;
    tc.path="/tmp/rb-probe-tools/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    opt.toolchain=&tc;opt.effective_arch=3;
    setenv("RB_PROBE_MODE","ok",1);
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","i386-compile"));
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","ppc-link"));
    CHECK(probe_text_has("/tmp/rb-probe-tools/chroots","chroot"));
    for(i=0;modes[i];i++) {
        setenv("RB_PROBE_MODE",modes[i],1);
        CHECK_INT(builder_probe_toolchain(&p,&p,&opt),1);
    }
    setenv("RB_PROBE_MODE","extra",1);
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    opt.bootstrap=1;opt.effective_arch=1;
    tc.target_cc="/tmp/rb-probe-tools/bin/cc";tc.arch_flags="-arch i386";
    tc.cpp_flags="-I/probe-include";tc.ld_flags="-L/probe-library";
    tc.ld_flags_ready="@SYSROOT@/ready";opt.sysroot="/tmp/rb-probe-tools";
    setenv("RB_PROBE_MODE","link",1);
    unlink("/tmp/rb-probe-tools/calls");
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    CHECK(!probe_text_has("/tmp/rb-probe-tools/calls","link"));
    f=fopen("/tmp/rb-probe-tools/ready","w");CHECK(f!=0);if(f)fclose(f);
    unlink("/tmp/rb-probe-tools/calls");
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    CHECK(!probe_text_has("/tmp/rb-probe-tools/calls","link"));
    mkdir("/tmp/rb-probe-tools/lib", 0755);
    write_macho("/tmp/rb-probe-tools/ready", 18);
    write_macho("/tmp/rb-probe-tools/lib/crt1.o", 18);
    setenv("RB_PROBE_MODE","ok",1);
    unlink("/tmp/rb-probe-tools/calls");
    opt.effective_arch=3;
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","i386-compile"));
    CHECK(!probe_text_has("/tmp/rb-probe-tools/calls","i386-link"));
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","ppc-link"));
    write_macho("/tmp/rb-probe-tools/ready", 7);
    write_macho("/tmp/rb-probe-tools/lib/crt1.o", 7);
    unlink("/tmp/rb-probe-tools/calls");
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","i386-link"));
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","ppc-compile"));
    CHECK(!probe_text_has("/tmp/rb-probe-tools/calls","ppc-link"));
    opt.effective_arch=1;
    CHECK(probe_text_has("/tmp/rb-probe-tools/args","-I/probe-include"));
    CHECK(probe_text_has("/tmp/rb-probe-tools/args","-L/probe-library"));
    tc.ld_flags_ready=0;tc.arch_flags="-arch ppc";
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),1);
    tc.arch_flags="-arch i386";
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    unlink("/tmp/rb-probe-tools/calls");
    p.OBJROOT="/tmp/rb-probe-tools/missing";
    exec_dry_run=1;
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    exec_dry_run=0;
    CHECK(access(p.OBJROOT,F_OK)!=0);
    CHECK(access("/tmp/rb-probe-tools/calls",F_OK)!=0);
    unsetenv("RB_PROBE_MODE");
    system("rm -rf /tmp/rb-probe-tools");
}

TEST(test_probe_failure_precedes_project_make) {
    BuildOptions opt;
    Toolchain tc;
    strlist repo;
    FILE *f;
    static const char *envs[]={"BUILDROOT","SRCROOT","OBJROOT","SYMROOT","DSTROOT","HDRROOT","LIBCOBJROOT","PACKAGEROOT",0};
    static const char *dirs[]={"build","src","obj","sym","dst","hdr","objs","pkg"};
    char path[256]; int i;
    probe_fixture();
    CHECK_INT(system("mkdir -p /tmp/rb-probe-tools/source/dpkg /tmp/rb-probe-tools/repo"),0);
    f=fopen("/tmp/rb-probe-tools/source/dpkg/control","w"); CHECK(f!=0);if(!f)return;
    fputs("Package: probes\nVersion: 1\nBuild-Depends:\n",f);fclose(f);
    f=fopen("/tmp/rb-probe-tools/make","w");CHECK(f!=0);if(!f)return;
    fputs("#!/bin/sh\nfor arg do\ncase $arg in probe.o|probe) exec /bin/make \"$@\";; esac\ndone\n"
          "echo project >> /tmp/rb-probe-tools/project\nexit 1\n",f);
    fclose(f);chmod("/tmp/rb-probe-tools/make",0755);
    for(i=0;envs[i];i++){sprintf(path,"/tmp/rb-probe-tools/%s",dirs[i]);setenv(envs[i],path,1);}
    build_options_init(&opt);toolchain_init(&tc);strlist_init(&repo);
    tc.target_arch="i386";tc.arch_flags="-arch i386";
    tc.target_cc="/tmp/rb-probe-tools/bin/cc";tc.make="/tmp/rb-probe-tools/make";
    tc.rsync="/usr/bin/true";opt.bootstrap=1;opt.toolchain=&tc;
    setenv("RB_PROBE_MODE","link",1);
    CHECK_INT(builder_build("dir","/tmp/rb-probe-tools/source",&repo,"all","/tmp/rb-probe-tools/repo",&opt),1);
    CHECK(access("/tmp/rb-probe-tools/project",F_OK)!=0);
    CHECK(access("/tmp/rb-probe-tools/hdr/.PKGINFO",F_OK)!=0);
    CHECK(access("/tmp/rb-probe-tools/dst/.PKGINFO",F_OK)!=0);
    unlink("/tmp/rb-probe-tools/project");unlink("/tmp/rb-probe-tools/calls");
    CHECK_INT(builder_build("dir","/tmp/rb-probe-tools/source",&repo,"headers","/tmp/rb-probe-tools/repo",&opt),1);
    CHECK(access("/tmp/rb-probe-tools/project",F_OK)==0);
    CHECK(access("/tmp/rb-probe-tools/calls",F_OK)!=0);
    for(i=0;envs[i];i++)unsetenv(envs[i]);
    unsetenv("RB_PROBE_MODE");strlist_free(&repo);
    system("rm -rf /tmp/rb-probe-tools");
}

TEST(test_fallback_preserves_explicit_architecture) {
    static const char *controls[]={"Package: fallback\nArchitecture: i386\n",
        "Version: 1\nArchitecture: ppc\n"};
    static const char *labels[]={"i386","ppc"};
    Package pkg;Params params;FILE *f;int i;
    CHECK_INT(system("mkdir -p /tmp/rb-thin-fallback-1/dpkg"),0);
    for(i=0;i<2;i++) {
        f=fopen("/tmp/rb-thin-fallback-1/dpkg/control","w");CHECK(f!=0);if(!f)return;
        fputs(controls[i],f);fclose(f);package_init(&pkg);params_init(&params);
        CHECK_INT(builder_scan("dir","/tmp/rb-thin-fallback-1",&pkg,&params),0);
        CHECK_STR(pkg.architecture,labels[i]);
        package_free(&pkg);params_free(&params);
    }
    system("rm -rf /tmp/rb-thin-fallback-1");
}
TEST(test_direct_packaging_missing_architecture_defaults_universal) {
    Package pkg;Params params;FILE *f;char data[1024];size_t n;
    CHECK_INT(system("rm -rf /tmp/rb-default-package && mkdir -p /tmp/rb-default-package/root /tmp/rb-default-package/repo"),0);
    package_init(&pkg);params_init(&params);
    package_set(&pkg.package,"default");package_set(&pkg.version,"1");
    params.DSTROOT=xstrdup("/tmp/rb-default-package/root");params.PACKAGEDIR=xstrdup("/tmp/rb-default-package/repo");
    CHECK_INT(builder_buildpackage(&pkg,&params,"binary",0),0);
    CHECK(pkg.architecture==0);
    f=fopen("/tmp/rb-default-package/root/.PKGINFO","r");CHECK(f!=0);
    if(f){n=fread(data,1,sizeof(data)-1,f);data[n]=0;fclose(f);
        CHECK(strstr(data,"arch = universal-apple-rhapsody\n")!=0);}
    package_set(&pkg.architecture,"");
    CHECK(builder_buildpackage(&pkg,&params,"binary",0)!=0);
    CHECK_STR(pkg.architecture,"");
    package_free(&pkg);params_free(&params);system("rm -rf /tmp/rb-default-package");
}

static void run_all(void) {
    RUN(test_fallback_preserves_explicit_architecture);
    RUN(test_direct_packaging_missing_architecture_defaults_universal);
    RUN(test_probe_failure_precedes_project_make);
    RUN(test_toolchain_probes);
    RUN(test_base_cache_does_not_hide_incompatible_companions);
    RUN(test_dependency_fallback_and_reinstallation);
    RUN(test_direct_publication_quarantines_collision);
    RUN(test_cache_checks_payload_architecture);
    RUN(test_packaging_dry_run_keeps_command_trace);
    RUN(test_build_validates_all_roots_before_packaging);
    RUN(test_packaging_rejects_wrong_products);
    RUN(test_resolved_thin_flags);
    RUN(test_bootstrap_universal_resolve);
    RUN(test_build_rejects_unsupported_bootstrap_architecture);
    RUN(test_scan_architecture_labels);
    RUN(test_scan_rejects_invalid_architecture);
    RUN(test_dir2name);
    RUN(test_pkgname);
    RUN(test_match_pkgfile);
    RUN(test_resolve_and_exists);
    RUN(test_getparams_defaults);
    RUN(test_canonparams);
    RUN(test_chrootparams);
    RUN(test_bootstrap_flags_use_target_sysroot);
    RUN(test_buildflags);
    RUN(test_buildcmd_bootstrap);
    RUN(test_bootstrap_make_flags_wait_for_ready_path);
    RUN(test_bootstrap_coreos_makefiles_wait_for_sysroot);
    RUN(test_bootstrap_ld_flags_wait_for_ready_path);
    RUN(test_bootstrap_cpp_flags_wait_for_ready_path);
    RUN(test_bootstrap_indr_from_sysroot);
    RUN(test_bootstrap_harvest_stays_in_private_object_root);
    RUN(test_setupdirs_bootstrap_skips_makeroot);
    RUN(test_makeroot_dry_run_preserves_package_list);
    RUN(test_scan_dir);
    RUN(test_relativize_absolute_symlinks_inside_dstroot);
}

TEST_MAIN()
