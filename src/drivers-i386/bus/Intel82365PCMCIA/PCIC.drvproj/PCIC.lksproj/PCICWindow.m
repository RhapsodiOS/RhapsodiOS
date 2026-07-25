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
 * PCICWindow Implementation
 */

#import "PCICWindow.h"
#import "PCICSocket.h"
#import <machdep/i386/io_inline.h>
#import <objc/List.h>

/* External reference to global reg_base from PCIC.m */
extern unsigned int reg_base;

/* Internal helper functions */
static void setMemoryWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr);
static void setIoWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr);

@implementation PCICWindow

/*
 * Initialize window with socket, memory window type, and number
 */
- initWithSocket:theSocket memoryWindow:(char)memWindow number:(int)number
{
    /* Store socket at offset 4 */
    socket = theSocket;

    /* Get and cache socket number at offset 0xc */
    socketNumber = [theSocket socketNumber];

    /* Store window number at offset 0x10 */
    windowNumber = number;

    /* Store memory window flag at offset 0x14 */
    memoryWindow = memWindow;

    /* Create list of valid sockets and add the socket to it (offset 8) */
    validSockets = [[List alloc] init];
    [validSockets addObject:socket];

    return self;
}

/*
 * Get parent socket
 * Returns socket from offset 4
 */
- socket
{
    return socket;
}

/*
 * Get enabled state
 * Checks bit in Address Window Enable register
 */
- (char)enabled
{
    unsigned char regValue;
    char bitOffset;

    /* Read Address Window Enable register: (socket * 64) + 0x06 */
    outb(reg_base, (char)(socketNumber << 6) + 0x06);
    regValue = inb(reg_base + 1);

    /* Calculate bit position based on window type */
    bitOffset = 0;
    if (memoryWindow == 0) {
        /* Memory windows start at bit 6 */
        bitOffset = 6;
    }

    /* Check if the bit for this window is set */
    return ((unsigned int)regValue & (1 << ((bitOffset + (char)windowNumber) & 0x1F))) != 0;
}

/*
 * Get system address
 * Returns systemAddress from offset 0x18
 */
- (unsigned int)systemAddress
{
    return systemAddress;
}

/*
 * Get card address
 * Returns cardAddress from offset 0x1c
 */
- (unsigned int)cardAddress
{
    return cardAddress;
}

/*
 * Get map size
 * Returns mapSize from offset 0x20
 */
- (unsigned int)mapSize
{
    return mapSize;
}

/*
 * Get attribute memory flag
 * Reads bit 6 from window control register
 */
- (char)attributeMemory
{
    unsigned char regValue;

    /* Read window control register: (socket * 64) + 0x15 + (window * 8) */
    outb(reg_base, (char)(socketNumber << 6) + 0x15 + (char)windowNumber * 8);
    regValue = inb(reg_base + 1);

    /* Return bit 6 (attribute memory enable) */
    return (regValue >> 6) & 1;
}

/*
 * Get 16-bit data path flag
 * Reads different registers based on window type
 */
- (char)is16Bit
{
    unsigned char regValue;

    if (memoryWindow == 0) {
        /* Memory window: read I/O Control register */
        outb(reg_base, (char)(socketNumber << 6) + 0x07);
        regValue = inb(reg_base + 1);

        /* For window 0: bit 0, for window 1: bit 4 */
        if (windowNumber != 0) {
            regValue = regValue >> 4;
        }
        return regValue & 1;
    }
    else {
        /* I/O window: read window control register */
        outb(reg_base, (char)(socketNumber << 6) + 0x11 + (char)windowNumber * 8);
        regValue = inb(reg_base + 1);

        /* Return bit 7 */
        return regValue >> 7;
    }
}

/*
 * Get memory interface type
 * Returns memoryWindow flag from offset 0x14
 */
- (char)memoryInterface
{
    return memoryWindow;
}

/*
 * Get valid sockets
 * Returns validSockets from offset 8
 */
- validSockets
{
    return validSockets;
}

/*
 * Set parent socket
 * Validates that the socket matches the current socket
 */
- (char)setSocket:theSocket
{
    /* Check if the requested socket matches current socket */
    if (socket != theSocket) {
        /* Socket mismatch - cannot change socket */
        return 0;
    }
    /* Socket matches - no action needed */

    return 1;
}

