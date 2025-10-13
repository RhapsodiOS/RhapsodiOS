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
 * EISABus.h
 * EISA Bus Driver Header
 */

#ifndef _EISABUS_H_
#define _EISABUS_H_

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/* Forward declarations */
@class EISAKernBus;
@class EISAResourceDriver;
@class EISABusVersion;
@class EISAKernBusPlugAndPlay;
@class PnPArgStack;
@class PnPBios;
@class PnPDependentResources;
@class PnPInterruptResource;
@class PnPIOPortResource;
@class PnPMemoryResource;
@class PnPDMAResource;

/*
 * EISABus - Main EISA Bus driver class
 */
@interface EISABus : IODevice
{
    @private
    EISAKernBus *_kernBus;
    EISABusVersion *_version;
    BOOL _initialized;
}

/*
 * Driver lifecycle methods
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/*
 * Boot driver initialization
 */
- (BOOL)BootDriver;

/*
 * EISA bus operations
 */
- (int)getSlotCount;
- (BOOL)scanSlots;

@end

#endif /* _EISABUS_H_ */
