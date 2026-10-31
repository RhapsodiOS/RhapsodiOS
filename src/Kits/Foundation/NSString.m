/*	NSString.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSData.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSURL.h>
#import <objc/objc-class.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

extern NSComparisonResult NSCompareStringsWithLocale(NSString *first,
                                                      NSString *second,
                                                      unsigned char options,
                                                      unsigned rangeLocation,
                                                      unsigned rangeLength);
extern int NSCompareCharacters(const unichar *left, const unichar *right,
                               unsigned leftLength, unsigned rightLength,
                               unsigned options);
extern id __NSPlaceholderStringFromZone(NSZone *zone);
extern BOOL _NSWriteBytesToFile(NSString *path, const void *bytes,
                                unsigned length, BOOL atomically);
#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSStringPlaceholderLock;
extern int _NSIsMultiThreaded;

static void NSStringPlaceholderLockAcquire(void) {
    for (;;) {
        unsigned oldValue;
        unsigned acquired;
        unsigned one = 1;

        __asm__ volatile(
            "1: lwarx %0,0,%2\n\t"
            "cmpwi %0,0\n\t"
            "bne- 2f\n\t"
            "stwcx. %3,0,%2\n\t"
            "bne- 1b\n\t"
            "isync\n\t"
            "li %1,1\n\t"
            "b 3f\n"
            "2: li %1,0\n"
            "3:"
            : "=&r" (oldValue), "=&r" (acquired)
            : "r" (&__NSStringPlaceholderLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return;
        cthread_yield();
    }
}

static void NSStringPlaceholderLockRelease(void) {
    __asm__ volatile("sync" ::: "memory");
    __NSStringPlaceholderLock = 0;
}
#else
NSLock *_NSPlaceholderStringLock;
#endif
extern NSString *__NSEmptyString;
extern NSStringEncoding _NSCStringEncoding;
extern NSStringEncoding _NSDefaultCStringEncoding(void);
extern int NSPrecompUnicodeToNEXTSTEP(unichar character, unsigned char *byte);
extern int NSConvertToLower(unichar character, unichar *result, char flags);
extern int NSConvertToTitle(unichar character, unichar *result, char flags);
extern int NSConvertToUpper(unichar character, unichar *result, char flags);
extern int _NSConvertToASCIIorUnicode2(const void *bytes, unsigned length, NSStringEncoding encoding, BOOL flag, void *result, NSZone *zone);
extern id _NSNewInlineCString(const void *bytes, unsigned length, NSZone *zone);
extern id _NSNewInlineUnicodeString(const unichar *characters, unsigned length, NSZone *zone);
extern id _NSNewInlineCStringFromString(NSString *string, NSZone *zone);
extern id _NSNewInlineUnicodeStringFromString(NSString *string, NSZone *zone);
extern BOOL _NSScanIntFromString(NSString *string, NSCharacterSet *skipSet,
    int *result, unsigned *scanLocation);
extern BOOL _NSScanDoubleFromString(NSString *string, NSCharacterSet *skipSet,
    double *result, unsigned *scanLocation, NSDictionary *locale);

NSString * const NSParseErrorException = @"NSParseErrorException";
NSString * const NSCharacterConversionException = @"NSCharacterConversionException";

typedef int (*NSStringCaseConversionFunction)(unichar character, unichar *result, char flags);

static NSCharacterSet *NSStringWhitespaceSet;

unsigned NSHashString(NSString *string) {
    unsigned length;
    unsigned hash;
    unsigned index;
    unichar characters[16];

    length = [string length];
    hash = length;
    if (length > 16) {
        [string getCharacters:characters range:NSMakeRange(0, 8)];
        for (index = 0; index < 8; index++)
            hash = hash + (hash << 8) + characters[index];

        [string getCharacters:characters range:NSMakeRange(length - 8, 8)];
        for (index = 0; index < 8; index++)
            hash = hash + (hash << 8) + characters[index];
    } else {
        [string getCharacters:characters range:NSMakeRange(0, length)];
        for (index = 0; index < length; index++)
            hash = hash + (hash << 8) + characters[index];
    }

    return hash + (hash << (length & 0x1f));
}

BOOL NSBOOLFromString(NSString *string)
{
    unsigned length = [string length];
    NSRange range = NSMakeRange(0, length);

    return [string compare:@"yes" options:NSCaseInsensitiveSearch range:range] == NSOrderedSame ||
           [string compare:@"y" options:NSCaseInsensitiveSearch range:range] == NSOrderedSame;
}

NSString *NSStringFromBOOL(BOOL value)
{
    return value ? @"YES" : @"NO";
}

id _NSNewStringFromCString(const char *bytes) {
    unsigned length = (unsigned)strlen(bytes);

    return [[NSString stringWithCString:bytes length:length] retain];
}

static NSCharacterSet *NSStringGetWhitespaceSet(void) {
    if (NSStringWhitespaceSet == nil)
        NSStringWhitespaceSet = [NSCharacterSet whitespaceCharacterSet];
    return NSStringWhitespaceSet;
}

@interface NSConcreteMutableString : NSMutableString
- (id)initWithCapacity:(unsigned)capacity;
- (void)setStringWithFormat:(NSString *)format locale:(NSDictionary *)locale arguments:(va_list)argList;
- (id)_copyAndRelease;
@end

@interface NSPlaceholderString : NSString {
@public
    NSZone *zoneForString;
}
@end

static NSMutableArray *NSPlaceholderStrings;
static NSPlaceholderString *NSCachedPlaceholderString;

id __NSPlaceholderStringFromZone(NSZone *zone) {
    NSPlaceholderString *placeholder;
    int index;

#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSIsMultiThreaded)
        NSStringPlaceholderLockAcquire();
#else
    if (_NSPlaceholderStringLock != nil)
        [_NSPlaceholderStringLock lock];
#endif

    placeholder = NSCachedPlaceholderString;
    if (placeholder == nil || placeholder->zoneForString != zone) {
        if (NSPlaceholderStrings == nil) {
            NSPlaceholderStrings = [[NSMutableArray allocWithZone:NULL]
                initWithCapacity:8];
            placeholder = nil;
        } else {
            for (index = (int)[NSPlaceholderStrings count] - 1;
                 index >= 0; index--) {
                placeholder = [NSPlaceholderStrings objectAtIndex:(unsigned)index];
                if (placeholder->zoneForString == zone)
                    break;
            }
            if (index < 0)
                placeholder = nil;
        }

        if (placeholder == nil) {
            placeholder = NSAllocateObject([NSPlaceholderString class], 0, NULL);
            placeholder->zoneForString = zone;
            [NSPlaceholderStrings addObject:placeholder];
            [placeholder release];
        }
        NSCachedPlaceholderString = placeholder;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSIsMultiThreaded)
        NSStringPlaceholderLockRelease();
#else
    if (_NSPlaceholderStringLock != nil)
        [_NSPlaceholderStringLock unlock];
#endif
    return placeholder;
}

@interface NSCString : NSString
- (id)initWithCStringNoCopy:(char *)bytes length:(unsigned)length freeWhenDone:(BOOL)freeBuffer;
@end

@interface NSInlineCString : NSString
@end

@interface NSInlineUnicodeString : NSString
@end

@interface NSString (NSStringOtherEncodings)
- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength filledLength:(unsigned *)filledLength encoding:(NSStringEncoding)encoding allowLossyConversion:(BOOL)lossy range:(NSRange)range remainingRange:(NSRangePointer)remainingRange;
@end

@interface NSString (NSStringInitialization)
- (id)initWithBytes:(const char *)bytes length:(unsigned)length encoding:(NSStringEncoding)encoding;
@end

@interface NSString (NSStringCaseConversion)
- (NSString *)_caseCopyAux:(NSStringCaseConversionFunction)firstConverter :(NSStringCaseConversionFunction)wordConverter flags:(unsigned)flags;
@end

@interface NSString (NSStringRepresentations)
- (NSString *)quotedStringRepresentation;
@end

@interface NSUnicodeString : NSString
- (id)initWithCharacters:(const unichar *)characters length:(unsigned)length;
- (id)initWithCharactersNoCopy:(unichar *)characters length:(unsigned)length freeWhenDone:(BOOL)freeBuffer;
- (id)initWithBytes:(const char *)bytes length:(unsigned)length encoding:(NSStringEncoding)encoding;
- (id)initWithCString:(const char *)bytes length:(unsigned)length;
@end

typedef struct {
    BOOL isCString;
    BOOL allocated;
    unsigned char reserved[2];
    char *cstring;
    unichar *characters;
    unsigned length;
    unsigned char inlineStorage[1008];
} NSStringConversionBuffer;

static BOOL
_NSStringBytesAreASCII(const unsigned char *bytes, unsigned length)
{
    if (_NSCStringEncoding == _NSDefaultCStringEncoding())
        return YES;

    while (length != 0) {
        if (*bytes++ > 0x7f)
            return NO;
        length--;
    }

    return YES;
}

static char
_NSStringCharacterForCStringEncoding(unichar character)
{
    unsigned char byte;

    if ((unsigned short)(character - 32) <= 0x5e ||
        (unsigned short)(character - 9) <= 1 || character == 13)
        return (char)character;

    if (character <= 0x7f || _NSDefaultCStringEncoding() != NSNEXTSTEPStringEncoding)
        return 0;
    if (NSPrecompUnicodeToNEXTSTEP(character, &byte))
        return (char)byte;
    return 0;
}

id
_NSNewStringByAppendingStrings(NSZone *zone, NSString *firstString, ...)
{
    NSString *strings[40];
    unsigned lengths[40];
    NSStringEncoding encoding;
    unsigned count;
    unsigned size;
    unsigned index;
    BOOL useCString;
    va_list arguments;
    void *buffer;
    void *cursor;
    id result;

    count = 0;
    size = 0;
    useCString = YES;
    va_start(arguments, firstString);
    while (firstString != nil) {
        if (count == 40) {
            va_end(arguments);
            [NSException raise:NSRangeException format:@"Too many strings to append"];
        }

        strings[count] = firstString;
        if (useCString && [firstString fastestEncoding] != _NSDefaultCStringEncoding())
            useCString = NO;
        count++;
        firstString = va_arg(arguments, NSString *);
    }
    va_end(arguments);

    encoding = _NSDefaultCStringEncoding();
    for (index = 0; index < count; index++) {
        lengths[index] = useCString ? [strings[index] cStringLength] : [strings[index] length];
        size += lengths[index];
    }

    if (useCString) {
        buffer = size == 0 ? NULL : NSZoneMalloc(zone, size);
        cursor = buffer;
        for (index = 0; index < count; index++) {
            NSRange range;

            range = NSMakeRange(0, lengths[index]);
            [strings[index] getBytes:(char *)cursor
                           maxLength:lengths[index]
                         filledLength:NULL
                             encoding:encoding
                allowLossyConversion:NO
                               range:range
                       remainingRange:NULL];
            cursor = (char *)cursor + lengths[index];
        }
        result = [[NSString allocWithZone:zone] initWithCStringNoCopy:(char *)buffer
                                                               length:size
                                                        freeWhenDone:YES];
    } else {
        buffer = size == 0 ? NULL : NSZoneMalloc(zone, size * sizeof(unichar));
        cursor = buffer;
        for (index = 0; index < count; index++) {
            NSRange range;

            range = NSMakeRange(0, lengths[index]);
            [strings[index] getCharacters:(unichar *)cursor range:range];
            cursor = (unichar *)cursor + lengths[index];
        }
        result = [[NSString allocWithZone:zone] initWithCharactersNoCopy:(unichar *)buffer
                                                                   length:size
                                                            freeWhenDone:YES];
    }

    return result;
}

char *
_NSFastMultiCStringConcat(char *destination, char *firstCString, ...)
{
    char *write = destination;
    char *source = firstCString;
    va_list arguments;

    while (*write != '\0')
        write++;

    va_start(arguments, firstCString);
    while (source != NULL) {
        while (*source != '\0')
            *write++ = *source++;
        *write = '\0';
        source = va_arg(arguments, char *);
    }
    va_end(arguments);

    return destination;
}

@implementation NSString

+ (id)allocWithZone:(NSZone *)zone {
    return __NSPlaceholderStringFromZone(zone);
}

- (unsigned int)length {
    NSRequestConcreteImplementation(self, _cmd, [NSString class]);
    return 0;
}

- (unichar)characterAtIndex:(unsigned)index {
    NSRequestConcreteImplementation(self, _cmd, [NSString class]);
    return 0;
}

- (void)getCharacters:(unichar *)buffer {
    NSRange range;

    range.location = 0;
    range.length = [self length];
    [self getCharacters:buffer range:range];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)aRange {
    unsigned int index;

    for (index = 0; index < aRange.length; index++) {
        buffer[index] = [self characterAtIndex:aRange.location + index];
    }
}

- (NSString *)substringFromIndex:(unsigned)from {
    NSRange range;

    range.location = from;
    range.length = [self length] - from;
    return [self substringWithRange:range];
}

- (NSString *)substringToIndex:(unsigned)to {
    NSRange range;

    range.location = 0;
    range.length = to;
    return [self substringWithRange:range];
}

- (NSString *)substringWithRange:(NSRange)range {
    NSString *substring;

    substring = [self _newSubstringWithRange:range zone:[self zone]];
    return [substring autorelease];
}

- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone {
    unsigned length;
    unichar *characters;
    Class stringClass;

    length = [self length];
    if (range.location > length || range.location + range.length > length) {
        stringClass = [self class];
        [NSException raise:NSRangeException format:@"[%s %s]: Out of bounds",
                          stringClass->name, sel_getName(_cmd)];
    }

    if (range.length == 0) {
        return __NSEmptyString;
    }
    if (range.location == 0 && range.length == length) {
        return [self copyWithZone:zone];
    }

    characters = NSZoneMalloc(zone, range.length * sizeof(unichar));
    [self getCharacters:characters range:range];
    return [[NSString allocWithZone:zone] initWithCharactersNoCopy:characters
                                                            length:range.length
                                                      freeWhenDone:YES];
}

- (id)_newSubstringFromRange:(NSRange)range zone:(NSZone *)zone {
    return [self _newSubstringWithRange:range zone:[self zone]];
}

- (NSComparisonResult)compare:(NSString *)string {
    return [self compare:string options:0];
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)mask {
    NSRange compareRange;

    compareRange.location = 0;
    compareRange.length = [self length];
    return [self compare:string options:mask range:compareRange];
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)mask range:(NSRange)compareRange {
    return [self compare:string options:mask range:compareRange locale:nil];
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)mask range:(NSRange)compareRange locale:(NSDictionary *)dict {
    unichar receiverCharacters[32];
    unichar stringCharacters[32];
    unsigned receiverEnd;
    unsigned receiverIndex;
    unsigned stringLength;
    unsigned stringIndex = 0;

    if (dict)
        return NSCompareStringsWithLocale(self, string, (unsigned char)mask,
                                          compareRange.location, compareRange.length);

    receiverEnd = compareRange.location + compareRange.length;
    receiverIndex = compareRange.location;
    stringLength = [string length];
    for (;;) {
        unsigned receiverCount = receiverEnd - receiverIndex;
        unsigned stringCount = stringLength - stringIndex;
        int comparison;

        if (receiverCount > 32)
            receiverCount = 32;
        if (stringCount > 32)
            stringCount = 32;
        if (receiverCount == 0 && stringCount == 0)
            break;

        [self getCharacters:receiverCharacters
                      range:NSMakeRange(receiverIndex, receiverCount)];
        [string getCharacters:stringCharacters
                        range:NSMakeRange(stringIndex, stringCount)];
        comparison = NSCompareCharacters(receiverCharacters, stringCharacters,
                                         receiverCount, stringCount, mask);
        if (comparison != NSOrderedSame)
            return (NSComparisonResult)comparison;

        receiverIndex += receiverCount;
        stringIndex += stringCount;
    }
    return NSOrderedSame;
}

- (NSComparisonResult)caseInsensitiveCompare:(NSString *)string {
    NSRange compareRange;

    compareRange.location = 0;
    compareRange.length = [self length];
    return [self compare:string options:NSCaseInsensitiveSearch range:compareRange];
}

- (NSComparisonResult)localizedCompare:(NSString *)string {
    NSDictionary *locale;
    NSRange range;
#if defined(__ppc__) || defined(__POWERPC__)
    range = NSMakeRange(0, [self length]);
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
#else
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    range = NSMakeRange(0, [self length]);
#endif
    return [self compare:string options:0 range:range locale:locale];
}

- (NSComparisonResult)localizedCaseInsensitiveCompare:(NSString *)string {
    NSDictionary *locale;
    NSRange range;
#if defined(__ppc__) || defined(__POWERPC__)
    range = NSMakeRange(0, [self length]);
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
#else
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    range = NSMakeRange(0, [self length]);
#endif
    return [self compare:string options:NSCaseInsensitiveSearch range:range locale:locale];
}

- (BOOL)isEqualToString:(NSString *)aString {
    NSRange range;

    if (self == aString) {
        return YES;
    }

    range.location = 0;
    range.length = [self length];
    return [self compare:aString options:0 range:range] == NSOrderedSame;
}

- (BOOL)isEqual:(id)anObject {
    if (self == anObject) {
        return YES;
    }

    return [anObject isKindOfClass:[NSString class]] && [self isEqualToString:anObject];
}

- (BOOL)hasPrefix:(NSString *)aString {
    NSRange searchRange;
    NSRange matchRange;

    searchRange.location = 0;
    searchRange.length = [self length];
    matchRange = [self rangeOfString:aString options:NSAnchoredSearch range:searchRange];
    return matchRange.location != NSNotFound;
}

- (BOOL)hasSuffix:(NSString *)aString {
    NSRange searchRange;
    NSRange matchRange;

    searchRange.location = 0;
    searchRange.length = [self length];
    matchRange = [self rangeOfString:aString options:(NSAnchoredSearch | NSBackwardsSearch) range:searchRange];
    return matchRange.location != NSNotFound;
}

- (NSRange)rangeOfString:(NSString *)aString {
    NSRange searchRange;

    searchRange.location = 0;
    searchRange.length = [self length];
    return [self rangeOfString:aString options:0 range:searchRange];
}

- (NSRange)rangeOfString:(NSString *)aString options:(unsigned)mask {
    NSRange searchRange;

    searchRange.location = 0;
    searchRange.length = [self length];
    return [self rangeOfString:aString options:mask range:searchRange];
}

- (NSRange)rangeOfString:(NSString *)aString options:(unsigned)mask range:(NSRange)searchRange {
    unsigned stringLength;
    unsigned searchLength;
    unsigned firstLocation;
    unsigned lastLocation;
    unsigned rangeEnd;
    unsigned location;
    unsigned cacheStart;
    unsigned cacheLength;
    int step;
    unsigned index;
    unichar searchStackBuffer[100];
    unichar *searchCharacters;
    unichar receiverStackBuffer[32];
    unichar character;
    unichar lowercaseCharacter;
    NSRange result;
    BOOL backwards;
    BOOL matches;

    searchLength = [aString length];
    stringLength = [self length];
    if (searchRange.location + searchRange.length > stringLength) {
        Class stringClass;

        stringClass = [self class];
        [NSException raise:NSRangeException format:@"[%s %s]: Out of bounds",
                          stringClass->name, sel_getName(_cmd)];
    }

    result = NSMakeRange(NSNotFound, 0);
    if (searchRange.length == 0 || searchLength == 0 ||
        searchRange.length < searchLength)
        return result;

    if (searchLength <= 100)
        searchCharacters = searchStackBuffer;
    else
        searchCharacters = NSZoneMalloc(NULL, searchLength * sizeof(unichar));
    [aString getCharacters:searchCharacters range:NSMakeRange(0, searchLength)];

    if ((mask & NSCaseInsensitiveSearch) != 0) {
        for (index = 0; index < searchLength; index++) {
            character = searchCharacters[index];
            if (character > 0x7f) {
                NSConvertToLower(character, &lowercaseCharacter, 0);
                searchCharacters[index] = lowercaseCharacter;
            } else if ((unsigned short)(character - 'A') <= 'Z' - 'A') {
                searchCharacters[index] = character + ('a' - 'A');
            }
        }
    }

    firstLocation = searchRange.location;
    rangeEnd = searchRange.location + searchRange.length;
    lastLocation = rangeEnd - searchLength;
    backwards = (mask & NSBackwardsSearch) != 0;
    location = backwards ? lastLocation : firstLocation;
    if ((mask & NSAnchoredSearch) != 0)
        location = backwards ? lastLocation : firstLocation;
    step = backwards ? -1 : 1;

    cacheStart = backwards ? lastLocation : firstLocation;
    cacheLength = rangeEnd - cacheStart;
    if (cacheLength > 32)
        cacheLength = 32;
    [self getCharacters:receiverStackBuffer
                  range:NSMakeRange(cacheStart, cacheLength)];

    for (;;) {
        matches = YES;
        if (location < cacheStart || location >= cacheStart + cacheLength) {
            if (location > 15) {
                if (location <= rangeEnd - 16)
                    cacheStart = location - 16;
                else
                    cacheStart = rangeEnd > 31 ? rangeEnd - 32 : 0;
            } else {
                cacheStart = 0;
            }
            cacheLength = rangeEnd - cacheStart;
            if (cacheLength > 32)
                cacheLength = 32;
            [self getCharacters:receiverStackBuffer
                          range:NSMakeRange(cacheStart, cacheLength)];
        }
        for (index = 0; index < searchLength; index++) {
            unsigned characterIndex = location + index;

            while (characterIndex >= cacheStart + cacheLength) {
                cacheStart += cacheLength;
                cacheLength = rangeEnd - cacheStart;
                if (cacheLength > 32)
                    cacheLength = 32;
                [self getCharacters:receiverStackBuffer
                              range:NSMakeRange(cacheStart, cacheLength)];
            }
            character = receiverStackBuffer[characterIndex - cacheStart];
            if ((mask & NSCaseInsensitiveSearch) != 0) {
                if (character > 0x7f) {
                    NSConvertToLower(character, &lowercaseCharacter, 0);
                    character = lowercaseCharacter;
                } else if ((unsigned short)(character - 'A') <= 'Z' - 'A') {
                    character += 'a' - 'A';
                }
            }
            if (character != searchCharacters[index]) {
                matches = NO;
                break;
            }
        }

        if (matches) {
            result = NSMakeRange(location, searchLength);
            break;
        }
        if ((mask & NSAnchoredSearch) != 0 ||
            location == (backwards ? firstLocation : lastLocation))
            break;
        location += step;
    }

    if (searchCharacters != searchStackBuffer)
        NSZoneFree(NSZoneFromPointer(searchCharacters), searchCharacters);
    return result;
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)aSet {
    NSRange searchRange;

    searchRange.location = 0;
    searchRange.length = [self length];
    return [self rangeOfCharacterFromSet:aSet options:0 range:searchRange];
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)aSet options:(unsigned int)mask {
    NSRange searchRange;

    searchRange.location = 0;
    searchRange.length = [self length];
    return [self rangeOfCharacterFromSet:aSet options:mask range:searchRange];
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)aSet options:(unsigned int)mask range:(NSRange)searchRange {
    unsigned length;
    unsigned firstLocation;
    unsigned lastLocation;
    unsigned location;
    unsigned stopLocation;
    int step;

    length = [self length];
    if (searchRange.location + searchRange.length > length) {
        Class stringClass;

        stringClass = [self class];
        [NSException raise:NSRangeException format:@"[%s %s]: Out of bounds",
                          stringClass->name, sel_getName(_cmd)];
    }

    if (searchRange.length == 0)
        return NSMakeRange(NSNotFound, 0);

    firstLocation = searchRange.location;
    lastLocation = searchRange.location + searchRange.length - 1;
    if ((mask & NSBackwardsSearch) != 0) {
        location = lastLocation;
        stopLocation = firstLocation;
    } else {
        location = firstLocation;
        stopLocation = lastLocation;
    }
    if ((mask & NSAnchoredSearch) != 0)
        stopLocation = location;
    step = location <= stopLocation ? 1 : -1;

    for (;;) {
        if ([aSet characterIsMember:[self characterAtIndex:location]])
            return NSMakeRange(location, 1);
        if (location == stopLocation)
            break;
        location += step;
    }

    return NSMakeRange(NSNotFound, 0);
}

- (NSRange)rangeOfComposedCharacterSequenceAtIndex:(unsigned)index {
    static BOOL firstTimeRunning = YES;
    static NSCharacterSet *nonBaseChars;
    static NSCharacterSet *baseChars;
    unsigned length;
    unsigned start;
    unsigned end;

    length = [self length];
    if (index >= length) {
        Class stringClass;

        stringClass = [self class];
        [NSException raise:NSRangeException format:@"[%s %s]: Out of bounds",
                          stringClass->name, sel_getName(_cmd)];
    }

    if (firstTimeRunning) {
        nonBaseChars = [NSCharacterSet nonBaseCharacterSet];
        baseChars = [[nonBaseChars invertedSet] retain];
        firstTimeRunning = NO;
    }

    start = index;
    while ([nonBaseChars characterIsMember:[self characterAtIndex:start]]) {
        if (start == 0)
            break;
        start--;
    }

    if (start != 0 && [self characterAtIndex:start] >= 0xDC00 &&
        [self characterAtIndex:start] <= 0xDFFF &&
        [self characterAtIndex:start - 1] >= 0xD800 &&
        [self characterAtIndex:start - 1] <= 0xDBFF)
        start--;

    end = index;
    if ([self characterAtIndex:index] >= 0xD800 &&
        [self characterAtIndex:index] <= 0xDBFF)
        end++;

    do {
        end++;
        if (length <= end)
            break;
    } while ([nonBaseChars characterIsMember:[self characterAtIndex:end]]);

    if (index < start || index > end)
        NSLog(@"NSString: rangeOfComposedCharacterSequenceAtIndex:%d returned invalid\n",
              index);
    return NSMakeRange(start, end - start);
}

- (NSString *)stringByAppendingString:(NSString *)aString {
    NSString *string;

    if ([self length] == 0)
        string = [aString copyWithZone:NULL];
    else if ([aString length] == 0)
        string = [self copyWithZone:NULL];
    else {
        string = _NSNewStringByAppendingStrings([self zone], self, aString, nil);
        return [string autorelease];
    }

    return [string autorelease];
}

- (NSString *)stringByAppendingFormat:(NSString *)format, ... {
    va_list arguments;
    NSString *formattedString;
    NSString *string;

    va_start(arguments, format);
    formattedString = [__NSPlaceholderStringFromZone(NULL) initWithFormat:format
                                                                arguments:arguments];
    va_end(arguments);

    string = _NSNewStringByAppendingStrings([self zone], self, formattedString, nil);
    [formattedString release];
    return [string autorelease];
}

- (double)doubleValue {
    double value;
    unsigned scanLocation = 0;

    if (_NSScanDoubleFromString(self, NSStringGetWhitespaceSet(), &value,
                                &scanLocation, nil))
        return value;
    return 0.0;
}

- (float)floatValue {
    double value;
    unsigned scanLocation = 0;

    if (_NSScanDoubleFromString(self, NSStringGetWhitespaceSet(), &value,
                                &scanLocation, nil))
        return (float)value;
    return 0.0;
}

- (int)intValue {
    int value;
    unsigned scanLocation = 0;

    if (_NSScanIntFromString(self, NSStringGetWhitespaceSet(), &value,
                             &scanLocation))
        return value;
    return 0;
}

- (NSArray *)componentsSeparatedByString:(NSString *)separator {
    unsigned length = [self length];
    unsigned location = 0;
    NSRange searchRange = NSMakeRange(0, length);
    NSRange separatorRange = [self rangeOfString:separator options:0 range:searchRange];
    NSRange componentRange;
    NSMutableArray *components;
    NSString *component;
    NSZone *zone;

    if (separatorRange.length == 0)
        return [NSArray arrayWithObject:self];

    length = [self length];
    components = [NSMutableArray array];
    zone = [self zone];
    do {
        componentRange = NSMakeRange(location, separatorRange.location - location);
        component = [self _newSubstringWithRange:componentRange zone:zone];
        [components addObject:component];
        [component release];

        location = NSMaxRange(separatorRange);
        searchRange = NSMakeRange(location, length - location);
        separatorRange = [self rangeOfString:separator options:0 range:searchRange];
    } while (separatorRange.length != 0);

    component = [self _newSubstringWithRange:NSMakeRange(location, length - location)
                                         zone:zone];
    [components addObject:component];
    [component release];
    return components;
}

- (NSString *)commonPrefixWithString:(NSString *)aString options:(unsigned)mask {
    unsigned length = [self length];
    unsigned prefixLength = 0;
    NSString *commonPrefix = __NSEmptyString;

    while (prefixLength < length) {
        NSRange characterRange = [self rangeOfComposedCharacterSequenceAtIndex:prefixLength];
        NSString *candidate;
        NSRange searchRange;
        NSRange matchRange;

        if (characterRange.length == 0)
            break;
        prefixLength = NSMaxRange(characterRange);
        candidate = [self substringWithRange:NSMakeRange(0, prefixLength)];
        searchRange = NSMakeRange(0, [aString length]);
        matchRange = [aString rangeOfString:candidate
                                    options:mask | NSAnchoredSearch
                                      range:searchRange];
        if (matchRange.length == 0)
            break;
        commonPrefix = candidate;
    }
    return commonPrefix;
}

- (NSString *)uppercaseString {
    return [self _caseCopyAux:NSConvertToUpper :NULL flags:0];
}

- (NSString *)lowercaseString {
    return [self _caseCopyAux:NSConvertToLower :NULL flags:0];
}

- (NSString *)capitalizedString {
    return [self _caseCopyAux:NSConvertToLower :NSConvertToTitle flags:0];
}

- (NSString *)_caseCopyAux:(NSStringCaseConversionFunction)firstConverter :(NSStringCaseConversionFunction)wordConverter flags:(unsigned)flags {
    unsigned length;
    unsigned index;
    unsigned cacheStart;
    unsigned cacheLength;
    unsigned cacheIndex;
    unsigned convertedLength;
    unsigned char afterWord;
    unichar character;
    unichar characterBuffer[32];
    unichar *buffer;
    unichar *result;
    unichar stackBuffer[256];
    NSStringCaseConversionFunction converter;
    NSCharacterSet *letters;
    NSString *string;

    length = [self length];
    letters = [NSCharacterSet letterCharacterSet];
    if (length == 0) {
        return __NSEmptyString;
    }

    if (length > 256) {
        buffer = NSZoneMalloc(NULL, 2 * length);
    } else {
        buffer = stackBuffer;
    }
    result = buffer;
    afterWord = NO;
    cacheStart = 0;
    cacheLength = length;
    if (cacheLength > 32)
        cacheLength = 32;
    cacheIndex = 0;
    [self getCharacters:characterBuffer range:NSMakeRange(cacheStart, cacheLength)];

    for (index = 0; index < length; index++) {
        character = characterBuffer[cacheIndex];
        if (wordConverter == NULL || afterWord)
            converter = firstConverter;
        else
            converter = wordConverter;

        convertedLength = (*converter)(character, result, (char)flags);
        afterWord = NO;
        if (character == '\'' || character == 700 ||
            [letters characterIsMember:character])
            afterWord = YES;
        result += convertedLength;

        cacheIndex++;
        if (cacheIndex == cacheLength && index + 1 < length) {
            cacheStart += cacheLength;
            cacheLength = length - cacheStart;
            if (cacheLength > 32)
                cacheLength = 32;
            [self getCharacters:characterBuffer
                          range:NSMakeRange(cacheStart, cacheLength)];
            cacheIndex = 0;
        }
    }

    string = _NSNewInlineUnicodeString(buffer, (unsigned)(result - buffer), [self zone]);
    if (buffer != stackBuffer)
        NSZoneFree(NULL, buffer);
    return [string autorelease];
}

- (void)getLineStart:(unsigned *)startPtr end:(unsigned *)lineEndPtr contentsEnd:(unsigned *)contentsEndPtr forRange:(NSRange)range {
    unsigned length;
    unsigned location;
    unsigned end;
    unsigned contentsEnd;
    unichar character;
    Class stringClass;

    length = [self length];
    if (range.location + range.length > length) {
        stringClass = [self class];
        [NSException raise:NSRangeException format:@"[%s %s]: Out of bounds",
                          stringClass->name, sel_getName(_cmd)];
    }

    if (startPtr != NULL) {
        location = range.location;
        if (location < length && location != 0 &&
            [self characterAtIndex:location] == '\n' &&
            [self characterAtIndex:location - 1] == '\r')
            location--;

        while (location != 0) {
            character = [self characterAtIndex:location - 1];
            if (character == '\n' || character == '\r' ||
                character == 0x2028 || character == 0x2029)
                break;
            location--;
        }
        *startPtr = location;
    }

    if (lineEndPtr != NULL || contentsEndPtr != NULL) {
        end = range.location + range.length;
        if (range.length != 0)
            end--;

        if (end < length && [self characterAtIndex:end] == '\n' && end != 0 &&
            [self characterAtIndex:end - 1] == '\r') {
            contentsEnd = end - 1;
        } else {
            while (end < length) {
                character = [self characterAtIndex:end];
                if (character == '\n' || character == '\r' ||
                    character == 0x2028 || character == 0x2029)
                    break;
                end++;
            }

            contentsEnd = end;
            if (end < length && [self characterAtIndex:end] == '\r' &&
                end + 1 < length && [self characterAtIndex:end + 1] == '\n')
                end++;
        }

        if (contentsEndPtr != NULL)
            *contentsEndPtr = contentsEnd;
        if (lineEndPtr != NULL)
            *lineEndPtr = end + (end < length ? 1 : 0);
    }
}

- (NSRange)lineRangeForRange:(NSRange)range {
    unsigned start;
    unsigned end;

    [self getLineStart:&start end:&end contentsEnd:NULL forRange:range];
    return NSMakeRange(start, end - start);
}

- (NSString *)description {
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    unsigned version;
    unsigned length;
    const char *bytes;
    id decoded;

    version = [aDecoder versionForClassName:@"NSString"];
    if (version == 0) {
        [self dealloc];
        decoded = [aDecoder decodePropertyList];
        return [decoded retain];
    }
    if (version == 1) {
        bytes = [aDecoder decodeBytesWithReturnedLength:&length];
        return [self initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    }

    [NSException raise:NSGenericException
                format:@"NSString cannot decode class version %u", version];
    return nil;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    unsigned length;
    unsigned filledLength;
    unsigned maxLength;
    char stackBuffer[100];
    char *bytes;
    NSRange range;

    length = [self length];
    maxLength = 6 * length;
    bytes = maxLength <= sizeof(stackBuffer) ? stackBuffer : NSZoneMalloc(NULL, maxLength);
    range.location = 0;
    range.length = length;

    if (![self getBytes:bytes maxLength:maxLength filledLength:&filledLength
               encoding:NSUTF8StringEncoding allowLossyConversion:NO
                  range:range remainingRange:NULL]) {
        [NSException raise:NSInternalInconsistencyException format:@"couldn't encode string"];
    }

    [aCoder encodeBytes:bytes length:filledLength];
    if (bytes != stackBuffer) {
        NSZoneFree(NSZoneFromPointer(bytes), bytes);
    }
}

- (NSString *)_stringRepresentation {
    unsigned length;
    unsigned index;
    unsigned lastSlash;
    unsigned chunkStart;
    unsigned chunkLength;
    unsigned chunkOffset;
    BOOL canUseUnquotedString;
    unichar character;
    unichar characterBuffer[32];

    length = [self length];
    if (length == 0) {
        return __NSEmptyString;
    }

    canUseUnquotedString = YES;
    lastSlash = length;
    chunkStart = 0;
    while (chunkStart < length && canUseUnquotedString) {
        chunkLength = length - chunkStart;
        if (chunkLength > 32)
            chunkLength = 32;
        [self getCharacters:characterBuffer
                      range:NSMakeRange(chunkStart, chunkLength)];
        for (chunkOffset = 0; chunkOffset < chunkLength; chunkOffset++) {
            character = characterBuffer[chunkOffset];
            if ((character >= 'a' && character <= 'z') ||
                (character >= 'A' && character <= 'Z') ||
                (character >= '0' && character <= '9') ||
                character == '_' || character == '$' || character == '.')
                continue;

            index = chunkStart + chunkOffset;
            if (character == '/') {
                if (index == lastSlash + 1)
                    canUseUnquotedString = NO;
                lastSlash = index;
            } else {
                canUseUnquotedString = NO;
            }
            if (!canUseUnquotedString)
                break;
        }
        chunkStart += chunkLength;
    }

    if (!canUseUnquotedString) {
        return [self quotedStringRepresentation];
    }
    return [[self copyWithZone:NULL] autorelease];
}

- (NSString *)displayableString {
    unsigned length;
    unsigned chunkStart;
    unsigned chunkLength;
    unsigned chunkOffset;
    unsigned outputLength;
    unsigned char *bytes;
    char displayCharacter;
    unichar character;
    unichar characterBuffer[32];
    NSString *string;
    static const char hexadecimalDigits[] = "0123456789abcdef";

    length = [self length];
    chunkStart = 0;
    while (chunkStart < length) {
        chunkLength = length - chunkStart;
        if (chunkLength > 32)
            chunkLength = 32;
        [self getCharacters:characterBuffer
                      range:NSMakeRange(chunkStart, chunkLength)];
        for (chunkOffset = 0; chunkOffset < chunkLength; chunkOffset++) {
            if (_NSStringCharacterForCStringEncoding(characterBuffer[chunkOffset]) == 0)
                break;
        }
        if (chunkOffset < chunkLength)
            break;
        chunkStart += chunkLength;
    }
    if (chunkStart == length) {
        return self;
    }

    bytes = NSZoneMalloc(NULL, 6 * length);
    outputLength = 0;
    for (chunkStart = 0; chunkStart < length; chunkStart += chunkLength) {
        chunkLength = length - chunkStart;
        if (chunkLength > 32)
            chunkLength = 32;
        [self getCharacters:characterBuffer
                      range:NSMakeRange(chunkStart, chunkLength)];
        for (chunkOffset = 0; chunkOffset < chunkLength; chunkOffset++) {
            character = characterBuffer[chunkOffset];
            displayCharacter = _NSStringCharacterForCStringEncoding(character);
            if (displayCharacter != 0) {
                bytes[outputLength++] = displayCharacter;
            } else if (character > 0x7f) {
                bytes[outputLength++] = '\\';
                bytes[outputLength++] = 'U';
                bytes[outputLength++] = hexadecimalDigits[(character >> 12) & 0xf];
                bytes[outputLength++] = hexadecimalDigits[(character >> 8) & 0xf];
                bytes[outputLength++] = hexadecimalDigits[(character >> 4) & 0xf];
                bytes[outputLength++] = hexadecimalDigits[character & 0xf];
            } else {
                bytes[outputLength++] = '\\';
                bytes[outputLength++] = ((character >> 6) & 7) + '0';
                bytes[outputLength++] = ((character >> 3) & 7) + '0';
                bytes[outputLength++] = (character & 7) + '0';
            }
        }
    }

    bytes = NSZoneRealloc(NSZoneFromPointer(bytes), bytes, outputLength);
    string = [[NSString allocWithZone:NULL] initWithCStringNoCopy:(char *)bytes
                                                          length:outputLength
                                                    freeWhenDone:YES];
    return [string autorelease];
}

- (NSString *)quotedStringRepresentation {
    unsigned length;
    unsigned index;
    unsigned outputLength;
    unsigned chunkStart;
    unsigned chunkLength;
    unsigned char nextStepByte;
    char escapeCharacter;
    char *bytes;
    unichar character;
    unichar characterBuffer[32];
    NSString *string;
    static const char hexadecimalDigits[] = "0123456789abcdef";

    length = [self length];
    if (length == 0) {
        return __NSEmptyString;
    }

    bytes = NSZoneMalloc(NULL, 6 * length + 2);
    outputLength = 0;
    bytes[outputLength++] = '"';
    chunkStart = 0;
    chunkLength = length > 32 ? 32 : length;
    [self getCharacters:characterBuffer
                  range:NSMakeRange(chunkStart, chunkLength)];
    for (index = 0; index < length; index++) {
        if (index == chunkStart + chunkLength) {
            chunkStart += chunkLength;
            chunkLength = length - chunkStart;
            if (chunkLength > 32)
                chunkLength = 32;
            [self getCharacters:characterBuffer
                          range:NSMakeRange(chunkStart, chunkLength)];
        }
        character = characterBuffer[index - chunkStart];
        escapeCharacter = 0;

        switch (character) {
        case 7:  escapeCharacter = 'a'; break;
        case 8:  escapeCharacter = 'b'; break;
        case 9:  escapeCharacter = 't'; break;
        case 10: escapeCharacter = 'n'; break;
        case 11: escapeCharacter = 'v'; break;
        case 12: escapeCharacter = 'f'; break;
        case '"': escapeCharacter = '"'; break;
        case '\\': escapeCharacter = '\\'; break;
        default: break;
        }

        if (escapeCharacter != 0) {
            bytes[outputLength++] = '\\';
            bytes[outputLength++] = escapeCharacter;
        } else if ((unsigned short)(character - 32) <= 0x5e) {
            bytes[outputLength++] = (char)character;
        } else if (NSPrecompUnicodeToNEXTSTEP(character, &nextStepByte)) {
            bytes[outputLength++] = '\\';
            bytes[outputLength++] = ((nextStepByte >> 6) & 7) + '0';
            bytes[outputLength++] = ((nextStepByte >> 3) & 7) + '0';
            bytes[outputLength++] = (nextStepByte & 7) + '0';
        } else {
            bytes[outputLength++] = '\\';
            bytes[outputLength++] = 'U';
            bytes[outputLength++] = hexadecimalDigits[(character >> 12) & 0xf];
            bytes[outputLength++] = hexadecimalDigits[(character >> 8) & 0xf];
            bytes[outputLength++] = hexadecimalDigits[(character >> 4) & 0xf];
            bytes[outputLength++] = hexadecimalDigits[character & 0xf];
        }
    }
    bytes[outputLength++] = '"';

    bytes = NSZoneRealloc(NSZoneFromPointer(bytes), bytes, outputLength);
    string = [[NSString allocWithZone:NULL] initWithCStringNoCopy:bytes
                                                          length:outputLength
                                                    freeWhenDone:YES];
    return [string autorelease];
}

- (const char *)_fastCStringContents {
    return (const char *)0;
}

- (Class)classForCoder {
    return [NSString class];
}

- (id)replacementObjectForPortCoder:(id)coder {
    return self;
}

- (unsigned)hash {
    return NSHashString(self);
}

- (id)copyWithZone:(NSZone *)zone {
    return [[NSString allocWithZone:zone] initWithString:self];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [[NSMutableString allocWithZone:zone] initWithString:self];
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
#if defined(__ppc__) || defined(__POWERPC__)
    NSURL *url = [NSURL fileURLWithPath:path];

    return [self writeToURL:url atomically:useAuxiliaryFile];
#else
    unsigned length = [self length];
    unsigned usedLength = 0;
    unsigned multiplier = 1;
    unsigned capacity;
    unsigned filledLength;
    NSStringEncoding encoding = _NSDefaultCStringEncoding();
    NSRange range = NSMakeRange(0, length);
    char *bytes;
    BOOL result;

    if (![self getBytes:NULL maxLength:0x7ffffffe filledLength:&usedLength
                encoding:encoding allowLossyConversion:NO range:range
         remainingRange:NULL]) {
        encoding = NSUnicodeStringEncoding;
        if (![self getBytes:NULL maxLength:0x7ffffffe filledLength:&usedLength
                    encoding:encoding allowLossyConversion:NO range:range
             remainingRange:NULL])
            return NO;
        multiplier = 2;
    }

    usedLength += 4;
    capacity = multiplier * usedLength;
    bytes = NSZoneMalloc(NULL, capacity);
    [self getBytes:bytes maxLength:capacity filledLength:&filledLength
           encoding:encoding allowLossyConversion:NO range:range
    remainingRange:NULL];
    result = _NSWriteBytesToFile(path, bytes, filledLength, useAuxiliaryFile);
    NSZoneFree(NULL, bytes);
    return result;
#endif
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically { // the atomically flag is ignored if url is not of a type that can be accessed atomically
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned length = [self length];
    unsigned usedLength = 0;
    unsigned multiplier = 1;
    unsigned capacity;
    unsigned filledLength;
    NSStringEncoding encoding = _NSDefaultCStringEncoding();
    NSRange range = NSMakeRange(0, length);
    char *bytes;
    NSData *data;
    BOOL result;

    if (![self getBytes:NULL maxLength:0x7ffffffe filledLength:&usedLength
                encoding:encoding allowLossyConversion:NO range:range
         remainingRange:NULL]) {
        encoding = NSUnicodeStringEncoding;
        if (![self getBytes:NULL maxLength:0x7ffffffe filledLength:&usedLength
                    encoding:encoding allowLossyConversion:NO range:range
             remainingRange:NULL])
            return NO;
        multiplier = 2;
    }

    usedLength += 4;
    capacity = multiplier * usedLength;
    bytes = NSZoneMalloc(NULL, capacity);

    [self getBytes:bytes maxLength:capacity filledLength:&filledLength
           encoding:encoding allowLossyConversion:NO range:range
    remainingRange:NULL];
    data = [[NSData allocWithZone:NULL]
        initWithBytes:bytes length:filledLength];
    result = [data writeToURL:url atomically:atomically];

    [data release];
    return result;
#else
    if (![url isFileURL])
        return NO;
    return [self writeToFile:[url path] atomically:atomically];
#endif
}

+ (id)string {
    return [[[self allocWithZone:NULL] init] autorelease];
}

+ (id)stringWithString:(NSString *)string {
    return [[[self allocWithZone:NULL] initWithString:string] autorelease];
}

+ (id)stringWithCharacters:(const unichar *)characters length:(unsigned)length {
    return [_NSNewInlineUnicodeString(characters, length, NULL) autorelease];
}

+ (id)stringWithCString:(const char *)bytes length:(unsigned)length {
    const unsigned char *cursor = (const unsigned char *)bytes;
    unsigned remaining = length;
    BOOL isASCII = YES;

    if (_NSCStringEncoding != _NSDefaultCStringEncoding()) {
        while (remaining != 0) {
            if (*cursor++ > 0x7f) {
                isASCII = NO;
                break;
            }
            remaining--;
        }
    }

    if (isASCII)
        return [_NSNewInlineCString(bytes, length, NULL) autorelease];
    return [[[self allocWithZone:NULL]
        initWithBytes:bytes length:length encoding:_NSDefaultCStringEncoding()] autorelease];
}

+ (id)stringWithCString:(const char *)bytes {
    unsigned length = 0;
    const char *cursor;

    if (bytes == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"[%s %s]: NULL cString", ((Class)self)->name, _cmd];
        return nil;
    }

    cursor = bytes;
    while (*cursor++ != '\0')
        length++;
    return [NSString stringWithCString:bytes length:length];
}

#if defined(__ppc__) || defined(__POWERPC__)
+ (id)stringWithUTF8String:(const char *)bytes {
    unsigned length = 0;
    const char *cursor;
    id string;

    cursor = bytes;
    while (*cursor++ != '\0')
        length++;
    string = [[self allocWithZone:NULL]
        initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    return [string autorelease];
}
#endif

+ (id)stringWithFormat:(NSString *)format, ... {
    va_list arguments;
    NSString *string;

    va_start(arguments, format);
    string = [__NSPlaceholderStringFromZone(NULL)
        initWithFormat:format locale:nil arguments:arguments];
    va_end(arguments);
    return [string autorelease];
}

+ (id)stringWithFormat:(NSString *)format locale:(NSDictionary *)locale, ... {
    va_list arguments;
    NSString *string;

    va_start(arguments, locale);
    string = [__NSPlaceholderStringFromZone(NULL)
        initWithFormat:format locale:locale arguments:arguments];
    va_end(arguments);
    return [string autorelease];
}

+ (id)stringWithContentsOfFile:(NSString *)path {
    return [[__NSPlaceholderStringFromZone(NULL) initWithContentsOfFile:path] autorelease];
}

+ (id)stringWithContentsOfURL:(NSURL *)url {
    return [[__NSPlaceholderStringFromZone(NULL) initWithContentsOfURL:url] autorelease];
}

+ (id)localizedStringWithFormat:(NSString *)format, ... {
    NSDictionary *locale;
    va_list arguments;
    NSString *string;
    NSString *placeholder;

#if defined(__ppc__) || defined(__POWERPC__)
    placeholder = __NSPlaceholderStringFromZone(NULL);
#endif
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    va_start(arguments, format);
#if !defined(__ppc__) && !defined(__POWERPC__)
    placeholder = __NSPlaceholderStringFromZone(NULL);
#endif
    string = [placeholder initWithFormat:format locale:locale arguments:arguments];
    va_end(arguments);
    return [string autorelease];
}

- (id)initWithCharactersNoCopy:(unichar *)characters length:(unsigned)length freeWhenDone:(BOOL)freeBuffer {
    NSRequestConcreteImplementation(self, _cmd, [NSString class]);
    return self;
}

- (id)initWithCharacters:(const unichar *)characters length:(unsigned)length {
    unichar *copy = length != 0
        ? NSZoneMalloc([self zone], length * sizeof(unichar)) : NULL;
    if (length != 0)
        memmove(copy, characters, length * sizeof(unichar));
    return [self initWithCharactersNoCopy:copy length:length freeWhenDone:YES];
}

- (id)initWithCStringNoCopy:(char *)bytes length:(unsigned)length freeWhenDone:(BOOL)freeBuffer {
    NSRequestConcreteImplementation(self, _cmd, [NSString class]);
    return self;
}

- (id)initWithCString:(const char *)bytes length:(unsigned)length {
    return [self initWithBytes:bytes length:length encoding:_NSDefaultCStringEncoding()];
}

- (id)initWithCString:(const char *)bytes {
    unsigned length = 0;
    const char *cursor;

    if (bytes == NULL) {
        [NSException raise:NSInvalidArgumentException format:@"NULL C string"];
        return nil;
    }

    cursor = bytes;
    while (*cursor++ != '\0')
        length++;
    return [self initWithBytes:bytes length:length encoding:_NSDefaultCStringEncoding()];
}

#if defined(__ppc__) || defined(__POWERPC__)
- (id)initWithUTF8String:(const char *)bytes {
    unsigned length = 0;
    const char *cursor;

    if (bytes == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: nil string parameter",
                    _NSMethodExceptionProem(self, _cmd)];
        return nil;
    }
    cursor = bytes;
    while (*cursor++ != '\0')
        length++;
    return [self initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
}
#endif

- (id)initWithString:(NSString *)aString {
    unsigned length = [aString length];
    unichar *copy = length != 0
        ? NSZoneMalloc([self zone], length * sizeof(unichar)) : NULL;
    if (length != 0)
        [aString getCharacters:copy range:NSMakeRange(0, length)];
    return [self initWithCharactersNoCopy:copy length:length freeWhenDone:YES];
}

- (id)initWithFormat:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    id result = [self initWithFormat:format locale:nil arguments:arguments];
    va_end(arguments);
    return result;
}

- (id)initWithFormat:(NSString *)format arguments:(va_list)argList {
    return [self initWithFormat:format locale:nil arguments:argList];
}

- (id)initWithFormat:(NSString *)format locale:(NSDictionary *)dict, ... {
    va_list arguments;
    va_start(arguments, dict);
    id result = [self initWithFormat:format locale:dict arguments:arguments];
    va_end(arguments);
    return result;
}

- (id)initWithFormat:(NSString *)format locale:(NSDictionary *)dict arguments:(va_list)argList {
    NSRequestConcreteImplementation(self, _cmd, [NSString class]);
    return self;
}

- (id)initWithData:(NSData *)data encoding:(NSStringEncoding)encoding {
    return [self initWithBytes:[data bytes] length:[data length] encoding:encoding];
}

- (id)_initWithDataOfUnknownEncoding:(NSData *)data {
    const unsigned char *bytes;
    unsigned length;
    NSStringEncoding encoding;

    length = [data length];
    bytes = [data bytes];
    if (data == nil) {
        return nil;
    }

    if (length > 1 && (length & 1) == 0 &&
        ((bytes[0] == 0xfe && bytes[1] == 0xff) ||
         (bytes[0] == 0xff && bytes[1] == 0xfe))) {
        encoding = NSUnicodeStringEncoding;
    } else {
        encoding = _NSDefaultCStringEncoding();
    }
    return [self initWithData:data encoding:encoding];
}

- (id)initWithContentsOfFile:(NSString *)path {
    NSData *data = [[NSData allocWithZone:NULL] initWithContentsOfFile:path];
    id string = [self _initWithDataOfUnknownEncoding:data];
    [data release];
    return string;
}

- (id)initWithContentsOfURL:(NSURL *)url {
    NSData *data = [[NSData allocWithZone:NULL] initWithContentsOfURL:url];
    id string = [self _initWithDataOfUnknownEncoding:data];
    [data release];
    return string;
}

@end

@implementation NSPlaceholderString

+ (id)allocWithZone:(NSZone *)zone {
    return __NSPlaceholderStringFromZone(zone);
}

- (id)init {
    return __NSEmptyString;
}

- (id)initWithCString:(const char *)bytes {
    const char *cursor;
    unsigned int length;

    cursor = bytes;
    length = 0;
    while (*cursor != '\0') {
        cursor++;
        length++;
    }
    return [self initWithCString:bytes length:length];
}

- (id)initWithCharacters:(const unichar *)characters length:(unsigned)length {
    id string;

    string = NSAllocateObject([NSUnicodeString class], 0, zoneForString);
    return [string initWithCharacters:characters length:length];
}

- (id)initWithCharactersNoCopy:(unichar *)characters length:(unsigned)length freeWhenDone:(BOOL)freeBuffer {
    id string;

    string = NSAllocateObject([NSUnicodeString class], 0, zoneForString);
    return [string initWithCharactersNoCopy:characters length:length freeWhenDone:freeBuffer];
}

- (id)initWithBytes:(const char *)bytes length:(unsigned)length encoding:(NSStringEncoding)encoding {
    NSStringConversionBuffer converted;
    id string;

    if (length == 0)
        return __NSEmptyString;
    if (!_NSConvertToASCIIorUnicode2(bytes, length, encoding, NO, &converted, zoneForString))
        return nil;
    if (converted.length == 0)
        return __NSEmptyString;

    if (converted.isCString) {
        if (!converted.allocated)
            return _NSNewInlineCString(converted.cstring, converted.length, zoneForString);
        string = NSAllocateObject([NSCString class], 0, zoneForString);
        return [string initWithCStringNoCopy:converted.cstring length:converted.length freeWhenDone:YES];
    }

    if (!converted.allocated)
        return _NSNewInlineUnicodeString(converted.characters, converted.length, zoneForString);
    string = NSAllocateObject([NSUnicodeString class], 0, zoneForString);
    return [string initWithCharactersNoCopy:converted.characters length:converted.length freeWhenDone:YES];
}

- (id)initWithCString:(const char *)bytes length:(unsigned)length {
    NSStringEncoding encoding;
    id string;

    encoding = _NSDefaultCStringEncoding();
    if (_NSStringBytesAreASCII((const unsigned char *)bytes, length))
        return _NSNewInlineCString(bytes, length, zoneForString);

    string = NSAllocateObject([NSUnicodeString class], 0, zoneForString);
    return [string initWithBytes:bytes length:length encoding:encoding];
}

- (id)initWithCStringNoCopy:(char *)bytes length:(unsigned)length freeWhenDone:(BOOL)freeBuffer {
    id string;

    if (_NSStringBytesAreASCII((const unsigned char *)bytes, length)) {
        string = NSAllocateObject([NSCString class], 0, zoneForString);
        return [string initWithCStringNoCopy:bytes length:length freeWhenDone:freeBuffer];
    }

    string = NSAllocateObject([NSUnicodeString class], 0, zoneForString);
    string = [string initWithCString:bytes length:length];
    if (freeBuffer)
        NSZoneFree(NSZoneFromPointer(bytes), bytes);
    return string;
}

- (id)initWithData:(NSData *)data encoding:(NSStringEncoding)encoding {
    const unsigned char *bytes;
    unsigned length;

    bytes = [data bytes];
    length = [data length];
    if (encoding == _NSCStringEncoding &&
        _NSStringBytesAreASCII(bytes, length))
        return _NSNewInlineCString(bytes, length, zoneForString);
    return [self initWithBytes:bytes length:length encoding:encoding];
}

- (id)initWithString:(NSString *)aString {
    Class stringClass;

    if (NSShouldRetainWithZone(aString, zoneForString)) {
        stringClass = [aString class];
        if (stringClass == [NSInlineCString class] ||
            stringClass == [NSCString class] ||
            stringClass == [NSInlineUnicodeString class] ||
            stringClass == [NSUnicodeString class])
            return [aString retain];
    }

    if ([aString fastestEncoding] == _NSCStringEncoding)
        return _NSNewInlineCStringFromString(aString, zoneForString);
    return _NSNewInlineUnicodeStringFromString(aString, zoneForString);
}

- (id)initWithFormat:(NSString *)format locale:(NSDictionary *)locale arguments:(va_list)argList {
    id string;

    string = NSAllocateObject([NSConcreteMutableString class], 0, zoneForString);
    string = [string initWithCapacity:100];
    [string setStringWithFormat:format locale:locale arguments:argList];
    return [string _copyAndRelease];
}

- (unsigned int)length {
    NSLog(@"Did you forget to nest [NSString allocWithZone:NULL] and init?");
    NSRequestConcreteImplementation(self, _cmd, [NSString class]);
    return 0;
}

- (unichar)characterAtIndex:(unsigned)index {
    NSLog(@"Did you forget to nest [NSString allocWithZone:NULL] and init?");
    NSRequestConcreteImplementation(self, _cmd, [NSString class]);
    return 0;
}

- (id)retain {
    return self;
}

- (void)release {
}

- (id)autorelease {
    return self;
}

- (unsigned)retainCount {
    return (unsigned)-1;
}

- (void)dealloc {
}

@end

@implementation NSString (NSSearchMethods)

- (void)_copyToUnicharBuffer:(unichar **)buffer saveLength:(int *)saveLength {
    unsigned length = [self length];
    unichar *characters = NULL;

    *saveLength = (int)length;
    if (length != 0) {
        characters = NSZoneMalloc(NULL, (length + 1) * sizeof(unichar));
        [self getCharacters:characters range:NSMakeRange(0, length)];
    }
    if (*buffer != NULL)
        NSZoneFree(NSZoneFromPointer(*buffer), *buffer);
    *buffer = characters;
}

- (NSString *)_stringWithSeparator:(unichar)separator atFrequency:(int)frequency {
    int length = (int)[self length];
    int outputLength;
    int index;
    int outputIndex;
    unichar *source;
    unichar *output;
    NSString *result;

    if (length == 0)
        return __NSEmptyString;
    outputLength = length + (length - 1) / frequency;
    source = NSZoneMalloc(NULL, (unsigned)length * sizeof(unichar));
    output = NSZoneMalloc(NULL, (unsigned)outputLength * sizeof(unichar));
    [self getCharacters:source range:NSMakeRange(0, length)];
    outputIndex = outputLength;
    for (index = length - 1; index >= 0; index--) {
        if (index != length - 1 && (length - 1 - index) % frequency == 0)
            output[--outputIndex] = separator;
        output[--outputIndex] = source[index];
    }
    result = [NSString stringWithCharacters:output length:outputLength];
    NSZoneFree(NSZoneFromPointer(output), output);
    NSZoneFree(NSZoneFromPointer(source), source);
    return result;
}

- (BOOL)_containsCharFromSet:(NSCharacterSet *)set {
    NSScanner *scanner = [NSScanner scannerWithString:self];
    NSString *scanned = nil;

    [scanner scanUpToCharactersFromSet:set intoString:&scanned];
    return ![scanner isAtEnd];
}

- (NSArray *)_componentsSeparatedBySet:(NSCharacterSet *)set {
    NSMutableArray *components = [NSMutableArray arrayWithCapacity:3];
    NSScanner *scanner = [NSScanner scannerWithString:self];

    [scanner setCharactersToBeSkipped:nil];
    while (![scanner isAtEnd]) {
        NSString *component = nil;

        if ([scanner scanUpToCharactersFromSet:set intoString:&component])
            [components addObject:component];
        else
            [components addObject:@""];
        if (![scanner isAtEnd])
            [scanner setScanLocation:[scanner scanLocation] + 1];
    }
    return components;
}

- (BOOL)_containsChar:(char)character {
    unsigned length = [self length];
    unsigned char byte = (unsigned char)character;
    NSString *needle = [NSString stringWithCString:(const char *)&byte
                                             length:byte != 0 ? 1 : 0];
    NSRange range = [self rangeOfString:needle options:0
                                  range:NSMakeRange(0, length)];

    return range.length != 0;
}

- (BOOL)_containsString:(NSString *)string {
    unsigned length = [self length];
    NSRange range = [self rangeOfString:string options:0
                                  range:NSMakeRange(0, length)];

    return range.length != 0;
}

@end
