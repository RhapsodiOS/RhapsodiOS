/*	NSDistantObject.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDistantObject.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSString.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSZone.h>
#import <objc/Protocol.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

@interface NSConnection (NSDistantObjectPrivate)
- (id)getRemote:(id)target;
- (id)getLocal:(id)target;
- (id)insertProxy:(NSDistantObject *)proxy;
- (NSDistantObject *)getRemote:(id)target;
- (id)_objectWithName:(id)name;
- (void)sendWireCountForTarget:(id)target port:(NSPort *)port;
- (void)sendInvocation:(NSInvocation *)invocation target:(id)target;
- (BOOL)hasRunLoop:(NSRunLoop *)runLoop;
- (BOOL)multipleThreadsEnabled;
- (void)addRunLoop:(NSRunLoop *)runLoop;
@end

@interface NSObject (NSDistantObjectMethodDescription)
- (struct objc_method_description *)methodDescriptionForSelector:(SEL)selector;
@end

@interface NSInvocationBuilder
+ (id)builderForClass:(Class)aClass;
@end

@interface NSDistantObject (NSDistantObjectPrivateProtocolQuery)
- (BOOL)_conformsToProtocolNamed:(const char *)protocolName;
@end

@interface NSPortCoder (NSDistantObjectPrivate)
- (void)importObject:(id)object;
@end

@interface NSConnection (NSDistantObjectWireCounts)
- (void)releaseName:(id)name count:(unsigned)count;
- (void)removeProxy:(NSDistantObject *)proxy;
- (void)removeLocal:(NSDistantObject *)proxy;
@end

struct NSDistantObjectProtocolList {
    struct NSDistantObjectProtocolList *next;
    int count;
    Protocol *list[1];
};

struct NSDistantObjectProtocolLayout {
    Class isa;
    char *name;
    struct NSDistantObjectProtocolList *protocols;
    struct objc_method_description_list *instanceMethods;
    struct objc_method_description_list *classMethods;
};

extern NSLock *_NSDistantObjectSelectorsTableLock;
extern NSLock *_NSGlobalRetainLock;

#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSDistantObjectRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSDistantObjectLockRetainState(void)
{
    if (!_NSIsMultiThreaded)
        return NO;
    for (;;) {
        unsigned oldValue;
        unsigned acquired;
        unsigned one = 1;

        __asm__ volatile(
            "1: lwarx %0,0,%2\n\t"
            "cmpwi %0,0\n\t"
            "bne- 2f\n\t"
            "stwcx. %3,0,%2\n\t"
            "bne- 1b\n\t"
            "isync\n\t"
            "li %1,1\n\t"
            "b 3f\n"
            "2: li %1,0\n"
            "3:"
            : "=&r" (oldValue), "=&r" (acquired)
            : "r" (&__NSDistantObjectRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSDistantObjectUnlockRetainState(BOOL locked)
{
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSDistantObjectRetainLock = 0;
    }
}
#else
static BOOL NSDistantObjectLockRetainState(void)
{
    if (_NSGlobalRetainLock == nil)
        return NO;
    [_NSGlobalRetainLock lock];
    return YES;
}

static void NSDistantObjectUnlockRetainState(BOOL locked)
{
    if (locked)
        [_NSGlobalRetainLock unlock];
}
#endif

NSMethodSignature *__NSMethodDescriptionForSelectorSignature;
NSMethodSignature *__NSReleaseSignature;

static void NSDistantObjectRetainObject(NSMapTable *table, const void *object) {
    (void)table;
    [(id)object retain];
}

static int NSDistantObjectLoggingDepth;

@implementation NSDistantObject

+ (void)_enableLogging:(BOOL)flag
{
    if (flag)
        NSDistantObjectLoggingDepth++;
    else
        NSDistantObjectLoggingDepth--;
}

+ (BOOL)isAClassOfObject:(id)object
{
    Class candidate = object->isa;

    if (candidate == Nil)
        return NO;
    while (candidate != self) {
        candidate = candidate->super_class;
        if (candidate == Nil)
            return NO;
    }
    return YES;
}

+ (id)newDistantObjectWithCoder:(NSPortCoder *)coder {
    int objectName;
    int wireKind;
    NSConnection *connection;
    NSDistantObject *proxy;

    [coder decodeValueOfObjCType:"i" at:&objectName];
    [coder decodeValueOfObjCType:"i" at:&wireKind];
    if (wireKind == 0) {
        if (NSDistantObjectLoggingDepth)
            NSLog(@"initWithCoder: %x isLocal->isRemote", objectName);
        connection = [coder connection];
        proxy = [connection getRemote:(id)(unsigned long)objectName];
        if (proxy == nil) {
            proxy = [[self allocWithZone:[coder objectZone]]
                initWithTarget:(id)(unsigned long)objectName connection:connection];
        } else {
            [proxy retain];
        }
        ++proxy->wireCount;
        [coder importObject:proxy];
        return proxy;
    }
    if (wireKind == 1) {
        connection = [coder connection];
        proxy = [connection _objectWithName:(id)(unsigned long)objectName];
        if (NSDistantObjectLoggingDepth) {
            if (proxy != nil)
                NSLog(@"initWithCoder: %x isRemote->isLocal", objectName);
            else
                NSLog(@"initWithCoder: %x not given away", objectName);
        }
        return [proxy retain];
    }
    if (wireKind == 2) {
        NSPort *port;
        NSConnection *otherConnection;

        if (NSDistantObjectLoggingDepth)
            NSLog(@"initWithCoder: %x isOther", objectName);
        [coder decodeValueOfObjCType:"@" at:&port];
        if (port == nil)
            [NSException raise:NSInvalidArgumentException
                        format:@"NSDistantObject received a nil port"];
        connection = [coder connection];
        otherConnection = [NSConnection connectionWithReceivePort:
            [connection receivePort] sendPort:port];
        proxy = [[self allocWithZone:[coder objectZone]]
            initWithTarget:(id)(unsigned long)objectName connection:otherConnection];
        if (proxy != nil)
            ++proxy->wireCount;
        [port release];
        return proxy;
    }
    [NSException raise:NSInvalidArgumentException
                format:@"NSDistantObject received invalid wire kind %d", wireKind];
    return nil;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    NSConnection *targetConnection = [(NSPortCoder *)coder connection];
    id objectName = name;
    int wireKind;
    NSPort *port = nil;
    unsigned wireValue = wire & 3;

    if (targetConnection == nil)
        [NSException raise:NSInvalidArgumentException
                    format:@"NSDistantObject cannot encode without a connection"];
    if (wireValue == 1 && conn == targetConnection) {
        wireKind = 1;
    } else if (wireValue == 1) {
        wireKind = 2;
        port = [conn sendPort];
        [self retain];
        [self autorelease];
        [conn sendWireCountForTarget:name port:[targetConnection sendPort]];
    } else if (wireValue != 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSDistantObject has invalid wire kind %u", wireValue];
    } else if (conn == targetConnection) {
        wireKind = 0;
        ++wireCount;
    } else {
        NSConnection *otherConnection;
        NSDistantObject *counterpart;

        wireKind = 2;
        port = [conn receivePort];
        otherConnection = [NSConnection connectionWithReceivePort:port
            sendPort:[targetConnection sendPort]];
        counterpart = [isa proxyWithLocal:name connection:otherConnection];
        ++counterpart->wireCount;
    }
    [coder encodeValueOfObjCType:"i" at:&objectName];
    [coder encodeValueOfObjCType:"i" at:&wireKind];
    if (wireKind == 2)
        [coder encodeValueOfObjCType:"@" at:&port];
}

- (Class)classForPortCoder {
    return isa;
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    (void)coder;
    return self;
}

- (id)awakeAfterUsingCoder:(NSCoder *)coder {
    return self;
}

- (Class)classForArchiver {
    [NSException raise:NSInvalidArgumentException
                format:@"NSDistantObject asked to archive"];
    return Nil;
}

- (Class)class {
    return isa;
}

- (void)appendFormat:(NSString *)format, ... {
    va_list arguments;
    NSString *formattedString;
    id builder;
    NSInvocation *invocation;

    va_start(arguments, format);
    formattedString = [[NSString allocWithZone:NULL]
        initWithFormat:format arguments:arguments];
    va_end(arguments);

    builder = [NSInvocationBuilder builderForClass:[NSMutableString class]];
    invocation = [builder appendString:formattedString];
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [formattedString release];
}

- (NSString *)stringByAppendingFormat:(NSString *)format, ... {
    va_list arguments;
    NSString *formattedString;
    id builder;
    NSInvocation *invocation;
    NSString *result;

    va_start(arguments, format);
    formattedString = [[NSString allocWithZone:NULL]
        initWithFormat:format arguments:arguments];
    va_end(arguments);

    builder = [NSInvocationBuilder builderForClass:[NSString class]];
    invocation = [builder stringByAppendingString:formattedString];
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    [formattedString release];
    return result;
}

- (BOOL)conformsToProtocol:(Protocol *)protocol {
    if ((wire & 3) != 1) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"%s sent to invalid NSDistantObject", (char *)_cmd];
        return NO;
    }
    return [self _conformsToProtocolNamed:[protocol name]];
}

+ (NSDistantObject *)proxyWithTarget:(id)target connection:(NSConnection *)connection {
    NSDistantObject *proxy = [connection getRemote:target];

    if (proxy == nil)
        return [[[self allocWithZone:NULL] initWithTarget:target connection:connection]
            autorelease];
    return proxy;
}

- (id)initWithTarget:(id)target connection:(NSConnection *)connection {
    NSDistantObject *proxy;
    NSMapTableValueCallBacks valueCallbacks;

    name = target;
    conn = [connection retain];
    wire = 1;
    refCount = 1;
    proxy = [connection insertProxy:self];
    if (proxy == self) {
        valueCallbacks = NSObjectMapValueCallBacks;
        valueCallbacks.retain = NSDistantObjectRetainObject;
        _knownSelectors = NSCreateMapTableWithZone(
            NSNonOwnedPointerMapKeyCallBacks, valueCallbacks, 8, NULL);
        return self;
    }

    wire |= 3;
    [proxy retain];
    [self dealloc];
    return proxy;
}

+ (NSDistantObject *)proxyWithLocal:(id)target connection:(NSConnection *)connection {
    NSDistantObject *proxy = [connection getLocal:target];

    if (proxy == nil)
        return [[[self allocWithZone:NULL] initWithLocal:target connection:connection]
            autorelease];
    return proxy;
}

- (id)initWithLocal:(id)target connection:(NSConnection *)connection {
    NSDistantObject *proxy;

    name = target;
    conn = [connection retain];
    wire = 0;
    refCount = 1;
    proxy = [connection insertProxy:self];
    if (proxy == self) {
        _knownSelectors = NSCreateMapTableWithZone(
            NSNonOwnedPointerMapKeyCallBacks, NSObjectMapValueCallBacks, 0, NULL);
        [target retain];
        return self;
    }

    wire |= 3;
    [proxy retain];
    [self dealloc];
    return proxy;
}

- (id)initWithCoder:(NSCoder *)coder {
    id objectName;
    int wireKind;
    NSConnection *connection;
    NSDistantObject *proxy;

    [coder decodeValueOfObjCType:"i" at:&objectName];
    name = objectName;
    [coder decodeValueOfObjCType:"i" at:&wireKind];
    wire = wireKind & 3;

    if ((wireKind & 3) == 0) {
        if (NSDistantObjectLoggingDepth)
            NSLog(@"initWithCoder: %x isLocal->isRemote", name);
        connection = [(NSPortCoder *)coder connection];
        proxy = [self initWithTarget:name connection:connection];
        ++proxy->wireCount;
        [(NSPortCoder *)coder importObject:proxy];
        return proxy;
    }

    if ((wireKind & 3) == 1) {
        connection = [(NSPortCoder *)coder connection];
        proxy = [connection _objectWithName:name];
        if (NSDistantObjectLoggingDepth) {
            if (proxy != nil)
                NSLog(@"initWithCoder: %x isRemote->isLocal", name);
            else
                NSLog(@"initWithCoder: %x not given away", name);
        }
        [proxy retain];
        [super dealloc];
        return proxy;
    }

    if ((wireKind & 3) == 2) {
        NSPort *port;
        NSConnection *otherConnection;

        if (NSDistantObjectLoggingDepth)
            NSLog(@"initWithCoder: %x isOther", name);
        [coder decodeValueOfObjCType:"@" at:&port];
        if (port == nil)
            [NSException raise:NSInternalInconsistencyException
                        format:@"%s broken invariant", (char *)_cmd];
        connection = [(NSPortCoder *)coder connection];
        otherConnection = [NSConnection connectionWithReceivePort:
            [connection receivePort] sendPort:port];
        proxy = [self initWithTarget:name connection:otherConnection];
        if (proxy != nil)
            ++proxy->wireCount;
        [port release];
        return proxy;
    }

    [NSException raise:NSInternalInconsistencyException
                format:@"%s bad wire type: %x!", (char *)_cmd, wireKind];
    return self;
}

- (void)setProtocolForProxy:(Protocol *)proto {
    struct NSDistantObjectProtocolLayout *layout;
    struct objc_method_description_list *methods;
    struct NSDistantObjectProtocolList *protocols;
    int index;

    if (proto == nil)
        return;

    layout = (struct NSDistantObjectProtocolLayout *)proto;
    methods = layout->instanceMethods;
    if (methods != NULL && methods->count != 0) {
        if (_NSDistantObjectSelectorsTableLock != nil)
            [_NSDistantObjectSelectorsTableLock lock];
        for (index = 0; index < methods->count; index++) {
            struct objc_method_description *description = &methods->list[index];
            NSMethodSignature *signature =
                [NSMethodSignature signatureWithObjCTypes:description->types];

            NSMapInsert((NSMapTable *)_knownSelectors, description->name, signature);
        }
        if (_NSDistantObjectSelectorsTableLock != nil)
            [_NSDistantObjectSelectorsTableLock unlock];
    }

    protocols = layout->protocols;
    if (protocols != NULL) {
        for (index = 0; index < protocols->count; index++)
            [self setProtocolForProxy:protocols->list[index]];
    }
}

- (NSConnection *)connectionForProxy {
    return conn;
}

- (id)copyWithZone:(NSZone *)zone {
    NSInvocation *invocation = [NSInvocationBuilder builderForClass:[NSArray class]];
    id result;

#if defined(__ppc__) || defined(__POWERPC__)
    [invocation copyWithZone:zone];
#else
    [invocation copyWithZone:NULL];
#endif
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return [result retain];
}

- (id)copy {
    NSInvocation *invocation = [NSInvocationBuilder builderForClass:[NSObject class]];
    id result;

    [invocation copy];
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return [result retain];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSInvocation *invocation = [NSInvocationBuilder builderForClass:[NSArray class]];
    id result;

#if defined(__ppc__) || defined(__POWERPC__)
    [invocation mutableCopyWithZone:zone];
#else
    [invocation mutableCopyWithZone:NULL];
#endif
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return [result retain];
}

- (id)mutableCopy {
    NSInvocation *invocation = [NSInvocationBuilder builderForClass:[NSObject class]];
    id result;

    [invocation mutableCopy];
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return [result retain];
}

- (NSString *)description {
    NSInvocation *invocation = [NSInvocationBuilder builderForClass:[NSObject class]];
    NSString *result;

    [invocation description];
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return result;
}

- (unsigned)hash {
    NSInvocation *invocation = [NSInvocationBuilder builderForClass:[NSObject class]];
    unsigned result;

    [invocation hash];
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return result;
}

- (BOOL)isEqual:(id)object {
    NSInvocation *invocation;
    BOOL result;

    if (object == self)
        return YES;
    invocation = [NSInvocationBuilder builderForClass:[NSObject class]];
    [invocation isEqual:object];
    [invocation setTarget:self];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return result;
}

- (NSZone *)zone {
    return NSDefaultMallocZone();
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    NSMethodSignature *signature = nil;
    struct objc_method_description *description = NULL;

    if (selector == @selector(methodDescriptionForSelector:))
        return __NSMethodDescriptionForSelectorSignature;
    if (selector == @selector(release))
        return __NSReleaseSignature;
    if (NSDistantObjectLoggingDepth)
        NSLog(@"methodSignatureForSelector:@selector(%s)", (char *)selector);

    if (_NSDistantObjectSelectorsTableLock != nil)
        [_NSDistantObjectSelectorsTableLock lock];
    signature = (NSMethodSignature *)NSMapGet((NSMapTable *)_knownSelectors,
                                               selector);
    if (_NSDistantObjectSelectorsTableLock != nil)
        [_NSDistantObjectSelectorsTableLock unlock];
    if (signature != nil)
        return signature;

    if (wire == 1)
        description = [self methodDescriptionForSelector:selector];
    else if (wire == 0)
        description = [name methodDescriptionForSelector:selector];
    else
        [NSException raise:NSInternalInconsistencyException
                    format:@"methodSignature for bad wire type: %d", wire];

    if (description != NULL)
        signature = [NSMethodSignature signatureWithObjCTypes:description->types];
    if (signature != nil) {
        if (_NSDistantObjectSelectorsTableLock != nil)
            [_NSDistantObjectSelectorsTableLock lock];
        NSMapInsert((NSMapTable *)_knownSelectors, selector, signature);
        if (_NSDistantObjectSelectorsTableLock != nil)
            [_NSDistantObjectSelectorsTableLock unlock];
    }
    return signature;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    unsigned wireKind = wire;

    if (NSDistantObjectLoggingDepth)
        NSLog(@"entered forwardInvocation [0x%x %@...]", name,
              [invocation methodSignature]);

    switch (wireKind) {
    case 0:
        [NSException raise:NSInternalInconsistencyException
                    format:@"messaging a local proxy"];
        break;
    case 1:
        break;
    case 2:
        [NSException raise:NSInternalInconsistencyException
                    format:@"messaging garbage!"];
        break;
    case 3:
        [NSException raise:NSObjectInaccessibleException
                    format:@"NSDistantObject is invalid"];
        break;
    }
    if (![[invocation methodSignature] isOneway] && ![conn hasRunLoop:runLoop]) {
        if ([conn multipleThreadsEnabled])
            [conn addRunLoop:runLoop];
        else
            [NSException raise:NSObjectInaccessibleException
                        format:@"NSDistantObject accessed attempted from another thread"];
    }
    [conn sendInvocation:invocation target:name];
}

- (id)retain {
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSDistantObjectLockRetainState();

    if (refCount != 0xFFFFFF)
        ++refCount;
    NSDistantObjectUnlockRetainState(locked);
#else
    BOOL locked = NSDistantObjectLockRetainState();

    ++refCount;
    NSDistantObjectUnlockRetainState(locked);
#endif
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (void)release {
    unsigned releaseCount = 0;
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSDistantObjectLockRetainState();
    --refCount;
    if (refCount == 0) {
        if (wireCount != 0) {
            if (wire == 1)
                releaseCount = wireCount;
        } else {
            shouldDeallocate = YES;
        }
    }
    NSDistantObjectUnlockRetainState(locked);
    if (releaseCount != 0)
        [self _releaseWireCount:releaseCount];
    if (shouldDeallocate)
        [self dealloc];
}

- (unsigned)retainCount {
    return refCount;
}

- (void)retainWireCount {
    BOOL locked = NSDistantObjectLockRetainState();

    ++wireCount;
    NSDistantObjectUnlockRetainState(locked);
}

- (void)_releaseWireCount:(unsigned)count {
    BOOL countReachedZero;
    BOOL shouldDeallocate;
    BOOL locked;

    locked = NSDistantObjectLockRetainState();
    countReachedZero = wireCount == count;
    wireCount -= count;
    shouldDeallocate = countReachedZero && refCount == 0;
    NSDistantObjectUnlockRetainState(locked);

    if (wire == 1)
        [(NSConnection *)conn releaseName:name count:count];
    if (shouldDeallocate)
        [self dealloc];
    else if (countReachedZero)
        [self invalidateProxy];
}

- (void)_anticipateRelease {
    unsigned count = 0;

    if (wire != 1 && wire != 3)
        [NSException raise:NSInternalInconsistencyException
                    format:@"Cannot anticipate release for a local distant object"];
    if (refCount == 1)
        count = wireCount;
    if (count != 0) {
        if (NSDistantObjectLoggingDepth)
            NSLog(@"piggybacking [0x%x _releaseWireCount:%u]", name, count);
        [self _releaseWireCount:count];
    }
}

- (void)invalidateProxy {
    if (wire == 1)
        [conn removeProxy:self];
    else if (wire == 0) {
        [conn removeLocal:self];
        [name release];
    }
    wire = 3;
    wireCount = 0;
}

- (void)dealloc {
    [self invalidateProxy];
    if (_knownSelectors != NULL)
        NSFreeMapTable((NSMapTable *)_knownSelectors);
    [conn release];
    if (NSDistantObjectLoggingDepth)
        NSLog(@"deallocing %x", self);
    [super dealloc];
}

@end
