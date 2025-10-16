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
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/PCMCIAKernBus.h>
#import <machkit/NXLock.h>
#import <objc/List.h>
#import <bsd/sys/types.h>

#define PCIC_INDEX_PORT    0x00
#define PCIC_DATA_PORT     0x01

@implementation PCIC

/*
 * Probe for Intel 82365 compatible PCMCIA controller
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    unsigned int port;
    unsigned char id;
    IORange *range;

    /* Get I/O port base from device description */
    range = [deviceDescription portRangeList];
    if (!range) {
        IOLog("PCIC: No I/O port range specified\n");
        return NO;
    }

    port = range->start;

    /* Try to read the chip ID/revision register */
    outb(port + PCIC_INDEX_PORT, PCIC_ID_REVISION);
    id = inb(port + PCIC_DATA_PORT);

    /* Check for valid ID (Intel 82365 or compatible) */
    if ((id & 0xC0) == 0x80) {
        IOLog("PCIC: Intel 82365 PCMCIA controller detected (ID: 0x%02x)\n", id);
        return YES;
    }

    return NO;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IORange *range;
    const char *irqStr;
    int i;

    [super initFromDeviceDescription:deviceDescription];

    /* Get I/O port base */
    range = [deviceDescription portRangeList];
    if (!range) {
        IOLog("PCIC: No I/O port range specified\n");
        [self free];
        return nil;
    }
    basePort = range->start;

    /* Get IRQ level */
    irqStr = [deviceDescription interrupt];
    if (irqStr) {
        irqLevel = atoi(irqStr);
    } else {
        irqLevel = 5; /* Default IRQ */
    }

    /* Detect number of sockets (typically 2 for 82365) */
    numSockets = 2;

    /* Allocate card presence tracking array */
    cardPresent = (BOOL *)IOMalloc(numSockets * sizeof(BOOL));
    if (!cardPresent) {
        IOLog("PCIC: Failed to allocate card presence array\n");
        [self free];
        return nil;
    }

    /* Initialize card presence state */
    for (i = 0; i < numSockets; i++) {
        cardPresent[i] = NO;
    }

    /* Allocate device tracking lists */
    deviceList = (id *)IOMalloc(numSockets * sizeof(id));
    if (!deviceList) {
        IOLog("PCIC: Failed to allocate device list array\n");
        [self free];
        return nil;
    }
    for (i = 0; i < numSockets; i++) {
        deviceList[i] = [[List alloc] init];
        if (!deviceList[i]) {
            IOLog("PCIC: Failed to create device list for socket %d\n", i);
            [self free];
            return nil;
        }
    }

    /* Allocate window tracking bitmaps */
    memWindowsAllocated = (unsigned char *)IOMalloc(numSockets * sizeof(unsigned char));
    ioWindowsAllocated = (unsigned char *)IOMalloc(numSockets * sizeof(unsigned char));
    if (!memWindowsAllocated || !ioWindowsAllocated) {
        IOLog("PCIC: Failed to allocate window tracking arrays\n");
        [self free];
        return nil;
    }
    for (i = 0; i < numSockets; i++) {
        memWindowsAllocated[i] = 0;
        ioWindowsAllocated[i] = 0;
    }

    /* Create lock for thread-safe access */
    lock = [[NXLock alloc] init];
    if (!lock) {
        IOLog("PCIC: Failed to create lock\n");
        [self free];
        return nil;
    }

    /* Create PCMCIA bus instance */
    pcmciaBus = [[PCMCIAKernBus alloc] initWithSocketCount:numSockets];
    if (!pcmciaBus) {
        IOLog("PCIC: Failed to create PCMCIA bus\n");
        [self free];
        return nil;
    }

    /* Initialize each socket */
    for (i = 0; i < numSockets; i++) {
        [self resetSocket:i];
        [self enableSocket:i];
    }

    /* Register interrupt handler */
    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        IOLog("PCIC: Failed to enable interrupts\n");
        [self free];
        return nil;
    }

    IOLog("PCIC: Initialized at port 0x%x, IRQ %d, %d sockets\n",
          basePort, irqLevel, numSockets);

    /* Register with DriverKit */
    [self registerDevice];

    /* Probe all sockets for already-inserted cards */
    for (i = 0; i < numSockets; i++) {
        unsigned int status;
        [self getSocketStatus:i status:&status];
        if (status & 0x01) {
            /* Card is present, trigger detection */
            cardPresent[i] = YES;
            [self cardStatusChangeHandler:i];
        }
    }

    return self;
}

/*
 * Free resources
 */
