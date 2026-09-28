/*	NSException.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*	The active exception handlers, innermost first, chained through each
	NSHandler2's own _others field -- so the stack lives in the callers'
	own automatic storage and needs no allocation.

	The reference keys this per thread (NSHandler2 carries a _thread
	field, reached through the out-of-scope _NSCurrentThread()); NSThread.m
	is stage 7, so this is a single process-global chain, the same
	substitution NSAutoreleasePool.m makes for its pool stack and NSZone.m
	for _NSRefCountLock, and for the same reason.  Every test in this stage
	runs unthreaded.  Recorded in divergences.md.  */
static NSHandler2 *NSExceptionHandlerStack = 0;

/*	NS_DURING's expansion calls this with the address of an automatic it
	just declared; the record is the caller's, so this only links it in.  */
void
_NSAddHandler2(NSHandler2 *handler)
{
    if (handler == 0)
        return;

    handler->_exception = nil;
    handler->_others = (void *)NSExceptionHandlerStack;
    handler->_thread = 0;
    handler->_reserved1 = 0;
    NSExceptionHandlerStack = handler;
}

/*	Unlinks `handler`.  NS_VALUERETURN and NS_VOIDRETURN can reach this
	for a handler that is not the innermost -- a return out of the middle
	of a nested NS_DURING -- so this unwinds every handler inside it as
	well rather than assuming it is on top.  */
void
_NSRemoveHandler2(NSHandler2 *handler)
{
    NSHandler2 *scan;

    if (handler == 0)
        return;

    for (scan = NSExceptionHandlerStack; scan != 0; scan = (NSHandler2 *)scan->_others) {
        if (scan == handler) {
            NSExceptionHandlerStack = (NSHandler2 *)handler->_others;
            return;
        }
    }
}

/*	Read by NS_HANDLER's expansion after the transfer, which is why the
	exception is stored on the handler record rather than in a global a
	nested raise could overwrite before this is read.  */
NSException *
_NSExceptionObjectFromHandler2(NSHandler2 *handler)
{
    if (handler == 0)
        return nil;
    return handler->_exception;
}

/*	The pre-NSHandler2 entry point the reference still exports.  The older
	NSHandler is opaque in the shipped header (`typedef struct _NSHandler
	NSHandler;` with no definition), so nothing in this tree can construct
	one; both handler generations share this file's single chain, and this
	reads the same field the current one does.  Recorded in
	divergences.md as structurally reconstructed, not behaviourally
	confirmed.  */
NSException *
_NSExceptionObjectFromHandler(NSHandler2 *handler)
{
    return _NSExceptionObjectFromHandler2(handler);
}

/*	How many handlers are active.  Exported by the reference; used here by
	the test suite to assert the stack balances.  */
unsigned
_NSExceptionHandlerCount(void)
{
    NSHandler2 *scan;
    unsigned count;

    count = 0;
    for (scan = NSExceptionHandlerStack; scan != 0; scan = (NSHandler2 *)scan->_others)
        count++;

    return count;
}

/*	Drops every active handler.  The reference exports this for the
	unwind-everything case (a thread exiting, or a top-level loop
	recovering); nothing in this stage calls it except the tests.  */
void
_NSClearExceptionStack(void)
{
    NSExceptionHandlerStack = 0;
}

/*	The alternate handler pair.  The reference's bytes (0x425106f8 add,
	0x425097f0 remove) show these are NOT chain operations like
	_NSAddHandler2/_NSRemoveHandler2: each opens by fetching a per-thread
	state record and reads a table from it (record +0x14), then works a
	growable array of identifiers allocated 0x98 bytes on first use
	(capacity field 12) and grown by 6 entries through a realloc-style
	call when full.  Add appends one identifier at a 12-byte stride and
	bumps the count; Remove scans for its argument's value, memmoves the
	tail over the slot and decrements the count.  What the identifiers
	are keyed by and who consumes the table is out of this stage's scope
	-- the likely callers are Distributed Objects (stage 8).

	This reconstruction keeps the observed shape -- one growable
	identifier array, first allocation 12 entries, +6 growth, removal by
	tail memmove -- over a single process-global table, the same
	per-thread substitution this file's handler stack makes.  The
	identifier is the handler's own address, which is the only value the
	observed comparison can be shown to round-trip.  Listed in
	divergences.md's untested table: no test can reach the semantics, and
	the callers do not exist until stage 8.  */

typedef struct {
    unsigned	capacity;
    unsigned	count;
    NSHandler2	**identifiers;
} NSAltHandlerTable;

#define NSAltHandlerInitialCapacity 12
#define NSAltHandlerCapacityGrowth 6

static NSAltHandlerTable NSAltHandlers = { NSAltHandlerInitialCapacity, 0, 0 };

void
_NSAddAltHandler2(NSHandler2 *handler)
{
    if (handler == 0)
        return;

    if (NSAltHandlers.identifiers == 0)
        NSAltHandlers.identifiers = (NSHandler2 **)
            NSZoneMalloc(0, NSAltHandlers.capacity * sizeof(NSHandler2 *));

    if (NSAltHandlers.count == NSAltHandlers.capacity) {
        NSAltHandlerTable grown;

        grown.capacity = NSAltHandlers.capacity + NSAltHandlerCapacityGrowth;
        grown.count = NSAltHandlers.count;
        grown.identifiers = (NSHandler2 **)
            NSZoneRealloc(0, NSAltHandlers.identifiers,
                          grown.capacity * sizeof(NSHandler2 *));
        NSAltHandlers = grown;
    }

    NSAltHandlers.identifiers[NSAltHandlers.count++] = handler;
}

void
_NSRemoveAltHandler2(NSHandler2 *handler)
{
    unsigned index;

    if (handler == 0)
        return;

    for (index = 0; index < NSAltHandlers.count; index++) {
        if (NSAltHandlers.identifiers[index] == handler) {
            unsigned remaining = NSAltHandlers.count - index - 1;

            if (remaining != 0)
                memmove(&NSAltHandlers.identifiers[index],
                        &NSAltHandlers.identifiers[index + 1],
                        remaining * sizeof(NSHandler2 *));
            NSAltHandlers.count--;
            return;
        }
    }
}

@implementation NSException

+ (NSException *)exceptionWithName:(NSString *)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo {
    // TODO: Implement this method
    return nil;
}

- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo {
    // TODO: Implement this method
    return nil;
}

- (NSString *)name {
    // TODO: Implement this method
    return nil;
}

- (NSString *)reason {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)userInfo {
    // TODO: Implement this method
    return nil;
}

- (void)raise {
    // TODO: Implement this method
}

+ (void)raise:(NSString *)name format:(NSString *)format, ... {
    // TODO: Implement this method
}

+ (void)raise:(NSString *)name format:(NSString *)format arguments:(va_list)argList {
    // TODO: Implement this method
}

@end

@implementation NSAssertionHandler

+ (NSAssertionHandler *)currentHandler {
    // TODO: Implement this method
    return nil;
}

- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,... {
    // TODO: Implement this method
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,... {
    // TODO: Implement this method
}

@end
