/*  NSSimpleString.m
    Simple and owning Unicode string storage
*/

#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSCharacterSet.h>
#import "NSStringRetainLock.h"

#include <string.h>

extern NSString *__NSEmptyString;
extern void _NSGenericFree(void *ptr);
extern int _NSConvertToASCIIorUnicode2(const void *bytes, unsigned length,
                                      NSStringEncoding encoding, BOOL flag,
                                      void *result, NSZone *zone);
extern id _NSMethodExceptionProem(id object, SEL selector);

typedef struct {
    BOOL isCString;
    BOOL allocated;
    unsigned char reserved[2];
    char *cstring;
    unichar *characters;
    unsigned length;
    unsigned char inlineStorage[1008];
} NSStringConversionBuffer;

@interface NSSimpleString : NSString {
@protected
    unichar *characters;
    unsigned numCharacters;
}
- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length;
- (const unichar *)_characters;
@end

@interface NSUnicodeString : NSSimpleString {
@protected
    struct {
        unsigned refs : 8;
        unsigned freeWhenDone : 1;
        unsigned hasExternalRefCount : 1;
        unsigned reserved : 5;
        unsigned canWriteIntoBuffer : 1;
        unsigned capacity : 16;
    } _flags;
}
- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length
                 freeWhenDone:(BOOL)freeBuffer;
- (id)initWithCharacters:(const unichar *)buffer length:(unsigned)length;
@end

@interface NSInlineUnicodeString : NSString {
@protected
    struct {
        unsigned refs : 8;
        unsigned hasExternalRefCount : 1;
        unsigned : 7;
        unsigned numChars : 16;
    } _flags;
}
@end

@interface NSUnicodeSubstring : NSUnicodeString {
@protected
    NSSimpleString *_referenceString;
}
- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length
              referencedString:(NSString *)string;
- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length
                 freeWhenDone:(BOOL)freeBuffer;
@end

@interface NSUnicodeStringWithGap : NSUnicodeString {
@public
    unsigned gapBegin;
    unsigned gapEnd;
}
- (id)initWithCapacity:(unsigned)capacity;
- (id)_setRequiredLength:(unsigned)length gapPosition:(unsigned)position
                  delete:(unsigned)deleteLength extraRoom:(BOOL)extraRoom;
- (void)_copyToGapRange:(NSRange)range fromString:(NSString *)string;
- (void)_copyToGapLength:(unsigned)length fromCString:(const char *)string;
- (void)_copyToGapLength:(unsigned)length fromCharacters:(const unichar *)string;
@end

static unsigned NSUnicodeCapacityToInternal(unsigned capacity) {
    if (capacity > 0x7fff) {
        capacity = ((capacity - 32513) >> 8) + 0x8000;
        if (capacity > 0xffff)
            capacity = 0xffff;
    }
    return capacity;
}

static unsigned NSUnicodeCapacityToExternal(unsigned capacity) {
    if (capacity > 0x7fff)
        return (capacity << 8) - 8355840;
    return capacity;
}

static unsigned NSUnicodeGapPhysicalIndex(NSUnicodeStringWithGap *string,
                                          unsigned index) {
    return index < string->gapBegin ? index
                                    : index + string->gapEnd - string->gapBegin;
}

static unichar *NSInlineUnicodeCharacters(NSInlineUnicodeString *string) {
    return (unichar *)((char *)string + sizeof(NSInlineUnicodeString));
}

id _NSNewInlineUnicodeString(const unichar *characters, unsigned length,
                             NSZone *zone);
id _NSNewInlineUnicodeStringFromString(NSString *string, NSZone *zone);

unsigned NSHashCharacters(const unichar *characters, unsigned length) {
    unsigned hash = length;
    unsigned count = length > 16 ? 8 : length;
    unsigned index;

    for (index = 0; index < count; index++)
        hash += characters[index] + (hash << 8);
    if (length > 16) {
        characters += length - 8;
        for (index = 0; index < 8; index++)
            hash += characters[index] + (hash << 8);
    }
    return (hash << (length & 0x1f)) + hash;
}

