/*	NSConnection.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSConnection.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSPortNameServer.h>
#import <Foundation/NSRecursiveLock.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSProtocolChecker.h>
#import <Foundation/NSSerialization.h>
#import <Foundation/NSThread.h>
#import <objc/Protocol.h>
#import <objc/objc-runtime.h>

#include <string.h>

@protocol NSConnectionProtocol
- (id)rootObject;
@end

@interface NSConcretePortCoder : NSPortCoder
+ (void)_enableLogging:(BOOL)flag;
@end

@interface NSInvocation (NSConnectionLogging)
+ (void)_enableLogging:(BOOL)flag;
@end

@interface NSDistantObject (NSConnectionLogging)
+ (void)_enableLogging:(BOOL)flag;
@end

@interface NSThread (NSConnectionConversation)
- (id)lastConversation;
- (NSRunLoop *)runLoop;
- (void)addConversation:(id)conversation;
- (void)removeConversation;
- (id)conversationRequest;
- (void)clearConversationRequest;
- (void)setConversationRequest:(id)request;
- (NSMutableArray *)workQueue;
+ (NSThread *)mapConversationToThread:(id)conversation;
@end

@interface NSRunLoop (NSConnectionReplyWakeup)
- (void)_wakeup;
@end

@interface NSPort (NSConnectionPrivate)
- (void)addConnection:(NSConnection *)connection
           toRunLoop:(NSRunLoop *)runLoop
              forMode:(NSString *)mode;
- (void)removeConnection:(NSConnection *)connection
          fromRunLoop:(NSRunLoop *)runLoop
              forMode:(NSString *)mode;
@end

extern NSLock *_NSConnectionHashTableLock;
extern NSLock *_NSConnectionTableLock;
extern NSRecursiveLock *_NSConnectionModesLock;
#import "NSProcessInfoPrivate.h"
extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);
extern NSMethodSignature *__NSMethodDescriptionForSelectorSignature;
extern NSMethodSignature *__NSReleaseSignature;

@interface NSObject (NSConnectionMethodDescription)
- (struct objc_method_description *)methodDescriptionForSelector:(SEL)selector;
@end

@interface NSConnection (NSConnectionProxyRegistry)
+ (void)doQueuedWork;
- (void)handlePortCoder:(NSPortCoder *)coder;
- (void)handleRequest:(NSPortCoder *)coder sequence:(unsigned)sequence;
- (BOOL)_shouldDispatch:(id *)conversation invocation:(NSInvocation *)invocation
               sequence:(unsigned)sequence coder:(NSPortCoder *)coder;
- (void)_queueRequestForThread:(NSThread *)thread invocation:(NSInvocation *)invocation
                  conversation:(id)conversation sequence:(unsigned)sequence
                         coder:(NSPortCoder *)coder;
- (NSPortCoder *)getReplyWithSequence:(unsigned)sequence
                           withRunLoop:(NSRunLoop *)runLoop
                              inThread:(NSThread *)thread;
- (NSDistantObject *)getRemote:(id)target;
- (NSDistantObject *)getLocal:(id)target;
- (char *)getReleasedProxies:(NSPortCoder *)coder length:(unsigned *)length;
- (void)handleReleasedProxies:(char *)bytes length:(unsigned)length;
- (void)decodeReleasedProxies:(NSPortCoder *)coder;
- (BOOL)_cleanupAndAuthenticate:(NSPortCoder *)coder
                       sequence:(unsigned)sequence
                    conversation:(id *)conversation
                    invocation:(NSInvocation *)invocation
                          raise:(BOOL)shouldRaise;
- (NSDistantObject *)insertProxy:(NSDistantObject *)proxy;
- (id)proxyForObject:(id)object;
- (id)proxyWithLocal:(id)object;
- (id)_objectWithName:(id)object;
- (void)removeProxy:(NSDistantObject *)proxy;
- (void)removeLocal:(NSDistantObject *)proxy;
- (NSArray *)localProxies;
- (id)newConversation;
- (BOOL)hasRunLoop:(NSRunLoop *)runLoop;
- (NSDate *)requestLimit;
- (void)removeAllRequestModes;
- (void)returnResult:(NSInvocation *)invocation exception:(NSException *)exception
            sequence:(unsigned)sequence imports:(NSArray *)imports;
- (void)finishEncoding:(NSPortCoder *)coder;
- (id)dispatchInvocation:(NSInvocation *)invocation;
- (void)addPortsToAllRunLoops;
- (void)addPortsToRunLoop:(NSRunLoop *)runLoop;
- (void)removePortsFromAllRunLoops;
- (void)removePortsFromRunLoop:(NSRunLoop *)runLoop;
- (void)portalDied:(NSNotification *)notification;
- (void)run;
@end

@interface NSInvocation (NSConnectionPrivate)
- (BOOL)_signatureValid;
- (void)encodeReturnValueWithCoder:(NSCoder *)coder;
- (void)decodeReturnValueWithCoder:(NSCoder *)coder;
- (void)invalidate;
@end

@interface NSConcretePortCoder (NSConnectionWireCount)
- (id)initWithConnection:(NSConnection *)connection msgid:(unsigned)msgid;
- (void)encodeValueOfObjCType:(const char *)type at:(const void *)address;
- (void)decodeValueOfObjCType:(const char *)type at:(void *)address;
- (void)encodePortObject:(NSPort *)port;
- (NSPort *)decodePortObject;
- (void)encodeBytes:(const void *)bytes length:(unsigned)length;
- (void)sendBeforeTime:(NSTimeInterval)time;
- (void)decryptWithDelegate:(id)delegate;
- (void)encryptWithDelegate:(id)delegate;
- (void)authenticateWithDelegate:(id)delegate;
- (BOOL)verifyWithDelegate:(id)delegate;
- (NSArray *)importedObjects;
- (void)invalidate;
@end

@interface NSDistantObject (NSConnectionPrivate)
- (void)invalidateProxy;
- (void)retainWireCount;
- (void)_anticipateRelease;
- (void)_releaseWireCount:(unsigned)count;
@end

@interface NSObject (NSConnectionCopySelectors)
- (id)copy;
- (id)mutableCopy;
- (id)target;
+ (BOOL)isAncestorOfObject:(id)object;
@end

@interface NSDistributedObjectsStatistics : NSDictionary {
    unsigned requestsReceived;
    unsigned repliesSent;
    unsigned requestsSent;
    unsigned repliesReceived;
}
- (void)addStatistics:(NSDistributedObjectsStatistics *)statistics;
@end

@interface NSConcreteDistantObjectRequest : NSDistantObjectRequest {
@public
    NSInvocation *invocation;
    NSMutableArray *importedObjects;
    id conversation;
    NSConnection *connection;
    unsigned sequence;
}
- (id)initWithInvocation:(NSInvocation *)invocation conversation:(id)conversation
                sequence:(unsigned)sequence importedObjects:(NSMutableArray *)objects
              connection:(NSConnection *)connection;
@end

NSString * const NSConnectionReplyMode = @"NSConnectionReplyMode";
NSString * const NSConnectionDidDieNotification = @"NSConnectionDidDieNotification";
NSString * const NSConnectionDidInitializeNotification = @"NSConnectionDidInitializeNotification";
NSString * const NSFailedAuthenticationException = @"NSFailedAuthenticationException";

static NSHashTable *conn_table;
static NSMapTable *conversation_table;
static NSMapTable *reply_table;
NSLock *_NSConnectionReplyTableLock;
NSLock *_NSConnectionLock;
NSLock *_NSConnectionConversationTableLock;
NSLock *_NSConnectionWorkQueueLock;
static unsigned connectionSequence;

struct NSConnectionRequestFlags {
    Class isa;
    id receivePort;
    id sendPort;
    id delegate;
    unsigned isValid:1;
    unsigned isDead:1;
    unsigned isQueueing:1;
    unsigned authGen:1;
    unsigned authCheck:1;
    unsigned encryptFlag:1;
    unsigned decryptFlag:1;
    unsigned doRequest:1;
};

struct NSThreadRequestQueueLayout {
    Class isa;
    unsigned seqNum;
    unsigned lastStack;
    id threadDictionary;
    id runLoop;
    void *excHandlers;
    void *autoreleasePool;
    id doQueue;
};

static void NSConnectionHandleQueuedRequest(
    NSConcreteDistantObjectRequest *request, NSThread *thread) {
    NSConnection *connection = request->connection;
    struct NSConnectionRequestFlags *flags =
        (struct NSConnectionRequestFlags *)connection;
    NSInvocation *invocation = request->invocation;
    id conversation = request->conversation;
    NSException *exception = nil;
    BOOL handled = NO;

    if (conversation != nil)
        [thread addConversation:conversation];
    if (flags->doRequest) {
        NS_DURING
            handled = [[connection delegate] connection:connection
                handleRequest:request];
        NS_HANDLER
            NSLog(@"Error occured in delegate connection:handleRequest:\n");
        NS_ENDHANDLER
    }
    if (!handled)
        exception = [connection dispatchInvocation:invocation];
    if (conversation != nil)
        [thread removeConversation];
    if (!handled)
        [request replyWithException:exception];
    [request release];
}

/* The target reads these NSDistantObject fields when registering proxies. */
struct NSConnectionDistantObjectLayout {
    Class isa;
    id name;
    unsigned wire:2;
    unsigned unused:6;
    unsigned refCount:24;
    NSConnection *connection;
};

