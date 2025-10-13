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
 * PCMCIA Memory Pool Implementation
 */

#import <mach/mach_types.h>
#import <vm/vm_kern.h>
#import "PCMCIAPool.h"
#import "PCMCIASocket.h"
#import <driverkit/KernLock.h>
#import <kernserv/i386/spl.h>
#import <libkern/libkern.h>

@implementation PCMCIAPool

- initWithSocket:(unsigned int)socket
{
    [super init];

    _socket = socket;
    _state = PCMCIA_SOCKET_EMPTY;

    /* Initialize windows as unmapped */
    bzero(&_common_window, sizeof(pcmcia_mem_window_t));
    bzero(&_attr_window, sizeof(pcmcia_mem_window_t));
    bzero(&_io_window, sizeof(pcmcia_mem_window_t));

    _common_window.type = PCMCIA_MEM_COMMON;
    _attr_window.type = PCMCIA_MEM_ATTRIBUTE;
    _io_window.type = PCMCIA_MEM_IO;

    /* Initialize card information */
    _manufacturer_id = 0;
    _card_id = 0;
    _function_id = 0;

    /* Create lock for thread-safe access */
    _lock = [[KernLock alloc] initWithLevel:IPLHIGH];

    /* Create socket object for driverkit-3 compatibility */
    _socketObject = [[PCMCIASocket alloc] initWithSocketNumber:_socket pool:self];

    return self;
}

- free
{
    /* Unmap all windows */
    [self unmapWindow:PCMCIA_MEM_COMMON];
    [self unmapWindow:PCMCIA_MEM_ATTRIBUTE];
    [self unmapWindow:PCMCIA_MEM_IO];

    /* Free socket object */
    if (_socketObject) {
        [_socketObject free];
        _socketObject = nil;
    }

    if (_lock) {
        [_lock free];
        _lock = nil;
    }

    return [super free];
}

/* Socket management */
- (unsigned int)socket
{
    return _socket;
}

- (pcmcia_socket_state_t)state
{
    return _state;
}

- (BOOL)cardPresent
{
    return (_state == PCMCIA_SOCKET_OCCUPIED ||
            _state == PCMCIA_SOCKET_READY);
}

- (BOOL)cardReady
{
    return (_state == PCMCIA_SOCKET_READY);
}

/* Memory window management */
- (BOOL)mapWindow:(pcmcia_mem_type_t)type
         physAddr:(vm_offset_t)phys_addr
             size:(vm_size_t)size
            flags:(unsigned int)flags
{
    pcmcia_mem_window_t *window;
    vm_offset_t virt_addr;
    kern_return_t result;

    /* Select the appropriate window */
    switch (type) {
        case PCMCIA_MEM_COMMON:
            window = &_common_window;
            break;
        case PCMCIA_MEM_ATTRIBUTE:
            window = &_attr_window;
            break;
        case PCMCIA_MEM_IO:
            window = &_io_window;
            break;
        default:
            return NO;
    }

    [_lock acquire];

    /* Unmap existing window if necessary */
    if (window->flags & PCMCIA_WINDOW_MAPPED) {
        kmem_free(kernel_map, window->virt_addr, window->size);
        window->flags &= ~PCMCIA_WINDOW_MAPPED;
    }

    /* Map physical memory to virtual address space */
    result = kmem_alloc_pageable(kernel_map, &virt_addr, size);
    if (result != KERN_SUCCESS) {
        [_lock release];
        return NO;
    }

    /* Set up window structure */
    window->phys_addr = phys_addr;
    window->virt_addr = virt_addr;
    window->size = size;
    window->flags = flags | PCMCIA_WINDOW_MAPPED;

    [_lock release];
    return YES;
}

- (void)unmapWindow:(pcmcia_mem_type_t)type
{
    pcmcia_mem_window_t *window;

    /* Select the appropriate window */
    switch (type) {
        case PCMCIA_MEM_COMMON:
            window = &_common_window;
            break;
        case PCMCIA_MEM_ATTRIBUTE:
            window = &_attr_window;
            break;
        case PCMCIA_MEM_IO:
            window = &_io_window;
            break;
        default:
            return;
    }

    [_lock acquire];

    if (window->flags & PCMCIA_WINDOW_MAPPED) {
        kmem_free(kernel_map, window->virt_addr, window->size);
        bzero(window, sizeof(pcmcia_mem_window_t));
        window->type = type;
    }

    [_lock release];
}

- (vm_offset_t)windowAddress:(pcmcia_mem_type_t)type
{
    pcmcia_mem_window_t *window;
    vm_offset_t addr = 0;

    /* Select the appropriate window */
    switch (type) {
        case PCMCIA_MEM_COMMON:
            window = &_common_window;
            break;
        case PCMCIA_MEM_ATTRIBUTE:
            window = &_attr_window;
            break;
        case PCMCIA_MEM_IO:
            window = &_io_window;
            break;
        default:
            return 0;
    }

    [_lock acquire];

    if (window->flags & PCMCIA_WINDOW_MAPPED) {
        addr = window->virt_addr;
    }

    [_lock release];
    return addr;
}

