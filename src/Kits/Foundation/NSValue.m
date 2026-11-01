/*	NSValue.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSValue.h>
#import <Foundation/NSData.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#include <limits.h>
#include <math.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

typedef struct {
    unsigned size;
    const char *type;
} NSValueTypeInfo;

@interface NSConcreteValue : NSValue {
@public
    unsigned _valueType;
    NSValueTypeInfo *_typeInfo;
}
- (const void *)_value;
@end

@interface NSPlaceholderValue : NSValue {
@public
    NSZone *zoneForInstance;
}
@end

@interface NSPlaceholderNumber : NSPlaceholderValue
@end

@interface NSValueDecoder : NSObject
@end

#if defined(__ppc__) || defined(__POWERPC__)
#define NSRefCountingNumberRefCount _retainCount
#else
#define NSRefCountingNumberRefCount refs
#endif

@interface NSRefCountingNumber : NSNumber {
@public
    unsigned NSRefCountingNumberRefCount;
}
@end

@interface NSshortNumber : NSRefCountingNumber { @public short value; }
@end
@interface NSunsignedShortNumber : NSRefCountingNumber { @public unsigned short value; }
@end
@interface NSintNumber : NSRefCountingNumber { @public int value; }
@end
@interface NSunsignedIntNumber : NSRefCountingNumber { @public unsigned int value; }
@end
@interface NSlongLongNumber : NSRefCountingNumber { @public long long value; }
@end
@interface NSunsignedLongLongNumber : NSRefCountingNumber { @public unsigned long long value; }
@end
@interface NSfloatNumber : NSRefCountingNumber { @public float value; }
@end
@interface NSdoubleNumber : NSRefCountingNumber { @public double value; }
@end

extern NSLock *_NSGlobalRetainLock;
extern void _NSIncrementInternalRefCount(id object, unsigned *refCount,
                                         int mask, id lock);
extern BOOL _NSDecrementInternalRefCountWasZero(id object,
                                                 unsigned *refCount,
                                                 int mask, id lock);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);
extern id _NSMethodExceptionProem(id object, SEL selector);

static NSHashTable *NSValueTypeInfoTable;
static NSMutableArray *NSValuePlaceholders;
static NSPlaceholderValue *NSCachedPlaceholderValue;
#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSValuePlaceholderLock;
volatile unsigned int __NSNumberRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSRefCountingNumberLock(void) {
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

static void NSRefCountingNumberUnlock(BOOL locked) {
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSNumberRetainLock = 0;
    }
}

static void NSValuePlaceholderLockAcquire(void) {
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
            : "r" (&__NSValuePlaceholderLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return;
        cthread_yield();
    }
}

static void NSValuePlaceholderLockRelease(void) {
    __asm__ volatile("sync" ::: "memory");
    __NSValuePlaceholderLock = 0;
}
#else
extern NSLock *_NSPlaceholderValueLock;
#endif

static unsigned NSValueTypeInfoHash(NSHashTable *table, const void *pointer) {
    const unsigned char *type =
        (const unsigned char *)((const NSValueTypeInfo *)pointer)->type;
    unsigned hash = 0;
    unsigned shift = 0;

    (void)table;
    while (*type != '\0') {
        hash ^= (unsigned)((int)(signed char)*type << shift);
        type++;
        shift = (shift + 8) & 31;
    }
    return hash;
}

static BOOL NSValueTypeInfoEqual(NSHashTable *table, const void *left,
                                 const void *right) {
    (void)table;
    return strcmp(((const NSValueTypeInfo *)left)->type,
                  ((const NSValueTypeInfo *)right)->type) == 0;
}

static NSValueTypeInfo *NSValueTypeInfoForType(const char *type) {
    NSValueTypeInfo key;
    NSValueTypeInfo *info;
    NSHashTableCallBacks callbacks;
    unsigned length;

    key.size = 0;
    key.type = type;
    if (NSValueTypeInfoTable == NULL) {
        callbacks = NSNonOwnedPointerHashCallBacks;
        callbacks.hash = NSValueTypeInfoHash;
        callbacks.isEqual = NSValueTypeInfoEqual;
        NSValueTypeInfoTable = NSCreateHashTableWithZone(callbacks, 10, NULL);
    }

    info = (NSValueTypeInfo *)NSHashGet(NSValueTypeInfoTable, &key);
    if (info != NULL)
        return info;

    length = (unsigned)strlen(type) + 1;
    info = (NSValueTypeInfo *)NSZoneMalloc(NULL,
        (unsigned)(sizeof(NSValueTypeInfo) + length));
    info->size = 0;
    NSGetSizeAndAlignment(type, &info->size, NULL);
    info->type = (const char *)(info + 1);
    memcpy((char *)info->type, type, length);
    NSHashInsert(NSValueTypeInfoTable, info);
    return info;
}

NSConcreteValue *_NSNewValue(const void *bytes, const char *type,
                             NSZone *zone) {
    NSValueTypeInfo *info = NSValueTypeInfoForType(type);
    NSConcreteValue *value = (NSConcreteValue *)NSAllocateObject(
        [NSConcreteValue class], info->size, zone);

    value = [value init];
    value->_typeInfo = info;
    memmove((char *)value + value->isa->instance_size, bytes, info->size);
    return value;
}

static NSValue *NSNewGeometryValue(const void *bytes, const char *type,
                                  unsigned valueType) {
    NSConcreteValue *value = _NSNewValue(bytes, type, NULL);

    value->_valueType = valueType;
    return (NSValue *)[value autorelease];
}

static NSPlaceholderValue *NSPlaceholderForZone(NSZone *zone,
                                                 BOOL numberPlaceholder) {
    NSPlaceholderValue *placeholder;
    Class placeholderClass = numberPlaceholder
        ? [NSPlaceholderNumber class] : [NSPlaceholderValue class];
    int index;

#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSIsMultiThreaded)
        NSValuePlaceholderLockAcquire();
#else
    if (_NSPlaceholderValueLock != nil)
        [_NSPlaceholderValueLock lock];
#endif

    placeholder = NSCachedPlaceholderValue;
    if (placeholder == nil || placeholder->zoneForInstance != zone
        || placeholder->isa != placeholderClass) {
        if (NSValuePlaceholders == nil) {
            NSValuePlaceholders = [[NSMutableArray allocWithZone:NULL]
                initWithCapacity:8];
            placeholder = nil;
        } else {
            for (index = (int)[NSValuePlaceholders count] - 1;
                 index >= 0; index--) {
                placeholder = [NSValuePlaceholders
                    objectAtIndex:(unsigned)index];
                if (placeholder->zoneForInstance == zone
                    && placeholder->isa == placeholderClass)
                    break;
            }
            if (index < 0)
                placeholder = nil;
        }

        if (placeholder == nil) {
            placeholder = NSAllocateObject(placeholderClass, 0, NULL);
            placeholder->zoneForInstance = zone;
            [NSValuePlaceholders addObject:placeholder];
            [placeholder release];
        }
        NSCachedPlaceholderValue = placeholder;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSIsMultiThreaded)
        NSValuePlaceholderLockRelease();
#else
    if (_NSPlaceholderValueLock != nil)
        [_NSPlaceholderValueLock unlock];
#endif
    return placeholder;
}

static NSPlaceholderValue *NSValuePlaceholderForZone(NSZone *zone) {
    return NSPlaceholderForZone(zone, NO);
}

static NSPlaceholderNumber *NSNumberPlaceholderForZone(NSZone *zone) {
    return (NSPlaceholderNumber *)NSPlaceholderForZone(zone, YES);
}

static NSNumber *NSNumberCreateShort(short value, NSZone *zone) {
    NSshortNumber *number = (NSshortNumber *)NSAllocateObject(
        [NSshortNumber class], 0, zone);
    number->value = value;
    return number;
}

static NSNumber *NSNumberCreateUnsignedShort(unsigned short value,
                                             NSZone *zone) {
    NSunsignedShortNumber *number = (NSunsignedShortNumber *)NSAllocateObject(
        [NSunsignedShortNumber class], 0, zone);
    number->value = value;
    return number;
}

static NSNumber *NSNumberCreateInt(int value, NSZone *zone) {
    if (value >= SHRT_MIN && value <= SHRT_MAX)
        return NSNumberCreateShort((short)value, zone);
    {
        NSintNumber *number = (NSintNumber *)NSAllocateObject(
            [NSintNumber class], 0, zone);
        number->value = value;
        return number;
    }
}

static NSNumber *NSNumberCreateUnsignedInt(unsigned int value, NSZone *zone) {
    if (value <= USHRT_MAX)
        return NSNumberCreateUnsignedShort((unsigned short)value, zone);
    {
        NSunsignedIntNumber *number = (NSunsignedIntNumber *)NSAllocateObject(
            [NSunsignedIntNumber class], 0, zone);
        number->value = value;
        return number;
    }
}

static NSNumber *NSNumberCreateLongLong(long long value, NSZone *zone) {
    if ((((unsigned long long)value - 0x80000000ULL) >> 32) == 0)
        return NSNumberCreateInt((int)value, zone);
    {
        NSlongLongNumber *number = (NSlongLongNumber *)NSAllocateObject(
            [NSlongLongNumber class], 0, zone);
        number->value = value;
        return number;
    }
}

static NSNumber *NSNumberCreateUnsignedLongLong(unsigned long long value,
                                                NSZone *zone) {
    if (value <= UINT_MAX)
        return NSNumberCreateUnsignedInt((unsigned int)value, zone);
    {
        NSunsignedLongLongNumber *number =
            (NSunsignedLongLongNumber *)NSAllocateObject(
                [NSunsignedLongLongNumber class], 0, zone);
        number->value = value;
        return number;
    }
}

static NSNumber *NSNumberCreateFloat(float value, NSZone *zone) {
    NSfloatNumber *number = (NSfloatNumber *)NSAllocateObject(
        [NSfloatNumber class], 0, zone);
    number->value = value;
    return number;
}

static NSNumber *NSNumberCreateDouble(double value, NSZone *zone) {
    NSdoubleNumber *number = (NSdoubleNumber *)NSAllocateObject(
        [NSdoubleNumber class], 0, zone);
    number->value = value;
    return number;
}

static id NSValueNewDecodedValue(NSCoder *coder, NSZone *zone) {
    char *type = NULL;
    unsigned size = 0;
    char stackBytes[1024];
    void *bytes = stackBytes;
    id value;

    [coder decodeValueOfObjCType:"*" at:&type];
    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(stackBytes))
        bytes = NSZoneMalloc(NULL, size);
    [coder decodeValueOfObjCType:type at:bytes];
    value = _NSNewValue(bytes, type, zone);
    if (bytes != stackBytes)
        NSZoneFree(NULL, bytes);
    NSZoneFree(NSZoneFromPointer(type), type);
    return value;
}

static id NSValueNumberFromDecodedBytes(const char *type, const void *bytes,
                                        NSZone *zone) {
    id placeholder = NSNumberPlaceholderForZone(zone);

    switch (*type) {
        case 'C': return [placeholder initWithUnsignedChar:
                            *(const unsigned char *)bytes];
        case 'I': return [placeholder initWithUnsignedInt:
                            *(const unsigned int *)bytes];
        case 'L': return [placeholder initWithUnsignedLong:
                            *(const unsigned long *)bytes];
        case 'Q': return [placeholder initWithUnsignedLongLong:
                            *(const unsigned long long *)bytes];
        case 'S': return [placeholder initWithUnsignedShort:
                            *(const unsigned short *)bytes];
        case 'c': return [placeholder initWithChar:
                            *(const signed char *)bytes];
        case 'd': return [placeholder initWithDouble:
                            *(const double *)bytes];
        case 'f': return [placeholder initWithFloat:
                            *(const float *)bytes];
        case 'i': return [placeholder initWithInt:
                            *(const int *)bytes];
        case 'l': return [placeholder initWithLong:
                            *(const long *)bytes];
        case 'q': return [placeholder initWithLongLong:
                            *(const long long *)bytes];
        case 's': return [placeholder initWithShort:
                            *(const short *)bytes];
        default: return nil;
    }
}

static id NSNumberNewDecodedNumber(NSCoder *coder, NSZone *zone) {
    char *type = NULL;
    unsigned size = 0;
    char stackBytes[1024];
    void *bytes = stackBytes;
    id number = nil;
    NSString *badType = nil;

    [coder decodeValueOfObjCType:"*" at:&type];
    if (type != NULL && type[0] != '\0' && type[1] == '\0') {
        NSGetSizeAndAlignment(type, &size, NULL);
        if (size > sizeof(stackBytes))
            bytes = NSZoneMalloc(NULL, size);
        [coder decodeValueOfObjCType:type at:bytes];
        number = NSValueNumberFromDecodedBytes(type, bytes, zone);
    }
    if (number == nil && type != NULL)
        badType = [NSString stringWithCString:type];
    if (bytes != stackBytes)
        NSZoneFree(NSZoneFromPointer(bytes), bytes);
    if (type != NULL)
        NSZoneFree(NSZoneFromPointer(type), type);
    if (number != nil)
        return number;
    [NSException raise:NSInternalInconsistencyException
                format:@"*** -[NSNumber initWithCoder:] bad objCType: \"%s\"",
                       [badType cString]];
    return nil;
}

@implementation NSValue

- (Class)classForCoder {
    return [NSValue class];
}

- (id)init {
    if (isa == [NSValue class])
        NSRequestConcreteImplementation(self, _cmd, [NSValue class]);
    return [super init];
}

- (void)getValue:(void *)value {
    NSRequestConcreteImplementation(self, _cmd, [NSValue class]);
}

- (const char *)objCType {
    return (const char *)NSRequestConcreteImplementation(self, _cmd,
                                                         [NSValue class]);
}

- (id)initWithBytes:(const void *)value objCType:(const char *)type {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

+ (NSValue *)valueWithBytes:(const void *)value objCType:(const char *)type {
    return (NSValue *)[_NSNewValue(value, type, NULL) autorelease];
}

+ (NSValue *)value:(const void *)value withObjCType:(const char *)type {
    return [self valueWithBytes:value objCType:type];
}

+ (NSValue *)valueWithNonretainedObject:(id)anObject {
    return [NSValue valueWithBytes:&anObject objCType:"^v"];
}

- (id)nonretainedObjectValue {
    id object;

    [self getValue:&object];
    return object;
}

+ (NSValue *)valueWithPointer:(const void *)pointer {
    return [NSValue valueWithBytes:&pointer objCType:"^v"];
}

- (void *)pointerValue {
    void *pointer;

    [self getValue:&pointer];
    return pointer;
}

- (BOOL)isEqualToValue:(NSValue *)value {
    const char *type;
    unsigned size;
    char leftStackBuffer[1024];
    char rightStackBuffer[1024];
    void *leftBuffer = leftStackBuffer;
    void *rightBuffer = rightStackBuffer;
    BOOL equal;

    if (value == self)
        return YES;

    type = [self objCType];
    if (strcmp(type, [value objCType]) != 0)
        return NO;

    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(leftStackBuffer)) {
        leftBuffer = NSZoneMalloc(NULL, size);
        rightBuffer = NSZoneMalloc(NULL, size);
    }

    [self getValue:leftBuffer];
    [value getValue:rightBuffer];
    equal = memcmp(leftBuffer, rightBuffer, size) == 0;

    if (size > sizeof(leftStackBuffer)) {
        NSZoneFree(NSZoneFromPointer(leftBuffer), leftBuffer);
        NSZoneFree(NSZoneFromPointer(rightBuffer), rightBuffer);
    }
    return equal;
}

- (id)copyWithZone:(NSZone *)zone {
    const char *type = [self objCType];
    unsigned size;
    char stackBuffer[1024];
    void *bytes = stackBuffer;
    id copy;

    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(stackBuffer))
        bytes = NSZoneMalloc(NULL, size);
    [self getValue:bytes];
    copy = _NSNewValue(bytes, type, zone);
    if (bytes != stackBuffer)
        NSZoneFree(NULL, bytes);
    return copy;
}

- (NSString *)description {
    const char *type;
    unsigned size = 0;
    NSMutableData *data;
    NSString *result;

    /*  PPC allocates the data object before asking for the value type.  */