struct NSConnectionTableKey {
    void *reserved;
    NSPort *receivePort;
    NSPort *sendPort;
};

static unsigned hashConnection(NSHashTable *table, const void *value) {
    const struct NSConnectionTableKey *key =
        (const struct NSConnectionTableKey *)value;

    (void)table;
    return (unsigned)((unsigned long)key->receivePort
                    + (unsigned long)key->sendPort);
}

static BOOL isEqualConnection(NSHashTable *table,
                              const void *left,
                              const void *right) {
    const struct NSConnectionTableKey *leftKey =
        (const struct NSConnectionTableKey *)left;
    const struct NSConnectionTableKey *rightKey =
        (const struct NSConnectionTableKey *)right;

    (void)table;
    return leftKey->receivePort == rightKey->receivePort
        && leftKey->sendPort == rightKey->sendPort;
}

void NSConnectionRegisterConversation(id conversation, NSThread *thread) {
    if (conversation_table == NULL)
        return;
    if (_NSConnectionConversationTableLock != nil)
        [_NSConnectionConversationTableLock lock];
    NSMapInsert(conversation_table, conversation, thread);
    if (_NSConnectionConversationTableLock != nil)
        [_NSConnectionConversationTableLock unlock];
}

void NSConnectionUnregisterConversation(id conversation) {
    if (conversation_table == NULL)
        return;
    if (_NSConnectionConversationTableLock != nil)
        [_NSConnectionConversationTableLock lock];
    NSMapRemove(conversation_table, conversation);
    if (_NSConnectionConversationTableLock != nil)
        [_NSConnectionConversationTableLock unlock];
}

NSThread *NSConnectionThreadForConversation(id conversation) {
    NSThread *thread;

    if (conversation_table == NULL)
        return nil;
    if (_NSConnectionConversationTableLock != nil)
        [_NSConnectionConversationTableLock lock];
    thread = (NSThread *)NSMapGet(conversation_table, conversation);
    if (_NSConnectionConversationTableLock != nil)
        [_NSConnectionConversationTableLock unlock];
    return thread;
}

static unsigned NSConnectionHashProxy(NSHashTable *table, const void *value) {
    const struct NSConnectionDistantObjectLayout *proxy =
        (const struct NSConnectionDistantObjectLayout *)value;

    (void)table;
    return (unsigned)(unsigned long)proxy->name;
}

static BOOL NSConnectionEqualProxy(NSHashTable *table,
                                   const void *left,
                                   const void *right) {
    const struct NSConnectionDistantObjectLayout *leftProxy =
        (const struct NSConnectionDistantObjectLayout *)left;
    const struct NSConnectionDistantObjectLayout *rightProxy =
        (const struct NSConnectionDistantObjectLayout *)right;

    (void)table;
    return leftProxy->name == rightProxy->name;
}

static NSArray *NSDistributedObjectsStatisticsKeys;

static unsigned NSConnectionDecodeFastInteger(const unsigned char **cursor,
                                               const unsigned char *end) {
    int signedLength;
    unsigned length;
    unsigned value;
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned index;
#endif

    if (end <= *cursor)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more int data to decode (case %d)", 1];

    signedLength = (signed char)*(*cursor)++;
    length = signedLength < 0 ? (unsigned)-signedLength
                             : (unsigned)signedLength;
    if (signedLength < 0 && length > sizeof(value))
        [NSException raise:NSRangeException
                    format:@"more significant bytes than room to hold them"];
    if ((unsigned)(end - *cursor) < length)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more int data to decode (case %d)", 2];
    if (length > sizeof(value))
        [NSException raise:NSRangeException
                    format:@"more significant bytes than room to hold them"];

    value = signedLength < 0 ? ~(unsigned)0 : 0;
    if (length != 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        for (index = 0; index < length; ++index)
            ((unsigned char *)&value)[sizeof(value) - index - 1] =
                (*cursor)[index];
#else
        memcpy(&value, *cursor, length);
#endif
    }
    *cursor += length;
    return value;
}

static void NSConnectionHandleReleasedProxyBytes(NSConnection *connection,
                                                  const void *bytes,
                                                  unsigned length) {
    [connection handleReleasedProxies:(char *)bytes length:length];
}

@implementation NSDistributedObjectsStatistics

- (void)addStatistics:(NSDistributedObjectsStatistics *)statistics {
    requestsReceived += statistics->requestsReceived;
    repliesSent += statistics->repliesSent;
    requestsSent += statistics->requestsSent;
    repliesReceived += statistics->repliesReceived;
}

- (NSArray *)allKeys {
    if (NSDistributedObjectsStatisticsKeys == nil) {
        NSDistributedObjectsStatisticsKeys = [[NSArray allocWithZone:NULL]
            initWithObjects:@"NSConnectionRequestsReceived",
                            @"NSConnectionRepliesSent",
                            @"NSConnectionRequestsSent",
                            @"NSConnectionRepliesReceived", nil];
    }
    return NSDistributedObjectsStatisticsKeys;
}

- (unsigned)count {
    return 4;
}

- (NSEnumerator *)keyEnumerator {
    return [[self allKeys] objectEnumerator];
}

- (id)objectForKey:(id)key {
    if ([key isEqual:@"NSConnectionRequestsReceived"])
        return [NSNumber numberWithUnsignedInt:requestsReceived];
    if ([key isEqual:@"NSConnectionRepliesSent"])
        return [NSNumber numberWithUnsignedInt:repliesSent];
    if ([key isEqual:@"NSConnectionRequestsSent"])
        return [NSNumber numberWithUnsignedInt:requestsSent];
    if ([key isEqual:@"NSConnectionRepliesReceived"])
        return [NSNumber numberWithUnsignedInt:repliesReceived];
    return nil;
}

- (id)copyWithZone:(NSZone *)zone {
    NSDistributedObjectsStatistics *copy =
        [[(Class)self->isa allocWithZone:zone] init];
    [copy addStatistics:self];
    return copy;
}

@end

static int NSConnectionLoggingDepth;
static BOOL NSConnectionInfoLoggingEnabled;

@implementation NSConnection

+ (void)_enableLogging:(BOOL)flag
{
    if (flag)
        NSConnectionLoggingDepth++;
    else
        NSConnectionLoggingDepth--;
}

+ (void)_toggleLogging
{
    id portCoderClass;

    NSConnectionInfoLoggingEnabled = !NSConnectionInfoLoggingEnabled;
    [NSConnection _enableLogging:NSConnectionInfoLoggingEnabled];
    [NSInvocation _enableLogging:NSConnectionInfoLoggingEnabled];
    [NSDistantObject _enableLogging:NSConnectionInfoLoggingEnabled];
    portCoderClass = objc_lookUpClass("NSConcretePortCoder");
    [portCoderClass _enableLogging:NSConnectionInfoLoggingEnabled];
}

- (void)sendWireCountForTarget:(id)target port:(NSPort *)port {
    const unsigned messageID = 238026466;
    Class coderClass = objc_lookUpClass("NSConcretePortCoder");
    NSConcretePortCoder *coder = [[coderClass allocWithZone:NULL]
        initWithConnection:self msgid:messageID];
    id targetName = target;
    unsigned message = messageID;

    [coder encodeValueOfObjCType:"i" at:&message];
    [coder encodeValueOfObjCType:"i" at:&targetName];
    [coder encodePortObject:port];
    if (encryptFlag)
        [coder encryptWithDelegate:delegate];
    NS_DURING
        [coder sendBeforeTime:(NSTimeInterval)_NSCurrentTime() + replyLimit];
    NS_HANDLER
        (void)localException;
    NS_ENDHANDLER
    [coder invalidate];
    [coder release];
}

- (unsigned)versionForClassNamed:(NSString *)className {
    void *version = NULL;

    if (classInfoImported == NULL)
        return 0;
    if (_NSConnectionLock != nil)
        [_NSConnectionLock lock];
    NSMapMember(classInfoImported, className, NULL, &version);
    if (_NSConnectionLock != nil)
        [_NSConnectionLock unlock];
    return (unsigned)(unsigned long)version;
}

- (void)addClassNamed:(const char *)className version:(int)version {
    NSString *name = [NSString stringWithCString:className];
    NSMapTableValueCallBacks valueCallbacks = { NULL, NULL, NULL };

    if (_NSConnectionLock != nil)
        [_NSConnectionLock lock];
    if (classInfoImported == NULL)
        classInfoImported = NSCreateMapTableWithZone(
            NSObjectMapKeyCallBacks, valueCallbacks, 0, NULL);
    NSMapInsert(classInfoImported, name, (void *)(unsigned long)version);
    if (_NSConnectionLock != nil)
        [_NSConnectionLock unlock];
}

- (id)init {
    NSPort *port = [NSPort port];
    return [self initWithReceivePort:port sendPort:nil];
}