/*
 * Set enabled state
 * Sets or clears bit in Address Window Enable register
 */
- (char)setEnabled:(char)isEnabled
{
    unsigned char regValue;
    unsigned char bitPosition;
    char bitOffset;
    char regOffset;

    /* Read Address Window Enable register: (socket * 64) + 0x06 */
    outb(reg_base, (char)(socketNumber << 6) + 0x06);
    regValue = inb(reg_base + 1);

    /* Calculate bit offset based on window type */
    bitOffset = 0;
    if (memoryWindow == 0) {
        /* Memory windows start at bit 6 */
        bitOffset = 6;
    }

    /* Calculate bit position for this window */
    bitPosition = (bitOffset + (char)windowNumber) & 0x1F;

    if (isEnabled == 0) {
        /* Disable: clear the bit */
        regValue = regValue & ~(1 << bitPosition);
    }
    else {
        /* Enable: set the bit */
        regValue = regValue | (1 << bitPosition);
    }

    /* Write back to Address Window Enable register */
    regOffset = (char)(socketNumber << 6);
    outb(reg_base, regOffset + 0x06);
    outb(reg_base + 1, regValue);

    return 1;
}

/*
 * Set mapping with size, system address, and card address
 * Stores parameters and calls appropriate window configuration function
 */
- (char)setMapWithSize:(unsigned int)size systemAddress:(unsigned int)sysAddr cardAddress:(unsigned int)cardAddr
{
    /* Store parameters at their respective offsets */
    systemAddress = sysAddr;   /* Offset 0x18 */
    cardAddress = cardAddr;     /* Offset 0x1c */
    mapSize = size;             /* Offset 0x20 */

    /* Call appropriate window setup function based on window type
     * Note: The function calls appear inverted but match the decompiled binary */
    if (memoryWindow == 0) {
        setIoWindow(socketNumber, windowNumber, cardAddr, size, sysAddr);
    }
    else {
        setMemoryWindow(socketNumber, windowNumber, cardAddr, size, sysAddr);
    }

    return 1;
}

/*
 * Set attribute memory flag
 * Sets bit 6 in window control register
 */
- (char)setAttributeMemory:(char)attrMem
{
    unsigned char regValue;
    char regOffset;

    /* Calculate register offset: (socket * 64) + 0x15 + (window * 8) */
    regOffset = (char)socketNumber * 64 + 0x15 + (char)windowNumber * 8;

    /* Read current window control register value */
    outb(reg_base, regOffset);
    regValue = inb(reg_base + 1);

    /* Write back with bit 6 set according to attrMem parameter */
    regOffset = (char)socketNumber * 64 + 0x15 + (char)windowNumber * 8;
    outb(reg_base, regOffset);
    outb(reg_base + 1, (regValue & 0xBF) | ((attrMem & 1) << 6));

    return 1;
}

/*
 * Set 16-bit data path flag
 * Writes to different registers based on window type
 */
- (char)set16Bit:(char)is16
{
    unsigned char regValue;
    char regOffset;

    if (memoryWindow == 0) {
        /* Memory window: modify I/O Control register */
        outb(reg_base, (char)(socketNumber << 6) + 0x07);
        regValue = inb(reg_base + 1);

        if (windowNumber == 0) {
            /* Window 0: set bits 0-1 to the same value */
            regValue = (regValue & 0xF4) | (is16 & 1) | ((is16 & 1) << 1);
        }
        else {
            /* Window 1: set bits 4-5 to the same value */
            regValue = (regValue & 0x4F) | ((is16 & 1) << 4) | ((is16 & 1) << 5);
        }

        /* Write back to I/O Control register */
        regOffset = (char)(socketNumber << 6);
        outb(reg_base, regOffset + 0x07);
    }
    else {
        /* I/O window: modify window control register */
        regOffset = (char)socketNumber * 64 + 0x11 + (char)windowNumber * 8;
        outb(reg_base, regOffset);
        regValue = inb(reg_base + 1);

        /* Set bit 7 */
        regValue = (regValue & 0x7F) | (is16 << 7);

        /* Write back to window control register */
        regOffset = (char)socketNumber * 64 + 0x11 + (char)windowNumber * 8;
        outb(reg_base, regOffset);
    }

    /* Write the value */
    outb(reg_base + 1, regValue);

    return 1;
}

