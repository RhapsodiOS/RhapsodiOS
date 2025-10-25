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
 * PCIKernBus.h
 * PCI Kernel Bus Driver Header
 */

#ifndef _PCIKERNBUS_H_
#define _PCIKERNBUS_H_

#import <driverkit/KernBus.h>
#import <driverkit/return.h>

/*
 * PCIKernBus - PCI bus driver conforming to KernBus interface
 */
@interface PCIKernBus : KernBus
{
    @private
    unsigned int _maxBusNum;
    unsigned int _maxDevNum;
    BOOL _bios16Present;
    BOOL _configMech1;
    BOOL _configMech2;
    BOOL _specialCycle1;
    BOOL _specialCycle2;
    BOOL _bios32Present;
    void *_reserved;
    unsigned int _pciVersionMajor;
    unsigned int _pciVersionMinor;
}

/*
 * Initialization
 */
- init;
- free;

/*
 * PCI presence detection
 */
- (BOOL)isPCIPresent;

/*
 * PCI bus and device number limits
 */
- (unsigned int)maxBusNum;
- (unsigned int)maxDevNum;

- allocateResourcesForDeviceDescription:descr;

/*
 * PCI configuration space access (KernBus interface)
 */
- (IOReturn)configAddress:(id)deviceDescription
                   device:(unsigned char *)devNum
                 function:(unsigned char *)funNum
                      bus:(unsigned char *)busNum;

- (IOReturn)getRegister:(unsigned char)address
                 device:(unsigned char)devNum
               function:(unsigned char)funNum
                    bus:(unsigned char)busNum
                   data:(unsigned long *)data;

- (IOReturn)setRegister:(unsigned char)address
                 device:(unsigned char)devNum
               function:(unsigned char)funNum
                    bus:(unsigned char)busNum
                   data:(unsigned long)data;

- (BOOL)testIDs:(unsigned int *)ids dev:(unsigned int)dev fun:(unsigned int)func bus:(unsigned int)bus;

@end

#endif /* _PCIKERNBUS_H_ */
