/*	NSTask.h
	Process creation
	Copyright 1996-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@class NSString, NSArray, NSDictionary;

@interface NSTask : NSObject

// Create an NSTask which can be run at a later time
// An NSTask can only be run once. Subsequent attempts to
// run an NSTask will raise.
// Upon task death a notification will be sent
//   { Name = NSTaskDidTerminateNotification; object = task; }
//

- (id)init;

// set parameters
// these methods can only be done before a launch
- (void)setLaunchPath:(NSString *)path;
- (void)setArguments:(NSArray *)arguments;
- (void)setEnvironment:(NSDictionary *)dict;
	// if not set, use current
- (void)setCurrentDirectoryPath:(NSString *)path;
	// if not set, use current

// set standard I/O channels; may be either an NSFileHandle or an NSPipe
- (void)setStandardInput:(id)input;
- (void)setStandardOutput:(id)output;
- (void)setStandardError:(id)error;

// get parameters
- (NSString *)launchPath;
- (NSArray *)arguments;
- (NSDictionary *)environment;
- (NSString *)currentDirectoryPath;

// get standard I/O channels; could be either an NSFileHandle or an NSPipe
- (id)standardInput;
- (id)standardOutput;
- (id)standardError;

// actions
- (void)launch;

- (void)interrupt; // Not always possible. Sends SIGINT, or Ctrl-C on Windows
- (void)terminate; // Not always possible. Sends SIGTERM, or Ctrl-Break on Windows

// status
- (BOOL)isRunning;
	// true during running; false if could not run or terminated.

- (int)terminationStatus;
	// raises if isRunning.

@end

@interface NSTask (NSTaskConveniences)

+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments;
	// convenience; create and launch

- (void)waitUntilExit;
	// poll the runLoop in defaultMode until task completes

@end

FOUNDATION_EXPORT NSString * const NSTaskDidTerminateNotification;

