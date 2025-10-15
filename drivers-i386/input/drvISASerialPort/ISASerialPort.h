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
 * ISASerialPort.h - ISA 16550 UART Serial Port Driver for RhapsodiOS
 *
 * Supports standard PC COM ports (COM1-COM4) with 16550A UART
 * Based on industry-standard PC serial architecture
 */

#ifndef _ISA_SERIAL_PORT_H
#define _ISA_SERIAL_PORT_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/IODevice.h>
#import <driverkit/IOPower.h>
#import <kernserv/queue.h>
#import "ISASerialTypes.h"

/* Debug flags */
#define ISA_SERIAL_DEBUG        0
#define ISA_SERIAL_TRACE        0

/* Default settings */
#define DEFAULT_BAUD_RATE       9600
#define DEFAULT_DATA_BITS       8
#define DEFAULT_STOP_BITS       1
#define DEFAULT_PARITY          PARITY_NONE

/* Buffer sizes */
#define TX_BUFFER_SIZE          4096
#define RX_BUFFER_SIZE          4096
#define FIFO_SIZE               16

/* Port definitions for standard ISA COM ports */
#define COM1_BASE               0x3F8
#define COM1_IRQ                4
#define COM2_BASE               0x2F8
#define COM2_IRQ                3
#define COM3_BASE               0x3E8
#define COM3_IRQ                4
#define COM4_BASE               0x2E8
#define COM4_IRQ                3

/* Timeout values */
#define TX_TIMEOUT              1000    /* 1 second */
#define RX_TIMEOUT              100     /* 100ms */

@interface ISASerialPort : IODirectDevice <IOPower>
{
    /* Hardware resources */
    UInt16              basePort;               /* I/O port base address */
    UInt32              irqNumber;              /* IRQ line */
    port_t              interruptPort;          /* Interrupt message port */

    /* UART type and capabilities */
    UARTType            uartType;               /* Detected UART type */
    BOOL                hasFIFO;                /* FIFO support flag */
    UInt8               fifoSize;               /* FIFO depth */

    /* Port configuration */
    UInt32              baudRate;               /* Baud rate (bps) */
    UInt8               dataBits;               /* Data bits (5-8) */
    UInt8               stopBits;               /* Stop bits (1 or 2) */
    ParityType          parity;                 /* Parity setting */
    FlowControl         flowControl;            /* Flow control mode */

    /* Port state */
    BOOL                portOpen;               /* Port is open */
    BOOL                txEnabled;              /* Transmitter enabled */
    BOOL                rxEnabled;              /* Receiver enabled */
    BOOL                dtrState;               /* DTR signal state */
    BOOL                rtsState;               /* RTS signal state */

    /* Modem status */
    BOOL                ctsState;               /* CTS signal state */
    BOOL                dsrState;               /* DSR signal state */
    BOOL                riState;                /* RI signal state */
    BOOL                dcdState;               /* DCD signal state */

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

    /* Error statistics */
    UInt32              parityErrors;           /* Parity error count */
    UInt32              framingErrors;          /* Framing error count */
    UInt32              overrunErrors;          /* Overrun error count */
    UInt32              breakDetects;           /* Break detect count */
    UInt32              fifoErrors;             /* FIFO error count */

    /* Thread synchronization */
    id                  stateLock;              /* Port state lock */
}

/* Initialization and probing */
+ (Boolean) probe : deviceDescription;
- initFromDeviceDescription : deviceDescription;
- free;

/* Port control */
- (IOReturn) openPort;
- (IOReturn) closePort;
- (IOReturn) setPortConfig : (SerialPortConfig *) config;
- (IOReturn) getPortConfig : (SerialPortConfig *) config;

/* Data transfer */
- (IOReturn) writeBytes : (const UInt8 *) buffer
                  length : (UInt32) length
            bytesWritten : (UInt32 *) bytesWritten;

- (IOReturn) readBytes : (UInt8 *) buffer
                 length : (UInt32) length
               bytesRead : (UInt32 *) bytesRead;

/* Flow control */
- (IOReturn) setFlowControl : (FlowControl) mode;
- (IOReturn) getFlowControl : (FlowControl *) mode;

/* Modem control */
- (IOReturn) setDTR : (BOOL) state;
- (IOReturn) setRTS : (BOOL) state;
- (IOReturn) getDTR : (BOOL *) state;
- (IOReturn) getRTS : (BOOL *) state;

/* Modem status */
- (IOReturn) getCTS : (BOOL *) state;
- (IOReturn) getDSR : (BOOL *) state;
- (IOReturn) getDCD : (BOOL *) state;
- (IOReturn) getRI : (BOOL *) state;

/* Buffer control */
- (IOReturn) flushTxBuffer;
- (IOReturn) flushRxBuffer;
- (IOReturn) getTxBufferSpace : (UInt32 *) space;
- (IOReturn) getRxDataAvailable : (UInt32 *) available;

/* Interrupt handling */
- (void) interruptOccurred;

/* Statistics */
- (IOReturn) getStatistics : (SerialPortStats *) stats;
- (IOReturn) resetStatistics;

@end

#endif /* _ISA_SERIAL_PORT_H */
