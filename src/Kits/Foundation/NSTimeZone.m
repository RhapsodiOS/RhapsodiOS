/*	NSTimeZone.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSTimeZone.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSDistributedNotificationCenter.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

extern int _NSsnprintf(char *buffer, size_t size, char *format, ...);
extern char *_NSGetEnvironmentVariable(const char *name);
extern NSString *_NSFoundationResourceDirectory(void);
extern Class __NSTimeZoneClass;

@interface NSData (NSTimeZonePrivateCreation)
- (id)initWithBytes:(const void *)bytes length:(unsigned)length
               copy:(BOOL)copy freeWhenDone:(BOOL)freeWhenDone
        bytesAreVM:(BOOL)bytesAreVM;
@end

enum {
    NSTimeZoneEmbeddedNameCount = 497,
    NSTimeZoneNameOffsetCount = NSTimeZoneEmbeddedNameCount + 1,
    NSTimeZoneDataOffsetCount = 996,
    NSTimeZonePackedNameSize = 0x1efc,
    NSTimeZoneEmbeddedDataSize = 0x38f06
};

typedef struct {
    unsigned count;
    unsigned offsets[NSTimeZoneDataOffsetCount];
    unsigned char names[NSTimeZonePackedNameSize];
    unsigned char data[NSTimeZoneEmbeddedDataSize];
} NSTimeZoneDataRecord;

const NSTimeZoneDataRecord _NSTimeZoneData = {
#include "NSTimeZoneDataExport.inc"
};

static const char *NSTimeZoneCanonicalNameAtIndex(unsigned index) {
    return (const char *)_NSTimeZoneData.names + _NSTimeZoneData.offsets[index];
}

typedef struct {
    NSTimeInterval startTime;
    NSString *abbreviation;
    unsigned offsetAndFlags;
} NSTimeZonePeriod;

@interface NSConcreteTimeZone : NSTimeZone {
@public
    NSString *timeZoneName;
    NSData *timeZoneData;
    NSTimeZonePeriod *timeZonePeriods;
    unsigned timeZonePeriodsCount;
    unsigned refCount;
}
+ (BOOL)parseTimeZoneData:(NSData *)data into:(NSTimeZonePeriod **)periods
                    count:(unsigned *)count zone:(NSZone *)zone;
- (id)initWithExactName:(NSString *)name data:(NSData *)data;
@end

@interface NSTimeZone (NSTimeZonePrivate)
+ (NSString *)replacementTimeZoneNameForName:(NSString *)name;
+ (NSData *)dataForTimeZone:(NSString *)name;
+ (void)_resetTimeZones;
- (id)initWithExactName:(NSString *)name data:(NSData *)data;
- (NSTimeZone *)timeZoneForDate:(NSDate *)date;
@end

@interface NSLocalTimeZone : NSTimeZone
- (NSTimeZone *)timeZoneForDate:(NSDate *)date;
@end

@interface NSTimeZoneDetailDecoder : NSObject
@end

@interface NSWindowsDefaultTimeZoneDecoder : NSObject
@end

extern NSLock *_NSGlobalRetainLock;

static NSDictionary *NSTimeZoneAbbreviationDictionary;
static NSArray *NSTimeZoneKnownNames;
NSRecursiveLock *_NSTimeZoneLock;
static NSTimeZone *NSTimeZoneSystem;
static NSTimeZone *NSTimeZoneDefault;
static NSTimeZone *NSTimeZoneLocal;
static int NSTimeZoneRegisteredForChange;

static const unsigned char NSTimeZoneGMTData[56] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0, 0,
    0, 0, 'G', 'M', 'T', 0, 0, 0
};

NSString * const NSSystemTimeZoneDidChangeNotification =
    @"NSSystemTimeZoneDidChangeNotification";

static NSTimeZone *NSTimeZoneForLocalPath(Class timeZoneClass,
                                           NSString *path) {
    NSArray *components;
    unsigned count;
    NSString *name;
    NSTimeZone *timeZone;

    if (path == nil)
        return nil;
    components = [path pathComponents];
    count = [components count];
    if (count == 0)
        return nil;

    name = [components objectAtIndex:count - 1];
    timeZone = [[timeZoneClass allocWithZone:NULL] initWithName:name];
    if (timeZone != nil)
        return timeZone;
    if (count > 1) {
        NSString *parent = [components objectAtIndex:count - 2];
        NSString *qualifiedName = [parent stringByAppendingPathComponent:name];
        timeZone = [[timeZoneClass allocWithZone:NULL]
            initWithName:qualifiedName];
        if (timeZone != nil)
            return timeZone;
    }
    return [[timeZoneClass allocWithZone:NULL] initWithName:path];
}

static int NSTimeZoneBigEndianInt32(const unsigned char *bytes) {
    unsigned value = ((unsigned)bytes[0] << 24)
        | ((unsigned)bytes[1] << 16)
        | ((unsigned)bytes[2] << 8)
        | (unsigned)bytes[3];

    return (int)value;
}

static int NSTimeZoneComparePeriods(const void *first, const void *second) {
    const NSTimeZonePeriod *a = (const NSTimeZonePeriod *)first;
    const NSTimeZonePeriod *b = (const NSTimeZonePeriod *)second;

    if (a->startTime < b->startTime)
        return -1;
    if (a->startTime > b->startTime)
        return 1;
    return 0;
}

static unsigned NSTimeZonePeriodIndex(NSTimeZonePeriod *periods,
                                      unsigned count,
                                      NSTimeInterval interval) {
    unsigned low = 0;
    unsigned high = count;

    while (low < high) {
        unsigned middle = low + (high - low) / 2;

        if (periods[middle].startTime < interval)
            low = middle + 1;
        else
            high = middle;
    }
    if (low == 0)
        return 0;
    if (low >= count)
        return count - 1;
    return low - 1;
}

id __NSConcoctFixedTimeZone(int seconds, const char *abbreviation,
                           BOOL daylight) {
    unsigned abbreviationLength = (unsigned)strlen(abbreviation);
    unsigned characterCount = abbreviationLength + 1;
    unsigned length = 52 + characterCount;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    unsigned char *bytes = [data mutableBytes];
    unsigned offset = (unsigned)seconds;
    NSString *name = [NSString stringWithCString:abbreviation];
    NSTimeZone *timeZone;

    bytes[20] = 0;
    bytes[21] = 0;
    bytes[22] = 0;
    bytes[23] = 1;
    bytes[24] = 0;
    bytes[25] = 0;
    bytes[26] = 0;
    bytes[27] = 1;
    bytes[39] = 1;
    bytes[40] = (unsigned char)(characterCount >> 24);
    bytes[41] = (unsigned char)(characterCount >> 16);
    bytes[42] = (unsigned char)(characterCount >> 8);
    bytes[43] = (unsigned char)characterCount;
    bytes[44] = (unsigned char)(offset >> 24);
    bytes[45] = (unsigned char)(offset >> 16);
    bytes[46] = (unsigned char)(offset >> 8);
    bytes[47] = (unsigned char)offset;
    bytes[48] = daylight ? 1 : 0;
    memcpy(bytes + 50, abbreviation, characterCount);

    timeZone = [NSTimeZone allocWithZone:NULL];
    return [timeZone initWithExactName:name data:data];
}

@implementation NSConcreteTimeZone

+ (BOOL)parseTimeZoneData:(NSData *)data into:(NSTimeZonePeriod **)periods
                    count:(unsigned *)count zone:(NSZone *)zone {
    const unsigned char *bytes = [data bytes];
    unsigned length = [data length];
    int transitionCount;
    int typeCount;
    int characterCount;
    unsigned periodCount;
    unsigned remaining;
    const unsigned char *transitionTimes;
    const unsigned char *transitionTypes;
    const unsigned char *typeRecords;
    const unsigned char *abbreviations;
    NSString **abbreviationCache;
    NSTimeZonePeriod *result;
    unsigned index;

    if (bytes == NULL || length <= 43)
        return NO;

    transitionCount = NSTimeZoneBigEndianInt32(bytes + 32);
    typeCount = NSTimeZoneBigEndianInt32(bytes + 36);
    characterCount = NSTimeZoneBigEndianInt32(bytes + 40);
    if (transitionCount < 0 || typeCount <= 0 || characterCount < 0)
        return NO;
    remaining = length - 44;
    if ((unsigned)transitionCount > remaining / 5)
        return NO;
    remaining -= 5 * (unsigned)transitionCount;
    if ((unsigned)typeCount > remaining / 6)
        return NO;
    remaining -= 6 * (unsigned)typeCount;
    if ((unsigned)characterCount > remaining)
        return NO;

    periodCount = transitionCount != 0 ? (unsigned)transitionCount : 1;
    if (periodCount > (~0U) / sizeof(NSTimeZonePeriod)
        || (unsigned)characterCount + 1U > (~0U) / sizeof(NSString *))
        return NO;
    result = (NSTimeZonePeriod *)NSZoneMalloc(zone,
        periodCount * sizeof(NSTimeZonePeriod));
    *periods = result;
    memset(result, 0, periodCount * sizeof(NSTimeZonePeriod));
    abbreviationCache = (NSString **)NSZoneMalloc(NULL,
        ((unsigned)characterCount + 1U) * sizeof(NSString *));
    memset(abbreviationCache, 0,
        ((unsigned)characterCount + 1U) * sizeof(NSString *));

    transitionTimes = bytes + 44;
    transitionTypes = transitionTimes + 4U * (unsigned)transitionCount;
    typeRecords = transitionTypes + transitionCount;
    abbreviations = typeRecords + 6U * (unsigned)typeCount;

    for (index = 0; index < periodCount; index++) {
        unsigned typeIndex = transitionCount != 0
            ? transitionTypes[index] : 0;
        const unsigned char *type;
        int offset;
        unsigned char daylight;
        int abbreviationIndex;
        unsigned abbreviationLength;
        NSString *abbreviation;

        if (typeIndex >= (unsigned)typeCount)
            goto parse_failure;
        type = typeRecords + 6 * typeIndex;
        offset = NSTimeZoneBigEndianInt32(type);
        daylight = type[4];
        abbreviationIndex = (signed char)type[5];
        if (daylight > 1 || abbreviationIndex < 0
            || abbreviationIndex > characterCount)
            goto parse_failure;

        abbreviation = abbreviationCache[abbreviationIndex];
        if (abbreviation == nil) {
            abbreviationLength = 0;
            while (abbreviations[abbreviationIndex + abbreviationLength] != 0)
                abbreviationLength++;
            abbreviation = [NSString stringWithCString:
                (const char *)abbreviations + abbreviationIndex
                length:abbreviationLength];
            abbreviationCache[abbreviationIndex] = abbreviation;
        }

        if (transitionCount != 0) {
            int transition = NSTimeZoneBigEndianInt32(
                transitionTimes + 4 * index);
            result[index].startTime = (NSTimeInterval)transition - 978307200.0;
        } else {
            result[index].startTime = [[NSDate distantPast]
                timeIntervalSinceReferenceDate] - 1.0;
        }
        result[index].abbreviation = [abbreviation retain];
#if defined(__ppc__) || defined(__POWERPC__)
        result[index].offsetAndFlags = ((unsigned)offset << 1)
            | (unsigned)daylight;
#else
        result[index].offsetAndFlags = ((unsigned)offset & 0x7fffffffU)
            | ((unsigned)daylight << 31);
#endif
    }

    qsort(result, periodCount, sizeof(NSTimeZonePeriod),
          NSTimeZoneComparePeriods);
    NSZoneFree(NULL, abbreviationCache);
    *count = periodCount;
    return YES;

parse_failure:
    NSZoneFree(NULL, abbreviationCache);
    NSZoneFree(zone, result);
    *periods = NULL;
    return NO;
}

- (id)init {
    [self dealloc];
    return nil;
}

- (id)initWithExactName:(NSString *)name data:(NSData *)data {
    NSTimeZonePeriod *periods = NULL;
    unsigned count = 0;

    if (name == nil || data == nil
        || ![[self class] parseTimeZoneData:data into:&periods count:&count
                                       zone:[self zone]]) {
        [super dealloc];
        return nil;
    }
    timeZoneName = [name retain];
    timeZoneData = [data retain];
    timeZonePeriods = periods;
    timeZonePeriodsCount = count;
    return self;
}

- (NSString *)name {
    return timeZoneName;
}

- (NSData *)data {
    return timeZoneData;
}

- (int)secondsFromGMTForDate:(NSDate *)date {
    unsigned index = NSTimeZonePeriodIndex(timeZonePeriods,
        timeZonePeriodsCount, [date timeIntervalSinceReferenceDate]);
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned offset = timeZonePeriods[index].offsetAndFlags >> 1;
    if ((offset & 0x40000000U) != 0)
        offset |= 0x80000000U;
#else
    unsigned offset = timeZonePeriods[index].offsetAndFlags & 0x7fffffffU;

    if ((offset & 0x40000000U) != 0)
        offset |= 0x80000000U;
#endif
    return (int)offset;
}

- (NSString *)abbreviationForDate:(NSDate *)date {
    unsigned index = NSTimeZonePeriodIndex(timeZonePeriods,
        timeZonePeriodsCount, [date timeIntervalSinceReferenceDate]);

    return timeZonePeriods[index].abbreviation;
}

- (BOOL)isDaylightSavingTimeForDate:(NSDate *)date {
    unsigned index = NSTimeZonePeriodIndex(timeZonePeriods,
        timeZonePeriodsCount, [date timeIntervalSinceReferenceDate]);

#if defined(__ppc__) || defined(__POWERPC__)
    return (timeZonePeriods[index].offsetAndFlags & 1U) != 0;
#else
    return (timeZonePeriods[index].offsetAndFlags >> 31) != 0;
#endif
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (id)retain {
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    if (refCount != 0xffffffffU)
        ++refCount;
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    BOOL shouldDeallocate = NO;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    if (refCount != 0) {
        if (refCount != 0xffffffffU)
            --refCount;
    } else {
        shouldDeallocate = YES;
    }
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
    if (shouldDeallocate)
        [self dealloc];
}

- (unsigned)retainCount {
    return refCount + 1;
}

- (void)dealloc {
    unsigned index;

    [timeZoneName release];
    [timeZoneData release];
    for (index = 0; index < timeZonePeriodsCount; index++) {
        [timeZonePeriods[index].abbreviation release];
        timeZonePeriods[index].abbreviation = nil;
    }
    if (timeZonePeriods != NULL)
        NSZoneFree(NSZoneFromPointer(timeZonePeriods), timeZonePeriods);
    [super dealloc];
}

@end

@implementation NSLocalTimeZone

- (NSString *)description {
    return [NSString stringWithFormat:@"Local Time Zone [%@]",
        [[NSTimeZone defaultTimeZone] description]];
}

- (NSString *)name {
    return [[NSTimeZone defaultTimeZone] name];
}

- (NSData *)data {
    return [[NSTimeZone defaultTimeZone] data];
}

- (int)secondsFromGMTForDate:(NSDate *)date {
    return [[NSTimeZone defaultTimeZone] secondsFromGMTForDate:date];
}

- (NSString *)abbreviationForDate:(NSDate *)date {
    return [[NSTimeZone defaultTimeZone] abbreviationForDate:date];
}

- (BOOL)isDaylightSavingTimeForDate:(NSDate *)date {
    return [[NSTimeZone defaultTimeZone] isDaylightSavingTimeForDate:date];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (Class)classForCoder {
    return [NSLocalTimeZone class];
}

- (void)encodeWithCoder:(NSCoder *)coder {
}

- (id)initWithCoder:(NSCoder *)coder {
    [self dealloc];
    return [NSTimeZone localTimeZone];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    return self;
}

- (id)retain {
    return self;
}

- (oneway void)release {
}

- (unsigned)retainCount {
    return (unsigned)-1;
}

@end

@implementation NSLocalTimeZone (NSBackwardsCompatibility)

- (NSTimeZone *)timeZoneForDate:(NSDate *)date {
    return [[NSTimeZone defaultTimeZone] timeZoneForDate:date];
}

@end

@implementation NSTimeZone

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSTimeZone class])
        return [NSConcreteTimeZone allocWithZone:zone];
    return [super allocWithZone:zone];
}

- (NSString *)name {
    NSRequestConcreteImplementation(self, _cmd, [NSTimeZone class]);
    return nil;
}

- (NSData *)data {
    NSRequestConcreteImplementation(self, _cmd, [NSTimeZone class]);
    return nil;
}

- (id)initWithExactName:(NSString *)name data:(NSData *)data {
    [NSException raise:NSInvalidArgumentException
                format:@"*** initialization method -%s cannot be sent to an abstract object of class %s: Create a concrete instance!",
                       sel_getName(_cmd), self->isa->name];
    return nil;
}

- (int)secondsFromGMTForDate:(NSDate *)aDate {
    NSRequestConcreteImplementation(self, _cmd, [NSTimeZone class]);
    return 0;
}

- (NSString *)abbreviationForDate:(NSDate *)aDate {
    NSRequestConcreteImplementation(self, _cmd, [NSTimeZone class]);
    return nil;
}

- (BOOL)isDaylightSavingTimeForDate:(NSDate *)aDate {
    NSRequestConcreteImplementation(self, _cmd, [NSTimeZone class]);
    return NO;
}

- (int)secondsFromGMT {
    return [self secondsFromGMTForDate:[NSDate date]];
}

- (NSString *)abbreviation {
    return [self abbreviationForDate:[NSDate date]];
}

- (BOOL)isDaylightSavingTime {
    return [self isDaylightSavingTimeForDate:[NSDate date]];
}

- (Class)classForCoder {
    return [NSTimeZone class];
}

- (id)copyWithZone:(NSZone *)zone {
    NSData *data;
    NSString *name;
    NSTimeZone *copy;

#if defined(__ppc__) || defined(__POWERPC__)
    copy = [(Class)self->isa allocWithZone:zone];
    name = [self name];
    data = [self data];
#else
    data = [self data];
    name = [self name];
    copy = [(Class)self->isa allocWithZone:zone];
#endif

    return [copy initWithName:name data:data];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    NSString *name = [self name];
    NSData *data = [self data];

    [coder encodeValueOfObjCType:"@" at:&name];
    [coder encodeValueOfObjCType:"@" at:&data];
}

- (id)initWithCoder:(NSCoder *)coder {
    unsigned version = [coder versionForClassName:@"NSTimeZone"];

    if (version != 0) {
        NSString *name = nil;
        NSData *data = nil;

        [coder decodeValueOfObjCType:"@" at:&name];
        [coder decodeValueOfObjCType:"@" at:&data];
        self = [self initWithExactName:name data:data];
        [name release];
        [data release];
    } else {
        NSString *abbreviation = nil;
        NSTimeZone *timeZone;

        [coder decodeValueOfObjCType:"@" at:&abbreviation];
        timeZone = [[self class] timeZoneWithAbbreviation:abbreviation];
        if (timeZone != nil) {
            [self dealloc];
            self = [timeZone retain];
        } else {
            self = [self initWithName:abbreviation];
        }
        [abbreviation release];
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (object == self)
        return YES;
    if (object != nil && [object isKindOfClass:__NSTimeZoneClass])
        return [self isEqualToTimeZone:object];
    return NO;
}

- (unsigned)hash {
    return [[self name] hash];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)coder {
    if (![coder isByref])
        return self;
    return [NSDistantObject proxyWithLocal:self connection:[coder connection]];
}

- (BOOL)isEqualToTimeZone:(NSTimeZone *)aTimeZone {
    NSString *name;
    NSString *otherName;
    NSData *data;
    NSData *otherData;

    if (self == aTimeZone)
        return YES;
#if defined(__ppc__) || defined(__POWERPC__)
    name = [self name];
    otherName = [aTimeZone name];
#else
    otherName = [aTimeZone name];
    name = [self name];
#endif
    if (![name isEqualToString:otherName])
        return NO;
#if defined(__ppc__) || defined(__POWERPC__)
    data = [self data];
    otherData = [aTimeZone data];
#else
    otherData = [aTimeZone data];
    data = [self data];
#endif
    return [data isEqualToData:otherData];
}

+ (NSTimeZone *)systemTimeZone {
    NSTimeZone *timeZone = nil;
    const char *environmentName;
    NSString *localPath = @"/etc/localtime";
    NSString *linkPath;
    NSString *resolvedPath;
    NSData *data;

    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock lock];
    if (NSTimeZoneSystem == nil) {
        environmentName = _NSGetEnvironmentVariable("TZFILE");
        if (environmentName != NULL) {
            NSString *environmentString = [NSString stringWithCString:
                environmentName length:(unsigned)strlen(environmentName)];

            timeZone = [[self allocWithZone:NULL]
                initWithName:environmentString];
        }

        if (timeZone == nil) {
            NSFileManager *fileManager = [NSFileManager defaultManager];
            linkPath = [fileManager
                pathContentOfSymbolicLinkAtPath:localPath];

            if (linkPath != nil) {
                timeZone = NSTimeZoneForLocalPath(self, linkPath);
                if (timeZone == nil) {
                    resolvedPath = [localPath stringByResolvingSymlinksInPath];
                    timeZone = NSTimeZoneForLocalPath(self, resolvedPath);
                    if (timeZone == nil) {
                        data = [NSData dataWithContentsOfFile:resolvedPath];
                        if (data != nil)
                            timeZone = [[self allocWithZone:NULL]
                                initWithExactName:resolvedPath data:data];
                    }
                }
            } else {
                NSLog(@"%@: Cannot determine local time zone; %@ does not exist or is not a symbolic link",
                    _NSMethodExceptionProem(self, _cmd), localPath);
            }
        }

        if (timeZone == nil) {
            NSLog(@"%@: Could not compute system time zone, using GMT",
                _NSMethodExceptionProem(self, _cmd));
            data = [NSData dataWithBytes:NSTimeZoneGMTData length:56];
            timeZone = [[self allocWithZone:NULL]
                initWithExactName:@"GMT" data:data];
        }
        NSTimeZoneSystem = timeZone;
        if (!NSTimeZoneRegisteredForChange) {
            NSTimeZoneRegisteredForChange = YES;
            [[NSDistributedNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(_resetTimeZones)
                       name:@"NSSystemTimeZoneDidChangeDistributedNotification"
                     object:nil
          suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
        }
    }
    timeZone = NSTimeZoneSystem;
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock unlock];
    return timeZone;
}

+ (void)resetSystemTimeZone {
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock lock];
    [NSTimeZoneSystem release];
    NSTimeZoneSystem = nil;
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock unlock];
}

+ (void)_resetTimeZones {
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock lock];
    if (NSTimeZoneDefault == NSTimeZoneSystem)
        [NSTimeZone setDefaultTimeZone:nil];
    [NSTimeZone resetSystemTimeZone];
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock unlock];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSSystemTimeZoneDidChangeNotification
                      object:nil
                    userInfo:nil];
}

+ (NSTimeZone *)defaultTimeZone {
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock lock];
    if (NSTimeZoneDefault == nil)
        NSTimeZoneDefault = [[self systemTimeZone] retain];
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock unlock];
    return NSTimeZoneDefault;
}

+ (void)setDefaultTimeZone:(NSTimeZone *)aTimeZone {
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock lock];
    if (NSTimeZoneDefault != aTimeZone) {
        [NSTimeZoneDefault release];
        NSTimeZoneDefault = [aTimeZone retain];
    }
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock unlock];
}

+ (NSTimeZone *)localTimeZone {
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock lock];
    if (NSTimeZoneLocal == nil)
        NSTimeZoneLocal = [[NSLocalTimeZone allocWithZone:NULL] init];
    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock unlock];
    return NSTimeZoneLocal;
}

+ (NSArray *)knownTimeZoneNames {
    NSString *resourceDirectory;
    NSString *timeZoneInfoPath;
    NSMutableSet *names;
    NSArray *subpaths;
    NSArray *allNames;
    NSFileManager *fileManager;
    unsigned index;

    if (NSTimeZoneKnownNames == nil) {
        names = [[NSMutableSet allocWithZone:NULL]
            initWithCapacity:512];
        for (index = 0; index < _NSTimeZoneData.count; index++) {
            const char *cString = NSTimeZoneCanonicalNameAtIndex(index);
            unsigned length = 0;
            NSString *name;
#if !defined(__ppc__) && !defined(__POWERPC__)
            NSData *nameData;
#endif

            while (cString[length] != '\0')
                length++;
#if defined(__ppc__) || defined(__POWERPC__)
            name = [[NSString allocWithZone:NULL]
                initWithCString:cString length:length];
            [names addObject:name];
            [name release];
#else
            nameData = [[NSData allocWithZone:NULL]
                initWithBytes:cString length:length copy:NO freeWhenDone:NO
                bytesAreVM:NO];
            name = [[NSString allocWithZone:NULL]
                initWithData:nameData encoding:NSUTF8StringEncoding];
            [names addObject:name];
            [nameData release];
            /* The i386 reference leaves this initialized string at +1. */
