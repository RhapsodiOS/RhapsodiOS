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
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <machdep/i386/io_inline.h>
#import <objc/List.h>
#import <bsd/sys/types.h>

/* Global base port register (used by internal functions) */
unsigned int reg_base = 0;

/* Internal helper functions */
static char socketIsValid(unsigned int socket);
static unsigned char checkForCirrusChip(void);
static void setStatusChangeInterrupt(unsigned int socket, unsigned int irq);

@implementation PCIC_PCI

/*
 * Initialize from device description
 * Reads the bridge's I/O base out of PCI base address register 0, publishes it
 * as the port range, and lets PCIC drive the adapter from there
 */
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned char device, bus;
    IORange range;

    /* Locate the bridge; the function number is not wanted */
    if ([deviceDescription getPCIdevice:&device function:0 bus:&bus]) {
        return [super free];
    }

    IOLog("PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)\n",
          device, bus);

    /* BAR0 carries the I/O base; mask off the two base address type bits */
    [IODirectDevice getPCIConfigData:(unsigned long *)&reg_base
                          atRegister:0x10
               withDeviceDescription:deviceDescription];
    reg_base &= 0xfffc;

    /* The PD6832 exposes four ports, not the two the ISA path asks for */
    range.start = reg_base;
    range.size = 4;
    [deviceDescription setPortRangeList:&range num:1];

    if (![super initFromDeviceDescription:deviceDescription]) {
        return [super free];
    }

    return self;
}

@end

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
    int i;

    /* The adapter's index/data pair is the first port range */
    range = [(IOEISADeviceDescription *)deviceDescription portRangeList];
    reg_base = range->start;

    /* Validate socket 0 exists (basic hardware check) */
    if (!socketIsValid(0)) {
        IOLog("PCIC: No device at base address 0x%04x\n", reg_base);
        return [self free];
    }

    /* Call superclass initialization */
    if (![super initFromDeviceDescription:deviceDescription]) {
        return [super free];
    }

    /* Set device name and properties */
    [self setName:"PCIC"];
    [self setDeviceKind:"PCMCIA Adapter"];
    [self setUnit:0];

    sockets = [[List alloc] init];
    windows = [[List alloc] init];

    /* Create up to 4 sockets and collect their windows */
    for (i = 0; i < 4; i++) {
        socket = [[PCICSocket alloc] initWithAdapter:self socketNumber:i];
        if (!socket) {
            break;
        }

        /* Add socket to socket list */
        [sockets addObject:socket];

        /* Append the socket's windows to the master window list */
        [windows appendList:[socket windows]];
    }

    /* No socket answered: give the list back and fail */
    if ([sockets count] == 0) {
        [sockets free];
        [self free];
        return nil;
    }

    /* Check for Cirrus Logic chip */
    CirrusCompatible = checkForCirrusChip();

    /* Set up status change interrupts for each socket */
    for (i = 0; i < [sockets count]; i++) {
        setStatusChangeInterrupt(i, [deviceDescription interrupt]);
    }

    /* Interrupt enabling is not fatal; the IO thread starts either way */
    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        IOLog("PCIC: couldn't enable interrupts\n");
    }

    /* Start I/O thread */
    if ([self startIOThread] != IO_R_SUCCESS) {
        IOLog("PCIC: couldn't start IO thread\n");
        [self free];
        return nil;
    }

    /* Register device with system */
    [self registerDevice];

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
    count = [sockets count];

    /* Check each socket for status changes */
    for (i = 0; i < count; i++) {
        /* Get socket object */
        socket = [sockets objectAt:i];

        /* Calculate register offset: socket * 0x40 + 0x04 (Card Status Change register) */
        regOffset = (i << 6) + 0x04;

        /* Read from base port with calculated offset */
        outb(reg_base, regOffset);
        statusByte = inb(reg_base + 1);

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
            if (statusHandler) {
                [statusHandler statusChangedForSocket:socket changedStatus:changedStatus];
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
    return sockets;
}

/*
 * Get window list
 * Returns the List of PCICWindow objects (offset 0x130 / 304)
 */
- windows
{
    return windows;
}

/*
 * Set status change handler
 * Stores the handler object at offset 0x134
 * The handler will be called by interruptOccurred with statusChangedForSocket:changedStatus:
 */
- (void)setStatusChangeHandler:handler
{
    statusHandler = handler;
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
        count = [sockets count];
        for (i = 0; i < count; i++) {
            socket = [sockets objectAt:i];

            /* Disable card */
            [socket setCardEnabled:0];

            /* Turn off VCC power */
            [socket setCardVccPower:0];

            /* Disable all windows for this socket */
            windowCount = [windows count];
            for (j = 0; j < windowCount; j++) {
                window = [windows objectAt:j];
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
static char socketIsValid(unsigned int socket)
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
static unsigned char checkForCirrusChip(void)
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
static void setStatusChangeInterrupt(unsigned int socket, unsigned int irq)
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
