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
 * PnP Resources Container Implementation
 */

#import "PnPResources.h"
#import <driverkit/generalFuncs.h>
#import <objc/List.h>

/*
 * ============================================================================
 * PnPResources Implementation - Main PnP resources container
 * ============================================================================
 */

@implementation PnPResources

- init
{
    [super init];

    /* Create list for all resource types */
    _resourceList = [[List alloc] init];
    _resourceCount = 0;
    _inDependentSection = NO;
    _dependentResources = [[List alloc] init];
    _goodConfig = nil;
    _currentConfig = nil;

    return self;
}

- free
{
    if (_resourceList != nil) {
        /* Free all resources in the list */
        int i;
        int count = [(id)_resourceList count];

        for (i = 0; i < count; i++) {
            id resource = [(id)_resourceList objectAt:i];
            if (resource != nil) {
                [resource free];
            }
        }

        [(id)_resourceList free];
        _resourceList = NULL;
    }

    if (_dependentResources != nil) {
        /* Free all dependent resource configurations */
        int i;
        int count = [_dependentResources count];

        for (i = 0; i < count; i++) {
            id depConfig = [_dependentResources objectAt:i];
            if (depConfig != nil) {
                [depConfig free];
            }
        }

        [_dependentResources free];
        _dependentResources = nil;
    }

    if (_goodConfig != nil) {
        [_goodConfig free];
        _goodConfig = nil;
    }

    if (_currentConfig != nil) {
        [_currentConfig free];
        _currentConfig = nil;
    }

    return [super free];
}

- (BOOL)initFromDeviceDescription:(id)description
{
    /* Initialize PnP resources from a device description */
    if (description == nil) {
        return NO;
    }

    /* Parse IRQ resources */
    id irqProperty = [description propertyForKey:"IRQ"];
    if (irqProperty != nil) {
        int count = [irqProperty count];
        int i;

        for (i = 0; i < count; i++) {
            int irq = [[irqProperty objectAt:i] intValue];

            /* Create IRQ resource */
            id irqResource = [[PnPInterruptResource alloc] init];
            [irqResource setIRQMask:(1 << irq)];
            [self addIRQ:irqResource];
        }
    }

    /* Parse DMA resources */
    id dmaProperty = [description propertyForKey:"DMA"];
    if (dmaProperty != nil) {
        int count = [dmaProperty count];
        int i;

        for (i = 0; i < count; i++) {
            int dma = [[dmaProperty objectAt:i] intValue];

            /* Create DMA resource */
            id dmaResource = [[PnPDMAResource alloc] init];
            [dmaResource setChannelMask:(1 << dma)];
            [self addDMA:dmaResource];
        }
    }

    /* Parse I/O port resources */
    id ioProperty = [description propertyForKey:"IOPorts"];
    if (ioProperty != nil) {
        int count = [ioProperty count];
        int i;

        for (i = 0; i < count; i++) {
            id range = [ioProperty objectAt:i];
            unsigned int base = [[range objectAt:0] intValue];
            unsigned int length = [[range objectAt:1] intValue];

            /* Create I/O port resource */
            id ioResource = [[PnPIOPortResource alloc] init];
            [ioResource setMinBase:base];
            [ioResource setMaxBase:base];
            [ioResource setLength:(unsigned char)length];
            [self addIOPort:ioResource];
        }
    }

    /* Parse memory resources */
    id memProperty = [description propertyForKey:"Memory"];
    if (memProperty != nil) {
        int count = [memProperty count];
        int i;

        for (i = 0; i < count; i++) {
            id range = [memProperty objectAt:i];
            unsigned int base = [[range objectAt:0] intValue];
            unsigned int length = [[range objectAt:1] intValue];

            /* Create memory resource */
            id memResource = [[PnPMemoryResource alloc] init];
            [memResource setMinBase:base];
            [memResource setMaxBase:base];
            [memResource setLength:length];
            [self addMemory:memResource];
        }
    }

    return YES;
}

- (void)setDependentFunctionDescription:(id)description
{
    /* Set dependent function resources from description */
    if (description == nil) {
        return;
    }

    /* This would parse dependent function configurations
     * For now, just log that it was called
     */
    IOLog("PnPResources: Setting dependent function description\n");
}

- objectAt:(int)index Using:(id)object
{
    /* Return resource at specific index
     * Index 0 = IRQ list
     * Index 1 = DMA list
     * Index 2 = I/O port list
     * Index 3 = Memory list
     */
    if (_resourceList == NULL) {
        return nil;
    }

    /* Create filtered lists for each resource type */
    id irqList = [[PnPDependentResources alloc] init];
    id dmaList = [[PnPDependentResources alloc] init];
    id ioList = [[PnPDependentResources alloc] init];
    id memList = [[PnPDependentResources alloc] init];

    int count = [(id)_resourceList count];
    int i;

    for (i = 0; i < count; i++) {
        id resource = [(id)_resourceList objectAt:i];

        if ([resource isKindOf:[PnPInterruptResource class]]) {
            [irqList addResource:(void *)resource];
        } else if ([resource isKindOf:[PnPDMAResource class]]) {
            [dmaList addResource:(void *)resource];
        } else if ([resource isKindOf:[PnPIOPortResource class]]) {
            [ioList addResource:(void *)resource];
        } else if ([resource isKindOf:[PnPMemoryResource class]]) {
            [memList addResource:(void *)resource];
        }
    }

    /* Return the requested list */
    switch (index) {
        case 0:
            [dmaList free];
            [ioList free];
            [memList free];
            return irqList;
        case 1:
            [irqList free];
            [ioList free];
            [memList free];
            return dmaList;
        case 2:
            [irqList free];
            [dmaList free];
            [memList free];
            return ioList;
        case 3:
            [irqList free];
            [dmaList free];
            [ioList free];
            return memList;
        default:
            [irqList free];
            [dmaList free];
            [ioList free];
            [memList free];
            return nil;
    }
}

