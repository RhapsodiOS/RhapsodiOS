/*	NSZone.m
	Memory allocation
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>

// Function implementations

NSZone *NSDefaultMallocZone(void) {
    // TODO: Implement this function
    return NULL;
}

NSZone *NSCreateZone(unsigned startSize, unsigned granularity, BOOL canFree) {
    // TODO: Implement this function
    return NULL;
}

void NSRecycleZone(NSZone *zone) {
    // TODO: Implement this function
}

void NSSetZoneName(NSZone *zone, NSString *name) {
    // TODO: Implement this function
}

NSString *NSZoneName(NSZone *zone) {
    // TODO: Implement this function
    return nil;
}

NSZone *NSZoneFromPointer(void *ptr) {
    // TODO: Implement this function
    return NULL;
}

void *NSZoneMalloc(NSZone *zone, unsigned size) {
    // TODO: Implement this function
    return NULL;
}

void *NSZoneCalloc(NSZone *zone, unsigned numElems, unsigned byteSize) {
    // TODO: Implement this function
    return NULL;
}

void *NSZoneRealloc(NSZone *zone, void *ptr, unsigned size) {
    // TODO: Implement this function
    return NULL;
}

void NSZoneFree(NSZone *zone, void *ptr) {
    // TODO: Implement this function
}

unsigned NSPageSize(void) {
    // TODO: Implement this function
    return 4096;
}

unsigned NSLogPageSize(void) {
    // TODO: Implement this function
    return 12;
}

unsigned NSRoundUpToMultipleOfPageSize(unsigned bytes) {
    // TODO: Implement this function
    return 0;
}

unsigned NSRoundDownToMultipleOfPageSize(unsigned bytes) {
    // TODO: Implement this function
    return 0;
}

void *NSAllocateMemoryPages(unsigned bytes) {
    // TODO: Implement this function
    return NULL;
}

void NSDeallocateMemoryPages(void *ptr, unsigned bytes) {
    // TODO: Implement this function
}

void NSCopyMemoryPages(const void *source, void *dest, unsigned bytes) {
    // TODO: Implement this function
}

unsigned NSRealMemoryAvailable(void) {
    // TODO: Implement this function
    return 0;
}
