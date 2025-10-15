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
 * Plug and Play Device Resource Management Implementation
 */

#import "PnPDeviceResources.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

/* PnP Resource Tags */
#define PNP_TAG_VERSION             0x01
#define PNP_TAG_LOGICAL_DEVICE      0x02
#define PNP_TAG_COMPATIBLE_DEVICE   0x03
#define PNP_TAG_IRQ_FORMAT          0x04
#define PNP_TAG_DMA_FORMAT          0x05
#define PNP_TAG_START_DEPEND        0x06
#define PNP_TAG_END_DEPEND          0x07
#define PNP_TAG_IO_PORT             0x08
#define PNP_TAG_FIXED_IO_PORT       0x09
#define PNP_TAG_VENDOR_DEFINED      0x0E
#define PNP_TAG_END                 0x0F
#define PNP_TAG_MEM_RANGE           0x81
#define PNP_TAG_ANSI_ID_STRING      0x82
#define PNP_TAG_UNICODE_ID_STRING   0x83
#define PNP_TAG_VENDOR_DEFINED_LARGE 0x84
#define PNP_TAG_32BIT_MEM_RANGE     0x85
#define PNP_TAG_32BIT_FIXED_MEM     0x86

@implementation PnPDeviceResources

- init
{
    [super init];

    _logicalDevice = 0;
    _compatibleDevice = 0;
    _deviceId = 0;
    _serialNumber = 0;
    _checksum = 0;

    _ioPorts = NULL;
    _ioPortCount = 0;
    _memRanges = NULL;
    _memRangeCount = 0;
    _irqs = NULL;
    _irqCount = 0;
    _dmas = NULL;
    _dmaCount = 0;

    _allocated = NO;
    _configurable = YES;

    return self;
}

- free
{
    if (_ioPorts != NULL) {
        free(_ioPorts);
        _ioPorts = NULL;
    }

    if (_memRanges != NULL) {
        free(_memRanges);
        _memRanges = NULL;
    }

    if (_irqs != NULL) {
        free(_irqs);
        _irqs = NULL;
    }

    if (_dmas != NULL) {
        free(_dmas);
        _dmas = NULL;
    }

    return [super free];
}

/*
 * Device identification
 */

- (void)setLogicalDevice:(unsigned int)devId
{
    _logicalDevice = devId;
}

- (unsigned int)getLogicalDevice
{
    return _logicalDevice;
}

- (void)setCompatibleDevice:(unsigned int)devId
{
    _compatibleDevice = devId;
}

- (unsigned int)getCompatibleDevice
{
    return _compatibleDevice;
}

- (void)setDeviceId:(unsigned int)devId
{
    _deviceId = devId;
}

- (unsigned int)getDeviceId
{
    return _deviceId;
}

- (void)setSerialNumber:(unsigned int)serial
{
    _serialNumber = serial;
}

- (unsigned int)getSerialNumber
{
    return _serialNumber;
}

/*
 * Resource management
 */

- (BOOL)allocate:(id)logicalDevice
{
    if (_allocated) {
        return NO;
    }

    if (!_configurable) {
        return NO;
    }

    _allocated = YES;
    return YES;
}

- (void)deallocate
{
    _allocated = NO;
}

- (BOOL)isAllocated
{
    return _allocated;
}

/*
 * I/O Port resources
 */

- (BOOL)addIOPort:(unsigned short)base length:(unsigned short)len decode:(unsigned char)decode
{
    PnPResourceData *newPorts;

    newPorts = (PnPResourceData *)malloc((_ioPortCount + 1) * sizeof(PnPResourceData));
    if (newPorts == NULL) {
        return NO;
    }

    if (_ioPorts != NULL) {
        memcpy(newPorts, _ioPorts, _ioPortCount * sizeof(PnPResourceData));
        free(_ioPorts);
    }

    newPorts[_ioPortCount].tag = PNP_TAG_IO_PORT;
    newPorts[_ioPortCount].ioBase = base;
    newPorts[_ioPortCount].ioLength = len;
    newPorts[_ioPortCount].decode = decode;

    _ioPorts = newPorts;
    _ioPortCount++;

    return YES;
}

- (int)getIOPortCount
{
    return _ioPortCount;
}

- (PnPResourceData *)getIOPort:(int)index
{
    if (index < 0 || index >= _ioPortCount) {
        return NULL;
    }
    return &_ioPorts[index];
}

/*
 * Memory resources
 */

- (BOOL)addMemoryRange:(unsigned int)base length:(unsigned int)len
{
    PnPResourceData *newRanges;

    newRanges = (PnPResourceData *)malloc((_memRangeCount + 1) * sizeof(PnPResourceData));
    if (newRanges == NULL) {
        return NO;
    }

    if (_memRanges != NULL) {
        memcpy(newRanges, _memRanges, _memRangeCount * sizeof(PnPResourceData));
        free(_memRanges);
    }

    newRanges[_memRangeCount].tag = PNP_TAG_32BIT_MEM_RANGE;
    newRanges[_memRangeCount].memBase = base;
    newRanges[_memRangeCount].memLength = len;

    _memRanges = newRanges;
    _memRangeCount++;

    return YES;
}

