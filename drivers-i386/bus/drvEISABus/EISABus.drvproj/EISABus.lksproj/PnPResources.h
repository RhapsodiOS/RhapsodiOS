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
 * PnPResources.h
 * PnP Resources Collection
 */

#ifndef _PNPRESOURCES_H_
#define _PNPRESOURCES_H_

#import <objc/Object.h>

/* Structure for PnP configuration registers */
typedef struct {
    unsigned char field0_0x0[4][5];      /* 24-bit memory (4 slots x 5 bytes) */
    unsigned char field1_0x14[4][9];     /* 32-bit memory (4 slots x 9 bytes) */
    unsigned char field2_0x38[8][2];     /* I/O ports (8 slots x 2 bytes) */
    unsigned char field3_0x48[2][2];     /* IRQs (2 slots x 2 bytes) */
    unsigned char field4_0x4c[2][2];     /* DMAs (2 slots x 2 bytes) */
} PnPConfigRegisters;

/* PnPResources - Collection of all PnP resources for a device */
@interface PnPResources : Object
{
    @private
    id _irq;        /* IRQ resource container (PnPResource) at offset 0x04 */
    id _dma;        /* DMA resource container (PnPResource) at offset 0x08 */
    id _port;       /* I/O port resource container (PnPResource) at offset 0x0c */
    id _memory;     /* Memory resource container (PnPResource) at offset 0x10 */
}

/*
 * Initialization
 */
- init;
- initFromDeviceDescription:(id)description;
- initFromRegisters:(PnPConfigRegisters *)registers;

/*
 * Resource access
 */
- (id)irq;
- (id)dma;
- (id)port;
- (id)memory;

/*
 * Resource management
 */
- (id)addIRQ:(id)irqObject;
- (id)addDMA:(id)dmaObject;
- (id)addIOPort:(id)portObject;
- (id)addMemory:(id)memoryObject;

/*
 * Dependent resources
 */
- markStartDependentResources;

/*
 * Configuration
 */
- (void)configure:(id)config Using:(id)depConfig;

/*
 * Output
 */
- (void)print;

/*
 * Memory management
 */
- free;

@end

#endif /* _PNPRESOURCES_H_ */
