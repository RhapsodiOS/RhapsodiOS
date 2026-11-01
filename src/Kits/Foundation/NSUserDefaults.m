/*	NSUserDefaults.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSDistributedLock.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSSerialization.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSDecimalNumber.h>
#import <Foundation/NSValue.h>
#import <objc/objc-runtime.h>
#import <mach/cthreads.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

extern id _NSMethodExceptionProem(id object, SEL selector);
extern id _NSDeserializeObject(id serializer, NSData *data, unsigned *cursor,
                               BOOL mutableContainers, NSZone *zone,
                               unsigned lazyThreshold);
extern NSString *NSOpenStepDirectoryForUser(NSString *userName, BOOL create);
extern int _NSCreateDirectory2(char *path);
extern int _NSDeleteFile2(char *path);
extern int _NSRemoveDirectory2(char *path);
extern int _NSFileModificationUNIXTime(NSString *path, BOOL followLink);
extern unsigned NSPushAutoreleasePool();
extern void NSPopAutoreleasePool(unsigned token);

NSString * const NSGlobalDomain = @"NSGlobalDomain";
NSString * const NSArgumentDomain = @"NSArgumentDomain";
NSString * const NSRegistrationDomain = @"NSRegistrationDomain";
NSString * const NSUserDefaultsDidChangeNotification = @"NSUserDefaultsDidChangeNotification";
NSString * const NSWeekDayNameArray = @"NSWeekDayNameArray";
NSString * const NSShortWeekDayNameArray = @"NSShortWeekDayNameArray";
NSString * const NSMonthNameArray = @"NSMonthNameArray";
NSString * const NSShortMonthNameArray = @"NSShortMonthNameArray";
NSString * const NSTimeFormatString = @"NSTimeFormatString";
NSString * const NSDateFormatString = @"NSDateFormatString";
NSString * const NSTimeDateFormatString = @"NSTimeDateFormatString";
NSString * const NSShortTimeDateFormatString = @"NSShortTimeDateFormatString";
NSString * const NSCurrencySymbol = @"NSCurrencySymbol";
NSString * const NSDecimalSeparator = @"NSDecimalSeparator";
NSString * const NSThousandsSeparator = @"NSThousandsSeparator";
NSString * const NSDecimalDigits = @"NSDecimalDigits";
NSString * const NSAMPMDesignation = @"NSAMPMDesignation";
NSString * const NSHourNameDesignations = @"NSHourNameDesignations";
NSString * const NSYearMonthWeekDesignations = @"NSYearMonthWeekDesignations";
NSString * const NSEarlierTimeDesignations = @"NSEarlierTimeDesignations";
NSString * const NSLaterTimeDesignations = @"NSLaterTimeDesignations";
NSString * const NSThisDayDesignations = @"NSThisDayDesignations";
NSString * const NSNextDayDesignations = @"NSNextDayDesignations";
NSString * const NSNextNextDayDesignations = @"NSNextNextDayDesignations";
NSString * const NSPriorDayDesignations = @"NSPriorDayDesignations";
NSString * const NSDateTimeOrdering = @"NSDateTimeOrdering";
NSString * const NSInternationalCurrencyString = @"NSInternationalCurrencyString";
NSString * const NSShortDateFormatString = @"NSShortDateFormatString";
NSString * const NSPositiveCurrencyFormatString = @"NSPositiveCurrencyFormatString";
NSString * const NSNegativeCurrencyFormatString = @"NSNegativeCurrencyFormatString";

static NSUserDefaults *NSUserDefaultsStandard;
#if defined(__ppc__) || defined(__POWERPC__)
unsigned int __NSConvertOldDefaults;
#endif
NSLock *_NSUserDefaultsLock;
extern NSRecursiveLock *__NSLanguageContextLock;
static BOOL NSUserDefaultsCreatingStandard;
static NSArray *NSUserDefaultsNonDefaultArguments;
static NSArray *NSUserDefaultsDefaultArguments;
static id NSUserDefaultsAllKeysMarker = @"All keys must be replaced";

static id NSUserDefaultsDirtyKeysMarker(void) {
    return [NSArray array];
}

NSDictionary *
_NSDefaultEnglishLanguageDict(void)
{
    static NSDictionary *english;

    if (english != nil)
        return english;
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock lock];
    if (english == nil) {
        NSArray *weekdays = [NSArray arrayWithObjects:
            @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday",
            @"Friday", @"Saturday", nil];
        NSArray *shortWeekdays = [NSArray arrayWithObjects:
            @"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat", nil];
        NSArray *months = [NSArray arrayWithObjects:
            @"January", @"February", @"March", @"April", @"May", @"June",
            @"July", @"August", @"September", @"October", @"November",
            @"December", nil];
        NSArray *shortMonths = [NSArray arrayWithObjects:
            @"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun", @"Jul",
            @"Aug", @"Sep", @"Oct", @"Nov", @"Dec", nil];
        NSArray *ampm = [NSArray arrayWithObjects:@"AM", @"PM", nil];
        NSArray *hourNames = [NSArray arrayWithObjects:
            [NSArray arrayWithObjects:@"0", @"midnight", nil],
            [NSArray arrayWithObjects:@"10", @"morning", nil],
            [NSArray arrayWithObjects:@"12", @"noon", @"lunch", nil],
            [NSArray arrayWithObjects:@"14", @"afternoon", nil],
            [NSArray arrayWithObjects:@"19", @"dinner", nil], nil];
        NSArray *unitNames = [NSArray arrayWithObjects:
            [NSArray arrayWithObjects:@"1", @"year", @"years", nil],
            [NSArray arrayWithObjects:@"2", @"month", @"months", nil],
            [NSArray arrayWithObjects:@"3", @"week", @"weeks", nil], nil];
        NSArray *earlier = [NSArray arrayWithObjects:
            @"prior", @"last", @"past", @"ago", nil];
        NSArray *later = [NSArray arrayWithObject:@"next"];
        NSArray *priorDay = [NSArray arrayWithObject:@"yesterday"];
        NSArray *thisDay = [NSArray arrayWithObjects:@"today", @"now", nil];
        NSArray *nextDay = [NSArray arrayWithObject:@"tomorrow"];
        NSArray *nextNextDay = [NSArray arrayWithObjects:@"nextday", @"next", nil];

        english = [[NSDictionary alloc] initWithObjectsAndKeys:
            weekdays, NSWeekDayNameArray,
            shortWeekdays, NSShortWeekDayNameArray,
            months, NSMonthNameArray,
            shortMonths, NSShortMonthNameArray,
            @"%H:%M:%S", NSTimeFormatString,
            @"%A, %B %d, %Y", NSDateFormatString,
            @"%A, %B %d, %Y %H:%M:%S %Z", NSTimeDateFormatString,
            @"%d %b %Y %I:%M %p", NSShortTimeDateFormatString,
            @"$", NSCurrencySymbol,
            @".", NSDecimalSeparator,
            @",", NSThousandsSeparator,
            @"0123456789", NSDecimalDigits,
            ampm, NSAMPMDesignation,
            hourNames, NSHourNameDesignations,
            unitNames, NSYearMonthWeekDesignations,
            earlier, NSEarlierTimeDesignations,
            later, NSLaterTimeDesignations,
            thisDay, NSThisDayDesignations,
            nextDay, NSNextDayDesignations,
            nextNextDay, NSNextNextDayDesignations,
            priorDay, NSPriorDayDesignations,
            @"MDYH", NSDateTimeOrdering,
            @"USD", NSInternationalCurrencyString,
            @"%d %b %Y", NSShortDateFormatString,
            @"$9,999.00", NSPositiveCurrencyFormatString,
            @"-$9,999.00", NSNegativeCurrencyFormatString,
            nil];
    }
    if (__NSLanguageContextLock != nil)
        [__NSLanguageContextLock unlock];
    return english;
}

@interface NSLockedPropertyListFile : NSObject {
@public
    NSString *_path;
    NSString *_user;
    NSMutableDictionary *_cache;
    BOOL _changedEffectiveUser;
    NSZone *_zone;
}
- (id)initWithPath:(NSString *)path;
- (NSArray *)allDomains;
- (NSDictionary *)dictionaryForDomain:(NSString *)domain;
- (BOOL)domainExists:(NSString *)domain;
- (id)objectForKey:(NSString *)key domain:(NSString *)domain;
- (void)setObject:(id)object forKey:(NSString *)key domain:(NSString *)domain;
- (void)removeObjectForKey:(NSString *)key domain:(NSString *)domain;
- (void)setDictionary:(NSDictionary *)dictionary forDomain:(NSString *)domain;
- (void)removeDomain:(NSString *)domain;
- (BOOL)synchronize;
@end

@interface NSNonsavingDefaultsManager : NSObject {
@public
    NSMutableDictionary *_domains;
}
- (id)initWithPath:(NSString *)path;
- (NSArray *)allDomains;
- (NSDictionary *)dictionaryForDomain:(NSString *)domain;
- (BOOL)domainExists:(NSString *)domain;
- (id)objectForKey:(NSString *)key domain:(NSString *)domain;
- (void)setObject:(id)object forKey:(NSString *)key domain:(NSString *)domain;
- (void)removeObjectForKey:(NSString *)key domain:(NSString *)domain;
- (void)setDictionary:(NSDictionary *)dictionary forDomain:(NSString *)domain;
- (void)removeDomain:(NSString *)domain;
- (BOOL)synchronize;
@end

@interface NSFileManager (NSUserDefaultsPrivate)
- (BOOL)getFileSystemRepresentation:(char *)buffer maxLength:(unsigned)length
                           withPath:(NSString *)path;
@end

@interface NSNotificationCenter (NSUserDefaultsPrivate)
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)info;
@end

/*  The public object has a fixed five-word instance layout in the 32-bit
    Foundation ABI.  The C helper mirrors that layout so every mutator can
    rebuild the same precedence-ordered dictionary without adding a private
    Objective-C selector to NSUserDefaults' method table.  */