#if defined(__ppc__) || defined(__POWERPC__)
    data = [NSMutableData allocWithZone:NULL];
#endif
    type = [self objCType];
    NSGetSizeAndAlignment(type, &size, NULL);
#if !defined(__ppc__) && !defined(__POWERPC__)
    data = [NSMutableData allocWithZone:NULL];
#endif
    data = [data initWithLength:size];
    [self getValue:[data mutableBytes]];
    result = [data description];
    [data release];
    return result;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    const char *type = [self objCType];
    unsigned size = 0;
    char stackBytes[1024];
    void *bytes = stackBytes;

    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(stackBytes))
        bytes = NSZoneMalloc(NULL, size);
    if (type[0] == '^' && type[1] == 'v')
        [NSException raise:NSInvalidArgumentException
                    format:@"cannot encode (void *) value: %@", self];
    [self getValue:bytes];
    [coder encodeValueOfObjCType:"*" at:&type];
    [coder encodeValueOfObjCType:type at:bytes];
    if (bytes != stackBytes)
        NSZoneFree(NULL, bytes);
}

- (unsigned)hash {
    const char *type = [self objCType];
    unsigned size = 0;
    unsigned char stackBytes[1024];
    unsigned char *bytes = stackBytes;
    unsigned hash = 0;

    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(stackBytes))
        bytes = NSZoneMalloc(NULL, size);
    [self getValue:bytes];
    if (size != 0)
        hash = *bytes;
    if (bytes != stackBytes)
        NSZoneFree(NULL, bytes);
    return hash;
}