- free
{
    int i;

    /* Disable all sockets */
    for (i = 0; i < numSockets; i++) {
        [self disableSocket:i];
        [self removeAllDevicesFromSocket:i];
        [self freeAllWindowsForSocket:i];
    }

    /* Free device tracking lists */
    if (deviceList) {
        for (i = 0; i < numSockets; i++) {
            if (deviceList[i]) {
                [deviceList[i] free];
            }
        }
        IOFree(deviceList, numSockets * sizeof(id));
        deviceList = NULL;
    }

    /* Free window tracking arrays */
    if (memWindowsAllocated) {
        IOFree(memWindowsAllocated, numSockets * sizeof(unsigned char));
        memWindowsAllocated = NULL;
    }
    if (ioWindowsAllocated) {
        IOFree(ioWindowsAllocated, numSockets * sizeof(unsigned char));
        ioWindowsAllocated = NULL;
    }

    /* Free PCMCIA bus */
    if (pcmciaBus) {
        [pcmciaBus free];
        pcmciaBus = nil;
    }

    /* Free lock */
    if (lock) {
        [lock free];
        lock = nil;
    }

    /* Free card presence array */
    if (cardPresent) {
        IOFree(cardPresent, numSockets * sizeof(BOOL));
        cardPresent = NULL;
    }

    return [super free];
}

/*
 * Read PCIC register
 */
- (unsigned char)readRegister:(unsigned int)socket offset:(unsigned int)offset
{
    unsigned int reg;

    /* Calculate register address (socket * 0x40 + offset) */
    reg = (socket * 0x40) + offset;

    outb(basePort + PCIC_INDEX_PORT, reg);
    return inb(basePort + PCIC_DATA_PORT);
}

/*
 * Write PCIC register
 */
- (void)writeRegister:(unsigned int)socket offset:(unsigned int)offset value:(unsigned char)value
{
    unsigned int reg;

    /* Calculate register address (socket * 0x40 + offset) */
    reg = (socket * 0x40) + offset;

    outb(basePort + PCIC_INDEX_PORT, reg);
    outb(basePort + PCIC_DATA_PORT, value);
}

/*
 * Set power state for a socket
 */
- (IOReturn)setPowerState:(unsigned int)socket state:(unsigned int)state
{
    unsigned char power = 0;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Configure power based on requested state */
    if (state & PCMCIA_VCC_5V) {
        power |= PCIC_POWER_VCC_5V;
    } else if (state & PCMCIA_VCC_3V) {
        power |= PCIC_POWER_VCC_3V;
    }

    if (state & PCMCIA_VPP1_5V) {
        power |= PCIC_POWER_VPP1_5V;
    } else if (state & PCMCIA_VPP1_12V) {
        power |= PCIC_POWER_VPP1_12V;
    }

    if (state & PCMCIA_VPP2_5V) {
        power |= PCIC_POWER_VPP2_5V;
    } else if (state & PCMCIA_VPP2_12V) {
        power |= PCIC_POWER_VPP2_12V;
    }

    /* Enable output if any power requested */
    if (power)
        power |= PCIC_POWER_OUTPUT_ENA;

    [self writeRegister:socket offset:PCIC_POWER value:power];

    /* Wait for power stabilization */
    IOSleep(250);

    return IO_R_SUCCESS;
}

/*
 * Get power state for a socket
 */
- (IOReturn)getPowerState:(unsigned int)socket state:(unsigned int *)state
{
    unsigned char power;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    power = [self readRegister:socket offset:PCIC_POWER];

    *state = 0;
    if (power & PCIC_POWER_VCC_5V)
        *state |= PCMCIA_VCC_5V;
    if (power & PCIC_POWER_VCC_3V)
        *state |= PCMCIA_VCC_3V;
    if (power & PCIC_POWER_VPP1_5V)
        *state |= PCMCIA_VPP1_5V;
    if (power & PCIC_POWER_VPP1_12V)
        *state |= PCMCIA_VPP1_12V;
    if (power & PCIC_POWER_VPP2_5V)
        *state |= PCMCIA_VPP2_5V;
    if (power & PCIC_POWER_VPP2_12V)
        *state |= PCMCIA_VPP2_12V;

    return IO_R_SUCCESS;
}

/*
 * Set memory window mapping
 */