+ (void)initialize {
    if (conn_table == NULL) {
        NSObject *signatureSource;
        struct objc_method_description *description;
        NSHashTableCallBacks callbacks = {
            hashConnection, isEqualConnection, NULL, NULL, NULL
        };

        signatureSource = [[NSObject allocWithZone:NULL] init];
        conn_table = NSCreateHashTableWithZone(callbacks, 0, NULL);
        conversation_table = NSCreateMapTableWithZone(
            NSIntMapKeyCallBacks, NSObjectMapValueCallBacks, 0, NULL);
        reply_table = NSCreateMapTableWithZone(
            NSIntMapKeyCallBacks, NSObjectMapValueCallBacks, 0, NULL);
        description = [signatureSource methodDescriptionForSelector:
            @selector(methodDescriptionForSelector:)];
        __NSMethodDescriptionForSelectorSignature =
            [[NSMethodSignature signatureWithObjCTypes:description->types] retain];
        description = [signatureSource methodDescriptionForSelector:
            @selector(release)];
        __NSReleaseSignature =
            [[NSMethodSignature signatureWithObjCTypes:description->types] retain];
        [signatureSource release];
    }
}

- (id)retain {
    if (_NSConnectionLock != nil)
        [_NSConnectionLock lock];
    ++refCount;
    if (_NSConnectionLock != nil)
        [_NSConnectionLock unlock];
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (unsigned)retainCount {
    return refCount + 1;
}

- (void)release {
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    if (_NSConnectionLock != nil)
        [_NSConnectionLock lock];
    if (refCount != 0) {
        --refCount;
        if (_NSConnectionLock != nil)
            [_NSConnectionLock unlock];
        return;
    }
    if (isDead) {
        if (_NSConnectionLock != nil)
            [_NSConnectionLock unlock];
        [self dealloc];
        return;
    }
    isDead = YES;
    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock lock];
    NSHashRemove(conn_table, self);
    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock unlock];
    if (_NSConnectionLock != nil)
        [_NSConnectionLock unlock];
    if (isValid && releasedProxies != nil)
        [self sendReleasedProxies];
    [self invalidate];
    if (refCount == 0)
        [self dealloc];
}

- (void)handlePortCoder:(NSPortCoder *)coder {
    unsigned message;

    if (decryptFlag)
        [(NSConcretePortCoder *)coder decryptWithDelegate:delegate];
    [coder decodeValueOfObjCType:"I" at:&message];

    if (message == 238026446) {
        unsigned sequence;
        NSThread *waitingThread;
        NSThread *currentThread;
        void *originalKey = NULL;
        BOOL foundSequence;
        void *value = NULL;

        [coder decodeValueOfObjCType:"I" at:&sequence];
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"NSConnection got REPLY sequence %u from %@ on %@\n",
                  sequence, sendPort, receivePort);
        currentThread = _NSCurrentThread();
        if (_NSConnectionReplyTableLock != nil)
            [_NSConnectionReplyTableLock lock];
        foundSequence = NSMapMember(reply_table,
            (void *)(unsigned long)sequence, &originalKey, &value);
        if (foundSequence) {
            waitingThread = (NSThread *)value;
            NSMapInsert(reply_table, (void *)(unsigned long)sequence, coder);
            if (waitingThread != currentThread) {
                if (NSConnectionLoggingDepth != 0)
                    NSLog(@"%@: Waking up %@ with sequence %u in insertSequence",
                          currentThread, waitingThread, sequence);
                [[waitingThread runLoop] _wakeup];
            }
        }
        if (_NSConnectionReplyTableLock != nil)
            [_NSConnectionReplyTableLock unlock];

        if (!foundSequence) {
            NSLog(@"%@: tossing reply message sequence %u",
                  currentThread, sequence);
            [coder invalidate];
            return;
        }
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"seq %u in %x being stored in hash table\n", sequence, coder);
        return;
    }

    if (message == 236977901) {
        unsigned sequence;

        [coder decodeValueOfObjCType:"I" at:&sequence];
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"NSConnection got REQUEST sequence %u from %@ on %@\n",
                  sequence, sendPort, receivePort);
        [self handleRequest:coder sequence:sequence];
        [coder invalidate];
        return;
    }

    if (message == 238026466) {
        unsigned target;
        NSPort *port;
        NSConnection *localConnection;
        NSDistantObject *proxy;

        [coder decodeValueOfObjCType:"I" at:&target];
        port = [coder decodePortObject];
        localConnection = [[self class] connectionWithReceivePort:[self receivePort]
                                                         sendPort:port];
        proxy = [localConnection proxyWithLocal:(id)(unsigned long)target];
        [proxy retainWireCount];
        return;
    }

    if (message == 238026465) {
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"NSConnection got ADMIN from %@ on %@\n", sendPort, receivePort);
        [self decodeReleasedProxies:coder];
        [coder invalidate];
        return;
    }

    if (NSConnectionLoggingDepth != 0)
        NSLog(@"NSConnection: dropping unknown message type (%x)", message);
    [coder invalidate];
}

- (char *)getReleasedProxies:(NSPortCoder *)coder length:(unsigned *)length {
    return (char *)[coder decodeBytesWithReturnedLength:length];
}

- (void)handleReleasedProxies:(char *)bytes length:(unsigned)length {
    const unsigned char *cursor = (const unsigned char *)bytes;
    const unsigned char *end;

    if (cursor == NULL || length == 0)
        return;
    end = cursor + length;
    while (end > cursor) {
        unsigned target = NSConnectionDecodeFastInteger(&cursor, end);
        unsigned count = NSConnectionDecodeFastInteger(&cursor, end);

        if (NSConnectionInfoLoggingEnabled)
            NSLog(@"piggybacked [0x%x _releaseWireCount:%u]", target, count);
        [[self getLocal:(id)(unsigned long)target] _releaseWireCount:count];
    }
}

- (void)decodeReleasedProxies:(NSPortCoder *)coder {
    unsigned length = 0;
    char *bytes = [self getReleasedProxies:coder length:&length];

    [self handleReleasedProxies:bytes length:length];
}

- (BOOL)_cleanupAndAuthenticate:(NSPortCoder *)coder
                       sequence:(unsigned)sequence
                    conversation:(id *)conversation
                      invocation:(NSInvocation *)invocation
                           raise:(BOOL)shouldRaise {
    unsigned length = 0;
    char *bytes;

    [coder decodeValueOfObjCType:"@" at:conversation];
    bytes = [self getReleasedProxies:coder length:&length];
    if (!authCheck || [(NSConcretePortCoder *)coder
                          verifyWithDelegate:delegate]) {
        [self handleReleasedProxies:bytes length:length];
        [invocation release];
        return YES;
    }

    if (shouldRaise) {
        NSException *exception = [NSException
            exceptionWithName:NSFailedAuthenticationException
                       reason:@"*** Received message without authentication"
                     userInfo:nil];
        [self returnResult:nil exception:exception sequence:sequence
                   imports:[coder importedObjects]];
    }
    [invocation release];
    return NO;
}

- (void)releaseName:(id)name count:(unsigned)count {
    unsigned target = (unsigned)(unsigned long)name;

    if (_NSConnectionLock != nil)
        [_NSConnectionLock lock];
    if (releasedProxies == nil)
        releasedProxies = [[NSMutableData allocWithZone:NULL] init];
    [releasedProxies serializeDataAt:&target ofObjCType:"I" context:nil];
    [releasedProxies serializeDataAt:&count ofObjCType:"I" context:nil];
    if (_NSConnectionLock != nil)
        [_NSConnectionLock unlock];
}

- (void)sendReleasedProxies {
    Class coderClass = NSClassFromString(@"NSConcretePortCoder");
    NSConcretePortCoder *coder = [[coderClass allocWithZone:NULL]
        initWithConnection:self msgid:238026465];
    NSMutableData *proxies;
    unsigned message = 238026465;

    if (_NSConnectionLock != nil)
        [_NSConnectionLock lock];
    proxies = releasedProxies;
    releasedProxies = nil;
    if (_NSConnectionLock != nil)
        [_NSConnectionLock unlock];

    [coder encodeValueOfObjCType:"i" at:&message];
    [coder encodeBytes:[proxies bytes] length:[proxies length]];
    [proxies release];
    if (encryptFlag)
        [coder encryptWithDelegate:delegate];
    NS_DURING
        [coder sendBeforeTime:(NSTimeInterval)_NSCurrentTime() + replyLimit];
    NS_HANDLER
        (void)localException;
    NS_ENDHANDLER
    [coder invalidate];
    [coder release];
}

- (void)finishEncoding:(NSPortCoder *)coder {
    NSMutableData *proxies;

    if (_NSConnectionLock != nil)
        [_NSConnectionLock lock];
    proxies = releasedProxies;
    releasedProxies = nil;
    if (_NSConnectionLock != nil)
        [_NSConnectionLock unlock];

    [coder encodeBytes:[proxies bytes] length:[proxies length]];
    [proxies release];
    if (authGen)
        [(NSConcretePortCoder *)coder authenticateWithDelegate:delegate];
    if (encryptFlag)
        [(NSConcretePortCoder *)coder encryptWithDelegate:delegate];
}

