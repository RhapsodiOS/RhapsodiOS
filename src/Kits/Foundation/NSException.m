/*	NSException.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSException.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSCoder.h>
#import <objc/objc-class.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern NSString *NSStringFromStack(NSString *format, NSString *separator);
extern NSString *_NSFullMethodName(id object, char *selectorName);

/*	The target keeps a growable handler array in NSThread's exception slot
	(at byte offset 20).  _others is the per-handler alternate-cleanup table,
	not a chain link; _thread points back to the owning thread. */
typedef struct {
    unsigned generation;
    unsigned capacity;
    unsigned count;
    NSHandler2 *handlers[1];
} NSExceptionHandlerTable;

typedef struct {
    unsigned identifier;
    void (*function)(NSException *, void *);
    void *context;
} NSExceptionAltHandler;

typedef struct {
    unsigned capacity;
    unsigned count;
    NSExceptionAltHandler handlers[1];
} NSExceptionAltHandlerTable;

static BOOL NSExceptionLogging = NO;

static NSExceptionHandlerTable **NSExceptionHandlerTableSlot(NSThread *thread)
{
    return (NSExceptionHandlerTable **)((char *)thread + 20);
}

static NSExceptionHandlerTable *NSExceptionHandlersForThread(NSThread *thread)
{
    return *NSExceptionHandlerTableSlot(thread);
}

static void NSExceptionFreeAltHandlers(NSHandler2 *handler)
{
    if (handler->_others != 0) {
        NSZoneFree(NULL, handler->_others);
        handler->_others = 0;
    }
}

static void NSExceptionRunAltHandlers(NSHandler2 *handler,
                                      NSException *exception,
                                      BOOL whileRaising)
{
    NSExceptionAltHandlerTable *table =
        (NSExceptionAltHandlerTable *)handler->_others;
    unsigned index;

    if (table == 0)
        return;
    for (index = 0; index < table->count; index++) {
        NSExceptionAltHandler *entry = &table->handlers[index];

        if (NSExceptionLogging) {
            if (whileRaising)
                NSLog(@"Invoking alt handler (%x, %x) while raising exception %@ with handler %x\n",
                      entry->function, entry->context, exception, handler);
            else
                NSLog(@"Invoking alt handler (%x, %x) while removing non-top handler %x\n",
                      entry->function, entry->context, handler);
        }
        (*entry->function)(exception, entry->context);
    }
    NSZoneFree(NULL, table);
    handler->_others = 0;
}

/*	The binary retains these pre-NSHandler2 entry points as direct forwarding
    wrappers.  NSHandler is opaque in the public header, so callers can only
    pass the record pointer through to the NSHandler2 implementation.  */
void
_NSAddHandler(NSHandler *handler)
{
    _NSAddHandler2((NSHandler2 *)handler);
}

void
_NSRemoveHandler(NSHandler *handler)
{
    _NSRemoveHandler2((NSHandler2 *)handler);
}

/*	NS_DURING's expansion calls this with the address of an automatic it
    just declared; the per-thread table stores that record's address. */
void
_NSAddHandler2(NSHandler2 *handler)
{
    NSThread *thread;
    NSExceptionHandlerTable **slot;
    NSExceptionHandlerTable *table;
    unsigned capacity;
    unsigned index;

    thread = _NSCurrentThread();
    slot = NSExceptionHandlerTableSlot(thread);
    table = *slot;
    if (table == 0) {
        capacity = 32;
        table = (NSExceptionHandlerTable *)NSZoneMalloc(NULL,
        12 + capacity * sizeof(NSHandler2 *));
        table->generation = 0;
        table->capacity = capacity;
        table->count = 0;
        *slot = table;
        if (NSExceptionLogging)
        NSLog(@"Creating exception handler stack %x for thread %x\n",
              table, thread);
    } else if (table->count >= table->capacity) {
        capacity = table->capacity + 16;
        table = (NSExceptionHandlerTable *)NSZoneRealloc(NULL, table,
        12 + capacity * sizeof(NSHandler2 *));
        table->capacity = capacity;
        *slot = table;
        if (NSExceptionLogging)
        NSLog(@"Grew exception handler stack %x for thread %x to %d slots\n",
              table, thread, capacity);
    }

    handler->_exception = nil;
    handler->_others = 0;
    handler->_thread = thread;
    handler->_reserved1 = 0;
    index = table->count++;
    table->handlers[index] = handler;
    if (NSExceptionLogging)
        NSLog(@"Added top exception handler %x for stack %x for thread %x\n",
          handler, table, thread);
}

