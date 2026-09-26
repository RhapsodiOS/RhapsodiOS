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
 * PnPResource.h
 * PnP Resource Container
 */

#ifndef _PNPRESOURCE_H_
#define _PNPRESOURCE_H_

#import <objc/Object.h>

/* PnPResource - Container for a single type of PnP resource */
@interface PnPResource : Object
{
    @private
    id _list;           /* Resource list at offset 0x04 */
    int _depStart;      /* Dependent start index at offset 0x08 */
}

/*
 * Initialization
 */
- init;

/*
 * Resource list access
 */
- (id)list;
- (void)setDepStart:(int)startIndex;

/*
 * Resource access with dependent fallback
 */
- (id)objectAt:(int)index Using:(id)otherResource;

/*
 * Resource matching
 */
- (BOOL)matches:(id)configResource Using:(id)depResource;

/*
 * Memory management
 */
- free;

@end

#endif /* _PNPRESOURCE_H_ */
