/*  NSSimpleCString.m
    Simple and owning C string storage
*/

#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSHashTable.h>
#import "NSStringRetainLock.h"
#import <objc/objc-runtime.h>

#include <string.h>

extern NSStringEncoding _NSCStringEncoding;
extern unichar (*_NSCStringCharToUnichar)(unsigned char byte);
extern Class __NSInlineCStringClass;
extern void NSLog(NSString *format, ...);
extern NSString *__NSEmptyString;
extern NSLock *_NSUniqueCStringLock;
extern unsigned _NSHashTableHashCString(NSHashTable *table,
                                        const void *value);
extern BOOL _NSHashTableIsEqualCString(NSHashTable *table,
                                      const void *left,
                                      const void *right);
extern NSString *_NSHashTableDescribeCString(NSHashTable *table,
                                             const void *value);
extern void _NSGenericFree(void *ptr);

static NSHashTable *uniqueStrings;

void *
_NSUniqueCString(void *pointer)
{
    NSHashTableCallBacks callBacks;
    void *result;

    if (pointer == NULL)
        return NULL;
    if (_NSUniqueCStringLock != nil)
        [_NSUniqueCStringLock lock];
    if (uniqueStrings == NULL) {
        callBacks.hash = _NSHashTableHashCString;
        callBacks.isEqual = _NSHashTableIsEqualCString;
        callBacks.retain = NULL;
        callBacks.release = NULL;
        callBacks.describe = _NSHashTableDescribeCString;
        uniqueStrings = NSCreateHashTableWithZone(callBacks, 27, NULL);
    }
    result = NSHashGet(uniqueStrings, pointer);
    if (result == NULL) {
        unsigned length = (unsigned)strlen((const char *)pointer) + 1;

        result = NSZoneMalloc(NULL, length);
        memmove(result, pointer, length);
        NSHashInsertKnownAbsent(uniqueStrings, result);
    }
    if (_NSUniqueCStringLock != nil)
        [_NSUniqueCStringLock unlock];
    return result;
}

@interface NSString (NSSimpleCStringBytes)
- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange;
@end

