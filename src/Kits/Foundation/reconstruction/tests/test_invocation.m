/*  Behavioural tests for NSInvocation, stage 2c, Task 5:
    construction and bookkeeping.  Marshaling is Task 6, coding is
    Task 7, invocation itself is Task 8.  */

#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
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

static void test_setArgument_and_getArgument_round_trip_an_int(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12i16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int sent = 99;
    int received = 0;

    [invocation setArgument:&sent atIndex:2];
    [invocation getArgument:&received atIndex:2];
    CHECK(received == 99);
}

static void test_setArgument_and_getArgument_round_trip_an_object(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id sent = [[NSObject alloc] init];
    id received = nil;

    [invocation setArgument:&sent atIndex:2];
    [invocation getArgument:&received atIndex:2];
    CHECK(received == sent);
    [sent release];
}

static void test_setReturnValue_and_getReturnValue_round_trip(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int sent = 123;
    int received = 0;

    [invocation setReturnValue:&sent];
    [invocation getReturnValue:&received];
    CHECK(received == 123);
}

static void test_getArgument_at_index_zero_and_one_reads_self_and_cmd(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[NSObject alloc] init];
    id readSelf;
    SEL readCmd;

    [invocation setTarget:target];
    [invocation setSelector:@selector(description)];
    [invocation getArgument:&readSelf atIndex:0];
    [invocation getArgument:&readCmd atIndex:1];
    /*  Index 0/1 read self/_cmd from the argument FRAME -- the slots
        setTarget:/setSelector: write (see Task 5).  This test proves
        the frame's slots are distinctly addressable and carry what
        was written, not that -invoke has run.  */
    CHECK(readSelf == target);
    CHECK(readCmd == @selector(description));
    [target release];
}

static void test_getArgument_out_of_range_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;
    int dummy;

    NS_DURING
        [invocation getArgument:&dummy atIndex:9];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

/*  Review Focus item 2: setArgument:atIndex: shares
    getArgument:atIndex:'s bounds check, but is a separate entry point
    and gets its own test rather than resting on symmetry.  */
static void test_setArgument_out_of_range_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;
    int dummy = 1;

    NS_DURING
        [invocation setArgument:&dummy atIndex:9];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

/*  Review Focus item 1: a NULL argument/return pointer.  Neither
    header documents a nullability contract; an unchecked memcpy on a
    NULL pointer is undefined behaviour, not a defined failure a
    caller can catch -- these four raise instead.  */
static void test_getArgument_with_a_null_location_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12i16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    NS_DURING
        [invocation getArgument:NULL atIndex:2];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_setArgument_with_a_null_location_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12i16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    NS_DURING
        [invocation setArgument:NULL atIndex:2];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_getReturnValue_with_a_null_location_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    NS_DURING
        [invocation getReturnValue:NULL];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_setReturnValue_with_a_null_location_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    NS_DURING
        [invocation setReturnValue:NULL];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
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
    test_setArgument_and_getArgument_round_trip_an_int();
    test_setArgument_and_getArgument_round_trip_an_object();
    test_setReturnValue_and_getReturnValue_round_trip();
    test_getArgument_at_index_zero_and_one_reads_self_and_cmd();
    test_getArgument_out_of_range_raises();
    test_setArgument_out_of_range_raises();
    test_getArgument_with_a_null_location_raises();
    test_setArgument_with_a_null_location_raises();
    test_getReturnValue_with_a_null_location_raises();
    test_setReturnValue_with_a_null_location_raises();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
