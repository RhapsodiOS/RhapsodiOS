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
 * PnP Logical Device Representation
 */

#ifndef _PNPLOGICALDEVICE_H_
#define _PNPLOGICALDEVICE_H_

#import <objc/Object.h>

/* PnPLogicalDevice - Logical device representation */
@interface PnPLogicalDevice : Object
{
    @private
    int _deviceNumber;
    int _vendorID;
    char *_deviceName;
    id _resources;
}
- init;
- free;
- (void)findMatchingDependentFunction:(id)config;
- (void)addConfig:(id)config;
- (void)setID:(int)deviceID;
- (void)setLogicalDeviceNumber:(int)number;
- (int)ID;
- (void)setDeviceName:(const char *)name;
- (const char *)deviceName;
- (id)depResources;
- (id)resources;
@end

#endif /* _PNPLOGICALDEVICE_H_ */