@interface NSCString : NSSimpleCString {
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
- (id)initWithCStringNoCopy:(char *)buffer length:(unsigned)length
              freeWhenDone:(BOOL)freeBuffer;
@end

@interface NSCStringWithGap : NSCString {
@public
    unsigned gapBegin;
    unsigned gapEnd;
}
- (id)initWithCapacity:(unsigned)capacity;
- (id)_setRequiredLength:(unsigned)length gapPosition:(unsigned)position
                  delete:(unsigned)deleteLength extraRoom:(BOOL)extraRoom;
- (void)_copyToGapRange:(NSRange)range fromString:(NSString *)string;
- (void)_copyToGapLength:(unsigned)length fromCString:(const char *)string;
@end

@interface NSInlineCString : NSString {
@protected
    struct {
        unsigned refs : 8;
        unsigned hasExternalRefCount : 1;
        unsigned : 7;
        unsigned numBytes : 16;
    } _flags;
}
- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone;
@end

@interface NSCSubstring : NSCString {
@protected
    NSSimpleCString *_referenceString;
}
- (id)initWithCStringNoCopy:(char *)buffer length:(unsigned)length
          referencedString:(NSString *)string;
@end

id _NSNewInlineCString(const void *bytes, unsigned length, NSZone *zone);
id _NSNewInlineCStringFromString(NSString *string, NSZone *zone);

static char *NSInlineCStringBytes(NSInlineCString *string) {
    return (char *)string + __NSInlineCStringClass->instance_size;
}

static Class NSInlineCStringClassForAllocation(void) {
    if (__NSInlineCStringClass == nil)
        __NSInlineCStringClass = objc_lookUpClass("NSInlineCString");
    return __NSInlineCStringClass;
}

unsigned NSHashCString(const unsigned char *bytes, unsigned length) {
    unsigned hash = length;
    unsigned index;
    unsigned count = length > 16 ? 8 : length;

    for (index = 0; index < count; index++) {
        unsigned character = bytes[index];
        if (character > 0x7f)
            character = _NSCStringCharToUnichar((unsigned char)character);
        hash += character + (hash << 8);
    }
    if (length > 16) {
        bytes += length - 8;
        for (index = 0; index < 8; index++) {
            unsigned character = bytes[index];
            if (character > 0x7f)
                character = _NSCStringCharToUnichar((unsigned char)character);
            hash += character + (hash << 8);
        }
    }
    return (hash << (length & 0x1f)) + hash;
}

int NSCompareCString(const unsigned char *left, const unsigned char *right,
                     unsigned leftLength, unsigned rightLength,
                     unsigned options) {
    unsigned index;
    unsigned commonLength = leftLength < rightLength ? leftLength : rightLength;

    for (index = 0; index < commonLength; index++) {
        unsigned leftCharacter = left[index];
        unsigned rightCharacter = right[index];
        if (leftCharacter > 0x7f)
            leftCharacter = _NSCStringCharToUnichar((unsigned char)leftCharacter);
        if (rightCharacter > 0x7f)
            rightCharacter = _NSCStringCharToUnichar((unsigned char)rightCharacter);
        if (options & NSCaseInsensitiveSearch) {
            if (leftCharacter >= 'a' && leftCharacter <= 'z')
                leftCharacter -= 'a' - 'A';
            if (rightCharacter >= 'a' && rightCharacter <= 'z')
                rightCharacter -= 'a' - 'A';
        }
        if (leftCharacter < rightCharacter)
            return -1;
        if (leftCharacter > rightCharacter)
            return 1;
    }
    return leftLength < rightLength ? -1 : leftLength > rightLength;
}

static BOOL NSEqualCStringToString(const unsigned char *bytes, unsigned length,
                                  NSString *string) {
    unichar buffer[32];
    unsigned stringLength = [string length];
    unsigned offset = 0;

    if (length != stringLength)
        return NO;
    while (offset < length) {
        unsigned count = length - offset;
        unsigned index;
        if (count > 32)
            count = 32;
        [string getCharacters:buffer range:NSMakeRange(offset, count)];
        for (index = 0; index < count; index++) {
            unsigned character = bytes[offset + index];
            if (character > 0x7f)
                character = _NSCStringCharToUnichar((unsigned char)character);
            if (character != buffer[index])
                return NO;
        }
        offset += count;
    }
    return YES;
}

static unsigned NSCStringCapacityToInternal(unsigned capacity) {
    if (capacity > 0x7fff) {
        capacity = ((capacity - 32513) >> 8) + 0x8000;
        if (capacity > 0xffff)
            capacity = 0xffff;
    }
    return capacity;
}

static unsigned NSCStringCapacityToExternal(unsigned capacity) {
    if (capacity > 0x7fff)
        return (capacity << 8) - 8355840;
    return capacity;
}

static unsigned NSCStringGapPhysicalIndex(NSCStringWithGap *string,
                                          unsigned index) {
    return index < string->gapBegin ? index
                                    : index + string->gapEnd - string->gapBegin;
}

@implementation NSSimpleCString

+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 0, zone);
}

- (id)initWithCStringNoCopy:(char *)buffer length:(unsigned)length {
    bytes = buffer;
    numBytes = length;
    return self;
}

- (unsigned)length {
    return numBytes;
}

- (unsigned)cStringLength {
    return numBytes;
}

- (NSStringEncoding)fastestEncoding {
    return _NSCStringEncoding;
}

- (NSStringEncoding)smallestEncoding {
    return _NSCStringEncoding;
}

- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding {
    if (encoding == _NSCStringEncoding)
        return YES;
    return [super canBeConvertedToEncoding:encoding];
}

- (const char *)_fastCStringContents {
    return bytes;
}

- (id)copyWithZone:(NSZone *)zone {
    if (NSShouldRetainWithZone(self, zone))
        return [self retain];
    return _NSNewInlineCString(bytes, numBytes, zone);
}

- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone {
    Class stringClass;

    if (numBytes < range.location
        || numBytes < range.location + range.length) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    if (range.length == 0)
        return __NSEmptyString;
    if (range.location == 0 && range.length == numBytes) {
#if defined(__ppc__) || defined(__POWERPC__)
        return [self copy];
#else
        return [self retain];
#endif
    }
    if (range.length <= 24)
        return _NSNewInlineCString(bytes + range.location, range.length, zone);
    return [[NSCSubstring allocWithZone:zone]
        initWithCStringNoCopy:bytes + range.location length:range.length
        referencedString:self];
}

