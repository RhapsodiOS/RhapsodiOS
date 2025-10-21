/*	NSInvocation.m
	An Objective C message object
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSInvocation.h>

@implementation NSInvocation

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig {
    // TODO: Implement this method
    return nil;
}

- (SEL)selector {
    // TODO: Implement this method
    return NULL;
}

- (void)setSelector:(SEL)selector {
    // TODO: Implement this method
}

- (id)target {
    // TODO: Implement this method
    return nil;
}

- (void)setTarget:(id)target {
    // TODO: Implement this method
}

- (void)retainArguments {
    // TODO: Implement this method
}

- (BOOL)argumentsRetained {
    // TODO: Implement this method
    return NO;
}

- (void)getReturnValue:(void *)retLoc {
    // TODO: Implement this method
}

- (void)setReturnValue:(void *)retLoc {
    // TODO: Implement this method
}

- (void)getArgument:(void *)argumentLocation atIndex:(int)index {
    // TODO: Implement this method
}

- (void)setArgument:(void *)argumentLocation atIndex:(int)index {
    // TODO: Implement this method
}

- (NSMethodSignature *)methodSignature {
    // TODO: Implement this method
    return nil;
}

- (void)invoke {
    // TODO: Implement this method
}

- (void)invokeWithTarget:(id)target {
    // TODO: Implement this method
}

@end
