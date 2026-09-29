/*	NSCoder.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

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

- (void)encodeObject:(id)object {
    // TODO: Implement this method
}

- (void)encodePropertyList:(id)aPropertyList {
    // TODO: Implement this method
}

- (void)encodeRootObject:(id)rootObject {
    // TODO: Implement this method
}

- (void)encodeBycopyObject:(id)anObject {
    // TODO: Implement this method
}

- (void)encodeByrefObject:(id)anObject {
    // TODO: Implement this method
}

- (void)encodeConditionalObject:(id)object {
    // TODO: Implement this method
}

- (void)encodeValuesOfObjCTypes:(const char *)types, ... {
    // TODO: Implement this method
}

- (void)encodeArrayOfObjCType:(const char *)type count:(unsigned)count at:(const void *)array {
    // TODO: Implement this method
}

- (void)encodeBytes:(const void *)byteaddr length:(unsigned)length {
    // TODO: Implement this method
}

- (id)decodeObject {
    // TODO: Implement this method
    return nil;
}

- (id)decodePropertyList {
    // TODO: Implement this method
    return nil;
}

- (void)decodeValuesOfObjCTypes:(const char *)types, ... {
    // TODO: Implement this method
}

- (void)decodeArrayOfObjCType:(const char *)itemType count:(unsigned)count at:(void *)array {
    // TODO: Implement this method
}

- (void *)decodeBytesWithReturnedLength:(unsigned *)lengthp {
    // TODO: Implement this method
    return nil;
}

- (void)setObjectZone:(NSZone *)zone {
    // TODO: Implement this method
}

- (NSZone *)objectZone {
    // TODO: Implement this method
    return nil;
}

- (unsigned)systemVersion {
    // TODO: Implement this method
    return 0;
}

- (void)encodeNXObject:(id)object {
    // TODO: Implement this method
}

- (id)decodeNXObject {
    // TODO: Implement this method
    return nil;
}

@end
