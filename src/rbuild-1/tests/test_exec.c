#include "exec.h"
#include "test.h"
#include <stdlib.h>

TEST(test_checkret_strings) {
    char *a = exec_checkret(0);
    char *b = exec_checkret(2 << 8);      /* exit status 2 */
    CHECK_STR(a, "exited successfully");
    CHECK_STR(b, "failed with status 2");
    free(a); free(b);
}

TEST(test_run_true_false) {
    char *ok[] = { "true", 0 };
    char *bad[] = { "false", 0 };
    CHECK_INT(exec_run(ok), 0);
    CHECK(exec_run(bad) != 0);
}

TEST(test_dry_run) {
    char *cmd[] = { "false", 0 };
    exec_dry_run = 1;
    CHECK_INT(exec_run(cmd), 0);   /* not actually run */
    exec_dry_run = 0;
}

static void run_all(void) {
    RUN(test_checkret_strings);
    RUN(test_run_true_false);
    RUN(test_dry_run);
}

TEST_MAIN()
