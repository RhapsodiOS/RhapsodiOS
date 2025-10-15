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
 * SerialMouseProtocols.h - Serial Mouse Protocol Definitions
 *
 * Supports Microsoft, MouseSystems, Logitech, and wheel mouse protocols
 */

#ifndef _SERIAL_MOUSE_PROTOCOLS_H
#define _SERIAL_MOUSE_PROTOCOLS_H

/* ========== Serial Mouse Protocols ========== */
typedef enum {
    PROTOCOL_UNKNOWN = 0,       /* Unknown/not detected */
    PROTOCOL_MICROSOFT,         /* Microsoft 2-button (1200 baud, 7N1) */
    PROTOCOL_MICROSOFT_3BTN,    /* Microsoft 3-button */
    PROTOCOL_MOUSESYSTEMS,      /* MouseSystems 3-button (1200 baud, 8N1) */
    PROTOCOL_MOUSESYSTEMS_5BTN, /* MouseSystems 5-button */
    PROTOCOL_LOGITECH,          /* Logitech MouseMan */
    PROTOCOL_MM,                /* MM Series */
    PROTOCOL_INTELLIMOUSE,      /* Microsoft IntelliMouse (wheel) */
    PROTOCOL_INTELLIMOUSE_EX    /* Microsoft IntelliMouse Explorer (5-button + wheel) */
} SerialMouseProtocol;

/* ========== Microsoft Serial Mouse Protocol ========== */

/* Microsoft 2-button protocol (3 bytes) */
#define MS_SYNC_BYTE            0x40    /* Bit 6 must be set */
#define MS_SYNC_MASK            0x40

/* Byte 1 (sync byte) */
#define MS_B1_LEFT_BUTTON       0x20    /* Left button */
#define MS_B1_RIGHT_BUTTON      0x10    /* Right button */
#define MS_B1_Y_SIGN            0x08    /* Y sign bit (1=negative) */
#define MS_B1_Y_HIGH            0x0C    /* Y high bits */
#define MS_B1_X_SIGN            0x04    /* X sign bit (1=negative) */
#define MS_B1_X_HIGH            0x03    /* X high bits */

/* Bytes 2-3 (movement data) */
#define MS_MOVEMENT_MASK        0x3F    /* Movement data mask */

/* Microsoft 3-button extension (4th byte) */
#define MS_B4_MIDDLE_BUTTON     0x20    /* Middle button */

/* Microsoft wheel extension (4th byte for IntelliMouse) */
#define MS_B4_WHEEL_MASK        0x0F    /* Wheel movement mask */
#define MS_B4_WHEEL_SIGN        0x08    /* Wheel sign bit */

/* Packet sizes */
#define MS_PACKET_SIZE          3       /* Standard Microsoft */
#define MS_3BTN_PACKET_SIZE     4       /* 3-button */
#define MS_WHEEL_PACKET_SIZE    4       /* IntelliMouse */

/* ========== MouseSystems Protocol ========== */

/* MouseSystems 5-byte protocol */
#define MSC_SYNC_BYTE           0x80    /* Sync byte value */
#define MSC_SYNC_MASK           0xF8    /* Sync mask */

/* Byte 1 (buttons and sync) */
#define MSC_B1_LEFT_BUTTON      0x04    /* Left button (0=pressed) */
#define MSC_B1_MIDDLE_BUTTON    0x02    /* Middle button (0=pressed) */
#define MSC_B1_RIGHT_BUTTON     0x01    /* Right button (0=pressed) */

/* Movement bytes are signed 8-bit values */
#define MSC_PACKET_SIZE         5       /* Standard packet size */

/* ========== Logitech MouseMan Protocol ========== */

/* Logitech uses Microsoft format with extensions */
#define LOGI_3BTN_PACKET_SIZE   3       /* 3-button packet */
#define LOGI_WHEEL_PACKET_SIZE  4       /* Wheel packet */

/* Middle button in byte 4 */
#define LOGI_B4_MIDDLE_BUTTON   0x20

/* ========== MM Series Protocol ========== */

/* MM series uses modified Microsoft format */
#define MM_PACKET_SIZE          3

/* ========== Auto-detection Signatures ========== */

/* Microsoft mouse identification */
#define MS_IDENT_CHAR           'M'     /* Response to identification request */

/* MouseSystems doesn't respond to identification */

/* Logitech identification */
#define LOGI_IDENT_CHAR         'L'     /* Some Logitech mice respond with 'L' */

/* ========== Serial Settings ========== */

/* Baud rates */
#define MOUSE_BAUD_1200         1200    /* Standard for most serial mice */
#define MOUSE_BAUD_2400         2400    /* Some mice support higher rates */
#define MOUSE_BAUD_4800         4800
#define MOUSE_BAUD_9600         9600

/* Data formats */
#define MOUSE_DATA_BITS_7       7       /* Microsoft protocol */
#define MOUSE_DATA_BITS_8       8       /* MouseSystems protocol */

#define MOUSE_STOP_BITS_1       1
#define MOUSE_STOP_BITS_2       2

#define MOUSE_PARITY_NONE       0
#define MOUSE_PARITY_ODD        1
#define MOUSE_PARITY_EVEN       2

/* ========== DTR/RTS Control ========== */

/* Most serial mice are powered by DTR and RTS */
#define MOUSE_POWER_DTR         YES     /* DTR high */
#define MOUSE_POWER_RTS         YES     /* RTS high */

/* Some mice require toggling RTS for reset/identification */
#define MOUSE_RESET_DELAY       200000  /* 200ms reset delay */
#define MOUSE_IDENT_DELAY       100000  /* 100ms identification delay */

/* ========== Movement Limits ========== */
#define MAX_DELTA_MS            127     /* Microsoft max delta */
#define MIN_DELTA_MS            -128    /* Microsoft min delta */
#define MAX_DELTA_MSC           127     /* MouseSystems max delta */
#define MIN_DELTA_MSC           -128    /* MouseSystems min delta */

/* ========== Wheel Support ========== */
#define WHEEL_UP                1       /* Wheel scrolled up */
#define WHEEL_DOWN              -1      /* Wheel scrolled down */
#define WHEEL_NONE              0       /* No wheel movement */

/* ========== IntelliMouse PnP IDs ========== */
#define PNPID_INTELLIMOUSE      "MSHMOU" /* IntelliMouse (wheel) */
#define PNPID_INTELLIMOUSE_EX   "MSH0001" /* IntelliMouse Explorer */

/* ========== Detection Timeouts ========== */
#define DETECT_TIMEOUT          500000  /* 500ms for auto-detection */
#define PACKET_TIMEOUT          100000  /* 100ms between bytes */

#endif /* _SERIAL_MOUSE_PROTOCOLS_H */
