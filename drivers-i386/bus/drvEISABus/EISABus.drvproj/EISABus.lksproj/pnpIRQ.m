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
 * pnpIRQ.m
 * PnP IRQ Resource Descriptor Implementation
 */

#import "pnpIRQ.h"
#import <driverkit/generalFuncs.h>

/* External verbose flag */
extern char verbose;

@implementation pnpIRQ

/*
 * Initialize from buffer
 * Buffer format:
 *   +0-1: IRQ mask (2 bytes, bits 0-15 = IRQs 0-15)
 *   +2: Flags (1 byte, optional):
 *       bit 0: High/level
 *       bit 1: Flag 1
 *       bit 2: Flag 2
 *       bit 3: Flag 3
 */
- initFrom:(void *)buffer Length:(int)length
{
    unsigned char *data = (unsigned char *)buffer;
    unsigned short irqMask;
    int i;

    /* Call superclass init */
    [super init];

    /* Initialize count */
    _count = 0;

    /* Parse IRQ mask (first 2 bytes) */
    irqMask = *(unsigned short *)data;

    /* Add each set bit as an IRQ */
    for (i = 0; i < 16; i++) {
        if ((irqMask >> i) & 1) {
            _irqs[_count] = i;
            _count++;
        }
    }

    /* Default high/level flag */
    _highLevel = 1;

    /* Parse flags byte if present (length > 2) */
    if (length > 2) {
        unsigned char flags = data[2];
        _highLevel = flags & 1;
        _flag1 = (flags >> 1) & 1;
        _flag2 = (flags >> 2) & 1;
        _flag3 = (flags >> 3) & 1;
    }

    /* Print if verbose */
    if (verbose) {
        [self print];
    }

    return self;
}

/*
 * Get IRQs array
 * Returns pointer to array of IRQ numbers
 */
- (int *)irqs
{
    return _irqs;
}

/*
 * Get number of IRQs
 * Returns the count of IRQs in the array
 */
- (int)number
{
    return _count;
}

/*
 * Check if IRQ matches another IRQ object
 * Returns YES if any of our IRQs match the other IRQ's single IRQ
 * Only supports matching against single-IRQ descriptors
 */
- (BOOL)matches:(id)otherIRQ
{
    int otherCount;
    int *otherIRQs;
    int i;

    /* Check if other IRQ has channels */
    otherCount = [otherIRQ number];
    if (otherCount == 0) {
        return NO;
    }

    /* Only support matching against single IRQ */
    if (otherCount != 1) {
        IOLog("pnpIRQ: can only match one IRQ\n");
        return NO;
    }

    /* Get other IRQ's array */
    otherIRQs = [otherIRQ irqs];

    /* Check if any of our IRQs match the other IRQ's IRQ */
    for (i = 0; i < _count; i++) {
        if (_irqs[i] == otherIRQs[0]) {
            return YES;
        }
    }

    return NO;
}

/*
 * Set high/level flags
 * Sets the appropriate flag based on high/level combination:
 * - high=NO,  level=NO  -> low, edge
 * - high=NO,  level=YES -> low, level
 * - high=YES, level=NO  -> high, edge
 * - high=YES, level=YES -> high, level
 */
- setHigh:(BOOL)high Level:(BOOL)level
{
    if (!high) {
        if (level) {
            _flag3 = 1;  /* low, level */
        } else {
            _flag1 = 1;  /* low, edge */
        }
    } else {
        if (level) {
            _flag2 = 1;  /* high, level */
        } else {
            _highLevel = 1;  /* high, edge */
        }
    }

    return self;
}

/*
 * Add IRQ to list
 * Adds an IRQ number to the internal array (max 16)
 */
- addToIRQList:(id)list
{
    if (_count < 16) {
        _irqs[_count] = (int)list;
        _count++;
    }
    return self;
}

/*
 * Print IRQ information
 */
- print
{
    BOOL firstIRQ = YES;
    int i;
    const char *separator;

    /* Print IRQ numbers */
    IOLog("irq: ");
    for (i = 0; i < _count; i++) {
        separator = firstIRQ ? "" : ", ";
        IOLog("%s%d", separator, _irqs[i]);
        firstIRQ = NO;
    }

    /* Print flags */
    if (_highLevel) {
        IOLog(" [high, edge]");
    }
    if (_flag1) {
        IOLog(" [low, edge]");
    }
    if (_flag2) {
        IOLog(" [high, level]");
    }
    if (_flag3) {
        IOLog(" [low, level]");
    }

    IOLog("\n");

    return self;
}

/*
 * Write PnP configuration
 * Writes IRQ configuration to PnP config registers
 * Registers: 0x70 + (index*2) and 0x71 + (index*2)
 * Data: IRQ number (with IRQ 9 -> IRQ 2 redirection)
 */
- writePnPConfig:(id)irqObject Index:(int)index
{
    unsigned char *irqs;
    unsigned char irqNum;
    unsigned char regBase;

    /* Get IRQ array from object */
    irqs = (unsigned char *)[irqObject irqs];
    irqNum = irqs[0];

    /* IRQ 9 redirects to IRQ 2 */
    if (irqNum == 9) {
        irqNum = 2;
    }

    /* Calculate register base */
    regBase = 0x70 + (index * 2);

    /* Write IRQ number to first register (masked to 4 bits) */
    __asm__ volatile("outb %0, %1" : : "a"(regBase), "d"(0x279));
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)(irqNum & 0xF)), "d"(0xa79));

    /* Write 0 to second register */
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)(regBase + 1)), "d"(0x279));
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "d"(0xa79));

    return self;
}

@end
