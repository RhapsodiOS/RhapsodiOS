#include "package.h"
#include "architecture.h"
#include "test.h"
#include <stdlib.h>

TEST(test_package_copy) {
    Package src, dst;
    package_init(&src);
    package_set(&src.package, "foo");
    package_set(&src.version, "1");
    package_set(&src.url, "http://x");
    package_set(&src.license, "unknown");
    strlist_push(&src.build_depends, "build-base");
    src.has_build_depends = 1;
    package_init(&dst);
    CHECK_INT(package_copy(&dst, &src), 0);
    CHECK_STR(dst.package, "foo");
    CHECK_STR(dst.url, "http://x");
    CHECK_STR(dst.license, "unknown");
    CHECK_INT(dst.build_depends.count, 1);
    package_set(&src.package, "bar");
    CHECK_STR(dst.package, "foo");
    package_free(&src);
    package_free(&dst);
}

TEST(test_canon_names) {
    Package p;
    char *v, *n;
    package_init(&p);
    package_set(&p.package, "foo");
    package_set(&p.version, "1.2-3");
    package_set(&p.architecture, "universal-apple-rhapsody");
    v = package_canon_version(&p);
    n = package_canon_name(&p);
    CHECK_STR(v, "1.2-3");
    CHECK_STR(n, "foo-1.2-3-universal");
    free(v); free(n);

    package_set(&p.architecture, "i386-apple-rhapsody");
    n = package_canon_name(&p);
    CHECK_STR(n, "foo-1.2-3-i386");
    free(n);

    package_set(&p.architecture, "ppc-apple-rhapsody");
    n = package_canon_name(&p);
    CHECK_STR(n, "foo-1.2-3-ppc");
    free(n);

    package_set(&p.architecture, 0);
    n = package_canon_name(&p);
    CHECK_STR(n, "foo-1.2-3-universal");
    free(n);

    package_set(&p.architecture, "");
    n = package_canon_name(&p);
    CHECK(n == 0);

    package_set(&p.architecture, "m68k");
    n = package_canon_name(&p);
    CHECK(n == 0);
    package_free(&p);
}

static void run_all(void) {
    RUN(test_package_copy);
    RUN(test_canon_names);
}

TEST_MAIN()