- (IOReturn)setMemoryWindow:(unsigned int)window
                     socket:(unsigned int)socket
                       base:(unsigned int)base
                       size:(unsigned int)size
                     offset:(unsigned int)offset
                      flags:(unsigned int)flags
{
    unsigned int regBase;
    unsigned char val;

    if (socket >= numSockets || window >= 5)
        return IO_R_INVALID_ARG;

    regBase = PCIC_MEM_WINDOW_0 + (window * 8);

    /* Set window start address */
    val = (base >> 12) & 0xFF;
    [self writeRegister:socket offset:regBase + 0 value:val];
    val = (base >> 20) & 0x0F;
    if (flags & 0x01) /* 16-bit window */
        val |= 0x80;
    [self writeRegister:socket offset:regBase + 1 value:val];

    /* Set window end address */
    val = ((base + size - 1) >> 12) & 0xFF;
    [self writeRegister:socket offset:regBase + 2 value:val];
    val = ((base + size - 1) >> 20) & 0x0F;
    [self writeRegister:socket offset:regBase + 3 value:val];

    /* Set card offset */
    val = (offset >> 12) & 0xFF;
    [self writeRegister:socket offset:regBase + 4 value:val];
    val = (offset >> 20) & 0x3F;
    if (flags & 0x02) /* Write-protect */
        val |= 0x80;
    if (flags & 0x04) /* Attribute memory */
        val |= 0x40;
    [self writeRegister:socket offset:regBase + 5 value:val];

    /* Mark window as allocated */
    memWindowsAllocated[socket] |= (1 << window);

    return IO_R_SUCCESS;
}

/*
 * Set I/O window mapping
 */
- (IOReturn)setIOWindow:(unsigned int)window
                 socket:(unsigned int)socket
                   base:(unsigned int)base
                   size:(unsigned int)size
                  flags:(unsigned int)flags
{
    unsigned int regBase;
    unsigned char val;

    if (socket >= numSockets || window >= 2)
        return IO_R_INVALID_ARG;

    regBase = PCIC_IO_WINDOW_0 + (window * 8);

    /* Set window start address */
    val = base & 0xFF;
    [self writeRegister:socket offset:regBase + 0 value:val];
    val = (base >> 8) & 0xFF;
    [self writeRegister:socket offset:regBase + 1 value:val];

    /* Set window end address */
    val = (base + size - 1) & 0xFF;
    [self writeRegister:socket offset:regBase + 2 value:val];
    val = ((base + size - 1) >> 8) & 0xFF;
    [self writeRegister:socket offset:regBase + 3 value:val];

    /* Mark window as allocated */
    ioWindowsAllocated[socket] |= (1 << window);

    return IO_R_SUCCESS;
}

/*
 * Get socket status
 */
- (IOReturn)getSocketStatus:(unsigned int)socket status:(unsigned int *)status
{
    unsigned char stat;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    stat = [self readRegister:socket offset:PCIC_STATUS];

    *status = 0;
    if ((stat & (PCIC_STATUS_CD1 | PCIC_STATUS_CD2)) == (PCIC_STATUS_CD1 | PCIC_STATUS_CD2))
        *status |= 0x01; /* Card detected */
    if (stat & PCIC_STATUS_READY)
        *status |= 0x02; /* Card ready */
    if (stat & PCIC_STATUS_POWER)
        *status |= 0x04; /* Power active */

    return IO_R_SUCCESS;
}

/*
 * Reset socket
 */
- (IOReturn)resetSocket:(unsigned int)socket
{
    unsigned char ctrl;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Assert reset */
    ctrl = [self readRegister:socket offset:PCIC_INT_GEN_CTRL];
    ctrl |= PCIC_IGCTRL_CARD_RESET;
    [self writeRegister:socket offset:PCIC_INT_GEN_CTRL value:ctrl];

    IOSleep(10);

    /* Deassert reset */
    ctrl &= ~PCIC_IGCTRL_CARD_RESET;
    [self writeRegister:socket offset:PCIC_INT_GEN_CTRL value:ctrl];

    IOSleep(20);

    return IO_R_SUCCESS;
}

/*
 * Enable socket
 */
- (IOReturn)enableSocket:(unsigned int)socket
{
    unsigned char ctrl;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Enable management interrupt */
    ctrl = [self readRegister:socket offset:PCIC_INT_GEN_CTRL];
    ctrl |= PCIC_IGCTRL_INTR_ENA;
    ctrl = (ctrl & ~PCIC_IGCTRL_IRQ_MASK) | (irqLevel & PCIC_IGCTRL_IRQ_MASK);
    [self writeRegister:socket offset:PCIC_INT_GEN_CTRL value:ctrl];

    /* Enable card status change interrupts */
    [self enableCardStatusChangeInterrupts:socket];

    return IO_R_SUCCESS;
}

/*
 * Disable socket
 */
