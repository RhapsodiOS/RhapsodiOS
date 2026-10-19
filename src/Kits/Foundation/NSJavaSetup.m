/*	NSJavaSetup.m
	Setup of Java VM
	Copyright 1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSJavaSetup.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSUserDefaults.h>

@interface NSObject (NSJavaLibrarySearchPaths)
+ (void)removePathFromLibrarySearchPaths:(NSString *)path;
+ (void)addPathToLibrarySearchPaths:(NSString *)path;
+ (NSString *)defaultClassPath;
- (id)initWithClassPath:(NSString *)classPath;
- (void)setPath:(NSString *)path;
- (NSString *)getPath;
- (void)setResourceLocator:(id)locator;
- (id)getResourceLocator;
- (id)getClasses;
- (id)getClassesFromResourceLocator:(id)locator;
- (id)loadClass:(NSString *)className;
@end

@interface NSObject (NSJavaPathResourceLocator)
+ (id)instantiate:(id)classLoader :(NSString *)name;
@end

@interface NSObject (NSJavaSystemProperties)
+ (id)getProperties;
+ (id)getProperty:(NSString *)name :(NSString *)defaultValue;
+ (id)setProperties:(id)properties;
- (id)put:(NSString *)name :(NSString *)value;
@end

@interface NSBundle (NSJavaFastSetupPrivate)
- (void)_setJavaClassesLoaded;
@end

// Constant definitions
NSString * const NSJavaClasses = @"NSJavaClasses";
NSString * const NSJavaRoot = @"NSJavaRoot";
NSString * const NSJavaPath = @"NSJavaPath";
NSString * const NSJavaUserPath = @"NSJavaUserPath";
NSString * const NSJavaLibraryPath = @"NSJavaLibraryPath";
NSString * const NSJavaOwnVirtualMachine = @"NSJavaOwnVirtualMachine";

NSString * const NSJavaPathSeparator = @":";

NSString * const NSJavaWillSetupVirtualMachineNotification = @"NSJavaWillSetupVirtualMachineNotification";
NSString * const NSJavaDidSetupVirtualMachineNotification = @"NSJavaDidSetupVirtualMachineNotification";

NSString * const NSJavaWillCreateVirtualMachineNotification = @"NSJavaWillCreateVirtualMachineNotification";
NSString * const NSJavaDidCreateVirtualMachineNotification = @"NSJavaDidCreateVirtualMachineNotification";

static id _NSJavaVM;
static id _NSJavaCL;
#if defined(__ppc__) || defined(__POWERPC__)
int _usesFastJavaBundleSetup = 1;
#endif

NSString * const NSJavaBundleClassLoaderClassName =
    @"com.apple.misc.BundleClassLoader";
NSString * const NSJavaStandardClassLoaderClassName =
    @"com.apple.misc.StandardClassLoader";
NSString * const NSJavaPathResourceLocatorClassName =
    @"com.apple.util.PathResourceLocator";
static NSString * const NSJavaNativeRuntimeClassName =
    @"com.apple.alpha.core.NativeRuntime";

// Function implementations

BOOL NSJavaNeedsVirtualMachine(NSDictionary *plist) {
    id value;

#if defined(__ppc__) || defined(__POWERPC__)
    value = [plist objectForKey:@"NSJavaNeeded"];
    if ([value isKindOfClass:[NSString class]])
        return [value caseInsensitiveCompare:@"YES"] == NSOrderedSame;
    value = [plist objectForKey:@"NSJavaAware"];
    return [value isKindOfClass:[NSString class]] &&
        [value caseInsensitiveCompare:@"YES"] == NSOrderedSame;
#else
    Class stringClass = [NSString class];
    value = [plist objectForKey:@"NSJavaAware"];
    return [value isKindOfClass:stringClass] &&
        [value caseInsensitiveCompare:@"YES"] == NSOrderedSame;
#endif
}

BOOL NSJavaProvidesClasses(NSDictionary *plist) {
#if !defined(__ppc__) && !defined(__POWERPC__)
    Class arrayClass = [NSArray class];
    id path = [plist objectForKey:NSJavaPath];
    return [path isKindOfClass:arrayClass];
#else
    id path = [plist objectForKey:NSJavaPath];
    return [path isKindOfClass:[NSArray class]];
#endif
}

BOOL NSJavaNeedsToLoadClasses(NSDictionary *plist) {
    return NSJavaNeedsVirtualMachine(plist) ||
        (_NSJavaVM != nil && NSJavaProvidesClasses(plist));
}

NSDictionary *NSJavaDefinitiveSetupDictionary(NSDictionary *plist,
                                             BOOL useDefaults) {
    NSDictionary *valueClasses = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSArray class], NSJavaClasses,
        [NSString class], NSJavaRoot,
        [NSArray class], NSJavaPath,
        [NSArray class], NSJavaUserPath,
        [NSArray class], NSJavaLibraryPath,
        [NSString class], NSJavaOwnVirtualMachine,
        nil];
    NSEnumerator *keys = [valueClasses keyEnumerator];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *result = nil;
    id key;

    while ((key = [keys nextObject]) != nil) {
        Class expectedClass = (Class)[valueClasses objectForKey:key];
        id defaultValue = [defaults objectForKey:key];

        if ([defaultValue isKindOfClass:expectedClass]) {
            id plistValue = [plist objectForKey:key];

            if (![plistValue isKindOfClass:expectedClass])
                plistValue = nil;
            if (result == nil)
                result = [plist mutableCopy];

            if (plistValue != nil) {
                if ([(id)expectedClass isKindOfClass:[NSArray class]])
                    [result setObject:[defaultValue
                        arrayByAddingObjectsFromArray:plistValue] forKey:key];
                else
                    [result setObject:defaultValue forKey:key];
            } else if (useDefaults) {
                [result setObject:defaultValue forKey:key];
            }
        }
    }

    return result != nil ? result : plist;
}

static NSMutableArray *_NSJavaAbsolutePath(NSBundle *bundle,
                                          NSDictionary *plist,
                                          NSString *key, NSString *root) {
    NSMutableArray *paths = [NSMutableArray array];
    NSArray *relativePaths = nil;
    BOOL useRoot;
    unsigned index;

    if (plist == nil && bundle != nil)
        plist = [bundle infoDictionary];
    if (plist != nil) {
        id value = [plist objectForKey:key];
        if ([value isKindOfClass:[NSArray class]])
            relativePaths = value;
        if (root == nil) {
            value = [plist objectForKey:NSJavaRoot];
            if ([value isKindOfClass:[NSString class]])
                root = value;
        }
    }
    if (root == nil)
        root = @"Resources/Java";

#if defined(__ppc__) || defined(__POWERPC__)
    useRoot = [root length] != 0;
#else
    useRoot = ![root isEqualToString:@"/"];
#endif
    if (useRoot && ![root isAbsolutePath]) {
        NSString *base = bundle != nil ? [bundle bundlePath] : nil;
        if (base == nil) {
            id value = [plist objectForKey:@"NSJavaBundlePath"];
            if ([value isKindOfClass:[NSString class]])
                base = value;
        }
        if (base == nil)
            base = @".";
        root = [base stringByAppendingPathComponent:root];
    }

    if ([relativePaths count] == 0)
        relativePaths = [NSArray arrayWithObject:@"."];
    for (index = 0; index < [relativePaths count]; index++) {
        NSString *path = [relativePaths objectAtIndex:index];
        if (useRoot && ![path isAbsolutePath])
            path = [root stringByAppendingPathComponent:path];
        [paths addObject:path];
    }
    return paths;
}

#if defined(__ppc__) || defined(__POWERPC__)
static NSArray *_NSJavaPathCompsForBundle(NSBundle *bundle,
                                         NSDictionary *settings,
                                         BOOL absolutePath) {
    id userPaths;

    if (settings == nil)
        settings = NSJavaDefinitiveSetupDictionary([bundle infoDictionary],
                                                   YES);
    if (absolutePath)
        return _NSJavaAbsolutePath(bundle, settings, NSJavaPath, nil);
    userPaths = [settings objectForKey:NSJavaUserPath];
    return [userPaths isKindOfClass:[NSArray class]] ? userPaths : nil;
}
#endif

id _NSJavaBundleClassPath(NSBundle *bundle, NSString *key) {
    NSDictionary *info = [bundle infoDictionary];

    if (!NSJavaNeedsVirtualMachine(info))
        return nil;
    if ([key isEqualToString:NSJavaPath])
        return _NSJavaAbsolutePath(bundle, info, key, nil);
    return [info objectForKey:key];
}

id NSJavaResourceLocatorForPath(NSArray *path) {
    Class locatorClass = NSClassFromString(NSJavaPathResourceLocatorClassName);
    id locator;

    if (locatorClass == Nil) {
        NSLog(@"NSJavaResourceLocatorForPath: cannot locate class %@",
              NSJavaPathResourceLocatorClassName);
        return nil;
    }
    locator = [[[locatorClass alloc] init] autorelease];
    if (locator == nil) {
        NSLog(@"NSJavaResourceLocatorForPath: cannot create instance of %@",
              NSJavaPathResourceLocatorClassName);
        return nil;
    }
    [locator setPath:[path componentsJoinedByString:NSJavaPathSeparator]];
    return locator;
}

id NSJavaClassLoaderForPath(NSArray *path, BOOL useSystemClassLoader) {
    id classLoader;
    BOOL createdClassLoader;
    id resourceLocator;

#if defined(__ppc__) || defined(__POWERPC__)
    NSJavaSetupVirtualMachine();
    classLoader = useSystemClassLoader ? _NSJavaCL : nil;
#else
    classLoader = useSystemClassLoader ? _NSJavaCL : nil;
    if (_NSJavaVM == nil) {
        NSDictionary *vmSettings = [NSDictionary dictionaryWithObjectsAndKeys:
            @"YES", @"NSJavaAware", nil];
        NSJavaSetup(vmSettings);
    }
#endif
    createdClassLoader = classLoader == nil;

    if (!createdClassLoader) {
        resourceLocator = [classLoader getResourceLocator];
    } else {
        Class classLoaderClass = NSClassFromString(
            NSJavaBundleClassLoaderClassName);
        if (classLoaderClass == Nil) {
            NSLog(@"NSJavaClassLoaderForPath: cannot locate class %@",
                  NSJavaBundleClassLoaderClassName);
            return nil;
        }
        resourceLocator = NSJavaResourceLocatorForPath(path);
        classLoader = [[classLoaderClass alloc] init];
        if (classLoader == nil) {
            NSLog(@"NSJavaClassLoaderForPath: cannot create instance of %@",
                  NSJavaBundleClassLoaderClassName);
            return nil;
        }
        [classLoader setResourceLocator:resourceLocator];
        if (useSystemClassLoader)
            _NSJavaCL = classLoader;
        else
            [classLoader autorelease];
    }

    if (!createdClassLoader) {
#if defined(__ppc__) || defined(__POWERPC__)
        NSString *currentPath = [resourceLocator getPath];
        NSArray *existingPaths = [currentPath
            componentsSeparatedByString:NSJavaPathSeparator];
        NSMutableArray *addedPaths = [NSMutableArray array];
        unsigned count = (unsigned)[path count];
        unsigned index;

        for (index = 0; index < count; index++) {
            id pathEntry = [path objectAtIndex:index];

            if (![existingPaths containsObject:pathEntry])
                [addedPaths addObject:pathEntry];
        }
        if ([addedPaths count] != 0) {
            NSString *addedPath = [addedPaths
                componentsJoinedByString:NSJavaPathSeparator];

            [resourceLocator setPath:[addedPath
                stringByAppendingFormat:@"%@%@", NSJavaPathSeparator,
                                        currentPath]];
        }
#else
        NSString *addedPath = [path componentsJoinedByString:NSJavaPathSeparator];
        NSString *currentPath = [resourceLocator getPath];
        [resourceLocator setPath:[currentPath
            stringByAppendingFormat:@":%@", addedPath]];
#endif
    }
    return classLoader;
}

static NSArray *_NSJavaClassesFromVector(id vector) {
    NSMutableArray *classes;
    unsigned count;
    unsigned index;

    if (vector == nil)
        return nil;
    count = (unsigned)[vector size];
    classes = [NSMutableArray array];
    for (index = 0; index < count; index++)
        [classes addObject:[vector objectAtIndex:index]];
    return classes;
}

NSArray *NSJavaClassesFromClassLoader(id classLoader) {
    id vector;

    if (![classLoader respondsToSelector:@selector(getClasses)])
        return nil;
    vector = [classLoader getClasses];
    return _NSJavaClassesFromVector(vector);
}

NSArray *NSJavaClassesFromClassLoaderFromPath(id classLoader, NSArray *path) {
    id resourceLocator;
    id vector;

    if (![classLoader respondsToSelector:
            @selector(getClassesFromResourceLocator:)])
        return nil;
    resourceLocator = NSJavaResourceLocatorForPath(path);
    if (resourceLocator == nil)
        return nil;
    vector = [classLoader getClassesFromResourceLocator:resourceLocator];
    return _NSJavaClassesFromVector(vector);
}

#if defined(__ppc__) || defined(__POWERPC__)
static NSArray *NSJavaSpecifiedClassesForBundle(NSBundle *bundle,
                                                NSDictionary *plist,
                                                NSArray *requestedClasses,
                                                BOOL useSystemClassLoader,
                                                id *vm) {
#else
static NSArray *NSJavaSpecifiedClassesForBundle(NSBundle *bundle,
                                                NSDictionary *plist,
                                                BOOL loadAllClasses,
                                                BOOL useSystemClassLoader,
                                                id *vm) {
#endif
    id javaVM = _NSJavaVM;
    NSDictionary *setupDictionary;
    NSMutableArray *classPaths;
    NSArray *userPaths;
    NSArray *wantedClasses;
    NSArray *classes = nil;
    id classLoader;
    unsigned index;

    if (plist == nil && bundle != nil)
        plist = [bundle infoDictionary];
    if (javaVM != nil) {
        if (vm != NULL)
            *vm = javaVM;
    } else {
        NSMutableDictionary *vmSettings = [plist mutableCopy];

#if defined(__ppc__) || defined(__POWERPC__)
        if (_usesFastJavaBundleSetup <= 0) {
#endif
            [vmSettings removeObjectForKey:NSJavaPath];
            [vmSettings removeObjectForKey:NSJavaUserPath];
            [vmSettings removeObjectForKey:NSJavaClasses];
#if defined(__ppc__) || defined(__POWERPC__)
        }
#endif
        javaVM = NSJavaBundleSetup(bundle, vmSettings);
        if (vm != NULL)
            *vm = javaVM;
#if defined(__ppc__) || defined(__POWERPC__)
        if (_usesFastJavaBundleSetup > 0)
            return nil;
#endif
    }

    if (javaVM == nil)
        return nil;

    setupDictionary = NSJavaDefinitiveSetupDictionary(plist, YES);
#if defined(__ppc__) || defined(__POWERPC__)
    classPaths = _NSJavaPathCompsForBundle(bundle, setupDictionary, YES);
    userPaths = _NSJavaPathCompsForBundle(bundle, setupDictionary, NO);
    wantedClasses = [requestedClasses isKindOfClass:[NSArray class]]
        ? requestedClasses : nil;
#else
    classPaths = _NSJavaAbsolutePath(bundle, setupDictionary, NSJavaPath, nil);
    userPaths = [setupDictionary objectForKey:NSJavaUserPath];
    if (![userPaths isKindOfClass:[NSArray class]])
        userPaths = nil;
#endif
    if ([userPaths count] != 0) {
        [classPaths addObjectsFromArray:userPaths];
    }

    classLoader = NSJavaClassLoaderForPath(classPaths, useSystemClassLoader);
#if defined(__ppc__) || defined(__POWERPC__)
    if (wantedClasses != nil) {
        NSMutableArray *loadedClasses = [NSMutableArray array];

        for (index = 0; index < [wantedClasses count]; index++) {
            id loadedClass = [classLoader
                loadClass:[wantedClasses objectAtIndex:index]];

            if (loadedClass != nil)
                [loadedClasses addObject:loadedClass];
        }
        classes = loadedClasses;
    } else {
        classes = NSJavaClassesFromClassLoaderFromPath(classLoader,
                                                        classPaths);
    }
#else
    if (loadAllClasses)
        classes = NSJavaClassesFromClassLoaderFromPath(classLoader, classPaths);

    wantedClasses = [setupDictionary objectForKey:NSJavaClasses];
#endif
#if defined(__ppc__) || defined(__POWERPC__)
    wantedClasses = [setupDictionary objectForKey:NSJavaClasses];
#endif
    if ([wantedClasses isKindOfClass:[NSArray class]]) {
        for (index = 0; index < [wantedClasses count]; index++)
            [classLoader loadClass:[wantedClasses objectAtIndex:index]];
    }
    return classes;
}

id NSJavaSetup(NSDictionary *plist) {
    return NSJavaBundleSetup(nil, plist);
}

#if defined(__ppc__) || defined(__POWERPC__)
id NSJavaSetupVirtualMachine() {
    NSBundle *bundle = [NSBundle mainBundle];
    NSMutableDictionary *setupDictionary = [[bundle infoDictionary] mutableCopy];
    id virtualMachine;

    [setupDictionary setObject:@"YES" forKey:@"NSJavaNeeded"];
    virtualMachine = NSJavaSetup(setupDictionary);
    [setupDictionary release];
    return virtualMachine;
}
#endif

#if defined(__ppc__) || defined(__POWERPC__)
id NSJavaGetSystemProperty(NSString *name) {
    return NSJavaGetSystemPropertyOrUseDefault(name, nil);
}

id NSJavaGetSystemPropertyOrUseDefault(NSString *name,
                                       NSString *defaultValue) {
    Class systemClass;

    NSJavaSetupVirtualMachine();
    systemClass = NSClassFromString(@"java/lang/System");
    return [systemClass getProperty:name :defaultValue];
}

id NSJavaSetSystemProperty(NSString *name, NSString *value) {
    Class systemClass;
    id properties;

    NSJavaSetupVirtualMachine();
    systemClass = NSClassFromString(@"java/lang/System");
    properties = [systemClass getProperties];
    [properties put:name :value];
    systemClass = NSClassFromString(@"java/lang/System");
    return [systemClass setProperties:properties];
}
#endif

#if defined(__ppc__) || defined(__POWERPC__)
id NSJavaObjectNamedInPath(NSString *name, NSArray *path) {
    id classLoader = NSJavaClassLoaderForPath(path, YES);
    Class locatorClass = NSClassFromString(NSJavaPathResourceLocatorClassName);

    return [locatorClass instantiate:classLoader :name];
}
#endif

NSArray *NSJavaClassesFromPath(NSArray *path, NSArray *wanted, BOOL usesyscl, id *vm) {
#if defined(__ppc__) || defined(__POWERPC__)
    NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
        @"/", NSJavaRoot,
        path, NSJavaPath,
        nil];
    return NSJavaSpecifiedClassesForBundle(nil, plist, wanted, usesyscl, vm);
#else
    NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
        @"/", NSJavaRoot,
        path, NSJavaPath,
        wanted, NSJavaClasses,
        nil];
    return NSJavaSpecifiedClassesForBundle(nil, plist, wanted == nil,
                                           usesyscl, vm);
#endif
}

NSArray *NSJavaClassesForBundle(NSBundle *bundle, BOOL usesyscl, id *vm) {
#if defined(__ppc__) || defined(__POWERPC__)
    return NSJavaSpecifiedClassesForBundle(bundle, nil, nil, usesyscl, vm);
#else
    return NSJavaSpecifiedClassesForBundle(bundle, nil, YES, usesyscl, vm);
#endif
}

#if defined(__ppc__) || defined(__POWERPC__)
id _NSFastJavaBundleSetup(NSBundle *bundle, NSDictionary *plist) {
    NSArray *searchPaths;
    NSMutableArray *classPaths;
    NSMutableArray *bundles;
    NSMutableArray *frameworkPaths;
    NSMutableArray *userPaths;
    NSArray *paths;
    NSArray *libraryPaths;
    NSArray *classes;
    NSString *frameworkPath;
    NSString *classPath;
    NSBundle *vmBundle;
    NSBundle *javaBundle;
    NSDictionary *setupDictionary;
    Class vmClass;
    Class nativeRuntime;
    id javaVM = _NSJavaVM;
    id ownVM;
    id vmAllocation;
    unsigned index;

    if (javaVM != nil) {
        ownVM = [plist objectForKey:NSJavaOwnVirtualMachine];
        if (![ownVM isKindOfClass:[NSString class]])
            return javaVM;
    }

    searchPaths = NSSearchPathForDirectoriesInDomains(
        NSLibraryDirectory, NSSystemDomainMask, YES);
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSJavaWillSetupVirtualMachineNotification
                      object:nil];
    frameworkPath = [searchPaths count] != 0
        ? [[searchPaths objectAtIndex:0]
            stringByAppendingPathComponent:@"Frameworks/JavaVM.framework"]
        : [@"/" stringByAppendingPathComponent:
            @"Frameworks/JavaVM.framework"];
    vmBundle = [NSBundle bundleWithPath:frameworkPath];
    vmClass = [vmBundle classNamed:@"NSJavaVirtualMachine"];
    if (vmClass == Nil)
        return nil;

    if (plist == nil)
        plist = [bundle infoDictionary];
    setupDictionary = NSJavaDefinitiveSetupDictionary(plist, YES);
    classPaths = _NSJavaAbsolutePath(bundle, setupDictionary,
                                     NSJavaPath, nil);
    classes = [[vmClass defaultClassPath]
        componentsSeparatedByString:NSJavaPathSeparator];
    [classPaths addObjectsFromArray:classes];
    paths = _NSJavaPathCompsForBundle(bundle, setupDictionary, NO);
    if ([paths count] != 0)
        [classPaths addObjectsFromArray:paths];

    bundles = [NSMutableArray arrayWithCapacity:8];
    [bundles addObjectsFromArray:[NSBundle allFrameworks]];
    [bundles addObjectsFromArray:[NSBundle allBundles]];
    frameworkPaths = [NSMutableArray array];
    userPaths = [NSMutableArray array];
    for (index = 0; index < [bundles count]; index++) {
        javaBundle = [bundles objectAtIndex:index];
        if (NSJavaProvidesClasses([javaBundle infoDictionary])) {
            paths = _NSJavaPathCompsForBundle(javaBundle, nil, YES);
            if (paths != nil)
                [frameworkPaths addObjectsFromArray:paths];
            paths = _NSJavaPathCompsForBundle(javaBundle, nil, NO);
            if (paths != nil)
                [userPaths addObjectsFromArray:paths];
        }
    }
    [classPaths addObjectsFromArray:frameworkPaths];
    [classPaths addObjectsFromArray:userPaths];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSJavaWillCreateVirtualMachineNotification
                      object:nil];
    vmAllocation = [vmClass allocWithZone:NULL];
    classPath = [classPaths componentsJoinedByString:NSJavaPathSeparator];
    javaVM = [vmAllocation initWithClassPath:classPath];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSJavaDidCreateVirtualMachineNotification
                      object:javaVM];
    if (javaVM == nil)
        return nil;
    if (_NSJavaVM == nil)
        _NSJavaVM = javaVM;

    if ([bundles count] != 0) {
        libraryPaths = _NSJavaAbsolutePath(bundle, setupDictionary,
                                           NSJavaLibraryPath, @"Resources");
        if ([libraryPaths count] != 0) {
            nativeRuntime = NSClassFromString(NSJavaNativeRuntimeClassName);
            if (nativeRuntime != Nil) {
                for (index = 0; index < [libraryPaths count]; index++)
                    [nativeRuntime addPathToLibrarySearchPaths:
                        [libraryPaths objectAtIndex:index]];
            } else {
                NSLog(@"NSJavaBundleSetup: cannot locate class com.apple.alpha.core.NativeRuntime, library search path not set up");
            }
        }
    }

    NSJavaClassLoaderForPath([NSArray array], YES);
    for (index = 0; index < [bundles count]; index++) {
        javaBundle = [bundles objectAtIndex:index];
        if (NSJavaProvidesClasses([javaBundle infoDictionary])) {
            [javaBundle _setJavaClassesLoaded];
            [javaBundle load];
        }
    }

    classes = [setupDictionary objectForKey:NSJavaClasses];
    if ([classes isKindOfClass:[NSArray class]]) {
        for (index = 0; index < [classes count]; index++)
            [javaVM loadClass:[classes objectAtIndex:index]];
    }
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSJavaDidSetupVirtualMachineNotification
                      object:javaVM];
    return javaVM;
}
#endif

id NSJavaBundleSetup(NSBundle *bundle, NSDictionary *plist) {
    NSArray *libraryPaths;
    NSArray *searchPaths;
    NSMutableArray *classPaths;
    NSMutableArray *bundles;
#if defined(__ppc__) || defined(__POWERPC__)
    NSMutableArray *frameworkPaths;
    NSMutableArray *userBundlePaths;
    NSArray *paths;
#endif
    NSArray *userPaths;
    NSArray *classes;
    NSString *frameworkPath;
    NSString *classPath;
    NSBundle *vmBundle;
    NSBundle *loadedBundle;
    NSDictionary *setupDictionary;
    Class vmClass;
    Class nativeRuntime;
    id javaVM = _NSJavaVM;
    id ownVM;
    unsigned index;
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned libraryIndex;
#endif

#if defined(__ppc__) || defined(__POWERPC__)
    if (_usesFastJavaBundleSetup > 0)
        return _NSFastJavaBundleSetup(bundle, plist);
#endif

    ownVM = [plist objectForKey:NSJavaOwnVirtualMachine];
    if (javaVM != nil && ![ownVM isKindOfClass:[NSString class]])
        return javaVM;

    searchPaths = NSSearchPathForDirectoriesInDomains(
        NSLibraryDirectory, NSSystemDomainMask, YES);
#if defined(__ppc__) || defined(__POWERPC__)
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSJavaWillSetupVirtualMachineNotification
                      object:nil];
#endif
    frameworkPath = [searchPaths count] != 0
        ? [[searchPaths objectAtIndex:0]
            stringByAppendingPathComponent:@"Frameworks/JavaVM.framework"]
        : [@"/" stringByAppendingPathComponent:
            @"Frameworks/JavaVM.framework"];
    vmBundle = [NSBundle bundleWithPath:frameworkPath];
    vmClass = [vmBundle classNamed:@"NSJavaVirtualMachine"];
    if (vmClass == Nil)
        return nil;

    if (plist == nil)
        plist = [bundle infoDictionary];
    setupDictionary = NSJavaDefinitiveSetupDictionary(plist, YES);
    classPaths = _NSJavaAbsolutePath(bundle, setupDictionary,
                                     NSJavaPath, nil);
    classes = [[vmClass defaultClassPath]
        componentsSeparatedByString:NSJavaPathSeparator];
    [classPaths addObjectsFromArray:classes];
    userPaths = [setupDictionary objectForKey:NSJavaUserPath];
    if ([userPaths isKindOfClass:[NSArray class]] && [userPaths count] != 0)
        [classPaths addObjectsFromArray:userPaths];
    classPath = [classPaths componentsJoinedByString:NSJavaPathSeparator];
#if defined(__ppc__) || defined(__POWERPC__)
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSJavaWillCreateVirtualMachineNotification
                      object:nil];
#endif
    javaVM = [[vmClass allocWithZone:NULL] initWithClassPath:classPath];
#if defined(__ppc__) || defined(__POWERPC__)
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSJavaDidCreateVirtualMachineNotification
                      object:javaVM];
#endif
    if (javaVM == nil)
        return nil;
    if (_NSJavaVM == nil)
        _NSJavaVM = javaVM;

#if defined(__ppc__) || defined(__POWERPC__)
    bundles = [NSMutableArray arrayWithCapacity:8];
    [bundles addObjectsFromArray:[NSBundle allFrameworks]];
    [bundles addObjectsFromArray:[NSBundle allBundles]];
    if ([bundles count] != 0) {
        frameworkPaths = [NSMutableArray array];
        userBundlePaths = [NSMutableArray array];
        for (index = 0; index < [bundles count]; index++) {
            loadedBundle = [bundles objectAtIndex:index];
            if (NSJavaProvidesClasses([loadedBundle infoDictionary])) {
                if (loadedBundle != bundle) {
                    paths = _NSJavaPathCompsForBundle(loadedBundle, nil, YES);
                    if (paths != nil)
                        [frameworkPaths addObjectsFromArray:paths];
                    paths = _NSJavaPathCompsForBundle(loadedBundle, nil, NO);
                    if (paths != nil)
                        [userBundlePaths addObjectsFromArray:paths];
                }

                libraryPaths = _NSJavaAbsolutePath(bundle, setupDictionary,
                    NSJavaLibraryPath, @"Resources");
                if ([libraryPaths count] != 0) {
                    nativeRuntime = NSClassFromString(
                        NSJavaNativeRuntimeClassName);
                    if (nativeRuntime != Nil) {
                        for (libraryIndex = 0;
                             libraryIndex < [libraryPaths count];
                             libraryIndex++)
                            [nativeRuntime addPathToLibrarySearchPaths:
                                [libraryPaths objectAtIndex:libraryIndex]];
                    } else {
                        NSLog(@"NSJavaBundleSetup: cannot locate class com.apple.alpha.core.NativeRuntime, library search path not set up");
                    }
                }
            }
        }
        [frameworkPaths addObjectsFromArray:userBundlePaths];
        NSJavaClassLoaderForPath(frameworkPaths, YES);
        for (index = 0; index < [bundles count]; index++) {
            loadedBundle = [bundles objectAtIndex:index];
            if (NSJavaProvidesClasses([loadedBundle infoDictionary])) {
                [loadedBundle _setJavaClassesLoaded];
                [loadedBundle load];
            }
        }
    }
#else
    bundles = [NSMutableArray arrayWithCapacity:8];
    [bundles addObjectsFromArray:[NSBundle allBundles]];
    [bundles addObjectsFromArray:[NSBundle allFrameworks]];
    for (index = 0; index < [bundles count]; index++) {
        loadedBundle = [bundles objectAtIndex:index];
        if (loadedBundle != bundle)
            [loadedBundle load];
    }

    libraryPaths = _NSJavaAbsolutePath(bundle, setupDictionary,
                                       NSJavaLibraryPath, @"Resources");
    nativeRuntime = NSClassFromString(NSJavaNativeRuntimeClassName);
    if (nativeRuntime != Nil) {
        for (index = 0; index < [libraryPaths count]; index++)
            [nativeRuntime addPathToLibrarySearchPaths:
                [libraryPaths objectAtIndex:index]];
    } else {
        NSLog(@"NSJavaBundleSetup: cannot locate class com.apple.alpha.core.NativeRuntime, library search path not set up");
    }
#endif

    classes = [setupDictionary objectForKey:NSJavaClasses];
    if ([classes isKindOfClass:[NSArray class]]) {
        for (index = 0; index < [classes count]; index++)
            [javaVM loadClass:[classes objectAtIndex:index]];
    }
#if defined(__ppc__) || defined(__POWERPC__)
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSJavaDidSetupVirtualMachineNotification
                      object:javaVM];
#endif
    return javaVM;
}

void NSJavaBundleCleanup(NSBundle *bundle, NSDictionary *plist) {
    NSArray *libraryPaths = _NSJavaAbsolutePath(bundle, plist,
                                                NSJavaLibraryPath, @"Resources");
    Class nativeRuntime;
    unsigned count;
    unsigned index;

    if (libraryPaths == nil || [libraryPaths count] == 0)
        return;
    nativeRuntime = NSClassFromString(NSJavaNativeRuntimeClassName);
    if (nativeRuntime == Nil) {
        NSLog(@"NSJavaBundleCleanup: cannot locate class com.apple.alpha.core.NativeRuntime, library search path not cleaned up");
        return;
    }
    count = [libraryPaths count];
    for (index = 0; index < count; index++)
        [nativeRuntime removePathFromLibrarySearchPaths:
            [libraryPaths objectAtIndex:index]];
}
