/*	NSSerialization.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSSerialization.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>

#include <string.h>

@class NSInvocation;

extern NSString *__NSEmptyString;
extern id _NSMethodExceptionProem(id object, SEL selector);

@interface NSString (NSSerializationBytes)
- (id)initWithBytes:(const char *)bytes length:(unsigned)length encoding:(unsigned)encoding;
@end

@interface NSData (NSSerializationBytes)
- (id)initWithBytes:(const void *)bytes length:(unsigned)length
               copy:(BOOL)copy freeWhenDone:(BOOL)freeWhenDone
        bytesAreVM:(BOOL)bytesAreVM;
@end

@interface NSFaultHandler : NSObject
{
    Class _targetClass;
    void *_extraData;
    unsigned _extraRefCount;
}
- (void)setTargetClass:(Class)aClass extraData:(void *)data;
- (void)incrementExtraRefCount;
- (void)completeInitializationOfObject:(id)object;
- (BOOL)shouldPerformInvocation:(NSInvocation *)invocation;
@end

@interface NSObject (NSSerializationArchiveObjects)
- (void)encodeObject:(id)object isBycopy:(BOOL)bycopy isByref:(BOOL)byref;
- (id)decodeRetainedObject;
@end

@interface NSFault
{
    Class isa;
    NSFaultHandler *_handler;
}
+ (void)makeObjectIntoFault:(id)object withHandler:(NSFaultHandler *)handler;
+ (void)clearFault:(id)object;
+ (id)handlerForFault:(id)object;
- (BOOL)isFault;
- (void)doesNotRecognizeSelector:(SEL)selector;
- (id)autorelease;
@end

@interface _NSLazyDeserializationFault : NSFault
- (NSArray *)allKeys;
- (id)objectForKey:(id)key;
- (unsigned)count;
- (id)objectAtIndex:(unsigned)index;
@end

@interface _NSLazyDeserializationFaultHandler : NSFaultHandler
{
@public
    NSData *_data;
    NSRange _range;
    unsigned _cnt;
    unsigned _lazy;
    NSArray *_keys;
    BOOL _mutable;
    BOOL _isDict;
}
- (id)initWithData:(NSData *)data range:(NSRange)range count:(unsigned)count
           mutable:(BOOL)mutableContainers lazyThreshold:(unsigned)threshold
            isDict:(BOOL)isDict;
- (void)completeInitializationOfObject:(id)object;
- (void)serializeIntoData:(NSMutableData *)data;
@end

id _NSDeserializeObject(id serializer, NSData *data, unsigned *cursor,
                        BOOL mutableContainers, NSZone *zone,
                        unsigned lazyThreshold);
static unsigned NSDeserializerLazyThreshold;

typedef struct {
    void *owner;
    unsigned char *cursor;
    unsigned char *end;
} NSFastDecoderContext;

int
decodeFastByte(NSFastDecoderContext *context)
{
    if (context->end < context->cursor)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more string data to decode"];
    return *context->cursor++;
}

static void decodeFastInt(NSFastDecoderContext *context, void *destination,
                          unsigned length)
{
    signed char encodedLength;
    unsigned count;
    unsigned index;
    unsigned char signByte = 0;

    if ((unsigned long)context->cursor + 1 > (unsigned long)context->end)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more int data to decode (case %d)", 1];

    encodedLength = (signed char)*context->cursor++;
    if ((unsigned long)context->cursor + encodedLength
        > (unsigned long)context->end)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more int data to decode (case %d)", 2];

    if (encodedLength < 0) {
        signByte = 0xff;
        count = (unsigned)(-(int)encodedLength);
    } else {
        count = (unsigned)encodedLength;
    }

    if (count > length)
        [NSException raise:NSRangeException
                    format:@"more significant bytes than room to hold them"];

#if defined(__ppc__) || defined(__POWERPC__)
    for (index = 0; index < count; index++)
        ((unsigned char *)destination)[length - index - 1] =
            *context->cursor++;
    for (; index < length; index++)
        ((unsigned char *)destination)[length - index - 1] = signByte;
#else
    for (index = 0; index < count; index++)
        ((unsigned char *)destination)[index] = *context->cursor++;
    for (; index < length; index++)
        ((unsigned char *)destination)[index] = signByte;
#endif
}

static void *decodeFastData(NSFastDecoderContext *context, unsigned length)
{
    unsigned char *data = context->cursor;
    unsigned long end = (unsigned long)data + length;

    context->cursor = (unsigned char *)end;
    if (end > (unsigned long)context->end)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more data to decode"];
    return data;
}

static void *decodeFastCharStar(NSFastDecoderContext *context)
{
    unsigned length;
    unsigned long end;
    void *data;

    if ((unsigned char)decodeFastByte(context) == 0)
        return NULL;

    decodeFastInt(context, &length, sizeof(length));
    data = context->cursor;
    end = (unsigned long)context->cursor + length;
    if (end > (unsigned long)context->end)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more string data to decode"];
    context->cursor = (unsigned char *)end;
    return data;
}

static void NSSerializerAppendPropertyList(id object, NSMutableData *data,
                                          id serializer, SEL selector) {
    unsigned count;

    if (object == nil) {
        [data serializeInt:8];
        return;
    }

    if ([(NSFault *)object isFault]) {
        id handler = [NSFault handlerForFault:object];

        if ([handler isKindOfClass:[_NSLazyDeserializationFaultHandler class]]) {
            [handler serializeIntoData:data];
            return;
        }
    }

    if ([object isKindOfClass:[NSString class]]) {
        NSString *string = object;
        const char *interned = NULL;
        unsigned length;
        NSData *bytes;
        int zero = 0;

        if ([string isEqualToString:@"YES"])
            interned = "YES";
        else if ([string isEqualToString:@"NO"])
            interned = "NO";
        else if ([string isEqualToString:@"Yes"])
            interned = "Yes";
        else if ([string isEqualToString:@"No"])
            interned = "No";
        else if ([string length] == 1) {
            unichar character = [string characterAtIndex:0];

            if (character >= '0' && character <= '4') {
                char digit = (char)character;

                [data serializeInt:5];
                [data serializeAlignedBytesLength:1];
                [data appendBytes:&digit length:1];
                while (([data length] & 3) != 0)
                    [data appendBytes:&zero length:1];
                return;
            }
        }

        if (interned != NULL) {
            length = (unsigned)strlen(interned);
            [data serializeInt:5];
            [data serializeAlignedBytesLength:length];
            [data appendBytes:interned length:length];
            while (([data length] & 3) != 0)
                [data appendBytes:&zero length:1];
            return;
        }

        bytes = [string dataUsingEncoding:NSUnicodeStringEncoding];
        length = (unsigned)[bytes length];
        [data serializeInt:6];
        [data serializeAlignedBytesLength:length];
        if (length != 0)
            [data appendBytes:[bytes bytes] length:length];
        while (([data length] & 3) != 0)
            [data appendBytes:&zero length:1];
        return;
    }

    if ([object isKindOfClass:[NSData class]]) {
        NSData *bytes = object;
        unsigned length = (unsigned)[bytes length];
        int zero = 0;

        [data serializeInt:4];
        [data serializeAlignedBytesLength:length];
        if (length != 0)
            [data appendBytes:[bytes bytes] length:length];
        while (([data length] & 3) != 0)
            [data appendBytes:&zero length:1];
        return;
    }

    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = object;
        unsigned stackLengths[128] = { 0 };
        unsigned *lengths = stackLengths;
        unsigned lengthIndex;
        unsigned tableIndex;

        count = [array count];
        [data serializeInt:2];
        [data serializeInt:(int)count];
        if (count > 128) {
            lengths = (unsigned *)NSZoneMalloc(NULL, count * sizeof(*lengths));
            memset(lengths, 0, count * sizeof(*lengths));
        }
        tableIndex = (unsigned)[data length];
        [data serializeInts:(int *)lengths count:count];
        for (lengthIndex = 0; lengthIndex < count; lengthIndex++) {
            unsigned start = (unsigned)[data length];

            NSSerializerAppendPropertyList([array objectAtIndex:lengthIndex],
                                           data, serializer, selector);
            [data serializeInt:(int)([data length] - start)
                       atIndex:tableIndex + lengthIndex * sizeof(int)];
        }
        if (lengths != stackLengths)
            NSZoneFree(NULL, lengths);
        return;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = object;
        unsigned stackLengths[64] = { 0 };
        unsigned *lengths = stackLengths;
        id stackKeys[64];
        id *keys = stackKeys;
        id enumerator;
        unsigned index;
        unsigned tableIndex;

        count = [dictionary count];
        [data serializeInt:7];
        [data serializeInt:(int)count];
        if (count > 64) {
            keys = (id *)NSZoneMalloc(NULL, count * sizeof(*keys));
            lengths = (unsigned *)NSZoneMalloc(NULL, count * sizeof(*lengths));
            memset(lengths, 0, count * sizeof(*lengths));
        }
        enumerator = [dictionary keyEnumerator];
        for (index = 0; index < count; index++)
            keys[index] = [enumerator nextObject];
        for (index = 0; index < count; index++)
            NSSerializerAppendPropertyList(keys[index], data, serializer,
                                           selector);

        tableIndex = (unsigned)[data length];
        [data serializeInts:(int *)lengths count:count];
        for (index = 0; index < count; index++) {
            unsigned start = (unsigned)[data length];

            NSSerializerAppendPropertyList([dictionary objectForKey:keys[index]],
                                           data, serializer, selector);
            [data serializeInt:(int)([data length] - start)
                       atIndex:tableIndex + index * sizeof(int)];
        }
        if (keys != stackKeys)
            NSZoneFree(NULL, keys);
        if (lengths != stackLengths)
            NSZoneFree(NULL, lengths);
        return;
    }

    NSLog(@"%@: Cannot serialize object '%@' of class '%s' -- not a property list.",
          _NSMethodExceptionProem(serializer, selector), object,
          ((Class)object)->isa->name);
    [data serializeInt:8];
}

static unsigned NSDeserializerAlignedLength(NSData *data, unsigned *cursor) {
    return [data deserializeAlignedBytesLengthAtCursor:cursor];
}

#if defined(__ppc__) || defined(__POWERPC__)
static unsigned NSDeserializerSumLengths(NSData *data, unsigned *cursor,
                                         unsigned count) {
    int lengths[128];
    unsigned total = 0;
    unsigned index;

    for (index = 0; index < count; index += 128) {
        unsigned chunk = count - index;
        unsigned lengthIndex;

        if (chunk > 128)
            chunk = 128;
        [data deserializeInts:lengths count:chunk atCursor:cursor];
        for (lengthIndex = 0; lengthIndex < chunk; lengthIndex++)
            total += (unsigned)lengths[lengthIndex];
    }
    return total;
}
#endif

static id NSDeserializerObjectFromData(_NSLazyDeserializationFaultHandler *handler,
                                       unsigned *cursor, BOOL mutableContainers,
                                       NSZone *zone, unsigned lazyThreshold) {
    return _NSDeserializeObject(nil, handler->_data, cursor, mutableContainers,
                               zone, lazyThreshold);
}

@implementation _NSLazyDeserializationFaultHandler

- (id)initWithData:(NSData *)data range:(NSRange)range count:(unsigned)count
           mutable:(BOOL)mutableContainers lazyThreshold:(unsigned)threshold
            isDict:(BOOL)isDict {
    _data = [data retain];
    _range = range;
    _cnt = count;
    _lazy = threshold;
    _keys = nil;
    _mutable = mutableContainers;
    _isDict = isDict;
    return self;
}

- (void)dealloc {
    [_data release];
    [_keys release];
    [super dealloc];
}

- (void)completeInitializationOfObject:(id)object {
    NSZone *zone = NSZoneFromPointer(object);
    unsigned count = _cnt;
    unsigned index;
    BOOL nestedMutable = _mutable;
    unsigned nestedLazyThreshold = _lazy;

    if (_isDict) {
        id stackKeys[64];
        id stackObjects[64];
        id *keys = count > 64 ? NSZoneMalloc(NULL, count * sizeof(id)) : stackKeys;
        id *objects = count > 64 ? NSZoneMalloc(NULL, count * sizeof(id)) : stackObjects;
        unsigned cursor = _range.location;

        for (index = 0; index < count; index++)
            keys[index] = _NSDeserializeObject(nil, _data, &cursor, NO, zone, 0);
        cursor += count * sizeof(int);
        for (index = 0; index < count; index++)
            objects[index] = _NSDeserializeObject(nil, _data, &cursor,
                                                  nestedMutable, zone,
                                                  nestedLazyThreshold);

        for (index = 0; index < count; index++) {
            if (keys[index] == nil || objects[index] == nil) {
                count--;
                keys[index] = keys[count];
                objects[index] = objects[count];
                index--;
                NSLog(@"*** Attempt to enter nil in a dictionary while deserializing; skipping");
            }
        }

        [NSFault clearFault:object];
        [object initWithObjects:objects forKeys:keys count:count];
        for (index = count; index != 0; index--) {
            [keys[index - 1] release];
            [objects[index - 1] release];
        }
        if (keys != stackKeys)
            NSZoneFree(NULL, keys);
        if (objects != stackObjects)
            NSZoneFree(NULL, objects);
    } else {
        id stackObjects[128];
        id *objects = count > 128 ? NSZoneMalloc(NULL, count * sizeof(id)) : stackObjects;
        unsigned cursor = _range.location + count * sizeof(int);

        for (index = 0; index < count; index++)
            objects[index] = _NSDeserializeObject(nil, _data, &cursor,
                                                  nestedMutable, zone,
                                                  nestedLazyThreshold);
        for (index = 0; index < count; index++) {
            if (objects[index] == nil) {
                count--;
                objects[index] = objects[count];
                index--;
                NSLog(@"*** Attempt to enter nil in an array while deserializing; item skipped");
            }
        }
        [NSFault clearFault:object];
        [object initWithObjects:objects count:count];
        for (index = count; index != 0; index--)
            [objects[index - 1] release];
        if (objects != stackObjects)
            NSZoneFree(NULL, objects);
    }
}

- (void)serializeIntoData:(NSMutableData *)data {
    [data serializeInt:_isDict ? 7 : 2];
    [data serializeInt:(int)_cnt];
    [data appendBytes:(const unsigned char *)[_data bytes] + _range.location
               length:_range.length];
}

@end

@implementation _NSLazyDeserializationFault

- (unsigned)count {
    return ((_NSLazyDeserializationFaultHandler *)[NSFault handlerForFault:self])->_cnt;
}

- (NSArray *)allKeys {
    _NSLazyDeserializationFaultHandler *handler =
        (_NSLazyDeserializationFaultHandler *)[NSFault handlerForFault:self];
    unsigned count;
    unsigned cursor;
    unsigned index;
    id stackKeys[128];
    id *keys;
    NSArray *result;

    if (!handler->_isDict) {
        [self doesNotRecognizeSelector:_cmd];
        return nil;
    }
    if (handler->_keys != nil)
        return handler->_keys;

    count = handler->_cnt;
    cursor = handler->_range.location;
    keys = count > 128 ? NSZoneMalloc(NULL, count * sizeof(id)) : stackKeys;
    for (index = 0; index < count; index++)
        keys[index] = NSDeserializerObjectFromData(handler, &cursor,
                                                   NO, NSZoneFromPointer(self),
                                                   0);
    for (index = 0; index < count; index++) {
        if (keys[index] == nil) {
            count--;
            keys[index] = keys[count];
            index--;
        }
    }

    result = [[NSArray allocWithZone:NSZoneFromPointer(self)]
        initWithObjects:keys count:count];
    for (index = count; index != 0; index--)
        [keys[index - 1] release];
    if (keys != stackKeys)
        NSZoneFree(NULL, keys);
    handler->_keys = result;
    return result;
}

- (id)objectForKey:(id)key {
    _NSLazyDeserializationFaultHandler *handler =
        (_NSLazyDeserializationFaultHandler *)[NSFault handlerForFault:self];
    unsigned count = handler->_cnt;
    unsigned cursor = handler->_range.location;
    unsigned index;
    unsigned keyIndex;
    unsigned precedingLength = 0;
    unsigned valuesStart;
    unsigned valueLength;

    if (!handler->_isDict) {
        [self doesNotRecognizeSelector:_cmd];
        return nil;
    }
    if (count == 0)
        return nil;
    if (handler->_keys == nil)
        [self allKeys];
    keyIndex = (unsigned)[handler->_keys indexOfObject:key];
    if (keyIndex == (unsigned)NSNotFound)
        return nil;

    for (index = 0; index < count; index++) {
        int type = [handler->_data deserializeIntAtCursor:&cursor];
        if (type == 0)
            (void)[handler->_data deserializeIntAtCursor:&cursor];
        valueLength = NSDeserializerAlignedLength(handler->_data, &cursor);
        cursor += (valueLength + 3) & ~3U;
    }
    valuesStart = cursor;
    for (index = 0; index < keyIndex; index++)
        precedingLength += (unsigned)[handler->_data deserializeIntAtCursor:&cursor];

    cursor = valuesStart + precedingLength + count * sizeof(int);
    return NSDeserializerObjectFromData(handler, &cursor, handler->_mutable,
                                        NSZoneFromPointer(self), handler->_lazy);
}

- (id)objectAtIndex:(unsigned)index {
    _NSLazyDeserializationFaultHandler *handler =
        (_NSLazyDeserializationFaultHandler *)[NSFault handlerForFault:self];
    unsigned cursor;
    unsigned precedingLength = 0;
    unsigned item;

    if (handler->_isDict) {
        [self doesNotRecognizeSelector:_cmd];
        return nil;
    }
    if (index >= handler->_cnt) {
#if defined(__ppc__) || defined(__POWERPC__)
        [NSException raise:NSRangeException
                    format:@"%@: index (%d) beyond bounds (%d)",
                           _NSMethodExceptionProem([NSArray array], _cmd),
                           index, handler->_cnt];
#else
        [NSException raise:NSRangeException
                    format:@"%@: index (%d) beyond bounds (%d)",
                           _NSMethodExceptionProem([NSArray array], _cmd)];
#endif
    }

    cursor = handler->_range.location;
    for (item = 0; item < index; item++)
        precedingLength += (unsigned)[handler->_data deserializeIntAtCursor:&cursor];
    cursor = handler->_range.location + precedingLength
        + handler->_cnt * sizeof(int);
    return [NSDeserializerObjectFromData(handler, &cursor, handler->_mutable,
                                         NSZoneFromPointer(self), handler->_lazy)
        autorelease];
}

@end

@implementation NSMutableData

- (void)serializeInt:(int)value {
    unsigned int bits = (unsigned int)value;
    unsigned char bytes[sizeof(value)];

    bytes[0] = (unsigned char)bits;
    bytes[1] = (unsigned char)(bits >> 8);
    bytes[2] = (unsigned char)(bits >> 16);
    bytes[3] = (unsigned char)(bits >> 24);
    [self appendBytes:bytes length:sizeof(bytes)];
}

- (void)serializeInts:(int *)intBuffer count:(unsigned)numInts {
    while (numInts-- != 0)
        [self serializeInt:*intBuffer++];
}

- (void)serializeInt:(int)value atIndex:(unsigned)index {
    unsigned int bits = (unsigned int)value;
    unsigned char bytes[sizeof(value)];

    bytes[0] = (unsigned char)bits;
    bytes[1] = (unsigned char)(bits >> 8);
    bytes[2] = (unsigned char)(bits >> 16);
    bytes[3] = (unsigned char)(bits >> 24);
    [self replaceBytesInRange:NSMakeRange(index, sizeof(value))
                    withBytes:bytes];
}

- (void)serializeInts:(int *)intBuffer count:(unsigned)numInts atIndex:(unsigned)index {
    while (numInts-- != 0) {
        [self serializeInt:*intBuffer++ atIndex:index];
        index += sizeof(int);
    }
}

- (void)serializeAlignedBytesLength:(unsigned)length {
    unsigned pageSize = NSPageSize();
    unsigned currentLength = [self length];

    if (length >= pageSize &&
        ((currentLength + sizeof(int)) & (pageSize - 1)) != 0) {
        unsigned padding = pageSize -
            ((pageSize - 1) & (currentLength + 3 * sizeof(int)));

        [self serializeInt:(int)0x80000000];
        [self serializeInt:(int)length];
        [self serializeInt:(int)padding];
        [self increaseLengthBy:padding];
    } else {
        [self serializeInt:(int)length];
    }
}

@end

@implementation NSData

- (int)deserializeIntAtIndex:(unsigned)index {
    int value;

    [self getBytes:&value range:NSMakeRange(index, sizeof(value))];
    return value;
}

- (void)deserializeInts:(int *)intBuffer count:(unsigned)numInts atIndex:(unsigned)index {
    while (numInts-- != 0) {
        *intBuffer++ = [self deserializeIntAtIndex:index];
        index += sizeof(int);
    }
}

- (int)deserializeIntAtCursor:(unsigned *)cursor {
    int value = [self deserializeIntAtIndex:*cursor];

    *cursor += sizeof(value);
    return value;
}

- (void)deserializeInts:(int *)intBuffer count:(unsigned)numInts atCursor:(unsigned *)cursor {
    while (numInts-- != 0)
        *intBuffer++ = [self deserializeIntAtCursor:cursor];
}

- (unsigned)deserializeAlignedBytesLengthAtCursor:(unsigned *)cursor {
    unsigned length = (unsigned)[self deserializeIntAtCursor:cursor];

    if (length == 0x80000000) {
        length = (unsigned)[self deserializeIntAtCursor:cursor];
        *cursor += (unsigned)[self deserializeIntAtCursor:cursor];
    }
    return length;
}

- (void)deserializeBytes:(void *)buffer length:(unsigned)bytes atCursor:(unsigned *)cursor {
    [self getBytes:buffer range:NSMakeRange(*cursor, bytes)];
    *cursor += bytes;
}

@end

static void NSSerializerAppendFastInteger(NSMutableData *data,
                                           const void *value,
                                           unsigned width) {
    const unsigned char *bytes = (const unsigned char *)value;
    unsigned char encoded[9];
    unsigned payloadLength;
    unsigned length;
    int marker;

    /* The compact integer stream is little-endian on both targets. */
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned index;

    for (index = 0; index < width; index++)
        encoded[index + 1] = bytes[width - index - 1];
