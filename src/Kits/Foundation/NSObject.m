/*	NSObject.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSString.h>
#import <Foundation/NSProxy.h>
#import <objc/objc-runtime.h>
#import <objc/Protocol.h>
#include <string.h>

/*  Routines this file calls that are not declared by any header this
    project ships: either the Objective-C runtime's own private routines
    (present in the guest's System framework, but only declared in its
    build-internal objc-private.h, which isn't part of the shipped
    Headers), or Foundation-internal helpers that stage 2a hasn't
    reconstructed yet (NSPrivate/NSAutoreleasePool, later tasks).  Declared
    locally with the signatures the reference disassembly calls them with.  */

extern BOOL class_respondsToMethod(Class aClass, SEL aSelector);
extern id _objc_msgForward(id self, SEL op, ...);

extern IMP _NSIMPForSelector(Class aClass, SEL aSelector);
extern struct objc_method_description *_NSMethodDescriptionForSelector(Class aClass, SEL aSelector);
extern BOOL _NSClassConformsToProtocol(Class aClass, Protocol *aProtocol);
extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern void _NSObjectRaiseNullSelectorException(id object, SEL aSelector);
extern void NSAutoreleaseObject(id anObject);

/*  Task 8 additions.  _NSInitializePlatform backs both +load and
    +initialize (the reference gives them identical bodies).
    NSStringFromStack backs _NSZombie's diagnostic message (NSDebug.h's
    "Stack processing" group, stage 3 territory -- not reconstructed).  */
extern void _NSInitializePlatform(void);
extern NSString *NSStringFromStack(NSString *format, NSString *separator);

@implementation NSObject

+ (void)load {
    _NSInitializePlatform();
}

+ (void)initialize {
    _NSInitializePlatform();
}

/*  The reference builds this as [[self alloc] init] (two chained
    objc_msgSend calls, receiver of the second being the first's result).
    The two selector cells it reads live in __message_refs entries this
    slice's own relocations resolve to an address outside the slice
    (0x414067cc/0x41406990 -- another prebound image, not present in
    Foundation-i386), so the exact selector text can't be pulled from this
    analysis the way the doesNotRecognizeSelector:/description strings
    could; the two-call shape plus +new's single, unchanged definition
    throughout the OpenStep/Cocoa lineage leave no other candidate.  */
+ (id)new {
    return [[self alloc] init];
}

/*  allocWithZone:/alloc are scoped to Task 8 along with the rest of
    NSObject's class methods, but the brief's own test_object.m -- written
    verbatim from the brief and not ours to change -- allocates real
    instances with `[[NSObject alloc] init]`, which is unrunnable while
    +alloc returns nil.  Implemented here as a deliberate, disclosed
    exception (see the stage 2a Task 7 report); confirmed against the
    reference disassembly, which is exactly this two-line handoff to
    NSAllocateObject.  The other 45 class methods and _NSZombie are
    untouched.  */
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

+ (Class)superclass {
    return ((Class)self)->super_class;
}

/*  Also scoped to Task 8, and also implemented here for the same reason as
    +allocWithZone:/+alloc above: the brief's test_object.m compares
    `[object class]` against `[NSObject class]`, which is unrunnable while
    +class returns nil.  The reference is exactly `return self;` (a class
    method's "self" is the class object).  */
+ (Class)class {
    return self;
}

+ (void)poseAsClass:(Class)aClass {
    class_poseAs(self, aClass);
}

+ (BOOL)instancesRespondToSelector:(SEL)aSelector {
    return class_respondsToMethod(self, aSelector);
}

+ (BOOL)conformsToProtocol:(Protocol *)protocol {
    return _NSClassConformsToProtocol(self, protocol);
}

+ (IMP)instanceMethodForSelector:(SEL)aSelector {
    return _NSIMPForSelector(self, aSelector);
}

+ (int)version {
    return ((Class)self)->version;
}

+ (void)setVersion:(int)aVersion {
    ((Class)self)->version = aVersion;
}