- (id)initWithCoder:(NSCoder *)coder {
    NSZone *zone = [self zone];

    [self dealloc];
    return NSValueNewDecodedValue(coder, zone);
}

- (BOOL)isEqual:(id)object {
    if (self == object)
        return YES;
    if (object->isa == [NSConcreteValue class] ||
        [object isKindOfClass:[NSValue class]])
        return [self isEqualToValue:object];
    return NO;
}

- (id)replacementObjectForPortCoder:(id)coder {
    (void)coder;
    return self;
}

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSValue class])
        return NSValuePlaceholderForZone(zone);
    return NSAllocateObject(self, 0, zone);
}

+ (NSValue *)valueWithPoint:(NSPoint)point {
    return NSNewGeometryValue(&point, "{?=ff}", 1);
}

+ (NSValue *)valueWithSize:(NSSize)size {
    return NSNewGeometryValue(&size, "{?=ff}", 2);
}

+ (NSValue *)valueWithRect:(NSRect)rect {
    return NSNewGeometryValue(&rect, "{?={?=ff}{?=ff}}", 3);
}

+ (NSValue *)valueWithRange:(NSRange)range {
    return NSNewGeometryValue(&range, "{?=II}", 4);
}

- (NSPoint)pointValue {
    NSPoint value;
    [self getValue:&value];
    return value;
}