- (unichar)characterAtIndex:(unsigned)index {
    unsigned char byte;
    Class stringClass;

    if (index >= numBytes) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    byte = (unsigned char)bytes[index];
    return byte > 0x7f ? _NSCStringCharToUnichar(byte) : byte;
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    unsigned index;
    Class stringClass;

    if (numBytes < range.location + range.length) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    for (index = 0; index < range.length; index++) {
        unsigned char byte = (unsigned char)bytes[range.location + index];
        buffer[index] = byte > 0x7f ? _NSCStringCharToUnichar(byte) : byte;
    }
}

- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    unsigned length;

    if (encoding != _NSCStringEncoding)
        return [super getBytes:buffer maxLength:maxLength filledLength:usedLength
                      encoding:encoding allowLossyConversion:allowLossy
                         range:range remainingRange:remainingRange];

    length = range.length < maxLength ? range.length : maxLength;
    if (buffer != NULL && length != 0)
        memmove(buffer, bytes + range.location, length);
    if (usedLength != NULL)
        *usedLength = length;
    if (remainingRange != NULL) {
        remainingRange->location = range.location + length;
        remainingRange->length = range.length - length;
    }
    return YES;
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)options
                         range:(NSRange)range {
    const char *otherBytes;
    unsigned otherLength;

    if (*(Class *)string == *(Class *)self) {
        NSSimpleCString *other = (NSSimpleCString *)string;
        otherBytes = other->bytes;
        otherLength = other->numBytes;
    } else {
        otherBytes = [string _fastCStringContents];
        if (otherBytes == NULL)
            return [super compare:string options:options range:range];
        otherLength = [string cStringLength];
    }
    if (otherBytes == NULL)
        return [super compare:string options:options range:range];
    return NSCompareCString((const unsigned char *)bytes + range.location,
                            (const unsigned char *)otherBytes, range.length,
                            otherLength, options);
}

- (BOOL)hasPrefix:(NSString *)string {
    const char *otherBytes;
    unsigned otherLength;

    if (*(Class *)string == *(Class *)self) {
        NSSimpleCString *other = (NSSimpleCString *)string;
        otherBytes = other->bytes;
        otherLength = other->numBytes;
    } else {
        otherBytes = [string _fastCStringContents];
        if (otherBytes == NULL)
            return [super hasPrefix:string];
        otherLength = [string cStringLength];
    }
    if (otherBytes == NULL)
        return [super hasPrefix:string];
    return otherLength != 0 && numBytes >= otherLength
        && memcmp(bytes, otherBytes, otherLength) == 0;
}

- (BOOL)hasSuffix:(NSString *)string {
    const char *otherBytes;
    unsigned otherLength;

    if (*(Class *)string == *(Class *)self) {
        NSSimpleCString *other = (NSSimpleCString *)string;
        otherBytes = other->bytes;
        otherLength = other->numBytes;
    } else {
        otherBytes = [string _fastCStringContents];
        if (otherBytes == NULL)
            return [super hasSuffix:string];
        otherLength = [string cStringLength];
    }
    if (otherBytes == NULL)
        return [super hasSuffix:string];
    return otherLength != 0 && numBytes >= otherLength
        && memcmp(bytes + numBytes - otherLength, otherBytes, otherLength) == 0;
}

- (BOOL)isEqual:(id)object {
    const char *otherBytes;
    unsigned otherLength;

    if (self == object)
        return YES;
    if (object == nil)
        return NO;
    if ([object isKindOfClass:[NSSimpleCString class]]) {
        NSSimpleCString *other = (NSSimpleCString *)object;
        return other->numBytes == numBytes
            && memcmp(bytes, other->bytes, numBytes) == 0;
    }
    if (![object isKindOfClass:[NSString class]])
        return NO;
    otherBytes = [object _fastCStringContents];
    if (otherBytes == NULL)
        return NSEqualCStringToString((const unsigned char *)bytes, numBytes,
                                     (NSString *)object);
    otherLength = [object cStringLength];
    return numBytes == otherLength
        && memcmp(bytes, otherBytes, otherLength) == 0;
}

- (BOOL)isEqualToString:(NSString *)string {
    const char *otherBytes;
    unsigned otherLength;

    if (self == (id)string)
        return YES;
    if (string == nil)
        return NO;
    if ([string isKindOfClass:[NSSimpleCString class]]) {
        NSSimpleCString *other = (NSSimpleCString *)string;
        return other->numBytes == numBytes
            && memcmp(bytes, other->bytes, numBytes) == 0;
    }
    otherBytes = [string _fastCStringContents];
    if (otherBytes == NULL)
        return NSEqualCStringToString((const unsigned char *)bytes, numBytes,
                                     string);
    otherLength = [string cStringLength];
    return numBytes == otherLength
        && memcmp(bytes, otherBytes, otherLength) == 0;
}

