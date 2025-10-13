/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * PCMCIABus.m
 * PCMCIA Bus Driver Implementation
 *
 * This driver wraps the PCMCIAKernBus implementation and provides
 * PCMCIA bus enumeration and card detection services.
 */

#import "PCMCIABus.h"
#import "PCMCIAKernBus.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/* Default number of PCMCIA sockets */
#define PCMCIA_DEFAULT_SOCKETS  2

/*
 * ============================================================================
 * PCMCIABusVersion Implementation
 * ============================================================================
 */

@interface PCMCIABusVersion : Object
{
    @private
    unsigned int _majorVersion;
    unsigned int _minorVersion;
    const char *_versionString;
}
- init;
- free;
- (unsigned int)majorVersion;
- (unsigned int)minorVersion;
- (const char *)versionString;
@end

@implementation PCMCIABusVersion

- init
{
    [super init];

    _majorVersion = 5;
    _minorVersion = 1;
    _versionString = "5.01";

    return self;
}

- free
{
    return [super free];
}

- (unsigned int)majorVersion
{
    return _majorVersion;
}

- (unsigned int)minorVersion
{
    return _minorVersion;
}

- (const char *)versionString
{
    return _versionString;
}

@end

/*
 * ============================================================================
 * PCMCIABus Implementation
 * ============================================================================
 */

@implementation PCMCIABus

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    if ([deviceDescription isKindOf:[IODeviceDescription class]]) {
        return YES;
    }
    return NO;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Create kernel bus instance */
    _kernBus = [[PCMCIAKernBus alloc] init];
    if (_kernBus == nil) {
        IOLog("PCMCIABus: Failed to create kernel bus instance\n");
        return nil;
    }

    /* Create version object */
    _version = [[PCMCIABusVersion alloc] init];
    if (_version == nil) {
        IOLog("PCMCIABus: Failed to create version object\n");
        [_kernBus free];
        return nil;
    }

    _initialized = NO;

    [self setName:"PCMCIABus"];
    [self setDeviceKind:"PCMCIABus"];
    [self setLocation:NULL];

    IOLog("PCMCIABus: Initialized (Version %s)\n", [_version versionString]);

    [self registerDevice];

    return self;
}

- free
{
    if (_version != nil) {
        [_version free];
        _version = nil;
    }

    if (_kernBus != nil) {
        [_kernBus free];
        _kernBus = nil;
    }

    return [super free];
}

/*
 * Boot driver initialization - called during boot
 */
- (BOOL)BootDriver
{
    if (_initialized) {
        return YES;
    }

    if (_kernBus == nil) {
        IOLog("PCMCIABus: BootDriver called without kernel bus\n");
        return NO;
    }

    /* Scan PCMCIA sockets */
    if ([self scanSockets]) {
        _initialized = YES;
        IOLog("PCMCIABus: BootDriver completed successfully\n");
        return YES;
    }

    IOLog("PCMCIABus: BootDriver failed to scan sockets\n");
    return NO;
}

/*
 * PCMCIA bus operations
 */

- (int)getSocketCount
{
    if (_kernBus != nil) {
        return [_kernBus numSockets];
    }
    return 0;
}

- (BOOL)scanSockets
{
    int socketCount;
    int cardsFound = 0;
    int i;

    if (_kernBus == nil) {
        return NO;
    }

    socketCount = [_kernBus numSockets];

    IOLog("PCMCIABus: Scanning %d PCMCIA socket%s\n",
          socketCount, (socketCount == 1) ? "" : "s");

    /* Trigger socket probing */
    [_kernBus probeAllSockets];

    /* Count how many sockets have cards */
    for (i = 0; i < socketCount; i++) {
        id pool = [_kernBus socketAtIndex:i];
        if (pool && [pool cardPresent]) {
            cardsFound++;
        }
    }

    IOLog("PCMCIABus: Found %d PCMCIA card%s\n",
          cardsFound, (cardsFound == 1) ? "" : "s");

    return YES;  /* Always return success even if no cards found */
}

@end
