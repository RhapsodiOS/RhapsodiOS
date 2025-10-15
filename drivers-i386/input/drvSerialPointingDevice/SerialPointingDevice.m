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
 * SerialPointingDevice.m - Serial Mouse Driver Implementation
 */

#import "SerialPointingDevice.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>

@implementation SerialPointingDevice

/*
 * Probe for serial mouse
 */
+ (Boolean) probe : deviceDescription
{
    SerialPointingDevice *driver;
    const char *port;

    /* Get port name */
    port = [deviceDescription valueForStringKey:"Port"];
    if (!port) {
        port = "COM1";  /* Default to COM1 */
    }

    IOLog("SerialMouse: Probing %s\n", port);

    /* Create driver instance */
    driver = [self alloc];
    if (driver == nil) {
        return NO;
    }

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
    const char *port;
    const char *proto;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get port name */
    port = [deviceDescription valueForStringKey:"Port"];
    if (!port) {
        port = "COM1";
    }
    portName = port;

    /* Get protocol hint */
    proto = [deviceDescription valueForStringKey:"Protocol"];
    if (proto) {
        if (strcmp(proto, "Microsoft") == 0) {
            protocol = PROTOCOL_MICROSOFT;
        } else if (strcmp(proto, "MouseSystems") == 0) {
            protocol = PROTOCOL_MOUSESYSTEMS;
        } else if (strcmp(proto, "Logitech") == 0) {
            protocol = PROTOCOL_LOGITECH;
        } else if (strcmp(proto, "IntelliMouse") == 0) {
            protocol = PROTOCOL_INTELLIMOUSE;
        } else {
            protocol = PROTOCOL_UNKNOWN;
        }
    } else {
        protocol = PROTOCOL_UNKNOWN;  /* Will auto-detect */
    }

    /* Allocate event queue */
    queueSize = EVENT_QUEUE_SIZE;
    eventQueue = IOMalloc(queueSize * sizeof(SerialMouseQueueEntry));
    if (!eventQueue) {
        IOLog("SerialMouse: Failed to allocate event queue\n");
        [super free];
        return nil;
    }
    bzero(eventQueue, queueSize * sizeof(SerialMouseQueueEntry));
    queueHead = queueTail = queueCount = 0;

    /* Create locks */
    queueLock = [self allocLock];
    stateLock = [self allocLock];
    packetLock = [self allocLock];

    /* Initialize state */
    mouseOpen = NO;
    baudRate = DEFAULT_BAUD_RATE;
    dataBits = MOUSE_DATA_BITS_7;  /* Microsoft default */
    stopBits = MOUSE_STOP_BITS_1;
    parity = MOUSE_PARITY_NONE;
    acceleration = DEFAULT_ACCELERATION;
    threshold = DEFAULT_THRESHOLD;
    autoPower = YES;

    /* Clear button states */
    bzero(&buttons, sizeof(buttons));
    bzero(&prevButtons, sizeof(prevButtons));

    /* Clear position */
    position.x = 0;
    position.y = 0;
    position.wheelPosition = 0;
    bzero(&position.buttons, sizeof(position.buttons));

    /* Clear packet buffer */
    bzero(&currentPacket, sizeof(currentPacket));
    bzero(packetBuffer, sizeof(packetBuffer));
    packetIndex = 0;

    /* Clear statistics */
    bzero(&stats, sizeof(stats));

    /* Set default capabilities (will be updated after detection) */
    capabilities.protocol = protocol;
    capabilities.hasWheel = NO;
    capabilities.buttonCount = 2;
    capabilities.maxBaudRate = MOUSE_BAUD_1200;
    capabilities.supportsPnP = NO;
    bzero(capabilities.pnpID, sizeof(capabilities.pnpID));

    /* Get serial port object */
    serialPort = [IOSerialPort lookupByName:portName];
    if (!serialPort) {
        IOLog("SerialMouse: Serial port %s not found\n", portName);
        IOFree(eventQueue, queueSize * sizeof(SerialMouseQueueEntry));
        [super free];
        return nil;
    }

    /* Register device */
    [self setName:"SerialMouse"];
    [self setDeviceKind:"Pointing Device"];
    [self setLocation:portName];
    [self registerDevice];

    IOLog("SerialMouse: Initialized on %s\n", portName);

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
        IOFree(eventQueue, queueSize * sizeof(SerialMouseQueueEntry));
        eventQueue = NULL;
    }

    if (queueLock) {
        [self freeLock:queueLock];
    }
    if (stateLock) {
        [self freeLock:stateLock];
    }
    if (packetLock) {
        [self freeLock:packetLock];
    }

    return [super free];
}

