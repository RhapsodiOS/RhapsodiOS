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
 * PCICSocket - Represents a single PCMCIA socket in the 82365 controller
 */

#ifndef _PCIC_SOCKET_H_
#define _PCIC_SOCKET_H_

#import <objc/Object.h>

/* Forward declarations */
@class List;
@class PCIC;

/*
 * Socket status bits
 */
typedef struct {
    unsigned int present:1;
    unsigned int locked:1;
    unsigned int ejectRequest:1;
    unsigned int insertRequest:1;
    unsigned int batteryStatus:2;
    unsigned int writeProtect:1;
    unsigned int ready:1;
} PCMCIAStatus;

@interface PCICSocket : Object
{
    id adapter;                     /* Parent PCIC controller */
    int socketNumber;               /* Socket number (0-3) */
    PCMCIAStatus statusMask;        /* Status change interrupt mask (offset 0xc) */
    List *windows;                  /* List of PCICWindow instances for this socket */
}

/* Initialization */
- initWithAdapter:theAdapter socketNumber:(unsigned int)number;

/* Window management */
- windows;

/* Socket information */
- (unsigned int)socketNumber;
- adapter;

/* Power management getters */
- (unsigned int)cardEnabled;
- (unsigned int)cardVccPower;
- (unsigned int)cardVppPower;
- (unsigned int)cardAutoPower;
- (unsigned int)powerStates;

/* Card configuration getters */
- (unsigned int)cardIRQ;
- (unsigned int)memoryInterface;
- (PCMCIAStatus)statusChangeMask;

/* Status */
- (PCMCIAStatus)status;

/* Power management setters */
- (void)setCardEnabled:(unsigned int)enabled;
- (void)setCardVccPower:(unsigned int)power;
- (void)setCardVppPower:(unsigned int)power;
- (void)setCardAutoPower:(unsigned int)autoPower;

/* Card configuration setters */
- (void)setCardIRQ:(unsigned int)irq;
- (void)setCardReset:(unsigned int)reset;
- (void)setMemoryInterface:(unsigned int)interface;
- (void)setStatusChangeMask:(PCMCIAStatus)mask;

/* Reset */
- (void)reset;

@end

#endif /* _PCIC_SOCKET_H_ */
