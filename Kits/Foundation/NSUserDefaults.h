/*	NSUserDefaults.h
	Storage and retrieval of user defaults
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@class NSArray, NSData, NSDictionary, NSMutableArray, NSString;

FOUNDATION_EXPORT NSString * const NSGlobalDomain;
FOUNDATION_EXPORT NSString * const NSArgumentDomain;
FOUNDATION_EXPORT NSString * const NSRegistrationDomain;

@interface NSUserDefaults : NSObject {
@private
    id			_dlplf;
    NSArray		*_search;
    NSDictionary	*_temp;
    NSDictionary 	*_dictRep;
    void		*_reserved;
}

+ (NSUserDefaults *)standardUserDefaults;
+ (void)resetStandardUserDefaults;

- (id)init;
- (id)initWithUser:(NSString *)username;

- (id)objectForKey:(NSString *)defaultName;
- (void)setObject:(id)value forKey:(NSString *)defaultName;
- (void)removeObjectForKey:(NSString *)defaultName;

- (NSString *)stringForKey:(NSString *)defaultName;
- (NSArray *)arrayForKey:(NSString *)defaultName;
- (NSDictionary *)dictionaryForKey:(NSString *)defaultName;
- (NSData *)dataForKey:(NSString *)defaultName;
- (NSArray *)stringArrayForKey:(NSString *)defaultName;
- (int)integerForKey:(NSString *)defaultName; 
- (float)floatForKey:(NSString *)defaultName; 
- (BOOL)boolForKey:(NSString *)defaultName;  

- (void)setInteger:(int)value forKey:(NSString *)defaultName;
- (void)setFloat:(float)value forKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;

- (NSArray *)searchList;
- (void)setSearchList:(NSArray *)array;

- (void)registerDefaults:(NSDictionary *)registrationDictionary;

- (NSDictionary *)dictionaryRepresentation;

- (NSArray *)volatileDomainNames;
- (NSDictionary *)volatileDomainForName:(NSString *)domainName;
- (void)setVolatileDomain:(NSDictionary *)domain forName:(NSString *)domainName;
- (void)removeVolatileDomainForName:(NSString *)domainName;

- (NSArray *)persistentDomainNames;
- (NSDictionary *)persistentDomainForName:(NSString *)domainName;
- (void)setPersistentDomain:(NSDictionary *)domain forName:(NSString *)domainName;
- (void)removePersistentDomainForName:(NSString *)domainName;

- (BOOL)synchronize;

@end

FOUNDATION_EXPORT NSString * const NSUserDefaultsDidChangeNotification;

FOUNDATION_EXPORT NSString * const NSWeekDayNameArray;
FOUNDATION_EXPORT NSString * const NSShortWeekDayNameArray;
FOUNDATION_EXPORT NSString * const NSMonthNameArray;
FOUNDATION_EXPORT NSString * const NSShortMonthNameArray;
FOUNDATION_EXPORT NSString * const NSTimeFormatString;
FOUNDATION_EXPORT NSString * const NSDateFormatString;
FOUNDATION_EXPORT NSString * const NSTimeDateFormatString;
FOUNDATION_EXPORT NSString * const NSShortTimeDateFormatString;
FOUNDATION_EXPORT NSString * const NSCurrencySymbol;
FOUNDATION_EXPORT NSString * const NSDecimalSeparator;
FOUNDATION_EXPORT NSString * const NSThousandsSeparator;
FOUNDATION_EXPORT NSString * const NSDecimalDigits;
FOUNDATION_EXPORT NSString * const NSAMPMDesignation;
FOUNDATION_EXPORT NSString * const NSHourNameDesignations;
FOUNDATION_EXPORT NSString * const NSYearMonthWeekDesignations;
FOUNDATION_EXPORT NSString * const NSEarlierTimeDesignations;
FOUNDATION_EXPORT NSString * const NSLaterTimeDesignations;
FOUNDATION_EXPORT NSString * const NSThisDayDesignations;
FOUNDATION_EXPORT NSString * const NSNextDayDesignations;
FOUNDATION_EXPORT NSString * const NSNextNextDayDesignations;
FOUNDATION_EXPORT NSString * const NSPriorDayDesignations;
FOUNDATION_EXPORT NSString * const NSDateTimeOrdering;
FOUNDATION_EXPORT NSString * const NSInternationalCurrencyString;
FOUNDATION_EXPORT NSString * const NSShortDateFormatString;
FOUNDATION_EXPORT NSString * const NSPositiveCurrencyFormatString;
FOUNDATION_EXPORT NSString * const NSNegativeCurrencyFormatString;

