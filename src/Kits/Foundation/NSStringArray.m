/*	NSStringArray.m
	Packed UTF-8 string arrays
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSException.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

@interface NSStringArray : NSArray {
    unsigned _count;
    unsigned _extraRefCount;
    NSData *_data;
    void *_strings;
    void *_reserved;
}
@end

NSStringArray *__NSEmptyStringArray;
extern Class __NSStringArrayClass;

@interface _NSUTF8String : NSString {
@protected
    NSStringArray *_array;
}
@end

@interface _NSUTF8ASCIIString : _NSUTF8String {
@protected
    const char *_bytes;
    unsigned _length;
}
@end

@interface _NSUTF8NonASCIIString : _NSUTF8String {
@protected
    NSString *_realString;
    unsigned _length;
}
@end

@interface NSString (NSStringArrayByteEncoding)
- (id)initWithBytes:(const void *)bytes length:(unsigned)length
    encoding:(NSStringEncoding)encoding;
- (BOOL)getBytes:(void *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)lossy range:(NSRange)range
    remainingRange:(NSRangePointer)leftover;
@end

#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSStringArrayRetainLock;
extern int _NSIsMultiThreaded;

static void _NSStringArrayRetainLockAcquire(void) {
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
            : "r" (&__NSStringArrayRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return;
        cthread_yield();
    }
}

static void _NSStringArrayRetainLockRelease(void) {
    __asm__ volatile("sync" ::: "memory");
    __NSStringArrayRetainLock = 0;
}

static BOOL _NSStringArrayLock(void) {
    if (!_NSIsMultiThreaded)
        return NO;
    _NSStringArrayRetainLockAcquire();
    return YES;
}

static void _NSStringArrayUnlock(BOOL locked) {
    if (locked)
        _NSStringArrayRetainLockRelease();
}
#else
extern NSLock *_NSGlobalRetainLock;

static BOOL _NSStringArrayLock(void) {
    if (_NSGlobalRetainLock == nil)
        return NO;
    [_NSGlobalRetainLock lock];
    return YES;
}

static void _NSStringArrayUnlock(BOOL locked) {
    if (locked)
        [_NSGlobalRetainLock unlock];
}
#endif
extern NSStringEncoding _NSCStringEncoding;
extern unichar (*_NSCStringCharToUnichar)(unsigned char byte);
extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);

static void _NSStringArrayRetainOwner(NSStringArray *array) {
    BOOL locked = _NSStringArrayLock();

    if (array->_extraRefCount++ == UINT_MAX)
        array->_extraRefCount = UINT_MAX;
    _NSStringArrayUnlock(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, array);
}

static BOOL _NSStringArrayReleaseOwner(NSStringArray *array) {
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, array);
    locked = _NSStringArrayLock();
    if (array->_extraRefCount != 0) {
        if (array->_extraRefCount != UINT_MAX)
            array->_extraRefCount--;
    } else {
        shouldDeallocate = YES;
    }
    _NSStringArrayUnlock(locked);
    return shouldDeallocate;
}

static unsigned _NSStringArrayEncodeString(NSString *string, char *buffer) {
    unsigned usedLength = 0;
    unsigned maximumLength = 3 * [string length];
    NSRange remainingRange = NSMakeRange(0, 0);

    if (![string getBytes:buffer maxLength:maximumLength
              filledLength:&usedLength encoding:NSUTF8StringEncoding
        allowLossyConversion:NO range:NSMakeRange(0, [string length])
            remainingRange:&remainingRange]) {
        [NSException raise:NSCharacterConversionException
                    format:@"Cannot encode %@ as UTF-8", string];
    }
    return usedLength;
}

static unsigned _NSStringArrayByteLength(const char *string) {
    const char *cursor = string;
    while (*cursor != '\0')
        cursor++;
    return (unsigned)(cursor - string);
}

static unsigned _NSStringArrayHashCString(const unsigned char *bytes,
                                           unsigned length) {
    unsigned hash = length;
    unsigned index;
    if (length > 16) {
        for (index = 0; index < 8; index++) {
            unsigned value = bytes[index];
            if (value > 0x7f)
                value = _NSCStringCharToUnichar((unsigned char)value);
            hash += value + (hash << 8);
        }
        for (index = length - 8; index < length; index++) {
            unsigned value = bytes[index];
            if (value > 0x7f)
                value = _NSCStringCharToUnichar((unsigned char)value);
            hash += value + (hash << 8);
        }
    } else {
        for (index = 0; index < length; index++) {
            unsigned value = bytes[index];
            if (value > 0x7f)
                value = _NSCStringCharToUnichar((unsigned char)value);
            hash += value + (hash << 8);
        }
    }
    return (hash << (length & 0x1f)) + hash;
}

static BOOL _NSStringArrayByteMatch(const char *candidate,
                                   unsigned candidateLength,
                                   const char *query, unsigned queryLength,
                                   unsigned option) {
    if (candidateLength < queryLength)
        return NO;
    if (option == 0)
        return candidateLength == queryLength
            && memcmp(candidate, query, queryLength) == 0;
    if (option == 1)
        return memcmp(candidate, query, candidateLength) == 0;
    if (option == 2) {
        unsigned offset;
        if (queryLength == 0)
            return NO;
        for (offset = 0; offset + queryLength <= candidateLength; offset++) {
            if (memcmp(candidate + offset, query, queryLength) == 0)
                return YES;
        }
    }
    return NO;
}

static void _NSStringArrayBuildSubstringShifts(unsigned shifts[256],
                                              const char *query,
                                              unsigned queryLength) {
    unsigned index;

    for (index = 0; index < 256; index++)
        shifts[index] = queryLength;
    if (queryLength != 1) {
        /* Match the target's unsigned length - 1 bound, including zero. */
        index = 0;
        do {
            shifts[(unsigned char)query[index]] = queryLength - index - 1;
            ++index;
        } while (index < queryLength - 1);
    }
}

