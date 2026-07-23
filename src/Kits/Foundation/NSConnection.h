/*	NSConnection.h
	Encapsulates the state of a DO circuit
	Copyright 1989-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSMapTable.h>

@class NSMutableData, NSDistantObject, NSException, NSData, NSRunLoop;
@class NSPort;

/*****************	NSConnection	**************************/

@interface NSConnection : NSObject {
    @private
    id		receivePort;
    id		sendPort;
    id          delegate;
    unsigned    isValid:1;
    unsigned	isDead:1;
    unsigned	isQueueing:1;
    unsigned	authGen:1;
    unsigned	authCheck:1;
    unsigned	encryptFlag:1;
    unsigned	decryptFlag:1;
    unsigned    doRequest:1;
    unsigned	isMulti:1;
    unsigned	filler:7;
    unsigned	refCount:16;
    void        *localProxies;
    void        *remoteProxies;
    id          runLoops;
    NSTimeInterval	requestLimit;
    NSTimeInterval	replyLimit;
    id		requestModes;
    id          rootObject;
    id		registerName;
    id		statistics;
    NSHashTable	*classInfoExported;
    NSMapTable	*classInfoImported;
    NSMutableData	*releasedProxies;
    void	*reserved;
}

- (NSDictionary *)statistics;

+ (NSArray *)allConnections;

+ (NSConnection *)defaultConnection;

+ (NSConnection *)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName;
+ (NSDistantObject *)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName;

- (void)setRequestTimeout:(NSTimeInterval)ti;
- (NSTimeInterval)requestTimeout;
- (void)setReplyTimeout:(NSTimeInterval)ti;
- (NSTimeInterval)replyTimeout;

- (void)setRootObject:(id)anObject;
- (id)rootObject;

- (NSDistantObject *)rootProxy;
  
- (void)setDelegate:(id)anObject;
- (id)delegate;

- (void)setIndependentConversationQueueing:(BOOL)yorn;
- (BOOL)independentConversationQueueing;

- (BOOL)isValid;

- (void)invalidate;

- (void)addRequestMode:(NSString *)rmode;
- (void)removeRequestMode:(NSString *)rmode;
- (NSArray *)requestModes;

- (BOOL)registerName:(NSString *) name;

+ (NSConnection *)connectionWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort;

+ (id)currentConversation;

- (id)initWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort;
- (NSPort *)sendPort;
- (NSPort *)receivePort;

- (void)enableMultipleThreads;
- (BOOL)multipleThreadsEnabled;

- (void)addRunLoop:(NSRunLoop *)runloop;
- (void)removeRunLoop:(NSRunLoop *)runloop;

- (void)runInNewThread;

- (NSArray *)remoteObjects;
- (NSArray *)localObjects;

@end

FOUNDATION_EXPORT NSString * const NSConnectionReplyMode;

FOUNDATION_EXPORT NSString * const NSConnectionDidDieNotification;


@interface NSObject (NSConnectionDelegateMethods)

// Use the NSConnectionDidInitializeNotification notification instead
// of this delegate method if possible.
- (BOOL)makeNewConnection:(NSConnection *)conn sender:(NSConnection *)ancestor;

// Use the NSConnectionDidInitializeNotification notification instead
// of this delegate method if possible.
- (BOOL)connection:(NSConnection *)ancestor shouldMakeNewConnection:(NSConnection *)conn;

- (NSData *)authenticationDataForComponents:(NSArray *)components;
- (BOOL)authenticateComponents:(NSArray *)components withData:(NSData *)signature;

- (id)createConversationForConnection:(NSConnection *)conn;

FOUNDATION_EXPORT NSString * const NSFailedAuthenticationException;

FOUNDATION_EXPORT NSString * const NSConnectionDidInitializeNotification;

@end

@interface NSDistantObjectRequest : NSObject

- (NSInvocation *)invocation;
- (NSConnection *)connection;
- (id)conversation;
- (void)replyWithException:(NSException *)exception;

@end

@interface NSObject (NSDistantObjectRequestMethods)

- (BOOL)connection:(NSConnection *)connection handleRequest:(NSDistantObjectRequest *)doreq;

@end

