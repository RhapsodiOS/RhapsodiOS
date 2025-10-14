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
 * PCIBus.m
 * PCI Bus Driver Implementation
 */

#import "PCIBus.h"
#import "PCIKernelServer.h"
#import "PCIResourceDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>

/*
 * ============================================================================
 * PCIBus Implementation
 * ============================================================================
 */

@implementation PCIBus

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

    /* Create kernel server instance */
    _kernelServer = [[PCIKernelServerInstance alloc]
                     initFromDeviceDescription:deviceDescription];
    if (_kernelServer == nil) {
        IOLog("PCIBus: Failed to create kernel server instance\n");
        return nil;
    }

    _initialized = NO;
    maxBusNum = 0;
    maxDevNum = 0;

    [self setName:"PCIBus"];
    [self setDeviceKind:"PCIBus"];
    [self setLocation:NULL];

    IOLog("PCI bus support enabled\n");

    [self registerDevice];

    return self;
}

- free
{
    if (_kernelServer != nil) {
        [_kernelServer free];
        _kernelServer = nil;
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

    if (_kernelServer == nil) {
        IOLog("PCIBus: BootDriver called without kernel server\n");
        return NO;
    }

    /* Scan PCI buses */
    if ([self scanBuses]) {
        _initialized = YES;
        IOLog("PCIBus: BootDriver completed successfully\n");
        return YES;
    }

    IOLog("PCIBus: BootDriver failed to scan buses\n");
    return NO;
}

/*
 * PCI bus operations
 */

- (int)getBusCount
{
    return (int)(maxBusNum + 1);
}

- (BOOL)scanBuses
{
    unsigned int bus, dev, func;
    int totalDevices = 0;
    unsigned int highestBus = 0;
    unsigned int highestDev = 0;

    IOLog("PCIBus: Scanning for PCI devices...\n");

    /* Scan all possible buses (0-255) */
    for (bus = 0; bus < 256; bus++) {
        BOOL foundOnBus = NO;

        /* Scan all possible devices (0-31) */
        for (dev = 0; dev < 32; dev++) {
            /* Check function 0 first */
            if ([_kernelServer deviceExists:bus device:dev function:0]) {
                unsigned int headerType;

                foundOnBus = YES;
                totalDevices++;

                /* Update highest bus and device numbers */
                if (bus > highestBus) {
                    highestBus = bus;
                }
                if (dev > highestDev) {
                    highestDev = dev;
                }

                /* Check if this is a multi-function device */
                headerType = [_kernelServer configRead:bus device:dev function:0
                                               offset:0x0E width:1];

                if (headerType & 0x80) {
                    /* Multi-function device, scan functions 1-7 */
                    for (func = 1; func < 8; func++) {
                        if ([_kernelServer deviceExists:bus device:dev function:func]) {
                            totalDevices++;
                        }
                    }
                }
            }
        }

        /* Early exit optimization - if we haven't found devices in 8 consecutive buses, stop */
        if (!foundOnBus && bus > highestBus + 8) {
            break;
        }
    }

    /* Store the maximum bus and device numbers found */
    maxBusNum = highestBus;
    maxDevNum = highestDev;

    IOLog("PCIBus: Scan complete - Found %d device%s on %d bus%s\n",
          totalDevices, (totalDevices == 1) ? "" : "s",
          highestBus + 1, (highestBus == 0) ? "" : "es");
    IOLog("PCIBus: Max Bus Number: %d, Max Device Number: %d\n",
          maxBusNum, maxDevNum);

    /* Now do detailed scan on buses that have devices */
    for (bus = 0; bus <= highestBus; bus++) {
        [_kernelServer scanBus:bus];
    }

    return (totalDevices > 0);
}

@end
