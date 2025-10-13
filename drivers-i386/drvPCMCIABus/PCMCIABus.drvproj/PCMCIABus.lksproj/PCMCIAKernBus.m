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
 * Copyright (c) 1995 NeXT Computer, Inc.
 *
 * Kernel PCMCIA Bus Resource Object(s).
 */

#import <mach/mach_types.h>

#import <driverkit/KernLock.h>
#import "PCMCIAKernBus.h"
#import "PCMCIAKernBusPrivate.h"
#import "PCMCIAPool.h"
#import "PCMCIATuple.h"
#import "PCMCIATupleList.h"
#import "PCMCIAWindow.h"
#import "PCMCIASocket.h"
#import <driverkit/KernDevice.h>
#import <driverkit/KernDeviceDescription.h>
#import <kernserv/i386/spl.h>
#import <machdep/i386/intr_exported.h>
#import <machdep/i386/io_inline.h>
#import <libkern/libkern.h>

#define IO_NUM_PCMCIA_INTERRUPTS	16
#define PCMCIA_DEFAULT_SOCKETS		2

/* PCMCIA controller I/O ports (Intel 82365SL compatible) */
#define PCMCIA_INDEX_REG		0x3E0
#define PCMCIA_DATA_REG			0x3E1

/* PCMCIA registers */
#define PCMCIA_REG_IDENT		0x00
#define PCMCIA_REG_STATUS		0x01
#define PCMCIA_REG_POWER		0x02
#define PCMCIA_REG_INTCTL		0x03
#define PCMCIA_REG_CARDSTAT		0x04

/* Status register bits */
#define PCMCIA_STATUS_CD1		0x01	/* Card Detect 1 */
#define PCMCIA_STATUS_CD2		0x02	/* Card Detect 2 */
#define PCMCIA_STATUS_RDY		0x20	/* Ready */
#define PCMCIA_STATUS_PWR		0x40	/* Power */

/* Card present mask */
#define PCMCIA_CARD_PRESENT		(PCMCIA_STATUS_CD1 | PCMCIA_STATUS_CD2)

/* Function name strings for diagnostic output */
static const char *pcmcia_function_names[] = {
    "Multi-Function",
    "Memory",
    "Serial I/O",
    "Parallel I/O",
    "Fixed Disk",
    "Video Adapter",
    "Network Adapter",
    "AIMS"
};

/*
 * Read PCMCIA controller register
 */
static inline unsigned char
pcmcia_read_reg(unsigned int socket, unsigned char reg)
{
    unsigned char index;

    /* Calculate register index (socket << 6 | reg) */
    index = (socket << 6) | reg;

    outb(PCMCIA_INDEX_REG, index);
    return inb(PCMCIA_DATA_REG);
}

/*
 * Write PCMCIA controller register
 */
static inline void
pcmcia_write_reg(unsigned int socket, unsigned char reg, unsigned char value)
{
    unsigned char index;

    /* Calculate register index (socket << 6 | reg) */
    index = (socket << 6) | reg;

    outb(PCMCIA_INDEX_REG, index);
    outb(PCMCIA_DATA_REG, value);
}

/*
 * Check if card is present in socket
 */
static BOOL
pcmcia_card_present(unsigned int socket)
{
    unsigned char status;

    status = pcmcia_read_reg(socket, PCMCIA_REG_CARDSTAT);

    /* Both card detect pins must be low for card to be present */
    return ((status & PCMCIA_CARD_PRESENT) == 0);
}

/*
 * Parse CIS (Card Information Structure) tuples
 * Returns tuple list and parsed information
 */
