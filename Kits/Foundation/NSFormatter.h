/*	NSFormatter.h
	Object formatting and parsing
	Copyright 1995-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@class NSString;
@class NSAttributedString;
@class NSDictionary;

@interface NSFormatter : NSObject <NSCopying, NSCoding>

- (NSString *)stringForObjectValue:(id)obj;

- (NSAttributedString *)attributedStringForObjectValue:(id)obj withDefaultAttributes:(NSDictionary *)attrs;

- (NSString *)editingStringForObjectValue:(id)obj;

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error;

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;

@end

