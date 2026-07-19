/*	NSURLHandle.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSURLHandle.h>

@implementation NSURLHandle

+ (void)registerURLHandleClass:(Class)anURLHandleSubclass; // Call this to register a new subclass of NSURLHandle {
    // TODO: Implement this method
}

+ (Class)URLHandleClassForURL:(NSURL *)anURL {
    // TODO: Implement this method
    return nil;
}

- (NSURLHandleStatus)status {
    // TODO: Implement this method
    return (NSURLHandleStatus)0;
}

- (NSString *)failureReason; // if status is NSURLHandleLoadFailed, then failureReason returns the reason for failure; otherwise, it returns nil {
    // TODO: Implement this method
    return nil;
}

- (void)addClient:(id <NSURLHandleClient>)client {
    // TODO: Implement this method
}

- (void)removeClient:(id <NSURLHandleClient>)client {
    // TODO: Implement this method
}

- (void)loadInBackground {
    // TODO: Implement this method
}

- (void)cancelLoadInBackground {
    // TODO: Implement this method
}

- (NSData *)resourceData; // Blocks until all data is available {
    // TODO: Implement this method
    return nil;
}

- (NSData *)availableResourceData;  // Immediately returns whatever data is available {
    // TODO: Implement this method
    return nil;
}

- (void)flushCachedData {
    // TODO: Implement this method
}

- (void)backgroundLoadDidFailWithReason:(NSString *)reason; // Sends the failure message to clients {
    // TODO: Implement this method
}

- (void)didLoadBytes:(NSData *)newBytes loadComplete:(BOOL)yorn {
    // TODO: Implement this method
}

+ (BOOL)canInitWithURL:(NSURL *)anURL {
    // TODO: Implement this method
    return NO;
}

+ (NSURLHandle *)cachedHandleForURL:(NSURL *)anURL {
    // TODO: Implement this method
    return nil;
}

- initWithURL:(NSURL *)anURL cached:(BOOL)willCache {
    // TODO: Implement this method
    return nil;
}

- (id)propertyForKey:(NSString *)propertyKey;  // Must be overridden by subclasses {
    // TODO: Implement this method
    return nil;
}

- (id)propertyForKeyIfAvailable:(NSString *)propertyKey {
    // TODO: Implement this method
    return nil;
}

- (BOOL)writeProperty:(id)propertyValue forKey:(NSString *)propertyKey {
    // TODO: Implement this method
    return NO;
}

- (BOOL)writeData:(NSData *)data; // Must be overridden by subclasses; returns success or failure {
    // TODO: Implement this method
    return NO;
}

- (NSData *)loadInForeground;   // Called from resourceData, above. {
    // TODO: Implement this method
    return nil;
}

- (void)beginLoadInBackground;  // Called from -loadInBackground, above. {
    // TODO: Implement this method
}

- (void)endLoadInBackground;    // Called from -cancelLoadInBackground, above. {
    // TODO: Implement this method
}

@end
