/*	NSConstantString.m
	Compiler-emitted constant strings
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSString.h>
#import <Foundation/NSObjCRuntime.h>
#import <objc/objc-runtime.h>

#include <limits.h>

NSString *__NSEmptyString = @"";

@implementation NSConstantString

- (const char *)lossyCString {
    return bytes;
}

- (const char *)cString {
    return bytes;
}

- (void)dealloc {
    NSLog(@"*** dealloc called for %s", self->isa->name);
}

- (void)release {
}

- (unsigned)retainCount {
    return UINT_MAX;
}

- (id)retain {
    return self;
}

- (id)autorelease {
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

- (id)initWithCharactersNoCopy:(unichar *)characters length:(unsigned)length {
    (void)characters;
    (void)length;
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

@end
