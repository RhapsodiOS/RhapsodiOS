/*	NSFault.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSLock.h>
#import <objc/objc-runtime.h>
#import <objc/Protocol.h>

/*  No header in this tree declares NSFault or NSFaultHandler -- same
    treatment as NSPrivate.m's _NSAutoreleasedMallocMemory.  Everything
    below is reconstructed from the reference binary's disassembly:
    class records at 0x4260a4f4 (NSFault) and 0x4260a4cc (NSFaultHandler),
    method lists at 0x42611a18 / 0x4260d9c4 / 0x42611950, and the decoded
    bodies of all 29 class + 21 instance + 16 handler reference methods
    (tools/binrecon/out/fault-classside2.txt, fault-instance2.txt,
    fault-handler.txt; the per-iteration selector cells were resolved to
    their name strings with tools/binrecon/out/cells-fault.py).

    The structural discovery of the decode: NSFault is a ROOT class
    (class struct super field = 0) with 8-byte instances {isa, _handler},
    and its entire instance identity battery is NOT NSProxy-style
    boilerplate -- every method forwards to self->_handler with the same
    selector plus a forFault: argument, answering identity questions about
    the TARGET class the handler preserves.  The fault itself carries no
    target state.  NSFaultHandler is an NSObject subclass with 16-byte
    instances {isa, _targetClass, _extraData, _extraRefCount}.

    The second discovery is the faulting mechanism itself
    (+makeObjectIntoFault:withHandler:, 0x42519da4): the object's isa is
    swapped IN PLACE (0x42519e73: mov [edi], ecx) to the receiver class
    (self, which lets NSFault subclasses supply fault-specific behavior), the
    old (isa, word@+4) pair moves into the handler's (_targetClass,
    _extraData) slots, and the object's EXCESS references move onto the
    handler: the loop bound is [anObject retainCount] (send at
    0x42519e12-24, cell 0x426089b0), and each of the count-1 iterations is
    exactly [anObject release] (cell 0x426089b8) paired with [handler
    incrementExtraRefCount] (cell 0x42609154) -- 0x42519e2c-54.  One real
    reference stays on the object; -retainCount's slot+1 shape
    reconstructs the original count.  +clearFault: (0x42519fb4) reverses
    the exchange: it fires [handler faultWillFire:] FIRST (send at
    0x4251a01b-29, cell 0x42609138 -- before any state changes, the Task
    12 hook), restores (isa, +4) from (targetClass, extraData), then
    retains the object once per handler-slot unit ([anObject retain] is
    the loop body's ONLY send, 0x4251a078-85, bounded by dec ebx / cmp
    -1, exactly [handler extraRefCount] iterations) and releases the
    handler (0x4251a09b).  The slot itself is NOT decremented by
    clearFault in the reference -- the body contains no send to the
    handler -- so a made-then-cleared object ends with one more reference
    than a make at count 1 would suggest; reproduced verbatim.  This
    matches the reference's "faulting is metonymy, not copying" observable
    behavior: the faulted object keeps its address and all identity
    questions keep answering about the original class through the handler.

    Both classes are also self-patching like NSProxy.m: +initialize
    overwrites -[NSFault forward::]'s method_imp with NSObject's, so the
    raising body below (the bytes actually in the reference, guarded by
    a static flag) only serves messages sent before the first +initialize
    (0x42551610: static byte at base+0xb0e0d, sel_registerName("forward::"),
    class_getInstanceMethod on the literal class-name strings "NSObject"
    and "NSFault", Method struct's method_imp field (+8) copy,
    _NSInitializePlatform()).  */

extern BOOL class_respondsToMethod(Class aClass, SEL aSelector);
extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern BOOL _NSClassConformsToProtocol(Class aClass, Protocol *aProtocol);
extern void NSAutoreleaseObject(id anObject);
extern NSLock *_NSGlobalRetainLock;

extern void _NSInitializePlatform(void);

/*  NSFault.m's own null-selector diagnostic, static like NSProxy.m's
    counterpart (one per root class, confirmed from the reference's
    symbol table -- __NSFaultRaiseNullSelectorException @0x4257551c,
    68 bytes, called by all six performSelector: bodies).  */