#endif
        }
#if defined(__ppc__) || defined(__POWERPC__)
        fileManager = [NSFileManager defaultManager];
#endif
        resourceDirectory = _NSFoundationResourceDirectory();
        timeZoneInfoPath = [resourceDirectory
            stringByAppendingPathComponent:@"TimeZoneInfo"];
#if !defined(__ppc__) && !defined(__POWERPC__)
        fileManager = [NSFileManager defaultManager];
#endif
        subpaths = [fileManager subpathsAtPath:timeZoneInfoPath];
        for (index = 0; index < [subpaths count]; index++) {
            NSString *name = [subpaths objectAtIndex:index];
            if (![name hasSuffix:@".table"])
                [names addObject:name];
        }
        allNames = [names allObjects];
        NSTimeZoneKnownNames = [[NSArray allocWithZone:NULL]
            initWithArray:allNames];
        [names release];
    }
    return NSTimeZoneKnownNames;
}

+ (NSDictionary *)abbreviationDictionary {
    NSString *resourceDirectory;
    NSString *path;

    if (_NSTimeZoneLock != nil)
        [_NSTimeZoneLock lock];
    if (NSTimeZoneAbbreviationDictionary == nil) {
        resourceDirectory = _NSFoundationResourceDirectory();
        path = [[resourceDirectory stringByAppendingPathComponent:@"TimeZoneInfo"]
            stringByAppendingPathComponent:@"Abbreviation.table"];
        NSTimeZoneAbbreviationDictionary =
            [[NSDictionary allocWithZone:NULL] initWithContentsOfFile:path];
        if (NSTimeZoneAbbreviationDictionary == nil) {
            NSLog(@"%@: Could not find or parse time zone abbreviation dictionary %@",
                  _NSMethodExceptionProem(self, _cmd), path);
            NSTimeZoneAbbreviationDictionary = [[NSDictionary allocWithZone:NULL] init];
        }
    }
    {
        NSDictionary *dictionary = NSTimeZoneAbbreviationDictionary;
        if (_NSTimeZoneLock != nil)
            [_NSTimeZoneLock unlock];
        return dictionary;
    }
}

