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
 * SerialPointingDevice.h - Serial Mouse Driver
 *
 * Supports Microsoft, MouseSystems, Logitech, and IntelliMouse protocols
 * Works with standard serial ports (COM1-COM4)
 */

#ifndef _SERIAL_POINTING_DEVICE_H
#define _SERIAL_POINTING_DEVICE_H

#import <driverkit/IOSerialPort.h>
#import <driverkit/IODevice.h>
#import <driverkit/IOPower.h>
#import <driverkit/IOEventSource.h>
#import <kernserv/queue.h>
#import "SerialPointingDeviceTypes.h"
#import "SerialMouseProtocols.h"

/* Debug flags */
#define SMOUSE_DEBUG            0
#define SMOUSE_TRACE            0

/* Default settings */
#define DEFAULT_BAUD_RATE       MOUSE_BAUD_1200
#define DEFAULT_SAMPLE_RATE     40      /* ~40 Hz typical */
#define DEFAULT_ACCELERATION    2       /* 2x acceleration */
#define DEFAULT_THRESHOLD       4       /* Acceleration threshold */
#define EVENT_QUEUE_SIZE        64      /* Event queue size */

@interface SerialPointingDevice : IODevice <IOPower, IOEventSource>
{
    /* Serial port */
    id                  serialPort;             /* Serial port object */
    const char          *portName;              /* Port name */

    /* Protocol and capabilities */
    SerialMouseProtocol protocol;               /* Current protocol */
    SerialMouseCapabilities capabilities;       /* Mouse capabilities */

    /* Configuration */
    UInt32              baudRate;               /* Baud rate */
    UInt8               dataBits;               /* Data bits */
    UInt8               stopBits;               /* Stop bits */
    UInt8               parity;                 /* Parity */
    UInt32              acceleration;           /* Acceleration factor */
    UInt32              threshold;              /* Acceleration threshold */
    Boolean             autoPower;              /* Power via DTR/RTS */

    /* Current state */
    Boolean             mouseOpen;              /* Mouse is open */
    SerialMouseButtons  buttons;                /* Current button states */
    SerialMousePosition position;               /* Current position */

    /* Previous state (for delta calculation) */
    SerialMouseButtons  prevButtons;            /* Previous button states */

    /* Packet processing */
    SerialMousePacket   currentPacket;          /* Current packet buffer */
    UInt8               packetBuffer[MAX_PACKET_SIZE]; /* Raw packet buffer */
    UInt8               packetIndex;            /* Current packet index */

    /* Event queue */
    SerialMouseQueueEntry *eventQueue;          /* Event queue buffer */
    UInt32              queueSize;              /* Queue size */
    UInt32              queueHead;              /* Queue head index */
    UInt32              queueTail;              /* Queue tail index */
    UInt32              queueCount;             /* Events in queue */
    id                  queueLock;              /* Queue lock */

    /* Statistics */
    SerialMouseStats    stats;                  /* Statistics counters */

    /* Thread synchronization */
    id                  stateLock;              /* State lock */
    id                  packetLock;             /* Packet processing lock */
}

/* Initialization and probing */
+ (Boolean) probe : deviceDescription;
- initFromDeviceDescription : deviceDescription;
- free;

/* Mouse control */
- (IOReturn) openMouse;
- (IOReturn) closeMouse;
- (IOReturn) resetMouse;

/* Protocol detection and configuration */
- (IOReturn) detectProtocol;
- (IOReturn) setProtocol : (SerialMouseProtocol) proto;
- (SerialMouseProtocol) getProtocol;

/* Configuration */
- (IOReturn) setConfig : (SerialMouseConfig *) config;
- (IOReturn) getConfig : (SerialMouseConfig *) config;
- (IOReturn) setBaudRate : (UInt32) rate;
- (IOReturn) setAcceleration : (UInt32) accel
                    threshold : (UInt32) thresh;

/* Capabilities query */
- (IOReturn) getCapabilities : (SerialMouseCapabilities *) caps;

/* Position and state */
- (IOReturn) getPosition : (SerialMousePosition *) pos;
- (IOReturn) getButtons : (SerialMouseButtons *) btns;
- (IOReturn) setPosition : (int) x
                        y : (int) y;

/* Event handling */
- (IOReturn) getEvent : (SerialMouseEvent *) event;
- (IOReturn) peekEvent : (SerialMouseEvent *) event;
- (Boolean) hasEvent;
- (IOReturn) flushEvents;

/* Data processing */
- (void) processSerialData : (const UInt8 *) data
                     length : (UInt32) length;
- (void) processPacket : (SerialMousePacket *) packet;

/* Statistics */
- (IOReturn) getStatistics : (SerialMouseStats *) stats;
- (IOReturn) resetStatistics;

/* Protocol-specific packet parsing */
- (void) parseMicrosoftPacket : (SerialMousePacket *) packet;
- (void) parseMouseSystemsPacket : (SerialMousePacket *) packet;
- (void) parseLogitech3BtnPacket : (SerialMousePacket *) packet;
- (void) parseIntelliMousePacket : (SerialMousePacket *) packet;

/* Serial port control */
- (IOReturn) configureSerialPort;
- (IOReturn) powerOnMouse;
- (IOReturn) powerOffMouse;
- (IOReturn) sendIdentificationRequest;

/* IOEventSource protocol methods */
- (Boolean) dispatchEvent : (void *) event;
- (void) enableEvents;
- (void) disableEvents;

@end

#endif /* _SERIAL_POINTING_DEVICE_H */
