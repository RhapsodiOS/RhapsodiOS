/*	NSCharacterSet.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCharacterSet.h>

@implementation NSCharacterSet

+ (NSCharacterSet *)controlCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)whitespaceCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)whitespaceAndNewlineCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)decimalDigitCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)letterCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)lowercaseLetterCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)uppercaseLetterCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)nonBaseCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)alphanumericCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)decomposableCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)illegalCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)punctuationCharacterSet {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)characterSetWithRange:(NSRange)aRange {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)characterSetWithCharactersInString:(NSString *)aString {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)characterSetWithBitmapRepresentation:(NSData *)data {
    // TODO: Implement this method
    return nil;
}

+ (NSCharacterSet *)characterSetWithContentsOfFile:(NSString *)fName {
    // TODO: Implement this method
    return nil;
}

- (BOOL)characterIsMember:(unichar)aCharacter {
    // TODO: Implement this method
    return NO;
}

- (NSData *)bitmapRepresentation {
    // TODO: Implement this method
    return nil;
}

- (NSCharacterSet *)invertedSet {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSMutableCharacterSet

- (void)addCharactersInRange:(NSRange)aRange {
    // TODO: Implement this method
}

- (void)removeCharactersInRange:(NSRange)aRange {
    // TODO: Implement this method
}

- (void)addCharactersInString:(NSString *)aString {
    // TODO: Implement this method
}

- (void)removeCharactersInString:(NSString *)aString {
    // TODO: Implement this method
}

- (void)formUnionWithCharacterSet:(NSCharacterSet *)otherSet {
    // TODO: Implement this method
}

- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)otherSet {
    // TODO: Implement this method
}

- (void)invert {
    // TODO: Implement this method
}

@end