- (NSString *)description {
    NSString *name;
    NSString *abbreviation;
    NSString *daylightSuffix;
    int secondsFromGMT;

#if defined(__ppc__) || defined(__POWERPC__)
    name = [self name];
    secondsFromGMT = [self secondsFromGMT];
    abbreviation = [self abbreviation];
    daylightSuffix = [self isDaylightSavingTime] ? @" (Daylight)" : @"";
#else
    daylightSuffix = [self isDaylightSavingTime] ? @" (Daylight)" : @"";
    secondsFromGMT = [self secondsFromGMT];
    abbreviation = [self abbreviation];
    name = [self name];
#endif

    return [NSString stringWithFormat:@"%@ (%@) offset %d%@", name,
        abbreviation, secondsFromGMT, daylightSuffix];
}

+ (id)timeZoneWithName:(NSString *)tzName {
    return [[[self allocWithZone:NULL] initWithName:tzName] autorelease];
}

+ (id)timeZoneWithName:(NSString *)tzName data:(NSData *)aData {
    return [[[self allocWithZone:NULL] initWithName:tzName data:aData]
        autorelease];
}

+ (id)timeZoneForSecondsFromGMT:(int)seconds {
    char abbreviation[16];
    int hours;
    int minutes;
    unsigned remainder;

    if (seconds == 0)
        _NSsnprintf(abbreviation, sizeof(abbreviation), "GMT");
    else {
        hours = (seconds > 0 ? -seconds : seconds) / 3600;
        remainder = (unsigned)seconds - (unsigned)(3600 * hours);
        if (seconds > 0) {
            remainder += 30U;
            _NSsnprintf(abbreviation, sizeof(abbreviation), "GMT+%02d%02d",
                        hours, (int)remainder / 60);
        } else {
            remainder -= 30U;
            minutes = (int)remainder / 60;
            _NSsnprintf(abbreviation, sizeof(abbreviation), "GMT-%02d%02d",
                        hours, minutes);
        }
    }
    return [__NSConcoctFixedTimeZone(seconds, abbreviation, NO) autorelease];
}

