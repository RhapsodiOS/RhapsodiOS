/*	NSArchiver.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSArchiver.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSSerialization.h>
#import <objc/objc-runtime.h>

#include <string.h>
#include <stdio.h>
#include <stdarg.h>

static void _encodeInt(NSMutableData *data, int value);
static void _encodeCString(NSMutableData *data, const char *string);
static void _encodeClass(NSArchiver *archiver, Class aClass);
static void typeDescriptorError(char type, const char *descriptor,
                                const char *reason);
static unsigned _decodeIntStartingWithChar(id data, signed char marker,
                                           unsigned *cursor);
static unsigned _decodeIntAtCursor(id data, unsigned *cursor);
static char *_decodeCStringAtCursor(id data, unsigned *cursor);
static char *_decodeReusedCStringUsingTable(id data, void *stringTable,
                                             unsigned *cursor);
static void _freeStringTable(void *stringTable);
static void prematureEnd(unsigned cursor);
static void checkExpected(const char *actual, const char *expected);
extern int _NSsnprintf(char *buffer, size_t size, char *format, ...);
extern void *_NSUniqueCString(void *pointer);
extern Class __NSConcreteDataClass;
extern Class __NSConcreteMutableDataClass;
static unsigned char debugArchiver;
#if defined(__ppc__) || defined(__POWERPC__)
void *__NSJavaArchiverCallout;
#endif

static NSMapTable *NSArchiverEncodingMap;
static NSMapTable *NSUnarchiverDecodingMap;

@interface _NSArchiverData : NSData {
@public
    unsigned length;
    char *bytes;
    char swap;
}
- (id)initWithData:(NSData *)data;
- (void)_setSwap:(char)swapBytes;
- (BOOL)_decodeNewPtr:(void **)pointer label:(void **)label
          usingTable:(NSMapTable *)table lastLabel:(int *)lastLabel
            atCursor:(unsigned *)cursor;
@end

typedef struct {
    Class isa;
    NSMutableData *mdata;
    NSMapTable *pointerTable;
    void *stringTable;
    NSHashTable *ids;
    NSMutableDictionary *map;
    NSMapTable *replacementTable;
    void *reserved;
} NSArchiverState;

typedef struct {
    unsigned count;
    unsigned capacity;
    id *objects;
} NSUnarchivedObjects;

typedef struct {
    unsigned count;
    unsigned growth;
    unsigned capacity;
    char **strings;
} NSUnarchiverStringTable;

typedef struct {
    id data;
    unsigned *cursor;
    NSZone *objectZone;
    signed char streamerVersion;
    NSMapTable *pointerTable;
    void *stringTable;
    NSMapTable *classVersions;
    int *lastLabel;
    NSMutableDictionary *map;
    NSUnarchivedObjects *allUnarchivedObjects;
} NSUnarchiverContext;

static Class _decodeClass(NSUnarchiver *unarchiver,
                          NSUnarchiverContext *context);
static id _decodeObject(NSUnarchiver *unarchiver,
                        NSUnarchiverContext *context);
static const char *_decodeValueOfObjCType(NSUnarchiver *unarchiver,
                                          NSUnarchiverContext *context,
                                          const char *type, void *value);

#define NSUNARCHIVER_CONTEXT(context, unarchiver) \
    do { \
        (context).data = (unarchiver)->data; \
        (context).cursor = &(unarchiver)->cursor; \
        (context).objectZone = (unarchiver)->objectZone; \
        (context).streamerVersion = (unarchiver)->streamerVersion; \
        (context).pointerTable = (unarchiver)->pointerTable; \
        (context).stringTable = (unarchiver)->stringTable; \
        (context).classVersions = (unarchiver)->classVersions; \
        (context).lastLabel = &(unarchiver)->lastLabel; \
        (context).map = (unarchiver)->map; \
        (context).allUnarchivedObjects = \
            (NSUnarchivedObjects *)(unarchiver)->allUnarchivedObjects; \
    } while (0)

@interface NSArchiver (NSArchiverPrivate)
- (void)_replaceObject:(id)object withObject:(id)replacement;
@end

static void _encodeShort(NSMutableData *data, short value)
{
    signed char marker;

    if (value < -110 || value > 127) {
        marker = -127;
        [data appendBytes:&marker length:1];
        [data appendBytes:&value length:sizeof(value)];
    } else {
        marker = (signed char)value;
        [data appendBytes:&marker length:1];
    }
}

static void _encodeLong(NSMutableData *data, int value)
{
    signed char marker;

    if (value < -110 || value > 127) {
        if (value < -32767 || value > 32767) {
            int extendedValue = value;

            if (value == (-2147483647 - 1)) {
                /* Preserve the target's eight-byte read from the int argument. */

                marker = -121;
                [data appendBytes:&marker length:1];
                [data appendBytes:&value length:8];
            } else {
                marker = -126;
                [data appendBytes:&marker length:1];
                [data appendBytes:&extendedValue length:sizeof(extendedValue)];
            }
        } else {
            short shortValue = (short)value;

            marker = -127;
            [data appendBytes:&marker length:1];
            [data appendBytes:&shortValue length:sizeof(shortValue)];
        }
    } else {
        marker = (signed char)value;
        [data appendBytes:&marker length:1];
    }
}

static void _encodeLongLong(NSMutableData *data, long long value)
{
    signed char marker;

    if (value < -110 || value > 127) {
        if (value < -32767 || value > 32767) {
            if (value < -2147483647LL || value > 2147483647LL) {
                marker = -121;
                [data appendBytes:&marker length:1];
                [data appendBytes:&value length:sizeof(value)];
            } else {
                int intValue = (int)value;

                marker = -126;
                [data appendBytes:&marker length:1];
                [data appendBytes:&intValue length:sizeof(intValue)];
            }
        } else {
            short shortValue = (short)value;

            marker = -127;
            [data appendBytes:&marker length:1];
            [data appendBytes:&shortValue length:sizeof(shortValue)];
        }
    } else {
        marker = (signed char)value;
        [data appendBytes:&marker length:1];
    }
}

static void _encodeOrReuseCString(NSMutableData *data, const char *string,
                                  NSMapTable *table)
{
    void *label;
    signed char marker;

    if (string == NULL) {
        marker = -123;
        [data appendBytes:&marker length:1];
        return;
    }
    if (NSMapMember(table, string, NULL, &label)) {
        _encodeInt(data, (int)(unsigned long)label);
        return;
    }

    label = (void *)(unsigned long)(NSCountMapTable(table) - 110);
    marker = -124;
    [data appendBytes:&marker length:1];
    _encodeCString(data, string);
    {
        unsigned length = (unsigned)strlen(string) + 1;
        char *copy = NSZoneMalloc(NULL, length);

        memcpy(copy, string, length);
        NSMapInsert(table, copy, label);
    }
}