- (NSString *)stringByAppendingString:(NSString *)string {
    unsigned otherLength = [string length];
    unsigned length;
    NSZone *zone;

    if (numBytes == 0)
        return otherLength != 0 ? [[string copyWithZone:NULL] autorelease]
                                : __NSEmptyString;
    if (otherLength == 0)
        return [[self copyWithZone:NULL] autorelease];

    zone = NSZoneFromPointer(self);
    if ([string fastestEncoding] == _NSCStringEncoding) {
        unsigned otherCStringLength = [string cStringLength];
        length = numBytes + otherCStringLength;
        char *buffer = (char *)NSZoneMalloc(zone, numBytes + otherCStringLength);

        memmove(buffer, bytes, numBytes);
        [string getBytes:buffer + numBytes maxLength:otherCStringLength
            filledLength:NULL encoding:_NSCStringEncoding
            allowLossyConversion:NO
            range:NSMakeRange(0, otherCStringLength) remainingRange:NULL];
        return [[[NSString allocWithZone:zone]
            initWithCStringNoCopy:buffer length:length freeWhenDone:YES]
            autorelease];
    } else {
        length = numBytes + otherLength;
        unichar *characters = (unichar *)NSZoneMalloc(
            zone, length * sizeof(unichar));

        [self getCharacters:characters range:NSMakeRange(0, numBytes)];
        [string getCharacters:characters + numBytes
                        range:NSMakeRange(0, otherLength)];
        return [[[NSString allocWithZone:zone]
            initWithCharactersNoCopy:characters length:length freeWhenDone:YES]
            autorelease];
    }
}

- (unsigned)hash {
    unsigned hash = numBytes;
    unsigned index;
    unsigned count;
    const unsigned char *cursor = (const unsigned char *)bytes;

    count = numBytes > 16 ? 8 : numBytes;
    for (index = 0; index < count; index++) {
        unsigned character = cursor[index];
        if (character > 0x7f)
            character = _NSCStringCharToUnichar((unsigned char)character);
        hash += character + (hash << 8);
    }
    if (numBytes > 16) {
        cursor = (const unsigned char *)bytes + numBytes - 8;
        for (index = 0; index < 8; index++) {
            unsigned character = cursor[index];
            if (character > 0x7f)
                character = _NSCStringCharToUnichar((unsigned char)character);
            hash += character + (hash << 8);
        }
    }
    return (hash << (numBytes & 0x1f)) + hash;
}

- (void)dealloc {
    if (bytes != NULL)
        _NSGenericFree(bytes);
    [super dealloc];
}

@end

@implementation NSCString

- (id)initWithCStringNoCopy:(char *)buffer length:(unsigned)length {
    return [self initWithCStringNoCopy:buffer length:length freeWhenDone:YES];
}

- (id)initWithCStringNoCopy:(char *)buffer length:(unsigned)length
              freeWhenDone:(BOOL)freeBuffer {
    [super initWithCStringNoCopy:buffer length:length];
    _flags.freeWhenDone = freeBuffer & 1;
    return self;
}

- (id)initWithCString:(const char *)source length:(unsigned)length {
    char *copy = NULL;

    if (length != 0) {
        copy = (char *)NSZoneMalloc(NULL, length);
        memmove(copy, source, length);
    }
    return [self initWithCStringNoCopy:copy length:length freeWhenDone:YES];
}

- (void)dealloc {
    if (!_flags.freeWhenDone)
        bytes = NULL;
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

@implementation NSInlineCString

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
    return _flags.numBytes;
}

- (unsigned)cStringLength {
    return _flags.numBytes;
}

- (const char *)cString {
    return NSInlineCStringBytes(self);
}

- (const char *)lossyCString {
    return NSInlineCStringBytes(self);
}

- (const char *)_fastCStringContents {
    return NSInlineCStringBytes(self);
}

- (NSStringEncoding)fastestEncoding {
    return _NSCStringEncoding;
}

- (NSStringEncoding)smallestEncoding {
    return _NSCStringEncoding;
}

- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding {
    if (encoding == _NSCStringEncoding)
        return YES;
    return [super canBeConvertedToEncoding:encoding];
}

