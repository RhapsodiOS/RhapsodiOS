/*	NSNotificationQueue.m
\tCopyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSNotificationQueue.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSObjCRuntime.h>
#include <string.h>

extern id _NSMethodExceptionProem(id object, SEL selector);

@interface NSRunLoop (NSNotificationQueuePrivate)
- (void)addRunLoopActivityMonitor:(id)monitor;
@end

@interface NSObject (NSNotificationQueueMonitorPrivate)
- (BOOL)_mightPostIdle;
- (BOOL)monitorRunLoop:(NSRunLoop *)runLoop mode:(NSString *)mode
             activity:(unsigned)activity quit:(BOOL *)quit;
- (void)monitoringDiscontinued;
@end

typedef struct {
    NSNotification *notification;
    NSString *name;
    id object;
    NSArray *modes;
} NSNotificationQueueEvent;

typedef struct {
    NSNotificationQueueEvent *events;
    unsigned count;
    unsigned capacity;
} NSNotificationQueueStorage;

static BOOL NSNotificationQueueTraceEventQueue;

static NSNotificationQueueStorage *
NSNotificationQueueCreateStorage(void)
{
    NSNotificationQueueStorage *queue =
        (NSNotificationQueueStorage *)NSZoneMalloc(0, sizeof(NSNotificationQueueStorage));

    queue->count = 0;
    queue->capacity = 16;
    queue->events = (NSNotificationQueueEvent *)NSZoneMalloc(
        0, queue->capacity * sizeof(NSNotificationQueueEvent));
    return queue;
}

static void
NSNotificationQueueAddEvent(NSNotificationQueueStorage *queue,
                            NSNotification *notification, NSArray *modes)
{
    NSNotificationQueueEvent *event = &queue->events[queue->count];

    event->notification = notification;
    event->name = [notification name];
    event->object = [notification object];
    event->modes = (modes != nil) ? [modes copyWithZone:0] : nil;
    event->notification = [notification retain];
    queue->count++;
    if (queue->capacity <= queue->count) {
        queue->capacity *= 2;
        queue->events = (NSNotificationQueueEvent *)NSZoneRealloc(
            0, queue->events, queue->capacity * sizeof(NSNotificationQueueEvent));
    }
}

static unsigned
NSNotificationQueueRemoveEvents(NSNotificationQueueStorage *queue,
                                NSNotification *matching, BOOL oneOnly,
                                unsigned coalesceMask)
{
    id object;
    unsigned removed = 0;
    unsigned index;
    BOOL foundOne = NO;

    if (queue->count == 0 || coalesceMask == 0)
        return 0;
    object = (coalesceMask & NSNotificationCoalescingOnSender) ? [matching object] : nil;

    for (index = 0; index < queue->count; index++) {
        NSNotificationQueueEvent *event = &queue->events[index];
        BOOL matches = (!(coalesceMask & NSNotificationCoalescingOnSender)
                        || event->object == object);

        if (matches && (coalesceMask & NSNotificationCoalescingOnName)) {
            NSString *name = [matching name];

            matches = event->name == name || [event->name isEqual:name];
        }
        if (matches && (!oneOnly || foundOne)) {
            [event->notification release];
            [event->modes release];
            removed++;
            continue;
        }
        if (matches)
            foundOne = YES;
        if (removed != 0)
            queue->events[index - removed] = *event;
    }
    queue->count -= removed;
    return removed + ((oneOnly && foundOne) ? 1 : 0);
}

static void
NSNotificationQueueRemoveAllEvents(NSNotificationQueueStorage *queue)
{
    unsigned index;

    for (index = 0; index < queue->count; index++) {
        [queue->events[index].notification release];
        [queue->events[index].modes release];
    }
    queue->count = 0;
}

static void
NSNotificationQueueDestroyStorage(NSNotificationQueueStorage *queue)
{
    NSNotificationQueueRemoveAllEvents(queue);
    NSZoneFree(0, queue->events);
    NSZoneFree(0, queue);
}

static NSNotification *
NSNotificationQueueTakeFirstEvent(NSNotificationQueueStorage *queue, NSString *mode)
{
    unsigned index;

    for (index = 0; index < queue->count; index++) {
        NSNotificationQueueEvent event = queue->events[index];
        BOOL eligible = (event.modes != nil)
            ? [event.modes containsObject:mode]
            : (mode == nil || mode == NSDefaultRunLoopMode
               || [mode isEqual:NSDefaultRunLoopMode]);

        if (eligible) {
            NSNotification *notification = [event.notification autorelease];
            [event.modes release];
            queue->count--;
            if (index < queue->count)
                memmove(&queue->events[index], &queue->events[index + 1],
                        (queue->count - index) * sizeof(NSNotificationQueueEvent));
            return notification;
        }
    }
    return nil;
}

static void
NSNotificationQueuePost(NSNotificationCenter *center, NSNotificationQueue *queue,
                        NSNotification *notification, BOOL immediate)
{
    NS_DURING
        [center postNotification:notification];
    NS_HANDLER
        if (immediate)
            NSLog(@"%@: ignoring exception '%@' (reason '%@') that raised during posting of notification '%@'",
                  _NSMethodExceptionProem(queue, @selector(enqueueNotification:postingStyle:coalesceMask:forModes:)),
                  [localException name], [localException reason], [notification name]);
        else
            NSLog(@"NSNotificationQueue: ignoring exception '%@' (reason '%@') that raised during posting of notification '%@'",
                  [localException name], [localException reason], [notification name]);
    NS_ENDHANDLER
}

@implementation NSNotificationQueue

+ (NSNotificationQueue *)defaultQueue {
    NSMutableDictionary *threadDictionary = [_NSCurrentThread() threadDictionary];
    NSNotificationQueue *queue = [threadDictionary objectForKey:@"NSDefaultNotificationQueue"];

    if (queue == nil) {
        queue = [[self alloc] init];
        threadDictionary = [_NSCurrentThread() threadDictionary];
        [threadDictionary setObject:queue forKey:@"NSDefaultNotificationQueue"];
        [queue release];
    }
    return queue;
}

+ (void)setTraceEventQueue:(BOOL)flag {
    NSNotificationQueueTraceEventQueue = flag;
    NSLog(@"TraceEventQueue: %@", flag ? @"On" : @"Off");
}

- (id)initWithNotificationCenter:(NSNotificationCenter *)notificationCenter {
    self = [super init];
    if (self != nil) {
        _notificationCenter = [notificationCenter retain];
        _asapQueue = NSNotificationQueueCreateStorage();
        _idleQueue = NSNotificationQueueCreateStorage();
        _attached = NO;
    }
    return self;
}

- (id)init {
    return [self initWithNotificationCenter:[NSNotificationCenter defaultCenter]];
}

- (void)enqueueNotification:(NSNotification *)notification
               postingStyle:(NSPostingStyle)postingStyle
                coalesceMask:(unsigned)coalesceMask
                     forModes:(NSArray *)modes
{
    NSNotificationQueueStorage *asapQueue = (NSNotificationQueueStorage *)_asapQueue;
    NSNotificationQueueStorage *idleQueue = (NSNotificationQueueStorage *)_idleQueue;

    if (postingStyle == NSPostNow) {
        NSNotificationQueueRemoveEvents(idleQueue, notification, NO, coalesceMask);
        NSNotificationQueueRemoveEvents(asapQueue, notification, NO, coalesceMask);
        if (NSNotificationQueueTraceEventQueue)
            NSLog(@"NSNotificationQueue (NOW) -> %@", notification);
        NSNotificationQueuePost(_notificationCenter, self, notification, YES);
    } else if (postingStyle == NSPostASAP) {
        NSNotificationQueueRemoveEvents(idleQueue, notification, NO, coalesceMask);
        if (NSNotificationQueueRemoveEvents(asapQueue, notification, YES, coalesceMask) == 0) {
            NSNotificationQueueAddEvent(asapQueue, notification, modes);
            if (NSNotificationQueueTraceEventQueue)
                NSLog(@"NSNotificationQueue <- %@ ; will post ASAP modes %@", notification, modes);
        } else if (NSNotificationQueueTraceEventQueue) {
            NSLog(@"NSNotificationQueue dropped %@ ; coalesced in ASAP modes %@", notification, modes);
        }
    } else if (postingStyle == NSPostWhenIdle) {
        if (NSNotificationQueueRemoveEvents(asapQueue, notification, YES, coalesceMask) == 0) {
            if (NSNotificationQueueRemoveEvents(idleQueue, notification, YES, coalesceMask) == 0) {
                NSNotificationQueueAddEvent(idleQueue, notification, modes);
                if (NSNotificationQueueTraceEventQueue)
                    NSLog(@"NSNotificationQueue <- %@ ; will post WHEN IDLE modes %@", notification, modes);
            } else if (NSNotificationQueueTraceEventQueue) {
                NSLog(@"NSNotificationQueue dropped %@ ; coalesced in ASAP modes %@", notification, modes);
            }
        } else if (NSNotificationQueueTraceEventQueue) {
            NSLog(@"NSNotificationQueue dropped %@ ; coalesced in ASAP modes %@", notification, modes);
        }
    }

    if (asapQueue->count + idleQueue->count != 0 && !_attached) {
        [[NSRunLoop currentRunLoop] addRunLoopActivityMonitor:self];
        _attached = YES;
    }
}

- (void)enqueueNotification:(NSNotification *)notification postingStyle:(NSPostingStyle)postingStyle {
    [self enqueueNotification:notification postingStyle:postingStyle
                 coalesceMask:(NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender)
                     forModes:nil];
}

- (void)dequeueNotificationsMatching:(NSNotification *)notification coalesceMask:(unsigned)coalesceMask {
    if (coalesceMask != 0) {
        NSNotificationQueueRemoveEvents((NSNotificationQueueStorage *)_idleQueue,
                                        notification, NO, coalesceMask);
        NSNotificationQueueRemoveEvents((NSNotificationQueueStorage *)_asapQueue,
                                        notification, NO, coalesceMask);
    }
}

- (BOOL)_mightPostIdle {
    return ((NSNotificationQueueStorage *)_idleQueue)->count > 0;
}

- (int)_count {
    return ((NSNotificationQueueStorage *)_asapQueue)->count
        + ((NSNotificationQueueStorage *)_idleQueue)->count;
}

- (void)_postAsapNotificationsForMode:(NSString *)mode {
    NSNotificationQueueStorage *queue = (NSNotificationQueueStorage *)_asapQueue;
    NSNotification *notification;

    while ((notification = NSNotificationQueueTakeFirstEvent(queue, mode)) != nil) {
        if (NSNotificationQueueTraceEventQueue)
            NSLog(@"NSNotificationQueue (ASAP) -> %@", notification);
        NSNotificationQueuePost(_notificationCenter, self, notification, NO);
    }
}

- (BOOL)_postIdleNotificationsForMode:(NSString *)mode {
    NSNotificationQueueStorage *queue = (NSNotificationQueueStorage *)_idleQueue;
    NSNotification *stackNotifications[128];
    NSNotification **notifications = stackNotifications;
    unsigned capacity = 128;
    unsigned count = 0;
    unsigned index;
    NSNotification *notification;

    while ((notification = NSNotificationQueueTakeFirstEvent(queue, mode)) != nil) {
        if (count == capacity) {
            if (notifications == stackNotifications) {
                capacity = 512;
                notifications = (NSNotification **)NSZoneMalloc(
                    0, capacity * sizeof(NSNotification *));
                memmove(notifications, stackNotifications,
                        sizeof(stackNotifications));
            } else {
                capacity *= 2;
                notifications = (NSNotification **)NSZoneRealloc(
                    0, notifications, capacity * sizeof(NSNotification *));
            }
        }
        notifications[count++] = notification;
    }
    for (index = 0; index < count; index++) {
        if (NSNotificationQueueTraceEventQueue)
            NSLog(@"NSNotificationQueue (IDLE) -> %@", notifications[index]);
        NSNotificationQueuePost(_notificationCenter, self, notifications[index], NO);
        [self _postAsapNotificationsForMode:mode];
    }
    if (count == 0)
        [self _postAsapNotificationsForMode:mode];
    if (notifications != stackNotifications)
        NSZoneFree(0, notifications);
    return count != 0;
}

- (BOOL)monitorRunLoop:(NSRunLoop *)runLoop mode:(NSString *)mode
             activity:(unsigned)activity quit:(BOOL *)quit
{
    BOOL handled = NO;
    NSNotificationQueueStorage *asapQueue = (NSNotificationQueueStorage *)_asapQueue;
    NSNotificationQueueStorage *idleQueue = (NSNotificationQueueStorage *)_idleQueue;

    if (asapQueue->count + idleQueue->count != 0) {
        if (activity == 4 || activity == 1)
            [self _postAsapNotificationsForMode:mode];
        else if (activity == 3)
            handled = [self _postIdleNotificationsForMode:mode];
    }
    *quit = (asapQueue->count + idleQueue->count == 0);
    return handled;
}

- (void)monitoringDiscontinued {
    NSNotificationQueueStorage *asapQueue = (NSNotificationQueueStorage *)_asapQueue;
    NSNotificationQueueStorage *idleQueue = (NSNotificationQueueStorage *)_idleQueue;

    _attached = NO;
    if (asapQueue->count + idleQueue->count != 0) {
        [[NSRunLoop currentRunLoop] addRunLoopActivityMonitor:self];
        _attached = YES;
    }
}

- (void)_flushNotificationQueue {
    NSNotificationQueueRemoveAllEvents((NSNotificationQueueStorage *)_idleQueue);
    NSNotificationQueueRemoveAllEvents((NSNotificationQueueStorage *)_asapQueue);
}

- (void)dealloc {
    NSNotificationQueueDestroyStorage((NSNotificationQueueStorage *)_idleQueue);
    NSNotificationQueueDestroyStorage((NSNotificationQueueStorage *)_asapQueue);
    [_notificationCenter release];
    [super dealloc];
}

@end
