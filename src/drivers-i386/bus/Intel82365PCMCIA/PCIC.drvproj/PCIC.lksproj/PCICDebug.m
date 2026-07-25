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
#import <machdep/i386/io_inline.h>
#import <kernserv/prototypes.h>

/* External reference to global reg_base from PCIC.m */
extern unsigned int reg_base;

/* Global variables for memory mapping */
static char *__memory = NULL;

/* Forward declaration of setWindow function */
static void setWindow(int socket, int window, unsigned int cardAddress,
                      unsigned int size, unsigned int systemAddress,
                      char is16Bit, char extraWaitState,
                      char attributeMemory, char writeProtect);

/*
 * Find empty memory range in upper memory (0xCC000-0xF0000)
 * Scans for BIOS ROM signatures (0xAA55) and finds unused space
 */
static char * FindEmptyMemoryRange(void)
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
unsigned long long MapAttributeMemory(int socket)
{
    unsigned char regValue;
    unsigned char regOffset;
    unsigned int physicalAddr;
    vm_task_t task;

    /* Find and store empty memory range in global */
    __memory = FindEmptyMemoryRange();

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
     * Parameters: socket, window 0, card address 0, size 0x2000 (8KB),
     *            system address, 8-bit path, no extra wait state,
     *            attribute memory, no write protect
     */
    setWindow(socket, 0, 0, 0x2000, physicalAddr, 0, 0, 1, 0);

    /* Enable window (set bit 0 = window enable) */
    outb(reg_base, regOffset);
    outb(reg_base + 1, (regValue & 0xE0) | 1);

    /* Return the final register value written */
    return ((regValue & 0xE0) | 1);
}

/*
 * Set window configuration
 * Programs the six registers of one memory window: the system start and stop
 * addresses, the card offset, and the flags that ride in the high bits of the
 * three odd registers
 */
static void setWindow(int socket, int window, unsigned int cardAddress,
                      unsigned int size, unsigned int systemAddress,
                      char is16Bit, char extraWaitState,
                      char attributeMemory, char writeProtect)
{
    unsigned int cardOffset;
    unsigned int stopAddress;
    unsigned int socketOffset;
    unsigned int windowOffset;
    unsigned char regValue;

    /* The card offset register holds a displacement that is added to the
     * system address to reach the card address; 0x400000 is the 4MB wrap
     * constant that keeps the field positive */
    cardOffset = cardAddress + 0x400000 - systemAddress;

    /* Window register base: (socket * 64) + 0x10 + (window * 8) */
    windowOffset = window << 3;
    socketOffset = socket << 6;

    /* +0: system start address, bits 12-19 */
    outb(reg_base, socketOffset + windowOffset + 0x10);
    outb(reg_base + 1, (unsigned char)((systemAddress >> 12) & 0xFF));

    /* +1: system start address bits 20-23, plus the 16-bit data path */
    regValue = ((systemAddress >> 20) & 0x0F) | (is16Bit << 7);
    outb(reg_base, socketOffset + windowOffset + 0x11);
    outb(reg_base + 1, regValue);

    /* +2: system stop address, bits 12-19 */
    stopAddress = systemAddress + size - 1;
    outb(reg_base, socketOffset + windowOffset + 0x12);
    outb(reg_base + 1, (unsigned char)((stopAddress >> 12) & 0xFF));

    /* +3: system stop address bits 20-23, plus the extra wait state */
    regValue = ((stopAddress >> 20) & 0x0F) | (extraWaitState << 6);
    outb(reg_base, socketOffset + windowOffset + 0x13);
    outb(reg_base + 1, regValue);

    /* +4: card offset address, bits 12-19 */
    outb(reg_base, socketOffset + windowOffset + 0x14);
    outb(reg_base + 1, (unsigned char)((cardOffset >> 12) & 0xFF));

    /* +5: card offset bits 20-25, the attribute memory select and the
     * write protect bit */
    regValue = ((cardOffset >> 20) & 0x3F) | ((attributeMemory & 1) << 6);
    regValue = (regValue & 0x7F) | (writeProtect << 7);
    outb(reg_base, socketOffset + windowOffset + 0x15);
    outb(reg_base + 1, regValue);
}

@implementation PCIC(Debug)

/*
 * Read attribute memory at address for socket
 * On first call, initializes attribute memory mapping
 * Waits for card ready status before reading
 */
- (unsigned char)readAttributeMemory:(int)address forSocket:(int)socket
{
    static int __init_117 = 0;
    unsigned char statusReg;
    int retries;
    unsigned char value;

    /* Initialize attribute memory mapping on first call */
    if (__init_117 == 0) {
        MapAttributeMemory(0);
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
- (void)spoofInterrupt
{
    /* Call the interrupt handler directly to simulate an interrupt */
    [self interruptOccurred];
}

@end