- (IOReturn)disableSocket:(unsigned int)socket
{
    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Disable card status change interrupts */
    [self disableCardStatusChangeInterrupts:socket];

    /* Disable management interrupts */
    [self writeRegister:socket offset:PCIC_INT_GEN_CTRL value:0];

    /* Power off */
    [self writeRegister:socket offset:PCIC_POWER value:0];

    return IO_R_SUCCESS;
}

/*
 * Interrupt handler
 */
- (void)interruptOccurred
{
    unsigned int i;
    unsigned char csc;

    /* Check each socket for status changes */
    for (i = 0; i < numSockets; i++) {
        csc = [self readRegister:i offset:PCIC_CARD_STATUS];

        if (csc & (PCIC_CSC_CD | PCIC_CSC_READY | PCIC_CSC_BATTWARN | PCIC_CSC_BATTDEAD)) {
            [self cardStatusChangeHandler:i];

            /* Clear interrupt */
            [self writeRegister:i offset:PCIC_CARD_STATUS value:csc];
        }
    }
}

/*
 * Card status change handler
 *
 * Called when a card insertion/removal event is detected.
 * This method handles the hardware state changes and notifies
 * the PCMCIA bus subsystem to probe/remove the card.
 */
- (void)cardStatusChangeHandler:(unsigned int)socket
{
    unsigned int status;
    BOOL isCardPresent;
    BOOL wasCardPresent;

    if (socket >= numSockets) {
        return;
    }

    /* Acquire lock for thread-safe access */
    [lock lock];

    /* Get current socket status */
    [self getSocketStatus:socket status:&status];
    isCardPresent = (status & 0x01) ? YES : NO;

    /* Get previous card presence state */
    wasCardPresent = cardPresent[socket];

    /* Check if this is a real state change */
    if (isCardPresent == wasCardPresent) {
        [lock unlock];
        return;  /* No change, spurious interrupt */
    }

    /* Update card presence state */
    cardPresent[socket] = isCardPresent;

    [lock unlock];

    /* Handle card insertion */
    if (isCardPresent && !wasCardPresent) {
        IOLog("PCIC: Card inserted in socket %d\n", socket);

        /* Wait for card to stabilize (debounce) */
        IOSleep(100);

        /* Detect card voltage requirements */
        unsigned int cardVoltage;
        if ([self detectCardVoltage:socket voltage:&cardVoltage] == IO_R_SUCCESS) {
            const char *voltageStr = [self getCardTypeString:cardVoltage];
            IOLog("PCIC: Detected %s in socket %d\n", voltageStr, socket);

            /* Apply appropriate voltage to the socket */
            if ([self setCardVoltage:socket voltage:cardVoltage] != IO_R_SUCCESS) {
                IOLog("PCIC: Failed to set voltage for socket %d\n", socket);
                [self setPowerState:socket state:0];
                [lock lock];
                cardPresent[socket] = NO;
                [lock unlock];
                return;
            }
        } else {
            IOLog("PCIC: Using default 5V power for socket %d\n", socket);
            /* Fall back to 5V */
            [self setPowerState:socket state:(PCMCIA_VCC_5V | PCMCIA_VPP1_5V)];
            IOSleep(250);
        }

        /* Reset the card */
        [self resetSocket:socket];

        /* Wait for card to be ready */
        if ([self waitForReady:socket timeout:PCIC_READY_TIMEOUT] != IO_R_SUCCESS) {
            IOLog("PCIC: Card in socket %d not ready after reset\n", socket);
            /* Continue anyway, card might not support ready signal */
        }

        /* Enable the socket */
        [self enableSocket:socket];

        /* Notify PCMCIA bus to probe the socket */
        if (pcmciaBus) {
            IOLog("PCIC: Probing socket %d for card information\n", socket);
            if ([pcmciaBus probeSocket:socket]) {
                IOLog("PCIC: Socket %d card successfully enumerated\n", socket);

                /* Dump registers for debugging */
                #ifdef DEBUG
                [self dumpRegisters:socket];
                #endif
            } else {
                IOLog("PCIC: Socket %d card probe failed\n", socket);
                /* Power down on probe failure */
                [self setPowerState:socket state:0];
            }
        }
    }
    /* Handle card removal */
    else if (!isCardPresent && wasCardPresent) {
        IOLog("PCIC: Card removed from socket %d\n", socket);

        /* Remove all device drivers attached to this socket */
        [self removeAllDevicesFromSocket:socket];

        /* Free all allocated windows for this socket */
        [self freeAllWindowsForSocket:socket];

        /* Disable socket interrupts */
        [self disableCardStatusChangeInterrupts:socket];

        /* Power down the socket */
        [self setPowerState:socket state:0];

        /* Notify PCMCIA bus about card removal */
        if (pcmciaBus) {
            id socketObj = [pcmciaBus socketAtIndex:socket];
            if (socketObj) {
                IOLog("PCIC: Notifying bus of card removal from socket %d\n", socket);
                /* The bus will handle cleaning up any remaining socket state */
                /* Card Information Structure (CIS) tuples will be freed by the bus */
            }
        }

        IOLog("PCIC: Socket %d cleanup complete\n", socket);

        /* Re-enable status change detection for future insertions */
        [self enableCardStatusChangeInterrupts:socket];
    }
}

