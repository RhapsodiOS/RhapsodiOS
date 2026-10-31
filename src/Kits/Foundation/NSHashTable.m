/*	NSHashTable.m
	Scalable hash table
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSHashTable.h>
#import <Foundation/NSException.h>
#import <Foundation/NSZone.h>

#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned countAndCapacity;
    unsigned mutations;
    BOOL (*isEqual)(NSHashTable *, const void *, const void *);
    unsigned buckets[2];
} NSSimpleSet;

struct _NSHashTable {
    NSSimpleSet *set;
    NSHashTableCallBacks callBacks;
};

extern void NSFreeSimpleSet(NSSimpleSet *table);
typedef BOOL (*NSHashTableSimpleSetEqual)(void *, const void *, const void *);
extern NSSimpleSet *NSCreateSimpleSet(unsigned capacity,
                                      NSHashTableSimpleSetEqual valuesEqual,
                                      NSZone *zone);
extern void *NSSimpleSetLookup(NSSimpleSet *table, void *value,
                               unsigned hash, void *context);
extern void _NSGenericFree(void *pointer);
extern int NSSimpleSetInsert(NSSimpleSet **tablePointer, void **valuePointer,
                             unsigned hash, void *context, BOOL replaceValue);
extern int NSSimpleSetDelete(NSSimpleSet **tablePointer, void **valuePointer,
                             unsigned hash, void *context);
extern int *NSResetSimpleSet(NSSimpleSet *table,
                             int (*releaseValue)(void *, void *),
                             void *context);

static unsigned NSHashTableBuckets[] = {
    4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384,
    32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304,
    8388608, 16777216, 33554432, 67108864, 134217728, 268435456, 536870912
};

int NSLog2(unsigned value)
{
    int result = 0;

    while (value > 1) {
        value >>= 1;
        result++;
    }
    return result;
}

int _NSFastBSearchInt(unsigned int *values, unsigned int count,
                      unsigned int value)
{
    unsigned int low = 0;
    unsigned int high = count;

    while (low < high) {
        unsigned int middle = low + (high - low) / 2;

        if (values[middle] < value)
            low = middle + 1;
        else
            high = middle;
    }
    return (int)low;
}

static unsigned NSHashTableCount(NSSimpleSet *set) {
    return set->countAndCapacity & 0x07ffffff;
}

static unsigned NSHashTableBucketCount(NSSimpleSet *set) {
    return NSHashTableBuckets[set->countAndCapacity >> 27];
}

static unsigned NSHashTableValueHash(NSHashTable *table, const void *value) {
    unsigned hash = table->callBacks.hash != NULL
        ? table->callBacks.hash(table, value)
        : (unsigned)(unsigned long)value;
    return hash & 0x3fffffff;
}

static int NSHashTableReleaseValue(void *context, void *value) {
    NSHashTable *table = (NSHashTable *)context;

    if (table->callBacks.release != NULL)
        table->callBacks.release(table, value);
    return 0;
}

static BOOL NSHashTableInsertWithHash(NSHashTable *table, const void *value,
                                      unsigned hash, BOOL replace,
                                      const void **oldValue) {
    void *mutableValue = (void *)value;
    int inserted = NSSimpleSetInsert(&table->set, &mutableValue, hash, table,
                                     replace);

    if (oldValue != NULL)
        *oldValue = inserted ? NULL : mutableValue;
    return inserted != 0;
}

static BOOL NSHashTableInsert(NSHashTable *table, const void *value,
                              BOOL replace, const void **oldValue) {
    return NSHashTableInsertWithHash(table, value,
        NSHashTableValueHash(table, value), replace, oldValue);
}

static unsigned NSHashTableHashObject(NSHashTable *table,
                                      const void *value) {
    (void)table;
    return [(id)value hash];
}

static BOOL NSHashTableEqualObject(NSHashTable *table, const void *left,
                                   const void *right) {
    (void)table;
    return left == right || [(id)left isEqual:(id)right];
}

static void NSHashTableRetainObject(NSHashTable *table, const void *value) {
    (void)table;
    [(id)value retain];
}

static void NSHashTableReleaseObject(NSHashTable *table, void *value) {
    (void)table;
    [(id)value release];
}

static NSString *NSHashTableDescribeObject(NSHashTable *table,
                                           const void *value) {
    (void)table;
    return [(id)value description];
}

unsigned _NSHashTableHashCString(NSHashTable *table, const void *value) {
    const signed char *cursor = (const signed char *)value;
    unsigned hash = 0;
    unsigned shift = 0;

    (void)table;
    while (cursor != NULL && *cursor != 0) {
        hash ^= (unsigned)(int)*cursor++ << shift;
        shift = (shift + 8) & 0x18;
    }
    return hash;
}

BOOL _NSHashTableIsEqualCString(NSHashTable *table, const void *left,
                                const void *right) {
    (void)table;
    return strcmp((const char *)left, (const char *)right) == 0;
}

NSString *_NSHashTableDescribeCString(NSHashTable *table,
                                      const void *value) {
    (void)table;
    return [NSString stringWithCString:(const char *)value
                                length:(unsigned)strlen((const char *)value)];
}

static void NSHashTableFreePointer(NSHashTable *table, void *pointer) {
    (void)table;
    _NSGenericFree(pointer);
}

static unsigned NSHashTableHashPointerStruct(NSHashTable *table,
                                             const void *pointer) {
    (void)table;
    return *(const unsigned *)pointer;
}

static BOOL NSHashTableEqualPointerStruct(NSHashTable *table,
                                          const void *left,
                                          const void *right) {
    (void)table;
    return *(const unsigned *)left == *(const unsigned *)right;
}

const NSHashTableCallBacks NSIntHashCallBacks = { NULL, NULL, NULL, NULL, NULL };
const NSHashTableCallBacks NSNonOwnedPointerHashCallBacks =
    { NULL, NULL, NULL, NULL, NULL };
const NSHashTableCallBacks NSNonRetainedObjectHashCallBacks =
    { NSHashTableHashObject, NSHashTableEqualObject, NULL, NULL,
      NSHashTableDescribeObject };
const NSHashTableCallBacks NSObjectHashCallBacks =
    { NSHashTableHashObject, NSHashTableEqualObject, NSHashTableRetainObject,
      NSHashTableReleaseObject, NSHashTableDescribeObject };
const NSHashTableCallBacks NSOwnedObjectIdentityHashCallBacks =
    { NULL, NULL, NSHashTableRetainObject, NSHashTableReleaseObject,
      NSHashTableDescribeObject };
const NSHashTableCallBacks NSOwnedPointerHashCallBacks =
    { NULL, NULL, NULL, NSHashTableFreePointer, NULL };
const NSHashTableCallBacks NSPointerToStructHashCallBacks =
    { NSHashTableHashPointerStruct, NSHashTableEqualPointerStruct, NULL,
      NSHashTableFreePointer, NULL };

NSHashTable *NSCreateHashTableWithZone(NSHashTableCallBacks callBacks,
                                       unsigned capacity, NSZone *zone) {
    NSHashTable *table = NSZoneMalloc(zone, sizeof(NSHashTable));

    table->set = NSCreateSimpleSet(capacity,
        (NSHashTableSimpleSetEqual)callBacks.isEqual, zone);
    table->callBacks = callBacks;
    return table;
}

NSHashTable *NSCreateHashTable(NSHashTableCallBacks callBacks,
                               unsigned capacity) {
    return NSCreateHashTableWithZone(callBacks, capacity, NULL);
}

void NSResetHashTable(NSHashTable *table) {
    NSResetSimpleSet(table->set,
        table->callBacks.release != NULL ? NSHashTableReleaseValue : NULL,
        table);
}

void NSFreeHashTable(NSHashTable *table) {
    NSZone *zone;

    if (table->callBacks.release != NULL && NSHashTableCount(table->set) != 0)
        NSResetHashTable(table);
    NSFreeSimpleSet(table->set);
    zone = NSZoneFromPointer(table);
    NSZoneFree(zone, table);
}

BOOL NSCompareHashTables(NSHashTable *table1, NSHashTable *table2) {
    unsigned bucketCount;
    unsigned index;

    if (table1 == table2)
        return YES;
    if (NSHashTableCount(table1->set) != NSHashTableCount(table2->set))
        return NO;
    bucketCount = NSHashTableBucketCount(table1->set);
    for (index = bucketCount; index != 0; index--) {
        unsigned *bucket = table1->set->buckets + (index - 1) * 2;
        const void *value;

        if ((bucket[0] & 0xc0000000) != 0x80000000)
            continue;
        value = (const void *)(unsigned long)bucket[1];
        {
            unsigned hash = table2->callBacks.hash != NULL
                ? table2->callBacks.hash(table2, value)
                : (unsigned)(unsigned long)value;

            if (NSSimpleSetLookup(table2->set, (void *)value, hash, table2)
                == NULL)
                return NO;
        }
    }
    return YES;
}

NSHashTable *NSCopyHashTableWithZone(NSHashTable *table, NSZone *zone) {
    unsigned count = NSHashTableCount(table->set);
    unsigned bucketCount;
    unsigned index;
    NSHashTable *copy = NSCreateHashTableWithZone(table->callBacks, count,
                                                 zone);

    if (count != 0) {
        bucketCount = NSHashTableBucketCount(table->set);
        for (index = bucketCount; index != 0; index--) {
            unsigned *bucket = table->set->buckets + (index - 1) * 2;

            if ((bucket[0] & 0xc0000000) == 0x80000000) {
                const void *value = (const void *)(unsigned long)bucket[1];
                BOOL inserted = NSHashTableInsert(copy, value, NO, NULL);

                if (inserted && copy->callBacks.retain != NULL)
                    copy->callBacks.retain(copy, value);
            }
        }
    }
    return copy;
}

void *NSHashGet(NSHashTable *table, const void *pointer) {
    unsigned hash;
    unsigned *bucket;

    if (NSHashTableCount(table->set) == 0)
        return NULL;
    hash = NSHashTableValueHash(table, pointer);
    bucket = (unsigned *)NSSimpleSetLookup(table->set, (void *)pointer, hash,
                                           table);
    return bucket != NULL ? (void *)(unsigned long)bucket[1] : NULL;
}

void NSHashInsert(NSHashTable *table, const void *pointer) {
    const void *oldValue = NULL;
    BOOL inserted;
    unsigned hash;

    if (pointer == NULL)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSHashInsert(): attempt to insert NULL pointer"];
    hash = NSHashTableValueHash(table, pointer);
    if (table->callBacks.retain != NULL)
        table->callBacks.retain(table, pointer);
    inserted = NSHashTableInsertWithHash(table, pointer, hash, YES, &oldValue);
    if (!inserted && table->callBacks.release != NULL)
        table->callBacks.release(table, (void *)oldValue);
}

void NSHashInsertKnownAbsent(NSHashTable *table, const void *pointer) {
    NSString *description;

    if (pointer == NULL)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSHashInsertKnownAbsent(): attempt to insert NULL pointer"];
    if (!NSHashTableInsert(table, pointer, NO, NULL)) {
        if (table->callBacks.describe != NULL)
            description = table->callBacks.describe(table, pointer);
        else
            description = [NSString stringWithFormat:@"0x%x",
                (unsigned)(unsigned long)pointer];
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSHashInsertKnownAbsent(): item already in table: %@",
                    description];
    }
    if (table->callBacks.retain != NULL)
        table->callBacks.retain(table, pointer);
}

void *NSHashInsertIfAbsent(NSHashTable *table, const void *pointer) {
    const void *existing = NULL;

    if (pointer == NULL)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSHashInsertIfAbsent(): attempt to insert NULL pointer"];
    if (NSHashTableInsert(table, pointer, NO, &existing)) {
        if (table->callBacks.retain != NULL)
            table->callBacks.retain(table, pointer);
        return NULL;
    }
    return (void *)existing;
}

void NSHashRemove(NSHashTable *table, const void *pointer) {
    NSSimpleSet *set;
    unsigned hash;
    void *removed = (void *)pointer;

    if (pointer == NULL)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSHashRemove(): attempt to remove NULL pointer"];
    set = table->set;
    if (NSHashTableCount(set) == 0)
        return;
    hash = NSHashTableValueHash(table, pointer);
    if (!NSSimpleSetDelete(&table->set, &removed, hash, table))
        return;
    if (table->callBacks.release != NULL)
        table->callBacks.release(table, removed);
}

NSHashEnumerator NSEnumerateHashTable(NSHashTable *table) {
    NSHashEnumerator enumerator;

    enumerator._pi = NSHashTableBucketCount(table->set);
    enumerator._si = 0;
    enumerator._bs = table->set;
    return enumerator;
}

void *NSNextHashEnumeratorItem(NSHashEnumerator *enumerator) {
    NSSimpleSet *set = (NSSimpleSet *)enumerator->_bs;

    while (enumerator->_pi != 0) {
        unsigned *bucket = set->buckets + (--enumerator->_pi) * 2;

        if ((bucket[0] & 0xc0000000) == 0x80000000)
            return (void *)(unsigned long)bucket[1];
    }
    return NULL;
}

unsigned NSCountHashTable(NSHashTable *table) {
    return NSHashTableCount(table->set);
}

NSString *NSStringFromHashTable(NSHashTable *table) {
    unsigned count = NSHashTableCount(table->set);
    unsigned bucketCount = NSHashTableBucketCount(table->set);
    unsigned index;
    BOOL first = YES;
    NSMutableString *string;

    if (count == 0)
        return [NSString stringWithFormat:@"<NSHashTable: 0x%x> ()", table];
    string = [[NSMutableString allocWithZone:NULL]
        initWithCapacity:count << 6];
    [string autorelease];
    [string appendFormat:@"<NSHashTable: 0x%x> (", table];
    for (index = bucketCount; index != 0; index--) {
        unsigned *bucket = table->set->buckets + (index - 1) * 2;
        NSString *description;
        const void *value;

        if ((bucket[0] & 0xc0000000) != 0x80000000)
            continue;
        value = (const void *)(unsigned long)bucket[1];
        if (!first)
            [string replaceCharactersInRange:NSMakeRange([string length], 0)
                                  withString:@", "];
        if (table->callBacks.describe != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
            unsigned descriptionIndex = [string length];

            description = table->callBacks.describe(table, value);
            [string replaceCharactersInRange:
                NSMakeRange(descriptionIndex, 0) withString:description];
#else
            description = table->callBacks.describe(table, value);
            [string replaceCharactersInRange:NSMakeRange([string length], 0)
                                  withString:description];
#endif
        } else {
            [string appendFormat:@"0x%x", (unsigned)(unsigned long)value];
        }
        first = NO;
    }
    [string replaceCharactersInRange:NSMakeRange([string length], 0)
                          withString:@")"];
    return string;
}

NSArray *NSAllHashTableObjects(NSHashTable *table) {
    unsigned count = NSHashTableCount(table->set);
    unsigned bucketCount;
    unsigned index, output = 0;
    id stackObjects[128];
    id *objects = stackObjects;
    NSArray *array;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    bucketCount = NSHashTableBucketCount(table->set);
    for (index = bucketCount; index != 0; index--) {
        unsigned *bucket = table->set->buckets + (index - 1) * 2;

        if ((bucket[0] & 0xc0000000) == 0x80000000)
            objects[output++] = (id)(unsigned long)bucket[1];
    }
    array = [[NSArray allocWithZone:NULL] initWithObjects:objects
                                                   count:count];
    [array autorelease];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return array;
}
