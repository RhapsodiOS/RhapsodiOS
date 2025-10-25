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
 * Intel 82365 PCMCIA Controller Driver Implementation
 */

#import "PCIC.h"
#import "PCICSocket.h"
#import "PCICWindow.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <machdep/i386/io_inline.h>
#import <objc/List.h>
#import <bsd/sys/types.h>

/* Global base port register (used by internal functions) */
unsigned int reg_base = 0;

/* Internal helper functions */
static char _socketIsValid(unsigned int socket);
static unsigned char _checkForCirrusChip(void);
static void _setStatusChangeInterrupt(unsigned int socket, unsigned int irq);

@implementation PCIC

/*
 * Device style
 * Returns 0 (default device style)
 */
+ (int)deviceStyle
{
    return 0;
}

/*
 * Probe for Intel 82365 compatible PCMCIA controller
 * Allocates and initializes an instance
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id instance;
    int result;

    /* Allocate and initialize an instance */
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];

    /* Check if initialization succeeded */
    result = (instance != nil);

    return result;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IORange *range;
    id socket;
    id socketWindows;
    int i;

    /* Get port range list and validate */
    range = [deviceDescription resourcesForKey:"I/O Ports"];
    if (!range) {
        IOLog("PCIC: No I/O port range specified\n");
        [self free];
        return nil;
    }
    basePort = range->start;

    /* Set global base register for internal functions */
    reg_base = basePort;

    /* Validate socket 0 exists (basic hardware check) */
    if (!_socketIsValid(0)) {
        IOLog("PCIC: Hardware validation failed at port 0x%x\n", basePort);
        [self free];
        return nil;
    }

    /* Call superclass initialization */
    if (![super initFromDeviceDescription:deviceDescription]) {
        [super free];
        return nil;
    }

    /* Set device name and properties */
    [self setName:"PCIC"];
    [self setDeviceKind:"PCMCIA Adapter"];
    [self setUnit:0];

    /* Get IRQ level */
    irqLevel = [deviceDescription interrupt];
    if (irqLevel == 0) {
        irqLevel = 5; /* Default IRQ */
    }

    /* Create socket list */
    socketList = [[List alloc] init];
    if (!socketList) {
        IOLog("PCIC: Failed to create socket list\n");
        [self free];
        return nil;
    }

    /* Create window list */
    windowList = [[List alloc] init];
    if (!windowList) {
        IOLog("PCIC: Failed to create window list\n");
        [self free];
        return nil;
    }

    /* Create up to 4 sockets and collect their windows */
    for (i = 0; i < 4; i++) {
        socket = [[PCICSocket alloc] initWithAdapter:self socketNumber:i];
        if (!socket) {
            break;
        }

        /* Add socket to socket list */
        [socketList addObject:socket];

        /* Get socket's window list and append to master window list */
        socketWindows = [socket windows];
        if (socketWindows) {
            [windowList appendList:socketWindows];
        }
    }

    /* Check if we successfully created any sockets */
    if ([socketList count] == 0) {
        IOLog("PCIC: Failed to create any sockets\n");
        [self free];
        return nil;
    }

    /* Store actual number of sockets created */
    numSockets = [socketList count];

    /* Check for Cirrus Logic chip */
    isCirrusChip = _checkForCirrusChip();

    /* Set up status change interrupts for each socket */
    for (i = 0; i < [socketList count]; i++) {
        _setStatusChangeInterrupt(i, irqLevel);
    }

    /* Enable all interrupts */
    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        IOLog("PCIC: couldn't enable interrupts\n");
        [self free];
        return nil;
    }

    /* Start I/O thread */
    if ([self startIOThread] != IO_R_SUCCESS) {
        IOLog("PCIC: couldn't start IO thread\n");
        [self free];
        return nil;
    }

    /* Register device with system */
    [self registerDevice];

    IOLog("PCIC: Initialized at port 0x%x, IRQ %d, %d sockets%s\n",
          basePort, irqLevel, numSockets, isCirrusChip ? " (Cirrus)" : "");

    return self;
}

/*
 * Interrupt handler
 * Reads card status change registers and notifies the status change handler
 */
- (void)interruptOccurred
{
    unsigned int i, count;
    unsigned char statusByte;
    unsigned char changedStatus;
    id socket;
    unsigned char regOffset;

    /* Get number of sockets */
    count = [socketList count];

    /* Check each socket for status changes */
    for (i = 0; i < count; i++) {
        /* Get socket object */
        socket = [socketList objectAt:i];

        /* Calculate register offset: socket * 0x40 + 0x04 (Card Status Change register) */
        regOffset = (i << 6) + 0x04;

        /* Read from base port with calculated offset */
        outb(basePort, regOffset);
        statusByte = inb(basePort + 1);

        /* If any status change bits are set */
        if (statusByte != 0) {
            /* Reformat status bits:
             * Original bits -> New position:
             * bit 0 (BATTDEAD) -> bit 4
             * bit 1 (BATTWARN) -> bit 4 (OR'd)
             * bit 2 (READY)    -> bit 7
             * bit 3 (CD)       -> bit 0
             */
            changedStatus = (((statusByte >> 2) & 1) << 7) |  /* bit 2 -> bit 7 */
                           ((statusByte >> 3) & 1) |          /* bit 3 -> bit 0 */
                           (((statusByte >> 1) & 1) | (statusByte & 1)) << 4;  /* bits 0,1 -> bit 4 */

            /* Call status change handler if registered */
            if (statusChangeHandler) {
                [statusChangeHandler statusChangedForSocket:socket changedStatus:changedStatus];
            }
        }
    }
}

