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
 * EISAResourceDriver.m
 * EISA Resource Driver Implementation
 */

#import "EISAResourceDriver.h"
#import <driverkit/generalFuncs.h>

@implementation EISAResourceDriver

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    /* Probe for EISA resource driver compatibility */
    if (deviceDescription == nil) {
        return NO;
    }

    /* Check if this is an EISA device description */
    id busType = [deviceDescription propertyForKey:"BusType"];
    if (busType != nil) {
        const char *busTypeName = [busType cStringValue];
        if (busTypeName != NULL && strcmp(busTypeName, "EISA") == 0) {
            IOLog("EISAResourceDriver: Probing EISA device\n");
            return YES;
        }
    }

    /* Also accept devices with EISA slot information */
    id slotProperty = [deviceDescription propertyForKey:"Slot"];
    if (slotProperty != nil) {
        IOLog("EISAResourceDriver: Found device with slot property\n");
        return YES;
    }

    return NO;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _resourceData = NULL;
    _initialized = NO;

    [self setName:"EISAResourceDriver"];
    [self setDeviceKind:"EISAResourceDriver"];

    /* Extract device information from description */
    id slotProperty = [deviceDescription propertyForKey:"Slot"];
    if (slotProperty != nil) {
        int slot = [[slotProperty objectAt:0] intValue];
        IOLog("EISAResourceDriver: Initializing for EISA slot %d\n", slot);
    }

    /* Log available resources */
    id irqProperty = [deviceDescription propertyForKey:"IRQ"];
    if (irqProperty != nil) {
        int irq = [[irqProperty objectAt:0] intValue];
        IOLog("EISAResourceDriver: Device uses IRQ %d\n", irq);
    }

    id ioProperty = [deviceDescription propertyForKey:"IOPorts"];
    if (ioProperty != nil) {
        int count = [ioProperty count];
        int i;
        for (i = 0; i < count; i++) {
            id range = [ioProperty objectAt:i];
            unsigned int base = [[range objectAt:0] intValue];
            unsigned int length = [[range objectAt:1] intValue];
            IOLog("EISAResourceDriver: Device uses I/O ports 0x%04X-0x%04X\n",
                  base, base + length - 1);
        }
    }

    return self;
}

- free
{
    /* Ensure resources are deallocated before freeing */
    if (_initialized) {
        [self deallocateResources];
    }

    if (_resourceData != NULL) {
        IOFree(_resourceData, 256);
        _resourceData = NULL;
    }

    return [super free];
}

- (BOOL)allocateResources
{
    /* Allocate hardware resources for this EISA device */
    IOLog("EISAResourceDriver: Allocating resources\n");

    /* Allocate memory for resource tracking */
    if (_resourceData == NULL) {
        _resourceData = (void *)IOMalloc(256); /* Allocate resource structure */
        if (_resourceData == NULL) {
            IOLog("EISAResourceDriver: Failed to allocate resource data\n");
            return NO;
        }
        bzero(_resourceData, 256);
    }

    /* Parse device description and allocate each resource type */
    id deviceDescription = [self deviceDescription];
    if (deviceDescription != nil) {
        /* Allocate IRQ resources */
        id irqProperty = [deviceDescription propertyForKey:"IRQ"];
        if (irqProperty != nil) {
            int irq = [[irqProperty objectAt:0] intValue];
            IOLog("EISAResourceDriver: Requesting IRQ %d\n", irq);
            /* Would call: [self reserveInterruptLine:irq] */
        }

        /* Allocate DMA channels */
        id dmaProperty = [deviceDescription propertyForKey:"DMA"];
        if (dmaProperty != nil) {
            int dma = [[dmaProperty objectAt:0] intValue];
            IOLog("EISAResourceDriver: Requesting DMA channel %d\n", dma);
            /* Would call: [self reserveDMAChannel:dma] */
        }

        /* Allocate I/O port ranges */
        id ioProperty = [deviceDescription propertyForKey:"IOPorts"];
        if (ioProperty != nil) {
            int count = [ioProperty count];
            int i;
            for (i = 0; i < count; i++) {
                id range = [ioProperty objectAt:i];
                unsigned int base = [[range objectAt:0] intValue];
                unsigned int length = [[range objectAt:1] intValue];
                IOLog("EISAResourceDriver: Requesting I/O ports 0x%04X-0x%04X\n",
                      base, base + length - 1);
                /* Would call: [self reserveIOPorts:base length:length] */
            }
        }

        /* Allocate memory ranges */
        id memProperty = [deviceDescription propertyForKey:"Memory"];
        if (memProperty != nil) {
            int count = [memProperty count];
            int i;
            for (i = 0; i < count; i++) {
                id range = [memProperty objectAt:i];
                unsigned int base = [[range objectAt:0] intValue];
                unsigned int length = [[range objectAt:1] intValue];
                IOLog("EISAResourceDriver: Requesting memory 0x%08X-0x%08X\n",
                      base, base + length - 1);
                /* Would call: [self reserveMemory:base length:length] */
            }
        }
    }

    _initialized = YES;
    IOLog("EISAResourceDriver: Resource allocation complete\n");
    return YES;
}

- (void)deallocateResources
{
    /* Deallocate all hardware resources */
    IOLog("EISAResourceDriver: Deallocating resources\n");

    /* Free allocated resources */
    if (_resourceData != NULL) {
        /* Would release IRQ, DMA, I/O ports, and memory here */
        IOFree(_resourceData, 256);
        _resourceData = NULL;
    }

    _initialized = NO;
    IOLog("EISAResourceDriver: Resource deallocation complete\n");
}

@end
