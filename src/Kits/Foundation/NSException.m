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
