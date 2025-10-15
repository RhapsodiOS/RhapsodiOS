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

/**
 * BusMouseDriver.m - ISA Bus Mouse Driver Implementation
 */

#import "BusMouseDriver.h"
#import "BusMouseRegs.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/i386/directDevice.h>
#import <kernserv/prototypes.h>

@implementation BusMouseDriver

/*
 * Detect mouse type at given port
 */
- (BusMouseType) detectMouseAtPort : (UInt16) port
{
    UInt8 value;

    /* Try Microsoft InPort detection */
    outb(port + INPORT_ADDR_REG, INPORT_REG_SIGNATURE1);
    IODelay(10);
    value = inb(port + INPORT_DATA_REG);

    if (value == INPORT_SIGNATURE_BYTE1) {
        outb(port + INPORT_ADDR_REG, INPORT_REG_SIGNATURE2);
        IODelay(10);
        value = inb(port + INPORT_DATA_REG);

        if (value == INPORT_SIGNATURE_BYTE2) {
            /* Check identification register */
            value = inb(port + INPORT_IDENT_REG);
            if (value == INPORT_ID_BYTE) {
                IOLog("BusMouse: Microsoft InPort mouse detected at 0x%x\n", port);
                return MOUSE_TYPE_INPORT;
            }
        }
    }

    /* Try Logitech bus mouse detection */
    value = inb(port + LOGITECH_SIGNATURE_REG);
    if (value == LOGITECH_SIGNATURE) {
        IOLog("BusMouse: Logitech bus mouse detected at 0x%x\n", port);
        return MOUSE_TYPE_LOGITECH;
    }

    /* Try reading as InPort anyway (ATI mice don't have proper signatures) */
    outb(port + INPORT_ADDR_REG, INPORT_REG_STATUS);
    IODelay(10);
    value = inb(port + INPORT_DATA_REG);

    /* If we can read/write the address register, assume InPort compatible */
    if (value != 0xFF) {
        IOLog("BusMouse: InPort-compatible mouse detected at 0x%x\n", port);
        return MOUSE_TYPE_ATI;
    }

    return MOUSE_TYPE_UNKNOWN;
}

/*
 * Probe for bus mouse hardware
 */
+ (Boolean) probe : deviceDescription
{
    BusMouseDriver *driver;
    UInt16 port = INPORT_PRIMARY;
    const char *portStr;
    BusMouseType mouseType;

    /* Get port address from device description if specified */
    portStr = [deviceDescription valueForStringKey:"Port"];
    if (portStr) {
        port = strtoul(portStr, NULL, 16);
    }

    /* Create driver instance for detection */
    driver = [self alloc];
    if (driver == nil) {
        return NO;
    }

    /* Try to detect mouse */
    mouseType = [driver detectMouseAtPort:port];

    if (mouseType == MOUSE_TYPE_UNKNOWN) {
        /* Try secondary address */
        port = INPORT_SECONDARY;
        mouseType = [driver detectMouseAtPort:port];
    }

    if (mouseType == MOUSE_TYPE_UNKNOWN) {
        IOLog("BusMouse: No bus mouse detected\n");
        [driver free];
        return NO;
    }

    /* Initialize driver with detected port and type */
    if ([driver initFromDeviceDescription:deviceDescription] == nil) {
        [driver free];
        return NO;
    }

    return YES;
}

/*
 * Initialize driver instance
 */
