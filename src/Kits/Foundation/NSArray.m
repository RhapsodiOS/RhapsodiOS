/*	NSArray.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSException.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSSerialization.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

extern id _NSParseObjectFromASCIIPropertyListOrSerialization(NSData *data);
extern NSString *_NSIndentSpace(unsigned level);
extern NSString *__NSEmptyString;
extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern IMP _NSIMPForObjectAndSelector(id object, SEL aSelector);
extern void _NSGenericFree(void *ptr);
#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSArrayRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSArrayLockConcreteRetainCount(void)
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
            : "r" (&__NSArrayRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSArrayUnlockConcreteRetainCount(BOOL locked)
{
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSArrayRetainLock = 0;
    }
}
#else
extern NSLock *_NSGlobalRetainLock;

static BOOL NSArrayLockConcreteRetainCount(void)
{
    if (_NSGlobalRetainLock == nil)
        return NO;
    [_NSGlobalRetainLock lock];
    return YES;
}

static void NSArrayUnlockConcreteRetainCount(BOOL locked)
{
    if (locked)
        [_NSGlobalRetainLock unlock];
}
#endif

@interface NSString (NSArrayDescriptionPrivate)
- (NSString *)_stringRepresentation;
@end

@interface NSArray (PrivatePropertyListDataReading)
- (id)_initWithData:(NSData *)data;
- (NSString *)_stringToWrite;
@end

@interface NSMutableArray (PrivateRangeRemoval)
- (void)removeObject:(id)object range:(NSRange)range identical:(BOOL)identical;
@end

static NSString *NSArrayDescriptionForObject(id object,
                                              NSDictionary *locale,
                                              unsigned level)
{
    if ([object isKindOfClass:[NSString class]])
        return [object _stringRepresentation];
    if ([object respondsToSelector:
            @selector(descriptionWithLocale:indent:)])
        return [object descriptionWithLocale:locale indent:level + 1];
    if ([object respondsToSelector:@selector(descriptionWithLocale:)])
        return [object descriptionWithLocale:locale];
    return [object description];
}

@interface NSConcreteArray : NSArray {
@public
    unsigned _info;
    id *_items;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count;

@end

NSConcreteArray *__NSEmptyArray;

@interface NSConcreteMutableArray : NSMutableArray {
@public
    unsigned _info;
    id *_items;
    unsigned _size;
}

- (id)initWithCapacity:(unsigned)capacity;
- (id)initWithObjects:(id *)objects count:(unsigned)count;

@end

@interface NSIdEnumerator : NSEnumerator {
    id *_list;
    unsigned _slot;
    unsigned _limit;
    id _target;
    BOOL _free;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count target:(id)target
             reverse:(BOOL)reverse freeWhenDone:(BOOL)freeWhenDone;
- (void)invalidate;

@end

@interface NSArray (NSArrayPrivate)

- (NSArray *)arrayByAddingObjects:(id *)objects count:(unsigned)count;
- (id)initWithArray:(NSArray *)array copyItems:(BOOL)copyItems;
+ (id)arrayWithArray:(NSArray *)array copyItems:(BOOL)copyItems;

@end

typedef int (*NSArrayComparator)(id, id, void *);
typedef id (*NSArrayObjectAtIndexIMP)(id, SEL, unsigned);

static void NSArrayRaiseBoundException(id object, SEL selector,
                                       unsigned bound, unsigned count)
{
    id proem = _NSMethodExceptionProem(object, selector);

    [NSException raise:NSRangeException
                format:@"%@: index (%d) beyond bounds (%d)",
                       proem, bound, count];
}

static void NSArrayRaiseInsertNilException(id object, SEL selector)
{
    id proem = _NSMethodExceptionProem(object, selector);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: attempt to insert nil", proem];
}

static void NSArrayRaiseSizeException(id object, SEL selector,
                                      unsigned size, const char *sizeName)
{
    id proem = _NSMethodExceptionProem(object, selector);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: absurd %s: %d", proem, sizeName, size];
}

id *_NSMergeSort(unsigned count, id *source, id *destination, id *alternate,
                 NSArrayComparator comparator, void *context,
                 char checkBoundary)
{
    unsigned middle, rightCount, leftRemaining, rightRemaining;
    id *left, *right, *output;
    int order, adjacentOrder;

    switch (count) {
    case 0:
    case 1:
        return source;
    case 2:
        if (comparator(source[0], source[1], context) <= 0)
            return source;
        destination[0] = source[1];
        destination[1] = source[0];
        return destination;
    case 3:
        order = comparator(source[0], source[1], context);
        adjacentOrder = comparator(source[1], source[2], context);
        if (order > 0) {
            if (adjacentOrder > 0) {
                destination[0] = source[2];
                destination[1] = source[1];
                destination[2] = source[0];
            } else if (comparator(source[0], source[2], context) <= 0) {
                destination[0] = source[1];
                destination[1] = source[0];
                destination[2] = source[2];
            } else {
                destination[0] = source[1];
                destination[1] = source[2];
                destination[2] = source[0];
            }
        } else if (adjacentOrder <= 0) {
            return source;
        } else if (comparator(source[0], source[2], context) > 0) {
            destination[0] = source[2];
            destination[1] = source[0];
            destination[2] = source[1];
        } else {
            destination[0] = source[0];
            destination[1] = source[2];
            destination[2] = source[1];
        }
        return destination;
    }

    middle = count >> 1;
    rightCount = count - middle;
    left = _NSMergeSort(middle, source, alternate, destination,
                        comparator, context, checkBoundary);
    right = _NSMergeSort(rightCount, source + middle,
                         alternate + middle, destination,
                         comparator, context, checkBoundary);
    if (checkBoundary &&
        comparator(left[middle - 1], right[0], context) <= 0) {
        if (left == source && right == source + middle)
            return left;
        memmove(destination, left, middle * sizeof(id));
        output = destination + middle;
        memmove(output, right, rightCount * sizeof(id));
        return destination;
    }

    leftRemaining = middle;
    rightRemaining = rightCount;
    output = destination;
    while (leftRemaining != 0 && rightRemaining != 0) {
        order = comparator(*left, *right, context);
        if (order <= 0) {
            *output++ = *left++;
            --leftRemaining;
            if (order < 0)
                continue;
        }
        *output++ = *right++;
        --rightRemaining;
    }
    if (leftRemaining != 0)
        memmove(output, left, leftRemaining * sizeof(id));
    if (rightRemaining != 0)
        memmove(output, right, rightRemaining * sizeof(id));
    return destination;
}

static int NSArraySortUsingSelector(id first, id second, void *context)
{
    return (int)[first performSelector:(SEL)context withObject:second];
}

static int NSArrayCompareIndices(const void *first, const void *second)
{
    unsigned firstIndex = *(const unsigned *)first;
    unsigned secondIndex = *(const unsigned *)second;

    if (firstIndex < secondIndex)
        return -1;
    return firstIndex > secondIndex;
}

static BOOL NSArrayUsesConcreteStorage(id array)
{
    return array->isa == [NSConcreteArray class] ||
           array->isa == [NSConcreteMutableArray class];
}

static unsigned NSArrayConcreteCount(id array)
{
    return ((NSConcreteArray *)array)->_info & 0x07ffffff;
}

static unsigned NSArrayIndexOfObjectInRange(NSArray *array, id object,
                                             NSRange range, BOOL identical,
                                             unsigned count,
                                             BOOL searchBackward)
{
    BOOL concrete = NSArrayUsesConcreteStorage(array);
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned index;
    unsigned result = NSNotFound;
    IMP equalityImplementation = NULL;

    if (count < range.location + range.length)
        NSArrayRaiseBoundException(array,
            @selector(indexOfObject:range:identical:),
            range.location + range.length - 1, count);
    if (object == nil || range.length == 0)
        return NSNotFound;
    if (concrete)
        objects = ((NSConcreteArray *)array)->_items + range.location;
    else {
        if (range.length > 128)
            objects = NSZoneMalloc(NULL, range.length * sizeof(id));
        [array getObjects:objects range:range];
    }
    if (!identical && range.length > 1)
        equalityImplementation =
            _NSIMPForObjectAndSelector(object, @selector(isEqual:));
    if (searchBackward) {
        index = range.length;
        while (index != 0) {
            id item = objects[--index];

            if (item == object ||
                (!identical && (range.length == 1
                    ? [object isEqual:item]
                    : ((BOOL (*)(id, SEL, id))equalityImplementation)(
                        object, @selector(isEqual:), item)))) {
                result = range.location + index;
                break;
            }
        }
    } else {
        for (index = 0; index < range.length; index++) {
            id item = objects[index];

            if (item == object ||
                (!identical && (range.length == 1
                    ? [object isEqual:item]
                    : ((BOOL (*)(id, SEL, id))equalityImplementation)(
                        object, @selector(isEqual:), item)))) {
                result = range.location + index;
                break;
            }
        }
    }
    if (!concrete && objects != stackObjects)
        NSZoneFree(NULL, objects);
    return result;
}

static void NSConcreteMutableArrayEnsureCapacity(NSConcreteMutableArray *array,
                                                  unsigned additional)
{
    unsigned count = array->_info & 0x07ffffff;
    unsigned required = count + additional;
    unsigned capacity = array->_size;

    if (array->_items == nil) {
        if (capacity < 4)
            capacity = 4;
        if (required >= capacity)
            capacity = required;
        array->_size = capacity;
        array->_items = NSZoneMalloc(NSZoneFromPointer(array),
                                     capacity * sizeof(id));
    } else if (capacity < required) {
        capacity *= 2;
        if (capacity < required)
            capacity = required;
        array->_size = capacity;
        array->_items = NSZoneRealloc(NSZoneFromPointer(array->_items),
                                      array->_items, capacity * sizeof(id));
    }
}

static NSArray *NSArrayFromObjectsAndCount(id receiver, BOOL classMethod,
                                           id firstObject, va_list *arguments)
{
    id stackObjects[128];
    id *objects = nil;
    unsigned count = 0;
    unsigned index;
    id result;
    va_list countArguments;
    va_list copyArguments;

    if (firstObject != nil) {
        count = 1;
        memcpy(&countArguments, arguments, sizeof(countArguments));
        while (va_arg(countArguments, id) != nil)
            count++;
        va_end(countArguments);

        objects = count > 128
            ? NSZoneMalloc(0, count * sizeof(id)) : stackObjects;
        objects[0] = firstObject;
        memcpy(&copyArguments, arguments, sizeof(copyArguments));
        for (index = 1; index < count; index++)
            objects[index] = va_arg(copyArguments, id);
        va_end(copyArguments);
    }

    if (classMethod)
        result = [receiver arrayWithObjects:objects count:count];
    else
        result = [receiver initWithObjects:objects count:count];
    if (objects != nil && objects != stackObjects)
        NSZoneFree(0, objects);
    return result;
}

@implementation NSArray

+ (id)allocWithZone:(NSZone *)zone
{
    Class arrayClass = self;

    if (self == [NSArray class])
        arrayClass = [NSConcreteArray class];
    else if (self == [NSMutableArray class])
        arrayClass = [NSConcreteMutableArray class];
    return NSAllocateObject(arrayClass, 0, zone);
}

- (unsigned)count {
    if (NSArrayUsesConcreteStorage(self))
        return NSArrayConcreteCount(self);
    NSRequestConcreteImplementation(self, _cmd, [NSArray class]);
    return 0;
}

- (id)objectAtIndex:(unsigned)index {
    if (NSArrayUsesConcreteStorage(self)) {
        unsigned count = NSArrayConcreteCount(self);

        if (index >= count)
            NSArrayRaiseBoundException(self, _cmd, index, count);
        return ((NSConcreteArray *)self)->_items[index];
    }
    NSRequestConcreteImplementation(self, _cmd, [NSArray class]);
    return nil;
}

- (NSArray *)arrayByAddingObject:(id)anObject {
    if (anObject == nil) {
        NSArrayRaiseInsertNilException(self, _cmd);
        return nil;
    }
    return [self arrayByAddingObjects:&anObject count:1];
}

- (NSArray *)arrayByAddingObjectsFromArray:(NSArray *)otherArray {
    BOOL concrete = otherArray != nil && NSArrayUsesConcreteStorage(otherArray);
    unsigned count = otherArray == nil ? 0
        : concrete ? NSArrayConcreteCount(otherArray) : [otherArray count];
    id stackObjects[128];
    id *objects = stackObjects;
    NSArray *array;

    if (count == 0)
        return [NSArray arrayWithArray:self copyItems:NO];
    if (count > 128)
        objects = NSZoneMalloc(0, count * sizeof(id));
    if (concrete)
        memmove(objects, ((NSConcreteArray *)otherArray)->_items,
                count * sizeof(id));
    else
        [otherArray getObjects:objects range:NSMakeRange(0, count)];
    array = [self arrayByAddingObjects:objects count:count];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return array;
}

- (NSArray *)arrayByAddingObjects:(id *)objects count:(unsigned)count
{
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned originalCount = concrete ? NSArrayConcreteCount(self) : [self count];
    unsigned totalCount;
    id stackObjects[128];
    id *combinedObjects = stackObjects;
    NSArray *array;

    if (count == 0)
        return originalCount == 0 ? __NSEmptyArray
            : [NSArray arrayWithArray:self copyItems:NO];
    if (originalCount == 0)
        return [NSArray arrayWithObjects:objects count:count];
    totalCount = originalCount + count;
    if (totalCount > 128)
        combinedObjects = NSZoneMalloc(0, totalCount * sizeof(id));
    if (concrete)
        memmove(combinedObjects, ((NSConcreteArray *)self)->_items,
                originalCount * sizeof(id));
    else
        [self getObjects:combinedObjects range:NSMakeRange(0, originalCount)];
    memcpy(combinedObjects + originalCount, objects, count * sizeof(id));
    array = [NSArray arrayWithObjects:combinedObjects count:totalCount];
    if (combinedObjects != stackObjects)
        NSZoneFree(0, combinedObjects);
    return array;
}

- (NSString *)componentsJoinedByString:(NSString *)separator {
    unsigned count = [self count];
    unsigned separatorLength, objectIndex = 0, used = 0;
    unichar stackSeparator[256];
    unichar *separatorCharacters = stackSeparator;
    unichar *characters = NULL;
    id objects[64];
    unsigned lengths[64];
    unsigned batchLength;
    unsigned batch, index;
    NSString *result;

    if (count == 0)
        return __NSEmptyString;
    if (count == 1) {
        NSString *description = [[self objectAtIndex:0] description];

        return [[description copyWithZone:NULL] autorelease];
    }

    separatorLength = [separator length];
    if (separatorLength > 0x100)
        separatorCharacters = NSZoneMalloc(0,
                                           separatorLength * sizeof(unichar));

    [separator getCharacters:separatorCharacters
                       range:NSMakeRange(0, separatorLength)];
    while (objectIndex < count) {
        batch = count - objectIndex;
        if (batch > 64)
            batch = 64;
        [self getObjects:objects
                   range:NSMakeRange(objectIndex, batch)];
        batchLength = 0;
        for (index = 0; index < batch; index++) {
            objects[index] = [objects[index] description];
            lengths[index] = [objects[index] length];
            batchLength += lengths[index] + separatorLength;
        }
        characters = NSZoneRealloc(0, characters,
                                   2 * (used + batchLength));
        for (index = 0; index < batch; index++) {
            [objects[index] getCharacters:characters + used
                                    range:NSMakeRange(0, lengths[index])];
            used += lengths[index];
            memmove(characters + used, separatorCharacters,
                    separatorLength * sizeof(unichar));
            used += separatorLength;
        }
        objectIndex += batch;
    }

    result = [NSString stringWithCharacters:characters
                                    length:used - separatorLength];
    if (separatorCharacters != stackSeparator)
        NSZoneFree(0, separatorCharacters);
    NSZoneFree(0, characters);
    return result;
}

- (BOOL)containsObject:(id)anObject {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    if (anObject == nil || count == 0)
        return NO;
    return NSArrayIndexOfObjectInRange(
        self, anObject, NSMakeRange(0, count), NO, count, NO) != NSNotFound;
}

- (BOOL)containsObjectIdenticalTo:(id)anObject {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    return NSArrayIndexOfObjectInRange(
        self, anObject, NSMakeRange(0, count), YES, count, NO) != NSNotFound;
}

- (NSString *)description {
    return [self descriptionWithLocale:nil indent:0];
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    return [self descriptionWithLocale:locale indent:0];
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(unsigned)level {
    unsigned count = [self count];
    unsigned index;
    unsigned resultLength;
    unsigned compactLength;
    NSString *indent;
    NSMutableString *result = [[NSMutableString alloc] init];
    NSMutableString *compact = [[NSMutableString allocWithZone:NULL]
        initWithCapacity:79];

    resultLength = [result length];
    [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                           withString:@"("];
    resultLength = [result length];
    [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                           withString:@"\n"];
    compactLength = [compact length];
    [compact replaceCharactersInRange:NSMakeRange(compactLength, 0)
                            withString:@"("];

    for (index = 0; index < count; index++) {
        NSString *itemDescription = NSArrayDescriptionForObject(
            [self objectAtIndex:index], locale, level);

        if ([compact length] + [itemDescription length] > 0x4f) {
            [compact release];
            compact = nil;
        }

#if defined(__ppc__) || defined(__POWERPC__)
        resultLength = [result length];
        indent = _NSIndentSpace(level + 1);
#else
        indent = _NSIndentSpace(level + 1);
        resultLength = [result length];
#endif
        [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                               withString:indent];
        resultLength = [result length];
        [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                               withString:itemDescription];
        compactLength = [compact length];
        [compact replaceCharactersInRange:NSMakeRange(compactLength, 0)
                                withString:itemDescription];
        if (index + 1 < count) {
            resultLength = [result length];
            [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                                   withString:@", "];
            compactLength = [compact length];
            [compact replaceCharactersInRange:NSMakeRange(compactLength, 0)
                                    withString:@", "];
        }
        resultLength = [result length];
        [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                               withString:@"\n"];
    }

    indent = _NSIndentSpace(level);
    resultLength = [result length];
    [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                           withString:indent];
    resultLength = [result length];
    [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                           withString:@")"];
    compactLength = [compact length];
    [compact replaceCharactersInRange:NSMakeRange(compactLength, 0)
                            withString:@")"];

    if (compact != nil && [compact length] <= 0x4f) {
        [result release];
        return [compact autorelease];
    }
    [compact release];
    return [result autorelease];
}

- (id)firstObjectCommonWithArray:(NSArray *)otherArray {
    unsigned otherCount;
    unsigned count;
    unsigned totalCount;
    unsigned index;
    unsigned otherIndex;
    id stackObjects[128];
    id *objects = stackObjects;
    id result = nil;

    if (otherArray == nil)
        return nil;
    otherCount = [otherArray count];
    if (otherCount == 0)
        return nil;
    count = [self count];
    totalCount = count + otherCount;
    if (totalCount > 128)
        objects = NSZoneMalloc(NULL, totalCount * sizeof(id));
    [self getObjects:objects range:NSMakeRange(0, count)];
    [otherArray getObjects:objects + count
                     range:NSMakeRange(0, otherCount)];

    for (index = 0; index < count; index++) {
        id object = objects[index];
        IMP equalityImplementation = otherCount > 1
            ? _NSIMPForObjectAndSelector(object, @selector(isEqual:)) : NULL;

        for (otherIndex = 0; otherIndex < otherCount; otherIndex++) {
            id otherObject = objects[count + otherIndex];

            if (object == otherObject ||
                (otherCount == 1
                    ? [object isEqual:otherObject]
                    : ((BOOL (*)(id, SEL, id))equalityImplementation)(
                        object, @selector(isEqual:), otherObject))) {
                result = object;
                goto done;
            }
        }
    }

done:
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return result;
}

- (void)getObjects:(id *)objects {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    [self getObjects:objects range:NSMakeRange(0, count)];
}

- (void)getObjects:(id *)objects range:(NSRange)range {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    if (count < range.location + range.length)
        NSArrayRaiseBoundException(self, _cmd,
                                   range.location + range.length - 1, count);
    if (range.length == 0)
        return;
    if (concrete) {
        memmove(objects, ((NSConcreteArray *)self)->_items + range.location,
                range.length * sizeof(id));
    } else {
        NSArrayObjectAtIndexIMP objectAtIndex =
            (NSArrayObjectAtIndexIMP)_NSIMPForObjectAndSelector(
                self, @selector(objectAtIndex:));
        unsigned index;

        for (index = 0; index < range.length; index++)
            objects[index] = objectAtIndex(self, @selector(objectAtIndex:),
                                           range.location + index);
    }
}

- (unsigned)indexOfObject:(id)anObject {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    return [self indexOfObject:anObject
                         range:NSMakeRange(0, count)
                     identical:NO];
}

- (unsigned)indexOfObject:(id)anObject inRange:(NSRange)range {
    return [self indexOfObject:anObject range:range identical:NO];
}

- (unsigned)indexOfObjectIdenticalTo:(id)anObject {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    return [self indexOfObject:anObject
                         range:NSMakeRange(0, count)
                     identical:YES];
}

- (unsigned)indexOfObjectIdenticalTo:(id)anObject inRange:(NSRange)range {
    return [self indexOfObject:anObject range:range identical:YES];
}

- (unsigned)indexOfObject:(id)anObject range:(NSRange)range
                identical:(BOOL)identical {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    return NSArrayIndexOfObjectInRange(
        self, anObject, range, identical, count, NO);
}

- (unsigned)indexOfAttributeBySelector:(SEL)selector
                       equalToObject:(id)object {
    unsigned count = [self count];
    unsigned offset = 0;
    id batch[128];
    SEL equalitySelector = @selector(isEqual:);
    BOOL (*equalityImplementation)(id, SEL, id) =
        (BOOL (*)(id, SEL, id))_NSIMPForObjectAndSelector(
            object, equalitySelector);

    if (count == 0)
        return NSNotFound;

    while (offset < count) {
        unsigned batchCount = count - offset;
        unsigned index;

        if (batchCount > 128)
            batchCount = 128;
        [self getObjects:batch range:NSMakeRange(offset, batchCount)];
        for (index = 0; index < batchCount; index++) {
            id value = objc_msgSend(batch[index], selector);

            if (equalityImplementation(object, equalitySelector, value))
                return offset + index;
        }
        offset += batchCount;
    }
    return NSNotFound;
}

- (int)indexOf:(id)object :(int)start :(BOOL)reverse {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    if ((unsigned)start >= count)
        NSArrayRaiseBoundException(self, _cmd, (unsigned)start, count);
    if (start < 0)
        NSArrayRaiseBoundException(self, _cmd, (unsigned)start, 0);
    if (object == nil || count == 0)
        return NSNotFound;

    return NSArrayIndexOfObjectInRange(
        self, object,
        reverse ? NSMakeRange((unsigned)start, count - (unsigned)start)
                : NSMakeRange(0, (unsigned)start + 1),
        NO, count, !reverse);
}

- (BOOL)isEqualToArray:(NSArray *)otherArray {
    BOOL concrete;
    BOOL otherConcrete;
    unsigned count;
    unsigned otherCount;
    unsigned totalCount;
    unsigned index;
    id stackObjects[128];
    id *objects = stackObjects;

    concrete = NSArrayUsesConcreteStorage(self);
    count = concrete ? NSArrayConcreteCount(self) : [self count];
    otherConcrete = otherArray != nil &&
        NSArrayUsesConcreteStorage(otherArray);
    otherCount = otherArray == nil ? 0 :
        (otherConcrete ? NSArrayConcreteCount(otherArray) : [otherArray count]);
    if (otherArray == nil || count != otherCount)
        return NO;
    if (self == otherArray || count == 0)
        return YES;
    totalCount = count + otherCount;
    if (totalCount > 128)
        objects = NSZoneMalloc(NULL, totalCount * sizeof(id));
    if (concrete)
        memmove(objects, ((NSConcreteArray *)self)->_items,
                count * sizeof(id));
    else
        [self getObjects:objects range:NSMakeRange(0, count)];
    if (otherConcrete)
        memmove(objects + count, ((NSConcreteArray *)otherArray)->_items,
                otherCount * sizeof(id));
    else
        [otherArray getObjects:objects + count
                         range:NSMakeRange(0, otherCount)];
    for (index = 0; index < count; index++) {
        id first = objects[index];
        id second = objects[count + index];

        if (first != second && ![first isEqual:second])
            break;
    }
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return index >= count;
}

- (BOOL)isEqual:(id)object {
    if (object == self)
        return YES;
    if (object == nil)
        return NO;
    if (!NSArrayUsesConcreteStorage(object) &&
        ![object isKindOfClass:[NSArray class]])
        return NO;
    return [self isEqualToArray:object];
}

- (Class)classForCoder {
    return [NSArray class];
}

- (unsigned)hash {
    return NSArrayUsesConcreteStorage(self)
        ? NSArrayConcreteCount(self) : [self count];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [[NSMutableArray allocWithZone:zone]
        initWithArray:self copyItems:NO];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    NSConnection *connection;

    if (![coder isByref])
        return self;
    connection = [coder connection];
    return [NSDistantObject proxyWithLocal:self connection:connection];
}

- (id)retain {
    BOOL locked;

    if (!NSArrayUsesConcreteStorage(self))
        return [super retain];

    locked = NSArrayLockConcreteRetainCount();
    if ((((NSConcreteArray *)self)->_info & 0xf0000000) == 0xf0000000) {
        if (((NSConcreteArray *)self)->_info & 0x08000000)
            NSIncrementExtraRefCount(self);
        else
            ((NSConcreteArray *)self)->_info ^= 0x08000000;
        ((NSConcreteArray *)self)->_info &= 0x0fffffff;
    } else {
        ((NSConcreteArray *)self)->_info += 0x10000000;
    }
    NSArrayUnlockConcreteRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    BOOL shouldDeallocate = NO;
    BOOL locked;
    NSConcreteArray *array;

    if (!NSArrayUsesConcreteStorage(self)) {
        [super release];
        return;
    }
    array = (NSConcreteArray *)self;
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSArrayLockConcreteRetainCount();
    if ((array->_info >> 28) != 0) {
        array->_info -= 0x10000000;
    } else if (array->_info & 0x08000000) {
        if (NSDecrementExtraRefCountWasZero(self))
            array->_info ^= 0x08000000;
        array->_info |= 0xf0000000;
    } else {
        shouldDeallocate = YES;
    }
    NSArrayUnlockConcreteRetainCount(locked);
    if (shouldDeallocate)
        [super dealloc];
}

- (unsigned)retainCount {
    unsigned count;

    if (!NSArrayUsesConcreteStorage(self))
        return [super retainCount];
    count = ((NSConcreteArray *)self)->_info >> 28;
    if (((NSConcreteArray *)self)->_info & 0x08000000)
        return count + 16 * (NSExtraRefCount(self) + 1) + 1;
    return count + 1;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[NSArray allocWithZone:zone] initWithArray:self copyItems:YES];
}

- (id)lastObject {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];

    if (count == 0)
        return nil;
    if (concrete)
        return ((NSConcreteArray *)self)->_items[count - 1];
    return [self objectAtIndex:count - 1];
}

- (NSEnumerator *)objectEnumerator {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    id *objects = nil;

    if (count != 0) {
        if (concrete) {
            objects = ((NSConcreteArray *)self)->_items;
        } else {
            objects = NSZoneMalloc(0, count * sizeof(id));
            [self getObjects:objects range:NSMakeRange(0, count)];
        }
    }
    return [[[NSIdEnumerator allocWithZone:NSZoneFromPointer(self)]
             initWithObjects:objects count:count target:self reverse:NO
             freeWhenDone:!concrete] autorelease];
}

- (NSEnumerator *)reverseObjectEnumerator {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    id *objects = nil;

    if (count != 0) {
        if (concrete) {
            objects = ((NSConcreteArray *)self)->_items;
        } else {
            objects = NSZoneMalloc(0, count * sizeof(id));
            [self getObjects:objects range:NSMakeRange(0, count)];
        }
    }
    return [[[NSIdEnumerator allocWithZone:NSZoneFromPointer(self)]
             initWithObjects:objects count:count target:self reverse:YES
             freeWhenDone:!concrete] autorelease];
}

- (NSData *)sortedArrayHint {
    unsigned count = [self count], offset = 0;
    NSMutableData *hint = [NSMutableData dataWithCapacity:count * sizeof(int)];
    id objects[128];
    SEL serializeSelector = @selector(serializeInt:);
    void (*serializeInt)(id, SEL, int) =
        (void (*)(id, SEL, int))_NSIMPForObjectAndSelector(hint, serializeSelector);

    while (offset < count) {
        unsigned batch = count - offset;
        unsigned index;

        if (batch > 128)
            batch = 128;
        [self getObjects:objects range:NSMakeRange(offset, batch)];
        for (index = 0; index < batch; index++)
            serializeInt(hint, serializeSelector, (int)[objects[index] hash]);
        offset += batch;
    }
    return hint;
}

- (NSArray *)sortedArrayUsingFunction:(int (*)(id, id, void *))comparator context:(void *)context {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    id stackStorage[128 * 3];
    id *storage = stackStorage;
    id *sorted;
    NSArray *array;

    if (count == 0)
        return __NSEmptyArray;
    if (count == 1)
        return [NSArray arrayWithArray:self];
    if (count > 128)
        storage = NSZoneMalloc(0, 3 * count * sizeof(id));
    if (concrete)
        memmove(storage, ((NSConcreteArray *)self)->_items, count * sizeof(id));
    else
        [self getObjects:storage range:NSMakeRange(0, count)];
    sorted = _NSMergeSort(count, storage, storage + count,
                          storage + 2 * count,
                          (NSArrayComparator)comparator, context,
                          count > 0x3f);
    array = [NSArray arrayWithObjects:sorted count:count];
    if (storage != stackStorage)
        NSZoneFree(0, storage);
    return array;
}

- (NSArray *)sortedArrayUsingFunction:(int (*)(id, id, void *))comparator context:(void *)context hint:(NSData *)hint {
    unsigned count = [self count];
    unsigned hintCount, index, uniqueCount, outputCount;
    unsigned *hintHashes;
    id *storage;
    id *sorted;
    void *key, *value;
    NSMapTable *hashes;
    NSMapEnumerator enumerator;
    NSArray *array;

    if (count <= 3)
        return [self sortedArrayUsingFunction:comparator context:context];

    hintCount = [hint length] / sizeof(int);
    hashes = NSCreateMapTableWithZone(NSIntMapKeyCallBacks,
                                      NSNonOwnedPointerMapValueCallBacks,
                                      3 * count, 0);
    hintHashes = NSZoneMalloc(0, hintCount * sizeof(unsigned));
    storage = NSZoneMalloc(0, 4 * count * sizeof(id));
    uniqueCount = count;
    outputCount = 0;
    for (index = 0; index < count; index++) {
        id object = [self objectAtIndex:index];
        unsigned hash = [object hash];

        key = (void *)(unsigned long)hash;
        if (key == NSIntMapKeyCallBacks.notAKeyMarker ||
            NSMapGet(hashes, key) != NULL)
            storage[--uniqueCount] = object;
        else
            NSMapInsertKnownAbsent(hashes, key, object);
    }

    [hint deserializeInts:(int *)hintHashes count:hintCount atIndex:0];
    for (index = 0; index < hintCount; index++) {
        key = (void *)(unsigned long)hintHashes[index];
        value = NSMapGet(hashes, key);
        if (value != NULL) {
            storage[outputCount++] = value;
            NSMapRemove(hashes, key);
        }
    }
    enumerator = NSEnumerateMapTable(hashes);
    while (NSNextMapEnumeratorPair(&enumerator, &key, &value))
        storage[outputCount++] = value;
    if (outputCount != uniqueCount)
        NSLog(@"%@: broken invariant, %d != %d",
              _NSMethodExceptionProem(self, _cmd), outputCount, uniqueCount);
    NSFreeMapTable(hashes);
    NSZoneFree(0, hintHashes);

    sorted = _NSMergeSort(count, storage, storage + count,
                          storage + 2 * count,
                          (NSArrayComparator)comparator, context, 1);
    array = [NSArray arrayWithObjects:sorted count:count];
    NSZoneFree(0, storage);
    return array;
}

- (NSArray *)sortedArrayUsingSelector:(SEL)comparator {
    return [self sortedArrayUsingFunction:NSArraySortUsingSelector
                                  context:(void *)comparator];
}

- (NSArray *)sortedArrayUsingSelector:(SEL)comparator hint:(NSData *)hint {
    return [self sortedArrayUsingFunction:NSArraySortUsingSelector
                                  context:(void *)comparator
                                     hint:hint];
}

- (NSArray *)arrayByApplyingSelector:(SEL)selector {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned resultCount = 0, index;
    NSArray *result;

    if (count == 0)
        return __NSEmptyArray;
    if (count > 128)
        objects = NSZoneMalloc(0, count * sizeof(id));
    if (concrete)
        memmove(objects, ((NSConcreteArray *)self)->_items,
                count * sizeof(id));
    else
        [self getObjects:objects range:NSMakeRange(0, count)];
    for (index = 0; index < count; index++) {
        id value = objc_msgSend(objects[index], selector);

        if (value != nil)
            objects[resultCount++] = value;
    }
    result = [NSArray arrayWithObjects:objects count:resultCount];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return result;
}

- (NSArray *)arrayByExcludingObjectsInArray:(NSArray *)otherArray
                                  identical:(BOOL)identical {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    BOOL otherConcrete = otherArray != nil &&
        NSArrayUsesConcreteStorage(otherArray);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    unsigned otherCount = otherArray == nil ? 0 :
        (otherConcrete ? NSArrayConcreteCount(otherArray) : [otherArray count]);
    unsigned totalCount;
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned resultCount = 0, index;
    NSArray *result;

    if (count == 0)
        return __NSEmptyArray;
    if (otherCount == 0)
        return [NSArray arrayWithArray:self copyItems:NO];
    totalCount = count + otherCount;
    if (totalCount > 128)
        objects = NSZoneMalloc(0, totalCount * sizeof(id));
    if (concrete)
        memmove(objects, ((NSConcreteArray *)self)->_items,
                count * sizeof(id));
    else
        [self getObjects:objects range:NSMakeRange(0, count)];
    if (otherConcrete)
        memmove(objects + count, ((NSConcreteArray *)otherArray)->_items,
                otherCount * sizeof(id));
    else
        [otherArray getObjects:objects + count
                         range:NSMakeRange(0, otherCount)];
    for (index = 0; index < count; index++) {
        id object = objects[index];
        unsigned otherIndex;
        BOOL found = NO;
        IMP equalityImplementation = NULL;

        if (!identical && otherCount > 1)
            equalityImplementation = _NSIMPForObjectAndSelector(
                object, @selector(isEqual:));
        for (otherIndex = 0; otherIndex < otherCount; otherIndex++) {
            id candidate = objects[count + otherIndex];

            if (candidate == object || (!identical &&
                (otherCount == 1 ? [object isEqual:candidate]
                    : ((BOOL (*)(id, SEL, id))equalityImplementation)(
                        object, @selector(isEqual:), candidate)))) {
                found = YES;
                break;
            }
        }
        if (!found)
            objects[resultCount++] = object;
    }
    result = [NSArray arrayWithObjects:objects count:resultCount];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return result;
}

- (NSArray *)arrayByExcludingObjectsInArray:(NSArray *)otherArray {
    return [self arrayByExcludingObjectsInArray:otherArray identical:NO];
}

- (NSArray *)arrayByExcludingIdenticalObjectsInArray:(NSArray *)otherArray {
    return [self arrayByExcludingObjectsInArray:otherArray identical:YES];
}

- (NSArray *)arrayByExcludingToObjectsInArray:(NSArray *)otherArray {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    BOOL otherConcrete = NO;
    unsigned count, otherCount;
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned resultCount = 0, index;
    NSArray *result;

#if defined(__ppc__) || defined(__POWERPC__)
    otherConcrete = NSArrayUsesConcreteStorage(otherArray);
#endif
    count = concrete ? NSArrayConcreteCount(self) : [self count];
#if !defined(__ppc__) && !defined(__POWERPC__)
    if (otherArray != nil)
        otherConcrete = NSArrayUsesConcreteStorage(otherArray);
#endif
    otherCount = otherArray == nil ? 0
        : (otherConcrete ? NSArrayConcreteCount(otherArray) : [otherArray count]);

    if (count == 0)
        return __NSEmptyArray;
    if (otherCount == 0)
        return [NSArray arrayWithArray:self copyItems:NO];

    if (count + otherCount > 128)
        objects = NSZoneMalloc(0, (count + otherCount) * sizeof(id));
    if (concrete)
        memmove(objects, ((NSConcreteArray *)self)->_items, count * sizeof(id));
    else
        [self getObjects:objects range:NSMakeRange(0, count)];
    if (otherConcrete)
        memmove(objects + count,
                ((NSConcreteArray *)otherArray)->_items,
                otherCount * sizeof(id));
    else
        [otherArray getObjects:objects + count
                         range:NSMakeRange(0, otherCount)];

    for (index = 0; index < count; index++) {
        id object = objects[index];
        IMP equalityImplementation = NULL;
        BOOL found = NO;
        unsigned otherIndex;

        if (object != nil && otherCount > 1)
            equalityImplementation = _NSIMPForObjectAndSelector(
                object, @selector(isEqual:));
        for (otherIndex = 0; object != nil && otherIndex < otherCount;
             otherIndex++) {
            id otherObject = objects[count + otherIndex];

            if (object == otherObject ||
                (otherCount == 1
                    ? [object isEqual:otherObject]
                    : ((BOOL (*)(id, SEL, id))equalityImplementation)(
                        object, @selector(isEqual:), otherObject))) {
                found = YES;
                break;
            }
        }
        if (found)
            objects[resultCount++] = object;
    }
    result = [NSArray arrayWithObjects:objects count:resultCount];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return result;
}

- (NSArray *)subarrayWithRange:(NSRange)range {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    id stackObjects[128];
    id *objects = stackObjects;
    NSArray *array;

    if (count < range.location + range.length)
        NSArrayRaiseBoundException(self, _cmd,
                                   range.location + range.length - 1, count);
    if (range.length == 0)
        return __NSEmptyArray;
    if (range.length > 128)
        objects = NSZoneMalloc(0, range.length * sizeof(id));
    [self getObjects:objects range:range];
    array = [NSArray arrayWithObjects:objects count:range.length];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return array;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    return [[self _stringToWrite] writeToFile:path
                                   atomically:useAuxiliaryFile];
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically {
    return [[self _stringToWrite] writeToURL:url atomically:atomically];
}

- (NSString *)_stringToWrite {
    NSString *string = [self descriptionWithLocale:nil indent:0];

    if (![string hasSuffix:@"\n"]) {
        if ([string isKindOfClass:[NSMutableString class]]) {
            unsigned length = [string length];

            [(NSMutableString *)string
                replaceCharactersInRange:NSMakeRange(length, 0)
                              withString:@"\n"];
        } else {
            string = [string stringByAppendingString:@"\n"];
        }
    }
    return string;
}

- (void)makeObjectsPerformSelector:(SEL)aSelector {
    [self makeObjectsPerformSelector:aSelector withObject:nil];
}

- (void)makeObjectsPerformSelector:(SEL)aSelector withObject:(id)argument {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    unsigned index;

    if (concrete) {
        id *objects = ((NSConcreteArray *)self)->_items;

        for (index = 0; index < count; index++)
            objc_msgSend(objects[index], aSelector, argument);
    } else {
        id objects[128];
        unsigned offset = 0;

        while (offset < count) {
            unsigned batch = count - offset;

            if (batch > 128)
                batch = 128;
            [self getObjects:objects range:NSMakeRange(offset, batch)];
            for (index = 0; index < batch; index++)
                objc_msgSend(objects[index], aSelector, argument);
            offset += batch;
        }
    }
}

- (void)makeObjectsPerform:(SEL)aSelector {
    [self makeObjectsPerformSelector:aSelector];
}

- (void)makeObjectsPerform:(SEL)aSelector withObject:(id)argument {
    [self makeObjectsPerformSelector:aSelector withObject:argument];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    int encodedCount = (int)count;
    unsigned index;
    SEL encodeSelector = @selector(encodeBycopyObject:);
    void (*encodeObject)(id, SEL, id);

    [coder encodeValueOfObjCType:"i" at:&encodedCount];
    if (count == 0)
        return;
    encodeObject = (void (*)(id, SEL, id))
        _NSIMPForObjectAndSelector(coder, encodeSelector);

    if (concrete) {
        id *items = ((NSConcreteArray *)self)->_items;

        for (index = 0; index < count; index++)
            encodeObject(coder, encodeSelector, items[index]);
    } else {
        id items[128];
        unsigned offset = 0;

        while (offset < count) {
            unsigned batch = count - offset;
            unsigned itemIndex;

            if (batch > 128)
                batch = 128;
            [self getObjects:items range:NSMakeRange(offset, batch)];
            for (itemIndex = 0; itemIndex < batch; itemIndex++)
                encodeObject(coder, encodeSelector, items[itemIndex]);
            offset += batch;
        }
    }
}

+ (id)array {
    if (self == [NSArray class])
        return __NSEmptyArray;
    return [[[self allocWithZone:NULL] initWithObjects:NULL
                                               count:0] autorelease];
}

+ (id)arrayWithContentsOfFile:(NSString *)path {
    return [[[self allocWithZone:NULL] initWithContentsOfFile:path] autorelease];
}

+ (id)arrayWithContentsOfURL:(NSURL *)url {
    return [[[self allocWithZone:NULL] initWithContentsOfURL:url] autorelease];
}

+ (id)arrayWithObject:(id)anObject {
    id objects[1];

    if (anObject == nil) {
        NSArrayRaiseInsertNilException(self, _cmd);
        return nil;
    }
    objects[0] = anObject;
    return [self arrayWithObjects:objects count:1];
}

+ (id)arrayWithObjects:(id)firstObj, ... {
    va_list arguments;
    id array;

    va_start(arguments, firstObj);
    array = NSArrayFromObjectsAndCount(self, YES, firstObj, &arguments);
    va_end(arguments);
    return array;
}

- (id)initWithArray:(NSArray *)array {
    return [self initWithArray:array copyItems:NO];
}

- (id)initWithArray:(NSArray *)array copyItems:(BOOL)copyItems {
    unsigned count = [array count];
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned index;
    id result;
    NSZone *zone = copyItems ? NSZoneFromPointer(self) : nil;

    if (count == 0)
        return [self initWithObjects:NULL count:0];
    if (count > 128)
        objects = NSZoneMalloc(0, count * sizeof(id));
    [array getObjects:objects range:NSMakeRange(0, count)];
    for (index = 0; index < count; index++) {
        if (copyItems)
            objects[index] = [objects[index] copyWithZone:zone];
    }
    result = [self initWithObjects:objects count:count];
    if (copyItems) {
        for (index = 0; index < count; index++)
            [objects[index] release];
    }
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return result;
}

- (id)initWithContentsOfFile:(NSString *)path {
    NSData *data = [[NSData allocWithZone:NULL] initWithContentsOfFile:path];
    id result = [self _initWithData:data];
    [data release];
    return result;
}

- (id)initWithContentsOfURL:(NSURL *)url {
    NSData *data = [[NSData allocWithZone:NULL] initWithContentsOfURL:url];
    id result = [self _initWithData:data];
    [data release];
    return result;
}

- (id)_initWithData:(NSData *)data {
    NSZone *zone = NSZoneFromPointer(self);
    id propertyList;

    [self dealloc];
    propertyList = data == nil ? nil
        : _NSParseObjectFromASCIIPropertyListOrSerialization(data);
    if (propertyList == nil ||
        ![propertyList isKindOfClass:[NSArray class]])
        return nil;
    return [propertyList copyWithZone:zone];
}

- (id)initWithCoder:(NSCoder *)coder {
    unsigned count;
    unsigned index;
    id stackObjects[128];
    id *objects = stackObjects;
    id result;
    SEL decodeSelector = @selector(decodeValueOfObjCType:at:);
    void (*decodeObject)(id, SEL, const char *, id *);

    [coder decodeValueOfObjCType:"i" at:&count];
    if (count > 0x07ffffff) {
        [self dealloc];
        NSArrayRaiseSizeException(self, _cmd, count, "count");
        return nil;
    }
    decodeObject = (void (*)(id, SEL, const char *, id *))
        _NSIMPForObjectAndSelector(coder, decodeSelector);
    if (count > 128)
        objects = NSZoneMalloc(0, count * sizeof(id));
    for (index = 0; index < count; index++)
        decodeObject(coder, decodeSelector, "@", &objects[index]);
    result = [self initWithObjects:objects count:count];
    while (count != 0)
        [objects[--count] release];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return result;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count {
    NSRequestConcreteImplementation(self, _cmd, [NSArray class]);
    return nil;
}

- (id)initWithObjects:(id)firstObj, ... {
    va_list arguments;
    id array;

    va_start(arguments, firstObj);
    array = NSArrayFromObjectsAndCount(self, NO, firstObj, &arguments);
    va_end(arguments);
    return array;
}

+ (id)arrayWithArray:(NSArray *)array {
    return [self arrayWithArray:array copyItems:NO];
}

+ (id)arrayWithArray:(NSArray *)array copyItems:(BOOL)copyItems {
    return [[[self allocWithZone:NULL] initWithArray:array
                                          copyItems:copyItems] autorelease];
}

+ (id)arrayWithObjects:(id *)objs count:(unsigned)cnt {
    return [[[self allocWithZone:NULL] initWithObjects:objs
                                                count:cnt] autorelease];
}

@end

@implementation NSConcreteArray

- (id)init
{
    return [self initWithObjects:nil count:0];
}

- (id)initWithObjects:(id *)objects count:(unsigned)count
{
    unsigned index;

    if (count == 0) {
        NSDeallocateObject(self);
        return [__NSEmptyArray retain];
    }
    if (count > 0x07ffffff) {
        NSDeallocateObject(self);
        NSArrayRaiseSizeException(self, _cmd, count, "count");
        return nil;
    }

    _items = NSZoneMalloc(NSZoneFromPointer(self), count * sizeof(id));
    for (index = 0; index < count; index++) {
        _items[index] = [objects[index] retain];
        if (_items[index] == nil) {
            _info = index | (_info & 0xf8000000);
            [self dealloc];
            NSArrayRaiseInsertNilException(self, _cmd);
            return nil;
        }
    }
    _info = count | (_info & 0xf8000000);
    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    unsigned count;
    unsigned index;
    SEL decodeSelector = @selector(decodeValueOfObjCType:at:);
    void (*decodeObject)(id, SEL, const char *, id *);

    [coder decodeValueOfObjCType:"i" at:&count];
    if (count == 0) {
        NSDeallocateObject(self);
        return [__NSEmptyArray retain];
    }
    if (count > 0x07ffffff) {
        _items = nil;
        [self dealloc];
        NSArrayRaiseSizeException(self, _cmd, count, "count");
        return nil;
    }

    _items = NSZoneMalloc(NSZoneFromPointer(self), count * sizeof(id));
    decodeObject = (void (*)(id, SEL, const char *, id *))
        _NSIMPForObjectAndSelector(coder, decodeSelector);
    for (index = 0; index < count; index++) {
        decodeObject(coder, decodeSelector, "@", &_items[index]);
        if (_items[index] == nil) {
            _info = (_info & 0xf8000000) | index;
            [self dealloc];
            NSArrayRaiseInsertNilException(self, _cmd);
            return nil;
        }
    }
    _info = (_info & 0xf8000000) | count;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];
}

- (void)dealloc
{
    unsigned count = _info & 0x07ffffff;

    while (count != 0)
        [_items[--count] release];
    if (_items != nil)
        NSZoneFree(NSZoneFromPointer(_items), _items);
    [super dealloc];
}

@end

@implementation NSIdEnumerator

- (id)initWithObjects:(id *)objects count:(unsigned)count target:(id)target
             reverse:(BOOL)reverse freeWhenDone:(BOOL)freeWhenDone
{
    _slot = reverse ? count : 0;
    _limit = reverse ? 0 : count;
    _list = count == 0 ? nil : objects;
    _target = _list != nil && target != nil ? [target retain] : nil;
    _free = freeWhenDone;
    return self;
}

- (id)nextObject
{
    id object;

    if (_list == nil)
        return nil;
    if (_slot <= _limit)
        object = _list[_slot++];
    else
        object = _list[--_slot];
    if (_limit == _slot) {
        [object retain];
        [object autorelease];
        [self invalidate];
    }
    return object;
}

- (NSArray *)allObjects
{
    unsigned count, index;
    id stackObjects[128];
    id *objects = stackObjects;
    NSArray *array;

    if (_list == nil)
        return [NSArray arrayWithObjects:nil count:0];
    if (_limit <= _slot) {
        count = _slot - _limit;
        if (count > 128)
            objects = NSZoneMalloc(0, count * sizeof(id));
        for (index = 0; index < count; index++)
            objects[index] = _list[--_slot];
        array = [NSArray arrayWithObjects:objects count:count];
        if (objects != stackObjects)
            NSZoneFree(0, objects);
    } else {
        count = _limit - _slot;
        array = [NSArray arrayWithObjects:_list + _slot count:count];
    }
    [self invalidate];
    return array;
}

- (void)invalidate
{
    if (_target != nil) {
        [_target release];
        _target = nil;
    }
    if (_free && _list != nil)
        _NSGenericFree(_list);
    _list = nil;
}

- (void)dealloc
{
    [self invalidate];
    [super dealloc];
}

@end

@implementation NSMutableArray

- (Class)classForCoder {
    return [NSMutableArray class];
}

- (void)exchangeObjectAtIndex:(unsigned)firstIndex
         withObjectAtIndex:(unsigned)secondIndex {
    unsigned count = NSArrayUsesConcreteStorage(self)
        ? NSArrayConcreteCount(self) : [self count];

    if (firstIndex >= count)
        NSArrayRaiseBoundException(self, _cmd, firstIndex, count);
    if (secondIndex >= count)
        NSArrayRaiseBoundException(self, _cmd, secondIndex, count);

    if (NSArrayUsesConcreteStorage(self)) {
        id *objects = ((NSConcreteArray *)self)->_items;
        id object = objects[firstIndex];

        objects[firstIndex] = objects[secondIndex];
        objects[secondIndex] = object;
    } else {
        id firstObject = [[self objectAtIndex:firstIndex] retain];
        id secondObject = [self objectAtIndex:secondIndex];

        [self replaceObjectAtIndex:firstIndex withObject:secondObject];
        [self replaceObjectAtIndex:secondIndex withObject:firstObject];
        [firstObject release];
    }
}

- (void)addObject:(id)anObject {
    NSConcreteMutableArray *array;
    unsigned count;

    if (!NSArrayUsesConcreteStorage(self)) {
        NSRequestConcreteImplementation(self, _cmd, [NSMutableArray class]);
    }
    if (anObject == nil) {
        NSArrayRaiseInsertNilException(self, _cmd);
        return;
    }
    array = (NSConcreteMutableArray *)self;
    count = array->_info & 0x07ffffff;
    NSConcreteMutableArrayEnsureCapacity(array, 1);
    array->_items[count] = [anObject retain];
    array->_info++;
}

- (void)insertObject:(id)anObject atIndex:(unsigned)index {
    NSConcreteMutableArray *array;
    unsigned count;

    if (!NSArrayUsesConcreteStorage(self)) {
        NSRequestConcreteImplementation(self, _cmd, [NSMutableArray class]);
    }
    if (anObject == nil) {
        NSArrayRaiseInsertNilException(self, _cmd);
        return;
    }
    array = (NSConcreteMutableArray *)self;
    count = array->_info & 0x07ffffff;
    if (index > count) {
        NSArrayRaiseBoundException(self, _cmd, index, count + 1);
        return;
    }
    NSConcreteMutableArrayEnsureCapacity(array, 1);
    if (index < count)
        memmove(array->_items + index + 1, array->_items + index,
                (count - index) * sizeof(id));
    array->_items[index] = [anObject retain];
    array->_info++;
}

- (void)removeLastObject {
    NSConcreteMutableArray *array;
    unsigned count;

    if (!NSArrayUsesConcreteStorage(self))
        NSRequestConcreteImplementation(self, _cmd, [NSMutableArray class]);
    array = (NSConcreteMutableArray *)self;
    count = NSArrayConcreteCount(self);
    if (count == 0)
        NSArrayRaiseBoundException(self, _cmd, 0, 0);
    [array->_items[count - 1] release];
    array->_info--;
}

- (void)removeObjectAtIndex:(unsigned)index {
    NSConcreteMutableArray *array;
    unsigned count;
    id object;

    if (!NSArrayUsesConcreteStorage(self)) {
        NSRequestConcreteImplementation(self, _cmd, [NSMutableArray class]);
    }
    array = (NSConcreteMutableArray *)self;
    count = array->_info & 0x07ffffff;
    if (index >= count) {
        NSArrayRaiseBoundException(self, _cmd, index, count);
        return;
    }
    object = array->_items[index];
    [object release];
    if (count > index + 1)
        memmove(array->_items + index, array->_items + index + 1,
                (count - (index + 1)) * sizeof(id));
    array->_info--;
}

- (void)replaceObjectAtIndex:(unsigned)index withObject:(id)anObject {
    NSConcreteMutableArray *array;
    id oldObject;

    if (!NSArrayUsesConcreteStorage(self)) {
        NSRequestConcreteImplementation(self, _cmd, [NSMutableArray class]);
    }
    if (anObject == nil) {
        NSArrayRaiseInsertNilException(self, _cmd);
        return;
    }
    array = (NSConcreteMutableArray *)self;
    if (index >= (array->_info & 0x07ffffff)) {
        NSArrayRaiseBoundException(self, _cmd, index,
                                   array->_info & 0x07ffffff);
        return;
    }
    oldObject = array->_items[index];
    if (oldObject != anObject) {
        array->_items[index] = [anObject retain];
        [oldObject release];
    }
}

- (void)addObjectsFromArray:(NSArray *)otherArray {
    unsigned count = otherArray == nil ? 0 :
        (NSArrayUsesConcreteStorage(otherArray)
            ? NSArrayConcreteCount(otherArray) : [otherArray count]);

    if (count == 0)
        return;

    if (NSArrayUsesConcreteStorage(self)) {
        NSConcreteMutableArray *array = (NSConcreteMutableArray *)self;
        unsigned oldCount = array->_info & 0x07ffffff;
        unsigned index;

        NSConcreteMutableArrayEnsureCapacity(array, count);
        if (NSArrayUsesConcreteStorage(otherArray)) {
            id *source = ((NSConcreteArray *)otherArray)->_items;

            memmove(array->_items + oldCount, source, count * sizeof(id));
        } else {
            [otherArray getObjects:array->_items + oldCount
                             range:NSMakeRange(0, count)];
        }
        for (index = 0; index < count; index++)
            [array->_items[oldCount + index] retain];
        array->_info = (array->_info & 0xf8000000) | (oldCount + count);
    } else {
        id objects[128];
        unsigned offset = 0;
        IMP addImplementation =
            _NSIMPForObjectAndSelector(self, @selector(addObject:));

        while (offset < count) {
            unsigned batch = count - offset;
            unsigned index;

            if (batch > 128)
                batch = 128;
            [otherArray getObjects:objects range:NSMakeRange(offset, batch)];
            for (index = 0; index < batch; index++)
                ((void (*)(id, SEL, id))addImplementation)(
                    self, @selector(addObject:), objects[index]);
            offset += batch;
        }
    }
}

- (void)removeAllObjects {
    NSConcreteMutableArray *array;
    unsigned count;

    if (!NSArrayUsesConcreteStorage(self)) {
        IMP removeLastImplementation;

        count = [self count];
        if (count == 0)
            return;
        removeLastImplementation =
            _NSIMPForObjectAndSelector(self, @selector(removeLastObject));
        while (count-- != 0)
            ((void (*)(id, SEL))removeLastImplementation)(
                self, @selector(removeLastObject));
        return;
    }
    array = (NSConcreteMutableArray *)self;
    count = NSArrayConcreteCount(self);
    while (count != 0)
        [array->_items[--count] release];
    array->_info &= 0xf8000000;
}

- (void)removeObject:(id)anObject inRange:(NSRange)range {
    [self removeObject:anObject range:range identical:NO];
}

- (void)removeObject:(id)object range:(NSRange)range identical:(BOOL)identical {
    unsigned count = NSArrayUsesConcreteStorage(self)
        ? NSArrayConcreteCount(self) : [self count];
    unsigned rangeEnd = range.location + range.length;
    unsigned remainingReferences;
    IMP equalityImplementation = NULL;

    if (rangeEnd > count) {
        NSArrayRaiseBoundException(self, _cmd, rangeEnd - 1, count);
        return;
    }
    if (range.length == 0)
        return;

    if (!identical)
        equalityImplementation =
            _NSIMPForObjectAndSelector(object, @selector(isEqual:));
    remainingReferences = [object retainCount];
    if (remainingReferences == 0)
        return;

    if (NSArrayUsesConcreteStorage(self)) {
        NSConcreteArray *array = (NSConcreteArray *)self;
        unsigned readIndex = range.location;
        unsigned writeIndex = range.location;

        while (readIndex < rangeEnd && remainingReferences != 0) {
            id candidate = array->_items[readIndex];

            if (candidate == object ||
                (!identical && ((BOOL (*)(id, SEL, id))equalityImplementation)(
                    object, @selector(isEqual:), candidate))) {
                [candidate release];
                if (candidate == object)
                    remainingReferences--;
            } else {
                array->_items[writeIndex++] = candidate;
            }
            readIndex++;
        }
        if (count > readIndex && writeIndex < readIndex)
            memmove(array->_items + writeIndex, array->_items + readIndex,
                    (count - readIndex) * sizeof(id));
        ((NSConcreteMutableArray *)self)->_info =
            (((NSConcreteMutableArray *)self)->_info & 0xf8000000) |
            (count + writeIndex - readIndex);
    } else {
        id objects[128];
        BOOL remove[128];
        unsigned current = range.location;
        IMP removeImplementation =
            _NSIMPForObjectAndSelector(self, @selector(removeObjectAtIndex:));

        while (current < rangeEnd && remainingReferences != 0) {
            unsigned batch = rangeEnd - current;
            unsigned index;
            unsigned removed = 0;

            if (batch > 128)
                batch = 128;
            [self getObjects:objects range:NSMakeRange(current, batch)];
            for (index = 0; index < batch; index++) {
                id candidate = objects[index];

                remove[index] = remainingReferences != 0 &&
                    (candidate == object ||
                     (!identical && ((BOOL (*)(id, SEL, id))equalityImplementation)(
                         object, @selector(isEqual:), candidate)));
                if (candidate == object)
                    remainingReferences--;
            }
            for (index = 0; index < batch; index++) {
                if (remove[index]) {
                    ((void (*)(id, SEL, unsigned))removeImplementation)(
                        self, @selector(removeObjectAtIndex:),
                        current + index - removed);
                    removed++;
                }
            }
            current += batch - removed;
            rangeEnd -= removed;
        }
    }
}

- (void)removeObject:(id)anObject {
    unsigned count = NSArrayUsesConcreteStorage(self)
        ? NSArrayConcreteCount(self) : [self count];

    [self removeObject:anObject range:NSMakeRange(0, count) identical:NO];
}

- (void)removeObjectIdenticalTo:(id)anObject inRange:(NSRange)range {
    [self removeObject:anObject range:range identical:YES];
}

- (void)removeObjectIdenticalTo:(id)anObject {
    unsigned count = NSArrayUsesConcreteStorage(self)
        ? NSArrayConcreteCount(self) : [self count];

    [self removeObject:anObject range:NSMakeRange(0, count) identical:YES];
}

- (void)removeObjectsFromIndices:(unsigned *)indices numIndices:(unsigned)count {
    unsigned index;
    unsigned *allocatedIndices = nil;

    if (count > 1) {
        BOOL ordered = YES;
        for (index = 1; index < count; index++) {
            if (indices[index] < indices[index - 1]) {
                ordered = NO;
                break;
            }
        }
        if (!ordered) {
            allocatedIndices = NSZoneMalloc(0, count * sizeof(unsigned));
            memmove(allocatedIndices, indices, count * sizeof(unsigned));
            qsort(allocatedIndices, count, sizeof(unsigned),
                  NSArrayCompareIndices);
            indices = allocatedIndices;
        }
    }
    while (count != 0)
        [self removeObjectAtIndex:indices[--count]];
    if (allocatedIndices != nil)
        NSZoneFree(0, allocatedIndices);
}

- (void)removeObjectsInArray:(NSArray *)otherArray {
    unsigned otherCount = [otherArray count];

    if (otherCount == 1) {
        [self removeObject:[otherArray objectAtIndex:0]];
    } else if (otherCount != 0) {
        NSHashTable *objects = NSCreateHashTableWithZone(
            NSNonRetainedObjectHashCallBacks, otherCount, NULL);
        unsigned receiverCount = [self count];
        unsigned *indices = NSZoneMalloc(NULL,
                                         receiverCount * sizeof(unsigned));
        unsigned index;
        unsigned indexCount = 0;

        for (index = 0; index < otherCount; index++)
            NSHashInsert(objects, [otherArray objectAtIndex:index]);
        for (index = 0; index < receiverCount; index++) {
            id object = [self objectAtIndex:index];

            if (NSHashGet(objects, object) != NULL)
                indices[indexCount++] = index;
        }
        NSFreeHashTable(objects);
        if (indexCount != 0)
            [self removeObjectsFromIndices:indices numIndices:indexCount];
        NSZoneFree(NULL, indices);
    }
}

- (void)removeObjectsInRange:(NSRange)range {
    unsigned index = range.length;

    while (index != 0) {
        index--;
        [self removeObjectAtIndex:range.location + index];
    }
}

- (void)replaceObjectsInRange:(NSRange)range withObjectsFromArray:(NSArray *)otherArray range:(NSRange)otherRange {
    unsigned location = otherRange.location;
    unsigned length = otherRange.length;

    while (range.length != 0 && length != 0) {
        id object = [otherArray objectAtIndex:location++];

        [self replaceObjectAtIndex:range.location++ withObject:object];
        range.length--;
        length--;
    }
    while (length != 0) {
        id object = [otherArray objectAtIndex:location++];

        [self insertObject:object atIndex:range.location++];
        length--;
    }
    while (range.length != 0) {
        [self removeObjectAtIndex:range.location];
        range.length--;
    }
}

- (void)replaceObjectsInRange:(NSRange)range withObjectsFromArray:(NSArray *)otherArray {
    unsigned count = 0;

    if (otherArray != nil) {
        count = NSArrayUsesConcreteStorage(otherArray)
            ? NSArrayConcreteCount(otherArray) : [otherArray count];
    }
    [self replaceObjectsInRange:range
           withObjectsFromArray:otherArray
                          range:NSMakeRange(0, count)];
}

- (void)setArray:(NSArray *)otherArray {
    [self removeAllObjects];
    [self addObjectsFromArray:otherArray];
}

- (void)sortUsingFunction:(int (*)(id, id, void *))compare context:(void *)context {
    BOOL concrete = NSArrayUsesConcreteStorage(self);
    unsigned count = concrete ? NSArrayConcreteCount(self) : [self count];
    id stackStorage[128 * 3];
    id *storage = stackStorage;
    id *sorted;
    unsigned index;

    if (count <= 1)
        return;
    if (count > 128)
        storage = NSZoneMalloc(0, 3 * count * sizeof(id));
    if (concrete)
        memmove(storage, ((NSConcreteArray *)self)->_items,
                count * sizeof(id));
    else
        [self getObjects:storage range:NSMakeRange(0, count)];
    sorted = _NSMergeSort(count, storage, storage + count,
                          storage + 2 * count,
                          (NSArrayComparator)compare, context,
                          count > 0x3f);

    if (concrete) {
        memmove(((NSConcreteArray *)self)->_items, sorted,
                count * sizeof(id));
    } else {
        for (index = 0; index < count; index++)
            [sorted[index] retain];
        for (index = 0; index < count; index++)
            [self replaceObjectAtIndex:index withObject:sorted[index]];
        for (index = 0; index < count; index++)
            [sorted[index] release];
    }

    if (storage != stackStorage)
        NSZoneFree(0, storage);
}

- (void)sortUsingSelector:(SEL)comparator {
    [self sortUsingFunction:NSArraySortUsingSelector context:(void *)comparator];
}

+ (id)arrayWithCapacity:(unsigned)numItems {
    return [[[self allocWithZone:NULL] initWithCapacity:numItems] autorelease];
}

- (id)initWithCapacity:(unsigned)numItems {
    NSRequestConcreteImplementation(self, _cmd, [NSMutableArray class]);
    return nil;
}

- (id)initWithContentsOfFile:(NSString *)path {
    NSData *data = [[NSData allocWithZone:NULL] initWithContentsOfFile:path];
    NSZone *zone = [self zone];
    id propertyList;

    [self dealloc];
    if (data == nil)
        return nil;
    propertyList = _NSParseObjectFromASCIIPropertyListOrSerialization(data);
    [data release];
    if (propertyList == nil ||
        ![propertyList isKindOfClass:[NSArray class]])
        return nil;
    return [propertyList mutableCopyWithZone:zone];
}

@end

@implementation NSConcreteMutableArray

- (id)init
{
    return [self initWithCapacity:0];
}

- (id)initWithCapacity:(unsigned)capacity
{
    _items = nil;
    if (capacity > 0x07ffffff) {
        [self dealloc];
        [NSException raise:NSInvalidArgumentException
                    format:@"Array capacity %u is too large", capacity];
        return nil;
    }
    _size = capacity < 4 ? 4 : capacity;
    return self;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count
{
    unsigned index;

    if (count > 0x07ffffff) {
        _items = nil;
        [self dealloc];
        NSArrayRaiseSizeException(self, _cmd, count, "count");
        return nil;
    }
    self = [self initWithCapacity:count];
    NSConcreteMutableArrayEnsureCapacity(self, count);
    for (index = 0; index < count; index++) {
        _items[index] = [objects[index] retain];
        if (_items[index] == nil) {
            _info = index | (_info & 0xf8000000);
            [self dealloc];
            NSArrayRaiseInsertNilException(self, _cmd);
            return nil;
        }
    }
    _info = count | (_info & 0xf8000000);
    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    unsigned count;
    unsigned index;
    SEL decodeSelector = @selector(decodeValueOfObjCType:at:);
    void (*decodeObject)(id, SEL, const char *, id *);

    [coder decodeValueOfObjCType:"i" at:&count];
    if (count > 0x07ffffff) {
        _items = nil;
        [self dealloc];
        NSArrayRaiseSizeException(self, _cmd, count, "count");
        return nil;
    }
    self = [self initWithCapacity:count];
    NSConcreteMutableArrayEnsureCapacity(self, count);
    decodeObject = (void (*)(id, SEL, const char *, id *))
        _NSIMPForObjectAndSelector(coder, decodeSelector);
    for (index = 0; index < count; index++) {
        decodeObject(coder, decodeSelector, "@", &_items[index]);
        if (_items[index] == nil) {
            _info = (_info & 0xf8000000) | index;
            [self dealloc];
            NSArrayRaiseInsertNilException(self, _cmd);
            return nil;
        }
    }
    _info = (_info & 0xf8000000) | count;
    return self;
}

- (void)dealloc
{
    unsigned count = _info & 0x07ffffff;

    while (count != 0)
        [_items[--count] release];
    if (_items != nil)
        NSZoneFree(NSZoneFromPointer(_items), _items);
    [super dealloc];
}

@end
