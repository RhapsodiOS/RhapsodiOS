/*  NSMutableString.m
    Mutable string objects
*/

#import <Foundation/NSString.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSUserDefaults.h>
#import "NSStringRetainLock.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

@class NSCStringWithGap;
@class NSUnicodeStringWithGap;

extern NSString *__NSEmptyString;
extern Class __NSCStringWithGapClass;
extern Class __NSUnicodeStringWithGapClass;
extern NSStringEncoding _NSDefaultFileSystemEncoding(void);
extern NSStringEncoding _NSCStringEncoding;
extern NSStringEncoding _NSDefaultCStringEncoding(void);
extern id _NSMethodExceptionProem(id object, SEL selector);
extern int _NSConvertToASCIIorUnicode2(const void *bytes, unsigned length,
                                      NSStringEncoding encoding, BOOL flag,
                                      void *result, NSZone *zone);
#if defined(__ppc__) || defined(__POWERPC__)
extern int _NSvsnprintf(char *buffer, size_t size, const char *format,
                        va_list arguments);
#endif

typedef struct {
    BOOL isCString;
    BOOL allocated;
    unsigned char reserved[2];
    char *cstring;
    unichar *characters;
    unsigned length;
    unsigned char inlineStorage[1008];
} NSStringConversionBuffer;

@interface NSString (NSCheapMutableStringBytes)
- (id)initWithBytes:(const char *)bytes length:(unsigned)length
           encoding:(NSStringEncoding)encoding;
- (id)initWithFormat:(NSString *)format locale:(NSDictionary *)locale
           arguments:(va_list)arguments;
- (id)initWithCStringNoCopy:(char *)bytes length:(unsigned)length
              freeWhenDone:(BOOL)freeBuffer;
- (id)initWithCharactersNoCopy:(unichar *)characters length:(unsigned)length
                 freeWhenDone:(BOOL)freeBuffer;
- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange;
- (void)_pack;
- (const char *)_fastCStringContents;
- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone;
- (id)_setRequiredLength:(unsigned)length gapPosition:(unsigned)position
                  delete:(unsigned)deleteLength extraRoom:(BOOL)extraRoom;
- (void)_copyToGapRange:(NSRange)range fromString:(NSString *)string;
- (void)_copyToGapLength:(unsigned)length fromCString:(const char *)string;
- (void)_copyToGapLength:(unsigned)length fromCharacters:(const unichar *)characters;
@end

@interface NSCheapMutableString : NSMutableString {
@private
    void *contents;
    struct {
        unsigned isFat : 1;
        unsigned freeWhenDone : 1;
        unsigned refs : 30;
    } flags;
    unsigned numCharacters;
    void *_reserved;
}
- (void)setContentsNoCopy:(void *)newContents length:(unsigned)length
    freeWhenDone:(BOOL)freeBuffer isUnicode:(BOOL)isUnicode;
@end

@interface NSConcreteMutableString : NSMutableString
{
@private
    struct {
        unsigned refs : 8;
        unsigned contentsIsMine : 1;
        unsigned contentsIsCString : 1;
        unsigned hasExternalRefCount : 1;
        unsigned reserved : 5;
        unsigned capacity : 16;
    } _flags;
    NSString *contents;
}
- (id)initWithCapacity:(unsigned)capacity;
- (id)initWithString:(NSString *)string;
- (void)setStringWithFormat:(NSString *)format locale:(NSDictionary *)locale
                  arguments:(va_list)arguments;
- (void)_pack;
- (const char *)_fastCStringContents;
- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone;
@end

static unsigned NSConcreteMutableStringExternalCapacity(unsigned capacity) {
    if (capacity > 0x7fff)
        return (capacity << 8) - 8355840;
    return capacity;
}

typedef struct {
    char format[32];
    unsigned outputOffset;
    unsigned formatLength;
    unsigned char widthIndex;
    unsigned char widthOffset;
    unsigned char sourceLength;
    unsigned char argumentIndex;
    unsigned char precisionIndex;
    unsigned char precisionOffset;
    unsigned char argumentClass;
    unsigned char reserved;
} NSStringFormatRecord;

static unsigned NSStringFormatArgumentClass(char conversion) {
    if (conversion == '\0')
        return 0;
    if (strchr("$%*.", conversion) != NULL)
        return 7;
    if (conversion == '@')
        return 6;
    if (conversion != '\0' && strchr("eEfgG", conversion) != NULL)
        return 3;
    if (conversion == 's')
        return 2;
    if (conversion == 'p')
        return 4;
    if (conversion == 'n')
        return 5;
    if (strchr("diouxXc", conversion) != NULL)
        return 1;
    return 0;
}

static void *NSStringFormatAdvanceArgument(void *argument, unsigned argumentClass) {
    if (argumentClass == 3)
        return (char *)argument + 8;
    if (argumentClass == 1 || argumentClass == 2 || argumentClass == 4 ||
        argumentClass == 5 || argumentClass == 6)
        return (char *)argument + 4;
    return argument;
}

static unsigned NSStringFormatArgumentInteger(void *argument) {
    int value = *(int *)argument;

    if (value < 0)
        value = 0;
    if (value > 999999999)
        value = 999999999;
    return (unsigned)value;
}