/*
 * Enable card status change interrupts
 */
- (IOReturn)enableCardStatusChangeInterrupts:(unsigned int)socket
{
    unsigned char cscen;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Enable all card status change interrupts */
    cscen = PCIC_CSCEN_CD | PCIC_CSCEN_READY | PCIC_CSCEN_BATTWARN | PCIC_CSCEN_BATTDEAD;
    [self writeRegister:socket offset:PCIC_CARD_STATUS_CHG value:cscen];

    return IO_R_SUCCESS;
}

/*
 * Disable card status change interrupts
 */
- (IOReturn)disableCardStatusChangeInterrupts:(unsigned int)socket
{
    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Disable all card status change interrupts */
    [self writeRegister:socket offset:PCIC_CARD_STATUS_CHG value:0];

    return IO_R_SUCCESS;
}

/*
 * Detect card voltage from voltage sense pins
 * Returns voltage type based on VS1 and VS2 pins
 */
- (IOReturn)detectCardVoltage:(unsigned int)socket voltage:(unsigned int *)voltage
{
    unsigned char status;
    unsigned char vs1, vs2;

    if (socket >= numSockets || !voltage)
        return IO_R_INVALID_ARG;

    /* Read status register to get voltage sense pins */
    status = [self readRegister:socket offset:PCIC_STATUS];

    /* Extract VS1 and VS2 bits (bits 6 and 5) */
    vs1 = (status >> 6) & 0x01;
    vs2 = (status >> 5) & 0x01;

    /* Determine card type based on voltage sense pins
     * VS1=1, VS2=1: 5V card
     * VS1=0, VS2=1: 3.3V card
     * VS1=1, VS2=0: X.V card (low voltage)
     * VS1=0, VS2=0: Y.V card (low voltage)
     */
    if (vs1 && vs2) {
        *voltage = PCMCIA_CARD_TYPE_5V;
    } else if (!vs1 && vs2) {
        *voltage = PCMCIA_CARD_TYPE_3V;
    } else if (vs1 && !vs2) {
        *voltage = PCMCIA_CARD_TYPE_XV;
    } else {
        *voltage = PCMCIA_CARD_TYPE_YV;
    }

    return IO_R_SUCCESS;
}

/*
 * Set card voltage based on detected type
 */
- (IOReturn)setCardVoltage:(unsigned int)socket voltage:(unsigned int)voltage
{
    unsigned char power;
    unsigned char misc1;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Configure power based on voltage type */
    switch (voltage) {
        case PCMCIA_CARD_TYPE_5V:
            /* 5V card */
            power = PCIC_POWER_VCC_5V | PCIC_POWER_VPP1_5V;
            misc1 = 0;
            break;

        case PCMCIA_CARD_TYPE_3V:
            /* 3.3V card */
            power = PCIC_POWER_VCC_3V | PCIC_POWER_VPP1_5V;
            misc1 = PCIC_MISC1_VCC_33;
            break;

        case PCMCIA_CARD_TYPE_XV:
        case PCMCIA_CARD_TYPE_YV:
            /* Low voltage cards - use 3.3V */
            power = PCIC_POWER_VCC_3V;
            misc1 = PCIC_MISC1_VCC_33;
            break;

        default:
            return IO_R_INVALID_ARG;
    }

    /* Set misc control register for 3.3V if needed */
    if (misc1) {
        unsigned char current = [self readRegister:socket offset:PCIC_MISC_CTRL_1];
        current |= misc1;
        [self writeRegister:socket offset:PCIC_MISC_CTRL_1 value:current];
    }

    /* Enable power output */
    power |= PCIC_POWER_OUTPUT_ENA;

    /* Apply power */
    [self writeRegister:socket offset:PCIC_POWER value:power];

    /* Wait for power to stabilize */
    IOSleep(250);

    return IO_R_SUCCESS;
}

