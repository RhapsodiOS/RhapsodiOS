#include "pkginfo.h"
#include "package.h"
#include "test.h"
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

static void run_all(void) {
    RUN(test_pkginfo_write);
}

TEST_MAIN()
