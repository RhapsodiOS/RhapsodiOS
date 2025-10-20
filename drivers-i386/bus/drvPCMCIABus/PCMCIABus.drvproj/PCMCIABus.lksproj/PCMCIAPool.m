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
 * PCMCIA Object Pool Implementation
 */

#import "PCMCIAPool.h"
#import "PCMCIAPoolElement.h"
#import <objc/List.h>
#import <libkern/libkern.h>

/* Internal structure containing the two lists */
typedef struct {
    id elementList;  /* List for available elements/objects (used by addList/addObject) */
    id objectList;   /* List for allocated objects */
} PoolData;

@implementation PCMCIAPool

- init
{
    PoolData *poolData;

    [super init];

    /* Allocate 8 bytes for the two list pointers */
    poolData = (PoolData *)IOMalloc(sizeof(PoolData));
    _poolData = poolData;

    /* Create and initialize the element list */
    poolData->elementList = [[List alloc] init];

    /* Create and initialize the object list */
    poolData->objectList = [[List alloc] init];

    return self;
}

- free
{
    PoolData *poolData = (PoolData *)_poolData;

    /* Free the element list */
    [poolData->elementList free];

    /* Free the object list */
    [poolData->objectList free];

    /* Free the pool data structure (8 bytes) */
    IOFree(_poolData, 8);

    return [super free];
}

- addList:list
{
    PoolData *poolData = (PoolData *)_poolData;

    if (poolData != NULL && list != nil) {
        /* Append entire list to element list */
        [poolData->elementList appendList:list];
    }

    return list;
}

- addObject:object
{
    PoolData *poolData = (PoolData *)_poolData;

    if (poolData != NULL && object != nil) {
        /* Add object to element list */
        [poolData->elementList addObject:object];
    }

    return object;
}

- allocElement
{
    id object;
    id element = nil;

    /* Allocate an object from the pool */
    object = [self allocObject];

    if (object != nil) {
        /* Wrap it in a PCMCIAPoolElement */
        element = [[PCMCIAPoolElement alloc] initWithPCMCIAPool:self object:object];
    }

    return element;
}

- allocElementByMethod:(SEL)method
{
    PoolData *poolData = (PoolData *)_poolData;
    unsigned int index = 0;
    unsigned int count;
    id object;
    int result;
    id element;

    if (poolData == NULL || method == NULL) {
        return nil;
    }

    /* Search through elementList for first object where method returns non-zero */
    while (1) {
        count = [poolData->elementList count];
        if (count <= index) {
            /* No object found that matches */
            return nil;
        }

        object = [poolData->elementList objectAt:index];
        result = (int)[object perform:method];

        if (result != 0) {
            /* Found a matching object */
            break;
        }

        index++;
    }

    /* Remove from element list */
    [poolData->elementList removeObjectAt:index];

    /* Add to object list (tracking) */
    [poolData->objectList addObject:object];

    /* Wrap in PCMCIAPoolElement */
    element = [[PCMCIAPoolElement alloc] initWithPCMCIAPool:self object:object];

    return element;
}

- allocObject
{
    PoolData *poolData = (PoolData *)_poolData;
    id object;

    if (poolData == NULL) {
        return nil;
    }

    /* Get and remove first object from element list (available pool) */
    object = [poolData->elementList objectAt:0];
    if (object != nil) {
        [poolData->elementList removeObjectAt:0];

        /* Track it in the allocated object list */
        [poolData->objectList addObject:object];
    }

    return object;
}

- allocObjectByMethod:(SEL)method
{
    PoolData *poolData = (PoolData *)_poolData;
    unsigned int index = 0;
    unsigned int count;
    id object;
    int result;

    if (poolData == NULL || method == NULL) {
        return nil;
    }

    /* Search through elementList for first object where method returns non-zero */
    while (1) {
        count = [poolData->elementList count];
        if (count <= index) {
            /* No object found that matches */
            return nil;
        }

        object = [poolData->elementList objectAt:index];
        result = (int)[object perform:method];

        if (result != 0) {
            /* Found a matching object */
            break;
        }

        index++;
    }

    /* Remove from element list */
    [poolData->elementList removeObjectAt:index];

    /* Add to object list (tracking) */
    [poolData->objectList addObject:object];

    return object;
}

- releaseObject:object
{
    PoolData *poolData = (PoolData *)_poolData;
    id result;

    /* Remove from allocated (object) list */
    result = [poolData->objectList removeObject:object];

    if (result == nil) {
        /* Object wasn't in the allocated list, return nil */
        return nil;
    }

    /* Successfully removed, return object to the element list (back to available pool) */
    [poolData->elementList addObject:object];

    return object;
}

- removeObject:object
{
    PoolData *poolData = (PoolData *)_poolData;
    id result;

    /* Remove from element list */
    result = [poolData->elementList removeObject:object];

    return result;
}

@end