- (id)initWithName:(NSString *)tzName {
    NSString *name = [[self class] replacementTimeZoneNameForName:tzName];
    NSData *data = [[self class] dataForTimeZone:name];

    if (data != nil)
        return [self initWithExactName:name data:data];
#if defined(__ppc__) || defined(__POWERPC__)
    [self dealloc];
#else
    [self release];
#endif
    return nil;
}

- (id)initWithName:(NSString *)tzName data:(NSData *)aData {
    if (aData == nil) {
        [super dealloc];
        return nil;
    }
    return [self initWithExactName:
        [[self class] replacementTimeZoneNameForName:tzName] data:aData];
}

+ (NSString *)replacementTimeZoneNameForName:(NSString *)name {
    NSString *resourceDirectory;
    NSString *path;
    NSDictionary *oldNames;
    NSString *replacement;

    resourceDirectory = _NSFoundationResourceDirectory();
    path = [resourceDirectory stringByAppendingPathComponent:@"TimeZoneInfo"];
    if (name == nil)
        return nil;
    path = [path stringByAppendingPathComponent:@"OldTZToNewTZ.table"];
    oldNames = [[NSDictionary allocWithZone:NULL] initWithContentsOfFile:path];
    if (oldNames == nil) {
        NSLog(@"%@: Cannot load time zone old name mapping table %@",
            _NSMethodExceptionProem(self, _cmd), path);
        return name;
    }
    replacement = [[oldNames objectForKey:name] retain];
    [oldNames release];
    return replacement != nil ? [replacement autorelease] : name;
}

