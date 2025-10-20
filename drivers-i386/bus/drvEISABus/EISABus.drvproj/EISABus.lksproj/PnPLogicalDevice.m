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
 * PnP Logical Device Implementation
 */

#import "PnPLogicalDevice.h"
#import "PnPResources.h"
#import <objc/List.h>
#import <string.h>

@implementation PnPLogicalDevice

/*
 * Initialize logical device
 * Creates empty resources and lists
 */
- init
{
    [super init];

    /* Allocate and initialize PnPResources object */
    _resources = [[PnPResources alloc] init];

    /* Allocate and initialize lists */
    _depResources = [[List alloc] init];
    _compatIDs = [[List alloc] init];

    return self;
}

/*
 * Free logical device
 * Frees all resources and lists
 */
- free
{
    /* Free resources */
    [_resources free];

    /* Free objects in dependent resources list, then free the list */
    [[_depResources freeObjects:@selector(free)] free];

    /* Free compatible IDs list */
    [_compatIDs free];

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
 * Get device name
 * Returns pointer to inline buffer
 */
- (char *)deviceName
{
    return _deviceName;
}

/*
 * Get logical device number
 */
- (int)logicalDeviceNumber
{
    return _logicalDeviceNumber;
}

/*
 * Get resources
 */
- (id)resources
{
    return _resources;
}

/*
 * Get dependent resources
 */
- (id)depResources
{
    return _depResources;
}

/*
 * Get compatible IDs list
 */
- (id)compatIDs
{
    return _compatIDs;
}

/*
 * Set device ID
 */
- (void)setID:(unsigned int)deviceID
{
    _id = deviceID;
}

/*
 * Set device name
 * Copies name to inline buffer (max 79 bytes + null terminator)
 * Returns YES if name was set (not already set), NO if already set
 */
- (BOOL)setDeviceName:(const char *)name Length:(int)length
{
    size_t copyLength;

    /* Check if already set */
    if (_deviceNameLength != 0) {
        return NO;
    }

    /* Limit length to 79 bytes (0x4f) */
    copyLength = (length < 0x4f) ? length : 0x4f;
    _deviceNameLength = copyLength;

    /* Copy name to buffer */
    strncpy(_deviceName, name, copyLength);

    /* Null-terminate */
    _deviceName[_deviceNameLength] = '\0';

    return YES;
}

/*
 * Set logical device number
 */
- (void)setLogicalDeviceNumber:(int)number
{
    _logicalDeviceNumber = number;
}

/*
 * Add compatible ID to list
 * Adds ID as an object to the compatible IDs list
 */
- (void)addCompatID:(unsigned int)compatID
{
    [_compatIDs addObject:(id)compatID];
}

/*
 * Find matching dependent function
 * Searches through dependent resources to find one that matches the config
 * For each dependent resource, checks if all resource types (IRQ, port, DMA, memory) match
 * Returns YES if found, NO otherwise
 * Sets matchedFunction to the matching dependent resource (or nil if not found)
 */
- (BOOL)findMatchingDependentFunction:(id *)matchedFunction ForConfig:(id)config
{
    int count;
    int i;
    id depResource;
    id depIRQ, configIRQ, resourceIRQ;
    id depPort, configPort, resourcePort;
    id depDMA, configDMA, resourceDMA;
    id depMemory, configMemory, resourceMemory;
    BOOL matches;

    /* Initialize output parameter */
    *matchedFunction = nil;

    /* Get count of dependent resources */
    count = [_depResources count];
    if (count == 0) {
        return YES;
    }

    /* Iterate through dependent resources */
    for (i = 0; i < count; i++) {
        depResource = [_depResources objectAt:i];
        if (depResource == nil) {
            break;
        }

        /* Check IRQ matching */
        depIRQ = [depResource irq];
        configIRQ = [config irq];
        resourceIRQ = [_resources irq];
        matches = [resourceIRQ matches:configIRQ Using:depIRQ];
        if (!matches) {
            continue;
        }

        /* Check port matching */
        depPort = [depResource port];
        configPort = [config port];
        resourcePort = [_resources port];
        matches = [resourcePort matches:configPort Using:depPort];
        if (!matches) {
            continue;
        }

        /* Check DMA matching */
        depDMA = [depResource dma];
        configDMA = [config dma];
        resourceDMA = [_resources dma];
        matches = [resourceDMA matches:configDMA Using:depDMA];
        if (!matches) {
            continue;
        }

        /* Check memory matching */
        depMemory = [depResource memory];
        configMemory = [config memory];
        resourceMemory = [_resources memory];
        matches = [resourceMemory matches:configMemory Using:depMemory];
        if (!matches) {
            continue;
        }

        /* All resources match - set output and break */
        if (*matchedFunction == nil) {
            *matchedFunction = depResource;
            break;
        }
    }

    /* Return YES if found a match */
    return (*matchedFunction != nil);
}

@end
