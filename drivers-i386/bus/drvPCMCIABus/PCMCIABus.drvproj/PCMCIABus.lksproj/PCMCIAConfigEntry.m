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
    return _configIndex;
}

- (unsigned int)interfaceType
{
    return _interfaceType;
}

/* I/O accessors */
- (unsigned int)ioAddressLines
{
    return _ioAddressLines;
}

- (BOOL)io8BitSupported
{
    return _io8BitSupported;
}

- (BOOL)io16BitSupported
{
    return _io16BitSupported;
}

- (unsigned int)ioRangeCount
{
    return _ioRangeCount;
}

- (unsigned int)ioRangeStartAt:(unsigned int)index
{
    if (index >= MAX_IO_RANGES) {
        return 0;
    }
    return _ioRangeStart[index];
}

- (unsigned int)ioRangeLengthAt:(unsigned int)index
{
    if (index >= MAX_IO_RANGES) {
        return 0;
    }
    return _ioRangeLength[index];
}

/* IRQ accessors */
- (BOOL)irqPresent
{
    return _irqPresent;
}

- (BOOL)irqShared
{
    return _irqShared;
}

- (BOOL)irqPulse
{
    return _irqPulse;
}

- (BOOL)irqLevel
{
    return _irqLevel;
}

- (unsigned int)irqMask
{
    return _irqMask;
}

/* Memory window accessors */
- (unsigned int)memWindowCount
{
    return _memWindowCount;
}

- (unsigned int)memCardAddressAt:(unsigned int)index
{
    if (index >= MAX_MEM_WINDOWS) {
        return 0;
    }
    return _memCardAddress[index];
}

- (unsigned int)memLengthAt:(unsigned int)index
{
    if (index >= MAX_MEM_WINDOWS) {
        return 0;
    }
    return _memLength[index];
}

- (unsigned int)memHostAddressAt:(unsigned int)index
{
    if (index >= MAX_MEM_WINDOWS) {
        return 0;
    }
    return _memHostAddress[index];
}

- (BOOL)memHostAddressValidAt:(unsigned int)index
{
    if (index >= MAX_MEM_WINDOWS) {
        return NO;
    }
    return _memHostAddressValid[index];
}

@end
