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

/*	Stage 2b has no NSString (stage 3).  A `@"..."` literal is laid out by
	this project's Objective-C frontend (src/cc-1/cc/objc/NXConstStr.h) as
	{ Class isa; char *c_string; unsigned int len; }, so these three read
	and build that shape -- enough for this file to carry an exception's
	name and reason and to compare them.  NSObjCRuntime.m has the same
	helpers, file-static there for the same reason they are file-static
	here: neither is part of any module's exported surface, and stage 3
	deletes both when real NSString arrives.  */

typedef struct {
    Class	isa;
    char	*c_string;
    unsigned	len;
} NSExceptionStringRecord;

/*	NSString.h declares this symbol `extern void *`; that header is this
	file's declaration of record for it, so the record builder below casts
	its address rather than re-declaring it with a struct type that would
	conflict.  */

static const char *
_NSExceptionStringBytes(NSString *string)
{
    if (string == nil)
        return NULL;
    return ((NSExceptionStringRecord *)string)->c_string;
}

static NSString *
_NSExceptionStringWithCString(const char *bytes)
{
    NSExceptionStringRecord *record;
    unsigned length;

    if (bytes == NULL)
        return nil;

    length = strlen(bytes);
    record = (NSExceptionStringRecord *)
        NSZoneMalloc(0, sizeof(NSExceptionStringRecord) + length + 1);
    record->isa = (Class)&_NSConstantStringClassReference;
    record->c_string = (char *)(record + 1);
    record->len = length;
    memcpy(record->c_string, bytes, length + 1);

    return (NSString *)record;
}

/*	Compares two of this stage's strings by their bytes.  Sending
	-isEqual: would dispatch to a class stage 2b does not implement;
	stage 3 replaces this with the real message.  */
static BOOL
NSExceptionStringsEqual(NSString *lhs, NSString *rhs)
{
    const char *left;
    const char *right;

    if (lhs == rhs)
        return YES;

    left = _NSExceptionStringBytes(lhs);
    right = _NSExceptionStringBytes(rhs);
    if (left == NULL || right == NULL)
        return NO;

    return strcmp(left, right) == 0;
}

/*	Builds an exception's reason by formatting `format` over `argList`.
	Shares NSLogv's specifier handling by going through it is not
	possible -- NSLogv writes rather than returns -- so this repeats the
	same walk into a buffer.  Both are provisional and both go away in
	stage 3; see divergences.md.  */

#define NSExceptionReasonMax 1024

static NSString *
_NSExceptionReasonFromFormat(NSString *format, va_list argList)
{
    const char *bytes;
    char reason[NSExceptionReasonMax];
    unsigned out;
    unsigned i;

    bytes = _NSExceptionStringBytes(format);
    if (bytes == NULL)
        return nil;

    out = 0;
    i = 0;
    while (bytes[i] != '\0' && out < NSExceptionReasonMax - 1) {
        if (bytes[i] != '%') {
            reason[out++] = bytes[i++];
            continue;
        }
        if (bytes[i + 1] == '%') {
            reason[out++] = '%';
            i += 2;
            continue;
        }
        if (bytes[i + 1] == '@') {
            id object = va_arg(argList, id);
            const char *text = _NSExceptionStringBytes((NSString *)object);

            if (text == NULL)
                text = "(null)";
            while (*text != '\0' && out < NSExceptionReasonMax - 1)
                reason[out++] = *text++;
            i += 2;
            continue;
        }
        {
            char specifier[16];
            char converted[NSExceptionReasonMax];
            unsigned length = 0;
            unsigned k = 0;

            specifier[length++] = bytes[i++];
            while (bytes[i] != '\0' && length < sizeof(specifier) - 1) {
                specifier[length++] = bytes[i];
                if (strchr("diouxXeEfgGcsp", bytes[i]) != NULL) {
                    i++;
                    break;
                }
                i++;
            }
            specifier[length] = '\0';

            converted[0] = '\0';
            if (strchr(specifier, 's') != NULL)
                sprintf(converted, specifier, va_arg(argList, char *));
            else if (strchr(specifier, 'f') != NULL ||
                     strchr(specifier, 'e') != NULL ||
                     strchr(specifier, 'g') != NULL)
                sprintf(converted, specifier, va_arg(argList, double));
            else
                sprintf(converted, specifier, va_arg(argList, int));

            while (converted[k] != '\0' && out < NSExceptionReasonMax - 1)
                reason[out++] = converted[k++];
        }
    }
    reason[out] = '\0';

    return _NSExceptionStringWithCString(reason);
}

/*	The exception names.  Each is a compiler-emitted NXConstantString
	literal: stage 2b has no NSString (stage 3), and a literal is exactly
	what a `NSString * const` global holds in the reference.  Callers
	compare these by pointer, which works because each name is one shared
	instance.

	The reference exports 23 such constants; the 14 here are the ones
	NSException.h declares.  The other 9 are declared in other stages'
	headers -- NSString.h, NSDecimalNumber.h, NSFileHandle.h,
	NSArchiver.h, NSConnection.h -- and belong to those stages under the
	project's attribute-by-declaring-header rule.  Listed in
	divergences.md so none is lost.  */