static unsigned NSStringFormatWriteUnsigned(unsigned value, char *buffer) {
    char reversed[10];
    unsigned length = 0;
    unsigned index;

    do {
        reversed[length++] = '0' + value % 10;
        value /= 10;
    } while (value != 0);
    for (index = 0; index < length; index++)
        buffer[index] = reversed[length - index - 1];
    return length;
}

static void NSStringFormatResolveStars(NSStringFormatRecord *record,
                                      void **arguments) {
    char *search = record->format;
    char *star;
    char number[10];

    while ((star = strchr(search, '*')) != NULL) {
        unsigned index = star > record->format && star[-1] == '.'
            ? record->precisionIndex : record->widthIndex;
        if (index != 0 && index <= 9) {
            void *argument = arguments[index - 1];
            unsigned value;
            unsigned numberLength;
            char *argumentIndex = star + 1;

            if (*argumentIndex == '0' + index && argumentIndex[1] == '$')
                argumentIndex += 2;

            arguments[index - 1] = (char *)argument + 4;
            value = NSStringFormatArgumentInteger(argument);
            numberLength = NSStringFormatWriteUnsigned(value, number);
            memmove(star + numberLength, argumentIndex,
                    strlen(argumentIndex) + 1);
            memmove(star, number, numberLength);
            search = star + numberLength;
        } else {
            search = star + 1;
        }
    }
}

static void NSStringFormatRemoveArgumentIndex(char *format) {
    char *digit = format + 1;

    if (*digit >= '1' && *digit <= '9' && digit[1] == '$')
        memmove(digit, digit + 2, strlen(digit + 2) + 1);
}

static unsigned NSStringFormatSubstitute(NSConcreteMutableString *string,
                                         NSStringFormatRecord *record,
                                         void *argument,
                                         unsigned argumentClass,
                                         NSDictionary *locale,
                                         char **scratch,
                                         unsigned *scratchCapacity) {
    unsigned oldLength = record->sourceLength;
    unsigned newLength;
    unsigned stringLengthBefore;

    if (argumentClass == 6) {
        id object = *(id *)argument;
        NSString *description;
        if (object == nil)
            description = @"(null)";
        else if ([object respondsToSelector:@selector(descriptionWithLocale:)])
            description = [object descriptionWithLocale:locale];
        else
            description = [object description];
        [string replaceCharactersInRange:NSMakeRange(record->outputOffset,
                                                      oldLength)
                              withString:description];
        newLength = [description length];
    } else {
        int count;
        va_list formatArguments = (va_list)argument;
        if (*scratchCapacity == 0) {
            *scratchCapacity = 512;
            *scratch = NSZoneMalloc(NULL, *scratchCapacity);
        }
        for (;;) {
#if defined(__ppc__) || defined(__POWERPC__)
            count = _NSvsnprintf(*scratch, *scratchCapacity,
                                 record->format, formatArguments);
#else
            count = vsnprintf(*scratch, *scratchCapacity,
                              record->format, formatArguments);
#endif
            if ((unsigned)count < *scratchCapacity)
                break;
            *scratchCapacity *= 2;
            *scratch = NSZoneRealloc(NULL, *scratch, *scratchCapacity);
        }
        newLength = strlen(*scratch);
        stringLengthBefore = [string length];
        if (argumentClass == 3 && locale != nil) {
            BOOL localized = NO;
            unsigned index;

            for (index = 0; index < newLength; index++) {
                if ((*scratch)[index] == '.') {
                    NSString *separator = [locale objectForKey:NSDecimalSeparator];
                    if (separator != nil) {
                        NSMutableString *localizedString =
                            [[NSMutableString allocWithZone:NULL]
                                initWithCString:*scratch length:newLength];
                        NSString *decimal = [separator substringWithRange:
                            NSMakeRange(0, 1)];

                        [localizedString replaceCharactersInRange:
                            NSMakeRange(index, 1) withString:decimal];
                        [string replaceCharactersInRange:
                            NSMakeRange(record->outputOffset, oldLength)
                                             withString:localizedString];
                        [localizedString release];
                        localized = YES;
                    }
                    break;
                }
            }
            if (!localized)
                [string replaceCharactersInRange:NSMakeRange(record->outputOffset,
                                                              oldLength)
                                      withCString:*scratch length:newLength];
        } else {
            [string replaceCharactersInRange:NSMakeRange(record->outputOffset,
                                                          oldLength)
                                  withCString:*scratch length:newLength];
        }
        newLength = [string length] + oldLength - stringLengthBefore;
    }
    return newLength;
}

@implementation NSMutableString

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSMutableString class])
        return NSAllocateObject([NSConcreteMutableString class], 0, zone);
    return [super allocWithZone:zone];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)aString {
    NSRequestConcreteImplementation(self, _cmd, [NSMutableString class]);
}

- (void)replaceCharactersInRange:(NSRange)range
                  withCharacters:(const unichar *)characters
                           length:(unsigned)length {
    NSString *replacement = [[NSString allocWithZone:NULL]
        initWithCharacters:characters length:length];
    [self replaceCharactersInRange:range withString:replacement];
    [replacement release];
}

- (void)replaceCharactersInRange:(NSRange)range
                      withCString:(const char *)bytes
                            length:(unsigned)length {
    NSString *replacement = [[NSString allocWithZone:NULL]
        initWithCString:bytes length:length];
    [self replaceCharactersInRange:range withString:replacement];
    [replacement release];
}

