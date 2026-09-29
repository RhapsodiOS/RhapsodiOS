/*  Behavioural tests for NSFault's identity/dispatch surface, stage 2c.

    Every expectation here was corrected against the decoded reference
    bodies (tools/binrecon/out/fault-classside2.txt, fault-instance2.txt,
    fault-handler.txt, plus tools/binrecon/out/cells-fault.py for the
    per-iteration selector cells).  The plan's own sketch assumed
    [[NSFault alloc] init]; the reference has no +alloc/-init on NSFault
    at all (faults are manufactured by +makeObjectIntoFault:withHandler:
    swapping an existing object's isa in place), so that sketch is not
    tested.  Description paths are also not exercised: the tree's
    NSString is a link-stage stub that aborts on any use, and the
    reference's +description/-description and the handler's
    descriptionForObject: all need real strings.  Nothing below sends
    description or debugDescription.

    The make/clear arithmetic the tests pin down (decoded, not invented):
    +makeObjectIntoFault:withHandler: reads [anObject retainCount] once
    (0x42519e12-24, cell 0x426089b0), runs the body [anObject release]
    (cell 0x426089b8) + [handler incrementExtraRefCount] (cell
    0x42609154) exactly count-1 times (dec/jne at 0x42519e53-54), then
    setTargetClass:extraData: + isa swap + [handler retain] into +4.
    +clearFault: gates on -isFault, fires [handler faultWillFire:] FIRST
    (0x4251a01b-29), restores (isa,+4) from (targetClass,extraData),
    then [anObject retain] exactly [handler extraRefCount] times (dec /
    cmp -1 loop at 0x4251a08d-91), then [handler release] -- the slot
    itself is NOT decremented by clearFault, reproduced verbatim below
    and in NSFault.m.

    The fault target below is an NSObject subclass with two ivars:
    NSFault's instances are 8 bytes ({isa, _handler}), the reference
    raises '%@: cannot create a fault for a class %s ...' when the old
    class's instance_size is SMALLER than that (cmp at 0x42519dc7), and
    plain NSObject's instances are 4 bytes ({isa} only) -- too small.
    The fault stores its old word@+4 into the handler's _extraData and
    puts [handler retain] there, so the ivar word MUST be writable:
    the test class gives it a real ivar slot.
 */

#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSAutoreleasePool.h>
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

/*  NXConstantString-shaped record reader, same as test_exception.m's
    TestStringBytes: this stage's string literals carry their bytes at
    the record's second field.  */
static const char *TestStringBytes(id string)
{
    struct { Class isa; char *c_string; unsigned int len; } *record = (void *)string;

    return (string == nil) ? NULL : record->c_string;
}

/*  No header in the tree declares these two classes; the tests bind the
    exact surface the reference implements (decoded, not invented).
    The ivar block MUST match NSFault.m's: this file compiles the
    TestFaultRecorder SUBCLASS, and the old NeXT class builder derives
    instance_size from the interfaces visible in THIS unit -- without
    the ivars a subclass allocates 4 bytes and every inherited field
    access at +4/+8/+12 runs off the end of the object.  */
@interface NSFaultHandler : NSObject
{
@private
    Class _targetClass;
    void *_extraData;
    unsigned _extraRefCount;
}
- (Class)targetClass;
- (void *)extraData;
- (void)setTargetClass:(Class)aClass extraData:(void *)data;
- (unsigned)extraRefCount;
- (void)incrementExtraRefCount;
- (BOOL)decrementExtraRefCountWasZero;
- (Class)classForFault:(id)anObject;
- (BOOL)isKindOfClass:(Class)aClass forFault:(id)anObject;
- (BOOL)isMemberOfClass:(Class)aClass forFault:(id)anObject;
- (BOOL)respondsToSelector:(SEL)aSelector forFault:(id)anObject;
- (BOOL)conformsToProtocol:(Protocol *)aProtocol forFault:(id)anObject;
- (void)completeInitializationOfObject:(id)anObject;
- (void)faultWillFire:(id)anObject;
- (BOOL)shouldPerformInvocation:(NSInvocation *)anInvocation;
@end

