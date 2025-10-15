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
 * ISASerialRegs.h - 16550 UART Register Definitions
 */

#ifndef _ISA_SERIAL_REGS_H
#define _ISA_SERIAL_REGS_H

/* ========== UART Register Offsets ========== */

/* When DLAB=0 (normal mode) */
#define UART_RBR                0       /* Receiver Buffer Register (R) */
#define UART_THR                0       /* Transmitter Holding Register (W) */
#define UART_IER                1       /* Interrupt Enable Register */
#define UART_IIR                2       /* Interrupt Identification Register (R) */
#define UART_FCR                2       /* FIFO Control Register (W) */
#define UART_LCR                3       /* Line Control Register */
#define UART_MCR                4       /* Modem Control Register */
#define UART_LSR                5       /* Line Status Register */
#define UART_MSR                6       /* Modem Status Register */
#define UART_SCR                7       /* Scratch Register */

/* When DLAB=1 (divisor latch mode) */
#define UART_DLL                0       /* Divisor Latch Low */
#define UART_DLM                1       /* Divisor Latch High */

/* ========== Interrupt Enable Register (IER) ========== */
#define IER_RDA                 0x01    /* Received Data Available */
#define IER_THRE                0x02    /* Transmitter Holding Register Empty */
#define IER_RLS                 0x04    /* Receiver Line Status */
#define IER_MS                  0x08    /* Modem Status */

/* ========== Interrupt Identification Register (IIR) ========== */
#define IIR_PENDING             0x01    /* 0 = Interrupt pending */
#define IIR_ID_MASK             0x0E    /* Interrupt ID mask */
#define IIR_ID_RLS              0x06    /* Receiver Line Status */
#define IIR_ID_RDA              0x04    /* Received Data Available */
#define IIR_ID_CTI              0x0C    /* Character Timeout Indication */
#define IIR_ID_THRE             0x02    /* Transmitter Holding Register Empty */
#define IIR_ID_MS               0x00    /* Modem Status */
#define IIR_FIFO_ENABLED        0xC0    /* FIFO enabled (16550A+) */

/* ========== FIFO Control Register (FCR) ========== */
#define FCR_ENABLE              0x01    /* Enable FIFO */
#define FCR_CLEAR_RX            0x02    /* Clear receive FIFO */
#define FCR_CLEAR_TX            0x04    /* Clear transmit FIFO */
#define FCR_DMA_MODE            0x08    /* DMA mode select */
#define FCR_TRIGGER_1           0x00    /* Trigger level 1 byte */
#define FCR_TRIGGER_4           0x40    /* Trigger level 4 bytes */
#define FCR_TRIGGER_8           0x80    /* Trigger level 8 bytes */
#define FCR_TRIGGER_14          0xC0    /* Trigger level 14 bytes */

/* ========== Line Control Register (LCR) ========== */
#define LCR_WLS_5               0x00    /* Word length: 5 bits */
#define LCR_WLS_6               0x01    /* Word length: 6 bits */
#define LCR_WLS_7               0x02    /* Word length: 7 bits */
#define LCR_WLS_8               0x03    /* Word length: 8 bits */
#define LCR_WLS_MASK            0x03    /* Word length mask */
#define LCR_STB                 0x04    /* Stop bits: 0=1 bit, 1=2 bits */
#define LCR_PEN                 0x08    /* Parity enable */
#define LCR_EPS                 0x10    /* Even parity select */
#define LCR_SP                  0x20    /* Stick parity */
#define LCR_BC                  0x40    /* Break control */
#define LCR_DLAB                0x80    /* Divisor Latch Access Bit */

/* ========== Modem Control Register (MCR) ========== */
#define MCR_DTR                 0x01    /* Data Terminal Ready */
#define MCR_RTS                 0x02    /* Request To Send */
#define MCR_OUT1                0x04    /* Out 1 (auxiliary output) */
#define MCR_OUT2                0x08    /* Out 2 (interrupt enable) */
#define MCR_LOOP                0x10    /* Loopback mode */
#define MCR_AFE                 0x20    /* Auto flow control enable (16750) */

/* ========== Line Status Register (LSR) ========== */
#define LSR_DR                  0x01    /* Data Ready */
#define LSR_OE                  0x02    /* Overrun Error */
#define LSR_PE                  0x04    /* Parity Error */
#define LSR_FE                  0x08    /* Framing Error */
#define LSR_BI                  0x10    /* Break Interrupt */
#define LSR_THRE                0x20    /* Transmitter Holding Register Empty */
#define LSR_TEMT                0x40    /* Transmitter Empty */
#define LSR_FIFO_ERROR          0x80    /* FIFO error */

/* ========== Modem Status Register (MSR) ========== */
#define MSR_DCTS                0x01    /* Delta Clear To Send */
#define MSR_DDSR                0x02    /* Delta Data Set Ready */
#define MSR_TERI                0x04    /* Trailing Edge Ring Indicator */
#define MSR_DDCD                0x08    /* Delta Data Carrier Detect */
#define MSR_CTS                 0x10    /* Clear To Send */
#define MSR_DSR                 0x20    /* Data Set Ready */
#define MSR_RI                  0x40    /* Ring Indicator */
#define MSR_DCD                 0x80    /* Data Carrier Detect */

/* ========== Baud Rate Divisors ========== */
#define UART_CLOCK              1843200 /* Standard UART clock frequency */

/* Calculate divisor for baud rate */
#define UART_DIVISOR(baud)      (UART_CLOCK / (16 * (baud)))

/* Common baud rate divisors */
#define DIV_110                 1047
#define DIV_300                 384
#define DIV_600                 192
#define DIV_1200                96
#define DIV_2400                48
#define DIV_4800                24
#define DIV_9600                12
#define DIV_14400               8
#define DIV_19200               6
#define DIV_38400               3
#define DIV_57600               2
#define DIV_115200              1

#endif /* _ISA_SERIAL_REGS_H */
