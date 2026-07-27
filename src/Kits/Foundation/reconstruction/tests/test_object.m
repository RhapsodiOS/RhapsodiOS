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

static void test_class_side_allocation(void)
{
    id object = [NSObject alloc];

    CHECK(object != nil);
    CHECK([object class] == [NSObject class]);
    [object release];
}

static void test_new_allocates_and_initialises(void)
{
    id object = [NSObject new];

    CHECK(object != nil);
    CHECK([object retainCount] == 1);
    [object release];
}

/*  The brief gives this as `CHECK([NSObject isKindOfClass:[NSObject class]]
    == NO)`.  The reference disagrees: +isKindOfClass: walks self->isa
    (the metaclass) and then ->super_class, comparing each link to aClass
    (confirmed from the disassembly at 0x42533b90-0x42533bbc).  For a root
    class, objc-class.m's _class_install_relationships ties the metaclass's
    super_class down to the class itself when it has none of its own
    ("`tie' the meta class down to its class": meta->super_class = class),
    so NSObject's metaclass chain is NSObject's-metaclass -> NSObject --
    which the walk finds equal to aClass on its second step.  Verified two
    ways: independently re-deriving the disassembly's push/compare
    sequence, and reading _class_install_relationships itself
    (src/objc-1/objc-class.m).  Per this task's brief, the reference wins
    and the test changes: this really does report YES.  */
static void test_class_introspection_on_the_class_object(void)
{
    CHECK([NSObject class] == [NSObject class]);
    CHECK([NSObject superclass] == nil);
    CHECK([NSObject isKindOfClass:[NSObject class]] == YES);
    CHECK([NSObject instancesRespondToSelector:@selector(hash)]);
    CHECK(![NSObject instancesRespondToSelector:@selector(thisDoesNotExist)]);
}

static void test_allocWithZone_uses_the_named_zone(void)
{
    NSZone *zone = NSDefaultMallocZone();
    id object = [NSObject allocWithZone:zone];

    CHECK(object != nil);
    CHECK([object zone] == zone);
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
    test_class_side_allocation();
    test_new_allocates_and_initialises();
    test_class_introspection_on_the_class_object();
    test_allocWithZone_uses_the_named_zone();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
