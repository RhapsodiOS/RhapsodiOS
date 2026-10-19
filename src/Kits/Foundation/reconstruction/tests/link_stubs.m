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
    - NSString stub class -- test-only placeholder; the full implementation
      lives in NSString.m
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
    stage 2b; none is stubbed here any more.  The global
    _NSObjectRaiseNullSelectorException/_NSProxyRaiseNullSelectorException
    stubs that used to stand in here were removed in stage 2c: NSObject.m
    and NSProxy.m each define their own static versions (stage 2b Task 11),
    and nothing referenced the stub globals.  */

/*  NSLog and NSLogv are defined by NSObjCRuntime.m, which now links into
    every suite that links this file.  The old abort()-ing stub was removed
    when NSObjCRuntime.m joined the link line, because the two definitions
    collided.  That module now reconstructs the target's formatting and
    logging path.  */

/*  Full NSString behavior lives in NSString.m.  These isolated test suites
    link selected Foundation sources only, so a minimal stub class provides
    the NSString class object needed by -methodSignatureForSelector: and
    -description.  Its unimplemented factories intentionally fail if a test
    exercises those paths without linking the real NSString implementation.  */
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
    processing" group); its implementation lives in NSDebug.m.  This
    test-only aborting stand-in is used by suites that do not link NSDebug.m. */
id NSStringFromStack(id format, id separator)
{
    unimplemented("NSStringFromStack");
    return nil;
}

/*  Task 9 (NSProxy) addition retired in stage 2c: NSProxy.m defines its
    own static _NSProxyRaiseNullSelectorException (stage 2b Task 11), so
    this file never needed to supply it once that landed -- the global
    stub was unreferenced dead code.  */
