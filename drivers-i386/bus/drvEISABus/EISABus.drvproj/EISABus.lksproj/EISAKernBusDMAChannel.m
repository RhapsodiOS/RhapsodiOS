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
 * EISAKernBusDMAChannel.m
 * EISA/ISA DMA Channel Resource Implementation
 */

#import "EISAKernBusDMAChannel.h"
#import <machdep/i386/dma_exported.h>

@implementation EISAKernBusDMAChannel

/*
 * Initialize DMA channel resource
 *
 * Initializes the DMA channel and assigns it at the hardware level.
 * If assignment fails, the object is freed and nil is returned.
 */
- initForResource:resource item:(unsigned int)item shareable:(BOOL)shareable
{
    int result;

    /* Call superclass initialization */
    [super initForResource:resource item:item shareable:shareable];

    /* Assign the DMA channel at hardware level */
    result = dma_assign_chan(item);
    if (result == 0) {
        /* DMA channel assignment failed - free and return nil */
        [super free];
        return nil;
    }

    return self;
}

/*
 * Deallocate DMA channel
 *
 * Releases the DMA channel at the hardware level before deallocating.
 */
- dealloc
{
    unsigned int channel;

    /* Get the DMA channel number */
    channel = [self item];

    /* Deassign the DMA channel at hardware level */
    dma_deassign_chan(channel);

    /* Call superclass dealloc */
    return [super dealloc];
}

@end