- (void)insertString:(NSString *)aString atIndex:(unsigned)loc {
    [self replaceCharactersInRange:NSMakeRange(loc, 0) withString:aString];
}

- (void)deleteCharactersInRange:(NSRange)range {
    [self replaceCharactersInRange:range withString:@""];
}

- (void)appendString:(NSString *)aString {
    [self replaceCharactersInRange:NSMakeRange([self length], 0) withString:aString];
}

- (void)appendFormat:(NSString *)format, ... {
    va_list arguments;
    NSString *appendedString;

    va_start(arguments, format);
    appendedString = [[NSString allocWithZone:NULL]
        initWithFormat:format locale:nil arguments:arguments];
    va_end(arguments);
    [self replaceCharactersInRange:NSMakeRange([self length], 0)
                        withString:appendedString];
    [appendedString release];
}

- (void)setString:(NSString *)aString {
    [self replaceCharactersInRange:NSMakeRange(0, [self length]) withString:aString];
}

+ (id)stringWithCapacity:(unsigned)capacity {
    NSConcreteMutableString *string = [NSConcreteMutableString allocWithZone:NULL];
    return [[string initWithCapacity:capacity] autorelease];
}

+ (id)stringWithContentsOfFile:(NSString *)path {
    NSConcreteMutableString *string = [NSConcreteMutableString allocWithZone:NULL];
    return [[string initWithContentsOfFile:path] autorelease];
}

+ (id)stringWithCString:(const char *)bytes length:(unsigned)length {
    NSConcreteMutableString *string = [NSConcreteMutableString allocWithZone:NULL];
    return [[string initWithCString:bytes length:length] autorelease];
}

+ (id)stringWithCString:(const char *)bytes {
    NSConcreteMutableString *string = [NSConcreteMutableString allocWithZone:NULL];
    return [[string initWithCString:bytes] autorelease];
}

+ (id)stringWithCharacters:(const unichar *)characters length:(unsigned)length {
    NSConcreteMutableString *string = [NSConcreteMutableString allocWithZone:NULL];
    return [[string initWithCharacters:characters length:length] autorelease];
}

+ (id)stringWithFormat:(NSString *)format, ... {
    va_list arguments;
    NSConcreteMutableString *string = [NSConcreteMutableString allocWithZone:NULL];

    va_start(arguments, format);
    string = [string initWithFormat:format locale:nil arguments:arguments];
    va_end(arguments);
    return [string autorelease];
}

+ (id)localizedStringWithFormat:(NSString *)format, ... {
    NSDictionary *locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    va_list arguments;
    NSConcreteMutableString *string = [NSConcreteMutableString allocWithZone:NULL];

    va_start(arguments, format);
    string = [string initWithFormat:format locale:locale arguments:arguments];
    va_end(arguments);
    return [string autorelease];
}

- (Class)classForCoder {
    return [NSMutableString class];
}

- (id)initWithCoder:(NSCoder *)coder {
    unsigned version = [coder versionForClassName:@"NSMutableString"];

    if (version == 0)
        return [self initWithString:[coder decodePropertyList]];
    if (version == 1)
        return [super initWithCoder:coder];

    [NSException raise:NSGenericException
                format:@"NSMutableString cannot decode class version %u", version];
    return nil;
}

- (id)initWithCapacity:(unsigned)capacity {
    NSRequestConcreteImplementation(self, _cmd, [NSMutableString class]);
    return self;
}

@end

@implementation NSConcreteMutableString

- (id)initWithCapacity:(unsigned)initialCapacity {
    unsigned internalCapacity = initialCapacity;

    contents = __NSEmptyString;
    if (internalCapacity > 0x7fff) {
        internalCapacity = ((internalCapacity - 32513) >> 8) + 0x8000;
        if (internalCapacity > 0xffff)
            internalCapacity = 0xffff;
    }
    _flags.capacity = internalCapacity;
    _flags.contentsIsMine = 0;
    _flags.contentsIsCString = 1;
    return self;
}

- (id)init {
    return [self initWithCapacity:32];
}

- (id)initWithFormat:(NSString *)format locale:(NSDictionary *)locale
           arguments:(va_list)arguments {
    self = [self initWithCapacity:100];
    if (self != nil)
        [self setStringWithFormat:format locale:locale arguments:arguments];
    return self;
}