+ (NSData *)dataForTimeZone:(NSString *)name {
    NSString *resourceDirectory;
    NSString *path;
    NSData *data;
    unsigned index;

    if (name == nil)
        return nil;
    resourceDirectory = _NSFoundationResourceDirectory();
    path = [[resourceDirectory stringByAppendingPathComponent:@"TimeZoneInfo"]
        stringByAppendingPathComponent:name];
    data = [NSData dataWithContentsOfFile:path];
    if (data != nil)
        return data;

    for (index = 0; index < _NSTimeZoneData.count; index++) {
        NSString *canonicalName = [NSString stringWithCString:
            NSTimeZoneCanonicalNameAtIndex(index)];

        if ([name isEqualToString:canonicalName]) {
            unsigned start = _NSTimeZoneData.offsets[
                NSTimeZoneNameOffsetCount + index];
            unsigned end = _NSTimeZoneData.offsets[
                NSTimeZoneNameOffsetCount + index + 1];

            return [NSData dataWithBytes:_NSTimeZoneData.data + start
                                  length:end - start];
        }
    }
    data = [NSData dataWithContentsOfFile:name];
    return data;
}

+ (id)timeZoneWithAbbreviation:(NSString *)abbreviation {
    NSString *name = [[self abbreviationDictionary] objectForKey:abbreviation];
    NSTimeZone *timeZone = [[self allocWithZone:NULL] initWithName:name];

    return [timeZone autorelease];
}