static id
pcmcia_parse_cis(id pool, unsigned short *manfid, unsigned short *cardid,
                 unsigned char *funcid, char *vendor, char *product)
{
    unsigned int offset = 0;
    unsigned char code, link;
    unsigned char data[MAX_TUPLE_SIZE];
    int tuple_count = 0;
    int i;
    id tuple;
    id tupleList;
    BOOL found_manfid = NO;
    BOOL found_funcid = NO;

    /* Initialize output parameters */
    if (vendor) vendor[0] = '\0';
    if (product) product[0] = '\0';

    /* Create tuple list */
    tupleList = [[PCMCIATupleList alloc] init];
    if (!tupleList) {
        return nil;
    }

    /* Parse tuples from attribute memory */
    while (offset < 0x1000 && tuple_count < 100) {
        /* Read tuple code */
        code = [pool readByte:offset type:PCMCIA_MEM_ATTRIBUTE];

        /* Check for end of chain */
        if (code == CISTPL_END || code == 0xFF) {
            break;
        }

        /* Read link byte */
        link = [pool readByte:(offset + 2) type:PCMCIA_MEM_ATTRIBUTE];

        /* Sanity check link value */
        if (link == 0xFF || link > MAX_TUPLE_SIZE) {
            break;
        }

        /* Read tuple data */
        for (i = 0; i < link && i < MAX_TUPLE_SIZE; i++) {
            data[i] = [pool readByte:(offset + 4 + (i * 2)) type:PCMCIA_MEM_ATTRIBUTE];
        }

        /* Create tuple object */
        tuple = [[PCMCIATuple alloc] initWithCode:code
                                             link:link
                                             data:data
                                           length:link];

        if (tuple) {
            /* Add to list */
            [tupleList addObject:tuple];

            /* Parse specific tuple types */
            if (code == CISTPL_MANFID) {
                if ([tuple parseManufacturerID:manfid cardID:cardid]) {
                    found_manfid = YES;
                }
            } else if (code == CISTPL_FUNCID) {
                if ([tuple parseFunctionID:funcid]) {
                    found_funcid = YES;
                }
            } else if (code == CISTPL_VERS_1) {
                char vers[64];
                [tuple parseVersionString:product vendor:vendor version:vers];
            }
        }

        /* Move to next tuple (code + link + data) */
        offset += 4 + (link * 2);
        tuple_count++;
    }

    /* Return tuple list if we found minimum required info */
    if (found_manfid && found_funcid && [tupleList count] > 0) {
        return tupleList;
    }

    /* Failed to parse properly, free tuples */
    [tupleList freeObjects];
    [tupleList free];
    return nil;
}


static void
PCMCIAKernBusInterruptDispatch(int deviceIntr, void * ssp, int old_ipl, void *_interrupt)
{
    BOOL			leave_enabled;
    PCMCIAKernBusInterrupt_ *	interrupt = (PCMCIAKernBusInterrupt_ *)_interrupt;

    leave_enabled = KernBusInterruptDispatch(_interrupt, ssp);
    if (!leave_enabled) {
        KernLockAcquire(interrupt->_PCMCIALock);
        intr_disable_irq(interrupt->_irq);
        interrupt->_irqEnabled = NO;
        KernLockRelease(interrupt->_PCMCIALock);
    }
}

@implementation PCMCIAKernBusInterrupt

- initForResource:	resource
	item:		(unsigned int)item
	shareable:	(BOOL)shareable
{
    [super initForResource:resource item:item shareable:shareable];

    _irq = item;
    _irqEnabled = NO;
    _PCMCIALock = [[KernLock alloc] initWithLevel:IPLHIGH];
    _priorityLevel = IPLDEVICE;

    return self;
}

- dealloc
{
    [_PCMCIALock free];
    return [super dealloc];
}

- attachDeviceInterrupt:	interrupt
{
    if (!interrupt)
    	return nil;

    [_PCMCIALock acquire];

    if( NO == _irqAttached) {
        intr_register_irq(_irq,
                        (intr_handler_t)PCMCIAKernBusInterruptDispatch,
                        (unsigned int)self,
                        _priorityLevel);
	_irqAttached = YES;
    }

    if ([super attachDeviceInterrupt:interrupt]) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    } else {
        intr_disable_irq(_irq);
        _irqEnabled = NO;
    }

    [_PCMCIALock release];

    return self;
}

