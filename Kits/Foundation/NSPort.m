/*	NSPort.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPort.h>

@implementation NSPort

+ (NSPort *)port {
    // TODO: Implement this method
    return nil;
}

+ (NSPort *)portWithMachPort:(int)machPort {
    // TODO: Implement this method
    return nil;
}

- (id)initWithMachPort:(int)machPort {
    // TODO: Implement this method
    return nil;
}

- (void)invalidate {
    // TODO: Implement this method
}

- (BOOL)isValid {
    // TODO: Implement this method
    return NO;
}

- (int)machPort {
    // TODO: Implement this method
    return 0;
}

- (void)setDelegate:(id)anId {
    // TODO: Implement this method
}

- (id)delegate {
    // TODO: Implement this method
    return nil;
}

- (unsigned)reservedSpaceLength;	// space to reserve in first data component for header {
    // TODO: Implement this method
    return 0;
}

- (BOOL) sendBeforeDate:(NSDate *)limitDate components:(NSMutableArray *)components from:(NSPort *) receivePort reserved:(unsigned)headerSpaceReserved {
    // TODO: Implement this method
    return NO;
}

- (void)addConnection:(NSConnection *)conn toRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode {
    // TODO: Implement this method
}

- (void)removeConnection:(NSConnection *)conn fromRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode {
    // TODO: Implement this method
}

@end

@implementation NSObject

- (void)handleMachMessage:(void *)msg {
    // TODO: Implement this method
}

- (void)handlePortMessage:(NSPortMessage *)message {
    // TODO: Implement this method
}

@end
