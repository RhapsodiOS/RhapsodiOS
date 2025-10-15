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
 * ISASerialHW.m - Hardware support functions for ISA Serial Port
 */

#import "ISASerialPort.h"
#import "ISASerialRegs.h"
#import <architecture/i386/pio.h>
#import <kernserv/prototypes.h>

@implementation ISASerialPort (Hardware)

/*
 * Detect UART type
 */
- (void) detectUART
{
    UInt8 oldFCR, oldIIR;

    /* Assume 8250 initially */
    uartType = UART_TYPE_8250;
    hasFIFO = NO;
    fifoSize = 1;

    /* Test for 16550A FIFO */
    oldFCR = inb(basePort + UART_FCR);
    outb(basePort + UART_FCR, FCR_ENABLE | FCR_CLEAR_RX | FCR_CLEAR_TX);
    IODelay(1);

    oldIIR = inb(basePort + UART_IIR);
    if ((oldIIR & IIR_FIFO_ENABLED) == IIR_FIFO_ENABLED) {
        /* FIFO present */
        uartType = UART_TYPE_16550A;
        hasFIFO = YES;
        fifoSize = 16;
    } else {
        /* Check for 16450 vs 8250 */
        UInt8 oldSCR = inb(basePort + UART_SCR);
        outb(basePort + UART_SCR, 0x55);
        if (inb(basePort + UART_SCR) == 0x55) {
            uartType = UART_TYPE_16450;
        }
        outb(basePort + UART_SCR, oldSCR);
    }

    /* Restore FCR */
    outb(basePort + UART_FCR, oldFCR);
}

/*
 * Reset UART
 */
- (void) resetUART
{
    /* Disable interrupts */
    outb(basePort + UART_IER, 0);

    /* Disable FIFO */
    outb(basePort + UART_FCR, 0);

    /* Clear modem control */
    outb(basePort + UART_MCR, 0);

    /* Read and clear status registers */
    (void)inb(basePort + UART_LSR);
    (void)inb(basePort + UART_MSR);
    (void)inb(basePort + UART_IIR);
    (void)inb(basePort + UART_RBR);
}

/*
 * Configure UART
 */
- (void) configureUART
{
    UInt16 divisor;
    UInt8 lcr;

    /* Calculate divisor */
    divisor = UART_DIVISOR(baudRate);

    /* Set DLAB to access divisor */
    outb(basePort + UART_LCR, LCR_DLAB);
    outb(basePort + UART_DLL, divisor & 0xFF);
    outb(basePort + UART_DLM, (divisor >> 8) & 0xFF);

    /* Configure line control */
    lcr = 0;
    switch (dataBits) {
        case 5: lcr |= LCR_WLS_5; break;
        case 6: lcr |= LCR_WLS_6; break;
        case 7: lcr |= LCR_WLS_7; break;
        case 8: lcr |= LCR_WLS_8; break;
    }

    if (stopBits == 2) {
        lcr |= LCR_STB;
    }

    switch (parity) {
        case PARITY_NONE:
            break;
        case PARITY_ODD:
            lcr |= LCR_PEN;
            break;
        case PARITY_EVEN:
            lcr |= LCR_PEN | LCR_EPS;
            break;
        case PARITY_MARK:
            lcr |= LCR_PEN | LCR_SP;
            break;
        case PARITY_SPACE:
            lcr |= LCR_PEN | LCR_EPS | LCR_SP;
            break;
    }

    outb(basePort + UART_LCR, lcr);

    /* Enable and configure FIFO if available */
    if (hasFIFO) {
        outb(basePort + UART_FCR,
             FCR_ENABLE | FCR_CLEAR_RX | FCR_CLEAR_TX | FCR_TRIGGER_14);
    }

    /* Enable OUT2 for interrupts */
    outb(basePort + UART_MCR, MCR_OUT2);
}

/*
 * Enable interrupts
 */
- (void) enableInterrupts
{
    outb(basePort + UART_IER,
         IER_RDA | IER_THRE | IER_RLS | IER_MS);
}

/*
 * Disable interrupts
 */
- (void) disableInterrupts
{
    outb(basePort + UART_IER, 0);
}

/*
 * Trigger TX interrupt
 */
- (void) triggerTxInterrupt
{
    UInt8 ier = inb(basePort + UART_IER);
    outb(basePort + UART_IER, ier | IER_THRE);
}

/*
 * Flush TX buffer
 */
- (IOReturn) flushTxBuffer
{
    [txLock lock];
    txHead = txTail = txCount = 0;
    [txLock unlock];
    return IO_R_SUCCESS;
}

/*
 * Flush RX buffer
 */
- (IOReturn) flushRxBuffer
{
    [rxLock lock];
    rxHead = rxTail = rxCount = 0;
    [rxLock unlock];

    /* Clear UART RX FIFO */
    if (hasFIFO) {
        outb(basePort + UART_FCR, FCR_ENABLE | FCR_CLEAR_RX);
    }

    return IO_R_SUCCESS;
}

/*
 * Get UART type name
 */
- (const char *) uartTypeName
{
    switch (uartType) {
        case UART_TYPE_8250: return "8250";
        case UART_TYPE_16450: return "16450";
        case UART_TYPE_16550: return "16550";
        case UART_TYPE_16550A: return "16550A";
        case UART_TYPE_16650: return "16650";
        case UART_TYPE_16750: return "16750";
        default: return "Unknown";
    }
}

@end