/*
 * Check if socket supports a specific voltage
 */
- (BOOL)supportsVoltage:(unsigned int)socket voltage:(unsigned int)voltage
{
    unsigned int detectedVoltage;

    if (socket >= numSockets)
        return NO;

    /* Detect actual card voltage */
    if ([self detectCardVoltage:socket voltage:&detectedVoltage] != IO_R_SUCCESS)
        return NO;

    /* Check if requested voltage matches detected voltage */
    return (voltage == detectedVoltage);
}

/*
 * Set command timing (setup and hold times)
 */
- (IOReturn)setCommandTiming:(unsigned int)socket setup:(unsigned int)setup hold:(unsigned int)hold
{
    unsigned char timing;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Read current timing register */
    timing = [self readRegister:socket offset:PCIC_TIMING_0];

    /* Clear and set command timing bits */
    timing &= ~0x03;
    if (setup == 0 && hold == 0) {
        timing |= PCIC_TIMING_COMMAND_FAST;
    } else if (setup == 1 && hold == 1) {
        timing |= PCIC_TIMING_COMMAND_MEDIUM;
    } else {
        timing |= PCIC_TIMING_COMMAND_SLOW;
    }

    /* Write timing register */
    [self writeRegister:socket offset:PCIC_TIMING_0 value:timing];

    return IO_R_SUCCESS;
}

/*
 * Set memory timing speed
 */
- (IOReturn)setMemoryTiming:(unsigned int)socket speed:(unsigned int)speed
{
    unsigned char timing;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Read current timing register */
    timing = [self readRegister:socket offset:PCIC_TIMING_0];

    /* Clear and set memory timing bits */
    timing &= ~0x30;
    switch (speed) {
        case 0:  /* Fast */
            timing |= PCIC_TIMING_MEMORY_FAST;
            break;
        case 1:  /* Medium */
            timing |= PCIC_TIMING_MEMORY_MEDIUM;
            break;
        default: /* Slow */
            timing |= PCIC_TIMING_MEMORY_SLOW;
            break;
    }

    /* Write timing register */
    [self writeRegister:socket offset:PCIC_TIMING_0 value:timing];

    return IO_R_SUCCESS;
}

/*
 * Get card type based on voltage sense pins
 */
- (IOReturn)getCardType:(unsigned int)socket type:(unsigned int *)type
{
    return [self detectCardVoltage:socket voltage:type];
}

/*
 * Get string representation of card type
 */
- (const char *)getCardTypeString:(unsigned int)type
{
    switch (type) {
        case PCMCIA_CARD_TYPE_5V:
            return "5V PC Card";
        case PCMCIA_CARD_TYPE_3V:
            return "3.3V CardBus/PC Card";
        case PCMCIA_CARD_TYPE_XV:
            return "X.V Card (Low Voltage)";
        case PCMCIA_CARD_TYPE_YV:
            return "Y.V Card (Low Voltage)";
        default:
            return "Unknown Card Type";
    }
}

/*
 * Force card ejection (power down and disable)
 */
- (IOReturn)forceCardEject:(unsigned int)socket
{
    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    IOLog("PCIC: Force ejecting card from socket %d\n", socket);

    /* Disable socket */
    [self disableSocket:socket];

    /* Power down */
    [self setPowerState:socket state:0];

    /* Update card presence state */
    [lock lock];
    cardPresent[socket] = NO;
    [lock unlock];

    /* Trigger card removal handler */
    [self cardStatusChangeHandler:socket];

    return IO_R_SUCCESS;
}

/*
 * Lock card (prevent removal)
 * Note: Not all hardware supports this feature
 */
- (IOReturn)lockCard:(unsigned int)socket
{
    unsigned char misc2;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Read misc control register 2 */
    misc2 = [self readRegister:socket offset:PCIC_MISC_CTRL_2];

    /* Set lock bit if supported */
    misc2 |= 0x01;  /* Lock enable bit */

    [self writeRegister:socket offset:PCIC_MISC_CTRL_2 value:misc2];

    IOLog("PCIC: Card locked in socket %d\n", socket);

    return IO_R_SUCCESS;
}

/*
 * Unlock card (allow removal)
 */
- (IOReturn)unlockCard:(unsigned int)socket
{
    unsigned char misc2;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Read misc control register 2 */
    misc2 = [self readRegister:socket offset:PCIC_MISC_CTRL_2];

    /* Clear lock bit */
    misc2 &= ~0x01;  /* Lock disable */

    [self writeRegister:socket offset:PCIC_MISC_CTRL_2 value:misc2];

    IOLog("PCIC: Card unlocked in socket %d\n", socket);

    return IO_R_SUCCESS;
}

