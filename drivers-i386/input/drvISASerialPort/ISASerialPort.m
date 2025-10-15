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
 * ISASerialPort.m - ISA 16550 UART Serial Port Driver Implementation
 * Refactored to support kernel server instance exports
 */

#import "ISASerialPort.h"
#import "ISASerialPortKernelServerInstance.h"
#import "ISASerialRegs.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <mach/mach_interface.h>
#import <string.h>
#import <architecture/i386/pio.h>

@implementation ISASerialPort

/* Kernel server instance for this driver */
static ISASerialPortKernelServerInstance *kernelServerInstance = nil;

/*
 * Probe for ISA serial ports
 */
+ (Boolean) probe : deviceDescription
{
    ISASerialPort *instance;
    const char *deviceType;
    const char *portStr;
    UInt16 port;
    UInt32 irq;

    /* Initialize kernel server instance if needed */
    if (kernelServerInstance == nil) {
        kernelServerInstance = [ISASerialPortKernelServerInstance allocKernelInstance];
        if (kernelServerInstance) {
            [kernelServerInstance initFromMachine:NULL fromSource:NULL];
        }
    }

    /* Check device type */
    deviceType = [deviceDescription valueForStringKey:"IODeviceType"];
    if (!deviceType || strcmp(deviceType, "Serial Port") != 0) {
        return NO;
    }

    /* Get port and IRQ from device description */
    portStr = [deviceDescription valueForStringKey:"Port"];
    if (!portStr) {
        return NO;
    }

    port = strtoul(portStr, NULL, 0);

    portStr = [deviceDescription valueForStringKey:"IRQ"];
    if (!portStr) {
        return NO;
    }

    irq = strtoul(portStr, NULL, 0);

    /* Verify port is accessible */
    if (port == 0 || irq == 0) {
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
    const char *portStr;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get port base address */
    portStr = [deviceDescription valueForStringKey:"Port"];
    if (portStr) {
        basePort = strtoul(portStr, NULL, 0);
    } else {
        basePort = COM1_BASE;  /* Default to COM1 */
    }

    /* Get IRQ */
    portStr = [deviceDescription valueForStringKey:"IRQ"];
    if (portStr) {
        irqNumber = strtoul(portStr, NULL, 0);
    } else {
        irqNumber = COM1_IRQ;  /* Default to COM1 IRQ */
    }

    /* Initialize state */
    portOpen = NO;
    txEnabled = NO;
    rxEnabled = NO;
    dtrState = NO;
    rtsState = NO;

    /* Create locks */
    txLock = [[NXLock alloc] init];
    rxLock = [[NXLock alloc] init];
    stateLock = [[NXLock alloc] init];

    if (!txLock || !rxLock || !stateLock) {
        [self free];
        return nil;
    }

    /* Allocate buffers using kernel server instance */
    if (kernelServerInstance) {
        txBuffer = (UInt8 *)[kernelServerInstance allocPacketBuffer:TX_BUFFER_SIZE
                                                        fromMachine:NULL
                                                         fromSource:NULL];
        rxBuffer = (UInt8 *)[kernelServerInstance allocPacketBuffer:RX_BUFFER_SIZE
                                                        fromMachine:NULL
                                                         fromSource:NULL];
    } else {
        txBuffer = (UInt8 *)IOMalloc(TX_BUFFER_SIZE);
        rxBuffer = (UInt8 *)IOMalloc(RX_BUFFER_SIZE);
    }

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

    /* Reset statistics */
    parityErrors = 0;
    framingErrors = 0;
    overrunErrors = 0;
    breakDetects = 0;
    fifoErrors = 0;

    /* Detect UART type */
    [self detectUART];

    /* Reset UART */
    [self resetUART];

    /* Register device */
    [self registerDevice];

    /* Notify kernel server instance of event */
    if (kernelServerInstance) {
        [kernelServerInstance identEvent:EVENT_TYPE_DATA];
    }

    IOLog("ISASerialPort: Initialized port 0x%x, IRQ %d, UART %s\n",
          basePort, irqNumber, [self uartTypeName]);

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

    /* Configure UART */
    [self configureUART];

    /* Enable interrupts */
    [self enableInterrupts];

    /* Set DTR and RTS */
    [self setDTR:YES];
    [self setRTS:YES];

    txEnabled = YES;
    rxEnabled = YES;
    portOpen = YES;

    /* Notify kernel server */
    if (kernelServerInstance) {
        [kernelServerInstance newDataState:1 mask:0xFFFFFFFF];
    }

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

    /* Notify kernel server */
    if (kernelServerInstance) {
        [kernelServerInstance newDataState:0 mask:0xFFFFFFFF];
    }

    [stateLock unlock];

    return IO_R_SUCCESS;
}

/*
 * Write data to port
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
            /* Buffer full, trigger TX interrupt */
            [self triggerTxInterrupt];
            break;
        }

        txBuffer[txHead] = buffer[written++];
        txHead = (txHead + 1) % txBufferSize;
        txCount++;
    }

    /* Trigger transmission */
    [self triggerTxInterrupt];

    /* Notify kernel server of data queue */
    if (kernelServerInstance) {
        [kernelServerInstance dataQueue:(void *)buffer bytesTransferred:written];
        [kernelServerInstance enqueueAsap:(void *)buffer bufferSize:written];
    }

    [txLock unlock];

    if (bytesWritten) {
        *bytesWritten = written;
    }

    return (written > 0) ? IO_R_SUCCESS : IO_R_INVALID_ARG;
}

