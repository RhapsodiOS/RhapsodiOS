/*	NSRunLoop.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSRunLoop.h>

@implementation NSRunLoop

+ (NSRunLoop *)currentRunLoop {
    // TODO: Implement this method
    return nil;
}

- (NSString *)currentMode {
    // TODO: Implement this method
    return nil;
}

- (void)addTimer:(NSTimer *)timer forMode:(NSString *)mode {
    // TODO: Implement this method
}

- (void)addPort:(NSPort *)aPort forMode:(NSString *)mode {
    // TODO: Implement this method
}

- (void)removePort:(NSPort *)aPort forMode:(NSString *)mode {
    // TODO: Implement this method
}

- (NSDate *)limitDateForMode:(NSString *)mode {
    // TODO: Implement this method
    return nil;
}

- (void)acceptInputForMode:(NSString *)mode beforeDate:(NSDate *)limitDate {
    // TODO: Implement this method
}

- (void)run {
    // TODO: Implement this method
}

- (void)runUntilDate:(NSDate *)limitDate {
    // TODO: Implement this method
}

- (BOOL)runMode:(NSString *)mode beforeDate:(NSDate *)limitDate {
    // TODO: Implement this method
    return NO;
}

- (void)configureAsServer {
    // TODO: Implement this method
}

@end

@implementation NSObject

- (void)performSelector:(SEL)aSelector withObject:(id)anArgument afterDelay:(NSTimeInterval)delay inModes:(NSArray *)modes {
    // TODO: Implement this method
}

- (void)performSelector:(SEL)aSelector withObject:(id)anArgument afterDelay:(NSTimeInterval)delay {
    // TODO: Implement this method
}

+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget selector:(SEL)aSelector object:(id)anArgument {
    // TODO: Implement this method
}

@end

@implementation NSRunLoop

- (void)performSelector:(SEL)aSelector target:(id)target argument:(id)arg order:(unsigned)order modes:(NSArray *)modes {
    // TODO: Implement this method
}

- (void)cancelPerformSelector:(SEL)aSelector target:(id)target argument:(id)arg {
    // TODO: Implement this method
}

@end

@implementation NSObject

- (NSDate *)limitDateForMode:(NSString *)mode {
    // TODO: Implement this method
    return nil;
}

@end