#else
    memcpy(encoded + 1, bytes, width);
#endif
    if (encoded[width] == 0) {
        payloadLength = width - 1;
        while (payloadLength > 0 && encoded[payloadLength] == 0)
            payloadLength--;
        marker = (int)payloadLength;
        length = payloadLength + 1;
    } else if (encoded[width] == 0xff) {
        payloadLength = width - 1;
        while (payloadLength > 1 && encoded[payloadLength] == 0xff)
            payloadLength--;
        marker = -(int)payloadLength;
        length = payloadLength + 1;
    } else {
        marker = (int)width;
        length = width + 1;
    }
    encoded[0] = (unsigned char)marker;
    [data appendBytes:encoded length:length];
}

static void NSDataReadFastInteger(NSData *data, unsigned *cursor,
                                  void *value, unsigned width) {
    signed char marker;
    unsigned length;
    unsigned dataLength = [data length];
    unsigned char bytes[8];

    if ((unsigned long)*cursor + 1 > (unsigned long)dataLength)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more int data to decode (case %d)", 1];

    [data getBytes:&marker range:NSMakeRange(*cursor, 1)];
    (*cursor)++;
    if (marker > 0
        && (unsigned long)*cursor + (unsigned)marker
            > (unsigned long)dataLength)
        [NSException raise:NSInternalInconsistencyException
                    format:@"no more int data to decode (case %d)", 2];

    length = marker < 0 ? (unsigned)(-marker) : (unsigned)marker;
    memset(bytes, marker < 0 ? 0xff : 0, width);
    if (length > width)
        [NSException raise:NSRangeException
                    format:@"more significant bytes than room to hold them"];
    if (length != 0) {
        [data getBytes:bytes range:NSMakeRange(*cursor, length)];
        *cursor += length;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    {
        unsigned char *destination = (unsigned char *)value;
        unsigned index;

        for (index = 0; index < width; index++)
            destination[index] = bytes[width - index - 1];
    }
#else
    memcpy(value, bytes, width);
#endif
}

static void NSSerializerAppendCString(NSMutableData *data,
                                      const char *string) {
    unsigned char present = string != NULL;
    unsigned length = 0;

    [data appendBytes:&present length:1];
    if (string == NULL)
        return;
    length = (unsigned)strlen(string) + 1;
    NSSerializerAppendFastInteger(data, &length, sizeof(length));
    [data appendBytes:string length:length];
}

static char *NSDataReadCString(NSData *data, unsigned *cursor) {
    unsigned char present;
    unsigned length;
    char *string;

    [data getBytes:&present range:NSMakeRange(*cursor, 1)];
    (*cursor)++;
    if (!present)
        return NULL;
    NSDataReadFastInteger(data, cursor, &length, sizeof(length));
    string = (char *)NSZoneMalloc(NULL, length);
    [data getBytes:string range:NSMakeRange(*cursor, length)];
    *cursor += length;
    return string;
}

static unsigned NSSerializerBitfieldSizeAndAdvance(const char **type,
                                                    unsigned startOffset) {
    const char *fieldType = *type;
    unsigned bitsInWord = 32 - (8 * startOffset) % 32;
    unsigned bitSpan = 0;

    if (*fieldType == 'b') {
        do {
            const char *fieldStart = fieldType++;
            unsigned width = 0;

            while (*fieldType >= '0' && *fieldType <= '9')
                width = width * 10 + (unsigned)(*fieldType++ - '0');
            if (width != 0) {
                if (bitsInWord < width) {
                    bitSpan += bitsInWord;
                    bitsInWord = 32;
                    fieldType = fieldStart;
                } else {
                    bitSpan += width;
                    bitsInWord -= width;
                }
            } else {
                bitSpan = 32 * ((bitSpan + 8 * startOffset + 31) / 32)
                    - 8 * startOffset;
                bitsInWord = 32 - ((bitSpan + 8 * startOffset) % 32);
            }
        } while (*fieldType == 'b');
    }

    *type = fieldType;
    return (bitSpan + 7) / 8;
}

static unsigned NSSerializerExtractBitfield(const unsigned char *bytes,
                                             unsigned bitOffset,
                                             unsigned width) {
    unsigned value = 0;
    unsigned index;

    for (index = 0; index < width; index++) {
        unsigned sourceBit = bitOffset + index;
#if defined(__ppc__) || defined(__POWERPC__)
        if ((bytes[sourceBit / 8] & (1U << (7 - (sourceBit % 8)))) != 0)
            value |= 1U << (width - index - 1);
#else
        if ((bytes[sourceBit / 8] & (1U << (sourceBit % 8))) != 0)
            value |= 1U << index;
#endif
    }
    return value;
}

static void NSSerializerInsertBitfield(unsigned char *bytes,
                                       unsigned bitOffset,
                                       unsigned width,
                                       unsigned value) {
    unsigned index;

    for (index = 0; index < width; index++) {
        unsigned targetBit = bitOffset + index;
#if defined(__ppc__) || defined(__POWERPC__)
        unsigned char mask = (unsigned char)(1U << (7 - (targetBit % 8)));

        if ((value & (1U << (width - index - 1))) != 0)
            bytes[targetBit / 8] |= mask;
        else
            bytes[targetBit / 8] &= (unsigned char)~mask;
#else
        unsigned char mask = (unsigned char)(1U << (targetBit % 8));

        if ((value & (1U << index)) != 0)
            bytes[targetBit / 8] |= mask;
        else
            bytes[targetBit / 8] &= (unsigned char)~mask;
#endif
    }
}

typedef struct {
    id storage;
    unsigned char *cursor;
    unsigned char *end;
    void *reserved;
    const void *functionTable;
    id <NSObjCTypeSerializationCallBack> callback;
    unsigned char callbackMode;
    unsigned char reservedFlag;
} NSWalkDataArchiveContext;

static void NSWalkDataReadInteger(NSWalkDataArchiveContext *archive,
                                  void *value, unsigned width);
static unsigned NSWalkDataCursorOffset(NSWalkDataArchiveContext *archive);
static void NSWalkDataWriteArchiveInteger(NSWalkDataArchiveContext *archive,
                                          const void *value, unsigned width);

static unsigned NSSerializerWalkBitfields(BOOL serializing, id storage,
                                           NSWalkDataArchiveContext *archive,
                                           unsigned *cursor, void *value,
                                           const char **type,
                                           unsigned startOffset) {
    const char *fieldType = *type;
    unsigned bytesAdvanced = 0;
    unsigned bitsUsed = 0;
    unsigned bitsInWord = 32 - ((8 * startOffset) & 0x1f);

    while (*fieldType == 'b') {
        const char *fieldStart = fieldType++;
        unsigned width = 0;

        while (*fieldType >= '0' && *fieldType <= '9')
            width = width * 10 + (unsigned)(*fieldType++ - '0');
        if (width != 0) {
            if (bitsInWord >= ((width + bitsUsed) & 0x1f)) {
                unsigned fieldValue;
                unsigned char *bytes = (unsigned char *)value + bytesAdvanced;

                if (serializing) {
                    fieldValue = NSSerializerExtractBitfield(bytes, bitsUsed,
                                                              width);
                    if (archive != NULL && archive->callbackMode)
                        NSWalkDataWriteArchiveInteger(archive, &fieldValue,
                                                      sizeof(fieldValue));
                    else
                        NSSerializerAppendFastInteger(storage, &fieldValue,
                                                       sizeof(fieldValue));
                } else {
                    if (archive != NULL) {
                        NSWalkDataReadInteger(archive, &fieldValue,
                                              sizeof(fieldValue));
                        *cursor = NSWalkDataCursorOffset(archive);
                    } else {
                        NSDataReadFastInteger(storage, cursor, &fieldValue,
                                              sizeof(fieldValue));
                    }
                    NSSerializerInsertBitfield(bytes, bitsUsed, width,
                                               fieldValue);
                }
                bitsUsed += width;
                continue;
            }

            {
                unsigned wordAdvance =
                    ((8 * startOffset + bitsUsed + 31) & ~31U) / 8
                    - startOffset;
                bytesAdvanced += wordAdvance;
                startOffset += wordAdvance;
            }
            fieldType = fieldStart;
        } else {
            unsigned wordAdvance =
                ((8 * startOffset + bitsUsed + 31) & ~31U) / 8
                - startOffset;
            bytesAdvanced += wordAdvance;
            startOffset += wordAdvance;
        }
        bitsInWord = 32 - ((8 * startOffset) & 0x1f);
        bitsUsed = 0;
    }

    if (bitsUsed != 0)
        bytesAdvanced += (bitsUsed + 7) / 8;
    *type = fieldType;
    return bytesAdvanced;
}

extern Class (*_NSAltClassNameFromString)(NSString *className);
extern void *_NSUniqueCString(void *pointer);

typedef void (*NSWalkDataWriteFunction)(id storage, const void *value,
                                        unsigned width);

typedef char *(*NSWalkDataStreamWriteByteFunction)(void *stream,
                                                    unsigned char value);
#if defined(__ppc__) || defined(__POWERPC__)
typedef char *(*NSWalkDataStreamWriteFastIntFunction)(void *stream,
                                                       const void *value,
                                                       unsigned width);
#else
typedef int (*NSWalkDataStreamWriteFastIntFunction)(void *stream,
                                                     const void *value,
                                                     unsigned width);
#endif
typedef void *(*NSWalkDataStreamWriteCStringFunction)(void *stream,
                                                       const char *string);

typedef struct {
    NSWalkDataStreamWriteByteFunction writeByte;
    NSWalkDataStreamWriteFastIntFunction writeFastInt;
    NSWalkDataStreamWriteCStringFunction writeCString;
    void *writeData;
} NSWalkDataStreamFunctions;

static void NSWalkDataWriteBytes(id storage, const void *value,
                                 unsigned width) {
    [storage appendBytes:value length:width];
}

static void NSWalkDataWriteInteger(id storage, const void *value,
                                   unsigned width) {
    NSSerializerAppendFastInteger(storage, value, width);
}

static void NSWalkDataWriteCString(id storage, const void *value,
                                   unsigned width) {
    (void)width;
    NSSerializerAppendCString(storage, *(const char * const *)value);
}

static const NSWalkDataWriteFunction NSWalkDataFunctions[] = {
    NSWalkDataWriteBytes,
    NSWalkDataWriteInteger,
    NSWalkDataWriteCString
};

static void NSWalkDataWriteByte(NSWalkDataArchiveContext *archive,
                                const void *value, unsigned width) {
    if (archive->callbackMode) {
        NSWalkDataStreamFunctions *functions =
            (NSWalkDataStreamFunctions *)archive->functionTable;

        (void)width;
        functions->writeByte(archive, *(const unsigned char *)value);
    } else {
        ((const NSWalkDataWriteFunction *)archive->functionTable)[0](
            archive->storage, value, width);
    }
}

static void NSWalkDataWriteArchiveInteger(
    NSWalkDataArchiveContext *archive, const void *value, unsigned width) {
    if (archive->callbackMode) {
        NSWalkDataStreamFunctions *functions =
            (NSWalkDataStreamFunctions *)archive->functionTable;

        functions->writeFastInt(archive, value, width);
    } else {
        ((const NSWalkDataWriteFunction *)archive->functionTable)[1](
            archive->storage, value, width);
    }
}

static void NSWalkDataWriteCStringValue(NSWalkDataArchiveContext *archive,
                                        const char *string) {
    if (archive->callbackMode) {
        NSWalkDataStreamFunctions *functions =
            (NSWalkDataStreamFunctions *)archive->functionTable;

        functions->writeCString(archive, string);
    } else {
        ((const NSWalkDataWriteFunction *)archive->functionTable)[2](
            archive->storage, &string, 0);
    }
}

static unsigned NSWalkDataCursorOffset(NSWalkDataArchiveContext *archive) {
    const unsigned char *start = archive->callbackMode
        ? (const unsigned char *)archive->reserved
        : (const unsigned char *)[archive->storage bytes];

    return (unsigned)(archive->cursor - start);
}

static void NSWalkDataSetCursorOffset(NSWalkDataArchiveContext *archive,
                                      unsigned offset) {
    unsigned char *start = archive->callbackMode
        ? (unsigned char *)archive->reserved
        : (unsigned char *)[archive->storage bytes];

    archive->cursor = start + offset;
}

static unsigned char NSWalkDataReadByte(NSWalkDataArchiveContext *archive) {
    return (unsigned char)decodeFastByte((NSFastDecoderContext *)archive);
}

static void NSWalkDataReadInteger(NSWalkDataArchiveContext *archive,
                                  void *value, unsigned width) {
    decodeFastInt((NSFastDecoderContext *)archive, value, width);
}

static char *NSWalkDataReadCString(NSWalkDataArchiveContext *archive) {
    unsigned stringLength;
    const char *encoded;
    char *string;

    encoded = (const char *)decodeFastCharStar(
        (NSFastDecoderContext *)archive);
    if (encoded == NULL)
        return NULL;
    stringLength = (unsigned)strlen(encoded) + 1;
    string = (char *)NSZoneMalloc(NULL, stringLength);
    memmove(string, encoded, stringLength);
    return string;
}

static char *NSWalkDataReadUniqueCString(NSWalkDataArchiveContext *archive) {
    const char *string;

    string = (const char *)decodeFastCharStar(
        (NSFastDecoderContext *)archive);
    if (string == NULL)
        return NULL;
    return (char *)_NSUniqueCString((void *)string);
}

unsigned
_NSWalkData(int operation, BOOL walkPointers, void *context,
            void *value, const char *type)
{
    const char *originalType = type;
    NSWalkDataArchiveContext *archive = (NSWalkDataArchiveContext *)context;
    BOOL bycopy;
    BOOL byref;
    unsigned size = 0;
    unsigned index;

    if (type == NULL || value == NULL)
        [NSException raise:NSInvalidArgumentException
                    format:@"Invalid Objective-C type walker argument"];
    if ((operation == 0 || operation == 1) && archive == NULL)
        [NSException raise:NSInvalidArgumentException
                    format:@"Missing Objective-C type archive context"];
    bycopy = NO;
    byref = NO;

    while (*type == 'N' || *type == 'V' || *type == 'n' || *type == 'o'
        || *type == 'r' || *type == 'O' || *type == 'R') {
        if (*type == 'O')
            bycopy = YES;
        else if (*type == 'R')
            byref = YES;
        type++;
    }
    switch (*type) {
        case 'c': case 'C': case '$':
            size = 1;
            if (operation == 1)
                NSWalkDataWriteByte(archive, value, size);
            else if (operation == 0)
                *(unsigned char *)value = NSWalkDataReadByte(archive);
            return size;

        case 's': case 'S':
            size = 2;
            if (operation == 1) {
                if (archive->callbackMode) {
#if defined(__ppc__) || defined(__POWERPC__)
                    NSWalkDataWriteByte(archive, (const char *)value + 1, 1);
                    NSWalkDataWriteByte(archive, value, 1);
#else
                    NSWalkDataWriteByte(archive, value, 1);
                    NSWalkDataWriteByte(archive, (const char *)value + 1, 1);
#endif
                } else {
                    const NSWalkDataWriteFunction *functions =
                        (const NSWalkDataWriteFunction *)archive->functionTable;
                    functions[0](archive->storage, value, 1);
                    functions[0](archive->storage,
                                 (const char *)value + 1, 1);
                }
            }
            else if (operation == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
                ((unsigned char *)value)[1] = NSWalkDataReadByte(archive);
                ((unsigned char *)value)[0] = NSWalkDataReadByte(archive);
#else
                ((unsigned char *)value)[0] = NSWalkDataReadByte(archive);
                ((unsigned char *)value)[1] = NSWalkDataReadByte(archive);
#endif
            }
            return size;

        case 'i': case 'I': case 'l': case 'L': case 'f':
            size = 4;
            if (operation == 1)
                NSWalkDataWriteArchiveInteger(archive, value, size);
            else if (operation == 0)
                NSWalkDataReadInteger(archive, value, size);
            return size;

        case 'q': case 'Q': case 'd':
            size = 8;
            if (operation == 1)
                NSWalkDataWriteArchiveInteger(archive, value, size);
            else if (operation == 0)
                NSWalkDataReadInteger(archive, value, size);
            return size;

        case '#': {
            Class objectClass;
            char *className;

            if (operation == 1) {
                objectClass = *(Class *)value;
                {
                    const char *className = objectClass->name;
                    NSWalkDataWriteCStringValue(archive, className);
                }
            } else if (operation == 0) {
                className = NSWalkDataReadUniqueCString(archive);
                objectClass = objc_getClass(className);
                if (objectClass == Nil && _NSAltClassNameFromString != NULL)
                    objectClass = _NSAltClassNameFromString(
                        [NSString stringWithCString:className]);
                *(Class *)value = objectClass;
            }
            return sizeof(Class);
        }

        case ':': {
            SEL selector;
            char *selectorName;

            if (operation == 1) {
                selector = *(SEL *)value;
                {
                    const char *selectorName = selector == NULL
                        ? NULL : sel_getName(selector);
                    NSWalkDataWriteCStringValue(archive, selectorName);
                }
            } else if (operation == 0) {
                selectorName = NSWalkDataReadUniqueCString(archive);
                *(SEL *)value = sel_registerName(selectorName);
            }
            return sizeof(SEL);
        }

        case '*': case '%': {
            char *string;

            if (operation == 1)
                NSWalkDataWriteCStringValue(archive, *(const char * const *)value);
            else if (operation == 0) {
                if (*type == '%')
                    *(char **)value = NSWalkDataReadUniqueCString(archive);
                else
                    *(char **)value = NSWalkDataReadCString(archive);
            } else if (*type == '*' && operation == 2) {
                string = *(char **)value;
                if (string != NULL)
                    NSZoneFree(NSZoneFromPointer(string), string);
            } else if (*type == '*' && operation == 3) {
                string = *(char **)value;
                if (string != NULL) {
                    unsigned length = (unsigned)strlen(string) + 1;
                    char *copy = NSZoneMalloc(NULL, length);
                    memcpy(copy, string, length);
                    *(char **)value = copy;
                }
            } else if (*type == '*' && operation == 4) {
                string = *(char **)value;
                if (string != NULL) {
                    [NSData dataWithBytes:string
                                   length:(unsigned)strlen(string) + 1];
                }
            }
            return sizeof(char *);
        }

        case '@':
            if (operation == 1) {
                if (archive->callbackMode)
                    [(id)archive->callback encodeObject:*(id *)value
                                                 isBycopy:bycopy
                                                  isByref:byref];
                else
                    [archive->callback serializeObjectAt:(id *)value
                                               ofObjCType:originalType
                                                intoData:archive->storage];
            } else if (operation == 0) {
                if (archive->callbackMode)
                    *(id *)value = [(id)archive->callback decodeRetainedObject];
                else {
                    unsigned cursorOffset = NSWalkDataCursorOffset(archive);

                    [archive->callback deserializeObjectAt:(id *)value
                                                  ofObjCType:originalType
                                                  fromData:archive->storage
                                                  atCursor:&cursorOffset];
                    NSWalkDataSetCursorOffset(archive, cursorOffset);
                }
            } else if (*(id *)value != nil) {
                if (operation == 2)
                    [*(id *)value release];
                else if (operation == 3)
                    [*(id *)value retain];
                else if (operation == 4)
                    [*(id *)value autorelease];
            }
            return sizeof(id);

        case '^': {
            unsigned char present;
            void *pointer;
            const char *pointeeType;

            if (!walkPointers || (operation != 0 && operation != 1))
                return sizeof(void *);
            if (operation == 1) {
                pointer = *(void **)value;
                present = pointer != NULL;
                NSWalkDataWriteByte(archive, &present, 1);
                if (present) {
                    pointeeType = type + 1;
                    if (bycopy || byref) {
                        if (*pointeeType != '@')
                            [NSException raise:NSGenericException
                                        format:@"encodeDataAt:ofObjCType: unencodable type (%s)",
                                               originalType];
                        pointeeType = bycopy ? "O@" : "R@";
                    }
                    _NSWalkData(operation, NO, context, pointer, pointeeType);
                }
            } else {
                present = NSWalkDataReadByte(archive);
                if (!present)
                    *(void **)value = NULL;
                else if (*(void **)value != NULL)
                    _NSWalkData(operation, NO, context, *(void **)value,
                                type + 1);
            }
            return sizeof(void *);
        }

        case '[': {
            const char *elementType = type + 1;
            const char *afterElement;
            unsigned count = 0;
            unsigned walkedSize = 0;

            while (*elementType >= '0' && *elementType <= '9')
                count = count * 10 + (unsigned)(*elementType++ - '0');
            for (index = 0; index < count; index++)
                walkedSize += _NSWalkData(operation, NO, context,
                    (char *)value + walkedSize, elementType);
            afterElement = NSGetSizeAndAlignment(elementType, NULL, NULL);
            if (*afterElement != ']')
                [NSException raise:NSGenericException
                            format:@"badly formed array description"];
            return walkedSize;
        }

        case '{': {
            const char *fieldType = type + 1;
            unsigned offset = 0;
            unsigned maximumAlignment = 1;

            while (*fieldType != '\0' && *fieldType != '=')
                fieldType++;
            if (*fieldType == '=') {
                fieldType++;
            } else {
                [NSException raise:NSGenericException
                            format:@"decodeDataTo:ofObjCType: can't decode struct %s",
                                   originalType];
            }
            while (*fieldType != '\0' && *fieldType != '}') {
                unsigned fieldAlignment;
                const char *nextType;

                if (*fieldType == '"') {
                    fieldType++;
                    while (*fieldType != '\0' && *fieldType != '"')
                        fieldType++;
                    if (*fieldType == '"')
                        fieldType++;
                    else
                        [NSException raise:NSInvalidArgumentException
                                    format:@"Unterminated struct field name"];
                    continue;
                }
                if (*fieldType == 'b') {
                    const char *endOfBitfields = fieldType;
                    unsigned bitfieldSize = NSSerializerBitfieldSizeAndAdvance(
                        &endOfBitfields, offset);

                    if (operation == 0)
                        memset((char *)value + offset, 0, bitfieldSize);
                    if (operation == 0 || operation == 1) {
                        unsigned cursorOffset = operation == 0
                            ? NSWalkDataCursorOffset(archive) : 0;
                        unsigned walkedBitfieldSize =
                            NSSerializerWalkBitfields(operation == 1,
                                archive->storage,
                                (operation == 0
                                    || (archive != NULL
                                        && archive->callbackMode))
                                    ? archive : NULL,
                                &cursorOffset,
                                (char *)value + offset, &fieldType, offset);

                        if (operation == 0)
                            NSWalkDataSetCursorOffset(archive, cursorOffset);
                        offset += walkedBitfieldSize;
                    } else {
                        offset += bitfieldSize;
                        fieldType = endOfBitfields;
                    }
                    maximumAlignment = 4;
                    continue;
                }
                nextType = NSGetSizeAndAlignment(fieldType, NULL,
                                                 &fieldAlignment);
                if (nextType == NULL || nextType == fieldType)
                    [NSException raise:NSInvalidArgumentException
                                format:@"Malformed struct Objective-C encoding %s",
                                       originalType];
                if (fieldAlignment > 1)
                    offset = (offset + fieldAlignment - 1)
                        / fieldAlignment * fieldAlignment;
                offset += _NSWalkData(operation, NO, context,
                                      (char *)value + offset, fieldType);
                if (fieldAlignment > maximumAlignment)
                    maximumAlignment = fieldAlignment;
                fieldType = nextType;
            }
            if (*fieldType != '}')
                [NSException raise:NSGenericException
                            format:@"decodeDataTo:ofObjCType: couldn't decode %s",
                                   originalType];
            offset = (offset + maximumAlignment - 1)
                / maximumAlignment * maximumAlignment;
            return offset;
        }

        case '!': case '(': case 'v':
            [NSException raise:NSGenericException
                        format:@"encodeDataAt:ofObjCType: unencodable type (%s)",
                               originalType];
            return 4;

        default:
            [NSException raise:NSGenericException
                        format:@"decodeDataTo: unknown type descriptor %s",
                               originalType];
            [NSException raise:NSInternalInconsistencyException
                        format:@"didn't return from case statement"];
            return 0;
    }
}

unsigned
_NSParseAndRelease(const char *type, void *value)
{
    return _NSWalkData(2, YES, NULL, value, type);
}

unsigned
_NSParseAndRetain(const char *type, void *value)
{
    return _NSWalkData(3, YES, NULL, value, type);
}

unsigned
_NSParseAndAutorelease(const char *type, void *value)
{
    return _NSWalkData(4, YES, NULL, value, type);
}

@implementation NSMutableData (NSMutableDataObjcTypeSerialization)

- (void)serializeDataAt:(const void *)data ofObjCType:(const char *)type context:(id <NSObjCTypeSerializationCallBack>)callback {
    NSWalkDataArchiveContext context;

    context.storage = self;
    context.cursor = NULL;
    context.end = NULL;
    context.reserved = NULL;
    context.functionTable = NSWalkDataFunctions;
    context.callback = callback;
    context.callbackMode = NO;
    context.reservedFlag = 0;
    _NSWalkData(1, YES, &context, (void *)data, type);
}

@end

@implementation NSData (NSDataObjCTypeDeserialization)

- (void)deserializeDataAt:(void *)data ofObjCType:(const char *)type atCursor:(unsigned *)cursor context:(id <NSObjCTypeSerializationCallBack>)callback {
    NSWalkDataArchiveContext context;
    unsigned char *bytes;

    context.storage = self;
    context.cursor = NULL;
    context.end = NULL;
    context.reserved = NULL;
    context.functionTable = NULL;
    context.callback = callback;
    context.callbackMode = NO;
    context.reservedFlag = 0;
    bytes = (unsigned char *)[self bytes];
    context.cursor = bytes + *cursor;
    context.end = bytes + [self length];
    _NSWalkData(0, YES, &context, data, type);
    *cursor = (unsigned)(context.cursor - bytes);
}

@end

@implementation NSSerializer

+ (void)serializePropertyList:(id)aPropertyList intoData:(NSMutableData *)mdata {
    NSSerializerAppendPropertyList(aPropertyList, mdata, self, _cmd);
}

+ (NSData *)serializePropertyList:(id)aPropertyList {
    NSMutableData *data = [[NSMutableData allocWithZone:NULL] init];

    [NSSerializer serializePropertyList:aPropertyList intoData:data];
    if ([data length] & 3) {
        NSLog(@"%@: mdata should be word aligned after serializing (%s;%d;%@); still getting these old serializations!",
              _NSMethodExceptionProem(self, _cmd), aPropertyList->isa->name,
              [data length], data);
    }
    return [data autorelease];
}

@end

@implementation NSDeserializer

+ (void)_setLazyThreshold:(unsigned)threshold {
    NSDeserializerLazyThreshold = threshold;
}

+ (id)deserializePropertyListFromData:(NSData *)data atCursor:(unsigned *)cursor mutableContainers:(BOOL)mut {
    id object = _NSDeserializeObject(self, data, cursor, mut,
                                    NSZoneFromPointer(data), 0);

    return [object autorelease];
}

+ (id)deserializePropertyListLazilyFromData:(NSData *)data atCursor:(unsigned *)cursor length:(unsigned)length mutableContainers:(BOOL)mut {
    NSZone *zone = NSZoneFromPointer(data);
    NSData *copy = [data copyWithZone:zone];
    id object;

    if (data == nil)
        [NSException raise:NSInvalidArgumentException
                    format:@"Unable to deserialize a nil property list"];
    object = _NSDeserializeObject(self, copy, cursor, mut, zone,
                                 NSDeserializerLazyThreshold);
    [copy release];
    return [object autorelease];
}

+ (id)deserializePropertyListFromData:(NSData *)serialization mutableContainers:(BOOL)mut {
    unsigned cursor = 0;
    NSZone *zone = NSZoneFromPointer(serialization);
    id object = _NSDeserializeObject(self, serialization, &cursor, mut,
                                     zone, 0);

    return [object autorelease];
}

@end

id _NSDeserializeObject(id serializer, NSData *data, unsigned *cursor,
                        BOOL mutableContainers, NSZone *zone,
                        unsigned lazyThreshold) {
    unsigned type = (unsigned)[data deserializeIntAtCursor:cursor];

    if (type == 0)
        type = (unsigned)[data deserializeIntAtCursor:cursor];

    switch (type) {
        case 2: {
            unsigned count = (unsigned)[data deserializeIntAtCursor:cursor];
            id stackObjects[128];
            id *objects;
            unsigned index;
            Class arrayClass = mutableContainers
                ? [NSMutableArray class] : [NSArray class];
            id array;

            if (count == 0)
                return [[arrayClass array] retain];
            if (!mutableContainers && lazyThreshold != 0
                && lazyThreshold <= count * sizeof(int)) {
                unsigned rangeLocation = *cursor;
                unsigned serializedLength = 0;
                unsigned rangeLength;
                _NSLazyDeserializationFaultHandler *handler;

#if defined(__ppc__) || defined(__POWERPC__)
                serializedLength = NSDeserializerSumLengths(data, cursor,
                                                           count);
#else
                for (index = 0; index < count; index++)
                    serializedLength +=
                        (unsigned)[data deserializeIntAtCursor:cursor];
#endif
                rangeLength = *cursor - rangeLocation + serializedLength;
                handler = [[_NSLazyDeserializationFaultHandler allocWithZone:zone]
                    initWithData:data
                    range:NSMakeRange(rangeLocation, rangeLength)
                    count:count mutable:NO lazyThreshold:lazyThreshold isDict:NO];
                array = [NSArray allocWithZone:zone];
                [_NSLazyDeserializationFault makeObjectIntoFault:array
                                                     withHandler:handler];
                [handler release];
                *cursor += serializedLength;
                return array;
            }
            objects = count > 128
                ? (id *)NSZoneMalloc(NULL, sizeof(id) * count) : stackObjects;
            *cursor += sizeof(int) * count;
            for (index = 0; index < count; index++)
                objects[index] = _NSDeserializeObject(serializer, data, cursor,
                                                     mutableContainers, zone,
                                                     lazyThreshold);

            index = 0;
            while (index < count) {
                if (objects[index] == nil) {
                    count--;
                    objects[index] = objects[count];
                    NSLog(@"*** Attempt to enter nil in an array while deserializing; item skipped");
                } else {
                    index++;
                }
            }

            array = [[arrayClass allocWithZone:zone]
                initWithObjects:objects count:count];
            for (index = count; index != 0; index--)
                [objects[index - 1] release];
            if (objects != stackObjects)
                NSZoneFree(NULL, objects);
            return array;
        }

        case 3:
            NSLog(@"Invalid serialized property-list type %u", type);
            return nil;

        case 4: {
            unsigned length = [data deserializeAlignedBytesLengthAtCursor:cursor];
            const unsigned char *bytes = (const unsigned char *)[data bytes] + *cursor;
            id object;

#if !defined(__ppc__) && !defined(__POWERPC__)
            if (length == 0)
                return [__NSEmptyString retain];
#endif
            object = [[NSData allocWithZone:zone]
                initWithBytes:bytes length:length
                copy:YES freeWhenDone:YES bytesAreVM:NO];
            *cursor += (length + 3) & ~3U;
            return object;
        }

        case 5: {
            unsigned length = [data deserializeAlignedBytesLengthAtCursor:cursor];
            const unsigned char *bytes = (const unsigned char *)[data bytes] + *cursor;
            NSString *string;
            unsigned index;
            unsigned stringEncoding = 10;
            static const char *interned[] = { "YES", "NO", "Yes", "No" };

#if defined(__ppc__) || defined(__POWERPC__)
            stringEncoding = 2;
#endif

            if (length == 0)
                return [__NSEmptyString retain];
            if (length == 1 && bytes[0] >= '0' && bytes[0] <= '4') {
                switch (bytes[0]) {
                    case '0': string = @"0"; break;
                    case '1': string = @"1"; break;
                    case '2': string = @"2"; break;
                    case '3': string = @"3"; break;
                    default:  string = @"4"; break;
                }
                *cursor += (length + 3) & ~3U;
                return [string retain];
            }
            if (length == 2 && memcmp(bytes, "NO", 2) == 0) {
                *cursor += (length + 3) & ~3U;
                return [@"NO" retain];
            }
            for (index = 0; index < sizeof(interned) / sizeof(interned[0]); index++) {
                unsigned internedLength = (unsigned)strlen(interned[index]);

                if (length == internedLength
                    && memcmp(bytes, interned[index], length) == 0) {
                    *cursor += (length + 3) & ~3U;
                    switch (index) {
                        case 0: return [@"YES" retain];
                        case 1: return [@"NO" retain];
                        case 2: return [@"Yes" retain];
                        default: return [@"No" retain];
                    }
                }
            }
            string = [[NSString allocWithZone:zone]
                initWithBytes:(const char *)bytes length:length
                encoding:stringEncoding];
            *cursor += (length + 3) & ~3U;
            return string;
        }

        case 6: {
            unsigned length = [data deserializeAlignedBytesLengthAtCursor:cursor];
            const unsigned char *bytes = (const unsigned char *)[data bytes] + *cursor;
            NSString *string;

            if (length == 0)
                return [__NSEmptyString retain];
            string = [[NSString allocWithZone:zone]
                initWithBytes:(const char *)bytes length:length encoding:10];
            *cursor += (length + 3) & ~3U;
            return string;
        }

        case 7: {
            unsigned count = (unsigned)[data deserializeIntAtCursor:cursor];
            id stackKeys[64];
            id stackObjects[64];
            id *keys;
            id *objects;
            unsigned index;
            Class dictionaryClass = mutableContainers
                ? [NSMutableDictionary class] : [NSDictionary class];
            id dictionary;

            if (count == 0)
                return [[dictionaryClass dictionary] retain];
            if (!mutableContainers && lazyThreshold != 0
                && lazyThreshold <= count * 2 * sizeof(int)) {
                unsigned rangeLocation = *cursor;
                unsigned lazyCursor = *cursor;
                unsigned serializedLength = 0;
                unsigned index;
                unsigned rangeLength;
                _NSLazyDeserializationFaultHandler *handler;

                for (index = 0; index < count; index++) {
                    int keyType = [data deserializeIntAtCursor:&lazyCursor];
                    unsigned keyLength;

                    if (keyType == 0)
                        (void)[data deserializeIntAtCursor:&lazyCursor];
                    keyLength = [data deserializeAlignedBytesLengthAtCursor:
                        &lazyCursor];
                    lazyCursor += (keyLength + 3) & ~3U;
                }
#if defined(__ppc__) || defined(__POWERPC__)
                serializedLength = NSDeserializerSumLengths(data, &lazyCursor,
                                                           count);
#else
                for (index = 0; index < count; index++)
                    serializedLength += (unsigned)[data
                        deserializeIntAtCursor:&lazyCursor];
#endif

                rangeLength = lazyCursor - rangeLocation + serializedLength;
                handler = [[_NSLazyDeserializationFaultHandler allocWithZone:zone]
                    initWithData:data
                    range:NSMakeRange(rangeLocation, rangeLength)
                    count:count mutable:NO lazyThreshold:lazyThreshold isDict:YES];
                dictionary = [NSDictionary allocWithZone:zone];
                [_NSLazyDeserializationFault makeObjectIntoFault:dictionary
                                                     withHandler:handler];
                [handler release];
                *cursor = lazyCursor + serializedLength;
                return dictionary;
            }
            keys = count > 64
                ? (id *)NSZoneMalloc(NULL, sizeof(id) * count) : stackKeys;
            objects = count > 64
                ? (id *)NSZoneMalloc(NULL, sizeof(id) * count) : stackObjects;
            for (index = 0; index < count; index++)
                keys[index] = _NSDeserializeObject(serializer, data, cursor,
                                                  NO, zone, 0);
            *cursor += sizeof(int) * count;
            for (index = 0; index < count; index++)
                objects[index] = _NSDeserializeObject(serializer, data, cursor,
                                                     mutableContainers, zone,
                                                     lazyThreshold);

            index = 0;
            while (index < count) {
                if (keys[index] == nil || objects[index] == nil) {
                    count--;
                    keys[index] = keys[count];
                    objects[index] = objects[count];
                    NSLog(@"*** Attempt to enter nil in a dictionary while deserializing; skipping");
                } else {
                    index++;
                }
            }

            dictionary = [[dictionaryClass allocWithZone:zone]
                initWithObjects:objects forKeys:keys count:count];
            for (index = count; index != 0; index--) {
                [keys[index - 1] release];
                [objects[index - 1] release];
            }
            if (keys != stackKeys)
                NSZoneFree(NULL, keys);
            if (objects != stackObjects)
                NSZoneFree(NULL, objects);
            return dictionary;
        }

        case 8:
            return nil;

        default:
            NSLog(@"Invalid serialized property-list type %u", type);
            return nil;
    }
}
