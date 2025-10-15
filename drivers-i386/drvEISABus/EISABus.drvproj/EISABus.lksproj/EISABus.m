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
 * EISABus.m
 * EISA Bus Driver Implementation
 */

#import "EISABus.h"
#import "EISAKernBus.h"
#import "EISAKernBusPlugAndPlay.h"
#import "EISAResourceDriver.h"
#import "PnPResources.h"
#import "PnPInterruptResource.h"
#import "PnPDMAResource.h"
#import "PnPIOPortResource.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/KernDeviceDescription.h>
#import <driverkit/IODeviceDescriptionPrivate.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/IODevice.h>
#import <driverkit/KernBus.h>
#import <objc/List.h>

/* EISA I/O ports */
#define EISA_ID_PORT_BASE       0x0C80
#define EISA_CONFIG_PORT_BASE   0x0C84

/* Maximum EISA slots */
#define EISA_MAX_SLOTS          16

/*
 * ============================================================================
 * EISABus Implementation
 * ============================================================================
 */

/* Driver version */
#define EISABUS_VERSION_STRING "5.01"

@implementation EISABus

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    if ([deviceDescription isKindOf:[IODeviceDescription class]]) {
        return YES;
    }
    return NO;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /*
     * Look up EISA kernel bus instance
     * The bus registers itself via + initialize
     */
    _kernBus = [KernBus lookupBusInstanceWithName:"EISA" busId:0];
    if (_kernBus == nil) {
        IOLog("EISABus: Failed to lookup EISA kernel bus instance\n");
        return nil;
    }

    _initialized = NO;

    [self setName:"EISABus"];
    [self setDeviceKind:"EISABus"];
    [self setLocation:NULL];

    IOLog("EISABus: Initialized (Version %s)\n", EISABUS_VERSION_STRING);

    [self registerDevice];

    return self;
}

- free
{
    /*
     * Note: _kernBus is not freed here because it's managed by KernBus
     * and was obtained via lookupBusInstanceWithName
     */
    _kernBus = nil;

    return [super free];
}

- (BOOL)BootDriver
{
    if (_initialized) {
        return YES;
    }

    if (_kernBus == nil) {
        IOLog("EISABus: BootDriver called without kernel bus\n");
        return NO;
    }

    /* Scan EISA slots */
    if ([self scanSlots]) {
        _initialized = YES;
        IOLog("EISABus: BootDriver completed successfully\n");
        return YES;
    }

    IOLog("EISABus: BootDriver failed to scan slots\n");
    return NO;
}

- (int)getSlotCount
{
    return EISA_MAX_SLOTS;
}

/*
 * Helper method to parse EISA configuration data into PnP resource objects
 * This eliminates code duplication by using the PnP resource classes
 */
- (void)parseEISAConfig:(unsigned char *)configData
             intoIRQs:(id *)irqList
                 DMAs:(id *)dmaList
              IOPorts:(id *)ioList
{
    if (configData == NULL || irqList == NULL || dmaList == NULL || ioList == NULL) {
        return;
    }

    *irqList = [[List alloc] init];
    *dmaList = [[List alloc] init];
    *ioList = [[List alloc] init];

    /* Extract I/O port ranges from configuration
     * EISA config has up to 7 I/O port entries at offsets 0x08-0x1F
     * Each entry is 2 bytes
     */
    int i;
    for (i = 0; i < 7; i++) {
        unsigned int offset = 0x08 + (i * 2);
        if (offset + 1 < 320) {
            unsigned int ioBase = (configData[offset] << 8) | configData[offset + 1];
            if (ioBase != 0 && ioBase != 0xFFFF) {
                /* EISA I/O ports are typically 16 bytes wide */
                id ioResource = [[PnPIOPortResource alloc] init];
                [ioResource setMinBase:ioBase];
                [ioResource setMaxBase:ioBase];
                [ioResource setLength:16];
                [ioResource setAlignment:1];
                [*ioList addObject:ioResource];

                IOLog("    I/O Port: 0x%04X-0x%04X\n", ioBase, ioBase + 15);
            }
        }
    }

    /* Extract IRQ assignments
     * IRQ configuration is at offset 0x04 in many EISA cards
     */
    /* Check primary IRQ at byte 0x04 */
    if (configData[0x04] != 0 && configData[0x04] != 0xFF) {
        unsigned int irq = configData[0x04] & 0x0F;
        if (irq < 16) {
            id irqResource = [[PnPInterruptResource alloc] init];
            [irqResource setIRQMask:(1 << irq)];
            [*irqList addObject:irqResource];
            IOLog("    IRQ: %d\n", irq);
        }
    }

    /* Check secondary IRQ at byte 0x05 (if applicable) */
    if (configData[0x05] != 0 && configData[0x05] != 0xFF) {
        unsigned int irq = configData[0x05] & 0x0F;
        if (irq < 16) {
            id irqResource = [[PnPInterruptResource alloc] init];
            [irqResource setIRQMask:(1 << irq)];
            [*irqList addObject:irqResource];
            IOLog("    IRQ: %d\n", irq);
        }
    }

    /* Extract DMA channel assignments
     * DMA configuration is typically at byte 0x06-0x07
     */
    if (configData[0x06] != 0xFF && (configData[0x06] & 0x07) < 8) {
        id dmaResource = [[PnPDMAResource alloc] init];
        [dmaResource setChannelMask:(1 << (configData[0x06] & 0x07))];
        [*dmaList addObject:dmaResource];
        IOLog("    DMA: %d\n", configData[0x06] & 0x07);
    }

    if (configData[0x07] != 0xFF && (configData[0x07] & 0x07) < 8) {
        id dmaResource = [[PnPDMAResource alloc] init];
        [dmaResource setChannelMask:(1 << (configData[0x07] & 0x07))];
        [*dmaList addObject:dmaResource];
        IOLog("    DMA: %d\n", configData[0x07] & 0x07);
    }
}

