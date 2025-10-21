/*	NSScanner.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSScanner.h>

@implementation NSScanner

- (NSString *)string {
    // TODO: Implement this method
    return nil;
}

- (unsigned)scanLocation {
    // TODO: Implement this method
    return 0;
}

- (void)setScanLocation:(unsigned)pos {
    // TODO: Implement this method
}

- (void)setCharactersToBeSkipped:(NSCharacterSet *)set {
    // TODO: Implement this method
}

- (void)setCaseSensitive:(BOOL)flag {
    // TODO: Implement this method
}

- (void)setLocale:(NSDictionary *)dict {
    // TODO: Implement this method
}

- (NSCharacterSet *)charactersToBeSkipped {
    // TODO: Implement this method
    return nil;
}

- (BOOL)caseSensitive {
    // TODO: Implement this method
    return NO;
}

- (NSDictionary *)locale {
    // TODO: Implement this method
    return nil;
}

- (BOOL)scanInt:(int *)value {
    // TODO: Implement this method
    return NO;
}

- (BOOL)scanHexInt:(unsigned *)value;		/* Optionally prefixed with "0x" or "0X" */ {
    // TODO: Implement this method
    return NO;
}

- (BOOL)scanLongLong:(long long *)value {
    // TODO: Implement this method
    return NO;
}

- (BOOL)scanFloat:(float *)value {
    // TODO: Implement this method
    return NO;
}

- (BOOL)scanDouble:(double *)value {
    // TODO: Implement this method
    return NO;
}

- (BOOL)scanString:(NSString *)string intoString:(NSString **)value {
    // TODO: Implement this method
    return NO;
}

- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)value {
    // TODO: Implement this method
    return NO;
}

- (BOOL)scanUpToString:(NSString *)string intoString:(NSString **)value {
    // TODO: Implement this method
    return NO;
}

- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)value {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isAtEnd {
    // TODO: Implement this method
    return NO;
}

- (id)initWithString:(NSString *)string {
    // TODO: Implement this method
    return nil;
}

+ (id)scannerWithString:(NSString *)string {
    // TODO: Implement this method
    return nil;
}

+ (id)localizedScannerWithString:(NSString *)string {
    // TODO: Implement this method
    return nil;
}

@end
