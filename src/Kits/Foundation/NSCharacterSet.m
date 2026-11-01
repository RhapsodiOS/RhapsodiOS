/*	NSCharacterSet.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#import <stdlib.h>
#import <string.h>

extern int _NSFileAccessibleForMode(NSString *path, int mode);

NSString *_NSFoundationResourceDirectory(void) {
    return @"/System/Library/Frameworks/Foundation.framework/Resources";
}

static int warnAboutLoading(void) {
    static BOOL warned = NO;

    if (!warned) {
        warned = YES;
        NSLog(@"Unable to load extended character set(s); using builtin.\n");
    }
    return 0;
}

typedef struct _NSCharacterSetSet {
    unsigned int type;
    unsigned int masks[4];
    unsigned int numSingles;
    unsigned int numRanges;
    unsigned int singleMin;
    unsigned int singleMax;
    unsigned int values[1];
} NSCharacterSetSet;

static NSCharacterSetSet *
NSCharacterSetSetCopyFromZone(NSCharacterSetSet *set, NSZone *zone)
{
    NSCharacterSetSet *copy;
    unsigned index;
    unsigned valueCount;
    unsigned size;

    size = 40 + 4 * set->numSingles + 8 * set->numRanges;
    copy = NSZoneMalloc(zone, size);
    copy->type = set->type;
    for (index = 0; index < 4; index++)
        copy->masks[index] = set->masks[index];
    copy->numSingles = set->numSingles;
    copy->numRanges = set->numRanges;
    copy->singleMin = set->singleMin;
    copy->singleMax = set->singleMax;

    valueCount = set->numSingles + 2 * set->numRanges;
    for (index = 0; index < valueCount; index++)
        copy->values[index] = set->values[index];
    return copy;
}

@interface NSMutableCharacterSet (NSCharacterSetPrivateCreation)
- (id)initWithCharactersInString:(NSString *)aString;
- (id)initWithBitmapRepresentation:(NSData *)aData;
@end

@interface NSConcreteMutableCharacterSet : NSMutableCharacterSet {
    NSCharacterSetSet *set;
    unsigned char *bits;
    NSData *data;
    BOOL isMutable;
}

+ (id)characterSetWithRange:(NSRange)aRange;
+ (id)characterSetWithCharactersInString:(NSString *)aString;
+ (id)characterSetWithName:(NSString *)aName;
+ (id)_findDictOrBitmapSetNamed:(NSString *)aName;
+ (id)_readAndRetainFileNamed:(NSString *)aName makeCompact:(BOOL)compact;
- (id)_initWithSet:(NSCharacterSetSet *)aSet;

- (id)init;
- (id)initWithRange:(NSRange)aRange;
- (id)initWithCharactersInString:(NSString *)aString;
- (id)initWithBitmapRepresentation:(NSData *)aData;
- (id)initWithContentsOfFile:(NSString *)path;
- (NSData *)bitmapRepresentation;
- (id)mutableCopyWithZone:(NSZone *)zone;
- (void)makeCharacterSetFast;
- (void)makeCharacterSetCompact;
- (BOOL)isCompact;
- (void)freeBitsAndReleaseDataIfNecessary;
- (void)_makeSelfMutable;
- (void)addCharactersInRange:(NSRange)aRange;
- (void)removeCharactersInRange:(NSRange)aRange;
- (void)removeCharactersInString:(NSString *)aString;
- (void)formUnionWithCharacterSet:(NSCharacterSet *)otherSet;
- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)otherSet;
- (void)invert;
- (BOOL)isMutable;
- (void)makeImmutable;
- (unsigned)count;
- (BOOL)isEmpty;
- (NSCharacterSet *)invertedSet;

@end

@interface NSImmutableRangeCharacterSet : NSCharacterSet {
    unsigned short low;
    unsigned short high;
}

+ (id)characterSetWithRange:(NSRange)aRange;

@end

@interface NSImmutableStringCharacterSet : NSCharacterSet {
    unichar buffer[64];
    unsigned short numChars;
}

+ (id)characterSetWithCharactersInString:(NSString *)aString;
+ (id)_immutableStringCharacterSetWithArray:(NSArray *)characters;

@end

@interface NSInvertedCharacterSet : NSCharacterSet {
    NSCharacterSet *realset;
}

- (id)init;
- (id)initWithCharacterSet:(NSCharacterSet *)aSet;

@end

@interface NSBuiltinCharacterSet : NSCharacterSet {
    int offset;
    NSCharacterSet *expandedset;
}

+ (id)_setWithOffset:(int)anOffset;
+ (id)controlCharacterSet;
+ (id)whitespaceCharacterSet;
+ (id)whitespaceAndNewlineCharacterSet;
+ (id)decimalDigitCharacterSet;
+ (id)letterCharacterSet;
+ (id)lowercaseLetterCharacterSet;
+ (id)uppercaseLetterCharacterSet;
+ (id)nonBaseCharacterSet;
+ (id)alphanumericCharacterSet;
+ (id)decomposableCharacterSet;
+ (id)illegalCharacterSet;
+ (id)punctuationCharacterSet;

- (id)initWithOffset:(int)anOffset;
- (NSCharacterSet *)expandSetWithOffset:(int)anOffset;
- (BOOL)characterIsMember:(unichar)aCharacter;
- (NSData *)bitmapRepresentation;
- (BOOL)isEmpty;
- (BOOL)isEqual:(id)anObject;
- (id)mutableCopyWithZone:(NSZone *)zone;
- (id)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
- (void)release;
- (unsigned)retainCount;
- (id)retain;
- (id)autorelease;
- (void)dealloc;

@end

@interface NSExpandedBuiltinCharacterSet : NSBuiltinCharacterSet
+ (id)controlCharacterSet;
+ (id)whitespaceCharacterSet;
+ (id)whitespaceAndNewlineCharacterSet;
+ (id)decimalDigitCharacterSet;
+ (id)letterCharacterSet;
+ (id)lowercaseLetterCharacterSet;
+ (id)uppercaseLetterCharacterSet;
+ (id)alphanumericCharacterSet;
+ (id)nonBaseCharacterSet;
+ (id)decomposableCharacterSet;
+ (id)illegalCharacterSet;
+ (id)punctuationCharacterSet;
- (BOOL)characterIsMember:(unichar)aCharacter;
- (NSData *)bitmapRepresentation;
- (BOOL)isEqual:(id)anObject;
- (NSCharacterSet *)invertedSet;
@end

static void NSCharacterSetCheckMutableOperation(
    NSConcreteMutableCharacterSet *characterSet, SEL selector) {
    if (characterSet->isMutable != 0) {
        NSLog(@"NSConcreteMutableCharacterSet: attempted mutation of immutable instance\n");
        [NSException raise:NSInvalidArgumentException
                    format:@"%s %s: Illegal operation on this class or instance",
         characterSet->isa->name, selector];
    }
}

static int chcompar(const void *left, const void *right) {
    return *(const unichar *)left - *(const unichar *)right;
}

static NSBuiltinCharacterSet *builtinCharacterSets[12];

static const unsigned char builtinCharacterSetTables[6][32] = {
    { 0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0x03,0xFE,0xFF,0xFF,0x47,0xFF,0xFF,0xFF,0x07,
      0x00,0x00,0x00,0x00,0x00,0x85,0x3C,0x77,0xFF,0xFF,0x7F,0xFF,0xFF,0xFF,0x7F,0xFF },
    { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFE,0xFF,0xFF,0x47,0xFF,0xFF,0xFF,0x07,
      0x00,0x00,0x00,0x00,0x00,0x85,0x30,0x05,0xFF,0xFF,0x7F,0xFF,0xFF,0xFF,0x7F,0xFF },
    { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFE,0xFF,0xFF,0x07,
      0x00,0x00,0x00,0x00,0x00,0x04,0x20,0x04,0x00,0x00,0x00,0x80,0xFF,0xFF,0x7F,0xFF },
    { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFE,0xFF,0xFF,0x07,0x00,0x00,0x00,0x00,
      0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0xFF,0x7F,0x7F,0x00,0x00,0x00,0x00 },
    { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
      0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xBF,0xFF,0x7E,0x3E,0xBF,0xFF,0x7E,0xBE },
    { 0x00,0x00,0x00,0x00,0xA6,0xF3,0x00,0x8C,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x28,
      0x00,0x00,0x00,0x00,0x02,0x28,0x80,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 }
};

static NSMutableDictionary *namedCharacterSets;
NSLock *_NSCharacterSetLock;

static BOOL NSBuiltinCharacterIsMember(int offset, unichar character) {
    unsigned table;

    switch (offset) {
        case 0:
            return character <= 0x1F || (character >= 0x7F && character <= 0x9F);
        case 1:
            return character == 9 || character == 32 || character == 160;
        case 2:
            return character == 9 || character == 10 || character == 32 || character == 160;
        case 3:
            return character >= '0' && character <= '9';
        case 4: table = 1; break;
        case 5: table = 2; break;
        case 6: table = 3; break;
        case 7: table = 0; break;
        case 9: table = 4; break;
        case 11: table = 5; break;
        default:
            return NO;
    }
    return (builtinCharacterSetTables[table][character >> 3] &
            (1 << (character & 7))) != 0;
}

static unsigned NSCharacterSetParseInteger(NSString *string) {
    unsigned index = 0;
    unsigned value = 0;
    unsigned radix = 10;

    while ([string characterAtIndex:index] == ' ')
        index++;
    if ([string hasPrefix:@"0x"]) {
        radix = 16;
        index += [@"0x" length];
    }
    while (index < [string length]) {
        unichar character = [string characterAtIndex:index];
        unsigned digit;

        if (character >= '0' && character <= '9')
            digit = character - '0';
#if defined(__ppc__) || defined(__POWERPC__)
        else if (character == 'a' || character == 'b')
#else
        else if (character >= 'a' && character <= 'f')
#endif
            digit = character - 'a' + 10;
        else if (character >= 'A' && character <= 'F')
            digit = character - 'A' + 10;
        else
            break;
        value = value * radix + digit;
        index++;
    }
    return value;
}

static NSCharacterSetSet *NSCharacterSetSetFromBitmap(const unsigned char *bits) {
    NSCharacterSetSet *set;
    unsigned numSingles = 0;
    unsigned numRanges = 0;
    unsigned index;
    unsigned singlesIndex = 0;
    unsigned rangesIndex;
    unsigned size;

    for (index = 0; index < 0x10000;) {
        unsigned start;
        unsigned end;

        if ((bits[index >> 3] & (1 << (index & 7))) == 0) {
            index++;
            continue;
        }
        start = index;
        end = index;
        while (end < 0xFFFF &&
               (bits[(end + 1) >> 3] & (1 << ((end + 1) & 7))) != 0)
            end++;
        if (start == end)
            numSingles++;
        else
            numRanges++;
        index = end + 1;
    }

    size = 40 + 4 * numSingles + 8 * numRanges;
    set = NSZoneMalloc(NULL, size);
    memset(set, 0, size);
    set->type = 1;
    set->numSingles = numSingles;
    set->numRanges = numRanges;
    set->singleMin = 0x1FFFF;
    set->singleMax = 0;
    rangesIndex = 9 + numSingles;

    for (index = 0; index < 0x10000;) {
        unsigned start;
        unsigned end;

        if ((bits[index >> 3] & (1 << (index & 7))) == 0) {
            index++;
            continue;
        }
        start = index;
        end = index;
        while (end < 0xFFFF &&
               (bits[(end + 1) >> 3] & (1 << ((end + 1) & 7))) != 0)
            end++;
        if (start == end) {
            set->values[singlesIndex++] = start;
            if (start < set->singleMin)
                set->singleMin = start;
            if (start > set->singleMax)
                set->singleMax = start;
        } else {
            set->values[rangesIndex++] = start;
            set->values[rangesIndex++] = end;
        }
        while (start <= end) {
            unsigned plane = (start >> 15) + 1;
            unsigned chunk = (start & 0x7FFF) >> 10;
            set->masks[plane - 1] |= 1U << chunk;
            start++;
        }
        index = end + 1;
    }
    return set;
}

static BOOL NSCharacterSetSetContainsCharacter(NSCharacterSetSet *set, unsigned character) {
    unsigned low;
    unsigned high;
    unsigned plane = character >> 15;
    unsigned chunk = (character & 0x7FFF) >> 10;

    if (set->type != 1 || (set->masks[plane] & (1U << chunk)) == 0)
        return NO;

    if (character >= set->singleMin && character <= set->singleMax) {
        if (set->numSingles > 9) {
            low = 0;
            high = set->numSingles;
            while (low < high) {
                unsigned middle = low + (high - low) / 2;
                unsigned value = set->values[middle];

                if (value == character)
                    return YES;
                if (value < character)
                    low = middle + 1;
                else
                    high = middle;
            }
        } else {
            for (low = 0; low < set->numSingles; low++) {
                if (set->values[low] == character)
                    return YES;
            }
        }
    }

    if (set->numRanges > 9) {
        low = 0;
        high = set->numRanges;
        while (low < high) {
            unsigned middle = low + (high - low) / 2;
            unsigned *range = &set->values[set->numSingles + middle * 2];

            if (character < range[0])
                high = middle;
            else if (character > range[1])
                low = middle + 1;
            else
                return YES;
        }
    } else {
        for (low = 0; low < set->numRanges; low++) {
            unsigned *range = &set->values[set->numSingles + low * 2];
            if (character >= range[0] && character <= range[1])
                return YES;
        }
    }
    return NO;
}

static unsigned NSCharacterSetSetCount(NSCharacterSetSet *set) {
    unsigned count = 0;
    unsigned index;

    count = set->numSingles;
    for (index = 0; index < set->numRanges; index++) {
        unsigned *range = &set->values[set->numSingles + index * 2];
        count += range[1] - range[0] + 1;
    }
    return count;
}

static int _countMembersOfBitmap(const unsigned char *bitmap,
                                 unsigned length) {
    unsigned count = 0;
    unsigned index;

    if (bitmap == NULL)
        return 0;
    for (index = 0; index < length; index++) {
        unsigned char byte = bitmap[index];

        while (byte != 0) {
            count++;
            byte &= byte - 1;
        }
    }
    return count;
}

static void NSCharacterSetSetCopyToBitmap(NSCharacterSetSet *set, unsigned char *bits) {
    unsigned index;

    if (set == NULL)
        return;
    for (index = 0; index < set->numSingles; index++) {
        unsigned character = (unsigned short)set->values[index];
        bits[character >> 3] |= 1 << (character & 7);
    }
    for (index = 0; index < set->numRanges; index++) {
        unsigned *range = &set->values[set->numSingles + index * 2];
        unsigned short character = (unsigned short)range[0];

        for (; character <= range[1]; character++)
            bits[character >> 3] |= 1 << (character & 7);
    }
}

static unsigned char *NSMakeSetBitmapFromSet(NSCharacterSetSet *set) {
    unsigned char *bits;

    bits = NSZoneMalloc(NULL, 0x2000);
    memset(bits, 0, 0x2000);
    NSCharacterSetSetCopyToBitmap(set, bits);
    return bits;
}

static NSCharacterSetSet *NSCharacterSetSetFromDictionary(NSDictionary *dictionary) {
    NSCharacterSetSet *inputSet;
    NSArray *singles;
    NSArray *ranges;
    unsigned char *bits;
    unsigned numSingles;
    unsigned numRanges;
    unsigned index;
    unsigned count;

    if (dictionary == nil) {
        NSCharacterSetSet *emptySet = NSZoneMalloc(NULL, 0x28);

        memset(emptySet, 0, 0x28);
        emptySet->type = 1;
        emptySet->singleMin = 0xFFFF;
        return emptySet;
    }

    numSingles = NSCharacterSetParseInteger(
        [dictionary objectForKey:@"nsingles"]);
    numRanges = NSCharacterSetParseInteger(
        [dictionary objectForKey:@"nranges"]);
    inputSet = NSZoneMalloc(NULL,
        36 + 4 * numSingles + 8 * numRanges);
    inputSet->type = 1;
    inputSet->numSingles = numSingles;
    inputSet->numRanges = numRanges;
    inputSet->singleMin = NSCharacterSetParseInteger(
        [dictionary objectForKey:@"singmin"]);
    inputSet->singleMax = NSCharacterSetParseInteger(
        [dictionary objectForKey:@"singmax"]);

    singles = [dictionary objectForKey:@"singles"];
    if (singles != nil) {
        count = [singles count];
        for (index = 0; index < count; index++)
            inputSet->values[index] = NSCharacterSetParseInteger(
                [singles objectAtIndex:index]);
    }
    ranges = [dictionary objectForKey:@"ranges"];
    if (ranges != nil) {
        count = [ranges count];
        for (index = 0; index < count; index++)
            inputSet->values[numSingles + index] = NSCharacterSetParseInteger(
                [ranges objectAtIndex:index]);
    }
    memset(inputSet->masks, 0, sizeof(inputSet->masks));

    bits = NSMakeSetBitmapFromSet(inputSet);
    NSZoneFree(NULL, inputSet);
    inputSet = NSCharacterSetSetFromBitmap(bits);
    NSZoneFree(NULL, bits);
    return inputSet;
}

@implementation NSImmutableStringCharacterSet

+ (id)_immutableStringCharacterSetWithArray:(NSArray *)characters {
    NSImmutableStringCharacterSet *characterSet;
    unsigned index;
    unsigned length;

    characterSet = [NSImmutableStringCharacterSet allocWithZone:NULL];
    for (index = 0; index < 64; index++)
        characterSet->buffer[index] = 0;
    length = [characters count];
    if (length > 64)
        length = 64;
    for (index = 0; index < length; index++)
        characterSet->buffer[index] = NSCharacterSetParseInteger([characters objectAtIndex:index]);
    characterSet->numChars = length;
    qsort(characterSet->buffer, length, sizeof(unichar), chcompar);
    return [characterSet autorelease];
}

+ (id)characterSetWithCharactersInString:(NSString *)aString {
    NSImmutableStringCharacterSet *characterSet;
    unsigned index;

    characterSet = [NSImmutableStringCharacterSet allocWithZone:NULL];
    for (index = 0; index < 64; index++)
        characterSet->buffer[index] = 0;
    characterSet->numChars = [aString length];
    [aString getCharacters:characterSet->buffer
                     range:NSMakeRange(0, characterSet->numChars)];
    qsort(characterSet->buffer, characterSet->numChars, sizeof(unichar), chcompar);
    return [characterSet autorelease];
}

- (BOOL)characterIsMember:(unichar)aCharacter {
    unsigned index;

    for (index = 0; index < numChars; index++) {
        if (buffer[index] == aCharacter)
            return YES;
    }
    return NO;
}

- (unsigned)count {
    return numChars;
}

- (BOOL)isEmpty {
    return numChars == 0;
}

- (BOOL)isEqual:(id)anObject {
    unsigned index;

    if (anObject == self)
        return YES;
    if ([anObject class] != self->isa)
        return [super isEqual:anObject];
    if (numChars != ((NSImmutableStringCharacterSet *)anObject)->numChars)
        return NO;
    for (index = 0; index < numChars; index++) {
        if (buffer[index] != ((NSImmutableStringCharacterSet *)anObject)->buffer[index])
            return NO;
    }
    return YES;
}

- (NSData *)bitmapRepresentation {
    NSString *characters = [NSString stringWithCharacters:buffer length:numChars];
    NSCharacterSet *characterSet =
        [NSConcreteMutableCharacterSet characterSetWithCharactersInString:characters];
    NSData *bitmap;
    NSData *result;

#if defined(__ppc__) || defined(__POWERPC__)
    result = [NSData allocWithZone:NULL];
    bitmap = [characterSet bitmapRepresentation];
    result = [result initWithData:bitmap];
#else
    bitmap = [characterSet bitmapRepresentation];
    result = [[NSData allocWithZone:NULL] initWithData:bitmap];
#endif

    return [result autorelease];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    NSString *characters = [NSString stringWithCharacters:buffer
                                                   length:numChars];

    [coder encodePropertyList:characters];
}

- (id)initWithCoder:(NSCoder *)coder {
    NSString *characters = [coder decodePropertyList];

    numChars = (unsigned short)[characters length];
    [characters getCharacters:buffer range:NSMakeRange(0, numChars)];
    return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSMutableCharacterSet *characterSet;
    NSString *characters;

    characters = [NSString stringWithCharacters:buffer length:numChars];
    characterSet = [NSConcreteMutableCharacterSet
                    characterSetWithCharactersInString:characters];
    return [characterSet retain];
}

@end

@implementation NSInvertedCharacterSet

- (id)init {
    [super dealloc];
    return nil;
}

- (id)initWithCharacterSet:(NSCharacterSet *)aSet {
    [super init];
    if ([aSet isMutable]) {
        realset = [aSet copyWithZone:NULL];
        [realset makeImmutable];
    } else {
        realset = [aSet retain];
    }
    return self;
}

- (void)dealloc {
    [realset autorelease];
    [super dealloc];
}

- (unsigned)count {
    return 0x10000 - [realset count];
}

- (BOOL)isEmpty {
    return ![realset isEmpty];
}

- (BOOL)characterIsMember:(unichar)aCharacter {
    return ![realset characterIsMember:aCharacter];
}

- (NSCharacterSet *)invertedSet {
    return realset;
}

- (NSData *)bitmapRepresentation {
    NSMutableData *data;
    unsigned char *bits;
    unsigned index;

#if defined(__ppc__) || defined(__POWERPC__)
    data = [[NSMutableData allocWithZone:NULL] initWithData:[realset bitmapRepresentation]];
#else
    NSData *bitmap = [realset bitmapRepresentation];
    data = [[NSMutableData allocWithZone:NULL] initWithData:bitmap];
#endif
    bits = [data mutableBytes];
    for (index = 0; index < 0x2000; index++)
        bits[index] = ~bits[index];
    return [data autorelease];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSMutableCharacterSet *set;

    set = [realset mutableCopyWithZone:zone];
    [set makeImmutable];
    return set;
}

- (BOOL)isEqual:(id)anObject {
    if (anObject == self)
        return YES;
    if ([anObject class] == self->isa &&
        ((NSInvertedCharacterSet *)anObject)->realset == realset)
        return YES;
    return [super isEqual:anObject];
}

@end

@implementation NSConcreteMutableCharacterSet

+ (id)characterSetWithBitmapRepresentation:(NSData *)bitmap {
    NSConcreteMutableCharacterSet *characterSet;

    characterSet = [[NSConcreteMutableCharacterSet allocWithZone:NULL]
                    initWithBitmapRepresentation:bitmap];
    return [characterSet autorelease];
}

+ (id)_findDictOrBitmapSetNamed:(NSString *)aName {
    NSString *resourceDirectory;
    NSString *characterSetsDirectory;
    NSString *basePath;
    NSString *catalogPath;
    NSString *path;
    NSDictionary *catalog;
    NSDictionary *definition;
    NSConcreteMutableCharacterSet *characterSet;
    NSCharacterSetSet *set;

    resourceDirectory = _NSFoundationResourceDirectory();
    characterSetsDirectory = [resourceDirectory stringByAppendingPathComponent:@"CharacterSets"];
    basePath = [characterSetsDirectory stringByAppendingPathComponent:aName];

    path = [basePath stringByAppendingPathExtension:@"dict"];
    if (_NSFileAccessibleForMode(path, 4))
        return [[NSMutableCharacterSet allocWithZone:NULL]
                initWithContentsOfFile:path];

    path = [basePath stringByAppendingPathExtension:@"bitmap"];
    if (_NSFileAccessibleForMode(path, 4))
        return [[NSMutableCharacterSet allocWithZone:NULL]
                initWithContentsOfFile:path];

    catalogPath = [characterSetsDirectory stringByAppendingPathComponent:@"SystemCharacterSetAux.dict"];
    if (!_NSFileAccessibleForMode(catalogPath, 4)) {
        warnAboutLoading();
        return nil;
    }
    catalog = [[NSDictionary allocWithZone:NULL] initWithContentsOfFile:catalogPath];
    if (catalog == nil) {
        warnAboutLoading();
        return nil;
    }
    definition = [catalog objectForKey:aName];
    if (definition == nil)
        warnAboutLoading();
    set = NSCharacterSetSetFromDictionary(definition);
    [catalog release];
    characterSet = [NSMutableCharacterSet allocWithZone:NULL];
    return [characterSet _initWithSet:set];
}

+ (id)characterSetWithName:(NSString *)aName {
    NSCharacterSet *characterSet;

    if (_NSCharacterSetLock != nil)
        [_NSCharacterSetLock lock];
    characterSet = [namedCharacterSets objectForKey:aName];
    if (characterSet == nil) {
        characterSet = [NSConcreteMutableCharacterSet
            _findDictOrBitmapSetNamed:aName];
        if (characterSet != nil) {
            if (namedCharacterSets == nil)
                namedCharacterSets = [[NSMutableDictionary allocWithZone:NULL]
                    initWithCapacity:16];
            [namedCharacterSets setObject:characterSet forKey:aName];
        }
    }
    if (_NSCharacterSetLock != nil)
        [_NSCharacterSetLock unlock];
    return characterSet;
}

+ (id)_readAndRetainFileNamed:(NSString *)aName makeCompact:(BOOL)compact {
    NSCharacterSet *characterSet;

    if (_NSCharacterSetLock != nil)
        [_NSCharacterSetLock lock];
    characterSet = [namedCharacterSets objectForKey:aName];
    if (_NSCharacterSetLock != nil)
        [_NSCharacterSetLock unlock];

    if (characterSet == nil) {
        characterSet = [NSConcreteMutableCharacterSet characterSetWithName:aName];
        if (characterSet != nil) {
            if (compact)
                [(NSConcreteMutableCharacterSet *)characterSet makeCharacterSetCompact];
            [characterSet makeImmutable];
        }
    }
    return characterSet;
}

+ (id)characterSetWithRange:(NSRange)aRange {
    NSConcreteMutableCharacterSet *characterSet;

    characterSet = [[NSConcreteMutableCharacterSet allocWithZone:NULL] initWithRange:aRange];
    return [characterSet autorelease];
}

+ (id)characterSetWithCharactersInString:(NSString *)aString {
    NSConcreteMutableCharacterSet *characterSet;

    characterSet = [[NSConcreteMutableCharacterSet allocWithZone:NULL]
                    initWithCharactersInString:aString];
    return [characterSet autorelease];
}

- (id)init {
    unsigned int *initialSet;

    [super init];
    bits = NULL;
    initialSet = NSZoneMalloc(NULL, 10 * sizeof(unsigned int));
    memset(initialSet, 0, 10 * sizeof(unsigned int));
    initialSet[0] = 1;
    initialSet[7] = 0xFFFF;
    set = (NSCharacterSetSet *)initialSet;
    data = nil;
    return self;
}

- (id)initWithRange:(NSRange)aRange {
    [self init];
    [self addCharactersInRange:aRange];
    return self;
}

- (id)initWithCharactersInString:(NSString *)aString {
    [self init];
    [self addCharactersInString:aString];
    return self;
}

- (id)initWithBitmapRepresentation:(NSData *)aData {
    [self init];
    data = [aData copyWithZone:NULL];
    bits = (unsigned char *)[data bytes];
    NSZoneFree(NSZoneFromPointer(set), set);
    set = NULL;
    return self;
}

- (id)initWithContentsOfFile:(NSString *)path {
    if ([path hasSuffix:@".bitmap"]) {
        NSData *bitmap = [NSData dataWithContentsOfFile:path];

        if (bitmap != nil) {
            if ([bitmap length] <= 0x1FFF) {
                bits = (unsigned char *)[bitmap bytes];
                data = [bitmap retain];
            } else {
                bits = NSZoneMalloc(NULL, 0x2000);
                memmove(bits, [bitmap bytes], 0x2000);
            }
            return self;
        }
    } else if ([path hasSuffix:@".dict"]) {
        NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:path];

        if (dictionary != nil) {
            set = NSCharacterSetSetFromDictionary(dictionary);
            return self;
        }
    }
    return [self init];
}

- (id)_initWithSet:(NSCharacterSetSet *)aSet {
    [self init];
    if (set != NULL)
        NSZoneFree(NULL, set);
    set = aSet;
    return self;
}

- (void)makeCharacterSetFast {
    if (bits == NULL) {
        bits = NSMakeSetBitmapFromSet(set);
        NSZoneFree(NULL, set);
        set = NULL;
    }
}

- (void)freeBitsAndReleaseDataIfNecessary {
    if (data != nil) {
        [data autorelease];
        data = nil;
    } else {
        if (bits == NULL)
            return;
        NSZoneFree(NSZoneFromPointer(bits), bits);
    }
    bits = NULL;
}

- (void)makeCharacterSetCompact {
    if (set == NULL) {
        set = NSCharacterSetSetFromBitmap(bits);
        [self freeBitsAndReleaseDataIfNecessary];
    }
}

- (BOOL)isCompact {
    return bits != NULL;
}

- (void)_makeSelfMutable {
    if (data != nil) {
        NSZone *zone = [self zone];
        unsigned char *mutableBits = NSZoneMalloc(zone, 0x2000);

        memmove(mutableBits, [data bytes], 0x2000);
        bits = mutableBits;
        [data autorelease];
        data = nil;
    }
}

- (void)addCharactersInString:(NSString *)aString {
    unsigned length;
    unsigned index;

    NSCharacterSetCheckMutableOperation(self, _cmd);
    length = [aString length];
    if (length == 0)
        return;
    if (data != nil)
        [self _makeSelfMutable];
    if (bits == NULL)
        [self makeCharacterSetFast];
    for (index = 0; index < length; index++) {
        unsigned byteIndex = [aString characterAtIndex:index] >> 3;
        bits[byteIndex] |= 1 << ([aString characterAtIndex:index] & 7);
    }
}

- (void)addCharactersInRange:(NSRange)aRange {
    unsigned end;
    unsigned index;

    NSCharacterSetCheckMutableOperation(self, _cmd);
    if (aRange.length == 0)
        return;
    end = aRange.location + aRange.length - 1;
    if (data != nil)
        [self _makeSelfMutable];
    if (bits == NULL)
        [self makeCharacterSetFast];
    for (index = (unsigned short)aRange.location; index <= end;
         index = (unsigned short)(index + 1))
        bits[index >> 3] |= 1 << (index & 7);
}

- (void)removeCharactersInRange:(NSRange)aRange {
    unsigned end;
    unsigned index;

    NSCharacterSetCheckMutableOperation(self, _cmd);
    if (aRange.length == 0)
        return;
    end = aRange.location + aRange.length - 1;
    if (data != nil)
        [self _makeSelfMutable];
    if (bits == NULL)
        [self makeCharacterSetFast];
    for (index = (unsigned short)aRange.location; index <= end;
         index = (unsigned short)(index + 1))
        bits[index >> 3] &= ~(1 << (index & 7));
}

- (void)removeCharactersInString:(NSString *)aString {
    unsigned length;
    unsigned index;

    NSCharacterSetCheckMutableOperation(self, _cmd);
    length = [aString length];
    if (length == 0)
        return;
    if (data != nil)
        [self _makeSelfMutable];
    if (bits == NULL)
        [self makeCharacterSetFast];
    for (index = 0; index < length; index++) {
        unsigned byteIndex = [aString characterAtIndex:index] >> 3;
        bits[byteIndex] &= ~(1 << ([aString characterAtIndex:index] & 7));
    }
}

- (void)formUnionWithCharacterSet:(NSCharacterSet *)otherSet {
    const unsigned int *otherWords = NULL;
    NSData *otherBitmap;
    BOOL hasBitmap = NO;
    unsigned index;

    NSCharacterSetCheckMutableOperation(self, _cmd);
    if (data != nil)
        [self _makeSelfMutable];
    if (bits == NULL)
        [self makeCharacterSetFast];

    if (self->isa == [otherSet class]) {
        [(NSConcreteMutableCharacterSet *)otherSet makeCharacterSetFast];
        otherWords = (const unsigned int *)
            ((NSConcreteMutableCharacterSet *)otherSet)->bits;
        hasBitmap = YES;
    } else if ([otherSet respondsToSelector:@selector(bitmapRepresentation)]) {
        otherBitmap = [otherSet bitmapRepresentation];
        otherWords = (const unsigned int *)[otherBitmap bytes];
        hasBitmap = YES;
    }
    if (hasBitmap) {
        for (index = 2048; index != 0; index--)
            ((unsigned int *)bits)[index - 1] |= otherWords[index - 1];
    } else {
        for (index = 0; index < 0x10000; index++) {
            if ([otherSet characterIsMember:(unichar)index])
                bits[index >> 3] |= 1 << (index & 7);
        }
    }
}

- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)otherSet {
    const unsigned int *otherWords = NULL;
    NSData *otherBitmap;
    BOOL hasBitmap = NO;
    unsigned index;

    NSCharacterSetCheckMutableOperation(self, _cmd);
    if (data != nil)
        [self _makeSelfMutable];
    if (bits == NULL)
        [self makeCharacterSetFast];

    if (self->isa == [otherSet class]) {
        [(NSConcreteMutableCharacterSet *)otherSet makeCharacterSetFast];
        otherWords = (const unsigned int *)
            ((NSConcreteMutableCharacterSet *)otherSet)->bits;
        hasBitmap = YES;
    } else if ([otherSet respondsToSelector:@selector(bitmapRepresentation)]) {
        otherBitmap = [otherSet bitmapRepresentation];
        otherWords = (const unsigned int *)[otherBitmap bytes];
        hasBitmap = YES;
    }
    if (hasBitmap) {
        for (index = 2048; index != 0; index--)
            ((unsigned int *)bits)[index - 1] &= otherWords[index - 1];
    } else {
        for (index = 0; index < 0x10000; index++) {
            unsigned char mask = 1 << (index & 7);
            if ((bits[index >> 3] & mask) != 0 &&
                ![otherSet characterIsMember:(unichar)index])
                bits[index >> 3] &= ~(1 << (index & 7));
        }
    }
}

- (void)invert {
    unsigned index;
    unsigned int *words;

    NSCharacterSetCheckMutableOperation(self, _cmd);
    if (data != nil)
        [self freeBitsAndReleaseDataIfNecessary];
    if (bits == NULL)
        [self makeCharacterSetFast];
    words = (unsigned int *)bits;
    for (index = 2048; index != 0; index--)
        words[index - 1] = ~words[index - 1];
}

- (BOOL)isMutable {
    return isMutable;
}

- (NSString *)dump {
    if (bits != NULL)
        return [(Class)self->isa _dumpBitmapRepresentation:bits];
    return [(Class)self->isa _dumpSetRepresentation:set];
}

- (id)replacementObjectForPortCoder:(id)coder {
    if (![coder isByref] || ![self isMutable])
        return self;
    return [NSDistantObject proxyWithLocal:self connection:[coder connection]];
}

- (void)makeImmutable {
    isMutable = 0;
}

- (BOOL)characterIsMember:(unichar)aCharacter {
    if (bits == NULL)
        return NSCharacterSetSetContainsCharacter(set, aCharacter);
    return (bits[aCharacter >> 3] & (1 << (aCharacter & 7))) != 0;
}

- (NSData *)bitmapRepresentation {
    if (data == nil) {
        if (bits == NULL)
            bits = NSMakeSetBitmapFromSet(set);
        data = [[NSData dataWithBytesNoCopy:bits length:0x2000] retain];
    }
    return data;
}

- (BOOL)isEqual:(id)anObject {
    if (anObject == self)
        return YES;
    return [super isEqual:anObject];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSConcreteMutableCharacterSet *copy;

    copy = [NSMutableCharacterSet allocWithZone:zone];
    if (data != nil) {
        copy->data = [data copyWithZone:NULL];
        copy->bits = (unsigned char *)[copy->data bytes];
    } else if (bits != NULL) {
        copy->bits = NSZoneMalloc(zone, 0x2000);
        memmove(copy->bits, bits, 0x2000);
    }
    if (set != NULL)
        copy->set = NSCharacterSetSetCopyFromZone(set, zone);
    return copy;
}

- (unsigned)count {
    if (set != NULL)
        return NSCharacterSetSetCount(set);
    return _countMembersOfBitmap(bits, 0x2000);
}

- (BOOL)isEmpty {
    unsigned index;

    if (set != NULL && set->numSingles == 0 && set->numRanges == 0)
        return YES;
    if (bits != NULL) {
        for (index = 0; index < 0x2000; index++) {
            if (bits[index] != 0)
                return NO;
        }
    }
    return YES;
}

- (NSCharacterSet *)invertedSet {
    NSConcreteMutableCharacterSet *copy;

    if ([self isMutable]) {
        copy = [self mutableCopyWithZone:[self zone]];
        [copy invert];
        return [copy autorelease];
    }
    return [super invertedSet];
}

- (void)dealloc {
    if (set != NULL)
        NSZoneFree(NSZoneFromPointer(set), set);
    if (data != nil)
        [data autorelease];
    if (bits != NULL && data == nil)
        NSZoneFree(NSZoneFromPointer(bits), bits);
    [super dealloc];
}

@end

@implementation NSImmutableRangeCharacterSet

+ (id)characterSetWithRange:(NSRange)aRange {
    NSImmutableRangeCharacterSet *characterSet;

    characterSet = [NSImmutableRangeCharacterSet allocWithZone:NULL];
    if (aRange.location != NSNotFound && aRange.length != 0) {
        characterSet->low = aRange.location;
        characterSet->high = (unsigned short)(aRange.location + aRange.length);
    } else {
        characterSet->low = 0;
        characterSet->high = 0;
    }
    return [characterSet autorelease];
}

- (BOOL)characterIsMember:(unichar)aCharacter {
    return low <= aCharacter && high > aCharacter;
}

- (unsigned)count {
    return high - low;
}

- (BOOL)isEmpty {
    return high == low;
}

- (BOOL)isEqual:(id)anObject {
    if (anObject == self)
        return YES;
    if ([anObject class] == self->isa &&
        ((NSImmutableRangeCharacterSet *)anObject)->low == low &&
        ((NSImmutableRangeCharacterSet *)anObject)->high == high)
        return YES;
    return [super isEqual:anObject];
}

- (NSData *)bitmapRepresentation {
    NSData *bitmap;
    NSData *copy;

#if defined(__ppc__) || defined(__POWERPC__)
    copy = [NSData allocWithZone:NULL];
    bitmap = [[NSConcreteMutableCharacterSet
               characterSetWithRange:NSMakeRange(low, high - low)]
              bitmapRepresentation];
    copy = [copy initWithData:bitmap];
#else
    bitmap = [[NSConcreteMutableCharacterSet
               characterSetWithRange:NSMakeRange(low, high - low)]
              bitmapRepresentation];
    copy = [[NSData allocWithZone:NULL] initWithData:bitmap];
#endif
    return [copy autorelease];
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSConcreteMutableCharacterSet *copy;

    copy = [NSConcreteMutableCharacterSet
            characterSetWithRange:NSMakeRange(low, high - low)];
    return [copy retain];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeValueOfObjCType:"i" at:&low];
    [coder encodeValueOfObjCType:"i" at:&high];
}

- (id)initWithCoder:(NSCoder *)coder {
    [coder decodeValueOfObjCType:"i" at:&low];
    [coder decodeValueOfObjCType:"i" at:&high];
    return self;
}

@end

@implementation NSBuiltinCharacterSet

+ (id)_setWithOffset:(int)anOffset {
    NSBuiltinCharacterSet *characterSet;

    characterSet = builtinCharacterSets[anOffset];
    if (characterSet == nil) {
        characterSet = [[NSBuiltinCharacterSet allocWithZone:NULL]
                        initWithOffset:anOffset];
        builtinCharacterSets[anOffset] = characterSet;
    }
    return characterSet;
}

+ (id)controlCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:0]; }
+ (id)whitespaceCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:1]; }
+ (id)whitespaceAndNewlineCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:2]; }
+ (id)decimalDigitCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:3]; }
+ (id)letterCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:4]; }
+ (id)lowercaseLetterCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:5]; }
+ (id)uppercaseLetterCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:6]; }
+ (id)alphanumericCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:7]; }
+ (id)nonBaseCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:8]; }
+ (id)decomposableCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:9]; }
+ (id)illegalCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:10]; }
+ (id)punctuationCharacterSet { return [NSBuiltinCharacterSet _setWithOffset:11]; }

- (id)initWithOffset:(int)anOffset {
    [super init];
    offset = anOffset;
    expandedset = nil;
    return self;
}

- (NSCharacterSet *)expandSetWithOffset:(int)anOffset {
    NSCharacterSet *set;

    switch (anOffset) {
        case 0: set = [NSExpandedBuiltinCharacterSet controlCharacterSet]; break;
        case 1: set = [NSExpandedBuiltinCharacterSet whitespaceCharacterSet]; break;
        case 2: set = [NSExpandedBuiltinCharacterSet whitespaceAndNewlineCharacterSet]; break;
        case 3: set = [NSExpandedBuiltinCharacterSet decimalDigitCharacterSet]; break;
        case 4: set = [NSExpandedBuiltinCharacterSet letterCharacterSet]; break;
        case 5: set = [NSExpandedBuiltinCharacterSet lowercaseLetterCharacterSet]; break;
        case 6: set = [NSExpandedBuiltinCharacterSet uppercaseLetterCharacterSet]; break;
        case 7: set = [NSExpandedBuiltinCharacterSet alphanumericCharacterSet]; break;
        case 8: set = [NSExpandedBuiltinCharacterSet nonBaseCharacterSet]; break;
        case 9: set = [NSExpandedBuiltinCharacterSet decomposableCharacterSet]; break;
        case 10: set = [NSExpandedBuiltinCharacterSet illegalCharacterSet]; break;
        case 11: set = [NSExpandedBuiltinCharacterSet punctuationCharacterSet]; break;
        default:
            NSLog(@"NSExpandedBuiltinCharacterSet: illegal offset %d encountered.\n",
                  anOffset);
            [NSException raise:NSInvalidArgumentException
                        format:@"%s %s: Illegal operation on this class or instance",
             self->isa->name, _cmd];
            return self;
    }
    return set == nil ? self : set;
}

- (BOOL)characterIsMember:(unichar)aCharacter {
    NSCharacterSet *set;

    if (aCharacter <= 0xFF)
        return NSBuiltinCharacterIsMember(offset, aCharacter);
    if (aCharacter == 0xFFFF)
        return self == builtinCharacterSets[10];
    if (expandedset == nil) {
        set = [self expandSetWithOffset:offset];
        if (set != nil)
            expandedset = set;
    }
    if (expandedset == nil || expandedset == self)
        return NO;
    return [expandedset characterIsMember:aCharacter];
}

- (NSData *)bitmapRepresentation {
    NSMutableData *data;
    unsigned char *bits;
    unsigned character;
    NSCharacterSet *set;

    set = [self expandSetWithOffset:offset];
    if (set != nil && set != self)
        return [set bitmapRepresentation];
    expandedset = self;
    data = [[NSMutableData allocWithZone:NULL] init];
    [data setLength:0x2000];
    bits = [data mutableBytes];
    for (character = 0; character <= 0xFF; character++) {
        if ([self characterIsMember:(unichar)character])
            bits[character >> 3] |= 1 << (character & 7);
    }
    return [data autorelease];
}

- (BOOL)isEmpty {
    return NO;
}

- (BOOL)isEqual:(id)anObject {
    if (anObject == self)
        return YES;
    if ([anObject class] == self->isa &&
        ((NSBuiltinCharacterSet *)anObject)->offset == offset &&
        ((NSBuiltinCharacterSet *)anObject)->expandedset == expandedset)
        return YES;
    return [super isEqual:anObject];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSCharacterSet *set = [self expandSetWithOffset:offset];
    NSConcreteMutableCharacterSet *mutableSet;
    NSData *bitmap;

    if (set != nil && set != self) {
        expandedset = set;
        return [set mutableCopyWithZone:zone];
    }
#if defined(__ppc__) || defined(__POWERPC__)
    mutableSet = [NSConcreteMutableCharacterSet allocWithZone:NULL];
    bitmap = [self bitmapRepresentation];
#else
    bitmap = [self bitmapRepresentation];
    mutableSet = [NSConcreteMutableCharacterSet allocWithZone:NULL];
#endif
    return [mutableSet initWithBitmapRepresentation:bitmap];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeValueOfObjCType:"i" at:&offset];
}

- (id)initWithCoder:(NSCoder *)coder {
    [coder decodeValueOfObjCType:"i" at:&offset];
    expandedset = nil;
    return self;
}

- (void)release {
}

- (unsigned)retainCount {
    return (unsigned)-1;
}

- (id)retain {
    return self;
}

- (id)autorelease {
    return self;
}

- (void)dealloc {
    NSLog(@"*** dealloc called for %s", self->isa->name);
}

@end

static void NSCharacterSetDoesNotImplement(id characterSet, SEL selector) {
    NSLog(@"Abstract class %s does not implement method %s; it must be implemented in subclasses.",
          characterSet->isa->name, selector);
    [characterSet doesNotRecognizeSelector:selector];
}

@implementation NSExpandedBuiltinCharacterSet

+ (id)controlCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"controlCharacterSet"
                                                       makeCompact:YES];
}

+ (id)whitespaceCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"whitespaceCharacterSet"
                                                       makeCompact:YES];
}

+ (id)whitespaceAndNewlineCharacterSet {
    return [NSConcreteMutableCharacterSet
            _readAndRetainFileNamed:@"whitespaceAndNewlineCharacterSet" makeCompact:YES];
}

+ (id)decimalDigitCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"decimalDigitCharacterSet"
                                                       makeCompact:YES];
}

+ (id)letterCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"letterCharacterSet"
                                                       makeCompact:NO];
}

+ (id)lowercaseLetterCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"lowercaseLetterCharacterSet"
                                                       makeCompact:NO];
}

+ (id)uppercaseLetterCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"uppercaseLetterCharacterSet"
                                                       makeCompact:NO];
}

+ (id)alphanumericCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"alphanumericCharacterSet"
                                                       makeCompact:NO];
}

+ (id)nonBaseCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"nonBaseCharacterSet"
                                                       makeCompact:NO];
}

+ (id)decomposableCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"decomposableCharacterSet"
                                                       makeCompact:NO];
}

+ (id)illegalCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"illegalCharacterSet"
                                                       makeCompact:NO];
}

+ (id)punctuationCharacterSet {
    return [NSConcreteMutableCharacterSet _readAndRetainFileNamed:@"punctuationCharacterSet"
                                                       makeCompact:NO];
}

- (BOOL)characterIsMember:(unichar)aCharacter {
    NSCharacterSetDoesNotImplement(self, _cmd);
    return NO;
}

- (NSData *)bitmapRepresentation {
    NSCharacterSetDoesNotImplement(self, _cmd);
    return nil;
}

- (BOOL)isEqual:(id)anObject {
    NSCharacterSetDoesNotImplement(self, _cmd);
    return NO;
}

- (NSCharacterSet *)invertedSet {
    NSCharacterSetDoesNotImplement(self, _cmd);
    return nil;
}

@end

@implementation NSCharacterSet

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSCharacterSet class])
        return [NSConcreteMutableCharacterSet allocWithZone:zone];
    return [super allocWithZone:zone];
}

+ (id)characterSetWithCharactersInString:(NSString *)aString {
    if ([aString length] <= 64)
        return [NSImmutableStringCharacterSet
                characterSetWithCharactersInString:aString];
    return [[[NSConcreteMutableCharacterSet allocWithZone:NULL]
             initWithCharactersInString:aString] autorelease];
}

+ (NSString *)_dumpBitmapRepresentation:(const unsigned char *)bitmap {
    static const char header[] =
        "10 10 translate\n256 256 scale\n256 256 1 [256 0 0 -256 0 256]\n{<";
    NSMutableString *result;
    unsigned index;

    if (bitmap == NULL)
        return @"<NIL>";
    result = [[NSMutableString allocWithZone:NULL]
              initWithCString:header length:sizeof(header) - 1];
    for (index = 0; index < 0x2000; index++) {
        unsigned reversedBits = 0;
        unsigned mask = 0x80;
        unsigned outputBit = 1;
        unsigned bit;

        for (bit = 0; bit < 8; bit++) {
            if ((bitmap[index] & mask) != 0)
                reversedBits |= outputBit;
            mask >>= 1;
            outputBit <<= 1;
        }
        if ((index & 0x1f) == 0)
            [result replaceCharactersInRange:NSMakeRange([result length], 0)
                                   withString:@"\n"];
        [result appendFormat:@"%02X", (unsigned char)~reversedBits];
    }
    [result replaceCharactersInRange:NSMakeRange([result length], 0)
                           withString:@">} image\nshowpage\n"];
    return [result autorelease];
}

+ (NSString *)_dumpSetRepresentation:(NSCharacterSetSet *)set {
    NSMutableString *result;
    unsigned index;
    unsigned end;

    if (set == NULL)
        return @"<NIL>";
    result = [[NSMutableString allocWithZone:NULL]
        initWithCString:"{\n" length:2];
    [result appendFormat:@"\tnsingles = %d;\n", set->numSingles];
    [result appendFormat:@"\tnranges = %d;\n", set->numRanges];
    [result appendFormat:@"\tsingmin = %d;\n", set->singleMin];
    [result appendFormat:@"\tsingmax = %d;\n", set->singleMax];
    [result replaceCharactersInRange:NSMakeRange([result length], 0)
                           withString:@"\tsingles = ( "];
    for (index = 0; index < set->numSingles; index++) {
        if (index != 0)
            [result replaceCharactersInRange:NSMakeRange([result length], 0)
                                   withString:@", "];
        [result appendFormat:@"%d", set->values[index]];
    }
    [result replaceCharactersInRange:NSMakeRange([result length], 0)
                           withString:@" );\n"];
    [result replaceCharactersInRange:NSMakeRange([result length], 0)
                           withString:@"\tranges = ( "];
    end = set->numSingles + 2 * set->numRanges;
    for (index = set->numSingles; index < end; index++) {
        if (index != set->numSingles)
            [result replaceCharactersInRange:NSMakeRange([result length], 0)
                                   withString:@", "];
        [result appendFormat:@"%d", set->values[index]];
    }
    [result replaceCharactersInRange:NSMakeRange([result length], 0)
                           withString:@" );\n}\n"];
    return [result autorelease];
}

+ (NSCharacterSet *)controlCharacterSet {
    return [NSBuiltinCharacterSet controlCharacterSet];
}

+ (NSCharacterSet *)whitespaceCharacterSet {
    return [NSBuiltinCharacterSet whitespaceCharacterSet];
}

+ (NSCharacterSet *)whitespaceAndNewlineCharacterSet {
    return [NSBuiltinCharacterSet whitespaceAndNewlineCharacterSet];
}

+ (NSCharacterSet *)decimalDigitCharacterSet {
    return [NSBuiltinCharacterSet decimalDigitCharacterSet];
}

+ (NSCharacterSet *)letterCharacterSet {
    return [NSBuiltinCharacterSet letterCharacterSet];
}

+ (NSCharacterSet *)lowercaseLetterCharacterSet {
    return [NSBuiltinCharacterSet lowercaseLetterCharacterSet];
}

+ (NSCharacterSet *)uppercaseLetterCharacterSet {
    return [NSBuiltinCharacterSet uppercaseLetterCharacterSet];
}

+ (NSCharacterSet *)nonBaseCharacterSet {
    return [NSBuiltinCharacterSet nonBaseCharacterSet];
}

+ (NSCharacterSet *)alphanumericCharacterSet {
    return [NSBuiltinCharacterSet alphanumericCharacterSet];
}

+ (NSCharacterSet *)decomposableCharacterSet {
    return [NSBuiltinCharacterSet decomposableCharacterSet];
}

+ (NSCharacterSet *)illegalCharacterSet {
    return [NSBuiltinCharacterSet illegalCharacterSet];
}

+ (NSCharacterSet *)punctuationCharacterSet {
    return [NSBuiltinCharacterSet punctuationCharacterSet];
}

+ (NSCharacterSet *)characterSetWithRange:(NSRange)aRange {
    return [NSImmutableRangeCharacterSet characterSetWithRange:aRange];
}

+ (NSCharacterSet *)characterSetWithBitmapRepresentation:(NSData *)data {
    NSMutableCharacterSet *characterSet;

    characterSet = [[NSConcreteMutableCharacterSet allocWithZone:NULL]
                    initWithBitmapRepresentation:data];
    return [characterSet autorelease];
}

+ (NSCharacterSet *)characterSetWithContentsOfFile:(NSString *)fName {
    NSCharacterSet *characterSet;

    if ([fName hasSuffix:@".dict"]) {
        NSString *dictionaryPath;
        NSDictionary *systemSets;
        NSDictionary *definition;
        NSArray *characters;

        dictionaryPath = [[_NSFoundationResourceDirectory()
                           stringByAppendingPathComponent:@"CharacterSets"]
                          stringByAppendingPathComponent:@"SystemCharacterSetAux.dict"];
        systemSets = [NSDictionary dictionaryWithContentsOfFile:dictionaryPath];
        definition = [systemSets objectForKey:[fName stringByDeletingPathExtension]];
        if (definition == nil)
            return nil;
        characters = [definition objectForKey:@"characters"];
        if (characters != nil)
            characterSet = [NSImmutableStringCharacterSet
                            _immutableStringCharacterSetWithArray:characters];
        else {
            NSConcreteMutableCharacterSet *concrete;
            NSCharacterSetSet *set = NSCharacterSetSetFromDictionary(definition);

            concrete = [NSConcreteMutableCharacterSet allocWithZone:NULL];
            characterSet = [concrete _initWithSet:set];
            [characterSet autorelease];
        }
    } else {
        characterSet = [[NSConcreteMutableCharacterSet allocWithZone:NULL]
                        initWithContentsOfFile:fName];
        [characterSet autorelease];
    }
    if (characterSet != nil)
        [characterSet makeImmutable];
    return characterSet;
}

- (BOOL)characterIsMember:(unichar)aCharacter {
    NSCharacterSetDoesNotImplement(self, _cmd);
    return NO;
}

- (NSData *)bitmapRepresentation {
    NSMutableData *data;
    unsigned char *bits;
    unsigned int index;

#if defined(__ppc__) || defined(__POWERPC__)
    data = [[NSMutableData allocWithZone:NULL] initWithLength:0x2000];
#else
    data = [[NSMutableData allocWithZone:NULL] initWithCapacity:0x2000];
#endif
    bits = [data mutableBytes];
    memset(bits, 0, 0x2000);
    for (index = 0; index != 0xFFFF; index++) {
        if ([self characterIsMember:(unichar)index])
            bits[index >> 3] |= 1 << (index & 7);
    }
    return [data autorelease];
}

- (NSCharacterSet *)invertedSet {
    NSInvertedCharacterSet *set;

    set = [[NSInvertedCharacterSet allocWithZone:NULL] initWithCharacterSet:self];
    return [set autorelease];
}

- (BOOL)isMutable {
    return NO;
}

- (void)makeImmutable {
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSCharacterSetDoesNotImplement(self, _cmd);
    return nil;
}

- (unsigned)count {
    const unsigned char *bitmap = [[self bitmapRepresentation] bytes];

    return _countMembersOfBitmap(bitmap, 0x2000);
}

- (BOOL)isEmpty {
    NSData *bitmap = [self bitmapRepresentation];
    const unsigned char *bytes;
    int length;
    int index;

    if (bitmap == nil)
        return YES;
    bytes = [bitmap bytes];
    length = (int)[bitmap length];
    for (index = 0; index < length; index++) {
        if (bytes[index] != 0)
            return NO;
    }
    return YES;
}

- (BOOL)isEqual:(id)anObject {
    NSData *otherBitmap;
    NSData *selfBitmap;

    if (anObject == self)
        return YES;
    if (![anObject respondsToSelector:@selector(bitmapRepresentation)])
        return NO;
#if !defined(__ppc__) && !defined(__POWERPC__)
    otherBitmap = [anObject bitmapRepresentation];
    selfBitmap = [self bitmapRepresentation];
#else
    selfBitmap = [self bitmapRepresentation];
    otherBitmap = [anObject bitmapRepresentation];
#endif
    return [selfBitmap isEqual:otherBitmap];
}

- (unsigned)hash {
    return [[self bitmapRepresentation] hash];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodePropertyList:[self bitmapRepresentation]];
}

- (id)initWithCoder:(NSCoder *)coder {
    NSData *bitmap;
    NSMutableCharacterSet *characterSet;

#if defined(__ppc__) || defined(__POWERPC__)
    characterSet = [NSConcreteMutableCharacterSet allocWithZone:NULL];
    bitmap = [coder decodePropertyList];
    characterSet = [characterSet initWithBitmapRepresentation:bitmap];
#else
    bitmap = [coder decodePropertyList];
    characterSet = [[NSConcreteMutableCharacterSet allocWithZone:NULL]
        initWithBitmapRepresentation:bitmap];
#endif

    [self dealloc];
    return characterSet;
}

- (id)replacementObjectForPortCoder:(id)coder {
    if (![coder isByref] || ![self isMutable])
        return self;
    return [NSDistantObject proxyWithLocal:self connection:[coder connection]];
}

@end

@implementation NSMutableCharacterSet

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSMutableCharacterSet class])
        return [NSConcreteMutableCharacterSet allocWithZone:zone];
    return [super allocWithZone:zone];
}

+ (NSMutableCharacterSet *)characterSetWithRange:(NSRange)aRange {
    return [NSConcreteMutableCharacterSet characterSetWithRange:aRange];
}

+ (NSMutableCharacterSet *)characterSetWithCharactersInString:(NSString *)aString {
    return [NSConcreteMutableCharacterSet characterSetWithCharactersInString:aString];
}

- (BOOL)isMutable {
    return YES;
}

- (id)copyWithZone:(NSZone *)zone {
    id copy = [self mutableCopyWithZone:zone];
    [copy makeImmutable];
    return copy;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSCharacterSetDoesNotImplement(self, _cmd);
    return nil;
}

- (void)addCharactersInRange:(NSRange)aRange {
    NSCharacterSetDoesNotImplement(self, _cmd);
}

- (void)removeCharactersInRange:(NSRange)aRange {
    NSCharacterSetDoesNotImplement(self, _cmd);
}

- (void)addCharactersInString:(NSString *)aString {
    NSCharacterSetDoesNotImplement(self, _cmd);
}

- (void)removeCharactersInString:(NSString *)aString {
    NSCharacterSetDoesNotImplement(self, _cmd);
}

- (void)formUnionWithCharacterSet:(NSCharacterSet *)otherSet {
    NSCharacterSetDoesNotImplement(self, _cmd);
}

- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)otherSet {
    NSCharacterSetDoesNotImplement(self, _cmd);
}

- (void)invert {
    NSCharacterSetDoesNotImplement(self, _cmd);
}

@end
