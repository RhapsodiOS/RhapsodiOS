/*	NSPort.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPort.h>
#import <Foundation/NSPortMessage.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSException.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSString.h>

#include <mach/mach.h>
#include <mach/mach_init.h>
#include <mach/mach_error.h>
#include <mach/notify.h>
#include <string.h>

extern kern_return_t port_status(task_t task, port_t port,
                                 port_set_name_t *portSet,
                                 int *numMessages, int *backlog,
                                 boolean_t *amOwner,
                                 boolean_t *isReceiver);
extern id _NSMethodExceptionProem(id object, SEL selector);

@interface NSMachPort : NSPort {
@public
    unsigned int _retainState;
    unsigned int _machPort;
    id _delegate;
}
+ (id)allocWithZone:(NSZone *)zone;
+ (id)newWithMachPort:(unsigned int)machPort;
+ (NSPort *)portWithMachPort:(unsigned int)machPort;
+ (void)resetAllPorts;
+ (void)_enableLogging:(BOOL)flag;
+ (NSArray *)allPorts;
+ (void)handleMachMessage:(void *)message;
+ (void)statusForMachPort:(int)machPort;
- (id)init;
- (id)initWithMachPort:(unsigned int)machPort;
- (unsigned int)machPort;
- (id)delegate;
- (void)setDelegate:(id)delegate;
- (BOOL)isValid;
- (void)invalidate;
- (id)retain;
- (oneway void)release;
- (unsigned int)retainCount;
- (void)removeConnection:(NSConnection *)connection
             fromRunLoop:(NSRunLoop *)runLoop
                  forMode:(NSString *)mode;
- (unsigned int)hash;
- (BOOL)isEqual:(id)object;
- (NSString *)description;
@end
static NSHashTable *NSPortTable;
static NSMachPort *NSPortCache[4];
static int NSMachPortLoggingEnabled;
extern NSLock *_NSPortTableLock;
extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);

@interface NSConcretePortCoder : NSPortCoder
@end

static unsigned NSMachPortHash(NSHashTable *table, const void *value) {
    return ((const NSMachPort *)value)->_machPort;
}

static BOOL NSMachPortEqual(NSHashTable *table, const void *left, const void *right) {
    return ((const NSMachPort *)left)->_machPort
        == ((const NSMachPort *)right)->_machPort;
}

static const NSHashTableCallBacks NSMachPortTableCallbacks = {
    NSMachPortHash, NSMachPortEqual, NULL, NULL, NULL
};

#if defined(__ppc__) || defined(__POWERPC__)
#define NSMachPortValidMask 0x80000000u
#define NSMachPortReleasingMask 0x40000000u
static unsigned NSMachPortReferenceCount(unsigned state) {
    return state & 0x00ffffffu;
}

static unsigned NSMachPortSetReferenceCount(unsigned state, unsigned count) {
    return (state & 0xff000000u) | (count & 0x00ffffffu);
}
#else
#define NSMachPortValidMask 0x00000001u
#define NSMachPortReleasingMask 0x00000002u
static unsigned NSMachPortReferenceCount(unsigned state) {
    return (state & 0xffffff00u) >> 8;
}

static unsigned NSMachPortSetReferenceCount(unsigned state, unsigned count) {
    return (state & 0x000000ffu) | ((count & 0x00ffffffu) << 8);
}
#endif

static unsigned NSMachPortIncrementReferenceCount(unsigned state) {
    return NSMachPortSetReferenceCount(state,
        NSMachPortReferenceCount(state) + 1);
}

NSString * const NSPortDidBecomeInvalidNotification = @"NSPortDidBecomeInvalidNotification";

@implementation NSPort

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSPort class])
        return [NSMachPort allocWithZone:zone];
    return NSAllocateObject(self, 0, NULL);
}

+ (NSPort *)port {
    NSPort *port = [[self allocWithZone:NULL] init];
    return [port autorelease];
}

+ (NSPort *)portWithMachPort:(int)machPort {
    NSPort *port = [[self allocWithZone:NULL] initWithMachPort:machPort];
    return [port autorelease];
}

+ (NSPort *)newWithMachPort:(int)machPort {
    return [[self allocWithZone:NULL] initWithMachPort:machPort];
}

- (id)initWithMachPort:(int)machPort {
    return NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
}

- (void)invalidate {
    NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
}

- (BOOL)isValid {
    NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
    return NO;
}

- (int)machPort {
    NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
    return 0;
}

- (void)setDelegate:(id)anId {
    NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
}

- (id)delegate {
    return NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
}

- (unsigned)reservedSpaceLength {
    return 0;
}

- (BOOL) sendBeforeDate:(NSDate *)limitDate components:(NSMutableArray *)components from:(NSPort *) receivePort reserved:(unsigned)headerSpaceReserved {
    NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
    return NO;
}

- (void)addConnection:(NSConnection *)conn toRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode {
    NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
}

- (void)removeConnection:(NSConnection *)conn fromRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode {
    NSRequestConcreteImplementation(self, _cmd, [NSPort class]);
}

- (id)classForCoder {
    return [NSPort class];
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [super retain];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodePortObject:self];
}

- (id)initWithCoder:(NSCoder *)coder {
    NSPort *port;

    [self dealloc];
    port = [coder decodePortObject];
    return [port retain];
}

- (id)replacementObjectForCoder:(NSCoder *)coder {
    (void)coder;
    return nil;
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    (void)coder;
    return self;
}

@end

@interface NSPortMessage (NSPortMessageSpeedups)
+ (BOOL)sendBeforeTime:(NSTimeInterval)time streamData:(id)streamData
            components:(NSArray *)components to:(NSPort *)sendPort
                  from:(NSPort *)receivePort msgid:(unsigned)msgid
              reserved:(unsigned)reserved;
@end

@implementation NSMachPort

+ (void)_enableLogging:(BOOL)flag {
    NSMachPortLoggingEnabled = flag;
}

+ (NSArray *)allPorts {
    NSArray *ports;

    if (_NSPortTableLock != nil)
        [_NSPortTableLock lock];
    ports = NSPortTable != NULL ? NSAllHashTableObjects(NSPortTable)
                                : [NSArray array];
    if (_NSPortTableLock != nil)
        [_NSPortTableLock unlock];
    return ports;
}

+ (void)handleMachMessage:(void *)message {
    mach_msg_header_t *header = (mach_msg_header_t *)message;

    if (header->msgh_id == MACH_NOTIFY_PORT_DELETED) {
        mach_port_deleted_notification_t *notification =
            (mach_port_deleted_notification_t *)message;
        NSPort *port = [NSPort portWithMachPort:notification->not_port];

        [port invalidate];
    } else {
        id proem = _NSMethodExceptionProem(self, _cmd);

        [NSException raise:NSInternalInconsistencyException
                    format:@"%@: bad notify msg %d", proem, header->msgh_id];
    }
}

+ (void)statusForMachPort:(int)machPort {
    port_set_name_t portSet;
    int numMessages, backlog;
    boolean_t amOwner, isReceiver;
    kern_return_t result;

    result = port_status(task_self_, (port_t)machPort, &portSet,
                         &numMessages, &backlog, &amOwner, &isReceiver);
    if (result != KERN_SUCCESS) {
        NSLog(@"port_status returned %d (%s)", result,
              mach_error_string(result));
    } else {
        NSLog(@"port %d inSet=%d num_msgs=%d backlog=%d amOwner=%d isRecvr=%d\n",
              machPort, portSet, numMessages, backlog, amOwner, isReceiver);
    }
}

+ (void)resetAllPorts {
    if (_NSPortTableLock != nil)
        [_NSPortTableLock lock];
    if (NSPortTable != NULL) {
        unsigned pool = NSPushAutoreleasePool();
        NSArray *ports = NSAllHashTableObjects(NSPortTable);

        NSFreeHashTable(NSPortTable);
        NSPortTable = NULL;
        if (_NSPortTableLock != nil)
            [_NSPortTableLock unlock];
        [ports makeObjectsPerformSelector:@selector(invalidate)];
        NSPopAutoreleasePool(pool);
    } else if (_NSPortTableLock != nil) {
        [_NSPortTableLock unlock];
    }
}

+ (id)allocWithZone:(NSZone *)zone {
    NSMachPort *port = nil;
    unsigned index;

    (void)zone;
    if (_NSPortTableLock != nil)
        [_NSPortTableLock lock];
    for (index = 0; index < 4; index++) {
        if (NSPortCache[index] != nil) {
            port = NSPortCache[index];
            NSPortCache[index] = nil;
            break;
        }
    }
    if (_NSPortTableLock != nil)
        [_NSPortTableLock unlock];
    if (port == nil)
        port = (NSMachPort *)NSAllocateObject(self, 0, NULL);
    else if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectAllocatedEvent, port, 0);
    return port;
}

+ (id)newWithMachPort:(unsigned int)machPort {
    NSMachPort *port = nil;

    if (machPort == 0)
        return nil;
    if (_NSPortTableLock != nil)
        [_NSPortTableLock lock];
    if (NSPortTable != NULL) {
        unsigned int key[3];
        key[2] = machPort;
        port = (NSMachPort *)NSHashGet(NSPortTable, key);
    }
    if (port != nil) {
        port->_retainState = NSMachPortIncrementReferenceCount(
            port->_retainState);
        if (_NSPortTableLock != nil)
            [_NSPortTableLock unlock];
        if (NSKeepAllocationStatistics)
            NSRecordAllocationEvent(NSObjectExtraRefIncrementedEvent, port);
        return port;
    }
    if (_NSPortTableLock != nil)
        [_NSPortTableLock unlock];
    return [[self allocWithZone:NULL] initWithMachPort:machPort];
}

+ (NSPort *)portWithMachPort:(unsigned int)machPort {
    NSMachPort *port;

    if (machPort == 0)
        return nil;
    port = [[self allocWithZone:NULL] initWithMachPort:machPort];
    return [port autorelease];
}

- (id)init {
    mach_port_t port;

    if (port_allocate(task_self_, &port) != KERN_SUCCESS)
        [NSException raise:NSInternalInconsistencyException
                    format:@"couldn't allocate a new mach port (kernel)"];
    port_set_backlog(task_self_, _machPort, 16);
    return [self initWithMachPort:port];
}

- (id)initWithMachPort:(unsigned int)machPort {
    NSMachPort *existing = nil;
    unsigned int key[3];

    if (machPort == 0) {
        [self dealloc];
        return nil;
    }
    key[2] = machPort;
    if (_NSPortTableLock != nil)
        [_NSPortTableLock lock];
    if (NSPortTable != NULL)
        existing = (NSMachPort *)NSHashGet(NSPortTable, key);
    if (existing != nil) {
        existing->_retainState = NSMachPortIncrementReferenceCount(
            existing->_retainState);
        if (_NSPortTableLock != nil)
            [_NSPortTableLock unlock];
        if (NSKeepAllocationStatistics)
            NSRecordAllocationEvent(NSObjectExtraRefIncrementedEvent, existing);
        [self dealloc];
        return existing;
    }

    _machPort = machPort;
    _retainState = NSMachPortSetReferenceCount(_retainState, 0)
        | NSMachPortValidMask;
    _retainState &= ~NSMachPortReleasingMask;
    if (NSPortTable == NULL)
        NSPortTable = NSCreateHashTableWithZone(NSMachPortTableCallbacks, 20, NULL);
    NSHashInsertKnownAbsent(NSPortTable, self);
    if (_NSPortTableLock != nil)
        [_NSPortTableLock unlock];
    return self;
}

- (unsigned int)machPort {
    return _machPort;
}

- (NSString *)description {
    NSString *description;
    const char *validity;

#if defined(__ppc__) || defined(__POWERPC__)
    description = [NSString allocWithZone:NULL];
    validity = (_retainState & NSMachPortValidMask) ? "valid" : "invalid";
#else
    validity = (_retainState & NSMachPortValidMask) ? "valid" : "invalid";
    description = [NSString allocWithZone:NULL];
#endif

    description = [description initWithFormat:@"<MachPort %d %s>",
        _machPort, validity];
    return [description autorelease];
}

- (id)delegate {
    return _delegate;
}

- (void)setDelegate:(id)delegate {
    _delegate = delegate;
}

- (BOOL)isValid {
    return (_retainState & NSMachPortValidMask) != 0;
}

- (void)invalidate {
    if ((_retainState & NSMachPortValidMask) != 0) {
        _retainState &= ~NSMachPortValidMask;
        if (_machPort != 0) {
            port_deallocate(task_self_, _machPort);
            if (NSMachPortLoggingEnabled != 0)
                NSLog(@"deallocating mach port %d\n", _machPort);
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:NSPortDidBecomeInvalidNotification
                          object:self
                        userInfo:nil];
    }
}

- (id)retain {
    if (_NSPortTableLock != nil)
        [_NSPortTableLock lock];
    _retainState = NSMachPortIncrementReferenceCount(_retainState);
    if (_NSPortTableLock != nil)
        [_NSPortTableLock unlock];
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectExtraRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    unsigned referenceCount;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectExtraRefDecrementedEvent, self);
    if (_NSPortTableLock != nil)
        [_NSPortTableLock lock];
    referenceCount = NSMachPortReferenceCount(_retainState);
    if (referenceCount != 0) {
        _retainState = NSMachPortSetReferenceCount(_retainState,
            referenceCount - 1);
        if (_NSPortTableLock != nil)
            [_NSPortTableLock unlock];
        return;
    }
    if ((_retainState & NSMachPortReleasingMask) != 0) {
        if (_NSPortTableLock != nil)
            [_NSPortTableLock unlock];
        [self dealloc];
        return;
    }
    _retainState |= NSMachPortReleasingMask;
    if (NSPortTable != NULL)
        NSHashRemove(NSPortTable, self);
    if (_NSPortTableLock != nil)
        [_NSPortTableLock unlock];
    [self invalidate];
    if (NSMachPortReferenceCount(_retainState) == 0)
        [self dealloc];
}

- (unsigned int)retainCount {
    return NSMachPortReferenceCount(_retainState) + 1;
}

- (unsigned int)hash {
    return _machPort;
}

- (void)addConnection:(NSConnection *)connection toRunLoop:(NSRunLoop *)runLoop
              forMode:(NSString *)mode {
    (void)connection;
    [self setDelegate:[NSConcretePortCoder class]];
    [runLoop addPort:self forMode:mode];
}

- (void)removeConnection:(NSConnection *)connection
             fromRunLoop:(NSRunLoop *)runLoop
                  forMode:(NSString *)mode {
    [runLoop removePort:self forMode:mode];
}

- (BOOL)isEqual:(id)object {
    return self == object;
}

- (void)dealloc {
    unsigned index;

    if (_NSPortTableLock != nil)
        [_NSPortTableLock lock];
    for (index = 0; index < 4; index++) {
        if (NSPortCache[index] == nil) {
            NSPortCache[index] = self;
            _retainState = NSMachPortSetReferenceCount(_retainState, 0);
            _delegate = nil;
            _machPort = 0;
            _retainState &= ~NSMachPortValidMask;
            if (_NSPortTableLock != nil)
                [_NSPortTableLock unlock];
            if (NSKeepAllocationStatistics)
                NSRecordAllocationEvent(NSObjectDeallocatedEvent, self);
            return;
        }
    }
    if (_NSPortTableLock != nil)
        [_NSPortTableLock unlock];
    [super dealloc];
}

@end

@implementation NSMachPort (NSPortMessageSpeedups)

#if defined(__ppc__) || defined(__POWERPC__)
- (BOOL)sendBeforeDate:(NSDate *)limitDate
            components:(NSMutableArray *)components
                  from:(NSPort *)receivePort
              reserved:(unsigned)headerSpaceReserved {
    NSTimeInterval time = [limitDate timeIntervalSinceReferenceDate];

    (void)headerSpaceReserved;
    return [NSPortMessage sendBeforeTime:time streamData:nil
                              components:components to:self from:receivePort
                                   msgid:0 reserved:0];
}
#endif

- (unsigned)reservedSpaceLength {
    return 36;
}

- (BOOL)sendBeforeTime:(NSTimeInterval)time streamData:(id)streamData
            components:(NSArray *)components from:(NSPort *)receivePort
                 msgid:(unsigned)msgid {
    return [NSPortMessage sendBeforeTime:time streamData:streamData
                              components:components to:self from:receivePort
                                   msgid:msgid reserved:36];
}

@end
