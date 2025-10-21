/*	NSArray.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSArray.h>

@implementation NSArray

- (unsigned)count {
    // TODO: Implement this method
    return 0;
}

- (id)objectAtIndex:(unsigned)index {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)arrayByAddingObject:(id)anObject {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)arrayByAddingObjectsFromArray:(NSArray *)otherArray {
    // TODO: Implement this method
    return nil;
}

- (NSString *)componentsJoinedByString:(NSString *)separator {
    // TODO: Implement this method
    return nil;
}

- (BOOL)containsObject:(id)anObject {
    // TODO: Implement this method
    return NO;
}

- (NSString *)description {
    // TODO: Implement this method
    return nil;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    // TODO: Implement this method
    return nil;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(unsigned)level {
    // TODO: Implement this method
    return nil;
}

- (id)firstObjectCommonWithArray:(NSArray *)otherArray {
    // TODO: Implement this method
    return nil;
}

- (void)getObjects:(id *)objects {
    // TODO: Implement this method
}

- (void)getObjects:(id *)objects range:(NSRange)range {
    // TODO: Implement this method
}

- (unsigned)indexOfObject:(id)anObject {
    // TODO: Implement this method
    return 0;
}

- (unsigned)indexOfObject:(id)anObject inRange:(NSRange)range {
    // TODO: Implement this method
    return 0;
}

- (unsigned)indexOfObjectIdenticalTo:(id)anObject {
    // TODO: Implement this method
    return 0;
}

- (unsigned)indexOfObjectIdenticalTo:(id)anObject inRange:(NSRange)range {
    // TODO: Implement this method
    return 0;
}

- (BOOL)isEqualToArray:(NSArray *)otherArray {
    // TODO: Implement this method
    return NO;
}

- (id)lastObject {
    // TODO: Implement this method
    return nil;
}

- (NSEnumerator *)objectEnumerator {
    // TODO: Implement this method
    return nil;
}

- (NSEnumerator *)reverseObjectEnumerator {
    // TODO: Implement this method
    return nil;
}

- (NSData *)sortedArrayHint {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)sortedArrayUsingFunction:(int (*)(id, id, void *))comparator context:(void *)context {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)sortedArrayUsingFunction:(int (*)(id, id, void *))comparator context:(void *)context hint:(NSData *)hint {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)sortedArrayUsingSelector:(SEL)comparator {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)subarrayWithRange:(NSRange)range {
    // TODO: Implement this method
    return nil;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    // TODO: Implement this method
    return NO;
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically {
    // TODO: Implement this method
    return NO;
}

- (void)makeObjectsPerformSelector:(SEL)aSelector {
    // TODO: Implement this method
}

- (void)makeObjectsPerformSelector:(SEL)aSelector withObject:(id)argument {
    // TODO: Implement this method
}

+ (id)array {
    // TODO: Implement this method
    return nil;
}

+ (id)arrayWithContentsOfFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

+ (id)arrayWithContentsOfURL:(NSURL *)url {
    // TODO: Implement this method
    return nil;
}

+ (id)arrayWithObject:(id)anObject {
    // TODO: Implement this method
    return nil;
}

+ (id)arrayWithObjects:(id)firstObj, ... {
    // TODO: Implement this method
    return nil;
}

- (id)initWithArray:(NSArray *)array {
    // TODO: Implement this method
    return nil;
}

- (id)initWithContentsOfFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (id)initWithContentsOfURL:(NSURL *)url {
    // TODO: Implement this method
    return nil;
}

- (id)initWithObjects:(id *)objects count:(unsigned)count {
    // TODO: Implement this method
    return nil;
}

- (id)initWithObjects:(id)firstObj, ... {
    // TODO: Implement this method
    return nil;
}

+ (id)arrayWithArray:(NSArray *)array {
    // TODO: Implement this method
    return nil;
}

+ (id)arrayWithObjects:(id *)objs count:(unsigned)cnt {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSMutableArray

- (void)addObject:(id)anObject {
    // TODO: Implement this method
}

- (void)insertObject:(id)anObject atIndex:(unsigned)index {
    // TODO: Implement this method
}

- (void)removeLastObject {
    // TODO: Implement this method
}

- (void)removeObjectAtIndex:(unsigned)index {
    // TODO: Implement this method
}

- (void)replaceObjectAtIndex:(unsigned)index withObject:(id)anObject {
    // TODO: Implement this method
}

- (void)addObjectsFromArray:(NSArray *)otherArray {
    // TODO: Implement this method
}

- (void)removeAllObjects {
    // TODO: Implement this method
}

- (void)removeObject:(id)anObject inRange:(NSRange)range {
    // TODO: Implement this method
}

- (void)removeObject:(id)anObject {
    // TODO: Implement this method
}

- (void)removeObjectIdenticalTo:(id)anObject inRange:(NSRange)range {
    // TODO: Implement this method
}

- (void)removeObjectIdenticalTo:(id)anObject {
    // TODO: Implement this method
}

- (void)removeObjectsFromIndices:(unsigned *)indices numIndices:(unsigned)count {
    // TODO: Implement this method
}

- (void)removeObjectsInArray:(NSArray *)otherArray {
    // TODO: Implement this method
}

- (void)removeObjectsInRange:(NSRange)range {
    // TODO: Implement this method
}

- (void)replaceObjectsInRange:(NSRange)range withObjectsFromArray:(NSArray *)otherArray range:(NSRange)otherRange {
    // TODO: Implement this method
}

- (void)replaceObjectsInRange:(NSRange)range withObjectsFromArray:(NSArray *)otherArray {
    // TODO: Implement this method
}

- (void)setArray:(NSArray *)otherArray {
    // TODO: Implement this method
}

- (void)sortUsingFunction:(int (*)(id, id, void *))compare context:(void *)context {
    // TODO: Implement this method
}

- (void)sortUsingSelector:(SEL)comparator {
    // TODO: Implement this method
}

+ (id)arrayWithCapacity:(unsigned)numItems {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCapacity:(unsigned)numItems {
    // TODO: Implement this method
    return nil;
}

@end
