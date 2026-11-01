/*	NSDistributedLock.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDistributedLock.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSString.h>
#import <mach/cthreads.h>

#include <errno.h>
#include <sys/stat.h>
#include <objc/objc-class.h>

typedef struct {
    NSLock *guard;
    NSString *path;
    BOOL ownsLock;
} NSDistributedLockPrivate;

@interface NSFileManager (NSDistributedLockPrivate)
- (BOOL)directoryCanBeCreatedAtPath:(NSString *)path;
@end

extern int _NSFileModificationUNIXTime(NSString *path, BOOL followLink);

@implementation NSDistributedLock

+ (NSDistributedLock *)lockWithPath:(NSString *)path {
    return [[[self allocWithZone:NULL] initWithPath:path] autorelease];
}

- (id)initWithPath:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDistributedLockPrivate *state;

    if (![fileManager directoryCanBeCreatedAtPath:path]) {
        [self release];
        return nil;
    }

    state = NSZoneMalloc(NSZoneFromPointer(self), sizeof(NSDistributedLockPrivate));
    _priv = state;
    state->guard = [[NSLock allocWithZone:NULL] init];
    state->path = [path copyWithZone:NULL];
    state->ownsLock = NO;
    return self;
}

- (BOOL)tryLock {
    NSDistributedLockPrivate *state = _priv;
    char filePath[1028];

    if (state->guard != nil)
        [state->guard lock];
    if (state->ownsLock
        || ![state->path getFileSystemRepresentation:filePath maxLength:1024]) {
        if (state->guard != nil)
            [state->guard unlock];
        return NO;
    }
    if (mkdir(filePath, 0777) != 0) {
        if (state->guard != nil)
            [state->guard unlock];
        if (cthread_errno() == EEXIST)
            return NO;
        [NSException raise:NSGenericException
                    format:@"Attempt to lock %@ failed unexpectedly",
                           state->path];
    }
    state->ownsLock = YES;
    if (state->guard != nil)
        [state->guard unlock];
    return YES;
}

- (void)unlock {
    [self breakLock];
}

- (void)breakLock {
    NSDistributedLockPrivate *state = _priv;

    if (state->guard != nil)
        [state->guard lock];
    [[NSFileManager defaultManager] removeFileAtPath:state->path handler:nil];
    state->ownsLock = NO;
    if (state->guard != nil)
        [state->guard unlock];
}

- (NSDate *)lockDate {
    NSDistributedLockPrivate *state = _priv;
    unsigned timestamp = (unsigned)_NSFileModificationUNIXTime(state->path, NO);

    return [NSDate dateWithTimeIntervalSince1970:(double)timestamp];
}

- (id)init {
    [NSException raise:NSGenericException
                format:@"%s should not be used.", "-[NSDistributedLock init]"];
    return self;
}

- (void)dealloc {
    NSDistributedLockPrivate *state = _priv;

    if (state != NULL) {
        if (state->guard != nil)
            [state->guard lock];
        if (state->ownsLock)
            [[NSFileManager defaultManager] removeFileAtPath:state->path handler:nil];
        [state->path release];
        [state->guard release];
        NSZoneFree(NSZoneFromPointer(state), state);
    }
    [super dealloc];
}

- (NSString *)description {
    NSDistributedLockPrivate *state = _priv;

    return [NSString stringWithFormat:@"%s(0x%x) locked: %s  path: '%@'",
            self->isa->name, (unsigned)self,
            state->ownsLock ? "YES" : "NO", state->path];
}

@end