- (void)returnResult:(NSInvocation *)invocation exception:(NSException *)exception
            sequence:(unsigned)sequence imports:(NSArray *)imports {
    NSConcretePortCoder *coder;
    unsigned message = 238026446;

    if ([[invocation methodSignature] isOneway]) {
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"  handleRequest oneway request: [0x%x '%s'] completed\n",
                  [invocation target], [invocation selector]);
        return;
    }
    coder = [[NSConcretePortCoder allocWithZone:NULL]
        initWithConnection:self msgid:message];
    if (coder == nil)
        [NSException raise:NSDestinationInvalidException
                    format:@"target not reachable"];

    NS_DURING
        [coder encodeValueOfObjCType:"i" at:&message];
        [coder encodeValueOfObjCType:"i" at:&sequence];
        [coder encodeObject:exception];
        if (exception == nil)
            [invocation encodeReturnValueWithCoder:coder];
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"  handleRequest request: [0x%x '%s'] returning, exception %@",
                  [invocation target], [invocation selector], exception);
        [invocation invalidate];
        [imports makeObjectsPerformSelector:@selector(_anticipateRelease)];
        [self finishEncoding:coder];
        [coder sendBeforeTime:(NSTimeInterval)_NSCurrentTime() + replyLimit];
        [coder invalidate];
        [coder release];
        ++((NSDistributedObjectsStatistics *)statistics)->repliesSent;
    NS_HANDLER
        [coder invalidate];
        [coder release];
        [localException raise];
    NS_ENDHANDLER
}

- (NSPortCoder *)getReplyWithSequence:(unsigned)sequence
                           withRunLoop:(NSRunLoop *)runLoop
                              inThread:(NSThread *)thread {
    BOOL hasUnlimitedReplyLimit = replyLimit == 4294967295.0;
    NSDate *deadline = hasUnlimitedReplyLimit
        ? [NSDate distantFuture]
        : [NSDate dateWithTimeIntervalSinceNow:replyLimit];

    for (;;) {
        unsigned pool = NSPushAutoreleasePool();
        void *reply = NULL;
        void *replyKey = NULL;
        NSDate *limitDate;

        if (!isValid)
            [NSException raise:NSInvalidReceivePortException
                        format:@"connection is invalid"];
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"awaiting sequence %u on %d\n", sequence,
                  [(NSPort *)receivePort machPort]);

        limitDate = [runLoop limitDateForMode:NSConnectionReplyMode];
        if (limitDate == nil)
            [NSException raise:NSInvalidReceivePortException
                        format:@"nothing to listen to for reply message"];

        if (_NSConnectionReplyTableLock != nil)
            [_NSConnectionReplyTableLock lock];
        if (NSMapMember(reply_table, (void *)(unsigned long)sequence,
                        &replyKey, &reply) && reply != thread && reply != NULL) {
            [reply retain];
            if (NSConnectionLoggingDepth != 0)
                NSLog(@"%@: Deleting sequence %d in extractSequence",
                      thread, sequence);
            NSMapRemove(reply_table, (void *)(unsigned long)sequence);
        } else {
            reply = NULL;
        }
        if (_NSConnectionReplyTableLock != nil)
            [_NSConnectionReplyTableLock unlock];
        if (reply != NULL) {
            NSPopAutoreleasePool(pool);
            break;
        }

        if (!hasUnlimitedReplyLimit
            && [deadline timeIntervalSinceReferenceDate]
            < [limitDate timeIntervalSinceReferenceDate])
            limitDate = deadline;
        [runLoop acceptInputForMode:NSConnectionReplyMode beforeDate:limitDate];

        replyKey = NULL;
        reply = NULL;
        if (_NSConnectionReplyTableLock != nil)
            [_NSConnectionReplyTableLock lock];
        if (NSMapMember(reply_table, (void *)(unsigned long)sequence,
                        &replyKey, &reply) && reply != thread && reply != NULL) {
            [reply retain];
            if (NSConnectionLoggingDepth != 0)
                NSLog(@"%@: Deleting sequence %d in extractSequence",
                      thread, sequence);
            NSMapRemove(reply_table, (void *)(unsigned long)sequence);
        } else {
            reply = NULL;
        }
        if (_NSConnectionReplyTableLock != nil)
            [_NSConnectionReplyTableLock unlock];

        NSPopAutoreleasePool(pool);
        if (reply != NULL)
            break;
        if ([deadline timeIntervalSinceNow] <= 0.0)
            [NSException raise:NSPortTimeoutException
                        format:@"connection timeout: did not receive reply"];
    }

    ++((NSDistributedObjectsStatistics *)statistics)->repliesReceived;
    if (NSConnectionLoggingDepth != 0)
        NSLog(@"got reply sequence %u in %x\n", sequence, reply);
    return (NSPortCoder *)reply;
}

- (void)sendInvocation:(NSInvocation *)invocation target:(id)target {
    NSThread *conversationThread = [NSThread currentThread];
    BOOL oneWay = [[invocation methodSignature] isOneway];
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    NSThread *thread = [NSThread currentThread];
    NSConcretePortCoder *coder = nil;
    unsigned message = 236977901;
    unsigned sequence;
    id conversation = nil;
    BOOL addedConversation = NO;
    BOOL temporaryReplyMode = NO;
    NSPortCoder *replyCoder = nil;
    NSException *remoteException = nil;

    if (NSConnectionLoggingDepth != 0)
        NSLog(@"entered sendInvocation [0x%x %@...]", target,
              [invocation methodSignature]);
    if (!isValid)
        [NSException raise:NSInvalidReceivePortException
                    format:@"connection is invalid"];
    coder = [[NSConcretePortCoder allocWithZone:NULL]
        initWithConnection:self msgid:236977901];
    if (coder == nil)
        [NSException raise:NSDestinationInvalidException
                    format:@"target not reachable"];
    [coder encodeValueOfObjCType:"i" at:&message];
    if (_NSConnectionLock != nil)
        [_NSConnectionLock lock];
    sequence = ++connectionSequence;
    if (_NSConnectionLock != nil)
        [_NSConnectionLock unlock];
    [coder encodeValueOfObjCType:"i" at:&sequence];
    [coder encodeValueOfObjCType:"@" at:&invocation];

    if (!oneWay) {
        conversation = [conversationThread lastConversation];
        if (conversation != nil) {
            [conversationThread addConversation:conversation];
            addedConversation = YES;
        } else if (isQueueing) {
            conversation = [self newConversation];
            [conversationThread addConversation:conversation];
            addedConversation = conversation != nil;
            [conversation release];
        }
    }
    NS_DURING
        [coder encodeValueOfObjCType:"@" at:&conversation];
        [self finishEncoding:coder];

        if (!oneWay) {
            void *existing;

            if (_NSConnectionReplyTableLock != nil)
                [_NSConnectionReplyTableLock lock];
            existing = NSMapInsertIfAbsent(reply_table,
                (void *)(unsigned long)sequence, thread);
            if (_NSConnectionReplyTableLock != nil)
                [_NSConnectionReplyTableLock unlock];
            if (existing != NULL)
                [NSException raise:NSInternalInconsistencyException
                            format:@"duplicate entry, seq # %u\n", sequence];
        }

        [coder sendBeforeTime:(NSTimeInterval)_NSCurrentTime() + requestLimit];
        [coder invalidate];
        [coder release];
        coder = nil;
        ++((NSDistributedObjectsStatistics *)statistics)->requestsSent;

        if (!oneWay) {
            if (rootObject == nil
                && NSCountHashTable((NSHashTable *)localProxies) == 0) {
                [(NSPort *)receivePort addConnection:self toRunLoop:runLoop
                                             forMode:NSConnectionReplyMode];
                temporaryReplyMode = YES;
            }
            replyCoder = [self getReplyWithSequence:sequence
                withRunLoop:runLoop inThread:thread];
            if (temporaryReplyMode)
                [(NSPort *)receivePort removeConnection:self fromRunLoop:runLoop
                                                forMode:NSConnectionReplyMode];
            remoteException = [replyCoder decodeObject];
            if (remoteException == nil)
                [invocation decodeReturnValueWithCoder:replyCoder];
            {
                unsigned length = 0;
                const void *bytes =
                    [replyCoder decodeBytesWithReturnedLength:&length];

                if (!authCheck || [(NSConcretePortCoder *)replyCoder
                                      verifyWithDelegate:delegate])
                    NSConnectionHandleReleasedProxyBytes(self, bytes, length);
                else
                    remoteException = [NSException
                        exceptionWithName:NSFailedAuthenticationException
                        reason:@"*** handleRequest: received message without authentication"
                        userInfo:nil];
            }
            [replyCoder invalidate];
            [replyCoder release];
            replyCoder = nil;
        }
    NS_HANDLER
        if (NSConnectionLoggingDepth != 0) {
            NSThread *loggingThread = [NSThread currentThread];
            NSLog(@"%@: raised in sendInvocation for sequence %d, exception is %@",
                  loggingThread, sequence, localException);
        }
        if (temporaryReplyMode)
            [(NSPort *)receivePort removeConnection:self fromRunLoop:runLoop
                                            forMode:NSConnectionReplyMode];
        if (!oneWay) {
            if (_NSConnectionReplyTableLock != nil)
                [_NSConnectionReplyTableLock lock];
            if (NSConnectionLoggingDepth != 0) {
                NSThread *loggingThread = [NSThread currentThread];
                NSLog(@"%@: Deleting sequence %d in extractSequence",
                      loggingThread, sequence);
            }
            NSMapRemove(reply_table, (void *)(unsigned long)sequence);
            if (_NSConnectionReplyTableLock != nil)
                [_NSConnectionReplyTableLock unlock];
        }
        if (addedConversation)
            [conversationThread removeConversation];
        if ([[localException name] isEqualToString:NSInvalidSendPortException])
            [(NSPort *)sendPort invalidate];
        [localException raise];
    NS_ENDHANDLER

    if (addedConversation)
        [conversationThread removeConversation];
    if (NSConnectionLoggingDepth != 0)
        NSLog(@"exiting sendInvocation - [%x (name %x) %s...] conn:%x exception: %@",
              self, target, [invocation selector], self, remoteException);
    if (remoteException != nil) {
        [remoteException retain];
        [remoteException autorelease];
        [remoteException raise];
    }
}