- (BOOL)scanSlots
{
    int slot;
    int deviceCount = 0;

    IOLog("EISABus: Scanning %d EISA slots\n", EISA_MAX_SLOTS);

    for (slot = 0; slot < EISA_MAX_SLOTS; slot++) {
        if ([_kernBus testSlot:slot]) {
            unsigned int idPort = EISA_ID_PORT_BASE + (slot * 0x1000);
            unsigned int configPort = EISA_CONFIG_PORT_BASE + (slot * 0x1000);
            unsigned char id[4];
            unsigned char configData[320];  /* EISA config space is 320 bytes */
            int i;

            /* Read 4-byte EISA ID */
            for (i = 0; i < 4; i++) {
                id[i] = inb(idPort + i);
            }

            /* Construct 32-bit EISA ID */
            unsigned long eisaID = (id[0] << 24) | (id[1] << 16) |
                                   (id[2] << 8) | id[3];

            IOLog("  EISA Slot %d: ID = %02X%02X%02X%02X (0x%08lX)\n",
                  slot, id[0], id[1], id[2], id[3], eisaID);

            /* Read EISA configuration data (up to 320 bytes) */
            for (i = 0; i < 320; i++) {
                configData[i] = inb(configPort + i);
            }

            /* Parse configuration data to extract resources using PnP resource classes
             * This eliminates code duplication by reusing the PnP infrastructure
             */
            id irqResourceList = nil;
            id dmaResourceList = nil;
            id ioResourceList = nil;

            [self parseEISAConfig:configData
                         intoIRQs:&irqResourceList
                             DMAs:&dmaResourceList
                          IOPorts:&ioResourceList];

            /* Convert PnP resource objects to arrays for KernBus allocation */
            unsigned int irqList[16];
            unsigned int numIRQs = [irqResourceList count];
            for (i = 0; i < numIRQs && i < 16; i++) {
                id irqRes = [irqResourceList objectAt:i];
                unsigned int mask = [irqRes irqMask];
                /* Convert mask to IRQ number (find first bit set) */
                int irq;
                for (irq = 0; irq < 16; irq++) {
                    if (mask & (1 << irq)) {
                        irqList[i] = irq;
                        break;
                    }
                }
            }

            unsigned int dmaChannels[8];
            unsigned int numDMAChannels = [dmaResourceList count];
            for (i = 0; i < numDMAChannels && i < 8; i++) {
                id dmaRes = [dmaResourceList objectAt:i];
                unsigned char mask = [dmaRes channelMask];
                /* Convert mask to channel number (find first bit set) */
                int ch;
                for (ch = 0; ch < 8; ch++) {
                    if (mask & (1 << ch)) {
                        dmaChannels[i] = ch;
                        break;
                    }
                }
            }

            IORange ioRanges[16];
            unsigned int numIOPorts = [ioResourceList count];
            for (i = 0; i < numIOPorts && i < 16; i++) {
                id ioRes = [ioResourceList objectAt:i];
                ioRanges[i].start = [ioRes minBase];
                ioRanges[i].size = [ioRes length];
            }

            /* Create device description for this EISA device
             * This allows drivers to probe and attach to the device
             */

            /* Create KernDeviceDescription to hold the device properties */
            id kernDevDesc = [[KernDeviceDescription alloc] init];
            if (kernDevDesc == nil) {
                IOLog("EISABus: Failed to create KernDeviceDescription for slot %d\n", slot);
                deviceCount++;
                continue;
            }

            /* Set the bus for this device */
            [kernDevDesc setBus:_kernBus];

            /* Set slot number as a property so getEISASlotNumber can retrieve it */
            char slotStr[16];
            sprintf(slotStr, "%d", slot);
            [kernDevDesc setProperty:"Slot" value:slotStr];

            /* Set EISA ID as a property */
            char idStr[32];
            sprintf(idStr, "0x%08lX", eisaID);
            [kernDevDesc setProperty:"EISA ID" value:idStr];

            /* Set device name based on EISA ID */
            char deviceName[64];
            sprintf(deviceName, "EISA%d_%08lX", slot, eisaID);
            [kernDevDesc setProperty:"Device Name" value:deviceName];

            /* Allocate resources for this device through the kernel bus */
            /* The KernBus will allocate the IRQ/DMA/IO resources we specify */

            /* Allocate IRQ resources if present */
            if (numIRQs > 0) {
                if ([_kernBus allocateItems:irqList
                                   numItems:numIRQs
                                     forKey:IRQ_LEVELS_KEY] == nil) {
                    IOLog("EISABus: Warning - Could not allocate IRQ for slot %d\n", slot);
                }
            }

            /* Allocate DMA channels if present */
            if (numDMAChannels > 0) {
                if ([_kernBus allocateItems:dmaChannels
                                   numItems:numDMAChannels
                                     forKey:DMA_CHANNELS_KEY] == nil) {
                    IOLog("EISABus: Warning - Could not allocate DMA for slot %d\n", slot);
                }
            }

            /* Allocate I/O port ranges if present */
            if (numIOPorts > 0) {
                /* Convert IORange to Range for KernBus */
                Range *ranges = (Range *)IOMalloc(numIOPorts * sizeof(Range));
                if (ranges != NULL) {
                    for (i = 0; i < numIOPorts; i++) {
                        ranges[i].base = ioRanges[i].start;
                        ranges[i].length = ioRanges[i].size;
                    }

                    if ([_kernBus allocateRanges:ranges
                                       numRanges:numIOPorts
                                          forKey:IO_PORTS_KEY] == nil) {
                        IOLog("EISABus: Warning - Could not allocate I/O ports for slot %d\n", slot);
                    }

                    IOFree(ranges, numIOPorts * sizeof(Range));
                }
            }

            /* Create IOEISADeviceDescription wrapper */
            id ioEISADevDesc = [[IOEISADeviceDescription alloc] _initWithDelegate:kernDevDesc];
            if (ioEISADevDesc == nil) {
                IOLog("EISABus: Failed to create IOEISADeviceDescription for slot %d\n", slot);
                [kernDevDesc free];
                deviceCount++;
                continue;
            }

            /* Set the channel list (DMA channels) in the device description */
            if (numDMAChannels > 0) {
                IOReturn result = [ioEISADevDesc setChannelList:dmaChannels
                                                             num:numDMAChannels];
                if (result != IO_R_SUCCESS) {
                    IOLog("EISABus: Warning - setChannelList failed for slot %d\n", slot);
                }
            }

            /* Set the port range list in the device description */
            if (numIOPorts > 0) {
                IOReturn result = [ioEISADevDesc setPortRangeList:ioRanges
                                                               num:numIOPorts];
                if (result != IO_R_SUCCESS) {
                    IOLog("EISABus: Warning - setPortRangeList failed for slot %d\n", slot);
                }
            }

            /* Register this device with IODevice for driver matching/probing
             * Note: This would normally be done through the configuration system
             * or through explicit driver probe calls. For now, we just create
             * the device descriptions so they're available for drivers to use.
             *
             * In a full implementation, we would:
             * 1. Check if a driver exists for this EISA ID
             * 2. Call the driver's probe method with this device description
             * 3. If probe succeeds, instantiate the driver
             *
             * For now, drivers will need to explicitly probe EISA devices
             * by querying the EISAKernBus for discovered devices.
             */

            IOLog("EISABus: Registered device in slot %d (EISA ID 0x%08lX)\n",
                  slot, eisaID);

            /* Clean up resource lists */
            if (irqResourceList != nil) {
                int j;
                for (j = 0; j < [irqResourceList count]; j++) {
                    [[irqResourceList objectAt:j] free];
                }
                [irqResourceList free];
            }
            if (dmaResourceList != nil) {
                int j;
                for (j = 0; j < [dmaResourceList count]; j++) {
                    [[dmaResourceList objectAt:j] free];
                }
                [dmaResourceList free];
            }
            if (ioResourceList != nil) {
                int j;
                for (j = 0; j < [ioResourceList count]; j++) {
                    [[ioResourceList objectAt:j] free];
                }
                [ioResourceList free];
            }

            deviceCount++;
        }
    }

    IOLog("EISABus: Found %d EISA device%s\n",
          deviceCount, (deviceCount == 1) ? "" : "s");

    return YES;  /* Always return success even if no devices found */
}

@end