static void
__NSFaultRaiseNullSelectorException(id object, SEL aSelector)
{
    [NSException raise:NSInvalidArgumentException
                format:@"%@: null selector",
                       _NSMethodExceptionProem(object, aSelector)];
}

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
- (NSString *)descriptionForObject:(id)anObject;
@end

/*  Root class, like NSProxy.h: isa at offset 0, no superclass, 8-byte
    instances {isa, _handler} -- no +alloc/-init exists in the reference
    method lists; the ONLY way to make a fault is
    +makeObjectIntoFault:withHandler: swapping the isa of an existing
    object.  Declares its own isa; subclassing Object instead is fatal
    on the guest's cc1obj (duplicate-member 'isa' error path segfaults).  */
@interface NSFault
{
    Class isa;
    NSFaultHandler *_handler;
}
+ (BOOL)isFault;
+ (BOOL)isFault:(id)anObject;
+ (void)clearFault:(id)anObject;
+ (id)handlerForFault: (id)anObject;
+ (Class)targetClassForFault:(id)anObject;
+ (void)makeObjectIntoFault:(id)anObject withHandler:(NSFaultHandler *)aHandler;
@end

@implementation NSFault

+ (void)load
{
    _NSInitializePlatform();
}

/*  Self-patching +initialize: -[NSFault forward::]'s compiled body is a
    raise; once the runtime first runs +initialize the imp is swapped to
    NSObject's -forward:: (which routes to -forwardInvocation: and fires
    the fault). Both targets set the static flag after the platform hook. */
+ (void)initialize
{
    static BOOL initialized = NO;

    if (!initialized) {
        SEL twoArgForward;
        Method objectForward;
        Method faultForward;

        twoArgForward = sel_registerName("forward::");
        objectForward = class_getInstanceMethod(objc_lookUpClass("NSObject"),
                                                twoArgForward);
        faultForward = class_getInstanceMethod(objc_lookUpClass("NSFault"),
                                               twoArgForward);
        faultForward->method_imp = objectForward->method_imp;
        _NSInitializePlatform();
        initialized = YES;
    }
}

/*  battery of 29 class-side methods (0x4260d9c4, count 29, +load and
    +initialize included)  */

+ (id)self
{
    return self;
}

+ (Class)class
{
    return self;
}

/*  Field read of the class struct's super_class (0x42572900: mov eax,
    [eax+4]) -- for a root class the reference's field is 0.  */
+ (Class)superclass
{
    return ((Class)self)->super_class;
}

+ (BOOL)isEqual:(id)object
{
    return self == object;
}

+ (unsigned)hash
{
    return (unsigned)self >> 2;
}

/*  Walks the METACLASS chain (self->isa), identical to
    +[NSObject isKindOfClass:] (NSObject.m line 179).  */
+ (BOOL)isKindOfClass:(Class)aClass
{
    Class candidate;

    for (candidate = self->isa; candidate != Nil; candidate = candidate->super_class)
        if (candidate == aClass)
            return YES;
    return NO;
}

+ (BOOL)isMemberOfClass:(Class)aClass
{
    return self->isa == aClass;
}

/*  0x425728cc: class_respondsToMethod on the METACLASS.  */
+ (BOOL)respondsToSelector:(SEL)aSelector
{
    return class_respondsToMethod(self->isa, aSelector);
}

+ (BOOL)conformsToProtocol:(Protocol *)aProtocol
{
    return _NSClassConformsToProtocol(self, aProtocol);
}

+ (BOOL)isProxy
{
    return NO;
}

/*  Class objects are immortal in the reference: +retain returns self,
    +release is an 8-byte empty body, +retainCount returns -1, +autorelease
    returns self (all four confirmed as register-constant bodies at
    0x425728f4/0x425728c4/0x425728e8/0x42572688).  */
+ (id)retain
{
    return self;
}

+ (void)release
{
}

+ (unsigned)retainCount
{
    return (unsigned)-1;
}

+ (id)autorelease
{
    return self;
}

/*  Class-side +zone returns NSDefaultMallocZone() unconditionally
    (0x42572958: call NSDefaultMallocZone, no receiver use).  */
+ (NSZone *)zone
{
    return NSDefaultMallocZone();
}

/*  The performSelector: family (0x42572834/0x42572860/0x42572890): a
    NULL selector raises through __NSFaultRaiseNullSelectorException,
    then the message goes out with the given arguments.  */
+ (id)performSelector:(SEL)aSelector
{
    if (aSelector == NULL)
        __NSFaultRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector);
}