- (int)getMemoryRangeCount
{
    return _memRangeCount;
}

- (PnPResourceData *)getMemoryRange:(int)index
{
    if (index < 0 || index >= _memRangeCount) {
        return NULL;
    }
    return &_memRanges[index];
}

/*
 * IRQ resources
 */

- (BOOL)addIRQ:(unsigned char)irq level:(unsigned char)level edge:(BOOL)edge
{
    PnPResourceData *newIRQs;

    newIRQs = (PnPResourceData *)malloc((_irqCount + 1) * sizeof(PnPResourceData));
    if (newIRQs == NULL) {
        return NO;
    }

    if (_irqs != NULL) {
        memcpy(newIRQs, _irqs, _irqCount * sizeof(PnPResourceData));
        free(_irqs);
    }

    newIRQs[_irqCount].tag = PNP_TAG_IRQ_FORMAT;
    newIRQs[_irqCount].irqMask[0] = irq & 0xFF;
    newIRQs[_irqCount].irqMask[1] = (irq >> 8) & 0xFF;
    newIRQs[_irqCount].info = (level << 1) | (edge ? 1 : 0);

    _irqs = newIRQs;
    _irqCount++;

    return YES;
}

- (int)getIRQCount
{
    return _irqCount;
}

- (PnPResourceData *)getIRQ:(int)index
{
    if (index < 0 || index >= _irqCount) {
        return NULL;
    }
    return &_irqs[index];
}

/*
 * DMA resources
 */

- (BOOL)addDMA:(unsigned char)channel type:(unsigned char)type
{
    PnPResourceData *newDMAs;

    newDMAs = (PnPResourceData *)malloc((_dmaCount + 1) * sizeof(PnPResourceData));
    if (newDMAs == NULL) {
        return NO;
    }

    if (_dmas != NULL) {
        memcpy(newDMAs, _dmas, _dmaCount * sizeof(PnPResourceData));
        free(_dmas);
    }

    newDMAs[_dmaCount].tag = PNP_TAG_DMA_FORMAT;
    newDMAs[_dmaCount].dmaChannel = channel;
    newDMAs[_dmaCount].info = type;

    _dmas = newDMAs;
    _dmaCount++;

    return YES;
}

- (int)getDMACount
{
    return _dmaCount;
}

- (PnPResourceData *)getDMA:(int)index
{
    if (index < 0 || index >= _dmaCount) {
        return NULL;
    }
    return &_dmas[index];
}

/*
 * Configuration parsing
 */

- (BOOL)parseResourceData:(unsigned char *)data length:(int)length
{
    int offset = 0;
    unsigned char tag, len;

    while (offset < length) {
        tag = data[offset];

        /* Check if this is a large resource item */
        if (tag & 0x80) {
            /* Large item: tag | length_lo | length_hi | data... */
            if (offset + 3 > length) break;

            len = data[offset + 1] | (data[offset + 2] << 8);
            offset += 3;

            switch (tag) {
                case PNP_TAG_MEM_RANGE:
                case PNP_TAG_32BIT_MEM_RANGE:
                case PNP_TAG_32BIT_FIXED_MEM:
                    if (len >= 9) {
                        unsigned int base = data[offset + 4] | (data[offset + 5] << 8) |
                                          (data[offset + 6] << 16) | (data[offset + 7] << 24);
                        unsigned int size = data[offset + 8] | (data[offset + 9] << 8) |
                                          (data[offset + 10] << 16) | (data[offset + 11] << 24);
                        [self addMemoryRange:base length:size];
                    }
                    break;
            }

            offset += len;
        } else {
            /* Small item: tag+length | data... */
            len = tag & 0x07;
            tag = (tag >> 3) & 0x0F;
            offset++;

            switch (tag) {
                case PNP_TAG_IO_PORT:
                    if (len >= 7) {
                        unsigned short base = data[offset + 1] | (data[offset + 2] << 8);
                        unsigned short size = data[offset + 6];
                        [self addIOPort:base length:size decode:data[offset]];
                    }
                    break;

                case PNP_TAG_FIXED_IO_PORT:
                    if (len >= 3) {
                        unsigned short base = data[offset] | (data[offset + 1] << 8);
                        unsigned short size = data[offset + 2];
                        [self addIOPort:base length:size decode:0];
                    }
                    break;

                case PNP_TAG_IRQ_FORMAT:
                    if (len >= 2) {
                        unsigned char irq = data[offset] | (data[offset + 1] << 8);
                        unsigned char info = (len > 2) ? data[offset + 2] : 0;
                        [self addIRQ:irq level:(info >> 1) & 1 edge:info & 1];
                    }
                    break;

                case PNP_TAG_DMA_FORMAT:
                    if (len >= 1) {
                        [self addDMA:data[offset] type:(len > 1) ? data[offset + 1] : 0];
                    }
                    break;

                case PNP_TAG_LOGICAL_DEVICE:
                    if (len >= 4) {
                        _logicalDevice = data[offset] | (data[offset + 1] << 8) |
                                       (data[offset + 2] << 16) | (data[offset + 3] << 24);
                    }
                    break;

                case PNP_TAG_COMPATIBLE_DEVICE:
                    if (len >= 4) {
                        _compatibleDevice = data[offset] | (data[offset + 1] << 8) |
                                          (data[offset + 2] << 16) | (data[offset + 3] << 24);
                    }
                    break;

                case PNP_TAG_END:
                    return YES;
            }

            offset += len;
        }
    }

    return YES;
}

