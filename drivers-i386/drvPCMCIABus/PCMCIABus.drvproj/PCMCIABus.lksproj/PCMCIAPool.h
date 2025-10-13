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
 * PCMCIA Memory Pool Management
 */

#ifndef _DRIVERKIT_I386_PCMCIAPOOL_H_
#define _DRIVERKIT_I386_PCMCIAPOOL_H_

#import <objc/Object.h>
#import <mach/mach_types.h>

/* PCMCIA Memory Types */
typedef enum {
    PCMCIA_MEM_COMMON = 0,      /* Common memory */
    PCMCIA_MEM_ATTRIBUTE = 1,   /* Attribute memory (CIS) */
    PCMCIA_MEM_IO = 2           /* I/O space */
} pcmcia_mem_type_t;

/* PCMCIA Socket States */
typedef enum {
    PCMCIA_SOCKET_EMPTY = 0,    /* No card present */
    PCMCIA_SOCKET_OCCUPIED = 1, /* Card present */
    PCMCIA_SOCKET_READY = 2,    /* Card ready */
    PCMCIA_SOCKET_SUSPENDED = 3 /* Card suspended */
} pcmcia_socket_state_t;

/* PCMCIA Memory Window */
typedef struct pcmcia_mem_window {
    pcmcia_mem_type_t   type;           /* Memory type */
    vm_offset_t         phys_addr;      /* Physical address */
    vm_offset_t         virt_addr;      /* Virtual address */
    vm_size_t           size;           /* Window size */
    unsigned int        flags;          /* Window flags */
} pcmcia_mem_window_t;

/* Window flags */
#define PCMCIA_WINDOW_MAPPED    0x01    /* Window is mapped */
#define PCMCIA_WINDOW_ACTIVE    0x02    /* Window is active */
#define PCMCIA_WINDOW_16BIT     0x04    /* 16-bit access */
#define PCMCIA_WINDOW_8BIT      0x08    /* 8-bit access */

#ifdef DRIVER_PRIVATE

@interface PCMCIAPool : Object
{
@private
    unsigned int        _socket;        /* Socket number */
    pcmcia_socket_state_t _state;       /* Socket state */

    /* Memory windows */
    pcmcia_mem_window_t _common_window; /* Common memory window */
    pcmcia_mem_window_t _attr_window;   /* Attribute memory window */
    pcmcia_mem_window_t _io_window;     /* I/O window */

    /* Card information */
    unsigned short      _manufacturer_id;
    unsigned short      _card_id;
    unsigned char       _function_id;

    /* Tuple list */
    id                  _tupleList;     /* Array/list of tuples */

    /* Socket object for driverkit-3 compatibility */
    id                  _socketObject;  /* PCMCIASocket instance */

    id                  _lock;          /* Access lock */
}

- initWithSocket:(unsigned int)socket;

/* Socket management */
- (unsigned int)socket;
- (pcmcia_socket_state_t)state;
- (BOOL)cardPresent;
- (BOOL)cardReady;

/* Memory window management */
- (BOOL)mapWindow:(pcmcia_mem_type_t)type
         physAddr:(vm_offset_t)phys_addr
             size:(vm_size_t)size
            flags:(unsigned int)flags;
- (void)unmapWindow:(pcmcia_mem_type_t)type;
- (vm_offset_t)windowAddress:(pcmcia_mem_type_t)type;

/* Memory access functions */
- (unsigned char)readByte:(vm_offset_t)offset type:(pcmcia_mem_type_t)type;
- (unsigned short)readWord:(vm_offset_t)offset type:(pcmcia_mem_type_t)type;
- (void)writeByte:(unsigned char)value offset:(vm_offset_t)offset type:(pcmcia_mem_type_t)type;
- (void)writeWord:(unsigned short)value offset:(vm_offset_t)offset type:(pcmcia_mem_type_t)type;

/* Card information */
- (void)setManufacturerID:(unsigned short)manfid cardID:(unsigned short)cardid;
- (void)setFunctionID:(unsigned char)funcid;
- (unsigned short)manufacturerID;
- (unsigned short)cardID;
- (unsigned char)functionID;

/* Socket state management */
- (void)setState:(pcmcia_socket_state_t)state;

/* Tuple list management */
- (void)setTupleList:tuples;
- tupleList;

/* Socket object access */
- socketObject;

@end

#endif /* DRIVER_PRIVATE */

#endif /* _DRIVERKIT_I386_PCMCIAPOOL_H_ */
