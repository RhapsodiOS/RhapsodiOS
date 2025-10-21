/*	NSFileManager.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSFileManager.h>

@implementation NSFileManager

+ (NSFileManager *)defaultManager {
    // TODO: Implement this method
    return nil;
}

- (NSString *)currentDirectoryPath {
    // TODO: Implement this method
    return nil;
}

- (BOOL)changeCurrentDirectoryPath:(NSString *)path {
    // TODO: Implement this method
    return NO;
}

- (NSDictionary *)fileAttributesAtPath:(NSString *)path traverseLink:(BOOL)yorn {
    // TODO: Implement this method
    return nil;
}

- (BOOL)changeFileAttributes:(NSDictionary *)attributes atPath:(NSString *)path {
    // TODO: Implement this method
    return NO;
}

- (BOOL)fileExistsAtPath:(NSString *)path {
    // TODO: Implement this method
    return NO;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isReadableFileAtPath:(NSString *)path {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isWritableFileAtPath:(NSString *)path {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isExecutableFileAtPath:(NSString *)path {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isDeletableFileAtPath:(NSString *)path {
    // TODO: Implement this method
    return NO;
}

- (BOOL)contentsEqualAtPath:(NSString *)path1 andPath:(NSString *)path2 {
    // TODO: Implement this method
    return NO;
}

- (BOOL)linkPath:(NSString *)src toPath:(NSString *)dest handler:handler {
    // TODO: Implement this method
    return NO;
}

- (BOOL)copyPath:(NSString *)src toPath:(NSString *)dest handler:handler {
    // TODO: Implement this method
    return NO;
}

- (BOOL)movePath:(NSString *)src toPath:(NSString *)dest handler:handler {
    // TODO: Implement this method
    return NO;
}

- (BOOL)removeFileAtPath:(NSString *)path handler:handler {
    // TODO: Implement this method
    return NO;
}

- (NSArray *)directoryContentsAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (NSDirectoryEnumerator *)enumeratorAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)subpathsAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (BOOL)createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes {
    // TODO: Implement this method
    return NO;
}

- (NSData *)contentsAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr {
    // TODO: Implement this method
    return NO;
}

- (NSString *)pathContentOfSymbolicLinkAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (BOOL)createSymbolicLinkAtPath:(NSString *)path pathContent:(NSString *)otherpath {
    // TODO: Implement this method
    return NO;
}

- (NSDictionary *)fileSystemAttributesAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (const char *)fileSystemRepresentationWithPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringWithFileSystemRepresentation:(const char *)str length:(unsigned)len {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSObject

- (BOOL)fileManager:(NSFileManager *)fm shouldProceedAfterError:(NSDictionary *)errorInfo {
    // TODO: Implement this method
    return NO;
}

- (void)fileManager:(NSFileManager *)fm willProcessPath:(NSString *)path {
    // TODO: Implement this method
}

@end

@implementation NSDirectoryEnumerator

- (NSDictionary *)fileAttributes {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)directoryAttributes {
    // TODO: Implement this method
    return nil;
}

- (void)skipDescendents {
    // TODO: Implement this method
}

@end

@implementation NSDictionary

- (unsigned long long)fileSize {
    // TODO: Implement this method
    return 0;
}

- (NSDate *)fileModificationDate {
    // TODO: Implement this method
    return nil;
}

- (NSString *)fileType {
    // TODO: Implement this method
    return nil;
}

- (unsigned long)filePosixPermissions {
    // TODO: Implement this method
    return 0;
}

- (NSString *)fileOwnerAccountName {
    // TODO: Implement this method
    return nil;
}

- (NSString *)fileGroupOwnerAccountName {
    // TODO: Implement this method
    return nil;
}

- (unsigned long)fileSystemNumber {
    // TODO: Implement this method
    return 0;
}

- (unsigned long)fileSystemFileNumber {
    // TODO: Implement this method
    return 0;
}

@end
