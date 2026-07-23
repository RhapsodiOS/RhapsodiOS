/*	NSCompatibility.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCompatibility.h>
#import <Foundation/obsoleteTimeZoneDetail.h>

@implementation NSTimeZoneDetail

- (int)timeZoneSecondsFromGMT {
    // TODO: Implement this method
    return 0;
}

- (NSString *)timeZoneAbbreviation {
    // TODO: Implement this method
    return nil;
}

- (BOOL)isDaylightSavingTimeZone {
    // TODO: Implement this method
    return NO;
}

@end

@implementation NSTimeZone

+ (NSArray *)timeZoneArray {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)timeZoneDetailArray {
    // TODO: Implement this method
    return nil;
}

- (NSTimeZoneDetail *)timeZoneDetailForDate:(NSDate *)date {
    // TODO: Implement this method
    return nil;
}

- (BOOL)isDaylightSavingTimeZone {
    // TODO: Implement this method
    return NO;
}

- (int)timeZoneSecondsFromGMT {
    // TODO: Implement this method
    return 0;
}

- (NSString *)timeZoneAbbreviation {
    // TODO: Implement this method
    return nil;
}

- (NSString *)timeZoneName {
    // TODO: Implement this method
    return nil;
}

- (NSTimeZone *)timeZoneForDate:(NSDate *)date {
    // TODO: Implement this method
    return nil;
}

@end