typedef struct {
    Class isa;
    id defaultsManager;
    NSArray *searchList;
    NSDictionary *temporaryDomains;
    NSDictionary *dictionaryRepresentation;
} NSUserDefaultsLayout;

static id
computeDictRep(NSUserDefaults *defaults, NSArray *searchList, NSZone *zone)
{
    NSUserDefaultsLayout *layout = (NSUserDefaultsLayout *)defaults;
    unsigned count = [searchList count];
    unsigned pool;
    id stackDomains[128];
    id *domains = stackDomains;
    NSMutableDictionary *result;
    unsigned index;

    if (count == 0)
        return nil;

    pool = NSPushAutoreleasePool(4);
    if (count > 128)
        domains = NSZoneMalloc(NULL, count * sizeof(id));
    [searchList getObjects:domains range:NSMakeRange(0, count)];
    result = [[NSMutableDictionary allocWithZone:zone] initWithCapacity:256];
    if ([NSRegistrationDomain isEqualToString:domains[count - 1]])
        count--;
    index = count;
    while (index != 0) {
        NSString *domain = domains[--index];
        NSDictionary *values = [layout->temporaryDomains objectForKey:domain];

        if (values == nil)
            values = [layout->defaultsManager dictionaryForDomain:domain];
        if (values != nil)
            [result addEntriesFromDictionary:values];
    }
    if (domains != stackDomains)
        NSZoneFree(NULL, domains);
    NSPopAutoreleasePool(pool);
    return result;
}

static id
NSUserDefaultsValueForKey(NSUserDefaults *defaults, NSString *key)
{
    NSUserDefaultsLayout *layout = (NSUserDefaultsLayout *)defaults;
    id value = [layout->dictionaryRepresentation objectForKey:key];

    if (value == nil
        && [NSRegistrationDomain isEqualToString:[layout->searchList lastObject]])
        value = [[layout->temporaryDomains objectForKey:NSRegistrationDomain]
            objectForKey:key];
    return value;
}

static void
NSUserDefaultsPostChange(id object)
{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSUserDefaultsDidChangeNotification object:object userInfo:nil];
}

static BOOL
NSUserDefaultsSetReservedObject(NSUserDefaults *defaults, id value,
                                NSString *key)
{
    NSUserDefaultsLayout *layout = (NSUserDefaultsLayout *)defaults;
    BOOL searched;

    [layout->defaultsManager setObject:value forKey:key
                               domain:(NSString *)layout->reserved];
    searched = [layout->searchList containsObject:(NSString *)layout->reserved];
    if (searched) {
        [layout->dictionaryRepresentation release];
        layout->dictionaryRepresentation = computeDictRep(defaults,
                                                            layout->searchList,
                                                            NULL);
    }
    return searched;
}

int
_NSIsPList(id object, BOOL recursively)
{
    unsigned index;

    if (object == nil)
        return 0;
    if ([object isKindOfClass:[NSString class]])
        return 1;
    if ([object isKindOfClass:[NSData class]])
        return 2;
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = object;

        if (recursively) {
            for (index = 0; index < [array count]; index++)
                if (!_NSIsPList([array objectAtIndex:index], YES))
                    return 0;
        }
        return 3;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = object;

        if (recursively) {
            NSEnumerator *keys = [dictionary keyEnumerator];
            id key;

            while ((key = [keys nextObject]) != nil) {
                if (!_NSIsPList(key, YES)
                    || !_NSIsPList([dictionary objectForKey:key], YES))
                    return 0;
            }
        }
        return 4;
    }
    return 0;
}

static time_t
NSUserDefaultsCurrentUNIXTime(void)
{
    struct timeval time;

    gettimeofday(&time, NULL);
    return time.tv_sec;
}

static time_t
NSUserDefaultsFileSystemUNIXTime(NSString *path)
{
    char filePath[1028];
    struct stat status;
    time_t result = 0;

    if (![path getFileSystemRepresentation:filePath maxLength:1024])
        return 0;

    (void)_NSCreateDirectory2(filePath);
    if (stat(filePath, &status) == 0)
        result = status.st_mtime;
    (void)_NSRemoveDirectory2(filePath);

    return result;
}

int
_NSCurrentFileSystemUNIXTime(NSString *path)
{
    return (int)NSUserDefaultsFileSystemUNIXTime(path);
}

static void
NSUserDefaultsSleepMilliseconds(unsigned milliseconds)
{
    usleep(milliseconds * 1000);
}

static kern_return_t
NSUserDefaultsResumeOtherThreads(thread_t currentThread)
{
    thread_act_array_t threads;
    mach_msg_type_number_t count;
    mach_msg_type_number_t index;
    kern_return_t result;

    result = task_threads(task_self(), &threads, &count);
    if (result != KERN_SUCCESS)
        return result;
    for (index = 0; index < count; index++) {
        if (threads[index] != currentThread)
            thread_resume(threads[index]);
    }
    return vm_deallocate(task_self(), (vm_address_t)threads,
                         sizeof(thread_t) * count);
}

