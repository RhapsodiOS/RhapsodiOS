/*  Behavioural tests for NSAutoreleasePool, stage 2a.  */

#import <Foundation/NSAutoreleasePool.h>
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

static void test_pool_allocates_and_releases(void)
{
    id pool = [[NSAutoreleasePool alloc] init];

    CHECK(pool != nil);
    [pool release];
}

static void test_autoreleased_object_survives_until_the_pool_drains(void)
{
    id pool = [[NSAutoreleasePool alloc] init];
    id object = [[NSObject alloc] init];

    [object autorelease];
    CHECK([object retainCount] == 1);
    [pool release];
}

static void test_extra_retain_survives_the_pool(void)
{
    id pool = [[NSAutoreleasePool alloc] init];
    id object = [[[NSObject alloc] init] autorelease];

    [object retain];
    CHECK([object retainCount] == 2);
    [pool release];
    CHECK([object retainCount] == 1);
    [object release];
}

static void test_nested_pools_drain_independently(void)
{
    id outer = [[NSAutoreleasePool alloc] init];
    id object = [[[NSObject alloc] init] autorelease];
    id inner;

    [object retain];
    inner = [[NSAutoreleasePool alloc] init];
    [object autorelease];
    [inner release];
    CHECK([object retainCount] == 1);

    [outer release];
}

static void test_addObject_accepts_an_object(void)
{
    id pool = [[NSAutoreleasePool alloc] init];
    id object = [[NSObject alloc] init];

    [NSAutoreleasePool addObject:object];
    [pool release];
}

int main(void)
{
    test_pool_allocates_and_releases();
    test_autoreleased_object_survives_until_the_pool_drains();
    test_extra_retain_survives_the_pool();
    test_nested_pools_drain_independently();
    test_addObject_accepts_an_object();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