- (void)setStringWithFormat:(NSString *)format locale:(NSDictionary *)locale
                  arguments:(va_list)arguments {
    NSStringFormatRecord records[9];
    void *argumentPointers[9];
    unsigned char argumentClasses[9];
    unichar chunk[32];
    char *scratch = NULL;
    unsigned scratchCapacity = 0;
    unsigned oldLength;
    unsigned formatLength;
    unsigned chunkStart;
    unsigned chunkLength = 0;
    unsigned chunkIndex = 0;
    unsigned index = 0;
    unsigned recordCount = 0;
    unsigned outputOffset = 0;
    int outputOffsetDelta = 0;
    unsigned maxArgumentIndex = 0;
    BOOL positional = NO;
    BOOL sequentialSeen = NO;
    void *nextArgument = (void *)arguments;
    unichar character;

    oldLength = [self length];
    [self replaceCharactersInRange:NSMakeRange(0, oldLength)
                        withString:format];
    formatLength = [format length];
    for (index = 0; index < 9; index++) {
        argumentPointers[index] = NULL;
        argumentClasses[index] = 1;
    }
    index = 0;
    chunkStart = 0;
    while (index < formatLength) {
        if (chunkIndex >= chunkLength) {
            chunkStart = index;
            chunkLength = formatLength - chunkStart;
            if (chunkLength > 32)
                chunkLength = 32;
            [format getCharacters:chunk range:NSMakeRange(chunkStart, chunkLength)];
            chunkIndex = 0;
        }
        character = chunk[chunkIndex++];
        if (character != '%') {
            outputOffset++;
            index++;
            continue;
        }

        {
            NSStringFormatRecord *record;
            char token[32];
            unsigned tokenLength = 0;
            unsigned sourceStart = index;
            unsigned conversionClass;
            unsigned positionalIndex = 0;
            unsigned valueArgumentIndex = 0;
            unsigned valueStart;
            unsigned digits;
            char conversion;
            void *sequentialArgument;
            unsigned char precisionPhase = 0;
            unsigned char hasWidthStar = 0;
            unsigned char hasPrecisionStar = 0;

            if (positional && recordCount == 9)
                break;
            record = positional ? &records[recordCount] : &records[0];
            memset(record, 0, sizeof(*record));
            sequentialArgument = nextArgument;
            token[tokenLength++] = '%';
            index++;
            while (index < formatLength) {
                if (chunkIndex >= chunkLength) {
                    chunkStart = index;
                    chunkLength = formatLength - chunkStart;
                    if (chunkLength > 32)
                        chunkLength = 32;
                    [format getCharacters:chunk
                                    range:NSMakeRange(chunkStart, chunkLength)];
                    chunkIndex = 0;
                }
                character = chunk[chunkIndex];
                if (character > 0x7f || tokenLength >= sizeof(token) - 1)
                    break;
                token[tokenLength++] = (char)character;
                chunkIndex++;
                index++;
                if (character == '.')
                    precisionPhase = 1;
                else if (character == '*') {
                    if (precisionPhase)
                        hasPrecisionStar = 1;
                    else
                        hasWidthStar = 1;
                }
                if (character == '$') {
                    unsigned char previous = (unsigned char)token[tokenLength - 2];
                    unsigned char beforePrevious = tokenLength > 2
                        ? (unsigned char)token[tokenLength - 3] : 0;
                    if (!sequentialSeen &&
                        previous >= '1' && previous <= '9' &&
                        beforePrevious == '*') {
                        positionalIndex = previous - '0';
                        if (tokenLength > 3 && token[tokenLength - 4] == '.') {
                            record->precisionIndex = positionalIndex;
                            record->precisionOffset = tokenLength - 4;
                        } else {
                            record->widthIndex = positionalIndex;
                            record->widthOffset = tokenLength - 3;
                        }
                        tokenLength -= 2;
                    } else if (!sequentialSeen &&
                               previous >= '1' && previous <= '9' &&
                               beforePrevious == '%' && tokenLength == 3) {
                        positionalIndex = previous - '0';
                        valueArgumentIndex = positionalIndex;
                        if (recordCount == 0)
                            positional = YES;
                        tokenLength -= 2;
                    }
                }
                if (character != '\0' &&
                    strchr("diouxXeEfgGcspn@%", (char)character) != NULL)
                    break;
            }
            conversion = token[tokenLength - 1];
            token[tokenLength] = '\0';
            conversionClass = NSStringFormatArgumentClass(conversion);
            record->outputOffset = (unsigned)((int)outputOffset +
                                               outputOffsetDelta);
            record->sourceLength = index - sourceStart;
            record->argumentIndex = valueArgumentIndex;
            record->argumentClass = conversionClass;
            memcpy(record->format, token, tokenLength + 1);
            record->formatLength = tokenLength;
            recordCount++;
            if (valueArgumentIndex != 0) {
                unsigned slot = valueArgumentIndex - 1;
                if (slot < 9) {
                    argumentClasses[slot] = conversionClass;
                    if (slot + 1 > maxArgumentIndex)
                        maxArgumentIndex = slot + 1;
                }
            }
            if (record->widthIndex != 0 && record->widthIndex <= 9) {
                argumentClasses[record->widthIndex - 1] = 1;
                if (record->widthIndex > maxArgumentIndex)
                    maxArgumentIndex = record->widthIndex;
            }
            if (record->precisionIndex != 0 && record->precisionIndex <= 9) {
                argumentClasses[record->precisionIndex - 1] = 1;
                if (record->precisionIndex > maxArgumentIndex)
                    maxArgumentIndex = record->precisionIndex;
            }
            valueStart = 1;
            while (valueStart < tokenLength &&
                   token[valueStart] >= '0' && token[valueStart] <= '9')
                valueStart++;
            if (!sequentialSeen && valueStart == 2 &&
                token[1] >= '1' && token[1] <= '9' &&
                token[valueStart] == '$') {
                valueArgumentIndex = token[1] - '0';
                record->argumentIndex = valueArgumentIndex;
                if (recordCount == 1)
                    positional = YES;
                if (valueArgumentIndex != 0 && valueArgumentIndex <= 9) {
                    argumentClasses[valueArgumentIndex - 1] = conversionClass;
                    if (valueArgumentIndex > maxArgumentIndex)
                        maxArgumentIndex = valueArgumentIndex;
                }
            }
            valueStart = 0;
            while (valueStart < tokenLength) {
                if (token[valueStart] == '*') {
                    unsigned starIndex = valueStart + 1;
                    digits = 0;
                    positionalIndex = 0;
                    while (starIndex < tokenLength && token[starIndex] >= '0' &&
                           token[starIndex] <= '9') {
                        positionalIndex = positionalIndex * 10 +
                                          token[starIndex++] - '0';
                        digits++;
                    }
                    if (!sequentialSeen && digits != 0 &&
                        starIndex < tokenLength &&
                        token[starIndex] == '$' && positionalIndex <= 9) {
                        if (token[valueStart - 1] == '.') {
                            record->precisionIndex = positionalIndex;
                            record->precisionOffset = valueStart;
                        } else {
                            record->widthIndex = positionalIndex;
                            record->widthOffset = valueStart;
                        }
                        if (positionalIndex != 0) {
                            argumentClasses[positionalIndex - 1] = 1;
                            if (positionalIndex > maxArgumentIndex)
                                maxArgumentIndex = positionalIndex;
                        }
                    }
                }
                valueStart++;
            }
            if (!positional) {
                unsigned starCount = hasWidthStar + hasPrecisionStar;
                unsigned newLength;
                sequentialSeen = YES;
                newLength = NSStringFormatSubstitute(self, record,
                    sequentialArgument, conversionClass,
                    locale, &scratch, &scratchCapacity);
                nextArgument = (char *)nextArgument + starCount * 4;
                nextArgument = NSStringFormatAdvanceArgument(nextArgument,
                                                              conversionClass);
                outputOffsetDelta += (int)newLength -
                                     (int)record->sourceLength;
            }
            outputOffset += record->sourceLength;
        }
    }

    if (positional) {
        unsigned argumentIndex;
        for (argumentIndex = 0; argumentIndex < maxArgumentIndex; argumentIndex++) {
            argumentPointers[argumentIndex] = nextArgument;
            nextArgument = NSStringFormatAdvanceArgument(
                nextArgument, argumentClasses[argumentIndex]);
        }
        {
        int offsetDelta = 0;
        for (index = 0; index < recordCount; index++) {
            NSStringFormatRecord *record = &records[index];
            unsigned newLength;
            unsigned originalLength = record->sourceLength;
            void *valueArgument;
            NSStringFormatResolveStars(record, argumentPointers);
            NSStringFormatRemoveArgumentIndex(record->format);
            valueArgument = record->argumentIndex == 0
                ? argumentPointers[0]
                : record->argumentIndex <= 9
                    ? argumentPointers[record->argumentIndex - 1]
                    : argumentPointers[0];
            record->outputOffset = (unsigned)((int)record->outputOffset + offsetDelta);
            newLength = NSStringFormatSubstitute(self, record, valueArgument,
                record->argumentClass, locale, &scratch, &scratchCapacity);
            offsetDelta += (int)newLength - (int)originalLength;
        }
        }
    }
    if (scratch != NULL)
        NSZoneFree(NULL, scratch);
}

