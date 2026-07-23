/*	NSHost.h
	Abstraction of computer hosts
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@class NSString, NSArray, NSMutableArray;

@interface NSHost : NSObject {
@private
    NSMutableArray 	*names;
    NSMutableArray 	*addresses;
    void		*reserved;
}

+ (NSHost *)currentHost;
+ (NSHost *)hostWithName:(NSString *)name;
+ (NSHost *)hostWithAddress:(NSString *)address;

+ (void)setHostCacheEnabled:(BOOL)flag;
+ (BOOL)isHostCacheEnabled;
+ (void)flushHostCache;

- (BOOL)isEqualToHost:(NSHost *)aHost;

- (NSString *)name;
- (NSArray *)names;

- (NSString *)address;
- (NSArray *)addresses;

@end