- initFromDeviceDescription : deviceDescription
{
    const char *portStr;
    const char *irqStr;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get port address */
    portStr = [deviceDescription valueForStringKey:"Port"];
    if (portStr) {
        basePort = strtoul(portStr, NULL, 16);
    } else {
        basePort = INPORT_PRIMARY;
    }

    /* Detect mouse type */
    mouseType = [self detectMouseAtPort:basePort];
    if (mouseType == MOUSE_TYPE_UNKNOWN) {
        basePort = INPORT_SECONDARY;
        mouseType = [self detectMouseAtPort:basePort];
    }

    if (mouseType == MOUSE_TYPE_UNKNOWN) {
        IOLog("BusMouse: Failed to detect mouse\n");
        [super free];
        return nil;
    }

    /* Get IRQ */
    irqStr = [deviceDescription valueForStringKey:"IRQ"];
    if (irqStr) {
        irqNumber = atoi(irqStr);
    } else {
        irqNumber = INPORT_IRQ;
    }

    /* Allocate event queue */
    queueSize = EVENT_QUEUE_SIZE;
    eventQueue = IOMalloc(queueSize * sizeof(BusMouseQueueEntry));
    if (!eventQueue) {
        IOLog("BusMouse: Failed to allocate event queue\n");
        [super free];
        return nil;
    }
    bzero(eventQueue, queueSize * sizeof(BusMouseQueueEntry));
    queueHead = queueTail = queueCount = 0;

    /* Create locks */
    queueLock = [self allocLock];
    stateLock = [self allocLock];

    /* Initialize state */
    mouseOpen = NO;
    sampleRate = DEFAULT_SAMPLE_RATE;
    acceleration = DEFAULT_ACCELERATION;
    threshold = DEFAULT_THRESHOLD;
    irqEnabled = YES;
    quadratureMode = NO;

    /* Clear button states */
    bzero(&buttons, sizeof(buttons));
    bzero(&prevButtons, sizeof(prevButtons));

    /* Clear position */
    position.x = 0;
    position.y = 0;
    bzero(&position.buttons, sizeof(position.buttons));

    /* Clear statistics */
    bzero(&stats, sizeof(stats));

    /* Set capabilities based on mouse type */
    capabilities.mouseType = mouseType;
    capabilities.supportsIRQ = YES;

    switch (mouseType) {
        case MOUSE_TYPE_INPORT:
        case MOUSE_TYPE_ATI:
            capabilities.hasThreeButtons = YES;
            capabilities.maxSampleRate = RATE_200HZ;
            capabilities.supportsQuadrature = YES;
            break;
        case MOUSE_TYPE_LOGITECH:
            capabilities.hasThreeButtons = YES;
            capabilities.maxSampleRate = RATE_100HZ;
            capabilities.supportsQuadrature = NO;
            break;
        default:
            capabilities.hasThreeButtons = NO;
            capabilities.maxSampleRate = RATE_100HZ;
            capabilities.supportsQuadrature = NO;
            break;
    }

    /* Reset mouse */
    [self resetMouse];

    /* Register device */
    [self setName:"BusMouse"];
    [self setDeviceKind:"Pointing Device"];
    [self setLocation:"ISA"];
    [self registerDevice];

    IOLog("BusMouse: Initialized at 0x%x, IRQ %d\n", basePort, irqNumber);

    return self;
}

/*
 * Free driver resources
 */
- free
{
    if (mouseOpen) {
        [self closeMouse];
    }

    if (eventQueue) {
        IOFree(eventQueue, queueSize * sizeof(BusMouseQueueEntry));
        eventQueue = NULL;
    }

    if (queueLock) {
        [self freeLock:queueLock];
    }
    if (stateLock) {
        [self freeLock:stateLock];
    }

    return [super free];
}

/*
 * Reset mouse to default state
 */
