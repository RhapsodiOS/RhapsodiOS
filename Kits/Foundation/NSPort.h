/*	NSPort.h
	An idealized many-to-one IPC interface
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@class NSRunLoop, NSMutableArray, NSDate, NSConnection;

/***************    Port Class		***************/

FOUNDATION_EXPORT NSString * const NSPortDidBecomeInvalidNotification;

@interface NSPort : NSObject <NSCopying, NSCoding>

+ (NSPort *)port;
+ (NSPort *)portWithMachPort:(int)machPort;
- (id)initWithMachPort:(int)machPort;

- (void)invalidate;
- (BOOL)isValid;

- (int)machPort;

- (void)setDelegate:(id)anId;
- (id)delegate;

// DO Transport API
// subclassers should implement these methods
- (unsigned)reservedSpaceLength;	// space to reserve in first data component for header
- (BOOL) sendBeforeDate:(NSDate *)limitDate components:(NSMutableArray *)components from:(NSPort *) receivePort reserved:(unsigned)headerSpaceReserved;

- (void)addConnection:(NSConnection *)conn toRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode;
- (void)removeConnection:(NSConnection *)conn fromRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode;
@end

@class NSPortMessage;

@interface NSObject (NSPortMessageDelegateMethods)

- (void)handleMachMessage:(void *)msg;
- (void)handlePortMessage:(NSPortMessage *)message;

@end

