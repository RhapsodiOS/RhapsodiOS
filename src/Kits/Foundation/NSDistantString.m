/*	NSDistantString.m
	Proxy methods for remote strings
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDistantObject.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSString.h>

extern NSStringEncoding _NSDefaultCStringEncoding(void);

@interface NSString (NSDistantStringPrivate)
- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)filledLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)lossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange;
@end

@interface NSMutableStringProxy : NSDistantObject
@end

@interface NSString (NSDistantString)
- (BOOL)_getBytesAsData:(NSData **)data maxLength:(unsigned)maxLength
    filledLength:(unsigned *)filledLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)lossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange;
- (NSString *)_getCharactersAsStringInRange:(NSRange)range;
@end

@implementation NSString (NSDistantString)

- (BOOL)_getBytesAsData:(NSData **)resultData maxLength:(unsigned)maxLength
    filledLength:(unsigned *)filledLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)lossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    NSMutableData *data = [NSMutableData dataWithLength:maxLength];
    unsigned usedLength = 0;
    BOOL success = [self getBytes:[data mutableBytes] maxLength:maxLength
        filledLength:&usedLength encoding:encoding
        allowLossyConversion:lossy range:range remainingRange:remainingRange];

    if (success) {
        [data setLength:usedLength];
        if (filledLength != NULL)
            *filledLength = usedLength;
        *resultData = data;
    } else {
        *resultData = nil;
    }
    return success;
}

- (NSString *)_getCharactersAsStringInRange:(NSRange)range {
    return [self substringWithRange:range];
}

@end

@implementation NSMutableString (NSDistantString)

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    if (![coder isByref])
        return self;
    return [NSDistantObject proxyWithLocal:self connection:[coder connection]];
}

@end

@implementation NSMutableStringProxy

- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)filledLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)lossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    NSData *data = nil;
    BOOL success = [self _getBytesAsData:&data maxLength:maxLength
        filledLength:filledLength encoding:encoding
        allowLossyConversion:lossy range:range remainingRange:remainingRange];

    if (success)
        [data getBytes:buffer];
    if (filledLength != NULL)
        NSLog(@"filled length %d", (int)*filledLength);
    return success;
}

- (void)getCString:(char *)buffer {
    [self getCString:buffer maxLength:NSMaximumStringLength
        range:NSMakeRange(0, [self length]) remainingRange:NULL];
}

- (void)getCString:(char *)buffer maxLength:(unsigned)maxLength {
    [self getCString:buffer maxLength:maxLength
        range:NSMakeRange(0, [self length]) remainingRange:NULL];
}

- (void)getCString:(char *)buffer maxLength:(unsigned)maxLength
    range:(NSRange)range remainingRange:(NSRangePointer)remainingRange {
    unsigned usedLength = 0;
    if ([self getBytes:buffer maxLength:maxLength filledLength:&usedLength
        encoding:_NSDefaultCStringEncoding() allowLossyConversion:NO
        range:range remainingRange:remainingRange])
        buffer[usedLength] = '\0';
    else
        buffer[0] = '\0';
}

- (void)getCharacters:(unichar *)buffer {
    [self getCharacters:buffer range:NSMakeRange(0, [self length])];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    NSString *characters = [self _getCharactersAsStringInRange:range];
    [characters getCharacters:buffer range:NSMakeRange(0, range.length)];
}

@end