static BOOL
NSUserDefaultsGrabLock(NSLockedPropertyListFile *store, SEL selector,
                       NSString *domain)
{
    NSFileManager *manager;
    NSString *domainPath;
    NSString *lockPath;
    char filePath[1028];
    BOOL adjustedClock = NO;
    time_t filesystemOffset = 0;
    unsigned attempts = 0;

    domainPath = [store->_path stringByAppendingPathComponent:domain];
    lockPath = [domainPath stringByAppendingPathExtension:@"lock"];
    manager = [NSFileManager defaultManager];
    if (![manager getFileSystemRepresentation:filePath maxLength:1024 withPath:lockPath]) {
        NSLog(@"%@: Could not grab lock for %@: conversion error",
              _NSMethodExceptionProem(store, selector), domain);
        return NO;
    }
    if (geteuid() == 0 && getuid() != 0) {
        thread_t currentThread = thread_self();
        thread_act_array_t threads;
        mach_msg_type_number_t count;
        mach_msg_type_number_t index;

        if (task_threads(task_self(), &threads, &count) != KERN_SUCCESS)
            return NO;
        for (index = 0; index < count; index++) {
            if (threads[index] != currentThread)
                thread_suspend(threads[index]);
        }
        vm_deallocate(task_self(), (vm_address_t)threads,
                      sizeof(thread_t) * count);
        seteuid(getuid());
        store->_changedEffectiveUser = YES;
    }

    for (;;) {
        if (_NSCreateDirectory2(filePath))
            return YES;
        if (cthread_errno() != EEXIST)
            break;
        NSUserDefaultsSleepMilliseconds(300);
        if (++attempts > 0x4A) {
            if (!adjustedClock) {
                NSString *timePath = [lockPath stringByAppendingPathExtension:@"time"];
                filesystemOffset = NSUserDefaultsFileSystemUNIXTime(timePath)
                    - NSUserDefaultsCurrentUNIXTime();
                adjustedClock = YES;
            }
            {
                struct stat status;
                time_t currentFileTime = NSUserDefaultsCurrentUNIXTime() + filesystemOffset;

                if (stat(filePath, &status) == 0 && status.st_mtime != 0
                    && currentFileTime > status.st_mtime + 21) {
                    chmod(filePath, 0700);
                    rmdir(filePath);
                }
            }
        }
    }

    if (store->_changedEffectiveUser) {
        thread_t currentThread = thread_self();
        seteuid(0);
        store->_changedEffectiveUser = NO;
        NSUserDefaultsResumeOtherThreads(currentThread);
    }
    return NO;
}

kern_return_t
_NSReleaseLock(NSLockedPropertyListFile *store, SEL selector, NSString *domain)
{
    NSFileManager *manager;
    NSString *domainPath;
    NSString *lockPath;
    char filePath[1028];
    kern_return_t result = KERN_SUCCESS;

#if defined(__ppc__) || defined(__POWERPC__)
    manager = [NSFileManager defaultManager];
    domainPath = [store->_path stringByAppendingPathComponent:domain];
    lockPath = [domainPath stringByAppendingPathExtension:@"lock"];
#else
    domainPath = [store->_path stringByAppendingPathComponent:domain];
    lockPath = [domainPath stringByAppendingPathExtension:@"lock"];
    manager = [NSFileManager defaultManager];
#endif
    (void)selector;
    if ([manager getFileSystemRepresentation:filePath maxLength:1024 withPath:lockPath]) {
        chmod(filePath, 0700);
        result = _NSRemoveDirectory2(filePath);
    }
    if (store->_changedEffectiveUser) {
        thread_t currentThread = thread_self();
        seteuid(0);
        store->_changedEffectiveUser = NO;
        result = NSUserDefaultsResumeOtherThreads(currentThread);
    }
    return result;
}

static NSString *
NSUserDefaultsPropertyListPath(NSLockedPropertyListFile *store, NSString *domain)
{
    return [store->_path stringByAppendingPathComponent:
        [domain stringByAppendingPathExtension:@"plist"]];
}

static void
NSUserDefaultsConvertOldDefaultsToNew2(NSLockedPropertyListFile *store,
                                       SEL selector, NSString *path)
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *legacyGlobal = [path stringByAppendingPathComponent:
        @"NSGlobalDomain.defaults"];
    NSMutableArray *domains;
    int index;

    if ([manager fileExistsAtPath:legacyGlobal])
        return;
#if defined(__ppc__) || defined(__POWERPC__)
    NSLog(@"Converting old domain files to new domain files");
#endif
    domains = [[manager directoryContentsAtPath:path] mutableCopy];
    if (domains == nil)
        return;
    for (index = (int)[domains count] - 1; index >= 0; index--) {
        NSString *name = [domains objectAtIndex:index];
        if ([name hasSuffix:@".lock"] || [name hasSuffix:@".time"]
            || [name hasSuffix:@".defaults"] || [name hasPrefix:@"."])
            [domains removeObjectAtIndex:index];
    }
    for (index = (int)[domains count] - 1; index >= 0; index--) {
        NSString *domain = [domains objectAtIndex:index];
        NSString *oldPath = [path stringByAppendingPathComponent:domain];
        NSString *newPath = [path stringByAppendingPathComponent:
            [domain stringByAppendingPathExtension:@"plist"]];

        if (NSUserDefaultsGrabLock(store, selector, domain)) {
            if (![manager isReadableFileAtPath:newPath])
                [manager copyPath:oldPath toPath:newPath handler:nil];
            _NSReleaseLock(store, NULL, domain);
        }
    }
    [domains release];
}

static BOOL
NSUserDefaultsGrabLegacyLock(NSString *lockPath, NSDistributedLock **lockOut)
{
    NSString *staleLockPath = [lockPath stringByAppendingPathExtension:@"time"];
    NSDistributedLock *lock = [NSDistributedLock lockWithPath:lockPath];
    char filePath[1028];

    *lockOut = lock;
    if (lock == nil || ![staleLockPath getFileSystemRepresentation:filePath
                                                        maxLength:1024])
        return NO;

    for (;;) {
        unsigned int lockTime = 0;
        unsigned int probeTime = 0;

        while (![lock tryLock]) {
            struct stat status;

            NSUserDefaultsSleepMilliseconds(300);
            _NSCreateDirectory2(filePath);
            probeTime = 0;
            if (stat(filePath, &status) == 0)
                probeTime = (unsigned int)status.st_mtime;
            _NSRemoveDirectory2(filePath);
            lockTime = (unsigned int)_NSFileModificationUNIXTime(lockPath, YES);
            if (lockTime != 0 && probeTime >= lockTime + 21)
                break;
        }
        if (lockTime == 0 || probeTime < lockTime + 30)
            break;
        [lock breakLock];
    }
    return YES;
}

static BOOL
NSUserDefaultsConvertOldDefaultsToNew(NSLockedPropertyListFile *store,
                                      SEL selector, NSString *defaultsPath)
{
    NSFileManager *manager;
    NSString *libraryPath = [defaultsPath stringByDeletingLastPathComponent];
#if defined(__ppc__) || defined(__POWERPC__)
    NSString *legacyPath = [libraryPath stringByAppendingPathComponent:@"UserDefaults"];
#else
    NSString *legacyPath = libraryPath;
#endif
    NSString *lockPath = [legacyPath stringByAppendingPathComponent:@"lock"];
    NSString *legacyGlobal;
    NSString *legacyDataPath;
    NSDistributedLock *lock;
    NSData *data;
    unsigned cursor = 0;
    NSDictionary *legacyDomains = nil;
    BOOL deserializationFailed = NO;

    if (!NSUserDefaultsGrabLegacyLock(lockPath, &lock))
        return YES;
#if defined(__ppc__) || defined(__POWERPC__)
    manager = [NSFileManager defaultManager];
#endif
    legacyGlobal = [defaultsPath stringByAppendingPathComponent:
        @"NSGlobalDomain.defaults"];
#if !defined(__ppc__) && !defined(__POWERPC__)
    manager = [NSFileManager defaultManager];
#endif
    if ([manager fileExistsAtPath:legacyGlobal]) {
        [lock unlock];
        return YES;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    NSLog(@"Converting old defaults file to new defaults files");
#endif
    legacyDataPath = [legacyPath stringByAppendingPathComponent:@"data"];
    manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:legacyDataPath]) {
        [lock unlock];
        return YES;
    }
    data = [[NSData allocWithZone:NULL]
        initWithContentsOfFile:legacyDataPath];
    if (data == nil) {
        [lock unlock];
        return NO;
    }
    manager = [NSFileManager defaultManager];
    [manager removeFileAtPath:legacyDataPath handler:nil];
    NS_DURING
        legacyDomains = _NSDeserializeObject(nil, data, &cursor, NO, NULL, 0);
    NS_HANDLER
        NSLog(@"%@: Defaults can not convert old style defaults to new style",
              _NSMethodExceptionProem(store, selector), legacyDataPath);
        deserializationFailed = YES;
    NS_ENDHANDLER
    if (deserializationFailed) {
        [lock unlock];
        return NO;
    }
    {
        NSEnumerator *keys = [legacyDomains keyEnumerator];
        id domain;

        while ((domain = [keys nextObject]) != nil) {
            NSDictionary *values;
            NSString *oldDomainPath;

            if ([domain isEqualToString:@""])
                continue;
            values = [legacyDomains objectForKey:domain];
            if ([values count] == 0)
                continue;
#if defined(__ppc__) || defined(__POWERPC__)
            manager = [NSFileManager defaultManager];
#endif
            oldDomainPath = [defaultsPath stringByAppendingPathComponent:
                [domain stringByAppendingPathExtension:@"defaults"]];
#if !defined(__ppc__) && !defined(__POWERPC__)
            manager = [NSFileManager defaultManager];
#endif
            if (![manager isReadableFileAtPath:oldDomainPath])
                [store setDictionary:values forDomain:domain];
        }
    }
    [lock unlock];
    [legacyDomains release];
    [data release];
    return YES;
}

