#include "builder.h"
#include "test.h"
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

static void run_all(void) {
    RUN(test_dir2name);
    RUN(test_pkgname);
    RUN(test_match_pkgfile);
    RUN(test_resolve_and_exists);
}

TEST_MAIN()