- (void)handleRequest:(NSPortCoder *)coder sequence:(unsigned)sequence {
    NSInvocation *invocation = nil;
    id conversation = nil;
    NSMethodSignature *signature;
    NSException *exception = nil;
    BOOL canDispatch = NO;

    ++((NSDistributedObjectsStatistics *)statistics)->requestsReceived;
    [coder decodeValueOfObjCType:"@" at:&invocation];
    signature = [invocation methodSignature];

    if (![invocation _signatureValid]) {
        if (![signature isOneway]) {
            if ([invocation target] != nil)
                exception = [NSException exceptionWithName:NSInvalidArgumentException
                    reason:@"*** Object does not implement or has different method signature"
                    userInfo:nil];
            else
                exception = [NSException exceptionWithName:NSInvalidArgumentException
                    reason:@"*** Invocation contained nil target" userInfo:nil];
            [self returnResult:nil exception:exception sequence:sequence
                       imports:[coder importedObjects]];
        }
        [self _cleanupAndAuthenticate:coder sequence:sequence
            conversation:&conversation invocation:invocation raise:NO];
        return;
    }

    {
        id target = [invocation target];

        if (target == nil
            || ([self _objectWithName:target] == nil
                && (![NSObject isAncestorOfObject:target] || self != [target target]))) {
            if (![signature isOneway]) {
                exception = [NSException exceptionWithName:NSObjectNotAvailableException
                    reason:@"*** Object not exported" userInfo:nil];
                [self returnResult:nil exception:exception sequence:sequence
                           imports:[coder importedObjects]];
            }
            [self _cleanupAndAuthenticate:coder sequence:sequence
                conversation:&conversation invocation:invocation raise:NO];
            return;
        }

        if ([invocation selector] == NULL) {
            if (![signature isOneway]) {
                NSString *reason = [NSString stringWithFormat:
                    @"*** handleRequest: received message for %x with no selector",
                    (unsigned)(unsigned long)target];
                exception = [NSException exceptionWithName:NSInvalidArgumentException
                    reason:reason userInfo:nil];
                [self returnResult:nil exception:exception sequence:sequence
                           imports:[coder importedObjects]];
            }
            [self _cleanupAndAuthenticate:coder sequence:sequence
                conversation:&conversation invocation:invocation raise:NO];
            return;
        }
    }

    if (![self _cleanupAndAuthenticate:coder sequence:sequence
        conversation:&conversation invocation:nil raise:YES]) {
        [invocation release];
        return;
    }

    canDispatch = [self _shouldDispatch:&conversation invocation:invocation
        sequence:sequence coder:coder];
    [conversation release];
    if (!canDispatch)
        return;

    if (doRequest) {
        NSConcreteDistantObjectRequest *request =
            [[NSConcreteDistantObjectRequest allocWithZone:NULL]
                initWithInvocation:invocation conversation:conversation
                sequence:sequence importedObjects:(NSMutableArray *)[coder importedObjects]
                connection:self];
        BOOL handled = [delegate connection:self handleRequest:request];

        [request release];
        if (handled) {
            [invocation release];
            if (conversation != nil)
                [_NSCurrentThread() removeConversation];
            return;
        }
    }

    if (exception == nil)
        exception = [self dispatchInvocation:invocation];
    if (conversation != nil)
        [_NSCurrentThread() removeConversation];
    [self returnResult:invocation exception:exception sequence:sequence
               imports:[coder importedObjects]];
    [invocation release];
}

- (BOOL)_shouldDispatch:(id *)conversation invocation:(NSInvocation *)invocation
               sequence:(unsigned)sequence coder:(NSPortCoder *)coder {
    NSThread *thread = _NSCurrentThread();
    id currentConversation = [thread lastConversation];
    NSThread *conversationThread;

    if (currentConversation == nil && *conversation == nil) {
        if (!isQueueing)
            return YES;
        *conversation = [self newConversation];
        [thread addConversation:*conversation];
        return YES;
    }
    if (*conversation == nil) {
        if (currentConversation != nil) {
            if (isQueueing) {
                *conversation = [self newConversation];
                if (NSConnectionLoggingDepth != 0)
                    NSLog(@"Creating new conversation %x but queueing in deference to %x",
                          *conversation, currentConversation);
            } else if (NSConnectionLoggingDepth != 0) {
                NSLog(@"Queueing without conversation in deference to %x",
                      currentConversation);
            }
            [self _queueRequestForThread:thread invocation:invocation
                conversation:*conversation sequence:sequence coder:coder];
            return NO;
        } else {
            *conversation = [self newConversation];
            if (NSConnectionLoggingDepth != 0)
                NSLog(@"Starting new conversation %x for request without conversation",
                      *conversation);
            [thread addConversation:*conversation];
            return YES;
        }
    }

    if (*conversation == currentConversation) {
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"Continuing conversation %x", *conversation);
        [thread addConversation:*conversation];
        return YES;
    }

    conversationThread = [NSThread mapConversationToThread:*conversation];
    if (conversationThread != nil) {
        [self _queueRequestForThread:conversationThread invocation:invocation
            conversation:*conversation sequence:sequence coder:coder];
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"Queueing conversation %x for %@", *conversation,
                  conversationThread);
        return NO;
    }
    if (currentConversation != nil) {
        if (NSConnectionLoggingDepth != 0)
            NSLog(@"Queueing conversation %x in deference to %x",
                  *conversation, currentConversation);
        [self _queueRequestForThread:thread invocation:invocation
            conversation:*conversation sequence:sequence coder:coder];
        return NO;
    }
    if (NSConnectionLoggingDepth != 0)
        NSLog(@"Handling request conversation %x", *conversation);
    [thread addConversation:*conversation];
    return YES;
}

- (void)_queueRequestForThread:(NSThread *)thread invocation:(NSInvocation *)invocation
                  conversation:(id)conversation sequence:(unsigned)sequence
                         coder:(NSPortCoder *)coder {
    NSConcreteDistantObjectRequest *request =
        [[NSConcreteDistantObjectRequest allocWithZone:NULL]
            initWithInvocation:invocation conversation:conversation sequence:sequence
            importedObjects:(NSMutableArray *)[coder importedObjects] connection:self];

    if (_NSConnectionWorkQueueLock != nil)
        [_NSConnectionWorkQueueLock lock];
    if (thread == [NSThread currentThread]) {
        [[thread workQueue] insertObject:request atIndex:0];
    } else {
        [thread setConversationRequest:request];
        [[thread runLoop] _wakeup];
    }
    if (_NSConnectionWorkQueueLock != nil)
        [_NSConnectionWorkQueueLock unlock];
    [request release];
    [invocation release];
}

+ (void)doQueuedWork {
    NSThread *thread = [NSThread currentThread];
    NSConcreteDistantObjectRequest *request;
    NSMutableArray *queue;

    if ([thread lastConversation] != nil) {
        request = [thread conversationRequest];
        if (request != nil) {
            [request retain];
            if (_NSConnectionWorkQueueLock != nil)
                [_NSConnectionWorkQueueLock lock];
            [thread clearConversationRequest];
            if (_NSConnectionWorkQueueLock != nil)
                [_NSConnectionWorkQueueLock unlock];
            NSConnectionHandleQueuedRequest(request, thread);
        }
        return;
    }

    if (_NSConnectionWorkQueueLock != nil)
        [_NSConnectionWorkQueueLock lock];
    queue = (NSMutableArray *)
        ((struct NSThreadRequestQueueLayout *)thread)->doQueue;
    if (_NSConnectionWorkQueueLock != nil)
        [_NSConnectionWorkQueueLock unlock];
    while ([queue count] != 0) {
        if (_NSConnectionWorkQueueLock != nil)
            [_NSConnectionWorkQueueLock lock];
        request = [[queue objectAtIndex:0] retain];
        if (request != nil)
            [queue removeObjectAtIndex:0];
        if (_NSConnectionWorkQueueLock != nil)
            [_NSConnectionWorkQueueLock unlock];
        if (request != nil) {
            if (NSConnectionLoggingDepth != 0)
                NSLog(@"dispatching a queued conversation %x",
                      request->conversation);
            NSConnectionHandleQueuedRequest(request, thread);
        }
    }
}