@interface NSFault : NSObject
+ (BOOL)isFault;
+ (BOOL)isFault:(id)anObject;
+ (id)clearFault:(id)anObject;
+ (id)handlerForFault: (id)anObject;
+ (Class)targetClassForFault:(id)anObject;
+ (void)makeObjectIntoFault:(id)anObject withHandler:(NSFaultHandler *)aHandler;
@end

/*  The fault target: an ordinary NSObject subclass whose instances are
    8 bytes, the same size as NSFault's own -- the gate at 0x42519dc7
    raises only for classes SMALLER than the fault class.  */
@interface TestFaultTarget : NSObject
{
@public
    id payload;
}
@end

@implementation TestFaultTarget
@end

/*  Records what faultWillFire: observed; the base handler's hook is an
    8-byte empty body (0x42519f40), so the subclass reproduces that and
    adds test bookkeeping only.  */
static int faultWillFireCount = 0;
static id faultWillFireObject = nil;

@interface TestFaultRecorder : NSFaultHandler
@end

@implementation TestFaultRecorder
- (void)faultWillFire:(id)anObject
{
    faultWillFireCount++;
    faultWillFireObject = anObject;
}
@end

/*  ---------- class-side identity ---------- */

static void test_class_side_identity_answers_locally(void)
{
    CHECK([NSFault class] == [NSFault class]);
    CHECK([NSFault self] == [NSFault class]);
    CHECK([NSFault superclass] == Nil);
    CHECK([NSFault isProxy] == NO);
    CHECK(![NSFault isKindOfClass:[NSObject class]]);
    CHECK(![NSFault isMemberOfClass:[NSObject class]]);
    CHECK([NSFault respondsToSelector:@selector(self)]);
    CHECK(![NSFault respondsToSelector:@selector(noSuchSelectorAnywhere)]);
    CHECK([NSFault retainCount] == (unsigned)-1);
    CHECK([NSFault retain] == [NSFault class]);
    CHECK([NSFault autorelease] == [NSFault class]);
    [NSFault release];
}

static void test_class_side_isFault(void)
{
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];

    CHECK(![NSFault isFault]);

    /*  +isFault: answers by SENDING -isFault (0x425727a0), not by an
        isa compare -- an NSObject instance answers NO, a faulted object
        answers YES.  */
    CHECK(![NSFault isFault:nil]);

    /*  A handler (plain NSObject subclass) is not a fault either.  */
    CHECK(![NSFault isFault:handler]);
    [handler release];
}

/*  ---------- making faults ---------- */

static void test_makeObjectIntoFault_swaps_the_isa_in_place(void)
{
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];
    Class originalClass = [target class];
    /*  A raw non-object marker: _extraData is the object's raw +4 word
        in the reference (make/clear never retain or release it), so the
        test verifies the word round-trip without any refcounting.  */
    id payload = (id)0x1234;

    target->payload = payload;

    CHECK(![target isFault]);
    CHECK([NSFault handlerForFault:target] == nil);

    [NSFault makeObjectIntoFault:target withHandler:handler];

    /*  Same object, new identity: the address is unchanged (the test
        holds the one pointer throughout), the isa is NSFault, and every
        identity question answers about the TARGET class through the
        handler.  */
    CHECK([target isFault]);
    CHECK([NSFault isFault:target]);
    CHECK([target class] == originalClass);
    CHECK([target superclass] == [NSObject class]);
    CHECK([target isKindOfClass:originalClass]);
    CHECK([target isKindOfClass:[NSObject class]]);
    CHECK(![target isKindOfClass:[NSException class]]);
    CHECK([target isMemberOfClass:originalClass]);
    CHECK(![target isMemberOfClass:[NSObject class]]);

    /*  The handler now owns the target state.  */
    CHECK([handler targetClass] == originalClass);
    CHECK([handler extraData] == payload);
    CHECK([NSFault handlerForFault:target] == handler);
    CHECK([NSFault targetClassForFault:target] == originalClass);
    CHECK(faultWillFireCount == 0);  /* make does not fire the hook */

    [target release];   /* back to the make-time count */
    [handler release];
}

static void test_a_fresh_fault_reports_its_original_retain_count(void)
{
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];

    CHECK([target retainCount] == 1);
    [NSFault makeObjectIntoFault:target withHandler:handler];

    /*  -retainCount = [handler extraRefCount] + 1 (0x42573bcc): the
        drain moved no references at count 1, so the fault reports 1.  */
    CHECK([target retainCount] == 1);
    CHECK([handler extraRefCount] == 0);

    [target release];
    [handler release];
}

