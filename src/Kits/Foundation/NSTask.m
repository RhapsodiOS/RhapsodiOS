/*	NSTask.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSTask.h>

@implementation NSTask

- (id)init {
    // TODO: Implement this method
    return nil;
}

- (void)setLaunchPath:(NSString *)path {
    // TODO: Implement this method
}

- (void)setArguments:(NSArray *)arguments {
    // TODO: Implement this method
}

- (void)setEnvironment:(NSDictionary *)dict {
    // TODO: Implement this method
}

- (void)setCurrentDirectoryPath:(NSString *)path {
    // TODO: Implement this method
}

- (void)setStandardInput:(id)input {
    // TODO: Implement this method
}

- (void)setStandardOutput:(id)output {
    // TODO: Implement this method
}

- (void)setStandardError:(id)error {
    // TODO: Implement this method
}

- (NSString *)launchPath {
    // TODO: Implement this method
    return nil;
}

- (NSArray *)arguments {
    // TODO: Implement this method
    return nil;
}

- (NSDictionary *)environment {
    // TODO: Implement this method
    return nil;
}

- (NSString *)currentDirectoryPath {
    // TODO: Implement this method
    return nil;
}

- (id)standardInput {
    // TODO: Implement this method
    return nil;
}

- (id)standardOutput {
    // TODO: Implement this method
    return nil;
}

- (id)standardError {
    // TODO: Implement this method
    return nil;
}

- (void)launch {
    // TODO: Implement this method
}

- (void)interrupt; // Not always possible. Sends SIGINT, or Ctrl-C on Windows {
    // TODO: Implement this method
}

- (void)terminate; // Not always possible. Sends SIGTERM, or Ctrl-Break on Windows {
    // TODO: Implement this method
}

- (BOOL)isRunning {
    // TODO: Implement this method
    return NO;
}

- (int)terminationStatus {
    // TODO: Implement this method
    return 0;
}

+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments {
    // TODO: Implement this method
    return nil;
}

- (void)waitUntilExit {
    // TODO: Implement this method
}

@end