/*
 * Wait for card to be ready with timeout
 */
- (IOReturn)waitForReady:(unsigned int)socket timeout:(unsigned int)timeout
{
    unsigned int elapsed = 0;
    unsigned char status;

    if (socket >= numSockets)
        return IO_R_INVALID_ARG;

    /* Wait for ready bit with timeout */
    while (elapsed < timeout) {
        status = [self readRegister:socket offset:PCIC_STATUS];

        if (status & PCIC_STATUS_READY) {
            return IO_R_SUCCESS;
        }

        IOSleep(10);
        elapsed += 10;
    }

    IOLog("PCIC: Timeout waiting for ready on socket %d\n", socket);
    return IO_R_TIMEOUT;
}

/*
 * Dump all registers for debugging
 */
- (void)dumpRegisters:(unsigned int)socket
{
    unsigned int i;
    unsigned char value;

    if (socket >= numSockets) {
        IOLog("PCIC: Invalid socket %d for register dump\n", socket);
        return;
    }

    IOLog("PCIC: Register dump for socket %d:\n", socket);
    IOLog("  ID/Revision:      0x%02x\n", [self readRegister:socket offset:PCIC_ID_REVISION]);
    IOLog("  Status:           0x%02x\n", [self readRegister:socket offset:PCIC_STATUS]);
    IOLog("  Power:            0x%02x\n", [self readRegister:socket offset:PCIC_POWER]);
    IOLog("  Int/Gen Ctrl:     0x%02x\n", [self readRegister:socket offset:PCIC_INT_GEN_CTRL]);
    IOLog("  Card Status:      0x%02x\n", [self readRegister:socket offset:PCIC_CARD_STATUS]);
    IOLog("  Card Status Chg:  0x%02x\n", [self readRegister:socket offset:PCIC_CARD_STATUS_CHG]);
    IOLog("  I/O Control:      0x%02x\n", [self readRegister:socket offset:PCIC_IO_CONTROL]);
    IOLog("  Misc Ctrl 1:      0x%02x\n", [self readRegister:socket offset:PCIC_MISC_CTRL_1]);
    IOLog("  Misc Ctrl 2:      0x%02x\n", [self readRegister:socket offset:PCIC_MISC_CTRL_2]);
    IOLog("  Timing 0:         0x%02x\n", [self readRegister:socket offset:PCIC_TIMING_0]);
    IOLog("  Timing 1:         0x%02x\n", [self readRegister:socket offset:PCIC_TIMING_1]);

    /* Dump memory windows */
    for (i = 0; i < 5; i++) {
        unsigned int regBase = PCIC_MEM_WINDOW_0 + (i * 8);
        IOLog("  Memory Window %d:  Start=0x%02x%02x End=0x%02x%02x Offset=0x%02x%02x\n",
              i,
              [self readRegister:socket offset:regBase + 1],
              [self readRegister:socket offset:regBase + 0],
              [self readRegister:socket offset:regBase + 3],
              [self readRegister:socket offset:regBase + 2],
              [self readRegister:socket offset:regBase + 5],
              [self readRegister:socket offset:regBase + 4]);
    }

    /* Dump I/O windows */
    IOLog("  I/O Window 0:     Start=0x%02x%02x End=0x%02x%02x\n",
          [self readRegister:socket offset:PCIC_IO_WINDOW_0_START_MSB],
          [self readRegister:socket offset:PCIC_IO_WINDOW_0_START_LSB],
          [self readRegister:socket offset:PCIC_IO_WINDOW_0_END_MSB],
          [self readRegister:socket offset:PCIC_IO_WINDOW_0_END_LSB]);
    IOLog("  I/O Window 1:     Start=0x%02x%02x End=0x%02x%02x\n",
          [self readRegister:socket offset:PCIC_IO_WINDOW_1_START_MSB],
          [self readRegister:socket offset:PCIC_IO_WINDOW_1_START_LSB],
          [self readRegister:socket offset:PCIC_IO_WINDOW_1_END_MSB],
          [self readRegister:socket offset:PCIC_IO_WINDOW_1_END_LSB]);
}

/*
 * Register a device driver instance for a socket
 * Called when a device driver is attached to a card
 */
- (void)registerDevice:device forSocket:(unsigned int)socket
{
    if (socket >= numSockets || !device) {
        IOLog("PCIC: Invalid socket or device in registerDevice\n");
        return;
    }

    [lock lock];

    if (deviceList[socket]) {
        [deviceList[socket] addObject:device];
        IOLog("PCIC: Registered device %s for socket %d\n",
              [device name] ? [device name] : "unknown", socket);
    }

    [lock unlock];
}