static BOOL
NSUserDefaultsValidDomain(id domain, id object, SEL selector)
{
    if (domain != nil && ![domain isEqualToString:@""])
        return YES;
    [NSException raise:NSInvalidArgumentException
                format:@"%@: domain name cannot be nil or empty",
                       _NSMethodExceptionProem(object, selector)];
    return NO;
}

@implementation NSLockedPropertyListFile

- (id)initWithPath:(NSString *)path {
    NSFileManager *manager;
    NSString *parent;
    NSDictionary *parentAttributes;
    BOOL isDirectory = NO;

#if defined(__ppc__) || defined(__POWERPC__)
    manager = [NSFileManager defaultManager];
    parent = [path stringByDeletingLastPathComponent];
#else
    parent = [path stringByDeletingLastPathComponent];
    manager = [NSFileManager defaultManager];
#endif
    parentAttributes = [manager fileAttributesAtPath:parent traverseLink:YES];
    manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
        /* The defaults directory already exists. */
    } else {
        id owner;
        NSNumber *permissions;
        NSDictionary *attributes;

#if defined(__ppc__) || defined(__POWERPC__)
        owner = [parentAttributes objectForKey:NSFileOwnerAccountName];
        permissions = [NSNumber numberWithUnsignedLong:493];
#else
        permissions = [NSNumber numberWithUnsignedLong:493];
        owner = [parentAttributes objectForKey:NSFileOwnerAccountName];
#endif
        attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            owner, NSFileOwnerAccountName,
            permissions, NSFilePosixPermissions, nil];
        manager = [NSFileManager defaultManager];
        [manager removeFileAtPath:path handler:nil];
        manager = [NSFileManager defaultManager];
        if (![manager createDirectoryAtPath:path attributes:attributes]) {
            [self release];
            return nil;
        }
    }
    _zone = NSZoneFromPointer(self);
    _path = [path copyWithZone:_zone];
    _user = [[parentAttributes objectForKey:NSFileOwnerAccountName] retain];
    _cache = [[NSMutableDictionary allocWithZone:_zone] init];
#if defined(__ppc__) || defined(__POWERPC__)
    if (__NSConvertOldDefaultsToNew) {
        NSUserDefaultsConvertOldDefaultsToNew2(self, _cmd, _path);
        if (!NSUserDefaultsConvertOldDefaultsToNew(self, _cmd, _path))
            NSLog(@"%@ could not convert old defaults", _NSMethodExceptionProem(self, _cmd));
    }
    return self;
#else
    NSUserDefaultsConvertOldDefaultsToNew2(self, _cmd, _path);
    if (!NSUserDefaultsConvertOldDefaultsToNew(self, _cmd, _path)) {
        NSLog(@"%@ could not convert old defaults", _NSMethodExceptionProem(self, _cmd));
        [self release];
        return nil;
    }
    return self;
#endif
}

- (id)_dictionaryForDomain:(NSString *)domain {
    NSString *path = NSUserDefaultsPropertyListPath(self, domain);
    NSData *data = [[NSData allocWithZone:_zone]
        initWithContentsOfFile:path];
    unsigned cursor = 0;
    id dictionary;

    if (data == nil)
        return nil;
    if ([data length] == 0) {
        [self removeDomain:domain];
        return nil;
    }
    NS_DURING
        dictionary = [NSDeserializer deserializePropertyListFromData:data
                                                               atCursor:&cursor
                                                     mutableContainers:NO];
    NS_HANDLER
        NSLog(@"%@ could not read defaults domain %@",
              _NSMethodExceptionProem(self, _cmd), path);
        dictionary = nil;
    NS_ENDHANDLER
    [data release];
    return dictionary;
}

- (void)cacheDictionary:(NSDictionary *)dictionary forDomain:(NSString *)domain {
    NSMutableDictionary *cached = [dictionary mutableCopyWithZone:_zone];
    NSMutableArray *dirtyKeys = [NSMutableArray array];

    [cached setObject:dirtyKeys forKey:NSUserDefaultsDirtyKeysMarker()];
    [_cache setObject:cached forKey:domain];
    [cached release];
}

- (NSDictionary *)dictionaryForDomain:(NSString *)domain {
    NSMutableDictionary *cached;

    NSUserDefaultsValidDomain(domain, self, _cmd);
    cached = [_cache objectForKey:domain];
    if (cached == nil) {
        NSDictionary *dictionary = nil;

        if (NSUserDefaultsGrabLock(self, _cmd, domain)) {
            dictionary = [self _dictionaryForDomain:domain];
            _NSReleaseLock(self, _cmd, domain);
            if (dictionary != nil)
                [self cacheDictionary:dictionary forDomain:domain];
        }
        return dictionary;
    }
    if ([cached count] == 0)
        return nil;
    {
        id marker = [[cached objectForKey:NSUserDefaultsDirtyKeysMarker()] retain];
        NSDictionary *copy;

        [cached removeObjectForKey:NSUserDefaultsDirtyKeysMarker()];
        copy = [NSDictionary dictionaryWithDictionary:cached];
        [cached setObject:marker forKey:NSUserDefaultsDirtyKeysMarker()];
        [marker release];
        return copy;
    }
}

- (id)objectForKey:(NSString *)key domain:(NSString *)domain {
    NSDictionary *dictionary;

    NSUserDefaultsValidDomain(domain, self, _cmd);
    dictionary = [_cache objectForKey:domain];
    if (dictionary == nil) {
        if (!NSUserDefaultsGrabLock(self, _cmd, domain))
            return nil;
        dictionary = [self _dictionaryForDomain:domain];
        _NSReleaseLock(self, _cmd, domain);
        if (dictionary != nil)
            [self cacheDictionary:dictionary forDomain:domain];
    }
    return [dictionary objectForKey:key];
}

- (void)setObject:(id)object forKey:(NSString *)key domain:(NSString *)domain {
    NSMutableDictionary *cached;
    id dirtyKeys;

    NSUserDefaultsValidDomain(domain, self, _cmd);
    cached = [_cache objectForKey:domain];
    if (cached == nil) {
        NSDictionary *dictionary = nil;
        if (!NSUserDefaultsGrabLock(self, _cmd, domain))
            return;
        dictionary = [self _dictionaryForDomain:domain];
        _NSReleaseLock(self, _cmd, domain);
        if (dictionary == nil)
            dictionary = [NSDictionary dictionary];
        [self cacheDictionary:dictionary forDomain:domain];
        cached = [_cache objectForKey:domain];
    }
    [cached setObject:object forKey:key];
    dirtyKeys = [cached objectForKey:NSUserDefaultsDirtyKeysMarker()];
    if (dirtyKeys == nil) {
        [cached setObject:[NSArray arrayWithObjects:NSUserDefaultsAllKeysMarker, nil]
                   forKey:NSUserDefaultsDirtyKeysMarker()];
    } else if ([dirtyKeys count] == 0
               || [dirtyKeys objectAtIndex:0] != NSUserDefaultsAllKeysMarker) {
        if ([dirtyKeys indexOfObject:key] == NSNotFound)
            [dirtyKeys addObject:key];
    }
}

