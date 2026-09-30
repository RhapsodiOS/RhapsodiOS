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

/*  NSCoder (NSTypedstreamCompatibility).  Gate 1 (stage 2c) walked
    the reference's 80 __OBJC,__module_info records: the NXObject pair
    is declared in THIS module as a category on NSCoder -- NSCoder.m's
    own class record is 22 flat methods with no category, and
    NSCoder.m's copy of the pair was moved here on the ABI evidence.
    The bodies are the same encodeObject:/decodeObject delegations.  */
#import <Foundation/NSCoder.h>

@implementation NSCoder (NSTypedstreamCompatibility)

- (void)encodeNXObject:(id)object
{
    [self encodeObject:object];
}

- (id)decodeNXObject
{
    return [self decodeObject];
}

@end