/*
 * Set memory interface type
 * Validates that the interface matches the window type
 */
- (char)setMemoryInterface:(char)interface
{
    /* Check if the requested interface matches current window type */
    if (memoryWindow != interface) {
        /* Interface mismatch - cannot change window type */
        return 0;
    }
    /* Interface matches - no action needed */

    return 1;
}

@end

/*
 * Configure a memory window
 * Sets up PCIC registers for memory window mapping
 */
static void setMemoryWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr)
{
    unsigned char socketOffset;
    unsigned char windowOffset;
    unsigned int startAddr;
    unsigned int stopAddr;
    unsigned int cardOffset;

    /* Calculate socket base offset: socket * 64 */
    socketOffset = socket << 6;

    /* Calculate window register base: 0x10 + (window * 8) for memory windows */
    /* Each memory window uses 8 registers:
     * +0: Memory window start address low (bits 12-19)
     * +1: Memory window start address high (bits 20-23)
     * +2: Memory window stop address low (bits 12-19)
     * +3: Memory window stop address high (bits 20-23)
     * +4: Card offset address low (bits 12-19)
     * +5: Card offset address high (bits 20-25) + flags
     * +6: Reserved
     * +7: Reserved
     */
    windowOffset = 0x10 + (window * 8);

    /* Memory addresses are shifted right by 12 bits (4KB pages) */
    startAddr = sysAddr >> 12;
    stopAddr = (sysAddr + size - 1) >> 12;
    cardOffset = cardAddr >> 12;

    /* Write system start address */
    outb(reg_base, socketOffset + windowOffset);
    outb(reg_base + 1, (unsigned char)(startAddr & 0xFF));
    outb(reg_base, socketOffset + windowOffset + 1);
    outb(reg_base + 1, (unsigned char)((startAddr >> 8) & 0x0F));

    /* Write system stop address */
    outb(reg_base, socketOffset + windowOffset + 2);
    outb(reg_base + 1, (unsigned char)(stopAddr & 0xFF));
    outb(reg_base, socketOffset + windowOffset + 3);
    outb(reg_base + 1, (unsigned char)((stopAddr >> 8) & 0x0F));

    /* Write card offset address */
    outb(reg_base, socketOffset + windowOffset + 4);
    outb(reg_base + 1, (unsigned char)(cardOffset & 0xFF));
    outb(reg_base, socketOffset + windowOffset + 5);
    outb(reg_base + 1, (unsigned char)((cardOffset >> 8) & 0x3F));
}

/*
 * Configure an I/O window
 * Sets up PCIC registers for I/O window mapping
 */
static void setIoWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr)
{
    unsigned char socketOffset;
    unsigned char windowOffset;
    unsigned short startAddr;
    unsigned short stopAddr;

    /* Calculate socket base offset: socket * 64 */
    socketOffset = socket << 6;

    /* Calculate window register base: 0x08 + (window * 4) for I/O windows */
    /* Each I/O window uses 4 registers:
     * +0: I/O window start address low
     * +1: I/O window start address high
     * +2: I/O window stop address low
     * +3: I/O window stop address high
     */
    windowOffset = 0x08 + (window * 4);

    /* Calculate start and stop addresses */
    startAddr = (unsigned short)sysAddr;
    stopAddr = (unsigned short)(sysAddr + size - 1);

    /* Write start address low byte */
    outb(reg_base, socketOffset + windowOffset);
    outb(reg_base + 1, (unsigned char)(startAddr & 0xFF));

    /* Write start address high byte */
    outb(reg_base, socketOffset + windowOffset + 1);
    outb(reg_base + 1, (unsigned char)((startAddr >> 8) & 0xFF));

    /* Write stop address low byte */
    outb(reg_base, socketOffset + windowOffset + 2);
    outb(reg_base + 1, (unsigned char)(stopAddr & 0xFF));

    /* Write stop address high byte */
    outb(reg_base, socketOffset + windowOffset + 3);
    outb(reg_base + 1, (unsigned char)((stopAddr >> 8) & 0xFF));
}
