/*	NSHashTable.m
	Scalable hash table
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSHashTable.h>

// Callback structures
const NSHashTableCallBacks NSIntHashCallBacks = {0};
const NSHashTableCallBacks NSNonOwnedPointerHashCallBacks = {0};
const NSHashTableCallBacks NSNonRetainedObjectHashCallBacks = {0};
const NSHashTableCallBacks NSObjectHashCallBacks = {0};
const NSHashTableCallBacks NSOwnedObjectIdentityHashCallBacks = {0};
const NSHashTableCallBacks NSOwnedPointerHashCallBacks = {0};
const NSHashTableCallBacks NSPointerToStructHashCallBacks = {0};

// Function implementations

NSHashTable *NSCreateHashTableWithZone(NSHashTableCallBacks callBacks, unsigned capacity, NSZone *zone) {
    // TODO: Implement this function
    return NULL;
}

NSHashTable *NSCreateHashTable(NSHashTableCallBacks callBacks, unsigned capacity) {
    // TODO: Implement this function
    return NULL;
}

void NSFreeHashTable(NSHashTable *table) {
    // TODO: Implement this function
}

void NSResetHashTable(NSHashTable *table) {
    // TODO: Implement this function
}

BOOL NSCompareHashTables(NSHashTable *table1, NSHashTable *table2) {
    // TODO: Implement this function
    return NO;
}

NSHashTable *NSCopyHashTableWithZone(NSHashTable *table, NSZone *zone) {
    // TODO: Implement this function
    return NULL;
}

void *NSHashGet(NSHashTable *table, const void *pointer) {
    // TODO: Implement this function
    return NULL;
}

void NSHashInsert(NSHashTable *table, const void *pointer) {
    // TODO: Implement this function
}

void NSHashInsertKnownAbsent(NSHashTable *table, const void *pointer) {
    // TODO: Implement this function
}

void *NSHashInsertIfAbsent(NSHashTable *table, const void *pointer) {
    // TODO: Implement this function
    return NULL;
}

void NSHashRemove(NSHashTable *table, const void *pointer) {
    // TODO: Implement this function
}

NSHashEnumerator NSEnumerateHashTable(NSHashTable *table) {
    // TODO: Implement this function
    NSHashEnumerator enumerator = {0, 0, NULL};
    return enumerator;
}

void *NSNextHashEnumeratorItem(NSHashEnumerator *enumerator) {
    // TODO: Implement this function
    return NULL;
}

unsigned NSCountHashTable(NSHashTable *table) {
    // TODO: Implement this function
    return 0;
}

NSString *NSStringFromHashTable(NSHashTable *table) {
    // TODO: Implement this function
    return nil;
}

NSArray *NSAllHashTableObjects(NSHashTable *table) {
    // TODO: Implement this function
    return nil;
}