- attachDeviceInterrupt:	interrupt
		atLevel: 	(int)level
{
    if (!interrupt)
	return nil;

    [_PCMCIALock acquire];

    if (level < _priorityLevel || level >  IPLSCHED) {
	[_PCMCIALock release];
    	return nil;
    }

    if (level > _priorityLevel)
    	intr_change_ipl(_irq, level);

    _priorityLevel = level;

    if( NO == _irqAttached) {
        intr_register_irq(_irq,
                        (intr_handler_t)PCMCIAKernBusInterruptDispatch,
                        (unsigned int)self,
                        _priorityLevel);
	_irqAttached = YES;
    }

    if ([super attachDeviceInterrupt:interrupt]) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    } else {
        intr_disable_irq(_irq);
        _irqEnabled = NO;
    }

    [_PCMCIALock release];
    return self;
}

- detachDeviceInterrupt:	interrupt
{
    int			irq = [self item];

    [_PCMCIALock acquire];

    if ( ![super detachDeviceInterrupt:interrupt]) {
      intr_disable_irq(_irq);
      _irqEnabled = NO;
    }

    [_PCMCIALock release];
    return self;
}

- suspend
{
    [_PCMCIALock acquire];

    [super suspend];

    if (_irqEnabled) {
      intr_disable_irq(_irq);
      _irqEnabled = NO;
    }

    [_PCMCIALock release];

    return self;
}

- resume
{
    [_PCMCIALock acquire];

    if ([super resume] && !_irqEnabled) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    }

    [_PCMCIALock release];

    return self;
}

@end



@implementation PCMCIAKernBus

static const char *resourceNameStrings[] = {
    IRQ_LEVELS_KEY,
    DMA_CHANNELS_KEY,
    MEM_MAPS_KEY,
    IO_PORTS_KEY,
    PCMCIA_SOCKETS_KEY,
    NULL
};

+ initialize
{
    [self registerBusClass:self name:"PCMCIA"];
    return self;
}

- init
{
    return [self initWithSocketCount:PCMCIA_DEFAULT_SOCKETS];
}

- initWithSocketCount:(int)count
{
    int i;

    [super init];

    _numSockets = count;

    /* Allocate socket array */
    if (_numSockets > 0) {
        _sockets = (id *)IOMalloc(_numSockets * sizeof(id));
        if (_sockets == NULL) {
            [super free];
            return nil;
        }

        /* Create pool for each socket */
        for (i = 0; i < _numSockets; i++) {
            _sockets[i] = [[PCMCIAPool alloc] initWithSocket:i];
        }
    } else {
        _sockets = NULL;
    }

    [self _insertResource:[[KernBusItemResource alloc]
				initWithItemCount:IO_NUM_PCMCIA_INTERRUPTS
				itemKind:[PCMCIAKernBusInterrupt class]
				owner:self]
		    withKey:IRQ_LEVELS_KEY];

    [self _insertResource:[[KernBusRangeResource alloc]
    					initWithExtent:RangeMAX
					kind:[KernBusMemoryRange class]
					owner:self]
		    withKey:MEM_MAPS_KEY];

    [[self class] registerBusInstance:self name:"PCMCIA" busId:[self busId]];

    /* Probe all sockets for cards */
    [self probeAllSockets];

    printf("PCMCIA bus support enabled (%d socket%s)\n",
           _numSockets, _numSockets == 1 ? "" : "s");
    return self;
}

- (const char **)resourceNames
{
    return resourceNameStrings;
}

- free
{
    int i;

    if ([self areResourcesActive])
    	return self;

    /* Free all sockets */
    if (_sockets) {
        for (i = 0; i < _numSockets; i++) {
            if (_sockets[i]) {
                [_sockets[i] free];
            }
        }
        IOFree(_sockets, _numSockets * sizeof(id));
        _sockets = NULL;
    }

    [[self _deleteResourceWithKey:IRQ_LEVELS_KEY] free];
    [[self _deleteResourceWithKey:MEM_MAPS_KEY] free];

    return [super free];
}

/* Socket management */
- (int)numSockets
{
    return _numSockets;
}

