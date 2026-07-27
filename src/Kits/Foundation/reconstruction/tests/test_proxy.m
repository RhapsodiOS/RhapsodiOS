/*  Behavioural tests for NSProxy, stage 2a.  NSProxy is a root class whose
    purpose is to forward; a concrete subclass supplies the forwarding.  */

#import <Foundation/NSProxy.h>
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

/*  The brief gives this as `CHECK([NSProxy superclass] == nil)`.  The
    reference disagrees, for the same reason test_object.m's
    test_class_introspection_on_the_class_object already documents for
    NSObject: NSProxy's ABI has no class-side +superclass (confirmed
    against abi/NSProxy.json's 20 class methods -- unlike NSObject, which
    defines one explicitly), so `[NSProxy superclass]` falls through the
    metaclass chain to NSProxy's own -superclass (isa->super_class), with
    self bound to the NSProxy class object itself.  A root metaclass's
    super_class is tied back to its class (objc-class.m:708,
    _class_install_relationships, the same mechanism cited there), so that
    read returns NSProxy, not nil.  Confirmed on the guest directly:
    `[NSProxy superclass] == [NSProxy class]` is true.  Per this task's
    brief, the reference wins and the test changes: `[NSProxy class]
    superclass` (an actual instance's -superclass, unaffected by the
    tie-down) is nil, which is what a root class's ivar/instance_size
    contract in abi/NSProxy.json (superclass: null) actually describes;
    `[NSProxy superclass]` sent to the class object itself is a different,
    non-nil question.  */
static void test_proxy_is_a_root_class(void)
{
    id proxy = [NSProxy alloc];

    CHECK([proxy superclass] == nil);
    CHECK([NSProxy superclass] == [NSProxy class]);
    [proxy dealloc];
}

static void test_alloc_produces_an_instance(void)
{
    id proxy = [NSProxy alloc];

    CHECK(proxy != nil);
    CHECK([proxy class] == [NSProxy class]);
    [proxy dealloc];
}

static void test_proxy_reports_its_own_class(void)
{
    id proxy = [NSProxy alloc];

    CHECK([proxy self] == proxy);
    [proxy dealloc];
}

static void test_retain_count_starts_at_one(void)
{
    id proxy = [NSProxy alloc];

    CHECK([proxy retainCount] == 1);
    [proxy dealloc];
}

int main(void)
{
    test_proxy_is_a_root_class();
    test_alloc_produces_an_instance();
    test_proxy_reports_its_own_class();
    test_retain_count_starts_at_one();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