static BOOL _NSStringArrayByteSubstringMatch(const char *candidate,
                                             unsigned candidateLength,
                                             const char *query,
                                             unsigned queryLength,
                                             const unsigned shifts[256]) {
    unsigned offset;

    if (queryLength == 0 || queryLength > candidateLength)
        return NO;

    offset = queryLength - 1;
    while (offset < candidateLength) {
        unsigned candidateIndex = offset;
        unsigned queryIndex = queryLength - 1;

        while ((unsigned char)candidate[candidateIndex]
               == (unsigned char)query[queryIndex]) {
            if (queryIndex == 0)
                return YES;
            candidateIndex--;
            queryIndex--;
        }
        offset += shifts[(unsigned char)candidate[offset]];
    }
    return NO;
}

static BOOL _NSStringArrayContainsQuery(NSStringArray *array,
                                        const char *query,
                                        unsigned queryLength,
                                        unsigned option) {
    const char *candidate;
    const char *end;
    unsigned shifts[256];

    if (array->_data == nil)
        return NO;
    if (option == 2) {
        _NSStringArrayBuildSubstringShifts(shifts, query, queryLength);
    }
    candidate = [array->_data bytes];
    if (candidate == NULL)
        return NO;
    end = candidate + [array->_data length];
    while (candidate < end) {
        unsigned candidateLength = _NSStringArrayByteLength(candidate);
        BOOL matched;

        if (option == 2)
            matched = _NSStringArrayByteSubstringMatch(candidate,
                candidateLength, query, queryLength, shifts);
        else
            matched = _NSStringArrayByteMatch(candidate, candidateLength,
                query, queryLength, option);
        if (matched)
            return YES;
        candidate += candidateLength + 1;
    }
    return NO;
}

static unsigned _NSStringArrayWordHash(NSHashTable *table, const void *word) {
    const unsigned char *bytes = word;
    unsigned length = 0;
    while (bytes[length] != 0)
        length++;
    if (length == 0)
        return 0;
    {
        unsigned hash = length;
        unsigned positions[5];
        unsigned index;
        positions[0] = 0;
        positions[1] = length >> 2;
        positions[2] = length >> 1;
        positions[3] = (3 * length) >> 2;
        positions[4] = length - 1;
        for (index = 0; index < 5; index++) {
            unsigned value = bytes[positions[index]];
            hash = ((value << (value & 7)) + (hash << 8) + hash);
        }
        return hash;
    }
}

static BOOL _NSStringArrayWordEqual(NSHashTable *table, const void *first,
                                    const void *second) {
    return strcmp(first, second) == 0;
}

static NSHashTable *_NSStringArrayWordTable(unsigned capacity) {
    NSHashTableCallBacks callbacks = {
        _NSStringArrayWordHash, _NSStringArrayWordEqual, NULL, NULL, NULL
    };
    return NSCreateHashTable(callbacks, capacity);
}