+ (id)performSelector: (SEL)aSelector withObject:(id)object
{
    if (aSelector == NULL)
        __NSFaultRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object);
}

+ (id)performSelector: (SEL)aSelector withObject:(id)object1 withObject:(id)object2
{
    if (aSelector == NULL)
        __NSFaultRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object1, object2);
}

/*  NOT the proemless shape: 0x4257271c computes the proem, NSLogs it
    with the shared '%@: selector not recognized' format object
    (0x42606b0c), recomputes the proem and raises with the SAME format
    object (0x42572736-67 -- the format object is reused, the proem is
    built twice).  NSLog is a no-op in this tree (NSObjCRuntime.m); the
    call is kept for shape.  */
+ (void)doesNotRecognizeSelector:(SEL)aSelector
{
    NSLog(@"%@: selector not recognized",
          _NSMethodExceptionProem(self, aSelector));
    [NSException raise:NSInvalidArgumentException
                format:@"%@: selector not recognized",
                       _NSMethodExceptionProem(self, aSelector)];
}

/*  = [NSString stringWithCString: self->name length: strlen(self->name)]
    (0x425726d8: name from +0x8, inline strlen, then the length pushed
    before the bytes pointer).  */
+ (NSString *)description
{
    return [NSString stringWithCString:((Class)self)->name
                                length:strlen(((Class)self)->name)];
}

/*  Shares the instance side's selector cell (0x42608974 -- the same
    unrelocated cell -[NSFault debugDescription] loads at 0x42573a91),
    so it is the same forwarding body on the class object:
    [self description].  */
+ (id)debugDescription
{
    return [self description];
}

+ (BOOL)isFault
{
    return NO;
}

/*  Answers by SENDING -isFault to anObject (0x425727a0: one
    objc_msgSend whose selector cell is 'isFault', arg independent of
    _cmd).  The plan's isa-comparison sketch is wrong on this point.  */
+ (BOOL)isFault:(id)anObject
{
    return anObject != nil && [anObject isFault];
}

/*  All three gate-helpers share the same shape (0x42524a5c,
    0x42572910): [anObject isFault] gate, then the field read.  */
+ (id)handlerForFault: (id)anObject
{
    if (anObject == nil || ![anObject isFault])
        return nil;
    return ((NSFault *)anObject)->_handler;
}

+ (Class)targetClassForFault:(id)anObject
{
    if (anObject == nil || ![anObject isFault])
        return Nil;
    return [anObject->_handler targetClass];
}

/*  The faulting operation itself, 0x42519da4.  Verbatim translation:
    gate the size (0x42519dc7: cmp [self+0x14=instance_size],
    oldClass->instance_size -- raise when the old class's instances are
    SMALLER than the receiver class's instances, '%s' the old class's name,
    '%d' the receiver's instance size,
    proem of the receiver, i.e. the NSFault class object), then drain the
    object's excess references into the handler, then swap isa and
    _handler.  */
+ (void)makeObjectIntoFault:(id)anObject withHandler:(NSFaultHandler *)aHandler
{
    Class oldClass = anObject->isa;
    id oldWord4 = ((id *)anObject)[1];
    unsigned extra;

    /*  The gate comes FIRST (0x42519dc7, before the retainCount read at
        0x42519e12): a refused make leaves the object completely
        untouched.  */
    if (oldClass->instance_size < ((Class)self)->instance_size)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: cannot create a fault for a class %s because its instances are smaller than %d bytes",
                           _NSMethodExceptionProem(self, _cmd),
                           oldClass->name,
                           ((Class)self)->instance_size];

    extra = [anObject retainCount];

    /*  Transfer every reference but the object's own one (the loop bound
        is the retainCount read once at 0x42519e24 into ebx; the dec/jne
        at 0x42519e53-54 runs the body count-1 times): the object loses
        one reference per iteration while the handler's slot gains one.
        The reference reads the count once, not per iteration.  */
    while (extra > 1) {
        [anObject release];
        [aHandler incrementExtraRefCount];
        extra = extra - 1;
    }

    /*  Snapshot the old (isa, +4) pair into (targetClass, extraData)
        (send at 0x42519e6b, cell 0x4260d13c = 'setTargetClass:extraData:').  */
    [aHandler setTargetClass:oldClass extraData:oldWord4];

    /*  THE fault: swap isa in place.  0x42519e73 stores the class-side
        receiver (self) directly, so subclasses retain their own fault
        dispatch while sharing NSFault's root-class state layout.  */
    anObject->isa = (Class)self;

    /*  [handler retain] result stored INTO the object's +4 word (i.e.
        the future _handler ivar slot), not discarded: 0x42519e85:
        mov [edi+4], eax.  */
    ((id *)anObject)[1] = [aHandler retain];
}

