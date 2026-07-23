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
 * pnpMemory.m
 * PnP Memory Resource Descriptor Implementation
 */

#import "pnpMemory.h"
#import <driverkit/generalFuncs.h>

/* External verbose flag */
extern char verbose;

@implementation pnpMemory

/*
 * Initialize from buffer with type
 * Type 1: Memory Range Descriptor (24-bit, 9 bytes)
 *   +0: control byte
 *   +1-2: min base address (256-byte units)
 *   +3-4: max base address (256-byte units)
 *   +5-6: alignment
 *   +7-8: length (256-byte units)
 * Type 5: 32-bit Memory Range Descriptor (17 bytes)
 *   +0: control byte
 *   +1-4: min base address
 *   +5-8: max base address
 *   +9-12: alignment
 *   +13-16: length
 * Type 6: 32-bit Fixed Memory Range Descriptor (9 bytes)
 *   +0: control byte
 *   +1-4: base address
 *   +5-8: length
 */
- initFrom:(void *)buffer Length:(int)length Type:(int)type
{
    unsigned char *data = (unsigned char *)buffer;
    unsigned int *data32;

    /* Call superclass init */
    [super init];

    /* Initialize flags */
    _bit32 = 0;
    _bit16 = 0;
    _bit8 = 0;
    _is32 = 0;
    _expROM = 0;
    _shadow = 0;
    _ROM = 0;

    if (type == 5) {
        /* 32-bit Memory Range Descriptor */
        _is32 = 1;

        if (length != 17) {
            IOLog("PnPDeviceResources: 32BIT_MEMORY_RANGE ilen is %d, should be 17\n", length);
            return [self free];
        }

        /* Set control flags */
        [self setControl:data[0]];

        /* Parse addresses */
        data32 = (unsigned int *)(data + 1);
        _min_base = data32[0];
        _max_base = data32[1];
        _alignment = data32[2];
        _length = data32[3];

        /* If alignment is 0, use length */
        if (_alignment == 0) {
            _alignment = _length;
        }
    }
    else if (type == 6) {
        /* 32-bit Fixed Memory Range Descriptor */
        _is32 = 1;

        if (length != 9) {
            IOLog("PnPDeviceResources: 32BIT_FIXED_MEMORY ilen is %d, should be 9\n", length);
            return [self free];
        }

        /* Set control flags */
        [self setControl:data[0]];

        /* Parse base and length (fixed address) */
        data32 = (unsigned int *)(data + 1);
        _min_base = data32[0];
        _max_base = data32[0];
        _length = data32[1];
        _alignment = data32[1];

        /* Print if verbose */
        if (verbose) {
            IOLog("fixed ");
            [self print];
        }
    }
    else if (type == 1) {
        /* 24-bit Memory Range Descriptor */
        if (length != 9) {
            IOLog("PnPDeviceResources: MEMORY_RANGE ilen is %d, should be 3\n", length);
            return [self free];
        }

        /* Set control flags */
        [self setControl:data[0]];

        /* Parse addresses (in 256-byte units) */
        _min_base = (unsigned int)(*(unsigned short *)(data + 1)) << 8;
        _max_base = (unsigned int)(*(unsigned short *)(data + 3)) << 8;
        _alignment = (unsigned int)(*(unsigned short *)(data + 5));
        _length = (unsigned int)(*(unsigned short *)(data + 7)) << 8;

        /* If alignment is 0, use 64K */
        if (_alignment == 0) {
            _alignment = 0x10000;
        }
    }

    /* Print if verbose */
    if (verbose && type != 6) {
        [self print];
    }

    return self;
}

/*
 * Initialize with base and length
 */
