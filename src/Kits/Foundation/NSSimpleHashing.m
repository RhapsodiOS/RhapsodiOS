/*	NSSimpleHashing.m
	Simple dictionary and set primitives
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSZone.h>

#include <limits.h>
#include <string.h>

#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>

volatile unsigned int __NSSimpleHashingRetainLock;
extern int _NSIsMultiThreaded;

static void NSSimpleHashingRetainLockAcquire(void)
{
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
            : "r" (&__NSSimpleHashingRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return;
        cthread_yield();
    }
}

static void NSSimpleHashingRetainLockRelease(void)
{
    __asm__ volatile("sync" ::: "memory");
    __NSSimpleHashingRetainLock = 0;
}

static BOOL NSSimpleHashingLock(void)
{
    if (!_NSIsMultiThreaded)
        return NO;
    NSSimpleHashingRetainLockAcquire();
    return YES;
}

static void NSSimpleHashingUnlock(BOOL locked)
{
    if (locked)
        NSSimpleHashingRetainLockRelease();
}
#else
extern NSLock *_NSSimpleHashingLock;

static BOOL NSSimpleHashingLock(void)
{
    if (_NSSimpleHashingLock == nil)
        return NO;
    [_NSSimpleHashingLock lock];
    return YES;
}

static void NSSimpleHashingUnlock(BOOL locked)
{
    if (locked)
        [_NSSimpleHashingLock unlock];
}
#endif

typedef BOOL (*NSSimpleHashingEqual)(void *, const void *, const void *);

typedef struct {
    unsigned hashAndState;
    void *key;
    void *value;
} NSSimpleDictionaryBucket;

typedef struct {
    unsigned countAndCapacity;
    unsigned retainCount;
    NSSimpleHashingEqual keysEqual;
    NSSimpleDictionaryBucket buckets[1];
} NSSimpleDictionary;

typedef struct {
    unsigned hashAndState;
    void *value;
} NSSimpleSetBucket;

typedef struct {
    unsigned countAndCapacity;
    unsigned retainCount;
    NSSimpleHashingEqual valuesEqual;
    NSSimpleSetBucket buckets[1];
} NSSimpleSet;

static const unsigned NSSimpleHashingCapacities[] = {
    3, 7, 11, 21, 43, 85, 171, 341, 683, 1365, 2731, 5461, 10923, 21845,
    43691, 87381, 174763, 349525, 699051, 1398101, 2796203, 5592405,
    11184811, 22369621, 44739243, 89478485, 178956971, 357913941
};

static const unsigned NSSimpleHashingBucketCounts[] = {
    4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384,
    32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304,
    8388608, 16777216, 33554432, 67108864, 134217728, 268435456, 536870912
};

#define NSSIMPLE_COUNT_MASK 0x07ffffffU
#define NSSIMPLE_HASH_MASK  0x3fffffffU
#define NSSIMPLE_STATE_MASK 0xc0000000U
#define NSSIMPLE_OCCUPIED   0x80000000U
#define NSSIMPLE_DELETED    0x40000000U

static unsigned NSSimpleHashingLevel(unsigned capacity)
{
    unsigned level;

    for (level = 0; level < sizeof(NSSimpleHashingCapacities) /
                               sizeof(NSSimpleHashingCapacities[0]); level++) {
        if (NSSimpleHashingCapacities[level] >= capacity)
            return level;
    }
    return sizeof(NSSimpleHashingCapacities) /
           sizeof(NSSimpleHashingCapacities[0]) - 1;
}

static unsigned NSSimpleHashingCount(unsigned *countAndCapacity)
{
    return *countAndCapacity & NSSIMPLE_COUNT_MASK;
}

static unsigned NSSimpleHashingLevelFor(unsigned *countAndCapacity)
{
    return *countAndCapacity >> 27;
}

static unsigned NSSimpleDictionaryBuckets(NSSimpleDictionary *table)
{
    return NSSimpleHashingBucketCounts[NSSimpleHashingLevelFor(
        &table->countAndCapacity)];
}

static unsigned NSSimpleSetBuckets(NSSimpleSet *table)
{
    return NSSimpleHashingBucketCounts[NSSimpleHashingLevelFor(
        &table->countAndCapacity)];
}

static NSSimpleDictionaryBucket *NSSimpleDictionaryFindBuckets(
    NSSimpleDictionary *table, const void *key, unsigned hash, void *context,
    NSSimpleDictionaryBucket **match, NSSimpleDictionaryBucket **empty)
{
    unsigned level = NSSimpleHashingLevelFor(&table->countAndCapacity);
    unsigned count = NSSimpleHashingCount(&table->countAndCapacity);
    unsigned index;

    *match = NULL;
    *empty = NULL;
    if (level <= 1) {
#if defined(__ppc__) || defined(__POWERPC__)
        for (index = count; index != 0; index--) {
            NSSimpleDictionaryBucket *bucket = &table->buckets[index - 1];

            if (bucket->key == key) {
                *match = bucket;
                return bucket;
            }
        }
#else
        for (index = 0; index < count; index++) {
            NSSimpleDictionaryBucket *bucket = &table->buckets[index];

            if (bucket->key == key) {
                *match = bucket;
                return bucket;
            }
        }
#endif
        if (table->keysEqual != NULL) {
            for (index = 0; index < count; index++) {
                NSSimpleDictionaryBucket *bucket = &table->buckets[index];

                if ((bucket->hashAndState & NSSIMPLE_HASH_MASK) == hash &&
                    table->keysEqual(context, bucket->key, key)) {
                    *match = bucket;
                    return bucket;
                }
            }
        }
        *empty = &table->buckets[count];
        return *empty;
    }

    {
        unsigned mask = NSSimpleDictionaryBuckets(table) - 1;
        unsigned start = hash & mask;
        unsigned firstDeleted = mask + 1;

        index = start;
        do {
            NSSimpleDictionaryBucket *bucket = &table->buckets[index];
            unsigned state = bucket->hashAndState & NSSIMPLE_STATE_MASK;

            if (state == 0) {
                *empty = &table->buckets[firstDeleted <= mask
                    ? firstDeleted : index];
                return *empty;
            }
            if (state == NSSIMPLE_DELETED) {
                if (firstDeleted > mask)
                    firstDeleted = index;
            } else if (bucket->key == key ||
                       (table->keysEqual != NULL &&
                        (bucket->hashAndState & NSSIMPLE_HASH_MASK) == hash &&
                        table->keysEqual(context, bucket->key, key))) {
                *match = bucket;
                return bucket;
            }
            index = (index + ((hash & 2U) != 0 ? 0U : ~0U) +
                     (mask & (hash >> 1))) & mask;
        } while (index != start);
        if (firstDeleted <= mask)
            *empty = &table->buckets[firstDeleted];
    }
    return *empty;
}

static NSSimpleSetBucket *NSSimpleSetFindBuckets(
    NSSimpleSet *table, const void *value, unsigned hash, void *context,
    NSSimpleSetBucket **match, NSSimpleSetBucket **empty)
{
    unsigned level = NSSimpleHashingLevelFor(&table->countAndCapacity);
    unsigned count = NSSimpleHashingCount(&table->countAndCapacity);
    unsigned index;

    *match = NULL;
    *empty = NULL;
    if (level <= 1) {
#if defined(__ppc__) || defined(__POWERPC__)
        for (index = count; index != 0; index--) {
            NSSimpleSetBucket *bucket = &table->buckets[index - 1];

            if (bucket->value == value) {
                *match = bucket;
                return bucket;
            }
        }
#else
        for (index = 0; index < count; index++) {
            NSSimpleSetBucket *bucket = &table->buckets[index];

            if (bucket->value == value) {
                *match = bucket;
                return bucket;
            }
        }
#endif
        if (table->valuesEqual != NULL) {
            for (index = 0; index < count; index++) {
                NSSimpleSetBucket *bucket = &table->buckets[index];

                if ((bucket->hashAndState & NSSIMPLE_HASH_MASK) == hash &&
                    table->valuesEqual(context, bucket->value, value)) {
                    *match = bucket;
                    return bucket;
                }
            }
        }
        *empty = &table->buckets[count];
        return *empty;
    }

    {
        unsigned mask = NSSimpleSetBuckets(table) - 1;
        unsigned start = hash & mask;
        unsigned firstDeleted = mask + 1;

        index = start;
        do {
            NSSimpleSetBucket *bucket = &table->buckets[index];
            unsigned state = bucket->hashAndState & NSSIMPLE_STATE_MASK;

            if (state == 0) {
                *empty = &table->buckets[firstDeleted <= mask
                    ? firstDeleted : index];
                return *empty;
            }
            if (state == NSSIMPLE_DELETED) {
                if (firstDeleted > mask)
                    firstDeleted = index;
            } else if (bucket->value == value ||
                       (table->valuesEqual != NULL &&
                        (bucket->hashAndState & NSSIMPLE_HASH_MASK) == hash &&
                        table->valuesEqual(context, bucket->value, value))) {
                *match = bucket;
                return bucket;
            }
            index = (index + ((hash & 2U) != 0 ? 0U : ~0U) +
                     (mask & (hash >> 1))) & mask;
        } while (index != start);
        if (firstDeleted <= mask)
            *empty = &table->buckets[firstDeleted];
    }
    return *empty;
}

static NSSimpleDictionaryBucket *NSSimpleDictionaryFindBucketNoMatch(
    NSSimpleDictionary *table, unsigned hash, unsigned denseIndex)
{
    unsigned level = NSSimpleHashingLevelFor(&table->countAndCapacity);
    unsigned index;

    if (level <= 1)
        return &table->buckets[denseIndex];
    {
        unsigned mask = NSSimpleDictionaryBuckets(table) - 1;
        index = hash & mask;
        while ((table->buckets[index].hashAndState & NSSIMPLE_STATE_MASK) ==
               NSSIMPLE_OCCUPIED)
            index = (index + ((hash & 2U) != 0 ? 0U : ~0U) +
                     (mask & (hash >> 1))) & mask;
    }
    return &table->buckets[index];
}

static NSSimpleSetBucket *NSSimpleSetFindBucketNoMatch(
    NSSimpleSet *table, unsigned hash, unsigned denseIndex)
{
    unsigned level = NSSimpleHashingLevelFor(&table->countAndCapacity);
    unsigned index;

    if (level <= 1)
        return &table->buckets[denseIndex];
    {
        unsigned mask = NSSimpleSetBuckets(table) - 1;
        index = hash & mask;
        while ((table->buckets[index].hashAndState & NSSIMPLE_STATE_MASK) ==
               NSSIMPLE_OCCUPIED)
            index = (index + ((hash & 2U) != 0 ? 0U : ~0U) +
                     (mask & (hash >> 1))) & mask;
    }
    return &table->buckets[index];
}

NSSimpleDictionary *NSCreateSimpleDictionary(unsigned capacity,
                                              NSSimpleHashingEqual keysEqual,
                                              NSZone *zone)
{
    unsigned level = NSSimpleHashingLevel(capacity);
    unsigned bucketCount = NSSimpleHashingBucketCounts[level];
    unsigned size = sizeof(unsigned) * 3 +
                    sizeof(NSSimpleDictionaryBucket) * bucketCount;
    unsigned index;
    NSSimpleDictionary *table = NSZoneMalloc(zone, size);

    table->countAndCapacity = level << 27;
    table->retainCount = 0;
    table->keysEqual = keysEqual;
    for (index = 0; index < bucketCount; index++)
        table->buckets[index].hashAndState = 0;
    return table;
}

NSSimpleSet *NSCreateSimpleSet(unsigned capacity,
                               NSSimpleHashingEqual valuesEqual, NSZone *zone)
{
    unsigned level = NSSimpleHashingLevel(capacity);
    unsigned bucketCount = NSSimpleHashingBucketCounts[level];
    unsigned size = sizeof(unsigned) * 3 + sizeof(NSSimpleSetBucket) * bucketCount;
    unsigned index;
    NSSimpleSet *table = NSZoneMalloc(zone, size);

    table->countAndCapacity = level << 27;
    table->retainCount = 0;
    table->valuesEqual = valuesEqual;
    for (index = 0; index < bucketCount; index++)
        table->buckets[index].hashAndState = 0;
    return table;
}

NSSimpleDictionary *NSCopySimpleDictionary(NSSimpleDictionary *source,
                                           NSZone *zone)
{
    unsigned size = sizeof(unsigned) * 3 +
                    sizeof(NSSimpleDictionaryBucket) *
                    NSSimpleDictionaryBuckets(source);
    NSSimpleDictionary *copy = NSZoneMalloc(zone, size);

    memmove(copy, source, size);
    copy->retainCount = 0;
    return copy;
}

NSSimpleSet *NSCopySimpleSet(NSSimpleSet *source, NSZone *zone)
{
    unsigned size = sizeof(unsigned) * 3 +
                    sizeof(NSSimpleSetBucket) * NSSimpleSetBuckets(source);
    NSSimpleSet *copy = NSZoneMalloc(zone, size);

    memmove(copy, source, size);
    copy->retainCount = 0;
    return copy;
}

void NSFreeSimpleDictionary(NSSimpleDictionary *table)
{
    unsigned size = sizeof(unsigned) * 3 +
                    sizeof(NSSimpleDictionaryBucket) *
                    NSSimpleDictionaryBuckets(table);
    NSZone *zone = NSZoneFromPointer(table);

    memset(table, 0, size);
    NSZoneFree(zone, table);
}

void NSFreeSimpleSet(NSSimpleSet *table)
{
    unsigned size = sizeof(unsigned) * 3 +
                    sizeof(NSSimpleSetBucket) * NSSimpleSetBuckets(table);
    NSZone *zone = NSZoneFromPointer(table);

    memset(table, 0, size);
    NSZoneFree(zone, table);
}

unsigned NSSimpleDictionaryCount(NSSimpleDictionary *table)
{
    return NSSimpleHashingCount(&table->countAndCapacity);
}

unsigned NSSimpleSetCount(NSSimpleSet *table)
{
    return NSSimpleHashingCount(&table->countAndCapacity);
}

unsigned NSSimpleDictionaryNumBuckets(NSSimpleDictionary *table)
{
    return NSSimpleDictionaryBuckets(table);
}

unsigned NSSimpleSetNumBuckets(NSSimpleSet *table)
{
    return NSSimpleSetBuckets(table);
}

NSSimpleDictionaryBucket *NSSimpleDictionaryGetBucket(
    NSSimpleDictionary *table, unsigned index)
{
    NSSimpleDictionaryBucket *bucket = &table->buckets[index];

    return (bucket->hashAndState & NSSIMPLE_STATE_MASK) == NSSIMPLE_OCCUPIED
        ? bucket : NULL;
}

NSSimpleSetBucket *NSSimpleSetGetBucket(NSSimpleSet *table, unsigned index)
{
    NSSimpleSetBucket *bucket = &table->buckets[index];

    return (bucket->hashAndState & NSSIMPLE_STATE_MASK) == NSSIMPLE_OCCUPIED
        ? bucket : NULL;
}

NSSimpleDictionaryBucket *NSSimpleDictionaryLookup(
    NSSimpleDictionary *table, void *key, unsigned hash, void *context)
{
    NSSimpleDictionaryBucket *match, *empty;

    if (NSSimpleDictionaryCount(table) == 0)
        return NULL;
    NSSimpleDictionaryFindBuckets(table, key, hash & NSSIMPLE_HASH_MASK,
                                  context, &match, &empty);
    return match;
}

NSSimpleSetBucket *NSSimpleSetLookup(NSSimpleSet *table, void *value,
                                     unsigned hash, void *context)
{
    NSSimpleSetBucket *match, *empty;

    if (NSSimpleSetCount(table) == 0)
        return NULL;
    NSSimpleSetFindBuckets(table, value, hash & NSSIMPLE_HASH_MASK,
                           context, &match, &empty);
    return match;
}

static NSSimpleDictionary *NSSimpleDictionaryResize(
    NSSimpleDictionary *table)
{
    unsigned oldBucketCount = NSSimpleDictionaryBuckets(table);
    unsigned index, count = 0;
    NSZone *zone = NSZoneFromPointer(table);
    NSSimpleDictionary *resized = NSCreateSimpleDictionary(
        NSSimpleDictionaryCount(table), table->keysEqual, zone);
    unsigned level = NSSimpleHashingLevelFor(&resized->countAndCapacity);

    for (index = oldBucketCount; index != 0; index--) {
        NSSimpleDictionaryBucket *source = &table->buckets[index - 1];
        NSSimpleDictionaryBucket *destination;

        if ((source->hashAndState & NSSIMPLE_STATE_MASK) != NSSIMPLE_OCCUPIED)
            continue;
        destination = NSSimpleDictionaryFindBucketNoMatch(
            resized, source->hashAndState & NSSIMPLE_HASH_MASK, count);
        *destination = *source;
        count++;
    }
    resized->countAndCapacity = count | (level << 27);
    resized->retainCount = table->retainCount;
    NSFreeSimpleDictionary(table);
    return resized;
}

static NSSimpleSet *NSSimpleSetResize(NSSimpleSet *table)
{
    unsigned oldBucketCount = NSSimpleSetBuckets(table);
    unsigned index, count = 0;
    NSZone *zone = NSZoneFromPointer(table);
    NSSimpleSet *resized = NSCreateSimpleSet(
        NSSimpleSetCount(table), table->valuesEqual, zone);
    unsigned level = NSSimpleHashingLevelFor(&resized->countAndCapacity);

    for (index = oldBucketCount; index != 0; index--) {
        NSSimpleSetBucket *source = &table->buckets[index - 1];
        NSSimpleSetBucket *destination;

        if ((source->hashAndState & NSSIMPLE_STATE_MASK) != NSSIMPLE_OCCUPIED)
            continue;
        destination = NSSimpleSetFindBucketNoMatch(
            resized, source->hashAndState & NSSIMPLE_HASH_MASK, count);
        *destination = *source;
        count++;
    }
    resized->countAndCapacity = count | (level << 27);
    resized->retainCount = table->retainCount;
    NSFreeSimpleSet(table);
    return resized;
}

static void NSSimpleDictionaryRemoveBucket(NSSimpleDictionary *table,
                                           NSSimpleDictionaryBucket *bucket)
{
    if (NSSimpleHashingLevelFor(&table->countAndCapacity) <= 1) {
        unsigned count = NSSimpleDictionaryCount(table);
        NSSimpleDictionaryBucket *last = &table->buckets[count - 1];

        *bucket = *last;
        last->hashAndState = NSSIMPLE_DELETED;
        last->key = NULL;
        last->value = NULL;
    } else {
        bucket->hashAndState = NSSIMPLE_DELETED;
        bucket->key = NULL;
        bucket->value = NULL;
    }
    if (NSSimpleHashingCount(&table->countAndCapacity) != 0)
        table->countAndCapacity--;
}

static void NSSimpleSetRemoveBucket(NSSimpleSet *table,
                                    NSSimpleSetBucket *bucket)
{
    if (NSSimpleHashingLevelFor(&table->countAndCapacity) <= 1) {
        unsigned count = NSSimpleSetCount(table);
        NSSimpleSetBucket *last = &table->buckets[count - 1];

        *bucket = *last;
        last->hashAndState = NSSIMPLE_DELETED;
        last->value = NULL;
    } else {
        bucket->hashAndState = NSSIMPLE_DELETED;
        bucket->value = NULL;
    }
    if (NSSimpleHashingCount(&table->countAndCapacity) != 0)
        table->countAndCapacity--;
}

int NSSimpleDictionaryInsert(NSSimpleDictionary **tablePointer,
                             void **keyPointer, unsigned hash,
                             void **valuePointer, void *context,
                             BOOL replaceValue)
{
    NSSimpleDictionary *table = *tablePointer;
    NSSimpleDictionaryBucket *match, *empty;

    NSSimpleDictionaryFindBuckets(table, *keyPointer, hash & NSSIMPLE_HASH_MASK,
                                  context, &match, &empty);
    if (match != NULL) {
        void *oldValue = match->value;

        if (replaceValue)
            match->value = *valuePointer;
        *valuePointer = oldValue;
        *keyPointer = match->key;
        return 0;
    }
    empty->hashAndState = (hash & NSSIMPLE_HASH_MASK) | NSSIMPLE_OCCUPIED;
    empty->key = *keyPointer;
    empty->value = *valuePointer;
    if (NSSimpleDictionaryCount(table) != NSSIMPLE_COUNT_MASK)
        table->countAndCapacity++;
    if (NSSimpleHashingCapacities[NSSimpleHashingLevelFor(
            &table->countAndCapacity)] < NSSimpleDictionaryCount(table))
        *tablePointer = NSSimpleDictionaryResize(table);
    return 1;
}

int NSSimpleDictionaryDelete(NSSimpleDictionary **tablePointer,
                             void **keyPointer, unsigned hash,
                             void **valuePointer, void *context)
{
    NSSimpleDictionary *table = *tablePointer;
    NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryLookup(
        table, *keyPointer, hash, context);

    if (bucket == NULL)
        return 0;
    *keyPointer = bucket->key;
    *valuePointer = bucket->value;
    NSSimpleDictionaryRemoveBucket(table, bucket);
    return 1;
}

int NSSimpleDictionaryIncrementValue(NSSimpleDictionary **tablePointer,
                                     void **keyPointer, unsigned hash,
                                     void *context)
{
    NSSimpleDictionary *table = *tablePointer;
    NSSimpleDictionaryBucket *match, *empty;

    NSSimpleDictionaryFindBuckets(table, *keyPointer, hash & NSSIMPLE_HASH_MASK,
                                  context, &match, &empty);
    if (match != NULL) {
        match->value = (void *)((unsigned long)match->value + 1);
        *keyPointer = match->key;
        return 0;
    }
    empty->hashAndState = (hash & NSSIMPLE_HASH_MASK) | NSSIMPLE_OCCUPIED;
    empty->key = *keyPointer;
    empty->value = (void *)1;
    if (NSSimpleDictionaryCount(table) != NSSIMPLE_COUNT_MASK)
        table->countAndCapacity++;
    if (NSSimpleHashingCapacities[NSSimpleHashingLevelFor(
            &table->countAndCapacity)] < NSSimpleDictionaryCount(table))
        *tablePointer = NSSimpleDictionaryResize(table);
    return 1;
}

int NSSimpleDictionaryDecrementValue(NSSimpleDictionary **tablePointer,
                                     void **keyPointer, unsigned hash,
                                     void *context)
{
    NSSimpleDictionary *table = *tablePointer;
    NSSimpleDictionaryBucket *bucket = NSSimpleDictionaryLookup(
        table, *keyPointer, hash, context);
    unsigned long value;

    if (bucket == NULL)
        return 0;
    value = (unsigned long)bucket->value - 1;
    bucket->value = (void *)value;
    if (value != 0)
        return 0;
    *keyPointer = bucket->key;
    NSSimpleDictionaryRemoveBucket(table, bucket);
    return 1;
}

NSSimpleDictionary *NSSimpleDictionaryDeleteEntriesWithValue(
    NSSimpleDictionary **tablePointer, void *value)
{
    NSSimpleDictionary *table = *tablePointer;
    unsigned level = NSSimpleHashingLevelFor(&table->countAndCapacity);
    unsigned index = NSSimpleDictionaryBuckets(table);

    if (NSSimpleDictionaryCount(table) == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        return NULL;
#else
        return table;
#endif
    }

    while (index != 0) {
        NSSimpleDictionaryBucket *bucket = &table->buckets[--index];

        if ((bucket->hashAndState & NSSIMPLE_STATE_MASK) == NSSIMPLE_OCCUPIED &&
            bucket->value == value)
            NSSimpleDictionaryRemoveBucket(table, bucket);
    }
    {
#if defined(__ppc__) || defined(__POWERPC__)
        NSSimpleDictionary *result = (NSSimpleDictionary *)(unsigned long)
            NSSimpleDictionaryCount(table);
#else
        NSSimpleDictionary *result =
            (NSSimpleDictionary *)NSSimpleHashingCapacities;
#endif

        if (NSSimpleHashingCapacities[level] < NSSimpleDictionaryCount(table)) {
            result = NSSimpleDictionaryResize(table);
            *tablePointer = result;
        }
        return result;
    }
}

int NSRetainSimpleDictionary(NSSimpleDictionary *table)
{
    int saturated;
    BOOL locked;

    saturated = NO;
    locked = NSSimpleHashingLock();
    if (table->retainCount == UINT_MAX)
        saturated = YES;
    else
        table->retainCount++;
    NSSimpleHashingUnlock(locked);
    return saturated;
}

int NSReleaseSimpleDictionary(NSSimpleDictionary *table)
{
    int wasZero;
    BOOL locked;

    wasZero = NO;
    locked = NSSimpleHashingLock();
    if (table->retainCount == 0)
        wasZero = YES;
    else if (table->retainCount != UINT_MAX)
        table->retainCount--;
    NSSimpleHashingUnlock(locked);
    return wasZero;
}

unsigned NSSimpleDictionaryRetainCount(NSSimpleDictionary *table)
{
    return table->retainCount + 1;
}

int NSSimpleSetInsert(NSSimpleSet **tablePointer, void **valuePointer,
                      unsigned hash, void *context, BOOL replaceValue)
{
    NSSimpleSet *table = *tablePointer;
    NSSimpleSetBucket *match, *empty;

    NSSimpleSetFindBuckets(table, *valuePointer, hash & NSSIMPLE_HASH_MASK,
                           context, &match, &empty);
    if (match != NULL) {
        void *oldValue = match->value;

        if (replaceValue)
            match->value = *valuePointer;
        *valuePointer = oldValue;
        return 0;
    }
    empty->hashAndState = (hash & NSSIMPLE_HASH_MASK) | NSSIMPLE_OCCUPIED;
    empty->value = *valuePointer;
    if (NSSimpleSetCount(table) != NSSIMPLE_COUNT_MASK)
        table->countAndCapacity++;
    if (NSSimpleHashingCapacities[NSSimpleHashingLevelFor(
            &table->countAndCapacity)] < NSSimpleSetCount(table))
        *tablePointer = NSSimpleSetResize(table);
    return 1;
}

int NSSimpleSetDelete(NSSimpleSet **tablePointer, void **valuePointer,
                      unsigned hash, void *context)
{
    NSSimpleSet *table = *tablePointer;
    NSSimpleSetBucket *bucket = NSSimpleSetLookup(table, *valuePointer,
                                                  hash, context);

    if (bucket == NULL)
        return 0;
    *valuePointer = bucket->value;
    NSSimpleSetRemoveBucket(table, bucket);
    return 1;
}

unsigned NSResetSimpleDictionary(NSSimpleDictionary *table,
                                 int (*releaseEntry)(void *, void *, void *),
                                 void *context)
{
    unsigned level = NSSimpleHashingLevelFor(&table->countAndCapacity);
    unsigned index = NSSimpleDictionaryBuckets(table);
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned result = (unsigned long)table;
#else
    unsigned result = (unsigned long)NSSimpleHashingBucketCounts;
#endif

    while (index != 0) {
        unsigned bucketIndex = --index;
        NSSimpleDictionaryBucket *bucket = &table->buckets[bucketIndex];
        unsigned state = bucket->hashAndState & NSSIMPLE_STATE_MASK;

#if !defined(__ppc__) && !defined(__POWERPC__)
        result = 3 * bucketIndex;
        if (releaseEntry != NULL) {
            result = state;
            if (state == NSSIMPLE_OCCUPIED)
                result = (unsigned)releaseEntry(context, bucket->key,
                                                bucket->value);
        }
#else
        if (releaseEntry != NULL && state == NSSIMPLE_OCCUPIED)
            result = (unsigned)releaseEntry(context, bucket->key,
                                            bucket->value);
#endif
        bucket->hashAndState = 0;
    }
    table->countAndCapacity = level << 27;
    return result;
}

int *NSResetSimpleSet(NSSimpleSet *table,
                      int (*releaseValue)(void *, void *), void *context)
{
    unsigned level = NSSimpleHashingLevelFor(&table->countAndCapacity);
    unsigned index = NSSimpleSetBuckets(table);
#if defined(__ppc__) || defined(__POWERPC__)
    int *result = (int *)table;
#else
    int *result = (int *)NSSimpleHashingBucketCounts;
#endif

    while (index != 0) {
        NSSimpleSetBucket *bucket = &table->buckets[--index];
        unsigned state = bucket->hashAndState & NSSIMPLE_STATE_MASK;

#if !defined(__ppc__) && !defined(__POWERPC__)
        if (releaseValue != NULL) {
            result = (int *)(long)state;
            if (state == NSSIMPLE_OCCUPIED)
                result = (int *)(long)releaseValue(context, bucket->value);
        }
#else
        if (releaseValue != NULL && state == NSSIMPLE_OCCUPIED)
            result = (int *)(long)releaseValue(context, bucket->value);
#endif
        bucket->hashAndState = 0;
    }
    table->countAndCapacity = level << 27;
    return result;
}

int NSRetainSimpleSet(NSSimpleSet *table)
{
    int saturated;
    BOOL locked;

    saturated = NO;
    locked = NSSimpleHashingLock();
    if (table->retainCount == UINT_MAX)
        saturated = YES;
    else
        table->retainCount++;
    NSSimpleHashingUnlock(locked);
    return saturated;
}

int NSReleaseSimpleSet(NSSimpleSet *table)
{
    int wasZero;
    BOOL locked;

    wasZero = NO;
    locked = NSSimpleHashingLock();
    if (table->retainCount == 0)
        wasZero = YES;
    else if (table->retainCount != UINT_MAX)
        table->retainCount--;
    NSSimpleHashingUnlock(locked);
    return wasZero;
}

unsigned NSSimpleSetRetainCount(NSSimpleSet *table)
{
    return table->retainCount + 1;
}