static int _encodePointerIfNew(NSMutableData *data, const void *pointer,
                               NSMapTable *table)
{
    void *label;
    signed char marker;

    if (pointer == NULL) {
        marker = -123;
        [data appendBytes:&marker length:1];
        return 0;
    }
    if (NSMapMember(table, pointer, NULL, &label)) {
        _encodeInt(data, (int)(unsigned long)label);
        return 0;
    }

    label = (void *)(unsigned long)(NSCountMapTable(table) - 110);
    marker = -124;
    [data appendBytes:&marker length:1];
    NSMapInsert(table, pointer, label);
    return 1;
}

static void typeDescriptorError(char type, const char *descriptor,
                                const char *reason)
{
    [NSException raise:NSInconsistentArchiveException
                format:@"*** type descriptor error for '%c' in '%s': %s",
                       type, descriptor, reason];
}

static id _replacementObjectForObject(NSArchiver *archiver, id object)
{
    id replacement;
    NSMapTable *replacementTable =
        ((NSArchiverState *)archiver)->replacementTable;

    if (replacementTable != NULL &&
        NSMapMember(replacementTable, object, NULL,
                    (void **)&replacement))
        return replacement;
    replacement = [object replacementObjectForArchiver:archiver];
    [archiver _replaceObject:object withObject:replacement];
    return replacement;
}

static void _encodeObject(NSArchiver *archiver, id object)
{
    signed char marker;
    id replacement;
    Class aClass;
    NSArchiverState *state = (NSArchiverState *)archiver;
    NSMutableData *data = state->mdata;
    NSMapTable *pointerTable = state->pointerTable;
    NSHashTable *ids = state->ids;

    if (data == nil) {
        replacement = _replacementObjectForObject(archiver, object);
        if (replacement != nil && NSHashGet(ids, replacement) == NULL) {
            NSHashInsert(ids, replacement);
            [replacement encodeWithCoder:archiver];
        }
        return;
    }

    if (!_encodePointerIfNew(data, object, pointerTable))
        return;
    replacement = _replacementObjectForObject(archiver, object);
    aClass = [replacement classForArchiver];
    if (debugArchiver != 0)
        NSLog(@"New label %d for object %x",
              (int)NSCountMapTable(pointerTable) - 111,
              (unsigned)(unsigned long)replacement);
    _encodeClass(archiver, aClass);
    [replacement encodeWithCoder:archiver];
    marker = -122;
    [data appendBytes:&marker length:1];
}

static const char *_skipAggregateName(const char *type)
{
    while (*type != '\0' && *type != '=' && *type != '{' && *type != '}' &&
           *type != '(' && *type != ')')
        type++;
    return *type == '=' ? type + 1 : type;
}

static const char *_sizeOfType(const char *type, unsigned *size,
                               unsigned *alignment)
{
    unsigned maximumSize = 0;
    unsigned maximumAlignment = 1;
    unsigned offset = 0;
    const char *cursor;
    char close;

    if (*type != '{' && *type != '(')
        return NSGetSizeAndAlignment(type, size, alignment);
    close = *type == '{' ? '}' : ')';
    cursor = _skipAggregateName(type + 1);
    while (*cursor != close && *cursor != '\0') {
        unsigned fieldSize, fieldAlignment;
        const char *next = _sizeOfType(cursor, &fieldSize, &fieldAlignment);

        if (fieldAlignment == 0)
            fieldAlignment = 1;
        if (fieldAlignment > maximumAlignment)
            maximumAlignment = fieldAlignment;
        if (close == ')') {
            if (fieldSize > maximumSize)
                maximumSize = fieldSize;
        } else {
            offset = fieldAlignment * ((offset + fieldAlignment - 1) /
                                       fieldAlignment);
            offset += fieldSize;
        }
        cursor = next;
    }
    *alignment = maximumAlignment;
    if (close == ')')
        *size = maximumAlignment * ((maximumSize + maximumAlignment - 1) /
                                    maximumAlignment);
    else
        *size = maximumAlignment * ((offset + maximumAlignment - 1) /
                                    maximumAlignment);
    return cursor + 1;
}

static char *_encodeValueOfObjCType(NSArchiver *archiver, const char *type,
                                    const void *value)
{
    NSArchiverState *state = (NSArchiverState *)archiver;
    NSMutableData *data = state->mdata;
    const char *cursor = type + 1;

    switch (*type) {
    case '!':
        return (char *)cursor;
    case 'c': case 'C':
        if (data != nil)
            [data appendBytes:value length:sizeof(char)];
        return (char *)cursor;
    case 's': case 'S':
        if (data != nil)
            _encodeShort(data, *(const short *)value);
        return (char *)cursor;
    case 'i': case 'I':
        if (data != nil)
            _encodeInt(data, *(const int *)value);
        return (char *)cursor;
    case 'l': case 'L':
        if (data != nil)
            _encodeLong(data, *(const int *)value);
        return (char *)cursor;
    case 'q': case 'Q':
        if (data != nil)
            _encodeLongLong(data, *(const long long *)value);
        return (char *)cursor;
    case 'f': {
        float number = *(const float *)value;

        if (data != nil) {
            if (number >= -2147483646.0f && number <= 2147483646.0f &&
                (float)(int)number == number) {
                _encodeInt(data, (int)number);
            } else {
                signed char marker = -125;

                [data appendBytes:&marker length:1];
                [data appendBytes:&number length:sizeof(number)];
            }
        }
        return (char *)cursor;
    }
    case 'd': {
        double number = *(const double *)value;

        if (data != nil) {
            if (number >= -2147483646.0 && number <= 2147483646.0 &&
                (double)(int)number == number) {
                _encodeInt(data, (int)number);
            } else {
                signed char marker = -125;

                [data appendBytes:&marker length:1];
                [data appendBytes:&number length:sizeof(number)];
            }
        }
        return (char *)cursor;
    }
    case '@':
        [archiver encodeObject:*(id const *)value];
        return (char *)cursor;
    case '*':
        if (data != nil && _encodePointerIfNew(data, *(char * const *)value,
                                               state->pointerTable))
            _encodeOrReuseCString(data, *(char * const *)value,
                                  (NSMapTable *)state->stringTable);
        return (char *)cursor;
    case '%': case ':':
        if (data != nil)
            _encodeOrReuseCString(data, *(const char * const *)value,
                                  (NSMapTable *)state->stringTable);
        return (char *)cursor;
    case '#':
        _encodeClass(archiver, *(Class const *)value);
        return (char *)cursor;
    case '[': {
        unsigned count = 0, itemSize, itemAlignment, index;

        while (*cursor >= '0' && *cursor <= '9')
            count = count * 10 + (unsigned)(*cursor++ - '0');
        {
            const char *end = _sizeOfType(cursor, &itemSize, &itemAlignment);

            for (index = 0; index < count; index++)
                _encodeValueOfObjCType(archiver, cursor,
                                       (const char *)value + index * itemSize);
            if (*end != ']')
                typeDescriptorError(*end, type, "missing ']' in type descriptor");
            return (char *)(end + 1);
        }
    }
    case '{': {
        unsigned offset = 0;

        cursor = _skipAggregateName(cursor);
        while (*cursor != '}' && *cursor != '\0') {
            unsigned fieldSize, fieldAlignment;
            const char *next = _sizeOfType(cursor, &fieldSize, &fieldAlignment);

            if (fieldAlignment == 0)
                fieldAlignment = 1;
            offset = fieldAlignment * ((offset + fieldAlignment - 1) /
                                       fieldAlignment);
            _encodeValueOfObjCType(archiver, cursor,
                                   (const char *)value + offset);
            offset += fieldSize;
            cursor = next;
        }
        if (*cursor != '}')
            typeDescriptorError(*cursor, type, "unknown type descriptor");
        return (char *)(cursor + 1);
    }
    case '(': {
        unsigned size, alignment, index;
        const char *end = _sizeOfType(type, &size, &alignment);

        if (data != nil) {
            for (index = 0; index < size; index++)
                [data appendBytes:(const char *)value + index length:1];
        }
        return (char *)end;
    }
    default:
        typeDescriptorError(*type, type, "unknown type descriptor");
        return (char *)cursor;
    }
}