- (unsigned)hash {
    return NSHashCString((const unsigned char *)NSInlineCStringBytes(self),
                         _flags.numBytes);
}

- (id)copyWithZone:(NSZone *)zone {
    if (NSShouldRetainWithZone(self, zone))
        return [self retain];
    return _NSNewInlineCString(NSInlineCStringBytes(self), _flags.numBytes, zone);
}

- (unichar)characterAtIndex:(unsigned)index {
    unsigned char byte;
    Class stringClass;
    if (index >= _flags.numBytes) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    byte = (unsigned char)NSInlineCStringBytes(self)[index];
    return byte > 0x7f ? _NSCStringCharToUnichar(byte) : byte;
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    unsigned index;
    Class stringClass;
    if (range.location + range.length > _flags.numBytes) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    for (index = 0; index < range.length; index++) {
        unsigned char byte = (unsigned char)NSInlineCStringBytes(self)
            [range.location + index];
        buffer[index] = byte > 0x7f ? _NSCStringCharToUnichar(byte) : byte;
    }
}

- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    unsigned length;

    if (encoding != _NSCStringEncoding)
        return [super getBytes:buffer maxLength:maxLength filledLength:usedLength
                      encoding:encoding allowLossyConversion:allowLossy
                         range:range remainingRange:remainingRange];
    length = range.length < maxLength ? range.length : maxLength;
    if (buffer != NULL && length != 0)
        memmove(buffer, NSInlineCStringBytes(self) + range.location, length);
    if (usedLength != NULL)
        *usedLength = length;
    if (remainingRange != NULL) {
        remainingRange->location = range.location + length;
        remainingRange->length = range.length - length;
    }
    return YES;
}

- (BOOL)isEqualToString:(NSString *)string {
    const char *otherBytes;
    unsigned otherLength;

    if (self == (id)string)
        return YES;
    if (string == nil)
        return NO;
    if (*(Class *)string == *(Class *)self) {
        NSInlineCString *other = (NSInlineCString *)string;
        return other->_flags.numBytes == _flags.numBytes
            && memcmp(NSInlineCStringBytes(self), NSInlineCStringBytes(other),
                      _flags.numBytes) == 0;
    }
    otherBytes = [string _fastCStringContents];
    if (otherBytes != NULL) {
        otherLength = [string cStringLength];
        return otherLength == _flags.numBytes
            && memcmp(NSInlineCStringBytes(self), otherBytes, otherLength) == 0;
    }
    return NSEqualCStringToString(
        (const unsigned char *)NSInlineCStringBytes(self), _flags.numBytes, string);
}

- (BOOL)isEqual:(id)object {
    if (self == object)
        return YES;
    if (object == nil)
        return NO;
    if (*(Class *)object == *(Class *)self) {
        NSInlineCString *other = (NSInlineCString *)object;
        return other->_flags.numBytes == _flags.numBytes
            && memcmp(NSInlineCStringBytes(self), NSInlineCStringBytes(other),
                      _flags.numBytes) == 0;
    }
    if (*(Class *)object != [NSConstantString class]
        && ![object isKindOfClass:[NSString class]])
        return NO;
    return [self isEqualToString:object];
}

- (NSComparisonResult)compare:(NSString *)string options:(unsigned)options
                         range:(NSRange)range {
    const char *otherBytes;
    unsigned otherLength;
    if (*(Class *)string == *(Class *)self) {
        NSInlineCString *other = (NSInlineCString *)string;
        otherBytes = NSInlineCStringBytes(other);
        otherLength = other->_flags.numBytes;
    } else {
        otherBytes = [string _fastCStringContents];
        if (otherBytes == NULL)
            return [super compare:string options:options range:range];
        otherLength = [string cStringLength];
    }
    return NSCompareCString(
        (const unsigned char *)NSInlineCStringBytes(self) + range.location,
        (const unsigned char *)otherBytes, range.length, otherLength, options);
}

- (BOOL)hasPrefix:(NSString *)string {
    const char *otherBytes;
    unsigned otherLength;
    if (*(Class *)string == *(Class *)self) {
        NSInlineCString *other = (NSInlineCString *)string;
        otherBytes = NSInlineCStringBytes(other);
        otherLength = other->_flags.numBytes;
    } else {
        otherBytes = [string _fastCStringContents];
        if (otherBytes == NULL)
            return [super hasPrefix:string];
        otherLength = [string cStringLength];
    }
    return otherLength != 0 && otherLength <= _flags.numBytes
        && memcmp(NSInlineCStringBytes(self), otherBytes, otherLength) == 0;
}