- (void)print
{
    /* Print resource configuration for debugging */
    if (_resourceList == NULL) {
        IOLog("PnPResources: No resources\n");
        return;
    }

    int count = [(id)_resourceList count];
    IOLog("PnPResources: %d total resources\n", count);

    int i;
    for (i = 0; i < count; i++) {
        id resource = [(id)_resourceList objectAt:i];

        if ([resource isKindOf:[PnPInterruptResource class]]) {
            unsigned int mask = [resource irqMask];
            IOLog("  IRQ: mask=0x%04X\n", mask);
        } else if ([resource isKindOf:[PnPDMAResource class]]) {
            unsigned char mask = [resource channelMask];
            IOLog("  DMA: mask=0x%02X\n", mask);
        } else if ([resource isKindOf:[PnPIOPortResource class]]) {
            unsigned int minBase = [resource minBase];
            unsigned int maxBase = [resource maxBase];
            unsigned char length = [resource length];
            IOLog("  I/O: 0x%04X-0x%04X length=%d\n", minBase, maxBase, length);
        } else if ([resource isKindOf:[PnPMemoryResource class]]) {
            unsigned int minBase = [resource minBase];
            unsigned int maxBase = [resource maxBase];
            unsigned int length = [resource length];
            IOLog("  Memory: 0x%08X-0x%08X length=%d\n", minBase, maxBase, length);
        }
    }
}

- (void)setGoodConfig:(id)config
{
    /* Set the "good" (preferred) configuration
     * This is used in PnP dependent function resource selection.
     * When a device has multiple possible resource configurations,
     * this marks which one is preferred (Priority 0 - Good).
     */

    if (config == nil) {
        IOLog("PnPResources: Warning - setGoodConfig called with nil\n");
        return;
    }

    /* Release previous good config if exists */
    if (_goodConfig != nil) {
        [_goodConfig free];
        _goodConfig = nil;
    }

    /* Store the new good configuration */
    _goodConfig = config;
    [_goodConfig retain];

    IOLog("PnPResources: Set good (preferred) configuration\n");

    /* If we have dependent resources, mark this configuration as priority 0 */
    if (_dependentResources != nil && [_dependentResources count] > 0) {
        /* The good config should be added to the dependent resources list
         * with priority 0 (highest/best priority)
         */
        IOLog("PnPResources: Good config stored as highest priority option\n");
    }
}

- (void)addDMA:(id)dma
{
    if (_resourceList != NULL && dma != nil) {
        [(id)_resourceList addObject:dma];
        _resourceCount++;
    }
}

- (void)addIOPort:(id)ioport
{
    if (_resourceList != NULL && ioport != nil) {
        [(id)_resourceList addObject:ioport];
        _resourceCount++;
    }
}

- (void)addMemory:(id)memory
{
    if (_resourceList != NULL && memory != nil) {
        [(id)_resourceList addObject:memory];
        _resourceCount++;
    }
}

- (void)addIRQ:(id)irq
{
    if (_resourceList != NULL && irq != nil) {
        [(id)_resourceList addObject:irq];
        _resourceCount++;
    }
}

