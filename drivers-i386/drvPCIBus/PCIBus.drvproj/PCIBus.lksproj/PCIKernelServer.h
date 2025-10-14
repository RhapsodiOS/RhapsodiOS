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
 * PCIKernelServer.h
 * PCI Kernel Server Instance Header
 */

#ifndef _PCIKERNELSERVER_H_
#define _PCIKERNELSERVER_H_

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>

/*
 * PCIKernelServerInstance - Kernel server for PCI operations
 */
@interface PCIKernelServerInstance : IODevice
{
    @private
    void *_pciData;
    BOOL _initialized;
}

/*
 * Server lifecycle methods
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/*
 * PCI presence detection
 */
- (BOOL)isPCIPresent;

/*
 * PCI configuration space access
 */
- (unsigned int)configAddress:(unsigned int)offset device:(unsigned int)dev
                      function:(unsigned int)func bus:(unsigned int)bus;
- (unsigned int)configRead:(unsigned int)bus device:(unsigned int)dev
                  function:(unsigned int)func offset:(unsigned int)offset width:(int)width;
- (void)configWrite:(unsigned int)bus device:(unsigned int)dev
           function:(unsigned int)func offset:(unsigned int)offset
              width:(int)width value:(unsigned int)value;

/*
 * High-level register access
 */
- (BOOL)getRegister:(unsigned int)reg device:(unsigned int)dev
           function:(unsigned int)func bus:(unsigned int)bus data:(unsigned int *)data;
- (BOOL)setRegister:(unsigned int)reg device:(unsigned int)dev
           function:(unsigned int)func bus:(unsigned int)bus data:(unsigned int)data;

/*
 * PCI device enumeration
 */
- (int)scanBus:(unsigned int)busNum;
- (BOOL)deviceExists:(unsigned int)bus device:(unsigned int)dev function:(unsigned int)func;
- (BOOL)testIDs:(unsigned int *)ids dev:(unsigned int)dev fun:(unsigned int)func bus:(unsigned int)bus;

/*
 * Resource allocation
 */
- (void *)allocateResourceDescriptionForDevice:(unsigned int)bus
                                        device:(unsigned int)dev
                                      function:(unsigned int)func;

@end

#endif /* _PCIKERNELSERVER_H_ */