@end


@implementation NSTimeZone (NSBackwardsCompatibility)

+ (NSArray *)timeZoneArray {
    return @"( (\"GMT-10\", US/Hawaii), (\"GMT-9\", US/Alaska), (\"GMT-8\", US/Pacific, \"US/Pacific-New\", Canada/Pacific), (\"GMT-7\", US/Mountain, US/Arizona, Canada/Mountain), (\"GMT-6\", US/Central, Canada/Central, \"Canada/East-Saskatchewan\"), (\"GMT-5\", US/Eastern, \"US/East-Indiana\", Canada/Eastern), (\"GMT-4\", Canada/Atlantic), (\"GMT-3\", Canada/Newfoundland), (\"GMT-2\"), (\"GMT-1\"), (Greenwich, GB, Eire, Iceland, WET), (\"GMT+1\", Poland, MET, CET), (\"GMT+2\", EET), (\"GMT+3\", Turkey, \"W-SU\"), (), (\"GMT+4\"), (\"GMT+5\"), (), (\"GMT+6\"), (\"GMT+7\"), (\"GMT+8\", Singapore, Australia/West), (\"GMT+9\", Japan), (Australia/North, Australia/South), ( \"GMT+10\", Australia/Tasmania, Australia/Queensland, Australia/Victoria, Australia/NSW ), (\"GMT+11\"), (\"GMT+12\", NZ) )" propertyList];
}