- (void)removeObjectForKey:(NSString *)key domain:(NSString *)domain {
    NSMutableDictionary *cached;
    id dirtyKeys;

    NSUserDefaultsValidDomain(domain, self, _cmd);
    cached = [_cache objectForKey:domain];
    if (cached == nil) {
        NSDictionary *dictionary;
        if (!NSUserDefaultsGrabLock(self, _cmd, domain))
            return;
        dictionary = [self _dictionaryForDomain:domain];
        _NSReleaseLock(self, _cmd, domain);
        if (dictionary == nil)
            return;
        [self cacheDictionary:dictionary forDomain:domain];
        cached = [_cache objectForKey:domain];
    }
    [cached removeObjectForKey:key];
    dirtyKeys = [cached objectForKey:NSUserDefaultsDirtyKeysMarker()];
    if (dirtyKeys != nil && ([dirtyKeys count] == 0
               || [dirtyKeys objectAtIndex:0] != NSUserDefaultsAllKeysMarker)) {
        if ([dirtyKeys indexOfObject:key] == NSNotFound)
            [dirtyKeys addObject:key];
    }
}

- (void)setDictionary:(NSDictionary *)dictionary forDomain:(NSString *)domain {
    NSMutableDictionary *cached;

    NSUserDefaultsValidDomain(domain, self, _cmd);
    [self cacheDictionary:dictionary forDomain:domain];
    cached = [_cache objectForKey:domain];
    [cached setObject:[NSArray arrayWithObjects:NSUserDefaultsAllKeysMarker, nil]
               forKey:NSUserDefaultsDirtyKeysMarker()];
}

- (void)removeDomain:(NSString *)domain {
    NSUserDefaultsValidDomain(domain, self, _cmd);
    [_cache setObject:[NSMutableDictionary dictionary] forKey:domain];
}

- (BOOL)domainExists:(NSString *)domain {
    NSFileManager *manager;
    NSString *path;
    NSMutableDictionary *cached;

    NSUserDefaultsValidDomain(domain, self, _cmd);
    cached = [_cache objectForKey:domain];
    if (cached != nil)
        return [cached count] != 0;
#if defined(__ppc__) || defined(__POWERPC__)
    manager = [NSFileManager defaultManager];
    path = NSUserDefaultsPropertyListPath(self, domain);
#else
    path = NSUserDefaultsPropertyListPath(self, domain);
    manager = [NSFileManager defaultManager];
#endif
    return [manager fileExistsAtPath:path];
}

- (NSArray *)allDomains {
    NSFileManager *manager;
    NSArray *cachedDomains;
    NSArray *directoryContents;
    NSMutableArray *domains;
    int index;

    cachedDomains = [_cache allKeys];
    manager = [NSFileManager defaultManager];
    directoryContents = [manager directoryContentsAtPath:_path];
    domains = [directoryContents mutableCopyWithZone:_zone];

    for (index = (int)[domains count] - 1; index >= 0; index--) {
        NSString *name = [domains objectAtIndex:index];
        if (![name hasSuffix:@".plist"] || [name hasPrefix:@"."])
            [domains removeObjectAtIndex:index];
        else
            [domains replaceObjectAtIndex:index withObject:[name stringByDeletingPathExtension]];
    }
    for (index = 0; index < (int)[cachedDomains count]; index++) {
        NSString *domain = [cachedDomains objectAtIndex:index];
        BOOL exists = [[_cache objectForKey:domain] count] != 0;
        unsigned position = domains != nil
            ? [domains indexOfObject:domain] : NSNotFound;

        if (exists && position == NSNotFound) {
            if (domains == nil)
                domains = [[NSMutableArray allocWithZone:_zone]
                    initWithObjects:domain, nil];
            else
                [domains addObject:domain];
        } else if (!exists && position != NSNotFound)
            [domains removeObjectAtIndex:position];
    }
    {
        NSArray *result = domains != nil
            ? [NSArray arrayWithArray:domains] : [NSArray array];
        [domains release];
        return result;
    }
}

- (void)_setDictionary:(NSDictionary *)dictionary forDomain:(NSString *)domain {
    NSFileManager *manager;
    NSString *path = NSUserDefaultsPropertyListPath(self, domain);
    NSMutableData *data = [[NSMutableData allocWithZone:_zone] initWithCapacity:0x2000];
    NSDictionary *oldAttributes;
    NSNumber *permissions;
    unsigned attempt;

    [NSSerializer serializePropertyList:dictionary intoData:data];
    manager = [NSFileManager defaultManager];
    oldAttributes = [manager fileAttributesAtPath:path traverseLink:YES];
    permissions = [oldAttributes objectForKey:NSFilePosixPermissions];
    if (permissions == nil)
        permissions = [NSNumber numberWithUnsignedLong:384];
    for (attempt = 0; attempt < 3; attempt++) {
        if ([data writeToFile:path atomically:YES]) {
            NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                permissions, NSFilePosixPermissions,
                _user, NSFileOwnerAccountName, nil];
            manager = [NSFileManager defaultManager];
            [manager changeFileAttributes:attributes atPath:path];
            manager = [NSFileManager defaultManager];
            if ([data length] <= [[manager fileAttributesAtPath:path traverseLink:YES] fileSize])
                break;
        } else {
            NSString *proem;
            int savedErrno;
#if defined(__ppc__) || defined(__POWERPC__)
            proem = _NSMethodExceptionProem(self, _cmd);
            savedErrno = cthread_errno();
#else
            savedErrno = cthread_errno();
            proem = _NSMethodExceptionProem(self, _cmd);
#endif
            NSLog(@"%@: Could not write to %@: %d", proem, path, savedErrno);
        }
    }
    if (attempt == 3)
        NSLog(@"%@: Could not write data, giving up on %@",
              _NSMethodExceptionProem(self, _cmd), path);
    [data release];
}

- (void)_removeDomain:(NSString *)domain {
    NSString *path;
    NSFileManager *manager;
    char filePath[1028];

#if defined(__ppc__) || defined(__POWERPC__)
    manager = [NSFileManager defaultManager];
#endif
    path = NSUserDefaultsPropertyListPath(self, domain);
#if !defined(__ppc__) && !defined(__POWERPC__)
    manager = [NSFileManager defaultManager];
#endif
    if ([manager getFileSystemRepresentation:filePath maxLength:1024 withPath:path]) {
        chmod(filePath, 0700);
        _NSDeleteFile2(filePath);
    }
}

