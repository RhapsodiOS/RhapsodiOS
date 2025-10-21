/*	NSFileHandle.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSFileHandle.h>

@implementation NSFileHandle

- (NSData *)availableData {
    // TODO: Implement this method
    return nil;
}

- (NSData *)readDataToEndOfFile {
    // TODO: Implement this method
    return nil;
}

- (NSData *)readDataOfLength:(unsigned int)length {
    // TODO: Implement this method
    return nil;
}

- (void)writeData:(NSData *)data {
    // TODO: Implement this method
}

- (unsigned long long)offsetInFile {
    // TODO: Implement this method
    return 0;
}

- (unsigned long long)seekToEndOfFile {
    // TODO: Implement this method
    return 0;
}

- (void)seekToFileOffset:(unsigned long long)offset {
    // TODO: Implement this method
}

- (void)truncateFileAtOffset:(unsigned long long)offset {
    // TODO: Implement this method
}

- (void)synchronizeFile {
    // TODO: Implement this method
}

- (void)closeFile {
    // TODO: Implement this method
}

+ (id)fileHandleWithStandardInput {
    // TODO: Implement this method
    return nil;
}

+ (id)fileHandleWithStandardOutput {
    // TODO: Implement this method
    return nil;
}

+ (id)fileHandleWithStandardError {
    // TODO: Implement this method
    return nil;
}

+ (id)fileHandleWithNullDevice {
    // TODO: Implement this method
    return nil;
}

+ (id)fileHandleForReadingAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

+ (id)fileHandleForWritingAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

+ (id)fileHandleForUpdatingAtPath:(NSString *)path {
    // TODO: Implement this method
    return nil;
}

- (void)readInBackgroundAndNotifyForModes:(NSArray *)modes {
    // TODO: Implement this method
}

- (void)readInBackgroundAndNotify {
    // TODO: Implement this method
}

- (void)readToEndOfFileInBackgroundAndNotifyForModes:(NSArray *)modes {
    // TODO: Implement this method
}

- (void)readToEndOfFileInBackgroundAndNotify {
    // TODO: Implement this method
}

- (void)acceptConnectionInBackgroundAndNotifyForModes:(NSArray *)modes {
    // TODO: Implement this method
}

- (void)acceptConnectionInBackgroundAndNotify {
    // TODO: Implement this method
}

- (void)waitForDataInBackgroundAndNotifyForModes:(NSArray *)modes {
    // TODO: Implement this method
}

- (void)waitForDataInBackgroundAndNotify {
    // TODO: Implement this method
}

- (id)initWithNativeHandle:(void *)nativeHandle closeOnDealloc:(BOOL)closeopt {
    // TODO: Implement this method
    return nil;
}

- (id)initWithNativeHandle:(void *)nativeHandle {
    // TODO: Implement this method
    return nil;
}

- (void *)nativeHandle {
    // TODO: Implement this method
    return nil;
}

- (id)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)closeopt {
    // TODO: Implement this method
    return nil;
}

- (id)initWithFileDescriptor:(int)fd {
    // TODO: Implement this method
    return nil;
}

- (int)fileDescriptor {
    // TODO: Implement this method
    return 0;
}

@end

@implementation NSPipe

- (NSFileHandle *)fileHandleForReading {
    // TODO: Implement this method
    return nil;
}

- (NSFileHandle *)fileHandleForWriting {
    // TODO: Implement this method
    return nil;
}

- (id)init {
    // TODO: Implement this method
    return nil;
}

+ (id)pipe {
    // TODO: Implement this method
    return nil;
}

@end
