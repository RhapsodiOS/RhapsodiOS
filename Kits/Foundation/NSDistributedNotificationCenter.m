/*	NSDistributedNotificationCenter.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDistributedNotificationCenter.h>

@implementation NSDistributedNotificationCenter

+ (NSDistributedNotificationCenter *)notificationCenterForType:(NSString *)notificationCenterType {
    // TODO: Implement this method
    return nil;
}

+ (id)defaultCenter {
    // TODO: Implement this method
    return nil;
}

- (void)addObserver:(id)observer selector:(SEL)selector name:(NSString *)name object:(NSString *)object suspensionBehavior:(NSNotificationSuspensionBehavior)suspensionBehavior {
    // TODO: Implement this method
}

- (void)postNotificationName:(NSString *)name object:(NSString *)object userInfo:(NSDictionary *)userInfo deliverImmediately:(BOOL)deliverImmediately {
    // TODO: Implement this method
}

- (void)setSuspended:(BOOL)suspended {
    // TODO: Implement this method
}

- (BOOL)suspended {
    // TODO: Implement this method
    return NO;
}

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(NSString *)anObject {
    // TODO: Implement this method
}

- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject {
    // TODO: Implement this method
}

- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject userInfo:(NSDictionary *)aUserInfo {
    // TODO: Implement this method
}

- (void)removeObserver:(id)observer name:(NSString *)aName object:(NSString *)anObject {
    // TODO: Implement this method
}

@end
