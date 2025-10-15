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
 * PCIResourceDriver.m
 * PCI Resource Driver Implementation
 */

#import "PCIResourceDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/*
 * ============================================================================
 * PCIResourceDriver Implementation
 * ============================================================================
 */

@implementation PCIResourceDriver

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _resourceData = NULL;
    _initialized = NO;
    _charValues = NULL;
    _charValuesCount = 0;

    [self setName:"PCIResourceDriver"];
    [self setDeviceKind:"PCIResourceDriver"];

    return self;
}

- free
{
    if (_resourceData != NULL) {
        IOFree(_resourceData, sizeof(void *));
        _resourceData = NULL;
    }

    if (_charValues != NULL) {
        IOFree(_charValues, _charValuesCount);
        _charValues = NULL;
        _charValuesCount = 0;
    }

    return [super free];
}

- (BOOL)allocateResources
{
    /* Allocate resources for PCI device */
    _initialized = YES;
    return YES;
}

- (void)deallocateResources
{
    if (_resourceData != NULL) {
        IOFree(_resourceData, sizeof(void *));
        _resourceData = NULL;
    }
    _initialized = NO;
}

- (BOOL)configureDevice
{
    return YES;
}

- (void *)getResourceDescription
{
    return _resourceData;
}

/*
 * Character value methods
 */

- (void)getCharValues:(unsigned char *)values forParameter:(unsigned int)count
{
    unsigned int i;
    unsigned int copyCount;

    if (values == NULL || count == 0) {
        return;
    }

    /* If we have no stored values, return zeros */
    if (_charValues == NULL || _charValuesCount == 0) {
        for (i = 0; i < count; i++) {
            values[i] = 0;
        }
        return;
    }

    /* Copy stored values up to the requested count */
    copyCount = (count < _charValuesCount) ? count : _charValuesCount;

    for (i = 0; i < copyCount; i++) {
        values[i] = _charValues[i];
    }

    /* If requested count is larger than stored count, fill remainder with zeros */
    for (i = copyCount; i < count; i++) {
        values[i] = 0;
    }
}

- (void)setCharValues:(unsigned char *)values forParameter:(unsigned int)count
{
    unsigned int i;
    unsigned char *newValues;

    if (values == NULL || count == 0) {
        return;
    }

    /* If count is different from current allocation, reallocate */
    if (_charValues == NULL || count != _charValuesCount) {
        /* Free old values if they exist */
        if (_charValues != NULL) {
            IOFree(_charValues, _charValuesCount);
            _charValues = NULL;
            _charValuesCount = 0;
        }

        /* Allocate new storage */
        newValues = (unsigned char *)IOMalloc(count);
        if (newValues == NULL) {
            IOLog("PCIResourceDriver: Failed to allocate %d bytes for char values\n", count);
            return;
        }

        _charValues = newValues;
        _charValuesCount = count;
    }

    /* Copy the values */
    for (i = 0; i < count; i++) {
        _charValues[i] = values[i];
    }
}

@end