- (id)initWithCStringNoCopy:(char *)bytes length:(unsigned)length
              freeWhenDone:(BOOL)freeBuffer {
    BOOL canKeepCString = (_NSCStringEncoding == _NSDefaultCStringEncoding());
    unsigned index;

    if (!canKeepCString) {
        canKeepCString = YES;
        for (index = 0; index < length; index++) {
            if ((unsigned char)bytes[index] > 0x7f) {
                canKeepCString = NO;
                break;
            }
        }
    }
    if (canKeepCString) {
        contents = [[NSCStringWithGap allocWithZone:NSZoneFromPointer(self)]
            initWithCStringNoCopy:bytes length:length freeWhenDone:freeBuffer];
        _flags.capacity = 32;
        _flags.contentsIsMine = YES;
        _flags.contentsIsCString = YES;
        return self;
    }
    self = [self initWithBytes:bytes length:length
                      encoding:_NSDefaultCStringEncoding()];
    if (freeBuffer && bytes != NULL)
        NSZoneFree(NSZoneFromPointer(bytes), bytes);
    return self;
}

- (id)initWithCharactersNoCopy:(unichar *)characters length:(unsigned)length
                 freeWhenDone:(BOOL)freeBuffer {
    contents = [[NSUnicodeStringWithGap allocWithZone:NSZoneFromPointer(self)]
        initWithCharactersNoCopy:characters length:length freeWhenDone:freeBuffer];
    _flags.capacity = 32;
    _flags.contentsIsMine = YES;
    _flags.contentsIsCString = NO;
    return self;
}

- (id)initWithBytes:(const char *)bytes length:(unsigned)length
           encoding:(NSStringEncoding)encoding {
    NSStringConversionBuffer converted;
    NSZone *zone = NSZoneFromPointer(self);
    void *storage;

    if (!_NSConvertToASCIIorUnicode2(bytes, length, encoding, NO,
                                     &converted, zone)) {
        [self release];
        return nil;
    }
    _flags.capacity = 32;
    _flags.contentsIsMine = YES;
    if (converted.isCString) {
        _flags.contentsIsCString = YES;
        storage = converted.cstring;
        if (!converted.allocated) {
            storage = NSZoneMalloc(zone, converted.length);
            if (converted.length != 0)
                memmove(storage, converted.cstring, converted.length);
        }
        contents = [[NSCStringWithGap allocWithZone:zone]
            initWithCStringNoCopy:(char *)storage length:converted.length
                     freeWhenDone:YES];
    } else {
        _flags.contentsIsCString = NO;
        storage = converted.characters;
        if (!converted.allocated) {
            storage = NSZoneMalloc(zone, converted.length * sizeof(unichar));
            if (converted.length != 0)
                memmove(storage, converted.characters,
                        converted.length * sizeof(unichar));
        }
        contents = [[NSUnicodeStringWithGap allocWithZone:zone]
            initWithCharactersNoCopy:(unichar *)storage length:converted.length
                       freeWhenDone:YES];
    }
    return self;
}

