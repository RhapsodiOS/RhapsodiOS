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
 * PCMCIA Memory Window Implementation
 */

#import <driverkit/i386/PCMCIAWindow.h>
#import <driverkit/KernLock.h>
#import <kernserv/i386/spl.h>

@implementation PCMCIAWindow

- initWithSocket:socket
{
    [super init];

    _socket = socket;
    _enabled = NO;
    _memoryInterface = NO;
    _attributeMemory = NO;
    _size = 0;
    _systemAddress = 0;
    _cardAddress = 0;

    _lock = [[KernLock alloc] initWithLevel:IPLHIGH];

    return self;
}

- free
{
    if (_lock) {
        [_lock free];
        _lock = nil;
    }

    return [super free];
}

/* Window control */
- (void)setEnabled:(BOOL)enabled
{
    [_lock acquire];
    _enabled = enabled;
    [_lock release];
}

- (BOOL)enabled
{
    BOOL result;
    [_lock acquire];
    result = _enabled;
    [_lock release];
    return result;
}

- (void)setMemoryInterface:(BOOL)memInterface
{
    [_lock acquire];
    _memoryInterface = memInterface;
    [_lock release];
}

- (BOOL)memoryInterface
{
    BOOL result;
    [_lock acquire];
    result = _memoryInterface;
    [_lock release];
    return result;
}

- (void)setAttributeMemory:(BOOL)attrMem
{
    [_lock acquire];
    _attributeMemory = attrMem;
    [_lock release];
}

- (BOOL)attributeMemory
{
    BOOL result;
    [_lock acquire];
    result = _attributeMemory;
    [_lock release];
    return result;
}

/* Window mapping */
- (void)setMapWithSize:(vm_size_t)size
        systemAddress:(vm_offset_t)sysAddr
          cardAddress:(vm_offset_t)cardAddr
{
    [_lock acquire];
    _size = size;
    _systemAddress = sysAddr;
    _cardAddress = cardAddr;
    [_lock release];
}

- (vm_size_t)size
{
    vm_size_t result;
    [_lock acquire];
    result = _size;
    [_lock release];
    return result;
}

- (vm_offset_t)systemAddress
{
    vm_offset_t result;
    [_lock acquire];
    result = _systemAddress;
    [_lock release];
    return result;
}

- (vm_offset_t)cardAddress
{
    vm_offset_t result;
    [_lock acquire];
    result = _cardAddress;
    [_lock release];
    return result;
}

/* Socket access */
- socket
{
    return _socket;
}

/* Element interface */
- object
{
    return self;
}

@end