/*
 * Configure serial port for mouse
 */
- (IOReturn) configureSerialPort
{
    if (!serialPort) {
        return SMOUSE_IO_R_PORT_ERROR;
    }

    /* Set baud rate */
    [serialPort setBaudRate:baudRate];

    /* Set data format */
    [serialPort setDataBits:dataBits];
    [serialPort setStopBits:stopBits];
    [serialPort setParity:parity];

    /* Disable flow control */
    [serialPort setFlowControl:0];

    return IO_R_SUCCESS;
}

/*
 * Power on mouse via DTR/RTS
 */
- (IOReturn) powerOnMouse
{
    if (!serialPort || !autoPower) {
        return IO_R_SUCCESS;
    }

    /* Assert DTR and RTS to power the mouse */
    [serialPort setDTR:YES];
    [serialPort setRTS:YES];

    /* Wait for mouse to power up */
    IOSleep(MOUSE_RESET_DELAY / 1000);

    return IO_R_SUCCESS;
}

/*
 * Power off mouse
 */
- (IOReturn) powerOffMouse
{
    if (!serialPort || !autoPower) {
        return IO_R_SUCCESS;
    }

    /* Deassert DTR and RTS */
    [serialPort setDTR:NO];
    [serialPort setRTS:NO];

    return IO_R_SUCCESS;
}

/*
 * Send identification request (for auto-detection)
 */
- (IOReturn) sendIdentificationRequest
{
    /* Toggle RTS to request identification on some mice */
    if (serialPort) {
        [serialPort setRTS:NO];
        IOSleep(10);
        [serialPort setRTS:YES];
        IOSleep(MOUSE_IDENT_DELAY / 1000);
    }

    return IO_R_SUCCESS;
}

/*
 * Detect mouse protocol
 */
- (IOReturn) detectProtocol
{
    UInt8 buffer[16];
    UInt32 bytesRead;
    IOReturn result;

    if (protocol != PROTOCOL_UNKNOWN) {
        /* Protocol already specified */
        return IO_R_SUCCESS;
    }

    IOLog("SerialMouse: Auto-detecting protocol\n");

    /* Try Microsoft protocol first (most common) */
    dataBits = MOUSE_DATA_BITS_7;
    parity = MOUSE_PARITY_NONE;
    [self configureSerialPort];
    [self sendIdentificationRequest];

    /* Read some data */
    result = [serialPort readBytes:buffer
                            length:16
                         bytesRead:&bytesRead
                           timeout:DETECT_TIMEOUT];

    if (result == IO_R_SUCCESS && bytesRead > 0) {
        /* Check for Microsoft sync byte pattern */
        int i;
        for (i = 0; i < bytesRead; i++) {
            if ((buffer[i] & MS_SYNC_MASK) == MS_SYNC_BYTE) {
                protocol = PROTOCOL_MICROSOFT;
                capabilities.protocol = PROTOCOL_MICROSOFT;
                capabilities.buttonCount = 2;
                IOLog("SerialMouse: Detected Microsoft protocol\n");
                return IO_R_SUCCESS;
            }
        }
    }

    /* Try MouseSystems protocol */
    dataBits = MOUSE_DATA_BITS_8;
    [self configureSerialPort];

    result = [serialPort readBytes:buffer
                            length:16
                         bytesRead:&bytesRead
                           timeout:DETECT_TIMEOUT];

    if (result == IO_R_SUCCESS && bytesRead > 0) {
        /* Check for MouseSystems sync byte */
        int i;
        for (i = 0; i < bytesRead; i++) {
            if ((buffer[i] & MSC_SYNC_MASK) == MSC_SYNC_BYTE) {
                protocol = PROTOCOL_MOUSESYSTEMS;
                capabilities.protocol = PROTOCOL_MOUSESYSTEMS;
                capabilities.buttonCount = 3;
                IOLog("SerialMouse: Detected MouseSystems protocol\n");
                return IO_R_SUCCESS;
            }
        }
    }

    /* Default to Microsoft if detection failed */
    protocol = PROTOCOL_MICROSOFT;
    capabilities.protocol = PROTOCOL_MICROSOFT;
    capabilities.buttonCount = 2;
    dataBits = MOUSE_DATA_BITS_7;
    [self configureSerialPort];

    IOLog("SerialMouse: Defaulting to Microsoft protocol\n");

    return IO_R_SUCCESS;
}