/*	A return out of a nested NS_DURING unwinds every handler above the
    requested record, running its alternate cleanup callbacks with nil. */
void
_NSRemoveHandler2(NSHandler2 *handler)
{
    NSThread *thread;
    NSExceptionHandlerTable *table;
    int index;
    unsigned cursor;

    thread = (NSThread *)handler->_thread;
    table = thread != nil ? NSExceptionHandlersForThread(thread) : 0;
    if (table == 0 || table->count == 0) {
        NSLog(@"*** Attempt to remove unrecognized exception handler 0x%x\n",
          handler);
        return;
    }

    index = (int)table->count - 1;
    if (table->handlers[index] == handler) {
        NSExceptionFreeAltHandlers(handler);
        table->handlers[index] = 0;
        table->count--;
        if (NSExceptionLogging)
        NSLog(@"Removed top exception handler %x for stack %x for thread %x\n",
              handler, table, thread);
        return;
    }

    if (NSExceptionLogging)
        NSLog(@"Removal of handler %x requested for stack %x for thread %x -- not on top\n",
          handler, table, thread);
    for (index = (int)table->count - 1; index >= 0; index--) {
        if (table->handlers[index] == handler)
        break;
    }
    if (index < 0) {
        NSLog(@"*** Attempt to remove unrecognized exception handler 0x%x\n",
          handler);
        return;
    }

    NSLog(@"*** Exception handlers were not properly removed. Some code has jumped or returned out of an NS_DURING...NS_HANDLER region without using the NS_VOIDRETURN or NS_VALUERETURN macros.\n");
    for (cursor = table->count; cursor > (unsigned)index + 1; cursor--) {
        NSHandler2 *inner = table->handlers[cursor - 1];

        NSExceptionRunAltHandlers(inner, nil, NO);
        table->handlers[cursor - 1] = 0;
    }
    NSExceptionFreeAltHandlers(handler);
    table->count = (unsigned)index;
    table->handlers[index] = 0;
    if (NSExceptionLogging)
        NSLog(@"Removed non-top exception handler %x for stack %x for thread %x\n",
          handler, table, thread);
}

/*	Read by NS_HANDLER's expansion after the transfer, which is why the
    exception is stored on the handler record rather than in a global a
    nested raise could overwrite before this is read.  */
NSException *
_NSExceptionObjectFromHandler2(NSHandler2 *handler)
{
    return handler->_exception;
}

/*	The pre-NSHandler2 entry point the reference still exports.  The older
    NSHandler is opaque in the shipped header (`typedef struct _NSHandler
    NSHandler;` with no definition), so nothing in this tree can construct
    one.  */
NSException *
_NSExceptionObjectFromHandler(NSHandler2 *handler)
{
    return _NSExceptionObjectFromHandler2(handler);
}

/*	How many handlers are active on the current thread. */
unsigned
_NSExceptionHandlerCount(void)
{
    NSExceptionHandlerTable *table =
        NSExceptionHandlersForThread(_NSCurrentThread());

    return table != 0 ? table->count : 0;
}

/*	Thread teardown passes the address of its exception-handler slot. The
    target frees the table and any alternate-action tables, then clears it. */
