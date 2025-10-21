/*	NSUserDefaults.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSUserDefaults.h>

@implementation NSUserDefaults

+ (NSUserDefaults *)standardUserDefaults {
    // TODO: Implement this method
    return nil;
}

+ (void)resetStandardUserDefaults {
    // TODO: Implement this method
}

- (id)init {
    // TODO: Implement this method
    return nil;
}

- (id)initWithUser:(NSString *)username {
    // TODO: Implement this method
    return nil;
}

- (id)objectForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return nil;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    // TODO: Implement this method
}

- (void)removeObjectForKey:(NSString *)defaultName {
    // TODO: Implement this method
}

- (NSString *)stringForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)arrayForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)dictionaryForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return nil;
}

- (NSData *)dataForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)stringArrayForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return nil;
}

- (int)integerForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return 0;
}

- (float)floatForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return 0.0;
}

- (BOOL)boolForKey:(NSString *)defaultName {
    // TODO: Implement this method
    return NO;
}

- (void)setInteger:(int)value forKey:(NSString *)defaultName {
    // TODO: Implement this method
}

- (void)setFloat:(float)value forKey:(NSString *)defaultName {
    // TODO: Implement this method
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    // TODO: Implement this method
}

- (NSArray *)searchList {
    // TODO: Implement this method
    return nil;
}

- (void)setSearchList:(NSArray *)array {
    // TODO: Implement this method
}

- (void)registerDefaults:(NSDictionary *)registrationDictionary {
    // TODO: Implement this method
}

- (NSDictionary *)dictionaryRepresentation {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)volatileDomainNames {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)volatileDomainForName:(NSString *)domainName {
    // TODO: Implement this method
    return nil;
}

- (void)setVolatileDomain:(NSDictionary *)domain forName:(NSString *)domainName {
    // TODO: Implement this method
}

- (void)removeVolatileDomainForName:(NSString *)domainName {
    // TODO: Implement this method
}

- (NSArray *)persistentDomainNames {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)persistentDomainForName:(NSString *)domainName {
    // TODO: Implement this method
    return nil;
}

- (void)setPersistentDomain:(NSDictionary *)domain forName:(NSString *)domainName {
    // TODO: Implement this method
}

- (void)removePersistentDomainForName:(NSString *)domainName {
    // TODO: Implement this method
}

- (BOOL)synchronize {
    // TODO: Implement this method
    return NO;
}

@end
