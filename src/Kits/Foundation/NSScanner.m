/*	NSScanner.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSScanner.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSString.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSDecimal.h>

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <cthreads.h>
#include <ctype.h>
#include <errno.h>
#endif

extern NSDecimal *_NSCStringToDecimal(NSDecimal *result, const char *string,
                                      const char **endPointer);
#if defined(__ppc__) || defined(__POWERPC__)
extern double _NSstrtod(const char *string, char **endPointer);
#endif

@interface NSConcreteScanner : NSScanner {
@private
    NSString *_scanString;
    NSCharacterSet *_skipSet;
    NSDictionary *_locale;
    unsigned _scanLocation;
    struct {
        unsigned int caseSensitive:1;
        unsigned int :31;
    } _flags;
}

@end

static NSCharacterSet *NSScannerDefaultCharacterSet;
static NSCharacterSet *NSScannerDecimalDigitCharacterSet;

unsigned char __NSNumberSet[16] = {
    0, 0, 0, 0, 0, 0x28, 0xff, 0x03,
    0x20, 0, 0, 0, 0x20, 0, 0, 0
};

#if defined(__ppc__) || defined(__POWERPC__)
unsigned int _NSCStringToUnsignedLong(char *string, char **endPointer) {
    unsigned base = 10;
    unsigned value = 0;
    unsigned quotient;
    unsigned remainder;
    int negative = NO;
    int overflow = NO;
    int character;

    do {
        character = *string++;
    } while (isspace(character));

    if (character == '-') {
        negative = YES;
        character = *string++;
    } else if (character == '+') {
        character = *string++;
    }

    if (character == '0') {
        base = 8;
        if (string[0] == 'x' || string[0] == 'X') {
            character = string[1];
            string += 2;
            base = 16;
        }
    }

    quotient = UINT_MAX / base;
    remainder = UINT_MAX % base;
    for (;;) {
        unsigned digit;

        if (isdigit(character)) {
            digit = (unsigned)(character - '0');
        } else if (isalpha(character)) {
            digit = (unsigned)(character - (isupper(character) ? 'A' - 10
                                                                  : 'a' - 10));
        } else {
            break;
        }
        if (digit >= base)
            break;

        if (overflow || value > quotient
            || (value == quotient && digit > remainder)) {
            overflow = YES;
        } else {
            value = value * base + digit;
        }
        character = *string++;
    }

    if (overflow) {
        value = UINT_MAX;
        cthread_set_errno_self(ERANGE);
        errno = ERANGE;
    } else if (negative) {
        value = 0U - value;
    }
    if (endPointer != NULL)
        *endPointer = string - 1;
    return value;
}
#endif

static NSCharacterSet *NSScannerGetDefaultCharacterSet(void) {
    if (NSScannerDefaultCharacterSet == nil)
        NSScannerDefaultCharacterSet =
            [NSCharacterSet whitespaceAndNewlineCharacterSet];
    return NSScannerDefaultCharacterSet;
}

static BOOL NSScannerIsNumberCharacter(unichar character) {
    return character <= 0x7f
        && ((__NSNumberSet[character >> 3] >> (character & 7)) & 1) != 0;
}

static unichar NSScannerNextHexCharacter(NSString *string, unsigned length,
                                         unsigned *nextPosition,
                                         unsigned *bufferStart,
                                         unsigned *bufferLength,
                                         unsigned *bufferPosition,
                                         unichar buffer[32],
                                         unsigned *characterPosition) {
    if (*bufferPosition >= *bufferLength) {
        if (*nextPosition >= length) {
            *characterPosition = length;
            return 0xffff;
        }
        *bufferStart = *nextPosition;
        *bufferLength = length - *nextPosition;
        if (*bufferLength > 32)
            *bufferLength = 32;
        [string getCharacters:buffer
                        range:NSMakeRange(*nextPosition, *bufferLength)];
        *nextPosition += *bufferLength;
        *bufferPosition = 0;
    }
    *characterPosition = *bufferStart + *bufferPosition;
    return buffer[(*bufferPosition)++];
}

static int NSScannerHexDigit(unichar character) {
    if (character >= '0' && character <= '9')
        return character - '0';
    if (character >= 'A' && character <= 'F')
        return character - 'A' + 10;
    if (character >= 'a' && character <= 'f')
        return character - 'a' + 10;
    return -1;
}

static void NSScannerAppendNumberCharacter(char **buffer, char **writePointer,
                                           char localBuffer[64],
                                           NSUInteger *allocatedSize,
                                           NSUInteger *capacity,
                                           char character);

BOOL _NSScanIntFromString(NSString *string, NSCharacterSet *skipSet,
                          int *result, unsigned *scanLocation) {
    unsigned length = [string length];
    unsigned location = *scanLocation;
    unsigned index;
    int negative = NO;
    int value = 0;
    int overflow = NO;
    unichar character;

    if (location >= length)
        return NO;

    while (location < length && skipSet != nil) {
        character = [string characterAtIndex:location];
        if (![skipSet characterIsMember:character])
            break;
        location++;
    }

    if (location < length) {
        character = [string characterAtIndex:location];
        if (character == '-' || character == '+') {
            negative = character == '-';
            location++;
            while (location < length && skipSet != nil) {
                character = [string characterAtIndex:location];
                if (![skipSet characterIsMember:character])
                    break;
                location++;
            }
        }
    }

    index = location;
    if (index >= length)
        return NO;
    if (NSScannerDecimalDigitCharacterSet == nil)
        NSScannerDecimalDigitCharacterSet =
            [NSCharacterSet decimalDigitCharacterSet];
    if (![NSScannerDecimalDigitCharacterSet characterIsMember:
            [string characterAtIndex:index]])
        return NO;

    while (index < length) {
        int digit;

        character = [string characterAtIndex:index];
        if (NSScannerDecimalDigitCharacterSet == nil)
            NSScannerDecimalDigitCharacterSet =
                [NSCharacterSet decimalDigitCharacterSet];
        if (![NSScannerDecimalDigitCharacterSet characterIsMember:character])
            break;
        digit = character >= '0' && character <= '9'
            ? (int)character - '0' : -1;
        if (!overflow) {
            int limit = negative ? INT_MIN : -INT_MAX;
            int multiplyLimit = limit / 10;

            if (value < multiplyLimit
                || (value == multiplyLimit && -digit < limit % 10)) {
                overflow = YES;
                value = limit;
            } else {
                value = value * 10 - digit;
            }
        }
        index++;
    }

    if (result != NULL)
        *result = negative ? value : -value;
    *scanLocation = index;
    return YES;
}

BOOL _NSScanLongLongFromString(NSString *string, NSCharacterSet *skipSet,
                               long long *result, unsigned *scanLocation) {
    unsigned length = [string length];
    unsigned location = *scanLocation;
    unsigned index;
    BOOL negative = NO;
    BOOL overflow = NO;
    long long value = 0;
    unichar character;

    if (location >= length)
        return NO;

    while (location < length && skipSet != nil) {
        character = [string characterAtIndex:location];
        if (![skipSet characterIsMember:character])
            break;
        location++;
    }

    if (location < length) {
        character = [string characterAtIndex:location];
        if (character == '-' || character == '+') {
            negative = character == '-';
            location++;
            while (location < length && skipSet != nil) {
                character = [string characterAtIndex:location];
                if (![skipSet characterIsMember:character])
                    break;
                location++;
            }
        }
    }

    index = location;
    if (index >= length)
        return NO;
    if (NSScannerDecimalDigitCharacterSet == nil)
        NSScannerDecimalDigitCharacterSet =
            [NSCharacterSet decimalDigitCharacterSet];
    if (![NSScannerDecimalDigitCharacterSet characterIsMember:
            [string characterAtIndex:index]])
        return NO;

    while (index < length) {
        int digit;

        character = [string characterAtIndex:index];
        if (NSScannerDecimalDigitCharacterSet == nil)
            NSScannerDecimalDigitCharacterSet =
                [NSCharacterSet decimalDigitCharacterSet];
        if (![NSScannerDecimalDigitCharacterSet characterIsMember:character])
            break;
        digit = character >= '0' && character <= '9'
            ? (int)character - '0' : -1;
        if (!overflow) {
            long long limit = negative ? LLONG_MIN : -LLONG_MAX;
            long long multiplyLimit = limit / 10;

            if (value < multiplyLimit
                || (value == multiplyLimit && -digit < limit % 10)) {
                overflow = YES;
                value = limit;
            } else {
                value = value * 10 - digit;
            }
        }
        index++;
    }

    if (result != NULL)
        *result = negative ? value : -value;
    *scanLocation = index;
    return YES;
}

BOOL _NSScanDoubleFromString(NSString *string, NSCharacterSet *skipSet,
                             double *result, unsigned *scanLocation,
                             NSDictionary *locale) {
    char localBuffer[64];
    char *buffer = localBuffer;
    char *writePointer = localBuffer;
    char *end;
    unsigned length = [string length];
    unsigned location = *scanLocation;
    unsigned parseStart;
    unsigned nextPosition = location;
    unsigned bufferStart = 0;
    unsigned bufferLength = 0;
    unsigned bufferPosition = 0;
    unsigned characterPosition;
    NSUInteger allocatedSize = 0;
    NSUInteger capacity = sizeof(localBuffer);
    unichar decimalSeparator = '.';
    unichar character;
    unichar characters[32];
    double value;

    if (locale != nil) {
        NSString *separator = [locale objectForKey:NSDecimalSeparator];
        if (separator != nil)
            decimalSeparator = [separator characterAtIndex:0];
    }

    character = NSScannerNextHexCharacter(string, length, &nextPosition,
        &bufferStart, &bufferLength, &bufferPosition, characters,
        &characterPosition);
    while (skipSet != nil && [skipSet characterIsMember:character]
           && character != 0xffff)
        character = NSScannerNextHexCharacter(string, length, &nextPosition,
            &bufferStart, &bufferLength, &bufferPosition, characters,
            &characterPosition);
    parseStart = characterPosition;

    if (character <= 0x7f && character != 0
        && character != '+' && character != '-' && character != '.'
        && !(character >= '0' && character <= '9')
        && character != 'E' && character != 'e'
        && character <= ' ')
        return NO;

    while (character <= 0x7f) {
        if (!NSScannerIsNumberCharacter(character)) {
            if (character != decimalSeparator)
                break;
            character = '.';
        }
        NSScannerAppendNumberCharacter(&buffer, &writePointer, localBuffer,
                                       &allocatedSize, &capacity,
                                       (char)character);
        character = NSScannerNextHexCharacter(string, length, &nextPosition,
            &bufferStart, &bufferLength, &bufferPosition, characters,
            &characterPosition);
    }
    *writePointer = '\0';

#if defined(__ppc__) || defined(__POWERPC__)
    value = _NSstrtod(buffer, &end);
#else
    value = strtod(buffer, &end);
#endif
    if (end == buffer) {
        if (buffer != localBuffer)
            NSZoneFree(NULL, buffer);
        return NO;
    }

    *scanLocation = parseStart + (unsigned)(end - buffer);
    *result = value;
    if (buffer != localBuffer)
        NSZoneFree(NULL, buffer);
    return YES;
}

typedef struct {
    NSString *string;
    NSUInteger length;
    NSUInteger chunkStart;
    NSUInteger chunkLength;
    NSUInteger nextIndex;
    NSUInteger characterLocation;
    unichar characters[32];
    unichar character;
} NSScannerDecimalCursor;

static void
NSScannerDecimalCursorInit(NSScannerDecimalCursor *cursor, NSString *string,
                           NSUInteger length, NSUInteger location)
{
    cursor->string = string;
    cursor->length = length;
    cursor->chunkStart = location;
    cursor->characterLocation = location;
    cursor->nextIndex = 1;
    if (location >= length) {
        cursor->chunkLength = 0;
        cursor->character = 0xffff;
        return;
    }
    cursor->chunkLength = length - location;
    if (cursor->chunkLength > 32)
        cursor->chunkLength = 32;
    [string getCharacters:cursor->characters
                    range:NSMakeRange(location, cursor->chunkLength)];
    cursor->character = cursor->characters[0];
}

static void
NSScannerDecimalCursorNext(NSScannerDecimalCursor *cursor)
{
    NSUInteger nextStart;

    if (cursor->chunkLength <= cursor->nextIndex) {
        nextStart = cursor->chunkStart + cursor->chunkLength;
        if (cursor->length <= nextStart) {
            cursor->nextIndex = cursor->chunkLength + 1;
            cursor->characterLocation = cursor->length;
            cursor->character = 0xffff;
            return;
        }
        cursor->chunkStart = nextStart;
        cursor->chunkLength = cursor->length - nextStart;
        if (cursor->chunkLength > 32)
            cursor->chunkLength = 32;
        [cursor->string getCharacters:cursor->characters
                                range:NSMakeRange(cursor->chunkStart,
                                                  cursor->chunkLength)];
        cursor->character = cursor->characters[0];
        cursor->characterLocation = cursor->chunkStart;
        cursor->nextIndex = 1;
    } else {
        cursor->character = cursor->characters[cursor->nextIndex++];
        cursor->characterLocation = cursor->chunkStart + cursor->nextIndex - 1;
    }
}

static void
NSScannerAppendNumberCharacter(char **buffer, char **writePointer,
                               char localBuffer[64],
                               NSUInteger *allocatedSize,
                               NSUInteger *capacity, char character)
{
    NSUInteger offset;

    if (*writePointer >= *buffer + *capacity - 1) {
        offset = *writePointer - *buffer;
        *allocatedSize += 128;
        if (*buffer == localBuffer) {
            *buffer = NSZoneMalloc(NULL, *allocatedSize);
            memmove(*buffer, localBuffer, sizeof(char[64]));
        } else {
            *buffer = NSZoneRealloc(NULL, *buffer, *allocatedSize);
        }
        *capacity = *allocatedSize;
        *writePointer = *buffer + offset;
    }
    *(*writePointer)++ = character;
}

int
_NSScanDecimalFromString(NSString *string, NSCharacterSet *skipSet,
                         NSDecimal *result, unsigned *scanLocation,
                         NSDictionary *locale)
{
    char localBuffer[64];
    char *buffer = localBuffer;
    char *writePointer = localBuffer;
    NSUInteger allocatedSize = 0;
    NSUInteger capacity = sizeof(localBuffer);
    NSUInteger length = [string length];
    NSUInteger start = *scanLocation;
    NSUInteger skippedCharacters;
    NSUInteger consumedCharacters;
    unichar decimalSeparator = '.';
    NSScannerDecimalCursor cursor;
    NSDecimal decimal;
    const char *parsedEnd;

    if (locale != nil) {
        NSString *separator = [locale objectForKey:NSDecimalSeparator];
        if (separator != nil)
            decimalSeparator = [separator characterAtIndex:0];
    }

    NSScannerDecimalCursorInit(&cursor, string, length, start);
    if (skipSet != nil) {
        while ([skipSet characterIsMember:cursor.character]
               && cursor.character != 0xffff)
            NSScannerDecimalCursorNext(&cursor);
    }
    skippedCharacters = start < length ? cursor.characterLocation - start : 0;

    if (cursor.character <= 0x7f
        && (cursor.character == ' '
            || (cursor.character >= '\t' && cursor.character <= '\r')))
        return 0;

    while (cursor.character <= 0x7f
           && NSScannerIsNumberCharacter(cursor.character)) {
        NSScannerAppendNumberCharacter(&buffer, &writePointer, localBuffer,
                                       &allocatedSize, &capacity,
                                       (char)cursor.character);
        NSScannerDecimalCursorNext(&cursor);
    }
    while (cursor.character == decimalSeparator) {
        NSScannerAppendNumberCharacter(&buffer, &writePointer, localBuffer,
                                       &allocatedSize, &capacity, '.');
        NSScannerDecimalCursorNext(&cursor);
        while (cursor.character <= 0x7f
               && NSScannerIsNumberCharacter(cursor.character)) {
            NSScannerAppendNumberCharacter(&buffer, &writePointer, localBuffer,
                                           &allocatedSize, &capacity,
                                           (char)cursor.character);
            NSScannerDecimalCursorNext(&cursor);
        }
    }

    *writePointer = '\0';
    _NSCStringToDecimal(&decimal, buffer, &parsedEnd);
    if (parsedEnd == buffer) {
        if (buffer != localBuffer)
            NSZoneFree(NULL, buffer);
        return 0;
    }

    consumedCharacters = (NSUInteger)(parsedEnd - buffer);
    if (buffer != localBuffer)
        NSZoneFree(NULL, buffer);
    *scanLocation += (unsigned)(skippedCharacters + consumedCharacters);
    *result = decimal;
    return 1;
}

@implementation NSScanner

+ (id)allocWithZone:(NSZone *)zone {
    Class scannerClass = self;

    if (self == [NSScanner class])
        scannerClass = [NSConcreteScanner class];
    return NSAllocateObject(scannerClass, 0, zone);
}

- (NSString *)string {
    return (NSString *)NSRequestConcreteImplementation(self, _cmd,
        [NSScanner class]);
}

- (unsigned)scanLocation {
    NSRequestConcreteImplementation(self, _cmd, [NSScanner class]);
    return 0;
}

- (void)setScanLocation:(unsigned)pos {
    NSRequestConcreteImplementation(self, _cmd, [NSScanner class]);
}

- (void)setCharactersToBeSkipped:(NSCharacterSet *)set {
    NSRequestConcreteImplementation(self, _cmd, [NSScanner class]);
}

- (void)setCaseSensitive:(BOOL)flag {
    NSRequestConcreteImplementation(self, _cmd, [NSScanner class]);
}

- (void)setLocale:(NSDictionary *)dict {
    NSRequestConcreteImplementation(self, _cmd, [NSScanner class]);
}

- (NSCharacterSet *)charactersToBeSkipped {
    return NSScannerGetDefaultCharacterSet();
}

- (BOOL)caseSensitive {
    return NO;
}

- (NSDictionary *)locale {
    return nil;
}

- (BOOL)scanInt:(int *)value {
    unsigned location = [self scanLocation];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    NSString *string = [self string];

    if (!_NSScanIntFromString(string, skipSet, value, &location))
        return NO;
    [self setScanLocation:location];
    return YES;
}

- (BOOL)scanHexInt:(unsigned *)value {
    NSString *source = [self string];
    unsigned location = [self scanLocation];
    unsigned length = [source length];
    unsigned nextPosition = location;
    unsigned bufferStart = location;
    unsigned bufferLength = 0;
    unsigned bufferPosition = 0;
    unsigned characterPosition = location;
    NSCharacterSet *skipSet;
    unichar buffer[32];
    unichar character;
    unsigned prefixPosition;
    unsigned result = 0;
    int digit;

    character = NSScannerNextHexCharacter(source, length, &nextPosition,
        &bufferStart, &bufferLength, &bufferPosition, buffer,
        &characterPosition);
    skipSet = [self charactersToBeSkipped];
    while (skipSet != nil && character != 0xffff
           && [skipSet characterIsMember:character]) {
        character = NSScannerNextHexCharacter(source, length, &nextPosition,
            &bufferStart, &bufferLength, &bufferPosition, buffer,
            &characterPosition);
    }
    if (character == 0xffff)
        return NO;

    if (character == '0') {
        character = NSScannerNextHexCharacter(source, length, &nextPosition,
            &bufferStart, &bufferLength, &bufferPosition, buffer,
            &characterPosition);
        if (character == 'x' || character == 'X') {
            prefixPosition = characterPosition;
            character = NSScannerNextHexCharacter(source, length,
                &nextPosition, &bufferStart, &bufferLength, &bufferPosition,
                buffer, &characterPosition);
            digit = NSScannerHexDigit(character);
            if (digit == -1) {
                [self setScanLocation:prefixPosition];
                if (value != NULL)
                    *value = 0;
                return YES;
            }
        } else {
            result = 0;
            digit = NSScannerHexDigit(character);
            if (digit == -1)
                goto finish;
        }
    } else {
        digit = NSScannerHexDigit(character);
        if (digit == -1)
            return NO;
    }

    for (;;) {
        if (result <= 0x0fffffff)
            result = result * 16 + (unsigned)digit;
        else
            result = UINT_MAX;
        character = NSScannerNextHexCharacter(source, length, &nextPosition,
            &bufferStart, &bufferLength, &bufferPosition, buffer,
            &characterPosition);
        digit = NSScannerHexDigit(character);
        if (digit == -1)
            break;
    }

finish:
    [self setScanLocation:characterPosition];
    if (value != NULL)
        *value = result;
    return YES;
}

- (BOOL)scanLongLong:(long long *)value {
    unsigned location = [self scanLocation];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    NSString *string = [self string];

    if (!_NSScanLongLongFromString(string, skipSet, value, &location))
        return NO;
    [self setScanLocation:location];
    return YES;
}

- (BOOL)scanFloat:(float *)value {
    unsigned location = [self scanLocation];
    NSDictionary *locale = [self locale];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    NSString *string = [self string];
    double number;

    if (!_NSScanDoubleFromString(string, skipSet, &number, &location, locale))
        return NO;
    if (value != NULL)
        *value = (float)number;
    [self setScanLocation:location];
    return YES;
}

- (BOOL)scanDouble:(double *)value {
    unsigned location = [self scanLocation];
    NSDictionary *locale = [self locale];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    NSString *string = [self string];

    if (!_NSScanDoubleFromString(string, skipSet, value, &location, locale))
        return NO;
    [self setScanLocation:location];
    return YES;
}

- (BOOL)scanString:(NSString *)string intoString:(NSString **)value {
    NSString *source = [self string];
    unsigned location = [self scanLocation];
    unsigned length = [source length];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    unsigned options = [self caseSensitive] ? NSAnchoredSearch
        : NSAnchoredSearch | NSCaseInsensitiveSearch;
    NSRange range;

    if (skipSet != nil) {
        range = [source rangeOfCharacterFromSet:[skipSet invertedSet]
            options:0 range:NSMakeRange(location, length - location)];
        location = range.location != NSNotFound ? range.location : length;
    }

    range = [source rangeOfString:string options:options
        range:NSMakeRange(location, length - location)];
    if (range.length == 0)
        return NO;

    if (value != NULL)
        *value = [source substringWithRange:
            NSMakeRange(location, NSMaxRange(range) - location)];
    [self setScanLocation:NSMaxRange(range)];
    return YES;
}

- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)value {
    NSString *source = [self string];
    unsigned location = [self scanLocation];
    unsigned length = [source length];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    unsigned options = [self caseSensitive] ? 0 : NSCaseInsensitiveSearch;
    NSRange range;

    if (skipSet != nil) {
        range = [source rangeOfCharacterFromSet:[skipSet invertedSet]
            options:0 range:NSMakeRange(location, length - location)];
        location = range.location != NSNotFound ? range.location : length;
    }

    range = [source rangeOfCharacterFromSet:[set invertedSet] options:options
        range:NSMakeRange(location, length - location)];
    if (range.location == NSNotFound)
        range.location = length;
    if (location == range.location)
        return NO;

    if (value != NULL)
        *value = [source substringWithRange:
            NSMakeRange(location, range.location - location)];
    [self setScanLocation:range.location];
    return YES;
}

- (BOOL)scanUpToString:(NSString *)string intoString:(NSString **)value {
    NSString *source = [self string];
    unsigned location = [self scanLocation];
    unsigned length = [source length];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    unsigned options = [self caseSensitive] ? 0 : NSCaseInsensitiveSearch;
    NSRange range;

    if (skipSet != nil) {
        range = [source rangeOfCharacterFromSet:[skipSet invertedSet]
            options:0 range:NSMakeRange(location, length - location)];
        location = range.location != NSNotFound ? range.location : length;
    }

    range = [source rangeOfString:string options:options
        range:NSMakeRange(location, length - location)];
    if (range.length == 0)
        range.location = length;
    if (location == range.location)
        return NO;

    if (value != NULL)
        *value = [source substringWithRange:
            NSMakeRange(location, range.location - location)];
    [self setScanLocation:range.location];
    return YES;
}

- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)value {
    NSString *source = [self string];
    unsigned location = [self scanLocation];
    unsigned length = [source length];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    unsigned options = [self caseSensitive] ? 0 : NSCaseInsensitiveSearch;
    NSRange range;

    if (skipSet != nil) {
        range = [source rangeOfCharacterFromSet:[skipSet invertedSet]
            options:0 range:NSMakeRange(location, length - location)];
        location = range.location != NSNotFound ? range.location : length;
    }

    range = [source rangeOfCharacterFromSet:set options:options
        range:NSMakeRange(location, length - location)];
    if (range.location == NSNotFound)
        range.location = length;
    if (location == range.location)
        return NO;

    if (value != NULL)
        *value = [source substringWithRange:
            NSMakeRange(location, range.location - location)];
    [self setScanLocation:range.location];
    return YES;
}

- (BOOL)isAtEnd {
    NSString *source = [self string];
    unsigned location = [self scanLocation];
    unsigned length = [source length];
    NSCharacterSet *skipSet = [self charactersToBeSkipped];
    NSRange range;

    if (skipSet != nil) {
        range = [source rangeOfCharacterFromSet:[skipSet invertedSet]
            options:0 range:NSMakeRange(location, length - location)];
        location = range.location != NSNotFound ? range.location : length;
    }
    return location == length;
}

- (id)initWithString:(NSString *)string {
    return [super init];
}

+ (id)scannerWithString:(NSString *)string {
    NSScanner *scanner = [[NSConcreteScanner allocWithZone:NULL]
        initWithString:string];
    return [scanner autorelease];
}

+ (id)localizedScannerWithString:(NSString *)string {
    NSScanner *scanner = [[NSConcreteScanner allocWithZone:NULL]
        initWithString:string];
    NSDictionary *locale;

    [scanner autorelease];
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    [scanner setLocale:locale];
    return scanner;
}

- (id)copyWithZone:(NSZone *)zone {
    NSString *string = [self string];
    NSScanner *scanner = [[NSConcreteScanner allocWithZone:NULL]
        initWithString:string];

    [scanner setCharactersToBeSkipped:[self charactersToBeSkipped]];
    [scanner setScanLocation:[self scanLocation]];
    [scanner setCaseSensitive:[self caseSensitive]];
    [scanner setLocale:[self locale]];
    return scanner;
}

@end

@implementation NSConcreteScanner

- (NSString *)string {
    return _scanString;
}

- (unsigned)scanLocation {
    return _scanLocation;
}

- (NSCharacterSet *)charactersToBeSkipped {
    return _skipSet;
}

- (void)setScanLocation:(unsigned)pos {
    if (_scanLocation > [_scanString length])
        [NSException raise:NSRangeException
            format:@"[%s %s]: Out of bounds",
            [NSStringFromClass([self class]) lossyCString],
            [NSStringFromSelector(_cmd) lossyCString]];
    _scanLocation = pos;
}

- (NSDictionary *)locale {
    return _locale;
}

- (id)initWithString:(NSString *)string {
    [super initWithString:string];

    _scanString = [string copyWithZone:NULL];
    _skipSet = NSScannerGetDefaultCharacterSet();
    _scanLocation = 0;
    return self;
}

- (void)dealloc {
    [_scanString release];
    [_skipSet release];
    [_locale release];
    [super dealloc];
}

- (void)setLocale:(NSDictionary *)locale {
    if (_locale != locale) {
        [_locale release];
        _locale = [locale retain];
    }
}

- (BOOL)caseSensitive {
    return _flags.caseSensitive;
}

- (void)setCharactersToBeSkipped:(NSCharacterSet *)set {
    [_skipSet autorelease];
    _skipSet = [set copyWithZone:[self zone]];
}

- (BOOL)scanInt:(int *)value {
    return _NSScanIntFromString(_scanString, _skipSet, value,
                                &_scanLocation);
}

- (void)setCaseSensitive:(BOOL)flag {
    _flags.caseSensitive = flag & 1;
}

@end

@implementation NSScanner (NSDecimalNumberScanning)

- (BOOL)scanDecimal:(NSDecimal *)decimal {
    unsigned endLocation;
    NSDictionary *locale;
    NSCharacterSet *skipSet;
    NSString *string;
    NSDecimal result;

    endLocation = [self scanLocation];
    locale = [self locale];
    skipSet = [self charactersToBeSkipped];
    string = [self string];
    if (!_NSScanDecimalFromString(string, skipSet, &result, &endLocation,
                                  locale))
        return NO;
    if (decimal != NULL)
        *decimal = result;
    [self setScanLocation:endLocation];
    return YES;
}

@end
