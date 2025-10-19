/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1998 Apple Computer, Inc.  All Rights
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

#import "Intel824X0.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <driverkit/kernelDriver.h>

/* PCI Configuration Space Registers */
#define PCI_REVISION_ID        0x08    /* Revision ID register */
#define PCI_DRAMC              0x54    /* DRAM Control Register */

/* PCI Vendor/Device IDs */
#define INTEL_VENDOR_ID        0x8086
#define INTEL_82440FX_DEVID    0x0483  /* 82440FX (Natoma) */
#define INTEL_82443FX_DEVID    0x04A3  /* 82443FX (Orion) */

/* DRAM Control Register bits */
#define DRAMC_WP_ENABLE        0x01    /* Bit 0: Write-Posting Enable */

@implementation Intel824X0

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    id instance;

    /* Attempt to allocate and initialize an instance */
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];

    /* If initialization failed, device is not supported */
    if (instance == nil) {
        return NO;
    }

    /* Initialization succeeded, device is supported */
    return YES;
}

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    BOOL needsWritePostingFix = NO;
    unsigned long configData;
    unsigned short vendorID, deviceID;
    unsigned char revisionID;
    const char *deviceName;

    /* Set device identification */
    [self setName:"Intel824X0"];
    [self setDeviceKind:"Intel 824X0 PCI Host Bridge"];

    /* Initialize from parent */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        [self free];
        return nil;
    }

    /* Verify this is device 0:0.0 (host bridge must be at device 0, function 0, bus 0) */
    if ([deviceDescription getPCIdevice:0 function:0 bus:0] != 0) {
        [self free];
        return nil;
    }

    /* Register the device */
    [self registerDevice];

    /* Read vendor and device ID */
    [self getPCIConfigData:&configData atRegister:0x00];
    vendorID = configData & 0xFFFF;
    deviceID = (configData >> 16) & 0xFFFF;

    deviceName = [self name];
    IOLog("Intel824X0: %s\n", deviceName);

    /* Identify the specific chipset */
    if (configData == ((INTEL_82440FX_DEVID << 16) | INTEL_VENDOR_ID)) {
        /* Intel 82440FX (Natoma) */
        IOLog("Intel824X0: Intel 82440FX (Natoma) PCI and Memory Controller detected\n");
        needsWritePostingFix = YES;
    }
    else if (configData == ((INTEL_82443FX_DEVID << 16) | INTEL_VENDOR_ID)) {
        /* Intel 82443FX (Orion) */
        [self getPCIConfigData:&configData atRegister:PCI_REVISION_ID];
        revisionID = configData & 0xFF;

        /* Determine stepping (C0 = 0x00, C1 = 0x01, etc.) */
        if (configData & 0x10) {
            IOLog("Intel824X0: Intel 82443FX (Orion) C-%d stepping detected\n",
                  0x0E, revisionID & 0x0F);
        } else {
            IOLog("Intel824X0: Intel 82443FX (Orion) C-%d stepping detected\n",
                  0x0C, revisionID & 0x0F);
        }

        /* Revision 0x10 and later need write-posting fix */
        if ((revisionID & 0xFF) == 0x10) {
            needsWritePostingFix = YES;
        }
    }
    else {
        /* Check if it's at least an Intel chipset */
        if (vendorID == INTEL_VENDOR_ID) {
            IOLog("Intel824X0: Intel chipset detected (device ID 0x%04x)\n", deviceID);
        }
        IOLog("Intel824X0: Unknown or unsupported chipset\n");
    }

    /* Apply write-posting fix if needed */
    if (needsWritePostingFix) {
        [self getPCIConfigData:&configData atRegister:PCI_DRAMC];

        if ((configData & DRAMC_WP_ENABLE) == 0) {
            deviceName = [self name];
            IOLog("Intel824X0: %s: Write-posting already disabled\n", deviceName);
        }
        else {
            deviceName = [self name];
            IOLog("Intel824X0: %s: Write-posting enabled, disabling...\n", deviceName);

            /* Disable write-posting by clearing bit 0 */
            configData &= ~DRAMC_WP_ENABLE;
            [self setPCIConfigData:configData atRegister:PCI_DRAMC];
        }
    }

    return self;
}

@end
