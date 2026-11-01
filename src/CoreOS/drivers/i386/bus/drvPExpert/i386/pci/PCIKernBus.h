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
    int _maxBusNum;
    int _maxDevNum;
    BOOL _bios16Present;
    BOOL _configMech1;
    BOOL _configMech2;
    BOOL _specialCycle1;
    BOOL _specialCycle2;
    BOOL _bios32Present;
    void *_reserved;
    int _pciVersionMajor;
    int _pciVersionMinor;
    int _lastBusNum;                /* highest bus the enumeration found */
    unsigned char _busScanned[256]; /* buses already walked */
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
- (int)maxBusNum;
- (int)maxDevNum;

- allocateResourcesForDeviceDescription:descr;

/*
 * Bus enumeration, following PCI-to-PCI bridges and numbering the ones
 * the firmware did not.
 */
- (void)scanBus:(unsigned char)bus;

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

- (BOOL)testIDs:(const char *)ids dev:(unsigned char)dev fun:(unsigned char)func bus:(unsigned char)bus;

/*
 * Message signalled interrupts.  Returns the irq the function raises
 * once enabled, or -1 when the machine is not in APIC mode or the
 * function has neither MSI nor MSI-X.  A driver puts that irq in its
 * interrupt list in place of the one from the Interrupt Line register.
 */
- (int)enableMSIForDevice:(unsigned char)devNum
                 function:(unsigned char)funNum
                      bus:(unsigned char)busNum;

- (int)disableMSIForDevice:(unsigned char)devNum
                  function:(unsigned char)funNum
                       bus:(unsigned char)busNum;

@end

#endif /* _PCIKERNBUS_H_ */
