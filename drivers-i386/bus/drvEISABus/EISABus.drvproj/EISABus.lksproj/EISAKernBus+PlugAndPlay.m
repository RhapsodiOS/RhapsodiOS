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
 * EISAKernBus+PlugAndPlay.m
 * Public PnP Methods Category Implementation
 */

#import "EISAKernBus+PlugAndPlay.h"
#import "eisa.h"
#import <driverkit/generalFuncs.h>
#import <objc/HashTable.h>

/* Global PnP device table and card count */
extern unsigned int maxPnPCard;
extern HashTable *pnpDeviceTable;

/* Global PnP read port */
extern unsigned short pnpReadPort;

@implementation EISAKernBus (PlugAndPlay)

/*
 * Get maximum PnP card number
 * Returns the number of PnP cards detected in the system
 */
- (unsigned int)maxPnPCard
{
    return maxPnPCard;
}

/*
 * Read a PnP configuration register
 * Reads a register from the currently selected PnP card/device
 * Uses I/O ports 0x279 (address) and pnpReadPort (data)
 */
- (unsigned char)readPnPRegister:(unsigned char)regNum
{
    unsigned char value;

    /* Write register number to address port (0x279) */
    __asm__ volatile("outb %0, %1" : : "a"(regNum), "d"(0x279));

    /* Read value from PnP read data port */
    __asm__ volatile("inb %1, %0" : "=a"(value) : "d"(pnpReadPort));

    return value;
}

/*
 * Write a PnP configuration register
 * Writes a value to a register on the currently selected PnP card/device
 * Uses I/O ports 0x279 (address) and 0xa79 (write data)
 */
- (void)writePnPRegister:(unsigned char)regNum value:(unsigned char)value
{
    /* Write register number to address port (0x279) */
    __asm__ volatile("outb %0, %1" : : "a"(regNum), "d"(0x279));

    /* Write value to PnP write data port (0xa79) */
    __asm__ volatile("outb %0, %1" : : "a"(value), "d"(0xa79));
}

/*
 * Read PnP card configuration
 * Reads the full configuration data for a specific card
 * Returns YES on success, NO on failure or invalid CSN
 */
- (BOOL)readPnPConfig:(void *)buffer length:(unsigned int *)length forCard:(unsigned char)csn
{
    /* Validate CSN (must be non-zero and within range) */
    if ((csn != 0) && (csn <= maxPnPCard)) {
        /* Call external function to read card configuration */
        return getCardConfig(csn, buffer, length);
    }

    /* Invalid CSN */
    return NO;
}

/*
 * Read PnP logical device configuration
 * Reads the configuration registers for a specific logical device on a card
 * Returns YES on success, NO on failure or invalid parameters
 */
- (BOOL)readPnPDeviceCfg:(void *)buffer
                  length:(unsigned int *)length
                 forCard:(unsigned char)csn
        andLogicalDevice:(int)logicalDevice
{
    id device;
    unsigned int deviceCount;

    /* Validate CSN (must be non-zero and within range) */
    if ((csn != 0) && (csn <= maxPnPCard)) {
        /* Get the device from the PnP device table */
        device = [pnpDeviceTable valueForKey:(void *)csn];

        /* Get the number of logical devices on this card */
        deviceCount = [device deviceCount];

        /* Validate logical device number is within range */
        if (logicalDevice <= (int)(deviceCount - 1)) {
            /* Call external function to read logical device configuration */
            return getDeviceCfg(csn, logicalDevice, buffer, length);
        }
    }

    /* Invalid CSN or logical device number */
    return NO;
}

/*
 * Read PnP system device node
 * Reads a system device node from PnP BIOS
 * Currently not implemented - always returns NO
 */
- (BOOL)readSystemNode:(void *)buffer length:(unsigned int *)length forNode:(int)nodeNum
{
    /* Not implemented - stub function */
    return NO;
}

/*
 * Get PnP ID for card
 * Reads the vendor ID from a specific card
 * Returns YES if the card was found, NO otherwise
 * The vendor ID is stored in the vendorID pointer parameter
 */