- (BOOL)synchronize {
    NSArray *domains = [_cache allKeys];
    BOOL success = YES;
    unsigned index;

    for (index = 0; index < [domains count]; index++) {
        NSString *domain = [domains objectAtIndex:index];
        NSMutableDictionary *cached = [_cache objectForKey:domain];
        NSArray *dirtyKeys = [cached objectForKey:NSUserDefaultsDirtyKeysMarker()];

        if (dirtyKeys == nil) {
            if (NSUserDefaultsGrabLock(self, _cmd, domain)) {
                [self _removeDomain:domain];
                [_cache removeObjectForKey:domain];
                _NSReleaseLock(self, _cmd, domain);
            } else {
                success = NO;
            }
            continue;
        }
        if ([dirtyKeys count] == 0) {
            [_cache removeObjectForKey:domain];
            continue;
        }
        if (!NSUserDefaultsGrabLock(self, _cmd, domain)) {
            success = NO;
            continue;
        }
        if ([dirtyKeys objectAtIndex:0] == NSUserDefaultsAllKeysMarker) {
            [cached removeObjectForKey:NSUserDefaultsDirtyKeysMarker()];
            [self _setDictionary:cached forDomain:domain];
            [cached setObject:[NSMutableArray array]
                       forKey:NSUserDefaultsDirtyKeysMarker()];
        } else {
            unsigned keyCount = [dirtyKeys count];
            NSDictionary *diskDictionary = [self _dictionaryForDomain:domain];
            NSMutableDictionary *merged = diskDictionary != nil
                ? [diskDictionary mutableCopyWithZone:_zone]
                : [[NSMutableDictionary allocWithZone:_zone] init];
            unsigned keyIndex;

            for (keyIndex = 0; keyIndex < keyCount; keyIndex++) {
                id key = [dirtyKeys objectAtIndex:keyIndex];
                id value = [cached objectForKey:key];
                if (value != nil)
                    [merged setObject:value forKey:key];
                else
                    [merged removeObjectForKey:key];
            }
            [self _setDictionary:merged forDomain:domain];
            [self cacheDictionary:merged forDomain:domain];
            [merged release];
        }
        _NSReleaseLock(self, _cmd, domain);
    }
    return success;
}

- (void)dealloc {
    [_path release];
    [_user release];
    [_cache release];
    [super dealloc];
}

@end

@implementation NSNonsavingDefaultsManager

- (id)initWithPath:(NSString *)path {
    _domains = [[NSMutableDictionary allocWithZone:NULL] init];
    return self;
}

- (NSArray *)allDomains { return [_domains allKeys]; }
- (NSDictionary *)dictionaryForDomain:(NSString *)domain { return [_domains objectForKey:domain]; }
- (BOOL)domainExists:(NSString *)domain { return [_domains objectForKey:domain] != nil; }
- (id)objectForKey:(NSString *)key domain:(NSString *)domain {
    return [[_domains objectForKey:domain] objectForKey:key];
}
- (void)setObject:(id)object forKey:(NSString *)key domain:(NSString *)domain {
    [[_domains objectForKey:domain] setObject:object forKey:key];
}
- (void)removeObjectForKey:(NSString *)key domain:(NSString *)domain {
    [[_domains objectForKey:domain] removeObjectForKey:key];
}
- (void)setDictionary:(NSDictionary *)dictionary forDomain:(NSString *)domain {
    NSMutableDictionary *copy = [dictionary mutableCopyWithZone:NULL];
    [_domains setObject:copy forKey:domain];
}
- (void)removeDomain:(NSString *)domain { [_domains removeObjectForKey:domain]; }
- (BOOL)synchronize { return YES; }

@end

@implementation NSUserDefaults