void
_NSClearExceptionStack(void **slot)
{
    NSExceptionHandlerTable *table = (NSExceptionHandlerTable *)*slot;
    NSThread *thread;
    unsigned index;

    if (table == 0)
        return;
    if (NSExceptionLogging) {
        thread = _NSCurrentThread();
        NSLog(@"Clearing exception handler stack %x for thread %x\n",
          table, thread);
    }
    for (index = 0; index < table->count; index++) {
        NSHandler2 *handler = table->handlers[index];

        if (handler->_others != 0)
            NSZoneFree(NULL, handler->_others);
    }
    NSZoneFree(NULL, table);
    *slot = 0;
}

/*	Alternate handlers belong to the innermost active handler. Their
    identifiers are per-handler generations; callbacks run with the raised
    exception, or with nil when non-top removal unwinds skipped frames. */
unsigned
_NSAddAltHandler2(void (*function)(NSException *, void *), void *context)
{
    NSThread *thread = _NSCurrentThread();
    NSExceptionHandlerTable *handlers = NSExceptionHandlersForThread(thread);
    NSExceptionAltHandlerTable *table;
    NSHandler2 *handler;
    NSExceptionAltHandler *entry;
    unsigned capacity;

    if (handlers == 0 || handlers->count == 0) {
        if (NSExceptionLogging)
        NSLog(@"*** No current exception handler for alt proc 0x%x -- ignoring\n",
              function);
        return 0;
    }
    handler = handlers->handlers[handlers->count - 1];
    table = (NSExceptionAltHandlerTable *)handler->_others;
    if (table == 0) {
        capacity = 12;
        table = (NSExceptionAltHandlerTable *)NSZoneMalloc(NULL,
        8 + capacity * sizeof(NSExceptionAltHandler));
        table->capacity = capacity;
        table->count = 0;
        handler->_others = table;
    } else if (table->count >= table->capacity) {
        capacity = table->capacity + 6;
        table = (NSExceptionAltHandlerTable *)NSZoneRealloc(NULL, table,
        8 + capacity * sizeof(NSExceptionAltHandler));
        table->capacity = capacity;
        handler->_others = table;
    }
    handlers->generation++;
    if (handlers->generation == 0)
        handlers->generation = 1;
    entry = &table->handlers[table->count++];
    entry->identifier = handlers->generation;
    entry->function = function;
    entry->context = context;
    if (NSExceptionLogging)
        NSLog(@"Adding alt handler %d (proc %x) to handler %x for thread %x\n",
          entry->identifier, function, handler, thread);
    return entry->identifier;
}

void
_NSRemoveAltHandler2(unsigned identifier)
{
    NSThread *thread = _NSCurrentThread();
    NSExceptionHandlerTable *handlers = NSExceptionHandlersForThread(thread);
    unsigned handlerIndex;

    if (handlers != 0) {
        for (handlerIndex = 0; handlerIndex < handlers->count; handlerIndex++) {
        NSHandler2 *handler = handlers->handlers[handlerIndex];
        NSExceptionAltHandlerTable *table =
            (NSExceptionAltHandlerTable *)handler->_others;
        unsigned index;

        if (table == 0)
            continue;
        for (index = 0; index < table->count; index++) {
            if (table->handlers[index].identifier == identifier) {
            unsigned remaining = table->count - index - 1;

            if (remaining != 0)
                memmove(&table->handlers[index],
                    &table->handlers[index + 1],
                    remaining * sizeof(NSExceptionAltHandler));
            table->count--;
            if (NSExceptionLogging)
                NSLog(@"Removing alt handler %d to handler %x for thread %x\n",
                  identifier, handler, thread);
            return;
            }
        }
        }
    }
    if (NSExceptionLogging)
        NSLog(@"Alt handler %d for thread %x not found\n", identifier, thread);
}

