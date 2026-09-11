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
 * Exported interface for Kernel PCMCIA Bus Resource Object(s).
 */

#ifdef	DRIVER_PRIVATE

#import <driverkit/KernBus.h>
#import <driverkit/driverTypes.h>
#import <driverkit/i386/PCMCIA.h>

#define IO_PORTS_KEY 		"I/O Ports"
#define MEM_MAPS_KEY 		"Memory Maps"
#define IRQ_LEVELS_KEY		"IRQ Levels"
#define DMA_CHANNELS_KEY	"DMA Channels"

#define PCMCIA_SOCKETS_KEY	"PCMCIA Sockets"
#define PCMCIA_TUPLE_LIST	"PCMCIA Tuple List"
#define PCMCIA_SOCKET_LIST	"PCMCIA Socket List"
#define PCMCIA_WINDOW_LIST	"PCMCIA Window List"

/*
 * PCMCIAStatus, and the protocols the adapter, socket
 * and window objects adopt, are in <driverkit/i386/PCMCIA.h>.
 */

/*
 * The PCMCIA bus object is supplied
 * by a loadable driver.  The kernel
 * only sends it messages, so the
 * instance variables are private
 * to the driver.
 */

@interface PCMCIAKernBus : KernBus

+ initialize;
+ (BOOL)probe: deviceDescription;
+ (IODeviceStyle)deviceStyle;
+ (Protocol **)requiredProtocols;
+ (BOOL)configureDriverWithTable: table;

- init;
- free;

- addAdapter: adapter;
- removeAdapter: adapter;

- allocIOWindowForSocket: socket;
- allocMemoryWindowForSocket: socket;

- memoryRangeResource;

- (void)setBusRange: (Range)range;
- (void)setVerbose: (BOOL)verbose;

- (void)statusChangedForSocket: socket
		 changedStatus: (PCMCIAStatus)status;

@end

#endif	/* DRIVER_PRIVATE */
