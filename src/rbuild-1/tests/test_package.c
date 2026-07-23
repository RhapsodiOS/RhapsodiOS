#include "package.h"
#include "test.h"
#include <stdlib.h>

TEST(test_parse_basic) {
    Package p;
    package_init(&p);
    package_parse(&p,
        "Package: objc4\n"
        "Maintainer: Darwin Developers <d@x>\n"
        "Version: 174\n"
        "Description: Objective-C runtime\n"
        "Build-Depends: build-base, libstreams-hdrs architecture-hdrs\n");
    CHECK_STR(p.package, "objc4");
    CHECK_STR(p.version, "174");
    CHECK_STR(p.maintainer, "Darwin Developers <d@x>");
    CHECK_STR(p.description, "Objective-C runtime");
    CHECK_INT(p.has_build_depends, 1);
    CHECK_INT(p.build_depends.count, 3);
    CHECK_STR(p.build_depends.items[0], "build-base");
    CHECK_STR(p.build_depends.items[2], "architecture-hdrs");
    package_free(&p);
}

TEST(test_parse_continuation) {
    Package p;
    package_init(&p);
    package_parse(&p,
        "Package: foo\n"
        "Version: 1\n"
        "Description: line one\n"
        " line two\n");
    CHECK_STR(p.description, "line one\n line two");
    package_free(&p);
}

TEST(test_canon_names) {
    Package p;
    char *v, *n;
    package_init(&p);
    package_parse(&p, "Package: foo\nVersion: 1.2-3\n");
    package_set(&p.architecture, "universal-apple-rhapsody");
    v = package_canon_version(&p);
    n = package_canon_name(&p);
    CHECK_STR(v, "1.2-3");
    CHECK_STR(n, "foo-1.2-3");
    free(v); free(n);
    package_free(&p);
}

TEST(test_unparse_order) {
    Package p;
    char *out;
    package_init(&p);
    package_set(&p.package, "foo");
    package_set(&p.maintainer, "M <m@x>");
    package_set(&p.version, "1");
    package_set(&p.source, "foo");
    package_set(&p.architecture, "universal-apple-rhapsody");
    package_set(&p.description, "d");
    out = package_unparse(&p);
    CHECK_STR(out,
        "Package: foo\n"
        "Maintainer: M <m@x>\n"
        "Version: 1\n"
        "Source: foo\n"
        "Architecture: universal-apple-rhapsody\n"
        "Description: d\n");
    free(out);
    package_free(&p);
}

static void run_all(void) {
    RUN(test_parse_basic);
    RUN(test_parse_continuation);
    RUN(test_canon_names);
    RUN(test_unparse_order);
}

TEST_MAIN()
