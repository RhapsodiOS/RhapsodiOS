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
 * PnPDependentResources.m
 * PnP Dependent Resource Configurations Implementation
 */

#import "PnPDependentResources.h"
#import <driverkit/generalFuncs.h>

#define MAX_DEPENDENT_RESOURCES 16

typedef struct {
    void *resources[MAX_DEPENDENT_RESOURCES];
    int count;
} DependentResourceData;

@implementation PnPDependentResources

- init
{
    [super init];

    _resources = IOMalloc(sizeof(DependentResourceData));
    if (_resources != NULL) {
        DependentResourceData *data = (DependentResourceData *)_resources;
        data->count = 0;
        _count = 0;
    }

    return self;
}

- free
{
    if (_resources != NULL) {
        IOFree(_resources, sizeof(DependentResourceData));
        _resources = NULL;
    }
    return [super free];
}

- (BOOL)addResource:(void *)resource
{
    if (_resources == NULL || resource == NULL) {
        return NO;
    }

    DependentResourceData *data = (DependentResourceData *)_resources;

    if (data->count >= MAX_DEPENDENT_RESOURCES) {
        IOLog("PnPDependentResources: Maximum resources reached\n");
        return NO;
    }

    data->resources[data->count] = resource;
    data->count++;
    _count = data->count;

    return YES;
}

- (void *)getResource:(int)index
{
    if (_resources == NULL || index < 0) {
        return NULL;
    }

    DependentResourceData *data = (DependentResourceData *)_resources;

    if (index >= data->count) {
        return NULL;
    }

    return data->resources[index];
}

- (int)count
{
    return _count;
}

@end
