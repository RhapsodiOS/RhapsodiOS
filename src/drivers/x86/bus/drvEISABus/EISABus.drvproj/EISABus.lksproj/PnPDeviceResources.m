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
#import "PnPLogicalDevice.h"
#import "PnPResource.h"
#import "PnPDependentResources.h"
#import "pnpMemory.h"
#import "pnpIRQ.h"
#import "pnpDMA.h"
#import "pnpIOPort.h"
#import <driverkit/generalFuncs.h>
#import <libkern/libkern.h>
#import <objc/List.h>
#import <stdio.h>
#import <string.h>

/* List category for freeObjects: method */
@interface List (FreeObjects)
- freeObjects:(SEL)aSelector;
@end

/* External verbose flag */
extern char verbose;

/* Global PnP read port - set by setReadPort: class method */
static unsigned short readPort = 0;

/* Offset where resource data starts (after 9-byte header) */
#define START_OFFSET 9

@implementation PnPDeviceResources

/*
 * Set the PnP read port
 * Class method to configure the I/O port used for reading PnP data
 */
+ (void)setReadPort:(unsigned short)port
{
    readPort = port;
}

/*
 * Set verbose logging mode
 * Enables or disables verbose logging for PnP device resource operations
 */
+ (void)setVerbose:(char)verboseFlag
{
    verbose = verboseFlag;
}

/*
 * Initialize from buffer with header
 * Buffer format:
 *   +0: Device ID (4 bytes, little-endian)
 *   +4: Serial number (4 bytes)
 *   +8: Checksum (1 byte)
 *   +9: Resource data...
 */
- initForBuf:(void *)buffer Length:(int)length CSN:(int)csn
{
    unsigned char *data = (unsigned char *)buffer;
    unsigned int deviceID;
    unsigned int serialNum;
    char vendorID[9];
    unsigned int idValue;

    /* Call superclass init */
    [super init];

    /* Check minimum length */
    if (length < START_OFFSET) {
        IOLog("PnPDeviceResources: len %d is < START_OFFSET %d\n", length, START_OFFSET);
        return nil;
    }

    /* Extract device ID (4 bytes, little-endian, reverse byte order) */
    deviceID = (data[3] << 24) | (data[2] << 16) | (data[1] << 8) | data[0];

    /* Set CSN */
    _csn = csn;

    /* Set device ID */
    [self setID:deviceID];

    /* Set serial number from offset +4 */
    serialNum = *(unsigned int *)(data + 4);
    [self setSerialNumber:serialNum];

    /* Log device information if verbose */
    if (verbose) {
        unsigned char checksum = data[8];
        idValue = [self ID];

        /* Convert device ID to vendor string (3 letters) */
        vendorID[0] = ((idValue >> 26) & 0x1F) + 0x40;  /* Bits 26-30 */
        vendorID[1] = ((idValue >> 21) & 0x1F) + 0x40;  /* Bits 21-25 */
        vendorID[2] = ((idValue >> 16) & 0x1F) + 0x40;  /* Bits 16-20 */
        sprintf(vendorID + 3, "%04x", idValue & 0xFFFF); /* Lower 16 bits as hex */
        vendorID[7] = '\0';

        IOLog("Vendor Id %s (0x%lx) Serial Number 0x%lx CheckSum 0x%x\n",
              vendorID, (unsigned long)idValue, (unsigned long)serialNum, checksum);
    }

    /* Allocate device list */
    _deviceList = [[List alloc] init];
    if (_deviceList == nil) {
        IOLog("PnPDeviceResources: failed to allocate device_list\n");
        return [self free];
    }

    /* Parse configuration data starting at offset 9 */
    if (![self parseConfig:(data + START_OFFSET) Length:length]) {
        return [self free];
    }

    return self;
}

/*
 * Initialize from buffer without header
 * Parses resource data directly without reading device ID/serial number
 */
- initForBufNoHeader:(void *)buffer Length:(int)length CSN:(int)csn
{
    /* Call superclass init */
    [super init];

    /* Set CSN */
    _csn = csn;

    /* Allocate device list */
    _deviceList = [[List alloc] init];
    if (_deviceList == nil) {
        IOLog("PnPDeviceResources: failed to allocate device_list\n");
        return [self free];
    }

    /* Parse configuration data directly from buffer (no header offset) */
    if (![self parseConfig:buffer Length:length]) {
        return [self free];
    }

    return self;
}

/*
 * Free device resources
 * Frees all logical devices in the list, then the list itself
 */
- free
{
    /* Free all devices in the list, then free the list */
    if (_deviceList != nil) {
        /* Free each device object in the list */
        [[_deviceList freeObjects:@selector(free)] free];
    }

    /* Call superclass free */
    return [super free];
}

