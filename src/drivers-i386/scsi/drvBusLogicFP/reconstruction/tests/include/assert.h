#ifndef BLFP_TEST_ASSERT_H
#define BLFP_TEST_ASSERT_H
void blfp_test_assert_failed(int line);
void abort(void);
#define assert(condition) ((condition) ? (void)0 : blfp_test_assert_failed(__LINE__))
#endif