/*	The exception names are compiler-emitted NXConstantString literals,
	matching the reference's shared `NSString * const` objects.  Callers
	compare these canonical names by pointer.

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

NSUncaughtExceptionHandler *
NSGetUncaughtExceptionHandler(void)
{
    return NSUncaughtHandler;
}

void
NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *handler)
{
    if (NSExceptionLogging)
        NSLog(@"Changing uncaught exception handler from %x to %x\n",
              NSUncaughtHandler, handler);
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
    NSThread *thread;
    NSExceptionHandlerTable *table;
    NSHandler2 *handler;
    sigset_t signalMask;

    thread = _NSCurrentThread();
    table = NSExceptionHandlersForThread(thread);

    if (table == 0 || table->count == 0) {
        NSString *name;
        NSString *reason;
        NSString *stack;

        if (NSExceptionLogging)
        NSLog(@"Raising exception %@ without top level handler\n", exception);
        if (NSUncaughtHandler != 0) {
            (*NSUncaughtHandler)(exception);
            /*  A handler that returns has declined to stop the process;
                fall through to the default treatment below.  */
        }
#if defined(__ppc__) || defined(__POWERPC__)
        name = [exception name];
        reason = [exception reason];
        stack = NSStringFromStack(@"0x%x", @" ");
#else
        stack = NSStringFromStack(@"0x%x", @" ");
        reason = [exception reason];
        name = [exception name];
#endif
        NSLog(@"*** Uncaught exception: <%@> %@\nstack: %@\n",
              name, reason, stack);
        if (NSHangOnUncaughtException) {
        memset(&signalMask, 0, sizeof(signalMask));
        sigsuspend(&signalMask);
        }
        exit(-1);
    }

    table->count--;
    handler = table->handlers[table->count];
    table->handlers[table->count] = 0;
    NSExceptionRunAltHandlers(handler, exception, YES);
    handler->_exception = exception;
    if (NSExceptionLogging)
        NSLog(@"Raising exception %@ with handler\n", exception);
    _longjmp(handler->_state, 1);
}

#if defined(__ppc__) || defined(__POWERPC__)
typedef void (*NSExceptionRaiserFunction)(NSException *exception);
static NSExceptionRaiserFunction __NSExceptionRaiser = _NSRaiseError;

NSExceptionRaiserFunction
_NSExceptionRaiser(void)
{
    return __NSExceptionRaiser;
}

NSExceptionRaiserFunction
_NSSetExceptionRaiser(NSExceptionRaiserFunction raiser)
{
    __NSExceptionRaiser = raiser != 0 ? raiser : _NSRaiseError;
    return raiser;
}
#endif

/*	The target's method proem begins with "*** -[" or "*** +[" and is
	returned as an NSString for the framework's diagnostic format strings. */
id
_NSMethodExceptionProem(id object, SEL aSelector)
{
    char buffer[1024];
    const char *className;
    const char *selectorName;
    BOOL isClassMethod;

    isClassMethod = object == [object class];
    className = ((Class)object)->isa->name;
    selectorName = (aSelector == NULL) ? "" : sel_getName(aSelector);

    sprintf(buffer, "*** %c[%s %s]",
            isClassMethod ? '+' : '-',
            className,
            selectorName);

    return [NSString stringWithCString:buffer length:(unsigned)strlen(buffer)];
}

@implementation NSException

+ (NSException *)exceptionWithName:(NSString *)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo
{
    return [[[self allocWithZone:NULL] initWithName:name
                                             reason:reason
                                           userInfo:userInfo] autorelease];
}

/*	The target copies its name and reason and retains userInfo. */
- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo
{
    name = [aName copyWithZone:NULL];
    reason = [aReason copyWithZone:NULL];
    userInfo = [aUserInfo retain];
    return self;
}

- (void)dealloc
{
    [name release];
    [reason release];
    [userInfo release];
    [super dealloc];
}

- (id)init
{
    [super dealloc];
    return nil;
}