+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)aSelector {
    struct objc_method_description *description = _NSMethodDescriptionForSelector(self, aSelector);

    if (description == NULL)
        return nil;
    return [NSMethodSignature signatureWithObjCTypes:description->types];
}

/*  The class name, by way of the same stringWithCString:length: entry
    point +[NSObject description] resolves to in the reference (recovered
    the same way as the doesNotRecognizeSelector:/description-instance
    strings: __message_refs symbol paStringwithcstr_0, dereferenced to
    "stringWithCString:length:" in this slice).  */
+ (NSString *)description {
    Class class = (Class)self;

    return [NSString stringWithCString:class->name length:strlen(class->name)];
}

/*  Identity and equality (class side).  A class's "self" is the class
    object itself; its "isa" is its metaclass.  Which of the two a given
    method reads is pinned per-method from the disassembly, the same way
    Task 7 pinned it for the instance side: anything about *this class
    object's own dispatch* (+respondsToSelector:, +methodForSelector:,
    +implementsSelector:, +isMemberOfClass:, +methodSignatureForSelector:,
    +methodDescriptionForSelector:) reads self->isa; anything about the
    instances this class produces (+instancesRespondToSelector:,
    +instanceMethodForSelector:, +instanceMethodSignatureForSelector:,
    +instanceMethodDescriptionForSelector:, +instancesImplementSelector:)
    reads self directly.  */

+ (id)self {
    return self;
}

+ (BOOL)isEqual:(id)object {
    return self == object;
}

+ (unsigned)hash {
    return (unsigned)self >> 2;
}

+ (BOOL)isKindOfClass:(Class)aClass {
    Class candidate;

    for (candidate = self->isa; candidate != Nil; candidate = candidate->super_class)
        if (candidate == aClass)
            return YES;
    return NO;
}

+ (BOOL)isMemberOfClass:(Class)aClass {
    return self->isa == aClass;
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

+ (BOOL)implementsSelector:(SEL)aSelector {
    return _NSIMPForSelector(self->isa, aSelector) != (IMP)_objc_msgForward;
}

+ (BOOL)instancesImplementSelector:(SEL)aSelector {
    return _NSIMPForSelector(self, aSelector) != (IMP)_objc_msgForward;
}

+ (IMP)methodForSelector:(SEL)aSelector {
    return _NSIMPForSelector(self->isa, aSelector);
}

+ (struct objc_method_description *)methodDescriptionForSelector:(SEL)aSelector {
    return _NSMethodDescriptionForSelector(self->isa, aSelector);
}

+ (struct objc_method_description *)instanceMethodDescriptionForSelector:(SEL)aSelector {
    return _NSMethodDescriptionForSelector(self, aSelector);
}

+ (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    struct objc_method_description *description = _NSMethodDescriptionForSelector(self->isa, aSelector);

    if (description == NULL)
        return nil;
    return [NSMethodSignature signatureWithObjCTypes:description->types];
}

/*  Message forwarding (class side).  */

+ (void)doesNotRecognizeSelector:(SEL)aSelector {
    id proem = _NSMethodExceptionProem(self, aSelector);

    NSLog(@"%@: selector not recognized", proem);
    proem = _NSMethodExceptionProem(self, aSelector);
    [NSException raise:NSInvalidArgumentException format:@"%@: selector not recognized", proem];
}

+ (void)forwardInvocation:(NSInvocation *)anInvocation {
    [self doesNotRecognizeSelector:[anInvocation selector]];
}

+ (id)performSelector:(SEL)aSelector {
    if (aSelector == NULL)
        _NSObjectRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector);
}

+ (id)performSelector:(SEL)aSelector withObject:(id)object {
    if (aSelector == NULL)
        _NSObjectRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object);
}

+ (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2 {
    if (aSelector == NULL)
        _NSObjectRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object1, object2);
}

/*  Retain/release (class side).  Classes are not reference-counted; the
    reference's class-side retain/release/autorelease are no-ops, and
    retainCount reports a fixed sentinel.  */

+ (id)init {
    return self;
}

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

+ (void)dealloc {
}

+ (NSZone *)zone {
    return NSDefaultMallocZone();
}

+ (BOOL)isProxy {
    return NO;
}

