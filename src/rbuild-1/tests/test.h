#ifndef RBUILD_TEST_H
#define RBUILD_TEST_H

#include <stdio.h>
#include <string.h>

static int test_failures = 0;
static int test_checks = 0;

#define CHECK(cond) \
    do { \
        test_checks++; \
        if (!(cond)) { \
            printf("  FAIL %s:%d: CHECK(%s)\n", __FILE__, __LINE__, #cond); \
            test_failures++; \
        } \
    } while (0)

#define CHECK_STR(got, want) \
    do { \
        const char *g_ = (got); \
        const char *w_ = (want); \
        test_checks++; \
        if (g_ == 0 || w_ == 0 || strcmp(g_, w_) != 0) { \
            printf("  FAIL %s:%d: got \"%s\" want \"%s\"\n", \
                   __FILE__, __LINE__, g_ ? g_ : "(null)", w_ ? w_ : "(null)"); \
            test_failures++; \
        } \
    } while (0)

#define CHECK_INT(got, want) \
    do { \
        long g_ = (long)(got); \
        long w_ = (long)(want); \
        test_checks++; \
        if (g_ != w_) { \
            printf("  FAIL %s:%d: got %ld want %ld\n", \
                   __FILE__, __LINE__, g_, w_); \
            test_failures++; \
        } \
    } while (0)

#define TEST(name) static void name(void)
#define RUN(name) \
    do { printf("- %s\n", #name); name(); } while (0)

#define TEST_MAIN() \
    int main(void) { \
        run_all(); \
        printf("%s: %d checks, %d failures\n", \
               __FILE__, test_checks, test_failures); \
        return test_failures ? 1 : 0; \
    }

#endif
