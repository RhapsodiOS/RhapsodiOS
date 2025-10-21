/*	NSPathUtilities.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPathUtilities.h>

@implementation NSString

+ (NSString *)pathWithComponents:(NSArray *)components {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)pathComponents {
    // TODO: Implement this method
    return nil;
}

- (BOOL)isAbsolutePath {
    // TODO: Implement this method
    return NO;
}

- (NSString *)lastPathComponent {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByDeletingLastPathComponent {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByAppendingPathComponent:(NSString *)str {
    // TODO: Implement this method
    return nil;
}

- (NSString *)pathExtension {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByDeletingPathExtension {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByAppendingPathExtension:(NSString *)str {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByAbbreviatingWithTildeInPath {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByExpandingTildeInPath {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByStandardizingPath {
    // TODO: Implement this method
    return nil;
}

- (NSString *)stringByResolvingSymlinksInPath {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)stringsByAppendingPaths:(NSArray *)paths {
    // TODO: Implement this method
    return nil;
}

- (unsigned)completePathIntoString:(NSString **)outputName caseSensitive:(BOOL)flag matchesIntoArray:(NSArray **)outputArray filterTypes:(NSArray *)filterTypes {
    // TODO: Implement this method
    return 0;
}

- (const char *)fileSystemRepresentation {
    // TODO: Implement this method
    return nil;
}

- (BOOL)getFileSystemRepresentation:(char *)cname maxLength:(unsigned)max {
    // TODO: Implement this method
    return NO;
}

@end

@implementation NSArray

- (NSArray *)pathsMatchingExtensions:(NSArray *)filterTypes {
    // TODO: Implement this method
    return nil;
}

@end