- (NSString *)timeZoneAbbreviation {
    return [self abbreviation];
}

- (NSArray *)timeZoneDetailArray {
    return [NSArray array];
}

- (NSTimeZoneDetail *)timeZoneDetailForDate:(NSDate *)date {
    return [self timeZoneForDate:date];
}

- (NSTimeZone *)timeZoneForDate:(NSDate *)date {
    int offset = [self secondsFromGMTForDate:date];
    NSString *abbreviation = [self abbreviationForDate:date];
    NSTimeZone *timeZone = __NSConcoctFixedTimeZone(offset,
        [abbreviation lossyCString], [self isDaylightSavingTimeForDate:date]);
    return [timeZone autorelease];
}

- (NSString *)timeZoneName {
    return [self name];
}

- (int)timeZoneSecondsFromGMT {
    return [self secondsFromGMT];
}

- (BOOL)isDaylightSavingTimeZone {
    return [self isDaylightSavingTime];
}

@end

@implementation NSTimeZoneDetailDecoder

- (id)initWithCoder:(NSCoder *)coder {
    NSString *name = nil;
    NSString *abbreviation = nil;
    int offset = 0;
    BOOL daylight = NO;
    NSTimeZone *timeZone;

    [self dealloc];
    [coder decodeValueOfObjCType:"@" at:&name];
    [coder decodeValueOfObjCType:"@" at:&abbreviation];
    [coder decodeValueOfObjCType:"i" at:&offset];
    timeZone = [NSTimeZone timeZoneWithName:name];
    if (timeZone != nil)
        daylight = [timeZone isDaylightSavingTimeForDate:[NSDate date]];
    [name autorelease];
    [abbreviation autorelease];
    return __NSConcoctFixedTimeZone(offset, [abbreviation lossyCString],
                                   daylight);
}

@end

@implementation NSWindowsDefaultTimeZoneDecoder

- (id)initWithCoder:(NSCoder *)coder {
    (void)coder;
    [self dealloc];
    NSLog(@"%@: Unarchiving a NSWindowsDefaultTimeZone; returning default time zone",
          _NSMethodExceptionProem(self, _cmd));
    return [[NSTimeZone defaultTimeZone] retain];
}

@end