/*
 * Get interrupt number from device description
 * Returns the IRQ number assigned to this controller
 */
- (unsigned int)interrupt
{
    id deviceDesc;

    deviceDesc = [self deviceDescription];
    return [deviceDesc interrupt];
}

/*
 * Get socket list
 * Returns the List of PCICSocket objects (offset 0x12C / 300)
 */
- sockets
{
    return socketList;
}

/*
 * Get window list
 * Returns the List of PCICWindow objects (offset 0x130 / 304)
 */
- windows
{
    return windowList;
}

/*
 * Set status change handler
 * Stores the handler object at offset 0x134
 * The handler will be called by interruptOccurred with statusChangedForSocket:changedStatus:
 */
- (void)setStatusChangeHandler:handler
{
    statusChangeHandler = handler;
}

/*
 * Set power management flags
 * Returns IO_R_UNSUPPORTED (not implemented in original binary)
 */
- (IOReturn)setPowerManagement:(int)flags
{
    return IO_R_UNSUPPORTED;
}

/*
 * Set system-wide power state
 * Based on decompiled implementation
 * Power state 3 disables all sockets and windows
 */
- (IOReturn)setPowerState:(int)powerState
{
    unsigned int i, count;
    unsigned int j, windowCount;
    id socket;
    id window;

    /* If power state is 3 (sleep/suspend), disable everything */
    if (powerState == 3) {
        /* Disable all sockets */
        count = [socketList count];
        for (i = 0; i < count; i++) {
            socket = [socketList objectAt:i];

            /* Disable card */
            [socket setCardEnabled:0];

            /* Turn off VCC power */
            [socket setCardVccPower:0];

            /* Disable all windows for this socket */
            windowCount = [windowList count];
            for (j = 0; j < windowCount; j++) {
                window = [windowList objectAt:j];
                [window setEnabled:0];
            }
        }
    }

    return IO_R_SUCCESS;
}

/*
 * Get power management flags
 * Returns IO_R_UNSUPPORTED (not implemented in original binary)
 */
- (IOReturn)getPowerManagement:(int *)flags
{
    return IO_R_UNSUPPORTED;
}

/*
 * Get power state
 * Returns IO_R_UNSUPPORTED (not implemented in original binary)
 */
- (IOReturn)getPowerState:(int *)state
{
    return IO_R_UNSUPPORTED;
}

@end

/*
 * Internal Helper Functions Implementation
 */

/*
 * Check if socket is valid by reading hardware
 * Returns 1 if valid, 0 if invalid
 * Based on decompiled implementation
 */
static char _socketIsValid(unsigned int socket)
{
    unsigned char regValue;
    unsigned char regOffset;

    /* Calculate register offset: socket * 0x40 */
    regOffset = socket << 6;

    /* Write register offset to index port */
    outb(reg_base, regOffset);

    /* Read register value from data port */
    regValue = inb(reg_base + 1);

    /* Check if socket is valid:
     * - Lower 4 bits must be > 1
     * - Bits 4-5 must be 0
     */
    if (((regValue & 0x0F) > 1) && ((regValue & 0x30) == 0)) {
        return 1;
    }

    return 0;
}

/*
 * Check for Cirrus Logic chip
 * Returns 1 if Cirrus chip detected, 0 otherwise
 */
static unsigned char _checkForCirrusChip(void)
{
    unsigned char value;
    unsigned short dataPort;

    dataPort = reg_base + 1;

    /* Write to register 0x1f (Cirrus-specific test register) */
    outb(reg_base, 0x1f);

    /* Write 0 to data port */
    outb(dataPort, 0);

    /* Write to register 0x1f again */
    outb(reg_base, 0x1f);

    /* Read from data port */
    value = inb(dataPort);

    /* Check if bits 6-7 are both set (0xc0) */
    if ((value & 0xc0) == 0xc0) {
        /* Write to register 0x1f again */
        outb(reg_base, 0x1f);

        /* Read from data port */
        value = inb(dataPort);

        /* Check if bits 6-7 are both clear */
        if ((value & 0xc0) == 0) {
            return 1;  /* Cirrus chip detected */
        }
    }

    return 0;  /* Not a Cirrus chip */
}

/*
 * Set status change interrupt for a socket
 * Configures the interrupt handling for card status changes
 */
static void _setStatusChangeInterrupt(unsigned int socket, unsigned int irq)
{
    unsigned char regOffset;
    unsigned char value;

    /* Calculate register offset: (socket * 64) + 5 */
    /* Register 5 is the Card Status Change Enable register */
    regOffset = (socket << 6) + 0x05;

    /* Write register offset to index port */
    outb(reg_base, regOffset);

    /* Write value to data port:
     * Upper nibble: IRQ number (irq << 4)
     * Lower nibble: Enable all status change interrupts (0x0f)
     */
    value = (irq << 4) | 0x0f;
    outb(reg_base + 1, value);
}

/*
 * Configure an I/O window
 * Sets up PCIC registers for I/O window mapping
 */
void _setIoWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr)
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

/*
 * Configure a memory window
 * Sets up PCIC registers for memory window mapping
 */
void _setMemoryWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr)
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