static int _NSStringArrayFindString(NSStringArray *array, NSString *string,
                                    unsigned option, NSData **bitVector) {
    char localQuery[196];
    const char *query;
    char *allocatedQuery = NULL;
    unsigned shifts[256];
    unsigned stringLength;
    unsigned queryLength;
    const char *cursor;
    const char *end;
    unsigned index = 0;
    unsigned matched = 0;
    unsigned lastMatch = 0;
    unsigned char *bits = NULL;

    stringLength = [string length];
    if (stringLength <= 0x3f)
        query = localQuery;
    else {
        allocatedQuery = NSZoneMalloc(NULL, 3 * stringLength + 1);
        query = allocatedQuery;
    }
    cursor = [array->_data bytes];
    end = cursor + [array->_data length];
    if (array->_data == nil)
        return 0;
    queryLength = _NSStringArrayEncodeString(string, (char *)query);
    ((char *)query)[queryLength] = 0;
    if (option == 2)
        _NSStringArrayBuildSubstringShifts(shifts, query, queryLength);
    while (cursor < end) {
        unsigned length = _NSStringArrayByteLength(cursor);
        BOOL isMatch = option == 2
            ? _NSStringArrayByteSubstringMatch(cursor, length, query,
                                               queryLength, shifts)
            : _NSStringArrayByteMatch(cursor, length, query, queryLength,
                                      option);
        if (isMatch) {
            if (bitVector != NULL) {
                if (bits == NULL) {
                    bits = NSZoneMalloc(NULL, ([array count] + 7) >> 3);
                    memset(bits, 0, ([array count] + 7) >> 3);
                }
                bits[index >> 3] |= (unsigned char)(1U << (index & 7));
            }
            matched++;
            lastMatch = index;
        }
        cursor += length + 1;
        index++;
    }
    if (allocatedQuery != NULL)
        NSZoneFree(NULL, allocatedQuery);
    if (bits != NULL) {
        *bitVector = [NSData dataWithBytes:bits length:(lastMatch + 8) >> 3];
        NSZoneFree(NULL, bits);
    }
    return (int)matched;
}

static int _NSStringArrayFindStringArray(NSStringArray *array,
                                        NSStringArray *queries,
                                        unsigned option,
                                        NSData **bitVector) {
    unsigned char *bits = NULL;
    unsigned lastMatch = 0;
    unsigned matched = 0;
    unsigned index;
    NSData *queryData = [queries UTF8Data];
    const char *queryStart = [queryData bytes];
    unsigned queryDataLength = [queryData length];
    const char *queryEnd = queryStart != NULL
        ? queryStart + queryDataLength : NULL;
    const char *candidate = [array->_data bytes];
    unsigned candidateDataLength = [array->_data length];
    const char *candidateEnd = candidate != NULL
        ? candidate + candidateDataLength : NULL;

    if ([queries count] == 0 || candidate == NULL || queryStart == NULL ||
        queryStart >= queryEnd)
        return 0;
    for (index = 0; candidate < candidateEnd; index++) {
        unsigned candidateLength = _NSStringArrayByteLength(candidate);
        const char *query = queryStart;
        BOOL found = NO;
        while (query < queryEnd) {
            unsigned queryLength = _NSStringArrayByteLength(query);
            if (_NSStringArrayByteMatch(candidate, candidateLength, query,
                                        queryLength, option)) {
                found = YES;
                break;
            }
            query += queryLength + 1;
        }
        if (found) {
            if (bitVector != NULL && bits == NULL) {
                bits = NSZoneMalloc(NULL, ([array count] + 7) >> 3);
                memset(bits, 0, ([array count] + 7) >> 3);
            }
            if (bits != NULL)
                bits[index >> 3] |= (unsigned char)(1U << (index & 7));
            matched++;
            lastMatch = index;
        }
        candidate += candidateLength + 1;
    }
    if (bits != NULL) {
        *bitVector = [NSData dataWithBytes:bits length:(lastMatch + 8) >> 3];
        NSZoneFree(NULL, bits);
    }
    return (int)matched;
}

static NSData *_NSStringArrayBitVectorForStrings(NSStringArray *strings,
                                                 NSMapTable *map,
                                                 NSMutableData **newStrings,
                                                 BOOL createVector) {
    unsigned count = [strings count];
    unsigned index;
    unsigned lastIndex = 0;
    unsigned char *bits = NULL;
    const char *key = [[strings UTF8Data] bytes];
    NSData *data;

    for (index = 0; index < count; index++) {
        unsigned length = _NSStringArrayByteLength(key);
        void *value = NULL;
        if (!NSMapMember(map, key, NULL, &value)) {
            unsigned position = NSCountMapTable(map);
            NSMapInsertKnownAbsent(map, key, (const void *)(uintptr_t)position);
            if (*newStrings == nil)
                *newStrings = [[NSMutableData alloc] initWithCapacity:64];
            [*newStrings appendBytes:key length:length + 1];
            value = (void *)(uintptr_t)position;
        }
        if (createVector) {
            unsigned position = (unsigned)(uintptr_t)value;
            unsigned mapCount = NSCountMapTable(map);
            unsigned byteCount = (count + mapCount + 7) >> 3;
            if (bits == NULL)
                bits = NSZoneCalloc(NULL, byteCount, 1);
            bits[position >> 3] |= (unsigned char)(1U << (position & 7));
            if (position > lastIndex)
                lastIndex = position;
        }
        key += length + 1;
    }
    if (!createVector)
        return nil;
    data = [NSData allocWithZone:NULL];
    if (bits == NULL)
        return [data init];
    data = [data initWithBytes:bits length:(lastIndex + 8) >> 3];
    NSZoneFree(NULL, bits);
    return data;
}