/*
 * Reset mouse
 */
- (IOReturn) resetMouse
{
    [self lock:stateLock];

    /* Power cycle if using DTR/RTS power */
    if (autoPower) {
        [self powerOffMouse];
        IOSleep(100);
        [self powerOnMouse];
    }

    /* Clear packet buffer */
    packetIndex = 0;
    bzero(&currentPacket, sizeof(currentPacket));
    bzero(packetBuffer, sizeof(packetBuffer));

    /* Flush serial port */
    if (serialPort) {
        [serialPort flushInput];
        [serialPort flushOutput];
    }

    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Open mouse
 */
- (IOReturn) openMouse
{
    IOReturn result;

    [self lock:stateLock];

    if (mouseOpen) {
        [self unlock:stateLock];
        return IO_R_BUSY;
    }

    /* Configure and open serial port */
    if (!serialPort) {
        [self unlock:stateLock];
        return SMOUSE_IO_R_PORT_ERROR;
    }

    result = [serialPort openPort];
    if (result != IO_R_SUCCESS) {
        [self unlock:stateLock];
        return result;
    }

    /* Configure port */
    [self configureSerialPort];

    /* Power on mouse */
    [self powerOnMouse];

    /* Detect protocol if unknown */
    if (protocol == PROTOCOL_UNKNOWN) {
        [self detectProtocol];
    }

    /* Set packet size based on protocol */
    switch (protocol) {
        case PROTOCOL_MICROSOFT:
            currentPacket.expectedLength = MS_PACKET_SIZE;
            break;
        case PROTOCOL_MICROSOFT_3BTN:
            currentPacket.expectedLength = MS_3BTN_PACKET_SIZE;
            break;
        case PROTOCOL_MOUSESYSTEMS:
        case PROTOCOL_MOUSESYSTEMS_5BTN:
            currentPacket.expectedLength = MSC_PACKET_SIZE;
            break;
        case PROTOCOL_LOGITECH:
            currentPacket.expectedLength = LOGI_3BTN_PACKET_SIZE;
            break;
        case PROTOCOL_INTELLIMOUSE:
        case PROTOCOL_INTELLIMOUSE_EX:
            currentPacket.expectedLength = MS_WHEEL_PACKET_SIZE;
            break;
        default:
            currentPacket.expectedLength = MS_PACKET_SIZE;
            break;
    }

    mouseOpen = YES;

    [self unlock:stateLock];

    /* Start reading from serial port */
    [self enableEvents];

    IOLog("SerialMouse: Mouse opened\n");

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

    /* Stop reading */
    [self disableEvents];

    /* Power off mouse */
    [self powerOffMouse];

    /* Close serial port */
    if (serialPort) {
        [serialPort closePort];
    }

    /* Flush event queue */
    [self flushEvents];

    mouseOpen = NO;

    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Process incoming serial data
 */
- (void) processSerialData : (const UInt8 *) data
                     length : (UInt32) length
{
    UInt32 i;

    [self lock:packetLock];

    for (i = 0; i < length; i++) {
        UInt8 byte = data[i];

        /* Check for sync byte to start new packet */
        Boolean isSync = NO;

        switch (protocol) {
            case PROTOCOL_MICROSOFT:
            case PROTOCOL_MICROSOFT_3BTN:
            case PROTOCOL_LOGITECH:
            case PROTOCOL_INTELLIMOUSE:
            case PROTOCOL_INTELLIMOUSE_EX:
                /* Microsoft-style sync byte */
                if ((byte & MS_SYNC_MASK) == MS_SYNC_BYTE) {
                    isSync = YES;
                }
                break;

            case PROTOCOL_MOUSESYSTEMS:
            case PROTOCOL_MOUSESYSTEMS_5BTN:
                /* MouseSystems sync byte */
                if ((byte & MSC_SYNC_MASK) == MSC_SYNC_BYTE) {
                    isSync = YES;
                }
                break;

            default:
                break;
        }

        if (isSync && packetIndex > 0) {
            /* Sync error - discard current packet and start new */
            stats.syncErrors++;
            packetIndex = 0;
        }

        /* Add byte to packet */
        if (packetIndex < MAX_PACKET_SIZE) {
            packetBuffer[packetIndex++] = byte;
            currentPacket.data[currentPacket.length++] = byte;

            /* Check if packet is complete */
            if (packetIndex >= currentPacket.expectedLength) {
                currentPacket.complete = YES;
                stats.packetsReceived++;

                /* Process complete packet */
                [self processPacket:&currentPacket];

                /* Reset for next packet */
                packetIndex = 0;
                currentPacket.length = 0;
                currentPacket.complete = NO;
                bzero(currentPacket.data, sizeof(currentPacket.data));
            }
        }
    }

    [self unlock:packetLock];
}

/*
 * Process complete packet
 */
- (void) processPacket : (SerialMousePacket *) packet
{
    if (!packet || !packet->complete) {
        return;
    }

    switch (protocol) {
        case PROTOCOL_MICROSOFT:
        case PROTOCOL_MICROSOFT_3BTN:
            [self parseMicrosoftPacket:packet];
            break;

        case PROTOCOL_MOUSESYSTEMS:
        case PROTOCOL_MOUSESYSTEMS_5BTN:
            [self parseMouseSystemsPacket:packet];
            break;

        case PROTOCOL_LOGITECH:
            [self parseLogitech3BtnPacket:packet];
            break;

        case PROTOCOL_INTELLIMOUSE:
        case PROTOCOL_INTELLIMOUSE_EX:
            [self parseIntelliMousePacket:packet];
            break;

        default:
            break;
    }
}

/*
 * Parse Microsoft protocol packet
 */
- (void) parseMicrosoftPacket : (SerialMousePacket *) packet
{
    SerialMouseEvent event;
    int dx, dy;
    UInt8 b1, b2, b3;

    if (packet->length < MS_PACKET_SIZE) {
        return;
    }

    b1 = packet->data[0];
    b2 = packet->data[1];
    b3 = packet->data[2];

    /* Extract button states */
    event.buttons.left = (b1 & MS_B1_LEFT_BUTTON) ? YES : NO;
    event.buttons.right = (b1 & MS_B1_RIGHT_BUTTON) ? YES : NO;
    event.buttons.middle = NO;
    event.buttons.button4 = NO;
    event.buttons.button5 = NO;

    /* Check for 3-button extension */
    if (packet->length >= MS_3BTN_PACKET_SIZE) {
        UInt8 b4 = packet->data[3];
        event.buttons.middle = (b4 & MS_B4_MIDDLE_BUTTON) ? YES : NO;
    }

    /* Extract movement */
    dx = ((b1 & 0x03) << 6) | (b2 & 0x3F);
    dy = ((b1 & 0x0C) << 4) | (b3 & 0x3F);

    /* Handle sign extension */
    if (dx > 127) dx -= 256;
    if (dy > 127) dy -= 256;

    /* Apply acceleration */
    if (acceleration > 1) {
        if (abs(dx) > threshold) dx *= acceleration;
        if (abs(dy) > threshold) dy *= acceleration;
    }

    event.deltaX = dx;
    event.deltaY = -dy;  /* Invert Y */
    event.wheelDelta = 0;
    event.timestamp = IOGetTimestamp() / 1000;

    /* Update position and queue event */
    [self queueEvent:&event];
}

/*
 * Parse MouseSystems protocol packet
 */
- (void) parseMouseSystemsPacket : (SerialMousePacket *) packet
{
    SerialMouseEvent event;
    int dx, dy;
    UInt8 b1;

    if (packet->length < MSC_PACKET_SIZE) {
        return;
    }

    b1 = packet->data[0];

    /* Extract button states (inverted logic) */
    event.buttons.left = !(b1 & MSC_B1_LEFT_BUTTON);
    event.buttons.middle = !(b1 & MSC_B1_MIDDLE_BUTTON);
    event.buttons.right = !(b1 & MSC_B1_RIGHT_BUTTON);
    event.buttons.button4 = NO;
    event.buttons.button5 = NO;

    /* Extract movement (signed bytes) */
    dx = (signed char)packet->data[1] + (signed char)packet->data[3];
    dy = (signed char)packet->data[2] + (signed char)packet->data[4];

    /* Apply acceleration */
    if (acceleration > 1) {
        if (abs(dx) > threshold) dx *= acceleration;
        if (abs(dy) > threshold) dy *= acceleration;
    }

    event.deltaX = dx;
    event.deltaY = -dy;  /* Invert Y */
    event.wheelDelta = 0;
    event.timestamp = IOGetTimestamp() / 1000;

    /* Queue event */
    [self queueEvent:&event];
}

/*
 * Parse Logitech 3-button packet
 */
- (void) parseLogitech3BtnPacket : (SerialMousePacket *) packet
{
    /* Logitech uses Microsoft format with middle button extension */
    [self parseMicrosoftPacket:packet];
}

/*
 * Parse IntelliMouse packet (with wheel)
 */
- (void) parseIntelliMousePacket : (SerialMousePacket *) packet
{
    SerialMouseEvent event;
    int dx, dy, wheel;
    UInt8 b1, b2, b3, b4;

    if (packet->length < MS_WHEEL_PACKET_SIZE) {
        return;
    }

    b1 = packet->data[0];
    b2 = packet->data[1];
    b3 = packet->data[2];
    b4 = packet->data[3];

    /* Extract button states */
    event.buttons.left = (b1 & MS_B1_LEFT_BUTTON) ? YES : NO;
    event.buttons.right = (b1 & MS_B1_RIGHT_BUTTON) ? YES : NO;
    event.buttons.middle = (b4 & MS_B4_MIDDLE_BUTTON) ? YES : NO;
    event.buttons.button4 = NO;
    event.buttons.button5 = NO;

    /* Extract movement */
    dx = ((b1 & 0x03) << 6) | (b2 & 0x3F);
    dy = ((b1 & 0x0C) << 4) | (b3 & 0x3F);

    /* Handle sign extension */
    if (dx > 127) dx -= 256;
    if (dy > 127) dy -= 256;

    /* Extract wheel */
    wheel = b4 & MS_B4_WHEEL_MASK;
    if (wheel & MS_B4_WHEEL_SIGN) {
        wheel |= 0xF0;  /* Sign extend */
    }
    wheel = (signed char)wheel;

    /* Apply acceleration */
    if (acceleration > 1) {
        if (abs(dx) > threshold) dx *= acceleration;
        if (abs(dy) > threshold) dy *= acceleration;
    }

    event.deltaX = dx;
    event.deltaY = -dy;  /* Invert Y */
    event.wheelDelta = -wheel;  /* Invert wheel */
    event.timestamp = IOGetTimestamp() / 1000;

    if (wheel != 0) {
        stats.wheelScrolls++;
    }

    /* Queue event */
    [self queueEvent:&event];
}

/*
 * Queue an event
 */
- (void) queueEvent : (SerialMouseEvent *) event
{
    [self lock:queueLock];

    /* Update position */
    position.x += event->deltaX;
    position.y += event->deltaY;
    position.wheelPosition += event->wheelDelta;
    position.buttons = event->buttons;

    /* Count button clicks */
    if (event->buttons.left && !prevButtons.left) stats.buttonClicks++;
    if (event->buttons.right && !prevButtons.right) stats.buttonClicks++;
    if (event->buttons.middle && !prevButtons.middle) stats.buttonClicks++;

    prevButtons = event->buttons;

    /* Update max deltas */
    if (abs(event->deltaX) > stats.maxDeltaX) {
        stats.maxDeltaX = abs(event->deltaX);
    }
    if (abs(event->deltaY) > stats.maxDeltaY) {
        stats.maxDeltaY = abs(event->deltaY);
    }

    /* Add to queue */
    if (queueCount < queueSize) {
        eventQueue[queueHead].event = *event;
        eventQueue[queueHead].valid = YES;
        queueHead = (queueHead + 1) % queueSize;
        queueCount++;
        stats.totalEvents++;
    } else {
        stats.overrunErrors++;
    }

    [self unlock:queueLock];

    /* Dispatch to event system */
    [self dispatchEvent:event];
}

/*
 * Get next event from queue
 */
- (IOReturn) getEvent : (SerialMouseEvent *) event
{
    if (!event) return IO_R_INVALID_ARG;

    [self lock:queueLock];

    if (queueCount == 0) {
        [self unlock:queueLock];
        return SMOUSE_IO_R_NO_EVENT;
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
- (IOReturn) peekEvent : (SerialMouseEvent *) event
{
    if (!event) return IO_R_INVALID_ARG;

    [self lock:queueLock];

    if (queueCount == 0) {
        [self unlock:queueLock];
        return SMOUSE_IO_R_NO_EVENT;
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
    bzero(eventQueue, queueSize * sizeof(SerialMouseQueueEntry));

    [self unlock:queueLock];

    return IO_R_SUCCESS;
}

/*
 * Get current position
 */
- (IOReturn) getPosition : (SerialMousePosition *) pos
{
    if (!pos) return IO_R_INVALID_ARG;

    [self lock:stateLock];
    *pos = position;
    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Set position
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
- (IOReturn) getButtons : (SerialMouseButtons *) btns
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
- (IOReturn) setProtocol : (SerialMouseProtocol) proto
{
    protocol = proto;
    capabilities.protocol = proto;

    /* Update data bits based on protocol */
    if (proto == PROTOCOL_MOUSESYSTEMS || proto == PROTOCOL_MOUSESYSTEMS_5BTN) {
        dataBits = MOUSE_DATA_BITS_8;
    } else {
        dataBits = MOUSE_DATA_BITS_7;
    }

    if (mouseOpen) {
        [self configureSerialPort];
    }

    return IO_R_SUCCESS;
}

- (SerialMouseProtocol) getProtocol
{
    return protocol;
}

- (IOReturn) setBaudRate : (UInt32) rate
{
    baudRate = rate;

    if (mouseOpen) {
        [self configureSerialPort];
    }

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

- (IOReturn) getCapabilities : (SerialMouseCapabilities *) caps
{
    if (!caps) return IO_R_INVALID_ARG;
    *caps = capabilities;
    return IO_R_SUCCESS;
}

/*
 * Statistics
 */
- (IOReturn) getStatistics : (SerialMouseStats *) pstats
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
    return YES;
}

- (void) enableEvents
{
    /* Start reading from serial port */
    if (serialPort && mouseOpen) {
        /* Set up async read callback */
        /* This would integrate with the serial port's interrupt handler */
    }
}

- (void) disableEvents
{
    /* Stop reading from serial port */
}

@end
