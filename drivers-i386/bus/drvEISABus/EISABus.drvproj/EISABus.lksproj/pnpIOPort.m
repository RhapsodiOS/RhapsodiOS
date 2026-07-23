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
 * pnpIOPort.m
 * PnP I/O Port Resource Descriptor Implementation
 */

#import "pnpIOPort.h"
#import <driverkit/generalFuncs.h>

/* External verbose flag */
extern char verbose;

@implementation pnpIOPort

/*
 * Initialize from buffer with type
 * Type 8: I/O Port Descriptor (7 bytes)
 *   +0: flags (bit 0 = decode type: 0=10-bit, 1=16-bit)
 *   +1-2: min base address
 *   +3-4: max base address
 *   +5: alignment
 *   +6: length
 * Type 9: Fixed I/O Port Descriptor (3 bytes)
 *   +0-1: base address (10-bit)
 *   +2: length
 */
- initFrom:(void *)buffer Length:(int)length Type:(int)type
{
    unsigned char *data = (unsigned char *)buffer;
    unsigned char flags;
    unsigned short base;

    /* Call superclass init */
    [super init];

    if (type == 8) {
        /* I/O Port Descriptor (variable) */
        if (length != 7) {
            IOLog("PnPDeviceResources: ioport length is %d, should be 7\n", length);
            return [self free];
        }

        /* Parse flags byte */
        flags = data[0];

        /* Parse addresses and sizes */
        _min_base = *(unsigned short *)(data + 1);
        _max_base = *(unsigned short *)(data + 3);
        _alignment = (unsigned short)data[5];
        _length = (unsigned short)data[6];

        /* If alignment is 0, use length */
        if (_alignment == 0) {
            _alignment = _length;
        }

        /* Set lines decoded based on bit 0 of flags */
        if ((flags & 1) == 0) {
            _lines_decoded = 10;  /* 10-bit decode */
        } else {
            _lines_decoded = 16;  /* 16-bit decode */
        }

        /* Print if verbose */
        if (verbose) {
            [self print];
        }
    }
    else if (type == 9) {
        /* Fixed I/O Port Descriptor */
        if (length != 3) {
            IOLog("PnPDeviceResources: ioport length is %d, should be 3\n", length);
            return [self free];
        }

        /* Parse base address (mask to 10 bits) */
        base = *(unsigned short *)data & 0x3FF;
        _min_base = base;
        _max_base = base;

        /* Parse length */
        _length = (unsigned short)data[2];
        _alignment = _length;

        /* Fixed ports are always 10-bit decoded */
        _lines_decoded = 10;

        /* Print if verbose */
        if (verbose) {
            IOLog("fixed ");
            [self print];
        }
    }

    return self;
}

/*
 * Initialize with base and length
 * Sets both min and max base to the same value (fixed address)
 */
- initWithBase:(unsigned short)base Length:(unsigned short)length
{
    [super init];

    _max_base = base;
    _min_base = base;
    _length = length;

    return self;
}

/*
 * Get minimum base address
 */
- (unsigned short)min_base
{
    return _min_base;
}

/*
 * Get maximum base address
 */
- (unsigned short)max_base
{
    return _max_base;
}

/*
 * Get alignment
 */
- (unsigned short)alignment
{
    return _alignment;
}

/*
 * Get length
 */
- (unsigned short)length
{
    return _length;
}

/*
 * Get lines decoded
 */
- (unsigned char)lines_decoded
{
    return _lines_decoded;
}

/*
 * Check if port matches another port object
 * Returns YES if the other port's base address:
 *   1. Is aligned to our alignment requirement
 *   2. Falls within our min/max base range
 */
- (BOOL)matches:(id)otherPort
{
    unsigned short otherBase;
    unsigned short alignedBase;

    /* Get the other port's minimum base address */
    otherBase = [otherPort min_base];

    /* Calculate aligned base address */
    if (_alignment != 0) {
        /* Round up to next alignment boundary */
        alignedBase = _alignment * ((_alignment - 1 + otherBase) / _alignment);
    } else {
        alignedBase = otherBase;
    }

    /* Check if:
     * 1. Base is already aligned
     * 2. Base is >= our minimum
     * 3. Base is <= our maximum
     */
    if ((otherBase == alignedBase) &&
        (_min_base <= otherBase) &&
        (otherBase <= _max_base)) {
        return YES;
    }

    return NO;
}

/*
 * Print I/O port information
 */
- print
{
    IOLog("i/o port: 0x%x..0x%x align 0x%x length 0x%x [%d lines]\n",
          _min_base, _max_base, _alignment, _length, _lines_decoded);
    return self;
}

/*
 * Write PnP configuration
 * Writes I/O port configuration to PnP config registers
 * Registers: 0x60 + (index*2) and 0x61 + (index*2)
 * Data: Base address (high byte, then low byte)
 */
- writePnPConfig:(id)portObject Index:(int)index
{
    unsigned short baseAddress;
    unsigned char regBase;
    unsigned char lowByte, highByte;

    /* Get base address from port object */
    baseAddress = [portObject min_base];

    /* Validate base address is within our range */
    if ((baseAddress > _max_base) || (baseAddress < _min_base)) {
        IOLog("pnpIOPort: i/o port base out of range:\n");
        [portObject print];
        [self print];
    }

    /* Calculate register base */
    regBase = 0x60 + (index * 2);

    /* Split address into bytes */
    lowByte = (unsigned char)(baseAddress & 0xFF);
    highByte = (unsigned char)((baseAddress >> 8) & 0xFF);

    /* Write high byte to first register */
    __asm__ volatile("outb %b0,%w1" : : "a"(regBase), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"(highByte), "d"(0xa79));

    /* Write low byte to second register */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 1)), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"(lowByte), "d"(0xa79));

    return self;
}

@end
