/*	NSDictionary.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDictionary.h>

@implementation NSDictionary

- (unsigned)count {
    // TODO: Implement this method
    return 0;
}

- (NSEnumerator *)keyEnumerator {
    // TODO: Implement this method
    return nil;
}

- (id)objectForKey:(id)aKey {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)allKeys {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)allKeysForObject:(id)anObject {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)allValues {
    // TODO: Implement this method
    return nil;
}

- (NSString *)description {
    // TODO: Implement this method
    return nil;
}

- (NSString *)descriptionInStringsFileFormat {
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

- (BOOL)isEqualToDictionary:(NSDictionary *)otherDictionary {
    // TODO: Implement this method
    return NO;
}

- (NSEnumerator *)objectEnumerator {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)objectsForKeys:(NSArray *)keys notFoundMarker:(id)marker {
    // TODO: Implement this method
    return nil;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    // TODO: Implement this method
    return NO;
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically; // the atomically flag is ignored if url of a type that cannot be written atomically. {
    // TODO: Implement this method
    return NO;
}

- (NSArray *)keysSortedByValueUsingSelector:(SEL)comparator {
    // TODO: Implement this method
    return nil;
}

+ (id)dictionary {
    // TODO: Implement this method
    return nil;
}

+ (id)dictionaryWithContentsOfFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

+ (id)dictionaryWithContentsOfURL:(NSURL *)url {
    // TODO: Implement this method
    return nil;
}

+ (id)dictionaryWithObjects:(NSArray *)objects forKeys:(NSArray *)keys {
    // TODO: Implement this method
    return nil;
}

+ (id)dictionaryWithObjects:(id *)objects forKeys:(id *)keys count:(unsigned)count {
    // TODO: Implement this method
    return nil;
}

+ (id)dictionaryWithObjectsAndKeys:(id)firstObject, ... {
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

- (id)initWithObjects:(NSArray *)objects forKeys:(NSArray *)keys {
    // TODO: Implement this method
    return nil;
}

- (id)initWithObjects:(id *)objects forKeys:(id *)keys count:(unsigned)count {
    // TODO: Implement this method
    return nil;
}

- (id)initWithObjectsAndKeys:(id)firstObject, ... {
    // TODO: Implement this method
    return nil;
}

- (id)initWithDictionary:(NSDictionary *)otherDictionary {
    // TODO: Implement this method
    return nil;
}

+ (id)dictionaryWithDictionary:(NSDictionary *)dict {
    // TODO: Implement this method
    return nil;
}

+ (id)dictionaryWithObject:(id)object forKey:(id)key {
    // TODO: Implement this method
    return nil;
}

- (id)initWithDictionary:(NSDictionary *)otherDictionary copyItems:(BOOL)aBool {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSMutableDictionary

- (void)removeObjectForKey:(id)aKey {
    // TODO: Implement this method
}

- (void)setObject:(id)anObject forKey:(id)aKey {
    // TODO: Implement this method
}

- (void)addEntriesFromDictionary:(NSDictionary *)otherDictionary {
    // TODO: Implement this method
}

- (void)removeAllObjects {
    // TODO: Implement this method
}

- (void)removeObjectsForKeys:(NSArray *)keyArray {
    // TODO: Implement this method
}

- (void)setDictionary:(NSDictionary *)otherDictionary {
    // TODO: Implement this method
}

+ (id)dictionaryWithCapacity:(unsigned)numItems {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCapacity:(unsigned)numItems {
    // TODO: Implement this method
    return nil;
}

@end