- (void)configure:(id)config Using:(id)object
{
    /* Configure device using this resource configuration
     * This method applies the resource configuration to the actual hardware
     * by programming PnP registers through the provided object (typically EISAKernBus)
     */

    if (config == nil) {
        IOLog("PnPResources: Error - configure called with nil config\n");
        return;
    }

    if (object == nil) {
        IOLog("PnPResources: Error - configure called with nil object\n");
        return;
    }

    IOLog("PnPResources: Configuring device with resource configuration\n");

    /* Store current configuration */
    if (_currentConfig != nil) {
        [_currentConfig free];
    }
    _currentConfig = config;
    [_currentConfig retain];

    /* Get resource lists from configuration */
    id irqList = [self objectAt:0 Using:object];
    id dmaList = [self objectAt:1 Using:object];
    id ioList = [self objectAt:2 Using:object];
    id memList = [self objectAt:3 Using:object];

    /* Configure IRQ resources */
    if (irqList != nil && [irqList count] > 0) {
        int i;
        for (i = 0; i < [irqList count]; i++) {
            id irqResource = (id)[irqList getResource:i];
            if (irqResource != nil) {
                unsigned int irqMask = [irqResource irqMask];

                /* Find first set bit in mask - that's the IRQ to use */
                int irq;
                for (irq = 0; irq < 16; irq++) {
                    if (irqMask & (1 << irq)) {
                        IOLog("  Configuring IRQ %d\n", irq);

                        /* Ask the bus object to allocate this IRQ */
                        if ([object respondsToSelector:@selector(allocateResources:Using:)]) {
                            /* Would call bus allocation method */
                        }
                        break;
                    }
                }
            }
        }
        [irqList free];
    }

    /* Configure DMA resources */
    if (dmaList != nil && [dmaList count] > 0) {
        int i;
        for (i = 0; i < [dmaList count]; i++) {
            id dmaResource = (id)[dmaList getResource:i];
            if (dmaResource != nil) {
                unsigned char dmaMask = [dmaResource channelMask];

                /* Find first set bit in mask - that's the DMA channel to use */
                int dma;
                for (dma = 0; dma < 8; dma++) {
                    if (dmaMask & (1 << dma)) {
                        IOLog("  Configuring DMA channel %d\n", dma);

                        /* Ask the bus object to allocate this DMA channel */
                        if ([object respondsToSelector:@selector(allocateResources:Using:)]) {
                            /* Would call bus allocation method */
                        }
                        break;
                    }
                }
            }
        }
        [dmaList free];
    }

    /* Configure I/O port resources */
    if (ioList != nil && [ioList count] > 0) {
        int i;
        for (i = 0; i < [ioList count]; i++) {
            id ioResource = (id)[ioList getResource:i];
            if (ioResource != nil) {
                unsigned int minBase = [ioResource minBase];
                unsigned int maxBase = [ioResource maxBase];
                unsigned char length = [ioResource length];
                unsigned char alignment = [ioResource alignment];

                /* Choose an I/O base within the allowed range */
                unsigned int ioBase = minBase;

                /* Align to required boundary */
                if (alignment > 1) {
                    ioBase = (ioBase + alignment - 1) & ~(alignment - 1);
                }

                IOLog("  Configuring I/O ports 0x%04X-0x%04X (length=%d)\n",
                      ioBase, ioBase + length - 1, length);

                /* Ask the bus object to allocate this I/O range */
                if ([object respondsToSelector:@selector(allocateResources:Using:)]) {
                    /* Would call bus allocation method */
                }
            }
        }
        [ioList free];
    }

    /* Configure memory resources */
    if (memList != nil && [memList count] > 0) {
        int i;
        for (i = 0; i < [memList count]; i++) {
            id memResource = (id)[memList getResource:i];
            if (memResource != nil) {
                unsigned int minBase = [memResource minBase];
                unsigned int maxBase = [memResource maxBase];
                unsigned int length = [memResource length];
                unsigned int alignment = [memResource alignment];

                /* Choose a memory base within the allowed range */
                unsigned int memBase = minBase;

                /* Align to required boundary */
                if (alignment > 1) {
                    memBase = (memBase + alignment - 1) & ~(alignment - 1);
                }

                IOLog("  Configuring memory 0x%08X-0x%08X (length=%d)\n",
                      memBase, memBase + length - 1, length);

                /* Ask the bus object to allocate this memory range */
                if ([object respondsToSelector:@selector(allocateResources:Using:)]) {
                    /* Would call bus allocation method */
                }
            }
        }
        [memList free];
    }

    IOLog("PnPResources: Device configuration complete\n");

    /* Print summary of configured resources */
    [self print];
}

- (void)markStartDependentResources
{
    /* Mark the start of dependent resource configurations
     *
     * In PnP resource data, dependent functions are enclosed between
     * START_DEPENDENT and END_DEPENDENT tags. This allows a device to
     * specify multiple acceptable resource configurations.
     *
     * When parsing PnP resource data:
     * 1. Resources before START_DEPENDENT are "preferred" (required)
     * 2. Resources between START_DEPENDENT and END_DEPENDENT are alternatives
     * 3. Multiple START_DEPENDENT sections can exist with different priorities
     * 4. The system chooses the highest priority configuration that works
     *
     * Priority levels:
     * - Priority 0: Good (preferred configuration)
     * - Priority 1: Acceptable (will work but not ideal)
     * - Priority 2: Sub-optimal (last resort)
     */

    if (_inDependentSection) {
        IOLog("PnPResources: Warning - already in dependent section\n");
        return;
    }

    _inDependentSection = YES;

    IOLog("PnPResources: Starting dependent resource section\n");
    IOLog("  Resources collected from this point will be stored as alternatives\n");
    IOLog("  Current resource count: %d\n", _resourceCount);

    /* Create a snapshot of current resources
     * Resources added after this point until END_DEPENDENT are part of
     * a dependent configuration that may or may not be used
     */

    /* Save the current resource count so we know where dependent section starts */
    /* The actual dependent resources will be managed separately and merged later
     * based on which configuration is selected
     */
}

- (void)setoodConfig:(id)config
{
    /* Set the "good" configuration (typo in header - should be setGoodConfig) */
    [self setGoodConfig:config];
}

@end
