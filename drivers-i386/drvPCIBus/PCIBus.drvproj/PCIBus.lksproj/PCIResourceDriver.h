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
 * PCIResourceDriver.h
 * PCI Resource Driver Header
 */

#ifndef _PCIRESOURCEDRIVER_H_
#define _PCIRESOURCEDRIVER_H_

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>

/*
 * PCIResourceDriver - Manages PCI device resources
 */
@interface PCIResourceDriver : IODevice
{
    @private
    void *_resourceData;
    BOOL _initialized;
}

/*
 * Driver lifecycle methods
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/*
 * Resource management
 */
- (BOOL)allocateResources;
- (void)deallocateResources;

/*
 * Configuration methods
 */
- (BOOL)configureDevice;
- (void *)getResourceDescription;

@end

#endif /* _PCIRESOURCEDRIVER_H_ */