static char *_NSStringArrayAppendWords(char *output, NSHashTable *seen,
                                      const unsigned char *bytes,
                                      const unsigned char *end, unsigned mode,
                                      unsigned convertCase) {
    const unsigned char *cursor = bytes;

    while (cursor < end) {
        const unsigned char *start;
        const unsigned char *wordEnd;
        unsigned char character = *cursor;

        if (mode == 2 && character == '<') {
            while (cursor < end && *cursor != '>')
                cursor++;
            if (cursor < end)
                cursor++;
            continue;
        }
        if (mode == 1 && character == '\\') {
            cursor++;
            while (cursor < end
                   && ((*cursor >= 'A' && *cursor <= 'Z')
                       || (*cursor >= 'a' && *cursor <= 'z')
                       || (*cursor >= '0' && *cursor <= '9')))
                cursor++;
            continue;
        }
        if (!((character >= 'A' && character <= 'Z')
              || (character >= 'a' && character <= 'z')
              || character == '_')) {
            cursor++;
            continue;
        }
        start = cursor++;
        while (cursor < end) {
            character = *cursor;
            if (!((character >= 'A' && character <= 'Z')
                  || (character >= 'a' && character <= 'z')
                  || (character >= '0' && character <= '9')))
                break;
            cursor++;
        }
        wordEnd = cursor;
        {
            char *word = output;
            const unsigned char *wordCursor;
            for (wordCursor = start; wordCursor < wordEnd; wordCursor++) {
                unsigned char value = *wordCursor;
                if (convertCase == 1 && value >= 'A' && value <= 'Z')
                    value += 'a' - 'A';
                else if (convertCase == 2 && value >= 'a' && value <= 'z')
                    value -= 'a' - 'A';
                *output++ = value;
            }
            *output++ = 0;
            if (NSHashInsertIfAbsent(seen, word) != NULL)
                output = word;
        }
    }
    return output;
}

static id _NSStringArrayInitWithExtractedWords(NSStringArray *self,
                                               NSData *data,
                                               const unsigned char *inputEnd,
                                               unsigned length,
                                               unsigned mode,
                                               unsigned convertCase) {
    NSHashTable *seen = _NSStringArrayWordTable(length >> 3);
#if defined(__ppc__) || defined(__POWERPC__)
    NSMutableData *packed = [[NSMutableData allocWithZone:NULL]
        initWithCapacity:length + 1];
#else
    NSMutableData *packed = [[NSMutableData allocWithZone:NULL]
        initWithLength:length + 1];
#endif
    char *start = [packed mutableBytes];
    const unsigned char *bytes = [data bytes];
    char *outputEnd = _NSStringArrayAppendWords(start, seen, bytes, inputEnd,
                                                mode, convertCase);
    id result;
    NSFreeHashTable(seen);
    [packed setLength:(unsigned)(outputEnd - start)];
    result = [self initWithUTF8Data:packed];
    [packed release];
    return result;
}

@implementation NSStringArray

+ (id)stringArray {
    return __NSEmptyStringArray;
}

+ (id)stringArrayWithUTF8Data:(NSData *)data {
    NSStringArray *array = [[NSStringArray allocWithZone:NULL]
        initWithUTF8Data:data];
    return [array autorelease];
}

+ (id)stringArrayWithArray:(NSArray *)array {
    NSStringArray *result = [[NSStringArray allocWithZone:NULL] initWithArray:array];
    return [result autorelease];
}

+ (id)stringArrayWithComponents:(NSString *)components
              separatedByString:(NSString *)separator {
    NSStringArray *result = [[NSStringArray allocWithZone:NULL]
        initWithComponents:components separatedByString:separator];
    return [result autorelease];
}

- (id)init {
    [self dealloc];
    return [[NSStringArray stringArray] retain];
}

- (id)initWithUTF8Data:(NSData *)data {
    if ([data length] == 0) {
        [self release];
        return nil;
    }
    _count = UINT_MAX;
    _data = [data copyWithZone:NULL];
    return self;
}

