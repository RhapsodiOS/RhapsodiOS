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
 * PCMCIA Configuration Entry
 *
 * Represents a parsed CFTABLE_ENTRY tuple containing configuration
 * information for I/O ports, IRQs, and memory windows.
 */

#ifndef _DRIVERKIT_I386_PCMCIACONFIGENTRY_H_
#define _DRIVERKIT_I386_PCMCIACONFIGENTRY_H_

#import <objc/Object.h>

#ifdef DRIVER_PRIVATE

#define MAX_IO_RANGES 16
#define MAX_MEM_WINDOWS 16

@interface PCMCIAConfigEntry : Object
{
@private
    unsigned int    _configIndex;           /* Offset 0x04: Configuration index (0-63) */
    unsigned int    _interfaceType;         /* Offset 0x08: Interface type */

    /* I/O configuration */
    unsigned int    _ioAddressLines;        /* Offset 0x6c: Number of address lines decoded */
    unsigned char   _io8BitSupported;       /* Offset 0x70: 8-bit I/O transfers supported */
    unsigned char   _io16BitSupported;      /* Offset 0x71: 16-bit I/O transfers supported */
    unsigned int    _ioRangeCount;          /* Offset 0x74: Number of I/O ranges */
    unsigned int    _ioRangeStart[MAX_IO_RANGES];   /* Offset 0x78: I/O range base addresses */
    unsigned int    _ioRangeLength[MAX_IO_RANGES];  /* Offset 0x7c: I/O range lengths */

    /* IRQ configuration */
    unsigned char   _irqPresent;            /* Offset 0xf8: IRQ information present */
    unsigned char   _irqShared;             /* Offset 0xf9: IRQ can be shared */
    unsigned char   _irqPulse;              /* Offset 0xfa: Pulse mode IRQ */
    unsigned char   _irqLevel;              /* Offset 0xfb: Level mode IRQ */
    unsigned int    _irqMask;               /* Offset 0x100: Bitmask of supported IRQs */

    /* Memory configuration */
    unsigned int    _memWindowCount;        /* Offset 0x104: Number of memory windows */
    unsigned int    _memCardAddress[MAX_MEM_WINDOWS];   /* Offset 0x108: Card memory addresses */
    unsigned int    _memLength[MAX_MEM_WINDOWS];        /* Offset 0x10c: Memory window lengths */
    unsigned int    _memHostAddress[MAX_MEM_WINDOWS];   /* Offset 0x110: Host memory addresses */
    unsigned char   _memHostAddressValid[MAX_MEM_WINDOWS]; /* Offset 0x114: Host address valid flags */
}

- init;
- copy;

/* Accessors */
- (unsigned int)configIndex;
- (unsigned int)interfaceType;

- (unsigned int)ioAddressLines;
- (BOOL)io8BitSupported;
- (BOOL)io16BitSupported;
- (unsigned int)ioRangeCount;
- (unsigned int)ioRangeStartAt:(unsigned int)index;
- (unsigned int)ioRangeLengthAt:(unsigned int)index;

- (BOOL)irqPresent;
- (BOOL)irqShared;
- (BOOL)irqPulse;
- (BOOL)irqLevel;
- (unsigned int)irqMask;

- (unsigned int)memWindowCount;
- (unsigned int)memCardAddressAt:(unsigned int)index;
- (unsigned int)memLengthAt:(unsigned int)index;
- (unsigned int)memHostAddressAt:(unsigned int)index;
- (BOOL)memHostAddressValidAt:(unsigned int)index;

@end

#endif /* DRIVER_PRIVATE */

#endif /* _DRIVERKIT_I386_PCMCIACONFIGENTRY_H_ */
