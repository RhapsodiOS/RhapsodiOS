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
 * PCICSocket Implementation
 */

#import "PCICSocket.h"
#import "PCIC.h"
#import "PCICWindow.h"
#import <objc/List.h>
#import <driverkit/generalFuncs.h>
#import <machdep/i386/io_inline.h>

/* External reference to global reg_base from PCIC.m */
extern unsigned int reg_base;

/* External reference to _socketIsValid function from PCIC.m */
extern char _socketIsValid(unsigned int socket);

@implementation PCICSocket

/*
 * Initialize socket with adapter and socket number
 * Validates socket, initializes hardware registers, and creates window objects
 */
- initWithAdapter:theAdapter socketNumber:(unsigned int)number
{
    char socketValid;
    char socketOffset;
    unsigned short dataPort;
    id window;
    int i;
    char windowOffset;

    /* Store adapter and socket number at offsets 4 and 8 */
    adapter = theAdapter;
    socketNumber = number;

    /* Validate socket hardware */
    socketValid = _socketIsValid(number);
    if (socketValid == 0) {
        [self free];
        return nil;
    }

    /* Initialize socket registers */
    dataPort = reg_base + 1;

    /* Register 2: Power and RESETDRV Control - disable all power */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    outb(dataPort, 0);

    /* Register 3: Interrupt and General Control - disable interrupts */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x03);
    outb(dataPort, 0);

    /* Register 4: Card Status Change - clear status */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x04);
    outb(dataPort, 0);

    /* Register 5: Card Status Change Interrupt Enable - disable */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x05);
    outb(dataPort, 0);

    /* Register 6: Address Window Enable - enable bit 5 (0x20) */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x06);
    outb(dataPort, 0x20);

    /* Register 7: I/O Control - initialize to 0 */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x07);
    outb(dataPort, 0);

    /* Create window list with capacity for 7 windows (offset 0x10 = 16) */
    windowList = [[List alloc] initCount:7];
    windowList = [windowList init];

    /* Create 1 memory window (memoryWindow = 0) */
    for (i = 0; i < 1; i++) {
        window = [[PCICWindow alloc] initWithSocket:self memoryWindow:0 number:i];
        window = [window init];
        [windowList addObject:window];

        /* Configure memory window registers */
        windowOffset = (char)i * 4;

        /* Register 8+offset: Memory Window Start Address Low */
        socketOffset = (char)socketNumber * 64 + 0x08 + windowOffset;
        outb(reg_base, socketOffset);
        outb(dataPort, 0xFF);

        /* Register 9+offset: Memory Window Start Address High */
        socketOffset = (char)socketNumber * 64 + 0x09 + windowOffset;
        outb(reg_base, socketOffset);
        outb(dataPort, 7);

        /* Register 10+offset: Memory Window Stop Address Low */
        socketOffset = (char)socketNumber * 64 + 0x0A + windowOffset;
        outb(reg_base, socketOffset);
        outb(dataPort, 0xFF);

        /* Register 11+offset: Memory Window Stop Address High */
        windowOffset = (char)socketNumber * 64 + 0x0B + windowOffset;
        outb(reg_base, windowOffset);
        outb(dataPort, 7);
    }

    /* Create 5 I/O windows (memoryWindow = 1) */
    for (i = 0; i < 5; i++) {
        window = [[PCICWindow alloc] initWithSocket:self memoryWindow:1 number:i];
        window = [window init];
        [windowList addObject:window];

        /* Configure I/O window registers */
        windowOffset = (char)i * 8;

        /* Register 0x10+offset: I/O Window Start Address Low */
        socketOffset = (char)socketNumber * 64 + 0x10 + windowOffset;
        outb(reg_base, socketOffset);
        outb(dataPort, 0xFF);

        /* Register 0x11+offset: I/O Window Start Address High */
        socketOffset = (char)socketNumber * 64 + 0x11 + windowOffset;
        outb(reg_base, socketOffset);
        outb(dataPort, 7);

        /* Register 0x12+offset: I/O Window Stop Address Low */
        socketOffset = (char)socketNumber * 64 + 0x12 + windowOffset;
        outb(reg_base, socketOffset);
        outb(dataPort, 0xFF);

        /* Register 0x13+offset: I/O Window Stop Address High */
        windowOffset = (char)socketNumber * 64 + 0x13 + windowOffset;
        outb(reg_base, windowOffset);
        outb(dataPort, 7);
    }

    return self;
}

/*
 * Get list of windows for this socket
 * Returns window list from offset 0x10
 */
- windows
{
    return windowList;
}

/*
 * Get socket number
 * Returns socket number from offset 8
 */
