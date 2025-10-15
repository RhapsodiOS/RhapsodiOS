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
 * PnPDeviceResources.m
 * PnP Device Resource Collection Implementation
 */

#import "PnPDeviceResources.h"
#import "PnPInterruptResource.h"
#import "PnPDMAResource.h"
#import "PnPIOPortResource.h"
#import "PnPMemoryResource.h"
#import <driverkit/generalFuncs.h>
#import <objc/List.h>

@implementation PnPDeviceResources

- init
{
    [super init];

    _irqList = [[List alloc] init];
    _dmaList = [[List alloc] init];
    _ioPortList = [[List alloc] init];
    _memoryList = [[List alloc] init];

    return self;
}

- free
{
    if (_irqList != nil) {
        int i;
        int count = [_irqList count];
        for (i = 0; i < count; i++) {
            id obj = [_irqList objectAt:i];
            if (obj != nil) {
                [obj free];
            }
        }
        [_irqList free];
        _irqList = nil;
    }

    if (_dmaList != nil) {
        int i;
        int count = [_dmaList count];
        for (i = 0; i < count; i++) {
            id obj = [_dmaList objectAt:i];
            if (obj != nil) {
                [obj free];
            }
        }
        [_dmaList free];
        _dmaList = nil;
    }

    if (_ioPortList != nil) {
        int i;
        int count = [_ioPortList count];
        for (i = 0; i < count; i++) {
            id obj = [_ioPortList objectAt:i];
            if (obj != nil) {
                [obj free];
            }
        }
        [_ioPortList free];
        _ioPortList = nil;
    }

    if (_memoryList != nil) {
        int i;
        int count = [_memoryList count];
        for (i = 0; i < count; i++) {
            id obj = [_memoryList objectAt:i];
            if (obj != nil) {
                [obj free];
            }
        }
        [_memoryList free];
        _memoryList = nil;
    }

    return [super free];
}

- (void)setDeviceName:(const char *)name
{
    /* Set device name (for debugging) */
    if (name != NULL) {
        IOLog("PnPDeviceResources: Device name = %s\n", name);
    }
}

- (const char *)ID
{
    /* Return device ID string */
    return "PnPDevice";
}

- (void)setGoodConfig:(id)config
{
    /* Set good configuration priority */
    if (config != nil) {
        IOLog("PnPDeviceResources: Setting good configuration\n");
    }
}

- (void)setReadPort:(int)port
{
    /* Set PnP read data port */
    IOLog("PnPDeviceResources: Read port = 0x%04X\n", port);
}

- (void)setCSN:(int)csn
{
    /* Set Card Select Number */
    IOLog("PnPDeviceResources: CSN = %d\n", csn);
}

- (void)initFromBuffer:(void *)buffer Length:(int)length CSN:(int)csn
{
    /* Initialize resources from PnP resource data buffer */
    if (buffer == NULL || length <= 0) {
        IOLog("PnPDeviceResources: Invalid buffer\n");
        return;
    }

    IOLog("PnPDeviceResources: Parsing %d bytes of resource data for CSN %d\n", length, csn);

    unsigned char *data = (unsigned char *)buffer;
    int offset = 0;

    /* Parse PnP resource data stream
     * Resource data format consists of tagged items:
     * - Small resource items: tag byte + data
     * - Large resource items: tag byte + 2-byte length + data
     */

    while (offset < length) {
        unsigned char tag = data[offset];

        /* Check if this is a large or small resource item */
        if (tag & 0x80) {
            /* Large resource item */
            if (offset + 2 >= length) {
                break;
            }

            unsigned int itemLen = data[offset + 1] | (data[offset + 2] << 8);
            unsigned char itemType = tag & 0x7F;

            IOLog("  Large resource: type=0x%02X, length=%d\n", itemType, itemLen);

            /* Parse based on type */
            switch (itemType) {
                case 0x01: /* Memory range descriptor */
                    if (itemLen >= 9 && offset + 3 + itemLen <= length) {
                        id memResource = [[PnPMemoryResource alloc] init];
                        unsigned int minBase = (data[offset + 4] | (data[offset + 5] << 8)) << 8;
                        unsigned int maxBase = (data[offset + 6] | (data[offset + 7] << 8)) << 8;
                        unsigned int memLength = (data[offset + 10] | (data[offset + 11] << 8)) << 8;

                        [memResource setMinBase:minBase];
                        [memResource setMaxBase:maxBase];
                        [memResource setLength:memLength];
                        [_memoryList addObject:memResource];

                        IOLog("    Memory: 0x%08X-0x%08X (length=%d)\n", minBase, maxBase, memLength);
                    }
                    break;
            }

            offset += 3 + itemLen;
        } else {
            /* Small resource item */
            unsigned char itemLen = tag & 0x07;
            unsigned char itemType = (tag >> 3) & 0x0F;

            IOLog("  Small resource: type=0x%02X, length=%d\n", itemType, itemLen);

            /* Parse based on type */
            switch (itemType) {
                case 0x04: /* IRQ descriptor */
                    if (itemLen >= 2 && offset + 1 + itemLen <= length) {
                        unsigned int irqMask = data[offset + 1] | (data[offset + 2] << 8);
                        id irqResource = [[PnPInterruptResource alloc] init];
                        [irqResource setIRQMask:irqMask];
                        [_irqList addObject:irqResource];

                        IOLog("    IRQ mask: 0x%04X\n", irqMask);
                    }
                    break;

                case 0x05: /* DMA descriptor */
                    if (itemLen >= 1 && offset + 1 + itemLen <= length) {
                        unsigned char dmaMask = data[offset + 1];
                        id dmaResource = [[PnPDMAResource alloc] init];
                        [dmaResource setChannelMask:dmaMask];
                        [_dmaList addObject:dmaResource];

                        IOLog("    DMA mask: 0x%02X\n", dmaMask);
                    }
                    break;

                case 0x08: /* I/O port descriptor */
                    if (itemLen >= 7 && offset + 1 + itemLen <= length) {
                        unsigned int minBase = data[offset + 2] | (data[offset + 3] << 8);
                        unsigned int maxBase = data[offset + 4] | (data[offset + 5] << 8);
                        unsigned char alignment = data[offset + 6];
                        unsigned char portLen = data[offset + 7];

                        id ioResource = [[PnPIOPortResource alloc] init];
                        [ioResource setMinBase:minBase];
                        [ioResource setMaxBase:maxBase];
                        [ioResource setAlignment:alignment];
                        [ioResource setLength:portLen];
                        [_ioPortList addObject:ioResource];

                        IOLog("    I/O: 0x%04X-0x%04X align=%d length=%d\n",
                              minBase, maxBase, alignment, portLen);
                    }
                    break;

                case 0x0F: /* End tag */
                    IOLog("  End of resource data\n");
                    return;
            }

            offset += 1 + itemLen;
        }
    }

    IOLog("PnPDeviceResources: Parsed %d IRQs, %d DMAs, %d I/O ports, %d memory ranges\n",
          [_irqList count], [_dmaList count], [_ioPortList count], [_memoryList count]);
}

@end
