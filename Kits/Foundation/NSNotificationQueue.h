/*	NSNotificationQueue.h
	Enqueuing of notifications
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@class NSNotification, NSNotificationCenter, NSArray;

typedef enum {
    NSPostWhenIdle = 1,
    NSPostASAP = 2,
    NSPostNow = 3
} NSPostingStyle;

typedef enum {
    NSNotificationNoCoalescing = 0,
    NSNotificationCoalescingOnName = 1,
    NSNotificationCoalescingOnSender = 2
} NSNotificationCoalescing;

@interface NSNotificationQueue:NSObject {
@private
    NSNotificationCenter	*_notificationCenter;
    id		_asapQueue;
    id		_idleQueue;
    BOOL	_attached;
    void	*_reserved;
}

+ (NSNotificationQueue *)defaultQueue;

- (id)initWithNotificationCenter:(NSNotificationCenter *)notificationCenter;

- (id)init;

- (void)enqueueNotification:(NSNotification *)notification postingStyle:(NSPostingStyle)postingStyle coalesceMask:(unsigned)coalesceMask forModes:(NSArray *)modes;

- (void)enqueueNotification:(NSNotification *)notification postingStyle:(NSPostingStyle)postingStyle;

- (void)dequeueNotificationsMatching:(NSNotification *)notification coalesceMask:(unsigned)coalesceMask;

@end
