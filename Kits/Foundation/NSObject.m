/*	NSObject.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@implementation NSObject

+ (void)load {
    // TODO: Implement this method
}

+ (void)initialize {
    // TODO: Implement this method
}

- (id)init {
    // TODO: Implement this method
    return nil;
}

+ (id)new {
    // TODO: Implement this method
    return nil;
}

+ (id)allocWithZone:(NSZone *)zone {
    // TODO: Implement this method
    return nil;
}

+ (id)alloc {
    // TODO: Implement this method
    return nil;
}

- (void)dealloc {
    // TODO: Implement this method
}

- (id)copy {
    // TODO: Implement this method
    return nil;
}

- (id)mutableCopy {
    // TODO: Implement this method
    return nil;
}

+ (id)copyWithZone:(NSZone *)zone {
    // TODO: Implement this method
    return nil;
}

+ (id)mutableCopyWithZone:(NSZone *)zone {
    // TODO: Implement this method
    return nil;
}

+ (Class)superclass {
    // TODO: Implement this method
    return nil;
}

+ (Class)class {
    // TODO: Implement this method
    return nil;
}

+ (void)poseAsClass:(Class)aClass {
    // TODO: Implement this method
}

+ (BOOL)instancesRespondToSelector:(SEL)aSelector {
    // TODO: Implement this method
    return NO;
}

+ (BOOL)conformsToProtocol:(Protocol *)protocol {
    // TODO: Implement this method
    return NO;
}

- (IMP)methodForSelector:(SEL)aSelector {
    // TODO: Implement this method
    return NULL;
}

+ (IMP)instanceMethodForSelector:(SEL)aSelector {
    // TODO: Implement this method
    return NULL;
}

+ (int)version {
    // TODO: Implement this method
    return 0;
}

+ (void)setVersion:(int)aVersion {
    // TODO: Implement this method
}

- (void)doesNotRecognizeSelector:(SEL)aSelector {
    // TODO: Implement this method
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    // TODO: Implement this method
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    // TODO: Implement this method
    return nil;
}

+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)aSelector {
    // TODO: Implement this method
    return nil;
}

+ (NSString *)description {
    // TODO: Implement this method
    return nil;
}

- (Class)classForCoder {
    // TODO: Implement this method
    return nil;
}

- (id)replacementObjectForCoder:(NSCoder *)aCoder {
    // TODO: Implement this method
    return nil;
}

- (id)awakeAfterUsingCoder:(NSCoder *)aDecoder {
    // TODO: Implement this method
    return nil;
}

@end

// C function implementations

id <NSObject> NSAllocateObject(Class aClass, unsigned extraBytes, NSZone *zone) {
    // TODO: Implement this function
    return nil;
}

void NSDeallocateObject(id <NSObject>object) {
    // TODO: Implement this function
}

id <NSObject> NSCopyObject(id <NSObject>object, unsigned extraBytes, NSZone *zone) {
    // TODO: Implement this function
    return nil;
}

BOOL NSShouldRetainWithZone(id <NSObject> anObject, NSZone *requestedZone) {
    // TODO: Implement this function
    return NO;
}

void NSIncrementExtraRefCount(id object) {
    // TODO: Implement this function
}

BOOL NSDecrementExtraRefCountWasZero(id object) {
    // TODO: Implement this function
    return NO;
}

unsigned NSExtraRefCount(id object) {
    // TODO: Implement this function
    return 0;
}
