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
 * PnPLogicalDevice.m
 * PnP Logical Device Representation Implementation
 */

#import "PnPLogicalDevice.h"
#import <driverkit/generalFuncs.h>

/* Forward declaration - will be defined in separate file */
@class PnPResources;

@implementation PnPLogicalDevice

- init
{
    [super init];

    _deviceNumber = 0;
    _vendorID = 0;
    _deviceName = NULL;

    /* Import PnPResources class and allocate */
    Class resourceClass = objc_getClass("PnPResources");
    if (resourceClass != nil) {
        _resources = [[resourceClass alloc] init];
    } else {
        _resources = nil;
    }

    return self;
}

- free
{
    if (_deviceName != NULL) {
        IOFree(_deviceName, 256);
        _deviceName = NULL;
    }

    if (_resources != nil) {
        [_resources free];
        _resources = nil;
    }

    return [super free];
}

- (void)findMatchingDependentFunction:(id)config
{
    /* Find and select matching dependent function configuration */
    if (config == nil) {
        return;
    }

    IOLog("PnPLogicalDevice: Finding matching dependent function\n");
}

- (void)addConfig:(id)config
{
    /* Add configuration to this logical device */
    if (config == nil) {
        return;
    }

    IOLog("PnPLogicalDevice: Adding configuration\n");
}

- (void)setID:(int)deviceID
{
    _vendorID = deviceID;
}

- (void)setLogicalDeviceNumber:(int)number
{
    _deviceNumber = number;
}

- (int)ID
{
    return _vendorID;
}

- (void)setDeviceName:(const char *)name
{
    if (name == NULL) {
        return;
    }

    if (_deviceName != NULL) {
        IOFree(_deviceName, 256);
    }

    _deviceName = (char *)IOMalloc(256);
    if (_deviceName != NULL) {
        int i;
        for (i = 0; i < 255 && name[i] != '\0'; i++) {
            _deviceName[i] = name[i];
        }
        _deviceName[i] = '\0';
    }
}

- (const char *)deviceName
{
    return _deviceName;
}

- (id)depResources
{
    /* Return dependent resources */
    return _resources;
}

- (id)resources
{
    return _resources;
}

@end
