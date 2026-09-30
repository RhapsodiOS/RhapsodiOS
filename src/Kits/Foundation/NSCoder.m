/*	NSCoder.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#include <stdarg.h>
#include <string.h>

/*	NSCoder's instance_size is 4 -- isa only, no storage of its own.  Its
	five primitives have compiled bodies in the reference despite that,
	which -- given there is nowhere for a primitive to keep state -- can
	only mean each raises "subclass responsibility": the reference's
	reason literal "<method>: subclass should override ..." sits in
	__OBJC,__cstring_object, reached through _NSMethodExceptionProem plus
	the shared raise helper every primitive calls.  A real coder
	(NSArchiver, stage 6; NSPortCoder, stage 8) overrides all five with a
	concrete backing store.  Tasks 3-4 fill in the remaining methods.  */

@implementation NSCoder

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override encodeValueOfObjCType:at:", proem];
}

- (void)encodeDataObject:(NSData *)data
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override encodeDataObject:", proem];
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override decodeValueOfObjCType:at:", proem];
}

- (NSData *)decodeDataObject
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override decodeDataObject", proem];
    return nil;
}

- (unsigned)versionForClassName:(NSString *)className
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override versionForClassName:", proem];
    return 0;
}

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
    return object;
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
	The varargs conveniences.  Each type token is consumed exactly as
	NSGetSizeAndAlignment delimits it, then the matching va_arg is
	taken with the default promotions: ids as ids, everything no
	wider than an int as int (the integer promotions), anything wider
	as double.  */
- (void)encodeValuesOfObjCTypes:(const char *)types, ...
{
    va_list args;
    const char *cursor;

    va_start(args, types);
    cursor = types;
    while (*cursor != '\0') {
        unsigned size, align;
        const char *typeStart = cursor;
        char typeBuffer[32];
        unsigned typeLength;

        cursor = NSGetSizeAndAlignment(cursor, &size, &align);
        typeLength = (unsigned)(cursor - typeStart);
        if (typeLength >= sizeof(typeBuffer))
            typeLength = sizeof(typeBuffer) - 1;
        memcpy(typeBuffer, typeStart, typeLength);
        typeBuffer[typeLength] = '\0';

        if (typeBuffer[0] == '@') {
            id value = va_arg(args, id);

            [self encodeValueOfObjCType:typeBuffer at:&value];
        } else if (size <= sizeof(int)) {
            int value = va_arg(args, int);

            [self encodeValueOfObjCType:typeBuffer at:&value];
        } else {
            double value = va_arg(args, double);

            [self encodeValueOfObjCType:typeBuffer at:&value];
        }
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
        unsigned size, align;
        const char *typeStart = cursor;
        char typeBuffer[32];
        unsigned typeLength;
        void *destination;

        cursor = NSGetSizeAndAlignment(cursor, &size, &align);
        typeLength = (unsigned)(cursor - typeStart);
        if (typeLength >= sizeof(typeBuffer))
            typeLength = sizeof(typeBuffer) - 1;
        memcpy(typeBuffer, typeStart, typeLength);
        typeBuffer[typeLength] = '\0';

        destination = va_arg(args, void *);
        [self decodeValueOfObjCType:typeBuffer at:destination];
    }
    va_end(args);
}

- (void)encodeArrayOfObjCType:(const char *)type count:(unsigned)count at:(const void *)array
{
    unsigned size, align;
    unsigned i;
    const char *element = (const char *)array;

    NSGetSizeAndAlignment(type, &size, &align);
    for (i = 0; i < count; i++) {
        [self encodeValueOfObjCType:type at:element];
        element += size;
    }
}

- (void)decodeArrayOfObjCType:(const char *)itemType count:(unsigned)count at:(void *)array
{
    unsigned size, align;
    unsigned i;
    char *element = (char *)array;

    NSGetSizeAndAlignment(itemType, &size, &align);
    for (i = 0; i < count; i++) {
        [self decodeValueOfObjCType:itemType at:element];
        element += size;
    }
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
    unsigned length;
    void *buffer;

    [self decodeValueOfObjCType:"I" at:&length];
    buffer = NSZoneMalloc([self objectZone], length);
    [self decodeArrayOfObjCType:"c" count:length at:buffer];
    if (lengthp != NULL)
        *lengthp = length;
    return buffer;
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

/*
	Property-list and typedstream compatibility.  The reference's own
	bodies for all four methods are 2-6 message sends through the
	encodeObject:/decodeObject selector family (its __message_refs
	slots sit adjacent to decodeObject's), plus awake/fault machinery
	owned by later stages.  This stage carries the sends its tests can
	observe; the 748-byte ASCII/typedstream parser
	(__NSParseObjectFromASCIIPropertyListOrSerialization) turns raw
	text into real NSString/NSDictionary/NSArray/NSData records, none
	of which exist before stages 3-4, so the parser itself is
	reconstructed with them.  Recorded in divergences.md.
	*/
- (void)encodePropertyList:(id)aPropertyList
{
    [self encodeObject:aPropertyList];
}

- (id)decodePropertyList
{
    return [self decodeObject];
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
