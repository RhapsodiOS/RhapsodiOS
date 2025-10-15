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
 * ParallelPortDriver.h - Standard PC Parallel Port Driver
 *
 * Supports LPT1-LPT3 parallel ports with SPP, EPP, and ECP modes
 * Compatible with IEEE 1284 standard
 */

#ifndef _PARALLEL_PORT_DRIVER_H
#define _PARALLEL_PORT_DRIVER_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/IODevice.h>
#import <driverkit/IOPower.h>
#import <kernserv/queue.h>
#import "ParallelPortTypes.h"

/* Debug flags */
#define PP_DEBUG                0
#define PP_TRACE                0

/* Default settings */
#define DEFAULT_MODE            PP_MODE_SPP
#define DEFAULT_TIMEOUT         1000000 /* 1 second in microseconds */

/* Buffer sizes */
#define TX_BUFFER_SIZE          8192
#define RX_BUFFER_SIZE          8192

/* Standard parallel port addresses */
#define LPT1_BASE               0x378
#define LPT1_IRQ                7
#define LPT2_BASE               0x278
#define LPT2_IRQ                5
#define LPT3_BASE               0x3BC
#define LPT3_IRQ                7

/* ECP mode base offsets */
#define ECP_BASE_OFFSET         0x400

@interface ParallelPortDriver : IODirectDevice <IOPower>
{
    /* Hardware resources */
    UInt16              basePort;               /* I/O port base address */
    UInt16              ecpBase;                /* ECP base (if supported) */
    UInt32              irqNumber;              /* IRQ line */
    UInt32              dmaChannel;             /* DMA channel (ECP mode) */
    port_t              interruptPort;          /* Interrupt message port */

    /* Port capabilities */
    ParallelPortCapabilities capabilities;      /* Detected capabilities */

    /* Port configuration */
    ParallelPortMode    currentMode;            /* Current operating mode */
    ParallelPortDirection direction;            /* Current direction */
    BOOL                irqEnabled;             /* IRQ enabled */
    BOOL                dmaEnabled;             /* DMA enabled */
    UInt32              timeout;                /* Operation timeout (µs) */

    /* Port state */
    BOOL                portOpen;               /* Port is open */
    BOOL                portBusy;               /* Port is busy */
    BOOL                online;                 /* Device is online */

    /* Status signals */
    BOOL                busy;                   /* BUSY signal state */
    BOOL                ack;                    /* ACK signal state */
    BOOL                paperOut;               /* PAPER OUT signal state */
    BOOL                selectIn;               /* SELECT signal state */
    BOOL                error;                  /* ERROR signal state */

    /* Control signals */
    BOOL                strobe;                 /* STROBE signal state */
    BOOL                autoFeed;               /* AUTO FEED signal state */
    BOOL                init;                   /* INIT signal state */
    BOOL                selectOut;              /* SELECT OUT signal state */

    /* Transmit buffer */
    UInt8               *txBuffer;              /* TX buffer */
    UInt32              txBufferSize;           /* TX buffer size */
    UInt32              txHead;                 /* TX buffer head */
    UInt32              txTail;                 /* TX buffer tail */
    UInt32              txCount;                /* Bytes in TX buffer */
    id                  txLock;                 /* TX buffer lock */

    /* Receive buffer */
    UInt8               *rxBuffer;              /* RX buffer */
    UInt32              rxBufferSize;           /* RX buffer size */
    UInt32              rxHead;                 /* RX buffer head */
    UInt32              rxTail;                 /* RX buffer tail */
    UInt32              rxCount;                /* Bytes in RX buffer */
    id                  rxLock;                 /* RX buffer lock */

    /* Transfer statistics */
    ParallelPortStats   stats;                  /* Statistics counters */

    /* IEEE 1284 Device ID */
    ParallelPortDeviceID deviceID;              /* Cached device ID */
    BOOL                deviceIDValid;          /* Device ID is valid */

    /* Thread synchronization */
    id                  stateLock;              /* Port state lock */

    /* Transfer queue */
    queue_head_t        transferQueue;          /* Pending transfers */
    id                  queueLock;              /* Queue lock */
}

/* Initialization and probing */
+ (Boolean) probe : deviceDescription;
- initFromDeviceDescription : deviceDescription;
- free;

