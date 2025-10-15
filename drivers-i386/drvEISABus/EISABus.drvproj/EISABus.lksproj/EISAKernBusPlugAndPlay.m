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
 * EISAKernBusPlugAndPlay.m
 * EISA Plug and Play Support Implementation
 */

#import "EISAKernBusPlugAndPlay.h"
#import "PnPDeviceResources.h"
#import "PnPInterruptResource.h"
#import "PnPDMAResource.h"
#import "PnPIOPortResource.h"
#import "PnPMemoryResource.h"
#import <driverkit/generalFuncs.h>
#import <objc/List.h>

/* PnP I/O ports */
#define PNP_ADDRESS_PORT        0x279
#define PNP_WRITE_DATA_PORT     0xA79
#define PNP_READ_DATA_PORT      0x203
#define PNP_ISOLATION_PORT      0x279

/* PnP register offsets */
#define PNP_CONFIG_CONTROL      0x02
#define PNP_WAKE_CSN            0x03
#define PNP_RESOURCE_DATA       0x04
#define PNP_CARD_SELECT_NUMBER  0x06
#define PNP_LOGICAL_DEVICE      0x07
#define PNP_ACTIVATE            0x30

/* PnP commands */
#define PNP_CMD_RESET_CSN       0x04

@implementation EISAKernBusPlugAndPlay

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _pnpData = NULL;
    _initialized = NO;
    _isolationPort = PNP_ISOLATION_PORT;
    _addressPort = PNP_ADDRESS_PORT;
    _writeDataPort = PNP_WRITE_DATA_PORT;
    _readDataPort = PNP_READ_DATA_PORT;
    _csn = 0;

    [self setName:"EISAKernBusPlugAndPlay"];
    [self setDeviceKind:"EISAKernBusPlugAndPlay"];

    return self;
}

- free
{
    if (_pnpData != NULL) {
        IOFree(_pnpData, sizeof(void *));
        _pnpData = NULL;
    }

    return [super free];
}

- (BOOL)initiatePnP
{
    /* Send initiation key sequence */
    int i;
    unsigned char key[32];

    /* Generate initiation key */
    key[0] = 0x6A;
    for (i = 1; i < 32; i++) {
        key[i] = ((key[i-1] >> 1) | (key[i-1] << 7)) & 0xFF;
    }

    /* Send key sequence */
    for (i = 0; i < 32; i++) {
        outb(_addressPort, key[i]);
    }

    _initialized = YES;
    return YES;
}

- (BOOL)isolateCards
{
    /* Perform PnP isolation protocol to enumerate all PnP cards */
    int csn = 1;
    int cardsFound = 0;
    unsigned char serialID[9];
    int i;

    IOLog("EISAKernBusPlugAndPlay: Starting card isolation\n");

    /* Reset all cards */
    outb(_addressPort, PNP_CONFIG_CONTROL);
    outb(_writeDataPort, PNP_CMD_RESET_CSN);

    /* Wait for cards to reset */
    IODelay(2000); /* 2ms delay */

    /* Initiate isolation sequence */
    outb(_addressPort, 0x01); /* SERIAL_ISOLATION register */

    /* Read serial identifiers for each card */
    while (csn <= 255) {
        int bit, byte;
        BOOL cardPresent = NO;

        /* Clear serial ID buffer */
        bzero(serialID, 9);

        /* Read 72 bits (9 bytes) of serial identifier */
        for (byte = 0; byte < 9; byte++) {
            unsigned char byteVal = 0;
            for (bit = 0; bit < 8; bit++) {
                unsigned char val1 = inb(_readDataPort);
                unsigned char val2 = inb(_readDataPort);

                /* Check for valid isolation read */
                if (val1 == 0x55 && val2 == 0xAA) {
                    byteVal |= (1 << bit);
                    cardPresent = YES;
                }
            }
            serialID[byte] = byteVal;
        }

        /* If we found a card, assign it a CSN */
        if (cardPresent) {
            /* Assign CSN to this card */
            outb(_addressPort, PNP_CARD_SELECT_NUMBER);
            outb(_writeDataPort, csn);

            IOLog("  Found PnP card with serial: %02X%02X%02X%02X%02X%02X%02X%02X%02X (CSN=%d)\n",
                  serialID[0], serialID[1], serialID[2], serialID[3],
                  serialID[4], serialID[5], serialID[6], serialID[7],
                  serialID[8], csn);

            cardsFound++;
            csn++;
        } else {
            /* No more cards found */
            break;
        }

        /* Small delay between isolation attempts */
        IODelay(100);
    }

    IOLog("EISAKernBusPlugAndPlay: Found %d PnP card%s\n",
          cardsFound, (cardsFound == 1) ? "" : "s");

    return (cardsFound > 0) ? YES : NO;
}