+ (NSConnection *)connectionWithReceivePort:(NSPort *)receivePort
                                    sendPort:(NSPort *)sendPort {
    struct NSConnectionTableKey key;
    NSConnection *connection;

    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock lock];
    key.receivePort = receivePort;
    key.sendPort = sendPort;
    connection = (NSConnection *)NSHashGet(conn_table, &key);
    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock unlock];
    if (connection != nil)
        return connection;
    return [[[self allocWithZone:NULL]
        initWithReceivePort:receivePort sendPort:sendPort] autorelease];
}

- (id)initWithReceivePort:(NSPort *)newReceivePort
                 sendPort:(NSPort *)newSendPort {
    struct NSConnectionTableKey key;
    NSHashTableCallBacks proxyCallbacks = {
        NSConnectionHashProxy, NSConnectionEqualProxy, NULL, NULL, NULL
    };
    NSConnection *existing;
    NSConnection *parent;
    BOOL allowConnection = YES;
    unsigned index;
    unsigned runLoopCount;

    if (newReceivePort == nil) {
        [self dealloc];
        return nil;
    }
    if (newSendPort == nil)
        newSendPort = newReceivePort;

    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock lock];
    key.receivePort = newReceivePort;
    key.sendPort = newSendPort;
    existing = (NSConnection *)NSHashGet(conn_table, &key);
    if (existing != nil) {
        if (_NSConnectionTableLock != nil)
            [_NSConnectionTableLock unlock];
        [self dealloc];
        return [existing retain];
    }

    key.sendPort = newReceivePort;
    parent = (NSConnection *)NSHashGet(conn_table, &key);
    receivePort = [newReceivePort retain];
    sendPort = [newSendPort retain];
    localProxies = NSCreateHashTableWithZone(proxyCallbacks, 8, NULL);
    remoteProxies = NSCreateHashTableWithZone(proxyCallbacks, 8, NULL);
    statistics = [[NSDistributedObjectsStatistics allocWithZone:NULL] init];
    requestModes = [[NSMutableArray allocWithZone:NULL] init];
    isValid = YES;
    NSHashInsert(conn_table, self);
    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock unlock];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(portalDied:)
                                                  name:NSPortDidBecomeInvalidNotification
                                                object:receivePort];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(portalDied:)
                                                  name:NSPortDidBecomeInvalidNotification
                                                object:sendPort];

    if (parent != nil) {
        if (parent->rootObject != nil)
            [self setRootObject:parent->rootObject];
        if (parent->delegate != nil)
            [self setDelegate:parent->delegate];
        if (_NSConnectionModesLock != nil)
            [_NSConnectionModesLock lock];
        [requestModes addObjectsFromArray:parent->requestModes];
        runLoopCount = [parent->runLoops count];
        for (index = 0; index < runLoopCount; index++)
            [self addRunLoop:[parent->runLoops objectAtIndex:index]];
        if (_NSConnectionModesLock != nil)
            [_NSConnectionModesLock unlock];
        replyLimit = parent->replyLimit;
        requestLimit = parent->requestLimit;
        isQueueing = parent->isQueueing;
        isMulti = parent->isMulti;
    } else {
        [requestModes addObject:NSDefaultRunLoopMode];
        [self addRunLoop:[NSRunLoop currentRunLoop]];
        replyLimit = 4294967295.0;
        requestLimit = 4294967295.0;
    }

    if (delegate != nil) {
        if ([delegate respondsToSelector:@selector(connection:shouldMakeNewConnection:)])
            allowConnection = [delegate connection:parent shouldMakeNewConnection:self];
        else if ([delegate respondsToSelector:@selector(makeNewConnection:sender:)])
            allowConnection = [delegate makeNewConnection:self sender:parent];
    }
    if (!allowConnection) {
        if (_NSConnectionTableLock != nil)
            [_NSConnectionTableLock lock];
        NSHashRemove(conn_table, self);
        if (_NSConnectionTableLock != nil)
            [_NSConnectionTableLock unlock];
        [self release];
        return nil;
    }

    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSConnectionDidInitializeNotification
                      object:self userInfo:nil];
    if (isValid)
    {
        if (NSConnectionLoggingDepth != 0) {
            unsigned receiveMachPort;
            unsigned sendMachPort;

#if defined(__ppc__) || defined(__POWERPC__)
            receiveMachPort = [receivePort machPort];
            sendMachPort = [sendPort machPort];
#else
            sendMachPort = [sendPort machPort];
            receiveMachPort = [receivePort machPort];
#endif
            NSLog(@"adding conn %x with receivePorts %x (%d) sendPort %x (%d) root %x\n",
                  self, receivePort, receiveMachPort,
                  sendPort, sendMachPort, rootObject);
        }
        return self;
    }
    [self release];
    return nil;
}

- (NSDistantObject *)getRemote:(id)target {
    struct NSConnectionDistantObjectLayout key;
    NSDistantObject *proxy;

    key.name = target;
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock lock];
    proxy = (NSDistantObject *)NSHashGet((NSHashTable *)remoteProxies, &key);
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock unlock];
    return proxy;
}

- (NSDistantObject *)getLocal:(id)target {
    struct NSConnectionDistantObjectLayout key;
    NSDistantObject *proxy;

    key.name = target;
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock lock];
    proxy = (NSDistantObject *)NSHashGet((NSHashTable *)localProxies, &key);
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock unlock];
    return proxy;
}

- (NSDistantObject *)insertProxy:(NSDistantObject *)proxy {
    struct NSConnectionDistantObjectLayout *layout =
        (struct NSConnectionDistantObjectLayout *)proxy;
    NSHashTable *table;
    NSDistantObject *existing;
    BOOL hadLocalObjects;
    BOOL hasLocalObjects;

    if (!isValid)
        return nil;

    if (layout->wire == 1)
        table = (NSHashTable *)remoteProxies;
    else if (layout->wire == 0)
        table = (NSHashTable *)localProxies;
    else {
        [NSException raise:NSInternalInconsistencyException
                    format:@"entering bad NSDistantObject: %x %d\n",
                           (unsigned)proxy, layout->wire];
        return nil;
    }

    if (layout->connection != self) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"entering proxy with conn %x to %x\n",
                           (unsigned)layout->connection, (unsigned)self];
        return nil;
    }
    if (layout->wire == 0
        && *(Class *)layout->name == [NSDistantObject class]) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"entering local proxy with proxy target!"];
        return nil;
    }

    hadLocalObjects = rootObject != nil
        || NSCountHashTable((NSHashTable *)localProxies) != 0;
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock lock];
    existing = (NSDistantObject *)NSHashInsertIfAbsent(table, proxy);
    if (existing != nil) {
        if (_NSConnectionHashTableLock != nil)
            [_NSConnectionHashTableLock unlock];
        return existing;
    }
    hasLocalObjects = rootObject != nil
        || NSCountHashTable((NSHashTable *)localProxies) != 0;
    if (!hadLocalObjects && hasLocalObjects)
        [self addPortsToAllRunLoops];
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock unlock];
    if (NSConnectionLoggingDepth != 0)
        NSLog(@"new %s %s %x for %x on conn %x\n",
              layout->wire == 1 ? "isRemote" : "isLocal",
              proxy->isa->name, (unsigned)proxy, (unsigned)layout->name,
              (unsigned)self);
    return proxy;
}

- (void)addPortsToAllRunLoops {
    unsigned index;
    unsigned count = [runLoops count];

    for (index = 0; index < count; index++)
        [self addPortsToRunLoop:[runLoops objectAtIndex:index]];
}

- (void)addPortsToRunLoop:(NSRunLoop *)runLoop {
    unsigned count;
    unsigned index;

    [(NSPort *)receivePort addConnection:self toRunLoop:runLoop
                                 forMode:NSConnectionReplyMode];
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    count = [requestModes count];
    for (index = count; index > 0; index--) {
        NSString *mode = [requestModes objectAtIndex:index - 1];
        [(NSPort *)receivePort addConnection:self toRunLoop:runLoop forMode:mode];
    }
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
}

- (NSDictionary *)statistics {
    return statistics;
}

- (NSArray *)remoteObjects {
    NSArray *objects;

    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock lock];
    objects = NSAllHashTableObjects((NSHashTable *)remoteProxies);
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock unlock];
    return objects;
}

- (NSArray *)localObjects {
    NSMutableArray *objects = [NSMutableArray array];
    NSHashEnumerator enumerator;
    NSDistantObject *proxy;

    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock lock];
    enumerator = NSEnumerateHashTable((NSHashTable *)localProxies);
    while ((proxy = (NSDistantObject *)NSNextHashEnumeratorItem(&enumerator)) != nil)
        [objects addObject:((struct NSConnectionDistantObjectLayout *)proxy)->name];
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock unlock];
    return objects;
}

- (NSArray *)localProxies {
    NSArray *proxies;

    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock lock];
    proxies = NSAllHashTableObjects((NSHashTable *)localProxies);
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock unlock];
    return proxies;
}

- (void)removePortsFromAllRunLoops {
    unsigned index;
    unsigned count = [runLoops count];

    for (index = 0; index < count; index++)
        [self removePortsFromRunLoop:[runLoops objectAtIndex:index]];
}

- (void)removePortsFromRunLoop:(NSRunLoop *)runLoop {
    unsigned count;
    unsigned index;

    [(NSPort *)receivePort removeConnection:self fromRunLoop:runLoop
                                    forMode:NSConnectionReplyMode];
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    count = [requestModes count];
    for (index = count; index > 0; index--)
        [(NSPort *)receivePort removeConnection:self fromRunLoop:runLoop
                                        forMode:[requestModes objectAtIndex:index - 1]];
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
}

