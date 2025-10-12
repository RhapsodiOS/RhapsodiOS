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
 * PPCSerialPort.m - PowerPC SCC Serial Port Driver Implementation
 */

#import "PPCSerialPort.h"
#import "PPCSerialRegs.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <mach/mach_interface.h>
#import <string.h>

@implementation PPCSerialPort

/*
 * Probe for PowerMac serial ports
 */
+ (Boolean) probe : deviceDescription
{
    PPCSerialPort *instance;
    const char *deviceName;

    /* Check device name for serial ports */
    deviceName = [deviceDescription nodeName];
    if (!deviceName) {
        return NO;
    }

    /* Look for "ch-a" or "ch-b" (SCC channels) */
    if (strcmp(deviceName, "ch-a") != 0 && strcmp(deviceName, "ch-b") != 0) {
        return NO;
    }

    /* Create instance */
    instance = [self alloc];
    if (instance == nil) {
        return NO;
    }

    /* Initialize */
    if ([instance initFromDeviceDescription:deviceDescription] == nil) {
        [instance free];
        return NO;
    }

    return YES;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription : deviceDescription
{
    const char *deviceName;
    IOReturn ioReturn;
    IORange *range;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Determine channel from device name */
    deviceName = [deviceDescription nodeName];
    if (strcmp(deviceName, "ch-a") == 0) {
        channel = SCC_CHANNEL_A;
    } else if (strcmp(deviceName, "ch-b") == 0) {
        channel = SCC_CHANNEL_B;
    } else {
        [self free];
        return nil;
    }

    /* Map SCC registers */
    range = [deviceDescription memoryRangeList];
    if (range == NULL || range->size == 0) {
        IOLog("PPCSerialPort: No memory range found\n");
        [self free];
        return nil;
    }

    basePhysical = range->start;
    registerLength = range->size;

    ioReturn = [self mapMemoryRange:0
                                 to:&baseAddress
                          findSpace:YES
                              cache:IO_CacheOff];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("PPCSerialPort: Failed to map registers\n");
        [self free];
        return nil;
    }

    /* Initialize state */
    portOpen = NO;
    txEnabled = NO;
    rxEnabled = NO;
    dtrState = NO;
    rtsState = NO;
    appleTalkMode = NO;

    /* Create locks */
    txLock = [[NXLock alloc] init];
    rxLock = [[NXLock alloc] init];
    stateLock = [[NXLock alloc] init];

    if (!txLock || !rxLock || !stateLock) {
        [self free];
        return nil;
    }

    /* Allocate buffers */
    txBuffer = (UInt8 *)IOMalloc(TX_BUFFER_SIZE);
    rxBuffer = (UInt8 *)IOMalloc(RX_BUFFER_SIZE);

    if (!txBuffer || !rxBuffer) {
        [self free];
        return nil;
    }

    txBufferSize = TX_BUFFER_SIZE;
    rxBufferSize = RX_BUFFER_SIZE;
    txHead = txTail = txCount = 0;
    rxHead = rxTail = rxCount = 0;

    /* Set default configuration */
    baudRate = DEFAULT_BAUD_RATE;
    dataBits = DEFAULT_DATA_BITS;
    stopBits = DEFAULT_STOP_BITS;
    parity = DEFAULT_PARITY;
    flowControl = FLOW_NONE;
    clockRate = SCC_CLOCK_DEFAULT;

    /* Reset statistics */
    parityErrors = 0;
    framingErrors = 0;
    overrunErrors = 0;
    breakDetects = 0;

    /* Reset SCC */
    [self resetSCC];

    /* Register device */
    [self registerDevice];

    IOLog("PPCSerialPort: Initialized channel %c\n",
          (channel == SCC_CHANNEL_A) ? 'A' : 'B');

    return self;
}

/*
 * Free resources
 */
- free
{
    if (portOpen) {
        [self closePort];
    }

    if (txBuffer) {
        IOFree(txBuffer, txBufferSize);
        txBuffer = NULL;
    }

    if (rxBuffer) {
        IOFree(rxBuffer, rxBufferSize);
        rxBuffer = NULL;
    }

    if (txLock) {
        [txLock free];
        txLock = nil;
    }

    if (rxLock) {
        [rxLock free];
        rxLock = nil;
    }

    if (stateLock) {
        [stateLock free];
        stateLock = nil;
    }

    if (baseAddress) {
        [self unmapMemoryRange:0 from:baseAddress];
        baseAddress = 0;
    }

    return [super free];
}

/*
 * Open serial port
 */
