/*	NSProtocolChecker.h
	Distributed object message filtering
	Copyright 1995-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSProxy.h>
#import <Foundation/NSObject.h>

@interface NSProtocolChecker : NSProxy

- (Protocol *)protocol;
- (NSObject *)target;

@end

@interface NSProtocolChecker (NSProtocolCheckerCreation)

+ (id)protocolCheckerWithTarget:(NSObject *)anObject protocol:(Protocol *)aProtocol;
- (id)initWithTarget:(NSObject *)anObject protocol:(Protocol *)aProtocol;

@end