- (BOOL)hasSuffix:(NSString *)string {
    const char *otherBytes;
    unsigned otherLength;
    if (*(Class *)string == *(Class *)self) {
        NSInlineCString *other = (NSInlineCString *)string;
        otherBytes = NSInlineCStringBytes(other);
        otherLength = other->_flags.numBytes;
    } else {
        otherBytes = [string _fastCStringContents];
        if (otherBytes == NULL)
            return [super hasSuffix:string];
        otherLength = [string cStringLength];
    }
    return otherLength != 0 && otherLength <= _flags.numBytes
        && memcmp(NSInlineCStringBytes(self) + _flags.numBytes - otherLength,
                  otherBytes, otherLength) == 0;
}

- (NSString *)substringWithRange:(NSRange)range {
    NSString *result;
    Class stringClass;
    if (range.location + range.length > _flags.numBytes) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    if (range.length == 0)
        return __NSEmptyString;
    if (range.location == 0 && range.length == _flags.numBytes)
        return [[self retain] autorelease];
    result = [self _newSubstringWithRange:range zone:NULL];
    return [result autorelease];
}

- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone {
    Class stringClass;

    if (range.location > _flags.numBytes
        || range.location + range.length > _flags.numBytes) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    if (range.length == 0)
        return __NSEmptyString;
    if (range.location == 0 && range.length == _flags.numBytes) {
#if defined(__ppc__) || defined(__POWERPC__)
        return [self copy];
#else
        return [self retain];
#endif
    }
    if (range.length <= 24)
        return _NSNewInlineCString(NSInlineCStringBytes(self) + range.location,
                                   range.length, zone);
    return [[NSCSubstring allocWithZone:zone]
        initWithCStringNoCopy:NSInlineCStringBytes(self) + range.location
        length:range.length referencedString:(NSString *)self];
}

- (NSString *)stringByAppendingString:(NSString *)string {
    unsigned otherLength = [string length];
    unsigned length;
    NSZone *zone;

    if (_flags.numBytes == 0)
        return otherLength != 0 ? [[string copyWithZone:NULL] autorelease]
                                : __NSEmptyString;
    if (otherLength == 0)
        return [[self copyWithZone:NULL] autorelease];
    if ([string fastestEncoding] == _NSCStringEncoding) {
        unsigned otherCStringLength;

        zone = NSZoneFromPointer(self);
        otherCStringLength = [string cStringLength];
        length = _flags.numBytes + otherCStringLength;
        char *buffer = length != 0 ? (char *)NSZoneMalloc(zone, length) : NULL;
        memmove(buffer, NSInlineCStringBytes(self), _flags.numBytes);
        [string getBytes:buffer + _flags.numBytes maxLength:otherCStringLength
            filledLength:NULL encoding:_NSCStringEncoding
            allowLossyConversion:NO range:NSMakeRange(0, otherLength)
            remainingRange:NULL];
        return [[[NSString allocWithZone:zone]
            initWithCStringNoCopy:buffer length:length freeWhenDone:YES] autorelease];
    } else {
        zone = NSZoneFromPointer(self);
        length = _flags.numBytes + otherLength;
        unichar *characters = length != 0
            ? (unichar *)NSZoneMalloc(zone, length * sizeof(unichar)) : NULL;
        [self getCharacters:characters range:NSMakeRange(0, _flags.numBytes)];
        [string getCharacters:characters + _flags.numBytes
                        range:NSMakeRange(0, otherLength)];
        return [[[NSString allocWithZone:zone]
            initWithCharactersNoCopy:characters length:length freeWhenDone:YES]
            autorelease];
    }
}

@end

@implementation NSCSubstring

- (id)initWithCStringNoCopy:(char *)buffer length:(unsigned)length
          referencedString:(NSString *)string {
    [super initWithCStringNoCopy:buffer length:length];
    _referenceString = (NSSimpleCString *)[string copyWithZone:[string zone]];
    return self;
}

- (id)initWithCStringNoCopy:(char *)buffer length:(unsigned)length {
    [NSException raise:NSInvalidArgumentException
                format:@"%@ is not a supported initializer for %@",
                       NSStringFromSelector(_cmd), self];
    return nil;
}

