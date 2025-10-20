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
 * EISAKernBus+PlugAndPlayPrivate.h
 * Private PnP Methods Category for EISAKernBus
 */

#ifndef _EISAKERNBUS_PLUGANDPLAYPRIVATE_H_
#define _EISAKERNBUS_PLUGANDPLAYPRIVATE_H_

#import "EISAKernBus.h"

/*
 * PlugAndPlayPrivate category
 * Private methods for Plug and Play device enumeration and configuration
 */
@interface EISAKernBus (PlugAndPlayPrivate)

/*
 * Find a PnP card with matching ID, serial number, and logical device
 * Returns the matching card/device or nil if not found
 */
- findCardWithID:(unsigned int)cardID
          Serial:(unsigned int)serialNum
   LogicalDevice:(int)logicalDevice;

/*
 * Deactivate logical devices on a card
 * Disables the specified logical device(s)
 */
- (void)deactivateLogicalDevices:(id)device;

/*
 * Initialize PnP without BIOS support
 * Performs manual ISA PnP card enumeration
 */
- (BOOL)initializeNoBIOS;

/*
 * Initialize PnP subsystem
 * Sets up PnP BIOS interface and enumerates devices
 */
- (BOOL)initializePnP;

/*
 * Get configuration for a specific card and logical device
 * Returns the resource configuration for the device
 */
- getConfigForCard:(id)card LogicalDevice:(int)logicalDevice;

/*
 * Allocate resources for a device
 * Assigns resources using the specified dependent function and description
 */
- (BOOL)allocateResources:(id)resources
                    Using:(id)depFunction
       DependentFunction:(id)function
             Description:(id)description;

/*
 * Set PnP resources from device description
 * Configures device resources based on the description
 */
- (BOOL)pnpSetResourcesForDescription:(id)description;

@end

#endif /* _EISAKERNBUS_PLUGANDPLAYPRIVATE_H_ */
