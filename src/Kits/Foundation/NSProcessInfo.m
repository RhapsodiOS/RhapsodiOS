/*	NSProcessInfo.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSHost.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSZone.h>
#import "NSProcessInfoPrivate.h"

#include <crt_externs.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

static NSProcessInfo *NSProcessInfoCache;
static int NSProcessInfoUniqueStringCounter = -1;
static NSString *NSProcessInfoUniqueStringPrototype;
static NSDictionary *NSProcessInfoPlatformMap;
static char *NSProcessInfoCachedProcessPath;
static char *NSProcessInfoCachedProcessName;
extern NSLock *_NSTempFileCounterLock;
extern NSLock *_NSUniqueStringCounterLock;

@interface NSProcessInfo (NSProcessInfoPrivate)
- (NSDictionary *)platformOSDictionary;
@end

int _NSArgc(void) {
    return *_NSGetArgc();
}

char **_NSArgv(void) {
    return *_NSGetArgv();
}

char **_NSEnviron(void) {
    return *_NSGetEnviron();
}

NSProcessInfoCurrentTime _NSCurrentTime(void) {
    struct timeval now;

    gettimeofday(&now, NULL);
    return 0.000001 * (NSProcessInfoCurrentTime)now.tv_usec
        + (NSProcessInfoCurrentTime)(now.tv_sec - 978307200);
}

time_t _NSCurrentUNIXTime(void) {
    struct timeval now;

    gettimeofday(&now, NULL);
    return now.tv_sec;
}

int _NSProcessID(void) {
    return (int)getpid();
}

char *_NSGetEnvironmentVariable(const char *name) {
    char **variables = _NSEnviron();

    if (name == NULL || variables == NULL)
        return NULL;
    while (*variables != NULL) {
        const char *entry = *variables++;
        const char *requestedName = name;

        while (*requestedName == *entry) {
            ++requestedName;
            ++entry;
        }
        if (*requestedName == '\0' && *entry == '=')
            return (char *)entry + 1;
    }
    return NULL;
}

int _NSGetDirectory2(char *path, size_t size) {
    return getcwd(path, size) != NULL;
}

char *_NSSearchForNameInPath(const char *name, char *path) {
    size_t nameLength = strlen(name);
    size_t pathLength = strlen(path);
    char *candidate = (char *)NSZoneMalloc(NULL, (unsigned)(pathLength + nameLength + 2));
    char *component = path;

    while (component != NULL) {
        char *separator = strchr(component, ':');
        size_t directoryLength;
        struct stat status;

        if (separator != NULL)
            *separator = '\0';
        directoryLength = strlen(component);
        memcpy(candidate, component, directoryLength);
        candidate[directoryLength] = '/';
        memcpy(candidate + directoryLength + 1, name, nameLength + 1);
        if (stat(candidate, &status) == 0
            && (status.st_mode & S_IFMT) == S_IFREG) {
            if (separator != NULL)
                *separator = ':';
            return candidate;
        }
        if (separator == NULL) {
            free(candidate);
            return NULL;
        }
        *separator = ':';
        component = separator + 1;
    }

    return candidate;
}

static char *NSProcessInfoCopyPath(const char *path) {
    size_t length = strlen(path);
    char *copy = (char *)NSZoneMalloc(NULL, (unsigned)(length + 1));

    memcpy(copy, path, length + 1);
    return copy;
}

char *_NSProcessPath(void) {
    const char *path;
    char **arguments;
    char *resolvedPath = NULL;
    char pathBuffer[1026];
    struct stat status;

    if (NSProcessInfoCachedProcessPath != NULL)
        return NSProcessInfoCachedProcessPath;

    path = _NSGetEnvironmentVariable("NSProcessPath");
    if (path != NULL) {
        NSProcessInfoCachedProcessPath = NSProcessInfoCopyPath(path);
        if (NSProcessInfoCachedProcessPath != NULL)
            return NSProcessInfoCachedProcessPath;
    }

    arguments = _NSArgv();
    path = arguments[0];

    {
        char *searchPath = _NSGetEnvironmentVariable("PATH");

        if (searchPath != NULL && strchr(path, '/') == NULL)
            resolvedPath = _NSSearchForNameInPath(path, searchPath);
        if (resolvedPath != NULL) {
            if (resolvedPath[0] != '/' && _NSGetDirectory2(pathBuffer,
                                                          sizeof(pathBuffer))) {
                strcat(pathBuffer, "/");
                strcat(pathBuffer, resolvedPath);
                if (stat(pathBuffer, &status) == 0) {
                    NSZoneFree(NULL, resolvedPath);
                    resolvedPath = pathBuffer;
                }
            }
            if (resolvedPath != NULL) {
                NSProcessInfoCachedProcessPath = NSProcessInfoCopyPath(resolvedPath);
                if (resolvedPath != pathBuffer)
                    NSZoneFree(NULL, resolvedPath);
                if (NSProcessInfoCachedProcessPath == NULL)
                    NSProcessInfoCachedProcessPath = "";
                return NSProcessInfoCachedProcessPath;
            }
        }
    }

    if (_NSGetDirectory2(pathBuffer, sizeof(pathBuffer))) {
        strcat(pathBuffer, "/");
        strcat(pathBuffer, path);
        if (stat(pathBuffer, &status) == 0)
            resolvedPath = pathBuffer;
    }

    if (resolvedPath == NULL) {
        arguments = _NSArgv();
        resolvedPath = arguments[0];
        if (resolvedPath == NULL) {
            NSProcessInfoCachedProcessPath = "";
            return NSProcessInfoCachedProcessPath;
        }
    }
    NSProcessInfoCachedProcessPath = NSProcessInfoCopyPath(resolvedPath);
    if (NSProcessInfoCachedProcessPath == NULL)
        NSProcessInfoCachedProcessPath = "";
    return NSProcessInfoCachedProcessPath;
}

char *_NSProcessName(void) {
    const char *processPath;
    const char *lastSlash;

    if (NSProcessInfoCachedProcessName == NULL) {
        processPath = _NSProcessPath();
        lastSlash = strrchr(processPath, '/');
        if (lastSlash != NULL)
            processPath = lastSlash + 1;
        NSProcessInfoCachedProcessName = NSProcessInfoCopyPath(processPath);
        if (NSProcessInfoCachedProcessName == NULL)
            NSProcessInfoCachedProcessName = "";
    }
    return NSProcessInfoCachedProcessName;
}

@implementation NSProcessInfo

+ (NSProcessInfo *)processInfo {
    if (NSProcessInfoCache == nil)
        NSProcessInfoCache = [[NSProcessInfo allocWithZone:NULL] init];
    return NSProcessInfoCache;
}

- (NSDictionary *)environment {
    char **variables;
    NSMutableDictionary *values;

    if (environment != nil)
        return environment;

    variables = _NSEnviron();
    if (variables == NULL)
        return [NSDictionary dictionary];

    values = [[NSMutableDictionary allocWithZone:NULL] init];
    while (*variables != NULL) {
        const char *entry = *variables++;
        const char *separator = strchr(entry, '=');
        unsigned keyLength = separator != NULL
            ? (unsigned)(separator - entry) : (unsigned)strlen(entry);
        NSString *key = [[NSString allocWithZone:NULL]
            initWithCString:entry length:keyLength];

        if (separator != NULL) {
            unsigned valueLength = (unsigned)strlen(separator + 1);
            NSString *value = [[NSString allocWithZone:NULL]
                initWithCString:separator + 1 length:valueLength];

            [values setObject:value forKey:key];
            [value release];
        }
        [key release];
    }

    environment = [[NSDictionary allocWithZone:NULL] initWithDictionary:values];
    [values release];
    return environment;
}

- (NSArray *)arguments {
    int argumentCount;
    int objectCount;
    int index;
    char **processArguments;
    id stackObjects[256];
    id *objects;
    const char *path;
    const char *argument;
    NSString *argumentString;

    if (arguments != nil)
        return arguments;

    argumentCount = _NSArgc();
    processArguments = _NSArgv();
    path = _NSProcessPath();
    objectCount = 1;
    objects = argumentCount > 256
        ? (id *)NSZoneMalloc(NULL, (unsigned)(sizeof(id) * argumentCount))
        : stackObjects;

    if (processArguments != NULL) {
        for (index = 1; index < argumentCount; index++) {
            if (processArguments[index] == NULL)
                break;
            argument = processArguments[index];
            argumentString = [[NSString allocWithZone:NULL]
                initWithCString:argument length:(unsigned)strlen(argument)];
#if defined(__ppc__) || defined(__POWERPC__)
            argumentString = [argumentString stringByStandardizingPath];
#endif
            objects[objectCount++] = argumentString;
        }
    }

#if defined(__ppc__) || defined(__POWERPC__)
    argumentString = [[NSString allocWithZone:NULL]
        initWithCString:path length:(unsigned)strlen(path)];
    objects[0] = [argumentString stringByStandardizingPath];
#else
    objects[0] = [[NSString stringWithCString:path
                                       length:(unsigned)strlen(path)]
        stringByStandardizingPath];
#endif

    arguments = [[NSArray allocWithZone:NULL]
        initWithObjects:objects count:(unsigned)objectCount];
    for (index = 1; index < objectCount; index++)
        [objects[index] release];
    if (objects != stackObjects)
        NSZoneFree(NULL, objects);
    return arguments;
}

- (void)setArguments:(NSArray *)newArguments {
    [newArguments retain];
    if (arguments != nil)
        [arguments release];
    arguments = newArguments;
}

- (NSString *)hostName {
    if (hostName == nil) {
#if defined(__ppc__) || defined(__POWERPC__)
        hostName = [NSHostName() retain];
#else
        hostName = [[NSHost currentHost] name];
#endif
    }
    return hostName;
}

- (NSString *)processName {
    if (name == nil) {
#if defined(__ppc__) || defined(__POWERPC__)
        const char *processName = _NSProcessName();
        NSString *processNameString = [NSString allocWithZone:NULL];
        unsigned processNameLength = (unsigned)strlen(processName);

        name = [[processNameString initWithCString:processName
                                           length:processNameLength] autorelease];
#else
        unsigned processNameLength = (unsigned)strlen(_NSProcessName());
        const char *processName = _NSProcessName();
        NSString *processNameString = [NSString allocWithZone:NULL];

        name = [processNameString initWithCString:processName
                                           length:processNameLength];
#endif
    }
    return name;
}

- (void)setProcessName:(NSString *)newName {
#if defined(__ppc__) || defined(__POWERPC__)
    [name release];
#else
    [name autorelease];
#endif
    name = [newName copyWithZone:NULL];
}

- (NSString *)userFullName {
    return NSFullUserName();
}

- (NSString *)userHomeDirectory {
    return NSHomeDirectory();
}

- (NSString *)userName {
    return NSUserName();
}

- (NSString *)globallyUniqueString {
    int counter;

    if (_NSTempFileCounterLock != nil)
        [_NSUniqueStringCounterLock lock];
    NSProcessInfoUniqueStringCounter = (int)((unsigned)NSProcessInfoUniqueStringCounter + 1);
    counter = NSProcessInfoUniqueStringCounter;
    if (counter <= 0) {
        int seconds;
        int processID;
#if defined(__ppc__) || defined(__POWERPC__)
        unsigned processNameLength;
#else
        const char *processNameCString;
#endif
        NSString *currentHostName;
        NSString *processName;
        NSString *prototype;

        seconds = (int)_NSCurrentTime();
        currentHostName = [self hostName];
        NSProcessInfoUniqueStringCounter = 1;
        counter = 1;
        [NSProcessInfoUniqueStringPrototype release];
        if (seconds < 0)
            seconds = -seconds;
#if defined(__ppc__) || defined(__POWERPC__)
        prototype = [NSString allocWithZone:NULL];
        processID = _NSProcessID();
        processName = [self processName];
        processNameLength = [processName length];
        NSProcessInfoUniqueStringPrototype = [prototype
            initWithFormat:@"%@_%d_%d_%d_",
                           currentHostName != nil ? currentHostName : @"",
                           processID, seconds, processNameLength];
#else
        processName = [self processName];
        processNameCString = [processName cString];
        processID = _NSProcessID();
        prototype = [NSString allocWithZone:NULL];
        NSProcessInfoUniqueStringPrototype = [prototype
            initWithFormat:@"%@_%d_%d_%d_",
                           currentHostName != nil ? currentHostName : @"",
                           processID, seconds, (int)processNameCString];
#endif
    }
    if (_NSTempFileCounterLock != nil)
        [_NSUniqueStringCounterLock unlock];
    return [NSProcessInfoUniqueStringPrototype stringByAppendingFormat:@"%d", counter];
}

- (unsigned int)operatingSystem {
    return NSMACHOperatingSystem;
}

- (NSDictionary *)platformOSDictionary {
    if (NSProcessInfoPlatformMap == nil) {
        NSProcessInfoPlatformMap = [[NSDictionary allocWithZone:NULL]
            initWithObjectsAndKeys:
                @"win32", @"NSWindowsNTOperatingSystem",
                @"win32", @"NSWindows95OperatingSystem",
                @"mach", @"NSMACHOperatingSystem",
                @"solaris", @"NSSolarisOperatingSystem",
                @"hpux", @"NSHPUXOperatingSystem",
                nil];
    }
    return NSProcessInfoPlatformMap;
}

- (NSString *)operatingSystemName {
    switch ([self operatingSystem]) {
        case NSWindowsNTOperatingSystem: return @"NSWindowsNTOperatingSystem";
        case NSWindows95OperatingSystem: return @"NSWindows95OperatingSystem";
        case NSSolarisOperatingSystem: return @"NSSolarisOperatingSystem";
        case NSHPUXOperatingSystem: return @"NSHPUXOperatingSystem";
        case NSMACHOperatingSystem: return @"NSMACHOperatingSystem";
        default: return @"NSUnknownOperatingSystem";
    }
}

- (void)dealloc {
    [environment release];
    [arguments release];
    [hostName release];
    [name release];
    [super dealloc];
}

@end