/*
 * Remove all devices from a socket
 * Called during card removal to cleanly detach all device drivers
 */
- (void)removeAllDevicesFromSocket:(unsigned int)socket
{
    int i, count;
    id device;

    if (socket >= numSockets) {
        IOLog("PCIC: Invalid socket in removeAllDevicesFromSocket\n");
        return;
    }

    [lock lock];

    if (deviceList[socket]) {
        count = [deviceList[socket] count];

        if (count > 0) {
            IOLog("PCIC: Removing %d device(s) from socket %d\n", count, socket);
        }

        /* Detach and free each device driver */
        for (i = count - 1; i >= 0; i--) {
            device = [deviceList[socket] objectAt:i];
            if (device) {
                IOLog("PCIC: Detaching device %s from socket %d\n",
                      [device name] ? [device name] : "unknown", socket);

                /* Tell the device it's being removed */
                if ([device respondsTo:@selector(willTerminate)]) {
                    [device willTerminate];
                }

                /* Remove from our tracking list */
                [deviceList[socket] removeObjectAt:i];

                /* The device will be freed by the system */
            }
        }
    }

    [lock unlock];
}

/*
 * Free a memory window
 */
- (IOReturn)freeMemoryWindow:(unsigned int)window socket:(unsigned int)socket
{
    unsigned int regBase;
    unsigned char mask;

    if (socket >= numSockets || window >= 5) {
        return IO_R_INVALID_ARG;
    }

    mask = 1 << window;

    /* Check if window is allocated */
    if (!(memWindowsAllocated[socket] & mask)) {
        return IO_R_SUCCESS;  /* Already free */
    }

    regBase = PCIC_MEM_WINDOW_0 + (window * 8);

    /* Disable the window by clearing its registers */
    [self writeRegister:socket offset:regBase + 0 value:0];
    [self writeRegister:socket offset:regBase + 1 value:0];
    [self writeRegister:socket offset:regBase + 2 value:0];
    [self writeRegister:socket offset:regBase + 3 value:0];
    [self writeRegister:socket offset:regBase + 4 value:0];
    [self writeRegister:socket offset:regBase + 5 value:0];

    /* Mark window as free */
    memWindowsAllocated[socket] &= ~mask;

    IOLog("PCIC: Freed memory window %d for socket %d\n", window, socket);

    return IO_R_SUCCESS;
}

/*
 * Free an I/O window
 */
- (IOReturn)freeIOWindow:(unsigned int)window socket:(unsigned int)socket
{
    unsigned int regBase;
    unsigned char mask;

    if (socket >= numSockets || window >= 2) {
        return IO_R_INVALID_ARG;
    }

    mask = 1 << window;

    /* Check if window is allocated */
    if (!(ioWindowsAllocated[socket] & mask)) {
        return IO_R_SUCCESS;  /* Already free */
    }

    regBase = PCIC_IO_WINDOW_0 + (window * 8);

    /* Disable the window by clearing its registers */
    [self writeRegister:socket offset:regBase + 0 value:0];
    [self writeRegister:socket offset:regBase + 1 value:0];
    [self writeRegister:socket offset:regBase + 2 value:0];
    [self writeRegister:socket offset:regBase + 3 value:0];

    /* Mark window as free */
    ioWindowsAllocated[socket] &= ~mask;

    IOLog("PCIC: Freed I/O window %d for socket %d\n", window, socket);

    return IO_R_SUCCESS;
}

/*
 * Free all windows for a socket
 * Called during card removal cleanup
 */
- (void)freeAllWindowsForSocket:(unsigned int)socket
{
    int i;

    if (socket >= numSockets) {
        IOLog("PCIC: Invalid socket in freeAllWindowsForSocket\n");
        return;
    }

    /* Free all memory windows */
    for (i = 0; i < 5; i++) {
        if (memWindowsAllocated[socket] & (1 << i)) {
            [self freeMemoryWindow:i socket:socket];
        }
    }

    /* Free all I/O windows */
    for (i = 0; i < 2; i++) {
        if (ioWindowsAllocated[socket] & (1 << i)) {
            [self freeIOWindow:i socket:socket];
        }
    }

    /* Disable I/O window control */
    [self writeRegister:socket offset:PCIC_IO_CONTROL value:0];

    IOLog("PCIC: Freed all windows for socket %d\n", socket);
}

@end
