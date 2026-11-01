/*	NSDecimalNumber.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDecimalNumber.h>
#import <Foundation/NSMutableDictionary.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

NSString * const NSDecimalNumberExactnessException = @"NSDecimalNumberExactnessException";
NSString * const NSDecimalNumberOverflowException = @"NSDecimalNumberOverflowException";
NSString * const NSDecimalNumberUnderflowException = @"NSDecimalNumberUnderflowException";
NSString * const NSDecimalNumberDivideByZeroException = @"NSDecimalNumberDivideByZeroException";

static NSString * const NSDecimalNumberBehaviorsKey = @"NSDecimalNumberBehaviors";

extern NSLock *_NSGlobalRetainLock;

@interface NSDecimalNumberPlaceholder : NSObject {
@public
    NSZone *zoneForInstance;
}
- (id)initWithDecimal:(NSDecimal)decimal;
- (id)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)negative;
- (id)initWithString:(NSString *)string;
- (id)initWithString:(NSString *)string locale:(NSDictionary *)locale;
- (id)initWithBool:(BOOL)value;
- (id)initWithChar:(char)value;
- (id)initWithShort:(short)value;
- (id)initWithInt:(int)value;
- (id)initWithLong:(long)value;
- (id)initWithLongLong:(long long)value;
- (id)initWithUnsignedChar:(unsigned char)value;
- (id)initWithUnsignedShort:(unsigned short)value;
- (id)initWithUnsignedInt:(unsigned int)value;
- (id)initWithUnsignedLong:(unsigned long)value;
- (id)initWithUnsignedLongLong:(unsigned long long)value;
- (id)initWithFloat:(float)value;
- (id)initWithDouble:(double)value;
@end
#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSDecimalNumberPlaceholderLock;
extern volatile unsigned int __NSNumberRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSDecimalNumberRetainLockAcquire(void) {
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
            : "r" (&__NSNumberRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSDecimalNumberRetainLockRelease(BOOL locked) {
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSNumberRetainLock = 0;
    }
}

static void NSDecimalNumberPlaceholderLockAcquire(void) {
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
            : "r" (&__NSDecimalNumberPlaceholderLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return;
        cthread_yield();
    }
}

static void NSDecimalNumberPlaceholderLockRelease(void) {
    __asm__ volatile("sync" ::: "memory");
    __NSDecimalNumberPlaceholderLock = 0;
}
#else
NSLock *_NSPlaceholderDecimalNumberLock;
#endif
static NSMutableArray *NSDecimalNumberPlaceholders;
static NSDecimalNumberPlaceholder *NSCachedDecimalNumberPlaceholder;
static Class NSDecimalNumberConstantClass;

static NSDecimalNumberPlaceholder *NSDecimalNumberPlaceholderForZone(
    NSZone *zone) {
    NSDecimalNumberPlaceholder *placeholder;
    int index;

#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSIsMultiThreaded)
        NSDecimalNumberPlaceholderLockAcquire();
#else
    if (_NSPlaceholderDecimalNumberLock != nil)
        [_NSPlaceholderDecimalNumberLock lock];
#endif

    placeholder = NSCachedDecimalNumberPlaceholder;
    if (placeholder == nil || placeholder->zoneForInstance != zone) {
        if (NSDecimalNumberPlaceholders == nil) {
            NSDecimalNumberPlaceholders = [[NSMutableArray allocWithZone:NULL]
                initWithCapacity:8];
            placeholder = nil;
        } else {
            for (index = (int)[NSDecimalNumberPlaceholders count] - 1;
                 index >= 0; index--) {
                placeholder = [NSDecimalNumberPlaceholders
                    objectAtIndex:(unsigned)index];
                if (placeholder->zoneForInstance == zone)
                    break;
            }
            if (index < 0)
                placeholder = nil;
        }

        if (placeholder == nil) {
            placeholder = NSAllocateObject([NSDecimalNumberPlaceholder class],
                                           0, NULL);
            placeholder->zoneForInstance = zone;
            [NSDecimalNumberPlaceholders addObject:placeholder];
        }
        NSCachedDecimalNumberPlaceholder = placeholder;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSIsMultiThreaded)
        NSDecimalNumberPlaceholderLockRelease();
#else
    if (_NSPlaceholderDecimalNumberLock != nil)
        [_NSPlaceholderDecimalNumberLock unlock];
#endif
    return placeholder;
}

static NSDecimalNumber *NSDecimalNumberFinishOperation(
    NSCalculationError error, SEL operation, NSDecimalNumber *leftOperand,
    NSDecimalNumber *rightOperand, short scale, NSRoundingMode roundingMode,
    id <NSDecimalNumberBehaviors> behavior, NSDecimal *result) {
    if (error != NSCalculationNoError) {
        NSDecimalNumber *replacement = [behavior
            exceptionDuringOperation:operation
            error:error
            leftOperand:leftOperand
            rightOperand:rightOperand];
        if (replacement != nil) {
            if (scale == NSDecimalNoScale)
                return replacement;
            *result = [replacement decimalValue];
        }
    }

    if (scale != NSDecimalNoScale) {
        NSDecimal rounded;
        NSDecimalRound(&rounded, result, scale, roundingMode);
        *result = rounded;
    }
    return [NSDecimalNumber decimalNumberWithDecimal:*result];
}

@implementation NSDecimalNumber

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSDecimalNumber class])
        return NSDecimalNumberPlaceholderForZone(zone);
    return NSAllocateObject(self, 0, zone);
}

- (id)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)flag {
    [NSException raise:NSInternalInconsistencyException
                format:@"Did you forget to nest alloc and initWithDecimal: ?"];
    return nil;
}

- (id)initWithDecimal:(NSDecimal)decimal {
    [NSException raise:NSInternalInconsistencyException
                format:@"Did you forget to nest alloc and initWithDecimal: ?"];
    return nil;
}

- (id)initWithString:(NSString *)numberValue {
    [NSException raise:NSInternalInconsistencyException
                format:@"Did you forget to nest alloc and initWithDecimal: ?"];
    return nil;
}

- (id)initWithString:(NSString *)numberValue locale:(NSDictionary *)locale {
    [NSException raise:NSInternalInconsistencyException
                format:@"Did you forget to nest alloc and initWithDecimal: ?"];
    return nil;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    return NSDecimalString((const NSDecimal *)((const char *)self + sizeof(id)), locale);
}

- (NSString *)description {
    return [self descriptionWithLocale:nil];
}

- (Class)classForCoder {
    static Class decimalNumberClass;

    if (decimalNumberClass == Nil)
        decimalNumberClass = [NSDecimalNumber class];
    return decimalNumberClass;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    NSDecimal decimal = [self decimalValue];
    int exponent = decimal._exponent;
    unsigned short length = decimal._length & 0x0f;
    unsigned char isNegative = decimal._isNegative != 0;
    unsigned char isCompact = decimal._isCompact != 0;
    unsigned count = NSDecimalMaxSize;

    [coder encodeValueOfObjCType:"i" at:&exponent];
    [coder encodeValueOfObjCType:"S" at:&length];
    [coder encodeValueOfObjCType:"C" at:&isNegative];
    [coder encodeValueOfObjCType:"C" at:&isCompact];
    [coder encodeValueOfObjCType:"I" at:&count];
    [coder encodeArrayOfObjCType:"S" count:count at:decimal._mantissa];
}

- (id)initWithCoder:(NSCoder *)coder {
    (void)coder;
    [NSException raise:NSInvalidArgumentException
                format:@"Did you forget to nest alloc and initWithCoder: ?"];
    return nil;
}

- (id)replacementObjectForCoder:(NSCoder *)coder {
    (void)coder;
    return self;
}

- (NSDecimal)decimalValue {
    NSDecimal decimal;
    NSDecimalCopy(&decimal,
        (const NSDecimal *)((const char *)self + sizeof(id)));
    return decimal;
}

- (id)copyWithZone:(NSZone *)zone {
    NSDecimal decimal;
    NSDecimalNumber *copy;

    if (NSShouldRetainWithZone(self, zone))
        return [self retain];
#if defined(__ppc__) || defined(__POWERPC__)
    copy = NSDecimalNumberPlaceholderForZone(zone);
    decimal = [self decimalValue];
#else
    decimal = [self decimalValue];
    copy = NSDecimalNumberPlaceholderForZone(zone);
#endif
    return [copy initWithDecimal:decimal];
}

- (id)copy {
    return [self retain];
}

- (id)retain {
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSDecimalNumberRetainLockAcquire();
#else
    NSLock *lock = _NSGlobalRetainLock;

    if (lock != nil)
        [lock lock];
#endif
    if (_refs == 0xffff) {
        _refs = 0;
        if (_hasExternalRefCount)
            NSIncrementExtraRefCount(self);
        _hasExternalRefCount = 1;
    } else {
        _refs++;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    NSDecimalNumberRetainLockRelease(locked);
#else
    if (lock != nil)
        [lock unlock];
#endif
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked;
#else
    NSLock *lock = _NSGlobalRetainLock;
#endif
    BOOL extraReferenceRemains;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
#if defined(__ppc__) || defined(__POWERPC__)
    locked = NSDecimalNumberRetainLockAcquire();
#else
    if (lock != nil)
        [lock lock];
#endif
    if (_refs != 0) {
        _refs--;
#if defined(__ppc__) || defined(__POWERPC__)
        NSDecimalNumberRetainLockRelease(locked);
#else
        if (lock == nil)
            return;
        [lock unlock];
#endif
        return;
    }
    if (!_hasExternalRefCount) {
#if defined(__ppc__) || defined(__POWERPC__)
        NSDecimalNumberRetainLockRelease(locked);
#else
        if (lock != nil)
            [lock unlock];
#endif
        [super dealloc];
        return;
    }

    extraReferenceRemains = !NSDecrementExtraRefCountWasZero(self);
    _hasExternalRefCount = extraReferenceRemains;
    _refs = 0xffff;
#if defined(__ppc__) || defined(__POWERPC__)
    NSDecimalNumberRetainLockRelease(locked);
#else
    if (lock != nil)
        [lock unlock];
#endif
}

- (unsigned)retainCount {
    unsigned count = (unsigned)_refs + 1;

    if (_hasExternalRefCount)
        count += (NSExtraRefCount(self) << 16) + 0x10000;
    return count;
}

+ (NSDecimalNumber *)decimalNumberWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)flag {
    return (NSDecimalNumber *)[[NSDecimalNumberPlaceholderForZone(NULL)
        initWithMantissa:mantissa exponent:exponent isNegative:flag] autorelease];
}

+ (NSDecimalNumber *)decimalNumberWithDecimal:(NSDecimal)decimal {
    return (NSDecimalNumber *)[[NSDecimalNumberPlaceholderForZone(NULL)
        initWithDecimal:decimal] autorelease];
}

+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue {
    return (NSDecimalNumber *)[[NSDecimalNumberPlaceholderForZone(NULL)
        initWithString:numberValue] autorelease];
}

+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue locale:(NSDictionary *)locale {
    return (NSDecimalNumber *)[[NSDecimalNumberPlaceholderForZone(NULL)
        initWithString:numberValue locale:locale] autorelease];
}


+ (NSDecimalNumber *)zero {
    static NSDecimalNumber *number;

    if (number == nil) {
        if (NSDecimalNumberConstantClass == Nil)
            NSDecimalNumberConstantClass = [NSDecimalNumber class];
        number = (NSDecimalNumber *)NSAllocateObject(
            NSDecimalNumberConstantClass, 0, NULL);
    }
    return number;
}

+ (NSDecimalNumber *)one {
    static NSDecimalNumber *number;

    if (number == nil) {
        NSDecimal *decimal;
        if (NSDecimalNumberConstantClass == Nil)
            NSDecimalNumberConstantClass = [NSDecimalNumber class];
        number = (NSDecimalNumber *)NSAllocateObject(
            NSDecimalNumberConstantClass, sizeof(unsigned short), NULL);
        decimal = (NSDecimal *)((char *)number + sizeof(id));
        decimal->_length = 1;
        decimal->_mantissa[0] = 1;
    }
    return number;
}

+ (NSDecimalNumber *)minimumDecimalNumber {
    static NSDecimalNumber *number;

    if (number == nil) {
        NSDecimal decimal;
        unsigned index;
        memset(&decimal, 0, sizeof(decimal));
        decimal._exponent = 127;
        decimal._length = NSDecimalMaxSize;
        decimal._isNegative = 1;
        decimal._isCompact = 1;
        for (index = 0; index < NSDecimalMaxSize; index++)
            decimal._mantissa[index] = USHRT_MAX;
#if defined(__ppc__) || defined(__POWERPC__)
        number = [self decimalNumberWithDecimal:decimal];
#else
        number = [[self decimalNumberWithDecimal:decimal] retain];
#endif
    }
    return number;
}

+ (NSDecimalNumber *)maximumDecimalNumber {
    static NSDecimalNumber *number;

    if (number == nil) {
        NSDecimal decimal;
        unsigned index;
        memset(&decimal, 0, sizeof(decimal));
        decimal._exponent = 127;
        decimal._length = NSDecimalMaxSize;
        decimal._isCompact = 1;
        for (index = 0; index < NSDecimalMaxSize; index++)
            decimal._mantissa[index] = USHRT_MAX;
#if defined(__ppc__) || defined(__POWERPC__)
        number = [self decimalNumberWithDecimal:decimal];
#else
        number = [[self decimalNumberWithDecimal:decimal] retain];
#endif
    }
    return number;
}

+ (NSDecimalNumber *)notANumber {
    static NSDecimalNumber *number;

    if (number == nil) {
        NSDecimal *decimal;
        if (NSDecimalNumberConstantClass == Nil)
            NSDecimalNumberConstantClass = [NSDecimalNumber class];
        number = (NSDecimalNumber *)NSAllocateObject(
            NSDecimalNumberConstantClass, 0, NULL);
        decimal = (NSDecimal *)((char *)number + sizeof(id));
        decimal->_isNegative = 1;
    }
    return number;
}

- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)decimalNumber {
    return [self decimalNumberByAdding:decimalNumber
                          withBehavior:[NSDecimalNumber defaultBehavior]];
}

- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)decimalNumber withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    short scale = [behavior scale];
    NSRoundingMode roundingMode = [behavior roundingMode];
    NSDecimal result;
    NSCalculationError error = NSDecimalAdd(
        &result,
        (const NSDecimal *)((const char *)self + sizeof(id)),
        (const NSDecimal *)((const char *)decimalNumber + sizeof(id)),
        roundingMode);

    return NSDecimalNumberFinishOperation(error, _cmd, self, decimalNumber,
                                          scale, roundingMode, behavior, &result);
}

- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)decimalNumber {
    return [self decimalNumberBySubtracting:decimalNumber
                              withBehavior:[NSDecimalNumber defaultBehavior]];
}

- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)decimalNumber withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    short scale = [behavior scale];
    NSRoundingMode roundingMode = [behavior roundingMode];
    NSDecimal result;
    NSCalculationError error = NSDecimalSubtract(
        &result,
        (const NSDecimal *)((const char *)self + sizeof(id)),
        (const NSDecimal *)((const char *)decimalNumber + sizeof(id)),
        roundingMode);

    return NSDecimalNumberFinishOperation(error, _cmd, self, decimalNumber,
                                          scale, roundingMode, behavior, &result);
}

- (NSDecimalNumber *)decimalNumberBySubstracting:(NSDecimalNumber *)decimalNumber {
    return [self decimalNumberBySubtracting:decimalNumber
                               withBehavior:[NSDecimalNumber defaultBehavior]];
}

- (NSDecimalNumber *)decimalNumberBySubstracting:(NSDecimalNumber *)decimalNumber
                                    withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    return [self decimalNumberBySubtracting:decimalNumber
                               withBehavior:behavior];
}

- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)decimalNumber {
    return [self decimalNumberByMultiplyingBy:decimalNumber
                                withBehavior:[NSDecimalNumber defaultBehavior]];
}

- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)decimalNumber withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    short scale = [behavior scale];
    NSRoundingMode roundingMode = [behavior roundingMode];
    NSDecimal result;
    NSCalculationError error = NSDecimalMultiply(
        &result,
        (const NSDecimal *)((const char *)self + sizeof(id)),
        (const NSDecimal *)((const char *)decimalNumber + sizeof(id)),
        roundingMode);

    return NSDecimalNumberFinishOperation(error, _cmd, self, decimalNumber,
                                          scale, roundingMode, behavior, &result);
}

- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)decimalNumber {
    return [self decimalNumberByDividingBy:decimalNumber
                             withBehavior:[NSDecimalNumber defaultBehavior]];
}

- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)decimalNumber withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    short scale = [behavior scale];
    NSRoundingMode roundingMode = [behavior roundingMode];
    NSDecimal result;
    NSCalculationError error = NSDecimalDivide(
        &result,
        (const NSDecimal *)((const char *)self + sizeof(id)),
        (const NSDecimal *)((const char *)decimalNumber + sizeof(id)),
        roundingMode);

    return NSDecimalNumberFinishOperation(error, _cmd, self, decimalNumber,
                                          scale, roundingMode, behavior, &result);
}

- (NSDecimalNumber *)decimalNumberByRaisingToPower:(unsigned)power {
    return [self decimalNumberByRaisingToPower:power
                                 withBehavior:[NSDecimalNumber defaultBehavior]];
}

- (NSDecimalNumber *)decimalNumberByRaisingToPower:(unsigned)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    short scale = [behavior scale];
    NSRoundingMode roundingMode = [behavior roundingMode];
    NSDecimal result;
    NSCalculationError error = NSDecimalPower(
        &result, (const NSDecimal *)((const char *)self + sizeof(id)), power,
        roundingMode);

    return NSDecimalNumberFinishOperation(error, _cmd, self, nil, scale,
                                          roundingMode, behavior, &result);
}

- (NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(short)power {
    return [self decimalNumberByMultiplyingByPowerOf10:power
                                         withBehavior:[NSDecimalNumber defaultBehavior]];
}

- (NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(short)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    short scale = [behavior scale];
    NSRoundingMode roundingMode = [behavior roundingMode];
    NSDecimal result;
    NSCalculationError error = NSDecimalMultiplyByPowerOf10(
        &result, (const NSDecimal *)((const char *)self + sizeof(id)), power,
        roundingMode);

    return NSDecimalNumberFinishOperation(error, _cmd, self, nil, scale,
                                          roundingMode, behavior, &result);
}

- (NSDecimalNumber *)decimalNumberByRoundingAccordingToBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    short scale = [behavior scale];
    NSRoundingMode roundingMode;
    NSDecimal result;

    if (scale == NSDecimalNoScale)
        return [[self retain] autorelease];
    roundingMode = [behavior roundingMode];
    NSDecimalRound(&result,
                   (const NSDecimal *)((const char *)self + sizeof(id)),
                   scale, roundingMode);
    return [NSDecimalNumber decimalNumberWithDecimal:result];
}

- (NSComparisonResult)compare:(NSNumber *)decimalNumber {
    NSDecimal other;
    const NSDecimal *rightOperand;

    if ([decimalNumber isKindOfClass:[NSDecimalNumber class]])
        rightOperand = (const NSDecimal *)((const char *)decimalNumber + sizeof(id));
    else {
        other = [decimalNumber decimalValue];
        rightOperand = &other;
    }
    return NSDecimalCompare((const NSDecimal *)((const char *)self + sizeof(id)),
                            rightOperand);
}

- (BOOL)isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass:[NSNumber class]])
        return NO;
    return [self compare:object] == NSOrderedSame;
}

+ (void)setDefaultBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    NSThread *thread = [NSThread currentThread];
    [[thread threadDictionary] setObject:behavior forKey:NSDecimalNumberBehaviorsKey];
}

+ (id <NSDecimalNumberBehaviors>)defaultBehavior {
    NSThread *thread = [NSThread currentThread];
    id behavior = [[thread threadDictionary] objectForKey:NSDecimalNumberBehaviorsKey];

    if (behavior == nil)
        behavior = [NSDecimalNumberHandler defaultDecimalNumberHandler];
    return (id <NSDecimalNumberBehaviors>)behavior;
}

- (const char *)objCType {
    return "d";
}

- (double)doubleValue {
    const NSDecimal *decimal =
        (const NSDecimal *)((const char *)self + sizeof(id));
#if defined(__ppc__) || defined(__POWERPC__)
    double value = 0.0;
    int index;

    for (index = (int)decimal->_length; index > 0; ) {
        index--;
        value = value * 65536.0 + decimal->_mantissa[index];
    }
    if (decimal->_exponent > 0) {
        for (index = decimal->_exponent; index > 0; index--)
            value *= 10.0;
    } else {
        for (index = decimal->_exponent; index < 0; index++)
            value /= 10.0;
    }
    if (decimal->_isNegative)
        value = -value;
    return value;
#else
    long double value = 0.0L;
    int index;

    for (index = (int)decimal->_length; index > 0; ) {
        index--;
        value = value * 65536.0L + decimal->_mantissa[index];
    }
    if (decimal->_exponent > 0) {
        for (index = decimal->_exponent; index > 0; index--)
            value *= 10.0L;
    } else {
        for (index = decimal->_exponent; index < 0; index++)
            value /= 10.0L;
    }
    if (decimal->_isNegative)
        value = -value;
    return (double)value;
#endif
}

- (BOOL)boolValue {
    return (BOOL)(int)[self doubleValue];
}

- (char)charValue {
    return (char)(int)[self doubleValue];
}

- (short)shortValue {
    return (short)(int)[self doubleValue];
}

- (int)intValue {
    return (int)[self doubleValue];
}

- (long)longValue {
    return (long)(int)[self doubleValue];
}

- (long long)longLongValue {
    return (long long)[self doubleValue];
}

- (unsigned char)unsignedCharValue {
#if defined(__ppc__) || defined(__POWERPC__)
    return (unsigned char)(int)[self doubleValue];
#else
    return (unsigned char)(long long)[self doubleValue];
#endif
}

- (unsigned short)unsignedShortValue {
#if defined(__ppc__) || defined(__POWERPC__)
    return (unsigned short)(int)[self doubleValue];
#else
    return (unsigned short)(long long)[self doubleValue];
#endif
}

- (unsigned int)unsignedIntValue {
#if defined(__ppc__) || defined(__POWERPC__)
    double value = [self doubleValue];
    if (value >= 2147483648.0)
        return (unsigned int)((int)(value - 2147483648.0) ^ 0x80000000);
    return (unsigned int)(int)value;
#else
    return (unsigned int)(long long)[self doubleValue];
#endif
}

- (unsigned long)unsignedLongValue {
#if defined(__ppc__) || defined(__POWERPC__)
    double value = [self doubleValue];
    if (value >= 2147483648.0)
        return (unsigned long)((int)(value - 2147483648.0) ^ 0x80000000);
    return (unsigned long)(int)value;
#else
    return (unsigned long)(long long)[self doubleValue];
#endif
}

- (unsigned long long)unsignedLongLongValue {
    return (unsigned long long)(double)[self doubleValue];
}

- (float)floatValue {
    return (float)[self doubleValue];
}

- (void)getValue:(void *)value {
    double decimalValue = [self doubleValue];
    memmove(value, &decimalValue, sizeof(decimalValue));
}

@end

@implementation NSDecimalNumber (NSNumberCompatibility)

+ (NSDecimalNumber *)numberWithBool:(BOOL)value {
    return [[[NSDecimalNumber allocWithZone:NULL] initWithBool:value] autorelease];
}

+ (NSDecimalNumber *)numberWithChar:(char)value {
    return [[[NSDecimalNumber allocWithZone:NULL] initWithChar:value] autorelease];
}

+ (NSDecimalNumber *)numberWithShort:(short)value {
    return [[[NSDecimalNumber allocWithZone:NULL] initWithShort:value] autorelease];
}

+ (NSDecimalNumber *)numberWithInt:(int)value {
    return [[[NSDecimalNumber allocWithZone:NULL] initWithInt:value] autorelease];
}

+ (NSDecimalNumber *)numberWithLong:(long)value {
    return [[[NSDecimalNumber allocWithZone:NULL] initWithLong:value] autorelease];
}

+ (NSDecimalNumber *)numberWithLongLong:(long long)value {
    return [[[NSDecimalNumber allocWithZone:NULL] initWithLongLong:value] autorelease];
}

+ (NSDecimalNumber *)numberWithUnsignedChar:(unsigned char)value {
    return [[[NSDecimalNumber allocWithZone:NULL]
        initWithUnsignedChar:value] autorelease];
}

+ (NSDecimalNumber *)numberWithUnsignedShort:(unsigned short)value {
    return [[[NSDecimalNumber allocWithZone:NULL]
        initWithUnsignedShort:value] autorelease];
}

+ (NSDecimalNumber *)numberWithUnsignedInt:(unsigned int)value {
    return [[[NSDecimalNumber allocWithZone:NULL]
        initWithUnsignedInt:value] autorelease];
}

+ (NSDecimalNumber *)numberWithUnsignedLong:(unsigned long)value {
    return [[[NSDecimalNumber allocWithZone:NULL]
        initWithUnsignedLong:value] autorelease];
}

+ (NSDecimalNumber *)numberWithUnsignedLongLong:(unsigned long long)value {
    return [[[NSDecimalNumber allocWithZone:NULL]
        initWithUnsignedLongLong:value] autorelease];
}

+ (NSDecimalNumber *)numberWithFloat:(float)value {
    return [[[NSDecimalNumber allocWithZone:NULL] initWithFloat:value] autorelease];
}

+ (NSDecimalNumber *)numberWithDouble:(double)value {
    return [[[NSDecimalNumber allocWithZone:NULL] initWithDouble:value] autorelease];
}

@end

@implementation NSDecimalNumberPlaceholder

#if defined(__ppc__) || defined(__POWERPC__)
+ (id)allocWithZone:(NSZone *)zone {
    return NSDecimalNumberPlaceholderForZone(zone);
}
#endif

- (id)initWithCoder:(NSCoder *)coder {
    NSDecimal decimal;
    int exponent;
    unsigned short length;
    unsigned char isNegative;
    unsigned char isCompact;
    unsigned count;

    memset(&decimal, 0, sizeof(decimal));
    [coder decodeValueOfObjCType:"i" at:&exponent];
    [coder decodeValueOfObjCType:"S" at:&length];
    [coder decodeValueOfObjCType:"C" at:&isNegative];
    [coder decodeValueOfObjCType:"C" at:&isCompact];
    decimal._exponent = exponent;
    decimal._length = length & 0x0f;
    decimal._isNegative = isNegative != 0;
    decimal._isCompact = isCompact != 0;
    [coder decodeValueOfObjCType:"I" at:&count];
    [coder decodeArrayOfObjCType:"S" count:count at:decimal._mantissa];
    return [self initWithDecimal:decimal];
}

- (id)initWithDecimal:(NSDecimal)decimal {
    NSDecimalCompact(&decimal);
    NSDecimalNumber *number = (NSDecimalNumber *)NSAllocateObject(
        [NSDecimalNumber class], decimal._length * sizeof(unsigned short),
        zoneForInstance);
    NSDecimalCopy((NSDecimal *)((char *)number + sizeof(id)), &decimal);
    return number;
}

- (id)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)negative {
    NSDecimal decimal;
    memset(&decimal, 0, sizeof(decimal));
    decimal._exponent = exponent;
    decimal._isNegative = negative;
    while (mantissa != 0 && decimal._length < NSDecimalMaxSize) {
        decimal._mantissa[decimal._length++] = (unsigned short)mantissa;
        mantissa >>= 16;
    }
    return [self initWithDecimal:decimal];
}

- (id)initWithString:(NSString *)string {
    return [self initWithString:string locale:nil];
}

- (id)initWithString:(NSString *)string locale:(NSDictionary *)locale {
    NSScanner *scanner = [[NSScanner allocWithZone:NULL] initWithString:string];
    NSDecimal decimal;
    id result;

    if (locale != nil)
        [scanner setLocale:locale];
    if ([scanner scanDecimal:&decimal])
        result = [self initWithDecimal:decimal];
    else
        result = [self init];
    [scanner release];
    return result;
}

- (id)init {
    return [[NSDecimalNumber notANumber] copyWithZone:zoneForInstance];
}

- (id)retain { return self; }
- (oneway void)release { }
- (id)autorelease { return self; }
- (unsigned)retainCount { return (unsigned)-1; }
- (void)dealloc { }

@end

@implementation NSDecimalNumberPlaceholder (NSNumberCompatibility)

- (id)initWithBool:(BOOL)value {
    return [self initWithLongLong:(long long)value];
}

- (id)initWithChar:(char)value {
    return [self initWithLongLong:(long long)value];
}

- (id)initWithShort:(short)value {
    return [self initWithLongLong:(long long)value];
}

- (id)initWithInt:(int)value {
    return [self initWithLongLong:(long long)value];
}

- (id)initWithLong:(long)value {
    return [self initWithLongLong:(long long)value];
}

- (id)initWithLongLong:(long long)value {
    unsigned long long magnitude = value < 0
        ? 0ULL - (unsigned long long)value : (unsigned long long)value;
    return [self initWithMantissa:magnitude exponent:0 isNegative:value < 0];
}

- (id)initWithUnsignedChar:(unsigned char)value {
    return [self initWithUnsignedLongLong:(unsigned long long)value];
}

- (id)initWithUnsignedShort:(unsigned short)value {
    return [self initWithUnsignedLongLong:(unsigned long long)value];
}

- (id)initWithUnsignedInt:(unsigned int)value {
    return [self initWithUnsignedLongLong:(unsigned long long)value];
}

- (id)initWithUnsignedLong:(unsigned long)value {
    return [self initWithUnsignedLongLong:(unsigned long long)value];
}

- (id)initWithUnsignedLongLong:(unsigned long long)value {
    return [self initWithMantissa:value exponent:0 isNegative:NO];
}

- (id)initWithFloat:(float)value {
    return [self initWithDouble:(double)value];
}

- (id)initWithDouble:(double)value {
    NSNumber *number = [NSNumber numberWithDouble:value];
    return [self initWithDecimal:[number decimalValue]];
}

@end

@implementation NSDecimalNumberHandler

+ (id)defaultDecimalNumberHandler {
    static NSDecimalNumberHandler *handler;

    if (handler == nil) {
        handler = [[self allocWithZone:NULL]
            initWithRoundingMode:NSRoundPlain
            scale:NSDecimalNoScale
            raiseOnExactness:NO
            raiseOnOverflow:YES
            raiseOnUnderflow:YES
            raiseOnDivideByZero:YES];
    }
    return handler;
}

- (id)initWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale raiseOnExactness:(BOOL)exact raiseOnOverflow:(BOOL)overflow raiseOnUnderflow:(BOOL)underflow raiseOnDivideByZero:(BOOL)divideByZero {
    (void)[super init];

    _roundingMode = roundingMode;
    _scale = scale;
    _raiseOnExactness = exact;
    _raiseOnOverflow = overflow;
    _raiseOnUnderflow = underflow;
    _raiseOnDivideByZero = divideByZero;
    return self;
}

+ (id)decimalNumberHandlerWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale raiseOnExactness:(BOOL)exact raiseOnOverflow:(BOOL)overflow raiseOnUnderflow:(BOOL)underflow raiseOnDivideByZero:(BOOL)divideByZero {
    return [[[self allocWithZone:NULL]
        initWithRoundingMode:roundingMode
        scale:scale
        raiseOnExactness:exact
        raiseOnOverflow:overflow
        raiseOnUnderflow:underflow
        raiseOnDivideByZero:divideByZero] autorelease];
}

- (NSRoundingMode)roundingMode {
    return _roundingMode;
}

- (short)scale {
    return _scale;
}

- (NSDecimalNumber *)exceptionDuringOperation:(SEL)operation
                                         error:(NSCalculationError)error
                                  leftOperand:(NSDecimalNumber *)leftOperand
                                 rightOperand:(NSDecimalNumber *)rightOperand {
    (void)operation;
    (void)leftOperand;
    (void)rightOperand;

    switch (error) {
        case NSCalculationLossOfPrecision:
            if (_raiseOnExactness)
                [NSException raise:NSDecimalNumberExactnessException
                            format:@"NSDecimalNumber exactness exception"];
            break;
        case NSCalculationUnderflow:
#if defined(__ppc__) || defined(__POWERPC__)
            if (_raiseOnUnderflow)
                [NSException raise:NSDecimalNumberUnderflowException
                            format:@"NSDecimalNumber underflow exception"];
#else
            if (_raiseOnUnderflow)
                [NSException raise:NSDecimalNumberOverflowException
                            format:@"NSDecimalNumber overflow exception"];
#endif
            break;
        case NSCalculationOverflow:
#if defined(__ppc__) || defined(__POWERPC__)
            if (_raiseOnOverflow)
                [NSException raise:NSDecimalNumberOverflowException
                            format:@"NSDecimalNumber overflow exception"];
#else
            if (_raiseOnOverflow)
                [NSException raise:NSDecimalNumberUnderflowException
                            format:@"NSDecimalNumber underflow exception"];
#endif
            break;
        case NSCalculationDivideByZero:
            if (_raiseOnDivideByZero)
                [NSException raise:NSDecimalNumberDivideByZeroException
                            format:@"NSDecimalNumber divide by zero exception"];
            break;
        case NSCalculationNoError:
            break;
    }
    return nil;
}

@end

@implementation NSString (NSDecimalExtension)

- (NSDecimal)decimalValue {
    NSDecimal decimal;
    NSScanner *scanner = [NSScanner scannerWithString:self];

    if ([scanner scanDecimal:&decimal])
        return decimal;
    return [[NSDecimalNumber notANumber] decimalValue];
}

@end

@implementation NSNumber (NSDecimalNumberExtensions)

- (NSDecimal)decimalValue {
    NSDecimal decimal;
    NSScanner *scanner = [NSScanner scannerWithString:[self stringValue]];

    if ([scanner scanDecimal:&decimal])
        return decimal;
    return [[NSDecimalNumber notANumber] decimalValue];
}

@end
