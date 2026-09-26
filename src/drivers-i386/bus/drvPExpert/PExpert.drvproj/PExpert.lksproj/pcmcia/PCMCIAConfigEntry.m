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
 * PCMCIA Configuration Entry Implementation
 */

#import "PCMCIAConfigEntry.h"
#import <string.h>

@implementation PCMCIAConfigEntry

- init
{
    [super init];

    /* Initialize all fields to zero */
    memset((char *)self + sizeof(id), 0, sizeof(*self) - sizeof(id));

    return self;
}

- copy
{
    PCMCIAConfigEntry *newEntry = [[PCMCIAConfigEntry alloc] init];

    /* Copy all instance variables */
    memcpy((char *)newEntry + sizeof(id), (char *)self + sizeof(id),
           sizeof(*self) - sizeof(id));

    return newEntry;
}

/* Configuration accessors */
- (unsigned int)configIndex
{
    return index;
}

- (unsigned int)interfaceType
{
    return interfaceType;
}

/* I/O accessors */
- (unsigned int)ioAddressLines
{
    return IOAddrLines;
}

- (BOOL)io8BitSupported
{
    return bus8;
}

- (BOOL)io16BitSupported
{
    return bus16;
}

- (unsigned int)ioRangeCount
{
    return PortRanges.numEntries;
}

- (unsigned int)ioRangeStartAt:(unsigned int)index
{
    if (index >= PCMCIA_PORT_ENTRIES) {
        return 0;
    }
    return PortRanges.table[index].base;
}

- (unsigned int)ioRangeLengthAt:(unsigned int)index
{
    if (index >= PCMCIA_PORT_ENTRIES) {
        return 0;
    }
    return PortRanges.table[index].length;
}

/* IRQ accessors */
- (BOOL)irqPresent
{
    return IRQInfo.irqUsed;
}

- (BOOL)irqShared
{
    return IRQInfo.share;
}

- (BOOL)irqPulse
{
    return IRQInfo.pulse;
}

- (BOOL)irqLevel
{
    return IRQInfo.level;
}

- (unsigned int)irqMask
{
    return IRQInfo.irqLevels;
}

/* Memory window accessors */
- (unsigned int)memWindowCount
{
    return MemSpaceInfo.numEntries;
}

- (unsigned int)memCardAddressAt:(unsigned int)index
{
    if (index >= PCMCIA_MEM_ENTRIES) {
        return 0;
    }
    return MemSpaceInfo.table[index].cardBase;
}

- (unsigned int)memLengthAt:(unsigned int)index
{
    if (index >= PCMCIA_MEM_ENTRIES) {
        return 0;
    }
    return MemSpaceInfo.table[index].length;
}

- (unsigned int)memHostAddressAt:(unsigned int)index
{
    if (index >= PCMCIA_MEM_ENTRIES) {
        return 0;
    }
    return MemSpaceInfo.table[index].hostBase;
}

- (BOOL)memHostAddressValidAt:(unsigned int)index
{
    if (index >= PCMCIA_MEM_ENTRIES) {
        return NO;
    }
    return MemSpaceInfo.table[index].anyHostBase;
}

@end