- (NSSize)sizeValue {
    NSSize value;
    [self getValue:&value];
    return value;
}

- (NSRect)rectValue {
    NSRect value;
    [self getValue:&value];
    return value;
}

- (NSRange)rangeValue {
    NSRange value;
    [self getValue:&value];
    return value;
}

@end

@implementation NSConcreteValue

- (void)getValue:(void *)value {
    memmove(value, (char *)self + self->isa->instance_size, _typeInfo->size);
}

- (const char *)objCType {
    return _typeInfo->type;
}

- (const void *)_value {
    return (char *)self + self->isa->instance_size;
}

- (unsigned)hash {
    if (_typeInfo->size == 0)
        return 0;
    return *(const unsigned char *)[self _value];
}

- (BOOL)isEqualToValue:(NSValue *)value {
    const char *type = _typeInfo->type;
    unsigned size = _typeInfo->size;
    char stackBytes[1024];
    void *bytes = stackBytes;

    if (value == self)
        return YES;
    if (strcmp(type, [value objCType]) != 0)
        return NO;
    if (isa == value->isa || [value isKindOfClass:[NSConcreteValue class]])
        return memcmp([self _value], [(NSConcreteValue *)value _value],
                      size) == 0;
    if (size > sizeof(stackBytes))
        bytes = NSZoneMalloc(NULL, size);
    [value getValue:bytes];
    {
        BOOL equal = memcmp([self _value], bytes, size) == 0;

        if (bytes != stackBytes)
            NSZoneFree(NSZoneFromPointer(bytes), bytes);
        return equal;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    if (NSShouldRetainWithZone(self, zone))
        return [self retain];
    return _NSNewValue([self _value], _typeInfo->type, zone);
}

@end

@implementation NSValueDecoder

- (id)initWithCoder:(NSCoder *)coder {
    NSZone *zone = [self zone];
    char *type = NULL;
    unsigned size = 0;
    char stackBytes[1024];
    void *bytes = stackBytes;
    id value = nil;

    [coder decodeValueOfObjCType:"*" at:&type];
    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(stackBytes))
        bytes = NSZoneMalloc(NULL, size);
    [coder decodeValueOfObjCType:type at:bytes];
    if (type[0] != '\0' && type[1] == '\0')
        value = NSValueNumberFromDecodedBytes(type, bytes, zone);
    if (value == nil)
        value = _NSNewValue(bytes, type, zone);
    [self dealloc];
    if (bytes != stackBytes)
        NSZoneFree(NULL, bytes);
    NSZoneFree(NSZoneFromPointer(type), type);
    return value;
}

