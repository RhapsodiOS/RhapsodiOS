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
 * PnPResources.m
 * PnP Resources Collection Implementation
 */

#import "PnPResources.h"
#import "PnPResource.h"
#import "pnpIRQ.h"
#import "pnpDMA.h"
#import "pnpIOPort.h"
#import "pnpMemory.h"
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>

/* External verbose flag */
extern char verbose;

@implementation PnPResources

/*
 * Initialize resources collection
 * Creates four PnPResource containers for IRQ, DMA, port, and memory
 */
- init
{
    [super init];

    /* Allocate resource containers */
    _irq = [[PnPResource alloc] init];
    _dma = [[PnPResource alloc] init];
    _port = [[PnPResource alloc] init];
    _memory = [[PnPResource alloc] init];

    /* If any allocation failed, free and return nil */
    if ((_irq == nil) || (_dma == nil) || (_port == nil) || (_memory == nil)) {
        return [self free];
    }

    return self;
}

/*
 * Free resources collection
 * Frees all four resource containers
 */
- free
{
    [_irq free];
    [_dma free];
    [_port free];
    [_memory free];

    return [super free];
}

/*
 * Get IRQ resource container
 */
- (id)irq
{
    return _irq;
}

/*
 * Get DMA resource container
 */
- (id)dma
{
    return _dma;
}

/*
 * Get I/O port resource container
 */
- (id)port
{
    return _port;
}

/*
 * Get memory resource container
 */
- (id)memory
{
    return _memory;
}

/*
 * Add IRQ resource
 * Adds IRQ object to the IRQ resource list
 */
- (id)addIRQ:(id)irqObject
{
    id list = [_irq list];
    return [list addObject:irqObject];
}

/*
 * Add DMA resource
 * Adds DMA object to the DMA resource list
 */
- (id)addDMA:(id)dmaObject
{
    id list = [_dma list];
    return [list addObject:dmaObject];
}

/*
 * Add I/O port resource
 * Adds port object to the port resource list
 */
- (id)addIOPort:(id)portObject
{
    id list = [_port list];
    return [list addObject:portObject];
}

/*
 * Add memory resource
 * Adds memory object to the memory resource list
 */
- (id)addMemory:(id)memoryObject
{
    id list = [_memory list];
    return [list addObject:memoryObject];
}

/*
 * Mark start of dependent resources
 * Sets the dependent start index for all resource types
 * This marks where dependent (alternative) resources begin in each list
 */
- (void)markStartDependentResources
{
    int count;
    id list;

    /* Set IRQ dependent start */
    list = [_irq list];
    count = [list count];
    [_irq setDepStart:count];

    /* Set DMA dependent start */
    list = [_dma list];
    count = [list count];
    [_dma setDepStart:count];

    /* Set port dependent start */
    list = [_port list];
    count = [list count];
    [_port setDepStart:count];

    /* Set memory dependent start */
    list = [_memory list];
    count = [list count];
    [_memory setDepStart:count];
}

/*
 * Configure device using resources
 * Iterates through all resource types and writes configuration to PnP registers
 * For each resource type, gets resources from config and writes using depConfig for fallback
 */
- (void)configure:(id)config Using:(id)depConfig
{
    id resourceContainers[4];
    SEL selectors[4];
    int i, j;
    id configResourceContainer;
    id configList;
    id resourceObject;
    id depResourceContainer;
    id ourResourceObject;

    /* Setup arrays for iteration */
    resourceContainers[0] = _memory;
    resourceContainers[1] = _port;
    resourceContainers[2] = _irq;
    resourceContainers[3] = _dma;

    selectors[0] = @selector(memory);
    selectors[1] = @selector(port);
    selectors[2] = @selector(irq);
    selectors[3] = @selector(dma);

    /* Process each resource type */
    for (i = 0; i < 4; i++) {
        /* Get resource container from config */
        configResourceContainer = [config perform:selectors[i]];
        configList = [configResourceContainer list];

        /* Process each resource in this type */
        j = 0;
        while (1) {
            /* Get resource at index j from config */
            resourceObject = [configList objectAt:j];
            if (resourceObject == nil) {
                break;
            }

            /* Get our resource using dependent fallback */
            depResourceContainer = [depConfig perform:selectors[i]];
            ourResourceObject = [resourceContainers[i] objectAt:j Using:depResourceContainer];

            /* Write PnP configuration for this resource */
            [ourResourceObject writePnPConfig:resourceObject Index:j];

            j++;
        }
    }
}

