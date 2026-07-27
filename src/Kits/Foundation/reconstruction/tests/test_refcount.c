/*  Behavioural tests for the object-allocation and retain-count functions in
    NSZone.m, stage 2a.  These operate on raw allocations rather than live
    Objective-C objects, so they need no runtime.  */

#import <Foundation/NSObject.h>
#import <Foundation/NSZone.h>
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

/*  A stand-in for an object: the runtime only requires that the first word
    be the isa pointer, which these tests never dereference.  */
static id make_object(void)
{
    NSZone *zone = NSDefaultMallocZone();
    void *raw = NSZoneCalloc(zone, 1, 16);
    return (id)raw;
}

static void release_object(id object)
{
    NSZoneFree(NSDefaultMallocZone(), (void *)object);
}

static void test_fresh_object_has_no_extra_references(void)
{
    id object = make_object();

    CHECK(NSExtraRefCount(object) == 0);
    release_object(object);
}

static void test_increment_then_read(void)
{
    id object = make_object();

    NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 1);

    NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 2);

    NSDecrementExtraRefCountWasZero(object);
    NSDecrementExtraRefCountWasZero(object);
    release_object(object);
}

static void test_decrement_reports_the_zero_transition(void)
{
    id object = make_object();

    NSIncrementExtraRefCount(object);
    CHECK(NSDecrementExtraRefCountWasZero(object) == NO);
    CHECK(NSExtraRefCount(object) == 0);

    CHECK(NSDecrementExtraRefCountWasZero(object) == YES);
    release_object(object);
}

static void test_counts_are_per_object(void)
{
    id first = make_object();
    id second = make_object();

    NSIncrementExtraRefCount(first);
    NSIncrementExtraRefCount(first);
    NSIncrementExtraRefCount(second);

    CHECK(NSExtraRefCount(first) == 2);
    CHECK(NSExtraRefCount(second) == 1);

    NSDecrementExtraRefCountWasZero(first);
    NSDecrementExtraRefCountWasZero(first);
    NSDecrementExtraRefCountWasZero(second);
    release_object(first);
    release_object(second);
}

static void test_many_objects_exercise_the_side_table(void)
{
    id objects[256];
    int i;

    for (i = 0; i < 256; i++) {
        objects[i] = make_object();
        NSIncrementExtraRefCount(objects[i]);
    }
    for (i = 0; i < 256; i++)
        CHECK(NSExtraRefCount(objects[i]) == 1);
    for (i = 0; i < 256; i++) {
        CHECK(NSDecrementExtraRefCountWasZero(objects[i]) == NO);
        release_object(objects[i]);
    }
}

static void test_promotion_and_demotion_boundaries(void)
{
    id object = make_object();

    NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 1);

    NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 2);

    NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 3);

    NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 4);

    CHECK(NSDecrementExtraRefCountWasZero(object) == NO);
    CHECK(NSExtraRefCount(object) == 3);

    CHECK(NSDecrementExtraRefCountWasZero(object) == NO);
    CHECK(NSExtraRefCount(object) == 2);

    CHECK(NSDecrementExtraRefCountWasZero(object) == NO);
    CHECK(NSExtraRefCount(object) == 1);

    CHECK(NSDecrementExtraRefCountWasZero(object) == NO);
    CHECK(NSExtraRefCount(object) == 0);

    CHECK(NSDecrementExtraRefCountWasZero(object) == YES);
    CHECK(NSExtraRefCount(object) == 0);

    release_object(object);
}

static void test_overflow_store_holds_several_objects_at_once(void)
{
    id a = make_object();
    id b = make_object();
    id c = make_object();
    int i;

    for (i = 0; i < 3; i++)
        NSIncrementExtraRefCount(a);
    for (i = 0; i < 4; i++)
        NSIncrementExtraRefCount(b);
    for (i = 0; i < 5; i++)
        NSIncrementExtraRefCount(c);

    CHECK(NSExtraRefCount(a) == 3);
    CHECK(NSExtraRefCount(b) == 4);
    CHECK(NSExtraRefCount(c) == 5);

    /*  a was promoted into the overflow store first, so it occupies the
        first (non-last) overflow slot; releasing it while b and c are
        still promoted forces the swap-with-last removal path.  */
    CHECK(NSDecrementExtraRefCountWasZero(a) == NO);
    CHECK(NSDecrementExtraRefCountWasZero(a) == NO);
    CHECK(NSDecrementExtraRefCountWasZero(a) == NO);
    CHECK(NSDecrementExtraRefCountWasZero(a) == YES);
    CHECK(NSExtraRefCount(a) == 0);

    CHECK(NSExtraRefCount(b) == 4);
    CHECK(NSExtraRefCount(c) == 5);

    for (i = 0; i < 4; i++)
        CHECK(NSDecrementExtraRefCountWasZero(b) == NO);
    CHECK(NSExtraRefCount(b) == 0);

    for (i = 0; i < 5; i++)
        CHECK(NSDecrementExtraRefCountWasZero(c) == NO);
    CHECK(NSExtraRefCount(c) == 0);

    release_object(a);
    release_object(b);
    release_object(c);
}

static void test_deep_count_survives(void)
{
    id object = make_object();
    int i;

    for (i = 0; i < 1000; i++)
        NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 1000);
    for (i = 0; i < 1000; i++)
        NSDecrementExtraRefCountWasZero(object);
    CHECK(NSExtraRefCount(object) == 0);
    release_object(object);
}

static void test_should_retain_with_zone(void)
{
    id object = make_object();

    /*  A nil zone means "any zone", so retaining is always allowed.  */
    CHECK(NSShouldRetainWithZone(object, 0) == YES);
    release_object(object);
}

int main(void)
{
    test_fresh_object_has_no_extra_references();
    test_increment_then_read();
    test_decrement_reports_the_zero_transition();
    test_counts_are_per_object();
    test_many_objects_exercise_the_side_table();
    test_promotion_and_demotion_boundaries();
    test_overflow_store_holds_several_objects_at_once();
    test_deep_count_survives();
    test_should_retain_with_zone();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
