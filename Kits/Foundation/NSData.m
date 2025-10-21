/*	NSData.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSData.h>

@implementation NSData

- (unsigned)length {
    // TODO: Implement this method
    return 0;
}

- (const void *)bytes {
    // TODO: Implement this method
    return nil;
}

- (NSString *)description {
    // TODO: Implement this method
    return nil;
}

- (void)getBytes:(void *)buffer {
    // TODO: Implement this method
}

- (void)getBytes:(void *)buffer length:(unsigned)length {
    // TODO: Implement this method
}

- (void)getBytes:(void *)buffer range:(NSRange)range {
    // TODO: Implement this method
}

- (BOOL)isEqualToData:(NSData *)other {
    // TODO: Implement this method
    return NO;
}

- (NSData *)subdataWithRange:(NSRange)range {
    // TODO: Implement this method
    return nil;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    // TODO: Implement this method
    return NO;
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically; // the atomically flag is ignored if the url is not of a type the supports atomic writes {
    // TODO: Implement this method
    return NO;
}

+ (id)data {
    // TODO: Implement this method
    return nil;
}

+ (id)dataWithBytes:(const void *)bytes length:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

+ (id)dataWithBytesNoCopy:(void *)bytes length:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

+ (id)dataWithContentsOfFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

+ (id)dataWithContentsOfURL:(NSURL *)url {
    // TODO: Implement this method
    return nil;
}

+ (id)dataWithContentsOfMappedFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (id)initWithBytes:(const void *)bytes length:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

- (id)initWithBytesNoCopy:(void *)bytes length:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

- (id)initWithContentsOfFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (id)initWithContentsOfURL:(NSURL *)url {
    // TODO: Implement this method
    return nil;
}

- (id)initWithContentsOfMappedFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (id)initWithData:(NSData *)data {
    // TODO: Implement this method
    return nil;
}

+ (id)dataWithData:(NSData *)data {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSMutableData

- (void *)mutableBytes {
    // TODO: Implement this method
    return nil;
}

- (void)setLength:(unsigned)length {
    // TODO: Implement this method
}

- (void)appendBytes:(const void *)bytes length:(unsigned)length {
    // TODO: Implement this method
}

- (void)appendData:(NSData *)other {
    // TODO: Implement this method
}

- (void)increaseLengthBy:(unsigned)extraLength {
    // TODO: Implement this method
}

- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes {
    // TODO: Implement this method
}

- (void)resetBytesInRange:(NSRange)range {
    // TODO: Implement this method
}

- (void)setData:(NSData *)data {
    // TODO: Implement this method
}

+ (id)dataWithCapacity:(unsigned)aNumItems {
    // TODO: Implement this method
    return nil;
}

+ (id)dataWithLength:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

- (id)initWithCapacity:(unsigned)capacity {
    // TODO: Implement this method
    return nil;
}

- (id)initWithLength:(unsigned)length {
    // TODO: Implement this method
    return nil;
}

@end
