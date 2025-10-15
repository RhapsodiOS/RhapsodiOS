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
 * PnPResources.h
 * EISA Plug and Play Resource Management
 * Main header that includes all PnP resource classes
 */

#ifndef _PNPRESOURCES_H_
#define _PNPRESOURCES_H_

/* Include all individual PnP resource class headers */
#import "PnPArgStack.h"
#import "PnPBios.h"
#import "PnPDependentResources.h"
#import "PnPInterruptResource.h"
#import "PnPIOPortResource.h"
#import "PnPMemoryResource.h"
#import "PnPDMAResource.h"
#import "PnPLogicalDevice.h"
#import "PnPDeviceResources.h"

#import <objc/Object.h>

/* PnPResources - Main PnP resources container */
@interface PnPResources : Object
{
    @private
    void *_resourceList;
    int _resourceCount;
    BOOL _inDependentSection;
    id _dependentResources;
    id _goodConfig;
    id _currentConfig;
}
- init;
- free;
- (BOOL)initFromDeviceDescription:(id)description;
- (void)setDependentFunctionDescription:(id)description;
- objectAt:(int)index Using:(id)object;
- (void)print;
- (void)setGoodConfig:(id)config;
- (void)addDMA:(id)dma;
- (void)addIOPort:(id)ioport;
- (void)addMemory:(id)memory;
- (void)addIRQ:(id)irq;
- (void)configure:(id)config Using:(id)object;
- (void)markStartDependentResources;
- (void)setoodConfig:(id)config;
@end

#endif /* _PNPRESOURCES_H_ */
