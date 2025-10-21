/*	NSMapTable.m
	Scalable hash table for mapping keys to values
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSMapTable.h>

// Key callback structures
const NSMapTableKeyCallBacks NSIntMapKeyCallBacks = {0};
const NSMapTableKeyCallBacks NSNonOwnedPointerMapKeyCallBacks = {0};
const NSMapTableKeyCallBacks NSNonOwnedPointerOrNullMapKeyCallBacks = {0};
const NSMapTableKeyCallBacks NSNonRetainedObjectMapKeyCallBacks = {0};
const NSMapTableKeyCallBacks NSObjectMapKeyCallBacks = {0};
const NSMapTableKeyCallBacks NSOwnedPointerMapKeyCallBacks = {0};

// Value callback structures
const NSMapTableValueCallBacks NSIntMapValueCallBacks = {0};
const NSMapTableValueCallBacks NSNonOwnedPointerMapValueCallBacks = {0};
const NSMapTableValueCallBacks NSObjectMapValueCallBacks = {0};
const NSMapTableValueCallBacks NSNonRetainedObjectMapValueCallBacks = {0};
const NSMapTableValueCallBacks NSOwnedPointerMapValueCallBacks = {0};

// Function implementations

NSMapTable *NSCreateMapTableWithZone(NSMapTableKeyCallBacks keyCallBacks, NSMapTableValueCallBacks valueCallBacks, unsigned capacity, NSZone *zone) {
    // TODO: Implement this function
    return NULL;
}

NSMapTable *NSCreateMapTable(NSMapTableKeyCallBacks keyCallBacks, NSMapTableValueCallBacks valueCallBacks, unsigned capacity) {
    // TODO: Implement this function
    return NULL;
}

void NSFreeMapTable(NSMapTable *table) {
    // TODO: Implement this function
}

void NSResetMapTable(NSMapTable *table) {
    // TODO: Implement this function
}

BOOL NSCompareMapTables(NSMapTable *table1, NSMapTable *table2) {
    // TODO: Implement this function
    return NO;
}

NSMapTable *NSCopyMapTableWithZone(NSMapTable *table, NSZone *zone) {
    // TODO: Implement this function
    return NULL;
}

BOOL NSMapMember(NSMapTable *table, const void *key, void **originalKey, void **value) {
    // TODO: Implement this function
    return NO;
}

void *NSMapGet(NSMapTable *table, const void *key) {
    // TODO: Implement this function
    return NULL;
}

void NSMapInsert(NSMapTable *table, const void *key, const void *value) {
    // TODO: Implement this function
}

void NSMapInsertKnownAbsent(NSMapTable *table, const void *key, const void *value) {
    // TODO: Implement this function
}

void *NSMapInsertIfAbsent(NSMapTable *table, const void *key, const void *value) {
    // TODO: Implement this function
    return NULL;
}

void NSMapRemove(NSMapTable *table, const void *key) {
    // TODO: Implement this function
}

NSMapEnumerator NSEnumerateMapTable(NSMapTable *table) {
    // TODO: Implement this function
    NSMapEnumerator enumerator = {0, NULL, NULL};
    return enumerator;
}

BOOL NSNextMapEnumeratorPair(NSMapEnumerator *enumerator, void **key, void **value) {
    // TODO: Implement this function
    return NO;
}

unsigned NSCountMapTable(NSMapTable *table) {
    // TODO: Implement this function
    return 0;
}

NSString *NSStringFromMapTable(NSMapTable *table) {
    // TODO: Implement this function
    return nil;
}

NSArray *NSAllMapTableKeys(NSMapTable *table) {
    // TODO: Implement this function
    return nil;
}

NSArray *NSAllMapTableValues(NSMapTable *table) {
    // TODO: Implement this function
    return nil;
}
