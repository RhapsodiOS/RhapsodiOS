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
 * PPCSerialTypes.h - Type definitions for PPC Serial Port Driver
 */

#ifndef _PPC_SERIAL_TYPES_H
#define _PPC_SERIAL_TYPES_H

#import <mach/mach_types.h>

/* Physical address type */
typedef UInt32 PhysicalAddress;

/* Parity types */
typedef enum {
    PARITY_NONE = 0,
    PARITY_ODD,
    PARITY_EVEN,
    PARITY_MARK,
    PARITY_SPACE
} ParityType;

/* Flow control modes */
typedef enum {
    FLOW_NONE = 0,          /* No flow control */
    FLOW_XONXOFF,           /* Software (XON/XOFF) */
    FLOW_RTSCTS,            /* Hardware (RTS/CTS) */
    FLOW_DTRDSR             /* Hardware (DTR/DSR) */
} FlowControl;

/* Serial port configuration */
typedef struct {
    UInt32          baudRate;       /* Baud rate */
    UInt8           dataBits;       /* Data bits (5-8) */
    UInt8           stopBits;       /* Stop bits (1-2) */
    ParityType      parity;         /* Parity */
    FlowControl     flowControl;    /* Flow control mode */
} SerialPortConfig;

/* Serial port statistics */
typedef struct {
    UInt32          txBytes;        /* Bytes transmitted */
    UInt32          rxBytes;        /* Bytes received */
    UInt32          parityErrors;   /* Parity errors */
    UInt32          framingErrors;  /* Framing errors */
    UInt32          overrunErrors;  /* Overrun errors */
    UInt32          breakDetects;   /* Break detects */
} SerialPortStats;

/* Standard baud rates */
#define BAUD_110        110
#define BAUD_300        300
#define BAUD_600        600
#define BAUD_1200       1200
#define BAUD_2400       2400
#define BAUD_4800       4800
#define BAUD_9600       9600
#define BAUD_14400      14400
#define BAUD_19200      19200
#define BAUD_28800      28800
#define BAUD_38400      38400
#define BAUD_57600      57600
#define BAUD_115200     115200
#define BAUD_230400     230400

/* XON/XOFF characters */
#define XON_CHAR        0x11
#define XOFF_CHAR       0x13

/* SCC clock rates (PowerMac) */
#define SCC_CLOCK_3672000       3672000  /* 3.672 MHz */
#define SCC_CLOCK_4915200       4915200  /* 4.9152 MHz */
#define SCC_CLOCK_DEFAULT       SCC_CLOCK_3672000

#endif /* _PPC_SERIAL_TYPES_H */
