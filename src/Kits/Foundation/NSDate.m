/*	NSDate.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDate.h>
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSLock.h>

#include <sys/time.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

extern NSLock *_NSGlobalRetainLock;
extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern void _NSIncrementInternalRefCount(id object, unsigned *refCount,
                                         int mask, id lock);
extern BOOL _NSDecrementInternalRefCountWasZero(id object, unsigned *refCount,
                                                int mask, id lock);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);

#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSDateRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSDateLockConcreteRetainCount(void)
{
    if (!_NSIsMultiThreaded)
        return NO;
    for (;;) {
        unsigned oldValue;
        unsigned acquired;
        unsigned one = 1;

        __asm__ volatile(
            "1: lwarx %0,0,%2\n\t"
            "cmpwi %0,0\n\t"
            "bne- 2f\n\t"
            "stwcx. %3,0,%2\n\t"
            "bne- 1b\n\t"
            "isync\n\t"
            "li %1,1\n\t"
            "b 3f\n"
            "2: li %1,0\n"
            "3:"
            : "=&r" (oldValue), "=&r" (acquired)
            : "r" (&__NSDateRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSDateUnlockConcreteRetainCount(BOOL locked)
{
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSDateRetainLock = 0;
    }
}
#endif

@interface NSConcreteDate : NSDate {
    unsigned _refCount;
    NSTimeInterval _timeSinceInternalReference;
}

- (id)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs;

@end

@interface NSDistantDate : NSDate {
    unsigned _refCount;
    NSTimeInterval _timeInterval;
}

- (id)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs;

@end

NSDate *__NSDistantFutureDate;
NSDate *__NSDistantPastDate;

static NSTimeInterval NSCurrentTime(void)
{
    struct timeval time;

    gettimeofday(&time, 0);
    return (NSTimeInterval)(time.tv_sec - 978307200) +
           (NSTimeInterval)time.tv_usec / 1000000.0;
}

@implementation NSDate

+ (id)allocWithZone:(NSZone *)zone
{
    Class dateClass = self;

    if (self == [NSDate class])
        dateClass = [NSConcreteDate class];

    return NSAllocateObject(dateClass, 0, zone);
}

- (NSTimeInterval)timeIntervalSinceReferenceDate
{
    NSRequestConcreteImplementation(self, _cmd, [NSDate class]);
    return 0.0;
}

- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)anotherDate
{
    return [self timeIntervalSinceReferenceDate] -
           [anotherDate timeIntervalSinceReferenceDate];
}

- (NSTimeInterval)timeIntervalSinceNow
{
    return [self timeIntervalSinceReferenceDate] - NSCurrentTime();
}

- (NSTimeInterval)timeIntervalSince1970
{
    return [self timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970;
}

- (id)addTimeInterval:(NSTimeInterval)seconds
{
    NSDate *date = [(Class)self->isa allocWithZone:NULL];
    return [[date initWithTimeIntervalSinceReferenceDate:
                    [self timeIntervalSinceReferenceDate] + seconds] autorelease];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSDate *date = [NSConcreteDate allocWithZone:zone];
    return [date initWithTimeIntervalSinceReferenceDate:
                    [self timeIntervalSinceReferenceDate]];
}

- (NSDate *)earlierDate:(NSDate *)anotherDate
{
    NSDate *date = [self timeIntervalSinceReferenceDate] <
                   [anotherDate timeIntervalSinceReferenceDate] ? self : anotherDate;
    return [[date copy] autorelease];
}

- (NSDate *)laterDate:(NSDate *)anotherDate
{
    NSDate *date = [self timeIntervalSinceReferenceDate] >
                   [anotherDate timeIntervalSinceReferenceDate] ? self : anotherDate;
    return [[date copy] autorelease];
}

- (NSComparisonResult)compare:(NSDate *)other
{
    NSTimeInterval interval = [self timeIntervalSinceReferenceDate];
    NSTimeInterval otherInterval = [other timeIntervalSinceReferenceDate];

#if defined(__ppc__) || defined(__POWERPC__)
    if (interval >= otherInterval)
        return interval > otherInterval ? NSOrderedDescending : NSOrderedSame;
    return NSOrderedAscending;
#else
    if (interval < otherInterval)
        return NSOrderedAscending;
    if (interval > otherInterval)
        return NSOrderedDescending;
    return NSOrderedSame;
#endif
}

- (NSString *)description
{
    return [self descriptionWithLocale:nil];
}

- (BOOL)isEqualToDate:(NSDate *)otherDate
{
    return [self timeIntervalSinceReferenceDate] ==
           [otherDate timeIntervalSinceReferenceDate];
}

- (Class)classForCoder
{
    return [NSDate class];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSTimeInterval interval = [self timeIntervalSinceReferenceDate];
    [coder encodeValueOfObjCType:"d" at:&interval];
}

- (id)initWithCoder:(NSCoder *)coder
{
    NSTimeInterval interval;
    [coder decodeValueOfObjCType:"d" at:&interval];
    return [self initWithTimeIntervalSinceReferenceDate:interval];
}

- (id)initWithDate:(NSDate *)date
{
    return [self initWithTimeIntervalSinceReferenceDate:
                    [date timeIntervalSinceReferenceDate]];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder
{
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (object == nil || ![object isKindOfClass:[NSDate class]])
        return NO;
    return [self isEqualToDate:object];
}

- (unsigned)hash
{
    int interval = (int)[self timeIntervalSinceReferenceDate];
    return (unsigned)interval;
}

+ (NSTimeInterval)timeIntervalSinceReferenceDate
{
    return NSCurrentTime();
}

+ (id)date
{
    NSDate *date;
    NSTimeInterval interval;

#if defined(__ppc__) || defined(__POWERPC__)
    date = [self allocWithZone:NULL];
    interval = NSCurrentTime();
#else
    interval = NSCurrentTime();
    date = [self allocWithZone:NULL];
#endif

    return [[date initWithTimeIntervalSinceReferenceDate:interval] autorelease];
}

+ (id)dateWithDate:(NSDate *)date
{
    return [self initWithTimeIntervalSinceReferenceDate:
                    [date timeIntervalSinceReferenceDate]];
}

+ (id)dateWithTimeIntervalSinceNow:(NSTimeInterval)secs
{
    NSDate *date;
    NSTimeInterval interval;

#if defined(__ppc__) || defined(__POWERPC__)
    date = [self allocWithZone:NULL];
    interval = NSCurrentTime() + secs;
#else
    interval = NSCurrentTime() + secs;
    date = [self allocWithZone:NULL];
#endif

    return [[date initWithTimeIntervalSinceReferenceDate:interval] autorelease];
}

+ (id)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs
{
    return [[[self allocWithZone:NULL] initWithTimeIntervalSinceReferenceDate:secs]
        autorelease];
}

+ (id)dateWithTimeIntervalSince1970:(NSTimeInterval)secs
{
    return [[[self allocWithZone:NULL] initWithTimeIntervalSinceReferenceDate:
                    secs - NSTimeIntervalSince1970] autorelease];
}

+ (id)dateWithTimeInterval:(NSTimeInterval)secs sinceDate:(NSDate *)anotherDate
{
    NSDate *date;
    NSTimeInterval interval;

#if defined(__ppc__) || defined(__POWERPC__)
    date = [self allocWithZone:NULL];
    interval = [anotherDate timeIntervalSinceReferenceDate] + secs;
#else
    interval = [anotherDate timeIntervalSinceReferenceDate] + secs;
    date = [self allocWithZone:NULL];
#endif

    return [[date initWithTimeIntervalSinceReferenceDate:interval] autorelease];
}

+ (id)distantFuture
{
    return __NSDistantFutureDate;
}

+ (id)distantPast
{
    return __NSDistantPastDate;
}

- (id)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs
{
    NSRequestConcreteImplementation(self, _cmd, [NSDate class]);
    return nil;
}

- (id)initWithTimeInterval:(NSTimeInterval)secs sinceDate:(NSDate *)anotherDate
{
    return [self initWithTimeIntervalSinceReferenceDate:
                    [anotherDate timeIntervalSinceReferenceDate] + secs];
}

- (id)initWithTimeIntervalSinceNow:(NSTimeInterval)secs
{
    return [self initWithTimeIntervalSinceReferenceDate:NSCurrentTime() + secs];
}

- (id)initWithTimeIntervalSince1970:(NSTimeInterval)secs
{
    return [self initWithTimeIntervalSinceReferenceDate:secs - NSTimeIntervalSince1970];
}

@end

@implementation NSDistantDate

- (NSTimeInterval)timeIntervalSinceReferenceDate
{
    return _timeInterval;
}

- (NSTimeInterval)timeIntervalSinceNow
{
    return _timeInterval;
}

- (NSTimeInterval)timeIntervalSince1970
{
    return _timeInterval;
}

- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)anotherDate
{
    return _timeInterval;
}

- (id)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs
{
    _timeInterval = secs;
    return self;
}

- (id)init
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInternalInconsistencyException
                format:@"%@: shouldn't be called", proem];
    return nil;
}

- (id)addTimeInterval:(NSTimeInterval)seconds
{
    return self;
}

- (NSDate *)earlierDate:(NSDate *)anotherDate
{
    if (_timeInterval < 0.0)
        return self;
    return [[anotherDate copy] autorelease];
}

- (NSDate *)laterDate:(NSDate *)anotherDate
{
    if (_timeInterval > 0.0)
        return self;
    return [[anotherDate copy] autorelease];
}

- (NSComparisonResult)compare:(NSDate *)other
{
    if (self == other)
        return NSOrderedSame;
    return _timeInterval < 0.0 ? NSOrderedAscending : NSOrderedDescending;
}

- (BOOL)isEqualToDate:(NSDate *)otherDate
{
    return self == otherDate;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)retain
{
    return self;
}

- (oneway void)release
{
}

- (id)autorelease
{
    return self;
}

- (unsigned)retainCount
{
    return (unsigned)-1;
}

- (void)dealloc
{
    [super dealloc];
}

@end

@implementation NSConcreteDate

- (id)init
{
    return [self initWithTimeIntervalSinceReferenceDate:NSCurrentTime()];
}

- (NSTimeInterval)timeIntervalSinceReferenceDate
{
    return _timeSinceInternalReference;
}

- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return [self retain];
}

- (id)retain
{
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSDateLockConcreteRetainCount();

    if (_refCount != 0xffffffffU)
        ++_refCount;
    NSDateUnlockConcreteRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
#else
    _NSIncrementInternalRefCount(self, &_refCount, -1, _NSGlobalRetainLock);
#endif
    return self;
}

- (oneway void)release
{
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSDateLockConcreteRetainCount();
    if (_refCount != 0) {
        if (_refCount != 0xffffffffU)
            --_refCount;
    } else {
        shouldDeallocate = YES;
    }
    NSDateUnlockConcreteRetainCount(locked);
    if (shouldDeallocate)
        [self dealloc];
#else
    if (_NSDecrementInternalRefCountWasZero(self, &_refCount, -1,
                                             _NSGlobalRetainLock))
        [self dealloc];
#endif
}

- (unsigned)retainCount
{
#if defined(__ppc__) || defined(__POWERPC__)
    return _refCount + 1;
#else
    return _NSInternalRefCount(self, _refCount, -1);
#endif
}

- (void)dealloc
{
    [super dealloc];
}

- (id)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs
{
    _timeSinceInternalReference = secs;
    return self;
}

@end
