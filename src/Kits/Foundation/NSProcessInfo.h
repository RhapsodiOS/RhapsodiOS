/*	NSProcessInfo.h
	Information about the current process
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

enum {	/* Constants returned by -operatingSystem */
	NSWindowsNTOperatingSystem = 1,
	NSWindows95OperatingSystem,
	NSSolarisOperatingSystem,
	NSHPUXOperatingSystem,
	NSMACHOperatingSystem,
	NSSunOSOperatingSystem,
	NSOSF1OperatingSystem
};

@class NSArray, NSString, NSDictionary;

@interface NSProcessInfo : NSObject {
    @private	
    NSDictionary	*environment;
    NSArray		*arguments;
    NSString		*hostName;    
    NSString		*name;
    void		*reserved;
}

+ (NSProcessInfo *)processInfo;	

- (NSDictionary *)environment;

- (NSArray *)arguments;

- (NSString *)hostName;

- (NSString *)processName;

- (void)setProcessName:(NSString *)newName;

- (NSString *)globallyUniqueString;

- (unsigned int)operatingSystem;
- (NSString *)operatingSystemName;

@end
