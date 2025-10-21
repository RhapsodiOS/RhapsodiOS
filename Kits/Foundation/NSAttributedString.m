/*	NSAttributedString.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSAttributedString.h>

@implementation NSAttributedString

- (NSString *)string {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)attributesAtIndex:(unsigned)location effectiveRange:(NSRangePointer)range {
    // TODO: Implement this method
    return nil;
}

- (unsigned)length {
    // TODO: Implement this method
    return 0;
}

- (id)attribute:(NSString *)attrName atIndex:(unsigned int)location effectiveRange:(NSRangePointer)range {
    // TODO: Implement this method
    return nil;
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)attributesAtIndex:(unsigned)location longestEffectiveRange:(NSRangePointer)range inRange:(NSRange)rangeLimit {
    // TODO: Implement this method
    return nil;
}

- (id)attribute:(NSString *)attrName atIndex:(unsigned int)location longestEffectiveRange:(NSRangePointer)range inRange:(NSRange)rangeLimit {
    // TODO: Implement this method
    return nil;
}

- (BOOL)isEqualToAttributedString:(NSAttributedString *)other {
    // TODO: Implement this method
    return NO;
}

- (id)initWithString:(NSString *)str {
    // TODO: Implement this method
    return nil;
}

- (id)initWithString:(NSString *)str attributes:(NSDictionary *)attrs {
    // TODO: Implement this method
    return nil;
}

- (id)initWithAttributedString:(NSAttributedString *)attrStr {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSMutableAttributedString

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    // TODO: Implement this method
}

- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range {
    // TODO: Implement this method
}

- (NSMutableString *)mutableString {
    // TODO: Implement this method
    return nil;
}

- (void)addAttribute:(NSString *)name value:(id)value range:(NSRange)range {
    // TODO: Implement this method
}

- (void)addAttributes:(NSDictionary *)attrs range:(NSRange)range {
    // TODO: Implement this method
}

- (void)removeAttribute:(NSString *)name range:(NSRange)range {
    // TODO: Implement this method
}

- (void)replaceCharactersInRange:(NSRange)range withAttributedString:(NSAttributedString *)attrString {
    // TODO: Implement this method
}

- (void)insertAttributedString:(NSAttributedString *)attrString atIndex:(unsigned)loc {
    // TODO: Implement this method
}

- (void)appendAttributedString:(NSAttributedString *)attrString {
    // TODO: Implement this method
}

- (void)deleteCharactersInRange:(NSRange)range {
    // TODO: Implement this method
}

- (void)setAttributedString:(NSAttributedString *)attrString {
    // TODO: Implement this method
}

- (void)beginEditing {
    // TODO: Implement this method
}

- (void)endEditing {
    // TODO: Implement this method
}

@end
