/*	NSTimer.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSTimer.h>

@implementation NSTimer

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti invocation:(NSInvocation *)invocation repeats:(BOOL)yesOrNo {
    // TODO: Implement this method
    return nil;
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti invocation:(NSInvocation *)invocation repeats:(BOOL)yesOrNo {
    // TODO: Implement this method
    return nil;
}

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)yesOrNo {
    // TODO: Implement this method
    return nil;
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)yesOrNo {
    // TODO: Implement this method
    return nil;
}

- (void)fire {
    // TODO: Implement this method
}

- (NSDate *)fireDate {
    // TODO: Implement this method
    return nil;
}

- (NSTimeInterval)timeInterval {
    // TODO: Implement this method
    return 0.0;
}

- (void)invalidate {
    // TODO: Implement this method
}

- (BOOL)isValid {
    // TODO: Implement this method
    return NO;
}

- (id)userInfo {
    // TODO: Implement this method
    return nil;
}

@end
