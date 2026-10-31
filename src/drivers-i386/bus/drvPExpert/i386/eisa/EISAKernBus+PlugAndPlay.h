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
 * EISAKernBus+PlugAndPlay.h
 * Public PnP Methods Category for EISAKernBus
 */

#ifndef _EISAKERNBUS_PLUGANDPLAY_H_
#define _EISAKERNBUS_PLUGANDPLAY_H_

#import "EISAKernBus.h"

/*
 * PlugAndPlay category
 * Public methods for Plug and Play device access and enumeration
 */
@interface EISAKernBus (PlugAndPlay)

/*
 * Get maximum PnP card number
 * Returns the number of PnP cards detected in the system
 */
- (unsigned int)maxPnPCard;

/*
 * Read a PnP configuration register
 * Reads a register from the currently selected PnP card/device
 */
- (unsigned char)readPnPRegister:(unsigned char)regNum;

/*
 * Write a PnP configuration register
 * Writes a value to a register on the currently selected PnP card/device
 */
- (void)writePnPRegister:(unsigned char)regNum value:(unsigned char)value;

/*
 * Read PnP card configuration
 * Reads the full configuration data for a specific card
 */
- (BOOL)readPnPConfig:(void *)buffer length:(unsigned int *)length forCard:(unsigned char)csn;

/*
 * Read PnP logical device configuration
 * Reads the configuration registers for a specific logical device on a card
 */
- (BOOL)readPnPDeviceCfg:(void *)buffer
                  length:(unsigned int *)length
                 forCard:(unsigned char)csn
        andLogicalDevice:(int)logicalDevice;

/*
 * Read PnP system device node
 * Reads a system device node from PnP BIOS
 */
- (BOOL)readSystemNode:(void *)buffer length:(unsigned int *)length forNode:(int)nodeNum;

/*
 * Get PnP ID for card
 * Reads the vendor ID from a specific card
 * Returns YES if found, NO if not found
 */
- (BOOL)getPnPId:(unsigned int *)vendorID forCsn:(unsigned char)csn;

/*
 * Test if card matches PnP IDs
 * Checks if a card matches any of the specified vendor IDs
 */
- (BOOL)testIDs:(const char *)idList csn:(unsigned char)csn;

/*
 * Look for PnP IDs in system
 * Searches for cards matching the ID list and returns the specified instance
 */
- lookForPnPIDs:(const char *)idList
       Instance:(int)instance
  LogicalDevice:(unsigned int *)logicalDevice;

@end

#endif /* _EISAKERNBUS_PLUGANDPLAY_H_ */
