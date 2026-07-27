/*	NSObject.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSString.h>
#import <objc/objc-runtime.h>
#import <objc/Protocol.h>

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
extern const char *_NSMethodExceptionProem(id object, SEL aSelector);
extern void _NSObjectRaiseNullSelectorException(id object, SEL aSelector);
extern void NSAutoreleaseObject(id anObject);

@implementation NSObject

+ (void)load {
    // TODO: Implement this method
}

+ (void)initialize {
    // TODO: Implement this method
}

+ (id)new {
    // TODO: Implement this method
    return nil;
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
    // TODO: Implement this method
    return nil;
}

+ (id)mutableCopyWithZone:(NSZone *)zone {
    // TODO: Implement this method
    return nil;
}

+ (Class)superclass {
    // TODO: Implement this method
    return nil;
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
    // TODO: Implement this method
}

+ (BOOL)instancesRespondToSelector:(SEL)aSelector {
    // TODO: Implement this method
    return NO;
}

+ (BOOL)conformsToProtocol:(Protocol *)protocol {
    // TODO: Implement this method
    return NO;
}

+ (IMP)instanceMethodForSelector:(SEL)aSelector {
    // TODO: Implement this method
    return NULL;
}

+ (int)version {
    // TODO: Implement this method
    return 0;
}

+ (void)setVersion:(int)aVersion {
    // TODO: Implement this method
}

+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)aSelector {
    // TODO: Implement this method
    return nil;
}

+ (NSString *)description {
    // TODO: Implement this method
    return nil;
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
    const char *proem = _NSMethodExceptionProem(self, aSelector);

    NSLog(@"%s does not recognize the selector", proem);
    [NSException raise:NSInvalidArgumentException format:@"%s does not recognize the selector", proem];
}

- (id)forward:(SEL)aSelector :(marg_list)argFrame {
    [NSException raise:NSInternalInconsistencyException format:@"NSObject does not forward messages"];
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
    return [NSString stringWithFormat:@"<%s: %p>", isa->name, self];
}

- (NSString *)debugDescription {
    return [self description];
}

@end
