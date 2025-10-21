/*	NSArchiver.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSArchiver.h>

@implementation NSArchiver

- (id)initForWritingWithMutableData:(NSMutableData *)mdata {
    // TODO: Implement this method
    return nil;
}

- (NSMutableData *)archiverData {
    // TODO: Implement this method
    return nil;
}

- (void)encodeRootObject:(id)rootObject {
    // TODO: Implement this method
}

- (void)encodeConditionalObject:(id)object {
    // TODO: Implement this method
}

+ (NSData *)archivedDataWithRootObject:(id)rootObject {
    // TODO: Implement this method
    return nil;
}

+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString *)path {
    // TODO: Implement this method
    return NO;
}

- (void)encodeClassName:(NSString *)trueName intoClassName:(NSString *)inArchiveName {
    // TODO: Implement this method
}

- (NSString *)classNameEncodedForTrueClassName:(NSString *)trueName {
    // TODO: Implement this method
    return nil;
}

- (void)replaceObject:(id)object withObject:(id)newObject {
    // TODO: Implement this method
}

@end

@implementation NSUnarchiver

- (id)initForReadingWithData:(NSData *)data {
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

- (BOOL)isAtEnd {
    // TODO: Implement this method
    return NO;
}

- (unsigned)systemVersion {
    // TODO: Implement this method
    return 0;
}

+ (id)unarchiveObjectWithData:(NSData *)data {
    // TODO: Implement this method
    return nil;
}

+ (id)unarchiveObjectWithFile:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

+ (void)decodeClassName:(NSString *)inArchiveName asClassName:(NSString *)trueName {
    // TODO: Implement this method
}

- (void)decodeClassName:(NSString *)inArchiveName asClassName:(NSString *)trueName {
    // TODO: Implement this method
}

+ (NSString *)classNameDecodedForArchiveClassName:(NSString *)inArchiveName {
    // TODO: Implement this method
    return nil;
}

- (NSString *)classNameDecodedForArchiveClassName:(NSString *)inArchiveName {
    // TODO: Implement this method
    return nil;
}

- (void)replaceObject:(id)object withObject:(id)newObject {
    // TODO: Implement this method
}

@end

@implementation NSObject

- (Class)classForArchiver {
    // TODO: Implement this method
    return nil;
}

- (id)replacementObjectForArchiver:(NSArchiver *)archiver {
    // TODO: Implement this method
    return nil;
}

@end
