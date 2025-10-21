/*	NSGeometry.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSGeometry.h>

@implementation NSValue

+ (NSValue *)valueWithPoint:(NSPoint)point {
    // TODO: Implement this method
    return nil;
}

+ (NSValue *)valueWithSize:(NSSize)size {
    // TODO: Implement this method
    return nil;
}

+ (NSValue *)valueWithRect:(NSRect)rect {
    // TODO: Implement this method
    return nil;
}

- (NSPoint)pointValue {
    // TODO: Implement this method
    return NSMakePoint(0, 0);
}

- (NSSize)sizeValue {
    // TODO: Implement this method
    return NSMakeSize(0, 0);
}

- (NSRect)rectValue {
    // TODO: Implement this method
    return NSMakeRect(0, 0, 0, 0);
}

@end

@implementation NSCoder

- (void)encodePoint:(NSPoint)point {
    // TODO: Implement this method
}

- (NSPoint)decodePoint {
    // TODO: Implement this method
    return NSMakePoint(0, 0);
}

- (void)encodeSize:(NSSize)size {
    // TODO: Implement this method
}

- (NSSize)decodeSize {
    // TODO: Implement this method
    return NSMakeSize(0, 0);
}

- (void)encodeRect:(NSRect)rect {
    // TODO: Implement this method
}

- (NSRect)decodeRect {
    // TODO: Implement this method
    return NSMakeRect(0, 0, 0, 0);
}

@end