- (int)assignCSN:(int)logicalDevice
{
    /* Assign Card Select Number */
    return ++_csn;
}

- (BOOL)configureDevice:(int)csn logical:(int)logical
{
    /* Configure PnP device with the specified CSN and logical device number */
    if (csn < 1 || csn > 255) {
        return NO;
    }

    IOLog("EISAKernBusPlugAndPlay: Configuring device CSN=%d, logical=%d\n",
          csn, logical);

    /* Wake the card */
    outb(_addressPort, PNP_WAKE_CSN);
    outb(_writeDataPort, csn);

    /* Select logical device */
    outb(_addressPort, PNP_LOGICAL_DEVICE);
    outb(_writeDataPort, logical);

    /* Activate the logical device */
    outb(_addressPort, PNP_ACTIVATE);
    outb(_writeDataPort, 0x01); /* Activate */

    IOLog("  Device CSN=%d logical=%d activated\n", csn, logical);

    return YES;
}

- (void *)readResourceData:(int)csn
{
    /* Read resource data from PnP device and parse into PnPDeviceResources object
     * This uses the PnP resource classes to eliminate code duplication
     */
    unsigned char *buffer;
    int maxLength = 4096; /* Maximum resource data length */
    int offset = 0;
    unsigned char tag;

    if (csn < 1 || csn > 255) {
        return NULL;
    }

    buffer = (unsigned char *)IOMalloc(maxLength);
    if (buffer == NULL) {
        return NULL;
    }

    /* Wake the card */
    outb(_addressPort, PNP_WAKE_CSN);
    outb(_writeDataPort, csn);

    /* Read resource data */
    outb(_addressPort, PNP_RESOURCE_DATA);

    /* Read until we hit END tag or buffer full */
    while (offset < maxLength) {
        tag = inb(_readDataPort);
        buffer[offset++] = tag;

        /* Check for END tag (small tag, type 0x0F) */
        if ((tag & 0x78) == 0x78) {
            /* END tag found */
            break;
        }

        /* Read tag data based on size */
        if (tag & 0x80) {
            /* Large tag - read length and data */
            if (offset + 2 < maxLength) {
                buffer[offset++] = inb(_readDataPort);
                buffer[offset++] = inb(_readDataPort);
                int len = buffer[offset-2] | (buffer[offset-1] << 8);

                /* Read tag data */
                int i;
                for (i = 0; i < len && offset < maxLength; i++) {
                    buffer[offset++] = inb(_readDataPort);
                }
            }
        } else {
            /* Small tag - read data */
            int len = tag & 0x07;
            int i;
            for (i = 0; i < len && offset < maxLength; i++) {
                buffer[offset++] = inb(_readDataPort);
            }
        }
    }

    IOLog("EISAKernBusPlugAndPlay: Read %d bytes of resource data from CSN=%d\n",
          offset, csn);

    /* Parse the raw resource data into a PnPDeviceResources object
     * This provides a structured representation instead of raw bytes
     */
    id deviceResources = [[PnPDeviceResources alloc] init];
    if (deviceResources != nil) {
        /* Use PnPDeviceResources to parse the buffer */
        [deviceResources initFromBuffer:buffer Length:offset CSN:csn];

        /* Free the raw buffer - we now have a structured object */
        IOFree(buffer, maxLength);

        /* Return the PnPDeviceResources object instead of raw buffer
         * Caller should free this with [object free] instead of IOFree
         */
        return (void *)deviceResources;
    }

    /* Fallback: if we couldn't create the resources object, return raw buffer */
    return (void *)buffer;
}

- (void)freeResourceData:(void *)resources
{
    if (resources != NULL) {
        /* Check if this is a PnPDeviceResources object or raw buffer
         * PnPDeviceResources objects should be freed with [free]
         * We'll assume it's a PnPDeviceResources object if we successfully created one
         */
        id resourceObj = (id)resources;

        /* Try to treat it as an object and free it
         * If it was actually created by readResourceData, it will be a PnPDeviceResources
         */
        if ([resourceObj respondsToSelector:@selector(free)]) {
            [resourceObj free];
        } else {
            /* Fallback: treat as raw buffer (shouldn't happen with new implementation) */
            IOFree(resources, 4096);
        }
    }
}

@end