- (void)removeProxy:(NSDistantObject *)proxy {
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock lock];
    NSHashRemove((NSHashTable *)remoteProxies, proxy);
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock unlock];
    ((struct NSConnectionDistantObjectLayout *)proxy)->wire = 3;
}

- (void)removeLocal:(NSDistantObject *)proxy {
    BOOL hadLocalObjects = rootObject != nil
        || NSCountHashTable((NSHashTable *)localProxies) != 0;
    BOOL hasLocalObjects;

    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock lock];
    NSHashRemove((NSHashTable *)localProxies, proxy);
    hasLocalObjects = rootObject != nil
        || NSCountHashTable((NSHashTable *)localProxies) != 0;
    if (hadLocalObjects && !hasLocalObjects)
        [self removePortsFromAllRunLoops];
    if (_NSConnectionHashTableLock != nil)
        [_NSConnectionHashTableLock unlock];
    ((struct NSConnectionDistantObjectLayout *)proxy)->wire = 3;
}

- (id)proxyForObject:(id)object {
    struct NSConnectionDistantObjectLayout *proxyLayout;
    NSConnection *proxyConnection;

    if (![NSDistantObject isAncestorOfObject:object])
        return [NSDistantObject proxyWithLocal:object connection:self];
    proxyConnection = [(NSDistantObject *)object connectionForProxy];
    if (proxyConnection == self)
        return object;
    if (sendPort == [proxyConnection sendPort]) {
        proxyLayout = (struct NSConnectionDistantObjectLayout *)object;
        return [NSDistantObject proxyWithTarget:proxyLayout->name connection:self];
    }
    return nil;
}

- (id)proxyWithLocal:(id)object {
    NSConnection *connection;
    NSConnection *candidate = nil;
    NSDistantObject *proxy = nil;
    NSHashEnumerator enumerator;

    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock lock];
    enumerator = NSEnumerateHashTable(conn_table);
    while ((connection = (NSConnection *)NSNextHashEnumeratorItem(&enumerator)) != nil) {
        if ([receivePort isEqual:[connection receivePort]]) {
            proxy = [connection getLocal:object];
            if (proxy != nil) {
                candidate = connection;
                break;
            }
        }
    }
    if (proxy != nil && candidate != self) {
        struct NSConnectionDistantObjectLayout *proxyLayout =
            (struct NSConnectionDistantObjectLayout *)proxy;
        proxy = [NSDistantObject proxyWithLocal:proxyLayout->name connection:self];
    }
    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock unlock];
    return proxy;
}

- (id)_objectWithName:(id)object {
    if (object == nil)
        return [NSProtocolChecker protocolCheckerWithTarget:self
                                                    protocol:@protocol(NSConnectionProtocol)];
    if (rootObject == object || [self getLocal:object] != nil
        || [self proxyWithLocal:object] != nil)
        return object;
    return nil;
}

- (id)newConversation {
    if ([delegate respondsToSelector:@selector(createConversationForConnection:)])
        return [delegate createConversationForConnection:self];
    return NSAllocateObject([NSObject class], 0, NULL);
}

- (BOOL)hasRunLoop:(NSRunLoop *)runLoop {
    BOOL contains;

    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    contains = [self->runLoops containsObjectIdenticalTo:runLoop];
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
    return contains;
}

- (NSDate *)requestLimit {
    return [NSDate dateWithTimeIntervalSinceNow:requestLimit];
}

- (void)portalDied:(NSNotification *)notification {
    if (NSConnectionLoggingDepth != 0) {
        id loggedPort;
        unsigned machPort;

#if defined(__ppc__) || defined(__POWERPC__)
        loggedPort = [notification object];
        machPort = [[notification object] machPort];
#else
        id port = [notification object];
        machPort = [port machPort];
        loggedPort = [notification object];
#endif
        NSLog(@"NSConnection: %x death notification for port %x (%d)\n",
              (unsigned)self, (unsigned)loggedPort, machPort);
    }
    if (isValid)
        [self invalidate];
}

- (void)dealloc {
    if (NSConnectionLoggingDepth != 0)
        NSLog(@"deallocing Connection %x\n", self);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (remoteProxies != NULL) {
        if (NSCountHashTable((NSHashTable *)remoteProxies) != 0)
            NSLog(@"XXX connection %x still has %d remote proxies", self,
                  (int)NSCountHashTable((NSHashTable *)remoteProxies));
        NSFreeHashTable((NSHashTable *)remoteProxies);
    }
    if (localProxies != NULL) {
        if (NSCountHashTable((NSHashTable *)localProxies) != 0)
            NSLog(@"XXX connection %x still has %d local proxies", self,
                  (int)NSCountHashTable((NSHashTable *)localProxies));
        NSFreeHashTable((NSHashTable *)localProxies);
    }
    remoteProxies = NULL;
    localProxies = NULL;
    if (registerName != nil)
        [[NSPortNameServer defaultPortNameServer] removePortForName:registerName];
    [registerName release];
    [receivePort release];
    [sendPort release];
    [rootObject release];
    [requestModes release];
    [runLoops release];
    [statistics release];
    if (classInfoImported != NULL)
        NSFreeMapTable(classInfoImported);
    if (classInfoExported != NULL)
        NSFreeHashTable(classInfoExported);
    [super dealloc];
}

+ (NSArray *)allConnections {
    NSArray *connections;

    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock lock];
    connections = NSAllHashTableObjects(conn_table);
    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock unlock];
    return connections;
}

+ (NSUInteger)connectionsCount {
    NSUInteger count;

    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock lock];
    count = NSCountHashTable(conn_table);
    if (_NSConnectionTableLock != nil)
        [_NSConnectionTableLock unlock];
    return count;
}

+ (NSDictionary *)statistics {
    NSArray *connections = [self allConnections];
    unsigned index = [connections count];

    while (index > 0) {
        NSDictionary *connectionStatistics =
            [[connections objectAtIndex:--index] statistics];
        if (connectionStatistics != nil)
            return [[connectionStatistics copyWithZone:NULL] autorelease];
    }
    return nil;
}

+ (NSConnection *)defaultConnection {
    NSMutableDictionary *threadDictionary = [_NSCurrentThread() threadDictionary];
    NSConnection *connection = [threadDictionary objectForKey:@"defaultConnection"];

    if (connection == nil) {
        NSPort *port = [NSPort port];
        connection = [self connectionWithReceivePort:port sendPort:port];
        [threadDictionary setObject:connection forKey:@"defaultConnection"];
    }
    return connection;
}

+ (NSConnection *)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName {
    NSPort *sendPort = [[NSPortNameServer defaultPortNameServer]
        portForName:name host:hostName];
    NSConnection *connection;

    if (sendPort == nil)
        return nil;
    connection = [self defaultConnection];
    return [self connectionWithReceivePort:[connection receivePort]
                                  sendPort:sendPort];
}

+ (NSDistantObject *)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName {
    return [[self connectionWithRegisteredName:name host:hostName] rootProxy];
}

- (void)setRequestTimeout:(NSTimeInterval)ti {
    requestLimit = ti;
}

- (NSTimeInterval)requestTimeout {
    return requestLimit;
}

- (void)setReplyTimeout:(NSTimeInterval)ti {
    replyLimit = ti;
}

- (NSTimeInterval)replyTimeout {
    return replyLimit;
}

- (void)setRootObject:(id)anObject {
    BOOL hadLocalObjects = rootObject != nil
        || NSCountHashTable((NSHashTable *)localProxies) != 0;
    BOOL hasLocalObjects;

    if (NSConnectionLoggingDepth != 0)
        NSLog(@"setting root %x on connection %x\n", anObject, self);
    [anObject retain];
    [rootObject release];
    rootObject = anObject;
    hasLocalObjects = rootObject != nil
        || NSCountHashTable((NSHashTable *)localProxies) != 0;
    if (hadLocalObjects && !hasLocalObjects)
        [self removePortsFromAllRunLoops];
    else if (!hadLocalObjects && hasLocalObjects)
        [self addPortsToAllRunLoops];
}

- (id)rootObject {
    return rootObject;
}

- (NSDistantObject *)rootProxy {
    NSDistantObject *proxy = [NSDistantObject proxyWithTarget:nil connection:self];

    [proxy setProtocolForProxy:@protocol(NSConnectionProtocol)];
    return (NSDistantObject *)[(id<NSConnectionProtocol>)proxy rootObject];
}

- (void)setDelegate:(id)anObject {
    delegate = anObject;
    authGen = [delegate respondsToSelector:@selector(authenticationDataForComponents:)];
    authCheck = [delegate respondsToSelector:@selector(authenticateComponents:withData:)];
    decryptFlag = [delegate respondsToSelector:@selector(decryptComponents:)];
    encryptFlag = [delegate respondsToSelector:@selector(encryptComponents:)];
    doRequest = [delegate respondsToSelector:@selector(connection:handleRequest:)];
}

- (id)delegate {
    return delegate;
}

- (void)setIndependentConversationQueueing:(BOOL)yorn {
    isQueueing = yorn;
}

