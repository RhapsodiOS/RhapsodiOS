/*  Behavioural tests for NSObjCRuntime, stage 2b.  */

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <objc/objc-runtime.h>
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

/*  Reads an NSString the way this stage builds one: stage 2b has no real
    NSString, so both literals and the strings these functions return are
    NXConstantString-shaped records (see NSObjCRuntime.m's own comment).  */
static const char *TestStringBytes(id string)
{
    struct { Class isa; char *c_string; unsigned int len; } *record = (void *)string;

    return (string == nil) ? NULL : record->c_string;
}

#define CHECK_STRING(actual, expected) \
    do { \
        const char *bytes = TestStringBytes(actual); \
        if (bytes == NULL || strcmp(bytes, (expected)) != 0) { \
            printf("FAIL %s:%d expected \"%s\", got \"%s\"\n", \
                   __FILE__, __LINE__, (expected), bytes ? bytes : "(null)"); \
            failures++; \
        } \
    } while (0)

static void test_NSStringFromClass_gives_the_class_name(void)
{
    CHECK_STRING(NSStringFromClass([NSObject class]), "NSObject");
}

static void test_NSStringFromClass_of_Nil_is_nil(void)
{
    CHECK(NSStringFromClass(Nil) == nil);
}

static void test_NSClassFromString_finds_a_registered_class(void)
{
    CHECK(NSClassFromString(@"NSObject") == [NSObject class]);
}

static void test_NSClassFromString_of_an_unknown_name_is_Nil(void)
{
    CHECK(NSClassFromString(@"NSNoSuchClassExistsHere") == Nil);
}

static void test_NSStringFromSelector_gives_the_selector_name(void)
{
    CHECK_STRING(NSStringFromSelector(@selector(description)), "description");
    CHECK_STRING(NSStringFromSelector(@selector(isEqual:)), "isEqual:");
}

static void test_NSSelectorFromString_round_trips(void)
{
    SEL selector = NSSelectorFromString(@"isEqual:");

    CHECK(selector == @selector(isEqual:));
    CHECK_STRING(NSStringFromSelector(selector), "isEqual:");
}

static void test_NSSelectorFromString_registers_an_unseen_name(void)
{
    SEL selector = NSSelectorFromString(@"aSelectorNoOneHasUsedYet:");

    CHECK(selector != NULL);
    CHECK_STRING(NSStringFromSelector(selector), "aSelectorNoOneHasUsedYet:");
}

static void test_conversions_of_nil_are_safe(void)
{
    CHECK(NSClassFromString(nil) == Nil);
    CHECK(NSSelectorFromString(nil) == NULL);
    CHECK(NSStringFromSelector(NULL) == nil);
}

int main(void)
{
    test_NSStringFromClass_gives_the_class_name();
    test_NSStringFromClass_of_Nil_is_nil();
    test_NSClassFromString_finds_a_registered_class();
    test_NSClassFromString_of_an_unknown_name_is_Nil();
    test_NSStringFromSelector_gives_the_selector_name();
    test_NSSelectorFromString_round_trips();
    test_NSSelectorFromString_registers_an_unseen_name();
    test_conversions_of_nil_are_safe();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