static void _encodeClass(NSArchiver *archiver, Class aClass)
{
    NSArchiverState *state = (NSArchiverState *)archiver;
    NSMutableData *data = state->mdata;
    NSMapTable *pointerTable = state->pointerTable;
    NSMapTable *stringTable = (NSMapTable *)state->stringTable;

    if (data == nil)
        return;
    while (aClass != Nil && _encodePointerIfNew(data, aClass, pointerTable)) {
        NSString *trueName = NSStringFromClass(aClass);
        NSString *archiveName = [archiver classNameEncodedForTrueClassName:trueName];
        const char *name = [archiveName cString];
        const char *uniqueName =
            (const char *)_NSUniqueCString((void *)name);

        _encodeOrReuseCString(data, uniqueName, stringTable);
        _encodeInt(data, aClass->version);
        aClass = aClass->super_class;
        while (aClass != Nil && aClass->name != NULL && aClass->name[0] == '%')
            aClass = aClass->super_class;
    }
}

static void _encodeInt(NSMutableData *data, int value)
{
    signed char marker;

    if (value < -110 || value > 127) {
        if (value < -32767 || value > 32767) {
            marker = -126;
            [data appendBytes:&marker length:1];
            [data appendBytes:&value length:sizeof(value)];
        } else {
            short shortValue = (short)value;

            marker = -127;
            [data appendBytes:&marker length:1];
            [data appendBytes:&shortValue length:sizeof(shortValue)];
        }
    } else {
        marker = (signed char)value;
        [data appendBytes:&marker length:1];
    }
}

static void _encodeCString(NSMutableData *data, const char *string)
{
    signed char marker = -123;
    unsigned length;

    if (string == NULL) {
        [data appendBytes:&marker length:1];
        return;
    }

    length = (unsigned)strlen(string);
    _encodeInt(data, (int)length);
    [data appendBytes:string length:length];
}

static unsigned _decodeIntStartingWithChar(id data, signed char marker,
                                           unsigned *cursor)
{
    unsigned value;

    if (marker == -126) {
        [data deserializeBytes:&value length:sizeof(value) atCursor:cursor];
        if (((_NSArchiverData *)data)->swap)
            value = (value >> 24) | ((value >> 8) & 0x0000ff00) |
                    ((value << 8) & 0x00ff0000) | (value << 24);
        return value;
    }
    if (marker == -127) {
        short shortValue;

        [data deserializeBytes:&shortValue length:sizeof(shortValue)
                      atCursor:cursor];
        if (((_NSArchiverData *)data)->swap)
            shortValue = (short)((unsigned short)shortValue >> 8 |
                                 (unsigned short)shortValue << 8);
        return (unsigned)shortValue;
    }
    if (marker == -121) {
        [NSException raise:NSRangeException format:@"more data than room"];
        return 0;
    }
    return (unsigned)marker;
}

static unsigned _decodeIntAtCursor(id data, unsigned *cursor)
{
    signed char marker;

    if (*cursor >= [data length])
        prematureEnd(*cursor);
    marker = ((const signed char *)[data bytes])[*cursor];
    (*cursor)++;
    return _decodeIntStartingWithChar(data, marker, cursor);
}

static char *_decodeCStringAtCursor(id data, unsigned *cursor)
{
    signed char marker;
    unsigned length;
    char *string;

    if (*cursor >= [data length])
        prematureEnd(*cursor);
    marker = ((const signed char *)[data bytes])[*cursor];
    (*cursor)++;
    if (marker == -123)
        return NULL;
    length = _decodeIntStartingWithChar(data, marker, cursor);
    string = NSZoneMalloc(NULL, length + 1);
    [data deserializeBytes:string length:length atCursor:cursor];
    string[length] = '\0';
    return string;
}

static char *_decodeReusedCStringUsingTable(id data, void *stringTable,
                                            unsigned *cursor)
{
    NSUnarchiverStringTable *table = stringTable;
    signed char marker;
    unsigned index;
    char *string;

    if (*cursor >= [data length])
        prematureEnd(*cursor);
    marker = ((const signed char *)[data bytes])[*cursor];
    (*cursor)++;
    if (marker == -123)
        return NULL;
    if (marker == -124) {
        string = _decodeCStringAtCursor(data, cursor);
        if (table->count == table->capacity) {
            table->capacity += table->growth;
            table->growth = table->count;
            table->strings = NSZoneRealloc(NULL, table->strings,
                table->capacity * sizeof(char *));
        }
        table->strings[table->count++] = string;
        return string;
    }

    index = _decodeIntStartingWithChar(data, marker, cursor) + 110;
    if (table->count <= index || table->strings[index] == NULL)
        [NSException raise:NSInconsistentArchiveException
                    format:@"*** Incorrect archive: unexpected byte"];
    return table->strings[index];
}

static void prematureEnd(unsigned cursor)
{
    [NSException raise:NSInconsistentArchiveException
                format:@"*** End of archive encountered prematurely at %d",
                       (int)cursor];
}

static BOOL
_NSArchiverTypesStructurallyEqual(const char *first, const char *second)
{
    while (*first != '\0' && *second != '\0') {
        if (*first == *second) {
            first++;
            second++;
        } else if (*first == '?') {
            first++;
            while (*second != '\0' && *second != '=')
                second++;
        } else if (*second == '?') {
            second++;
            while (*first != '\0' && *first != '=')
                first++;
        } else {
            return NO;
        }
    }
    return *first == '\0' && *second == '\0';
}

static void checkExpected(const char *actual, const char *expected)
{
    if (actual == NULL || (strcmp(actual, expected) != 0 &&
        !_NSArchiverTypesStructurallyEqual(actual, expected)))
        [NSException raise:NSInconsistentArchiveException
                    format:@"*** file inconsistency: read '%s', expecting '%s'",
                           actual, expected];
}