- (BOOL)independentConversationQueueing {
    return isQueueing;
}

- (BOOL)isValid {
    return isValid;
}

- (NSString *)description {
    NSMutableString *description;
    NSString *objectsDescription;
    NSArray *objects;
    unsigned count;
    NSUInteger descriptionLength;

    if (!isValid)
        return [NSString stringWithFormat:@"connection 0x%x is invalid",
                  (unsigned)self];

    description = [[NSMutableString allocWithZone:NULL] init];
    [description appendFormat:
        @"(**NSConnection receivePort %@ sendPort %@ refCount %d\n",
        receivePort, sendPort, (int)[self retainCount]];

    objects = [self remoteObjects];
    count = NSCountHashTable((NSHashTable *)remoteProxies);
    [description appendFormat:@"%d remote ids\n", (int)count];
#if defined(__ppc__) || defined(__POWERPC__)
    descriptionLength = [description length];
    objectsDescription = [objects description];
#else
    objectsDescription = [objects description];
    descriptionLength = [description length];
#endif
    [description replaceCharactersInRange:NSMakeRange(descriptionLength, 0)
                                withString:objectsDescription];

    objects = [self localObjects];
    count = NSCountHashTable((NSHashTable *)localProxies);
    [description appendFormat:@"\n%d local ids\n", (int)count];
#if defined(__ppc__) || defined(__POWERPC__)
    descriptionLength = [description length];
    objectsDescription = [objects description];
#else
    objectsDescription = [objects description];
    descriptionLength = [description length];
#endif
    [description replaceCharactersInRange:NSMakeRange(descriptionLength, 0)
                                withString:objectsDescription];
    [description replaceCharactersInRange:NSMakeRange([description length], 0)
                                withString:@"\n**)\n"];
    return description;
}

- (void)invalidate {
    NSArray *remoteObjects;
    NSArray *localProxies;

    if (!isValid)
        return;
    isValid = NO;
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    while ([runLoops count] != 0)
        [self removeRunLoop:[runLoops lastObject]];
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];

    remoteObjects = [self remoteObjects];
    localProxies = [self localProxies];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSConnectionDidDieNotification object:self userInfo:nil];
    [localProxies makeObjectsPerformSelector:@selector(invalidateProxy)];
    [remoteObjects makeObjectsPerformSelector:@selector(invalidateProxy)];
}

- (void)addRequestMode:(NSString *)rmode {
    unsigned index;
    unsigned count;

    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    count = [runLoops count];
    [requestModes addObject:rmode];
    for (index = 0; index < count; index++) {
#if defined(__ppc__) || defined(__POWERPC__)
        [(NSPort *)receivePort addConnection:self toRunLoop:[runLoops objectAtIndex:index]
                                     forMode:rmode];
#else
        objc_msgSend((id)receivePort,
            @selector(addConnection:toRunLoop:forMode:), self,
            [runLoops objectAtIndex:index]);
#endif
    }
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
}

- (void)removeRequestMode:(NSString *)rmode {
    unsigned index;
    unsigned count;

    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    count = [runLoops count];
    [requestModes removeObject:rmode];
    for (index = 0; index < count; index++) {
#if defined(__ppc__) || defined(__POWERPC__)
        [(NSPort *)receivePort removeConnection:self fromRunLoop:[runLoops objectAtIndex:index]
                                        forMode:rmode];
#else
        objc_msgSend((id)receivePort,
            @selector(removeConnection:fromRunLoop:forMode:), self,
            [runLoops objectAtIndex:index]);
#endif
    }
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
}

- (void)removeAllRequestModes {
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    while ([requestModes count] != 0)
        [self removeRequestMode:[requestModes lastObject]];
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
}

- (id)dispatchInvocation:(NSInvocation *)invocationToDispatch {
    SEL selector = [invocationToDispatch selector];
    NSException *exception = nil;

    if (NSConnectionLoggingDepth != 0) {
        id logTarget;
        SEL logSelector;

#if defined(__ppc__) || defined(__POWERPC__)
        logTarget = [invocationToDispatch target];
        logSelector = [invocationToDispatch selector];
#else
        logSelector = [invocationToDispatch selector];
        logTarget = [invocationToDispatch target];
#endif
        NSLog(@"dispatchInvocation: [0x%x '%s']\n",
              logTarget, logSelector);
    }

    NS_DURING
        if (selector == @selector(release)) {
            [NSException raise:NSInternalInconsistencyException
                        format:@"a release came over the wire"];
        } else {
            [invocationToDispatch invoke];
            if (selector == @selector(copy) || selector == @selector(copyWithZone:)
                || selector == @selector(mutableCopy)
                || selector == @selector(mutableCopyWithZone:)) {
                id result = nil;
                [invocationToDispatch getReturnValue:&result];
                [result autorelease];
            }
        }
    NS_HANDLER
        exception = localException;
        if (NSConnectionLoggingDepth != 0) {
            id logTarget;
            SEL logSelector;

#if defined(__ppc__) || defined(__POWERPC__)
            logTarget = [invocationToDispatch target];
            logSelector = [invocationToDispatch selector];
#else
            logSelector = [invocationToDispatch selector];
            logTarget = [invocationToDispatch target];
#endif
            NSLog(@"Exception %@ while executing remote message for [0x%x %s ...]\n",
                  exception, logTarget, logSelector);
        }
    NS_ENDHANDLER
    return exception;
}

- (NSArray *)requestModes {
    NSArray *modes;

    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    modes = [[requestModes copyWithZone:NULL] autorelease];
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
    return modes;
}

- (BOOL)registerName:(NSString *) name {
    NSPortNameServer *nameServer;

    if (registerName != nil) {
        nameServer = [NSPortNameServer defaultPortNameServer];
        [nameServer removePortForName:registerName];
    }
    [registerName autorelease];
    registerName = nil;
    if (name == nil)
        return YES;
    nameServer = [NSPortNameServer defaultPortNameServer];
    if ([nameServer registerPort:receivePort name:name])
        registerName = [name copyWithZone:NULL];
    return registerName != nil;
}

+ (id)currentConversation {
    return [_NSCurrentThread() lastConversation];
}

- (NSPort *)sendPort {
    return sendPort;
}

- (NSPort *)receivePort {
    return receivePort;
}

- (void)enableMultipleThreads {
    isMulti = YES;
}

- (BOOL)multipleThreadsEnabled {
    return isMulti;
}

- (void)addRunLoop:(NSRunLoop *)runloop {
    unsigned count;

    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    if (runLoops == nil)
        runLoops = [[NSMutableArray allocWithZone:[self zone]] init];
    if (rootObject != nil || NSCountHashTable((NSHashTable *)localProxies) != 0)
        [self addPortsToRunLoop:runloop];
    [runLoops addObject:runloop];
    count = [runLoops count];
    isMulti = count > 1;
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
}

- (void)removeRunLoop:(NSRunLoop *)runloop {
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock lock];
    if ([runLoops containsObjectIdenticalTo:runloop]) {
        [runLoops removeObjectIdenticalTo:runloop];
        if (rootObject != nil || NSCountHashTable((NSHashTable *)localProxies) != 0)
            [self removePortsFromRunLoop:runloop];
    }
    if (_NSConnectionModesLock != nil)
        [_NSConnectionModesLock unlock];
}

- (void)runInNewThread {
    [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];
}

- (void)run {
    unsigned pool = NSPushAutoreleasePool();
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];

    [self addRunLoop:runLoop];
    while (isValid) {
        NS_DURING
            [runLoop run];
        NS_HANDLER
            (void)localException;
        NS_ENDHANDLER
    }
    NSPopAutoreleasePool(pool);
}

@end

@implementation NSDistantObjectRequest

- (NSInvocation *)invocation {
    return NSRequestConcreteImplementation(self, _cmd, [NSDistantObjectRequest class]);
}

- (NSConnection *)connection {
    return NSRequestConcreteImplementation(self, _cmd, [NSDistantObjectRequest class]);
}

- (id)conversation {
    return NSRequestConcreteImplementation(self, _cmd, [NSDistantObjectRequest class]);
}

- (void)replyWithException:(NSException *)exception {
    (void)exception;
    NSRequestConcreteImplementation(self, _cmd, [NSDistantObjectRequest class]);
}

@end

@implementation NSConcreteDistantObjectRequest

- (id)initWithInvocation:(NSInvocation *)newInvocation conversation:(id)newConversation
                sequence:(unsigned)newSequence importedObjects:(NSMutableArray *)objects
              connection:(NSConnection *)newConnection {
    invocation = [newInvocation retain];
    importedObjects = [objects retain];
    conversation = [newConversation retain];
    connection = [newConnection retain];
    sequence = newSequence;
    return self;
}

- (NSInvocation *)invocation {
    return invocation;
}

- (NSConnection *)connection {
    return connection;
}

- (id)conversation {
    return conversation;
}

- (void)replyWithException:(NSException *)exception {
    [conversation release];
    conversation = nil;
    [connection returnResult:invocation exception:exception sequence:sequence
                     imports:importedObjects];
}

- (void)dealloc {
    [invocation release];
    [importedObjects release];
    [conversation release];
    [connection release];
    [super dealloc];
}

@end