+ (NSUserDefaults *)standardUserDefaults {
    NSDictionary *registration;
    NSArray *searchList;
    NSString *language;

    if (NSUserDefaultsStandard != nil)
        return NSUserDefaultsStandard;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    if (NSUserDefaultsStandard == nil) {
        NSUserDefaultsCreatingStandard = YES;
        NSUserDefaultsStandard = [[NSUserDefaults allocWithZone:NULL] initWithUser:nil];
        NSUserDefaultsCreatingStandard = NO;
        registration = [NSUserDefaultsStandard->_temp
            objectForKey:NSRegistrationDomain];
        language = [registration objectForKey:@"NSLanguagesDirectory"];
        searchList = [[NSArray allocWithZone:NULL]
            initWithObjects:NSArgumentDomain,
                (NSString *)NSUserDefaultsStandard->_reserved,
                NSGlobalDomain, language, NSRegistrationDomain
                count:5];
        [NSUserDefaultsStandard setSearchList:searchList];
        [searchList release];
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return NSUserDefaultsStandard;
}

+ (void)resetStandardUserDefaults {
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [NSUserDefaultsStandard release];
    NSUserDefaultsStandard = nil;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
}

+ (void)setStandardUserDefaults:(NSUserDefaults *)defaults {
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [defaults retain];
    [NSUserDefaultsStandard release];
    NSUserDefaultsStandard = defaults;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
}

+ (NSArray *)nonUserDefaultsArguments {
    return NSUserDefaultsNonDefaultArguments;
}

- (id)init {
    return [self initWithUser:nil];
}

- (id)initWithUser:(NSString *)username {
    unsigned pool;
    NSString *defaultsPath;
    NSProcessInfo *processInfo;
    NSString *processName;
    BOOL processDomainExists;
    BOOL needsSynchronize = NO;
    NSArray *arguments;
    NSMutableArray *nonDefaultArguments;
    NSMutableArray *defaultArguments;
    NSMutableDictionary *argumentDomain;
    unsigned index;
    NSDictionary *english;
    NSArray *languages;
    Class languageContextClass;
    id context = nil;
    NSString *languageName = nil;
    BOOL usedSystemLanguageContext = NO;
    unsigned languageIndex;
    id (*sendObject)(id, SEL, id);
    id (*send)(id, SEL);

    pool = NSPushAutoreleasePool();
    self = [super init];
    if (self == nil)
        return nil;
    defaultsPath = [NSOpenStepDirectoryForUser(username, YES)
        stringByAppendingPathComponent:@"Defaults"];
    _dlplf = [[NSLockedPropertyListFile allocWithZone:NULL]
        initWithPath:defaultsPath];
    if (_dlplf == nil) {
        if (!NSUserDefaultsCreatingStandard) {
            [self dealloc];
            return nil;
        }
        _dlplf = [[NSNonsavingDefaultsManager allocWithZone:NULL]
            initWithPath:defaultsPath];
        NSLog(@"NSUserDefaults could not create the defaults directory; defaults will not be saved");
    }
    _temp = [[NSMutableDictionary allocWithZone:NULL] initWithCapacity:4];
    processInfo = [NSProcessInfo processInfo];
    processName = [[processInfo processName] copyWithZone:NULL];
    _reserved = processName;

    processDomainExists = [(NSLockedPropertyListFile *)_dlplf
        domainExists:processName];
    if (!processDomainExists) {
        [_dlplf setDictionary:[NSDictionary dictionary] forDomain:processName];
        needsSynchronize = YES;
    }
    if (![_dlplf domainExists:NSGlobalDomain]) {
        [_dlplf setDictionary:[NSDictionary dictionary] forDomain:NSGlobalDomain];
        needsSynchronize = YES;
    }
    if (needsSynchronize)
        [_dlplf synchronize];

    if (NSUserDefaultsNonDefaultArguments == nil) {
        arguments = [processInfo arguments];
        nonDefaultArguments = [[NSMutableArray allocWithZone:NULL] initWithCapacity:4];
        defaultArguments = [[NSMutableArray allocWithZone:NULL] initWithCapacity:0];
        [nonDefaultArguments addObject:[arguments objectAtIndex:0]];
        index = 1;
        while (index < [arguments count]) {
            NSString *argument = [arguments objectAtIndex:index];
            if ([argument hasPrefix:@"-"] && index + 1 < [arguments count]
                && ![[arguments objectAtIndex:index + 1] hasPrefix:@"-"]) {
                NSString *value = [arguments objectAtIndex:index + 1];
                NSCharacterSet *nonWhitespace =
                    [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
                NSRange firstRange = [value rangeOfCharacterFromSet:nonWhitespace];
                unichar first = firstRange.location != NSNotFound
                    ? [value characterAtIndex:firstRange.location] : 0;
                id parsedValue = value;

                if (first == '<' || first == '[' || first == '{'
                    || first == '"' || first == '(')
                    parsedValue = [value propertyList];
                [defaultArguments addObject:[argument substringFromIndex:1]];
                [defaultArguments addObject:parsedValue];
                index += 2;
            } else {
                [nonDefaultArguments addObject:argument];
                index++;
            }
        }
        NSUserDefaultsNonDefaultArguments = [nonDefaultArguments copyWithZone:NULL];
        [nonDefaultArguments release];
        NSUserDefaultsDefaultArguments = [defaultArguments copyWithZone:NULL];
        [defaultArguments release];
    }

    argumentDomain = [[NSMutableDictionary allocWithZone:NULL]
        initWithCapacity:[NSUserDefaultsDefaultArguments count] / 2];
    for (index = 0; index + 1 < [NSUserDefaultsDefaultArguments count]; index += 2)
        [argumentDomain setObject:[NSUserDefaultsDefaultArguments objectAtIndex:index + 1]
                           forKey:[NSUserDefaultsDefaultArguments objectAtIndex:index]];
    [_temp setObject:argumentDomain forKey:NSArgumentDomain];

    english = [_NSDefaultEnglishLanguageDict() mutableCopyWithZone:NULL];
    languages = [argumentDomain objectForKey:@"NSLanguages"];
    if (![languages isKindOfClass:[NSArray class]] && processDomainExists)
        languages = [[_dlplf dictionaryForDomain:processName] objectForKey:@"NSLanguages"];
    else if (![languages isKindOfClass:[NSArray class]])
        languages = nil;
    if (![languages isKindOfClass:[NSArray class]])
        languages = [[_dlplf dictionaryForDomain:NSGlobalDomain] objectForKey:@"NSLanguages"];
    if (![languages isKindOfClass:[NSArray class]])
        languages = [NSArray array];
    if (![languages containsObject:@"English"])
        languages = [languages arrayByAddingObject:@"English"];
    languageContextClass = objc_lookUpClass("NSLanguageContext");
    sendObject = (id (*)(id, SEL, id))objc_msgSend;
    send = (id (*)(id, SEL))objc_msgSend;
    if ([languages isKindOfClass:[NSArray class]] && languageContextClass != Nil) {
        for (languageIndex = 0; languageIndex < [languages count]; languageIndex++) {
            id candidate = [languages objectAtIndex:languageIndex];

            context = sendObject((id)languageContextClass,
                sel_registerName("languageContextWithName:"), candidate);
            if (context != nil) {
                languageName = candidate;
                break;
            }
        }
    }
    if (context == nil && languageContextClass != Nil) {
        context = send((id)languageContextClass,
                       sel_registerName("systemLanguageContext"));
        usedSystemLanguageContext = YES;
    }
    if (context != nil) {
        if (languageName == nil)
            languageName = send(context, sel_registerName("languageName"));
        if (languageName != nil) {
            if ([_dlplf domainExists:languageName])
                [_dlplf removeDomain:languageName];
            [_temp setObject:send(context, sel_registerName("_dictionary"))
                      forKey:languageName];
        }
    }
    if (languageName == nil)
        languageName = @"English";
    if (context != nil && !usedSystemLanguageContext) {
        [english setObject:languageName forKey:@"NSLanguagesDirectory"];
        [english setObject:languages forKey:@"NSLanguages"];
    } else {
        [english setObject:languageName forKey:@"NSLanguagesDirectory"];
        [english setObject:[NSArray arrayWithObject:languageName] forKey:@"NSLanguages"];
        if (context == nil)
            [_temp setObject:english forKey:languageName];
    }
    [_temp setObject:english forKey:NSRegistrationDomain];
    [english release];
    [argumentDomain release];
    NSPopAutoreleasePool(pool);
    return self;
}

- (id)objectForKey:(NSString *)defaultName {
    id value;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    value = [_dictRep objectForKey:defaultName];
    if (value == nil
        && [NSRegistrationDomain isEqualToString:[_search lastObject]])
        value = [[_temp objectForKey:NSRegistrationDomain] objectForKey:defaultName];
    if (value != nil)
        value = [[value retain] autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    BOOL searched;

    if (!_NSIsPList(value, YES)) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@ value is not a property list: %@",
                           _NSMethodExceptionProem(self, _cmd), value];
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [_dlplf setObject:value forKey:defaultName domain:_reserved];
    searched = [_search containsObject:_reserved];
    if (searched) {
        [_dictRep release];
        _dictRep = computeDictRep(self, _search, NULL);
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (void)removeObjectForKey:(NSString *)defaultName {
    BOOL changed = NO;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    if ([_search containsObject:_reserved] && [_dictRep objectForKey:defaultName] != nil) {
        changed = YES;
        [_dlplf removeObjectForKey:defaultName domain:_reserved];
        [_dictRep release];
        _dictRep = computeDictRep(self, _search, NULL);
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (changed)
        NSUserDefaultsPostChange(self);
}

- (id)objectForKey:(NSString *)defaultName inDomain:(NSString *)domainName {
    id value;

    NSUserDefaultsValidDomain(domainName, self, _cmd);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    value = [_dlplf objectForKey:defaultName domain:domainName];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName inDomain:(NSString *)domainName {
    BOOL searched;

    NSUserDefaultsValidDomain(domainName, self, _cmd);
    if (!_NSIsPList(value, YES))
        [NSException raise:NSInvalidArgumentException
                    format:@"%@ value is not a property list: %@",
                           _NSMethodExceptionProem(self, _cmd), value];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [_dlplf setObject:value forKey:defaultName domain:domainName];
    searched = [_search containsObject:domainName];
    if (searched) {
        [_dictRep release];
        _dictRep = computeDictRep(self, _search, NULL);
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (void)removeObjectForKey:(NSString *)defaultName inDomain:(NSString *)domainName {
    BOOL searched;

    NSUserDefaultsValidDomain(domainName, self, _cmd);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [_dlplf removeObjectForKey:defaultName domain:domainName];
    searched = [_search containsObject:domainName];
    if (searched) {
        [_dictRep release];
        _dictRep = computeDictRep(self, _search, NULL);
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (NSString *)stringForKey:(NSString *)defaultName {
    NSString *value = nil;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSString class]])
        value = [[candidate retain] autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (NSArray *)arrayForKey:(NSString *)defaultName {
    NSArray *value = nil;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSArray class]])
        value = [[candidate retain] autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (NSDictionary *)dictionaryForKey:(NSString *)defaultName {
    NSDictionary *value = nil;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSDictionary class]])
        value = [[candidate retain] autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (NSData *)dataForKey:(NSString *)defaultName {
    NSData *value = nil;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSData class]])
        value = [[candidate retain] autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (NSArray *)stringArrayForKey:(NSString *)defaultName {
    id array;
    id candidate;
    id stackObjects[256];
    id *objects = stackObjects;
    unsigned count = 0;
    unsigned index;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    array = candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSArray class]]) {
        count = [candidate count];
        if (count > 256)
            objects = (id *)NSZoneMalloc(NULL, sizeof(*objects) * count);
        if (count != 0)
            [candidate getObjects:objects range:NSMakeRange(0, count)];
        for (index = 0; index < count; index++)
            if (![objects[index] isKindOfClass:[NSString class]])
                break;
        if (objects != stackObjects)
            NSZoneFree(NULL, objects);
        if (index == count)
            array = [[candidate retain] autorelease];
        else
            array = nil;
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return array;
}

- (int)integerForKey:(NSString *)defaultName {
    int value = 0;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSString class]])
        value = [candidate intValue];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (double)doubleForKey:(NSString *)defaultName {
    double value = 0.0;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSString class]])
        value = [candidate doubleValue];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (long long)longForKey:(NSString *)defaultName {
    long long value = 0;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSString class]])
        value = [[NSDecimalNumber decimalNumberWithString:candidate locale:nil]
            longLongValue];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (float)floatForKey:(NSString *)defaultName {
    float value = 0.0f;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSString class]])
        value = [candidate floatValue];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return value;
}