static void test_retain_parks_references_on_the_handler(void)
{
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];

    [NSFault makeObjectIntoFault:target withHandler:handler];

    [target retain];
    [target retain];

    /*  Extra references live in the handler's slot, not the side table;
        -retainCount reconstructs slot + 1 (0x42573bcc).  */
    CHECK([handler extraRefCount] == 2);
    CHECK([target retainCount] == 3);

    [target release];
    CHECK([handler extraRefCount] == 1);
    CHECK([target retainCount] == 2);

    /*  -release routes through decrementExtraRefCountWasZero
        (0x42517658): the object is only dealloc'd when the slot empties.  */
    [target release];
    CHECK([handler extraRefCount] == 0);
    CHECK([target retainCount] == 1);
    CHECK([target isFault]);  /* still a fault: nothing released it away */

    [target release];
    [handler release];
}

static void test_autorelease_parks_through_NSAutoreleaseObject(void)
{
    id pool = [[NSAutoreleasePool alloc] init];
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];

    [NSFault makeObjectIntoFault:target withHandler:handler];

    /*  -autorelease is a direct NSAutoreleaseObject(self) + return self
        (0x42525de8): the same address comes back and the handler's slot
        is untouched -- parking costs no handler references.  */
    CHECK([target autorelease] == target);
    CHECK([handler extraRefCount] == 0);

    /*  Take the parking reference back before the drain (a manual
        retain balances the pool's coming release), so draining only
        undoes the park and the object survives it.  */
    [target retain];

    [pool release];

    CHECK([handler extraRefCount] == 0);
    CHECK([target retainCount] == 1);
    CHECK([target isFault]);   /* still faulted: the drain consumed the park */

    /*  Unwind: the slot is empty, so this release takes the dealloc
        path -- clearFault fires the hook, restores the isa and releases
        the handler's object+4 hold; the test's own handler reference is
        released last.  */
    [target release];
    [handler release];
}

static void test_clearFault_restores_the_isa_and_the_count(void)
{
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    TestFaultRecorder *handler = [[TestFaultRecorder alloc] init];
    Class originalClass = [target class];
    /*  Raw non-object marker: _extraData is the object's raw +4 word
        (make/clear never retain or release it), so the test verifies
        the word round-trip without any refcounting.  */
    id payload = (id)0x1234;
    unsigned slot;

    target->payload = payload;
    [NSFault makeObjectIntoFault:target withHandler:handler];

    [target retain];
    [target retain];
    slot = [handler extraRefCount];
    CHECK(slot == 2);
    CHECK(faultWillFireCount == 0);

    /*  The hook fires BEFORE any state change (0x4251a01b-29), with the
        faulted object as its argument.  */
    CHECK([NSFault clearFault:target] == target);
    CHECK(faultWillFireCount == 1);
    CHECK(faultWillFireObject == target);

    /*  Identity restored.  */
    CHECK(![target isFault]);
    CHECK([target class] == originalClass);
    CHECK([NSFault targetClassForFault:target] == Nil);

    /*  Refill arithmetic: exactly slot retentions (dec / cmp -1 loop),
        so the object is back to 1 + slot, and the base slot is left
        alone by clearFault (the reference body sends it nothing).  */
    CHECK([target retainCount] == 1 + slot);
    CHECK([handler extraRefCount] == slot);
    CHECK(target->payload == payload);

    /*  The handler keeps the extra refs it now records; release the
        object back down to its own single reference.  */
    [target release];
    [target release];
    CHECK([target retainCount] == 1);

    [target release];
    [handler release];
}

/*  ---------- the size gate and the not-a-fault gate ---------- */

static id caughtException = nil;

static void raise_makeFaultOnAnNSObject(void)
{
    id object = [[NSObject alloc] init];
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];

    NS_DURING
        [NSFault makeObjectIntoFault:object withHandler:handler];
    NS_HANDLER
        caughtException = localException;
    NS_ENDHANDLER

    /*  The object survives the refused make untouched (the gate raises
        before any state change: 0x42519dc7 precedes the loop).  */
    CHECK(![object isFault]);
    CHECK([object retainCount] == 1);

    [object release];
    [handler release];
}

