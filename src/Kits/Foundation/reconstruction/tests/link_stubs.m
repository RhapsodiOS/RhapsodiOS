/*  Link stubs for stage 2a's test binaries.

    Foundation symbols the reconstructed modules reference but that this stage
    does not implement.  Every stub aborts: a test that reaches one is depending
    on unreconstructed behaviour and must fail loudly rather than quietly
    observing a plausible-looking default.  */

#import <objc/objc.h>
#import <objc/Object.h>
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
@end

@implementation NSException
+ (void)raise:(id)name format:(id)format, ...
{
    unimplemented("[NSException raise:format:]");
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