/* Memory access functions */
- (unsigned char)readByte:(vm_offset_t)offset type:(pcmcia_mem_type_t)type
{
    pcmcia_mem_window_t *window;
    unsigned char value = 0xFF;

    /* Select the appropriate window */
    switch (type) {
        case PCMCIA_MEM_COMMON:
            window = &_common_window;
            break;
        case PCMCIA_MEM_ATTRIBUTE:
            window = &_attr_window;
            break;
        case PCMCIA_MEM_IO:
            window = &_io_window;
            break;
        default:
            return 0xFF;
    }

    [_lock acquire];

    if ((window->flags & PCMCIA_WINDOW_MAPPED) && offset < window->size) {
        value = *(volatile unsigned char *)(window->virt_addr + offset);
    }

    [_lock release];
    return value;
}

- (unsigned short)readWord:(vm_offset_t)offset type:(pcmcia_mem_type_t)type
{
    pcmcia_mem_window_t *window;
    unsigned short value = 0xFFFF;

    /* Select the appropriate window */
    switch (type) {
        case PCMCIA_MEM_COMMON:
            window = &_common_window;
            break;
        case PCMCIA_MEM_ATTRIBUTE:
            window = &_attr_window;
            break;
        case PCMCIA_MEM_IO:
            window = &_io_window;
            break;
        default:
            return 0xFFFF;
    }

    [_lock acquire];

    if ((window->flags & PCMCIA_WINDOW_MAPPED) &&
        (offset + 1) < window->size &&
        (window->flags & PCMCIA_WINDOW_16BIT)) {
        value = *(volatile unsigned short *)(window->virt_addr + offset);
    }

    [_lock release];
    return value;
}

- (void)writeByte:(unsigned char)value offset:(vm_offset_t)offset type:(pcmcia_mem_type_t)type
{
    pcmcia_mem_window_t *window;

    /* Select the appropriate window */
    switch (type) {
        case PCMCIA_MEM_COMMON:
            window = &_common_window;
            break;
        case PCMCIA_MEM_ATTRIBUTE:
            window = &_attr_window;
            break;
        case PCMCIA_MEM_IO:
            window = &_io_window;
            break;
        default:
            return;
    }

    [_lock acquire];

    if ((window->flags & PCMCIA_WINDOW_MAPPED) && offset < window->size) {
        *(volatile unsigned char *)(window->virt_addr + offset) = value;
    }

    [_lock release];
}

- (void)writeWord:(unsigned short)value offset:(vm_offset_t)offset type:(pcmcia_mem_type_t)type
{
    pcmcia_mem_window_t *window;

    /* Select the appropriate window */
    switch (type) {
        case PCMCIA_MEM_COMMON:
            window = &_common_window;
            break;
        case PCMCIA_MEM_ATTRIBUTE:
            window = &_attr_window;
            break;
        case PCMCIA_MEM_IO:
            window = &_io_window;
            break;
        default:
            return;
    }

    [_lock acquire];

    if ((window->flags & PCMCIA_WINDOW_MAPPED) &&
        (offset + 1) < window->size &&
        (window->flags & PCMCIA_WINDOW_16BIT)) {
        *(volatile unsigned short *)(window->virt_addr + offset) = value;
    }

    [_lock release];
}

/* Card information */
- (void)setManufacturerID:(unsigned short)manfid cardID:(unsigned short)cardid
{
    [_lock acquire];
    _manufacturer_id = manfid;
    _card_id = cardid;
    [_lock release];
}

- (void)setFunctionID:(unsigned char)funcid
{
    [_lock acquire];
    _function_id = funcid;
    [_lock release];
}

- (unsigned short)manufacturerID
{
    unsigned short manfid;
    [_lock acquire];
    manfid = _manufacturer_id;
    [_lock release];
    return manfid;
}

- (unsigned short)cardID
{
    unsigned short cardid;
    [_lock acquire];
    cardid = _card_id;
    [_lock release];
    return cardid;
}

- (unsigned char)functionID
{
    unsigned char funcid;
    [_lock acquire];
    funcid = _function_id;
    [_lock release];
    return funcid;
}

/* Socket state management */
- (void)setState:(pcmcia_socket_state_t)state
{
    [_lock acquire];
    _state = state;
    [_lock release];
}

/* Tuple list management */
- (void)setTupleList:tuples
{
    [_lock acquire];
    if (_tupleList) {
        [_tupleList free];
    }
    _tupleList = tuples;
    [_lock release];
}

- tupleList
{
    id list;
    [_lock acquire];
    list = _tupleList;
    [_lock release];
    return list;
}

/* Socket object access */
- socketObject
{
    id socket;
    [_lock acquire];
    socket = _socketObject;
    [_lock release];
    return socket;
}

@end