/*  The restore, i386 0x42519fb4 / PPC 0x42581a88.  Load the handler from
    +4 before the nil and isFault checks, matching both target prologues;
    if NO, raise '%@: object not a fault' with the proem of the NSFault
    CLASS OBJECT (proem args at 0x42519fe3-fea are ebp+8/ebp+0xc =
    self/_cmd, NOT anObject) and the format object at 0x42606b30
    (0x42519fe3-0x4251a013).  Returns void in the reference (method-list
    encoding v12@8:12@16) -- the caller works on the object in place.  */
+ (void)clearFault:(id)anObject
{
    NSFaultHandler *handler = ((NSFault *)anObject)->_handler;
    unsigned extra;

    if (anObject == nil || ![anObject isFault])
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: object not a fault",
                           _NSMethodExceptionProem(self, _cmd)];

    /*  [handler faultWillFire: anObject] -- the FIRST send after the
        gate (0x4251a01b-29, cell 0x42609138), BEFORE any state changes:
        the hook the fault-firing sequence (Task 12) rides on.  */
    [handler faultWillFire:anObject];

    /*  Both targets send extraRefCount here and discard the result before
        restoring the object's isa and +4 word.  */
    [handler extraRefCount];

    /*  Restore (isa, +4) from the following targetClass and extraData
        sends (cells 0x4260916c and 0x42609134, respectively).  */
    anObject->isa = [handler targetClass];
    ((id *)anObject)[1] = [handler extraData];

    /*  Symmetric refill: [anObject retain] is the loop body's ONLY send
        (0x4251a078-85), run exactly [handler extraRefCount] times (bound
        read once at 0x4251a06d, dec/cmp -1 loop).  The slot itself is
        NOT decremented -- the reference body sends nothing to the
        handler here.  */
    extra = [handler extraRefCount];
    while (extra != 0) {
        [anObject retain];
        extra = extra - 1;
    }

    /*  0x4251a09b (cell 0x426089b8 = 'release').  */
    [handler release];
}

/*  Instance side: the battery forwards everything to the handler
    (0x42611a18).  The reference keeps all 21 instance methods FLAT in
    the class's own method list (no Instance category in
    __OBJC,__module_info), so the reconstruction does the same: this
    block continues the single @implementation NSFault above -- no
    @end separates the class-side and instance-side batteries.  */

/*  Instance side: the battery forwards everything to the handler
    (0x42611a18).  */
- (id)self
{
    /*  The lazy-completion trigger, 0x42573bf0: [handler
        completeInitializationOfObject: self], then return self.  Task 12
        owns the sequence's semantics; the send itself is decoded here
        because -self IS the entry point the sequence rides on.  */
    [self->_handler completeInitializationOfObject:self];
    return self;
}

- (Class)class
{
    return [self->_handler classForFault:self];
}

- (Class)superclass
{
    /*  0x42573c18: [handler classForFault: self], then read +4 off the
        returned class -- [[handler classForFault:self] superclass].  */
    return [[self->_handler classForFault:self] superclass];
}

/*  Gate 1 (stage 2c): the reference's instance battery is exactly 21
    methods -- isEqual:, hash and the performSelector: family are NOT
    in it.  Such sends are ordinary unknown selectors on a fault: they
    forward, and forwardInvocation: gates them on the handler.  The
    CLASS-side family (0x42572834...) is the reference's own and stays.  */

- (BOOL)isKindOfClass:(Class)aClass
{
    return [self->_handler isKindOfClass:aClass forFault:self];
}