- (id)initWithArray:(NSArray *)array {
    char stackBuffer[1028];
    char *buffer = stackBuffer;
    unsigned capacity = 0;
    unsigned count;
    unsigned index;
    unsigned used = 0;
    NSData *packed;
    NSStringArray *result;

    if ([array isKindOfClass:__NSStringArrayClass]) {
        [self dealloc];
        return [array retain];
    }
    count = [array count];
    for (index = 0; index < count; index++) {
        id object = [array objectAtIndex:index];
        if ([object isKindOfClass:[NSString class]])
            capacity += 3 * [object length] + 1;
        else
            NSLog(@"%@: skipping non string at %d: '%@'",
                  _NSMethodExceptionProem(self, _cmd), index, object);
    }
    if (capacity > 0x3ff)
        buffer = NSZoneMalloc(NULL, capacity);
    for (index = 0; index < count; index++) {
        id object = [array objectAtIndex:index];
        if ([object isKindOfClass:[NSString class]]) {
            used += _NSStringArrayEncodeString(object, buffer + used);
            buffer[used++] = '\0';
        }
    }
    packed = [[NSData allocWithZone:NULL] initWithBytes:buffer length:used];
    result = [self initWithUTF8Data:packed];
    result->_count = count;
    [packed release];
    if (buffer != stackBuffer)
        NSZoneFree(NULL, buffer);
    return result;
}

- (id)initWithComponents:(NSString *)components
      separatedByString:(NSString *)separator {
    if ([separator length] == 1) {
        unichar separatorCharacter = [separator characterAtIndex:0];
        NSData *data = [components dataUsingEncoding:NSASCIIStringEncoding
                                  allowLossyConversion:NO];
        if (separatorCharacter <= 0x7f && data != nil) {
            NSMutableData *packed = [data mutableCopyWithZone:NULL];
            unsigned char nul = 0;
            unsigned char *bytes;
            unsigned length = [packed length];
            unsigned index;
            [packed appendBytes:&nul length:1];
            bytes = [packed mutableBytes];
            for (index = 0; index < length; index++) {
                if (bytes[index] == (unsigned char)separatorCharacter)
                    bytes[index] = 0;
            }
            bytes[length] = 0;
            {
                id result = [self initWithUTF8Data:packed];
                [packed release];
                return result;
            }
        }
    }
    return [self initWithArray:[components componentsSeparatedByString:separator]];
}

- (unsigned)count {
    if (_count == UINT_MAX) {
        if (_data == nil) {
            _count = 0;
        } else {
            const unsigned char *bytes = [_data bytes];
            unsigned length = [_data length];
            unsigned index;
            if (length != 0 && bytes[length - 1] != 0)
                [NSException raise:NSInvalidArgumentException
                            format:@"%@: Incorrect UTF8 buffer",
                                    _NSMethodExceptionProem(self, _cmd)];
            _count = 0;
            for (index = 0; index < length; index++)
                if (bytes[index] == 0)
                    _count++;
            if (_count == 0) {
                id proem = _NSMethodExceptionProem(self, _cmd);
#if defined(__ppc__) || defined(__POWERPC__)
                NSLog(@"%@: Invariant broken: NULL _count for 0x%x",
                      proem, self);
#else
                NSLog(@"%@: Invariant broken: NULL _count for 0x%x", proem);
#endif
            }
        }
    }
    return _count;
}

- (id)objectAtIndex:(unsigned)index {
    if (_strings == NULL && _data != nil) {
        const unsigned char *bytes = [_data bytes];
        unsigned length = [_data length];
        unsigned count;
        unsigned scan;
        unsigned cursor = 0;
        unsigned item = 0;
        Class asciiStringClass;
        Class nonASCIIStringClass;
        struct _NSStringArrayStringRecord {
            Class isa;
            NSStringArray *array;
            void *value;
            unsigned length;
        } *records;

        asciiStringClass = [_NSUTF8ASCIIString class];
        nonASCIIStringClass = [_NSUTF8NonASCIIString class];
        if (length != 0 && bytes[length - 1] != 0)
            [NSException raise:NSInvalidArgumentException
                        format:@"%@: Incorrect UTF8 buffer",
                                _NSMethodExceptionProem(self, _cmd)];
        count = _count;
        if (count != 0) {
            count = 0;
            for (scan = 0; scan < length; scan++)
                if (bytes[scan] == 0)
                    count++;
            _count = count;
        }
        records = NSZoneMalloc(NULL, count * sizeof(*records));
        _strings = records;
        while (cursor < length && item < count) {
            unsigned start = cursor;
            BOOL ascii = YES;
            while (cursor < length && bytes[cursor] != 0) {
                if (bytes[cursor] & 0x80)
                    ascii = NO;
                cursor++;
            }
            records[item].array = self;
            if (ascii) {
                records[item].isa = asciiStringClass;
                records[item].value = (void *)(bytes + start);
                records[item].length = cursor - start;
            } else {
                NSString *decoded = [[NSString allocWithZone:NULL]
                    initWithBytes:bytes + start length:cursor - start
                    encoding:NSUTF8StringEncoding];
                records[item].isa = nonASCIIStringClass;
                records[item].value = decoded;
                records[item].length = [decoded length];
            }
            cursor++;
            item++;
        }
    }
    if (index >= [self count]) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        unsigned count = [self count];
        [NSException raise:NSRangeException
                    format:@"%@: index (%d) beyond bounds (%d)",
                            proem, index, count];
    }
    return (id)((char *)_strings + 16 * index);
}

