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

/*
 * The ivar layout below is Apple's, recovered from the PCMCIABus_reloc
 * class structure: seventeen ivars totalling an instance size of 520.
 * PCMCIAKernBusParsing.m writes these fields by raw byte offset, using
 * the same offsets, so the layout is load-bearing rather than cosmetic.
 */

#define PCMCIA_POWER_ENTRIES    7
#define PCMCIA_PORT_ENTRIES     16
#define PCMCIA_MEM_ENTRIES      16

/* {?="mantissa"s"exponent"s} */
typedef struct {
    short           mantissa;
    short           exponent;
} PCMCIAScalar;

/* {_IOPortRangeTable="numEntries"I"table"[16{?="base"I"length"I}]} */
typedef struct _IOPortRangeTable {
    unsigned int    numEntries;
    struct {
        unsigned int    base;
        unsigned int    length;
    } table[PCMCIA_PORT_ENTRIES];
} IOPortRangeTable;

/* {?="irqUsed"c"share"c"pulse"c"level"c"NMI"c"IOCK"c"BERR"c"VEND"c"irqLevels"L} */
typedef struct {
    char            irqUsed;
    char            share;
    char            pulse;
    char            level;
    char            NMI;
    char            IOCK;
    char            BERR;
    char            VEND;
    unsigned long   irqLevels;
} PCMCIAIRQInfo;

/* {?="numEntries"I"table"[16{?="hostBase"I"length"I"cardBase"I"anyHostBase"c}]} */
typedef struct {
    unsigned int    numEntries;
    struct {
        unsigned int    hostBase;
        unsigned int    length;
        unsigned int    cardBase;
        char            anyHostBase;
    } table[PCMCIA_MEM_ENTRIES];
} PCMCIAMemSpaceInfo;

@interface PCMCIAConfigEntry : Object
{
@private
    unsigned int        index;                          /* +4   */
    int                 interfaceType;                  /* +8   */
    char                BVDActive;                      /* +12  */
    char                WPActive;                       /* +13  */
    char                ReadyBusyActive;                /* +14  */
    char                MemoryWaitRequired;             /* +15  */
    PCMCIAScalar        VccPowerInfo[PCMCIA_POWER_ENTRIES];  /* +16  */
    PCMCIAScalar        Vpp1PowerInfo[PCMCIA_POWER_ENTRIES]; /* +44  */
    PCMCIAScalar        Vpp2PowerInfo[PCMCIA_POWER_ENTRIES]; /* +72  */
    PCMCIAScalar        waitTiming;                     /* +100 */
    PCMCIAScalar        readyBusyTiming;                /* +104 */
    unsigned int        IOAddrLines;                    /* +108 */
    char                bus8;                           /* +112 */
    char                bus16;                          /* +113 */
    /* Declared by tag, not through the typedef: the reference encodes this
     * one as {_IOPortRangeTable=...} where its other structs are anonymous,
     * and the tag does not survive a typedef here. */
    struct _IOPortRangeTable  PortRanges;               /* +116 */
    PCMCIAIRQInfo       IRQInfo;                        /* +248 */
    PCMCIAMemSpaceInfo  MemSpaceInfo;                   /* +260 */
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
