/*	NSBundle.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSSerialization.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSData.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSJavaSetup.h>
#import <objc/objc-runtime.h>
#import <objc/objc-load.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern id __NSEmptyArray;
extern unsigned _NSStartOfPathExtension(const unichar *characters,
                                        unsigned length);
extern int NSCompareCharacters(const unichar *left, const unichar *right,
                               unsigned leftLength, unsigned rightLength,
                               unsigned options);

#if defined(__ppc__) || defined(__POWERPC__)
extern int _usesFastJavaBundleSetup;
#endif

static NSBundle *fouBundle_278;
static NSBundle *NSBundleMainBundle;
static BOOL NSBundleMainBundleTried;
static NSMutableDictionary *NSBundleResolvedPathToBundle;
static NSMutableArray *NSBundleLoadedBundles;
static NSMutableArray *NSBundleLoadedFrameworks;
static NSMutableArray *NSBundleStaticFrameworks;
#if defined(__ppc__) || defined(__POWERPC__)
static NSMutableDictionary *NSBundleJavaBundlesMap;
#endif
NSRecursiveLock *_NSBundleDataLock;
static int NSBundleLocalizedStringDebugOptions = -1;
static BOOL NSBundleCodeLoadEnabled = YES;
BOOL NSSafeBundleLoadingRead;
BOOL NSSafeBundleLoading;
BOOL NSPrintDynamicClassLoadsRead;
BOOL NSPrintDynamicClassLoads;
static Class *NSBundleLoadingClasses;
static unsigned NSBundleLoadingClassCount;
static unsigned NSBundleLoadingClassCapacity;

void NSBundleDisableCodeLoading(void)
{
    NSBundleCodeLoadEnabled = NO;
}

static BOOL _NSBundleLoadJavaCode(NSBundle *bundle, unsigned *flags,
                                  Class *principalClass,
                                  NSString **errorString);

NSString * const NSBundleDidLoadNotification = @"NSBundleDidLoadNotification";
NSString * const NSLoadedClasses = @"NSLoadedClasses";
NSString * const NSBundleInitialPath = @"NSBundleInitialPath";
NSString * const NSBundleResolvedPath = @"NSBundleResolvedPath";
NSString * const NSBundleExecutablePath = @"NSBundleExecutablePath";
NSString * const NSBundleResourcePath = @"NSBundleResourcePath";
NSString * const NSBundleLanguagesList = @"NSBundleLanguagesList";
NSString * const NSBundleDefaultsDictionary = @"NSBundleDefaultsDictionary";
NSString * const NSBundleStringTableTable = @"NSBundleStringTableTable";
NSString * const NSBundleResources = @"NSBundleResources";
NSString * const NSExecutable = @"NSExecutable";
NSString * const NSPrincipalClass = @"NSPrincipalClass";

@interface NSDebugString : NSString {
    NSString *string;
}
- (id)initWithString:(NSString *)aString;
@end

@implementation NSDebugString

- (id)initWithString:(NSString *)aString {
    self = [super init];
    string = [aString copyWithZone:[self zone]];
    return self;
}

- (unsigned)length {
    return [string length];
}

- (unichar)characterAtIndex:(unsigned)index {
    return [string characterAtIndex:index];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    [string getCharacters:buffer range:range];
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (void)dealloc {
    [string release];
    [super dealloc];
}

@end

int _NSIsLocalizedString(id string)
{
    return [string isKindOfClass:[NSDebugString class]];
}

id _NSLocalizedString(id string)
{
    if (_NSIsLocalizedString(string))
        return string;
    return [[[NSDebugString allocWithZone:NULL] initWithString:string]
        autorelease];
}

typedef struct {
    unsigned long start;
    unsigned long end;
    unsigned long imageIndex;
} NSBundleObjCImageRange;

static NSBundleObjCImageRange *NSBundleObjCImageRanges;
static unsigned NSBundleObjCImageRangeCount;
static unsigned NSBundleObjCImageRangeCapacity;
static unsigned NSBundleObjCImageCount;

extern char *_NSProcessPath(void);
extern Class objc_getOrigClass(const char *name);
extern NSString *_NSMapTableDescribeCString(NSMapTable *table,
                                             const void *key);

static NSBundle *NSBundleLookupOrCreate(NSString *path, BOOL cacheBundle,
    BOOL addToLoadedList, NSBundle *bundle, Class bundleClass, NSZone *zone);
static id initWithPathRecordNoLock(NSBundle *bundle, NSString *path,
    NSString *resolvedPath, BOOL addToLoadedList);
static void NSBundleLoadCallback(Class aClass, Category category);
static void NSBundleAddClassesAndNotify(Class *classes, unsigned count);
static BOOL NSBundleCouldBeBundle(NSString *path);
@interface NSNotificationCenter (NSBundlePrivate)
- (unsigned int)countObserversName:(NSString *)aName object:(id)anObject
                          literally:(BOOL)literally;
- (void)_bundleLoaded;
@end

static BOOL NSBundleLoadCode(NSString *executablePath, unsigned bundleType,
    NSString *bundlePath, NSString **errorString);

extern char *_NSGetEnvironmentVariable(const char *name);
extern id _NSMethodExceptionProem(id object, SEL selector);
extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);
extern NSLock *_NSGlobalRetainLock;

static const char *NSBundleLibraryPathForClass(Class aClass) {
    unsigned imageCount = (unsigned)_dyld_image_count();
    unsigned capacity = imageCount > 0 ? imageCount - 1 : 0;
    unsigned imageIndex;

    if (NSBundleObjCImageRanges == NULL
        || NSBundleObjCImageCount != imageCount) {
        if (NSBundleObjCImageRanges != NULL)
            NSZoneFree(NULL, NSBundleObjCImageRanges);
        NSBundleObjCImageRangeCapacity = capacity;
        NSBundleObjCImageRanges = capacity != 0
            ? (NSBundleObjCImageRange *)NSZoneMalloc(NULL,
                capacity * sizeof(NSBundleObjCImageRange)) : NULL;
        if (NSBundleObjCImageRanges == NULL)
            NSBundleObjCImageRangeCapacity = 0;
        NSBundleObjCImageRangeCount = 0;
        NSBundleObjCImageCount = imageCount;

        for (imageIndex = 1; imageIndex < imageCount; imageIndex++) {
            const struct mach_header *header =
                _dyld_get_image_header(imageIndex);
            const struct load_command *command;
            unsigned commandIndex;
            unsigned long slide =
                _dyld_get_image_vmaddr_slide(imageIndex);

            if (header == NULL || NSBundleObjCImageRanges == NULL)
                continue;
            command = (const struct load_command *)(header + 1);
            for (commandIndex = 0; commandIndex < header->ncmds;
                 commandIndex++) {
                if (command->cmd == LC_SEGMENT) {
                    const struct segment_command *segment =
                        (const struct segment_command *)command;

                    if (strcmp(segment->segname, "__OBJC") == 0) {
                        if (NSBundleObjCImageRangeCount
                            == NSBundleObjCImageRangeCapacity) {
                            unsigned newCapacity =
                                NSBundleObjCImageRangeCapacity != 0
                                ? NSBundleObjCImageRangeCapacity * 2 : 4;
                            NSBundleObjCImageRange *newRanges =
                                (NSBundleObjCImageRange *)NSZoneRealloc(NULL,
                                    NSBundleObjCImageRanges,
                                    newCapacity * sizeof(NSBundleObjCImageRange));

                            if (newRanges != NULL) {
                                NSBundleObjCImageRanges = newRanges;
                                NSBundleObjCImageRangeCapacity = newCapacity;
                            }
                        }
                        if (NSBundleObjCImageRangeCount
                            < NSBundleObjCImageRangeCapacity) {
                            NSBundleObjCImageRange *range =
                                &NSBundleObjCImageRanges[
                                    NSBundleObjCImageRangeCount++];
                            range->start = segment->vmaddr + slide;
                            range->end = segment->vmaddr + segment->vmsize + slide;
                            range->imageIndex = imageIndex;
                        }
                    }
                }
                command = (const struct load_command *)
                    ((const char *)command + command->cmdsize);
            }
        }
    }

    for (imageIndex = 0; imageIndex < NSBundleObjCImageRangeCount;
         imageIndex++) {
        NSBundleObjCImageRange *range = &NSBundleObjCImageRanges[imageIndex];
        unsigned long classAddress = (unsigned long)aClass;

        if (range->start <= classAddress && classAddress < range->end)
            return _dyld_get_image_name(range->imageIndex);
    }
    return _dyld_get_image_name(0);
}

static NSString *NSBundleFrameworkPathForLibraryPath(NSString *libraryPath) {
    NSString *path;

    if (libraryPath == nil)
        return nil;
    path = [libraryPath stringByDeletingLastPathComponent];
    if ([[path pathExtension] isEqualToString:@"framework"])
        return NSBundleCouldBeBundle(path) ? path : nil;
    {
        NSString *versionsPath = [path stringByDeletingLastPathComponent];

        if ([[versionsPath lastPathComponent] isEqualToString:@"Versions"]) {
            NSString *frameworkPath =
                [versionsPath stringByDeletingLastPathComponent];

            if ([[frameworkPath pathExtension] isEqualToString:@"framework"]
                && NSBundleCouldBeBundle(frameworkPath))
                return frameworkPath;
        }
    }
    return nil;
}

static void NSBundleLoadCallback(Class aClass, Category category) {
    if (category == NULL) {
        if (NSBundleLoadingClassCount == NSBundleLoadingClassCapacity) {
            NSBundleLoadingClassCapacity =
                2 * NSBundleLoadingClassCount + 1;
            NSBundleLoadingClasses = (Class *)NSZoneRealloc(NULL,
                NSBundleLoadingClasses,
                NSBundleLoadingClassCapacity * sizeof(Class));
        }
        NSBundleLoadingClasses[NSBundleLoadingClassCount++] = aClass;
    }

    if (!NSPrintDynamicClassLoadsRead) {
        NSPrintDynamicClassLoadsRead = YES;
        NSPrintDynamicClassLoads =
            _NSGetEnvironmentVariable("NSPrintDynamicClassLoads") != NULL;
    }
    if (NSPrintDynamicClassLoads) {
        if (category != NULL)
            NSLog(@"*** NSBundle loaded class '%s' (0x%x), category '%s' (0x%x)",
                  aClass->name, (unsigned)aClass, category->category_name,
                  (unsigned)category);
        else
            NSLog(@"*** NSBundle loaded class '%s' (0x%x)", aClass->name,
                  (unsigned)aClass);
    }
}

static void NSBundleAddClassesAndNotify(Class *classes, unsigned count) {
    NSBundle **bundles;
    const char *lastLibraryPath = NULL;
    NSBundle *lastBundle = nil;
    unsigned index;
    NSNotificationCenter *center;

    bundles = (NSBundle **)NSZoneMalloc(NULL, count * sizeof(NSBundle *));
    if (count != 0 && bundles == NULL)
        return;
    if (bundles != NULL)
        memset(bundles, 0, count * sizeof(NSBundle *));

    for (index = count; index != 0; index--) {
        unsigned classIndex = index - 1;
        Class aClass = classes[classIndex];
        Class originalClass = objc_getOrigClass(aClass->name);
        const char *libraryPath = NSBundleLibraryPathForClass(originalClass);
        NSBundle *bundle = nil;

        if (libraryPath == NULL)
            continue;
        if (lastLibraryPath == libraryPath) {
            bundle = lastBundle;
        } else {
#if defined(__ppc__) || defined(__POWERPC__)
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSString *path = [fileManager stringWithFileSystemRepresentation:
                libraryPath length:(unsigned)strlen(libraryPath)];
#else
            NSString *path = [NSString stringWithCString:libraryPath
                length:(unsigned)strlen(libraryPath)];
#endif
            NSString *bundlePath =
                NSBundleFrameworkPathForLibraryPath(path);

            if (bundlePath == nil)
                bundlePath = [path stringByDeletingLastPathComponent];
            bundle = NSBundleLookupOrCreate(bundlePath, YES, YES, nil,
                [NSBundle class], NULL);
            if (bundle != nil) {
                bundle->_flags |= 0x2000000;
                if ((bundle->_flags & 0xF0000) == 0x40000)
                    bundle->_flags |= 0x4000000;
            }
            lastLibraryPath = libraryPath;
            lastBundle = bundle;
        }

        if (bundle != nil) {
            bundles[classIndex] = bundle;
            if (bundle->_principalClass == Nil)
                bundle->_principalClass = aClass;
        }
    }

    center = [NSNotificationCenter defaultCenter];
    [center _bundleLoaded];
    center = [NSNotificationCenter defaultCenter];
    if ([center countObserversName:NSBundleDidLoadNotification object:nil
                         literally:NO] != 0) {
        for (index = count; index != 0; index--) {
            unsigned classIndex = index - 1;
            NSBundle *bundle = bundles[classIndex];
            NSMutableArray *classNames;
            unsigned scanIndex;

            if (bundle == nil)
                continue;
            classNames = [[NSMutableArray allocWithZone:NULL]
                initWithCapacity:4];
            for (scanIndex = index; scanIndex != 0; scanIndex--) {
                unsigned candidateIndex = scanIndex - 1;
                if (bundles[candidateIndex] == bundle) {
                    [classNames addObject:
                        NSStringFromClass(classes[candidateIndex])];
                    bundles[candidateIndex] = nil;
                }
            }
            [center postNotificationName:NSBundleDidLoadNotification
                object:bundle userInfo:[NSDictionary
                    dictionaryWithObjectsAndKeys:classNames,
                        NSLoadedClasses, nil]];
            [classNames release];
        }
    }

    NSZoneFree(NULL, bundles);
}

static BOOL NSBundleLoadCode(NSString *executablePath, unsigned bundleType,
    NSString *bundlePath, NSString **errorString) {
    char pathName[1028];

    if (errorString != NULL)
        *errorString = nil;
    if (!NSBundleCodeLoadEnabled) {
        if (errorString != NULL)
            *errorString = @"Dynamic loading of code is disabled";
        return NO;
    }
    if (![executablePath getFileSystemRepresentation:pathName maxLength:
            1024]) {
        if (errorString != NULL)
            *errorString = [NSString stringWithFormat:
                @"*** Couldn't convert path '%@' to file system representation",
                executablePath];
        return NO;
    }

    if (bundleType == 0x40000) {
        NXHashTable *before = objc_getClasses();
        unsigned beforeCount = NXCountHashTable(before);
        Class *oldClasses = (Class *)NSZoneMalloc(NULL,
            beforeCount * sizeof(Class));
        NXHashState state = NXInitHashState(before);
        unsigned oldCount = 0;
        void *classObject;
        BOOL loaded;

        while (NXNextHashState(before, &state, &classObject))
            oldClasses[oldCount++] = (Class)classObject;
        loaded = NSAddLibrary(pathName);
        if (loaded) {
            NXHashTable *after = objc_getClasses();
            unsigned afterCount = NXCountHashTable(after);
            Class *newClasses = (Class *)NSZoneMalloc(NULL,
                (afterCount - beforeCount) * sizeof(Class));
            unsigned newCount = 0;

            state = NXInitHashState(after);
            while (NXNextHashState(after, &state, &classObject)) {
                unsigned oldIndex;
                BOOL existed = NO;
                for (oldIndex = 0; oldIndex < oldCount; oldIndex++) {
                    if (oldClasses[oldIndex] == (Class)classObject) {
                        existed = YES;
                        break;
                    }
                }
                if (!existed)
                    newClasses[newCount++] = (Class)classObject;
            }
            NSBundleAddClassesAndNotify(newClasses, newCount);
            if (newClasses != NULL)
                NSZoneFree(NULL, newClasses);
        } else if (errorString != NULL) {
            *errorString = @"Couldn't dynamically load framework code";
        }
        if (oldClasses != NULL)
            NSZoneFree(NULL, oldClasses);
        return loaded;
    }

    {
        char *moduleList[2];
        long loadError;

        moduleList[0] = pathName;
        moduleList[1] = NULL;
        if (!NSSafeBundleLoadingRead) {
            NSSafeBundleLoadingRead = YES;
            NSSafeBundleLoading = [[NSUserDefaults standardUserDefaults]
                boolForKey:@"NSSafeBundleLoading"];
        }
        if (NSSafeBundleLoading) {
            pid_t child = vfork();
            if (child == -1) {
                if (errorString != NULL)
                    *errorString = @"Couldn't dynamically load code (fork failure)";
                return NO;
            }
            if (child == 0) {
                objc_loadModules(moduleList, NULL, NSBundleLoadCallback,
                                 NULL, NULL);
                _exit(0);
            }
            {
                int status;
                while (wait4(child, &status, 0, NULL) < 0) {
                    if (errno != EINTR) {
                        if (errorString != NULL)
                            *errorString = @"Couldn't dynamically load code (wait failure)";
                        return NO;
                    }
                }
                if ((status >> 8) != 0) {
                    if (errorString != NULL)
                        *errorString = @"Couldn't dynamically load code (dyld failure)";
                    return NO;
                }
            }
        }

        loadError = objc_loadModules(moduleList, NULL, NSBundleLoadCallback,
                                     NULL, NULL);
        if (loadError == 0) {
            NSBundleAddClassesAndNotify(NSBundleLoadingClasses,
                                        NSBundleLoadingClassCount);
        } else if (![[bundlePath pathExtension]
                      isEqualToString:@"framework"] && errorString != NULL) {
            *errorString = [NSString stringWithFormat:
                @"Error loading code %@ for bundle %@", executablePath,
                bundlePath];
        }
        if (NSBundleLoadingClasses != NULL)
            NSZoneFree(NULL, NSBundleLoadingClasses);
        NSBundleLoadingClasses = NULL;
        NSBundleLoadingClassCount = 0;
        NSBundleLoadingClassCapacity = 0;
        return loadError == 0;
    }
}

static void NSBundleInitializeStaticFrameworks(void) {
    NSAutoreleasePool *pool;
    NXHashTable *classes;
    NXHashState state;
    Class bundleClass;
    NSBundle *mainBundle;
    NSMapTableKeyCallBacks keyCallBacks;
    NSMapTable *pathsToBundles;
    const char *lastLibraryPath = NULL;
    NSBundle *lastBundle = nil;
    void *classObject;

    pool = [[NSAutoreleasePool allocWithZone:NULL] init];
    bundleClass = objc_getClass("NSBundle");
    mainBundle = [NSBundle mainBundle];
    classes = objc_getClasses();
    keyCallBacks = NSNonOwnedPointerOrNullMapKeyCallBacks;
    keyCallBacks.hash = _NSMapTableHashCString;
    keyCallBacks.isEqual = _NSMapTableIsEqualCString;
    keyCallBacks.describe = _NSMapTableDescribeCString;
    pathsToBundles = NSCreateMapTableWithZone(keyCallBacks,
        NSNonRetainedObjectMapValueCallBacks, 3, NULL);
    NSBundleStaticFrameworks = [[NSMutableArray allocWithZone:NULL]
        initWithCapacity:8];
    state = NXInitHashState(classes);
    while (NXNextHashState(classes, &state, &classObject)) {
        Class aClass = (Class)classObject;
        Class originalClass = objc_getOrigClass(aClass->name);
        const char *libraryPath = NSBundleLibraryPathForClass(originalClass);
        NSBundle *bundle = nil;

        if (libraryPath == NULL)
            continue;
        if (lastLibraryPath == libraryPath) {
            bundle = lastBundle;
        } else if (!NSMapMember(pathsToBundles, libraryPath, NULL,
                                (void **)&bundle)) {
#if defined(__ppc__) || defined(__POWERPC__)
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSString *libraryPathString =
                [fileManager stringWithFileSystemRepresentation:libraryPath
                    length:(unsigned)strlen(libraryPath)];
#else
            NSString *libraryPathString = [NSString
                stringWithCString:libraryPath
                length:(unsigned)strlen(libraryPath)];
#endif
            NSString *bundlePath = NSBundleFrameworkPathForLibraryPath(
                libraryPathString);

            if (bundlePath == nil)
                bundlePath = [libraryPathString
                    stringByDeletingLastPathComponent];
            bundle = NSBundleLookupOrCreate(bundlePath, YES, NO, nil,
                bundleClass, NULL);
            if (bundle != nil) {
                NSMapInsert(pathsToBundles, libraryPath, bundle);
                bundle->_flags |= 0x6000000;
                if (bundle != mainBundle
                    && ![NSBundleLoadedBundles containsObject:bundle]
                    && ![NSBundleLoadedFrameworks containsObject:bundle]
                    && ![NSBundleStaticFrameworks containsObject:bundle]) {
                    bundle->_flags |= 0x30000;
                    [NSBundleStaticFrameworks addObject:bundle];
                }
                if (NSJavaProvidesClasses([bundle infoDictionary]))
                    bundle->_flags |= 0x10000000;
            }
        }
        lastLibraryPath = libraryPath;
        lastBundle = bundle;
    }

    NSFreeMapTable(pathsToBundles);
    [NSBundleLoadedBundles removeObject:mainBundle];
    {
        NSMutableArray *frameworks =
            [[NSBundleStaticFrameworks mutableCopy] autorelease];
        unsigned count;
        unsigned index;

        if (mainBundle != nil) {
            if (NSJavaProvidesClasses([mainBundle infoDictionary]))
                mainBundle->_flags |= 0x10000000;
            [frameworks insertObject:mainBundle atIndex:0];
        }
        count = [frameworks count];
        for (index = 0; index < count; index++) {
            NSBundle *bundle = [frameworks objectAtIndex:index];

            if (NSJavaNeedsToLoadClasses([bundle infoDictionary])) {
                NSString *errorString = nil;

                if (!_NSBundleLoadJavaCode(bundle, &bundle->_flags,
                                           &bundle->_principalClass,
                                           &errorString)
#if defined(__ppc__) || defined(__POWERPC__)
                    && ![NSBundle _usesFastJavaBundleSetup]
#endif
                    && errorString != nil)
                    NSLog(@"_NSInitializeStaticJavaFrameworks: %@",
                          errorString);
                break;
            }
        }
    }
    [pool release];
}

@interface NSBundle (NSBundlePrivate)
- (void)_initInfoDictionary;
- (NSString *)_computeExecutablePath;
- (NSArray *)bundleLanguages;
+ (NSArray *)findBundleResources:(NSBundle *)bundle
                    callingMethod:(SEL)selector
                         directory:(NSString *)directory
                         languages:(NSArray *)languages
                              name:(NSString *)name
                             types:(NSArray *)types
                             limit:(unsigned)limit;
@end

void _NSSetMainBundle(NSBundle *bundle) {
    id resolvedPath;

    if (bundle == nil || (bundle->_flags & 0xF0000) != 0x20000)
        return;
    if (NSBundleMainBundle != nil) {
        NSBundleMainBundle->_flags |= 0x20000;
        if (NSBundleLoadedBundles == nil)
            NSBundleLoadedBundles = [[NSMutableArray allocWithZone:NULL]
                initWithCapacity:4];
        [NSBundleLoadedBundles addObject:NSBundleMainBundle];
    }
    NSBundleMainBundle = [bundle retain];
    [NSBundleLoadedBundles addObject:bundle];
    if ((NSBundleMainBundle->_flags & 0x200000) == 0)
        [NSBundleMainBundle _initInfoDictionary];
    NSBundleMainBundle->_flags |= 0x10000;
    NSBundleMainBundle->_flags |= 0x2000000;
    resolvedPath = [NSBundleMainBundle->_infoDictionary
        objectForKey:@"NSBundleResolvedPath"];
    if (resolvedPath != nil)
        [NSBundleMainBundle->_infoDictionary setObject:resolvedPath
                                                forKey:@"NSBundleInitialPath"];
}

@interface NSFileManager (NSBundlePrivate)
- (BOOL)getFileSystemRepresentation:(char *)cname maxLength:(unsigned)max
                            withPath:(NSString *)path;
- (NSArray *)directoryContentsAtPath:(NSString *)path
                  matchingExtension:(NSString *)extension
                             options:(unsigned)options
                       keepExtension:(BOOL)keepExtension;
@end

static BOOL NSBundleIsResourceAtPath(NSFileManager *fileManager,
                                     NSString *path) {
    char filePath[1028];
    struct stat status;

    return path != nil &&
        [fileManager getFileSystemRepresentation:filePath maxLength:1024
                                         withPath:path] &&
        stat(filePath, &status) == 0 && (status.st_mode & 0x124) != 0;
}

static NSString *NSBundleResourcePath(NSFileManager *fileManager,
                                      NSString *directory, NSString *name,
                                      NSString *type, NSString *style,
                                      BOOL windowsStyle) {
    NSString *base = directory != nil
        ? [directory stringByAppendingPathComponent:name] : name;
    NSString *localizedName;
    NSString *localized;

    if (type != nil)
        base = [base stringByAppendingPathExtension:type];
    if (!NSBundleIsResourceAtPath(fileManager, base))
        return nil;
    localizedName = [name stringByAppendingString:@"-"];
    if (style != nil && [style length] != 0)
        localizedName = [localizedName stringByAppendingString:style];
    localized = directory != nil
        ? [directory stringByAppendingPathComponent:localizedName]
        : localizedName;
    if (type != nil)
        localized = [localized stringByAppendingPathExtension:type];
    if (NSBundleIsResourceAtPath(fileManager, localized))
        return localized;
    if (windowsStyle) {
        localizedName = [name stringByAppendingString:@"-winnt"];
        localized = directory != nil
            ? [directory stringByAppendingPathComponent:localizedName]
            : localizedName;
        if (type != nil)
            localized = [localized stringByAppendingPathExtension:type];
        if (NSBundleIsResourceAtPath(fileManager, localized))
            return localized;
    }
    return base;
}

static void NSBundleAppendDirectoryContents(NSMutableArray *results,
                                             NSFileManager *fileManager,
                                             NSString *directory,
                                             NSString *type,
                                             unsigned limit) {
    NSArray *contents = [fileManager
        directoryContentsAtPath:directory
              matchingExtension:type
                         options:0
                   keepExtension:YES];
    unsigned count = [contents count];
    unsigned index;

    for (index = 0; index < count; index++) {
        NSString *path = [directory stringByAppendingPathComponent:
            [contents objectAtIndex:index]];
        [results addObject:path];
        if ([results count] >= limit)
            return;
    }
}

id _NSParseStringsFile(NSString *path, BOOL logErrors) {
    NSData *data = [[NSData allocWithZone:NULL] initWithContentsOfFile:path];
    id result = nil;

    if (data == nil)
        return nil;

    {
        unsigned length = [data length];
        const unsigned char *bytes = [data bytes];

        if ((length & 3) == 0 && length > 7 && bytes[0] <= 0x1f &&
            bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0) {
            unsigned cursor = 0;
            result = [NSDeserializer
                deserializePropertyListFromData:data atCursor:&cursor
                mutableContainers:NO];
        } else {
            NSStringEncoding encoding;
            NSString *source;

            if (length > 1 && (length & 1) == 0 &&
                ((bytes[0] == 0xfe && bytes[1] == 0xff) ||
                 (bytes[0] == 0xff && bytes[1] == 0xfe)))
                encoding = NSUnicodeStringEncoding;
            else
                encoding = [NSString defaultCStringEncoding];
            source = [[NSString allocWithZone:NULL] initWithData:data
                                                        encoding:encoding];

            if (source != nil) {
                NS_DURING {
                    result = [source propertyListFromStringsFileFormat];
                } NS_HANDLER {
                    if ([[localException name]
                            isEqualToString:NSParseErrorException]) {
                        if (logErrors)
                            NSLog(@"Syntax error in strings file %@: %@", path,
                                  [localException reason]);
                        result = nil;
                    } else {
                        [source release];
                        [data release];
                        [localException raise];
                    }
                } NS_ENDHANDLER
            }
            [source release];
        }
    }

    [data release];
    return result;
}

static NSDictionary *NSBundleParseStringsFile(NSString *path,
                                               BOOL logErrors) {
    id result = _NSParseStringsFile(path, logErrors);

    return [result isKindOfClass:[NSDictionary class]] ? result : nil;
}

extern int _NSFileAccessModes(NSString *path, BOOL *exists, BOOL *readable,
                              BOOL *writable, BOOL *executable,
                              BOOL *isDirectory, int *times);

static BOOL NSBundleCouldBeBundle(NSString *path) {
    BOOL exists = NO;
    BOOL readable = NO;
    BOOL isDirectory = NO;

    (void)_NSFileAccessModes(path, &exists, &readable, NULL, NULL,
                             &isDirectory, NULL);
    return exists && isDirectory ? readable : NO;
}

static NSBundle *NSBundleLookupOrCreate(NSString *path, BOOL cacheBundle,
                                       BOOL addToLoadedList, NSBundle *bundle,
                                       Class bundleClass, NSZone *zone) {
    NSString *resolvedPath;
    NSBundle *cachedBundle;

    cachedBundle = [NSBundleResolvedPathToBundle objectForKey:path];
    if (cachedBundle != nil) {
        if (bundle != nil)
            [bundle dealloc];
        return [cachedBundle retain];
    }

    if (NSBundleResolvedPathToBundle == nil)
        NSBundleResolvedPathToBundle = [[NSMutableDictionary allocWithZone:NULL]
            initWithCapacity:16];

    resolvedPath = [path stringByResolvingSymlinksInPath];
    if (resolvedPath == nil || [resolvedPath isEqualToString:@""]) {
        if (bundle != nil)
            [bundle dealloc];
        return nil;
    }

    cachedBundle = [NSBundleResolvedPathToBundle objectForKey:resolvedPath];
    if (cachedBundle != nil) {
        if (bundle != nil)
            [bundle dealloc];
        return [cachedBundle retain];
    }

    if (!NSBundleCouldBeBundle(resolvedPath)) {
        if (bundle != nil)
            [bundle dealloc];
        return nil;
    }

    if (bundle == nil)
        bundle = [bundleClass allocWithZone:zone];
    /* IDA passes this allocation directly to the path-record initializer. */

    initWithPathRecordNoLock(bundle, path, resolvedPath, addToLoadedList);
    if (cacheBundle)
        [NSBundleResolvedPathToBundle setObject:bundle forKey:resolvedPath];
    return bundle;
}