- (IOReturn) resetMouse
{
    UInt8 mode;

    [self lock:stateLock];

    switch (mouseType) {
        case MOUSE_TYPE_INPORT:
        case MOUSE_TYPE_ATI:
            /* Reset InPort mouse */
            /* Set mode register */
            mode = INPORT_MODE_HZ0;  /* Disable first */
            outb(basePort + INPORT_ADDR_REG, INPORT_REG_MODE);
            IODelay(10);
            outb(basePort + INPORT_DATA_REG, mode);
            IODelay(RESET_DELAY);

            /* Clear status */
            outb(basePort + INPORT_ADDR_REG, INPORT_REG_STATUS);
            IODelay(10);
            inb(basePort + INPORT_DATA_REG);

            /* Clear data registers */
            outb(basePort + INPORT_ADDR_REG, INPORT_REG_DATA1);
            IODelay(10);
            inb(basePort + INPORT_DATA_REG);

            outb(basePort + INPORT_ADDR_REG, INPORT_REG_DATA2);
            IODelay(10);
            inb(basePort + INPORT_DATA_REG);
            break;

        case MOUSE_TYPE_LOGITECH:
            /* Reset Logitech mouse */
            outb(basePort + LOGITECH_CONTROL_REG, LOGITECH_CTRL_RESET);
            IODelay(RESET_DELAY);

            /* Clear configuration */
            outb(basePort + LOGITECH_CONFIG_REG, 0);
            break;

        default:
            [self unlock:stateLock];
            return MOUSE_IO_R_RESET_FAILED;
    }

    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Open mouse
 */
- (IOReturn) openMouse
{
    UInt8 mode;

    [self lock:stateLock];

    if (mouseOpen) {
        [self unlock:stateLock];
        return IO_R_BUSY;
    }

    /* Reset mouse */
    [self resetMouse];

    /* Configure mouse based on type */
    switch (mouseType) {
        case MOUSE_TYPE_INPORT:
        case MOUSE_TYPE_ATI:
            /* Set sample rate */
            if (sampleRate >= 200) {
                mode = INPORT_MODE_HZ200;
            } else if (sampleRate >= 100) {
                mode = INPORT_MODE_HZ100;
            } else if (sampleRate >= 50) {
                mode = INPORT_MODE_HZ50;
            } else {
                mode = INPORT_MODE_HZ30;
            }

            if (irqEnabled) {
                mode |= INPORT_MODE_IRQ_ENABLE;
            }

            if (quadratureMode) {
                mode |= INPORT_MODE_QUADRATURE;
            }

            outb(basePort + INPORT_ADDR_REG, INPORT_REG_MODE);
            IODelay(10);
            outb(basePort + INPORT_DATA_REG, mode);
            break;

        case MOUSE_TYPE_LOGITECH:
            /* Enable interrupts if requested */
            if (irqEnabled) {
                outb(basePort + LOGITECH_CONFIG_REG, LOGITECH_CFG_IRQ_ENABLE);
            }
            break;

        default:
            break;
    }

    /* Enable interrupts */
    if (irqEnabled) {
        [self enableAllInterrupts];
    }

    mouseOpen = YES;

    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Close mouse
 */
- (IOReturn) closeMouse
{
    [self lock:stateLock];

    if (!mouseOpen) {
        [self unlock:stateLock];
        return IO_R_INVALID_ARG;
    }

    /* Disable interrupts */
    [self disableAllInterrupts];

    /* Reset mouse */
    [self resetMouse];

    /* Flush event queue */
    [self flushEvents];

    mouseOpen = NO;

    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Read mouse movement and buttons (low-level)
 */
- (IOReturn) readMovement : (int *) deltaX
                   deltaY : (int *) deltaY
                  buttons : (BusMouseButtons *) btns
{
    UInt8 status, data1, data2;
    int dx = 0, dy = 0;

    if (!deltaX || !deltaY || !btns) {
        return IO_R_INVALID_ARG;
    }

    switch (mouseType) {
        case MOUSE_TYPE_INPORT:
        case MOUSE_TYPE_ATI:
            /* Read InPort mouse */
            outb(basePort + INPORT_ADDR_REG, INPORT_REG_STATUS);
            IODelay(10);
            status = inb(basePort + INPORT_DATA_REG);

            /* Read X movement */
            outb(basePort + INPORT_ADDR_REG, INPORT_REG_DATA1);
            IODelay(10);
            data1 = inb(basePort + INPORT_DATA_REG);

            /* Read Y movement */
            outb(basePort + INPORT_ADDR_REG, INPORT_REG_DATA2);
            IODelay(10);
            data2 = inb(basePort + INPORT_DATA_REG);

            /* Convert to signed values */
            dx = (int)((signed char)data1);
            dy = (int)((signed char)data2);

            /* Read button states (inverted logic) */
            btns->left = (status & INPORT_STATUS_BUTTON1) ? YES : NO;
            btns->right = (status & INPORT_STATUS_BUTTON2) ? YES : NO;
            btns->middle = (status & INPORT_STATUS_BUTTON3) ? YES : NO;
            break;

        case MOUSE_TYPE_LOGITECH:
            /* Read Logitech mouse */
            /* Read X low nibble */
            outb(basePort + LOGITECH_CONTROL_REG,
                 LOGITECH_CTRL_READ_X | LOGITECH_CTRL_READ_LOW);
            IODelay(10);
            data1 = inb(basePort + LOGITECH_DATA_REG);

            /* Read X high nibble */
            outb(basePort + LOGITECH_CONTROL_REG,
                 LOGITECH_CTRL_READ_X | LOGITECH_CTRL_READ_HIGH);
            IODelay(10);
            data2 = inb(basePort + LOGITECH_DATA_REG);

            /* Combine nibbles */
            dx = ((data2 & 0x0F) << 4) | (data1 & 0x0F);
            if (data2 & LOGITECH_DATA_XSIGN) {
                dx = -dx;
            }

            /* Read Y low nibble */
            outb(basePort + LOGITECH_CONTROL_REG,
                 LOGITECH_CTRL_READ_Y | LOGITECH_CTRL_READ_LOW);
            IODelay(10);
            data1 = inb(basePort + LOGITECH_DATA_REG);

            /* Read Y high nibble */
            outb(basePort + LOGITECH_CONTROL_REG,
                 LOGITECH_CTRL_READ_Y | LOGITECH_CTRL_READ_HIGH);
            IODelay(10);
            data2 = inb(basePort + LOGITECH_DATA_REG);

            /* Combine nibbles */
            dy = ((data2 & 0x0F) << 4) | (data1 & 0x0F);
            if (data2 & LOGITECH_DATA_YSIGN) {
                dy = -dy;
            }

            /* Read buttons from last data read */
            btns->left = (data2 & LOGITECH_DATA_BUTTON1) ? YES : NO;
            btns->right = (data2 & LOGITECH_DATA_BUTTON2) ? YES : NO;
            btns->middle = (data2 & LOGITECH_DATA_BUTTON3) ? YES : NO;
            break;

        default:
            return MOUSE_IO_R_NOT_DETECTED;
    }

    *deltaX = dx;
    *deltaY = dy;

    /* Update max deltas */
    if (abs(dx) > stats.maxDeltaX) {
        stats.maxDeltaX = abs(dx);
    }
    if (abs(dy) > stats.maxDeltaY) {
        stats.maxDeltaY = abs(dy);
    }

    return IO_R_SUCCESS;
}

/*
 * Interrupt handler
 */
- (void) interruptOccurred
{
    BusMouseEvent event;
    int deltaX, deltaY;
    BusMouseButtons btns;
    IOReturn result;

    stats.interrupts++;

    /* Read movement and button data */
    result = [self readMovement:&deltaX deltaY:&deltaY buttons:&btns];
    if (result != IO_R_SUCCESS) {
        stats.errors++;
        return;
    }

    /* Apply acceleration */
    if (acceleration > 1) {
        if (abs(deltaX) > threshold) {
            deltaX *= acceleration;
        }
        if (abs(deltaY) > threshold) {
            deltaY *= acceleration;
        }
    }

    /* Create event */
    event.deltaX = deltaX;
    event.deltaY = deltaY;
    event.buttons = btns;
    event.timestamp = IOGetTimestamp() / 1000;  /* Convert to milliseconds */

    /* Update position */
    position.x += deltaX;
    position.y += deltaY;
    position.buttons = btns;

    /* Queue event */
    [self lock:queueLock];

    if (queueCount < queueSize) {
        eventQueue[queueHead].event = event;
        eventQueue[queueHead].valid = YES;
        queueHead = (queueHead + 1) % queueSize;
        queueCount++;
        stats.totalEvents++;

        /* Count button clicks */
        if (btns.left && !prevButtons.left) stats.buttonClicks++;
        if (btns.right && !prevButtons.right) stats.buttonClicks++;
        if (btns.middle && !prevButtons.middle) stats.buttonClicks++;

        prevButtons = btns;
    } else {
        stats.overruns++;
    }

    [self unlock:queueLock];

    /* Dispatch event to event system */
    [self dispatchEvent:&event];
}

/*
 * Get next event from queue
 */
- (IOReturn) getEvent : (BusMouseEvent *) event
{
    if (!event) return IO_R_INVALID_ARG;

    [self lock:queueLock];

    if (queueCount == 0) {
        [self unlock:queueLock];
        return MOUSE_IO_R_NO_EVENT;
    }

    *event = eventQueue[queueTail].event;
    eventQueue[queueTail].valid = NO;
    queueTail = (queueTail + 1) % queueSize;
    queueCount--;

    [self unlock:queueLock];

    return IO_R_SUCCESS;
}

/*
 * Peek at next event without removing it
 */
- (IOReturn) peekEvent : (BusMouseEvent *) event
{
    if (!event) return IO_R_INVALID_ARG;

    [self lock:queueLock];

    if (queueCount == 0) {
        [self unlock:queueLock];
        return MOUSE_IO_R_NO_EVENT;
    }

    *event = eventQueue[queueTail].event;

    [self unlock:queueLock];

    return IO_R_SUCCESS;
}

/*
 * Check if events are available
 */
- (Boolean) hasEvent
{
    Boolean result;

    [self lock:queueLock];
    result = (queueCount > 0);
    [self unlock:queueLock];

    return result;
}

/*
 * Flush event queue
 */
- (IOReturn) flushEvents
{
    [self lock:queueLock];

    queueHead = queueTail = queueCount = 0;
    bzero(eventQueue, queueSize * sizeof(BusMouseQueueEntry));

    [self unlock:queueLock];

    return IO_R_SUCCESS;
}

/*
 * Get current position
 */
- (IOReturn) getPosition : (BusMousePosition *) pos
{
    if (!pos) return IO_R_INVALID_ARG;

    [self lock:stateLock];
    *pos = position;
    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Set position (for absolute positioning)
 */
- (IOReturn) setPosition : (int) x
                        y : (int) y
{
    [self lock:stateLock];
    position.x = x;
    position.y = y;
    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Get button states
 */
- (IOReturn) getButtons : (BusMouseButtons *) btns
{
    if (!btns) return IO_R_INVALID_ARG;

    [self lock:stateLock];
    *btns = position.buttons;
    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Configuration methods
 */
- (IOReturn) setSampleRate : (UInt32) rate
{
    if (rate > capabilities.maxSampleRate) {
        return IO_R_INVALID_ARG;
    }

    sampleRate = rate;

    /* Reopen if already open to apply new rate */
    if (mouseOpen) {
        [self closeMouse];
        [self openMouse];
    }

    return IO_R_SUCCESS;
}

- (IOReturn) getSampleRate : (UInt32 *) rate
{
    if (!rate) return IO_R_INVALID_ARG;
    *rate = sampleRate;
    return IO_R_SUCCESS;
}

- (IOReturn) setAcceleration : (UInt32) accel
                    threshold : (UInt32) thresh
{
    if (accel < 1 || accel > 10) {
        return IO_R_INVALID_ARG;
    }

    acceleration = accel;
    threshold = thresh;

    return IO_R_SUCCESS;
}

- (IOReturn) getCapabilities : (BusMouseCapabilities *) caps
{
    if (!caps) return IO_R_INVALID_ARG;
    *caps = capabilities;
    return IO_R_SUCCESS;
}

- (BusMouseType) getMouseType
{
    return mouseType;
}

/*
 * Statistics
 */
- (IOReturn) getStatistics : (BusMouseStats *) pstats
{
    if (!pstats) return IO_R_INVALID_ARG;
    *pstats = stats;
    return IO_R_SUCCESS;
}

- (IOReturn) resetStatistics
{
    bzero(&stats, sizeof(stats));
    return IO_R_SUCCESS;
}

/*
 * IOEventSource protocol methods
 */
- (Boolean) dispatchEvent : (void *) event
{
    /* Forward to event system */
    /* This would integrate with the window server event queue */
    return YES;
}

- (void) enableEvents
{
    irqEnabled = YES;
    if (mouseOpen) {
        [self enableAllInterrupts];
    }
}

- (void) disableEvents
{
    irqEnabled = NO;
    [self disableAllInterrupts];
}

@end