static NSUnarchiverStringTable *_createStringTable(void)
{
    NSUnarchiverStringTable *table = NSZoneMalloc(NULL, sizeof(*table));

    table->count = 0;
    table->growth = 5;
    table->capacity = 8;
    table->strings = NSZoneMalloc(NULL, table->capacity * sizeof(char *));
    return table;
}

static void _freeStringTable(void *stringTable)
{
    NSUnarchiverStringTable *table = stringTable;
    unsigned index;

    for (index = 0; index < table->count; index++)
        NSZoneFree(NULL, table->strings[index]);
    NSZoneFree(NULL, table->strings);
    NSZoneFree(NULL, table);
}

NSString * const NSInconsistentArchiveException =
    @"NSArchiverArchiveInconsistency";

@implementation _NSArchiverData

- (id)initWithData:(NSData *)data {
    length = [data length];
    bytes = NSZoneMalloc(NULL, length);
    memmove(bytes, [data bytes], length);
    return self;
}

- (const void *)bytes {
    return bytes;
}

- (unsigned)length {
    return length;
}

- (void)_setSwap:(char)swapBytes {
    swap = swapBytes;
}

- (BOOL)_decodeNewPtr:(void **)pointer label:(void **)label
          usingTable:(NSMapTable *)table lastLabel:(int *)lastLabel
            atCursor:(unsigned *)cursor {
    signed char marker;
    unsigned decodedLabel;

    if (*cursor >= length)
        prematureEnd(*cursor);
    marker = bytes[(*cursor)++];
    if (marker == -123) {
        *pointer = NULL;
        return NO;
    }
    if (marker == -124) {
        *label = (void *)(unsigned long)++*lastLabel;
        return YES;
    }

    decodedLabel = _decodeIntStartingWithChar(self, marker, cursor);
    *label = (void *)(unsigned long)decodedLabel;
    *pointer = NSMapGet(table, *label);
    return NO;
}

- (void)dealloc {
    NSZoneFree(NSZoneFromPointer(bytes), bytes);
    [super dealloc];
}

@end

@implementation NSArchiver

- (id)initForWritingWithMutableData:(NSMutableData *)mdata {
    NSMapTableKeyCallBacks stringKeyCallBacks;
    NSMapTableValueCallBacks valueCallBacks = { NULL, NULL, NULL };
    signed char streamerVersion = 4;

    if (mdata == nil)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -initForWritingWithMutableData: nil argument"];

    self->mdata = [mdata retain];
    stringKeyCallBacks = NSOwnedPointerMapKeyCallBacks;
    stringKeyCallBacks.hash = _NSMapTableHashCString;
    stringKeyCallBacks.isEqual = _NSMapTableIsEqualCString;
    self->pointerTable = NSCreateMapTableWithZone(
        NSNonOwnedPointerOrNullMapKeyCallBacks, valueCallBacks, 0x28, NULL);
    self->stringTable = NSCreateMapTableWithZone(
        stringKeyCallBacks, valueCallBacks, 0x0a, NULL);
    [self->mdata appendBytes:&streamerVersion length:1];
#if defined(__ppc__) || defined(__POWERPC__)
    _encodeCString(self->mdata, "typedstream");
#else
    _encodeCString(self->mdata, "streamtyped");
#endif
    _encodeInt(self->mdata, 1000);
    return self;
}

- (NSMutableData *)archiverData {
    return self->mdata;
}

- (NSMutableData *)data {
    return self->mdata;
}

- (void)dealloc {
#if defined(__ppc__) || defined(__POWERPC__)
    if (__NSJavaArchiverCallout != NULL)
        ((void (*)(int, NSArchiver *, void *, void *))
            __NSJavaArchiverCallout)(3, self, NULL, NULL);
#endif
    [self->mdata release];
    if (self->replacementTable != NULL)
        NSFreeMapTable((NSMapTable *)self->replacementTable);
    if (self->pointerTable != NULL)
        NSFreeMapTable(self->pointerTable);
    if (self->stringTable != NULL)
        NSFreeMapTable((NSMapTable *)self->stringTable);
    if (self->ids != NULL)
        NSFreeHashTable(self->ids);
    [self->map release];
    [super dealloc];
}

- (void)encodeRootObject:(id)rootObject {
    NSMutableData *mdata;

    if (self->mdata == nil)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -encodeRootObject: called without a writing data stream"];
    if (self->ids == NULL)
        self->ids = NSCreateHashTableWithZone(NSNonOwnedPointerHashCallBacks,
                                               0, NULL);
    mdata = self->mdata;
    self->mdata = nil;
#if defined(__ppc__) || defined(__POWERPC__)
    if (__NSJavaArchiverCallout != NULL)
        ((void (*)(int, NSArchiver *, void *, void *))
            __NSJavaArchiverCallout)(1, self, NULL, NULL);
#endif
    [self encodeObject:rootObject];
    self->mdata = mdata;
#if defined(__ppc__) || defined(__POWERPC__)
    if (__NSJavaArchiverCallout != NULL)
        ((void (*)(int, NSArchiver *, void *, void *))
            __NSJavaArchiverCallout)(2, self, NULL, NULL);
#endif
    [self encodeObject:rootObject];
}

- (void)encodeConditionalObject:(id)object {
    id replacement;

    if (self->mdata == nil)
        return;
    if (self->ids == NULL)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** encodeConditionalObject: -encodeRootObject: has not been previously done for 0x%x",
                          (unsigned)(unsigned long)object];
    replacement = _replacementObjectForObject(self, object);
    [self encodeObject:(replacement != nil &&
                        NSHashGet(self->ids, replacement) != NULL)
                       ? object : nil];
}

- (void)encodeDataObject:(NSData *)data {
    int length = (int)[data length];

    [self encodeValueOfObjCType:"i" at:&length];
    [self encodeArrayOfObjCType:"c" count:(unsigned)length at:[data bytes]];
}

- (void)encodeValuesOfObjCTypes:(const char *)types, ... {
    va_list arguments;
    const char *cursor = types;

    if (self->mdata != nil)
        _encodeOrReuseCString(self->mdata, types,
                              (NSMapTable *)self->stringTable);
    va_start(arguments, types);
    while (*cursor != '\0') {
        void *value = va_arg(arguments, void *);

        cursor = _encodeValueOfObjCType(self, cursor, value);
    }
    va_end(arguments);
}

+ (void)encodeClassName:(NSString *)trueName intoClassName:(NSString *)inArchiveName {
    NSMapTableValueCallBacks valueCallBacks;

    if (NSArchiverEncodingMap == NULL) {
        valueCallBacks = NSObjectMapValueCallBacks;
        NSArchiverEncodingMap = NSCreateMapTableWithZone(
            NSObjectMapKeyCallBacks, valueCallBacks, 0x10, NULL);
    }
    NSMapInsert(NSArchiverEncodingMap, trueName, inArchiveName);
}

