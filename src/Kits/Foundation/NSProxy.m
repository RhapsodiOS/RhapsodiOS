/*	NSProxy.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSProxy.h>
#import <Foundation/NSException.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSString.h>
#import <objc/objc-runtime.h>
#import <objc/Protocol.h>

/*  Routines this file calls that are not declared by any header this
    project ships: the runtime's own private routine (present in the
    guest's System framework, but only declared in its build-internal
    objc-private.h, which isn't part of the shipped Headers -- the same
    one NSObject.m declares locally for the same reason), and a
    NSProxy-specific null-selector diagnostic helper the reference calls
    from its own performSelector: family.  NSObject.m has
    _NSObjectRaiseNullSelectorException for the identical purpose; the
    reference gives NSProxy its own, separately named, helper -- one per
    root class, confirmed from the disassembly (both root classes'
    performSelector: bodies are otherwise byte-for-byte the same shape,
    differing only in which helper they call).  */

extern BOOL class_respondsToMethod(Class aClass, SEL aSelector);
extern void _NSProxyRaiseNullSelectorException(id object, SEL aSelector);

/*  Backs both +load and +initialize, same as NSObject.m's Task 8 addition
    (the reference gives both root classes' +load identical one-call
    bodies).  */
extern void _NSInitializePlatform(void);

@implementation NSProxy

+ (void)load {
    _NSInitializePlatform();
}

/*  Beyond the +load-style platform hookup every root class needs, the
    reference's +initialize does one more thing: it looks up NSObject's
    and NSProxy's own compiled -forward:: methods by name and overwrites
    NSProxy's method_imp with NSObject's, so that after the first message
    to NSProxy (or any un-initialized subclass) is sent, -forward:: on a
    NSProxy instance actually runs NSObject.m's -forward:: body (raising
    NSInternalInconsistencyException with "*** forward:: implementation
    not overridden") rather than the body compiled for -[NSProxy forward::]
    below.  Confirmed from the disassembly at 0x4254a4b4-0x4254a523: guarded
    by a static flag, it registers the "forward::" selector once, resolves
    both classes by name (not through self -- the lookups are for the
    literal strings "NSObject" and "NSProxy", not derived from the
    receiver), reads NSObject's Method's method_imp field (struct
    objc_method's third field, objc-class.h) and stores it into NSProxy's
    Method's method_imp field, then calls the same platform hook +load
    does.  -[NSProxy forward::] itself (below) is still reconstructed from
    its own compiled body, since that's what's actually in the binary and
    what runs for any message sent before this patch takes effect.  */
+ (void)initialize {
    static BOOL initialized = NO;

    if (!initialized) {
        SEL twoArgForward;
        Method objectForward;
        Method proxyForward;

        twoArgForward = sel_registerName("forward::");
        objectForward = class_getInstanceMethod(objc_lookUpClass("NSObject"), twoArgForward);
        proxyForward = class_getInstanceMethod(objc_lookUpClass("NSProxy"), twoArgForward);
        proxyForward->method_imp = objectForward->method_imp;
        _NSInitializePlatform();
        initialized = YES;
    }
}

+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 0, zone);
}

+ (id)alloc {
    return [self allocWithZone:NULL];
}

+ (id)copyWithZone:(NSZone *)zone {
    return self;
}

+ (id)mutableCopyWithZone:(NSZone *)zone {
    return self;
}

+ (id)self {
    return self;
}

+ (Class)class {
    return self;
}

+ (BOOL)isAncestorOfObject:(id)anObject {
    Class candidate;

    for (candidate = anObject->isa; candidate != Nil; candidate = candidate->super_class)
        if (candidate == self)
            return YES;
    return NO;
}

+ (BOOL)respondsToSelector:(SEL)aSelector {
    return class_respondsToMethod(self->isa, aSelector);
}

+ (id)performSelector:(SEL)aSelector {
    if (aSelector == NULL)
        _NSProxyRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector);
}

+ (id)performSelector:(SEL)aSelector withObject:(id)object {
    if (aSelector == NULL)
        _NSProxyRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object);
}

+ (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2 {
    if (aSelector == NULL)
        _NSProxyRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object1, object2);
}

/*  Classes are not reference-counted; the reference's class-side
    retain/release/autorelease are no-ops, and retainCount reports a fixed
    sentinel -- identical to NSObject.m's class side.  */

+ (id)retain {
    return self;
}

+ (void)release {
}

+ (unsigned)retainCount {
    return (unsigned)-1;
}

+ (id)autorelease {
    return self;
}

/*  Unlike NSObject, whose instances are never proxies, NSProxy's own
    CLASS OBJECT still answers NO here -- only its instances answer YES
    (below).  Confirmed from the disassembly: +[NSProxy isProxy] is
    `xor eax,eax` (NO), the same as +[NSObject isProxy]; only
    -[NSProxy isProxy] differs from -[NSObject isProxy], returning YES.  */
