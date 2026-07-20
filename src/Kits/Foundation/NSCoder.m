/*	NSCoder.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCoder.h>

@implementation NSCoder

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr {
    // TODO: Implement this method
}

- (void)encodeDataObject:(NSData *)data {
    // TODO: Implement this method
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data {
    // TODO: Implement this method
}

- (NSData *)decodeDataObject {
    // TODO: Implement this method
    return nil;
}

- (unsigned)versionForClassName:(NSString *)className {
    // TODO: Implement this method
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