+ (NSString *)classNameEncodedForTrueClassName:(NSString *)trueName {
    NSString *archiveName;

    if (trueName == nil)
        return nil;
    archiveName = NSArchiverEncodingMap != NULL
        ? NSMapGet(NSArchiverEncodingMap, trueName) : nil;
    if (archiveName == nil)
        return [[trueName copyWithZone:NULL] autorelease];
    return archiveName;
}

+ (NSData *)archivedDataWithRootObject:(id)rootObject {
    NSMutableData *data = [NSMutableData data];
    NSArchiver *archiver = [[self allocWithZone:NULL]
        initForWritingWithMutableData:data];

    [archiver encodeRootObject:rootObject];
    [archiver release];
    return data;
}

+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString *)path {
    NSData *data = [self archivedDataWithRootObject:rootObject];

    return [data writeToFile:path atomically:YES];
}

- (void)encodeClassName:(NSString *)trueName intoClassName:(NSString *)inArchiveName {
    if (self->map == nil)
        self->map = [[NSMutableDictionary allocWithZone:NULL] init];
    [self->map setObject:inArchiveName forKey:trueName];
}

- (NSString *)classNameEncodedForTrueClassName:(NSString *)trueName {
    NSString *archiveName;

    if (trueName == nil)
        return nil;
    archiveName = [self->map objectForKey:trueName];
    if (archiveName == nil)
        return [[trueName copyWithZone:NULL] autorelease];
    return archiveName;
}

- (void)replaceObject:(id)object withObject:(id)newObject {
    [self _replaceObject:object
              withObject:[newObject replacementObjectForArchiver:self]];
}

- (void)_replaceObject:(id)object withObject:(id)replacement {
    NSMapTableValueCallBacks valueCallBacks = { NULL, NULL, NULL };

#if defined(__ppc__) || defined(__POWERPC__)
    valueCallBacks = NSObjectMapValueCallBacks;
#endif
    if (self->replacementTable == NULL)
        self->replacementTable = NSCreateMapTableWithZone(
            NSNonOwnedPointerOrNullMapKeyCallBacks, valueCallBacks, 7, NULL);
    NSMapInsert(self->replacementTable, object, replacement);
}

- (void)encodeObject:(id)object {
    if (self->mdata != nil)
        _encodeOrReuseCString(self->mdata, "@",
                              (NSMapTable *)self->stringTable);
    _encodeObject(self, object);
}

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)address {
    const char *next;

    if (self->mdata != nil)
        _encodeOrReuseCString(self->mdata, type,
                              (NSMapTable *)self->stringTable);
    next = _encodeValueOfObjCType(self, type, address);
    if (*next != '\0')
        typeDescriptorError(*next, type,
                            "excess characters in type descriptor");
}

- (void)encodeArrayOfObjCType:(const char *)itemType count:(unsigned)count
                            at:(const void *)array {
    unsigned typeLength = (unsigned)strlen(itemType);
    unsigned size, alignment, index;
    char *descriptor = NSZoneMalloc(NULL, typeLength + 15);
    char *wrappedType;
    const char *elementType = itemType;
    const char *next;

    _NSsnprintf(descriptor, typeLength + 15, "[%u%s]", count, itemType);
    if (self->mdata != nil)
        _encodeOrReuseCString(self->mdata, descriptor,
                              (NSMapTable *)self->stringTable);
    NSZoneFree(NULL, descriptor);

    if (strcmp(itemType, "c") == 0) {
        if (self->mdata != nil)
            [self->mdata appendBytes:array length:count];
        return;
    }

    if (itemType[0] != '\0' && itemType[0] != '{' && itemType[1] != '\0') {
        wrappedType = __builtin_alloca(typeLength + 3);
        wrappedType[0] = '{';
        memcpy(wrappedType + 1, itemType, typeLength);
        wrappedType[typeLength + 1] = '}';
        wrappedType[typeLength + 2] = '\0';
        elementType = wrappedType;
    }

    next = _sizeOfType(elementType, &size, &alignment);
    if (*next != '\0')
        typeDescriptorError(*next, itemType,
                            "excess characters in type descriptor");
    for (index = 0; index < count; index++)
        _encodeValueOfObjCType(self, elementType,
                               (const char *)array + index * size);
}

- (void)encodeBytes:(const void *)bytes length:(unsigned)length {
    if (self->mdata == nil)
        return;
    _encodeOrReuseCString(self->mdata, "+",
                          (NSMapTable *)self->stringTable);
    _encodeInt(self->mdata, (int)length);
    [self->mdata appendBytes:bytes length:length];
}

@end

static Class _decodeClass(NSUnarchiver *unarchiver, NSUnarchiverContext *context) {
    Class aClass;
    void *label;
    char *archiveNameBytes;
    NSString *archiveName;
    NSString *trueName;
    unsigned version;

    if (![( _NSArchiverData *)context->data
            _decodeNewPtr:(void **)&aClass label:&label
            usingTable:context->pointerTable lastLabel:context->lastLabel
            atCursor:context->cursor])
        return aClass;

    archiveNameBytes = _decodeReusedCStringUsingTable(
        context->data, context->stringTable, context->cursor);
    archiveName = [[NSString allocWithZone:NULL]
        initWithCString:archiveNameBytes
                 length:(unsigned)strlen(archiveNameBytes)];
    version = _decodeIntAtCursor(context->data, context->cursor);
    trueName = NSUnarchiverDecodingMap != NULL
        ? NSMapGet(NSUnarchiverDecodingMap, archiveName) : nil;
    if (trueName == nil)
        trueName = [context->map objectForKey:archiveName];
    if (trueName == nil)
        trueName = archiveName;
    (void)[trueName isEqual:archiveName];

    aClass = NSClassFromString(trueName);
    if (aClass == Nil)
        [NSException raise:NSInconsistentArchiveException
                    format:@"*** class error for '%@': %@", trueName,
                           @"class not loaded"];
    (void)[aClass initialize];
    NSMapInsert(context->classVersions, trueName,
                (void *)(unsigned long)version);
    NSMapInsert(context->pointerTable, label, aClass);
    _decodeClass(unarchiver, context);
    [archiveName release];
    return aClass;
}