@end

@implementation NSPlaceholderValue

- (void)getValue:(void *)value {
    NSLog(@"Did you forget to nest alloc and init?");
    NSRequestConcreteImplementation(self, _cmd,
        isa == [NSPlaceholderNumber class] ? [NSNumber class] : [NSValue class]);
}

- (const char *)objCType {
    NSLog(@"Did you forget to nest alloc and init?");
    NSRequestConcreteImplementation(self, _cmd,
        isa == [NSPlaceholderNumber class] ? [NSNumber class] : [NSValue class]);
    return NULL;
}

- (id)initWithBytes:(const void *)value objCType:(const char *)type {
    return (id)_NSNewValue(value, type, zoneForInstance);
}

- (id)initWithCoder:(NSCoder *)coder {
    return NSValueNewDecodedValue(coder, zoneForInstance);
}

- (id)retain {
    return self;
}

- (oneway void)release {
}

- (id)autorelease {
    return self;
}

- (unsigned)retainCount {
    return (unsigned)-1;
}

- (void)dealloc {
}

@end

@implementation NSPlaceholderNumber

- (id)initWithCoder:(NSCoder *)coder {
    return NSNumberNewDecodedNumber(coder, zoneForInstance);
}

- (id)initWithChar:(char)value {
    return NSNumberCreateShort((short)value, zoneForInstance);
}

- (id)initWithUnsignedChar:(unsigned char)value {
    return NSNumberCreateUnsignedShort((unsigned short)value, zoneForInstance);
}

- (id)initWithShort:(short)value {
    return NSNumberCreateShort(value, zoneForInstance);
}

- (id)initWithUnsignedShort:(unsigned short)value {
    return NSNumberCreateUnsignedShort(value, zoneForInstance);
}

- (id)initWithInt:(int)value {
    return NSNumberCreateInt(value, zoneForInstance);
}

- (id)initWithUnsignedInt:(unsigned int)value {
    return NSNumberCreateUnsignedInt(value, zoneForInstance);
}

- (id)initWithLong:(long)value {
    return NSNumberCreateInt((int)value, zoneForInstance);
}

- (id)initWithUnsignedLong:(unsigned long)value {
    return NSNumberCreateUnsignedInt((unsigned int)value, zoneForInstance);
}

- (id)initWithLongLong:(long long)value {
    return NSNumberCreateLongLong(value, zoneForInstance);
}

- (id)initWithUnsignedLongLong:(unsigned long long)value {
    return NSNumberCreateUnsignedLongLong(value, zoneForInstance);
}

- (id)initWithFloat:(float)value {
    return NSNumberCreateFloat(value, zoneForInstance);
}

- (id)initWithDouble:(double)value {
    return NSNumberCreateDouble(value, zoneForInstance);
}

- (id)initWithBool:(BOOL)value {
    return NSNumberCreateShort((short)value, zoneForInstance);
}

@end

@implementation NSRefCountingNumber

