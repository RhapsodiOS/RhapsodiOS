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

/* Vendor and device IDs, as read from configuration register 0 */
#define INTEL_VENDOR_ID        0x8086
#define INTEL_82424ZX_ID       0x04838086  /* 82424ZX host bridge */
#define INTEL_82434LX_ID       0x04A38086  /* 82434LX/NX host bridge */

/* DRAM Control Register bits */
#define DRAMC_WP_ENABLE        0x01    /* Bit 0: Write-Posting Enable */

@implementation Intel824X0

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    id instance;

    /* Attempt to allocate and initialize an instance */
    instance = [[Intel824X0 alloc] initFromDeviceDescription:deviceDescription];

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

    /* Set device identification */
    [self setName:"Intel824X0"];
    [self setDeviceKind:"Other"];

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

    /* One console line is composed from this prefix and one of the chipset
     * tails below, so the prefix deliberately carries no newline.
     */
    IOLog("%s: Detected ", [self name]);

    /* Identify the specific chipset */
    if (configData == INTEL_82424ZX_ID) {
        IOLog("Intel 82424ZX Host-Bridge\n");
        needsWritePostingFix = YES;
    }
    else if (configData == INTEL_82434LX_ID) {
        [self getPCIConfigData:&configData atRegister:PCI_REVISION_ID];

        /* Bit 4 of the revision picks the NX from the LX, the low nibble
         * is the A stepping number.
         */
        IOLog("Intel 82434%cX Host-Bridge (step A-%d)\n",
              (configData & 0x10) ? 'N' : 'L', configData & 0x0F);

        /* Only the 82434NX A-0 stepping needs the write-posting fix */
        if ((configData & 0xFF) == 0x10) {
            needsWritePostingFix = YES;
        }
    }
    else {
        /* Unrecognised part, name the vendor if it is Intel at all */
        if ((configData & 0xFFFF) == INTEL_VENDOR_ID) {
            IOLog("Intel ");
        }
        IOLog("Host-Bridge\n");
    }

    /* Apply write-posting fix if needed */
    if (needsWritePostingFix) {
        [self getPCIConfigData:&configData atRegister:PCI_DRAMC];

        if ((configData & DRAMC_WP_ENABLE) == 0) {
            IOLog("%s: PCI-to-Memory write posting disabled by BIOS.\n", [self name]);
        }
        else {
            IOLog("%s: Disabling PCI-to-Memory write posting.\n", [self name]);

            /* Disable write-posting by clearing bit 0 */
            configData &= ~DRAMC_WP_ENABLE;
            [self setPCIConfigData:configData atRegister:PCI_DRAMC];
        }
    }

    return self;
}

@end