- (id)initWithString:(NSString *)string {
    Class gapClass;
    contents = [string copyWithZone:NSZoneFromPointer(self)];
    _flags.capacity = 32;
    _flags.contentsIsCString = ([contents _fastCStringContents] != NULL);
    gapClass = _flags.contentsIsCString
        ? __NSCStringWithGapClass : __NSUnicodeStringWithGapClass;
    _flags.contentsIsMine = ([contents class] == gapClass);
    return self;
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    unsigned oldLength = [contents length];
    unsigned replacementLength = [string length];
    unsigned newLength;
    BOOL useCString;
    BOOL releaseReplacement = NO;
    NSString *oldContents = contents;
    NSString *replacement = string;
    Class gapClass;
    id gap;

    if (range.location > oldLength || range.length > oldLength - range.location) {
        [NSException raise:NSRangeException
                    format:@"%@: replacement range is beyond bounds",
                           NSStringFromSelector(_cmd)];
        return;
    }
    if (range.location == 0 && range.length == oldLength
        && !_flags.contentsIsMine) {
        contents = [string copyWithZone:NSZoneFromPointer(self)];
        [oldContents release];
        _flags.contentsIsCString = ([contents _fastCStringContents] != NULL);
        gapClass = _flags.contentsIsCString
            ? __NSCStringWithGapClass : __NSUnicodeStringWithGapClass;
        _flags.contentsIsMine = ([contents class] == gapClass);
        return;
    }
    newLength = oldLength - range.length + replacementLength;
    if (string == self || string == oldContents) {
        replacement = [string copyWithZone:NSZoneFromPointer(self)];
        releaseReplacement = YES;
        replacementLength = [replacement length];
    }
    useCString = (range.length == oldLength || _flags.contentsIsCString)
        && (replacementLength == 0 || [replacement _fastCStringContents] != NULL);

    if (_flags.contentsIsMine
        && (!_flags.contentsIsCString || useCString)) {
        gap = [oldContents _setRequiredLength:newLength
                                  gapPosition:range.location
                                       delete:range.length
                                    extraRoom:YES];
        contents = gap;
        if (replacementLength != 0)
            [gap _copyToGapRange:NSMakeRange(0, replacementLength)
                      fromString:replacement];
        if (releaseReplacement)
            [replacement release];
        return;
    }

    gapClass = useCString ? NSCStringWithGap : NSUnicodeStringWithGap;
    gap = [[gapClass allocWithZone:NSZoneFromPointer(self)]
            initWithCapacity:NSConcreteMutableStringExternalCapacity(
                _flags.capacity)];
    gap = [gap _setRequiredLength:newLength gapPosition:0
                           delete:0 extraRoom:YES];
    [gap _copyToGapRange:NSMakeRange(0, range.location) fromString:oldContents];
    if (replacementLength != 0)
        [gap _copyToGapRange:NSMakeRange(0, replacementLength) fromString:replacement];
    if (NSMaxRange(range) < oldLength)
        [gap _copyToGapRange:NSMakeRange(NSMaxRange(range),
                            oldLength - NSMaxRange(range)) fromString:oldContents];

    [oldContents release];
    contents = gap;
    _flags.contentsIsMine = YES;
    _flags.contentsIsCString = useCString;
    if (releaseReplacement)
        [replacement release];
}

- (void)replaceCharactersInRange:(NSRange)range
                 withCharacters:(const unichar *)characters
                          length:(unsigned)replacementLength {
    unsigned oldLength = [contents length];
    unsigned newLength;
    NSString *oldContents = contents;
    Class gapClass;
    id gap;

    if (range.location > oldLength || range.length > oldLength - range.location) {
        [NSException raise:NSRangeException
                    format:@"%@: replacement range is beyond bounds",
                           NSStringFromSelector(_cmd)];
        return;
    }
    newLength = oldLength - range.length + replacementLength;
    if (_flags.contentsIsMine && !_flags.contentsIsCString) {
        gap = [oldContents _setRequiredLength:newLength
                                  gapPosition:range.location
                                       delete:range.length
                                    extraRoom:YES];
        contents = gap;
        if (replacementLength != 0)
            [gap _copyToGapLength:replacementLength fromCharacters:characters];
        return;
    }

    gapClass = NSUnicodeStringWithGap;
    gap = [[gapClass allocWithZone:NSZoneFromPointer(self)]
            initWithCapacity:NSConcreteMutableStringExternalCapacity(
                _flags.capacity)];
    gap = [gap _setRequiredLength:newLength gapPosition:0 delete:0 extraRoom:YES];
    [gap _copyToGapRange:NSMakeRange(0, range.location) fromString:oldContents];
    if (replacementLength != 0)
        [gap _copyToGapLength:replacementLength fromCharacters:characters];
    if (NSMaxRange(range) < oldLength)
        [gap _copyToGapRange:NSMakeRange(NSMaxRange(range),
                            oldLength - NSMaxRange(range)) fromString:oldContents];
    [oldContents release];
    contents = gap;
    _flags.contentsIsMine = YES;
    _flags.contentsIsCString = NO;
}