/*
 * Get device ID
 */
- (unsigned int)ID
{
    return _id;
}

/*
 * Set device ID
 */
- setID:(unsigned int)deviceID
{
    _id = deviceID;
    return self;
}

/*
 * Get serial number
 */
- (unsigned int)serialNumber
{
    return _serialNumber;
}

/*
 * Set serial number
 */
- setSerialNumber:(unsigned int)serial
{
    _serialNumber = serial;
    return self;
}

/*
 * Get Card Select Number
 * Returns CSN at offset 100 (0x64)
 */
- (int)csn
{
    return _csn;
}

/*
 * Get device count
 * Returns count of devices in the device list
 */
- (int)deviceCount
{
    return [_deviceList count];
}

/*
 * Get device list
 * Returns the List object at offset 4
 */
- deviceList
{
    return _deviceList;
}

/*
 * Get device with specific logical device ID
 * Searches through device list for matching ID
 */
- deviceWithID:(int)logicalDeviceID
{
    int index = 0;
    id device;

    /* Iterate through device list */
    while (1) {
        /* Get device at current index */
        device = [_deviceList objectAt:index];

        /* If no device found at this index, search failed */
        if (device == nil) {
            return nil;
        }

        /* Check if this device's ID matches */
        if ([device ID] == logicalDeviceID) {
            break;
        }

        /* Try next index */
        index++;
    }

    return device;
}

/*
 * Get device name
 * Returns pointer to inline buffer at offset 8
 */
- (const char *)deviceName
{
    /* Device name is stored inline starting at offset 8 */
    return (const char *)((unsigned char *)self + 8);
}

/*
 * Set device name
 * Copies name to inline buffer at offset 8 (max 79 chars + null)
 * Returns YES if set successfully, NO if already set
 */
- setDeviceName:(const char *)name Length:(int)length
{
    char *nameBuffer = (char *)((unsigned char *)self + 8);
    int *nameLengthPtr = (int *)((unsigned char *)self + 0x58);
    int copyLength;

    /* Check if name is already set */
    if (*nameLengthPtr != 0) {
        return nil;
    }

    /* Limit length to 79 bytes (0x4F) to leave room for null terminator */
    copyLength = (length < 0x4F) ? length : 0x4F;

    /* Store length */
    *nameLengthPtr = copyLength;

    /* Copy name to inline buffer */
    strncpy(nameBuffer, name, copyLength);

    /* Null terminate */
    nameBuffer[copyLength] = '\0';

    return self;
}

/*
 * Parse configuration data
 * Parses PnP resource descriptors (both small and large items)
 * Returns YES on success, NO on error
 */
