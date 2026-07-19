/*	NSString.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSString.h>

@implementation NSString

- (unsigned int)length {
    // TODO: Implement this method
    return 0;
}

- (unichar)characterAtIndex:(unsigned)index {
    // TODO: Implement this method
    return 0;
}

- (void)getCharacters:(unichar *)buffer {
    // TODO: Implement this method
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)aRange {
    // TODO: Implement this method
}

- (NSString *)substringFromIndex:(unsigned)from {
    // TODO: Implement this method
    return nil;
}

- (NSString *)substringToIndex:(unsigned)to {
    // TODO: Implement this method
    return nil;
}

- (NSString *)substringWithRange:(NSRange)range {
    // TODO: Implement this method
    return nil;
}

- (NSComparisonResult)compare:(NSString *)string {
    // TODO: Implement this method
    return (NSComparisonResult)0;
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)mask {
    // TODO: Implement this method
    return (NSComparisonResult)0;
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)mask range:(NSRange)compareRange {
    // TODO: Implement this method
    return (NSComparisonResult)0;
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)mask range:(NSRange)compareRange locale:(NSDictionary *)dict {
    // TODO: Implement this method
    return (NSComparisonResult)0;
}

- (NSComparisonResult)caseInsensitiveCompare:(NSString *)string {
    // TODO: Implement this method
    return (NSComparisonResult)0;
}

- (NSComparisonResult)localizedCompare:(NSString *)string {
    // TODO: Implement this method
    return (NSComparisonResult)0;
}

- (NSComparisonResult)localizedCaseInsensitiveCompare:(NSString *)string {
    // TODO: Implement this method
    return (NSComparisonResult)0;
}

- (BOOL)isEqualToString:(NSString *)aString {
    // TODO: Implement this method
    return NO;
}

- (BOOL)hasPrefix:(NSString *)aString {
    // TODO: Implement this method
    return NO;
}

- (BOOL)hasSuffix:(NSString *)aString {
    // TODO: Implement this method
    return NO;
}

- (NSRange)rangeOfString:(NSString *)aString {
    // TODO: Implement this method
    return NSMakeRange(0, 0);
}

- (NSRange)rangeOfString:(NSString *)aString options:(unsigned)mask {
    // TODO: Implement this method
    return NSMakeRange(0, 0);
}

- (NSRange)rangeOfString:(NSString *)aString options:(unsigned)mask range:(NSRange)searchRange {
    // TODO: Implement this method
    return NSMakeRange(0, 0);
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)aSet {
    // TODO: Implement this method
    return NSMakeRange(0, 0);
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)aSet options:(unsigned int)mask {
    // TODO: Implement this method
    return NSMakeRange(0, 0);
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)aSet options:(unsigned int)mask range:(NSRange)searchRange {
    // TODO: Implement this method
    return NSMakeRange(0, 0);
}

- (NSRange)rangeOfComposedCharacterSequenceAtIndex:(unsigned)index {
    // TODO: Implement this method
    return NSMakeRange(0, 0);
}

- (NSString *)stringByAppendingString:(NSString *)aString {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByAppendingFormat:(NSString *)format, ... {
    // TODO: Implement this method
    return nil;
}

- (double)doubleValue {
    // TODO: Implement this method
    return 0.0;
}

- (float)floatValue {
    // TODO: Implement this method
    return 0.0;
}

- (int)intValue {
    // TODO: Implement this method
    return 0;
}

- (NSArray *)componentsSeparatedByString:(NSString *)separator {
    // TODO: Implement this method
    return nil;
}

- (NSString *)commonPrefixWithString:(NSString *)aString options:(unsigned)mask {
    // TODO: Implement this method
    return nil;
}

- (NSString *)uppercaseString {
    // TODO: Implement this method
    return nil;
}

- (NSString *)lowercaseString {
    // TODO: Implement this method
    return nil;
}

- (NSString *)capitalizedString {
    // TODO: Implement this method
    return nil;
}

- (void)getLineStart:(unsigned *)startPtr end:(unsigned *)lineEndPtr contentsEnd:(unsigned *)contentsEndPtr forRange:(NSRange)range {
    // TODO: Implement this method
}

- (NSRange)lineRangeForRange:(NSRange)range {
    // TODO: Implement this method
    return NSMakeRange(0, 0);
}

- (NSString *)description {
    // TODO: Implement this method
    return nil;
}

- (unsigned)hash {
    // TODO: Implement this method
    return 0;
}

- (NSStringEncoding)fastestEncoding {
    // TODO: Implement this method
    return 0;
}

- (NSStringEncoding)smallestEncoding {
    // TODO: Implement this method
    return 0;
}

- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding allowLossyConversion:(BOOL)lossy {
    // TODO: Implement this method
    return nil;
}

- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding {
    // TODO: Implement this method
    return nil;
}

- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding {
    // TODO: Implement this method
    return NO;
}

- (const char *)UTF8String;	// Convenience to return null-terminated UTF8 representation {
    // TODO: Implement this method
    return nil;
}

- (const char *)cString {
    // TODO: Implement this method
    return nil;
}

- (const char *)lossyCString {
    // TODO: Implement this method
    return nil;
}

- (unsigned)cStringLength {
    // TODO: Implement this method
    return 0;
}

- (void)getCString:(char *)bytes {
    // TODO: Implement this method
}

- (void)getCString:(char *)bytes maxLength:(unsigned)maxLength {
    // TODO: Implement this method
}

- (void)getCString:(char *)bytes maxLength:(unsigned)maxLength range:(NSRange)aRange remainingRange:(NSRangePointer)leftoverRange {
    // TODO: Implement this method
}

+ (NSStringEncoding)defaultCStringEncoding {
    // TODO: Implement this method
    return 0;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    // TODO: Implement this method
    return NO;
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically; // the atomically flag is ignored if url is not of a type that can be accessed atomically {
    // TODO: Implement this method
    return NO;
}

+ (const NSStringEncoding *)availableStringEncodings {
    // TODO: Implement this method
    return nil;
}

+ (NSString *)localizedNameOfStringEncoding:(NSStringEncoding)encoding {
    // TODO: Implement this method
    return nil;
}

+ (id)string {
    // TODO: Implement this method
    return nil;
}

+ (id)stringWithString:(NSString *)string {
    // TODO: Implement this method
    return nil;
}

+ (id)stringWithCharacters:(const unichar *)characters length:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

+ (id)stringWithCString:(const char *)bytes length:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

+ (id)stringWithCString:(const char *)bytes {
    // TODO: Implement this method
    return nil;
}

+ (id)stringWithUTF8String:(const char *)bytes {
    // TODO: Implement this method
    return nil;
}

+ (id)stringWithFormat:(NSString *)format, ... {
    // TODO: Implement this method
    return nil;
}

+ (id)stringWithContentsOfFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

+ (id)stringWithContentsOfURL:(NSURL *)url {
    // TODO: Implement this method
    return nil;
}

+ (id)localizedStringWithFormat:(NSString *)format, ... {
    // TODO: Implement this method
    return nil;
}

- (id)init {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCharactersNoCopy:(unichar *)characters length:(unsigned)length freeWhenDone:(BOOL)freeBuffer {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCharacters:(const unichar *)characters length:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCStringNoCopy:(char *)bytes length:(unsigned)length freeWhenDone:(BOOL)freeBuffer {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCString:(const char *)bytes length:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCString:(const char *)bytes {
    // TODO: Implement this method
    return nil;
}

- (id)initWithUTF8String:(const char *)bytes {
    // TODO: Implement this method
    return nil;
}

- (id)initWithString:(NSString *)aString {
    // TODO: Implement this method
    return nil;
}

- (id)initWithFormat:(NSString *)format, ... {
    // TODO: Implement this method
    return nil;
}

- (id)initWithFormat:(NSString *)format arguments:(va_list)argList {
    // TODO: Implement this method
    return nil;
}

- (id)initWithFormat:(NSString *)format locale:(NSDictionary *)dict, ... {
    // TODO: Implement this method
    return nil;
}

- (id)initWithFormat:(NSString *)format locale:(NSDictionary *)dict arguments:(va_list)argList {
    // TODO: Implement this method
    return nil;
}

- (id)initWithData:(NSData *)data encoding:(NSStringEncoding)encoding {
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

@end

@implementation NSMutableString

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)aString {
    // TODO: Implement this method
}

- (void)insertString:(NSString *)aString atIndex:(unsigned)loc {
    // TODO: Implement this method
}

- (void)deleteCharactersInRange:(NSRange)range {
    // TODO: Implement this method
}

- (void)appendString:(NSString *)aString {
    // TODO: Implement this method
}

- (void)appendFormat:(NSString *)format, ... {
    // TODO: Implement this method
}

- (void)setString:(NSString *)aString {
    // TODO: Implement this method
}

+ (id)stringWithCapacity:(unsigned)capacity {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCapacity:(unsigned)capacity {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSString

- (id)propertyList {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)propertyListFromStringsFileFormat {
    // TODO: Implement this method
    return nil;
}

@end