- (id)retain {
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSRefCountingNumberLock();

    if (NSRefCountingNumberRefCount != 0xffffffffU)
        ++NSRefCountingNumberRefCount;
    NSRefCountingNumberUnlock(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
#else
    _NSIncrementInternalRefCount(self, &NSRefCountingNumberRefCount,
                                 0xFFFF, _NSGlobalRetainLock);
#endif
    return self;
}

- (oneway void)release {
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSRefCountingNumberLock();
    if (NSRefCountingNumberRefCount != 0) {
        if (NSRefCountingNumberRefCount != 0xffffffffU)
            --NSRefCountingNumberRefCount;
    } else {
        shouldDeallocate = YES;
    }
    NSRefCountingNumberUnlock(locked);
    if (shouldDeallocate)
        [self dealloc];
#else
    if (_NSDecrementInternalRefCountWasZero(
            self, &NSRefCountingNumberRefCount, 0xFFFF,
            _NSGlobalRetainLock))
        [self dealloc];
#endif
}

- (unsigned)retainCount {
#if defined(__ppc__) || defined(__POWERPC__)
    return NSRefCountingNumberRefCount + 1;
#else
    return _NSInternalRefCount(self, NSRefCountingNumberRefCount, 0xFFFF);
#endif
}

- (id)copyWithZone:(NSZone *)zone {
    NSRefCountingNumber *copy;

    if (NSShouldRetainWithZone(self, zone))
        return [self retain];
    copy = (NSRefCountingNumber *)NSCopyObject(self, 0, zone);
    copy->NSRefCountingNumberRefCount = 0;
    return copy;
}

@end

@implementation NSshortNumber

- (void)getValue:(void *)value { memmove(value, &self->value, sizeof(self->value)); }
- (const char *)objCType { return "s"; }
- (short)shortValue { return self->value; }

@end

@implementation NSunsignedShortNumber

- (void)getValue:(void *)value { memmove(value, &self->value, sizeof(self->value)); }
- (const char *)objCType { return "S"; }
- (unsigned short)unsignedShortValue { return self->value; }

@end

@implementation NSintNumber

- (void)getValue:(void *)value { memmove(value, &self->value, sizeof(self->value)); }
- (const char *)objCType { return "i"; }
- (int)intValue { return self->value; }

@end

@implementation NSunsignedIntNumber

- (void)getValue:(void *)value { memmove(value, &self->value, sizeof(self->value)); }
- (const char *)objCType { return "I"; }
- (unsigned int)unsignedIntValue { return self->value; }

@end

@implementation NSlongLongNumber

- (void)getValue:(void *)value { memmove(value, &self->value, sizeof(self->value)); }
- (const char *)objCType { return "q"; }
- (long long)longLongValue { return self->value; }

@end

@implementation NSunsignedLongLongNumber

- (void)getValue:(void *)value { memmove(value, &self->value, sizeof(self->value)); }
- (const char *)objCType { return "Q"; }
- (unsigned long long)unsignedLongLongValue { return self->value; }

@end

@implementation NSfloatNumber

- (void)getValue:(void *)value { memmove(value, &self->value, sizeof(self->value)); }
- (const char *)objCType { return "f"; }
- (float)floatValue { return self->value; }

@end

@implementation NSdoubleNumber

- (void)getValue:(void *)value { memmove(value, &self->value, sizeof(self->value)); }
- (const char *)objCType { return "d"; }
- (double)doubleValue { return self->value; }

@end

@implementation NSunsignedIntNumber (_NSHash)

- (unsigned)hash { return self->value; }

@end

@implementation NSintNumber (_NSHash)

- (unsigned)hash { return self->value; }

@end

@implementation NSunsignedShortNumber (_NSHash)

- (unsigned)hash { return self->value; }

@end

@implementation NSshortNumber (_NSHash)

- (unsigned)hash { return self->value; }

@end

#define NS_NUMBER_CONVERSION_CASES(resultType) \
    case 'C': return (resultType)[self unsignedCharValue]; \
    case 'I': return (resultType)[self unsignedIntValue]; \
    case 'L': return (resultType)[self unsignedLongValue]; \
    case 'Q': return (resultType)[self unsignedLongLongValue]; \
    case 'S': return (resultType)[self unsignedShortValue]; \
    case 'c': return (resultType)[self charValue]; \
    case 'd': return (resultType)[self doubleValue]; \
    case 'f': return (resultType)[self floatValue]; \
    case 'i': return (resultType)[self intValue]; \
    case 'l': return (resultType)[self longValue]; \
    case 'q': return (resultType)[self longLongValue]; \
    case 's': return (resultType)[self shortValue]

#define NS_NUMBER_VALUE_METHOD(method, resultType) \
- (resultType)method { \
    const char *type = [self objCType]; \
    switch (*type) { \
        NS_NUMBER_CONVERSION_CASES(resultType); \
        default: \
            [NSException raise:NSInternalInconsistencyException \
                        format:@"%@: bad objCType: \"%s\"", \
                               _NSMethodExceptionProem(self, _cmd), type]; \
            return (resultType)0; \
    } \
}

static char NSNumberComparisonType(char left, char right) {
    const char *types = "dfQqLlIiSsCc";
    const char *type;

    for (type = types; *type != '\0'; type++) {
        if (*type == left || *type == right)
            return *type;
    }
    return '\0';
}

static NSComparisonResult NSNumberCompareValues(NSNumber *left,
                                               NSNumber *right,
                                               char type) {
#define NS_NUMBER_COMPARE_CASE(code, getter) \
    case code: { \
        __typeof__([left getter]) leftValue = [left getter]; \
        __typeof__([right getter]) rightValue = [right getter]; \
        if (leftValue > rightValue) return NSOrderedDescending; \
        if (leftValue < rightValue) return NSOrderedAscending; \
        return NSOrderedSame; \
    }
    switch (type) {
        NS_NUMBER_COMPARE_CASE('C', unsignedCharValue)
        NS_NUMBER_COMPARE_CASE('I', unsignedIntValue)
        NS_NUMBER_COMPARE_CASE('L', unsignedLongValue)
        NS_NUMBER_COMPARE_CASE('Q', unsignedLongLongValue)
        NS_NUMBER_COMPARE_CASE('S', unsignedShortValue)
        NS_NUMBER_COMPARE_CASE('c', charValue)
        NS_NUMBER_COMPARE_CASE('i', intValue)
        NS_NUMBER_COMPARE_CASE('l', longValue)
        NS_NUMBER_COMPARE_CASE('q', longLongValue)
        NS_NUMBER_COMPARE_CASE('s', shortValue)
        NS_NUMBER_COMPARE_CASE('f', floatValue)
        NS_NUMBER_COMPARE_CASE('d', doubleValue)
        default:
            return NSOrderedSame;
    }
#undef NS_NUMBER_COMPARE_CASE
}

@implementation NSNumber

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSNumber class])
        return NSNumberPlaceholderForZone(zone);
    return NSAllocateObject(self, 0, zone);
}

