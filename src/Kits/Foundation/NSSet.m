/*	NSSet.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSSet.h>

@implementation NSSet

- (unsigned)count {
    // TODO: Implement this method
    return 0;
}

- (id)member:(id)object {
    // TODO: Implement this method
    return nil;
}

- (NSEnumerator *)objectEnumerator {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)allObjects {
    // TODO: Implement this method
    return nil;
}

- (id)anyObject {
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

- (BOOL)intersectsSet:(NSSet *)otherSet {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isEqualToSet:(NSSet *)otherSet {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isSubsetOfSet:(NSSet *)otherSet {
    // TODO: Implement this method
    return NO;
}

- (void)makeObjectsPerformSelector:(SEL)aSelector {
    // TODO: Implement this method
}

- (void)makeObjectsPerformSelector:(SEL)aSelector withObject:(id)argument {
    // TODO: Implement this method
}

+ (id)set {
    // TODO: Implement this method
    return nil;
}

+ (id)setWithArray:(NSArray *)array {
    // TODO: Implement this method
    return nil;
}

+ (id)setWithObject:(id)object {
    // TODO: Implement this method
    return nil;
}

+ (id)setWithObjects:(id)firstObj, ... {
    // TODO: Implement this method
    return nil;
}

- (id)initWithArray:(NSArray *)array {
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

- (id)initWithSet:(NSSet *)set {
    // TODO: Implement this method
    return nil;
}

- (id)initWithSet:(NSSet *)set copyItems:(BOOL)flag {
    // TODO: Implement this method
    return nil;
}

+ (id)setWithSet:(NSSet *)set {
    // TODO: Implement this method
    return nil;
}

+ (id)setWithObjects:(id *)objs count:(unsigned)cnt {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSMutableSet

- (void)addObject:(id)object {
    // TODO: Implement this method
}

- (void)removeObject:(id)object {
    // TODO: Implement this method
}

- (void)addObjectsFromArray:(NSArray *)array {
    // TODO: Implement this method
}

- (void)intersectSet:(NSSet *)otherSet {
    // TODO: Implement this method
}

- (void)minusSet:(NSSet *)otherSet {
    // TODO: Implement this method
}

- (void)removeAllObjects {
    // TODO: Implement this method
}

- (void)unionSet:(NSSet *)otherSet {
    // TODO: Implement this method
}

- (void)setSet:(NSSet *)otherSet {
    // TODO: Implement this method
}

+ (id)setWithCapacity:(unsigned)numItems {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCapacity:(unsigned)numItems {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSCountedSet

- (id)initWithCapacity:(unsigned)numItems; // designated initializer {
    // TODO: Implement this method
    return nil;
}

- (id)initWithArray:(NSArray *)array {
    // TODO: Implement this method
    return nil;
}

- (id)initWithSet:(NSSet *)set {
    // TODO: Implement this method
    return nil;
}

- (unsigned)countForObject:(id)object {
    // TODO: Implement this method
    return 0;
}

- (NSEnumerator *)objectEnumerator {
    // TODO: Implement this method
    return nil;
}

- (void)addObject:(id)object {
    // TODO: Implement this method
}

- (void)removeObject:(id)object {
    // TODO: Implement this method
}

@end