- (void)dumpConfiguration
{
    int i, j;
    PnPResourceData *res;

    printf("\n=== PnP Device Configuration ===\n");
    printf("Device ID: 0x%08X\n", _deviceId);
    printf("Serial Number: 0x%08X\n", _serialNumber);

    if (_logicalDevice != 0) {
        printf("Logical Device: 0x%08X\n", _logicalDevice);
    }

    if (_compatibleDevice != 0) {
        printf("Compatible Device: 0x%08X\n", _compatibleDevice);
    }

    printf("Status: %s, %s\n",
           _allocated ? "Allocated" : "Not Allocated",
           _configurable ? "Configurable" : "Not Configurable");

    /* Dump I/O ports */
    if (_ioPortCount > 0) {
        printf("\nI/O Ports (%d):\n", _ioPortCount);
        for (i = 0; i < _ioPortCount; i++) {
            res = &_ioPorts[i];
            printf("  Port %d: 0x%04X-0x%04X (length=%d, decode=%s)\n",
                   i, res->ioBase, res->ioBase + res->ioLength - 1,
                   res->ioLength,
                   res->decode ? "16-bit" : "10-bit");
        }
    }

    /* Dump memory ranges */
    if (_memRangeCount > 0) {
        printf("\nMemory Ranges (%d):\n", _memRangeCount);
        for (i = 0; i < _memRangeCount; i++) {
            res = &_memRanges[i];
            printf("  Memory %d: 0x%08X-0x%08X (length=0x%X)\n",
                   i, res->memBase, res->memBase + res->memLength - 1,
                   res->memLength);
        }
    }

    /* Dump IRQs */
    if (_irqCount > 0) {
        printf("\nIRQs (%d):\n", _irqCount);
        for (i = 0; i < _irqCount; i++) {
            res = &_irqs[i];
            unsigned int irqMask = res->irqMask[0] | (res->irqMask[1] << 8);

            printf("  IRQ Set %d: ", i);
            for (j = 0; j < 16; j++) {
                if (irqMask & (1 << j)) {
                    printf("%d ", j);
                }
            }
            printf("(%s, %s)\n",
                   (res->info & 0x02) ? "level-triggered" : "edge-triggered",
                   (res->info & 0x01) ? "active-high" : "active-low");
        }
    }

    /* Dump DMA channels */
    if (_dmaCount > 0) {
        printf("\nDMA Channels (%d):\n", _dmaCount);
        for (i = 0; i < _dmaCount; i++) {
            res = &_dmas[i];
            unsigned char dmaMask = res->dmaChannel;

            printf("  DMA Set %d: ", i);
            for (j = 0; j < 8; j++) {
                if (dmaMask & (1 << j)) {
                    printf("%d ", j);
                }
            }

            /* Decode DMA info flags */
            printf("(");
            if (res->info & 0x01) printf("8-bit ");
            if (res->info & 0x02) printf("16-bit ");
            if (res->info & 0x04) printf("bus-master ");
            if (res->info & 0x08) printf("byte-count ");
            if (res->info & 0x10) printf("word-count ");
            printf("type=0x%02X)\n", res->info);
        }
    }

    if (_ioPortCount == 0 && _memRangeCount == 0 && _irqCount == 0 && _dmaCount == 0) {
        printf("\nNo resources configured.\n");
    }

    printf("\n");
}

- (unsigned char)calculateChecksum
{
    unsigned char sum = 0;
    unsigned int val;

    val = _deviceId;
    sum += (val & 0xFF) + ((val >> 8) & 0xFF) + ((val >> 16) & 0xFF) + ((val >> 24) & 0xFF);

    val = _serialNumber;
    sum += (val & 0xFF) + ((val >> 8) & 0xFF) + ((val >> 16) & 0xFF) + ((val >> 24) & 0xFF);

    return (0x100 - sum) & 0xFF;
}

- (BOOL)verifyChecksum:(unsigned char)checksum
{
    return (checksum == [self calculateChecksum]);
}

@end