typedef struct {
    Class isa;
    unsigned flags;
    id infoDictionary;
    void *reserved5;
    Class principalClass;
    id initialPath;
    id resolvedPath;
} NSBundlePathRecordLayout;

static id initWithPathRecordNoLock(NSBundle *bundle, NSString *path,
                                   NSString *resolvedPath,
                                   BOOL addToLoadedList) {
    NSBundlePathRecordLayout *record = (NSBundlePathRecordLayout *)bundle;
    unichar pathCharacters[1024];
    const unichar frameworkExtension[] = {
        'f', 'r', 'a', 'm', 'e', 'w', 'o', 'r', 'k'
    };
    unsigned pathLength = [resolvedPath length];
    unsigned copiedLength = pathLength > 0x400 ? 0x400 : pathLength;
    unsigned extensionStart;
    unsigned initialCapacity = 8;

#if defined(__ppc__) || defined(__POWERPC__)
    initialCapacity = 4;
#endif
    [resolvedPath getCharacters:pathCharacters
                          range:NSMakeRange(0, copiedLength)];
    extensionStart = _NSStartOfPathExtension(pathCharacters, pathLength);
    if (extensionStart != 0
        && NSCompareCharacters(pathCharacters + extensionStart + 1,
                               frameworkExtension,
                               pathLength - extensionStart - 1,
                               sizeof(frameworkExtension) / sizeof(unichar),
                               0) == 0) {
        record->flags |= 0x40000;
        if (addToLoadedList) {
            if (NSBundleLoadedFrameworks == nil)
                NSBundleLoadedFrameworks = [[NSMutableArray allocWithZone:NULL]
                    initWithCapacity:initialCapacity];
            [NSBundleLoadedFrameworks addObject:bundle];
        }
    } else {
        record->flags |= 0x20000;
        if (addToLoadedList) {
            if (NSBundleLoadedBundles == nil)
                NSBundleLoadedBundles = [[NSMutableArray allocWithZone:NULL]
                    initWithCapacity:initialCapacity];
            [NSBundleLoadedBundles addObject:bundle];
        }
    }
    record->initialPath = [path retain];
    record->resolvedPath = [resolvedPath retain];
    return record->resolvedPath;
}

