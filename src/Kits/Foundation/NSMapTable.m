/*	NSMapTable.m
	Scalable hash table for mapping keys to values
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSMapTable.h>
#import <Foundation/NSException.h>
#import <Foundation/NSZone.h>

#include <stdlib.h>

extern void _NSGenericFree(void *pointer);

typedef struct NSSimpleDictionary NSSimpleDictionary;

typedef struct {
    unsigned hashAndState;
    void *key;
    void *value;
} NSSimpleDictionaryBucket;

typedef BOOL (*NSSimpleHashingEqual)(void *, const void *, const void *);

extern NSSimpleDictionary *NSCreateSimpleDictionary(
    unsigned capacity, NSSimpleHashingEqual keysEqual, NSZone *zone);
extern void NSFreeSimpleDictionary(NSSimpleDictionary *table);
extern unsigned NSSimpleDictionaryCount(NSSimpleDictionary *table);
extern unsigned NSSimpleDictionaryNumBuckets(NSSimpleDictionary *table);
extern NSSimpleDictionaryBucket *NSSimpleDictionaryGetBucket(
    NSSimpleDictionary *table, unsigned index);
extern NSSimpleDictionaryBucket *NSSimpleDictionaryLookup(
    NSSimpleDictionary *table, void *key, unsigned hash, void *context);
extern int NSSimpleDictionaryInsert(
    NSSimpleDictionary **tablePointer, void **keyPointer, unsigned hash,
    void **valuePointer, void *context, BOOL replaceValue);
extern int NSSimpleDictionaryDelete(
    NSSimpleDictionary **tablePointer, void **keyPointer, unsigned hash,
    void **valuePointer, void *context);
extern unsigned NSResetSimpleDictionary(
    NSSimpleDictionary *table,
    int (*releaseEntry)(void *, void *, void *), void *context);

struct _NSMapTable {
    NSSimpleDictionary *_table;
    NSMapTableKeyCallBacks keyCallBacks;
    NSMapTableValueCallBacks valueCallBacks;
};

static void NSMapTableFreePointer(NSMapTable *table, void *pointer);

static unsigned NSMapTableKeyHash(NSMapTable *table, const void *key)
{
    unsigned hash = table->keyCallBacks.hash != NULL
                  ? table->keyCallBacks.hash(table, key)
                  : (unsigned)(unsigned long)key;

    return hash;
}

static int NSMapTableReleaseKeyValue(void *context, void *key, void *value)
{
    NSMapTable *table = context;

    if (table->keyCallBacks.release != NULL)
        table->keyCallBacks.release(table, key);
    if (table->valueCallBacks.release != NULL)
        table->valueCallBacks.release(table, value);
    return 0;
}

static unsigned NSMapTableHashObject(NSMapTable *table, const void *key)
{
    (void)table;
    return [(id)key hash];
}

static BOOL NSMapTableEqualObject(NSMapTable *table, const void *first,
                                  const void *second)
{
    (void)table;
    return first == second || [(id)first isEqual:(id)second];
}

static void NSMapTableRetainObject(NSMapTable *table, const void *object)
{
    (void)table;
    [(id)object retain];
}

static void NSMapTableReleaseObject(NSMapTable *table, void *object)
{
    (void)table;
    [(id)object release];
}

static NSString *NSMapTableDescribeObject(NSMapTable *table,
                                          const void *object)
{
    (void)table;
    return [(id)object description];
}

unsigned _NSMapTableHashCString(NSMapTable *table, const void *key)
{
    const char *cursor = (const char *)key;
    unsigned hash = 0;

    (void)table;
    while (cursor != NULL && *cursor != '\0') {
        hash ^= (unsigned)(int)(signed char)*cursor++;
        if (*cursor == '\0')
            break;
        hash ^= (unsigned)((int)(signed char)*cursor++ * 0x100);
        if (*cursor == '\0')
            break;
        hash ^= (unsigned)((int)(signed char)*cursor++ * 0x10000);
        if (*cursor == '\0')
            break;
        hash ^= (unsigned)((unsigned char)*cursor++ * 0x1000000U);
    }
    return hash;
}

BOOL _NSMapTableIsEqualCString(NSMapTable *table, const void *first,
                               const void *second)
{
    (void)table;
    return strcmp((const char *)first, (const char *)second) == 0;
}

NSString *_NSMapTableDescribeCString(NSMapTable *table, const void *key)
{
    (void)table;
    return [NSString stringWithCString:(const char *)key
                                length:(unsigned)strlen((const char *)key)];
}

static void NSMapTableFreePointer(NSMapTable *table, void *pointer)
{
    (void)table;
    _NSGenericFree(pointer);
}

// Key callback structures
const NSMapTableKeyCallBacks NSIntMapKeyCallBacks =
    { NULL, NULL, NULL, NULL, NULL, NSNotAnIntMapKey };
const NSMapTableKeyCallBacks NSNonOwnedPointerMapKeyCallBacks =
    { NULL, NULL, NULL, NULL, NULL, NULL };
const NSMapTableKeyCallBacks NSNonOwnedPointerOrNullMapKeyCallBacks =
    { NULL, NULL, NULL, NULL, NULL, NSNotAPointerMapKey };
const NSMapTableKeyCallBacks NSNonRetainedObjectMapKeyCallBacks =
    { NSMapTableHashObject, NSMapTableEqualObject, NULL, NULL,
      NSMapTableDescribeObject, NULL };
const NSMapTableKeyCallBacks NSObjectMapKeyCallBacks =
    { NSMapTableHashObject, NSMapTableEqualObject, NSMapTableRetainObject,
      NSMapTableReleaseObject, NSMapTableDescribeObject, NULL };
const NSMapTableKeyCallBacks NSOwnedPointerMapKeyCallBacks =
    { NULL, NULL, NULL, NSMapTableFreePointer, NULL, NULL };

// Value callback structures
const NSMapTableValueCallBacks NSIntMapValueCallBacks = { NULL, NULL, NULL };
const NSMapTableValueCallBacks NSNonOwnedPointerMapValueCallBacks =
    { NULL, NULL, NULL };
const NSMapTableValueCallBacks NSObjectMapValueCallBacks =
    { NSMapTableRetainObject, NSMapTableReleaseObject,
      NSMapTableDescribeObject };
const NSMapTableValueCallBacks NSNonRetainedObjectMapValueCallBacks =
    { NULL, NULL, NSMapTableDescribeObject };
const NSMapTableValueCallBacks NSOwnedPointerMapValueCallBacks =
    { NULL, NSMapTableFreePointer, NULL };

// Function implementations

static int NSMapTableInsert(NSMapTable *table, void **keyPointer,
                            void **valuePointer, BOOL replace,
                            BOOL retainValueBeforeInsert)
{
    unsigned hash = NSMapTableKeyHash(table, *keyPointer);
    int inserted;

    if (retainValueBeforeInsert && table->valueCallBacks.retain != NULL)
        table->valueCallBacks.retain(table, *valuePointer);
    inserted = NSSimpleDictionaryInsert(&table->_table, keyPointer, hash,
                                        valuePointer, table, replace);
    if (inserted) {
        if (table->keyCallBacks.retain != NULL)
            table->keyCallBacks.retain(table, *keyPointer);
        if (!retainValueBeforeInsert && table->valueCallBacks.retain != NULL)
            table->valueCallBacks.retain(table, *valuePointer);
    } else if (replace && table->valueCallBacks.release != NULL) {
        table->valueCallBacks.release(table, *valuePointer);
    }
    return inserted;
}

NSMapTable *NSCreateMapTableWithZone(NSMapTableKeyCallBacks keyCallBacks, NSMapTableValueCallBacks valueCallBacks, unsigned capacity, NSZone *zone) {
    NSMapTable *table = NSZoneMalloc(zone, sizeof(NSMapTable));

    table->_table = NSCreateSimpleDictionary(capacity,
                                             keyCallBacks.isEqual, zone);
    table->keyCallBacks = keyCallBacks;
    table->valueCallBacks = valueCallBacks;
    return table;
}

NSMapTable *NSCreateMapTable(NSMapTableKeyCallBacks keyCallBacks, NSMapTableValueCallBacks valueCallBacks, unsigned capacity) {
    NSMapTable *table = NSZoneMalloc(0, sizeof(NSMapTable));

    table->_table = NSCreateSimpleDictionary(capacity,
                                             keyCallBacks.isEqual, 0);
    table->keyCallBacks = keyCallBacks;
    table->valueCallBacks = valueCallBacks;
    return table;
}

void NSFreeMapTable(NSMapTable *table) {
    NSZone *zone;

    if ((table->keyCallBacks.release != NULL ||
         table->valueCallBacks.release != NULL) &&
        NSSimpleDictionaryCount(table->_table) != 0)
        NSResetSimpleDictionary(table->_table, NSMapTableReleaseKeyValue,
                                table);
    NSFreeSimpleDictionary(table->_table);
    zone = NSZoneFromPointer(table);
    NSZoneFree(zone, table);
}

void NSResetMapTable(NSMapTable *table) {
    NSResetSimpleDictionary(table->_table, NSMapTableReleaseKeyValue, table);
}

BOOL NSCompareMapTables(NSMapTable *table1, NSMapTable *table2) {
    unsigned count, bucketCount;

    if (table1 == table2)
        return YES;
    count = NSSimpleDictionaryCount(table1->_table);
    if (count != NSSimpleDictionaryCount(table2->_table))
        return NO;
    bucketCount = NSSimpleDictionaryNumBuckets(table1->_table);
    while (bucketCount != 0) {
        NSSimpleDictionaryBucket *bucket =
            NSSimpleDictionaryGetBucket(table1->_table, --bucketCount);

        if (bucket != NULL) {
            unsigned hash = NSMapTableKeyHash(table2, bucket->key);

            if (NSSimpleDictionaryLookup(table2->_table, bucket->key, hash,
                                         table2) == NULL)
                return NO;
        }
    }
    return YES;
}

NSMapTable *NSCopyMapTableWithZone(NSMapTable *table, NSZone *zone) {
    unsigned count = NSSimpleDictionaryCount(table->_table);
    unsigned bucketCount;
    unsigned index;
    NSMapTable *copy = NSCreateMapTableWithZone(table->keyCallBacks,
                                               table->valueCallBacks,
                                               count, zone);

    if (count != 0) {
        bucketCount = NSSimpleDictionaryNumBuckets(table->_table);
        for (index = bucketCount; index != 0; index--) {
            NSSimpleDictionaryBucket *bucket =
                NSSimpleDictionaryGetBucket(table->_table, index - 1);

            if (bucket != NULL) {
                void *key = bucket->key;
                void *value = bucket->value;

                if (NSSimpleDictionaryInsert(
                        &copy->_table, &key,
                        NSMapTableKeyHash(copy, key), &value, copy, NO)) {
                    if (copy->keyCallBacks.retain != NULL)
                        table->keyCallBacks.retain(copy, key);
                    if (copy->valueCallBacks.retain != NULL)
                        table->valueCallBacks.retain(copy, value);
                }
            }
        }
    }
    return copy;
}

BOOL NSMapMember(NSMapTable *table, const void *key, void **originalKey, void **value) {
    NSSimpleDictionaryBucket *bucket;

    if (NSSimpleDictionaryCount(table->_table) == 0)
        return NO;
    bucket = NSSimpleDictionaryLookup(table->_table, (void *)key,
                                      NSMapTableKeyHash(table, key), table);
    if (bucket == NULL)
        return NO;
    if (originalKey != NULL)
        *originalKey = (void *)bucket->key;
    if (value != NULL)
        *value = (void *)bucket->value;
    return YES;
}

void *NSMapGet(NSMapTable *table, const void *key) {
    void *value = NULL;

    NSMapMember(table, key, NULL, &value);
    return value;
}

void NSMapInsert(NSMapTable *table, const void *key, const void *value) {
    void *storedKey = (void *)key;
    void *storedValue = (void *)value;

    if (key == table->keyCallBacks.notAKeyMarker)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSMapInsert(): attempt to insert notAKeyMarker"];
    NSMapTableInsert(table, &storedKey, &storedValue, YES, YES);
}

void NSMapInsertKnownAbsent(NSMapTable *table, const void *key, const void *value) {
    void *storedKey = (void *)key;
    void *storedValue = (void *)value;

    if (key == table->keyCallBacks.notAKeyMarker)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSMapInsertKnownAbsent(): attempt to insert notAKeyMarker"];
    if (!NSMapTableInsert(table, &storedKey, &storedValue, NO, NO)) {
        NSString *keyDescription = table->keyCallBacks.describe != NULL
            ? table->keyCallBacks.describe(table, key)
            : [NSString stringWithFormat:@"0x%x", (unsigned)(unsigned long)key];

        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSMapInsertKnownAbsent(): key already in table: %@",
                           keyDescription];
    }
}

void *NSMapInsertIfAbsent(NSMapTable *table, const void *key, const void *value) {
    void *storedKey = (void *)key;
    void *storedValue = (void *)value;

    if (key == table->keyCallBacks.notAKeyMarker)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSMapInsertIfAbsent(): attempt to insert notAKeyMarker"];
    return NSMapTableInsert(table, &storedKey, &storedValue, NO, NO)
         ? NULL : (void *)storedKey;
}

void NSMapRemove(NSMapTable *table, const void *key) {
    void *removedKey = (void *)key;
    void *removedValue = NULL;

    if (key == table->keyCallBacks.notAKeyMarker)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSMapRemove(): attempt to remove notAKeyMarker"];
    if (NSSimpleDictionaryCount(table->_table) == 0)
        return;
    if (NSSimpleDictionaryDelete(&table->_table, &removedKey,
                                 NSMapTableKeyHash(table, key),
                                 &removedValue, table))
        NSMapTableReleaseKeyValue(table, removedKey, removedValue);
}

NSMapEnumerator NSEnumerateMapTable(NSMapTable *table) {
    NSMapEnumerator enumerator;

    enumerator._pi = NSSimpleDictionaryNumBuckets(table->_table);
    enumerator._nk = NULL;
    enumerator._bs = table->_table;
    return enumerator;
}

BOOL NSNextMapEnumeratorPair(NSMapEnumerator *enumerator, void **key, void **value) {
    NSSimpleDictionary *dictionary = enumerator->_bs;

    while (enumerator->_pi != 0) {
        NSSimpleDictionaryBucket *bucket =
            NSSimpleDictionaryGetBucket(dictionary, --enumerator->_pi);

        if (bucket != NULL) {
            *key = (void *)bucket->key;
            *value = (void *)bucket->value;
            return YES;
        }
    }
    return NO;
}

unsigned NSCountMapTable(NSMapTable *table) {
    return NSSimpleDictionaryCount(table->_table);
}

NSString *NSStringFromMapTable(NSMapTable *table) {
    unsigned count = NSSimpleDictionaryCount(table->_table);
    unsigned bucketCount = NSSimpleDictionaryNumBuckets(table->_table);
    unsigned index;
    NSMutableString *string;

    if (count == 0)
        return [NSString stringWithFormat:@"<NSMapTable: 0x%x> {}", table];
    string = [[NSMutableString allocWithZone:NULL] initWithCapacity:count << 6];
    [string autorelease];
    [string appendFormat:@"<NSMapTable: 0x%x> {", table];
    for (index = bucketCount; index != 0; index--) {
        NSSimpleDictionaryBucket *bucket =
            NSSimpleDictionaryGetBucket(table->_table, index - 1);

        if (bucket == NULL)
            continue;
        if (table->keyCallBacks.describe != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
            NSUInteger insertionLocation = [string length];
            NSString *keyDescription =
                table->keyCallBacks.describe(table, bucket->key);
            [string replaceCharactersInRange:NSMakeRange(insertionLocation, 0)
                                  withString:keyDescription];
#else
            NSString *keyDescription =
                table->keyCallBacks.describe(table, bucket->key);
            [string replaceCharactersInRange:NSMakeRange([string length], 0)
                                  withString:keyDescription];
#endif
        } else {
            [string appendFormat:@"0x%x", (unsigned)(unsigned long)bucket->key];
        }
        [string replaceCharactersInRange:NSMakeRange([string length], 0)
                              withString:@" = "];
        if (table->valueCallBacks.describe != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
            NSUInteger insertionLocation = [string length];
            NSString *valueDescription =
                table->valueCallBacks.describe(table, bucket->value);
            [string replaceCharactersInRange:NSMakeRange(insertionLocation, 0)
                                  withString:valueDescription];
#else
            NSString *valueDescription =
                table->valueCallBacks.describe(table, bucket->value);
            [string replaceCharactersInRange:NSMakeRange([string length], 0)
                                  withString:valueDescription];
#endif
        } else {
            [string appendFormat:@"0x%x", (unsigned)(unsigned long)bucket->value];
        }
        [string replaceCharactersInRange:NSMakeRange([string length], 0)
                              withString:@";\n"];
    }
    [string replaceCharactersInRange:NSMakeRange([string length], 0)
                          withString:@"}"];
    return string;
}

NSArray *NSAllMapTableKeys(NSMapTable *table) {
    unsigned count = NSSimpleDictionaryCount(table->_table);
    unsigned bucketCount = NSSimpleDictionaryNumBuckets(table->_table);
    unsigned index, output = 0;
    id stackObjects[128];
    id *objects = stackObjects;
    NSArray *array;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        objects = NSZoneMalloc(0, count * sizeof(id));
    for (index = bucketCount; index != 0; index--) {
        NSSimpleDictionaryBucket *bucket =
            NSSimpleDictionaryGetBucket(table->_table, index - 1);

        if (bucket != NULL)
            objects[output++] = (id)bucket->key;
    }
    array = [[NSArray allocWithZone:0] initWithObjects:objects count:count];
    [array autorelease];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return array;
}

NSArray *NSAllMapTableValues(NSMapTable *table) {
    unsigned count = NSSimpleDictionaryCount(table->_table);
    unsigned bucketCount = NSSimpleDictionaryNumBuckets(table->_table);
    unsigned index, output = 0;
    id stackObjects[128];
    id *objects = stackObjects;
    NSArray *array;

    if (count == 0)
        return [NSArray array];
    if (count > 128)
        objects = NSZoneMalloc(0, count * sizeof(id));
    for (index = bucketCount; index != 0; index--) {
        NSSimpleDictionaryBucket *bucket =
            NSSimpleDictionaryGetBucket(table->_table, index - 1);

        if (bucket != NULL)
            objects[output++] = (id)bucket->value;
    }
    array = [[NSArray allocWithZone:0] initWithObjects:objects count:count];
    [array autorelease];
    if (objects != stackObjects)
        NSZoneFree(0, objects);
    return array;
}
