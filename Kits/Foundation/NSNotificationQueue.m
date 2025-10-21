/*	NSNotificationQueue.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSNotificationQueue.h>

@implementation NSNotificationQueue

+ (NSNotificationQueue *)defaultQueue {
    // TODO: Implement this method
    return nil;
}

- (id)initWithNotificationCenter:(NSNotificationCenter *)notificationCenter {
    // TODO: Implement this method
    return nil;
}

- (id)init {
    // TODO: Implement this method
    return nil;
}

- (void)enqueueNotification:(NSNotification *)notification postingStyle:(NSPostingStyle)postingStyle coalesceMask:(unsigned)coalesceMask forModes:(NSArray *)modes {
    // TODO: Implement this method
}

- (void)enqueueNotification:(NSNotification *)notification postingStyle:(NSPostingStyle)postingStyle {
    // TODO: Implement this method
}

- (void)dequeueNotificationsMatching:(NSNotification *)notification coalesceMask:(unsigned)coalesceMask {
    // TODO: Implement this method
}

@end
