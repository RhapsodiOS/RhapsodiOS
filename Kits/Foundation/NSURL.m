/*	NSURL.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSURL.h>

@implementation NSURL

- initWithScheme:(NSString *)scheme host:(NSString *)host path:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- initFileURLWithPath:(NSString *)path;  // Equivalent to [self initWithScheme:NSFileScheme host:nil path:path] {
    // TODO: Implement this method
    return nil;
}

+ (id)fileURLWithPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- initWithString:(NSString *)URLString {
    // TODO: Implement this method
    return nil;
}

- initWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL; // It is an error for URLString to be nil {
    // TODO: Implement this method
    return nil;
}

+ (id)URLWithString:(NSString *)URLString {
    // TODO: Implement this method
    return nil;
}

+ (id)URLWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    // TODO: Implement this method
    return nil;
}

- (NSString *)absoluteString {
    // TODO: Implement this method
    return nil;
}

- (NSString *)relativeString; // The relative portion of a URL.  If baseURL is nil, or if the receiver is itself absolute, this is the same as absoluteString {
    // TODO: Implement this method
    return nil;
}

- (NSURL *)baseURL; // may be nil. {
    // TODO: Implement this method
    return nil;
}

- (NSURL *)absoluteURL; // if the receiver is itself absolute, this will return self. {
    // TODO: Implement this method
    return nil;
}

- (NSString *)scheme {
    // TODO: Implement this method
    return nil;
}

- (NSString *)resourceSpecifier {
    // TODO: Implement this method
    return nil;
}

- (NSString *)host {
    // TODO: Implement this method
    return nil;
}

- (NSNumber *)port {
    // TODO: Implement this method
    return nil;
}

- (NSString *)user {
    // TODO: Implement this method
    return nil;
}

- (NSString *)password {
    // TODO: Implement this method
    return nil;
}

- (NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (NSString *)fragment {
    // TODO: Implement this method
    return nil;
}

- (NSString *)parameterString {
    // TODO: Implement this method
    return nil;
}

- (NSString *)query {
    // TODO: Implement this method
    return nil;
}

- (NSString *)relativePath; // The same as path if baseURL is nil {
    // TODO: Implement this method
    return nil;
}

- (BOOL)isFileURL; // Whether the scheme is file:; if [myURL isFileURL] is YES, then [myURL path] is suitable for input into NSFileManager or NSPathUtilities. {
    // TODO: Implement this method
    return NO;
}

- (NSURL *)standardizedURL {
    // TODO: Implement this method
    return nil;
}

- (NSData *)resourceDataUsingCache:(BOOL)shouldUseCache; // Blocks to load the data if necessary.  If shouldUseCache is YES, then if an equivalent URL has already been loaded and cached, its resource data will be returned immediately.  If shouldUseCache is NO, a new load will be started {
    // TODO: Implement this method
    return nil;
}

- (void)loadResourceDataNotifyingClient:(id)client usingCache:(BOOL)shouldUseCache; // Starts an asynchronous load of the data, registering delegate to receive notification.  Only one such background load can proceed at a time. {
    // TODO: Implement this method
}

- (id)propertyForKey:(NSString *)propertyKey {
    // TODO: Implement this method
    return nil;
}

- (BOOL)setResourceData:(NSData *)data {
    // TODO: Implement this method
    return NO;
}

- (BOOL)setProperty:(id)property forKey:(NSString *)propertyKey {
    // TODO: Implement this method
    return NO;
}

- (NSURLHandle *)URLHandleUsingCache:(BOOL)shouldUseCache; // Sophisticated clients will want to ask for this, then message the handle directly.  If shouldUseCache is NO, a newly instantiated handle is returned, even if an equivalent URL has been loaded {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSObject

- (void)URL:(NSURL *)sender resourceDataDidBecomeAvailable:(NSData *)newBytes {
    // TODO: Implement this method
}

- (void)URLResourceDidFinishLoading:(NSURL *)sender {
    // TODO: Implement this method
}

- (void)URLResourceDidCancelLoading:(NSURL *)sender {
    // TODO: Implement this method
}

- (void)URL:(NSURL *)sender resourceDidFailLoadingWithReason:(NSString *)reason {
    // TODO: Implement this method
}

@end
