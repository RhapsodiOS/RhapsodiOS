/*	NSCoder.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCoder.h>
#import <Foundation/NSArchiver.h>
#import <Foundation/NSData.h>
#import <Foundation/NSMutableData.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSSerialization.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#include <stdarg.h>
#include <string.h>

extern int _NSsnprintf(char *buffer, size_t size, char *format, ...);

#if defined(__ppc__) || defined(__POWERPC__)
static unsigned char NSCoderEncodeNXObjectWarned;
static unsigned char NSCoderDecodeNXObjectWarned;

static void NSCoderWarnNXObjectCompatibility(id coder, SEL selector,
                                              unsigned char *warned)
{
    if (!*warned) {
        *warned = 1;
        NSLog(@"%@: warning: Object compatibility method has been executed at least once.  Convert source code off it NOW!",
              _NSMethodExceptionProem(coder, selector));
    }
}
#endif

/*	NSCoder's instance_size is 4 -- isa only, no storage of its own.
	Its abstract primitives report subclass responsibility through
	NSRequestConcreteImplementation.  Concrete coders provide the backing
	store and override these methods.  */

@implementation NSCoder

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr
{
    NSRequestConcreteImplementation(self, _cmd, [NSCoder class]);
}

- (void)encodeDataObject:(NSData *)data
{
    NSRequestConcreteImplementation(self, _cmd, [NSCoder class]);
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data
{
    NSRequestConcreteImplementation(self, _cmd, [NSCoder class]);
}

- (NSData *)decodeDataObject
{
    NSRequestConcreteImplementation(self, _cmd, [NSCoder class]);
    return nil;
}

- (unsigned)versionForClassName:(NSString *)className
{
    NSRequestConcreteImplementation(self, _cmd, [NSCoder class]);
    return 0;
}

#if defined(__ppc__) || defined(__POWERPC__)
- (void)encodeNXObject:(id)object
{
    NSData *data;

    NSCoderWarnNXObjectCompatibility(self, _cmd,
                                     &NSCoderEncodeNXObjectWarned);
    data = [NSArchiver archivedDataWithRootObject:object];
    [self encodeDataObject:data];
}

- (id)decodeNXObject
{
    NSData *data;

    NSCoderWarnNXObjectCompatibility(self, _cmd,
                                     &NSCoderDecodeNXObjectWarned);
    data = [self decodeDataObject];
    return [NSUnarchiver unarchiveObjectWithData:data];
}
#endif

/*
	The object conveniences.  At NSCoder's own level every object
	flavour encodes the same way -- the id by value through the "@"
	primitive -- because bycopy/byref/conditional/root distinction is
	real coder's machinery (NSArchiver stage 6, NSPortCoder stage 8);
	the reference's generic fallbacks confirmed from its disassembly
	all funnel into the primitive.  A real coder overrides these.
	*/
- (void)encodeObject:(id)object
{
    [self encodeValueOfObjCType:"@" at:&object];
}

- (id)decodeObject
{
    id object;

    [self decodeValueOfObjCType:"@" at:&object];
    return [object autorelease];
}

- (void)encodeBycopyObject:(id)anObject
{
    [self encodeObject:anObject];
}

- (void)encodeByrefObject:(id)anObject
{
    [self encodeObject:anObject];
}

- (void)encodeConditionalObject:(id)object
{
    [self encodeObject:object];
}

- (void)encodeRootObject:(id)rootObject
{
    [self encodeObject:rootObject];
}

/*
	The base-class varargs conveniences consume one encoding byte and
	one address argument at a time.  Concrete coders may override this
	path with their own descriptor handling.  */
- (void)encodeValuesOfObjCTypes:(const char *)types, ...
{
    va_list args;
    const char *cursor;

    va_start(args, types);
    cursor = types;
    while (*cursor != '\0') {
        void *value = va_arg(args, void *);

        [self encodeValueOfObjCType:cursor at:value];
        cursor++;
    }
    va_end(args);
}

- (void)decodeValuesOfObjCTypes:(const char *)types, ...
{
    va_list args;
    const char *cursor;

    va_start(args, types);
    cursor = types;
    while (*cursor != '\0') {
        void *destination = va_arg(args, void *);

        [self decodeValueOfObjCType:cursor at:destination];
        cursor++;
    }
    va_end(args);
}

- (void)encodeArrayOfObjCType:(const char *)type count:(unsigned)count at:(const void *)array
{
    unsigned length = (unsigned)strlen(type);
    char *arrayType = __builtin_alloca(length + 16);
    char format[] = "[%u%s]";

    _NSsnprintf(arrayType, length + 16, format, count, type);
    [self encodeValueOfObjCType:arrayType at:array];
}

- (void)decodeArrayOfObjCType:(const char *)itemType count:(unsigned)count at:(void *)array
{
    unsigned length = (unsigned)strlen(itemType);
    char *arrayType = __builtin_alloca(length + 16);
    char format[] = "[%u%s]";

    _NSsnprintf(arrayType, length + 16, format, count, itemType);
    [self decodeValueOfObjCType:arrayType at:array];
}

/*  The parameter is NOT const: the reference's method-list encoding is
    v16@8:12^v16I20 (abi-check Gate 1, stage 2c) -- an `r` qualifier in
    the source would compile into the encoding and diverge (probed:
    this cc1obj emits `r^v`/`r*` for const pointer params).  The
    mismatch with NSCoder.h's `const void *` declaration is Apple's
    own -- their shipped binary carries the same header/implementation
    pair -- and the header stays untouched under the programme's
    no-header-modification constraint.  The old cc treats the
    conflicting-types situation as a warning; message dispatch never
    reads it.  */
- (void)encodeBytes:(void *)byteaddr length:(unsigned)length
{
    [self encodeValueOfObjCType:"I" at:&length];
    [self encodeArrayOfObjCType:"c" count:length at:byteaddr];
}

- (void *)decodeBytesWithReturnedLength:(unsigned *)lengthp
{
    NSMutableData *data;
    void *bytes;

    [self decodeValueOfObjCType:"I" at:lengthp];
    data = [NSMutableData dataWithLength:*lengthp];
    bytes = [data mutableBytes];
    [self decodeArrayOfObjCType:"c" count:*lengthp at:bytes];
    return bytes;
}

/*	NSCoder has no ivars (instance_size 4), so the base class carries
	no zone of its own: the zone is whatever the concrete subclass
	records, and the generic fallback is the default malloc zone.  */
- (void)setObjectZone:(NSZone *)zone
{
}

- (NSZone *)objectZone
{
    return NSDefaultMallocZone();
}

/*	A fixed constant identifying this coding format's revision.
	Confirmed from the reference's raw bytes at 0x4257385c:
	mov eax, 0x3e8 -- 1000.  */
- (unsigned)systemVersion
{
    return 1000;
}

/*	The reference serializes property lists to NSData before encoding them as a
	data object; decoding reverses that path with mutableContainers:NO.  */
- (void)encodePropertyList:(id)aPropertyList
{
    NSData *data = [NSSerializer serializePropertyList:aPropertyList];

    [self encodeDataObject:data];
}

- (id)decodePropertyList
{
    NSData *data = [self decodeDataObject];

    return [NSDeserializer deserializePropertyListFromData:data
                                         mutableContainers:NO];
}

/*  NSTypedstreamCompatibility pair.  Gate 1 (stage 2c) walked the
    reference's 80 __OBJC,__module_info records: the pair is NOT here
    -- NSCoder's own class record is 22 flat methods with no category,
    and the pair lives in NSCoder(NSTypedstreamCompatibility) inside
    NSCompatibility.m (a later stage's module, outside this stage's
    abi-check set).  Moved there; the ABI comparison is authoritative.  */

@end

/*
	"Given an NSCoder, returns an object previously written with
	NXWriteNSObject()" -- the reference's 168-byte body resolves to a
	decodeObject send plus awake/fault bookkeeping, matching
	-decodeObject's contract exactly.  */
NSObject *
NXReadNSObjectFromCoder(NSCoder *decoder)
{
    return [decoder decodeObject];
}

#if !defined(__ppc__) && !defined(__POWERPC__)
typedef void NXTypedStream;

extern void NXReadTypes(NXTypedStream *stream, const char *types, ...);
extern int NXReadArray(NXTypedStream *stream, const char *type, int count,
                       void *data);
extern void NXWriteTypes(NXTypedStream *stream, const char *types, ...);
extern int NXWriteArray(NXTypedStream *stream, const char *type, int count,
                        const void *data);
extern id _NSNewImmutableDataNoCopy(const void *bytes, unsigned length,
                                    NSZone *zone);

id
NXReadNSObject(NXTypedStream *stream)
{
    unsigned size;
    void *bytes;
    id data;
    id object;

    NXReadTypes(stream, "i", &size);
    bytes = NSZoneMalloc(NULL, size);
    NXReadArray(stream, "c", (int)size, bytes);
    data = _NSNewImmutableDataNoCopy(bytes, size, NULL);
    object = [NSUnarchiver unarchiveObjectWithData:data];
    [data release];
    return object;
}

int
NXWriteNSObject(NXTypedStream *stream, id object)
{
    NSData *data = [NSArchiver archivedDataWithRootObject:object];
    unsigned size = [data length];

    NXWriteTypes(stream, "i", &size);
    return NXWriteArray(stream, "c", (int)size, [data bytes]);
}
#endif
