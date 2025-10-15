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
 * BusMouseTypes.h - Type definitions for bus mouse driver
 */

#ifndef _BUS_MOUSE_TYPES_H
#define _BUS_MOUSE_TYPES_H

#import <sys/types.h>

/* ========== Mouse Types ========== */
typedef enum {
    MOUSE_TYPE_UNKNOWN = 0,     /* Unknown/not detected */
    MOUSE_TYPE_INPORT,          /* Microsoft InPort mouse */
    MOUSE_TYPE_LOGITECH,        /* Logitech bus mouse */
    MOUSE_TYPE_ATI              /* ATI XL mouse (InPort compatible) */
} BusMouseType;

/* ========== Mouse Button States ========== */
typedef struct {
    Boolean         left;               /* Left button pressed */
    Boolean         right;              /* Right button pressed */
    Boolean         middle;             /* Middle button pressed */
} BusMouseButtons;

/* ========== Mouse Movement ========== */
typedef struct {
    int             deltaX;             /* X movement delta */
    int             deltaY;             /* Y movement delta */
    BusMouseButtons buttons;            /* Button states */
    UInt32          timestamp;          /* Event timestamp */
} BusMouseEvent;

/* ========== Mouse Position ========== */
typedef struct {
    int             x;                  /* Absolute X position */
    int             y;                  /* Absolute Y position */
    BusMouseButtons buttons;            /* Current button states */
} BusMousePosition;

/* ========== Mouse Configuration ========== */
typedef struct {
    UInt32          sampleRate;         /* Sample rate in Hz */
    Boolean         irqEnabled;         /* IRQ enabled */
    Boolean         quadratureMode;     /* Quadrature mode (InPort) */
    UInt32          acceleration;       /* Acceleration factor (1-10) */
    UInt32          threshold;          /* Acceleration threshold */
} BusMouseConfig;

/* ========== Mouse Capabilities ========== */
typedef struct {
    BusMouseType    mouseType;          /* Detected mouse type */
    Boolean         hasThreeButtons;    /* Has middle button */
    UInt32          maxSampleRate;      /* Maximum sample rate */
    Boolean         supportsIRQ;        /* Supports interrupts */
    Boolean         supportsQuadrature; /* Supports quadrature mode */
} BusMouseCapabilities;

/* ========== Mouse Statistics ========== */
typedef struct {
    UInt64          totalEvents;        /* Total events processed */
    UInt64          buttonClicks;       /* Total button clicks */
    UInt64          interrupts;         /* Interrupt count */
    UInt64          overruns;           /* Event buffer overruns */
    UInt64          errors;             /* Error count */
    UInt32          maxDeltaX;          /* Maximum X delta seen */
    UInt32          maxDeltaY;          /* Maximum Y delta seen */
} BusMouseStats;

/* ========== Mouse Event Queue Entry ========== */
typedef struct {
    BusMouseEvent   event;              /* Mouse event */
    Boolean         valid;              /* Entry is valid */
} BusMouseQueueEntry;

/* ========== Mouse Resolution ========== */
typedef enum {
    MOUSE_RES_LOW = 1,          /* Low resolution (1 count/mm) */
    MOUSE_RES_MEDIUM = 2,       /* Medium resolution (2 counts/mm) */
    MOUSE_RES_HIGH = 3,         /* High resolution (3 counts/mm) */
    MOUSE_RES_VERY_HIGH = 4     /* Very high resolution (4 counts/mm) */
} BusMouseResolution;

/* ========== IOKit Return Codes ========== */
/* Extended return codes for bus mouse operations */
#define MOUSE_IO_R_SUCCESS          0       /* Success */
#define MOUSE_IO_R_NOT_DETECTED     (-1)    /* Mouse not detected */
#define MOUSE_IO_R_TIMEOUT          (-2)    /* Operation timeout */
#define MOUSE_IO_R_QUEUE_FULL       (-3)    /* Event queue full */
#define MOUSE_IO_R_NO_EVENT         (-4)    /* No event available */
#define MOUSE_IO_R_RESET_FAILED     (-5)    /* Reset failed */

#endif /* _BUS_MOUSE_TYPES_H */
