/*	NSNotification.h
	Posting and observing notifications
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@class NSString, NSDictionary;

/****************	Notifications	****************/

@interface NSNotification : NSObject <NSCopying, NSCoding>

- (NSString *)name;
- (id)object;
- (NSDictionary *)userInfo;

@end

@interface NSNotification (NSNotificationCreation)

+ (id)notificationWithName:(NSString *)aName object:(id)anObject;
+ (id)notificationWithName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo;

@end

/****************	Notification Center	****************/

@interface NSNotificationCenter : NSObject {
    @private
    id _lock;
    void *_registry;
    unsigned int _registry_size;
    unsigned int _registry_count;
    int *_niltable;
    unsigned int _niltable_size;
    unsigned int _niltable_count;
    int *_hashtable;
    unsigned int _hashtable_size;
    unsigned int _hashtable_count;
    unsigned int _deleted_count;
    void *_reserved1;
    void *_reserved;
}

+ (id)defaultCenter;
    
- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(id)anObject;

- (void)postNotification:(NSNotification *)notification;
- (void)postNotificationName:(NSString *)aName object:(id)anObject;
- (void)postNotificationName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo;

- (void)removeObserver:(id)observer;
- (void)removeObserver:(id)observer name:(NSString *)aName object:(id)anObject;

@end