- (NSData *)UTF8Data {
    return _data != nil ? _data : [NSData data];
}

- (BOOL)containsObject:(id)object {
    unsigned length;
    unsigned capacity;
    char local[193];
    char *encoded = local;
    const char *cursor;
    const char *end;
    unsigned encodedLength;

    length = [object length];
    capacity = 3 * length + 1;
    if (length > 0x3f)
        encoded = NSZoneMalloc(NULL, capacity);
    cursor = [_data bytes];
    end = cursor + [_data length];
    if (_data == nil)
        return NO;
    encodedLength = _NSStringArrayEncodeString(object, encoded);
    encoded[encodedLength] = 0;
    while (cursor < end) {
        if (strcmp(cursor, encoded) == 0) {
            if (encoded != local)
                NSZoneFree(NULL, encoded);
            return YES;
        }
        cursor += _NSStringArrayByteLength(cursor) + 1;
    }
    if (encoded != local)
        NSZoneFree(NULL, encoded);
    return NO;
}

- (id)stringArrayByAppendingStringArray:(NSStringArray *)array {
    NSMutableData *data = _data != nil
        ? [_data mutableCopyWithZone:NULL]
        : [[NSMutableData allocWithZone:NULL] initWithCapacity:128];
    NSData *addition = array->_data;
    NSStringArray *result;
    if (addition != nil)
        [data appendData:addition];
    result = [[NSStringArray allocWithZone:NULL] initWithUTF8Data:data];
    [data release];
    return [result autorelease];
}

- (id)stringArrayByAppendingStringArrays:(NSArray *)arrays
                    resultingBitVectors:(NSArray **)bitVectors {
    NSMapTableKeyCallBacks keyCallbacks = {
        _NSMapTableHashCString, _NSMapTableIsEqualCString, NULL, NULL, NULL, NULL
    };
    NSMapTableValueCallBacks valueCallbacks = { NULL, NULL, NULL };
    NSMapTable *map = NSCreateMapTable(keyCallbacks, valueCallbacks, [self count]);
    NSMutableData *newStrings = nil;
    NSMutableArray *vectors = nil;
    unsigned index;
    id result = self;

    if (_data == nil)
        _data = [[NSData allocWithZone:NULL] initWithBytes:NULL length:0];
    {
        const char *cursor = [_data bytes];
        unsigned count = [self count];
        for (index = 0; index < count; index++) {
            unsigned length = _NSStringArrayByteLength(cursor);
            NSMapInsertKnownAbsent(map, cursor, (const void *)(uintptr_t)index);
            cursor += length + 1;
        }
    }
    if (bitVectors != NULL) {
        vectors = [NSMutableArray arrayWithCapacity:[arrays count]];
        *bitVectors = vectors;
    }
    for (index = 0; index < [arrays count]; index++) {
        NSData *vector = _NSStringArrayBitVectorForStrings(
            [arrays objectAtIndex:index], map, &newStrings, bitVectors != NULL);
        if (vectors != nil)
            [vectors addObject:vector];
        [vector release];
    }
    if (newStrings != nil) {
        NSStringArray *addition = [[NSStringArray allocWithZone:NULL]
            initWithUTF8Data:newStrings];
        result = [self stringArrayByAppendingStringArray:addition];
        [addition release];
        [newStrings release];
    }
    NSFreeMapTable(map);
    return result;
}

- (id)bitVectorMatchingString:(NSString *)string option:(unsigned)option {
    NSData *vector = nil;
    if (_NSStringArrayFindString(self, string, option, &vector) == 0)
        return nil;
    return vector;
}

- (BOOL)matchesString:(NSString *)string option:(unsigned)option {
    return _NSStringArrayFindString(self, string, option, NULL) != 0;
}

