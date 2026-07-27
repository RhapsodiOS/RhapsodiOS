/*  Behavioural tests for NSObject's instance methods, stage 2a.  */

#import <Foundation/NSObject.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

static void test_self_and_identity(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object self] == object);
    CHECK([object isEqual:object]);
    CHECK(![object isEqual:nil]);
    [object release];
}

static void test_hash_is_stable_and_matches_equality(void)
{
    id object = [[NSObject alloc] init];
    unsigned first = [object hash];

    CHECK([object hash] == first);
    [object release];
}

static void test_distinct_objects_are_not_equal(void)
{
    id first = [[NSObject alloc] init];
    id second = [[NSObject alloc] init];

    CHECK(![first isEqual:second]);
    [first release];
    [second release];
}

static void test_class_introspection(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object class] == [NSObject class]);
    CHECK([object isKindOfClass:[NSObject class]]);
    CHECK([object isMemberOfClass:[NSObject class]]);
    CHECK([object superclass] == nil);
    [object release];
}

static void test_responds_to_selector(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object respondsToSelector:@selector(hash)]);
    CHECK(![object respondsToSelector:@selector(thisDoesNotExist)]);
    [object release];
}

static void test_retain_count_tracks_the_extra_count(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object retainCount] == 1);
    [object retain];
    CHECK([object retainCount] == 2);
    [object release];
    CHECK([object retainCount] == 1);
    [object release];
}

static void test_retain_returns_self(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object retain] == object);
    [object release];
    [object release];
}

int main(void)
{
    test_self_and_identity();
    test_hash_is_stable_and_matches_equality();
    test_distinct_objects_are_not_equal();
    test_class_introspection();
    test_responds_to_selector();
    test_retain_count_tracks_the_extra_count();
    test_retain_returns_self();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