/* Port control */
- (IOReturn) openPort;
- (IOReturn) closePort;
- (IOReturn) resetPort;

/* Mode configuration */
- (IOReturn) setMode : (ParallelPortMode) mode;
- (IOReturn) getMode : (ParallelPortMode *) mode;
- (IOReturn) setDirection : (ParallelPortDirection) dir;
- (IOReturn) getDirection : (ParallelPortDirection *) dir;

/* Capabilities query */
- (IOReturn) getCapabilities : (ParallelPortCapabilities *) caps;

/* Data transfer - SPP mode */
- (IOReturn) writeByte : (UInt8) byte;
- (IOReturn) readByte : (UInt8 *) byte;
- (IOReturn) writeBytes : (const UInt8 *) buffer
                  length : (UInt32) length
            bytesWritten : (UInt32 *) bytesWritten;
- (IOReturn) readBytes : (UInt8 *) buffer
                 length : (UInt32) length
               bytesRead : (UInt32 *) bytesRead;

/* EPP mode transfers */
- (IOReturn) eppWriteAddress : (UInt8) address;
- (IOReturn) eppReadAddress : (UInt8 *) address;
- (IOReturn) eppWriteData : (const UInt8 *) buffer
                    length : (UInt32) length;
- (IOReturn) eppReadData : (UInt8 *) buffer
                   length : (UInt32) length;

/* ECP mode transfers */
- (IOReturn) ecpWrite : (const UInt8 *) buffer
                length : (UInt32) length
          bytesWritten : (UInt32 *) bytesWritten;
- (IOReturn) ecpRead : (UInt8 *) buffer
               length : (UInt32) length
             bytesRead : (UInt32 *) bytesRead;

/* IEEE 1284 operations */
- (IOReturn) negotiate1284Mode : (ParallelPortMode) mode;
- (IOReturn) terminate1284Mode;
- (IOReturn) getDeviceID : (ParallelPortDeviceID *) deviceID;

/* Status queries */
- (IOReturn) getStatus : (ParallelPortStatus *) status;
- (BOOL) isBusy;
- (BOOL) isOnline;
- (BOOL) isPaperOut;
- (BOOL) isError;

/* Control signals */
- (IOReturn) setStrobe : (BOOL) state;
- (IOReturn) setAutoFeed : (BOOL) state;
- (IOReturn) setInit : (BOOL) state;
- (IOReturn) setSelectOut : (BOOL) state;

/* Timeout configuration */
- (IOReturn) setTimeout : (UInt32) microseconds;
- (IOReturn) getTimeout : (UInt32 *) microseconds;

/* Buffer control */
- (IOReturn) flushTxBuffer;
- (IOReturn) flushRxBuffer;

/* Interrupt handling */
- (void) interruptOccurred;

/* Statistics */
- (IOReturn) getStatistics : (ParallelPortStats *) stats;
- (IOReturn) resetStatistics;

/* Low-level hardware access (for debugging) */
- (UInt8) readDataReg;
- (void) writeDataReg : (UInt8) value;
- (UInt8) readStatusReg;
- (UInt8) readControlReg;
- (void) writeControlReg : (UInt8) value;

/* Kernel thread and queue management */
- (void) minPhys : (struct buf *) bp;
- (int) strategyThread;
- (void) handleInterrupt;
- (IOReturn) attachInterrupt : (UInt32) irq;
- (void) detachInterrupt;

/* Buffer and transfer queue operations */
- (IOReturn) enqueueTransfer : (void *) transfer;
- (void *) dequeueTransfer;
- (IOReturn) abortTransfer : (void *) transfer;
- (void) processTransferQueue;

/* Device node operations */
- (IOReturn) createDeviceNode : (const char *) path
                   minorNumber : (UInt32) minor;
- (IOReturn) removeDeviceNode;

/* Power management */
- (IOReturn) setPowerState : (UInt32) state;
- (IOReturn) getPowerState : (UInt32 *) state;

/* Lock management extensions */
- (id) allocLock;
- (void) lock : (id) lockObj;
- (void) unlock : (id) lockObj;
- (void) freeLock : (id) lockObj;

@end

#endif /* _PARALLEL_PORT_DRIVER_H */
