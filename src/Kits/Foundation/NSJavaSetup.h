/*	NSJavaSetup.h
	Setup of Java VM
	Copyright 1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@class NSString, NSDictionary, NSBundle, NSArray;

FOUNDATION_EXPORT NSString * const NSJavaClasses;
FOUNDATION_EXPORT NSString * const NSJavaRoot;
FOUNDATION_EXPORT NSString * const NSJavaPath;
FOUNDATION_EXPORT NSString * const NSJavaUserPath;
FOUNDATION_EXPORT NSString * const NSJavaLibraryPath;
FOUNDATION_EXPORT NSString * const NSJavaOwnVirtualMachine;

FOUNDATION_EXPORT NSString * const NSJavaPathSeparator;
FOUNDATION_EXPORT NSString * const NSJavaBundleClassLoaderClassName;
FOUNDATION_EXPORT NSString * const NSJavaStandardClassLoaderClassName;
FOUNDATION_EXPORT NSString * const NSJavaPathResourceLocatorClassName;

FOUNDATION_EXPORT BOOL NSJavaNeedsVirtualMachine(NSDictionary *plist);
FOUNDATION_EXPORT BOOL NSJavaProvidesClasses(NSDictionary *plist);
FOUNDATION_EXPORT BOOL NSJavaNeedsToLoadClasses(NSDictionary *plist);

FOUNDATION_EXPORT NSString * const NSJavaWillSetupVirtualMachineNotification;
FOUNDATION_EXPORT NSString * const NSJavaDidSetupVirtualMachineNotification;

FOUNDATION_EXPORT NSString * const NSJavaWillCreateVirtualMachineNotification;
FOUNDATION_EXPORT NSString * const NSJavaDidCreateVirtualMachineNotification;

#ifdef __cplusplus
extern "Objective-C" {
#endif

FOUNDATION_EXPORT id NSJavaSetup(NSDictionary *plist);  // Setup if needed.
#if defined(__ppc__) || defined(__POWERPC__)
FOUNDATION_EXPORT id NSJavaSetupVirtualMachine();	// Setup in any case.
FOUNDATION_EXPORT id NSJavaGetSystemProperty(NSString *name);
FOUNDATION_EXPORT id NSJavaGetSystemPropertyOrUseDefault(NSString *name,
                                                          NSString *defaultValue);
FOUNDATION_EXPORT id NSJavaSetSystemProperty(NSString *name,
                                              NSString *value);
#endif

#if defined(__ppc__) || defined(__POWERPC__)
FOUNDATION_EXPORT id NSJavaObjectNamedInPath(NSString *name, NSArray *path);
#endif

FOUNDATION_EXPORT NSArray *NSJavaClassesFromPath(NSArray *path, NSArray *wanted, BOOL usesyscl, id *vm);
FOUNDATION_EXPORT NSArray *NSJavaClassesForBundle(NSBundle *bundle, BOOL usesyscl, id *vm);

// These functions are obsolete now...

FOUNDATION_EXPORT id NSJavaBundleSetup(NSBundle *bundle, NSDictionary *plist);
FOUNDATION_EXPORT void NSJavaBundleCleanup(NSBundle *bundle, NSDictionary *plist);
FOUNDATION_EXPORT id _NSJavaBundleClassPath(NSBundle *bundle, NSString *key);

#ifdef __cplusplus
}
#endif
