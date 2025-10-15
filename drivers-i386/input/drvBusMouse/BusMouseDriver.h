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
 * BusMouseDriver.h - ISA Bus Mouse Driver
 *
 * Supports Microsoft InPort Mouse, Logitech Bus Mouse, and ATI XL Mouse
 * Compatible with standard ISA bus mouse cards
 */

#ifndef _BUS_MOUSE_DRIVER_H
#define _BUS_MOUSE_DRIVER_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/IODevice.h>
#import <driverkit/IOPower.h>
#import <driverkit/IOEventSource.h>
#import <kernserv/queue.h>
#import "BusMouseTypes.h"

/* Debug flags */
#define BUSMOUSE_DEBUG          0
#define BUSMOUSE_TRACE          0

/* Default settings */
#define DEFAULT_SAMPLE_RATE     100     /* 100 Hz */
#define DEFAULT_ACCELERATION    2       /* 2x acceleration */
#define DEFAULT_THRESHOLD       4       /* Acceleration threshold */

@interface BusMouseDriver : IODirectDevice <IOPower, IOEventSource>
{
    /* Hardware resources */
    UInt16              basePort;               /* I/O port base address */
    UInt32              irqNumber;              /* IRQ line */
    port_t              interruptPort;          /* Interrupt message port */

    /* Mouse type and capabilities */
    BusMouseType        mouseType;              /* Detected mouse type */
    BusMouseCapabilities capabilities;          /* Mouse capabilities */

    /* Mouse configuration */
    UInt32              sampleRate;             /* Current sample rate */
    Boolean             irqEnabled;             /* IRQ enabled */
    Boolean             quadratureMode;         /* Quadrature mode */
    UInt32              acceleration;           /* Acceleration factor */
    UInt32              threshold;              /* Acceleration threshold */

    /* Current state */
    Boolean             mouseOpen;              /* Mouse is open */
    BusMouseButtons     buttons;                /* Current button states */
    BusMousePosition    position;               /* Current position */

    /* Previous state (for delta calculation) */
    BusMouseButtons     prevButtons;            /* Previous button states */

    /* Event queue */
    BusMouseQueueEntry  *eventQueue;            /* Event queue buffer */
    UInt32              queueSize;              /* Queue size */
    UInt32              queueHead;              /* Queue head index */
    UInt32              queueTail;              /* Queue tail index */
    UInt32              queueCount;             /* Events in queue */
    id                  queueLock;              /* Queue lock */

    /* Statistics */
    BusMouseStats       stats;                  /* Statistics counters */

    /* Thread synchronization */
    id                  stateLock;              /* State lock */
}

/* Initialization and probing */
+ (Boolean) probe : deviceDescription;
- initFromDeviceDescription : deviceDescription;
- free;

/* Mouse control */
- (IOReturn) openMouse;
- (IOReturn) closeMouse;
- (IOReturn) resetMouse;

/* Configuration */
- (IOReturn) setConfig : (BusMouseConfig *) config;
- (IOReturn) getConfig : (BusMouseConfig *) config;
- (IOReturn) setSampleRate : (UInt32) rate;
- (IOReturn) getSampleRate : (UInt32 *) rate;
- (IOReturn) setAcceleration : (UInt32) accel
                    threshold : (UInt32) thresh;

/* Capabilities query */
- (IOReturn) getCapabilities : (BusMouseCapabilities *) caps;
- (BusMouseType) getMouseType;

/* Position and state */
- (IOReturn) getPosition : (BusMousePosition *) pos;
- (IOReturn) getButtons : (BusMouseButtons *) btns;
- (IOReturn) setPosition : (int) x
                        y : (int) y;

/* Event handling */
- (IOReturn) getEvent : (BusMouseEvent *) event;
- (IOReturn) peekEvent : (BusMouseEvent *) event;
- (Boolean) hasEvent;
- (IOReturn) flushEvents;

/* Interrupt handling */
- (void) interruptOccurred;

/* Statistics */
- (IOReturn) getStatistics : (BusMouseStats *) stats;
- (IOReturn) resetStatistics;

/* Low-level hardware access */
- (IOReturn) readMovement : (int *) deltaX
                   deltaY : (int *) deltaY
                  buttons : (BusMouseButtons *) buttons;

/* IOEventSource protocol methods */
- (Boolean) dispatchEvent : (void *) event;
- (void) enableEvents;
- (void) disableEvents;

@end

#endif /* _BUS_MOUSE_DRIVER_H */
