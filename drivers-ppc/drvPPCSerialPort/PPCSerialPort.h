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
 * PPCSerialPort.h - PowerPC Zilog 8530 SCC Serial Port Driver
 *
 * Supports PowerMac serial ports (Printer and Modem ports)
 * Based on Zilog 8530 SCC (Serial Communications Controller)
 */

#ifndef _PPC_SERIAL_PORT_H
#define _PPC_SERIAL_PORT_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/IODevice.h>
#import <driverkit/IOPower.h>
#import <kernserv/queue.h>
#import "PPCSerialTypes.h"

/* Debug flags */
#define PPC_SERIAL_DEBUG        0
#define PPC_SERIAL_TRACE        0

/* Default settings */
#define DEFAULT_BAUD_RATE       38400
#define DEFAULT_DATA_BITS       8
#define DEFAULT_STOP_BITS       1
#define DEFAULT_PARITY          PARITY_NONE

/* Buffer sizes */
#define TX_BUFFER_SIZE          4096
#define RX_BUFFER_SIZE          4096

/* Channel definitions */
#define SCC_CHANNEL_A           0       /* Usually modem port */
#define SCC_CHANNEL_B           1       /* Usually printer port */

/* Timeout values */
#define TX_TIMEOUT              1000    /* 1 second */
#define RX_TIMEOUT              100     /* 100ms */

@interface PPCSerialPort : IODirectDevice <IOPower>
{
    /* Hardware resources */
    vm_address_t        baseAddress;            /* SCC base address (logical) */
    PhysicalAddress     basePhysical;           /* SCC base address (physical) */
    UInt32              registerLength;         /* Register space size */
    UInt8               channel;                /* Channel (A or B) */
    UInt32              irqNumber;              /* IRQ line */
    port_t              interruptPort;          /* Interrupt message port */

    /* Clock information */
    UInt32              clockRate;              /* SCC clock rate (Hz) */
    UInt32              brg_rate;               /* BRG generated rate */

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

    /* Thread synchronization */
    id                  stateLock;              /* Port state lock */

    /* AppleTalk compatibility */
    BOOL                appleTalkMode;          /* AppleTalk SDLC mode */
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
- (IOReturn) getDCD : (BOOL *) state;

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

/* AppleTalk support */
- (IOReturn) setAppleTalkMode : (BOOL) enable;

@end

#endif /* _PPC_SERIAL_PORT_H */
