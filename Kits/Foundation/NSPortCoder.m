/*	NSPortCoder.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPortCoder.h>

@implementation NSPortCoder

- (BOOL)isBycopy {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isByref {
    // TODO: Implement this method
    return NO;
}

- (NSConnection *)connection {
    // TODO: Implement this method
    return nil;
}

- (void)encodePortObject:(NSPort *)aport {
    // TODO: Implement this method
}

- (NSPort *)decodePortObject {
    // TODO: Implement this method
    return nil;
}

+ portCoderWithReceivePort:(NSPort *)rcvPort sendPort:(NSPort *)sndPort components:(NSArray *)comps {
    // TODO: Implement this method
    return nil;
}

- (void)dispatch {
    // TODO: Implement this method
}

@end

@implementation NSObject

- (Class)classForPortCoder {
    // TODO: Implement this method
    return nil;
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    // TODO: Implement this method
    return nil;
}

@end
