/*	NSTimer.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSTimer.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>
#import <Foundation/NSObjCRuntime.h>

#import "NSProcessInfoPrivate.h"
extern id _NSMethodExceptionProem(id object, SEL selector);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);

#if defined(__ppc__) || defined(__POWERPC__)
#define NSTimerFiring 0x80000000U
#define NSTimerRepeats 0x40000000U
#define NSTimerInvalid 0x20000000U
#define NSTimerUserInfoIsArgument 0x10000000U
#define NSTimerStateMask 0xff000000U
#define NSTimerInternalRefCountShift 0
#else
#define NSTimerFiring 1U
#define NSTimerRepeats 2U
#define NSTimerInvalid 4U
#define NSTimerUserInfoIsArgument 8U
#define NSTimerStateMask 0x000000ffU
#define NSTimerInternalRefCountShift 8
#endif

#define NSTimerInternalRefCountMask 0x00ffffffU

@interface NSConcreteTimer : NSTimer {
    NSDate *_fireDate;
    id _target;
    SEL _selector;
    id _userInfo;
    unsigned int _state;
    NSTimeInterval _timeInterval;
}
- (id)initWithFireDate:(NSDate *)fireDate
          interval:(NSTimeInterval)interval
            target:(id)target
          selector:(SEL)selector
          userInfo:(id)userInfo
           repeats:(BOOL)repeats
 userInfoIsArgument:(BOOL)userInfoIsArgument;
@end

@interface NSTimer (NSTimerPrivate)
- (void)schedule;
- (void)scheduleInModes:(NSArray *)modes;
+ (NSTimer *)timerWithFireDate:(NSDate *)fireDate target:(id)target
                      selector:(SEL)selector userInfo:(id)userInfo;
+ (void)scheduleTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target
                              selector:(SEL)selector withObject:(id)object;
+ (void)scheduleTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target
                              selector:(SEL)selector withObject:(id)object
                               inModes:(NSArray *)modes;
@end

@implementation NSTimer

+ (id)allocWithZone:(NSZone *)zone {
    Class timerClass = self;

    if (self == [NSTimer class])
        timerClass = [NSConcreteTimer class];
    return NSAllocateObject(timerClass, 0, zone);
}

- (void)schedule {
    [[NSRunLoop currentRunLoop] addTimer:self forMode:NSDefaultRunLoopMode];
}

- (void)scheduleInModes:(NSArray *)modes {
    NSRunLoop *runLoop;
    unsigned count = [modes count];
    unsigned index;

    runLoop = [NSRunLoop currentRunLoop];
    for (index = 0; index < count; index++)
        [runLoop addTimer:self forMode:[modes objectAtIndex:index]];
}

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti invocation:(NSInvocation *)invocation repeats:(BOOL)yesOrNo {
    NSDate *fireDate;
    NSTimer *timer;

    [invocation retainArguments];
#if defined(__ppc__) || defined(__POWERPC__)
    timer = [self allocWithZone:NULL];
    fireDate = [NSDate dateWithTimeIntervalSinceNow:ti];
    timer = [timer initWithFireDate:fireDate interval:ti target:invocation
        selector:@selector(invoke) userInfo:nil repeats:yesOrNo
        userInfoIsArgument:NO];
#else
    fireDate = [NSDate dateWithTimeIntervalSinceNow:ti];
    timer = [[self allocWithZone:NULL]
        initWithFireDate:fireDate interval:ti target:invocation
        selector:@selector(invoke) userInfo:nil repeats:yesOrNo
        userInfoIsArgument:NO];
#endif
    return [timer autorelease];
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti invocation:(NSInvocation *)invocation repeats:(BOOL)yesOrNo {
    NSDate *fireDate;
    NSTimer *timer;

    [invocation retainArguments];
#if defined(__ppc__) || defined(__POWERPC__)
    timer = [self allocWithZone:NULL];
    fireDate = [NSDate dateWithTimeIntervalSinceNow:ti];
    timer = [timer initWithFireDate:fireDate interval:ti target:invocation
        selector:@selector(invoke) userInfo:nil repeats:yesOrNo
        userInfoIsArgument:NO];
#else
    fireDate = [NSDate dateWithTimeIntervalSinceNow:ti];
    timer = [[self allocWithZone:NULL]
        initWithFireDate:fireDate interval:ti target:invocation
        selector:@selector(invoke) userInfo:nil repeats:yesOrNo
        userInfoIsArgument:NO];
#endif
    [timer autorelease];
    [timer schedule];
    return timer;
}

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)yesOrNo {
#if defined(__ppc__) || defined(__POWERPC__)
    NSTimer *timer = [self allocWithZone:NULL];
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:ti];

    timer = [timer initWithFireDate:fireDate interval:ti target:aTarget
        selector:aSelector userInfo:userInfo repeats:yesOrNo
        userInfoIsArgument:NO];
    return [timer autorelease];
#else
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:ti];

    return [[[self allocWithZone:NULL]
        initWithFireDate:fireDate interval:ti target:aTarget selector:aSelector
        userInfo:userInfo repeats:yesOrNo userInfoIsArgument:NO] autorelease];
#endif
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)yesOrNo {
#if defined(__ppc__) || defined(__POWERPC__)
    NSTimer *timer = [self allocWithZone:NULL];
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:ti];

    timer = [timer initWithFireDate:fireDate interval:ti target:aTarget
        selector:aSelector userInfo:userInfo repeats:yesOrNo
        userInfoIsArgument:NO];
#else
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:ti];
    NSTimer *timer = [[self allocWithZone:NULL]
        initWithFireDate:fireDate interval:ti target:aTarget selector:aSelector
        userInfo:userInfo repeats:yesOrNo userInfoIsArgument:NO];
#endif

    [timer autorelease];
    [timer schedule];
    return timer;
}

+ (NSTimer *)timerWithFireDate:(NSDate *)fireDate target:(id)target
                       selector:(SEL)selector userInfo:(id)userInfo {
    return [[[self allocWithZone:NULL]
        initWithFireDate:fireDate interval:0.0 target:target selector:selector
        userInfo:userInfo repeats:NO userInfoIsArgument:NO] autorelease];
}

+ (void)scheduleTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target
                              selector:(SEL)selector withObject:(id)object {
#if defined(__ppc__) || defined(__POWERPC__)
    NSTimer *timer = [self allocWithZone:NULL];
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:interval];

    timer = [timer initWithFireDate:fireDate interval:interval target:target
        selector:selector userInfo:object repeats:NO userInfoIsArgument:YES];
    [timer autorelease];
#else
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:interval];
    NSTimer *timer = [[[self allocWithZone:NULL]
        initWithFireDate:fireDate interval:interval target:target
        selector:selector userInfo:object repeats:NO
        userInfoIsArgument:YES] autorelease];
#endif
    [timer schedule];
}

+ (void)scheduleTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target
                              selector:(SEL)selector withObject:(id)object
                               inModes:(NSArray *)modes {
#if defined(__ppc__) || defined(__POWERPC__)
    NSTimer *timer = [self allocWithZone:NULL];
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:interval];

    timer = [timer initWithFireDate:fireDate interval:interval target:target
        selector:selector userInfo:object repeats:NO userInfoIsArgument:YES];
    [timer autorelease];
#else
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:interval];
    NSTimer *timer = [[[self allocWithZone:NULL]
        initWithFireDate:fireDate interval:interval target:target
        selector:selector userInfo:object repeats:NO
        userInfoIsArgument:YES] autorelease];
#endif
    [timer scheduleInModes:modes];
}

- (void)fire {
    NSRequestConcreteImplementation(self, _cmd, [NSTimer class]);
}

- (NSDate *)fireDate {
    return NSRequestConcreteImplementation(self, _cmd, [NSTimer class]);
}

- (NSTimeInterval)timeInterval {
    NSRequestConcreteImplementation(self, _cmd, [NSTimer class]);
    return 0.0;
}

- (void)invalidate {
    NSRequestConcreteImplementation(self, _cmd, [NSTimer class]);
}

- (BOOL)isValid {
    NSRequestConcreteImplementation(self, _cmd, [NSTimer class]);
    return NO;
}

- (id)userInfo {
    return nil;
}

- (BOOL)_isEqualTimerWithTarget:(id)target selector:(SEL)selector withObject:(id)object {
    return NO;
}

@end

@implementation NSConcreteTimer

- (id)initWithFireDate:(NSDate *)fireDate
          interval:(NSTimeInterval)interval
            target:(id)target
          selector:(SEL)selector
          userInfo:(id)userInfo
           repeats:(BOOL)repeats
 userInfoIsArgument:(BOOL)userInfoIsArgument {
    if (interval <= 0.0)
        interval = 0.0001;
    _fireDate = [fireDate retain];
    _target = [target retain];
    _userInfo = [userInfo retain];
    if (userInfoIsArgument)
        _state |= NSTimerUserInfoIsArgument;
    else
        _state &= ~NSTimerUserInfoIsArgument;
    _selector = selector;
    if (repeats)
        _state |= NSTimerRepeats;
    else
        _state &= ~NSTimerRepeats;
    _timeInterval = interval;
    return self;
}

- (id)retain {
    unsigned int count =
        (_state >> NSTimerInternalRefCountShift)
        & NSTimerInternalRefCountMask;

    if (count == NSTimerInternalRefCountMask)
        NSIncrementExtraRefCount(self);
    else
        count++;
    _state = (_state & NSTimerStateMask)
        | (count << NSTimerInternalRefCountShift);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    unsigned int count =
        (_state >> NSTimerInternalRefCountShift)
        & NSTimerInternalRefCountMask;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    if (count == 0) {
        [self dealloc];
        return;
    }
    if (count == NSTimerInternalRefCountMask
        && !NSDecrementExtraRefCountWasZero(self))
        return;
    count--;
    _state = (_state & NSTimerStateMask)
        | (count << NSTimerInternalRefCountShift);
}

- (unsigned)retainCount {
    unsigned int count =
        (_state >> NSTimerInternalRefCountShift)
        & NSTimerInternalRefCountMask;

    return _NSInternalRefCount(self, count, -1);
}

- (NSDate *)fireDate {
    return _fireDate;
}

- (NSTimeInterval)timeInterval {
    return _timeInterval;
}

- (id)userInfo {
    return _userInfo;
}

- (BOOL)isValid {
    return (_state & NSTimerInvalid) == 0;
}

- (void)invalidate {
    if ((_state & NSTimerInvalid) == 0) {
        _state |= NSTimerInvalid;
        [_target release];
        _target = nil;
        [_userInfo release];
        _userInfo = nil;
    }
}

- (BOOL)_isEqualTimerWithTarget:(id)target selector:(SEL)selector
                     withObject:(id)object {
    if ((_state & NSTimerUserInfoIsArgument) != 0
        && _selector == selector
        && (_target == target || [_target isEqual:target])
        && (_userInfo == object || [_userInfo isEqual:object]))
        return YES;
    return NO;
}

- (void)fire {
    if ((_state & (NSTimerFiring | NSTimerInvalid)) != 0)
        return;

    _state |= NSTimerFiring;
    NS_DURING
        id argument = (_state & NSTimerUserInfoIsArgument) != 0
            ? _userInfo : self;
        objc_msgSend(_target, _selector, argument);
    NS_HANDLER
        NSLog(@"%@: ignoring exception '%@' (reason '%@') that raised during posting of timer with target %x and selector '%s'",
              _NSMethodExceptionProem(self, _cmd), [localException name],
              [localException reason], (unsigned int)_target,
              _selector);
    NS_ENDHANDLER
    _state &= ~NSTimerFiring;

    if ((_state & (NSTimerRepeats | NSTimerInvalid)) == NSTimerRepeats) {
        NSTimeInterval nextFireTime = [_fireDate timeIntervalSinceReferenceDate]
            + _timeInterval;
        NSTimeInterval currentTime = (NSTimeInterval)_NSCurrentTime();

        [_fireDate release];
#if defined(__ppc__) || defined(__POWERPC__)
        if (!(nextFireTime >= currentTime))
            nextFireTime = currentTime;
#else
        if (nextFireTime < currentTime)
            nextFireTime = currentTime;
#endif
        _fireDate = [[NSDate allocWithZone:NULL]
            initWithTimeIntervalSinceReferenceDate:nextFireTime];
    } else {
        [self invalidate];
    }
}

- (NSString *)description {
    if ((_state & NSTimerUserInfoIsArgument) != 0)
        return [NSString stringWithFormat:
            @"Timer [%@ %s%@]: fire date %@", _target,
            (const char *)_selector, _userInfo, _fireDate];
    return [NSString stringWithFormat:
        @"Timer (0x%x -%s): fire date %@", (unsigned int)self,
        (const char *)_selector, _fireDate];
}

- (void)dealloc {
    [self invalidate];
    [_fireDate release];
    [super dealloc];
}

@end
