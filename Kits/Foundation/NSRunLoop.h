/*	NSRunLoop.h
	Event loop abstraction
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSMapTable.h>

@class NSTimer, NSPort;

FOUNDATION_EXPORT NSString * const NSDefaultRunLoopMode;

@interface NSRunLoop : NSObject {
@private
    void	*_modes;
    id		_currentMode;
    id		_callout;
    void	*_callouts;
    void	*_timers;
    id		_condition;
    void	*_currentSet;
    char	*_msg;
    void	*_performers;
    id		_wakeupPort;
    id          _winMessagePort;
}

+ (NSRunLoop *)currentRunLoop;
- (NSString *)currentMode;

- (void)addTimer:(NSTimer *)timer forMode:(NSString *)mode;

- (void)addPort:(NSPort *)aPort forMode:(NSString *)mode;
- (void)removePort:(NSPort *)aPort forMode:(NSString *)mode;

- (NSDate *)limitDateForMode:(NSString *)mode;
- (void)acceptInputForMode:(NSString *)mode beforeDate:(NSDate *)limitDate;

@end

@interface NSRunLoop (NSRunLoopConveniences)

- (void)run; 
- (void)runUntilDate:(NSDate *)limitDate;
- (BOOL)runMode:(NSString *)mode beforeDate:(NSDate *)limitDate;

- (void)configureAsServer;

@end

/**************** 	Delayed perform	 ******************/

@interface NSObject (NSDelayedPerforming)

- (void)performSelector:(SEL)aSelector withObject:(id)anArgument afterDelay:(NSTimeInterval)delay inModes:(NSArray *)modes;
- (void)performSelector:(SEL)aSelector withObject:(id)anArgument afterDelay:(NSTimeInterval)delay;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget selector:(SEL)aSelector object:(id)anArgument;

@end

@interface NSRunLoop (NSOrderedPerform)
- (void)performSelector:(SEL)aSelector target:(id)target argument:(id)arg order:(unsigned)order modes:(NSArray *)modes;
- (void)cancelPerformSelector:(SEL)aSelector target:(id)target argument:(id)arg;
@end

/**************** 	Delegate methods	 ******************/

@interface NSObject (NSRunLoopPortDelegateMethods)

- (NSDate *)limitDateForMode:(NSString *)mode;

@end

