/*  Behavioural tests for NSInvocation, stage 2c, Task 5:
    construction and bookkeeping.  Marshaling is Task 6, coding is
    Task 7, invocation itself is Task 8.  */

#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
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

static void test_invocationWithMethodSignature_has_the_given_signature(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];

    CHECK(invocation != nil);
    CHECK([invocation methodSignature] == sig);
}

static void test_selector_and_target_round_trip(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[NSObject alloc] init];

    [invocation setSelector:@selector(description)];
    CHECK([invocation selector] == @selector(description));

    [invocation setTarget:target];
    CHECK([invocation target] == target);

    [target release];
}

static void test_arguments_are_not_retained_until_asked(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];

    CHECK(![invocation argumentsRetained]);
    [invocation retainArguments];
    CHECK([invocation argumentsRetained]);
}

static void test_retain_release_use_the_invocations_own_count(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];

    CHECK([invocation retainCount] == 1);
    [invocation retain];
    CHECK([invocation retainCount] == 2);
    [invocation release];
    CHECK([invocation retainCount] == 1);
}

int main(void)
{
    /*  The guest's stdio block-buffers pipes; a crash mid-suite would
        otherwise swallow every FAIL line printed before it.  */
    setvbuf(stdout, NULL, _IONBF, 0);

    test_invocationWithMethodSignature_has_the_given_signature();
    test_selector_and_target_round_trip();
    test_arguments_are_not_retained_until_asked();
    test_retain_release_use_the_invocations_own_count();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