- initWithBase:(unsigned int)base
        Length:(unsigned int)length
         Bit16:(BOOL)bit16
         Bit32:(BOOL)bit32
      HighAddr:(BOOL)highAddr
          Is32:(BOOL)is32
{
    [super init];

    /* Set base addresses (fixed, so min == max) */
    _max_base = base;
    _min_base = base;

    /* Set length */
    _length = length;

    /* Set bit width flags - if not bit16, assume bit8 */
    _bit8 = !bit16;
    _bit16 = bit16;
    _bit32 = bit32;

    /* Set is32 and high address decode flags */
    _is32 = is32;
    _highAddressDecode = highAddr;

    return self;
}

/*
 * Get minimum base address
 */
- (unsigned int)min_base
{
    return _min_base;
}

/*
 * Get maximum base address
 */
- (unsigned int)max_base
{
    return _max_base;
}

/*
 * Get alignment
 */
- (unsigned int)alignment
{
    return _alignment;
}

/*
 * Get length
 */
- (unsigned int)length
{
    return _length;
}

/*
 * Get bit8 flag
 */
- (BOOL)bit8
{
    return _bit8;
}

/*
 * Get bit16 flag
 */
- (BOOL)bit16
{
    return _bit16;
}

/*
 * Get bit32 flag
 */
- (BOOL)bit32
{
    return _bit32;
}

/*
 * Get is32 flag
 */
- (BOOL)is32
{
    return _is32;
}

/*
 * Get high address decode flag
 */
- (BOOL)highAddressDecode
{
    return _highAddressDecode;
}

/*
 * Check if memory matches another memory object
 * Returns YES if the other memory's base address:
 *   1. Is aligned to our alignment requirement
 *   2. Falls within our min/max base range
 */