- (BOOL)getPnPId:(unsigned int *)vendorID forCsn:(unsigned char)csn
{
    id device;
    unsigned int id;

    /* Get the device from the PnP device table using CSN as key */
    device = [pnpDeviceTable valueForKey:(void *)csn];

    /* If device found, get its ID and store in pointer */
    if (device != nil) {
        id = [device ID];
        *vendorID = id;
    }

    /* Return whether device was found */
    return (device != nil);
}

/*
 * Test if card matches PnP IDs
 * Checks if a card matches any of the specified vendor IDs in the list
 * Returns YES if the card matches, NO otherwise
 */
- (BOOL)testIDs:(const char *)idList csn:(unsigned char)csn
{
    unsigned int vendorID;
    BOOL found;

    /* Get the vendor ID for this CSN */
    found = [self getPnPId:&vendorID forCsn:csn];

    /* If card not found, return NO */
    if (!found) {
        return NO;
    }

    /* Check if vendor ID matches any in the ID list */
    return EISAMatchIDs(vendorID, idList);
}

/*
 * Look for PnP IDs in system
 * Searches for cards/devices matching the ID list and returns the specified instance
 * Sets the logical device number in the logicalDevice pointer
 * Returns the card object containing the match, or nil if not found
 */
- lookForPnPIDs:(const char *)idList
       Instance:(int)instance
  LogicalDevice:(unsigned int *)logicalDevice
{
    id card;
    unsigned int csn;
    unsigned int cardID;
    BOOL matches;
    BOOL found;
    int instanceCounter;
    int logicalDeviceIndex;
    id logicalDeviceObj;
    unsigned int logicalDevID;
    unsigned int compatCount;
    unsigned int compatIndex;
    id compatIDObj;
    unsigned int compatID;
    unsigned int logicalDeviceNumber;

    /* Initialize return values and counters */
    card = nil;
    instanceCounter = 0;
    found = NO;
    *logicalDevice = 0;

    /* Search through all PnP cards */
    for (csn = 1; csn <= maxPnPCard && !found; csn++) {
        /* Get card from device table */
        card = [pnpDeviceTable valueForKey:(void *)csn];

        /* Check if the card's main ID matches the ID list */
        cardID = [card ID];
        matches = EISAMatchIDs(cardID, idList);

        if (matches) {
            /* Found a match - check if this is the requested instance */
            if (instance == instanceCounter) {
                found = YES;
                /* For card-level match, logical device is 0 */
                *logicalDevice = 0;
            } else {
                instanceCounter++;
            }
        } else {
            /* Card ID doesn't match - check logical devices */
            logicalDeviceIndex = 0;

            while (!found) {
                /* Get next logical device */
                logicalDeviceObj = [[card deviceList] objectAt:logicalDeviceIndex];
                if (logicalDeviceObj == nil) {
                    break;  /* No more logical devices */
                }

                /* Check if logical device ID matches */
                logicalDevID = [logicalDeviceObj ID];
                matches = EISAMatchIDs(logicalDevID, idList);

                if (matches) {
                    /* Found a match - check if this is the requested instance */
                    if (instance == instanceCounter) {
                        found = YES;
                        /* Get and store logical device number */
                        logicalDeviceNumber = [logicalDeviceObj logicalDeviceNumber];
                        *logicalDevice = logicalDeviceNumber;
                    } else {
                        instanceCounter++;
                    }
                } else {
                    /* Logical device ID doesn't match - check compatible IDs */
                    compatCount = [[logicalDeviceObj compatIDs] count];

                    for (compatIndex = 0; compatIndex < compatCount && !found; compatIndex++) {
                        /* Get compatible ID */
                        compatIDObj = [[logicalDeviceObj compatIDs] objectAt:compatIndex];
                        compatID = [compatIDObj unsignedIntValue];
                        matches = EISAMatchIDs(compatID, idList);

                        if (matches) {
                            /* Found a match - check if this is the requested instance */
                            if (instance == instanceCounter) {
                                found = YES;
                                /* Get and store logical device number */
                                logicalDeviceNumber = [logicalDeviceObj logicalDeviceNumber];
                                *logicalDevice = logicalDeviceNumber;
                            } else {
                                instanceCounter++;
                            }
                        }
                    }
                }

                logicalDeviceIndex++;
            }
        }
    }

    /* Return the card if found, nil otherwise */
    if (found) {
        return card;
    } else {
        return nil;
    }
}

@end
