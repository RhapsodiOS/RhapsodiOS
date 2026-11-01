/*	NSCalendarDate.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSLanguageContext.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSPortCoder.h>
#import <math.h>
#include <stdio.h>
#include <string.h>
#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>
#endif

extern NSLock *_NSGlobalRetainLock;
extern void _NSIncrementInternalRefCount(id object, unsigned *refCount, int mask, id lock);
extern BOOL _NSDecrementInternalRefCountWasZero(id object, unsigned *refCount, int mask, id lock);
extern unsigned _NSInternalRefCount(id object, unsigned refCount, int mask);
#import "NSProcessInfoPrivate.h"
extern id _NSMethodExceptionProem(id object, SEL selector);

#if defined(__ppc__) || defined(__POWERPC__)
extern volatile unsigned int __NSDateRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSCalendarDateLockRetainCount(void)
{
    if (!_NSIsMultiThreaded)
        return NO;
    for (;;) {
        unsigned oldValue;
        unsigned acquired;
        unsigned one = 1;

        __asm__ volatile(
            "1: lwarx %0,0,%2\n\t"
            "cmpwi %0,0\n\t"
            "bne- 2f\n\t"
            "stwcx. %3,0,%2\n\t"
            "bne- 1b\n\t"
            "isync\n\t"
            "li %1,1\n\t"
            "b 3f\n"
            "2: li %1,0\n"
            "3:"
            : "=&r" (oldValue), "=&r" (acquired)
            : "r" (&__NSDateRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSCalendarDateUnlockRetainCount(BOOL locked)
{
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSDateRetainLock = 0;
    }
}
#endif

static NSCalendarDate *NSCalendarDateDistantFuture;
static NSCalendarDate *NSCalendarDateDistantPast;

#if defined(__ppc__) || defined(__POWERPC__)
static int NSCalendarDateDoExcelLittleY = -1;

static void NSCalendarDateInitializeExcelLittleY(void) {
    if (NSCalendarDateDoExcelLittleY == -1) {
        NSString *key = @"NSUseExcelTwoDigitYearSemantics";
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        if ([defaults objectForKey:key] == nil)
            NSCalendarDateDoExcelLittleY = 1;
        else
            NSCalendarDateDoExcelLittleY = [defaults boolForKey:key];
    }
}
#endif

static const int NSCalendarDateMonthLengths[] = {
    0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

static BOOL leap_year(int year) {
    int remainder;

    if ((year & 3) != 0)
        return NO;
    remainder = year % 400;
    return remainder != 100 && remainder != 200 && remainder != 300;
}

static int last_day_of_gregorian_month(int month, int year) {
    if (month == 2 && leap_year(year))
        return 29;
    return NSCalendarDateMonthLengths[month];
}

static int absolute_from_gregorian(int date) {
    int year = date >> 16;
    int month = date & 0xff;
    int day = (date >> 8) & 0xff;
    int daysBeforeMonth = 0;
    int previousYear = year - 1;
    int adjustedYear = previousYear < 0 ? year + 2 : previousYear;
    int index;

    for (index = 1; index < month; index++)
        daysBeforeMonth += last_day_of_gregorian_month(index, year);

    return previousYear / 400 + (adjustedYear >> 2) + 365 * previousYear
        + daysBeforeMonth + day - previousYear / 100;
}

#if defined(__ppc__) || defined(__POWERPC__)
typedef struct {
    unsigned char month;
    unsigned char day;
    short year;
} NSGregorianDate;

static NSGregorianDate gregorian_from_absolute(int absoluteDay) {
#else
static int gregorian_from_absolute(int absoluteDay) {
#endif
    int year = absoluteDay / 366;
    int month;
    int day;

    while (absoluteDay >= absolute_from_gregorian(((year + 1) << 16) | 0x0101))
        year++;

    for (month = 1; ; month++) {
        int lastDay = last_day_of_gregorian_month(month, year);
        int endOfMonth = (year << 16) | (lastDay << 8) | month;

        if (absoluteDay <= absolute_from_gregorian(endOfMonth))
            break;
    }

    day = absoluteDay + 1
        - absolute_from_gregorian((year << 16) | 0x0101);
#if defined(__ppc__) || defined(__POWERPC__)
    {
        NSGregorianDate date;
        date.month = month;
        date.day = day;
        date.year = year;
        return date;
    }
#else
    return (year << 16) | (day << 8) | month;
#endif
}

static int absolute_from_year_day(int year, int day) {
    int previousYear = year - 1;
    int adjustedYear = previousYear < 0 ? year + 2 : previousYear;

    return previousYear / 400 + (adjustedYear >> 2) + 365 * previousYear
        + day - previousYear / 100;
}

static int NSCalendarDateAbsoluteDay(NSTimeInterval timeInterval,
                                    NSTimeZone *timeZone,
                                    NSCalendarDate *date) {
#if defined(__ppc__) || defined(__POWERPC__)
    double days = (timeInterval + [timeZone secondsFromGMTForDate:date])
        / 86400.0 + 730486.0;

    if (days < 1.0)
        return 1;
    if (days > 2147483647.0)
        return 1460972;
    return (int)days;
#else
    long double days = ((long double)timeInterval
        + [timeZone secondsFromGMTForDate:date]) / 86400.0L + 730486.0L;

    if (days < 1.0L)
        return 1;
    if (days > 2147483647.0L)
        return 1460972;
    return (int)days;
#endif
}

static int NSCalendarDateTimeComponent(NSTimeInterval timeInterval,
                                       NSTimeZone *timeZone,
                                       NSCalendarDate *date,
                                       int divisor,
                                       int unit) {
#if defined(__ppc__) || defined(__POWERPC__)
    double seconds = timeInterval + [timeZone secondsFromGMTForDate:date];
    double value = seconds / divisor;
#else
    long double seconds = (long double)timeInterval
        + [timeZone secondsFromGMTForDate:date];
    double value = (double)(seconds / divisor);
#endif
    int component = (int)(value - floor(value / unit) * unit);

    return component < 0 ? component + unit : component;
}

static int NSCalendarDateReadNumber(const char **cursor) {
    int value = 0;

    while (**cursor != '\0') {
        unsigned char digit = (unsigned char)(**cursor - '0');

        if (digit > 9)
            break;
        value = value * 10 + digit;
        (*cursor)++;
    }
    return value;
}

static NSMapTable *NSCalendarDateNaturalLanguageTokenMap;
static NSDictionary *NSCalendarDateNaturalLanguageCachedDictionary;
NSLock *_NSNaturalLanguageCacheLock;
static unichar NSCalendarDateNaturalLanguageNumberOrder[4];

static void NSCalendarDateNaturalLanguageAddTokens(NSArray *tokens,
                                                    unsigned value,
                                                    BOOL addIndex) {
    unsigned count = [tokens count];

    while (count != 0) {
        unsigned index = --count;
        NSString *token = [[tokens objectAtIndex:index] lowercaseString];
        NSMapInsert(NSCalendarDateNaturalLanguageTokenMap, token,
            (const void *)(unsigned long)(value + (addIndex ? index : 0)));
    }
}

static void NSCalendarDateNaturalLanguageAddUnitDesignations(
    NSArray *designations) {
    unsigned count = [designations count];

    while (count != 0) {
        NSArray *designation = [designations objectAtIndex:--count];
        unsigned tokenCount = [designation count];
        unsigned value = (unsigned)[[designation objectAtIndex:0] intValue] + 94;

        while (tokenCount != 0) {
            NSString *token = [[designation objectAtIndex:--tokenCount]
                lowercaseString];
            NSMapInsert(NSCalendarDateNaturalLanguageTokenMap, token,
                (const void *)(unsigned long)value);
        }
    }
}

static unsigned NSCalendarDateNaturalLanguageAction(NSString *token) {
    void *value = (void *)65;
    NSString *key = [token lowercaseString];

    NSMapMember(NSCalendarDateNaturalLanguageTokenMap, key, NULL, &value);
    return (unsigned long)value & 0xffff;
}

static void NSCalendarDateNaturalLanguageBuildTokenMap(NSDictionary *dictionary) {
    BOOL mutableDictionary;

    if (_NSNaturalLanguageCacheLock != nil)
        [_NSNaturalLanguageCacheLock lock];
    if (NSCalendarDateNaturalLanguageTokenMap == NULL)
        NSCalendarDateNaturalLanguageTokenMap = NSCreateMapTableWithZone(
            NSObjectMapKeyCallBacks, NSIntMapValueCallBacks, 0, NULL);
    mutableDictionary = [dictionary respondsToSelector:
        @selector(setObject:forKey:)];
    if (mutableDictionary ||
        NSCalendarDateNaturalLanguageCachedDictionary != dictionary) {
        NSResetMapTable(NSCalendarDateNaturalLanguageTokenMap);
        [NSCalendarDateNaturalLanguageCachedDictionary release];
        NSCalendarDateNaturalLanguageCachedDictionary = mutableDictionary
            ? nil : [dictionary retain];
    }
    if (_NSNaturalLanguageCacheLock != nil)
        [_NSNaturalLanguageCacheLock unlock];

    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSPriorDayDesignations"], 79, NO);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSNextDayDesignations"], 80, NO);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSNextNextDayDesignations"], 81, NO);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSThisDayDesignations"], 78, NO);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSEarlierTimeDesignations"], 90, NO);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSLaterTimeDesignations"], 89, NO);
    NSCalendarDateNaturalLanguageAddUnitDesignations(
        [dictionary objectForKey:@"NSYearMonthWeekDesignations"]);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSMonthNameArray"], 66, YES);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSShortMonthNameArray"], 66, YES);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSWeekDayNameArray"], 82, YES);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSShortWeekDayNameArray"], 82, YES);
    NSCalendarDateNaturalLanguageAddTokens(
        [dictionary objectForKey:@"NSAMPMDesignation"], 118, YES);

    {
        NSString *numberOrder =
            [[dictionary objectForKey:@"NSDateTimeOrdering"] uppercaseString];

        if (numberOrder != nil) {
            memset(NSCalendarDateNaturalLanguageNumberOrder, 0,
                sizeof(NSCalendarDateNaturalLanguageNumberOrder));
            [numberOrder getCharacters:NSCalendarDateNaturalLanguageNumberOrder
                range:NSMakeRange(0, 4)];
        }
    }
}

static void appendNumber(NSMutableString *string, int value,
                         const char *format, const char *defaultFormat) {
    char buffer[1040];
    unsigned length = [string length];
    const char *selectedFormat = format[0] != '\0' ? format : defaultFormat;

    snprintf(buffer, sizeof(buffer), selectedFormat, value);
    [string replaceCharactersInRange:NSMakeRange(length, 0)
                          withCString:buffer length:(unsigned)strlen(buffer)];
}

static void appendName(NSMutableString *string, int index, NSArray *names,
                       NSArray *defaultNames) {
    NSArray *selectedNames = names != nil ? names : defaultNames;
    id name;
    unsigned length;

#if defined(__ppc__) || defined(__POWERPC__)
    length = [string length];
    name = [selectedNames objectAtIndex:(unsigned)index];
#else
    name = [selectedNames objectAtIndex:(unsigned)index];
    length = [string length];
#endif
    [string replaceCharactersInRange:NSMakeRange(length, 0) withString:name];
}

static void append03(NSMutableString *string, int value) {
    unichar digits[3];
    unsigned length;

    digits[0] = (unichar)(value % 1000 / 100 + '0');
    digits[1] = (unichar)(value % 100 / 10 + '0');
    digits[2] = (unichar)(value % 10 + '0');
    length = [string length];
    [string replaceCharactersInRange:NSMakeRange(length, 0)
                      withCharacters:digits length:3];
}

static int NSCalendarDateRoundedMilliseconds(double seconds) {
    double milliseconds = (seconds - floor(seconds)) * 1000.0;
#if defined(__ppc__) || defined(__POWERPC__)
    return (int)rint(milliseconds);
#else
    int rounded = (int)milliseconds;
    double remainder = milliseconds - rounded;

    if (remainder > 0.5 || (remainder == 0.5 && (rounded & 1)))
        rounded++;
    return rounded;
#endif
}

static NSArray *NSCalendarDateNamesForKey(id locale,
                                          NSString *key,
                                          NSArray *fallbackNames) {
    id names = [locale objectForKey:key];

    return names != nil ? names : fallbackNames;
}

static NSArray *NSCalendarDateFormatterFallbackNames(id systemLanguageContext,
                                                      NSString *key) {
    return NSCalendarDateNamesForKey(systemLanguageContext, key, nil);
}

#if defined(__ppc__) || defined(__POWERPC__)
static void NSCalendarDateAppendLocalizedName(NSMutableString *result,
                                             int index, id locale,
                                             id systemLanguageContext,
                                             NSString *key) {
    NSArray *names = NSCalendarDateNamesForKey(locale, key, nil);
    NSArray *fallbackNames =
        NSCalendarDateFormatterFallbackNames(systemLanguageContext, key);

    appendName(result, index, names, fallbackNames);
}
#endif

static id NSCalendarDateParseObjectForKey(id locale, id systemLanguageContext,
                                          NSString *key) {
    id value = [locale objectForKey:key];

    return value != nil ? value : [systemLanguageContext objectForKey:key];
}

static id NSCalendarDateSystemLanguageContext(void) {
    return [NSLanguageContext systemLanguageContext];
}

@interface NSScanner (NSRemainingString)
- (NSString *)_remainingString;
- (BOOL)_scanDecimal:(unsigned)maximumDigits into:(int *)value;
@end

@implementation NSScanner (NSRemainingString)

- (NSString *)_remainingString {
    NSString *string = [self string];
    unsigned location = [self scanLocation];
    unsigned length = [string length];

    return [string substringWithRange:NSMakeRange(location,
        length - location)];
}

- (BOOL)_scanDecimal:(unsigned)maximumDigits into:(int *)value {
    unsigned location = [self scanLocation];
    NSString *string = [self string];
    unsigned length = [string length];
    unsigned count;
    int number = 0;

    for (count = 0; count < maximumDigits && location + count < length;
         count++) {
        unichar character = [string characterAtIndex:location + count];

        if (character < '0' || character > '9')
            break;
        number = number * 10 + character - '0';
    }
    if (count == 0)
        return NO;

    [self setScanLocation:location + count];
    *value = number;
    return YES;
}

@end

typedef struct {
    int year;
    int month;
    int day;
    int hour;
    int minute;
    int second;
    int dayOfYear;
    int milliseconds;
    int timeZoneOffset;
    NSString *timeZoneName;
} NSCalendarDateParseValues;

static void NSCalendarDateSkipWhitespace(NSScanner *scanner) {
    NSString *string = [scanner string];
    unsigned location = [scanner scanLocation];
    unsigned length = [string length];
    NSCharacterSet *skipSet = [scanner charactersToBeSkipped];

    while (location < length && skipSet != nil
        && [skipSet characterIsMember:[string characterAtIndex:location]])
        location++;
    [scanner setScanLocation:location];
}

static BOOL NSCalendarDateScanName(NSScanner *scanner, NSArray *names,
                                   int *nameIndex) {
    unsigned index;

    for (index = 0; index < [names count]; index++) {
        if ([scanner scanString:[names objectAtIndex:index] intoString:NULL]) {
            *nameIndex = (int)index;
            return YES;
        }
    }
    return NO;
}

static BOOL NSCalendarDateParseFormat(NSScanner *descriptionScanner,
                                     NSScanner *formatScanner,
                                     id locale,
                                     id systemLanguageContext,
                                     NSCalendarDateParseValues *values) {
    while (![formatScanner isAtEnd]) {
        unsigned formatLocation;
        unsigned descriptionLocation;
        unsigned directive;
        int parsedValue;

        if ([descriptionScanner isAtEnd])
            return NO;
        NSCalendarDateSkipWhitespace(descriptionScanner);
        if ([descriptionScanner isAtEnd])
            return NO;

        if ([formatScanner scanString:@"%" intoString:NULL]) {
            formatLocation = [formatScanner scanLocation];
            if (formatLocation >= [[formatScanner string] length])
                return NO;
            directive = [[formatScanner string] characterAtIndex:formatLocation];
            [formatScanner setScanLocation:formatLocation + 1];

            switch (directive) {
            case '%':
                if (![descriptionScanner scanString:@"%" intoString:NULL])
                    return NO;
                break;
            case 'A':
            case 'a':
                if (!NSCalendarDateScanName(descriptionScanner,
                    NSCalendarDateParseObjectForKey(locale,
                        systemLanguageContext,
                        directive == 'A' ? @"NSWeekDayNameArray"
                                         : @"NSShortWeekDayNameArray"),
                    &parsedValue))
                    return NO;
                break;
            case 'B':
            case 'b':
                if (!NSCalendarDateScanName(descriptionScanner,
                    NSCalendarDateParseObjectForKey(locale,
                        systemLanguageContext,
                        directive == 'B' ? @"NSMonthNameArray"
                                         : @"NSShortMonthNameArray"),
                    &values->month))
                    return NO;
                values->month++;
                break;
            case 'c': {
                NSString *localizedFormat = NSCalendarDateParseObjectForKey(
                    locale, systemLanguageContext, @"NSTimeDateFormatString");
                if (localizedFormat == nil)
                    localizedFormat = @"%a %b %d %H:%M:%S %Z %Y";
                if (!NSCalendarDateParseFormat(descriptionScanner,
                        [NSScanner scannerWithString:localizedFormat], locale,
                        systemLanguageContext, values))
                    return NO;
                break;
            }
            case 'd':
                if (![descriptionScanner _scanDecimal:2 into:&values->day])
                    return NO;
                break;
            case 'e':
                if (![descriptionScanner scanInt:&values->day])
                    return NO;
                break;
            case 'F':
                if (![descriptionScanner _scanDecimal:3
                                                into:&values->milliseconds])
                    return NO;
                break;
            case 'H':
            case 'I':
                if (![descriptionScanner _scanDecimal:2 into:&values->hour])
                    return NO;
                break;
            case 'j':
                if (![descriptionScanner scanInt:&values->dayOfYear])
                    return NO;
                break;
            case 'm':
                if (![descriptionScanner _scanDecimal:2 into:&values->month])
                    return NO;
                break;
            case 'M':
                if (![descriptionScanner _scanDecimal:2 into:&values->minute])
                    return NO;
                break;
            case 'p': {
                NSArray *names = NSCalendarDateParseObjectForKey(locale,
                    systemLanguageContext, @"NSAMPMDesignation");
                if ([descriptionScanner scanString:[names objectAtIndex:1]
                                         intoString:NULL]) {
                    if (values->hour <= 11)
                        values->hour += 12;
                } else {
                    if (![descriptionScanner scanString:[names objectAtIndex:0]
                                             intoString:NULL])
                        return NO;
                    if (values->hour == 12)
                        values->hour = 0;
                }
                break;
            }
            case 'S':
                if (![descriptionScanner _scanDecimal:2 into:&values->second])
                    return NO;
                break;
            case 'w': {
                NSString *string = [descriptionScanner string];
                unsigned location = [descriptionScanner scanLocation];
                unichar character;
                if (location >= [string length])
                    return NO;
                character = [string characterAtIndex:location];
                if (character < '0' || character > '6')
                    return NO;
                [descriptionScanner setScanLocation:location + 1];
                break;
            }
            case 'x': {
                NSString *localizedFormat = NSCalendarDateParseObjectForKey(
                    locale, systemLanguageContext, @"NSTimeDateFormatString");
                if (localizedFormat == nil)
                    localizedFormat = @"%a %b %d %Y";
                if (!NSCalendarDateParseFormat(descriptionScanner,
                        [NSScanner scannerWithString:localizedFormat], locale,
                        systemLanguageContext, values))
                    return NO;
                break;
            }
            case 'X': {
                NSString *localizedFormat = NSCalendarDateParseObjectForKey(
                    locale, systemLanguageContext, @"NSTimeDateFormatString");
                if (localizedFormat == nil)
                    localizedFormat = @"%H:%M:%S %Z";
                if (!NSCalendarDateParseFormat(descriptionScanner,
                        [NSScanner scannerWithString:localizedFormat], locale,
                        systemLanguageContext, values))
                    return NO;
                break;
            }
            case 'y':
                if (![descriptionScanner _scanDecimal:2 into:&values->year])
                    return NO;
#if defined(__ppc__) || defined(__POWERPC__)
                if (NSCalendarDateDoExcelLittleY)
                    values->year += values->year <= 29 ? 2000 : 1900;
                else
                    values->year += 1900;
#else
                values->year += 1900;
#endif
                break;
            case 'Y':
                if (![descriptionScanner _scanDecimal:4 into:&values->year])
                    return NO;
                break;
            case 'z':
                if (![descriptionScanner scanInt:&parsedValue])
                    return NO;
                values->timeZoneOffset = (parsedValue / 100) * 3600
                    + (parsedValue % 100) * 60;
                break;
            case 'Z': {
                NSString *timeZoneName = nil;
                if (![descriptionScanner scanUpToCharactersFromSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]
                        intoString:&timeZoneName])
                    return NO;
                values->timeZoneName = timeZoneName;
                break;
            }
            default:
                return NO;
            }
        } else {
            NSString *formatString = [formatScanner string];
            NSString *descriptionString = [descriptionScanner string];
            formatLocation = [formatScanner scanLocation];
            descriptionLocation = [descriptionScanner scanLocation];
            if (formatLocation >= [formatString length]
                || descriptionLocation >= [descriptionString length]
                || [formatString characterAtIndex:formatLocation]
                    != [descriptionString characterAtIndex:descriptionLocation])
                return NO;
            [formatScanner setScanLocation:formatLocation + 1];
            [descriptionScanner setScanLocation:descriptionLocation + 1];
        }
    }
    return YES;
}

@implementation NSCalendarDate

+ (id)dateWithYear:(int)year month:(unsigned)month day:(unsigned)day hour:(unsigned)hour minute:(unsigned)minute second:(unsigned)second timeZone:(NSTimeZone *)aTimeZone {
    return [[[self allocWithZone:NULL] initWithYear:year month:month day:day
        hour:hour minute:minute second:second timeZone:aTimeZone] autorelease];
}

+ (id)dateWithString:(NSString *)description calendarFormat:(NSString *)format {
    return [[[self allocWithZone:NULL]
        initWithString:description calendarFormat:format locale:nil] autorelease];
}

+ (id)dateWithString:(NSString *)description calendarFormat:(NSString *)format locale:(NSDictionary *)dict {
    return [[[self allocWithZone:NULL]
        initWithString:description calendarFormat:format locale:dict] autorelease];
}

+ (id)calendarDate {
    return [[[self allocWithZone:NULL] init] autorelease];
}

+ (id)distantFuture {
    if (NSCalendarDateDistantFuture == nil)
        NSCalendarDateDistantFuture = [[self allocWithZone:NULL]
            initWithTimeIntervalSinceReferenceDate:63113990400.0];
    return NSCalendarDateDistantFuture;
}

+ (id)distantPast {
    if (NSCalendarDateDistantPast == nil)
        NSCalendarDateDistantPast = [[self allocWithZone:NULL]
            initWithTimeIntervalSinceReferenceDate:-63113817600.0];
    return NSCalendarDateDistantPast;
}

- (id)initWithYear:(int)year month:(unsigned)month day:(unsigned)day hour:(unsigned)hour minute:(unsigned)minute second:(unsigned)second timeZone:(NSTimeZone *)aTimeZone {
    int offset;

    if (aTimeZone == nil) {
#if defined(__ppc__) || defined(__POWERPC__)
        aTimeZone = [NSTimeZone defaultTimeZone];
#else
        [self dealloc];
        return nil;
#endif
    }

    _timeIntervalSinceReferenceDate =
        86400.0 * (absolute_from_gregorian((year << 16)
            | (((day & 0xff) << 8) | (month & 0xff))) - 730486)
        + 3600.0 * hour + 60.0 * minute + second;
    offset = [aTimeZone secondsFromGMTForDate:self];
    _timeIntervalSinceReferenceDate -= offset;
    {
        int adjustedOffset = [aTimeZone secondsFromGMTForDate:self];
        if (adjustedOffset != offset)
            _timeIntervalSinceReferenceDate += offset - adjustedOffset;
    }
    _timeZone = [aTimeZone retain];
    if (_formatString == nil)
        _formatString = @"%Y-%m-%d %H:%M:%S %z";
    return self;
}

- (id)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)seconds {
    _timeIntervalSinceReferenceDate = seconds;
    if (_timeZone == nil)
        _timeZone = [[NSTimeZone defaultTimeZone] retain];
    if (_formatString == nil)
        _formatString = @"%Y-%m-%d %H:%M:%S %z";
    return self;
}

- (id)init {
    return [self initWithTimeIntervalSinceReferenceDate:
        (NSTimeInterval)_NSCurrentTime()];
}

- (NSTimeInterval)timeIntervalSinceReferenceDate {
    return _timeIntervalSinceReferenceDate;
}

- (Class)classForCoder {
    return [NSCalendarDate class];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeValueOfObjCType:"d" at:&_timeIntervalSinceReferenceDate];
    [coder encodeValueOfObjCType:"@" at:&_timeZone];
    [coder encodeValueOfObjCType:"@" at:&_formatString];
}

- (id)initWithCoder:(NSCoder *)coder {
    [coder decodeValueOfObjCType:"d" at:&_timeIntervalSinceReferenceDate];
    [coder decodeValueOfObjCType:"@" at:&_timeZone];
    [coder decodeValueOfObjCType:"@" at:&_formatString];
    return self;
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    if (![coder isByref])
        return self;
    return [NSDistantObject proxyWithLocal:self connection:[coder connection]];
}

- (id)initWithString:(NSString *)description {
    return [super initWithString:description];
}

- (id)initWithString:(NSString *)description calendarFormat:(NSString *)format {
    return [self initWithString:description calendarFormat:format locale:nil];
}

- (id)initWithString:(NSString *)description calendarFormat:(NSString *)format locale:(NSDictionary *)dict {
    NSCalendarDateParseValues values;
    NSScanner *descriptionScanner;
    NSScanner *formatScanner;
    NSTimeZone *timeZone;
    id languageContext;

    values.year = 0;
    values.month = 0;
    values.day = 0;
    values.hour = 0;
    values.minute = 0;
    values.second = 0;
    values.dayOfYear = 0;
    values.milliseconds = 0;
    values.timeZoneOffset = -1;
    values.timeZoneName = nil;

    descriptionScanner = [NSScanner scannerWithString:description];
    formatScanner = [NSScanner scannerWithString:format];
    languageContext = NSCalendarDateSystemLanguageContext();
#if defined(__ppc__) || defined(__POWERPC__)
    NSCalendarDateInitializeExcelLittleY();
#endif
    if (!NSCalendarDateParseFormat(descriptionScanner, formatScanner, dict,
                                   languageContext, &values)) {
        [self dealloc];
        return nil;
    }

    timeZone = nil;
    if (values.timeZoneName != nil) {
        timeZone = [NSTimeZone timeZoneWithName:values.timeZoneName];
        if (timeZone == nil)
            timeZone = [NSTimeZone timeZoneWithAbbreviation:values.timeZoneName];
    }
    if (timeZone == nil && values.timeZoneOffset != -1)
        timeZone = [NSTimeZone timeZoneForSecondsFromGMT:values.timeZoneOffset];
    if (timeZone == nil)
        timeZone = [NSTimeZone defaultTimeZone];

    if (values.dayOfYear != 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        NSGregorianDate date = gregorian_from_absolute(
            absolute_from_year_day(values.year, values.dayOfYear));
        int month = date.month;
        int day = date.day;
#else
        int date = gregorian_from_absolute(
            absolute_from_year_day(values.year, values.dayOfYear));
        int month = date & 0xff;
        int day = (date >> 8) & 0xff;
#endif

        if ((values.month != 0 && values.month != month)
            || (values.day != 0 && values.day != day)) {
            [self dealloc];
            return nil;
        }
        values.month = month;
        values.day = day;
    }

    if (values.month == 0)
        values.month = 1;
    if (values.day == 0)
        values.day = 1;

    self = [self initWithYear:values.year month:(unsigned)values.month
        day:(unsigned)values.day hour:(unsigned)values.hour
        minute:(unsigned)values.minute second:(unsigned)values.second
        timeZone:timeZone];
    [self setCalendarFormat:format];
    if (self != nil && values.milliseconds != 0)
        _timeIntervalSinceReferenceDate += values.milliseconds / 1000.0;
    return self;
}

- (NSTimeZone *)timeZone {
    return _timeZone;
}

- (id)retain {
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSCalendarDateLockRetainCount();

    if (refCount != 0xffffffffU)
        ++refCount;
    NSCalendarDateUnlockRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
#else
    _NSIncrementInternalRefCount(self, &refCount, -1, _NSGlobalRetainLock);
#endif
    return self;
}

- (oneway void)release {
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSCalendarDateLockRetainCount();
    if (refCount != 0) {
        if (refCount != 0xffffffffU)
            --refCount;
    } else {
        shouldDeallocate = YES;
    }
    NSCalendarDateUnlockRetainCount(locked);
    if (shouldDeallocate)
        [self dealloc];
#else
    if (_NSDecrementInternalRefCountWasZero(self, &refCount, -1, _NSGlobalRetainLock))
        [self dealloc];
#endif
}

- (unsigned)retainCount {
#if defined(__ppc__) || defined(__POWERPC__)
    return refCount + 1;
#else
    return _NSInternalRefCount(self, refCount, -1);
#endif
}

- (int)microsecondOfSecond {
    double seconds = _timeIntervalSinceReferenceDate;
    return (int)((seconds - floor(seconds)) * 1000000.0 + 0.5);
}

- (id)timeZoneDetail {
    return [self timeZone];
}

- (void)setTimeZone:(NSTimeZone *)aTimeZone {
    NSTimeZone *newTimeZone = aTimeZone != nil
        ? aTimeZone : [NSTimeZone defaultTimeZone];

    [newTimeZone retain];
    [_timeZone release];
    _timeZone = newTimeZone;
}

- (NSString *)calendarFormat {
    return _formatString;
}

- (void)setCalendarFormat:(NSString *)format {
    [_formatString autorelease];
    _formatString = format != nil
        ? [format copyWithZone:NULL] : @"%Y-%m-%d %H:%M:%S %z";
}

- (int)yearOfCommonEra {
#if defined(__ppc__) || defined(__POWERPC__)
    return gregorian_from_absolute(NSCalendarDateAbsoluteDay(
        _timeIntervalSinceReferenceDate, _timeZone, self)).year;
#else
    return gregorian_from_absolute(NSCalendarDateAbsoluteDay(
        _timeIntervalSinceReferenceDate, _timeZone, self)) >> 16;
#endif
}

- (int)monthOfYear {
#if defined(__ppc__) || defined(__POWERPC__)
    return gregorian_from_absolute(NSCalendarDateAbsoluteDay(
        _timeIntervalSinceReferenceDate, _timeZone, self)).month;
#else
    return gregorian_from_absolute(NSCalendarDateAbsoluteDay(
        _timeIntervalSinceReferenceDate, _timeZone, self)) & 0xff;
#endif
}

- (int)dayOfMonth {
#if defined(__ppc__) || defined(__POWERPC__)
    return gregorian_from_absolute(NSCalendarDateAbsoluteDay(
        _timeIntervalSinceReferenceDate, _timeZone, self)).day;
#else
    return (gregorian_from_absolute(NSCalendarDateAbsoluteDay(
        _timeIntervalSinceReferenceDate, _timeZone, self)) >> 8) & 0xff;
#endif
}

- (int)dayOfWeek {
    return NSCalendarDateAbsoluteDay(_timeIntervalSinceReferenceDate,
        _timeZone, self) % 7;
}

- (int)dayOfYear {
    int year;
#if defined(__ppc__) || defined(__POWERPC__)
    double days = (_timeIntervalSinceReferenceDate
        + [_timeZone secondsFromGMTForDate:self]) / 86400.0 + 730486.0;
#else
    double days = (double)(((long double)_timeIntervalSinceReferenceDate
        + [_timeZone secondsFromGMTForDate:self]) / 86400.0L) + 730486.0;
#endif

    year = [self yearOfCommonEra];
    if (days > 2147483647.0)
        days = 1460972.0;
    else if (days < 1.0)
        days = 1.0;
    return (int)days - absolute_from_gregorian((year << 16) | 0x0101) + 1;
}

- (int)dayOfCommonEra {
#if defined(__ppc__) || defined(__POWERPC__)
    double days = (_timeIntervalSinceReferenceDate
        + [_timeZone secondsFromGMTForDate:self]) / 86400.0 + 730486.0;

    return (int)days;
#else
    long double days = ((long double)_timeIntervalSinceReferenceDate
        + [_timeZone secondsFromGMTForDate:self]) / 86400.0L + 730486.0L;

    return (int)days;
#endif
}

- (int)hourOfDay {
    return NSCalendarDateTimeComponent(_timeIntervalSinceReferenceDate,
        _timeZone, self, 3600, 24);
}

- (int)minuteOfHour {
    return NSCalendarDateTimeComponent(_timeIntervalSinceReferenceDate,
        _timeZone, self, 60, 60);
}

- (int)secondOfMinute {
    return NSCalendarDateTimeComponent(_timeIntervalSinceReferenceDate,
        _timeZone, self, 1, 60);
}

- (id)addTimeInterval:(NSTimeInterval)seconds {
    NSCalendarDate *date = [super addTimeInterval:seconds];
    [date setTimeZone:_timeZone];
    [date setCalendarFormat:_formatString];
    return date;
}

- (id)copyWithZone:(NSZone *)zone {
    NSCalendarDate *date = [[NSCalendarDate allocWithZone:zone]
        initWithTimeIntervalSinceReferenceDate:_timeIntervalSinceReferenceDate];
    [date setTimeZone:_timeZone];
    [date setCalendarFormat:_formatString];
    return date;
}

- (NSCalendarDate *)dateByAddingYears:(int)year months:(int)month days:(int)day hours:(int)hour minutes:(int)minute seconds:(int)second {
    int targetYear;
    int targetMonth;
    int targetDay;
    int totalSeconds;
    int targetHour;
    int targetMinute;
    int targetSecond;
    int monthDays;
    NSCalendarDate *date;
#if defined(__ppc__) || defined(__POWERPC__)
    int currentTimeZoneOffset;
    int adjustedTimeZoneOffset;
#endif

    targetDay = [self dayOfMonth];
    targetYear = [self yearOfCommonEra] + year;
    targetMonth = [self monthOfYear] + month - 1;
    targetHour = [self hourOfDay] + hour;
    targetMinute = [self minuteOfHour] + minute;
    totalSeconds = [self secondOfMinute] + second;
#if defined(__ppc__) || defined(__POWERPC__)
    currentTimeZoneOffset = [_timeZone secondsFromGMTForDate:self];
#endif

    if (targetMonth > 11) {
        targetYear += targetMonth / 12;
        targetMonth %= 12;
    }
    if (targetMonth < 0) {
        targetYear += targetMonth / 12;
        targetMonth %= 12;
        if (targetMonth < 0) {
            targetYear--;
            targetMonth += 12;
        }
    }
    targetMonth++;
    monthDays = last_day_of_gregorian_month(targetMonth, targetYear);
    if (targetDay > monthDays)
        targetDay = monthDays;

    targetDay += day;
    while (targetDay > (monthDays = last_day_of_gregorian_month(targetMonth, targetYear))) {
        targetDay -= monthDays;
        if (++targetMonth == 13) {
            targetYear++;
            targetMonth = 1;
        }
    }
    while (targetDay <= 0) {
        if (--targetMonth == 0) {
            targetYear--;
            targetMonth = 12;
        }
        targetDay += last_day_of_gregorian_month(targetMonth, targetYear);
    }

#if defined(__ppc__) || defined(__POWERPC__)
    for (;;) {
        int carry;

        carry = targetMinute + totalSeconds / 60;
        targetSecond = totalSeconds % 60;
        if (targetSecond < 0) {
            carry--;
            targetSecond += 60;
        }

        targetHour += carry / 60;
        targetMinute = carry % 60;
        if (targetMinute < 0) {
            targetHour--;
            targetMinute += 60;
        }

        targetDay += targetHour / 24;
        targetHour %= 24;
        if (targetHour < 0) {
            targetDay--;
            targetHour += 24;
        }

        while (targetDay > (monthDays = last_day_of_gregorian_month(targetMonth, targetYear))) {
            targetDay -= monthDays;
            if (++targetMonth == 13) {
                targetYear++;
                targetMonth = 1;
            }
        }
        while (targetDay <= 0) {
            if (--targetMonth == 0) {
                targetYear--;
                targetMonth = 12;
            }
            targetDay += last_day_of_gregorian_month(targetMonth, targetYear);
        }

        date = [[(Class)self->isa allocWithZone:NULL]
            initWithYear:targetYear month:targetMonth day:targetDay
            hour:targetHour minute:targetMinute second:targetSecond
            timeZone:_timeZone];
        adjustedTimeZoneOffset = [_timeZone secondsFromGMTForDate:date];
        if (adjustedTimeZoneOffset == currentTimeZoneOffset)
            break;

        [date release];
        totalSeconds = targetSecond + adjustedTimeZoneOffset
            - currentTimeZoneOffset;
        currentTimeZoneOffset = adjustedTimeZoneOffset;
    }
    date = [date autorelease];
#else
    targetMinute += totalSeconds / 60;
    if (totalSeconds % 60 < 0)
        targetMinute--;
    targetSecond = totalSeconds % 60;
    if (targetSecond < 0)
        targetSecond += 60;

    targetHour += targetMinute / 60;
    if (targetMinute % 60 < 0)
        targetHour--;
    targetMinute %= 60;
    if (targetMinute < 0)
        targetMinute += 60;

    targetDay += targetHour / 24;
    if (targetHour % 24 < 0)
        targetDay--;
    targetHour %= 24;
    if (targetHour < 0)
        targetHour += 24;

    while (targetDay > (monthDays = last_day_of_gregorian_month(targetMonth, targetYear))) {
        targetDay -= monthDays;
        if (++targetMonth == 13) {
            targetYear++;
            targetMonth = 1;
        }
    }
    while (targetDay <= 0) {
        if (--targetMonth == 0) {
            targetYear--;
            targetMonth = 12;
        }
        targetDay += last_day_of_gregorian_month(targetMonth, targetYear);
    }

    date = [[(Class)self->isa allocWithZone:NULL]
        initWithYear:targetYear month:targetMonth day:targetDay
        hour:targetHour minute:targetMinute second:targetSecond timeZone:_timeZone];
    date = [date autorelease];
#endif
    if (date != nil) {
#if defined(__ppc__) || defined(__POWERPC__)
        date->_timeIntervalSinceReferenceDate +=
            _timeIntervalSinceReferenceDate
            - floor(_timeIntervalSinceReferenceDate);
#else
        date->_timeIntervalSinceReferenceDate +=
            (long double)_timeIntervalSinceReferenceDate
            - floor(_timeIntervalSinceReferenceDate);
#endif
    }
    [date setCalendarFormat:_formatString];
    return date;
}

- (void)years:(int *)yp months:(int *)mop days:(int *)dp hours:(int *)hp minutes:(int *)mip seconds:(int *)sp sinceDate:(NSCalendarDate *)date {
    int *outputs[] = {yp, mop, dp, hp, mip};
    int components[] = {0, 0, 0, 0, 0};
    const int unitLengths[] = {31622400, 2678400, 86400, 3600, 60};
    NSTimeInterval selfInterval;
    NSTimeInterval baseInterval;
    int direction;
    int index;
    NSCalendarDate *lastDate = nil;

    if (date == nil) {
#if defined(__ppc__) || defined(__POWERPC__)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: nil since-date parameter",
         _NSMethodExceptionProem(self, _cmd)];
#else
        [NSException raise:NSInvalidArgumentException format:@"nil since-date"];
#endif
    }

    baseInterval = [date timeIntervalSinceReferenceDate];
    selfInterval = [self timeIntervalSinceReferenceDate];
    if (selfInterval == baseInterval) {
        for (index = 0; index < 5; index++) {
            if (outputs[index] != NULL)
                *outputs[index] = 0;
        }
        if (sp != NULL)
            *sp = 0;
        return;
    }

    direction = selfInterval > baseInterval ? 1 : -1;
    for (index = 0; index < 5; index++) {
        NSCalendarDate *candidate;
        NSComparisonResult crossing = direction > 0
            ? NSOrderedAscending : NSOrderedDescending;

        if (outputs[index] == NULL)
            continue;

#if defined(__ppc__) || defined(__POWERPC__)
        components[index] = (int)((selfInterval - baseInterval)
            / unitLengths[index] - 2.0 * direction);
#else
        components[index] = (int)(((long double)selfInterval - baseInterval)
            / unitLengths[index] - 2.0 * direction);
#endif
        while (1) {
            candidate = [date dateByAddingYears:components[0]
                months:components[1] days:components[2]
                hours:components[3] minutes:components[4] seconds:0];
            if ([self compare:candidate] == crossing)
                break;
            components[index] += direction;
            lastDate = candidate;
        }

        components[index] -= direction;
        *outputs[index] = components[index];
        if (lastDate == nil)
            NSLog(@"%@: assertion failure", _NSMethodExceptionProem(self, _cmd));
        baseInterval = [lastDate timeIntervalSinceReferenceDate];
    }

    if (sp != NULL)
        *sp = (int)(selfInterval - baseInterval);
}

- (NSString *)description {
    return [self descriptionWithCalendarFormat:_formatString locale:nil];
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    return [self descriptionWithCalendarFormat:_formatString locale:locale];
}

- (NSString *)descriptionWithCalendarFormat:(NSString *)format {
    return [self descriptionWithCalendarFormat:format locale:nil];
}

- (NSString *)descriptionWithCalendarFormat:(NSString *)format locale:(NSDictionary *)locale {
    NSMutableString *result = [[NSMutableString allocWithZone:NULL] init];
    NSCharacterSet *decimalDigits;
    id systemLanguageContext;
    unsigned length;
    unsigned index = 0;

    length = [format length];
    decimalDigits = [NSCharacterSet decimalDigitCharacterSet];
    systemLanguageContext = NSCalendarDateSystemLanguageContext();
    if (length == 0)
        return [result autorelease];

    while (index < length) {
        NSRange percentRange = [format rangeOfString:@"%" options:0
            range:NSMakeRange(index, length - index)];
        unsigned literalStart = index;
        unsigned directive;
        char numberFormat[128] = "";

        if (percentRange.length == 0)
            percentRange.location = length;
        if (percentRange.location > literalStart) {
            NSString *literal;
            unsigned resultLength;
#if defined(__ppc__) || defined(__POWERPC__)
            resultLength = [result length];
            literal = [format substringWithRange:
                NSMakeRange(literalStart, percentRange.location - literalStart)];
#else
            literal = [format substringWithRange:
                NSMakeRange(literalStart, percentRange.location - literalStart)];
            resultLength = [result length];
#endif

            [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                withString:literal];
        }
        index = percentRange.location + percentRange.length;
        if (percentRange.length == 0)
            break;

        literalStart = index;
        while (index < length) {
            unichar character = [format characterAtIndex:index];
            if (![decimalDigits characterIsMember:character])
                break;
            index++;
        }
        if (index > literalStart) {
            NSString *width = [format substringWithRange:
                NSMakeRange(literalStart, index - literalStart)];
            snprintf(numberFormat, sizeof(numberFormat), "%%%sd",
                [width lossyCString]);
        }
        if (index >= length)
            break;

        directive = [format characterAtIndex:index++];
        switch (directive) {
        case 'A':
#if defined(__ppc__) || defined(__POWERPC__)
            {
                int dayOfWeek = [self dayOfWeek];
                NSCalendarDateAppendLocalizedName(result, dayOfWeek, locale,
                    systemLanguageContext, @"NSWeekDayNameArray");
            }
#else
            {
                NSArray *names = NSCalendarDateNamesForKey(locale,
                    @"NSWeekDayNameArray", nil);
                NSArray *fallbackNames =
                    NSCalendarDateFormatterFallbackNames(systemLanguageContext,
                        @"NSWeekDayNameArray");
                int dayOfWeek = [self dayOfWeek];

                appendName(result, dayOfWeek, names, fallbackNames);
            }
#endif
            break;
        case 'a':
#if defined(__ppc__) || defined(__POWERPC__)
            {
                int dayOfWeek = [self dayOfWeek];
                NSCalendarDateAppendLocalizedName(result, dayOfWeek, locale,
                    systemLanguageContext, @"NSShortWeekDayNameArray");
            }
#else
            {
                NSArray *names = NSCalendarDateNamesForKey(locale,
                    @"NSShortWeekDayNameArray", nil);
                NSArray *fallbackNames =
                    NSCalendarDateFormatterFallbackNames(systemLanguageContext,
                        @"NSShortWeekDayNameArray");
                int dayOfWeek = [self dayOfWeek];

                appendName(result, dayOfWeek, names, fallbackNames);
            }
#endif
            break;
        case 'B':
#if defined(__ppc__) || defined(__POWERPC__)
            {
                int month = [self monthOfYear] - 1;
                NSCalendarDateAppendLocalizedName(result, month, locale,
                    systemLanguageContext, @"NSMonthNameArray");
            }
#else
            {
                NSArray *names = NSCalendarDateNamesForKey(locale,
                    @"NSMonthNameArray", nil);
                NSArray *fallbackNames =
                    NSCalendarDateFormatterFallbackNames(systemLanguageContext,
                        @"NSMonthNameArray");
                int month = [self monthOfYear] - 1;

                appendName(result, month, names, fallbackNames);
            }
#endif
            break;
        case 'b':
#if defined(__ppc__) || defined(__POWERPC__)
            {
                int month = [self monthOfYear] - 1;
                NSCalendarDateAppendLocalizedName(result, month, locale,
                    systemLanguageContext, @"NSShortMonthNameArray");
            }
#else
            {
                NSArray *names = NSCalendarDateNamesForKey(locale,
                    @"NSShortMonthNameArray", nil);
                NSArray *fallbackNames =
                    NSCalendarDateFormatterFallbackNames(systemLanguageContext,
                        @"NSShortMonthNameArray");
                int month = [self monthOfYear] - 1;

                appendName(result, month, names, fallbackNames);
            }
#endif
            break;
        case 'c': {
            NSString *localizedFormat =
                [locale objectForKey:@"NSTimeDateFormatString"];
            if (localizedFormat == nil)
                localizedFormat = @"%a %b %d %H:%M:%S %Z %Y";
#if defined(__ppc__) || defined(__POWERPC__)
            {
                unsigned length = [result length];
                NSString *formatted = [self descriptionWithCalendarFormat:
                    localizedFormat locale:locale];
                [result replaceCharactersInRange:NSMakeRange(length, 0)
                                      withString:formatted];
            }
#else
            {
                NSString *formatted = [self descriptionWithCalendarFormat:
                    localizedFormat locale:locale];
                unsigned length = [result length];
                [result replaceCharactersInRange:NSMakeRange(length, 0)
                                      withString:formatted];
            }
#endif
            break;
        }
        case 'd':
            appendNumber(result, [self dayOfMonth], numberFormat, "%02d");
            break;
        case 'e':
            appendNumber(result, [self dayOfMonth], numberFormat, "%2d");
            break;
        case 'F':
            append03(result, NSCalendarDateRoundedMilliseconds(
                _timeIntervalSinceReferenceDate));
            break;
        case 'H':
            appendNumber(result, [self hourOfDay], numberFormat, "%02d");
            break;
        case 'I': {
            int hour = [self hourOfDay] % 12;
            appendNumber(result, hour == 0 ? 12 : hour, numberFormat, "%02d");
            break;
        }
        case 'j':
            appendNumber(result, [self dayOfYear], numberFormat, "%03d");
            break;
        case 'm':
            appendNumber(result, [self monthOfYear], numberFormat, "%02d");
            break;
        case 'M':
            appendNumber(result, [self minuteOfHour], numberFormat, "%02d");
            break;
        case 'p':
#if defined(__ppc__) || defined(__POWERPC__)
            {
                int designation = [self hourOfDay] < 12 ? 0 : 1;
                NSCalendarDateAppendLocalizedName(result, designation, locale,
                    systemLanguageContext, @"NSAMPMDesignation");
            }
#else
            {
                NSArray *names = NSCalendarDateNamesForKey(locale,
                    @"NSAMPMDesignation", nil);
                NSArray *fallbackNames =
                    NSCalendarDateFormatterFallbackNames(systemLanguageContext,
                        @"NSAMPMDesignation");
                int designation = [self hourOfDay] < 12 ? 0 : 1;

                appendName(result, designation, names, fallbackNames);
            }
#endif
            break;
        case 'S':
            appendNumber(result, [self secondOfMinute], numberFormat, "%02d");
            break;
        case 'w':
            appendNumber(result, [self dayOfWeek], numberFormat, "%d");
            break;
        case 'x': {
            NSString *localizedFormat =
                [locale objectForKey:@"NSTimeDateFormatString"];
            if (localizedFormat == nil)
                localizedFormat = @"%a %b %d %Y";
#if defined(__ppc__) || defined(__POWERPC__)
            {
                unsigned length = [result length];
                NSString *formatted = [self descriptionWithCalendarFormat:
                    localizedFormat locale:locale];
                [result replaceCharactersInRange:NSMakeRange(length, 0)
                                      withString:formatted];
            }
#else
            {
                NSString *formatted = [self descriptionWithCalendarFormat:
                    localizedFormat locale:locale];
                unsigned length = [result length];
                [result replaceCharactersInRange:NSMakeRange(length, 0)
                                      withString:formatted];
            }
#endif
            break;
        }
        case 'X': {
            NSString *localizedFormat =
                [locale objectForKey:@"NSTimeDateFormatString"];
            if (localizedFormat == nil)
                localizedFormat = @"%H:%M:%S %Z";
#if defined(__ppc__) || defined(__POWERPC__)
            {
                unsigned length = [result length];
                NSString *formatted = [self descriptionWithCalendarFormat:
                    localizedFormat locale:locale];
                [result replaceCharactersInRange:NSMakeRange(length, 0)
                                      withString:formatted];
            }
#else
            {
                NSString *formatted = [self descriptionWithCalendarFormat:
                    localizedFormat locale:locale];
                unsigned length = [result length];
                [result replaceCharactersInRange:NSMakeRange(length, 0)
                                      withString:formatted];
            }
#endif
            break;
        }
        case 'y':
            appendNumber(result, [self yearOfCommonEra] % 100, numberFormat,
                "%02d");
            break;
        case 'Y':
            appendNumber(result, [self yearOfCommonEra], numberFormat, "%d");
            break;
        case 'z': {
            NSTimeZone *timeZone = _timeZone;
            int offset = timeZone != nil
                ? [timeZone secondsFromGMTForDate:self] : 0;
            NSString *signString = offset < 0 ? @"-" : @"+";
            int absoluteOffset = offset < 0 ? -offset : offset;
            unsigned resultLength = [result length];

            [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                                  withString:signString];
            appendNumber(result, absoluteOffset / 3600, "", "%02d");
            appendNumber(result, absoluteOffset / 60 % 60, "", "%02d");
            break;
        }
        case 'Z': {
#if defined(__ppc__) || defined(__POWERPC__)
            NSString *abbreviation = [_timeZone abbreviationForDate:self];
            unsigned resultLength = [result length];

            [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                withString:abbreviation != nil ? abbreviation : @""];
#else
            NSString *name = [_timeZone name];

            [result appendString:name != nil ? name : @""];
#endif
            break;
        }
        default: {
            unsigned resultLength = [result length];

            [result replaceCharactersInRange:NSMakeRange(resultLength, 0)
                withString:@"?"];
            break;
        }
        }
    }

    return [result autorelease];
}

- (void)dealloc {
    [_timeZone release];
    [_formatString release];
    [super dealloc];
}

@end

@implementation NSDate (NSCalendarDateExtras)

+ (id)dateWithString:(NSString *)aString {
    return [[[NSDate allocWithZone:NULL] initWithString:aString] autorelease];
}

- (id)initWithString:(NSString *)description {
    const char *cursor = [description cString];
    int year;
    unsigned char month;
    unsigned char day;
    int hour;
    int minute;
    int second;
    int zoneSign;
    int zoneValue;
    int zoneOffset;
    NSTimeInterval interval;

    if (cursor == NULL)
        return nil;
    year = NSCalendarDateReadNumber(&cursor);
    if (*cursor == '\0')
        return nil;
    cursor++;
    month = (unsigned char)NSCalendarDateReadNumber(&cursor);
    if (*cursor == '\0')
        return nil;
    cursor++;
    day = (unsigned char)NSCalendarDateReadNumber(&cursor);
    if (*cursor == '\0')
        return nil;
    cursor++;
    hour = NSCalendarDateReadNumber(&cursor);
    if (*cursor == '\0')
        return nil;
    cursor++;
    minute = NSCalendarDateReadNumber(&cursor);
    if (*cursor == '\0')
        return nil;
    cursor++;
    second = NSCalendarDateReadNumber(&cursor);
    if (*cursor == '\0')
        return nil;
    cursor++;
    if (*cursor == '-')
        zoneSign = -1;
    else if (*cursor == '+')
        zoneSign = 1;
    else
        return nil;
    cursor++;
    zoneValue = NSCalendarDateReadNumber(&cursor);
    zoneOffset = 60 * zoneSign * (zoneValue % 100 + 60 * (zoneValue / 100));

    interval = 86400.0L * (absolute_from_gregorian((year << 16)
        | ((day << 8) | month)) - 730486)
        + (long double)(unsigned)(3600 * hour)
        + (long double)(unsigned)(60 * minute)
        + (long double)(unsigned)second - zoneOffset;
    self = [self initWithTimeIntervalSinceReferenceDate:interval];
    if ([self respondsToSelector:@selector(setTimeZone:)])
        [(NSCalendarDate *)self setTimeZone:
            [NSTimeZone timeZoneForSecondsFromGMT:zoneOffset]];
    return self;
}

- (NSCalendarDate *)dateWithCalendarFormat:(NSString *)format timeZone:(NSTimeZone *)aTimeZone {
    NSCalendarDate *date = [NSCalendarDate
        dateWithTimeIntervalSinceReferenceDate:[self timeIntervalSinceReferenceDate]];

    [date setTimeZone:aTimeZone];
    [date setCalendarFormat:format];
    return date;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale {
    NSCalendarDate *date = [[NSCalendarDate allocWithZone:NULL]
        initWithTimeIntervalSinceReferenceDate:[self timeIntervalSinceReferenceDate]];
    NSString *description;

    if (locale != nil) {
        [date setCalendarFormat:@"%c"];
        description = [date descriptionWithLocale:locale];
    } else {
        description = [date description];
    }
    [date release];
    return description;
}

- (NSString *)descriptionWithCalendarFormat:(NSString *)format timeZone:(NSTimeZone *)aTimeZone locale:(NSDictionary *)locale {
    NSCalendarDate *date = [[NSCalendarDate allocWithZone:NULL]
        initWithTimeIntervalSinceReferenceDate:[self timeIntervalSinceReferenceDate]];
    NSString *description;

    [date setTimeZone:aTimeZone];
    [date setCalendarFormat:format];
    description = [date descriptionWithLocale:locale];
    [date release];
    return description;
}

@end

@implementation NSCalendarDate (NSNaturalLanguageDate)

+ (NSCalendarDate *)dateWithNaturalLanguageString:(NSString *)string
                                             date:(NSCalendarDate *)baseDate
                                           locale:(NSDictionary *)locale {
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    NSMutableCharacterSet *signedDigits =
        [[NSMutableCharacterSet decimalDigitCharacterSet] mutableCopy];
    NSScanner *scanner;
    NSMutableArray *tokens = [NSMutableArray array];
    NSDictionary *defaults;
    NSString *token;
    NSString *scanText;
    NSString *timeZoneName = nil;
    NSTimeZone *timeZone = nil;
    int numbers[4] = { 0, 0, 0, 0 };
    unsigned numberCount = 0;
    int year = 0, month = 0, day = 0;
    int hour = -1, minute = 0, second = 0;
    int relativeDay = 0;
    BOOL hasRelativeDay = NO;
    BOOL recognizedDateToken = NO;
    BOOL flags[55] = { NO };
    unsigned index;

    if (string == nil)
        return nil;
    [signedDigits addCharactersInString:@"-+"];
    if (locale == nil) {
        defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        locale = defaults;
    }
    NSCalendarDateNaturalLanguageBuildTokenMap(locale);
#if defined(__ppc__) || defined(__POWERPC__)
    NSCalendarDateInitializeExcelLittleY();
#endif
    scanner = [NSScanner scannerWithString:string];
    [scanner setCharactersToBeSkipped:nil];
    while (![scanner isAtEnd]) {
        BOOL hadWhitespace = [scanner scanCharactersFromSet:whitespace
                                                  intoString:NULL];
        if ([scanner scanCharactersFromSet:digits intoString:&scanText]) {
            [tokens addObject:scanText];
        } else if (hadWhitespace &&
                   [scanner scanCharactersFromSet:signedDigits
                                       intoString:&scanText]) {
            [tokens addObject:scanText];
        } else if ([scanner scanCharactersFromSet:letters
                                       intoString:&scanText] ||
                   [scanner scanCharactersFromSet:alphanumeric
                                       intoString:&scanText]) {
            [tokens addObject:scanText];
        } else if ([scanner scanUpToCharactersFromSet:alphanumeric
                                           intoString:&scanText]) {
            [tokens addObject:scanText];
        } else {
            [NSException raise:@"format error" format:@"internal error"];
        }
    }

    for (index = 0; index < [tokens count]; index++) {
        token = [tokens objectAtIndex:index];
        if ([token length] == 0)
            continue;

        if ([digits characterIsMember:[token characterAtIndex:0]]) {
            int value = [token intValue];

            recognizedDateToken = YES;
            if (value > 31) {
                year = value <= 99 ? value + 1900 : value;
                continue;
            }
            if (year != 0 && value > 23) {
                day = value;
                continue;
            }
            if (index + 2 < [tokens count] &&
                [[tokens objectAtIndex:index + 1] isEqualToString:@":"] &&
                [[tokens objectAtIndex:index + 2] length] != 0 &&
                [digits characterIsMember:[[tokens objectAtIndex:index + 2]
                    characterAtIndex:0]]) {
                int parsedHour = value;
                int parsedMinute = [[tokens objectAtIndex:index + 2] intValue];
                index += 2;
                hour = parsedHour;
                minute = parsedMinute;
                if (index + 2 < [tokens count] &&
                    [[tokens objectAtIndex:index + 1] isEqualToString:@":"] &&
                    [[tokens objectAtIndex:index + 2] length] != 0 &&
                    [digits characterIsMember:[[tokens objectAtIndex:index + 2]
                        characterAtIndex:0]]) {
                    second = [[tokens objectAtIndex:index + 2] intValue];
                    index += 2;
                }
                if (hour > 23 || minute > 59 || second > 60)
                    return nil;
                continue;
            }
            if (hour == -1 && index + 1 < [tokens count]) {
                unsigned nextAction = NSCalendarDateNaturalLanguageAction(
                    [tokens objectAtIndex:index + 1]);
                if (nextAction == 118 || nextAction == 119) {
                    hour = value;
                    continue;
                }
            }
            if (numberCount < 4)
                numbers[numberCount++] = value;
            continue;
        }

        if ([token characterAtIndex:0] == '+' ||
            [token characterAtIndex:0] == '-') {
            int value = [token intValue];
            int absoluteValue = value < 0 ? -value : value;
            int offset = (absoluteValue / 100) * 3600
                + (absoluteValue % 100) * 60;
            if (value < 0)
                offset = -offset;
            timeZone = [NSTimeZone timeZoneForSecondsFromGMT:offset];
            continue;
        }

        {
            unsigned action = NSCalendarDateNaturalLanguageAction(token);
            if (action >= 66 && action <= 77) {
                month = action - 65;
                recognizedDateToken = YES;
            } else if (action >= 82 && action <= 88) {
                flags[action - 65] = YES;
                recognizedDateToken = YES;
            } else if ((action >= 78 && action <= 81) ||
                       (action >= 89 && action <= 90) ||
                       (action >= 91 && action <= 117) ||
                       (action >= 118 && action <= 119)) {
                flags[action - 65] = YES;
                recognizedDateToken = YES;
            } else if ([token isEqualToString:@"GMT"]) {
                NSString *zoneKey = token;
                if (index + 1 < [tokens count] &&
                    [[tokens objectAtIndex:index + 1] length] != 0 &&
                    ([signedDigits characterIsMember:[[tokens objectAtIndex:index + 1]
                        characterAtIndex:0]])) {
                    zoneKey = [zoneKey stringByAppendingString:
                        [tokens objectAtIndex:++index]];
                    if (index + 1 < [tokens count] &&
                        [[tokens objectAtIndex:index + 1] length] != 0 &&
                        [digits characterIsMember:[[tokens objectAtIndex:index + 1]
                            characterAtIndex:0]])
                        zoneKey = [zoneKey stringByAppendingString:
                            [tokens objectAtIndex:++index]];
                }
                if ([[NSTimeZone abbreviationDictionary] objectForKey:zoneKey]
                    != nil) {
                    timeZoneName = zoneKey;
                    recognizedDateToken = YES;
                }
            } else {
                NSDictionary *abbreviations = [NSTimeZone abbreviationDictionary];
                if ([abbreviations objectForKey:token] != nil) {
                    timeZoneName = token;
                    recognizedDateToken = YES;
                }
            }
        }
    }

    if (year == 0 || month == 0 || day == 0 || hour == -1) {
        for (index = 0; index < numberCount; index++) {
            int value = numbers[index];
            unsigned orderIndex;
            BOOL assigned = NO;

            for (orderIndex = 0; orderIndex < 4; orderIndex++) {
                unichar field = NSCalendarDateNaturalLanguageNumberOrder[
                    orderIndex];
                if (field == 'Y' && year == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
                    if (value <= 99 && NSCalendarDateDoExcelLittleY &&
                        value <= 29)
                        year = value + 2000;
                    else
                        year = value <= 99 ? value + 1900 : value;
#else
                    year = value <= 99 ? value + 1900 : value;
#endif
                    assigned = YES;
                } else if (field == 'M' && month == 0) {
                    if (value > 12)
                        return nil;
                    month = value;
                    assigned = YES;
                } else if (field == 'D' && day == 0) {
                    if (value > 31)
                        return nil;
                    day = value;
                    assigned = YES;
                } else if (field == 'H' && hour == -1) {
                    if (value > 23)
                        return nil;
                    hour = value;
                    assigned = YES;
                } else if (field != 'Y' && field != 'M' &&
                           field != 'D' && field != 'H') {
                    return nil;
                }
                if (assigned)
                    break;
            }
        }
    }

    if (month == 0) {
        for (index = 1; index <= 12; index++) {
            if (flags[index]) {
                month = index;
                break;
            }
        }
    }
    if (flags[13]) {
        relativeDay = 0;
        hasRelativeDay = YES;
    } else if (flags[14]) {
        relativeDay = -1;
        hasRelativeDay = YES;
    } else if (flags[15]) {
        relativeDay = 1;
        hasRelativeDay = YES;
    } else if (flags[16]) {
        relativeDay = 2;
        hasRelativeDay = YES;
    }
    if (hasRelativeDay)
        recognizedDateToken = YES;

    if (timeZoneName != nil)
        timeZone = [NSTimeZone timeZoneWithAbbreviation:timeZoneName];
    if (timeZone == nil)
        timeZone = [NSTimeZone defaultTimeZone];
    if (baseDate == nil)
        baseDate = [NSCalendarDate calendarDate];

    if (hasRelativeDay)
        baseDate = [baseDate dateByAddingYears:0 months:0 days:relativeDay
            hours:0 minutes:0 seconds:0];
    if (flags[26] && (flags[24] || flags[25]))
        baseDate = [baseDate dateByAddingYears:flags[24] ? 1 : -1
            months:0 days:0 hours:0 minutes:0 seconds:0];
    else if (flags[27] && (flags[24] || flags[25]))
        baseDate = [baseDate dateByAddingYears:0
            months:flags[24] ? 1 : -1 days:0 hours:0 minutes:0 seconds:0];
    else if (flags[28] && (flags[24] || flags[25]))
        baseDate = [baseDate dateByAddingYears:0 months:0
            days:flags[24] ? 7 : -7 hours:0 minutes:0 seconds:0];

    if (flags[26] || flags[27] || flags[28])
        recognizedDateToken = YES;

    {
        int weekday;
        for (weekday = 0; weekday < 7; weekday++) {
            if (flags[17 + weekday]) {
                int days = weekday - [baseDate dayOfWeek];
                if (flags[25]) {
                    if (days >= 0)
                        days -= 7;
                } else if (days <= 0) {
                    days += 7;
                }
                baseDate = [baseDate dateByAddingYears:0 months:0 days:days
                    hours:0 minutes:0 seconds:0];
                recognizedDateToken = YES;
                break;
            }
        }
    }

    for (index = 0; index < 24; index++) {
        if (flags[29 + index]) {
            hour = index;
            minute = 0;
            second = 0;
            recognizedDateToken = YES;
        }
    }
    if (!recognizedDateToken ||
        (year == 0 && month == 0 && day == 0 && hour == -1 &&
         !hasRelativeDay && !flags[17] && !flags[18] && !flags[19] &&
         !flags[20] && !flags[21] && !flags[22] && !flags[23] &&
         !(flags[26] && (flags[24] || flags[25])) &&
         !(flags[27] && (flags[24] || flags[25])) &&
         !(flags[28] && (flags[24] || flags[25]))))
        return nil;
    if (hour == -1)
        hour = 12;
    if (flags[53] && hour == 12)
        hour = 0;
    else if (flags[54] && hour <= 11)
        hour += 12;

    if (year == 0)
        year = [baseDate yearOfCommonEra];
    if (month == 0)
        month = [baseDate monthOfYear];
    if (day == 0)
        day = [baseDate dayOfMonth];
    if (month < 1 || month > 12 || day < 1 || day > 31)
        return nil;

    if (timeZoneName != nil)
        timeZone = [NSTimeZone timeZoneWithAbbreviation:timeZoneName];
    return [self dateWithYear:year month:(unsigned)month day:(unsigned)day
        hour:(unsigned)hour minute:(unsigned)minute second:(unsigned)second
        timeZone:timeZone];
}

@end

@implementation NSDate (NSNaturalLanguageDate)

+ (id)dateWithNaturalLanguageString:(NSString *)string {
    return [self dateWithNaturalLanguageString:string date:nil locale:nil];
}

+ (id)dateWithNaturalLanguageString:(NSString *)string locale:(NSDictionary *)dict {
    return [self dateWithNaturalLanguageString:string date:nil locale:dict];
}

+ (id)dateWithNaturalLanguageString:(NSString *)string
                               date:(NSDate *)date
                             locale:(NSDictionary *)locale {
    NSCalendarDate *calendarDate = [NSCalendarDate
        dateWithNaturalLanguageString:string date:(NSCalendarDate *)date
        locale:locale];

    if (calendarDate == nil)
        return nil;
    if (self == [NSDate class])
        return calendarDate;
    return [self dateWithTimeIntervalSinceReferenceDate:
        [calendarDate timeIntervalSinceReferenceDate]];
}

@end
