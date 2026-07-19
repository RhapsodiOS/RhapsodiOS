/*	NSPortCoder.h
	Sending Objective-C messages in Mach msgs
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCoder.h>

@class NSConnection, NSPort, NSArray;

@interface NSPortCoder : NSCoder

- (BOOL)isBycopy;
- (BOOL)isByref;
- (NSConnection *)connection;
- (void)encodePortObject:(NSPort *)aport;
- (NSPort *)decodePortObject;

// Transport
+ portCoderWithReceivePort:(NSPort *)rcvPort sendPort:(NSPort *)sndPort components:(NSArray *)comps;
- (void)dispatch;

@end

@interface NSObject (NSDistributedObjects)

- (Class)classForPortCoder;

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder;

@end
