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
 * Intel 82365 PCMCIA Controller Driver
 */

#ifndef _PCIC_H_
#define _PCIC_H_

#import <driverkit/IODirectDevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IOPower.h>
#import <driverkit/i386/PCMCIA.h>

/* Forward declarations */
@class List;
@class PCMCIAKernBus;
@class PCICSocket;
@class PCICWindow;

@interface PCIC : IODirectDevice <PCMCIAAdapter, IOPower>
{
    BOOL CirrusCompatible;     /* Flag indicating Cirrus Logic chip detection (offset 0x128) */
    List *sockets;             /* List of PCICSocket instances (offset 0x12C) */
    List *windows;             /* List of PCICWindow instances (offset 0x130) */
    id statusHandler;          /* Status change handler object (offset 0x134) */
}

/* Class methods */
+ (int)deviceStyle;
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Instance methods */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* Interrupt handling */
- (void)interruptOccurred;
- (unsigned int)interrupt;
- (void)setStatusChangeHandler:handler;

/* Power management */
- (IOReturn)setPowerState:(PMPowerState)powerState;
- (IOReturn)getPowerState:(PMPowerState *)state;
- (IOReturn)setPowerManagement:(PMPowerManagementState)flags;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)flags;

/* Socket and window list access */
- sockets;
- windows;

@end

/*
 * PCMCIA adapter behind a PCI-to-PCMCIA bridge (Cirrus Logic PD6832)
 * Recovers the adapter's I/O base from PCI configuration space, then defers
 * to PCIC for everything else
 */
@interface PCIC_PCI : PCIC

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;

@end

#endif /* _PCIC_H_ */