+ (BOOL)isFault {
    return NO;
}

/*  Coding and copying (class side).  */

+ (id)copy {
    return self;
}

+ (id)mutableCopy {
    return self;
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

- (BOOL)isKindOfClass:(Class)aClass {
    Class candidate;

    for (candidate = isa; candidate != Nil; candidate = candidate->super_class)
        if (candidate == aClass)
            return YES;
    return NO;
}

- (BOOL)isMemberOfClass:(Class)aClass {
    return isa == aClass;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return class_respondsToMethod(isa, aSelector);
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
    return _NSClassConformsToProtocol(isa, aProtocol);
}

- (BOOL)implementsSelector:(SEL)aSelector {
    return _NSIMPForSelector(isa, aSelector) != (IMP)_objc_msgForward;
}

- (IMP)methodForSelector:(SEL)aSelector {
    return _NSIMPForSelector(isa, aSelector);
}

- (struct objc_method_description *)methodDescriptionForSelector:(SEL)aSelector {
    return _NSMethodDescriptionForSelector(isa, aSelector);
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    struct objc_method_description *description = _NSMethodDescriptionForSelector(isa, aSelector);

    if (description == NULL)
        return nil;
    return [NSMethodSignature signatureWithObjCTypes:description->types];
}

/*  Message forwarding.  */

- (void)doesNotRecognizeSelector:(SEL)aSelector {
    id proem = _NSMethodExceptionProem(self, aSelector);

    NSLog(@"%@: selector not recognized", proem);
    proem = _NSMethodExceptionProem(self, aSelector);
    [NSException raise:NSInvalidArgumentException format:@"%@: selector not recognized", proem];
}

- (id)forward:(SEL)aSelector :(marg_list)argFrame {
    [NSException raise:NSInternalInconsistencyException format:@"*** forward:: implementation not overridden"];
    return nil;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    [self doesNotRecognizeSelector:[anInvocation selector]];
}

- (id)performv:(SEL)aSelector :(marg_list)argFrame {
    NSMethodSignature *signature;

    if (self == nil)
        return nil;
    signature = [self methodSignatureForSelector:aSelector];
    if (signature == nil)
        [self doesNotRecognizeSelector:aSelector];
    return objc_msgSendv(self, aSelector, [signature frameLength], argFrame);
}

- (id)performSelector:(SEL)aSelector {
    if (aSelector == NULL)
        _NSObjectRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector);
}

- (id)performSelector:(SEL)aSelector withObject:(id)object {
    if (aSelector == NULL)
        _NSObjectRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object);
}

