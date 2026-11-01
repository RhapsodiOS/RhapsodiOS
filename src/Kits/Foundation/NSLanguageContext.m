/*	NSLanguageContext.m
	Language-specific Foundation resources
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSLanguageContext.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSSerialization.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSCoder.h>

NSRecursiveLock *__NSLanguageContextLock;

static NSMutableDictionary *NSLanguageContextList;
static NSLanguageContext *NSDefaultLanguageContext;
static NSLanguageContext *NSSystemLanguageContext;
static NSLanguageContext *NSDefaultEnglishLanguageContext;

extern NSDictionary *_NSDefaultEnglishLanguageDict(void);
extern int _NSFileAccessibleForMode(NSString *path, int mode);
extern NSString *_NSFoundationResourceDirectory(void);

static id _NSTempLangDictFromFile(NSString *path) {
    NSString *fallbackPath;
    NSString *resourcePath;
    NSData *data;
    id dictionary;

    if (path == nil)
        return nil;

    fallbackPath = path;
    data = [NSData dataWithContentsOfFile:
        [path stringByAppendingPathExtension:@"splist"]];
    if (data != nil) {
        dictionary = [NSDeserializer
            deserializePropertyListFromData:data mutableContainers:YES];
        if (dictionary != nil)
            return dictionary;
        if ([path hasSuffix:@".splist"])
            fallbackPath = [path stringByDeletingPathExtension];
    }

    dictionary = [NSMutableDictionary dictionaryWithContentsOfFile:fallbackPath];
    if (dictionary != nil)
        return dictionary;

    resourcePath = [[_NSFoundationResourceDirectory()
        stringByAppendingPathComponent:@"Languages"]
        stringByAppendingPathComponent:path];
    fallbackPath = resourcePath;
    data = [NSData dataWithContentsOfFile:
        [resourcePath stringByAppendingPathExtension:@"splist"]];
    if (data != nil) {
        dictionary = [NSDeserializer
            deserializePropertyListFromData:data mutableContainers:YES];
        if (dictionary != nil)
            return dictionary;
        if ([resourcePath hasSuffix:@".splist"])
            fallbackPath = [resourcePath stringByDeletingPathExtension];
    }

    return [NSMutableDictionary dictionaryWithContentsOfFile:fallbackPath];
}

static NSDictionary *_NSUnionOfDictWithAncestors(NSDictionary *dictionary) {
    NSString *parentName;
    NSMutableDictionary *parent;

    if (dictionary == nil)
        return nil;

    parentName = [dictionary objectForKey:@"NSParentContext"];
    if (parentName == nil || [parentName isEqualToString:@""])
        return dictionary;

    parent = _NSTempLangDictFromFile(parentName);
    if (parent == nil)
        return dictionary;

    parent = (NSMutableDictionary *)_NSUnionOfDictWithAncestors(parent);
    [parent addEntriesFromDictionary:dictionary];
    return parent;
}

@interface NSLanguageContext (NSLanguageContextPrivate)
- (id)_initWithDictionary:(NSMutableDictionary *)dictionary;
- (id)initWithContentsOfFile:(NSString *)path;
@end

@implementation NSLanguageContext

+ (id)_langList {
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock lock];
    if (NSLanguageContextList == nil)
        NSLanguageContextList = [[NSMutableDictionary allocWithZone:NULL]
            initWithCapacity:6];
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock unlock];
    return NSLanguageContextList;
}

+ (NSArray *)allTheLanguageContextNamesInstalledOnTheSystem {
    NSString *directory;
    NSFileManager *manager;
    NSArray *contents;
    NSMutableArray *names;
    int index;

#if defined(__ppc__) || defined(__POWERPC__)
    manager = [NSFileManager defaultManager];
    directory = [_NSFoundationResourceDirectory()
        stringByAppendingPathComponent:@"Languages"];
#else
    directory = [_NSFoundationResourceDirectory()
        stringByAppendingPathComponent:@"Languages"];
    manager = [NSFileManager defaultManager];
#endif
    contents = [manager directoryContentsAtPath:directory];
    names = [contents mutableCopyWithZone:NULL];

    for (index = (int)[names count] - 1; index >= 0; index--) {
        NSString *name = [names objectAtIndex:(unsigned)index];
        if ([name hasSuffix:@".splist"] || [name isEqualToString:@"."]
            || [name isEqualToString:@".."]) {
            [names removeObjectAtIndex:(unsigned)index];
        }
    }
    return names;
}

+ (NSArray *)availableLanguageContextNames {
    if (NSLanguageContextList != nil)
        return [NSLanguageContextList allKeys];
    return [NSArray array];
}

+ (NSLanguageContext *)defaultLanguageContext {
    NSArray *names;
    unsigned count;
    unsigned index;

    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock lock];
    if (NSDefaultLanguageContext == nil) {
        names = [[NSUserDefaults standardUserDefaults] arrayForKey:@"NSLanguages"];
        if (names != nil) {
            count = [names count];
            for (index = 0; index < count; index++) {
                NSDefaultLanguageContext = [NSLanguageContext languageContextWithName:
                    [names objectAtIndex:index]];
                if (NSDefaultLanguageContext != nil)
                    break;
            }
        }
        if (NSDefaultLanguageContext == nil)
            NSDefaultLanguageContext = [self systemLanguageContext];
    }
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock unlock];
    return NSDefaultLanguageContext;
}

+ (id)languageContextWithName:(NSString *)name {
    NSString *path;
    NSString *compiledPath;
    NSLanguageContext *context;

    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock lock];

    if ([name isEqualToString:@"English"]) {
        if (NSDefaultEnglishLanguageContext == nil) {
#if defined(__ppc__) || defined(__POWERPC__)
            NSLanguageContext *context =
                [NSLanguageContext allocWithZone:NULL];
            NSMutableDictionary *dictionary = [[_NSDefaultEnglishLanguageDict()
                mutableCopyWithZone:NULL] autorelease];
            NSDefaultEnglishLanguageContext =
                [context _initWithDictionary:dictionary];
#else
            NSMutableDictionary *dictionary = [[_NSDefaultEnglishLanguageDict()
                mutableCopyWithZone:NULL] autorelease];
            NSDefaultEnglishLanguageContext = [[NSLanguageContext
                allocWithZone:NULL] _initWithDictionary:dictionary];
#endif
        }
        if (__NSLanguageContextLock != nil)
            [__NSLanguageContextLock unlock];
        return NSDefaultEnglishLanguageContext;
    }

    context = [NSLanguageContextList objectForKey:name];
    if (context != nil) {
        if (__NSLanguageContextLock != nil)
            [__NSLanguageContextLock unlock];
        return context;
    }

    path = [[_NSFoundationResourceDirectory()
        stringByAppendingPathComponent:@"Languages"]
        stringByAppendingPathComponent:name];
    compiledPath = [path stringByAppendingPathExtension:@"splist"];
    if (_NSFileAccessibleForMode(compiledPath, 4))
        path = compiledPath;

    if (!_NSFileAccessibleForMode(path, 4)) {
        if (__NSLanguageContextLock != nil)
            [__NSLanguageContextLock unlock];
        return nil;
    }

    context = [[NSLanguageContext allocWithZone:NULL]
        initWithContentsOfFile:path];
    if (NSLanguageContextList == nil)
        NSLanguageContextList = [[NSMutableDictionary allocWithZone:NULL]
            initWithCapacity:6];
    [NSLanguageContextList setObject:context forKey:name];
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock unlock];
    return [context autorelease];
}

+ (NSLanguageContext *)systemLanguageContext {
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock lock];
    if (NSSystemLanguageContext == nil) {
        NSSystemLanguageContext = [NSLanguageContext
            languageContextWithName:@".systemLanguage"];
        if (NSSystemLanguageContext == nil)
            NSSystemLanguageContext = [NSLanguageContext
                languageContextWithName:@"English"];
    }
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock unlock];
    return NSSystemLanguageContext;
}

+ (void)setDefaultLanguageContext:(NSLanguageContext *)context {
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock lock];
    if (NSDefaultLanguageContext != context) {
        [NSDefaultLanguageContext release];
        NSDefaultLanguageContext = [context retain];
    }
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock unlock];
}

+ (void)setSystemLanguageContext:(NSLanguageContext *)context {
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock lock];
    if (NSSystemLanguageContext != context) {
        [NSSystemLanguageContext release];
        NSSystemLanguageContext = [context retain];
    }
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock unlock];
}

- (NSDictionary *)_dictionary {
    return _dict;
}

- (id)_initWithDictionary:(NSMutableDictionary *)dictionary {
    _dict = [dictionary retain];
    return self;
}

- (Class)classForCoder {
    return [NSLanguageContext class];
}

- (id)copyWithZone:(NSZone *)zone {
#if defined(__ppc__) || defined(__POWERPC__)
    NSLanguageContext *copy = [NSLanguageContext allocWithZone:NULL];
    NSMutableDictionary *dictionary = [_dict mutableCopyWithZone:NULL];
    return [copy _initWithDictionary:dictionary];
#else
    NSMutableDictionary *dictionary = [_dict mutableCopyWithZone:NULL];
    return [[NSLanguageContext allocWithZone:NULL] _initWithDictionary:dictionary];
#endif
}

- (unsigned)count {
    return [_dict count];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[self languageName]];
}

- (NSString *)formalName {
    return [_dict objectForKey:@"NSFormalName"];
}

- (id)initWithCoder:(NSCoder *)coder {
    NSString *name = [coder decodeObject];
    [self release];
    return [NSLanguageContext languageContextWithName:name];
}

- (id)initWithContentsOfFile:(NSString *)path {
    NSDictionary *dictionary = _NSTempLangDictFromFile(path);
    dictionary = _NSUnionOfDictWithAncestors(dictionary);
    return [self _initWithDictionary:(NSMutableDictionary *)dictionary];
}

- (id)init {
    [super dealloc];
    return nil;
}

- (NSEnumerator *)keyEnumerator {
    return [_dict keyEnumerator];
}

- (NSString *)languageCode {
    return [_dict objectForKey:@"NSLanguageCode"];
}

- (NSString *)languageName {
    return [_dict objectForKey:@"NSLanguageName"];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [[NSLanguageContext allocWithZone:NULL]
        _initWithDictionary:_dict];
}

- (id)objectForKey:(id)key {
    return [_dict objectForKey:key];
}

- (void)removeObjectForKey:(id)key {
    [_dict removeObjectForKey:key];
}

- (void)setObject:(id)object forKey:(id)key {
    [_dict setObject:object forKey:key];
}

@end