+ (BOOL)isProxy {
    return NO;
}

+ (BOOL)isFault {
    return NO;
}

+ (NSString *)debugDescription {
    return [self description];
}

/*  Identity and equality.  */

- (id)self {
    return self;
}

- (BOOL)isEqual:(id)object {
    return self == object;
}

- (unsigned)hash {
    return (unsigned)self >> 2;
}

/*  Class introspection.  */

- (Class)class {
    return isa;
}

- (Class)superclass {
    return isa->super_class;
}

/*  isKindOfClass:/isMemberOfClass:/conformsToProtocol:/respondsToSelector:
    do NOT answer directly from isa the way NSObject's do.  The reference's
    four bodies (0x42574974, 0x42574b3c, 0x42574bc8, 0x42574d18) are all the
    same unconditional, branch-free shape: build a helper object via
    `[NSInvocationBuilder builderForClass: [NSObject class]->isa]`, send it
    the very selector being answered (recording that call, along with this
    method's own argument, on the helper), `[helper setTarget: self]`, hand
    the helper to `[self forwardInvocation: helper]`, then pull the answer
    back out with `[helper getReturnValue: &result]`.  NSProxy routes its
    own type-identity questions through the same forwarding path as
    everything else it doesn't implement, rather than answering for itself
    -- consistent with "NSProxy exists to forward" from a class that (unlike
    NSObject) has no real state to answer from.

    NSInvocationBuilder itself is not one of this task's 27+20 ABI methods,
    has no header in this tree, and is not NSInvocation or NSMethodSignature
    (the two dependencies the brief names for -forwardInvocation:/
    -methodSignatureForSelector: and defers to stage 2c) -- it is a further,
    separate private class this stage's scope does not cover. Reconstructing
    it would mean inventing an entire undocumented class's method table.
    What IS reconstructed here is the externally-observable shape the
    disassembly actually shows: these four methods forward to
    -forwardInvocation:, and since -forwardInvocation: below always raises
    (see its own comment -- it never reads its argument), that's the
    observable result for any NSProxy instance that hasn't overridden
    -forwardInvocation:, exactly matching the reference.  The gap: without
    a real NSInvocation, a subclass that DOES override -forwardInvocation:
    to inspect the invocation's selector/arguments for one of these four
    calls specifically will not see them here (nil is passed) -- deferred
    to stage 2c alongside NSInvocationBuilder itself.  No test in this
    stage exercises that path.  */

- (BOOL)isKindOfClass:(Class)aClass {
    [self forwardInvocation:nil];
    return NO;
}

- (BOOL)isMemberOfClass:(Class)aClass {
    [self forwardInvocation:nil];
    return NO;
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
    [self forwardInvocation:nil];
    return NO;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    [self forwardInvocation:nil];
    return NO;
}

/*  Not part of NSProxy.h, but in the ABI's 27: a forwarding-decision
    helper distinct from -respondsToSelector: above (that one forwards
    unconditionally, per the comment above it).  This one answers directly
    from isa, the ordinary way: YES exactly when self's own class does NOT
    already implement aSelector, i.e. when forwarding would actually be
    needed.  Confirmed from the disassembly (0x42556170): a single
    class_respondsToMethod(self->isa, aSelector) call, negated.  */
- (BOOL)willForwardSelector:(SEL)aSelector {
    return !class_respondsToMethod(isa, aSelector);
}

/*  Message forwarding.  */

/*  Confirmed from the disassembly (0x42574a68-0x42574a9d): self and the
    proem NSObject.m's version builds are never read here -- NSProxy's
    doesNotRecognizeSelector: raises directly with the selector spliced
    into a fixed NSProxy-specific format string, one %s substitution, no
    NSLog call first.  String recovered from the analysis JSON's `strings`
    array via the reference's own `references`/`relocations` tables (the
    __cstring_object at 0x42606e6c relocates its `bytes` field to
    aNsproxyDoesnot @ 0x425fc773), the same route Task 7's fix used for
    NSObject.m's three format strings -- not invented.  aSelector is a raw
    SEL; this runtime's selectors are themselves interned C strings, so the
    reference substitutes it directly with %s (no sel_getName call in the
    disassembly).  */
- (void)doesNotRecognizeSelector:(SEL)aSelector {
    [NSException raise:NSInvalidArgumentException
                format:@"*** -[NSProxy doesNotRecognizeSelector:%s] called!", (char *)aSelector];
}

