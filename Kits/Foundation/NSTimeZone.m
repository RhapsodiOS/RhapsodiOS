/*	NSTimeZone.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSTimeZone.h>

@implementation NSTimeZone

- (NSString *)name {
    // TODO: Implement this method
    return nil;
}

- (NSData *)data {
    // TODO: Implement this method
    return nil;
}

- (int)secondsFromGMTForDate:(NSDate *)aDate {
    // TODO: Implement this method
    return 0;
}

- (NSString *)abbreviationForDate:(NSDate *)aDate {
    // TODO: Implement this method
    return nil;
}

- (BOOL)isDaylightSavingTimeForDate:(NSDate *)aDate {
    // TODO: Implement this method
    return NO;
}

+ (NSTimeZone *)systemTimeZone {
    // TODO: Implement this method
    return nil;
}

+ (void)resetSystemTimeZone {
    // TODO: Implement this method
}

+ (NSTimeZone *)defaultTimeZone {
    // TODO: Implement this method
    return nil;
}

+ (void)setDefaultTimeZone:(NSTimeZone *)aTimeZone {
    // TODO: Implement this method
}

+ (NSTimeZone *)localTimeZone {
    // TODO: Implement this method
    return nil;
}

+ (NSArray *)knownTimeZoneNames {
    // TODO: Implement this method
    return nil;
}

+ (NSDictionary *)abbreviationDictionary {
    // TODO: Implement this method
    return nil;
}

- (int)secondsFromGMT {
    // TODO: Implement this method
    return 0;
}

- (NSString *)abbreviation {
    // TODO: Implement this method
    return nil;
}

- (BOOL)isDaylightSavingTime {
    // TODO: Implement this method
    return NO;
}

- (NSString *)description {
    // TODO: Implement this method
    return nil;
}

- (BOOL)isEqualToTimeZone:(NSTimeZone *)aTimeZone {
    // TODO: Implement this method
    return NO;
}

+ (id)timeZoneWithName:(NSString *)tzName {
    // TODO: Implement this method
    return nil;
}

+ (id)timeZoneWithName:(NSString *)tzName data:(NSData *)aData {
    // TODO: Implement this method
    return nil;
}

- (id)initWithName:(NSString *)tzName {
    // TODO: Implement this method
    return nil;
}

- (id)initWithName:(NSString *)tzName data:(NSData *)aData {
    // TODO: Implement this method
    return nil;
}

+ (id)timeZoneForSecondsFromGMT:(int)seconds {
    // TODO: Implement this method
    return nil;
}

+ (id)timeZoneWithAbbreviation:(NSString *)abbreviation {
    // TODO: Implement this method
    return nil;
}

@end