- (id)bitVectorMatchingStringArray:(NSStringArray *)array
                            option:(unsigned)option {
    NSData *vector = nil;
    if (_NSStringArrayFindStringArray(self, array, option, &vector) == 0)
        return nil;
    return vector;
}

- (BOOL)matchesStringArray:(NSStringArray *)array option:(unsigned)option
        eachMustBeMatched:(BOOL)eachMustBeMatched {
    NSData *queryData;
    const char *query;
    const char *queryEnd;
    if (!eachMustBeMatched)
        return _NSStringArrayFindStringArray(self, array, option, NULL) != 0;
    if (_data == nil || [array count] == 0)
        return NO;
    queryData = [array UTF8Data];
    query = [queryData bytes];
    if (query == NULL)
        return NO;
    queryEnd = query + [queryData length];
    while (query < queryEnd) {
        unsigned queryLength = _NSStringArrayByteLength(query);
        if (!_NSStringArrayContainsQuery(self, query, queryLength, option))
            return NO;
        query += queryLength + 1;
    }
    return YES;
}

- (id)stringArrayWithBitVector:(NSData *)bitVector {
    const unsigned char *bits = [bitVector bytes];
    unsigned bitCount = 8 * [bitVector length];
    const char *cursor;
    const char *end;
    unsigned index = 0;
    NSMutableData *selected = nil;
    if (bitCount == 0)
        return nil;
    if (_data == nil)
        _data = [[NSData allocWithZone:NULL] initWithBytes:NULL length:0];
    cursor = [_data bytes];
    end = cursor + [_data length];
    while (cursor < end) {
        unsigned length;
        if (index >= bitCount)
            break;
        length = _NSStringArrayByteLength(cursor);
        if ((bits[index >> 3] & (1U << (index & 7))) != 0) {
            if (selected == nil)
                selected = [[NSMutableData allocWithZone:NULL]
                    initWithCapacity:(unsigned)(end - cursor)];
            [selected appendBytes:cursor length:length + 1];
        }
        cursor += length + 1;
        index++;
    }
    if (selected == nil)
        return nil;
    {
        id result = [NSStringArray stringArrayWithUTF8Data:selected];
        [selected release];
        return result;
    }
}

- (id)initWithWordsOfString:(NSString *)string convertCase:(unsigned)convertCase
                     locale:(NSDictionary *)locale {
    unsigned pool = NSPushAutoreleasePool();
    NSScanner *scanner = [NSScanner scannerWithString:string];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];
    NSCharacterSet *separators = [alphanumeric invertedSet];
    NSHashTable *seen = NSCreateHashTable(NSNonRetainedObjectHashCallBacks,
                                           [string length] >> 3);
    NSString *word;

    if (locale != nil)
        [scanner setLocale:locale];
    [scanner setCharactersToBeSkipped:separators];
    while ([scanner scanUpToCharactersFromSet:separators intoString:&word]) {
        if ([word length] != 0
            && [letters characterIsMember:[word characterAtIndex:0]]) {
            if (convertCase == 1)
                word = [word lowercaseString];
            else if (convertCase == 2)
                word = [word uppercaseString];
            NSHashInsert(seen, word);
        }
    }
    {
        NSArray *words = NSAllHashTableObjects(seen);
        id result = [self initWithArray:words];
        NSFreeHashTable(seen);
        NSPopAutoreleasePool(pool);
        return result;
    }
}

- (id)initWithWordsOfData:(NSData *)data convertCase:(unsigned)convertCase
                    locale:(NSDictionary *)locale {
    unsigned length = [data length];
    const unsigned char *bytes = [data bytes];
    const unsigned char *end = bytes + length;
    unsigned index;
    for (index = 0; index < length; index++) {
        if (bytes[index] & 0x80) {
            NSString *allocated;
            NSStringEncoding encoding;
#if defined(__ppc__) || defined(__POWERPC__)
            allocated = [NSString allocWithZone:NULL];
            encoding = [NSString defaultCStringEncoding];
#else
            encoding = [NSString defaultCStringEncoding];
            allocated = [NSString allocWithZone:NULL];
#endif
            NSString *string = [allocated initWithData:data encoding:encoding];
            {
                id result = [self initWithWordsOfString:string
                    convertCase:convertCase locale:locale];
                [string release];
                return result;
            }
        }
    }
    return _NSStringArrayInitWithExtractedWords(self, data, end, length, 0,
                                                 convertCase);
}

- (id)initWithWordsOfHTMLData:(NSData *)data convertCase:(unsigned)convertCase {
    unsigned length = [data length];
    const unsigned char *bytes = [data bytes];
    const unsigned char *end = bytes + length;
    return _NSStringArrayInitWithExtractedWords(self, data, end, length, 2,
                                                 convertCase);
}

