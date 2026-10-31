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
 * PnPLogicalDevice.h
 * PnP Logical Device
 */

#ifndef _PNPLOGICALDEVICE_H_
#define _PNPLOGICALDEVICE_H_

#import <objc/Object.h>

/* PnPLogicalDevice - Represents a logical device within a PnP card */
@interface PnPLogicalDevice : Object
{
    @private
    char _deviceName[80];           /* Device name buffer at offset 0x04 */
    int _deviceNameLength;          /* Length of device name at offset 0x54 (84) */
    unsigned int _id;               /* Device ID at offset 0x58 (88) */
    id _compatIDs;                  /* Compatible IDs list at offset 0x5c (92) */
    id _resources;                  /* PnPResources object at offset 0x60 (96) */
    id _depResources;               /* Dependent resources list at offset 0x64 (100) */
    int _logicalDeviceNumber;       /* Logical device number at offset 0x68 (104) */
}

/*
 * Initialization
 */
- init;

/*
 * Device information
 */
- (unsigned int)ID;
- (char *)deviceName;
- (int)logicalDeviceNumber;
- (id)resources;
- (id)depResources;
- (id)compatIDs;

/*
 * Configuration
 */
- (void)setID:(unsigned int)deviceID;
- (BOOL)setDeviceName:(const char *)name Length:(int)length;
- (void)setLogicalDeviceNumber:(int)number;
- (void)addCompatID:(unsigned int)compatID;

/*
 * Matching
 */
- (BOOL)findMatchingDependentFunction:(id *)matchedFunction ForConfig:(id)config;

/*
 * Memory management
 */
- free;

@end

#endif /* _PNPLOGICALDEVICE_H_ */