NSString * const NSGenericException = @"NSGenericException";
NSString * const NSRangeException = @"NSRangeException";
NSString * const NSInvalidArgumentException = @"NSInvalidArgumentException";
NSString * const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
NSString * const NSMallocException = @"NSMallocException";
NSString * const NSObjectInaccessibleException = @"NSObjectInaccessibleException";
NSString * const NSObjectNotAvailableException = @"NSObjectNotAvailableException";
NSString * const NSDestinationInvalidException = @"NSDestinationInvalidException";
NSString * const NSPortTimeoutException = @"NSPortTimeoutException";
NSString * const NSInvalidSendPortException = @"NSInvalidSendPortException";
NSString * const NSInvalidReceivePortException = @"NSInvalidReceivePortException";
NSString * const NSPortSendException = @"NSPortSendException";
NSString * const NSPortReceiveException = @"NSPortReceiveException";
NSString * const NSOldStyleException = @"NSOldStyleException";

/*	Set by a process that would rather stop in the debugger than exit
	when an exception goes uncaught.  Exported by the reference in
	__DATA,__data; read below.  */
BOOL NSHangOnUncaughtException = NO;

static NSUncaughtExceptionHandler *NSUncaughtHandler = 0;
static BOOL NSExceptionLogging = NO;

NSUncaughtExceptionHandler *
NSGetUncaughtExceptionHandler(void)
{
    return NSUncaughtHandler;
}

void
NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *handler)
{
    NSUncaughtHandler = handler;
}

/*	Transfers `exception` to the innermost active handler.  The handler is
	popped here, not by NS_HANDLER: the macro only calls
	_NSRemoveHandler2 on the path where the body completed normally, so
	the raise path has to unlink it before transferring or the dead frame
	stays on the chain.

	_NSSETJMP resolves to _setjmp on this platform (NSException.h), so the
	transfer must be _longjmp -- pairing it with longjmp is undefined.
	See the hosting probe note for stage 2b.

	With no handler active the exception is uncaught: the installed
	handler gets it if there is one, and otherwise the process reports and
	stops, hanging instead of exiting when NSHangOnUncaughtException asks
	it to.  */
void
_NSRaiseError(NSException *exception)
{
    NSHandler2 *handler;

    if (exception == nil)
        return;

    handler = NSExceptionHandlerStack;

    if (handler == 0) {
        if (NSUncaughtHandler != 0) {
            (*NSUncaughtHandler)(exception);
            /*  A handler that returns has declined to stop the process;
                fall through to the default treatment below.  */
        }
        NSLog(@"*** Uncaught exception: %@ -- %@",
              [exception name], [exception reason]);
        if (NSHangOnUncaughtException) {
            for (;;)
                ;
        }
        abort();
    }

    NSExceptionHandlerStack = (NSHandler2 *)handler->_others;
    handler->_exception = exception;
    _longjmp(handler->_state, 1);
}

@implementation NSException

+ (NSException *)exceptionWithName:(NSString *)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo
{
    return [[[self allocWithZone:NULL] initWithName:name
                                             reason:reason
                                           userInfo:userInfo] autorelease];
}

/*	The name, reason and userInfo ivars are assigned, not retained.
	Stage 2b's strings are NXConstantString-shaped records whose class
	reference is still the zeroed test placeholder (stage 3 replaces it
	with real NSString), so a retain sent to one would dispatch through
	a class with no method list.  The records themselves are either
	compiler literals or NSZoneMalloc'd and never freed, so nothing is
	leaked that would not outlive the process anyway; the exception
	object itself takes the normal retain/autorelease path.  Stage 3
	switches these to retain/release.  Recorded in divergences.md.  */
- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo
{
    self = [super init];
    name = aName;
    reason = aReason;
    userInfo = aUserInfo;
    reserved = 0;
    return self;
}

- (void)dealloc
{
    [super dealloc];
}

- (NSString *)name      { return name; }
- (NSString *)reason    { return reason; }
- (NSDictionary *)userInfo { return userInfo; }

- (void)raise
{
    _NSRaiseError(self);
}

/*	Compares by name and reason rather than by identity.  Both are this
	stage's NXConstantString-shaped records, which implement no
	-isEqual:, so the comparison goes through NSExceptionStringsEqual
	above.  */
- (BOOL)isEqual:(id)object
{
    NSException *other;

    if (self == object)
        return YES;
    if (object == nil || ((NSException *)object)->isa != isa)
        return NO;

    other = (NSException *)object;
    return NSExceptionStringsEqual(name, other->name) &&
           NSExceptionStringsEqual(reason, other->reason);
}

- (NSString *)description
{
    return reason;
}

/*	Turns logging of every raise on or off.  No header declares this; the
	reference carries it in NSException's class method list and keeps the
	flag in __DATA,__data.  Claimed by name in symbols.json.  */
+ (void)_enableLogging:(BOOL)flag
{
    NSExceptionLogging = flag;
}

@end

@implementation NSException (NSExceptionRaisingConveniences)

+ (void)raise:(NSString *)name format:(NSString *)format, ...
{
    va_list arguments;

    va_start(arguments, format);
    [self raise:name format:format arguments:arguments];
    va_end(arguments);
}

+ (void)raise:(NSString *)name format:(NSString *)format arguments:(va_list)argList
{
    _NSRaiseError([self exceptionWithName:name
                                   reason:_NSExceptionReasonFromFormat(format, argList)
                                 userInfo:nil]);
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
