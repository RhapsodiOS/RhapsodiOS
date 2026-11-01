/*	NSPerformTimer.m
	Delayed run-loop performers
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>
#import "NSPerformTimerPrivate.h"

NSLock *_NSPerformTimerCacheLock;
static NSPerformTimer *NSPerformTimerCache[4];

@implementation NSPerformTimer

+ (id)newPerformSelector:(SEL)selector target:(id)target argument:(id)argument
                   order:(unsigned)order modes:(NSArray *)modes {
    NSPerformTimer *performer = nil;
    unsigned index;

    if (_NSPerformTimerCacheLock != nil)
        [_NSPerformTimerCacheLock lock];
    for (index = 0; index < 4; index++) {
        if (NSPerformTimerCache[index] != nil) {
            performer = NSPerformTimerCache[index];
            NSPerformTimerCache[index] = nil;
            break;
        }
    }
    if (_NSPerformTimerCacheLock != nil)
        [_NSPerformTimerCacheLock unlock];

    if (performer == nil) {
        performer = (NSPerformTimer *)NSAllocateObject(self, 0, NULL);
    } else if (NSKeepAllocationStatistics) {
        NSRecordAllocationEvent(NSObjectAllocatedEvent, performer, 0);
    }
    performer->target = target;
    performer->selector = selector;
    performer->argument = argument;
    performer->order = order;
    performer->invalid = 0;
    performer->modes = [modes copyWithZone:NULL];
    return performer;
}

- (void)invalidate {
    self->invalid = 1;
    [self->modes release];
    self->modes = nil;
}

- (void)fire {
    if (self->firing || self->invalid)
        return;

    self->firing = 1;
    NS_DURING
        objc_msgSend(self->target, self->selector, self->argument);
    NS_HANDLER
#if defined(__ppc__) || defined(__POWERPC__)
        NSLog(@"*** NSRunLoop: ignoring exception '%@' (reason '%@') that raised during delayed perform of target %u and selector '%s'",
              [localException name], [localException reason],
              (unsigned)self->target,
              (const char *)self->selector);
#else
        NSLog(@"*** NSRunLoop: ignoring exception '%@' (reason '%@') that raised during delayed perform of target %u and selector '%s'",
              [localException name], [localException reason]);
#endif
    NS_ENDHANDLER
    self->firing = 0;
    [self invalidate];
}

- (NSDate *)fireDate {
    return [NSDate date];
}

- (BOOL)isValid {
    return !self->invalid;
}

- (NSTimeInterval)timeInterval {
    return 0.0;
}

- (id)userInfo {
    return nil;
}

- (id)retain {
    self->refCount++;
    return self;
}

- (oneway void)release {
    if (self->refCount != 0)
        self->refCount--;
    else
        [self dealloc];
}

- (unsigned)retainCount {
    return self->refCount + 1;
}

- (NSString *)description {
    return [NSString stringWithFormat:
        @"Perform [%@ %s%@] order:%u",
        self->target, self->selector, self->argument, self->order];
}

- (void)dealloc {
    unsigned index;

    [self invalidate];
    if (_NSPerformTimerCacheLock != nil)
        [_NSPerformTimerCacheLock lock];
    for (index = 0; index < 4; index++) {
        if (NSPerformTimerCache[index] == nil) {
            NSPerformTimerCache[index] = self;
            self->target = nil;
            self->selector = NULL;
            self->argument = nil;
            self->order = 0;
            self->modes = nil;
            self->firing = 0;
            self->filler = 0;
            self->refCount = 0;
            self->link = nil;
            if (_NSPerformTimerCacheLock != nil)
                [_NSPerformTimerCacheLock unlock];
            if (NSKeepAllocationStatistics)
                NSRecordAllocationEvent(NSObjectDeallocatedEvent, self);
            return;
        }
    }
    if (_NSPerformTimerCacheLock != nil)
        [_NSPerformTimerCacheLock unlock];
    [super dealloc];
}

@end
