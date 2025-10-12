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
 * Copyright (c) 1994 NeXT Computer, Inc.
 *
 * Exported interface for Kernel PCI Bus Resource Object(s).
 *
 * HISTORY
 *
 * 11 Oct 2025 raynorpat
 *	Created proper PCI bus support for i386.
 */

#ifdef	DRIVER_PRIVATE

#import <driverkit/KernBus.h>
#import <driverkit/KernBusMemory.h>
#import <driverkit/KernBusInterrupt.h>


@interface PCIKernBusInterrupt : KernBusInterrupt <KernBusInterrupt>
{
@private
    id		_PCILock;
    int		_priorityLevel;
    int		_irq;
    BOOL	_irqAttached;
    BOOL	_irqEnabled;
}

@end


#define IO_PORTS_KEY 		"I/O Ports"
#define MEM_MAPS_KEY 		"Memory Maps"
#define IRQ_LEVELS_KEY		"IRQ Levels"
#define DMA_CHANNELS_KEY	"DMA Channels"

@interface PCIKernBus : KernBus
{
@private
}

- init;
- free;

/* PCI bus detection */
- (BOOL)isPCIPresent;

/* PCI configuration space access */
- (IOReturn)configAddress:deviceDescription
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

@end

#endif	/* DRIVER_PRIVATE */
