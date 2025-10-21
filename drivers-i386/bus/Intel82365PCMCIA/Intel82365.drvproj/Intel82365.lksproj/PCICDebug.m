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
 * PCIC Debug Category Implementation
 */

#import "PCIC.h"
#import <driverkit/generalFuncs.h>
#import <mach/mach.h>
#import <kernserv/prototypes.h>

/* External reference to global reg_base from PCIC.m */
extern unsigned int reg_base;

/* Global variables for memory mapping */
static char *__memory = NULL;

/* Forward declaration of _setWindow function */
static IOReturn _setWindow(int socket, int window, unsigned int baseAddr,
                           unsigned int size, unsigned int physicalAddr,
                           unsigned int offset, unsigned int flags,
                           int windowType, int enable);

/*
 * Find empty memory range in upper memory (0xCC000-0xF0000)
 * Scans for BIOS ROM signatures (0xAA55) and finds unused space
 */
static char * _FindEmptyMemoryRange(void)
{
    unsigned char *ptr;
    unsigned char biosLength;

    ptr = (unsigned char *)0xCC000;

    do {
        /* Check for BIOS signature: 0xAA55 */
        if ((ptr[0] == 0xAA) && (ptr[1] == 0x55)) {
            /* Third byte is BIOS length in 512-byte blocks */
            biosLength = ptr[2];
            IOLog("BIOS at %x, length %x\n", ptr, (unsigned int)biosLength * 0x200);

            /* Advance by BIOS length, rounded up to 0x800 boundary */
            ptr = ptr + (((unsigned int)biosLength * 0x200 + 0x7FF) & 0xFFFFF800);
        }
        else {
            IOLog("No BIOS at %x\n", ptr);

            /* If bit 0x2000 is clear, this is an empty range */
            if (((unsigned int)ptr & 0x2000) == 0) {
                return (char *)ptr;
            }

            /* Advance by 0x800 bytes (2KB) */
            ptr = ptr + 0x800;
        }
    } while (ptr < (unsigned char *)0xF0000);

    return (char *)ptr;
}

/*
 * Map attribute memory for PCMCIA socket
 * Finds empty memory range, maps it, and configures PCIC window
 */
static unsigned long long _MapAttributeMemory(int socket)
{
    unsigned char regValue;
    unsigned char regOffset;
    unsigned int physicalAddr;
    vm_task_t task;

    /* Find and store empty memory range in global */
    __memory = _FindEmptyMemoryRange();

    /* Get VM task */
    task = IOVmTaskSelf();

    /* Get physical address from virtual address */
    IOPhysicalFromVirtual(task, (vm_address_t)__memory, (vm_offset_t *)&physicalAddr);

    IOLog("buffer: logical %x, physical %x\n", __memory, physicalAddr);

    /* Calculate register offset: (socket * 64) + 6 */
    /* Register 6 is the Memory Window Control register */
    regOffset = (socket << 6) + 0x06;

    /* Read current window control register value */
    outb(reg_base, regOffset);
    regValue = inb(reg_base + 1);

    /* Disable window by clearing lower bits (keep only upper 3 bits) */
    outb(reg_base, regOffset);
    outb(reg_base + 1, regValue & 0xE0);

    /* Configure the window
     * Parameters: socket, window 0, base 0, size 0x2000 (8KB),
     *            physical address, offset 0, flags 0, type 1, enable 0
     */
    _setWindow(socket, 0, 0, 0x2000, physicalAddr, 0, 0, 1, 0);

    /* Enable window (set bit 0 = window enable) */
    outb(reg_base, regOffset);
    outb(reg_base + 1, (regValue & 0xE0) | 1);

    /* Return the final register value written */
    return ((regValue & 0xE0) | 1);
}

/*
 * Set window configuration
 * Configures a PCMCIA memory or I/O window
 * Implementation to be filled in from decompiled code
 */
static IOReturn _setWindow(int socket, int window, unsigned int baseAddr,
                           unsigned int size, unsigned int physicalAddr,
                           unsigned int offset, unsigned int flags,
                           int windowType, int enable)
{
    /* Placeholder implementation */
    /* This would configure PCIC window registers for the specified parameters */
    return IO_R_SUCCESS;
}

@implementation PCIC(Debug)

/*
 * Read attribute memory at address for socket
 * On first call, initializes attribute memory mapping
 * Waits for card ready status before reading
 */
- (unsigned char)_readAttributeMemory:(unsigned int)address forSocket:(unsigned int)socket
{
    static int __init_117 = 0;
    unsigned char statusReg;
    int retries;
    unsigned char value;

    /* Initialize attribute memory mapping on first call */
    if (__init_117 == 0) {
        _MapAttributeMemory(0);
        __init_117 = 1;
    }

    /* Wait for card to be ready (up to 1000 attempts) */
    retries = 1000;
    do {
        /* Read Interface Status register: (socket * 64) + 1 */
        outb(reg_base, (socket << 6) + 0x01);
        statusReg = inb(reg_base + 1);

        /* Check if ready bit (0x20) is set */
        if ((statusReg & 0x20) != 0) {
            break;
        }

        /* Delay 2 microseconds */
        IODelay(2);
        retries--;
    } while (retries != 0);

    /* Check if we timed out */
    if (retries == 0) {
        IOLog("PCIC: readAttributeMemory: not ready\n");
        value = 0xFF;
    }
    else {
        /* Read byte from mapped attribute memory */
        value = *((unsigned char *)(__memory + address));
    }

    return value;
}

/*
 * Spoof interrupt for testing
 * Simulates an interrupt by directly calling the interrupt handler
 */
- (void)_spoofInterrupt
{
    /* Call the interrupt handler directly to simulate an interrupt */
    [self interruptOccurred];
}

@end
