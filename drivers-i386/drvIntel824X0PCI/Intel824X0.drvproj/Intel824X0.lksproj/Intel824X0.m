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

/*
 * Intel 82430 (Triton) PCI-to-Memory Controller Configuration Registers
 * The 82430 chipset has a bug in A0 stepping that requires write-posting
 * to be disabled to prevent system crashes.
 */
#define INTEL_82430_DRAMC       0x57    /* DRAM Control Register */
#define INTEL_82430_WP_DISABLE  0xFE    /* Bit 0: 0 = Write-Posting Disabled */
#define INTEL_82430_WP_ENABLE   0x01    /* Bit 0: 1 = Write-Posting Enabled */

/* PCI Configuration Space Registers */
#define PCI_REVISION_ID         0x08    /* Revision ID register */

/* Binary exports required by the kernel */
static Protocol *protocols[] = {
    @protocol(IOPCIDirectDevice),
    nil
};

@implementation Intel824X0

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned int vendorID, deviceID;

    if ([super probe:deviceDescription] == NO) {
        return NO;
    }

    vendorID = [deviceDescription vendorID];
    deviceID = [deviceDescription deviceID];

    /* Intel vendor ID: 0x8086
     * Device IDs: 0x0483, 0x04A3
     */
    if (vendorID != 0x8086) {
        return NO;
    }

    if (deviceID != 0x0483 && deviceID != 0x04A3) {
        return NO;
    }

    IOLog("Intel824X0: probe detected device %04x:%04x\n", vendorID, deviceID);

    return YES;
}

+ (IODeviceStyle)deviceStyle
{
    return IO_DirectDevice;
}

+ (Protocol **)requiredProtocols
{
    return protocols;
}

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned int vendorID, deviceID;
    unsigned char revisionID, dramcReg;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    vendorID = [deviceDescription vendorID];
    deviceID = [deviceDescription deviceID];

    [self setDeviceKind:"Intel 824X0 PCI Host Bridge"];
    [self setLocation:""];

    /* Read the revision ID to check for A0 stepping */
    revisionID = [self configReadByte:PCI_REVISION_ID];

    IOLog("Intel824X0: initialized device %04x:%04x revision %02x\n",
          vendorID, deviceID, revisionID);

    /*
     * Disable write-posting on the Intel 82430 chipset.
     * The A0 stepping (revision 0x00) has a hardware bug that can cause
     * system crashes when write-posting is enabled. Later steppings may
     * work correctly, but we disable it unconditionally for safety.
     */
    dramcReg = [self configReadByte:INTEL_82430_DRAMC];
    if (dramcReg & INTEL_82430_WP_ENABLE) {
        IOLog("Intel824X0: Write-posting is enabled (DRAMC=0x%02x), disabling...\n", dramcReg);
        dramcReg &= INTEL_82430_WP_DISABLE;
        [self configWriteByte:dramcReg at:INTEL_82430_DRAMC];

        /* Verify the write was successful */
        dramcReg = [self configReadByte:INTEL_82430_DRAMC];
        if (dramcReg & INTEL_82430_WP_ENABLE) {
            IOLog("Intel824X0: WARNING - Failed to disable write-posting!\n");
        } else {
            IOLog("Intel824X0: Write-posting disabled successfully (DRAMC=0x%02x)\n", dramcReg);
        }
    } else {
        IOLog("Intel824X0: Write-posting already disabled (DRAMC=0x%02x)\n", dramcReg);
    }

    return self;
}

- free
{
    return [super free];
}

@end
