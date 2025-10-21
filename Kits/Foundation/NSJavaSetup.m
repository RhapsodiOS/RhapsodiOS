/*	NSJavaSetup.m
	Setup of Java VM
	Copyright 1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSJavaSetup.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSArray.h>

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

// Function implementations

BOOL NSJavaNeedsVirtualMachine(NSDictionary *plist) {
    // TODO: Implement this function
    return NO;
}

BOOL NSJavaProvidesClasses(NSDictionary *plist) {
    // TODO: Implement this function
    return NO;
}

BOOL NSJavaNeedsToLoadClasses(NSDictionary *plist) {
    // TODO: Implement this function
    return NO;
}

id NSJavaSetup(NSDictionary *plist) {
    // TODO: Implement this function
    return nil;
}

id NSJavaSetupVirtualMachine() {
    // TODO: Implement this function
    return nil;
}

id NSJavaObjectNamedInPath(NSString *name, NSArray *path) {
    // TODO: Implement this function
    return nil;
}

NSArray *NSJavaClassesFromPath(NSArray *path, NSArray *wanted, BOOL usesyscl, id *vm) {
    // TODO: Implement this function
    return nil;
}

NSArray *NSJavaClassesForBundle(NSBundle *bundle, BOOL usesyscl, id *vm) {
    // TODO: Implement this function
    return nil;
}

id NSJavaBundleSetup(NSBundle *bundle, NSDictionary *plist) {
    // TODO: Implement this function
    return nil;
}

void NSJavaBundleCleanup(NSBundle *bundle, NSDictionary *plist) {
    // TODO: Implement this function
}
