/*	NSNotification.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSNotification.h>

@implementation NSNotification

- (NSString *)name {
    // TODO: Implement this method
    return nil;
}

- (id)object {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)userInfo {
    // TODO: Implement this method
    return nil;
}

+ (id)notificationWithName:(NSString *)aName object:(id)anObject {
    // TODO: Implement this method
    return nil;
}

+ (id)notificationWithName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo {
    // TODO: Implement this method
    return nil;
}

@end

@implementation NSNotificationCenter

+ (id)defaultCenter {
    // TODO: Implement this method
    return nil;
}

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(id)anObject {
    // TODO: Implement this method
}

- (void)postNotification:(NSNotification *)notification {
    // TODO: Implement this method
}

- (void)postNotificationName:(NSString *)aName object:(id)anObject {
    // TODO: Implement this method
}

- (void)postNotificationName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo {
    // TODO: Implement this method
}

- (void)removeObserver:(id)observer {
    // TODO: Implement this method
}

- (void)removeObserver:(id)observer name:(NSString *)aName object:(id)anObject {
    // TODO: Implement this method
}

@end
