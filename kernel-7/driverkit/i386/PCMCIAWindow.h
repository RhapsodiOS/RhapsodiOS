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
 * PCMCIA Memory Window Object
 *
 * Represents a memory window that can be mapped to card memory
 */

#ifndef _DRIVERKIT_I386_PCMCIAWINDOW_H_
#define _DRIVERKIT_I386_PCMCIAWINDOW_H_

#import <objc/Object.h>
#import <mach/mach_types.h>

#ifdef DRIVER_PRIVATE

@interface PCMCIAWindow : Object
{
@private
    id              _socket;            /* Parent socket */
    BOOL            _enabled;           /* Window enabled */
    BOOL            _memoryInterface;   /* Memory interface mode */
    BOOL            _attributeMemory;   /* Attribute memory vs common */
    vm_size_t       _size;              /* Window size */
    vm_offset_t     _systemAddress;     /* System (physical) address */
    vm_offset_t     _cardAddress;       /* Card address offset */
    id              _lock;              /* Access lock */
}

- initWithSocket:socket;

/* Window control */
- (void)setEnabled:(BOOL)enabled;
- (BOOL)enabled;

- (void)setMemoryInterface:(BOOL)memInterface;
- (BOOL)memoryInterface;

- (void)setAttributeMemory:(BOOL)attrMem;
- (BOOL)attributeMemory;

/* Window mapping */
- (void)setMapWithSize:(vm_size_t)size
        systemAddress:(vm_offset_t)sysAddr
          cardAddress:(vm_offset_t)cardAddr;

- (vm_size_t)size;
- (vm_offset_t)systemAddress;
- (vm_offset_t)cardAddress;

/* Socket access */
- socket;

/* Element interface */
- object;

@end

#endif /* DRIVER_PRIVATE */

#endif /* _DRIVERKIT_I386_PCMCIAWINDOW_H_ */