/*  The reference's -forward:: (0x42574aa0-0x42574ad3) never reads self,
    aSelector, or argFrame -- it raises this fixed, zero-substitution
    string unconditionally.  String recovered the same way as above (the
    __cstring_object at 0x42606e48 relocates to aNsproxyForward @
    0x425fc6ed).  This is the body actually compiled for the selector;
    +initialize above overwrites its installed method_imp with NSObject's
    once the runtime has run it, but the compiled body below is what the
    reference's binary actually contains for -[NSProxy forward::] and what
    runs for any earlier caller.  */
- (id)forward:(SEL)aSelector :(marg_list)argFrame {
    [NSException raise:NSInvalidArgumentException format:@"*** -[NSProxy forward::] not overridden!"];
    return nil;
}

/*  Also unconditional and argument-blind, confirmed the same way
    (0x42574ad4-0x42574b05; __cstring_object at 0x42606e54 relocates to
    aNsproxyForward_0 @ 0x425fc716).  This is the abstract method the
    brief calls out by name: a NSProxy subclass is expected to override
    this to do real forwarding (as _NSZombie in NSObject.m does); the base
    implementation just refuses.  */
- (void)forwardInvocation:(NSInvocation *)anInvocation {
    [NSException raise:NSInvalidArgumentException format:@"*** -[NSProxy forwardInvocation:] called!"];
}

/*  The brief's other named-abstract method.  Same shape again
    (0x42574c54-0x42574c87; __cstring_object at 0x42606e60 relocates to
    aNsproxyMethods @ 0x425fc740) -- sel is never read, the raise is
    unconditional and zero-substitution.  */
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    [NSException raise:NSInvalidArgumentException format:@"*** -[NSProxy methodSignatureForSelector:] called!"];
    return nil;
}

- (id)performSelector:(SEL)aSelector {
    if (aSelector == NULL)
        _NSProxyRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector);
}

- (id)performSelector:(SEL)aSelector withObject:(id)object {
    if (aSelector == NULL)
        _NSProxyRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object);
}

- (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2 {
    if (aSelector == NULL)
        _NSProxyRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object1, object2);
}

/*  Retain/release.  Thin wrappers over the same refcount primitives
    NSObject.m's instance side uses (NSZone.m, Task 6) -- matches the
    reference exactly.  */

- (id)retain {
    NSIncrementExtraRefCount(self);
    return self;
}

- (void)release {
    if (NSDecrementExtraRefCountWasZero(self))
        [self dealloc];
}

- (unsigned)retainCount {
    return NSExtraRefCount(self) + 1;
}

- (id)autorelease {
    NSAutoreleaseObject(self);
    return self;
}

- (void)dealloc {
    NSDeallocateObject(self);
}

/*  Unlike -[NSObject zone], which falls back to NSDefaultMallocZone() when
    NSZoneFromPointer returns NULL, the reference's -[NSProxy zone]
    (0x42574dd4) has no fallback -- it is exactly `return
    NSZoneFromPointer(self);`.  Reproduced as-is rather than assuming
    symmetry with NSObject.  */
- (NSZone *)zone {
    return NSZoneFromPointer(self);
}

/*  Instances ARE proxies -- the one instance-side answer that differs from
    NSObject's (see the class-side comment above +isProxy).  Confirmed
    `mov eax,1` at 0x425561dc, unlike every other YES/NO method in this
    file (all `xor eax,eax` / `mov eax,0FFFFFFFFh`-style constants).  */
- (BOOL)isProxy {
    return YES;
}

- (BOOL)isFault {
    return NO;
}

/*  Class name plus pointer, the same shape as -[NSObject description] --
    but reads the name through a message send, `[self class]->name`, not
    directly through the isa ivar.  Confirmed from the disassembly
    (0x42574a20-0x42574a66): the first call's return value is dereferenced
    at offset +8, the `name` field of struct objc_class (objc-class.h:
    isa@0, super_class@4, name@8), so its receiver must be a Class; the
    only zero-argument message NSProxy sends to itself that returns a
    Class is -class.  The selector text itself is NOT recoverable from
    this analysis -- its __message_refs cell resolves to address
    0x414067b4, outside this slice (in the same out-of-slice prebound-image
    range as NSObject.m's +new selectors at 0x414067cc/0x41406990), the
    genuine-unrecoverable case the brief warns exists alongside the
    recoverable ones.  Using `[self class]` rather than `isa` directly also
    matches NSProxy's own purpose: a subclass that overrides -class to
    report a different apparent identity (the point of a transparent
    proxy) gets that override reflected in its description, where reading
    isa directly would not.  Format string recovered verbatim the same way
    as the others above (__cstring_object at 0x42606e78 relocates to
    aS0xX_1 @ 0x425f9f01, "<%s: 0x%x>").  */
- (NSString *)description {
    Class class = [self class];

    return [NSString stringWithFormat:@"<%s: 0x%x>", class->name, self];
}

- (NSString *)debugDescription {
    return [self description];
}

@end