- (id)retain {
    if (_referenceString != nil) {
        unsigned length = numBytes;
        char *copy = length != 0
            ? (char *)NSZoneMalloc([self zone], length) : NULL;
        if (length != 0)
            memmove(copy, bytes, length);
        bytes = copy;
        [_referenceString release];
        _referenceString = nil;
    }
    return [super retain];
}

- (void)dealloc {
    if (_referenceString != nil) {
        bytes = NULL;
        [_referenceString release];
    }
    [super dealloc];
}

@end

@implementation NSCStringWithGap

- (id)initWithCapacity:(unsigned)capacity {
    [super initWithCStringNoCopy:NULL length:0 freeWhenDone:NO];
    _flags.capacity = NSCStringCapacityToInternal(capacity);
    return self;
}

- (id)initWithCStringNoCopy:(char *)buffer length:(unsigned)length
              freeWhenDone:(BOOL)freeBuffer {
    [super initWithCStringNoCopy:buffer length:length
                  freeWhenDone:freeBuffer];
    _flags.capacity = NSCStringCapacityToInternal(32);
    return self;
}

- (id)_setRequiredLength:(unsigned)requiredLength gapPosition:(unsigned)position
                  delete:(unsigned)deleteLength extraRoom:(BOOL)extraRoom {
    NSCStringWithGap *target = self;
    NSZone *zone = NSZoneFromPointer(self);
    unsigned oldLength = numBytes;
    unsigned newLength = oldLength - deleteLength;
    unsigned initialCapacity = NSCStringCapacityToExternal(_flags.capacity);
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
    unsigned sourceGapBegin = gapBegin;
    unsigned sourceGapEnd = gapEnd;
    unsigned tailStart;
    unsigned tailLength;
    char *newBytes = NULL;
    char *sourceBytes;
    char *destination;

    if (copyOnWrite) {
        target = [[NSCStringWithGap allocWithZone:zone]
                    initWithCapacity:initialCapacity];
        target->bytes = bytes;
        target->numBytes = numBytes;
        [self release];
        target->_flags.freeWhenDone = NO;
        target->_flags.canWriteIntoBuffer = NO;
    }

    currentCapacity = target->gapEnd + target->numBytes - target->gapBegin;
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
        newBytes = (char *)NSZoneMalloc(zone, newCapacity);
    if (oldLength != 0) {
        gapLength = sourceGapEnd - sourceGapBegin;
        sourceBytes = target->bytes;
        destination = newBytes != NULL ? newBytes : target->bytes;

        firstLength = sourceGapBegin != 0
            ? (position < sourceGapBegin ? position : sourceGapBegin) : 0;
        secondLength = position - firstLength;
        if (firstLength != 0 && sourceBytes != destination)
            memmove(destination, sourceBytes, firstLength);
        if (secondLength != 0
            && sourceBytes + firstLength + gapLength != destination + firstLength)
            memmove(destination + firstLength,
                    sourceBytes + firstLength + gapLength, secondLength);

        tailStart = position + deleteLength;
        tailLength = newLength - position;
        firstLength = 0;
        if (tailStart < sourceGapBegin) {
            firstLength = tailLength;
            if (firstLength > sourceGapBegin - tailStart)
                firstLength = sourceGapBegin - tailStart;
        }
        secondLength = tailLength - firstLength;
        destination += position + newCapacity - newLength;
        if (firstLength != 0
            && sourceBytes + tailStart != destination)
            memmove(destination, sourceBytes + tailStart, firstLength);
        if (secondLength != 0
            && sourceBytes + tailStart + firstLength + gapLength
                != destination + firstLength)
            memmove(destination + firstLength,
                    sourceBytes + tailStart + firstLength + gapLength,
                    secondLength);
    }

    if (newBytes != NULL) {
        if (target->_flags.freeWhenDone) {
            char *oldBytes = target->bytes;
            NSZoneFree(NSZoneFromPointer(oldBytes), oldBytes);
        }
        target->bytes = newBytes;
        target->_flags.freeWhenDone = YES;
        target->_flags.canWriteIntoBuffer = YES;
    } else if (resizeBuffer) {
        target->bytes = (char *)NSZoneRealloc(zone, target->bytes, newCapacity);
    }
    target->numBytes = newLength;
    target->gapBegin = position;
    target->gapEnd = position + newCapacity - newLength;
    return target;
}