- (IOReturn) openPort
{
    [stateLock lock];

    if (portOpen) {
        [stateLock unlock];
        return IO_R_BUSY;
    }

    /* Configure SCC */
    [self configureSCC];

    /* Enable interrupts */
    [self enableInterrupts];

    /* Set DTR and RTS */
    [self setDTR:YES];
    [self setRTS:YES];

    txEnabled = YES;
    rxEnabled = YES;
    portOpen = YES;

    [stateLock unlock];

    return IO_R_SUCCESS;
}

/*
 * Close serial port
 */
- (IOReturn) closePort
{
    [stateLock lock];

    if (!portOpen) {
        [stateLock unlock];
        return IO_R_INVALID_ARG;
    }

    /* Disable interrupts */
    [self disableInterrupts];

    /* Clear DTR and RTS */
    [self setDTR:NO];
    [self setRTS:NO];

    /* Flush buffers */
    [self flushTxBuffer];
    [self flushRxBuffer];

    txEnabled = NO;
    rxEnabled = NO;
    portOpen = NO;

    [stateLock unlock];

    return IO_R_SUCCESS;
}

/*
 * Write data
 */
- (IOReturn) writeBytes : (const UInt8 *) buffer
                  length : (UInt32) length
            bytesWritten : (UInt32 *) bytesWritten
{
    UInt32 written = 0;
    UInt32 space;

    if (!portOpen || !txEnabled) {
        return IO_R_INVALID_ARG;
    }

    [txLock lock];

    while (written < length) {
        space = txBufferSize - txCount;
        if (space == 0) {
            [self triggerTxInterrupt];
            break;
        }

        txBuffer[txHead] = buffer[written++];
        txHead = (txHead + 1) % txBufferSize;
        txCount++;
    }

    [self triggerTxInterrupt];
    [txLock unlock];

    if (bytesWritten) {
        *bytesWritten = written;
    }

    return (written > 0) ? IO_R_SUCCESS : IO_R_INVALID_ARG;
}

/*
 * Read data
 */
- (IOReturn) readBytes : (UInt8 *) buffer
                 length : (UInt32) length
               bytesRead : (UInt32 *) bytesRead
{
    UInt32 read = 0;

    if (!portOpen || !rxEnabled) {
        return IO_R_INVALID_ARG;
    }

    [rxLock lock];

    while (read < length && rxCount > 0) {
        buffer[read++] = rxBuffer[rxTail];
        rxTail = (rxTail + 1) % rxBufferSize;
        rxCount--;
    }

    [rxLock unlock];

    if (bytesRead) {
        *bytesRead = read;
    }

    return (read > 0) ? IO_R_SUCCESS : IO_R_NO_DATA;
}

/*
 * Handle interrupt
 */
- (void) interruptOccurred
{
    UInt8 status0, status1;
    UInt8 data;

    /* Read interrupt status */
    status0 = [self readReg:0];

    /* Handle RX interrupt */
    if (status0 & RR0_RX_CHAR_AVAIL) {
        /* Check for errors */
        status1 = [self readReg:1];

        if (status1 & RR1_PARITY_ERROR) parityErrors++;
        if (status1 & RR1_RX_OVERRUN) overrunErrors++;
        if (status1 & RR1_CRC_FRAMING_ERROR) framingErrors++;

        /* Read data */
        data = [self readData];

        [rxLock lock];
        if (rxCount < rxBufferSize) {
            rxBuffer[rxHead] = data;
            rxHead = (rxHead + 1) % rxBufferSize;
            rxCount++;
        }
        [rxLock unlock];

        /* Reset error status */
        [self writeReg:0 value:WR0_CMD_ERR_RESET];
    }

    /* Handle TX interrupt */
    if (status0 & RR0_TX_BUFFER_EMPTY) {
        [txLock lock];
        if (txCount > 0) {
            [self writeData:txBuffer[txTail]];
            txTail = (txTail + 1) % txBufferSize;
            txCount--;
        } else {
            /* No more data, reset TX interrupt */
            [self writeReg:0 value:WR0_CMD_RST_TX_INT];
        }
        [txLock unlock];
    }

    /* Handle external/status interrupt */
    if (status0 & (RR0_DCD | RR0_CTS | RR0_BREAK_ABORT)) {
        ctsState = (status0 & RR0_CTS) != 0;
        dcdState = (status0 & RR0_DCD) != 0;

        if (status0 & RR0_BREAK_ABORT) {
            breakDetects++;
        }

        /* Reset external interrupt */
        [self writeReg:0 value:WR0_CMD_RST_EXT];
    }
}

/* Hardware methods implemented in PPCSerialHW.m */

@end