int NSCompareCharacters(const unichar *left, const unichar *right,
                        unsigned leftLength, unsigned rightLength,
                        unsigned options) {
    unsigned commonLength = leftLength < rightLength ? leftLength : rightLength;
    unsigned index;

    for (index = 0; index < commonLength; index++) {
        unsigned leftCharacter = left[index];
        unsigned rightCharacter = right[index];
        if (options & NSCaseInsensitiveSearch) {
            if ((unsigned short)(leftCharacter - 'a') <= 'z' - 'a')
                leftCharacter -= 'a' - 'A';
            if ((unsigned short)(rightCharacter - 'a') <= 'z' - 'a')
                rightCharacter -= 'a' - 'A';
        }
        if (leftCharacter < rightCharacter)
            return -1;
        if (leftCharacter > rightCharacter)
            return 1;
    }
    return leftLength >= rightLength ? leftLength > rightLength : -1;
}

static BOOL NSSimpleStringEqualsString(const unichar *characters,
                                       unsigned length, NSString *string) {
    unichar buffer[32];
    unsigned offset = 0;

    if ([string length] != length)
        return NO;
    while (offset < length) {
        unsigned count = length - offset;
        if (count > 32)
            count = 32;
        [string getCharacters:buffer range:NSMakeRange(offset, count)];
        if (memcmp(characters + offset, buffer, count * sizeof(unichar)) != 0)
            return NO;
        offset += count;
    }
    return YES;
}

@implementation NSSimpleString

+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 0, zone);
}

- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length {
    characters = buffer;
    numCharacters = length;
    return self;
}

- (unsigned)length {
    return numCharacters;
}

- (unichar)characterAtIndex:(unsigned)index {
    Class stringClass;
    if (index >= numCharacters) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    return characters[index];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    Class stringClass;
    if (numCharacters < range.location + range.length) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    if (range.length != 0)
        memmove(buffer, characters + range.location,
                range.length * sizeof(unichar));
}

- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone {
    Class stringClass;

    if (numCharacters < range.location
        || numCharacters < range.location + range.length) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    if (range.length == 0)
        return __NSEmptyString;
    if (range.location == 0 && range.length == numCharacters) {
#if defined(__ppc__) || defined(__POWERPC__)
        return [self copy];
#else
        return [self retain];
#endif
    }
    if (range.length > 24)
        return [[NSUnicodeSubstring allocWithZone:zone]
            initWithCharactersNoCopy:characters + range.location
            length:range.length referencedString:self];
    return [[NSString allocWithZone:zone]
        initWithCharacters:characters + range.location length:range.length];
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)options
                         range:(NSRange)range {
    unsigned otherLength;
    unsigned leftOffset = range.location;
    unsigned rightOffset = 0;

    if ([string isKindOfClass:[NSSimpleString class]]) {
        NSSimpleString *other = (NSSimpleString *)string;
        const unichar *otherCharacters;

        otherLength = [string length];
        otherCharacters = [other _characters];
        return NSCompareCharacters(characters + leftOffset, otherCharacters,
                                   range.length, otherLength, options);
    }

    otherLength = [string length];
    for (;;) {
        unsigned leftCount = range.location + range.length - leftOffset;
        unsigned rightCount = otherLength - rightOffset;
        unichar buffer[32];
        int comparison;

        if (leftCount > 32)
            leftCount = 32;
        if (rightCount > 32)
            rightCount = 32;
        if (leftCount == 0 && rightCount == 0)
            return NSOrderedSame;
        if (rightCount != 0)
            [string getCharacters:buffer
                            range:NSMakeRange(rightOffset, rightCount)];
        comparison = NSCompareCharacters(characters + leftOffset, buffer,
                                         leftCount, rightCount, options);
        if (comparison != 0)
            return comparison;
        leftOffset += leftCount;
        rightOffset += rightCount;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    if (NSShouldRetainWithZone(self, zone))
        return [self retain];
    return [[NSString allocWithZone:zone] initWithString:self];
}

- (unsigned)hash {
    return NSHashCharacters(characters, numCharacters);
}

- (id)initWithBytes:(const char *)bytes length:(unsigned)length
           encoding:(NSStringEncoding)encoding {
    NSStringConversionBuffer converted;
    NSZone *zone = [self zone];

    if (!_NSConvertToASCIIorUnicode2(bytes, length, encoding, YES,
                                     &converted, zone)) {
        [self release];
        return nil;
    }
    if (converted.length == 0)
        return [self initWithCharactersNoCopy:NULL length:0];
    if (converted.isCString) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: Did not get Unicode",
                           _NSMethodExceptionProem(self, _cmd)];
    }
    if (converted.allocated)
        return [self initWithCharactersNoCopy:converted.characters
                                       length:converted.length
                                freeWhenDone:YES];
    {
        unsigned byteLength = converted.length * sizeof(unichar);
        unichar *copy = (unichar *)NSZoneMalloc(zone, byteLength);
        memmove(copy, converted.characters, byteLength);
        return [self initWithCharactersNoCopy:copy length:converted.length
                                freeWhenDone:YES];
    }
}

