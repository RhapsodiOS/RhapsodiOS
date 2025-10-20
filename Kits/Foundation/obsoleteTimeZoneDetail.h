/*	obsoleteTimeZoneDetail.h
	Copyright 1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDate.h>
#import <Foundation/NSTimeZone.h>

@class NSString, NSArray, NSDate;

#warning This header and the NSTimeZoneDetail class will be
#warning going away in Rhapsody.  Do not use.

@interface NSTimeZoneDetail : NSTimeZone

- (int)timeZoneSecondsFromGMT;
- (NSString *)timeZoneAbbreviation;
- (BOOL)isDaylightSavingTimeZone;

@end

@interface NSTimeZone (NSObsoleteNSTimeZone)

+ (NSArray *)timeZoneArray;
- (NSArray *)timeZoneDetailArray;
- (NSTimeZoneDetail *)timeZoneDetailForDate:(NSDate *)date;
- (BOOL)isDaylightSavingTimeZone;
- (int)timeZoneSecondsFromGMT;
- (NSString *)timeZoneAbbreviation;
- (NSString *)timeZoneName;
- (NSTimeZone *)timeZoneForDate:(NSDate *)date;

@end

