/*	NSThread.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSThread.h>

@implementation NSThread

+ (NSThread *)currentThread {
    // TODO: Implement this method
    return nil;
}

+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument {
    // TODO: Implement this method
}

+ (BOOL)isMultiThreaded {
    // TODO: Implement this method
    return NO;
}

- (NSMutableDictionary *)threadDictionary {
    // TODO: Implement this method
    return nil;
}

+ (void)sleepUntilDate:(NSDate *)date {
    // TODO: Implement this method
}

+ (void)exit {
    // TODO: Implement this method
}

@end
