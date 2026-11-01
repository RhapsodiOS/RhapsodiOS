/*	NSDateFormatter.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDateFormatter.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSTimeZone.h>

extern NSBundle *_NSFoundationBundle(void);

@implementation NSDateFormatter

- (id)initWithDateFormat:(NSString *)format allowNaturalLanguage:(BOOL)flag {
    [super init];
    _format = format ? [format copy] : @"%Y-%m-%d %H:%M:%S %z";
    _naturalLanguage = flag;
    return self;
}

- (NSString *)dateFormat {
    return _format;
}

- (BOOL)allowsNaturalLanguage {
    return _naturalLanguage;
}

- (id)init {
    return [self initWithDateFormat:nil allowNaturalLanguage:YES];
}

- (void)dealloc {
    [_format release];
    [super dealloc];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeValuesOfObjCTypes:"@c", &_format, &_naturalLanguage];
}

- (id)initWithCoder:(NSCoder *)coder {
    unsigned version = [coder versionForClassName:@"NSDateFormatter"];
    self = [super initWithCoder:coder];

    if (version > 40) {
        [coder decodeValuesOfObjCTypes:"@c", &_format, &_naturalLanguage];
    } else {
        _format = [[coder decodeObject] retain];
        if (version > 31)
            [coder decodeValuesOfObjCTypes:"c", &_naturalLanguage];
    }

    return self;
}

- (NSString *)stringForObjectValue:(id)object {
    NSDictionary *locale;
    NSTimeZone *timeZone;

    if (![object isKindOfClass:[NSDate class]])
        return nil;

#if defined(__ppc__) || defined(__POWERPC__)
    timeZone = [NSTimeZone localTimeZone];
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
#else
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    timeZone = [NSTimeZone localTimeZone];
#endif
    return [object descriptionWithCalendarFormat:_format
                                        timeZone:timeZone
                                          locale:locale];
}

- (BOOL)getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString **)error {
    NSDictionary *locale;
    NSCalendarDate *date = nil;

    if ([string isEqualToString:@""]) {
        if (object)
            *object = nil;
        return YES;
    }

    NS_DURING
        locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
#if defined(__ppc__) || defined(__POWERPC__)
        date = [NSCalendarDate dateWithString:string calendarFormat:_format];
#else
        date = [NSCalendarDate dateWithString:string calendarFormat:_format locale:locale];
#endif
        if (!date && _naturalLanguage)
            date = (NSCalendarDate *)[NSDate dateWithNaturalLanguageString:string locale:locale];
    NS_HANDLER
        date = nil;
    NS_ENDHANDLER

    if (date) {
        if (object)
            *object = date;
        return YES;
    }

    if (error)
        *error = [_NSFoundationBundle() localizedStringForKey:@"Invalid date string" value:@"" table:nil];
    return NO;
}

@end