- (void)replaceCharactersInRange:(NSRange)range
                    withCString:(const char *)bytes
                          length:(unsigned)length {
    unsigned index;
    unsigned oldLength;
    unsigned newLength;
    NSString *oldContents;
    BOOL useCString;
    Class gapClass;
    id gap;
    BOOL isCString = (_NSCStringEncoding == _NSDefaultCStringEncoding());

    if (!isCString) {
        isCString = YES;
        for (index = 0; index < length; index++) {
            if ((unsigned char)bytes[index] > 0x7f) {
                isCString = NO;
                break;
            }
        }
    }

    if (isCString) {
        oldLength = [contents length];
        oldContents = contents;
        if (range.location > oldLength
            || range.location + range.length > oldLength) {
            [NSException raise:NSRangeException
                        format:@"%@: replacement range is beyond bounds",
                               NSStringFromSelector(_cmd)];
            return;
        }
        newLength = oldLength - range.length + length;
        if (_flags.contentsIsMine) {
            gap = [oldContents _setRequiredLength:newLength
                                      gapPosition:range.location
                                           delete:range.length
                                        extraRoom:YES];
            contents = gap;
            if (length != 0)
                [gap _copyToGapLength:length fromCString:bytes];
            return;
        }

        useCString = (range.length == oldLength || _flags.contentsIsCString);
        gapClass = useCString ? NSCStringWithGap : NSUnicodeStringWithGap;
        gap = [[gapClass allocWithZone:NSZoneFromPointer(self)]
                initWithCapacity:NSConcreteMutableStringExternalCapacity(
                    _flags.capacity)];
        gap = [gap _setRequiredLength:newLength gapPosition:0 delete:0
                           extraRoom:YES];
        [gap _copyToGapRange:NSMakeRange(0, range.location)
                  fromString:oldContents];
        if (length != 0)
            [gap _copyToGapLength:length fromCString:bytes];
        if (NSMaxRange(range) < oldLength)
            [gap _copyToGapRange:NSMakeRange(NSMaxRange(range),
                               oldLength - NSMaxRange(range))
                      fromString:oldContents];
        [oldContents release];
        contents = gap;
        _flags.contentsIsMine = YES;
        _flags.contentsIsCString = useCString;
    } else {
        NSStringConversionBuffer converted;
        if (!_NSConvertToASCIIorUnicode2(bytes, length,
                _NSDefaultFileSystemEncoding(), YES, &converted, NULL)) {
            [NSException raise:NSCharacterConversionException
                        format:@"%@: Bad cString",
                               _NSMethodExceptionProem(self, _cmd)];
        }
        if (converted.isCString) {
            [NSException raise:NSInternalInconsistencyException
                        format:@"%@: Didn't get Unicode",
                               _NSMethodExceptionProem(self, _cmd)];
        }
        [self replaceCharactersInRange:range
                        withCharacters:converted.characters
                                 length:converted.length];
        if (converted.allocated)
            NSZoneFree(NULL, converted.characters);
    }
}

- (unsigned)length {
    return [contents length];
}

- (unsigned)cStringLength {
    return [contents cStringLength];
}

- (NSStringEncoding)smallestEncoding {
    return [contents smallestEncoding];
}

- (NSStringEncoding)fastestEncoding {
    return [contents fastestEncoding];
}

- (unichar)characterAtIndex:(unsigned)index {
    return [contents characterAtIndex:index];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    [contents getCharacters:buffer range:range];
}

- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    return [contents getBytes:buffer maxLength:maxLength filledLength:usedLength
                     encoding:encoding allowLossyConversion:allowLossy
                        range:range remainingRange:remainingRange];
}

- (const char *)_fastCStringContents {
    if (!_flags.contentsIsCString)
        return NULL;
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents _fastCStringContents];
}

- (id)copyWithZone:(NSZone *)zone {
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents copyWithZone:zone];
}

- (NSString *)stringByAppendingString:(NSString *)string {
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents stringByAppendingString:string];
}

- (unsigned)hash {
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents hash];
}

- (BOOL)isEqualToString:(NSString *)string {
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents isEqualToString:string];
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set options:(unsigned)options
    range:(NSRange)range {
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents rangeOfCharacterFromSet:set options:options range:range];
}

- (NSRange)rangeOfString:(NSString *)string options:(unsigned)options
    range:(NSRange)range {
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents rangeOfString:string options:options range:range];
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)options
    range:(NSRange)range {
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents compare:string options:options range:range];
}

- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone {
    if (_flags.contentsIsMine)
        [contents _pack];
    return [contents _newSubstringWithRange:range zone:zone];
}

- (void)dealloc {
    [contents release];
    [super dealloc];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [[NSMutableString allocWithZone:zone] initWithString:contents];
}

- (id)_copyAndRelease {
    BOOL contentsIsMine = _flags.contentsIsMine;
    unsigned length = [contents length];
    id copy = [contents copyWithZone:NULL];

    [self release];
    if (contentsIsMine)
        return [copy _setRequiredLength:length gapPosition:length
                                 delete:0 extraRoom:NO];
    return copy;
}