- (id)initWithWordsOfRTFData:(NSData *)data convertCase:(unsigned)convertCase {
    unsigned length = [data length];
    const unsigned char *bytes = [data bytes];
    const unsigned char *end = bytes + length;
    return _NSStringArrayInitWithExtractedWords(self, data, end, length, 1,
                                                 convertCase);
}

- (unsigned)retainCount {
    return _extraRefCount == UINT_MAX ? UINT_MAX : _extraRefCount + 1;
}

- (id)retain {
    _NSStringArrayRetainOwner(self);
    return self;
}

- (void)release {
    if (_NSStringArrayReleaseOwner(self))
        [self dealloc];
}

- (void)dealloc {
    if (_strings != NULL) {
        struct _NSStringArrayStringRecord {
            Class isa;
            NSStringArray *array;
            void *value;
            unsigned length;
        } *records = _strings;
        unsigned count = [self count];
        Class nonASCIIStringClass = [_NSUTF8NonASCIIString class];
        while (count != 0) {
            --count;
            if (records[count].isa == nonASCIIStringClass)
                [(id)records[count].value release];
        }
        NSZoneFree(NULL, _strings);
    }
    [_data release];
    [super dealloc];
}

@end

@implementation _NSUTF8String

+ (id)allocWithZone:(NSZone *)zone {
    (void)zone;
    [NSException raise:NSInvalidArgumentException
                format:@"%@: Can't alloc _NSUTF8String",
                       _NSMethodExceptionProem(self, _cmd)];
    return nil;
}

- (id)init {
    [NSException raise:NSInvalidArgumentException
                format:@"%@: Can't init _NSUTF8String",
                       _NSMethodExceptionProem(self, _cmd)];
    return nil;
}

- (void)dealloc {
    [NSException raise:NSInvalidArgumentException
                format:@"%@: Can't dealloc _NSUTF8String",
                       _NSMethodExceptionProem(self, _cmd)];
}

- (id)retain {
    _NSStringArrayRetainOwner(_array);
    return self;
}

- (void)release {
    if (_NSStringArrayReleaseOwner(_array))
        [_array dealloc];
}

- (unsigned)retainCount {
    return UINT_MAX;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    _NSStringArrayRetainOwner(_array);
    return self;
}

@end

@implementation _NSUTF8ASCIIString

- (unsigned)length {
    return _length;
}

- (unichar)characterAtIndex:(unsigned)index {
    if (index >= _length)
        [NSException raise:NSRangeException
                    format:@"%@: location %d of bounds",
                            _NSMethodExceptionProem(self, _cmd), index];
    return (unsigned char)_bytes[index];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    unsigned index;
    if (range.location + range.length > _length)
        [NSException raise:NSRangeException
                    format:@"%@: Range %@ of bounds",
                            _NSMethodExceptionProem(self, _cmd),
                            NSStringFromRange(range)];
    for (index = 0; index < range.length; index++)
        buffer[index] = (unsigned char)_bytes[range.location + index];
}

- (unsigned)hash {
    return _NSStringArrayHashCString((const unsigned char *)_bytes, _length);
}

- (const char *)cString {
    return _bytes;
}

- (unsigned)cStringLength {
    return _length;
}

- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding {
    return encoding == _NSCStringEncoding
        || [super canBeConvertedToEncoding:encoding];
}

- (NSStringEncoding)fastestEncoding {
    return _NSCStringEncoding;
}

- (NSStringEncoding)smallestEncoding {
    return _NSCStringEncoding;
}

- (BOOL)getBytes:(void *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)lossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange {
    (void)lossy;
    if (encoding == _NSCStringEncoding) {
        unsigned length = range.length;
        if (length > maxLength)
            length = maxLength;
        if (buffer != NULL)
            memmove(buffer, _bytes + range.location, length);
        if (usedLength != NULL)
            *usedLength = length;
        if (remainingRange != NULL)
            *remainingRange = NSMakeRange(range.location + length,
                                          range.length - length);
        return YES;
    }
    return [super getBytes:buffer maxLength:maxLength filledLength:usedLength
        encoding:encoding allowLossyConversion:lossy range:range
        remainingRange:remainingRange];
}

@end

@implementation _NSUTF8NonASCIIString

- (unsigned)length {
    return _length;
}

- (unichar)characterAtIndex:(unsigned)index {
    return [_realString characterAtIndex:index];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    [_realString getCharacters:buffer range:range];
}

- (unsigned)hash {
    return [_realString hash];
}

@end