static void test_making_a_fault_of_a_too_small_class_raises(void)
{
    id caught = nil;

    /*  Plain NSObject instances are 4 bytes; NSFault needs 8.  */
    raise_makeFaultOnAnNSObject();
    caught = caughtException;
    caughtException = nil;

    CHECK(caught != nil);
    CHECK([caught name] == NSInvalidArgumentException);
    CHECK(strstr(TestStringBytes([caught reason]),
                 "cannot create a fault for a class") != NULL);
    CHECK(strstr(TestStringBytes([caught reason]), "TestFaultTarget") == NULL);
    CHECK(strstr(TestStringBytes([caught reason]), "NSObject") != NULL);
}

static void raise_clearFaultOnAnOrdinaryObject(void)
{
    id object = [[NSObject alloc] init];

    NS_DURING
        [NSFault clearFault:object];
    NS_HANDLER
        caughtException = localException;
    NS_ENDHANDLER

    CHECK(![object isFault]);
    [object release];
}

static void test_clearFault_of_a_non_fault_raises(void)
{
    id caught = nil;

    raise_clearFaultOnAnOrdinaryObject();
    caught = caughtException;
    caughtException = nil;

    CHECK(caught != nil);
    CHECK([caught name] == NSInvalidArgumentException);
    CHECK(strstr(TestStringBytes([caught reason]), "object not a fault") != NULL);
}

static void test_clearFault_of_nil_raises(void)
{
    id caught = nil;

    NS_DURING
        [NSFault clearFault:nil];
    NS_HANDLER
        caughtException = localException;
    NS_ENDHANDLER

    caught = caughtException;
    caughtException = nil;

    CHECK(caught != nil);
    CHECK([caught name] == NSInvalidArgumentException);
    CHECK(strstr(TestStringBytes([caught reason]), "object not a fault") != NULL);
}

/*  ---------- handler-surface delegation ---------- */

static void test_handler_surface_answers_about_the_target_class(void)
{
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];
    Class originalClass = [target class];

    [NSFault makeObjectIntoFault:target withHandler:handler];

    /*  -respondsToSelector: -> [_targetClass instancesRespondToSelector:]
        (0x4253c6d4, cell 0x42609130): payload accessors are inherited
        NSObject instance methods, so they answer YES.  */
    CHECK([target respondsToSelector:@selector(retain)]);
    CHECK([target respondsToSelector:@selector(isEqual:)]);
    CHECK(![target respondsToSelector:@selector(noSuchSelectorAnywhere)]);

    /*  -conformsToProtocol: -> [_targetClass conformsToProtocol:]
        (0x42573ca0): the fault's answer must mirror the target class's
        own answer (the protocol machinery itself is NSObject's, not
        NSFault's, so the test pins the delegation, not the answer).  */
    CHECK([target conformsToProtocol:@protocol(NSObject)] ==
          [originalClass conformsToProtocol:@protocol(NSObject)]);

    /*  -methodSignatureForSelector: ->
        [_targetClass instanceMethodSignatureForSelector:]
        (0x42525c54, cell 0x4260912c).  */
    CHECK([target methodSignatureForSelector:@selector(retain)] != nil);
    CHECK([target methodSignatureForSelector:@selector(noSuchSelectorAnywhere)] == nil);

    /*  The handler's own surface: classForFault: is the field read,
        isMemberOfClass:forFault: the single compare (0x42573d28).  */
    CHECK([handler classForFault:target] == originalClass);
    CHECK([handler isMemberOfClass:originalClass forFault:target]);
    CHECK(![handler isMemberOfClass:[NSObject class] forFault:target]);

    [target release];
    [handler release];
}

static void test_the_base_handlers_completion_step_raises(void)
{
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    id caught = nil;

    [NSFault makeObjectIntoFault:target withHandler:handler];

    /*  completeInitializationOfObject: is abstract in the reference
        (NSRequestConcreteImplementation, unavailable in this tree --
        reconstructed as the same NSInternalInconsistencyException
        raise); -self is the lazy-completion entry that reaches it
        (0x42573bf0).  The reference's -self RETURNS self only after
        the completion call returns, so a raising base handler means
        the send raises.  */
    NS_DURING
        [target self];
    NS_HANDLER
        caughtException = localException;
    NS_ENDHANDLER

    caught = caughtException;
    caughtException = nil;
    CHECK(caught != nil);
    CHECK([caught name] == NSInternalInconsistencyException);

    [target release];
    [handler release];
}