- (id)retain {
    BOOL locked = NSStringRetainLockAcquire();

    if (_flags.refs == 0xff) {
        _flags.refs = 0;
        if (_flags.hasExternalRefCount)
            NSIncrementExtraRefCount(self);
        _flags.hasExternalRefCount = YES;
    } else {
        _flags.refs++;
    }
    NSStringRetainLockRelease(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    BOOL extraCountWasZero;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSStringRetainLockAcquire();
    if (_flags.refs != 0) {
        _flags.refs--;
        NSStringRetainLockRelease(locked);
        return;
    }
    if (_flags.hasExternalRefCount) {
        extraCountWasZero = NSDecrementExtraRefCountWasZero(self);
        _flags.hasExternalRefCount = !extraCountWasZero;
        _flags.refs = 0xff;
        NSStringRetainLockRelease(locked);
    } else {
        NSStringRetainLockRelease(locked);
        [self dealloc];
    }
}

- (unsigned)retainCount {
    unsigned count = _flags.refs + 1;
    if (_flags.hasExternalRefCount)
        count += (NSExtraRefCount(self) << 8) + 256;
    return count;
}

@end

static void NSCheapMutableStringFree(void *contents) {
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSZoneFreeEvent, contents, 0, 0, 0);
    free(contents);
}

@implementation NSCheapMutableString

- (void)setContentsNoCopy:(void *)newContents length:(unsigned)length
    freeWhenDone:(BOOL)freeBuffer isUnicode:(BOOL)isUnicode {
    if (flags.freeWhenDone)
        NSCheapMutableStringFree(contents);
    contents = newContents;
    flags.isFat = isUnicode & 1;
    numCharacters = length;
    (void)freeBuffer;
}

- (unsigned)length {
    return numCharacters;
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    const unsigned char *bytes = (const unsigned char *)contents;
    unsigned index;

    if (flags.isFat) {
        memmove(buffer, (const unichar *)contents + range.location,
                range.length * sizeof(unichar));
    } else {
        for (index = 0; index < range.length; index++)
            buffer[index] = bytes[range.location + index];
    }
}

- (unichar)characterAtIndex:(unsigned)index {
    if (flags.isFat)
        return ((const unichar *)contents)[index];
    return ((const unsigned char *)contents)[index];
}

- (const char *)cString {
    if (!flags.isFat)
        return (const char *)contents;
    return [super cString];
}

- (const char *)lossyCString {
    if (!flags.isFat)
        return (const char *)contents;
    return [super lossyCString];
}

- (unsigned)cStringLength {
    if (!flags.isFat)
        return numCharacters;
    return [super cStringLength];
}

- (NSStringEncoding)fastestEncoding {
    if (flags.isFat)
        return NSUnicodeStringEncoding;
    return [NSString defaultCStringEncoding];
}

- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    unsigned length;
    unsigned index;

    if (flags.isFat || encoding != [NSString defaultCStringEncoding])
        return [super getBytes:buffer maxLength:maxLength filledLength:usedLength
                      encoding:encoding allowLossyConversion:allowLossy
                         range:range remainingRange:remainingRange];

    length = range.length < maxLength ? range.length : maxLength;
    if (buffer != NULL) {
        for (index = 0; index < length; index++)
            buffer[index] = ((const char *)contents)[range.location + index];
    }
    if (usedLength != NULL)
        *usedLength = length;
    if (remainingRange != NULL) {
        remainingRange->location = range.location + length;
        remainingRange->length = range.length - length;
    }
    return YES;
}

- (void)dealloc {
    if (flags.freeWhenDone)
        NSCheapMutableStringFree(contents);
    [super dealloc];
}

@end

@implementation NSMutableString (NSCharacterSetMethods)

- (void)_replaceFirstAppearanceOfString:(NSString *)string
                            withString:(NSString *)replacement {
    unsigned length = [self length];
    NSRange range = [self rangeOfString:string options:0
                                  range:NSMakeRange(0, length)];

    if (range.length != 0)
        [self replaceCharactersInRange:range withString:replacement];
}

- (void)_replaceLastAppearanceOfString:(NSString *)string
                           withString:(NSString *)replacement {
    unsigned length = [self length];
    NSRange range = [self rangeOfString:string options:NSBackwardsSearch
                                  range:NSMakeRange(0, length)];

    if (range.length != 0)
        [self replaceCharactersInRange:range withString:replacement];
}

- (void)_replaceAllAppearancesOfString:(NSString *)string
                           withString:(NSString *)replacement {
    NSString *marker = @"M*A*G*I*C";
    NSRange range;
    unsigned length;

    for (;;) {
        length = [self length];
        range = [self rangeOfString:string options:0
                              range:NSMakeRange(0, length)];
        if (range.length == 0)
            break;
        [self replaceCharactersInRange:range withString:marker];
    }
    for (;;) {
        length = [self length];
        range = [self rangeOfString:marker options:0
                              range:NSMakeRange(0, length)];
        if (range.length == 0)
            break;
        [self replaceCharactersInRange:range withString:replacement];
    }
}

- (void)_deleteAllCharactersFromSet:(NSCharacterSet *)set {
    NSRange range;
    unsigned length;

    for (;;) {
        length = [self length];
        range = [self rangeOfCharacterFromSet:set options:0
                                        range:NSMakeRange(0, length)];
        if (range.length == 0)
            break;
        [self replaceCharactersInRange:range withString:__NSEmptyString];
    }
}

@end
