/*	NSPortMessage.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPortMessage.h>

@implementation NSPortMessage

- (id)initWithSendPort:(NSPort *)sendPort receivePort:(NSPort *)replyPort components:(NSArray *)components {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)components {
    // TODO: Implement this method
    return nil;
}

- (NSPort *)receivePort {
    // TODO: Implement this method
    return nil;
}

- (NSPort *)sendPort {
    // TODO: Implement this method
    return nil;
}

- (BOOL)sendBeforeDate:(NSDate *)date {
    // TODO: Implement this method
    return NO;
}

- (id)initWithMachMessage:(void *)buf {
    // TODO: Implement this method
    return nil;
}

- (unsigned)msgid {
    // TODO: Implement this method
    return 0;
}

- (void)setMsgid:(unsigned)msgid {
    // TODO: Implement this method
}

@end
