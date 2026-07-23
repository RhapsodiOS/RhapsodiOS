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
#import <driverkit/KernBusMemory.h>
#import <driverkit/KernBusInterrupt.h>
#import <objc/List.h>

/* Socket info structure (24 bytes) */
typedef struct {
    unsigned int    status;         // Offset 0 - Current socket status
    unsigned char   flag1;          // Offset 4
    unsigned char   probed;         // Offset 5 - Card has been probed
    unsigned short  padding;        // Offset 6
    id              pool;           // Offset 8 - PCMCIAPool
    id              tupleList;      // Offset 12 - List of PCMCIATuple objects
    id              deviceDesc;     // Offset 16 - KernDeviceDescription
    id              cardID;         // Offset 20 - PCMCIAid
} SocketInfo;

/* Global BIOS memory bitmap - 3 uints (12 bytes) for tracking BIOS ROM regions */
/* Covers 0xC0000-0xF0000 range: 192KB / 2KB blocks = 96 blocks = 3 uints */
extern unsigned int biosBitmap[3];

/*
 * Protocol for PCMCIA status change notifications
 */
@protocol PCMCIAStatusChange

- statusChangedForSocket:socket changedStatus:(unsigned int)status;

@end

/*
 * Protocol for PCMCIA adapter drivers
 */
@protocol PCMCIAAdapter

- setStatusChangeHandler:handler;
- sockets;

@end


@interface PCMCIAKernBusInterrupt : KernBusInterrupt <KernBusInterrupt>
{
@private
    id		_PCMCIALock;
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
#define PCMCIA_SOCKETS_KEY	"PCMCIA Sockets"
#define PCMCIA_TUPLE_LIST	"PCMCIA Tuple List"
#define PCMCIA_SOCKET_LIST	"PCMCIA Socket List"
#define PCMCIA_WINDOW_LIST	"PCMCIA Window List"

@interface PCMCIAKernBus : KernBus
{
@private
    id              _adapters;              /* Offset 0x10: List of PCMCIA adapters */
    unsigned int    _memoryBase;            /* Offset 0x14: Memory range base */
    unsigned int    _memoryLength;          /* Offset 0x18: Memory range length */
    id              _socketMap;             /* Offset 0x1c: HashTable mapping sockets to info */
    int             _verbose;               /* Offset 0x20: Verbose logging flag */
    id              _memoryRangeResource;   /* Offset 0x24: Cached memory range resource */
}

/* Class methods */
+ (BOOL)configureDriverWithTable:table;
+ (int)deviceStyle;
+ (BOOL)probe:deviceDesc;
+ (id *)requiredProtocols;

- init;
- free;

/* Adapter management */
- addAdapter:adapter;
- removeAdapter:adapter;

/* Window allocation */
- allocIOWindowForSocket:socket;
- allocMemoryWindowForSocket:socket;

/* Resource access */
- memoryRangeResource;

/* Configuration */
- (void)setBusRange:(Range)range;
- (void)setVerbose:(BOOL)verbose;

/* Status changes */
- (void)statusChangedForSocket:socket changedStatus:(unsigned int)status;

@end

#endif	/* DRIVER_PRIVATE */
