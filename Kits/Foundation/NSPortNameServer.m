/*	NSPortNameServer.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPortNameServer.h>

@implementation NSPortNameServer

+ (id)defaultPortNameServer {
    // TODO: Implement this method
    return nil;
}

- (NSPort *)portForName:(NSString *)name {
    // TODO: Implement this method
    return nil;
}

- (NSPort *)portForName:(NSString *)name host:(NSString *) host {
    // TODO: Implement this method
    return nil;
}

- (BOOL)registerPort:(NSPort *)port name:(NSString *)netName {
    // TODO: Implement this method
    return NO;
}

- (void)removePortForName:(NSString *)key {
    // TODO: Implement this method
}

- (NSPort *)portForName:(NSString *)name onHost:(NSString *) host {
    // TODO: Implement this method
    return nil;
}

- (BOOL)registerPort:(NSPort *)port forName:(NSString *)netName {
    // TODO: Implement this method
    return NO;
}

@end
