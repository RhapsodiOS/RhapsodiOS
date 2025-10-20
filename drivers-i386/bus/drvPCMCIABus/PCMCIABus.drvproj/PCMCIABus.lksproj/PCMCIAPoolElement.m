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
 * PCMCIA Pool Element Wrapper Implementation
 */

#import "PCMCIAPoolElement.h"
#import <libkern/libkern.h>

/* Internal structure containing pool and object pointers */
typedef struct {
    id pool;    /* Reference to the pool */
    id object;  /* The wrapped object */
} ElementData;

@implementation PCMCIAPoolElement

- initWithPCMCIAPool:pool object:object
{
    ElementData *elementData;

    [super init];

    /* Allocate 8 bytes for the two pointers */
    elementData = (ElementData *)IOMalloc(8);
    _elementData = elementData;

    /* Store pool and object */
    elementData->pool = pool;
    elementData->object = object;

    return self;
}

- free
{
    ElementData *elementData = (ElementData *)_elementData;

    /* Release the object back to the pool */
    [elementData->pool releaseObject:elementData->object];

    /* Free the element data structure (8 bytes) */
    IOFree(_elementData, 8);

    return [super free];
}

- object
{
    ElementData *elementData = (ElementData *)_elementData;

    return elementData->object;
}

@end