/*
 * Initialize from device description
 * Parses device description and creates resource objects
 * Looks for "I/O Ports", "IRQ Levels", "DMA Channels", and "Memory Maps" keys
 */
- initFromDeviceDescription:(id)description
{
    id resources;
    int i;
    id resource;
    unsigned long long range;
    unsigned int base, length;
    id irqObject, dmaObject, portObject, memoryObject;
    int item;

    /* Initialize */
    if ([self init] == nil) {
        return nil;
    }

    /* Parse I/O ports */
    resources = [description resourcesForKey:"I/O Ports"];
    i = 0;
    while (1) {
        resource = [resources objectAt:i];
        if (resource == nil) {
            break;
        }

        /* Get range (base and length) */
        range = [resource range];
        base = range & 0xFFFF;
        length = (range >> 32) & 0xFFFF;

        /* Create port object */
        portObject = [[pnpIOPort alloc] initWithBase:base Length:length];
        if (portObject == nil) {
            return [self free];
        }

        [self addIOPort:portObject];
        i++;
    }

    /* Parse IRQ levels */
    resources = [description resourcesForKey:"IRQ Levels"];
    i = 0;
    while (1) {
        resource = [resources objectAt:i];
        if (resource == nil) {
            break;
        }

        /* Get IRQ number */
        item = [resource item];

        /* Create IRQ object */
        irqObject = [[pnpIRQ alloc] init];
        if (irqObject == nil) {
            return [self free];
        }

        [irqObject addToIRQList:(id)item];
        [self addIRQ:irqObject];
        i++;
    }

    /* Parse DMA channels */
    resources = [description resourcesForKey:"DMA Channels"];
    i = 0;
    while (1) {
        resource = [resources objectAt:i];
        if (resource == nil) {
            break;
        }

        /* Get DMA channel */
        item = [resource item];

        /* Create DMA object */
        dmaObject = [[pnpDMA alloc] init];
        if (dmaObject == nil) {
            return [self free];
        }

        [dmaObject addDMAToList:(id)item];
        [self addDMA:dmaObject];
        i++;
    }

    /* Parse memory maps */
    resources = [description resourcesForKey:"Memory Maps"];
    i = 0;
    while (1) {
        resource = [resources objectAt:i];
        if (resource == nil) {
            break;
        }

        /* Get range (base and length) */
        range = [resource range];
        base = range & 0xFFFFFFFF;
        length = (range >> 32) & 0xFFFFFFFF;

        /* Create memory object */
        memoryObject = [[pnpMemory alloc] initWithBase:base Length:length
                                                 Bit16:NO Bit32:NO HighAddr:NO Is32:NO];
        if (memoryObject == nil) {
            return [self free];
        }

        [self addMemory:memoryObject];
        i++;
    }

    return self;
}

/*
 * Initialize from PnP configuration registers
 * Reads current hardware configuration and creates resource objects
 */