- (BOOL)boolForKey:(NSString *)defaultName {
    BOOL result = NO;
    id candidate;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    candidate = NSUserDefaultsValueForKey(self, defaultName);
    if ([candidate isKindOfClass:[NSString class]]) {
        if ([candidate isEqualToString:@"YES"])
            result = YES;
        if (!result) {
            NSRange range = { 0, [candidate length] };

            result = [candidate compare:@"YES" options:NSCaseInsensitiveSearch
                                  range:range] == NSOrderedSame;
            if (!result)
                result = [candidate compare:@"Y" options:NSCaseInsensitiveSearch
                                      range:range] == NSOrderedSame;
            if (!result)
                result = [candidate intValue] != 0;
        }
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return result;
}

- (void)setInteger:(int)value forKey:(NSString *)defaultName {
    BOOL searched;
    NSString *string = [[NSString allocWithZone:NULL]
        initWithFormat:@"%d", value];

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    searched = NSUserDefaultsSetReservedObject(self, string, defaultName);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    [string release];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (void)setFloat:(float)value forKey:(NSString *)defaultName {
    BOOL searched;
    NSString *string = [[NSString allocWithZone:NULL]
        initWithFormat:@"%f", (double)value];

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    searched = NSUserDefaultsSetReservedObject(self, string, defaultName);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    [string release];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (void)setDouble:(double)value forKey:(NSString *)defaultName {
    BOOL searched;
    NSString *string = [[NSString allocWithZone:NULL]
        initWithFormat:@"%.16g", value];

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    searched = NSUserDefaultsSetReservedObject(self, string, defaultName);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    [string release];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (void)setLong:(long long)value forKey:(NSString *)defaultName {
    BOOL searched;
    NSString *string = [[NSDecimalNumber numberWithLongLong:value]
        descriptionWithLocale:nil];

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    searched = NSUserDefaultsSetReservedObject(self, string, defaultName);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    [string release];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    BOOL searched;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    searched = NSUserDefaultsSetReservedObject(self,
        value ? @"YES" : @"NO", defaultName);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (NSArray *)searchList {
    NSArray *search;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    search = _search != nil ? [[_search copyWithZone:NULL] autorelease] : [NSArray array];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return search;
}

- (void)setSearchList:(NSArray *)array {
    NSArray *search = [array copyWithZone:NULL];

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [_search release];
    _search = search;
    [_dictRep release];
    _dictRep = computeDictRep(self, _search, NULL);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
}

- (void)registerDefaults:(NSDictionary *)registrationDictionary {
    NSDictionary *currentRegistration;
    NSMutableDictionary *registration;
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned capacity;
#endif

    if (registrationDictionary == nil || [registrationDictionary count] == 0)
        return;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    currentRegistration = [_temp objectForKey:NSRegistrationDomain];
#if defined(__ppc__) || defined(__POWERPC__)
    registration = [NSMutableDictionary allocWithZone:NULL];
    capacity = [currentRegistration count];
    capacity += [registrationDictionary count];
    registration = [registration initWithCapacity:capacity];
    [registration addEntriesFromDictionary:currentRegistration];
#else
    registration = [currentRegistration mutableCopyWithZone:NULL];
#endif
    [registration addEntriesFromDictionary:registrationDictionary];
    [_temp setObject:registration forKey:NSRegistrationDomain];
    [registration release];
    if ([_search containsObject:NSRegistrationDomain]) {
        if (![[ _search lastObject] isEqualToString:NSRegistrationDomain]) {
            [_dictRep release];
            _dictRep = computeDictRep(self, _search, NULL);
        }
#if defined(__ppc__) || defined(__POWERPC__)
        if (_NSUserDefaultsLock != nil)
            [_NSUserDefaultsLock unlock];
        NSUserDefaultsPostChange(self);
#else
        NSUserDefaultsPostChange(self);
        if (_NSUserDefaultsLock != nil)
            [_NSUserDefaultsLock unlock];
#endif
        return;
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
}

- (NSDictionary *)dictionaryRepresentation {
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    if ([_dictRep isKindOfClass:[NSMutableDictionary class]]) {
        NSDictionary *dictRep = _dictRep;

        if ([NSRegistrationDomain isEqualToString:[_search lastObject]]) {
            NSDictionary *registration = [_temp objectForKey:NSRegistrationDomain];

            if (registration != nil) {
                NSMutableDictionary *merged =
                    [registration mutableCopyWithZone:NULL];

                if (merged != nil) {
                    [merged addEntriesFromDictionary:dictRep];
                    [dictRep release];
                    dictRep = merged;
                }
            }
        }
        _dictRep = [dictRep copyWithZone:NULL];
        [dictRep release];
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return _dictRep;
}

- (NSArray *)volatileDomainNames {
    NSArray *domains;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    domains = [[_temp allKeys] retain];
    domains = [domains autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return domains;
}

- (NSDictionary *)volatileDomainForName:(NSString *)domainName {
    NSDictionary *domain;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    domain = [[_temp objectForKey:domainName] copyWithZone:NULL];
    domain = [domain autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return domain;
}

- (void)setVolatileDomain:(NSDictionary *)domain forName:(NSString *)domainName {
    BOOL searched;
    NSDictionary *copy;

    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    if ([_dlplf domainExists:domainName]) {
        if (_NSUserDefaultsLock != nil)
            [_NSUserDefaultsLock unlock];
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: cannot create volatile domain %@. Persistent domain %@ already exists.",
                           _NSMethodExceptionProem(self, _cmd), domainName,
                           domainName];
        return;
    }
    copy = [domain copyWithZone:NULL];
    [_temp setObject:copy forKey:domainName];
    [copy release];
    searched = [_search containsObject:domainName];
    if (searched
        && ((domainName != NSRegistrationDomain
             && ![NSRegistrationDomain isEqualToString:domainName])
            || ![NSRegistrationDomain isEqualToString:[_search lastObject]])) {
        [_dictRep release];
        _dictRep = computeDictRep(self, _search, NULL);
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (void)removeVolatileDomainForName:(NSString *)domainName {
    BOOL searched;
    if ([_temp objectForKey:domainName] == nil)
        return;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [_temp removeObjectForKey:domainName];
    searched = [_search containsObject:domainName];
    if (searched) {
        [_dictRep release];
        _dictRep = computeDictRep(self, _search, NULL);
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (NSArray *)persistentDomainNames {
    NSArray *domains;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    domains = [[_dlplf allDomains] retain];
    domains = [domains autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return domains;
}

- (NSDictionary *)persistentDomainForName:(NSString *)domainName {
    NSDictionary *domain;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    domain = [[_dlplf dictionaryForDomain:domainName] copyWithZone:NULL];
    domain = [domain autorelease];
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return domain;
}

- (void)setPersistentDomain:(NSDictionary *)domain forName:(NSString *)domainName {
    BOOL searched;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    if ([domainName isEqualToString:NSArgumentDomain]
        || [domainName isEqualToString:NSRegistrationDomain]
        || [_temp objectForKey:domainName] != nil) {
        if (_NSUserDefaultsLock != nil)
            [_NSUserDefaultsLock unlock];
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: cannot create persistent domain %@. Volatile domain %@ already exists.",
                           _NSMethodExceptionProem(self, _cmd), domainName,
                           domainName];
        return;
    }
    [_dlplf setDictionary:domain forDomain:domainName];
    searched = [_search containsObject:domainName];
    if (searched) {
        [_dictRep release];
        _dictRep = computeDictRep(self, _search, NULL);
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (void)removePersistentDomainForName:(NSString *)domainName {
    BOOL searched;
    if (![_dlplf domainExists:domainName])
        return;
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [_dlplf removeDomain:domainName];
    searched = [_search containsObject:domainName];
    if (searched) {
        [_dictRep release];
        _dictRep = computeDictRep(self, _search, NULL);
    }
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    if (searched)
        NSUserDefaultsPostChange(self);
}

- (BOOL)synchronize {
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock lock];
    [_dlplf synchronize];
    [_dictRep release];
    _dictRep = computeDictRep(self, _search, NULL);
    if (_NSUserDefaultsLock != nil)
        [_NSUserDefaultsLock unlock];
    return YES;
}

- (void)dealloc {
    [_dictRep release];
    [_search release];
    [_dlplf release];
    [_temp release];
    [_reserved release];
    [super dealloc];
}

@end