- (NSString *)name      { return name; }
- (NSString *)reason    { return reason; }
- (NSDictionary *)userInfo { return userInfo; }

- (void)raise
{
#if defined(__ppc__) || defined(__POWERPC__)
    (*__NSExceptionRaiser)(self);
#else
    _NSRaiseError(self);
#endif
}

/*	The reference compares exception names after requiring an exact class
	match.  The reason and userInfo do not participate. */
- (BOOL)isEqual:(id)object
{
    if (object == nil || ((NSException *)object)->isa != isa)
        return NO;

    return [name isEqual:((NSException *)object)->name];
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

/*	The raising conveniences.  NSException.h declares them in an
	NSExceptionRaisingConveniences category, but Gate 1's abi-check reads
	the reference's __OBJC metadata, and this image carries them in the
	main class's method list with no such category -- so they are
	implemented here, inside the main @implementation.  Recorded in
	divergences.md.  */

+ (void)raise:(NSString *)name format:(NSString *)format, ...
{
    va_list arguments;

    va_start(arguments, format);
    [self raise:name format:format arguments:arguments];
    va_end(arguments);
}

+ (void)raise:(NSString *)name format:(NSString *)format arguments:(va_list)argList
{
    NSString *reason = [[[NSString allocWithZone:NULL]
        initWithFormat:format arguments:argList] autorelease];

    [[self exceptionWithName:name reason:reason userInfo:nil] raise];
}

/*	NSCoding and NSCopying.  Written against the declared APIs; NOT
	exercised by any test in this stage, because NSCoder is stage 2c,
	NSPortCoder is stage 8, and copying userInfo needs NSDictionary from
	stage 4.  Listed in divergences.md's untested table with the stage
	that unblocks each.  */

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:name];
    [aCoder encodeObject:reason];
    [aCoder encodeObject:userInfo];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    id decodedName = [aDecoder decodeObject];
    id decodedReason = [aDecoder decodeObject];
    id decodedUserInfo = [aDecoder decodeObject];

    return [self initWithName:decodedName reason:decodedReason
                     userInfo:decodedUserInfo];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];
}

/*	No header in this tree declares this selector (NSObject.h declares
	-replacementObjectForCoder:; the PortCoder form is undeclared here),
	but Gate 1 requires it with its exact type encoding: the reference
	carries it in NSException's method list.  A self return is the
	documented default for objects with no special cross-thread
	behaviour.  Claimed by name in symbols.json.  */
- (id)replacementObjectForPortCoder:(NSCoder *)aCoder
{
    return self;
}

@end

@implementation NSAssertionHandler

/*	The targets keep one handler per thread in threadDictionary under
	the NSAssertionHandler key. The instance itself carries no additional
	state; handler identity follows the owning thread. */
+ (NSAssertionHandler *)currentHandler
{
    static NSString *key = @"NSAssertionHandler";
    NSThread *thread = _NSCurrentThread();
    NSMutableDictionary *threadDictionary = [thread threadDictionary];
    NSAssertionHandler *handler = [threadDictionary objectForKey:key];

    if (handler == nil) {
        handler = [[NSAssertionHandler allocWithZone:NULL] init];
        thread = _NSCurrentThread();
        threadDictionary = [thread threadDictionary];
        [threadDictionary setObject:handler forKey:key];
        [handler release];
    }
    return handler;
}

- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format, ...
{
    va_list arguments;

    va_start(arguments, format);
    NSLog(@"*** Assertion failure in %@, %@:%d",
          _NSFullMethodName(object, (char *)selector), fileName, line);
    [NSException raise:NSInternalInconsistencyException
                format:format arguments:arguments];
    va_end(arguments);
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format, ...
{
    va_list arguments;

    va_start(arguments, format);
    NSLog(@"*** Assertion failure in %@(), %@:%d", functionName, fileName, line);
    [NSException raise:NSInternalInconsistencyException
                format:format arguments:arguments];
    va_end(arguments);
}

@end