- (BOOL)matches:(id)otherMemory
{
    unsigned int otherBase;
    unsigned int alignedBase;

    /* Get the other memory's minimum base address */
    otherBase = [otherMemory min_base];

    /* Calculate aligned base address */
    if (_alignment != 0) {
        /* Round up to next alignment boundary */
        alignedBase = ((_alignment - 1 + otherBase) / _alignment) * _alignment;
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
 * Set control byte flags
 * Parses control byte to set bit width and address decode flags
 * Control byte format:
 *   Bit 0: ROM flag
 *   Bit 1: (reserved/padding flag)
 *   Bit 2: High address decode
 *   Bits 3-4: Memory width (00=8-bit, 01=16-bit, 10=8&16-bit, 11=32-bit)
 *   Bit 5: Shadow flag
 *   Bit 6: Expansion ROM flag
 */
- setControl:(unsigned char)control
{
    unsigned char memWidth;

    /* Parse memory width (bits 3-4) */
    memWidth = (control >> 3) & 3;

    switch (memWidth) {
    case 0:
        /* 8-bit only */
        _bit8 = 1;
        _bit16 = 0;
        break;
    case 1:
        /* 16-bit only */
        _bit16 = 1;
        _bit8 = 0;
        break;
    case 2:
        /* 8-bit and 16-bit */
        _bit16 = 1;
        _bit8 = 1;
        break;
    case 3:
        /* 32-bit */
        _bit32 = 1;
        break;
    }

    /* Parse other control bits */
    _expROM = (control >> 6) & 1;
    _shadow = (control >> 5) & 1;
    _highAddressDecode = (control >> 2) & 1;
    _padding = (control >> 1) & 1;  /* Reserved bit at 0x17 */
    _ROM = control & 1;

    return self;
}

/*
 * Print memory information
 */
- print
{
    const char *memType;
    const char *addrType;

    /* Determine memory type label */
    memType = _is32 ? "32" : "24";

    /* Print base info */
    IOLog("mem%s: 0x%lx..0x%lx align 0x%lx len 0x%lx ",
          memType, (unsigned long)_min_base, (unsigned long)_max_base,
          (unsigned long)_alignment, (unsigned long)_length);

    /* Print bit width flags */
    if (_bit8) {
        IOLog("[8-bit]");
    }
    if (_bit16) {
        IOLog("[16-bit]");
    }
    if (_bit32) {
        IOLog("[32-bit]");
    }

    /* Print memory type flags */
    if (_expROM) {
        IOLog("[expROM]");
    }
    if (_shadow) {
        IOLog("[shadow]");
    }

    /* Print address decode type */
    addrType = _highAddressDecode ? "[hi addr]" : "[range]";
    IOLog(addrType);

    /* Print ROM flag */
    if (!_ROM) {
        IOLog("[ROM]");
    }

    IOLog("\n");

    return self;
}

/*
 * Write PnP configuration
 * Writes memory configuration to PnP config registers
 * 24-bit: Registers 0x40 + (index*8) through 0x44 + (index*8)
 * 32-bit: Different base per index (0x76, 0x80, 0x90, 0xa0)
 */
- writePnPConfig:(id)memoryObject Index:(int)index
{
    unsigned int baseAddr;
    unsigned char regBase;
    unsigned char control;
    unsigned int upperLimit;

    /* Get base address from memory object */
    baseAddr = [memoryObject min_base];

    /* Validate base address is within our range */
    if ((baseAddr > _max_base) || (baseAddr < _min_base)) {
        IOLog("pnpMemory: memory base out of range:\n");
        [memoryObject print];
        [self print];
    }

    if (!_is32) {
        /* 24-bit memory descriptor */
        regBase = 0x40 + (index * 8);

        /* Write base address (high byte, low byte) in 256-byte units */
        __asm__ volatile("outb %b0,%w1" : : "a"(regBase), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((baseAddr >> 8) & 0xFF)), "d"(0xa79));

        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 1)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((baseAddr >> 16) & 0xFF)), "d"(0xa79));

        /* Build control byte */
        control = 0;
        if (_bit16) {
            control |= 2;
        }

        /* Calculate upper limit */
        if (!_highAddressDecode) {
            /* Range length mode - write inverted length */
            upperLimit = ~((_length & 0xFFFFFF) - 1) >> 8;
        } else {
            /* High address decode mode - write upper address */
            control |= 1;
            upperLimit = (baseAddr + _length) >> 8;
        }

        /* Write control byte */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 2)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"(control), "d"(0xa79));

        /* Write upper limit (high byte, low byte) */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 3)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((upperLimit >> 8) & 0xFF)), "d"(0xa79));

        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 4)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(upperLimit & 0xFF)), "d"(0xa79));
    }
    else {
        /* 32-bit memory descriptor */
        /* Determine register base by index */
        switch (index) {
        case 0:
            regBase = 0x76;
            break;
        case 1:
            regBase = 0x80;
            break;
        case 2:
            regBase = 0x90;
            break;
        case 3:
            regBase = 0xa0;
            break;
        default:
            regBase = 0x76;
            break;
        }

        /* Write base address (4 bytes, little-endian) */
        __asm__ volatile("outb %b0,%w1" : : "a"(regBase), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(baseAddr & 0xFF)), "d"(0xa79));

        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 1)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((baseAddr >> 8) & 0xFF)), "d"(0xa79));

        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 2)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((baseAddr >> 16) & 0xFF)), "d"(0xa79));

        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 3)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((baseAddr >> 24) & 0xFF)), "d"(0xa79));

        /* Build control byte */
        control = 0;
        if (_bit32) {
            control = 6;
        } else if (_bit16) {
            control = 2;
        }

        /* Calculate upper limit */
        if (!_highAddressDecode) {
            /* Range length mode - write negated length */
            upperLimit = -_length;
        } else {
            /* High address decode mode - write upper address */
            control |= 1;
            upperLimit = baseAddr + _length;
        }

        /* Write control byte */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 4)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"(control), "d"(0xa79));

        /* Write upper limit (4 bytes, little-endian) */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 5)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((upperLimit >> 24) & 0xFF)), "d"(0xa79));

        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 6)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((upperLimit >> 16) & 0xFF)), "d"(0xa79));

        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 7)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)((upperLimit >> 8) & 0xFF)), "d"(0xa79));

        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(regBase + 8)), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(upperLimit & 0xFF)), "d"(0xa79));
    }

    return self;
}

@end
