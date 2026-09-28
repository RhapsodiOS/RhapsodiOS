/*  Link stubs for the Foundation reconstruction's test binaries.

    Foundation symbols the reconstructed modules reference but that no
    reconstructed module yet supplies.  Every stub aborts: a test that
    reaches one is depending on unreconstructed behaviour and must fail
    loudly rather than quietly observing a plausible-looking default.

    What remains here after stage 2b, and who owns each symbol's real
    reconstruction:
    - unimplemented (this file's own reporting helper)
    - NSKeepAllocationStatistics, NSRecordAllocationEvent, NSZombieEnabled,
      NSDeallocateZombies -- NSZone.m's allocation-statistics and zombie
      gates; the tests never set them
    - _NSConstantStringClassReference -- stage 3 (real NSString)
    - NSMethodSignature -- stage 3 territory
    - NSString stub class -- stage 3; no test reaches it any more
    - _NSInitializePlatform -- backs +load/+initialize, silent no-op
    - NSStringFromStack -- NSDebug.h stack text, stage 3 territory
    Stage 2b retired: the stub NSException class and its raise-capture
    machinery, the three exception-name placeholder globals, the three
    introspection helpers, NSLog, and _NSMethodExceptionProem.  */

#import <objc/objc.h>
#import <objc/Object.h>
#import <objc/Protocol.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void unimplemented(const char *name)
{
    fprintf(stderr, "link stub reached: %s\n", name);
    abort();
}

/*  The stage 2a raise-capture machinery (NSTestRaiseEnv,
    NSTestExpectingRaise, NSTestRaiseMessage and NSTestCaptureRaiseMessage)
    was retired in stage 2b: with the real NSException class and handler
    stack reconstructed, the suites catch raises the way any caller does --
    NS_DURING/NS_HANDLER -- instead of arming a stub.  */

/*  NSKeepAllocationStatistics gates every allocation-statistics call site
    in NSZone.m; every test in this stage leaves it at its real default
    (NO), so the calls it guards are never actually reached.  */
BOOL NSKeepAllocationStatistics = 0;

/*  The exception-name constants NSZone.m, NSObject.m and NSProxy.m
    reference back their memory-page and diagnostic error paths, which
    the tests never provoke.  The zeroed placeholder globals that used
    to stand in for them were removed when NSException.m defined the
    real NXConstantString constants (stage 2b Task 9); the placeholders
    collided with them at link time, and the real constants satisfy the
    same references.  */

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

/*  NSInternalInconsistencyException (Task 7 note) moved to NSException.m
    with the other real exception-name constants in stage 2b Task 9.

    Foundation-private helpers NSObject.m's reference calls.  The three
    introspection helpers (_NSIMPForSelector,
    _NSMethodDescriptionForSelector, _NSClassConformsToProtocol) moved to
    NSObjCRuntime.m, and _NSMethodExceptionProem to NSException.m, in
    stage 2b; none is stubbed here any more.  */

void _NSObjectRaiseNullSelectorException(id object, SEL aSelector)
{
    unimplemented("_NSObjectRaiseNullSelectorException");
}

/*  NSLog is defined by NSObjCRuntime.m (stage 2b), which now links into
    every suite that links this file; this file's abort()-ing stub was
    removed when NSObjCRuntime.m joined the link line, because the two
    definitions collided.  Its TODO body still does nothing until Task 4
    reconstructs the real formatter.  */

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
    above.  Not part of NSAutoreleasePool.json or NSPrivate.json's method
    lists, so Task 10 does not reconstruct it either -- still not
    reconstructed, and not reached by any test in this stage (none call
    performSelector: with a NULL selector).  */
void _NSProxyRaiseNullSelectorException(id object, SEL aSelector)
{
    unimplemented("_NSProxyRaiseNullSelectorException");
}
