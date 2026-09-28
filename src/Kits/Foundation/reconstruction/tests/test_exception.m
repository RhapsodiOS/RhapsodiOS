/*  Behavioural tests for NSException and the handler stack, stage 2b.
    These use the real NS_DURING / NS_HANDLER macros from NSException.h,
    so the macros are under test alongside the functions they call.  */

#import <Foundation/NSException.h>
#import <Foundation/NSObject.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

extern unsigned _NSExceptionHandlerCount(void);
extern void _NSClearExceptionStack(void);

static void test_handler_stack_starts_empty(void)
{
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_adding_and_removing_a_handler_balances(void)
{
    NSHandler2 handler;

    _NSAddHandler2(&handler);
    CHECK(_NSExceptionHandlerCount() == 1);
    _NSRemoveHandler2(&handler);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_handlers_nest(void)
{
    NSHandler2 outer;
    NSHandler2 inner;

    _NSAddHandler2(&outer);
    _NSAddHandler2(&inner);
    CHECK(_NSExceptionHandlerCount() == 2);
    _NSRemoveHandler2(&inner);
    _NSRemoveHandler2(&outer);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_a_handler_with_no_exception_reports_nil(void)
{
    NSHandler2 handler;

    _NSAddHandler2(&handler);
    CHECK(_NSExceptionObjectFromHandler2(&handler) == nil);
    _NSRemoveHandler2(&handler);
}

static void test_NS_DURING_normal_path_skips_the_handler(void)
{
    int ranBody = 0;
    int ranHandler = 0;

    NS_DURING
        ranBody = 1;
    NS_HANDLER
        ranHandler = 1;
    NS_ENDHANDLER

    CHECK(ranBody == 1);
    CHECK(ranHandler == 0);
    CHECK(_NSExceptionHandlerCount() == 0);
}

int main(void)
{
    test_handler_stack_starts_empty();
    test_adding_and_removing_a_handler_balances();
    test_handlers_nest();
    test_a_handler_with_no_exception_reports_nil();
    test_NS_DURING_normal_path_skips_the_handler();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