- parseConfig:(void *)buffer Length:(int)length
{
    unsigned char *data = (unsigned char *)buffer;
    unsigned int bytesLeft = length;
    unsigned char tag;
    unsigned char itemType;
    unsigned int itemLength;
    unsigned short largeLength;
    PnPLogicalDevice *logicalDevice = nil;
    int depthCounter = 0;
    PnPDependentResources *depResources = nil;
    char vendorID[9];
    unsigned int deviceID;
    int i;

    /* Parse resource data stream */
    while (bytesLeft > 0) {
        /* Read tag byte */
        tag = *data;
        data++;
        bytesLeft--;

        /* Check if this is a large item (bit 7 set) */
        if (tag & 0x80) {
            /* Large item format: [tag] [len_lo] [len_hi] [data...] */
            if (bytesLeft < 2) {
                IOLog("PnPDeviceResources: bytes left is < 2\n");
                return nil;
            }

            /* Read 16-bit length */
            largeLength = *(unsigned short *)data;
            data += 2;
            bytesLeft -= 2;
            itemLength = largeLength;

            /* Check if we have enough data */
            if (bytesLeft < itemLength) {
                IOLog("PnPDeviceResources: LIN ilen %d > bytes left %d\n", itemLength, bytesLeft);
                return nil;
            }

            /* Parse large item by type (bits 0-6) */
            switch (tag & 0x7F) {
            case 1:  /* Memory Range Descriptor (24-bit) */
            case 5:  /* 32-bit Memory Range Descriptor */
            case 6:  /* 32-bit Fixed Memory Range Descriptor */
            {
                pnpMemory *memory = [[[objc_getClass("pnpMemory") alloc]
                                     initFrom:data Length:largeLength Type:(tag & 0x7F)] init];
                if (memory == nil) {
                    IOLog("failed to init memory\n");
                    return nil;
                }
                if (depthCounter == 0) {
                    [[logicalDevice resources] addMemory:memory];
                } else {
                    [depResources addMemory:memory];
                }
                break;
            }
            case 2:  /* ANSI Identifier String */
            {
                /* Set device name */
                if (![self setDeviceName:(const char *)data Length:largeLength]) {
                    [logicalDevice setDeviceName:(const char *)data Length:largeLength];
                }
                if (verbose) {
                    IOLog("id string(%d) '", largeLength);
                    for (i = 0; i < largeLength; i++) {
                        IOLog("%c", data[i]);
                    }
                    IOLog("'\n");
                }
                break;
            }
            case 3:  /* Unicode Identifier String */
            {
                /* Skip 2-byte language ID, set device name */
                if (![self setDeviceName:(const char *)(data + 2) Length:(largeLength - 2)]) {
                    [logicalDevice setDeviceName:(const char *)(data + 2) Length:(largeLength - 2)];
                }
                if (verbose) {
                    IOLog("UNICODE id string(%d) '", largeLength);
                    for (i = 0; i < (largeLength - 2); i++) {
                        IOLog("%c", data[i + 2]);
                    }
                    IOLog("'\n");
                }
                break;
            }
            case 4:  /* Vendor Defined */
            {
                if (verbose) {
                    IOLog("vendor defined(%d bytes)", largeLength);
                    for (i = 0; i < largeLength; i++) {
                        unsigned char ch = data[i];
                        unsigned char printable = (ch >= 0x20 && ch < 0x80) ? ch : '.';
                        IOLog(" '%c'[%xh]", printable, ch);
                    }
                    IOLog(" ]\n");
                }
                break;
            }
            }

            /* Advance past item data */
            data += itemLength;
            bytesLeft -= itemLength;
        }
        else {
            /* Small item format: [tag+len] [data...] */
            /* Length is in bits 0-2, type is in bits 3-6 */
            itemLength = tag & 0x7;
            itemType = (tag >> 3) & 0xF;

            /* Check for end tag */
            if ((tag & 0x78) == 0x78) {  /* End tag (type 0xF) */
                return self;
            }

            /* Check if we have enough data */
            if (bytesLeft < itemLength) {
                IOLog("PnPDeviceResources: bytes left %d, needed %d\n", bytesLeft, itemLength);
                return nil;
            }

            /* Parse small item by type */
            switch (itemType) {
            case 1:  /* PnP Version Number */
            {
                if (verbose) {
                    IOLog("Plug and Play Version %d.%d (Vendor %d.%d)\n",
                          data[0] >> 4, data[0] & 0xF,
                          data[1] >> 4, data[1] & 0xF);
                }
                break;
            }
            case 2:  /* Logical Device ID */
            {
                /* Allocate new logical device */
                logicalDevice = (PnPLogicalDevice *)[[[objc_getClass("PnPLogicalDevice") alloc] init] init];
                if (logicalDevice == nil) {
                    IOLog("PnPDeviceResources: allocate PnPLogicalDevice failed\n");
                    return nil;
                }

                /* Set logical device number (count of devices so far) */
                [logicalDevice setLogicalDeviceNumber:[_deviceList count]];

                /* Add to device list */
                [_deviceList addObject:logicalDevice];

                /* Extract and set device ID (4 bytes, reversed) */
                deviceID = (data[3] << 24) | (data[2] << 16) | (data[1] << 8) | data[0];
                [logicalDevice setID:deviceID];

                if (verbose) {
                    /* Convert to vendor ID string */
                    vendorID[0] = ((deviceID >> 26) & 0x1F) + 0x40;
                    vendorID[1] = ((deviceID >> 21) & 0x1F) + 0x40;
                    vendorID[2] = ((deviceID >> 16) & 0x1F) + 0x40;
                    sprintf(vendorID + 3, "%04x", deviceID & 0xFFFF);
                    vendorID[7] = '\0';
                    IOLog("\nLogical Device %d: Id %s (0x%lx)\n",
                          [logicalDevice logicalDeviceNumber], vendorID, (unsigned long)deviceID);
                }

                /* Check flags byte at offset 4 (if length >= 5) */
                if (itemLength >= 5) {
                    unsigned char flags = data[4];
                    if ((flags & 1) && verbose) {
                        IOLog("boot process participation capable\n");
                    }
                    if (flags & 0xFE) {
                        if (verbose) IOLog("register support:");
                        for (i = 1; i < 8; i++) {
                            if ((flags >> i) & 1) {
                                if (verbose) IOLog(" 0x%x", 0x30 + i);
                            }
                        }
                        if (verbose) IOLog("\n");
                    }
                }

                /* Check extended flags at offset 5 (if length > 5) */
                if (itemLength > 5) {
                    unsigned char flags2 = data[5];
                    if (flags2 != 0) {
                        if (verbose) IOLog("register support:");
                        for (i = 0; i < 8; i++) {
                            if ((flags2 >> i) & 1) {
                                if (verbose) IOLog(" 0x%x", 0x38 + i);
                            }
                        }
                        if (verbose) IOLog("\n");
                    }
                }
                break;
            }
            case 3:  /* Compatible Device ID */
            {
                /* Extract compatible ID (4 bytes, reversed) */
                deviceID = (data[3] << 24) | (data[2] << 16) | (data[1] << 8) | data[0];

                if (verbose) {
                    vendorID[0] = ((deviceID >> 26) & 0x1F) + 0x40;
                    vendorID[1] = ((deviceID >> 21) & 0x1F) + 0x40;
                    vendorID[2] = ((deviceID >> 16) & 0x1F) + 0x40;
                    sprintf(vendorID + 3, "%04x", deviceID & 0xFFFF);
                    vendorID[7] = '\0';
                    IOLog("Compatible Device Id: %s (0x%lx)\n", vendorID, (unsigned long)deviceID);
                }

                [logicalDevice addCompatID:deviceID];
                break;
            }
            case 4:  /* IRQ Format */
            {
                pnpIRQ *irq = [[[objc_getClass("pnpIRQ") alloc] initFrom:data Length:itemLength] init];
                if (irq == nil) {
                    IOLog("PnPDeviceResources: failed to parse IRQ\n");
                    return nil;
                }
                if (depthCounter == 0) {
                    [[logicalDevice resources] addIRQ:irq];
                } else {
                    [depResources addIRQ:irq];
                }
                break;
            }
            case 5:  /* DMA Format */
            {
                pnpDMA *dma = [[[objc_getClass("pnpDMA") alloc] initFrom:data Length:itemLength] init];
                if (dma == nil) {
                    IOLog("PnPDeviceResources: failed to parse DMA\n");
                    return nil;
                }
                if (depthCounter == 0) {
                    [[logicalDevice resources] addDMA:dma];
                } else {
                    [depResources addDMA:dma];
                }
                break;
            }
            case 6:  /* Start Dependent Functions */
            {
                if (verbose) {
                    IOLog("Start dependent function %d ", depthCounter);
                }
                depthCounter++;

                /* Allocate dependent resources object */
                depResources = (PnPDependentResources *)[[[objc_getClass("PnPDependentResources") alloc] init] init];
                if (depResources == nil) {
                    IOLog("PnPDeviceResources: failed to alloc depResources\n");
                    return nil;
                }

                /* Mark start of dependent resources */
                [[logicalDevice resources] markStartDependentResources];

                /* Add to logical device's dependent resources list */
                [[logicalDevice depResources] addObject:depResources];

                /* Set good config flag (default: good) */
                [depResources setGoodConfig:1];

                /* Check priority byte if present */
                if (itemLength > 0) {
                    unsigned char priority = data[0];
                    if (priority == 0) {
                        if (verbose) IOLog("[good configuration]");
                    } else if (priority == 1) {
                        if (verbose) IOLog("[acceptable configuration]");
                    } else if (priority == 2) {
                        [depResources setGoodConfig:0];
                        if (verbose) IOLog("[suboptimal configuration]");
                    }
                }
                if (verbose) IOLog("\n");
                break;
            }
            case 7:  /* End Dependent Functions */
            {
                if (verbose) {
                    IOLog("End of dependent functions\n");
                }
                depthCounter = 0;
                depResources = nil;
                break;
            }
            case 8:  /* I/O Port Descriptor */
            case 9:  /* Fixed I/O Port Descriptor */
            {
                pnpIOPort *ioPort = [[[objc_getClass("pnpIOPort") alloc]
                                     initFrom:data Length:itemLength Type:itemType] init];
                if (ioPort == nil) {
                    IOLog("PnPDeviceResources: failed to parse ioPort\n");
                    return nil;
                }
                if (depthCounter == 0) {
                    [[logicalDevice resources] addIOPort:ioPort];
                } else {
                    [depResources addIOPort:ioPort];
                }
                break;
            }
            case 0xE:  /* Vendor Defined */
            {
                if (verbose) {
                    IOLog("vendor defined(%d bytes)[", itemLength);
                    for (i = 0; i < itemLength; i++) {
                        unsigned char ch = data[i];
                        unsigned char printable = (ch >= 0x20 && ch < 0x80) ? ch : '.';
                        IOLog(" '%c'[%xh]", printable, ch);
                    }
                    IOLog(" ]\n");
                }
                break;
            }
            }

            /* Advance past item data */
            data += itemLength;
            bytesLeft -= itemLength;
        }
    }

    return self;
}

@end