- (unsigned int)socketNumber
{
    return socketNumber;
}

/*
 * Get parent adapter
 */
- adapter
{
    return adapter;
}

/*
 * Get card enabled state
 * Reads bit 7 from Power and RESETDRV Control register
 */
- (unsigned int)cardEnabled
{
    unsigned char regValue;

    /* Read Power and RESETDRV Control register: (socket * 64) + 2 */
    outb(reg_base, (char)(socketNumber << 6) + 0x02);
    regValue = inb(reg_base + 1);

    /* Return bit 7 (card enable/output enable) */
    return regValue >> 7;
}

/*
 * Get card VCC power level
 * Reads bit 4 from Power and RESETDRV Control register
 */
- (unsigned int)cardVccPower
{
    unsigned char regValue;

    /* Read Power and RESETDRV Control register: (socket * 64) + 2 */
    outb(reg_base, (char)(socketNumber << 6) + 0x02);
    regValue = inb(reg_base + 1);

    /* Return bit 4 (VCC power enable) */
    return (regValue >> 4) & 1;
}

/*
 * Get card VPP power level
 * Reads lower 2 bits from Power and RESETDRV Control register
 */
- (unsigned int)cardVppPower
{
    unsigned char regValue;

    /* Read Power and RESETDRV Control register: (socket * 64) + 2 */
    outb(reg_base, (char)(socketNumber << 6) + 0x02);
    regValue = inb(reg_base + 1);

    /* Return lower 2 bits (VPP1/VPP2 power level) */
    return regValue & 3;
}

/*
 * Get card auto power state
 * Reads bit 5 from Power and RESETDRV Control register
 */
- (unsigned int)cardAutoPower
{
    unsigned char regValue;

    /* Read Power and RESETDRV Control register: (socket * 64) + 2 */
    outb(reg_base, (char)(socketNumber << 6) + 0x02);
    regValue = inb(reg_base + 1);

    /* Return bit 5 (auto power switch enable) */
    return (regValue >> 5) & 1;
}

/*
 * Get card IRQ number
 * Reads lower 4 bits from Interrupt and General Control register
 */
- (unsigned int)cardIRQ
{
    unsigned char regValue;

    /* Read Interrupt and General Control register: (socket * 64) + 3 */
    outb(reg_base, (char)(socketNumber << 6) + 0x03);
    regValue = inb(reg_base + 1);

    /* Return lower 4 bits (IRQ select) */
    return regValue & 0x0F;
}

/*
 * Get memory interface type
 * Reads inverted bit 5 from Interrupt and General Control register
 */
- (unsigned int)memoryInterface
{
    unsigned char regValue;

    /* Read Interrupt and General Control register: (socket * 64) + 3 */
    outb(reg_base, (char)(socketNumber << 6) + 0x03);
    regValue = inb(reg_base + 1);

    /* Return inverted bit 5 (memory only interface flag) */
    return (~(regValue >> 5)) & 1;
}

/*
 * Get status change mask
 * Returns mask from offset 0xc
 */
- (unsigned int)statusChangeMask
{
    return statusChangeMask;
}

/*
 * Get power states
 * Returns available power states (currently none)
 */
- (unsigned int)powerStates
{
    return 0;
}

/*
 * Get socket status
 * Reads and reformats Interface Status register
 */
- (unsigned int)status
{
    unsigned char regValue;
    char socketOffset;

    /* Read Interface Status register: (socket * 64) + 1 */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x01);
    regValue = inb(reg_base + 1);

    /* Reformat status bits:
     * bit 0: Card detect (1 if both CD bits 2-3 are set)
     * bits 4-5: Battery status (from register bits 0-1)
     * bit 6: From register bit 4
     * bit 7: Ready status (from register bit 5)
     */
    return ((regValue & 0x0C) == 0x0C) |           /* bit 0: CD status */
           ((unsigned char)(regValue & 3) << 4) |   /* bits 4-5: battery */
           ((unsigned char)((regValue >> 4) & 1) << 6) |  /* bit 6 */
           ((unsigned char)((regValue >> 5) & 1) << 7);   /* bit 7: ready */
}

/*
 * Set card enabled state
 * Sets bit 7 in Power and RESETDRV Control register
 */
- (void)setCardEnabled:(unsigned int)enabled
{
    unsigned char regValue;
    char socketOffset;

    /* Read current Power and RESETDRV Control register */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    regValue = inb(reg_base + 1);

    /* Write back with bit 7 set according to enabled parameter */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    outb(reg_base + 1, (regValue & 0x7F) | (enabled << 7));
}

/*
 * Set card VCC power level
 * Sets bit 4 in Power and RESETDRV Control register
 */