- (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2 {
    if (aSelector == NULL)
        _NSObjectRaiseNullSelectorException(self, _cmd);
    return objc_msgSend(self, aSelector, object1, object2);
}

- (void)perform:(SEL)aSelector withEachObjectInArray:(id)anArray {
    unsigned count = [anArray count];
    unsigned index;

    if (aSelector == NULL)
        _NSObjectRaiseNullSelectorException(self, _cmd);
    for (index = 0; index < count; index++)
        objc_msgSend(self, aSelector, [anArray objectAtIndex:index]);
}

/*  Retain/release.  */

- (id)init {
    return self;
}

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

- (NSZone *)zone {
    NSZone *zone = NSZoneFromPointer(self);

    if (zone == NULL)
        zone = NSDefaultMallocZone();
    return zone;
}

- (BOOL)isProxy {
    return NO;
}

- (BOOL)isFault {
    return NO;
}

/*  Coding and copying.  */

- (id)copy {
    return [self copyWithZone:NULL];
}

- (id)mutableCopy {
    return [self mutableCopyWithZone:NULL];
}

- (Class)classForCoder {
    return isa;
}

- (id)replacementObjectForCoder:(NSCoder *)aCoder {
    return self;
}

- (id)awakeAfterUsingCoder:(NSCoder *)aDecoder {
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%s: 0x%x>", isa->name, self];
}

- (NSString *)debugDescription {
    return [self description];
}

@end

/*  _NSZombie: NSZombieEnabled's target class.  NSDeallocateObject
    (NSZone.m) retargets a deallocated object's isa to one of these -- one
    synthesized per original class, named "NSZombie_<originalClass>" -- so
    that a message sent afterward is caught here instead of touching freed
    storage, and the diagnostic can still name the object's real class.

    The reference (_NSDeallocateObject, disassembled directly since it's
    within this stage's analysis scope) keeps that original-class -> zombie
    lookup in a real NSMapTable (classToZombie, backed by
    NSCreateMapTableWithZone/NSMapGet/NSMapInsert) and finds the reverse
    mapping for a logging call by linearly walking it
    (NSEnumerateMapTable/NSNextMapEnumeratorPair, in a small local helper
    the reference calls _findOriginalClass).  NSMapTable.m in this tree is
    still unimplemented stubs and is out of this task's file list, so this
    reconstruction substitutes a private table for both directions of that
    lookup -- the same substitution NSZone.m's ExtraRefCountTable already
    makes for NSMapTable's overflow case, for the identical reason.  That
    table (and the synthesis itself) live in NSZone.m, not here: NSZone.m
    is linked into every stage-2a test binary, while this file (NSObject.m)
    is linked only into ones that need NSObject itself, and
    NSDeallocateObject -- the only place that creates a zombie class --
    already lives in NSZone.m.  _NSOriginalClassForZombieClass is the one
    accessor this file needs back, for the diagnostic message's class name.  */

@interface _NSZombie : NSProxy
@end

extern Class _NSOriginalClassForZombieClass(Class zombieClass);

/*  The common trap every _NSZombie method below falls into.  Reconstructed
    directly from the reference's disassembly at 0x42575890 (a local
    symbol, out of this task's analysis-scope export, so pulled with an
    ad hoc idat script against the same slice/database rather than the
    published JSON -- the same slice, just a wider read of it).  Builds
    "*** Selector '<erroringSelector>' sent to dealloced instance
    0x<self> of class <originalClass>.\nBreak at '-[_NSZombie <cmd>]' to
    debug. Stack=<backtrace>" (the 108-byte literal recovered from the
    slice's __cstring section, __cstring_object struct at 0x42606e24),
    logs it prefixed with "*** ", then raises NSGenericException with that
    message as the reason.  erroringSelector is usually cmd (the zombie
    method's own selector) but is the wrapped invocation's original
    selector when called from -forwardInvocation:, and the selector being
    queried when called from -methodSignatureForSelector: -- confirmed
    from each call site's own push sequence, not assumed uniform.  */
static void
logMessageAndRaise(SEL erroringSelector, SEL cmd, id self)
{
    Class originalClass = _NSOriginalClassForZombieClass(self->isa);
    NSString *stack = NSStringFromStack(@"0x%x", @" ");
    NSString *message = [NSString stringWithFormat:
        @"*** Selector '%s' sent to dealloced instance 0x%x of class %s.\n"
        @"Break at '-[_NSZombie %s]' to debug. Stack=%@",
        erroringSelector, self, originalClass->name, cmd, stack];

    NSLog(@"*** %@", message);
    [[NSException exceptionWithName:NSGenericException reason:message userInfo:nil] raise];
}

@implementation _NSZombie

- (void)appendFormat:(id)format {
    logMessageAndRaise(_cmd, _cmd, self);
}

- (id)autorelease {
    logMessageAndRaise(_cmd, _cmd, self);
    return self;
}

- (void)dealloc {
    logMessageAndRaise(_cmd, _cmd, self);
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    logMessageAndRaise([anInvocation selector], _cmd, self);
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    logMessageAndRaise(aSelector, _cmd, self);
    return nil;
}

- (void)release {
    logMessageAndRaise(_cmd, _cmd, self);
}

- (unsigned)retainCount {
    logMessageAndRaise(_cmd, _cmd, self);
    return (unsigned)-1;
}

- (id)retain {
    logMessageAndRaise(_cmd, _cmd, self);
    return self;
}

- (id)stringByAppendingFormat:(id)format {
    logMessageAndRaise(_cmd, _cmd, self);
    return nil;
}

@end
