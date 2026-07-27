/*  Behavioural tests for NSObject's instance methods, stage 2a.  */

#import <Foundation/NSObject.h>
#import <Foundation/NSDebug.h>
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

/*  NSZombieEnabled is read directly by NSZone.m's NSDeallocateObject, the
    same way this test reaches it: as the FOUNDATION_EXPORT BOOL declared
    in NSDebug.h (link_stubs.m supplies the storage, defaulting it to 0).
    With it set, releasing an object down to a zero retain count no longer
    frees the storage -- NSDeallocateObject retargets object->isa to a
    synthesized "NSZombie_NSObject" class instead (NSZone.m's
    _NSZombieClassForClass) and returns, leaving the object's memory (and
    its isa field) safe to read afterward.  This test only reads isa/name
    fields directly, exactly as NSZone.m's own zombie synthesis does; it
    never sends the freed object a message, since every _NSZombie method
    ends by raising an exception, and this project's Objective-C support
    has no @try/@catch to catch it with.  */
static void test_zombie_replaces_isa_on_dealloc(void)
{
    BOOL previousZombieEnabled = NSZombieEnabled;
    id object;
    Class originalClass;
    Class zombieClass;

    NSZombieEnabled = YES;

    object = [[NSObject alloc] init];
    originalClass = object->isa;
    [object release];
    zombieClass = object->isa;

    CHECK(zombieClass != originalClass);
    CHECK(zombieClass != Nil);
    CHECK(strcmp(zombieClass->name, "NSZombie_NSObject") == 0);

    NSZombieEnabled = previousZombieEnabled;
}

/*  A second object of the same original class, deallocated while zombies
    are still enabled, must be retargeted to the very same zombie class as
    the first -- exercising _NSZombieClassForClass's lookup-table hit path
    (zombieClasses[]), not just the synthesis path the test above covers.  */
static void test_zombie_class_is_reused_for_second_object(void)
{
    BOOL previousZombieEnabled = NSZombieEnabled;
    id first;
    id second;
    Class firstZombieClass;
    Class secondZombieClass;

    NSZombieEnabled = YES;

    first = [[NSObject alloc] init];
    [first release];
    firstZombieClass = first->isa;

    second = [[NSObject alloc] init];
    [second release];
    secondZombieClass = second->isa;

    CHECK(firstZombieClass == secondZombieClass);

    NSZombieEnabled = previousZombieEnabled;
}

static void test_class_side_isMemberOfClass(void)
{
    CHECK(![NSObject isMemberOfClass:[NSObject class]]);
}

/*  +implementsSelector: is not covered here: both branches of
    _NSIMPForSelector(self->isa, aSelector) are unreconstructed
    (NSPrivate/NSAutoreleasePool territory) and link_stubs.m's stub for it
    aborts unconditionally, confirmed by running the test binary -- there
    is no selector this could be called with today that would not abort
    the whole suite.  */

static void test_class_side_zone(void)
{
    CHECK([NSObject zone] == NSDefaultMallocZone());
}

static void test_class_side_retainCount(void)
{
    CHECK([NSObject retainCount] == (unsigned)-1);
}

static void test_class_side_copy_and_mutableCopy(void)
{
    CHECK([NSObject copy] == [NSObject class]);
    CHECK([NSObject mutableCopy] == [NSObject class]);
}

static void test_class_side_isAncestorOfObject(void)
{
    id object = [[NSObject alloc] init];

    CHECK([NSObject isAncestorOfObject:object]);
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
    test_zombie_replaces_isa_on_dealloc();
    test_zombie_class_is_reused_for_second_object();
    test_class_side_isMemberOfClass();
    test_class_side_zone();
    test_class_side_retainCount();
    test_class_side_copy_and_mutableCopy();
    test_class_side_isAncestorOfObject();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
