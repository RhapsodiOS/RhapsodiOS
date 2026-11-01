/*	NSFormatter.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSFormatter.h>
#import <Foundation/NSObjCRuntime.h>

@implementation NSFormatter

- (id)initWithCoder:(id)coder {
    (void)coder;
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}

- (void)encodeWithCoder:(id)coder {
    (void)coder;
}

- (NSString *)stringForObjectValue:(id)obj {
    NSRequestConcreteImplementation(self, _cmd, [NSFormatter class]);
    return nil;
}

- (NSAttributedString *)attributedStringForObjectValue:(id)obj withDefaultAttributes:(NSDictionary *)attrs {
    return nil;
}

- (NSString *)editingStringForObjectValue:(id)obj {
    return [self stringForObjectValue:obj];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error {
    NSRequestConcreteImplementation(self, _cmd, [NSFormatter class]);
    return NO;
}

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error {
    return YES;
}

@end
