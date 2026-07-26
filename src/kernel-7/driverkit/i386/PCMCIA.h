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
 * Copyright (c) 1995 NeXT Computer, Inc.
 *
 * Protocols adopted by the objects a PCMCIA adapter driver supplies:
 * the adapter itself, its sockets, and its windows.  The kernel never
 * sees these classes, only the messages they answer, so the contract
 * between the two lives here rather than in either one.
 *
 * These four declarations were recovered from the Objective-C protocol
 * records in Apple's shipped Intel82365PCMCIA driver, whose PCIC,
 * PCICSocket and PCICWindow classes adopt them.  Selector order matches
 * that binary: GCC emits a protocol's method list in reverse source
 * order, so the order below is the reverse of the order found there.
 */

#ifndef _DRIVERKIT_I386_PCMCIA_H_
#define _DRIVERKIT_I386_PCMCIA_H_

#ifdef	DRIVER_PRIVATE

/*
 * The state of a socket, as reported by an adapter driver.
 * The 82365 adapter driver declares the same eight bits in
 * PCICSocket.h.
 */

typedef struct {
    unsigned int	present:1;
    unsigned int	locked:1;
    unsigned int	ejectRequest:1;
    unsigned int	insertRequest:1;
    unsigned int	batteryStatus:2;
    unsigned int	writeProtect:1;
    unsigned int	ready:1;
} PCMCIAStatus;

/*
 * The adapter: the driver object that owns a set of
 * sockets and the windows that can be mapped onto them.
 */

@protocol PCMCIAAdapter

- sockets;
- windows;
- (void)setStatusChangeHandler:handler;

@end

/*
 * A socket, into which one card is inserted.
 */

@protocol PCMCIASocket

- adapter;
- (int)socketNumber;
- windows;

- (PCMCIAStatus)status;
- (void)reset;
- powerStates;

/* Setter first here, unlike the pairs below; that is the reference's order. */
- (char)setStatusChangeMask:(PCMCIAStatus)mask;
- (PCMCIAStatus)statusChangeMask;

- (char)cardEnabled;
- (char)setCardEnabled:(char)enabled;

- (char)cardAutoPower;
- (char)setCardAutoPower:(char)autoPower;

- (unsigned int)cardVccPower;
- (char)setCardVccPower:(unsigned int)power;

- (unsigned int)cardVppPower;
- (char)setCardVppPower:(unsigned int)power;

- (unsigned int)cardIRQ;
- (void)setCardReset:(char)reset;
- (char)setCardIRQ:(unsigned int)irq;

- (char)memoryInterface;
- (char)setMemoryInterface:(char)memoryInterface;

@end

/*
 * A window: a range of host address space mapped
 * onto a card's memory or I/O space.
 */

@protocol PCMCIAWindow

- validSockets;
- socket;
- (char)setSocket:socket;

- (unsigned int)systemAddress;
- (unsigned int)cardAddress;
- (unsigned int)mapSize;
- (char)setMapWithSize:(unsigned int)size
	 systemAddress:(unsigned int)systemAddress
	   cardAddress:(unsigned int)cardAddress;

- (char)attributeMemory;
- (char)setAttributeMemory:(char)attributeMemory;

- (char)enabled;
- (char)setEnabled:(char)enabled;

- (char)memoryInterface;
- (char)setMemoryInterface:(char)memoryInterface;

- (char)is16Bit;
- (char)set16Bit:(char)is16Bit;

@end

/*
 * What a window is capable of.  Adopted separately from
 * PCMCIAWindow so that an adapter can describe windows
 * that differ in what they can map.
 */

@protocol PCMCIAWindowAttributes

- (char)supportsMemory;
- (char)supportsIO;
- (char)canUse8Bit;
- (char)canUse16Bit;
- (char)mustBePowerOfTwo;

- (unsigned int)firstSystemAddress;
- (unsigned int)lastSystemAddress;

- (int)minimumSize;
- (int)maximumSize;
- (int)sizeAlignment;
- (int)baseAlignment;
- (int)offsetAlignment;

- (int)slowestSpeed;
- (int)fastestSpeed;

- (char)writeProtectable;
- (int)addressLinesDecoded;

@end

#endif	/* DRIVER_PRIVATE */

#endif	/* _DRIVERKIT_I386_PCMCIA_H_ */
