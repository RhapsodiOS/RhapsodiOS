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
 * PnPResource.m
 * PnP Resource Container Implementation
 */

#import "PnPResource.h"
#import "pnpIRQ.h"
#import "pnpIOPort.h"
#import "pnpDMA.h"
#import "pnpMemory.h"
#import <objc/List.h>

@implementation PnPResource

/*
 * Initialize resource container
 * Allocates empty list for resources
 */
- init
{
    [super init];

    /* Allocate list */
    _list = [[List alloc] init];

    /* Initialize dependent start index */
    _depStart = 0;

    /* If list allocation failed, free and return nil */
    if (_list == nil) {
        return [self free];
    }

    return self;
}

/*
 * Free resource container
 * Frees all objects in list, then frees the list
 */
- free
{
    /* Free all objects in list, then free the list itself */
    [[_list freeObjects:@selector(free)] free];

    return [super free];
}

/*
 * Get resource list
 */
- (id)list
{
    return _list;
}

/*
 * Set dependent start index
 * This index determines where dependent resources are inserted in the virtual list
 */
- (void)setDepStart:(int)startIndex
{
    _depStart = startIndex;
}

/*
 * Get object at index, using another resource for dependent resources
 * Creates a virtual combined list:
 *   - Indices 0 to (_depStart-1): from our list
 *   - Indices _depStart to (_depStart+usingCount-1): from "using" resource
 *   - Indices (_depStart+usingCount) onwards: from our list (offset)
 */
- (id)objectAt:(int)index Using:(id)otherResource
{
    int usingCount;
    id usingList;

    /* Get count from the "using" resource */
    usingList = [otherResource list];
    usingCount = [usingList count];

    /* If index is in dependent range */
    if (index >= _depStart) {
        /* If index falls within the dependent resource range */
        if (index < (usingCount + _depStart)) {
            /* Return object from "using" resource at adjusted index */
            return [usingList objectAt:(index - _depStart)];
        }

        /* Index is past dependent resources - adjust for the inserted dependent items */
        return [_list objectAt:(usingCount + _depStart + index)];
    }

    /* Index is before dependent start - return from our list */
    return [_list objectAt:index];
}

/*
 * Check if resources match
 * Compares resources from configResource against our resources
 * Uses depResource for dependent resource fallback via objectAt:Using:
 * Returns YES if all resources match, NO otherwise
 */
- (BOOL)matches:(id)configResource Using:(id)depResource
{
    int count;
    int i;
    id ourObject;
    id configObject;
    id configList;
    BOOL match;

    /* Get count from config resource */
    configList = [configResource list];
    count = [configList count];

    /* If no resources to match, return YES */
    if (count == 0) {
        return YES;
    }

    /* Check each resource */
    for (i = 0; ; i++) {
        /* Get our resource (using dependent fallback) */
        ourObject = [self objectAt:i Using:depResource];
        if (ourObject == nil) {
            break;
        }

        /* Get config resource to match against */
        configObject = [configList objectAt:i];

        /* Check if they match */
        match = [ourObject matches:configObject];
        if (!match) {
            return NO;
        }
    }

    /* Return YES if we processed at least one item */
    return (i > 0);
}

@end
