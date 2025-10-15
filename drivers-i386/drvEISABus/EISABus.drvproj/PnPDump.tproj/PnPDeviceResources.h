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
 * PnPDeviceResources.h
 * Plug and Play Device Resource Management
 */

#ifndef _PNPDEVICERESOURCES_H_
#define _PNPDEVICERESOURCES_H_

#import <objc/Object.h>

/* Resource Types */
typedef enum {
    PNP_RESOURCE_IOPORT = 1,
    PNP_RESOURCE_MEMORY,
    PNP_RESOURCE_IRQ,
    PNP_RESOURCE_DMA,
    PNP_RESOURCE_CONFIG
} PnPResourceType;

/* Device Resource Structure */
typedef struct {
    unsigned char tag;
    unsigned short ioBase;
    unsigned short ioLength;
    unsigned char irqMask[2];
    unsigned char dmaChannel;
    unsigned int memBase;
    unsigned int memLength;
    unsigned char decode;
    unsigned char info;
} PnPResourceData;

@interface PnPDeviceResources : Object
{
    @private
    unsigned int _logicalDevice;
    unsigned int _compatibleDevice;
    unsigned int _deviceId;
    unsigned int _serialNumber;
    unsigned char _checksum;

    /* Resource arrays */
    PnPResourceData *_ioPorts;
    unsigned int _ioPortCount;
    PnPResourceData *_memRanges;
    unsigned int _memRangeCount;
    PnPResourceData *_irqs;
    unsigned int _irqCount;
    PnPResourceData *_dmas;
    unsigned int _dmaCount;

    BOOL _allocated;
    BOOL _configurable;
}

/*
 * Initialization
 */
- init;
- free;

/*
 * Device identification
 */
- (void)setLogicalDevice:(unsigned int)devId;
- (unsigned int)getLogicalDevice;
- (void)setCompatibleDevice:(unsigned int)devId;
- (unsigned int)getCompatibleDevice;
- (void)setDeviceId:(unsigned int)devId;
- (unsigned int)getDeviceId;
- (void)setSerialNumber:(unsigned int)serial;
- (unsigned int)getSerialNumber;

/*
 * Resource management
 */
- (BOOL)allocate:(id)logicalDevice;
- (void)deallocate;
- (BOOL)isAllocated;

/*
 * I/O Port resources
 */
- (BOOL)addIOPort:(unsigned short)base length:(unsigned short)len decode:(unsigned char)decode;
- (int)getIOPortCount;
- (PnPResourceData *)getIOPort:(int)index;

/*
 * Memory resources
 */
- (BOOL)addMemoryRange:(unsigned int)base length:(unsigned int)len;
- (int)getMemoryRangeCount;
- (PnPResourceData *)getMemoryRange:(int)index;

/*
 * IRQ resources
 */
- (BOOL)addIRQ:(unsigned char)irq level:(unsigned char)level edge:(BOOL)edge;
- (int)getIRQCount;
- (PnPResourceData *)getIRQ:(int)index;

/*
 * DMA resources
 */
- (BOOL)addDMA:(unsigned char)channel type:(unsigned char)type;
- (int)getDMACount;
- (PnPResourceData *)getDMA:(int)index;

/*
 * Configuration
 */
- (BOOL)parseResourceData:(unsigned char *)data length:(int)length;
- (void)dumpConfiguration;

/*
 * Utility methods
 */
- (unsigned char)calculateChecksum;
- (BOOL)verifyChecksum:(unsigned char)checksum;

@end

#endif /* _PNPDEVICERESOURCES_H_ */