- socketAtIndex:(int)index
{
    if (index < 0 || index >= _numSockets || _sockets == NULL) {
        return nil;
    }

    return _sockets[index];
}

/* Card detection and enumeration */
- (BOOL)probeSocket:(int)socket
{
    id pool;
    id tupleList;
    unsigned short manfid = 0, cardid = 0;
    unsigned char funcid = 0;
    char vendor[64], product[64];
    const char *func_name;

    if (socket < 0 || socket >= _numSockets) {
        return NO;
    }

    /* Check if card is present */
    if (!pcmcia_card_present(socket)) {
        return NO;
    }

    pool = _sockets[socket];
    [pool setState:PCMCIA_SOCKET_OCCUPIED];

    /* Map attribute memory window to read CIS */
    if (![pool mapWindow:PCMCIA_MEM_ATTRIBUTE
                physAddr:0xD0000  /* Typical PCMCIA attribute memory base */
                    size:0x4000
                   flags:PCMCIA_WINDOW_8BIT]) {
        printf("PCMCIA Socket %d: Failed to map attribute memory\n", socket);
        return NO;
    }

    /* Parse CIS tuples */
    tupleList = pcmcia_parse_cis(pool, &manfid, &cardid, &funcid, vendor, product);
    if (!tupleList) {
        printf("PCMCIA Socket %d: Card present but CIS parse failed\n", socket);
        [pool unmapWindow:PCMCIA_MEM_ATTRIBUTE];
        return NO;
    }

    /* Store card information and tuple list in pool */
    [pool setManufacturerID:manfid cardID:cardid];
    [pool setFunctionID:funcid];
    [pool setTupleList:tupleList];
    [pool setState:PCMCIA_SOCKET_READY];

    /* Get function name string */
    if (funcid < (sizeof(pcmcia_function_names) / sizeof(char *))) {
        func_name = pcmcia_function_names[funcid];
    } else {
        func_name = "Unknown";
    }

    /* Print card information */
    printf("PCMCIA Socket %d: %s Card detected\n", socket, func_name);
    printf("  Manufacturer: %s\n", vendor[0] ? vendor : "Unknown");
    printf("  Product: %s\n", product[0] ? product : "Unknown");
    printf("  IDs: %04x:%04x Function: 0x%02x\n", manfid, cardid, funcid);
    printf("  Tuples: %d\n", [tupleList count]);

    /* Keep attribute memory mapped for driver use */
    /* Drivers can access via IOPCMCIADirectDevice methods */

    return YES;
}

- (void)probeAllSockets
{
    int i;
    int cards_found = 0;

    printf("Scanning PCMCIA sockets...\n");

    for (i = 0; i < _numSockets; i++) {
        if ([self probeSocket:i]) {
            cards_found++;
        }
    }

    if (cards_found == 0) {
        printf("No PCMCIA cards detected\n");
    }
}

/*
 * Allocate resources for a PCMCIA device description
 */
- allocateResourcesForDeviceDescription:descr
{
    id pool;
    int socket;

    /* Get socket number from device description */
    if ([descr respondsTo:@selector(socket)]) {
        socket = [descr socket];

        if (socket >= 0 && socket < _numSockets) {
            pool = _sockets[socket];

            /* Set bus reference */
            [descr setBus:self];

            /* Allocate interrupt and memory resources via parent class */
            return [super allocateResourcesForDeviceDescription:descr];
        }
    }

    return nil;
}

/*
 * Allocate memory window for socket
 * Takes a PCMCIASocket object and returns a PCMCIAWindow object
 */
- allocMemoryWindowForSocket:socketObj
{
    id window;

    if (!socketObj) {
        return nil;
    }

    /* Create new window associated with this socket */
    window = [[PCMCIAWindow alloc] initWithSocket:socketObj];

    return window;
}

/*
 * Return memory range resource for mapping
 */
- memoryRangeResource
{
    return [self _lookupResourceWithKey:MEM_MAPS_KEY];
}

@end