- (void)setCardVccPower:(unsigned int)power
{
    unsigned char regValue;
    char socketOffset;

    /* Read current Power and RESETDRV Control register */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    regValue = inb(reg_base + 1);

    /* Write back with bit 4 set according to power parameter */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    outb(reg_base + 1, (regValue & 0xEF) | (((unsigned char)power & 1) << 4));
}

/*
 * Set card VPP power level
 * Sets lower 2 bits in Power and RESETDRV Control register
 */
- (void)setCardVppPower:(unsigned int)power
{
    unsigned char regValue;
    char socketOffset;

    /* Read current Power and RESETDRV Control register */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    regValue = inb(reg_base + 1);

    /* Write back with lower 2 bits set to VPP power level */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    outb(reg_base + 1, (regValue & 0xFC) | ((unsigned char)power & 3));
}

/*
 * Set card auto power state
 * Sets bit 5 in Power and RESETDRV Control register
 */
- (void)setCardAutoPower:(unsigned int)autoPower
{
    unsigned char regValue;
    char socketOffset;

    /* Read current Power and RESETDRV Control register */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    regValue = inb(reg_base + 1);

    /* Write back with bit 5 set according to autoPower parameter */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x02);
    outb(reg_base + 1, (regValue & 0xDF) | ((autoPower & 1) << 5));
}

/*
 * Set card IRQ number
 * Sets lower 4 bits in Interrupt and General Control register
 */
- (void)setCardIRQ:(unsigned int)irq
{
    unsigned char regValue;
    char socketOffset;

    /* Read current Interrupt and General Control register */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x03);
    regValue = inb(reg_base + 1);

    /* Write back with lower 4 bits set to IRQ number */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x03);
    outb(reg_base + 1, (regValue & 0xF0) | ((unsigned char)irq & 0x0F));
}

/*
 * Set card reset state
 * Sets bit 6 in Interrupt and General Control register (inverted logic)
 */
- (void)setCardReset:(unsigned int)reset
{
    char socketOffset;

    /* Write to Interrupt and General Control register */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x03);

    /* Write inverted reset value to bit 6 */
    /* If reset == 1, bit 6 = 0 (reset active) */
    /* If reset != 1, bit 6 = 1 (reset inactive) */
    outb(reg_base + 1, (reset != 1) << 6);
}

/*
 * Set memory interface type
 * Sets bit 5 in Interrupt and General Control register (inverted logic)
 */
- (void)setMemoryInterface:(unsigned int)interface
{
    unsigned char regValue;
    char socketOffset;

    /* Read current Interrupt and General Control register */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x03);
    regValue = inb(reg_base + 1);

    /* Write back with bit 5 set according to inverted interface parameter */
    /* If interface == 0, bit 5 = 1 (memory only) */
    /* If interface != 0, bit 5 = 0 (memory and I/O) */
    socketOffset = (char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x03);
    outb(reg_base + 1, (regValue & 0xDF) | ((interface == 0) << 5));
}

/*
 * Set status change mask
 * Configures Card Status Change Interrupt Enable register
 */
- (void)setStatusChangeMask:(unsigned int)mask
{
    unsigned char readyBit;
    unsigned char batteryBits;
    unsigned char irq;
    char socketOffset;

    /* Store mask at offset 0xc */
    statusChangeMask = mask;

    /* Extract bit 7 (READY status change) */
    readyBit = (unsigned char)(mask >> 7) & 1;

    /* Check if bits 4-5 are set (battery status changes) */
    batteryBits = ((unsigned char)mask & 0x30) != 0;

    /* Get IRQ number from adapter */
    irq = (unsigned char)[adapter interrupt];

    /* Write to Card Status Change Interrupt Enable register: (socket * 64) + 5 */
    socketOffset = (unsigned char)(socketNumber << 6);
    outb(reg_base, socketOffset + 0x05);

    /* Build register value:
     * bit 3: CD status change enable (bit 0 of mask)
     * bit 2: READY status change enable (bit 7 of mask)
     * bit 1: Battery warning status change enable (bits 4-5 of mask)
     * bit 0: Battery dead status change enable (bits 4-5 of mask)
     * bits 4-7: IRQ number
     */
    outb(reg_base + 1,
         (((unsigned char)mask & 1) != 0) << 3 |  /* CD change */
         readyBit << 2 |                           /* READY change */
         batteryBits << 1 |                        /* Battery warning */
         batteryBits |                             /* Battery dead */
         irq << 4);                                /* IRQ number */
}

/*
 * Reset the socket
 * Currently a no-op
 */
- (void)reset
{
    /* No operation - reset not implemented */
    return;
}

@end
