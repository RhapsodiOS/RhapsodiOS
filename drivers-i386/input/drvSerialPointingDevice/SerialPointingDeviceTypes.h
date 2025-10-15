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
 * SerialPointingDeviceTypes.h - Type definitions for serial pointing devices
 */

#ifndef _SERIAL_POINTING_DEVICE_TYPES_H
#define _SERIAL_POINTING_DEVICE_TYPES_H

#import <sys/types.h>
#import "SerialMouseProtocols.h"

/* ========== Serial Mouse Button States ========== */
typedef struct {
    Boolean         left;               /* Left button pressed */
    Boolean         right;              /* Right button pressed */
    Boolean         middle;             /* Middle button pressed */
    Boolean         button4;            /* 4th button (5-button mice) */
    Boolean         button5;            /* 5th button (5-button mice) */
} SerialMouseButtons;

/* ========== Serial Mouse Movement ========== */
typedef struct {
    int             deltaX;             /* X movement delta */
    int             deltaY;             /* Y movement delta */
    int             wheelDelta;         /* Wheel movement delta */
    SerialMouseButtons buttons;         /* Button states */
    UInt32          timestamp;          /* Event timestamp */
} SerialMouseEvent;

/* ========== Serial Mouse Position ========== */
typedef struct {
    int             x;                  /* Absolute X position */
    int             y;                  /* Absolute Y position */
    int             wheelPosition;      /* Cumulative wheel position */
    SerialMouseButtons buttons;         /* Current button states */
} SerialMousePosition;

/* ========== Serial Mouse Configuration ========== */
typedef struct {
    SerialMouseProtocol protocol;       /* Mouse protocol */
    UInt32          baudRate;           /* Baud rate */
    UInt8           dataBits;           /* Data bits (7 or 8) */
    UInt8           stopBits;           /* Stop bits */
    UInt8           parity;             /* Parity */
    UInt32          sampleRate;         /* Desired sample rate */
    UInt32          acceleration;       /* Acceleration factor */
    UInt32          threshold;          /* Acceleration threshold */
    Boolean         autoPower;          /* Power via DTR/RTS */
} SerialMouseConfig;

/* ========== Serial Mouse Capabilities ========== */
typedef struct {
    SerialMouseProtocol protocol;       /* Detected protocol */
    Boolean         hasWheel;           /* Has scroll wheel */
    UInt8           buttonCount;        /* Number of buttons */
    UInt32          maxBaudRate;        /* Maximum baud rate */
    Boolean         supportsPnP;        /* Supports Plug and Play */
    char            pnpID[32];          /* PnP identification string */
} SerialMouseCapabilities;

/* ========== Serial Mouse Statistics ========== */
typedef struct {
    UInt64          totalEvents;        /* Total events processed */
    UInt64          buttonClicks;       /* Total button clicks */
    UInt64          wheelScrolls;       /* Total wheel scrolls */
    UInt64          packetsReceived;    /* Packets received */
    UInt64          syncErrors;         /* Sync byte errors */
    UInt64          framingErrors;      /* Framing errors */
    UInt64          overrunErrors;      /* Buffer overruns */
    UInt32          maxDeltaX;          /* Maximum X delta seen */
    UInt32          maxDeltaY;          /* Maximum Y delta seen */
} SerialMouseStats;

/* ========== Packet Buffer ========== */
#define MAX_PACKET_SIZE         5       /* Maximum packet size */

typedef struct {
    UInt8           data[MAX_PACKET_SIZE];  /* Packet data */
    UInt8           length;                  /* Current length */
    UInt8           expectedLength;          /* Expected length */
    Boolean         complete;                /* Packet is complete */
} SerialMousePacket;

/* ========== Event Queue Entry ========== */
typedef struct {
    SerialMouseEvent event;             /* Mouse event */
    Boolean         valid;              /* Entry is valid */
} SerialMouseQueueEntry;

/* ========== Serial Port Settings ========== */
typedef struct {
    const char      *portName;          /* Port name (e.g., "/dev/cuaa0") */
    UInt16          portBase;           /* I/O port base (for direct access) */
    UInt32          irq;                /* IRQ number */
} SerialPortInfo;

/* ========== IOKit Return Codes ========== */
/* Extended return codes for serial mouse operations */
#define SMOUSE_IO_R_SUCCESS         0       /* Success */
#define SMOUSE_IO_R_NOT_DETECTED    (-1)    /* Mouse not detected */
#define SMOUSE_IO_R_TIMEOUT         (-2)    /* Operation timeout */
#define SMOUSE_IO_R_SYNC_ERROR      (-3)    /* Sync byte error */
#define SMOUSE_IO_R_QUEUE_FULL      (-4)    /* Event queue full */
#define SMOUSE_IO_R_NO_EVENT        (-5)    /* No event available */
#define SMOUSE_IO_R_PROTOCOL_ERROR  (-6)    /* Protocol error */
#define SMOUSE_IO_R_PORT_ERROR      (-7)    /* Serial port error */

#endif /* _SERIAL_POINTING_DEVICE_TYPES_H */