static id _decodeObject(NSUnarchiver *unarchiver, NSUnarchiverContext *context) {
    id object = nil;
    Class aClass;
    void *label;
    BOOL isNew;
    signed char marker;
    NSUnarchivedObjects *objects;

    isNew = [( _NSArchiverData *)context->data
        _decodeNewPtr:&object label:&label usingTable:context->pointerTable
        lastLabel:context->lastLabel atCursor:context->cursor];
    if (!isNew)
        return object;

    aClass = _decodeClass(unarchiver, context);
    if (context->streamerVersion == 3)
        _decodeIntAtCursor(context->data, context->cursor);
    if (aClass == Nil)
        [NSException raise:NSInconsistentArchiveException
                    format:@"*** class error for '%@': %@", @"NULL",
                           @"found null class"];

    if (aClass == __NSConcreteDataClass ||
        aClass == __NSConcreteMutableDataClass) {
        object = [[unarchiver decodeDataObject] retain];
    } else {
        object = [aClass allocWithZone:context->objectZone];
        NSMapInsert(context->pointerTable, label, object);
        object = [object initWithCoder:unarchiver];
        object = [object awakeAfterUsingCoder:unarchiver];
    }
    NSMapInsert(context->pointerTable, label, object);
    if (debugArchiver != 0)
        NSLog(@"Assigned label %d for object %x",
              (int)(unsigned long)label,
              (unsigned)(unsigned long)object);

    if (object != nil) {
        objects = context->allUnarchivedObjects;
        if (objects->capacity <= objects->count) {
            objects->capacity += 512;
            objects->objects = NSZoneRealloc(NULL, objects->objects,
                objects->capacity * sizeof(id));
        }
        objects->objects[objects->count++] = object;
    }
    if (debugArchiver != 0)
        NSLog(@"Assigned label %d for object %x",
              (int)(unsigned long)label,
              (unsigned)(unsigned long)object);

    if (*context->cursor >= [context->data length])
        prematureEnd(*context->cursor);
    marker = ((const signed char *)[context->data bytes])[(*context->cursor)++];
    if (marker != -122)
        [NSException raise:NSInconsistentArchiveException
                    format:@"*** NSUnarchiver: inconsistency between written and read data for object 0x%x",
                           (unsigned)(unsigned long)object];
    return object;
}

@implementation NSUnarchiver

- (id)decodeObject {
    NSUnarchiverContext context;
    const char *type;

    NSUNARCHIVER_CONTEXT(context, self);

    if (self->streamerVersion > 3) {
        type = _decodeReusedCStringUsingTable(
            self->data, self->stringTable, &self->cursor);
        checkExpected(type, "@");
    }
    return _decodeObject(self, &context);
}

@end

static const char *_decodeValueOfObjCType(NSUnarchiver *unarchiver,
                                             NSUnarchiverContext *context,
                                             const char *type, void *value) {
    const char *cursor = type + 1;

    switch (*type) {
    case '!':
        return cursor;
    case 'c': case 'C': {
        signed char byte;

        if (*context->cursor >= [context->data length])
            prematureEnd(*context->cursor);
        byte = ((const signed char *)[context->data bytes])[(*context->cursor)++];
        memcpy(value, &byte, sizeof(byte));
        return cursor;
    }
    case 's': case 'S': {
        signed char marker;
        short number;

        if (*context->cursor >= [context->data length])
            prematureEnd(*context->cursor);
        marker = ((const signed char *)[context->data bytes])[(*context->cursor)++];
        if (marker == -127) {
            [context->data deserializeBytes:&number length:sizeof(number)
                                atCursor:context->cursor];
            if (((_NSArchiverData *)context->data)->swap)
                number = (short)((unsigned short)number >> 8 |
                                 (unsigned short)number << 8);
        } else {
            number = marker;
        }
        memcpy(value, &number, sizeof(number));
        return cursor;
    }
    case 'i': case 'I': case 'l': case 'L': {
        int number = (int)_decodeIntAtCursor(context->data, context->cursor);

        memcpy(value, &number, sizeof(number));
        return cursor;
    }
    case 'q': case 'Q': {
        signed char marker;
        long long number;

        if (*context->cursor >= [context->data length])
            prematureEnd(*context->cursor);
        marker = ((const signed char *)[context->data bytes])[(*context->cursor)++];
        if (marker == -121) {
            [context->data deserializeBytes:&number length:sizeof(number)
                                atCursor:context->cursor];
            if (((_NSArchiverData *)context->data)->swap) {
                unsigned long long bits = (unsigned long long)number;
                bits = ((bits & 0x00000000000000ffULL) << 56) |
                       ((bits & 0x000000000000ff00ULL) << 40) |
                       ((bits & 0x0000000000ff0000ULL) << 24) |
                       ((bits & 0x00000000ff000000ULL) << 8) |
                       ((bits & 0x000000ff00000000ULL) >> 8) |
                       ((bits & 0x0000ff0000000000ULL) >> 24) |
                       ((bits & 0x00ff000000000000ULL) >> 40) |
                       ((bits & 0xff00000000000000ULL) >> 56);
                number = (long long)bits;
            }
        } else {
            number = (int)_decodeIntStartingWithChar(
                context->data, marker, context->cursor);
        }
        memcpy(value, &number, sizeof(number));
        return cursor;
    }
    case 'f': case 'd': {
        signed char marker;
        double number;

        if (*context->cursor >= [context->data length])
            prematureEnd(*context->cursor);
        marker = ((const signed char *)[context->data bytes])[(*context->cursor)++];
        if (marker == -125) {
            if (*type == 'f') {
                float floatNumber;

                [context->data deserializeBytes:&floatNumber
                                      length:sizeof(floatNumber)
                                    atCursor:context->cursor];
                if (((_NSArchiverData *)context->data)->swap) {
                    unsigned bits;
                    memcpy(&bits, &floatNumber, sizeof(bits));
                    bits = (bits >> 24) | ((bits >> 8) & 0x0000ff00) |
                           ((bits << 8) & 0x00ff0000) | (bits << 24);
                    memcpy(&floatNumber, &bits, sizeof(bits));
                }
                memcpy(value, &floatNumber, sizeof(floatNumber));
            } else {
                [context->data deserializeBytes:&number length:sizeof(number)
                                    atCursor:context->cursor];
                if (((_NSArchiverData *)context->data)->swap) {
                    unsigned long long bits;
                    memcpy(&bits, &number, sizeof(bits));
                    bits = ((bits & 0x00000000000000ffULL) << 56) |
                           ((bits & 0x000000000000ff00ULL) << 40) |
                           ((bits & 0x0000000000ff0000ULL) << 24) |
                           ((bits & 0x00000000ff000000ULL) << 8) |
                           ((bits & 0x000000ff00000000ULL) >> 8) |
                           ((bits & 0x0000ff0000000000ULL) >> 24) |
                           ((bits & 0x00ff000000000000ULL) >> 40) |
                           ((bits & 0xff00000000000000ULL) >> 56);
                    memcpy(&number, &bits, sizeof(bits));
                }
                memcpy(value, &number, sizeof(number));
            }
        } else {
            number = (int)_decodeIntStartingWithChar(
                context->data, marker, context->cursor);
            if (*type == 'f') {
                float floatNumber = (float)number;

                memcpy(value, &floatNumber, sizeof(floatNumber));
            } else {
                memcpy(value, &number, sizeof(number));
            }
        }
        return cursor;
    }
    case '@': {
        id object = _decodeObject(unarchiver, context);

        if (object != nil)
            [object retain];

        memcpy(value, &object, sizeof(object));
        return cursor;
    }
    case '#': {
        Class aClass = _decodeClass(unarchiver, context);

        memcpy(value, &aClass, sizeof(aClass));
        return cursor;
    }
    case '%': {
        char *string = _decodeReusedCStringUsingTable(
            context->data, context->stringTable, context->cursor);
        void *uniqueString = _NSUniqueCString(string);

        memcpy(value, &uniqueString, sizeof(uniqueString));
        return cursor;
    }
    case ':': {
        char *name = _decodeReusedCStringUsingTable(
            context->data, context->stringTable, context->cursor);
        SEL selector = sel_registerName(name);

        memcpy(value, &selector, sizeof(selector));
        return cursor;
    }
    case '*': {
        char *string = NULL;
        void *label;
        BOOL isNew = [( _NSArchiverData *)context->data
            _decodeNewPtr:(void **)&string label:&label
            usingTable:context->pointerTable lastLabel:context->lastLabel
            atCursor:context->cursor];

        if (isNew) {
            string = _decodeReusedCStringUsingTable(
                context->data, context->stringTable, context->cursor);
            NSMapInsert(context->pointerTable, label, string);
        }
        if (string != NULL) {
            unsigned length = (unsigned)strlen(string) + 1;
            char *copy = NSZoneMalloc(context->objectZone, length);

            memcpy(copy, string, length);
            string = copy;
        }
        memcpy(value, &string, sizeof(string));
        return cursor;
    }
    case '[': {
        unsigned count = 0;
        unsigned size, alignment, index;
        const char *end;

        while (*cursor >= '0' && *cursor <= '9')
            count = count * 10 + (unsigned)(*cursor++ - '0');
        end = _sizeOfType(cursor, &size, &alignment);
        for (index = 0; index < count; index++)
            _decodeValueOfObjCType(unarchiver, context, cursor,
                                (char *)value + index * size);
        if (*end != ']')
            typeDescriptorError(*end, type, "missing ']' in type descriptor");
        return end + 1;
    }
    case '{': {
        unsigned offset = 0;

        cursor = _skipAggregateName(cursor);
        while (*cursor != '}' && *cursor != '\0') {
            unsigned size, alignment;
            const char *next = _sizeOfType(cursor, &size, &alignment);

            if (alignment == 0)
                alignment = 1;
            offset = alignment * ((offset + alignment - 1) / alignment);
            _decodeValueOfObjCType(unarchiver, context, cursor,
                                        (char *)value + offset);
            offset += size;
            cursor = next;
        }
        if (*cursor != '}')
            typeDescriptorError(*cursor, type, "unknown type descriptor");
        return cursor + 1;
    }
    case '(': {
        unsigned size, alignment, index;
        const char *end = _sizeOfType(type, &size, &alignment);

        for (index = 0; index < size; index++)
            _decodeValueOfObjCType(unarchiver, context, "C",
                                   (char *)value + index);
        return end;
    }
    default:
        typeDescriptorError(*type, type, "unknown type descriptor");
        return cursor;
    }
}