- initFromRegisters:(PnPConfigRegisters *)registers
{
    int i;
    unsigned short portBase;
    unsigned char irqNum, irqFlags;
    unsigned char dmaChannel;
    unsigned int memBase24, memControl24, memLimit24;
    unsigned int memBase32, memControl32, memLimit32;
    unsigned int length;
    id portObject, irqObject, dmaObject, memoryObject;
    id memList;
    int memCount;

    /* Initialize */
    if ([self init] == nil) {
        return nil;
    }

    /* Parse I/O ports (8 slots) */
    for (i = 0; i < 8; i++) {
        portBase = (registers->field2_0x38[i][0] << 8) | registers->field2_0x38[i][1];

        if (portBase != 0) {
            portObject = [[pnpIOPort alloc] initWithBase:portBase Length:0];
            if (portObject == nil) {
                return [self free];
            }

            [self addIOPort:portObject];

            if (verbose) {
                [portObject print];
            }
        }
    }

    /* Parse IRQs (2 slots) */
    for (i = 0; i < 2; i++) {
        irqNum = registers->field3_0x48[i][0];

        /* IRQ 2 redirects to IRQ 9 */
        if (irqNum == 2) {
            irqNum = 9;
        }

        irqFlags = registers->field3_0x48[i][1];

        if (irqNum != 0) {
            irqObject = [[pnpIRQ alloc] init];
            if (irqObject == nil) {
                return [self free];
            }

            [irqObject addToIRQList:(id)irqNum];
            [irqObject setHigh:(irqFlags & 2) Level:(irqFlags & 1)];
            [self addIRQ:irqObject];

            if (verbose) {
                [irqObject print];
            }
        }
    }

    /* Parse DMA channels (2 slots) */
    for (i = 0; i < 2; i++) {
        dmaChannel = registers->field4_0x4c[i][0];

        if (dmaChannel != 4) {
            dmaObject = [[pnpDMA alloc] init];
            if (dmaObject == nil) {
                return [self free];
            }

            [dmaObject addDMAToList:(id)dmaChannel];
            [self addDMA:dmaObject];

            if (verbose) {
                [dmaObject print];
            }
        }
    }

    /* Parse 24-bit memory (4 slots) */
    for (i = 0; i < 4; i++) {
        memBase24 = ((unsigned int)registers->field0_0x0[i][0] << 16) |
                    ((unsigned int)registers->field0_0x0[i][1] << 8);

        if (memBase24 != 0) {
            memControl24 = registers->field0_0x0[i][2];
            memLimit24 = ((unsigned int)registers->field0_0x0[i][3] << 16) |
                         ((unsigned int)registers->field0_0x0[i][4] << 8);

            /* Calculate length */
            length = 0;
            if (memLimit24 != 0) {
                if ((memControl24 & 1) == 0) {
                    /* Range length mode - invert and add 1 */
                    length = ((memLimit24 ^ 0xFFFFFF) + 1);
                } else {
                    /* High address decode mode - subtract base from limit */
                    length = memLimit24 - memBase24;
                }
            }

            memoryObject = [[pnpMemory alloc] initWithBase:memBase24
                                                    Length:length
                                                     Bit16:(memControl24 & 2)
                                                     Bit32:NO
                                                  HighAddr:(memControl24 & 1)
                                                      Is32:NO];
            if (memoryObject == nil) {
                return [self free];
            }

            [self addMemory:memoryObject];

            if (verbose) {
                [memoryObject print];
            }
        }
    }

    /* Check if we already have 32-bit memory */
    memList = [_memory list];
    memCount = [memList count];

    if (memCount == 0) {
        /* Parse 32-bit memory (4 slots) */
        for (i = 0; i < 4; i++) {
            memBase32 = ((unsigned int)registers->field1_0x14[i][0] << 24) |
                        ((unsigned int)registers->field1_0x14[i][1] << 16) |
                        ((unsigned int)registers->field1_0x14[i][2] << 8) |
                        ((unsigned int)registers->field1_0x14[i][3]);

            if (memBase32 != 0) {
                memControl32 = registers->field1_0x14[i][4];
                memLimit32 = ((unsigned int)registers->field1_0x14[i][5] << 24) |
                             ((unsigned int)registers->field1_0x14[i][6] << 16) |
                             ((unsigned int)registers->field1_0x14[i][7] << 8) |
                             ((unsigned int)registers->field1_0x14[i][8]);

                /* Calculate length */
                length = 0;
                if (memLimit32 != 0) {
                    if ((memControl32 & 1) == 0) {
                        /* Range length mode - negate */
                        length = (~memLimit32 + 1);
                    } else {
                        /* High address decode mode - subtract base from limit */
                        length = memLimit32 - memBase32;
                    }
                }

                memoryObject = [[pnpMemory alloc] initWithBase:memBase32
                                                        Length:length
                                                         Bit16:(memControl32 & 2)
                                                         Bit32:(memControl32 & 4)
                                                      HighAddr:(memControl32 & 1)
                                                          Is32:YES];

                [self addMemory:memoryObject];

                if (verbose) {
                    [memoryObject print];
                }
            }
        }
    }

    return self;
}

/*
 * Print all resources
 * Iterates through all resource types and prints each resource
 */
- (void)print
{
    id resourceContainers[4];
    id list;
    int i, j;
    id resource;

    /* Setup array for iteration (port, IRQ, memory, DMA) */
    resourceContainers[0] = _port;
    resourceContainers[1] = _irq;
    resourceContainers[2] = _memory;
    resourceContainers[3] = _dma;

    /* Print each resource type */
    for (i = 0; i < 4; i++) {
        list = [resourceContainers[i] list];

        /* Print each resource in this type */
        j = 0;
        while (1) {
            resource = [list objectAt:j];
            if (resource == nil) {
                break;
            }

            [resource print];
            j++;
        }
    }
}

@end
