/*	NSLock.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSLock.h>

@implementation NSLock

- (BOOL)tryLock {
    // TODO: Implement this method
    return NO;
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    // TODO: Implement this method
    return NO;
}

@end

@implementation NSConditionLock

- (id)initWithCondition:(int)condition {
    // TODO: Implement this method
    return nil;
}

- (int)condition {
    // TODO: Implement this method
    return 0;
}

- (void)lockWhenCondition:(int)condition {
    // TODO: Implement this method
}

- (BOOL)tryLock {
    // TODO: Implement this method
    return NO;
}

- (BOOL)tryLockWhenCondition:(int)condition {
    // TODO: Implement this method
    return NO;
}

- (void)unlockWithCondition:(int)condition {
    // TODO: Implement this method
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    // TODO: Implement this method
    return NO;
}

- (BOOL)lockWhenCondition:(int)condition beforeDate:(NSDate *)limit {
    // TODO: Implement this method
    return NO;
}

@end

@implementation NSRecursiveLock

- (BOOL)tryLock {
    // TODO: Implement this method
    return NO;
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    // TODO: Implement this method
    return NO;
}

@end
