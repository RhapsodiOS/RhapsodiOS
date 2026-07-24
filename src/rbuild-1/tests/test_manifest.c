#include "manifest.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>

TEST(test_manifest_file) {
    Manifest m;
    FILE *f = fopen("/tmp/rbtest_srclist", "w");
    fputs("# a comment\n"
          "\n"
          "dir  /src/gnumake-3.79   all\n"
          "dir /src/objc4-174\n"
          "   \n"
          "dir /src/foo # trailing comment\n", f);
    fclose(f);

    manifest_init(&m);
    CHECK_INT(manifest_read(&m, "/tmp/rbtest_srclist"), 0);
    CHECK_INT(m.count, 3);
    CHECK_STR(m.items[0].type, "dir");
    CHECK_STR(m.items[0].source, "/src/gnumake-3.79");
    CHECK_STR(m.items[0].targets, "all");
    CHECK_STR(m.items[1].source, "/src/objc4-174");
    CHECK(m.items[1].targets == 0);
    CHECK_STR(m.items[2].source, "/src/foo");
    manifest_free(&m);
    remove("/tmp/rbtest_srclist");
}

static void run_all(void) {
    RUN(test_manifest_file);
}

TEST_MAIN()