- (BOOL)isMemberOfClass:(Class)class
{
    return [self->_handler isMemberOfClass:class forFault:self];
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    return [self->_handler respondsToSelector:aSelector forFault:self];
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol
{
    return [self->_handler conformsToProtocol:aProtocol forFault:self];
}

- (BOOL)isProxy
{
    return NO;
}

/*  Routes through the handler's extraRefCount slot (0x42573bcc:
    objc_msgSend(_handler, 'extraRefCount'); inc eax), NOT the side
    table: the fault's count lives in the handler since
    makeObjectIntoFault moved it there.  */
- (unsigned)retainCount
{
    return [self->_handler extraRefCount] + 1;
}

/*  Extra references park on the handler (0x4251ab88: objc_msgSend to
    _handler with cell 0x42609154 = 'incrementExtraRefCount', then
    return self).  */
- (id)retain
{
    [self->_handler incrementExtraRefCount];
    return self;
}

/*  0x42517658: [handler decrementExtraRefCountWasZero]; if YES
    ([self dealloc]).  The object's dealloc runs while the object is
    still a fault; -dealloc below un-faults it first.  */
- (void)release
{
    if ([self->_handler decrementExtraRefCountWasZero])
        [self dealloc];
}

/*  Parks the object via the package-private helper (0x42525de8: call
    NSAutoreleaseObject at 0x42503d8c, return self) -- the same entry
    NSProxy's instance side uses; parked objects return to the pool
    unchanged (still faults).  */
- (id)autorelease
{
    NSAutoreleaseObject(self);
    return self;
}

/*  0x4251c354: TWO sends only: [NSFault clearFault: self] (first send at
    0x4251c375) then [self release] (second send at 0x4251c382, cell
    0x426089b8).  Because clearFault has restored the isa by then, that
    release reaches the RESTORED class's -release (NSObject's side-table
    one after the make/clear exchange), not -[NSFault release] again --
    which is what terminates a count-1 faulted object via
    decrementExtraRefCountWasZero -> dealloc -> clearFault -> release.  */
- (void)dealloc
{
    [NSFault clearFault:self];
    [self release];
}

/*  0x42573c3c: NSZoneFromPointer(self), falling back to
    NSDefaultMallocZone() when it answers NULL.  */
- (NSZone *)zone
{
    NSZone *zone = NSZoneFromPointer(self);

    return zone ? zone : NSDefaultMallocZone();
}

- (BOOL)isFault
{
    return YES;
}

/*  Proem + NSLog + raise, all with the SHARED format object at
    0x42606b0c (same object the class side uses).  */
- (void)doesNotRecognizeSelector:(SEL)aSelector
{
    Class targetClass = [self->_handler targetClass];

    NSLog(@"%@: selector not recognized",
          _NSMethodExceptionProem(targetClass, aSelector));
    [NSException raise:NSInvalidArgumentException
                format:@"%@: selector not recognized",
                       _NSMethodExceptionProem(targetClass, aSelector)];
}

/*  Instance description forwards to the handler (0x42573aa8: one send,
    selector cell 0x42609170 = 'descriptionForObject:').  */
- (NSString *)description
{
    return [self->_handler descriptionForObject:self];
}

/*  Same selector cell 0x42608974 as +debugDescription: [self
    description].  */
- (id)debugDescription
{
    return [self description];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    /*  0x42525ca0: [handler shouldPerformInvocation: inv] gates the
        completion+dispatch pair.  Body shape: [handler
        completeInitializationOfObject: self] (second send), then
        [inv invokeWithTarget: self] (third send).  Task 12 owns the
        sequence's semantics; the sends are decoded here because this
        body is where they live.  */
    if ([self->_handler shouldPerformInvocation:anInvocation]) {
        [self->_handler completeInitializationOfObject:self];
        [anInvocation invokeWithTarget:self];
    }
}

/*  The compiled body: unconditional raise with the literal reference
    format string recovered from the cstring_object at 0x42606b18
    ('*** -[NSFault forward::] not overridden!').  The reference's
    +initialize overwrites this method's imp with NSObject's before any
    test can observe it (static-flag-guarded, 0x42551610); this body is
    what runs before that patch takes effect.  */
- (id)forward:(SEL)aSelector :(marg_list)argFrame
{
    [NSException raise:NSInvalidArgumentException
                format:@"*** -[NSFault forward::] not overridden!"];
    return nil;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
#if defined(__ppc__) || defined(__POWERPC__)
    return [self->_handler methodSignatureForSelector:aSelector];
#else
    return [self->_handler methodSignatureForSelector:aSelector forFault:self];
#endif
}

@end

/*  NSFaultHandler: NSObject subclass, 16-byte instances.  The handler
    owns the fault's target state.  All 16 instance methods decoded from
    0x42611950; no class methods of its own (class-side messages inherit
    NSObject's).  */

@implementation NSFaultHandler

- (Class)targetClass
{
    return _targetClass;
}

- (void *)extraData
{
    return _extraData;
}

/*  0x42519d8c: straight field stores at +4/+8.  */
- (void)setTargetClass:(Class)aClass extraData:(void *)data
{
    _targetClass = aClass;
    _extraData = data;
}

- (unsigned)extraRefCount
{
    return _extraRefCount;
}

/*  The target protects this counter with the optional global retain lock.  */
- (void)incrementExtraRefCount
{
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    _extraRefCount++;
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
}

/*  A zero count reports true without decrementing; otherwise decrement once.  */
- (BOOL)decrementExtraRefCountWasZero
{
    BOOL wasZero = NO;

    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    if (_extraRefCount == 0)
        wasZero = YES;
    else
        _extraRefCount--;
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
    return wasZero;
}

/*  0x42573c58: targetClass read, nothing else.  */
- (Class)classForFault:(id)anObject
{
    return _targetClass;
}

/*  0x42573cfc: forward-jump-into-loop identical to NSObject.m's
    class-side walk (jmp before first compare).  */
- (BOOL)isKindOfClass:(Class)aClass forFault:(id)anObject
{
    Class candidate;

    for (candidate = _targetClass; candidate != Nil; candidate = candidate->super_class)
        if (candidate == aClass)
            return YES;
    return NO;
}

/*  0x42573d28: single compare of _targetClass (+4) against aClass.  */
- (BOOL)isMemberOfClass:(Class)aClass forFault:(id)anObject
{
    return _targetClass == aClass;
}

/*  0x4253c6d4: objc_msgSend(_targetClass, cell 0x42609130 =
    'instancesRespondToSelector:', sel) -- a CLASS-side send to the
    target class, not a class_respondsToMethod call.  */
- (BOOL)respondsToSelector:(SEL)aSelector forFault:(id)anObject
{
#if defined(__ppc__) || defined(__POWERPC__)
    return objc_msgSend(_targetClass, @selector(instancesRespondToSelector:),
                        aSelector, anObject);
#else
    return [_targetClass instancesRespondToSelector:aSelector];
#endif
}

/*  0x42573ca0: objc_msgSend(_targetClass, 'conformsToProtocol:', proto).
    NSObject implements +conformsToProtocol: (NSObject.m line 120, via
    _NSClassConformsToProtocol).  */
- (BOOL)conformsToProtocol:(Protocol *)aProtocol forFault:(id)anObject
{
#if defined(__ppc__) || defined(__POWERPC__)
    return objc_msgSend(_targetClass, @selector(conformsToProtocol:),
                        aProtocol, anObject);
#else
    return [_targetClass conformsToProtocol:aProtocol];
#endif
}

/*  0x42573cc8: 5 pushes then msgSend -- stringWithFormat-shaped, format
    '<%@(Fault 0x%x)>' with (targetClass, anObject).  Translated with the
    nearest reconstructed equivalent: [NSString stringWithFormat:].  The
    NSString stub aborts on any use (link_stubs.m), so no test may reach
    this body.  */
- (NSString *)descriptionForObject:(id)anObject
{
    return [NSString stringWithFormat:@"<%@(Fault 0x%x)>", _targetClass, anObject];
}

/*  0x42573c68: the reference calls NSRequestConcreteImplementation with
    NSFaultHandler's class object.  */
- (void)completeInitializationOfObject:(id)anObject
{
    NSRequestConcreteImplementation(self, _cmd, [NSFaultHandler class]);
}

/*  0x42519f40: 8-byte empty body.  */
- (void)faultWillFire:(id)anObject
{
}

/*  0x42525c48: mov eax, 1.  */
- (BOOL)shouldPerformInvocation:(NSInvocation *)anInvocation
{
    return YES;
}

/*  0x42525c54: objc_msgSend(_targetClass, cell 0x4260912c =
    'instanceMethodSignatureForSelector:', sel) -- a CLASS-side send to
    the target class, not methodSignatureForSelector:.  */
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector forFault:(id)anObject
{
    return [_targetClass instanceMethodSignatureForSelector:aSelector];
}

@end
