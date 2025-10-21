/*	NSConnection.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSConnection.h>

@implementation NSConnection

- (NSDictionary *)statistics {
    // TODO: Implement this method
    return nil;
}

+ (NSArray *)allConnections {
    // TODO: Implement this method
    return nil;
}

+ (NSConnection *)defaultConnection {
    // TODO: Implement this method
    return nil;
}

+ (NSConnection *)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName {
    // TODO: Implement this method
    return nil;
}

+ (NSDistantObject *)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName {
    // TODO: Implement this method
    return nil;
}

- (void)setRequestTimeout:(NSTimeInterval)ti {
    // TODO: Implement this method
}

- (NSTimeInterval)requestTimeout {
    // TODO: Implement this method
    return 0.0;
}

- (void)setReplyTimeout:(NSTimeInterval)ti {
    // TODO: Implement this method
}

- (NSTimeInterval)replyTimeout {
    // TODO: Implement this method
    return 0.0;
}

- (void)setRootObject:(id)anObject {
    // TODO: Implement this method
}

- (id)rootObject {
    // TODO: Implement this method
    return nil;
}

- (NSDistantObject *)rootProxy {
    // TODO: Implement this method
    return nil;
}

- (void)setDelegate:(id)anObject {
    // TODO: Implement this method
}

- (id)delegate {
    // TODO: Implement this method
    return nil;
}

- (void)setIndependentConversationQueueing:(BOOL)yorn {
    // TODO: Implement this method
}

- (BOOL)independentConversationQueueing {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isValid {
    // TODO: Implement this method
    return NO;
}

- (void)invalidate {
    // TODO: Implement this method
}

- (void)addRequestMode:(NSString *)rmode {
    // TODO: Implement this method
}

- (void)removeRequestMode:(NSString *)rmode {
    // TODO: Implement this method
}

- (NSArray *)requestModes {
    // TODO: Implement this method
    return nil;
}

- (BOOL)registerName:(NSString *) name {
    // TODO: Implement this method
    return NO;
}

+ (NSConnection *)connectionWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort {
    // TODO: Implement this method
    return nil;
}

+ (id)currentConversation {
    // TODO: Implement this method
    return nil;
}

- (id)initWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort {
    // TODO: Implement this method
    return nil;
}

- (NSPort *)sendPort {
    // TODO: Implement this method
    return nil;
}

- (NSPort *)receivePort {
    // TODO: Implement this method
    return nil;
}

- (void)enableMultipleThreads {
    // TODO: Implement this method
}

- (BOOL)multipleThreadsEnabled {
    // TODO: Implement this method
    return NO;
}

- (void)addRunLoop:(NSRunLoop *)runloop {
    // TODO: Implement this method
}

- (void)removeRunLoop:(NSRunLoop *)runloop {
    // TODO: Implement this method
}

- (void)runInNewThread {
    // TODO: Implement this method
}

- (NSArray *)remoteObjects {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)localObjects {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSObject

- (BOOL)makeNewConnection:(NSConnection *)conn sender:(NSConnection *)ancestor {
    // TODO: Implement this method
    return NO;
}

- (BOOL)connection:(NSConnection *)ancestor shouldMakeNewConnection:(NSConnection *)conn {
    // TODO: Implement this method
    return NO;
}

- (NSData *)authenticationDataForComponents:(NSArray *)components {
    // TODO: Implement this method
    return nil;
}

- (BOOL)authenticateComponents:(NSArray *)components withData:(NSData *)signature {
    // TODO: Implement this method
    return NO;
}

- (id)createConversationForConnection:(NSConnection *)conn {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSDistantObjectRequest

- (NSInvocation *)invocation {
    // TODO: Implement this method
    return nil;
}

- (NSConnection *)connection {
    // TODO: Implement this method
    return nil;
}

- (id)conversation {
    // TODO: Implement this method
    return nil;
}

- (void)replyWithException:(NSException *)exception {
    // TODO: Implement this method
}

@end

@implementation NSObject

- (BOOL)connection:(NSConnection *)connection handleRequest:(NSDistantObjectRequest *)doreq {
    // TODO: Implement this method
    return NO;
}

@end