- (BOOL)isEqualToString:(NSString *)string {
    if (self == (id)string)
        return YES;
    if (string == nil)
        return NO;
    if ([string isKindOfClass:[NSSimpleString class]]) {
        NSSimpleString *other = (NSSimpleString *)string;
        return other->numCharacters == numCharacters
            && memcmp(characters, other->characters,
                      numCharacters * sizeof(unichar)) == 0;
    }
    return NSSimpleStringEqualsString(characters, numCharacters, string);
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set options:(unsigned)options
                              range:(NSRange)range {
    unsigned first;
    unsigned last;
    unsigned index;
    int step;
    Class stringClass;

    if (numCharacters < range.location + range.length) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    if (range.length == 0)
        return NSMakeRange(NSNotFound, 0);

    first = (options & NSBackwardsSearch) != 0
        ? range.location + range.length - 1 : range.location;
    last = (options & NSBackwardsSearch) != 0
        ? range.location : range.location + range.length - 1;
    if (options & NSAnchoredSearch)
        last = first;
    step = first <= last ? 1 : -1;
    index = first;
    for (;;) {
        if ([set characterIsMember:characters[index]])
            return NSMakeRange(index, 1);
        if (index == last)
            break;
        index += step;
    }
    return NSMakeRange(NSNotFound, 0);
}

- (NSString *)stringByAppendingString:(NSString *)string {
    unsigned otherLength = [string length];
    unsigned length;
    NSZone *zone;
    unichar *buffer;

    if (numCharacters == 0)
        return otherLength != 0 ? [[string copyWithZone:NULL] autorelease]
                                : __NSEmptyString;
    if (otherLength == 0)
        return [[self copyWithZone:NULL] autorelease];

    zone = [self zone];
    length = numCharacters + otherLength;
    buffer = (unichar *)NSZoneMalloc(zone, length * sizeof(unichar));
    [self getCharacters:buffer range:NSMakeRange(0, numCharacters)];
    [string getCharacters:buffer + numCharacters
                    range:NSMakeRange(0, otherLength)];
    return [[[NSString allocWithZone:zone]
        initWithCharactersNoCopy:buffer length:length freeWhenDone:YES]
        autorelease];
}

- (const unichar *)_characters {
    return characters;
}

- (void)dealloc {
    if (characters != NULL)
        _NSGenericFree(characters);
    [super dealloc];
}

@end

@implementation NSUnicodeString

- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length {
    return [self initWithCharactersNoCopy:buffer length:length freeWhenDone:YES];
}

- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length
                 freeWhenDone:(BOOL)freeBuffer {
    [super initWithCharactersNoCopy:buffer length:length];
    _flags.freeWhenDone = freeBuffer & 1;
    return self;
}

- (void)dealloc {
    if (!_flags.freeWhenDone)
        characters = NULL;
    [super dealloc];
}

- (id)retain {
    BOOL locked = NSStringRetainLockAcquire();

    if (_flags.refs == 0xff) {
        _flags.refs = 0;
        if (_flags.hasExternalRefCount)
            NSIncrementExtraRefCount(self);
        _flags.hasExternalRefCount = 1;
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

@implementation NSInlineUnicodeString

- (id)retain {
    BOOL locked = NSStringRetainLockAcquire();

    if (_flags.refs == 0xff) {
        _flags.refs = 0;
        if (_flags.hasExternalRefCount)
            NSIncrementExtraRefCount(self);
        _flags.hasExternalRefCount = 1;
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
        NSDeallocateObject(self);
    }
}

- (unsigned)retainCount {
    unsigned count = _flags.refs + 1;

    if (_flags.hasExternalRefCount)
        count += (NSExtraRefCount(self) << 8) + 256;
    return count;
}

- (unsigned)length {
    return _flags.numChars;
}

- (unichar)characterAtIndex:(unsigned)index {
    Class stringClass;
    if (index >= _flags.numChars) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    return NSInlineUnicodeCharacters(self)[index];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    Class stringClass;
    if (_flags.numChars < range.location + range.length) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    memmove(buffer, NSInlineUnicodeCharacters(self) + range.location,
            range.length * sizeof(unichar));
}

- (unsigned)hash {
    return NSHashCharacters(NSInlineUnicodeCharacters(self), _flags.numChars);
}

- (BOOL)isEqualToString:(NSString *)string {
    unsigned length = _flags.numChars;
    unsigned offset;
    unichar characters[32];

    if (string == (id)self)
        return YES;
    if (string == nil)
        return NO;
    if (*(Class *)string == *(Class *)self)
        return ((NSInlineUnicodeString *)string)->_flags.numChars == length
            && memcmp(NSInlineUnicodeCharacters(self),
                      NSInlineUnicodeCharacters((NSInlineUnicodeString *)string),
                      length * sizeof(unichar)) == 0;
    if ([string length] != length)
        return NO;
    for (offset = 0; offset < length; offset += 32) {
        unsigned count = length - offset;
        if (count > 32)
            count = 32;
        [string getCharacters:characters range:NSMakeRange(offset, count)];
        if (memcmp(NSInlineUnicodeCharacters(self) + offset, characters,
                   count * sizeof(unichar)) != 0)
            return NO;
    }
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (object == self)
        return YES;
    if (object == nil)
        return NO;
    if (*(Class *)object == *(Class *)self) {
        NSInlineUnicodeString *other = object;
        return other->_flags.numChars == _flags.numChars
            && memcmp(NSInlineUnicodeCharacters(self),
                      NSInlineUnicodeCharacters(other),
                      _flags.numChars * sizeof(unichar)) == 0;
    }
    if (![object isKindOfClass:[NSString class]])
        return NO;
    return [self isEqualToString:object];
}

- (id)copyWithZone:(NSZone *)zone {
    if (NSShouldRetainWithZone(self, zone))
        return [self retain];
    return _NSNewInlineUnicodeString(NSInlineUnicodeCharacters(self),
                                     _flags.numChars, zone);
}

- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding {
    if (encoding == NSUnicodeStringEncoding)
        return YES;
    return [super canBeConvertedToEncoding:encoding];
}

@end

@implementation NSUnicodeSubstring

- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length
              referencedString:(NSString *)string {
    [super initWithCharactersNoCopy:buffer length:length freeWhenDone:NO];
    _referenceString = (NSSimpleString *)[string copyWithZone:[string zone]];
    return self;
}

- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length
                 freeWhenDone:(BOOL)freeBuffer {
    (void)buffer;
    (void)length;
    (void)freeBuffer;
    [NSException raise:NSInvalidArgumentException
                format:@"%@ is not a valid initializer for %@",
                       NSStringFromSelector(_cmd), [self description]];
    return nil;
}

- (id)retain {
    if (_referenceString != nil) {
        unsigned length = [self length];
        unsigned sourceLength = [_referenceString length];

        if (length < sourceLength - sourceLength / 10) {
            unichar *copy = length != 0
                ? NSZoneMalloc([self zone], length * sizeof(unichar))
                : NULL;
            if (length != 0)
                memmove(copy, characters, length * sizeof(unichar));
            characters = copy;
            _flags.freeWhenDone = YES;
            [_referenceString release];
            _referenceString = nil;
        }
    }
    return [super retain];
}

- (NSString *)substringWithRange:(NSRange)range {
    NSUnicodeSubstring *substring;
    NSSimpleString *referenceString;
    Class stringClass;

    if (numCharacters < range.location + range.length) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    if (range.length == 0)
        return __NSEmptyString;
    if (range.location == 0 && range.length == numCharacters)
        return [[self copyWithZone:NULL] autorelease];
    referenceString = _referenceString != nil ? _referenceString : self;
    substring = NSAllocateObject([NSUnicodeSubstring class], 0, NULL);
    substring = [substring initWithCharactersNoCopy:characters + range.location
                                              length:range.length
                                    referencedString:referenceString];
    return [substring autorelease];
}

- (void)dealloc {
    if (_referenceString != nil) {
        characters = NULL;
        [_referenceString release];
    }
    [super dealloc];
}

@end

@implementation NSUnicodeStringWithGap

- (id)initWithCapacity:(unsigned)capacity {
    [super initWithCharactersNoCopy:NULL length:0 freeWhenDone:NO];
    _flags.capacity = NSUnicodeCapacityToInternal(capacity);
    return self;
}

- (id)initWithCharactersNoCopy:(unichar *)buffer length:(unsigned)length
                 freeWhenDone:(BOOL)freeBuffer {
    [super initWithCharactersNoCopy:buffer length:length
                      freeWhenDone:freeBuffer];
    _flags.capacity = NSUnicodeCapacityToInternal(0x20);
    return self;
}

- (id)_setRequiredLength:(unsigned)requiredLength gapPosition:(unsigned)position
                  delete:(unsigned)deleteLength extraRoom:(BOOL)extraRoom {
    NSUnicodeStringWithGap *target = self;
    NSZone *zone = NSZoneFromPointer(self);
    unsigned oldLength = numCharacters;
    unsigned newLength = oldLength - deleteLength;
    unsigned initialCapacity = NSUnicodeCapacityToExternal(_flags.capacity);
    unsigned doubled = requiredLength * 2;
    unsigned grown = (requiredLength * 3) >> 1;
    unsigned threshold = initialCapacity > doubled ? initialCapacity : doubled;
    BOOL copyOnWrite = [self retainCount] > 1;
    BOOL allocateNewBuffer = NO;
    BOOL resizeBuffer = NO;
    unsigned currentCapacity;
    unsigned newCapacity;
    unsigned firstLength;
    unsigned secondLength;
    unsigned gapLength;
    unsigned tailStart;
    unsigned tailLength;
    unichar *newCharacters = NULL;
    unichar *sourceCharacters;
    unichar *destination;

    if (copyOnWrite) {
        target = [[NSUnicodeStringWithGap allocWithZone:zone]
                    initWithCapacity:initialCapacity];
        target->characters = characters;
        target->numCharacters = numCharacters;
        [self release];
        target->_flags.freeWhenDone = NO;
        target->_flags.canWriteIntoBuffer = NO;
    }

    currentCapacity = target->gapEnd + target->numCharacters - target->gapBegin;
    newCapacity = currentCapacity;
    if (currentCapacity != 0 || requiredLength != 0) {
        if (!target->_flags.canWriteIntoBuffer
            || currentCapacity < requiredLength) {
            newCapacity = extraRoom
                ? (grown > initialCapacity ? grown : initialCapacity)
                : requiredLength;
            allocateNewBuffer = YES;
        } else if (!target->_flags.freeWhenDone
                   && currentCapacity > threshold) {
            newCapacity = extraRoom
                ? (grown > initialCapacity ? grown : initialCapacity)
                : requiredLength;
            allocateNewBuffer = YES;
        } else if (currentCapacity > threshold
                   || (!extraRoom && currentCapacity > requiredLength)) {
            newCapacity = extraRoom
                ? (grown > initialCapacity ? grown : initialCapacity)
                : requiredLength;
            resizeBuffer = YES;
        }
    }

    if (allocateNewBuffer)
        newCharacters = (unichar *)NSZoneMalloc(zone,
                                                newCapacity * sizeof(unichar));
    if (oldLength != 0) {
        gapLength = gapEnd - gapBegin;
        sourceCharacters = characters;
        destination = newCharacters != NULL ? newCharacters : characters;

        firstLength = gapBegin != 0
            ? (position < gapBegin ? position : gapBegin) : 0;
        secondLength = position - firstLength;
        if (firstLength != 0 && sourceCharacters != destination)
            memmove(destination, sourceCharacters,
                    firstLength * sizeof(unichar));
        if (secondLength != 0
            && sourceCharacters + firstLength + gapLength
                != destination + firstLength)
            memmove(destination + firstLength,
                    sourceCharacters + firstLength + gapLength,
                    secondLength * sizeof(unichar));

        tailStart = position + deleteLength;
        tailLength = newLength - position;
        firstLength = 0;
        if (tailStart < gapBegin) {
            firstLength = tailLength;
            if (firstLength > gapBegin - tailStart)
                firstLength = gapBegin - tailStart;
        }
        secondLength = tailLength - firstLength;
        destination += position + newCapacity - newLength;
        if (firstLength != 0
            && sourceCharacters + tailStart != destination)
            memmove(destination, sourceCharacters + tailStart,
                    firstLength * sizeof(unichar));
        if (secondLength != 0
            && sourceCharacters + tailStart + firstLength + gapLength
                != destination + firstLength)
            memmove(destination + firstLength,
                    sourceCharacters + tailStart + firstLength + gapLength,
                    secondLength * sizeof(unichar));
    }

    if (newCharacters != NULL) {
        if (target->_flags.freeWhenDone) {
            unichar *oldCharacters = target->characters;
            NSZoneFree(NSZoneFromPointer(oldCharacters), oldCharacters);
        }
        target->characters = newCharacters;
        target->_flags.freeWhenDone = YES;
        target->_flags.canWriteIntoBuffer = YES;
    } else if (resizeBuffer) {
        target->characters = (unichar *)NSZoneRealloc(
            zone, target->characters, newCapacity * sizeof(unichar));
    }
    target->numCharacters = newLength;
    target->gapBegin = position;
    target->gapEnd = position + newCapacity - newLength;
    return target;
}

- (void)_copyToGapRange:(NSRange)range fromString:(NSString *)string {
    [string getCharacters:&characters[gapBegin] range:range];
    gapBegin += range.length;
    numCharacters += range.length;
}

- (void)_copyToGapLength:(unsigned)length fromCString:(const char *)string {
    unsigned index;
    for (index = 0; index < length; index++) {
        unsigned char byte = (unsigned char)string[index];
        characters[gapBegin + index] = byte > 0x7f
            ? _NSCStringCharToUnichar(byte) : byte;
    }
    gapBegin += length;
    numCharacters += length;
}

- (void)_copyToGapLength:(unsigned)length fromCharacters:(const unichar *)source {
    memmove(characters + gapBegin, source, length * sizeof(unichar));
    gapBegin += length;
    numCharacters += length;
}

- (unsigned)characterAtIndex:(unsigned)index {
    Class stringClass;
    if (index >= numCharacters) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    return characters[NSUnicodeGapPhysicalIndex(self, index)];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    unsigned firstLength;
    unsigned secondLength;
    unsigned gapLength;
    Class stringClass;
    if (range.location + range.length > numCharacters) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    gapLength = gapEnd - gapBegin;
    firstLength = 0;
    if (range.location < gapBegin) {
        firstLength = range.length;
        if (firstLength > gapBegin - range.location)
            firstLength = gapBegin - range.location;
    }
    secondLength = range.length - firstLength;
    if (firstLength != 0 && buffer != characters + range.location)
        memmove(buffer, characters + range.location,
                firstLength * sizeof(unichar));
    if (secondLength != 0
        && characters + range.location + firstLength + gapLength
            != buffer + firstLength)
        memmove(buffer + firstLength,
                characters + range.location + firstLength + gapLength,
                secondLength * sizeof(unichar));
}

- (void)_pack {
    unsigned tailLength = numCharacters - gapBegin;
    if (tailLength != 0 && gapEnd != gapBegin)
        memmove(characters + gapBegin, characters + gapEnd,
                tailLength * sizeof(unichar));
    gapEnd += tailLength;
    gapBegin = numCharacters;
}

- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    [self _pack];
    return [super getBytes:buffer maxLength:maxLength filledLength:usedLength
                  encoding:encoding allowLossyConversion:allowLossy range:range
            remainingRange:remainingRange];
}

@end

id _NSNewInlineUnicodeString(const unichar *characters, unsigned length,
                             NSZone *zone) {
    NSInlineUnicodeString *string;

    if (length > 0xffff)
        return [[NSUnicodeString allocWithZone:zone]
            initWithCharacters:characters length:length];

    string = NSAllocateObject([NSInlineUnicodeString class],
                              length * sizeof(unichar), zone);
    memmove(NSInlineUnicodeCharacters(string), characters,
            length * sizeof(unichar));
    *((unsigned short *)((char *)string + 6)) = (unsigned short)length;
    return string;
}

id _NSNewInlineUnicodeStringFromString(NSString *source, NSZone *zone) {
    unsigned length = [source length];
    NSInlineUnicodeString *string;
    unichar *characters;

    if (length > 0xffff) {
        characters = NSZoneMalloc(zone, length * sizeof(unichar));
        [source getCharacters:characters range:NSMakeRange(0, length)];
        return [[NSUnicodeString allocWithZone:zone]
            initWithCharactersNoCopy:characters length:length
                       freeWhenDone:YES];
    }

    string = NSAllocateObject([NSInlineUnicodeString class],
                              length * sizeof(unichar), zone);
    [source getCharacters:NSInlineUnicodeCharacters(string)
                    range:NSMakeRange(0, length)];
    *((unsigned short *)((char *)string + 6)) = (unsigned short)length;
    return string;
}