NSBundle *
_NSFoundationBundle(void)
{
    if (fouBundle_278 == nil) {
        fouBundle_278 = [NSBundle bundleForClass:objc_lookUpClass("NSConcreteArray")];
        if (fouBundle_278 == [NSBundle mainBundle]) {
            fouBundle_278 = [[NSBundle bundleWithPath:@"/System/Library/Frameworks/Foundation.framework"] retain];
        }
    }
    return fouBundle_278;
}

static BOOL _NSBundleLoadJavaCode(NSBundle *bundle, unsigned *flags,
                                  Class *principalClass,
                                  NSString **errorString) {
    NSArray *classes;
    Class *loadedClasses;
    unsigned count;
    unsigned index;

    if ((*flags & 0x60000000) != 0)
        return (*flags & 0x40000000) != 0;
    if ((*flags & 0x10000000) == 0)
        return YES;

#if !defined(__ppc__) && !defined(__POWERPC__)
    *flags |= 0x20000000;
#endif
    if (!NSJavaNeedsToLoadClasses([bundle infoDictionary])) {
#if !defined(__ppc__) && !defined(__POWERPC__)
        *flags |= 0x40000000;
#endif
        return YES;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    *flags |= 0x20000000;
#endif

    classes = NSJavaClassesForBundle(bundle, YES, NULL);
    if (classes == nil) {
        if (errorString != NULL)
            *errorString = [NSString stringWithFormat:
                @"Error loading Java code for bundle %@", [bundle bundlePath]];
        return NO;
    }

    count = [classes count];
    loadedClasses = (Class *)NSZoneMalloc(NULL, count * sizeof(Class));
    if (loadedClasses == NULL) {
        if (errorString != NULL)
            *errorString = [NSString stringWithFormat:
                @"Error loading Java code for bundle %@", [bundle bundlePath]];
        return NO;
    }
    for (index = count; index != 0; index--)
        loadedClasses[index - 1] = (Class)[classes objectAtIndex:index - 1];
    *flags |= 0x40000000;
#if defined(__ppc__) || defined(__POWERPC__)
    if (NSBundleJavaBundlesMap == nil)
        NSBundleJavaBundlesMap = [[NSMutableDictionary dictionary] retain];
    {
        for (index = 0; index < count; index++) {
            Class javaClass = (Class)[classes objectAtIndex:index];

            [NSBundleJavaBundlesMap setObject:bundle
                                       forKey:NSStringFromClass(javaClass)];
        }
    }
#endif
    if (*principalClass == Nil && count != 0)
        *principalClass = loadedClasses[0];
    return YES;
}

@implementation NSBundle

+ (NSBundle *)mainBundle {
    const char *processPath;
    const char *processPathForLength;
    unsigned processPathLength;
    NSString *executablePath;
    NSString *path;
    NSMutableDictionary *infoDictionary;
    NSString *resolvedPath;
    NSString *errorString;

    [_NSBundleDataLock lock];
    if (NSBundleMainBundle == nil && !NSBundleMainBundleTried) {
        NSBundleMainBundleTried = YES;
#if defined(__ppc__) || defined(__POWERPC__)
        processPath = _NSProcessPath();
        processPathForLength = _NSProcessPath();
        processPathLength = (unsigned)strlen(processPathForLength);
#else
        processPathForLength = _NSProcessPath();
        processPathLength = (unsigned)strlen(processPathForLength);
        processPath = _NSProcessPath();
#endif
        executablePath = [NSString stringWithCString:processPath
            length:processPathLength];
        executablePath = [executablePath stringByResolvingSymlinksInPath];
        path = [executablePath stringByDeletingLastPathComponent];
        NSBundleMainBundle = NSBundleLookupOrCreate(path, YES, NO, nil,
            self, NULL);
        if (NSBundleMainBundle != nil) {
            if ((NSBundleMainBundle->_flags & 0x200000) == 0)
                [NSBundleMainBundle _initInfoDictionary];
            NSBundleMainBundle->_flags |= 0x10000 | 0x4000000 | 0x2000000;
            infoDictionary = (NSMutableDictionary *)
                [NSBundleMainBundle infoDictionary];
            [infoDictionary setObject:executablePath
                               forKey:NSBundleExecutablePath];
            resolvedPath = [infoDictionary objectForKey:NSBundleResolvedPath];
            [infoDictionary setObject:resolvedPath forKey:NSBundleInitialPath];
            if (NSJavaNeedsToLoadClasses(infoDictionary)) {
                NSBundleMainBundle->_flags |= 0x10000000;
                errorString = nil;
                if (!_NSBundleLoadJavaCode(NSBundleMainBundle,
                                           &NSBundleMainBundle->_flags,
                                           &NSBundleMainBundle->_principalClass,
                                           &errorString)
#if defined(__ppc__) || defined(__POWERPC__)
                    && ![NSBundle _usesFastJavaBundleSetup]
#endif
                    )
                    NSLog(@"%@: mainBundle: %@",
                          _NSMethodExceptionProem(self, _cmd), errorString);
            }
            [NSBundleLoadedBundles removeObject:NSBundleMainBundle];
        } else
            NSLog(@"*** Warning: could not determine main bundle");
    }
    [_NSBundleDataLock unlock];
    return NSBundleMainBundle;
}

+ (NSBundle *)bundleWithPath:(NSString *)path {
    return [[[self allocWithZone:NULL] initWithPath:path] autorelease];
}

- (id)initWithPath:(NSString *)path {
    NSBundle *bundle;

    [_NSBundleDataLock lock];
    bundle = NSBundleLookupOrCreate(path, YES, YES, self, [self class], NULL);
    [_NSBundleDataLock unlock];
    return bundle;
}

+ (NSBundle *)bundleForClass:(Class)aClass {
    NSBundle *bundle;
    NSBundle *mainBundle = [NSBundle mainBundle];
    Class originalClass;
    const char *libraryPath;
    NSString *libraryPathString;
    NSString *bundlePath;

    [_NSBundleDataLock lock];
    if (aClass == Nil) {
        [_NSBundleDataLock unlock];
        return mainBundle;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    if (NSBundleJavaBundlesMap != nil)
        bundle = [NSBundleJavaBundlesMap objectForKey:NSStringFromClass(aClass)];
    else
        bundle = nil;
    if (bundle == nil) {
#endif
        originalClass = objc_getOrigClass(aClass->name);
        libraryPath = NSBundleLibraryPathForClass(originalClass);
        if (libraryPath == NULL) {
            [_NSBundleDataLock unlock];
            return mainBundle;
        }

#if defined(__ppc__) || defined(__POWERPC__)
        {
            NSFileManager *fileManager = [NSFileManager defaultManager];
            libraryPathString = [fileManager stringWithFileSystemRepresentation:
                libraryPath length:(unsigned)strlen(libraryPath)];
        }
#else
        libraryPathString = [NSString stringWithCString:libraryPath
            length:(unsigned)strlen(libraryPath)];
#endif
        bundlePath = NSBundleFrameworkPathForLibraryPath(libraryPathString);
        if (bundlePath == nil)
            bundlePath = [libraryPathString stringByDeletingLastPathComponent];

        bundle = NSBundleLookupOrCreate(bundlePath, YES, NO, nil,
            [NSBundle class], NULL);
        if (bundle != nil) {
            bundle->_flags |= 0x2000000 | 0x4000000 | 0x30000;
            [NSBundleStaticFrameworks addObject:bundle];
        }
#if defined(__ppc__) || defined(__POWERPC__)
    }
#endif
    [_NSBundleDataLock unlock];
    return bundle != nil ? bundle : mainBundle;
}

+ (NSArray *)allBundles {
    NSMutableArray *bundles = [NSMutableArray arrayWithCapacity:8];
    NSBundle *mainBundle = [NSBundle mainBundle];

    [_NSBundleDataLock lock];
    if (mainBundle != nil)
        [bundles addObject:mainBundle];
    if (NSBundleLoadedBundles != nil)
        [bundles addObjectsFromArray:NSBundleLoadedBundles];
    [_NSBundleDataLock unlock];
    return bundles;
}

+ (NSArray *)allFrameworks {
    NSMutableArray *frameworks = [NSMutableArray arrayWithCapacity:8];

    [_NSBundleDataLock lock];
    if (NSBundleStaticFrameworks == nil)
        NSBundleInitializeStaticFrameworks();
    if (NSBundleStaticFrameworks != nil)
        [frameworks addObjectsFromArray:NSBundleStaticFrameworks];
    if (NSBundleLoadedFrameworks != nil)
        [frameworks addObjectsFromArray:NSBundleLoadedFrameworks];
    [_NSBundleDataLock unlock];
    return frameworks;
}

+ (NSArray *)loadedBundles {
    NSMutableArray *bundles = [NSMutableArray arrayWithCapacity:8];

    [bundles addObjectsFromArray:[self allBundles]];
    [bundles addObjectsFromArray:[self allFrameworks]];
    return bundles;
}

+ (NSString *)debugDescription {
    return [[self loadedBundles] description];
}

+ (void)setSystemLanguages:(NSArray *)languages {
    (void)languages;
}

- (id)retain {
    unsigned count;

    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    count = _flags & 0x7f;
    if (count == 0x7f) {
        if ((_flags & 0x80) != 0)
            NSIncrementExtraRefCount(self);
        _flags |= 0x80;
    } else {
        _flags |= ((unsigned char)count + 1) & 0x7f;
    }
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (void)release {
    unsigned count;
    unsigned bundleType;
    BOOL shouldDeallocate = NO;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    count = _flags & 0x7f;
    if (count != 0) {
        _flags |= ((unsigned char)count - 1) & 0x7f;
    } else if ((_flags & 0x80) != 0) {
        if (NSDecrementExtraRefCountWasZero(self)) {
            _flags &= ~0x80;
        }
        _flags |= 0x7f;
    } else {
        bundleType = _flags & 0x000f0000;
        shouldDeallocate = bundleType != 0x00030000 &&
            bundleType != 0x00010000;
    }
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
    if (shouldDeallocate)
        [self dealloc];
}

- (unsigned)retainCount {
    unsigned count = _flags & 0x7f;

    if ((_flags & 0x80) != 0)
        return count + ((NSExtraRefCount(self) + 1) << 7) + 1;
    return count + 1;
}

- (void)dealloc {
    unsigned bundleType;

    if (_infoDictionary == nil) {
        [super dealloc];
        return;
    }
    if ((_flags & 0x04000000) != 0)
        [self unload];
    bundleType = _flags & 0x000f0000;
    if (bundleType == 0x00010000 || bundleType == 0x00030000)
        return;
    if (_NSBundleDataLock != nil)
        [_NSBundleDataLock lock];
    [NSBundleResolvedPathToBundle removeObjectForKey:
        [_infoDictionary objectForKey:@"NSBundleResolvedPath"]];
    if (bundleType == 0x00040000)
        [NSBundleLoadedFrameworks removeObject:self];
    else
        [NSBundleLoadedBundles removeObject:self];
    if (_NSBundleDataLock != nil)
        [_NSBundleDataLock unlock];
    [_infoDictionary release];
    [super dealloc];
}

- (NSString *)_computeExecutablePath {
    NSMutableDictionary *infoDictionary =
        (NSMutableDictionary *)[self infoDictionary];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *executablePath =
        [infoDictionary objectForKey:@"NSBundleExecutablePath"];
    NSString *resolvedPath;
    NSString *initialPath;
    NSString *executableName = nil;

    if (executablePath != nil) {
        if (NSBundleIsResourceAtPath(fileManager, executablePath))
            return executablePath;
        [infoDictionary removeObjectForKey:@"NSBundleExecutablePath"];
    }

    resolvedPath = [infoDictionary objectForKey:@"NSBundleResolvedPath"];
    initialPath = [infoDictionary objectForKey:@"NSBundleInitialPath"];
    if ((_flags & 0xF0000) == 0x20000) {
        executableName = [infoDictionary objectForKey:@"NSExecutable"];
        if (executableName != nil &&
            ![executableName isKindOfClass:[NSString class]]) {
            NSLog(@"*** Value for key NSExecutable in the info dictionary for bundle %@ is not a string. Will not load code.",
                  initialPath);
            executableName = nil;
        }
        if ([executableName isEqualToString:@"\\"] ||
            [executableName isEqualToString:@"/"])
            executableName = nil;
        if (executableName != nil)
            executablePath = [resolvedPath
                stringByAppendingPathComponent:executableName];
    }

    if (executablePath == nil ||
        !NSBundleIsResourceAtPath(fileManager, executablePath)) {
        NSString *lastComponent = [resolvedPath lastPathComponent];
        executableName = [lastComponent stringByDeletingPathExtension];
        if ([executableName isEqualToString:@"\\"] ||
            [executableName isEqualToString:@"/"])
            executableName = nil;
        executablePath = executableName != nil
            ? [resolvedPath stringByAppendingPathComponent:executableName]
            : nil;
        if (!NSBundleIsResourceAtPath(fileManager, executablePath))
            return nil;
    }

    [infoDictionary setObject:executablePath
                       forKey:@"NSBundleExecutablePath"];
    return executablePath;
}

- (BOOL)load {
    if ((_flags & 0x6000000) == 0) {
        NSString *executablePath;

        [_NSBundleDataLock lock];
        if ((_flags & 0x6000000) == 0) {
            NSString *bundlePath;
            NSString *errorString = nil;

            _flags |= 0x2000000;
            executablePath = [self _computeExecutablePath];
            if (executablePath != nil) {
                unsigned pool = NSPushAutoreleasePool();

                bundlePath = [self bundlePath];
                if (NSBundleLoadCode(executablePath, _flags & 0xF0000,
                                     bundlePath, &errorString))
                    _flags |= 0x4000000;
                else if (errorString != nil)
                    NSLog(@"%@: %@", _NSMethodExceptionProem(self, _cmd),
                          errorString);

                if (NSJavaProvidesClasses([self infoDictionary])) {
                    _flags |= 0x10000000;
                    errorString = nil;
                    if (!_NSBundleLoadJavaCode(self, &_flags,
                                               &_principalClass, &errorString) &&
#if defined(__ppc__) || defined(__POWERPC__)
                        ![NSBundle _usesFastJavaBundleSetup] &&
#endif
                        errorString != nil)
                        NSLog(@"%@: %@", _NSMethodExceptionProem(self, _cmd),
                              errorString);
                }

                if ((_flags & 0x44000000) != 0) {
                    NSMutableDictionary *infoDictionary =
                        (NSMutableDictionary *)[self infoDictionary];
                    NSString *principalClassName =
                        [infoDictionary objectForKey:NSPrincipalClass];
                    Class principalClass = principalClassName != nil
                        ? NSClassFromString(principalClassName) : Nil;
                    NSString *principalClassString;

                    if (principalClass != Nil)
                        _principalClass = principalClass;
                    else if (_principalClass != Nil) {
#if defined(__ppc__) || defined(__POWERPC__)
                        infoDictionary = (NSMutableDictionary *)
                            [self infoDictionary];
                        principalClassString =
                            NSStringFromClass(_principalClass);
#else
                        principalClassString =
                            NSStringFromClass(_principalClass);
                        infoDictionary = (NSMutableDictionary *)
                            [self infoDictionary];
#endif
                        [infoDictionary setObject:principalClassString
                                           forKey:NSPrincipalClass];
                    }
                }

                NSPopAutoreleasePool(pool);
                [_NSBundleDataLock unlock];
                return (_flags & 0x44000000) != 0;
            }

            {
                NSString *missingProem;
                NSString *missingBundlePath;

#if defined(__ppc__) || defined(__POWERPC__)
                missingProem = _NSMethodExceptionProem(self, _cmd);
                missingBundlePath = [self bundlePath];
#else
                missingBundlePath = [self bundlePath];
                missingProem = _NSMethodExceptionProem(self, _cmd);
#endif
                NSLog(@"%@: Cannot find executable code for bundle '%@'",
                      missingProem, missingBundlePath);
            }
        }
        [_NSBundleDataLock unlock];
        return (_flags & 0x4000000) != 0;
    }

    if ((_flags & 0x4000000) == 0)
        return NO;
    {
        NSString *errorString = nil;
        if (!_NSBundleLoadJavaCode(self, &_flags, &_principalClass,
                                   &errorString)
#if defined(__ppc__) || defined(__POWERPC__)
            && ![NSBundle _usesFastJavaBundleSetup]
#endif
            ) {
            NSLog(@"%@: %@", _NSMethodExceptionProem(self, _cmd),
                  errorString);
            return NO;
        }
    }
    return YES;
}

- (BOOL)unload {
    if ((_flags & 0x40000000) != 0)
        NSJavaBundleCleanup(self, nil);
    return NO;
}

- (NSString *)bundlePath {
    return [[self infoDictionary] objectForKey:@"NSBundleInitialPath"];
}

- (NSString *)description {
    NSString *bundlePath;
    Class bundleClass;
    const char *loadState;

#if defined(__ppc__) || defined(__POWERPC__)
    bundleClass = [self class];
    bundlePath = [self bundlePath];
    loadState = (_flags & 0x4000000) != 0 ? "" : "not yet ";
#else
    loadState = (_flags & 0x4000000) != 0 ? "" : "not yet ";
    bundleClass = [self class];
    bundlePath = [self bundlePath];
#endif

    return [NSString stringWithFormat:@"%@ <%@> (%sloaded)", bundleClass,
                                      bundlePath, loadState];
}

- (NSString *)resourcePath {
    NSDictionary *infoDictionary = [self infoDictionary];
    NSString *key = (_flags & 0x100000) != 0
        ? @"NSBundleResourcePath" : @"NSBundleResolvedPath";
    return [infoDictionary objectForKey:key];
}

- (NSArray *)bundleLanguages {
    return [[self infoDictionary] objectForKey:@"NSBundleLanguagesList"];
}

+ (NSArray *)findBundleResources:(NSBundle *)bundle
                    callingMethod:(SEL)selector
                         directory:(NSString *)directory
                         languages:(NSArray *)languages
                              name:(NSString *)name
                             types:(NSArray *)types
                             limit:(unsigned)limit {
    NSMutableArray *results;
    NSFileManager *fileManager;
    NSString *style;
    BOOL windowsStyle;
    unsigned typeCount;
    unsigned typeIndex;

    results = [NSMutableArray arrayWithCapacity:limit + 3];
    style = [[NSUserDefaults standardUserDefaults]
        stringForKey:@"NSInterfaceStyle"];
    windowsStyle = [style isEqualToString:@"windows"];
    fileManager = [NSFileManager defaultManager];

    (void)bundle;
    (void)selector;

    if (limit == 0) {
        NSString *type;
        NSString *path;

        if (name == nil)
            return results;
        if (types != nil) {
            typeCount = [types count];
            if (typeCount == 0)
                return results;
        }
        type = types != nil ? [types objectAtIndex:0] : nil;
        path = NSBundleResourcePath(fileManager, directory, name, type,
                                    style, windowsStyle);
        if (path != nil)
            [results addObject:path];
        return results;
    }

    if (name == nil) {
        if (types == nil) {
            NSBundleAppendDirectoryContents(results, fileManager, directory,
                                            nil, limit);
        } else {
            typeCount = [types count];
            for (typeIndex = 0; typeIndex < typeCount &&
                 [results count] < limit; typeIndex++)
                NSBundleAppendDirectoryContents(results, fileManager,
                    directory, [types objectAtIndex:typeIndex], limit);
        }
    } else if (types == nil) {
        NSString *path = NSBundleResourcePath(fileManager, directory, name,
                                              nil, style, windowsStyle);
        if (path != nil)
            [results addObject:path];
    } else {
        typeCount = [types count];
        for (typeIndex = 0; typeIndex < typeCount &&
             [results count] < limit; typeIndex++) {
            NSString *type = [types objectAtIndex:typeIndex];
            NSString *path = NSBundleResourcePath(fileManager, directory,
                name, type, style, windowsStyle);
            if (path != nil)
                [results addObject:path];
        }
    }

    if ([results count] < limit) {
        unsigned languageIndex;
        unsigned languageCount = [languages count];

        for (languageIndex = 0; languageIndex < languageCount &&
             [results count] < limit; languageIndex++) {
            NSString *language = [languages objectAtIndex:languageIndex];
            NSString *languageDirectory = directory != nil
                ? [[directory stringByAppendingPathComponent:language]
                    stringByAppendingPathExtension:@"lproj"]
                : [language stringByAppendingPathExtension:@"lproj"];

            if (name == nil) {
                if (types == nil) {
                    NSBundleAppendDirectoryContents(results, fileManager,
                        languageDirectory, nil, limit);
                } else {
                    typeCount = [types count];
                    for (typeIndex = 0; typeIndex < typeCount &&
                         [results count] < limit; typeIndex++)
                        NSBundleAppendDirectoryContents(results, fileManager,
                            languageDirectory,
                            [types objectAtIndex:typeIndex], limit);
                }
            } else if (types == nil) {
                NSString *path = NSBundleResourcePath(fileManager,
                    languageDirectory, name, nil, style, windowsStyle);
                if (path != nil)
                    [results addObject:path];
            } else {
                typeCount = [types count];
                for (typeIndex = 0; typeIndex < typeCount &&
                     [results count] < limit; typeIndex++) {
                    NSString *type = [types objectAtIndex:typeIndex];
                    NSString *path = NSBundleResourcePath(fileManager,
                        languageDirectory, name, type, style, windowsStyle);
                    if (path != nil)
                        [results addObject:path];
                }
            }
        }
    }

    return results;
}

- (Class)classNamed:(NSString *)className {
    if ((_flags & 0x2000000) == 0)
        [self load];

    Class aClass = NSClassFromString(className);
    return [NSBundle bundleForClass:aClass] == self ? aClass : Nil;
}

- (Class)principalClass {
    if ((_flags & 0x2000000) == 0)
        [self load];
    return _principalClass;
}

+ (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext inDirectory:(NSString *)path {
    NSFileManager *fileManager;
    BOOL isDirectory = NO;
    NSString *directory = path;
    NSString *resourcesPath;
    NSArray *languages;
    NSArray *types = nil;
    NSArray *results;
    NSString *result = nil;
    unsigned pool;

    if (name == nil || !NSBundleCouldBeBundle(path))
        return nil;
    pool = NSPushAutoreleasePool();
    resourcesPath = [path stringByAppendingPathComponent:@"Resources"];
    fileManager = [NSFileManager defaultManager];
    isDirectory = NO;
    if ([fileManager fileExistsAtPath:resourcesPath isDirectory:&isDirectory] &&
        isDirectory)
        directory = resourcesPath;

    if ([ext isEqualToString:@""])
        ext = nil;
    if (ext != nil)
        types = [NSArray arrayWithObject:ext];
    languages = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSLanguages"];
    results = [self findBundleResources:nil callingMethod:_cmd
        directory:directory languages:languages name:name types:types limit:1];
    if ([results count] != 0)
        result = [[results objectAtIndex:0] retain];
    NSPopAutoreleasePool(pool);
    return [result autorelease];
}

- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext {
    NSArray *bundleLanguages;
    NSArray *languages;
    NSArray *types = nil;
    NSArray *results;
    NSString *directory;
    NSString *result = nil;
    unsigned pool;

    if (name == nil)
        return nil;
    pool = NSPushAutoreleasePool();
    directory = [self resourcePath];
    if ([ext isEqualToString:@""])
        ext = nil;
#if !defined(__ppc__) && !defined(__POWERPC__)
    bundleLanguages = [self bundleLanguages];
    languages = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSLanguages"];
#else
    languages = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSLanguages"];
    bundleLanguages = [self bundleLanguages];
#endif
    languages = [languages arrayByExcludingToObjectsInArray:bundleLanguages];
    if (ext != nil)
        types = [NSArray arrayWithObject:ext];

    results = [NSBundle findBundleResources:self callingMethod:_cmd
        directory:directory languages:languages name:name types:types limit:1];
    if ([results count] != 0)
        result = [[results objectAtIndex:0] retain];
    NSPopAutoreleasePool(pool);
    return [result autorelease];
}

- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext inDirectory:(NSString *)subpath {
    NSString *directory;
    NSArray *languages;
    NSArray *bundleLanguages;
    NSArray *types = nil;
    NSArray *results;

    if (name == nil)
        return nil;
    directory = [self resourcePath];
    if (subpath != nil)
        directory = [directory stringByAppendingPathComponent:subpath];
    if (ext != nil && [ext isEqualToString:@""])
        ext = nil;
#if !defined(__ppc__) && !defined(__POWERPC__)
    bundleLanguages = [self bundleLanguages];
    languages = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSLanguages"];
#else
    languages = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSLanguages"];
    bundleLanguages = [self bundleLanguages];
#endif
    languages = [languages arrayByExcludingToObjectsInArray:bundleLanguages];
    if (ext != nil)
        types = [NSArray arrayWithObject:ext];

    results = [NSBundle findBundleResources:self callingMethod:_cmd
        directory:directory languages:languages name:name types:types
        limit:1];
    return [results count] != 0 ? [results objectAtIndex:0] : nil;
}

- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext
                  inDirectory:(NSString *)subpath
                  forLanguage:(NSString *)language {
    unsigned pool;
    NSString *directory;
    NSArray *languages;
    NSArray *types = nil;
    NSArray *results;
    NSString *path = nil;

    if (name == nil)
        return nil;
    pool = NSPushAutoreleasePool();
    directory = [self resourcePath];
    if (subpath != nil)
        directory = [directory stringByAppendingPathComponent:subpath];
    if (ext != nil && [ext isEqualToString:@""])
        ext = nil;
    if (language != nil) {
        languages = [NSArray arrayWithObject:language];
    } else {
#if !defined(__ppc__) && !defined(__POWERPC__)
        NSArray *bundleLanguages = [self bundleLanguages];
        NSArray *systemLanguages = [[NSUserDefaults standardUserDefaults]
            objectForKey:@"NSLanguages"];
#else
        NSArray *systemLanguages = [[NSUserDefaults standardUserDefaults]
            objectForKey:@"NSLanguages"];
        NSArray *bundleLanguages = [self bundleLanguages];
#endif
        languages = [systemLanguages arrayByExcludingToObjectsInArray:
            bundleLanguages];
    }
    if (ext != nil)
        types = [NSArray arrayWithObject:ext];
    results = [NSBundle findBundleResources:self callingMethod:_cmd
        directory:directory languages:languages name:name types:types limit:1];
    if ([results count] != 0)
        path = [[results objectAtIndex:0] retain];
    NSPopAutoreleasePool(pool);
    return [path autorelease];
}

+ (NSArray *)pathsForResourcesOfType:(NSString *)ext inDirectory:(NSString *)subpath {
    unsigned pool;
    NSFileManager *fileManager;
    BOOL isDirectory = NO;
    NSString *directory = subpath;
    NSString *resourcesPath;
    NSArray *languages;
    NSArray *types = nil;
    NSArray *results;

    if (!NSBundleCouldBeBundle(subpath))
        return __NSEmptyArray;
    pool = NSPushAutoreleasePool();
    resourcesPath = [subpath stringByAppendingPathComponent:@"Resources"];
    fileManager = [NSFileManager defaultManager];
    isDirectory = NO;
    if ([fileManager fileExistsAtPath:resourcesPath isDirectory:&isDirectory] &&
        isDirectory)
        directory = resourcesPath;

    languages = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSLanguages"];
    if (ext != nil)
        types = [NSArray arrayWithObject:ext];
    results = [self findBundleResources:nil callingMethod:_cmd
        directory:directory languages:languages name:nil types:types
        limit:(unsigned)-1];
    [results retain];
    NSPopAutoreleasePool(pool);
    return [results autorelease];
}

- (NSArray *)pathsForResourcesOfType:(NSString *)ext inDirectory:(NSString *)subpath {
    unsigned pool;
    NSString *directory;
    NSArray *languages;
    NSArray *bundleLanguages;
    NSArray *types = nil;
    NSArray *results;

    pool = NSPushAutoreleasePool();
    directory = [self resourcePath];
    if (subpath != nil)
        directory = [directory stringByAppendingPathComponent:subpath];
#if !defined(__ppc__) && !defined(__POWERPC__)
    bundleLanguages = [self bundleLanguages];
    languages = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSLanguages"];
#else
    languages = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSLanguages"];
    bundleLanguages = [self bundleLanguages];
#endif
    languages = [languages arrayByExcludingToObjectsInArray:bundleLanguages];
    if (ext != nil)
        types = [NSArray arrayWithObject:ext];

    results = [NSBundle findBundleResources:self callingMethod:_cmd
        directory:directory languages:languages name:nil types:types
        limit:(unsigned)-1];
    [results retain];
    NSPopAutoreleasePool(pool);
    return [results autorelease];
}

- (NSArray *)pathsForResourcesOfType:(NSString *)ext inDirectory:(NSString *)subpath
                        forLanguage:(NSString *)language {
    unsigned pool = NSPushAutoreleasePool();
    NSString *directory = [self resourcePath];
    NSArray *languages;
    NSArray *types = ext != nil ? [NSArray arrayWithObject:ext] : nil;
    NSArray *results;

    if (subpath != nil)
        directory = [directory stringByAppendingPathComponent:subpath];
    if (language != nil) {
        languages = [NSArray arrayWithObject:language];
    } else {
#if !defined(__ppc__) && !defined(__POWERPC__)
        NSArray *bundleLanguages = [self bundleLanguages];
        NSArray *systemLanguages = [[NSUserDefaults standardUserDefaults]
            objectForKey:@"NSLanguages"];
#else
        NSArray *systemLanguages = [[NSUserDefaults standardUserDefaults]
            objectForKey:@"NSLanguages"];
        NSArray *bundleLanguages = [self bundleLanguages];
#endif
        languages = [systemLanguages arrayByExcludingToObjectsInArray:
            bundleLanguages];
    }
    results = [NSBundle findBundleResources:self callingMethod:_cmd
        directory:directory languages:languages name:nil types:types
        limit:(unsigned)-1];
    results = [results retain];
    NSPopAutoreleasePool(pool);
    return [results autorelease];
}

- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName {
    NSMutableDictionary *infoDictionary;
    NSMutableDictionary *tableTable;
    NSDictionary *strings;
    NSString *result;

    if (key == nil)
        return value != nil ? value : @"";
    if ([tableName isEqualToString:@""])
        tableName = nil;
    if (tableName == nil)
        tableName = @"Localizable";

    infoDictionary = (NSMutableDictionary *)[self infoDictionary];
    tableTable = [infoDictionary objectForKey:@"NSBundleStringTableTable"];
    strings = tableTable != nil ? [tableTable objectForKey:tableName] : nil;
    if (strings == nil) {
        NSString *path = [self pathForResource:tableName ofType:@"strings"];

        strings = path != nil
            ? [NSBundleParseStringsFile(path, YES) retain] : nil;
        if (strings == nil)
            strings = [[NSMutableDictionary allocWithZone:NULL]
                initWithCapacity:4];
        if (tableTable == nil) {
            tableTable = [[NSMutableDictionary allocWithZone:NULL]
                initWithCapacity:4];
            [infoDictionary setObject:tableTable
                               forKey:@"NSBundleStringTableTable"];
            [tableTable release];
        }
        [tableTable setObject:strings forKey:tableName];
        [strings release];
    }

    result = [strings objectForKey:key];
    if (result == nil) {
        if (value != nil && ![value isEqualToString:@""])
            result = value;
        else {
            result = key;
        }
        if (NSBundleLocalizedStringDebugOptions == -1) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSBundleLocalizedStringDebugOptions = 0;
            if ([defaults boolForKey:@"NSShowNonLocalizedStrings"])
                NSBundleLocalizedStringDebugOptions |= 1;
            if ([defaults boolForKey:@"NSShowNonLocalizableStrings"])
                NSBundleLocalizedStringDebugOptions |= 2;
        }
        if (NSBundleLocalizedStringDebugOptions != 0) {
            if ((NSBundleLocalizedStringDebugOptions & 1) != 0 &&
                result == key) {
                NSLog(@"%@: Localized string \"%@\" not found in strings table \"%@\".",
                      self, result, tableName);
                result = [result uppercaseString];
            }
            result = _NSLocalizedString(result);
        }
    }
    return result;
}

- (NSDictionary *)infoDictionary {
    if ((_flags & 0x200000) == 0)
        [self _initInfoDictionary];
    return _infoDictionary;
}

- (NSDictionary *)defaultsDictionary {
    NSDictionary *defaults =
        [[self infoDictionary] objectForKey:@"NSBundleDefaultsDictionary"];

    if (defaults == nil) {
        NSString *path = [self pathForResource:@"Defaults" ofType:@"plist"];
        defaults = path != nil
            ? [NSDictionary dictionaryWithContentsOfFile:path]
            : [NSDictionary dictionary];
        [(NSMutableDictionary *)[self infoDictionary]
            setObject:defaults forKey:@"NSBundleDefaultsDictionary"];
    }
    return defaults;
}

- (void)invalidateResourceCache {
    [(NSMutableDictionary *)[self infoDictionary]
        removeObjectForKey:@"NSBundleResources"];
    [(NSMutableDictionary *)[self infoDictionary]
        removeObjectForKey:@"NSBundleStringTableTable"];
}

- (void)_initInfoDictionary {
    NSString *resolvedPath;
    NSString *resourcePath;
    NSString *infoPath;
    NSUserDefaults *defaults;
    NSString *interfaceStyle;
    NSFileManager *fileManager;
    BOOL isDirectory = NO;
    NSDictionary *loadedDictionary;
    NSMutableDictionary *infoDictionary;

    _flags |= 0x200000;
    resolvedPath = (NSString *)_tmp2;
    resourcePath = [resolvedPath stringByAppendingPathComponent:@"Resources"];
    defaults = [NSUserDefaults standardUserDefaults];
    [defaults synchronize];
    interfaceStyle = [defaults stringForKey:@"NSInterfaceStyle"];
    loadedDictionary = nil;
    if (interfaceStyle != nil) {
        NSString *styleInfoName = [NSString stringWithFormat:@"Info-%@.plist",
            interfaceStyle];
        infoPath = [resourcePath stringByAppendingPathComponent:styleInfoName];
        loadedDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    }
    if (loadedDictionary == nil) {
        infoPath = [resourcePath
            stringByAppendingPathComponent:@"Info-nextstep.plist"];
        loadedDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    }
    if (loadedDictionary == nil) {
        infoPath = [resourcePath stringByAppendingPathComponent:@"Info.plist"];
        loadedDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    }
    if (loadedDictionary == nil) {
        infoPath = [resolvedPath stringByAppendingPathComponent:@"Info.plist"];
        loadedDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    }

    infoDictionary = loadedDictionary != nil
        ? [loadedDictionary mutableCopy]
#if defined(__ppc__) || defined(__POWERPC__)
        : [[NSMutableDictionary allocWithZone:NULL] initWithCapacity:16];
#else
        : [[NSMutableDictionary allocWithZone:NULL] init];
#endif
    if (infoDictionary != nil) {
        if ([infoDictionary objectForKey:@"NSBundleInitialPath"] == nil)
            [infoDictionary setObject:[(NSString *)_tmp1 stringByStandardizingPath]
                forKey:@"NSBundleInitialPath"];
        if ([infoDictionary objectForKey:@"NSBundleResolvedPath"] == nil)
            [infoDictionary setObject:resolvedPath
                forKey:@"NSBundleResolvedPath"];
    }

    fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:resourcePath
                          isDirectory:&isDirectory] && isDirectory)
        _flags |= 0x100000;
    if (infoDictionary != nil &&
        [infoDictionary objectForKey:@"NSBundleResourcePath"] == nil) {
        NSString *defaultResourcePath = (_flags & 0x100000) != 0
            ? resourcePath : resolvedPath;
        [infoDictionary setObject:defaultResourcePath
                           forKey:@"NSBundleResourcePath"];
    }

    _infoDictionary = infoDictionary;
    [_tmp1 release];
    _tmp1 = NULL;
    [_tmp2 release];
    _tmp2 = NULL;
    if ([infoDictionary objectForKey:NSBundleLanguagesList] == nil) {
        NSArray *languages = [[NSFileManager defaultManager]
            directoryContentsAtPath:resourcePath
                  matchingExtension:@"lproj"
                             options:0
                       keepExtension:NO];

        if (languages == nil)
            languages = [NSArray array];
        [infoDictionary setObject:languages forKey:NSBundleLanguagesList];
    }
}

@end

#if defined(__ppc__) || defined(__POWERPC__)
@implementation NSBundle (_NSJavaSetupPrivate)

+ (void)_setUsesFastJavaBundleSetup:(BOOL)useFastSetup {
    _usesFastJavaBundleSetup = useFastSetup != NO;
}

+ (int)_usesFastJavaBundleSetup {
    return _usesFastJavaBundleSetup;
}

- (void)_setJavaClassesLoaded {
    _flags |= 0x60000000;
}

@end
#endif