/*
 * Read data from port
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

    /* Notify kernel server of data received */
    if (kernelServerInstance) {
        [kernelServerInstance dataQueue:(void *)buffer bytesTransferred:read];
    }

    [rxLock unlock];

    if (bytesRead) {
        *bytesRead = read;
    }

    return (read > 0) ? IO_R_SUCCESS : IO_R_NO_DATA;
}

/*
 * Set DTR signal
 */
- (IOReturn) setDTR : (BOOL) state
{
    UInt8 mcr;

    mcr = inb(basePort + UART_MCR);
    if (state) {
        mcr |= MCR_DTR;
    } else {
        mcr &= ~MCR_DTR;
    }
    outb(basePort + UART_MCR, mcr);

    dtrState = state;

    /* Notify kernel server of modem status change */
    if (kernelServerInstance) {
        [kernelServerInstance identEvent:EVENT_TYPE_MODEM_STATUS];
    }

    return IO_R_SUCCESS;
}

/*
 * Set RTS signal
 */
- (IOReturn) setRTS : (BOOL) state
{
    UInt8 mcr;

    mcr = inb(basePort + UART_MCR);
    if (state) {
        mcr |= MCR_RTS;
    } else {
        mcr &= ~MCR_RTS;
    }
    outb(basePort + UART_MCR, mcr);

    rtsState = state;

    /* Notify kernel server of modem status change */
    if (kernelServerInstance) {
        [kernelServerInstance identEvent:EVENT_TYPE_MODEM_STATUS];
    }

    return IO_R_SUCCESS;
}

/*
 * Handle interrupt
 */
- (void) interruptOccurred
{
    UInt8 iir, lsr, msr;
    UInt8 data;

    /* Notify kernel server of interrupt */
    if (kernelServerInstance) {
        [kernelServerInstance resolveInterrupt:NULL sleep:0];
    }

    while (1) {
        iir = inb(basePort + UART_IIR);
        if (iir & IIR_PENDING) {
            break;  /* No interrupt pending */
        }

        switch (iir & IIR_ID_MASK) {
            case IIR_ID_RLS:
                /* Line status interrupt */
                lsr = inb(basePort + UART_LSR);
                if (lsr & LSR_OE) overrunErrors++;
                if (lsr & LSR_PE) parityErrors++;
                if (lsr & LSR_FE) framingErrors++;
                if (lsr & LSR_BI) breakDetects++;

                /* Notify kernel server of line status event */
                if (kernelServerInstance) {
                    [kernelServerInstance identEvent:EVENT_TYPE_LINE_STATUS];
                }
                break;

            case IIR_ID_RDA:
            case IIR_ID_CTI:
                /* Received data available */
                while (inb(basePort + UART_LSR) & LSR_DR) {
                    data = inb(basePort + UART_RBR);
                    [rxLock lock];
                    if (rxCount < rxBufferSize) {
                        rxBuffer[rxHead] = data;
                        rxHead = (rxHead + 1) % rxBufferSize;
                        rxCount++;

                        /* Enqueue data event */
                        if (kernelServerInstance) {
                            [kernelServerInstance enqueueULongEvent:data];
                        }
                    }
                    [rxLock unlock];
                }
                break;

            case IIR_ID_THRE:
                /* Transmitter holding register empty */
                [txLock lock];
                while ((inb(basePort + UART_LSR) & LSR_THRE) && txCount > 0) {
                    outb(basePort + UART_THR, txBuffer[txTail]);
                    txTail = (txTail + 1) % txBufferSize;
                    txCount--;
                }
                [txLock unlock];
                break;

            case IIR_ID_MS:
                /* Modem status interrupt */
                msr = inb(basePort + UART_MSR);
                ctsState = (msr & MSR_CTS) != 0;
                dsrState = (msr & MSR_DSR) != 0;
                riState = (msr & MSR_RI) != 0;
                dcdState = (msr & MSR_DCD) != 0;

                /* Notify kernel server of modem status change */
                if (kernelServerInstance) {
                    [kernelServerInstance identEvent:EVENT_TYPE_MODEM_STATUS];
                }
                break;
        }
    }
}

/* Include hardware-specific methods from ISASerialHW.m */
#import "ISASerialHW.m"

@end