- (Class)classForCoder {
    return [NSNumber class];
}

- (id)copyWithZone:(NSZone *)zone {
    const char *type = [self objCType];
    unsigned size = 0;
    char stackBytes[1024];
    void *bytes = stackBytes;
    id copy;

    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(stackBytes))
        bytes = NSZoneMalloc(NULL, size);
    [self getValue:bytes];
    copy = NSValueNumberFromDecodedBytes(type, bytes, zone);
    if (copy == nil)
        [NSException raise:NSInternalInconsistencyException
                    format:@"%@: bad objCType: \"%s\"",
                           _NSMethodExceptionProem(self, _cmd), type];
    if (bytes != stackBytes)
        NSZoneFree(NULL, bytes);
    return copy;
}

- (id)initWithCoder:(NSCoder *)coder {
    NSZone *zone = [self zone];

    [self dealloc];
    return NSNumberNewDecodedNumber(coder, zone);
}

- (unsigned)hash {
    const char *type = [self objCType];

    switch (*type) {
        case 'C':
        case 'I':
        case 'L':
        case 'S':
        case 'c':
        case 'i':
        case 'l':
        case 's':
            return [self unsignedIntValue];
        case 'Q': {
            unsigned long long value = [self unsignedLongLongValue];

            return value > UINT_MAX ? 17 : (unsigned)value;
        }
        case 'q': {
            long long value = [self longLongValue];
            unsigned long long offset =
                (unsigned long long)value - 0x80000000ULL;

            return offset > 0x17FFFFFFFULL ? 17 : (unsigned)value;
        }
        default: {
            double value = [self doubleValue];

            if (value != value)
                return (unsigned)INT_MIN;
            if (value < 0.0) {
                if (value < INT_MIN)
                    return 17;
                return (unsigned)(int)floor(value);
            }
            if (value > UINT_MAX)
                return 17;
            return (unsigned)floor(value);
        }
    }
}

NS_NUMBER_VALUE_METHOD(charValue, char)
NS_NUMBER_VALUE_METHOD(unsignedCharValue, unsigned char)
NS_NUMBER_VALUE_METHOD(shortValue, short)
NS_NUMBER_VALUE_METHOD(unsignedShortValue, unsigned short)
NS_NUMBER_VALUE_METHOD(intValue, int)
NS_NUMBER_VALUE_METHOD(unsignedIntValue, unsigned int)
NS_NUMBER_VALUE_METHOD(longValue, long)
NS_NUMBER_VALUE_METHOD(unsignedLongValue, unsigned long)
NS_NUMBER_VALUE_METHOD(longLongValue, long long)
NS_NUMBER_VALUE_METHOD(unsignedLongLongValue, unsigned long long)
NS_NUMBER_VALUE_METHOD(floatValue, float)
NS_NUMBER_VALUE_METHOD(doubleValue, double)
NS_NUMBER_VALUE_METHOD(boolValue, BOOL)

#undef NS_NUMBER_VALUE_METHOD
#undef NS_NUMBER_CONVERSION_CASES

- (NSString *)stringValue {
    return [self descriptionWithLocale:nil];
}

- (NSString *)description {
    return [self descriptionWithLocale:nil];
}

- (NSComparisonResult)compare:(NSNumber *)otherNumber {
    char type = NSNumberComparisonType(*[self objCType],
                                       *[otherNumber objCType]);

    if (type == '\0') {
        /* Keep the target's selected-byte argument for the %s conversion. */

        [NSException raise:NSInternalInconsistencyException
                    format:@"%@: bad objCType: \"%s\"",
                           _NSMethodExceptionProem(self, _cmd), type];
        return NSOrderedDescending;
    }
    return NSNumberCompareValues(self, otherNumber, type);
}

- (BOOL)isEqualToNumber:(NSNumber *)number {
    return self == number || [self compare:number] == NSOrderedSame;
}