static void test_performSelector_family_dispatches_through_the_fault(void)
{
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];

    [NSFault makeObjectIntoFault:target withHandler:handler];

    /*  The performSelector: bodies (0x42572834-class/0x42573a10-shaped
        instance side) send objc_msgSend(self, sel): the runtime resolves
        through the FAULT's isa, so only NSFault's own instance methods
        answer.  -isFault answers locally.  */
    CHECK([target performSelector:@selector(isFault)] != nil);

    /*  A null selector raises through NSFault.m's own static helper
        (0x4257551c, '%@: null selector').  */
    {
        id caught = nil;

        NS_DURING
            [target performSelector:(SEL)NULL];
        NS_HANDLER
            caughtException = localException;
        NS_ENDHANDLER

        caught = caughtException;
        caughtException = nil;
        CHECK(caught != nil);
        CHECK([caught name] == NSInvalidArgumentException);
        CHECK(strstr(TestStringBytes([caught reason]), "null selector") != NULL);
    }

    [target release];
    [handler release];
}

static void test_an_unknown_selector_falls_through_forwarding(void)
{
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];
    id caught = nil;

    [NSFault makeObjectIntoFault:target withHandler:handler];

    /*  NSFault has no -noSuchSelectorAnywhere; -doesNotRecognizeSelector:
        raises with the shared '%@: selector not recognized' format
        object (0x42606b0c).  */
    NS_DURING
        [target noSuchSelectorAnywhere];
    NS_HANDLER
        caughtException = localException;
    NS_ENDHANDLER

    caught = caughtException;
    caughtException = nil;
    CHECK(caught != nil);
    CHECK([caught name] == NSInvalidArgumentException);
    CHECK(strstr(TestStringBytes([caught reason]), "selector not recognized") != NULL);

    [target release];
    [handler release];
}

static void test_the_handler_slot_round_trips_through_zero(void)
{
    TestFaultTarget *target = [[TestFaultTarget alloc] init];
    TestFaultRecorder *handler = [[TestFaultRecorder alloc] init];
    Class originalClass = [target class];
    int fireCountBefore;

    /*  decrementExtraRefCountWasZero reports YES at zero without
        decrementing below it (0x42518bc8) -- exercised indirectly
        through the fault's -release, which gates [self dealloc] on it.  */
    [NSFault makeObjectIntoFault:target withHandler:handler];
    [target retain];
    [target release];
    CHECK([handler extraRefCount] == 0);
    CHECK([target retainCount] == 1);
    CHECK([target isFault]);

    /*  The NEXT release empties an already-empty slot: the YES answer
        runs [self dealloc], which un-faults through clearFault (firing
        the hook on the way) and then frees the object.  Everything
        observable afterwards goes through the handler -- the target
        itself is deallocated at that point and must not be touched.  */
    fireCountBefore = faultWillFireCount;
    faultWillFireObject = nil;
    [target release];

    CHECK(faultWillFireCount == fireCountBefore + 1);
    CHECK(faultWillFireObject == target);
    CHECK([handler targetClass] == originalClass);
    CHECK([handler extraRefCount] == 0);

    [handler release];
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);

    test_class_side_identity_answers_locally();
    test_class_side_isFault();
    test_makeObjectIntoFault_swaps_the_isa_in_place();
    test_a_fresh_fault_reports_its_original_retain_count();
    test_retain_parks_references_on_the_handler();
    test_autorelease_parks_through_NSAutoreleaseObject();
    test_clearFault_restores_the_isa_and_the_count();
    test_making_a_fault_of_a_too_small_class_raises();
    test_clearFault_of_a_non_fault_raises();
    test_clearFault_of_nil_raises();
    test_handler_surface_answers_about_the_target_class();
    test_the_base_handlers_completion_step_raises();
    test_performSelector_family_dispatches_through_the_fault();
    test_an_unknown_selector_falls_through_forwarding();
    test_the_handler_slot_round_trips_through_zero();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
