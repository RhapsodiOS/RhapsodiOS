/*	NSException.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSException.h>

@implementation NSException

+ (NSException *)exceptionWithName:(NSString *)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo {
    // TODO: Implement this method
    return nil;
}

- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo {
    // TODO: Implement this method
    return nil;
}

- (NSString *)name {
    // TODO: Implement this method
    return nil;
}

- (NSString *)reason {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)userInfo {
    // TODO: Implement this method
    return nil;
}

- (void)raise {
    // TODO: Implement this method
}

+ (void)raise:(NSString *)name format:(NSString *)format, ... {
    // TODO: Implement this method
}

+ (void)raise:(NSString *)name format:(NSString *)format arguments:(va_list)argList {
    // TODO: Implement this method
}

@end

@implementation NSAssertionHandler

+ (NSAssertionHandler *)currentHandler {
    // TODO: Implement this method
    return nil;
}

- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,... {
    // TODO: Implement this method
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format,... {
    // TODO: Implement this method
}

@end