@implementation NSUnarchiver

- (void)decodeValueOfObjCType:(const char *)type at:(void *)value {
    NSUnarchiverContext context;
    const char *encodedType = _decodeReusedCStringUsingTable(
        self->data, self->stringTable, &self->cursor);
    const char *next;

    NSUNARCHIVER_CONTEXT(context, self);
    checkExpected(encodedType, type);
    next = _decodeValueOfObjCType(self, &context, type, value);
    if (*next != '\0')
        typeDescriptorError(*next, type, "excess characters in type descriptor");
}

- (void)decodeValuesOfObjCTypes:(const char *)types, ... {
    NSUnarchiverContext context;
    const char *encodedType = _decodeReusedCStringUsingTable(
        self->data, self->stringTable, &self->cursor);
    const char *cursor = types;
    va_list arguments;

    checkExpected(encodedType, types);
    NSUNARCHIVER_CONTEXT(context, self);
    va_start(arguments, types);
    while (*cursor != '\0') {
        void *destination = va_arg(arguments, void *);
        cursor = _decodeValueOfObjCType(self, &context, cursor, destination);
    }
    va_end(arguments);
}

- (void)decodeArrayOfObjCType:(const char *)itemType count:(unsigned)count
                           at:(void *)array {
    NSUnarchiverContext context;
    unsigned typeLength = (unsigned)strlen(itemType);
    char *expected = NSZoneMalloc(NULL, typeLength + 15);
    char *wrappedType;
    const char *elementType = itemType;
    const char *encodedType;
    const char *cursor;
    unsigned size, alignment, index;

    NSUNARCHIVER_CONTEXT(context, self);
    _NSsnprintf(expected, typeLength + 15, "[%u%s]", count, itemType);
    encodedType = _decodeReusedCStringUsingTable(
        self->data, self->stringTable, &self->cursor);
    checkExpected(encodedType, expected);
    NSZoneFree(NULL, expected);
    if (strcmp(itemType, "c") == 0) {
        [self->data deserializeBytes:array length:count atCursor:&self->cursor];
        return;
    }

    if (itemType[0] != '\0' && itemType[0] != '{' && itemType[1] != '\0') {
        wrappedType = __builtin_alloca(typeLength + 3);
        wrappedType[0] = '{';
        memcpy(wrappedType + 1, itemType, typeLength);
        wrappedType[typeLength + 1] = '}';
        wrappedType[typeLength + 2] = '\0';
        elementType = wrappedType;
    }

    cursor = _sizeOfType(elementType, &size, &alignment);
    if (*cursor != '\0')
        typeDescriptorError(*cursor, itemType, "excess characters in type descriptor");
    for (index = 0; index < count; index++)
        _decodeValueOfObjCType(self, &context, elementType,
                              (char *)array + size * index);
}

- (NSData *)decodeDataObject {
    int length;
    NSMutableData *data;

    [self decodeValueOfObjCType:"i" at:&length];
    data = [[NSMutableData allocWithZone:self->objectZone]
        initWithLength:(unsigned)length];
    [self decodeArrayOfObjCType:"c" count:(unsigned)length
                             at:[data mutableBytes]];
    return [data autorelease];
}

- (void *)decodeBytesWithReturnedLength:(unsigned *)lengthp {
    const char *type;
    unsigned length;
    void *bytes;

    if (self->streamerVersion > 3) {
        type = _decodeReusedCStringUsingTable(
            self->data, self->stringTable, &self->cursor);
        checkExpected(type, "+");
    }
    length = _decodeIntAtCursor(self->data, &self->cursor);
    *lengthp = length;
    bytes = (char *)[self->data bytes] + self->cursor;
    self->cursor += length;
    return bytes;
}

- (unsigned)versionForClassName:(NSString *)className {
    void *version;

    if (NSMapMember(self->classVersions, className, NULL, &version))
        return (unsigned)(unsigned long)version;
    return 0x7fffffff;
}

