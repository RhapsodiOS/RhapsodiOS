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
 * pnpDMA.m
 * PnP DMA Resource Descriptor Implementation
 */

#import "pnpDMA.h"
#import <driverkit/generalFuncs.h>

/* External verbose flag */
extern char verbose;

@implementation pnpDMA

/*
 * Initialize from buffer
 * Buffer format:
 *   +0: DMA channel mask (1 byte, bits 0-7 = channels 0-7)
 *   +1: Flags (1 byte):
 *       bits 0-1: Speed/type
 *       bit 2: Bus master
 *       bit 3: Byte mode
 *       bit 4: Word mode
 *       bits 5-6: Speed field
 */
- initFrom:(void *)buffer Length:(int)length
{
    unsigned char *data = (unsigned char *)buffer;
    unsigned char channelMask;
    unsigned char flags;
    int i;

    /* Call superclass init */
    [super init];

    /* Initialize count */
    _count = 0;

    /* Parse channel mask (first byte) */
    channelMask = data[0];

    /* Add each set bit as a DMA channel */
    for (i = 0; i < 8; i++) {
        if ((channelMask >> i) & 1) {
            _dmaChannels[_count] = i;
            _count++;
        }
    }

    /* Parse flags byte (second byte) */
    flags = data[1];

    /* Parse speed/type field (bits 0-1) */
    switch (flags & 0x3) {
    case 0:
        _speedType1 = 1;
        _speedType2 = 0;
        break;
    case 1:
        _speedType1 = 1;
        _speedType2 = 1;
        break;
    case 2:
        _speedType1 = 0;
        _speedType2 = 1;
        break;
    }

    /* Parse flag bits */
    _busmaster = (flags >> 2) & 1;
    _byteMode = (flags >> 3) & 1;
    _wordMode = (flags >> 4) & 1;
    _speedField = (flags >> 5) & 3;

    /* Print if verbose */
    if (verbose) {
        [self print];
    }

    return self;
}

/*
 * Get DMA channels array
 * Returns pointer to array of DMA channel numbers
 */
- (int *)dmaChannels
{
    return _dmaChannels;
}

/*
 * Add DMA channel to list
 * Adds a DMA channel number to the internal array (max 8)
 */
- addDMAToList:(id)list
{
    if (_count < 8) {
        _dmaChannels[_count] = (int)list;
        _count++;
    }
    return self;
}

/*
 * Get number of DMA channels
 * Returns the count of DMA channels in the array
 */
- (int)number
{
    return _count;
}

/*
 * Check if DMA matches another DMA object
 * Returns YES if any of our channels match the other DMA's single channel
 * Only supports matching against single-channel DMA descriptors
 */
- (BOOL)matches:(id)otherDMA
{
    int otherCount;
    int *otherChannels;
    int i;

    /* Check if other DMA has channels */
    otherCount = [otherDMA number];
    if (otherCount == 0) {
        return NO;
    }

    /* Only support matching against single DMA channel */
    if (otherCount != 1) {
        IOLog("pnpDMA: can only match one DMA\n");
        return NO;
    }

    /* Get other DMA's channel array */
    otherChannels = [otherDMA dmaChannels];

    /* Check if any of our channels match the other DMA's channel */
    for (i = 0; i < _count; i++) {
        if (_dmaChannels[i] == otherChannels[0]) {
            return YES;
        }
    }

    return NO;
}

/*
 * Print DMA information
 */
- print
{
    BOOL firstChannel = YES;
    int i;
    const char *separator;
    const char *speedType;

    /* Print DMA channels */
    IOLog("dma channel: ");
    for (i = 0; i < _count; i++) {
        separator = firstChannel ? "" : ", ";
        IOLog("%s%d", separator, _dmaChannels[i]);
        firstChannel = NO;
    }

    IOLog(" ");

    /* Print bit width */
    if (_speedType1) {
        IOLog("[8 bit]");
    }
    if (_speedType2) {
        IOLog("[16 bit]");
    }

    /* Always print these flags */
    IOLog("[bus master]");
    IOLog("[byte]");
    IOLog("[word]");

    /* Print speed type based on speed field */
    switch (_speedField) {
    case 0:
        speedType = "[compat]";
        break;
    case 1:
        speedType = "[type A]";
        break;
    case 2:
        speedType = "[type B]";
        break;
    case 3:
        speedType = "[type F]";
        break;
    default:
        speedType = NULL;
        break;
    }

    if (speedType != NULL) {
        IOLog(speedType);
    }

    IOLog("\n");

    return self;
}

/*
 * Write PnP configuration
 * Writes DMA configuration to PnP config registers
 * Register: 0x74 + index
 * Data: First DMA channel (masked to 3 bits)
 */
- writePnPConfig:(id)dmaObject Index:(int)index
{
    unsigned char *channels;
    unsigned char reg;

    /* Get DMA channels from the object */
    channels = (unsigned char *)[dmaObject dmaChannels];

    /* Write to PnP config register */
    reg = 0x74 + (unsigned char)index;
    __asm__ volatile("outb %b0,%w1" : : "a"(reg), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(channels[0] & 0x7)), "d"(0xa79));

    return self;
}

@end