- (void)_copyToGapRange:(NSRange)range fromString:(NSString *)string {
    unsigned copied = 0;
    if (![string getBytes:&bytes[gapBegin] maxLength:range.length
              filledLength:&copied encoding:_NSCStringEncoding
       allowLossyConversion:NO range:range remainingRange:NULL]
        || copied != range.length)
        NSLog(@"Unable to copy string characters into an NSCStringWithGap.");
    gapBegin += range.length;
    numBytes += range.length;
}

- (void)_copyToGapLength:(unsigned)length fromCString:(const char *)string {
    if (length != 0)
        memmove(bytes + gapBegin, string, length);
    gapBegin += length;
    numBytes += length;
}

- (unsigned)characterAtIndex:(unsigned)index {
    unsigned char byte;
    Class stringClass;
    if (index >= numBytes) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    byte = (unsigned char)bytes[NSCStringGapPhysicalIndex(self, index)];
    return byte > 0x7f ? _NSCStringCharToUnichar(byte) : byte;
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    unsigned index;
    Class stringClass;
    if (range.location + range.length > numBytes) {
        stringClass = [self class];
        [NSException raise:NSRangeException
                    format:@"[%s %s]: Out of bounds",
                           stringClass->name, sel_getName(_cmd)];
    }
    for (index = 0; index < range.length; index++)
        buffer[index] = [self characterAtIndex:range.location + index];
}

- (void)_pack {
    unsigned tailLength = numBytes - gapBegin;
    if (tailLength != 0 && gapEnd != gapBegin)
        memmove(bytes + gapBegin, bytes + gapEnd, tailLength);
    gapEnd += tailLength;
    gapBegin = numBytes;
}

- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    unsigned length;
    unsigned firstLength;
    if (encoding != _NSCStringEncoding) {
        [self _pack];
        return [super getBytes:buffer maxLength:maxLength filledLength:usedLength
                      encoding:encoding allowLossyConversion:allowLossy range:range
                remainingRange:remainingRange];
    }
    length = range.length < maxLength ? range.length : maxLength;
    firstLength = 0;
    if (range.location < gapBegin) {
        firstLength = length;
        if (firstLength > gapBegin - range.location)
            firstLength = gapBegin - range.location;
    }
    if (buffer != NULL && firstLength != 0)
        memmove(buffer, bytes + range.location, firstLength);
    if (buffer != NULL && length > firstLength) {
        unsigned secondStart = range.location + firstLength;
        memmove(buffer + firstLength,
                bytes + NSCStringGapPhysicalIndex(self, secondStart),
                length - firstLength);
    }
    if (usedLength != NULL)
        *usedLength = length;
    if (remainingRange != NULL) {
        remainingRange->location = range.location + length;
        remainingRange->length = range.length - length;
    }
    return YES;
}

@end

id _NSNewInlineCString(const void *source, unsigned length, NSZone *zone) {
    if (length <= 0xffff) {
        NSInlineCString *string = (NSInlineCString *)NSAllocateObject(
            NSInlineCStringClassForAllocation(), length + 1, zone);
        if (length != 0)
            memmove(NSInlineCStringBytes(string), source, length);
        NSInlineCStringBytes(string)[length] = '\0';
        *((unsigned short *)((char *)string + 6)) = (unsigned short)length;
        return string;
    } else {
        return [[NSSimpleCString allocWithZone:zone]
            initWithCString:source length:length];
    }
}

id _NSNewInlineCStringFromString(NSString *source, NSZone *zone) {
    unsigned length = [source cStringLength];
    unsigned sourceLength;
    char *buffer;

    if (length <= 0xffff) {
        NSInlineCString *string = (NSInlineCString *)NSAllocateObject(
            NSInlineCStringClassForAllocation(), length + 1, zone);
        sourceLength = [source length];
        [source getCString:NSInlineCStringBytes(string) maxLength:length
            range:NSMakeRange(0, sourceLength) remainingRange:NULL];
        *((unsigned short *)((char *)string + 6)) = (unsigned short)length;
        return string;
    }

    buffer = length == (unsigned)-1 ? NULL
        : (char *)NSZoneMalloc(zone, length + 1);
    sourceLength = [source length];
    [source getCString:buffer maxLength:length
        range:NSMakeRange(0, sourceLength) remainingRange:NULL];
    return [[NSSimpleCString allocWithZone:zone]
        initWithCStringNoCopy:buffer length:length freeWhenDone:YES];
}
