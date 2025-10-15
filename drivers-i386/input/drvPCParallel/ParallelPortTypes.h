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
 * ParallelPortTypes.h - Type definitions for parallel port driver
 */

#ifndef _PARALLEL_PORT_TYPES_H
#define _PARALLEL_PORT_TYPES_H

#import <sys/types.h>

/* ========== Parallel Port Modes ========== */
typedef enum {
    PP_MODE_SPP = 0,            /* Standard Parallel Port (Centronics) */
    PP_MODE_PS2,                /* PS/2 Bidirectional mode */
    PP_MODE_EPP,                /* Enhanced Parallel Port (EPP) */
    PP_MODE_ECP,                /* Extended Capabilities Port (ECP) */
    PP_MODE_AUTO                /* Auto-detect best mode */
} ParallelPortMode;

/* ========== Port Direction ========== */
typedef enum {
    PP_DIRECTION_OUTPUT = 0,    /* Output mode (to printer) */
    PP_DIRECTION_INPUT          /* Input mode (from printer) */
} ParallelPortDirection;

/* ========== Port Capabilities ========== */
typedef struct {
    Boolean         hasSPP;             /* Supports SPP mode */
    Boolean         hasPS2;             /* Supports PS/2 bidirectional */
    Boolean         hasEPP;             /* Supports EPP mode */
    Boolean         hasECP;             /* Supports ECP mode */
    Boolean         hasFIFO;            /* Has FIFO buffer */
    Boolean         hasDMA;             /* Supports DMA */
    Boolean         hasIRQ;             /* Supports interrupts */
    UInt8           fifoSize;           /* FIFO depth (0 if none) */
    UInt32          maxSpeed;           /* Maximum transfer rate (bytes/sec) */
} ParallelPortCapabilities;

/* ========== Port Configuration ========== */
typedef struct {
    ParallelPortMode    mode;           /* Operating mode */
    ParallelPortDirection direction;    /* Data direction */
    Boolean             irqEnabled;     /* IRQ enabled */
    Boolean             dmaEnabled;     /* DMA enabled */
    UInt32              timeout;        /* Operation timeout (µs) */
} ParallelPortConfig;

/* ========== Port Status ========== */
typedef struct {
    Boolean         busy;               /* Printer busy */
    Boolean         ack;                /* Acknowledge signal */
    Boolean         paperOut;           /* Out of paper */
    Boolean         selectIn;           /* Printer selected */
    Boolean         error;              /* Error condition */
    Boolean         online;             /* Printer online */
} ParallelPortStatus;

/* ========== Transfer Statistics ========== */
typedef struct {
    UInt64          bytesWritten;       /* Total bytes written */
    UInt64          bytesRead;          /* Total bytes read */
    UInt32          writeErrors;        /* Write error count */
    UInt32          readErrors;         /* Read error count */
    UInt32          timeoutErrors;      /* Timeout error count */
    UInt32          fifoOverruns;       /* FIFO overrun count */
    UInt32          interrupts;         /* Interrupt count */
} ParallelPortStats;

/* ========== IEEE 1284 Device ID ========== */
#define PP_DEVICE_ID_MAX        1024    /* Maximum device ID length */

typedef struct {
    UInt16          length;             /* ID string length */
    char            data[PP_DEVICE_ID_MAX]; /* ID string data */
} ParallelPortDeviceID;

/* ========== EPP Address/Data Structure ========== */
typedef struct {
    UInt8           address;            /* EPP address */
    UInt8           *data;              /* Data buffer */
    UInt32          length;             /* Transfer length */
} ParallelPortEPPTransfer;

/* ========== ECP Channel Structure ========== */
typedef enum {
    ECP_CHANNEL_FWD = 0,        /* Forward channel (host to device) */
    ECP_CHANNEL_REV             /* Reverse channel (device to host) */
} ECPChannel;

typedef struct {
    ECPChannel      channel;            /* Channel direction */
    UInt8           *data;              /* Data buffer */
    UInt32          length;             /* Transfer length */
    Boolean         useFIFO;            /* Use FIFO for transfer */
} ParallelPortECPTransfer;

/* ========== IOKit Return Codes ========== */
/* Extended return codes for parallel port operations */
#define PP_IO_R_SUCCESS         0       /* Success */
#define PP_IO_R_TIMEOUT         (-1)    /* Operation timeout */
#define PP_IO_R_BUSY            (-2)    /* Device busy */
#define PP_IO_R_OFFLINE         (-3)    /* Device offline */
#define PP_IO_R_PAPER_OUT       (-4)    /* Out of paper */
#define PP_IO_R_ERROR           (-5)    /* General error */
#define PP_IO_R_NOT_SUPPORTED   (-6)    /* Operation not supported */
#define PP_IO_R_INVALID_MODE    (-7)    /* Invalid mode */
#define PP_IO_R_FIFO_ERROR      (-8)    /* FIFO error */

#endif /* _PARALLEL_PORT_TYPES_H */
