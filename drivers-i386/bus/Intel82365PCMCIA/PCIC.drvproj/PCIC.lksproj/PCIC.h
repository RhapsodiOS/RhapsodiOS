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
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/PCMCIA.h>
#import <driverkit/i386/PCMCIAKernBus.h>

/* Forward declarations */
@class PCMCIAKernBus;
@class PCICSocket;
@class PCICWindow;

@interface PCIC : IODirectDevice
{
    unsigned int basePort;
    unsigned int numSockets;
    unsigned int irqLevel;
    BOOL isCirrusChip;         /* Flag indicating Cirrus Logic chip detection */
    id socketList;             /* List of PCICSocket instances */
    id windowList;             /* List of PCICWindow instances */
    id statusChangeHandler;    /* Status change handler object (offset 0x134) */
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
- (IOReturn)setPowerState:(int)powerState;
- (IOReturn)getPowerState:(int *)state;
- (IOReturn)setPowerManagement:(int)flags;
- (IOReturn)getPowerManagement:(int *)flags;

/* Socket and window list access */
- sockets;
- windows;

@end

#endif /* _PCIC_H_ */