- (BOOL)isEqual:(id)object {
    return self == object
        || ([object isKindOfClass:[NSNumber class]]
            && [self isEqualToNumber:object]);
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    char type = *[self objCType];
    NSString *format;
    double floatingValue;

    switch (type) {
        case 'C': format = @"%hhu"; break;
        case 'I': format = @"%u"; break;
        case 'L': format = @"%lu"; break;
        case 'S': format = @"%hu"; break;
        case 'c': format = @"%hhd"; break;
        case 'i': format = @"%d"; break;
        case 'l': format = @"%ld"; break;
        case 's': format = @"%hd"; break;
        case 'f':
            floatingValue = [self floatValue];
            return [[[NSString allocWithZone:NULL]
                initWithFormat:@"%g" locale:locale, floatingValue] autorelease];
        case 'd':
            floatingValue = [self doubleValue];
            return [[[NSString allocWithZone:NULL]
                initWithFormat:@"%g" locale:locale, floatingValue] autorelease];
        case 'q':
        case 'Q': {
            char buffer[24];
            unsigned long long value;
            unsigned length = 0;
            BOOL negative = NO;

            if (type == 'q') {
                long long signedValue = [self longLongValue];
                negative = signedValue < 0;
                value = negative ? (unsigned long long)(-(signedValue + 1)) + 1
                                 : (unsigned long long)signedValue;
            } else {
                value = (unsigned long long)[self longLongValue];
            }
            do {
                buffer[length++] = (char)('0' + value % 10);
                value /= 10;
            } while (value != 0);
            if (negative)
                buffer[length++] = '-';
            {
                unsigned left = 0;
                unsigned right = length - 1;
                while (left < right) {
                    char temporary = buffer[left];
                    buffer[left++] = buffer[right];
                    buffer[right--] = temporary;
                }
            }
            return [[[NSString allocWithZone:NULL]
                initWithCString:buffer length:length] autorelease];
        }
        default:
            {
                const char *type = [self objCType];

                [NSException raise:NSInternalInconsistencyException
                            format:@"%@: bad objCType: \"%s\"",
                                   _NSMethodExceptionProem(self, _cmd), type];
                return nil;
            }
    }

    switch (type) {
        case 'C': return [[[NSString allocWithZone:NULL]
            initWithFormat:format locale:locale, [self unsignedCharValue]] autorelease];
        case 'I': return [[[NSString allocWithZone:NULL]
            initWithFormat:format locale:locale, [self unsignedIntValue]] autorelease];
        case 'L': return [[[NSString allocWithZone:NULL]
            initWithFormat:format locale:locale, [self unsignedLongValue]] autorelease];
        case 'S': return [[[NSString allocWithZone:NULL]
            initWithFormat:format locale:locale, [self unsignedShortValue]] autorelease];
        case 'c': return [[[NSString allocWithZone:NULL]
            initWithFormat:format locale:locale, [self charValue]] autorelease];
        case 'i': return [[[NSString allocWithZone:NULL]
            initWithFormat:format locale:locale, [self intValue]] autorelease];
        case 'l': return [[[NSString allocWithZone:NULL]
            initWithFormat:format locale:locale, [self longValue]] autorelease];
        case 's': return [[[NSString allocWithZone:NULL]
            initWithFormat:format locale:locale, [self shortValue]] autorelease];
    }
    return nil;
}

- (id)initWithChar:(char)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithUnsignedChar:(unsigned char)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithShort:(short)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithUnsignedShort:(unsigned short)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithInt:(int)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithUnsignedInt:(unsigned int)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithLong:(long)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithUnsignedLong:(unsigned long)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithLongLong:(long long)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithUnsignedLongLong:(unsigned long long)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithFloat:(float)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithDouble:(double)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithBool:(BOOL)value {
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

+ (NSNumber *)numberWithChar:(char)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithChar:value] autorelease];
}

+ (NSNumber *)numberWithUnsignedChar:(unsigned char)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithUnsignedChar:value] autorelease];
}

+ (NSNumber *)numberWithShort:(short)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithShort:value] autorelease];
}

+ (NSNumber *)numberWithUnsignedShort:(unsigned short)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithUnsignedShort:value] autorelease];
}

+ (NSNumber *)numberWithInt:(int)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithInt:value] autorelease];
}

+ (NSNumber *)numberWithUnsignedInt:(unsigned int)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithUnsignedInt:value] autorelease];
}

+ (NSNumber *)numberWithLong:(long)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithLong:value] autorelease];
}

+ (NSNumber *)numberWithUnsignedLong:(unsigned long)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithUnsignedLong:value] autorelease];
}

+ (NSNumber *)numberWithLongLong:(long long)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithLongLong:value] autorelease];
}

+ (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithUnsignedLongLong:value] autorelease];
}

+ (NSNumber *)numberWithFloat:(float)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithFloat:value] autorelease];
}

+ (NSNumber *)numberWithDouble:(double)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithDouble:value] autorelease];
}

+ (NSNumber *)numberWithBool:(BOOL)value {
    return (NSNumber *)[[NSNumberPlaceholderForZone(NULL)
        initWithBool:value] autorelease];
}

@end
