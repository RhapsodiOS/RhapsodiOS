/*	NSLanguageContext.h
	Language-specific Foundation resources
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDictionary.h>

@class NSArray, NSString;

@interface NSLanguageContext : NSMutableDictionary {
@private
    NSMutableDictionary *_dict;
    void *_reserved;
}

+ (id)_langList;
+ (NSArray *)allTheLanguageContextNamesInstalledOnTheSystem;
+ (NSArray *)availableLanguageContextNames;
+ (id)defaultLanguageContext;
+ (id)languageContextWithName:(NSString *)name;
+ (id)systemLanguageContext;
+ (void)setDefaultLanguageContext:(id)context;
+ (void)setSystemLanguageContext:(id)context;

- (NSDictionary *)_dictionary;
- (NSString *)formalName;
- (NSString *)languageCode;
- (NSString *)languageName;

@end