+ (void)initialize {
    if (self != [NSUnarchiver class])
        return;
    [self decodeClassName:@"NSMoneyFormatter" asClassName:@"NSNumberFormatter"];
    [self decodeClassName:@"NSWindowsDefaultTimeZone"
             asClassName:@"NSWindowsDefaultTimeZoneDecoder"];
    [self decodeClassName:@"NSTimeZoneDetail" asClassName:@"NSTimeZoneDetailDecoder"];
}

- (id)initForReadingWithData:(NSData *)data {
    _NSArchiverData *archiveData;
    char *streamType;
    NSMapTableValueCallBacks valueCallBacks = { NULL, NULL, NULL };
    NSUnarchivedObjects *objects;

    if (data == nil)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -initForReadingWithData: nil argument"];
    archiveData = [[_NSArchiverData allocWithZone:NULL] initWithData:data];
    self->data = archiveData;
    if ([archiveData length] <= self->cursor)
        prematureEnd(self->cursor);
    self->streamerVersion = ((const signed char *)[archiveData bytes])[
        self->cursor++];
    if (self->streamerVersion != 3 && self->streamerVersion != 4) {
        [self dealloc];
        return nil;
    }

    streamType = _decodeCStringAtCursor(archiveData, &self->cursor);
    if (strcmp(streamType, "typedstream") == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        [archiveData _setSwap:0];
#else
        [archiveData _setSwap:1];
#endif
    } else if (strcmp(streamType, "streamtyped") == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        [archiveData _setSwap:1];
#else
        [archiveData _setSwap:0];
#endif
    } else {
        [self dealloc];
        return nil;
    }
    NSZoneFree(NULL, streamType);

    if ([archiveData length] <= self->cursor)
        prematureEnd(self->cursor);
    self->systemVersion = _decodeIntStartingWithChar(
        archiveData, ((const signed char *)[archiveData bytes])[self->cursor++],
        &self->cursor);
    self->pointerTable = NSCreateMapTableWithZone(
        NSIntMapKeyCallBacks, valueCallBacks, 0x100, NULL);
    self->stringTable = _createStringTable();
    self->classVersions = NSCreateMapTableWithZone(
        NSObjectMapKeyCallBacks, valueCallBacks, 0x20, NULL);
    self->objectZone = NULL;
    self->lastLabel = -111;
    objects = NSZoneMalloc(NULL, sizeof(*objects));
    objects->count = 0;
    objects->capacity = 512;
    objects->objects = NSZoneMalloc(NULL, objects->capacity * sizeof(id));
    self->allUnarchivedObjects = objects;
    return self;
}

- (void)setObjectZone:(NSZone *)zone {
    self->objectZone = zone;
}

- (NSZone *)objectZone {
    return self->objectZone;
}

- (NSData *)data {
    return self->data;
}

- (BOOL)isAtEnd {
    return self->cursor >= [self->data length];
}

- (unsigned)systemVersion {
    return self->systemVersion;
}

+ (id)unarchiveObjectWithData:(NSData *)data {
    NSUnarchiver *unarchiver = [[self allocWithZone:NULL]
        initForReadingWithData:data];
    id object = [unarchiver decodeObject];

    if (![unarchiver isAtEnd])
        NSLog(@"*** +[NSUnarchiver unarchiveObjectWithData:]: extra data discarded");
    [object retain];
    [object autorelease];
    [unarchiver release];
    return object;
}

+ (id)unarchiveObjectWithFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];

    return data != nil ? [self unarchiveObjectWithData:data] : nil;
}

+ (void)decodeClassName:(NSString *)inArchiveName asClassName:(NSString *)trueName {
    NSMapTableValueCallBacks valueCallBacks;

    if (NSUnarchiverDecodingMap == NULL) {
        valueCallBacks = NSObjectMapValueCallBacks;
        NSUnarchiverDecodingMap = NSCreateMapTableWithZone(
            NSObjectMapKeyCallBacks, valueCallBacks, 0xaa, NULL);
    }
    NSMapInsert(NSUnarchiverDecodingMap, inArchiveName, trueName);
}

- (void)decodeClassName:(NSString *)inArchiveName asClassName:(NSString *)trueName {
    if (self->map == nil)
        self->map = [[NSMutableDictionary allocWithZone:NULL] init];
    [self->map setObject:trueName forKey:inArchiveName];
}

+ (NSString *)classNameDecodedForArchiveClassName:(NSString *)inArchiveName {
    NSString *trueName;

    if (inArchiveName == nil)
        return nil;
    trueName = NSUnarchiverDecodingMap != NULL
        ? NSMapGet(NSUnarchiverDecodingMap, inArchiveName) : nil;
    if (trueName == nil)
        return [[inArchiveName copyWithZone:NULL] autorelease];
    return trueName;
}

- (NSString *)classNameDecodedForArchiveClassName:(NSString *)inArchiveName {
    NSString *trueName;

    if (inArchiveName == nil)
        return nil;
    trueName = [self->map objectForKey:inArchiveName];
    if (trueName == nil)
        return [[inArchiveName copyWithZone:NULL] autorelease];
    return trueName;
}

- (void)replaceObject:(id)object withObject:(id)newObject {
    NSMapEnumerator enumerator = NSEnumerateMapTable(self->pointerTable);
    void **keys;
    void *key;
    void *value;
    unsigned count = 0;
    unsigned index;

    keys = NSZoneMalloc(NULL,
        NSCountMapTable(self->pointerTable) * sizeof(void *));
    while (NSNextMapEnumeratorPair(&enumerator, &key, &value)) {
        if (value == object)
            keys[count++] = key;
    }
    for (index = 0; index < count; index++)
        NSMapInsert(self->pointerTable, keys[index], newObject);
    NSZoneFree(NULL, keys);
}

- (void)dealloc {
    NSUnarchivedObjects *objects = self->allUnarchivedObjects;
    unsigned index;

#if defined(__ppc__) || defined(__POWERPC__)
    if (__NSJavaArchiverCallout != NULL)
        ((void (*)(int, NSUnarchiver *, void *, void *))
            __NSJavaArchiverCallout)(3, self, NULL, NULL);
#endif
    [self->data release];
    if (self->pointerTable != NULL)
        NSFreeMapTable(self->pointerTable);
    if (self->stringTable != NULL)
        _freeStringTable(self->stringTable);
    if (self->classVersions != NULL)
        NSFreeMapTable(self->classVersions);
    [self->map release];
    if (objects != NULL) {
        for (index = objects->count; index != 0; )
            [objects->objects[--index] release];
        NSZoneFree(NULL, objects->objects);
        NSZoneFree(NULL, objects);
    }
    [super dealloc];
}

@end

@implementation NSObject (NSArchiverCallBack)

- (Class)classForArchiver {
    return [self classForCoder];
}

- (id)replacementObjectForArchiver:(NSArchiver *)archiver {
    return [self replacementObjectForCoder:archiver];
}

@end
