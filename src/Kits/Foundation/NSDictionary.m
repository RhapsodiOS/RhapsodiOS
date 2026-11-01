/*	NSDictionary.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSZone.h>

#include <stdarg.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <limits.h>
#include <mach/cthreads.h>
#endif

NSString * const NSDictionaryAddComponents = @"NSDictionaryAddComponents";
NSString * const NSDictionaryReplaceComponents = @"NSDictionaryReplaceComponents";
NSString * const NSDictionaryRemoveComponents = @"NSDictionaryRemoveComponents";
NSString * const NSDictionarySetComponents = @"NSDictionarySetComponents";
NSString * const NSDictionaryToggleComponents = @"NSDictionaryToggleComponents";

extern Class __NSDictionaryClass;
extern Class __NSConcreteDictionaryClass;
extern Class __NSConcreteMutableDictionaryClass;
extern Class __NSMutableDictionaryClass;

extern id _NSParseObjectFromASCIIPropertyListOrSerialization(NSData *data);
extern id _NSMethodExceptionProem(id object, SEL selector);
extern id _NSRequestConcreteObject(id object, const char *selectorName);
extern NSLock *_NSGlobalRetainLock;
extern void _NSIncrementInternalRefCount(id object, unsigned *refCount,
                                         int mask, id lock);
extern BOOL _NSDecrementInternalRefCountWasZero(id object,
                                                 unsigned *refCount,
                                                 int mask, id lock);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);

static id _NSDictionaryRaiseInsertNilKeyException(id object, SEL selector)
{
    id proem = _NSMethodExceptionProem(object, selector);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: attempt to insert nil key", proem];
    return nil;
}

static id _NSDictionaryRaiseInsertNilValueException(id object, SEL selector)
{
    id proem = _NSMethodExceptionProem(object, selector);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: attempt to insert nil value", proem];
    return nil;
}

static id _NSDictionaryRaiseRemoveNilKeyException(id object, SEL selector)
{
    id proem = _NSMethodExceptionProem(object, selector);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: attempt to remove nil key", proem];
    return nil;
}

#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSDictionaryRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSDictionaryLockConcreteRetainCount(void)
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
            : "r" (&__NSDictionaryRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSDictionaryUnlockConcreteRetainCount(BOOL locked)
{
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSDictionaryRetainLock = 0;
    }
}
#endif

static void NSDictionaryCheckSize(id object, SEL selector, unsigned count,
                                  const char *sizeName) {
    if (count > 0x07ffffffU) {
        id proem = _NSMethodExceptionProem(object, selector);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: absurd %s: %d", proem, sizeName, count];
    }
}

@interface NSString (NSDictionaryDescriptionPrivate)
- (NSString *)_stringRepresentation;
- (NSString *)quotedStringRepresentation;
@end
static NSMutableArray *NSDictionaryIndentStrings;

typedef struct {
    NSDictionary *dictionary;
    SEL comparator;
} NSDictionaryValueSortContext;

static int NSDictionaryCompareKeysByValue(id firstKey, id secondKey,
                                           void *context)
{
    NSDictionaryValueSortContext *sortContext = context;
    id firstValue = [sortContext->dictionary objectForKey:firstKey];
    id secondValue = [sortContext->dictionary objectForKey:secondKey];

    return (int)[firstValue performSelector:sortContext->comparator
                                 withObject:secondValue];
}

NSString *_NSIndentSpace(unsigned level)
{
    NSString *indent;

    if (NSDictionaryIndentStrings == nil) {
        NSDictionaryIndentStrings = [[NSMutableArray alloc]
            initWithObjects:@"    ", @"        ", nil];
    }
    if (level < [NSDictionaryIndentStrings count])
        return [NSDictionaryIndentStrings objectAtIndex:level];

    indent = [_NSIndentSpace(level - 1) stringByAppendingString:@"    "];
    [NSDictionaryIndentStrings addObject:indent];
    return indent;
}

static NSString *NSDictionaryDescriptionForObject(id object,
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

@interface NSDictionary (PrivatePropertyListDataReading)
- (id)_initWithData:(NSData *)data;
- (NSString *)_stringToWrite;
@end

typedef struct {
    unsigned hashAndState;
    id key;
    id value;
} NSSimpleDictionaryBucket;

typedef struct {
    unsigned countAndCapacity;
    unsigned mutations;
    BOOL (*keysEqual)(id, id);
    NSSimpleDictionaryBucket buckets[1];
} NSSimpleDictionary;

extern unsigned NSResetSimpleDictionary(
    NSSimpleDictionary *table,
    int (*releaseEntry)(void *, void *, void *), void *context);

static int NSDictionaryReleaseKeyAndValue(void *context, void *key,
                                          void *value)
{
    (void)context;
    [(id)key release];
    [(id)value release];
    return 0;
}

@interface NSConcreteDictionary : NSDictionary {
@public
    NSSimpleDictionary *_table;
    unsigned _retainCount;
}

- (id)initWithObjects:(id *)objects forKeys:(id *)keys count:(unsigned)count;
- (id)initWithDictionary:(NSDictionary *)dictionary copyItems:(BOOL)copyItems;

@end

NSConcreteDictionary *__NSEmptyDictionary;

@interface NSConcreteMutableDictionary : NSMutableDictionary {
@public
    NSSimpleDictionary *_table;
    unsigned _retainCount;
}

- (id)initWithCapacity:(unsigned)capacity;
- (id)initWithDictionary:(NSDictionary *)dictionary copyItems:(BOOL)copyItems;

@end

@interface NSIdEnumerator : NSEnumerator
- (id)initWithObjects:(id *)objects count:(unsigned)count target:(id)target
             reverse:(BOOL)reverse freeWhenDone:(BOOL)freeWhenDone;
@end

static const unsigned NSSimpleDictionaryCapacities[] = {
    3, 7, 11, 21, 43, 85, 171, 341, 683, 1365, 2731, 5461, 10923, 21845,
    43691, 87381, 174763, 349525, 699051, 1398101, 2796203, 5592405,
    11184811, 22369621, 44739243, 89478485, 178956971, 357913941
};

static BOOL NSDictionaryObjectsEqual(id first, id second)
{
    return [first isEqual:second];
}

static unsigned NSSimpleDictionaryCapacityIndex(unsigned capacity)
{
    unsigned index;

    for (index = 0; index < sizeof(NSSimpleDictionaryCapacities) /
                                sizeof(NSSimpleDictionaryCapacities[0]); index++) {
        if (NSSimpleDictionaryCapacities[index] >= capacity)
            return index;
    }

    return sizeof(NSSimpleDictionaryCapacities) /
           sizeof(NSSimpleDictionaryCapacities[0]) - 1;
}

static unsigned NSSimpleDictionaryCapacity(NSSimpleDictionary *table)
{
    return table->countAndCapacity & 0x07ffffff;
}

static unsigned NSSimpleDictionaryCapacityLevel(NSSimpleDictionary *table)
{
    return table->countAndCapacity >> 27;
}

static unsigned NSSimpleDictionaryBucketCount(NSSimpleDictionary *table)
{
    return 1U << (NSSimpleDictionaryCapacityLevel(table) + 2);
}

static NSSimpleDictionary *NSSimpleDictionaryCopy(NSSimpleDictionary *table,
                                                   NSZone *zone)
{
    unsigned bucketCount = NSSimpleDictionaryBucketCount(table);
    unsigned size = sizeof(unsigned) * 3 +
                    sizeof(NSSimpleDictionaryBucket) * bucketCount;
    NSSimpleDictionary *copy = NSZoneMalloc(zone, size);

    memmove(copy, table, size);
    copy->mutations = 0;
    return copy;
}

static NSConcreteMutableDictionary *NSSimpleDictionaryMutableCopy(
    NSSimpleDictionary *table, NSZone *zone)
{
    NSConcreteMutableDictionary *copy =
        (NSConcreteMutableDictionary *)NSAllocateObject(
            __NSConcreteMutableDictionaryClass, 0, zone);
    unsigned bucketCount;
    unsigned index;

    copy->_table = NSSimpleDictionaryCopy(table, zone);
    bucketCount = NSSimpleDictionaryBucketCount(copy->_table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket =
            &copy->_table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000) {
            bucket->key = [bucket->key copyWithZone:zone];
            bucket->value = [bucket->value retain];
        }
    }
    return copy;
}

static void NSSimpleDictionaryGetObjectsAndKeys(NSSimpleDictionary *table,
                                                 id *objects, id *keys)
{
    unsigned index;
    unsigned bucketCount;

    if (table == nil || NSSimpleDictionaryCapacity(table) == 0)
        return;
    bucketCount = NSSimpleDictionaryBucketCount(table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000) {
            *keys++ = bucket->key;
            *objects++ = bucket->value;
        }
    }
}

static void NSSimpleDictionaryGetObjects(NSSimpleDictionary *table,
                                         id *objects)
{
    unsigned index;
    unsigned bucketCount;

    if (table == nil || NSSimpleDictionaryCapacity(table) == 0)
        return;
    bucketCount = NSSimpleDictionaryBucketCount(table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000)
            *objects++ = bucket->value;
    }
}

static void NSSimpleDictionaryEncode(NSSimpleDictionary *table, id coder)
{
    int count = table == nil ? 0 : (int)NSSimpleDictionaryCapacity(table);
    unsigned index;
    unsigned bucketCount;

    [coder encodeValueOfObjCType:"i" at:&count];
    if (count == 0)
        return;
    bucketCount = NSSimpleDictionaryBucketCount(table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000) {
            [coder encodeBycopyObject:bucket->key];
            [coder encodeBycopyObject:bucket->value];
        }
    }
}

static NSArray *NSSimpleDictionaryAllKeysForObject(
    NSSimpleDictionary *table, id object)
{
    id stackKeys[128];
    id *keys = stackKeys;
    unsigned count = table == nil ? 0 : NSSimpleDictionaryCapacity(table);
    unsigned used = 0;
    unsigned index;
    unsigned bucketCount;
    NSArray *result;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        keys = NSZoneMalloc(NULL, count * sizeof(id));
    bucketCount = NSSimpleDictionaryBucketCount(table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000 &&
            (bucket->value == object || [bucket->value isEqual:object]))
            keys[used++] = bucket->key;
    }
    result = [[[NSArray allocWithZone:NULL] initWithObjects:keys
                                                    count:used] autorelease];
    if (keys != stackKeys)
        NSZoneFree(NULL, keys);
    return result;
}

static NSArray *NSSimpleDictionaryArray(NSSimpleDictionary *table,
                                        BOOL keys)
{
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned count = table == nil ? 0 : NSSimpleDictionaryCapacity(table);
    unsigned used = 0;
    unsigned index;
    unsigned bucketCount;
    NSArray *result;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    bucketCount = NSSimpleDictionaryBucketCount(table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000)
            objects[used++] = keys ? bucket->key : bucket->value;
    }
    result = [[[NSArray allocWithZone:NULL] initWithObjects:objects
                                                    count:used] autorelease];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return result;
}

static NSSimpleDictionary **NSSimpleDictionaryTablePointer(id object)
{
    Class objectClass = ((struct objc_object *)object)->isa;

    if (objectClass == __NSConcreteMutableDictionaryClass)
        return &((NSConcreteMutableDictionary *)object)->_table;
    return &((NSConcreteDictionary *)object)->_table;
}

static BOOL NSSimpleDictionaryInitializeFromConcreteDictionary(
    id destination, NSDictionary *dictionary, BOOL copyItems, id *result)
{
    Class sourceClass;
    NSSimpleDictionary *sourceTable;
    NSSimpleDictionary **destinationTable;
    NSZone *zone;
    unsigned bucketCount;
    unsigned index;

    if (dictionary == nil)
        return NO;
    sourceClass = ((struct objc_object *)dictionary)->isa;
    if (sourceClass != __NSConcreteMutableDictionaryClass &&
        sourceClass != __NSConcreteDictionaryClass)
        return NO;

    sourceTable = *NSSimpleDictionaryTablePointer(dictionary);
    if (sourceTable == nil || NSSimpleDictionaryCapacity(sourceTable) == 0) {
        *result = [destination initWithObjects:NULL forKeys:NULL count:0];
        return YES;
    }

    zone = NSZoneFromPointer(destination);
    destinationTable = NSSimpleDictionaryTablePointer(destination);
    *destinationTable = NSSimpleDictionaryCopy(sourceTable, zone);
    bucketCount = NSSimpleDictionaryBucketCount(*destinationTable);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket =
            &(*destinationTable)->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000) {
            bucket->key = [bucket->key copyWithZone:zone];
            bucket->value = copyItems
                ? [bucket->value copyWithZone:zone] : [bucket->value retain];
        }
    }
    *result = destination;
    return YES;
}

static BOOL NSSimpleDictionaryIsEqualToDictionary(
    NSSimpleDictionary *table, NSDictionary *otherDictionary)
{
    unsigned count = table == nil ? 0 : NSSimpleDictionaryCapacity(table);
    unsigned index;
    unsigned bucketCount;

    if (otherDictionary == nil || count != [otherDictionary count])
        return NO;
    if (count == 0)
        return YES;
    bucketCount = NSSimpleDictionaryBucketCount(table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000) {
            id value = [otherDictionary objectForKey:bucket->key];

            if (value == nil ||
                (bucket->value != value && ![bucket->value isEqual:value]))
                return NO;
        }
    }
    return YES;
}

static NSSimpleDictionary *NSSimpleDictionaryCreate(unsigned capacity, NSZone *zone)
{
    unsigned level = NSSimpleDictionaryCapacityIndex(capacity);
    unsigned bucketCount = 1U << (level + 2);
    unsigned size = sizeof(unsigned) * 3 +
                    sizeof(NSSimpleDictionaryBucket) * bucketCount;
    NSSimpleDictionary *table = NSZoneMalloc(zone, size);

    memset(table, 0, size);
    table->countAndCapacity = level << 27;
    table->keysEqual = NSDictionaryObjectsEqual;
    return table;
}

static NSSimpleDictionaryBucket *NSSimpleDictionaryFind(
    NSSimpleDictionary *table, id key, unsigned hash, BOOL *found)
{
    unsigned count = NSSimpleDictionaryCapacity(table);
    unsigned level = NSSimpleDictionaryCapacityLevel(table);
    NSSimpleDictionaryBucket *buckets = table->buckets;
    unsigned index;

    *found = NO;
    if (level <= 1) {
        for (index = 0; index < count; index++) {
            if ((buckets[index].hashAndState & 0xc0000000) == 0x80000000 &&
                buckets[index].hashAndState == (hash | 0x80000000) &&
                table->keysEqual(key, buckets[index].key)) {
                *found = YES;
                return &buckets[index];
            }
        }
        return &buckets[count];
    }

    {
        unsigned mask = (1U << (level + 2)) - 1;
        unsigned start = hash & mask;
        unsigned firstDeleted = mask + 1;

        index = start;
        do {
            unsigned state = buckets[index].hashAndState & 0xc0000000;

            if (state == 0) {
                return &buckets[firstDeleted <= mask ? firstDeleted : index];
            }
            if (state == 0x40000000) {
                if (firstDeleted > mask)
                    firstDeleted = index;
            } else if (buckets[index].hashAndState == (hash | 0x80000000) &&
                       table->keysEqual(key, buckets[index].key)) {
                *found = YES;
                return &buckets[index];
            }

            index = (index + (((hash & 2) != 0) - 1) +
                     (mask & (hash >> 1))) & mask;
        } while (index != start);

        return firstDeleted <= mask ? &buckets[firstDeleted] : 0;
    }
}

static NSSimpleDictionary *NSSimpleDictionaryResize(
    NSSimpleDictionary *table, NSZone *zone)
{
    unsigned oldBucketCount = NSSimpleDictionaryBucketCount(table);
    unsigned nextLevel = NSSimpleDictionaryCapacityLevel(table) + 1;
    unsigned newBucketCount = 1U << (nextLevel + 2);
    unsigned size = sizeof(unsigned) * 3 +
                    sizeof(NSSimpleDictionaryBucket) * newBucketCount;
    NSSimpleDictionary *resized = NSZoneMalloc(zone, size);
    unsigned index;

    memset(resized, 0, size);
    resized->countAndCapacity = nextLevel << 27;
    resized->mutations = table->mutations;
    resized->keysEqual = table->keysEqual;
    for (index = oldBucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *oldBucket = &table->buckets[index - 1];
        NSSimpleDictionaryBucket *newBucket;
        BOOL found;

        if ((oldBucket->hashAndState & 0xc0000000) != 0x80000000)
            continue;
        newBucket = NSSimpleDictionaryFind(resized, oldBucket->key,
                                           oldBucket->hashAndState & 0x3fffffff,
                                           &found);
        (void)found;
        *newBucket = *oldBucket;
        resized->countAndCapacity++;
    }

    memset(table, 0, sizeof(unsigned) * 3 +
                    sizeof(NSSimpleDictionaryBucket) * oldBucketCount);
    NSZoneFree(zone, table);
    return resized;
}

static void NSSimpleDictionaryInsertPrepared(NSSimpleDictionary **tablePointer,
                                             id copiedKey, unsigned hash,
                                             id retainedValue, NSZone *zone)
{
    NSSimpleDictionary *table = *tablePointer;
    BOOL found;
    NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryFind(table, copiedKey,
                                                              hash, &found);

    if (found) {
        id oldKey = bucket->key;
        id oldValue = bucket->value;
        bucket->value = retainedValue;
        [oldKey release];
        [oldValue release];
        return;
    }

    bucket->hashAndState = hash | 0x80000000;
    bucket->key = copiedKey;
    bucket->value = retainedValue;
    table->countAndCapacity++;

    if (NSSimpleDictionaryCapacity(table) >
        NSSimpleDictionaryCapacities[NSSimpleDictionaryCapacityLevel(table)])
        *tablePointer = NSSimpleDictionaryResize(table, zone);
}

static void NSSimpleDictionaryInsert(NSSimpleDictionary **tablePointer,
                                     id key, id value, NSZone *zone)
{
    id copiedKey = [key copyWithZone:zone];
    id retainedValue = [value retain];
    unsigned hash = [copiedKey hash] & 0x3fffffff;

    NSSimpleDictionaryInsertPrepared(tablePointer, copiedKey, hash,
                                     retainedValue, zone);
}

static void NSSimpleDictionaryRemove(NSSimpleDictionary *table, id key)
{
    BOOL found;
    id removedKey;
    id removedValue;
    unsigned hash = [key hash] & 0x3fffffff;
    NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryFind(table, key, hash,
                                                              &found);

    if (!found)
        return;

    removedKey = bucket->key;
    removedValue = bucket->value;

    if (NSSimpleDictionaryCapacityLevel(table) <= 1) {
        unsigned count = NSSimpleDictionaryCapacity(table);
        if (bucket != &table->buckets[count - 1])
            *bucket = table->buckets[count - 1];
        table->buckets[count - 1].hashAndState = 0x40000000;
        table->buckets[count - 1].key = nil;
        table->buckets[count - 1].value = nil;
    } else {
        bucket->hashAndState = 0x40000000;
        bucket->key = nil;
        bucket->value = nil;
    }
    table->countAndCapacity--;

    [removedKey release];
    [removedValue release];
}

static id NSSimpleDictionaryObjectForKey(NSSimpleDictionary *table, id key)
{
    BOOL found;
    NSSimpleDictionaryBucket *bucket;

    if (key == nil || table == nil)
        return nil;
    bucket = NSSimpleDictionaryFind(table, key, [key hash] & 0x3fffffff,
                                    &found);
    return found ? bucket->value : nil;
}

static NSEnumerator *NSSimpleDictionaryKeyEnumerator(id target)
{
    unsigned count = [target count];
    id *keys = count == 0 ? nil : NSZoneMalloc(0, count * sizeof(id));

    if (count != 0)
        [target getKeys:keys];

    return [[[NSIdEnumerator allocWithZone:NSZoneFromPointer(target)]
        initWithObjects:keys count:count target:target reverse:NO
        freeWhenDone:YES] autorelease];
}

static NSArray *NSSimpleDictionaryArrayFromEnumerator(NSEnumerator *enumerator,
                                                       unsigned capacity)
{
    id stackObjects[128];
    id *objects = stackObjects;
    unsigned count = 0;
    NSArray *array;

    if (capacity == 0)
        return [NSArray array];
    if (capacity > 128)
        objects = NSZoneMalloc(0, capacity * sizeof(id));
    while ((objects[count] = [enumerator nextObject]) != nil)
        count++;
    array = [[NSArray alloc] initWithObjects:objects count:count];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return [array autorelease];
}

static void NSSimpleDictionaryRelease(NSSimpleDictionary *table, NSZone *zone)
{
    unsigned index, bucketCount;

    if (table == nil)
        return;
    bucketCount = NSSimpleDictionaryBucketCount(table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &table->buckets[index - 1];
        if ((bucket->hashAndState & 0xc0000000) == 0x80000000) {
            [bucket->key release];
            [bucket->value release];
        }
        bucket->hashAndState = 0;
    }
    memset(table, 0, sizeof(unsigned) * 3 +
                    sizeof(NSSimpleDictionaryBucket) * bucketCount);
    NSZoneFree(zone, table);
}

static id NSDictionaryFromObjectsAndKeys(id receiver, BOOL classMethod,
                                         SEL selector, id firstObject,
                                         va_list arguments)
{
    id stackObjects[128], stackKeys[128];
    id *objects = stackObjects, *keys = stackKeys;
    unsigned argumentCount = 1, count = 0, index;
    va_list countArguments, pairArguments;
    id result;

    if (firstObject != nil) {
        va_copy(countArguments, arguments);
        while (va_arg(countArguments, id) != nil)
            argumentCount++;
        va_end(countArguments);

        if (argumentCount & 1) {
            [NSException raise:NSInvalidArgumentException
                        format:@"%@: second object of each pair must be non-nil",
                        _NSMethodExceptionProem(receiver, selector)];
            return nil;
        }

        count = argumentCount >> 1;
        if (count > 128) {
            objects = NSZoneMalloc(0, count * sizeof(id));
            keys = NSZoneMalloc(0, count * sizeof(id));
        }

        objects[0] = firstObject;
        va_copy(pairArguments, arguments);
        keys[0] = va_arg(pairArguments, id);
        for (index = 1; index < count; index++) {
            objects[index] = va_arg(pairArguments, id);
            keys[index] = va_arg(pairArguments, id);
        }
        va_end(pairArguments);
    }

    if (classMethod)
        result = [[receiver allocWithZone:NULL]
            initWithObjects:objects forKeys:keys count:count];
    else
        result = [receiver initWithObjects:objects forKeys:keys count:count];
    if (objects != stackObjects) {
        NSZoneFree(0, objects);
        NSZoneFree(0, keys);
    }
    return classMethod ? [result autorelease] : result;
}

@implementation NSDictionary

+ (id)allocWithZone:(NSZone *)zone
{
    Class dictionaryClass = self;

    if (self == __NSDictionaryClass)
        dictionaryClass = __NSConcreteDictionaryClass;
    return NSAllocateObject(dictionaryClass, 0, zone);
}

- (Class)classForCoder {
    return __NSDictionaryClass;
}

- (unsigned)count {
    NSRequestConcreteImplementation(self, _cmd, __NSDictionaryClass);
    return 0;
}

- (NSEnumerator *)keyEnumerator {
    NSRequestConcreteImplementation(self, _cmd, __NSDictionaryClass);
    return nil;
}

- (id)objectForKey:(id)aKey {
    NSRequestConcreteImplementation(self, _cmd, __NSDictionaryClass);
    return nil;
}

- (id)copyWithZone:(NSZone *)zone {
    id copy = NSAllocateObject(__NSConcreteDictionaryClass, 0, zone);
    return [copy initWithDictionary:self copyItems:YES];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    id copy = NSAllocateObject(__NSConcreteMutableDictionaryClass, 0, zone);
    return [copy initWithDictionary:self copyItems:NO];
}

- (BOOL)containsKey:(id)key {
    return [self objectForKey:key] != nil;
}

- (BOOL)containsObject:(id)object {
    NSEnumerator *enumerator;
    id key;

    if (object == nil || [self count] == 0)
        return NO;
    enumerator = [self keyEnumerator];
    while ((key = [enumerator nextObject]) != nil) {
        if (object == key || [[self objectForKey:key] isEqual:object])
            return YES;
    }
    return NO;
}

- (unsigned)countForObject:(id)object {
    NSEnumerator *enumerator;
    id key;
    unsigned count = 0;

    if (object == nil || [self count] == 0)
        return 0;
    enumerator = [self keyEnumerator];
    while ((key = [enumerator nextObject]) != nil) {
        if (object == key || [[self objectForKey:key] isEqual:object])
            count++;
    }
    return count;
}

- (void)getObjects:(id *)objects
{
    NSEnumerator *keys;
    id key;

    if ([self count] == 0)
        return;
    keys = [self keyEnumerator];
    while ((key = [keys nextObject]) != nil)
        *objects++ = [self objectForKey:key];
}

- (void)getObjects:(id *)objects andKeys:(id *)keys
{
    NSEnumerator *enumerator;
    id key;

    if ([self count] == 0)
        return;
    enumerator = [self keyEnumerator];
    while ((key = [enumerator nextObject]) != nil) {
        *keys++ = key;
        *objects++ = [self objectForKey:key];
    }
}

- (void)getKeys:(id *)keys {
    NSEnumerator *enumerator;
    id key;

    if ([self count] == 0)
        return;
    enumerator = [self keyEnumerator];
    while ((key = [enumerator nextObject]) != nil)
        *keys++ = key;
}

- (NSArray *)allKeys {
    return NSSimpleDictionaryArrayFromEnumerator([self keyEnumerator],
                                                  [self count]);
}

- (NSArray *)allKeysForObject:(id)anObject {
    id stackKeys[128];
    id *keys = stackKeys;
    unsigned count = [self count], used = 0;
    NSEnumerator *enumerator;
    id key;
    NSArray *array;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        keys = NSZoneMalloc(0, count * sizeof(id));
    enumerator = [self keyEnumerator];
    while ((key = [enumerator nextObject]) != nil) {
        id value = [self objectForKey:key];

        if (anObject == value || [anObject isEqual:value])
            keys[used++] = key;
    }
    array = [[NSArray alloc] initWithObjects:keys count:used];
    if (keys != stackKeys)
        NSZoneFree(0, keys);
    return [array autorelease];
}

- (NSArray *)allValues {
    return NSSimpleDictionaryArrayFromEnumerator([self objectEnumerator],
                                                  [self count]);
}

- (NSDictionary *)invertedDictionary {
    NSArray *values = [self allValues];
    NSArray *keys = [self allKeys];

    return [NSDictionary dictionaryWithObjects:keys forKeys:values];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    int count = (int)[self count];

    [coder encodeValueOfObjCType:"i" at:&count];
    if (count != 0) {
        NSEnumerator *enumerator = [self keyEnumerator];
        id key;

        while ((key = [enumerator nextObject]) != nil) {
            [coder encodeBycopyObject:key];
            [coder encodeBycopyObject:[self objectForKey:key]];
        }
    }
}

- (id)initWithCoder:(NSCoder *)coder {
    id stackKeys[128];
    id stackObjects[128];
    id *keys = stackKeys;
    id *objects = stackObjects;
    unsigned count;
    unsigned index;
    id result;

    [coder decodeValueOfObjCType:"i" at:&count];
    if (count == 0)
        return [self initWithObjects:NULL forKeys:NULL count:0];
    NSDictionaryCheckSize(self, _cmd, count, "count");
    if (count > 128) {
        keys = NSZoneMalloc(NULL, count * sizeof(id));
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    }
    for (index = 0; index < count; index++) {
        [coder decodeValueOfObjCType:"@" at:&keys[index]];
        [coder decodeValueOfObjCType:"@" at:&objects[index]];
    }
    result = [self initWithObjects:objects forKeys:keys count:count];
    for (index = 0; index < count; index++) {
        [keys[index] release];
        [objects[index] release];
    }
    if (keys != stackKeys) {
        NSZoneFree(NULL, keys);
        NSZoneFree(NULL, objects);
    }
    return result;
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    if (![coder isByref])
        return self;
    return [NSDistantObject proxyWithLocal:self connection:[coder connection]];
}

- (NSDictionary *)dictionaryByCompositingWithDictionary:(NSDictionary *)dictionary
                                               operation:(NSString *)operation {
    enum {
        NSDictionaryAdd = 1,
        NSDictionaryReplace,
        NSDictionaryRemove,
        NSDictionarySet,
        NSDictionaryToggle
    } operationKind;
    NSMutableDictionary *result;
    NSEnumerator *enumerator;
    id key;

    if ([@"NSDictionaryAddComponents" isEqualToString:operation])
        operationKind = NSDictionaryAdd;
    else if ([@"NSDictionaryReplaceComponents" isEqualToString:operation])
        operationKind = NSDictionaryReplace;
    else if ([@"NSDictionaryRemoveComponents" isEqualToString:operation])
        operationKind = NSDictionaryRemove;
    else if ([@"NSDictionarySetComponents" isEqualToString:operation])
        operationKind = NSDictionarySet;
    else if ([@"NSDictionaryToggleComponents" isEqualToString:operation])
        operationKind = NSDictionaryToggle;
    else {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: unknown operation '%@'", proem, operation];
        return nil;
    }

    result = [[NSMutableDictionary allocWithZone:NULL]
        initWithDictionary:self];
    enumerator = [dictionary keyEnumerator];
    while ((key = [enumerator nextObject]) != nil) {
        switch (operationKind) {
        case NSDictionaryAdd:
            if ([self objectForKey:key] == nil)
                [result setObject:[dictionary objectForKey:key] forKey:key];
            break;
        case NSDictionaryReplace:
            if ([self objectForKey:key] != nil)
                [result setObject:[dictionary objectForKey:key] forKey:key];
            break;
        case NSDictionaryRemove:
            [result removeObjectForKey:key];
            break;
        case NSDictionarySet:
            [result setObject:[dictionary objectForKey:key] forKey:key];
            break;
        case NSDictionaryToggle:
            if ([self objectForKey:key] != nil)
                [result removeObjectForKey:key];
            else
                [result setObject:[dictionary objectForKey:key] forKey:key];
            break;
        }
    }
    {
        NSDictionary *composite = [NSDictionary dictionaryWithDictionary:result];
        [result release];
        return composite;
    }
}

- (NSString *)description {
    return [self descriptionWithLocale:nil indent:0];
}

- (NSString *)descriptionInStringsFileFormat {
    NSMutableString *result = [[[NSMutableString alloc] init] autorelease];
    NSEnumerator *keys = [self keyEnumerator];
    id key;

    while ((key = [keys nextObject]) != nil) {
        id value = [self objectForKey:key];
        NSString *valueDescription = [value isKindOfClass:[NSString class]]
            ? [value quotedStringRepresentation] : [value description];
        NSString *keyDescription = [key quotedStringRepresentation];

        [result replaceCharactersInRange:NSMakeRange([result length], 0)
                              withString:keyDescription];
        [result replaceCharactersInRange:NSMakeRange([result length], 0)
                              withString:@" = "];
        [result replaceCharactersInRange:NSMakeRange([result length], 0)
                              withString:valueDescription];
        [result replaceCharactersInRange:NSMakeRange([result length], 0)
                              withString:@";\n"];
    }
    return result;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    return [self descriptionWithLocale:locale indent:0];
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(unsigned)level {
    NSArray *keys = [self allKeys];
    unsigned keyCount = [keys count];
    unsigned index;
    BOOL canSort = YES;
    NSMutableString *result = [[NSMutableString alloc] init];
    NSMutableString *compact = [[NSMutableString alloc] initWithCapacity:79];

    for (index = 0; index < keyCount; index++) {
        if (![[keys objectAtIndex:index] respondsToSelector:@selector(compare:)]) {
            canSort = NO;
            break;
        }
    }
    if (canSort)
        keys = [keys sortedArrayUsingSelector:@selector(compare:)];

    [result appendString:@"{"];
    [result appendString:@"\n"];
    [compact appendString:@"{"];

    for (index = 0; index < keyCount; index++) {
        id key = [keys objectAtIndex:index];
        id value = [self objectForKey:key];
        NSString *keyDescription = NSDictionaryDescriptionForObject(
            key, locale, level);
        NSString *valueDescription = NSDictionaryDescriptionForObject(
            value, locale, level);

        if ([compact length] + [keyDescription length]
                + [valueDescription length] > 0x4f) {
            [compact release];
            compact = nil;
        }

        [result appendString:_NSIndentSpace(level + 1)];
        [result appendString:keyDescription];
        [result appendString:@" = "];
        [result appendString:valueDescription];
        [result appendString:@"; "];
        [result appendString:@"\n"];

        [compact appendString:keyDescription];
        [compact appendString:@" = "];
        [compact appendString:valueDescription];
        [compact appendString:@"; "];
    }

    [result appendString:_NSIndentSpace(level)];
    [result appendString:@"}"];
    [compact appendString:@"}"];

    if (compact != nil && [compact length] <= 0x4f) {
        [result release];
        return [compact autorelease];
    }
    [compact release];
    return [result autorelease];
}

- (BOOL)isEqualToDictionary:(NSDictionary *)otherDictionary {
    NSEnumerator *keys;
    id key, otherValue, value;

    if (otherDictionary == self)
        return YES;
    if (otherDictionary == nil || [self count] != [otherDictionary count])
        return NO;

    keys = [self keyEnumerator];
    while ((key = [keys nextObject]) != nil) {
        if ((otherValue = [otherDictionary objectForKey:key]) == nil ||
            ((value = [self objectForKey:key]) != otherValue &&
             !NSDictionaryObjectsEqual(value, otherValue)))
            return NO;
    }
    return YES;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (object == nil || ![object isKindOfClass:__NSDictionaryClass])
        return NO;
    return [self isEqualToDictionary:object];
}

- (unsigned)hash
{
    return [self count];
}

- (NSEnumerator *)objectEnumerator {
    unsigned count = [self count];
    id *objects = count == 0 ? nil : NSZoneMalloc(0, count * sizeof(id));

    if (count != 0)
        [self getObjects:objects];
    return [[[NSIdEnumerator allocWithZone:NSZoneFromPointer(self)]
        initWithObjects:objects count:count target:self reverse:NO
        freeWhenDone:YES] autorelease];
}

- (NSArray *)objectsForKeys:(NSArray *)keys notFoundMarker:(id)marker {
    unsigned count = [keys count], index;
    id stackObjects[128];
    id stackKeys[128];
    id *objects = stackObjects;
    id *keyBuffer = stackKeys;
    NSArray *array;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        objects = NSZoneMalloc(0, count * sizeof(id));

    if ([keys isProxy]) {
        for (index = 0; index < count; index++) {
            id object = [self objectForKey:[keys objectAtIndex:index]];
            objects[index] = object == nil ? marker : object;
        }
    } else {
        if (count > 128)
            keyBuffer = NSZoneMalloc(0, count * sizeof(id));
        [keys getObjects:keyBuffer range:NSMakeRange(0, count)];
        for (index = 0; index < count; index++) {
            id object = [self objectForKey:keyBuffer[index]];
            objects[index] = object == nil ? marker : object;
        }
        if (keyBuffer != stackKeys)
            NSZoneFree(0, keyBuffer);
    }

    array = [[NSArray allocWithZone:NULL] initWithObjects:objects count:count];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return [array autorelease];
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    return [[self _stringToWrite] writeToFile:path
                                   atomically:useAuxiliaryFile];
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically {
#if !defined(__ppc__) && !defined(__POWERPC__)
    if (![url isFileURL])
        return NO;
#endif
    return [[self _stringToWrite] writeToURL:url atomically:atomically];
}

- (NSString *)_stringToWrite {
    NSString *string = [self descriptionWithLocale:nil indent:0];
    unsigned length = [string length];

    if ([string characterAtIndex:length - 1] != '\n') {
        if ([string isKindOfClass:[NSMutableString class]]) {
            [(NSMutableString *)string
                replaceCharactersInRange:NSMakeRange(length, 0)
                              withString:@"\n"];
        } else {
            string = [string stringByAppendingString:@"\n"];
        }
    }
    return string;
}

- (NSArray *)keysSortedByValueUsingSelector:(SEL)comparator {
    NSDictionaryValueSortContext context;

    context.dictionary = self;
    context.comparator = comparator;
    return [[self allKeys] sortedArrayUsingFunction:
        NSDictionaryCompareKeysByValue context:&context];
}

+ (id)dictionary {
    if (self == __NSDictionaryClass) {
        if (__NSEmptyDictionary == nil)
            __NSEmptyDictionary = NSAllocateObject(
                __NSConcreteDictionaryClass, 0, NULL);
        return __NSEmptyDictionary;
    }
    return [[[self allocWithZone:NULL] init] autorelease];
}

+ (id)dictionaryWithContentsOfFile:(NSString *)path {
    return [[[self allocWithZone:NULL] initWithContentsOfFile:path] autorelease];
}

+ (id)dictionaryWithContentsOfURL:(NSURL *)url {
    return [[[self allocWithZone:NULL] initWithContentsOfURL:url] autorelease];
}

+ (id)dictionaryWithObjects:(NSArray *)objects forKeys:(NSArray *)keys {
    return [[[self allocWithZone:NULL] initWithObjects:objects forKeys:keys]
        autorelease];
}

+ (id)dictionaryWithObjects:(id *)objects forKeys:(id *)keys count:(unsigned)count {
    return [[[self allocWithZone:NULL] initWithObjects:objects forKeys:keys
        count:count] autorelease];
}

+ (id)dictionaryWithObjectsAndKeys:(id)firstObject, ... {
    va_list arguments;
    id dictionary;

    va_start(arguments, firstObject);
    dictionary = NSDictionaryFromObjectsAndKeys(self, YES, _cmd, firstObject,
                                                arguments);
    va_end(arguments);
    return dictionary;
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
    propertyList = _NSParseObjectFromASCIIPropertyListOrSerialization(data);
    if (propertyList == nil ||
        ![propertyList isKindOfClass:__NSDictionaryClass])
        return nil;
    return [propertyList copyWithZone:zone];
}

- (id)initWithObjects:(NSArray *)objects forKeys:(NSArray *)keys {
    unsigned count = [objects count];
    unsigned keyCount;
    id objectBuffer[128], keyBuffer[128];
    id *objectList = objectBuffer, *keyList = keyBuffer;
    unsigned index;
    id result;
    id proem;

    if (count != [keys count]) {
#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        keyCount = [keys count];
#else
        keyCount = [keys count];
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: number of objects (%d) not equal to number of keys (%d)",
                    proem, count, keyCount];
        return nil;
    }
    if (count == 0)
        return [self initWithObjects:NULL forKeys:NULL count:0];
    if (count > 128) {
        objectList = NSZoneMalloc(0, count * sizeof(id));
        keyList = NSZoneMalloc(0, count * sizeof(id));
    }

    if ([objects isProxy]) {
        for (index = 0; index < count; index++)
            objectList[index] = [objects objectAtIndex:index];
    } else {
        [objects getObjects:objectList range:NSMakeRange(0, count)];
    }
    if ([keys isProxy]) {
        for (index = 0; index < count; index++)
            keyList[index] = [keys objectAtIndex:index];
    } else {
        [keys getObjects:keyList range:NSMakeRange(0, count)];
    }
    result = [self initWithObjects:objectList forKeys:keyList count:count];
    if (objectList != objectBuffer) {
        NSZoneFree(0, objectList);
        NSZoneFree(0, keyList);
    }
    return result;
}

- (id)initWithObjects:(id *)objects forKeys:(id *)keys count:(unsigned)count {
    (void)objects;
    (void)keys;
    (void)count;
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return self;
}

- (id)initWithObjectsAndKeys:(id)firstObject, ... {
    va_list arguments;
    id dictionary;

    va_start(arguments, firstObject);
    dictionary = NSDictionaryFromObjectsAndKeys(self, NO, _cmd, firstObject,
                                                arguments);
    va_end(arguments);
    return dictionary;
}

- (id)initWithDictionary:(NSDictionary *)otherDictionary {
    return [self initWithDictionary:otherDictionary copyItems:NO];
}

+ (id)dictionaryWithDictionary:(NSDictionary *)dict {
    return [[[self allocWithZone:NULL] initWithDictionary:dict] autorelease];
}

+ (id)dictionaryWithObject:(id)object forKey:(id)key {
    id objects[1], keys[1];

    objects[0] = object;
    keys[0] = key;
    return [[[self allocWithZone:NULL] initWithObjects:objects forKeys:keys
        count:1] autorelease];
}

- (id)initWithDictionary:(NSDictionary *)otherDictionary copyItems:(BOOL)aBool {
    id stackKeys[128];
    id stackObjects[128];
    id *keys = stackKeys;
    id *objects = stackObjects;
    NSEnumerator *enumerator;
    NSZone *zone;
    unsigned count = [otherDictionary count];
    unsigned index;
    id key;
    id result;

    if (count == 0)
        return [self initWithObjects:nil forKeys:nil count:0];

    if (count > 128) {
        keys = NSZoneMalloc(NULL, count * sizeof(id));
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    }

    zone = aBool ? NSZoneFromPointer(self) : NULL;

    enumerator = [otherDictionary keyEnumerator];
    index = 0;
    while ((key = [enumerator nextObject]) != nil) {
        id value = [otherDictionary objectForKey:key];

        keys[index] = key;
        objects[index] = aBool ? [value copyWithZone:zone] : value;
        index++;
    }

    result = [self initWithObjects:objects forKeys:keys count:count];
    if (aBool) {
        for (index = 0; index < count; index++)
            [objects[index] release];
    }
    if (objects != stackObjects) {
        NSZoneFree(NULL, objects);
        NSZoneFree(NULL, keys);
    }
    return result;
}

@end

@implementation NSConcreteDictionary

- (id)retain
{
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSDictionaryLockConcreteRetainCount();

    if (_retainCount != UINT_MAX)
        ++_retainCount;
    NSDictionaryUnlockConcreteRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
#else
    _NSIncrementInternalRefCount(self, &_retainCount, -1,
                                 _NSGlobalRetainLock);
#endif
    return self;
}

- (void)release
{
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSDictionaryLockConcreteRetainCount();
    if (_retainCount != 0) {
        if (_retainCount != UINT_MAX)
            --_retainCount;
    } else {
        shouldDeallocate = YES;
    }
    NSDictionaryUnlockConcreteRetainCount(locked);
    if (shouldDeallocate)
        [self dealloc];
#else
    if (_NSDecrementInternalRefCountWasZero(self, &_retainCount, -1,
                                            _NSGlobalRetainLock))
        [self dealloc];
#endif
}

- (unsigned)retainCount
{
#if defined(__ppc__) || defined(__POWERPC__)
    return _retainCount + 1;
#else
    return _NSInternalRefCount(self, _retainCount, -1);
#endif
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self retain];
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    if (_table == nil)
        return [[NSMutableDictionary allocWithZone:NULL] initWithCapacity:0];
    return NSSimpleDictionaryMutableCopy(_table, zone);
}

- (id)init
{
    return [self initWithObjects:nil forKeys:nil count:0];
}

- (unsigned)count
{
    return _table == nil ? 0 : NSSimpleDictionaryCapacity(_table);
}

- (id)objectForKey:(id)key
{
    return NSSimpleDictionaryObjectForKey(_table, key);
}

- (NSEnumerator *)keyEnumerator
{
    return NSSimpleDictionaryKeyEnumerator(self);
}

- (void)getKeys:(id *)keys
{
    unsigned index;
    unsigned bucketCount;

    if (_table == nil || NSSimpleDictionaryCapacity(_table) == 0)
        return;
    bucketCount = NSSimpleDictionaryBucketCount(_table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &_table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000)
            *keys++ = bucket->key;
    }
}

- (void)getObjects:(id *)objects andKeys:(id *)keys
{
    NSSimpleDictionaryGetObjectsAndKeys(_table, objects, keys);
}

- (void)getObjects:(id *)objects
{
    NSSimpleDictionaryGetObjects(_table, objects);
}

- (NSArray *)allKeysForObject:(id)object
{
    return NSSimpleDictionaryAllKeysForObject(_table, object);
}

- (NSArray *)allKeys
{
    return NSSimpleDictionaryArray(_table, YES);
}

- (NSArray *)allValues
{
    return NSSimpleDictionaryArray(_table, NO);
}

- (BOOL)isEqualToDictionary:(NSDictionary *)otherDictionary
{
    return NSSimpleDictionaryIsEqualToDictionary(_table, otherDictionary);
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSSimpleDictionaryEncode(_table, coder);
}

- (id)initWithObjects:(id *)objects forKeys:(id *)keys count:(unsigned)count
{
    unsigned index;

    if (count != 0)
        NSDictionaryCheckSize(self, _cmd, count, "count");
    if (count == 0) {
        if (__NSEmptyDictionary == nil)
            __NSEmptyDictionary = NSAllocateObject(
                __NSConcreteDictionaryClass, 0, NULL);
        [self dealloc];
        return [__NSEmptyDictionary retain];
    }

    _table = NSSimpleDictionaryCreate(count, NSZoneFromPointer(self));
    for (index = 0; index < count; index++) {
        if (keys[index] == nil) {
            _NSDictionaryRaiseInsertNilKeyException(self, _cmd);
        }
        if (objects[index] == nil) {
            _NSDictionaryRaiseInsertNilValueException(self, _cmd);
        }
        NSSimpleDictionaryInsert(&_table, keys[index], objects[index],
                                 NSZoneFromPointer(self));
    }
    return self;
}

- (id)initWithDictionary:(NSDictionary *)dictionary copyItems:(BOOL)copyItems
{
    id result;

    if (NSSimpleDictionaryInitializeFromConcreteDictionary(
            self, dictionary, copyItems, &result))
        return result;
    return [super initWithDictionary:dictionary copyItems:copyItems];
}

- (void)dealloc
{
    NSSimpleDictionaryRelease(_table, NSZoneFromPointer(self));
    _table = nil;
    [super dealloc];
}

@end
@implementation NSMutableDictionary

+ (id)allocWithZone:(NSZone *)zone
{
    Class dictionaryClass = self;

    if (self == __NSMutableDictionaryClass)
        dictionaryClass = __NSConcreteMutableDictionaryClass;
    return NSAllocateObject(dictionaryClass, 0, zone);
}

- (Class)classForCoder {
    return __NSMutableDictionaryClass;
}

- (id)initWithContentsOfFile:(NSString *)path {
    NSData *data = [[NSData allocWithZone:NULL] initWithContentsOfFile:path];
    NSZone *zone = NSZoneFromPointer(self);
    id propertyList;

    [self dealloc];
    if (data == nil)
        return nil;
    propertyList = _NSParseObjectFromASCIIPropertyListOrSerialization(data);
    [data release];
    if (propertyList == nil ||
        ![propertyList isKindOfClass:__NSDictionaryClass])
        return nil;
    return [propertyList mutableCopyWithZone:zone];
}

- (void)removeObjectForKey:(id)aKey {
    NSRequestConcreteImplementation(self, _cmd, __NSMutableDictionaryClass);
}

- (void)setObject:(id)anObject forKey:(id)aKey {
    NSRequestConcreteImplementation(self, _cmd, __NSMutableDictionaryClass);
}

- (void)addEntriesFromDictionary:(NSDictionary *)otherDictionary {
    NSEnumerator *keys = [otherDictionary keyEnumerator];
    id key;

    while ((key = [keys nextObject]) != nil)
        [self setObject:[otherDictionary objectForKey:key] forKey:key];
}

- (void)removeAllObjects {
    NSArray *keys = [self allKeys];
    [self removeObjectsForKeys:keys];
}

- (void)removeKeysForObject:(id)object {
    NSMutableArray *keys = [NSMutableArray array];
    NSEnumerator *enumerator = [self keyEnumerator];
    id key;

    while ((key = [enumerator nextObject]) != nil) {
        if (object == [self objectForKey:key])
            [keys addObject:key];
    }
    [self removeObjectsForKeys:keys];
}

- (void)removeObjectsForKeys:(NSArray *)keyArray {
    id stackKeys[128];
    id *keys = stackKeys;
    unsigned count = [keyArray count];
    unsigned index;

    if (count == 0)
        return;

    if ([keyArray isProxy]) {
        while (count > 0) {
            count--;
            [self removeObjectForKey:[keyArray objectAtIndex:count]];
        }
        return;
    }

    if (count > 128)
        keys = NSZoneMalloc(NULL, count * sizeof(id));
    [keyArray getObjects:keys range:NSMakeRange(0, count)];
    for (index = count; index > 0; index--)
        [self removeObjectForKey:keys[index - 1]];
    if (keys != stackKeys)
        NSZoneFree(NULL, keys);
}

- (void)invert {
    NSArray *keys = [self allKeys];
    NSArray *values = [self allValues];
    unsigned index;
    unsigned count;

    [self removeObjectsForKeys:keys];
    count = [keys count];
    for (index = 0; index < count; index++)
        [self setObject:[keys objectAtIndex:index]
                forKey:[values objectAtIndex:index]];
}

- (void)setDictionary:(NSDictionary *)otherDictionary {
    [self removeAllObjects];
    [self addEntriesFromDictionary:otherDictionary];
}

+ (id)dictionaryWithCapacity:(unsigned)numItems {
    return [[[self allocWithZone:NULL] initWithCapacity:numItems] autorelease];
}

- (id)initWithCapacity:(unsigned)numItems {
    (void)numItems;
    _NSRequestConcreteObject(self, (const char *)_cmd);
    return nil;
}

- (id)initWithObjects:(id *)objects forKeys:(id *)keys count:(unsigned)count
{
    unsigned index;

    NSDictionaryCheckSize(self, _cmd, count, "count");
    self = [self initWithCapacity:count];
    for (index = 0; index < count; index++)
        [self setObject:objects[index] forKey:keys[index]];
    return self;
}

@end

@implementation NSConcreteMutableDictionary

- (id)retain
{
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSDictionaryLockConcreteRetainCount();

    if (_retainCount != UINT_MAX)
        ++_retainCount;
    NSDictionaryUnlockConcreteRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
#else
    _NSIncrementInternalRefCount(self, &_retainCount, -1,
                                 _NSGlobalRetainLock);
#endif
    return self;
}

- (void)release
{
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSDictionaryLockConcreteRetainCount();
    if (_retainCount != 0) {
        if (_retainCount != UINT_MAX)
            --_retainCount;
    } else {
        shouldDeallocate = YES;
    }
    NSDictionaryUnlockConcreteRetainCount(locked);
    if (shouldDeallocate)
        [self dealloc];
#else
    if (_NSDecrementInternalRefCountWasZero(self, &_retainCount, -1,
                                            _NSGlobalRetainLock))
        [self dealloc];
#endif
}

- (unsigned)retainCount
{
#if defined(__ppc__) || defined(__POWERPC__)
    return _retainCount + 1;
#else
    return _NSInternalRefCount(self, _retainCount, -1);
#endif
}

- (id)init
{
    return [self initWithCapacity:0];
}

- (id)initWithCapacity:(unsigned)capacity
{
    NSDictionaryCheckSize(self, _cmd, capacity, "capacity");

    _table = NSSimpleDictionaryCreate(capacity, NSZoneFromPointer(self));
    return self;
}

- (id)initWithObjects:(id *)objects forKeys:(id *)keys count:(unsigned)count
{
    unsigned index;

    NSDictionaryCheckSize(self, _cmd, count, "count");
    self = [self initWithCapacity:count];
    if (self == nil)
        return nil;

    for (index = 0; index < count; index++) {
        if (keys[index] == nil) {
            _NSDictionaryRaiseInsertNilKeyException(self, _cmd);
        }
        if (objects[index] == nil) {
            _NSDictionaryRaiseInsertNilValueException(self, _cmd);
        }
        NSSimpleDictionaryInsert(&_table, keys[index], objects[index],
                                 NSZoneFromPointer(self));
    }
    return self;
}

- (id)initWithDictionary:(NSDictionary *)dictionary copyItems:(BOOL)copyItems
{
    id result;

    if (NSSimpleDictionaryInitializeFromConcreteDictionary(
            self, dictionary, copyItems, &result))
        return result;
    return [super initWithDictionary:dictionary copyItems:copyItems];
}

- (unsigned)count
{
    return NSSimpleDictionaryCapacity(_table);
}

- (id)objectForKey:(id)key
{
    BOOL found;
    NSSimpleDictionaryBucket *bucket;

    if (key == nil)
        return nil;
    bucket = NSSimpleDictionaryFind(_table, key, [key hash] & 0x3fffffff,
                                    &found);
    return found ? bucket->value : nil;
}

- (NSEnumerator *)keyEnumerator
{
    return NSSimpleDictionaryKeyEnumerator(self);
}

- (void)getKeys:(id *)keys
{
    unsigned index;
    unsigned bucketCount;

    if (_table == nil || NSSimpleDictionaryCapacity(_table) == 0)
        return;
    bucketCount = NSSimpleDictionaryBucketCount(_table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &_table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000)
            *keys++ = bucket->key;
    }
}

- (void)getObjects:(id *)objects andKeys:(id *)keys
{
    NSSimpleDictionaryGetObjectsAndKeys(_table, objects, keys);
}

- (void)getObjects:(id *)objects
{
    NSSimpleDictionaryGetObjects(_table, objects);
}

- (NSArray *)allKeysForObject:(id)object
{
    return NSSimpleDictionaryAllKeysForObject(_table, object);
}

- (NSArray *)allKeys
{
    return NSSimpleDictionaryArray(_table, YES);
}

- (NSArray *)allValues
{
    return NSSimpleDictionaryArray(_table, NO);
}

- (BOOL)isEqualToDictionary:(NSDictionary *)otherDictionary
{
    return NSSimpleDictionaryIsEqualToDictionary(_table, otherDictionary);
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSSimpleDictionaryEncode(_table, coder);
}

- (void)addEntriesFromDictionary:(NSDictionary *)otherDictionary
{
    Class otherClass;
    NSSimpleDictionary *sourceTable;
    unsigned bucketCount;
    unsigned index;
    NSZone *zone;

    if (otherDictionary == nil)
        return;
    otherClass = ((struct objc_object *)otherDictionary)->isa;
    if (otherClass != __NSConcreteMutableDictionaryClass &&
        otherClass != __NSConcreteDictionaryClass) {
        [super addEntriesFromDictionary:otherDictionary];
        return;
    }

    sourceTable = otherClass == __NSConcreteMutableDictionaryClass
        ? ((NSConcreteMutableDictionary *)otherDictionary)->_table
        : ((NSConcreteDictionary *)otherDictionary)->_table;
    if (sourceTable == nil || NSSimpleDictionaryCapacity(sourceTable) == 0)
        return;

    zone = NSZoneFromPointer(self);
    bucketCount = NSSimpleDictionaryBucketCount(sourceTable);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket = &sourceTable->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000)
            NSSimpleDictionaryInsert(&_table, bucket->key, bucket->value,
                                     zone);
    }
}

- (void)setObject:(id)object forKey:(id)key
{
    if (key == nil) {
        _NSDictionaryRaiseInsertNilKeyException(self, _cmd);
    }
    if (object == nil) {
        _NSDictionaryRaiseInsertNilValueException(self, _cmd);
    }
    if (_table == nil)
        _table = NSSimpleDictionaryCreate(0, NSZoneFromPointer(self));
    NSSimpleDictionaryInsert(&_table, key, object, NSZoneFromPointer(self));
}

- (void)removeObjectForKey:(id)key
{
    if (key == nil) {
        _NSDictionaryRaiseRemoveNilKeyException(self, _cmd);
    }
    if (_table != nil && NSSimpleDictionaryCapacity(_table) != 0)
        NSSimpleDictionaryRemove(_table, key);
}

- (void)removeAllObjects
{
    if (_table == nil || NSSimpleDictionaryCapacity(_table) == 0)
        return;
    NSResetSimpleDictionary(_table, NSDictionaryReleaseKeyAndValue, NULL);
}

- (id)copyWithZone:(NSZone *)zone
{
    NSConcreteDictionary *copy;
    unsigned bucketCount;
    unsigned index;

    if (NSSimpleDictionaryCapacity(_table) == 0)
        return [[NSDictionary allocWithZone:NULL] init];

    copy = (NSConcreteDictionary *)NSAllocateObject(
        __NSConcreteDictionaryClass, 0, zone);
    copy->_table = NSSimpleDictionaryCopy(_table, zone);
    bucketCount = NSSimpleDictionaryBucketCount(copy->_table);
    for (index = bucketCount; index > 0; index--) {
        NSSimpleDictionaryBucket *bucket =
            &copy->_table->buckets[index - 1];

        if ((bucket->hashAndState & 0xc0000000) == 0x80000000) {
            bucket->key = [bucket->key copyWithZone:zone];
            bucket->value = [bucket->value copyWithZone:zone];
        }
    }
    return copy;
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    return NSSimpleDictionaryMutableCopy(_table, zone);
}

- (void)dealloc
{
    if (_table != nil) {
        [self removeAllObjects];
        memset(_table, 0, sizeof(unsigned) * 3 +
                          sizeof(NSSimpleDictionaryBucket) *
                          NSSimpleDictionaryBucketCount(_table));
        NSZoneFree(NSZoneFromPointer(self), _table);
        _table = nil;
    }
    [super dealloc];
}

@end
