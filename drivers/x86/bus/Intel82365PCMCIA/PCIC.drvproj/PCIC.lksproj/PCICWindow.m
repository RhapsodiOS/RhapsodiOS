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

/* External helper functions */
extern void _setIoWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr);
extern void _setMemoryWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr);

@implementation PCICWindow

/*
 * Initialize window with socket, memory window type, and number
 */
- initWithSocket:theSocket memoryWindow:(int)memWindow number:(int)number
{
    /* Store socket at offset 4 */
    socket = theSocket;

    /* Get and cache socket number at offset 0xc */
    socketNumber = [theSocket socketNumber];

    /* Store window number at offset 0x10 */
    windowNumber = number;

    /* Store memory window flag at offset 0x14 */
    memoryWindow = (unsigned char)memWindow;

    /* Create list of valid sockets and add the socket to it (offset 8) */
    validSocketsList = [[List alloc] init];
    [validSocketsList addObject:socket];

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
- (unsigned int)enabled
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
- (unsigned int)attributeMemory
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
- (unsigned int)is16Bit
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
- (unsigned int)memoryInterface
{
    return memoryWindow;
}

/*
 * Get valid sockets
 * Returns validSocketsList from offset 8
 */
- validSockets
{
    return validSocketsList;
}

/*
 * Set parent socket
 * Validates that the socket matches the current socket
 */
- (void)setSocket:theSocket
{
    /* Check if the requested socket matches current socket */
    if (socket != theSocket) {
        /* Socket mismatch - cannot change socket */
        return;
    }
    /* Socket matches - no action needed */
}

/*
 * Set enabled state
 * Sets or clears bit in Address Window Enable register
 */
- (void)setEnabled:(unsigned int)isEnabled
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
}

/*
 * Set mapping with size, system address, and card address
 * Stores parameters and calls appropriate window configuration function
 */
- (void)setMapWithSize:(unsigned int)size systemAddress:(unsigned int)sysAddr cardAddress:(unsigned int)cardAddr
{
    /* Store parameters at their respective offsets */
    systemAddress = sysAddr;   /* Offset 0x18 */
    cardAddress = cardAddr;     /* Offset 0x1c */
    mapSize = size;             /* Offset 0x20 */

    /* Call appropriate window setup function based on window type
     * Note: The function calls appear inverted but match the decompiled binary */
    if (memoryWindow == 0) {
        _setIoWindow(socketNumber, windowNumber, cardAddr, size, sysAddr);
    }
    else {
        _setMemoryWindow(socketNumber, windowNumber, cardAddr, size, sysAddr);
    }
}

/*
 * Set attribute memory flag
 * Sets bit 6 in window control register
 */
- (void)setAttributeMemory:(unsigned int)attrMem
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
}

/*
 * Set 16-bit data path flag
 * Writes to different registers based on window type
 */
- (void)set16Bit:(unsigned int)is16
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
}

/*
 * Set memory interface type
 * Validates that the interface matches the window type
 */
- (void)setMemoryInterface:(unsigned int)interface
{
    /* Check if the requested interface matches current window type */
    if (memoryWindow != interface) {
        /* Interface mismatch - cannot change window type */
        return;
    }
    /* Interface matches - no action needed */
}

@end
