/*  Link stubs for stage 2a's test binaries.

    Foundation symbols the reconstructed modules reference but that this stage
    does not implement.  Every stub aborts: a test that reaches one is depending
    on unreconstructed behaviour and must fail loudly rather than quietly
    observing a plausible-looking default.  */

#import <objc/objc.h>
#import <objc/Object.h>
#import <objc/Protocol.h>
#include <stdio.h>
#include <stdlib.h>

static void unimplemented(const char *name)
{
    fprintf(stderr, "link stub reached: %s\n", name);
    abort();
}

/*  NSKeepAllocationStatistics gates every allocation-statistics call site
    in NSZone.m; every test in this stage leaves it at its real default
    (NO), so the calls it guards are never actually reached.  */
BOOL NSKeepAllocationStatistics = 0;

/*  NSException and NSInvalidArgumentException back NSZone.m's memory-page
    error paths (vm_allocate/vm_deallocate/vm_copy failing), which the
    tests never provoke.  NSException here is a minimal root class (not a
    subclass of the not-yet-reconstructed NSObject) that exists only to
    supply the linker symbol and abort if a test ever does reach it.  */
id NSInvalidArgumentException = 0;

@interface NSException : Object
+ (void)raise:(id)name format:(id)format, ...;
+ (id)exceptionWithName:(id)name reason:(id)reason userInfo:(id)userInfo;
- (void)raise;
@end

@implementation NSException
+ (void)raise:(id)name format:(id)format, ...
{
    unimplemented("[NSException raise:format:]");
}
+ (id)exceptionWithName:(id)name reason:(id)reason userInfo:(id)userInfo
{
    unimplemented("[NSException exceptionWithName:reason:userInfo:]");
    return nil;
}
- (void)raise
{
    unimplemented("[NSException raise]");
}
@end

/*  NXConstantString's class reference backs every @"..." literal in a
    compiled translation unit, including NSZoneName's `return @"";` --
    referenced by NSZone.m's object code whether or not that path runs.
    NXConstantString itself is not reconstructed, so this is a zeroed
    placeholder: safe as long as no test actually sends a message to a
    string literal, which none in this stage do.  */
struct objc_class _NSConstantStringClassReference;

void NSRecordAllocationEvent(int eventType, ...)
{
    unimplemented("NSRecordAllocationEvent");
}

/*  Task 7 (NSObject's instance methods) additions.  NSInternalInconsistencyException
    is another exception-name constant, inert for the same reason
    NSInvalidArgumentException above is: only read by code paths the
    abort()-ing NSException stub is set up to catch before it's used.  */
id NSInternalInconsistencyException = 0;

/*  Foundation-private helpers NSObject.m's reference calls but that no
    stage-2a task has reconstructed yet (NSPrivate/NSAutoreleasePool
    territory).  */
IMP _NSIMPForSelector(Class aClass, SEL aSelector)
{
    unimplemented("_NSIMPForSelector");
    return NULL;
}

struct objc_method_description *_NSMethodDescriptionForSelector(Class aClass, SEL aSelector)
{
    unimplemented("_NSMethodDescriptionForSelector");
    return NULL;
}

BOOL _NSClassConformsToProtocol(Class aClass, Protocol *aProtocol)
{
    unimplemented("_NSClassConformsToProtocol");
    return NO;
}

id _NSMethodExceptionProem(id object, SEL aSelector)
{
    unimplemented("_NSMethodExceptionProem");
    return nil;
}

void _NSObjectRaiseNullSelectorException(id object, SEL aSelector)
{
    unimplemented("_NSObjectRaiseNullSelectorException");
}

void NSAutoreleaseObject(id anObject)
{
    unimplemented("NSAutoreleaseObject");
}

void NSLog(id format, ...)
{
    unimplemented("NSLog");
}

/*  NSMethodSignature and NSString are not reconstructed until later
    (NSMethodSignature.m is task-8-plus territory; NSString.m is stage 3).
    -methodSignatureForSelector: and -description need their class objects
    to link; minimal stub classes, not subclasses of NSObject, for the same
    reason NSException above isn't -- ObjC dispatch is purely selector-based
    so the real superclass doesn't matter to a stub that only aborts.  */
@interface NSMethodSignature : Object
+ (id)signatureWithObjCTypes:(const char *)types;
@end

@implementation NSMethodSignature
+ (id)signatureWithObjCTypes:(const char *)types
{
    unimplemented("[NSMethodSignature signatureWithObjCTypes:]");
    return nil;
}
@end

@interface NSString : Object
+ (id)stringWithFormat:(id)format, ...;
+ (id)stringWithCString:(const char *)bytes length:(unsigned)length;
@end

@implementation NSString
+ (id)stringWithFormat:(id)format, ...
{
    unimplemented("[NSString stringWithFormat:]");
    return nil;
}
+ (id)stringWithCString:(const char *)bytes length:(unsigned)length
{
    unimplemented("[NSString stringWithCString:length:]");
    return nil;
}
@end

/*  Task 8 (NSObject's class methods and _NSZombie) additions.  */

/*  NSGenericException backs _NSZombie's diagnostic raise, which none of
    this stage's tests provoke -- inert for the same reason
    NSInvalidArgumentException above is.  */
id NSGenericException = 0;

/*  NSZombieEnabled/NSDeallocateZombies gate NSZone.m's zombie path in
    NSDeallocateObject; every test in this stage leaves them at their real
    defaults (NO), so that path is never actually reached.  */
BOOL NSZombieEnabled = 0;
BOOL NSDeallocateZombies = 0;

/*  _NSInitializePlatform backs +[NSObject load]/+[NSObject initialize].
    Unlike this file's other stubs, +load fires unconditionally -- the
    Objective-C runtime calls every loaded class's +load automatically
    before main() runs, not only when a test explicitly exercises that
    path -- so an abort()-ing stub here would fail every test that links
    NSObject.m, including ones that have nothing to do with Task 8.  A
    silent no-op is the correct stand-in until this is reconstructed.  */
void _NSInitializePlatform(void)
{
}

/*  NSStringFromStack backs _NSZombie's backtrace text (NSDebug.h's "Stack
    processing" group) -- not reconstructed yet, and only reachable by
    actually sending a message to a zombie, which no test in this stage
    does, so this one keeps the usual abort()-ing shape.  */
id NSStringFromStack(id format, id separator)
{
    unimplemented("NSStringFromStack");
    return nil;
}

/*  Task 9 (NSProxy) addition.  NSProxy's own null-selector diagnostic
    helper, the direct counterpart to _NSObjectRaiseNullSelectorException
    above -- not reconstructed (NSPrivate territory, Task 10), and not
    reached by any test in this stage (none call performSelector: with a
    NULL selector).  */
void _NSProxyRaiseNullSelectorException(id object, SEL aSelector)
{
    unimplemented("_NSProxyRaiseNullSelectorException");
}
