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
 * PCSpeakerRegs.h - PC Speaker (8254 PIT Channel 2) Register Definitions
 *
 * The PC speaker is controlled by:
 * - Intel 8254 Programmable Interval Timer (PIT) Channel 2
 * - Port 61h (PPI Port B) for speaker control
 */

#ifndef _PC_SPEAKER_REGS_H
#define _PC_SPEAKER_REGS_H

/* ========== 8254 PIT Registers ========== */

/* PIT I/O Ports */
#define PIT_COUNTER0            0x40    /* Counter 0 (system timer) */
#define PIT_COUNTER1            0x41    /* Counter 1 (unused in modern systems) */
#define PIT_COUNTER2            0x42    /* Counter 2 (PC speaker) */
#define PIT_CONTROL             0x43    /* Control register */

/* PIT Control Register Bits */
#define PIT_SELECT_COUNTER0     0x00    /* Select counter 0 */
#define PIT_SELECT_COUNTER1     0x40    /* Select counter 1 */
#define PIT_SELECT_COUNTER2     0x80    /* Select counter 2 */
#define PIT_SELECT_READBACK     0xC0    /* Readback command */

/* Access mode */
#define PIT_ACCESS_LATCH        0x00    /* Latch count value */
#define PIT_ACCESS_LOBYTE       0x10    /* Access low byte only */
#define PIT_ACCESS_HIBYTE       0x20    /* Access high byte only */
#define PIT_ACCESS_LOHI         0x30    /* Access low byte, then high byte */

/* Operating mode */
#define PIT_MODE_0              0x00    /* Mode 0: Interrupt on terminal count */
#define PIT_MODE_1              0x02    /* Mode 1: Hardware retriggerable one-shot */
#define PIT_MODE_2              0x04    /* Mode 2: Rate generator */
#define PIT_MODE_3              0x06    /* Mode 3: Square wave generator */
#define PIT_MODE_4              0x08    /* Mode 4: Software triggered strobe */
#define PIT_MODE_5              0x0A    /* Mode 5: Hardware triggered strobe */

/* BCD/Binary mode */
#define PIT_BINARY              0x00    /* Binary counter */
#define PIT_BCD                 0x01    /* BCD counter */

/* Common control words */
#define PIT_CMD_COUNTER2_LOHI_MODE3 \
    (PIT_SELECT_COUNTER2 | PIT_ACCESS_LOHI | PIT_MODE_3 | PIT_BINARY)

/* ========== PPI Port B (8255) ========== */

/* PPI Port B I/O Port */
#define PPI_PORT_B              0x61    /* Programmable Peripheral Interface Port B */

/* PPI Port B Bits */
#define PPI_TIMER2_GATE         0x01    /* Timer 2 gate input (1=enable) */
#define PPI_SPEAKER_DATA        0x02    /* Speaker data (1=enable) */
#define PPI_PARITY_CHECK_ENABLE 0x04    /* Enable parity checking */
#define PPI_IOCHK_ENABLE        0x08    /* Enable I/O channel check */
#define PPI_REFRESH_TOGGLE      0x10    /* Memory refresh toggle (read-only) */
#define PPI_TIMER2_OUTPUT       0x20    /* Timer 2 output (read-only) */
#define PPI_IOCHK_STATUS        0x40    /* I/O channel check status (read-only) */
#define PPI_PARITY_STATUS       0x80    /* Parity check status (read-only) */

/* Speaker enable bits (both must be set) */
#define PPI_SPEAKER_ENABLE      (PPI_TIMER2_GATE | PPI_SPEAKER_DATA)

/* ========== PIT Clock Frequency ========== */

/* Base frequency of the PIT */
#define PIT_CLOCK_RATE          1193182 /* 1.193182 MHz */

/* Frequency calculation */
#define PIT_DIVISOR(freq)       (PIT_CLOCK_RATE / (freq))

/* Maximum and minimum frequencies */
#define MIN_FREQUENCY           20      /* 20 Hz (lowest audible) */
#define MAX_FREQUENCY           20000   /* 20 kHz (highest audible) */

/* ========== Standard Beep Frequencies ========== */
#define BEEP_DEFAULT_FREQ       800     /* Default beep frequency */
#define BEEP_ERROR_FREQ         500     /* Error beep (lower pitch) */
#define BEEP_WARNING_FREQ       1000    /* Warning beep (higher pitch) */
#define BEEP_INFO_FREQ          600     /* Information beep */

/* ========== Duration Constants ========== */
#define DURATION_SHORT          100     /* 100ms */
#define DURATION_MEDIUM         250     /* 250ms */
#define DURATION_LONG           500     /* 500ms */
#define DURATION_VERY_LONG      1000    /* 1 second */

/* ========== Maximum Values ========== */
#define MAX_DIVISOR             65535   /* Maximum PIT divisor (16-bit) */
#define MIN_DIVISOR             1       /* Minimum PIT divisor */

#endif /* _PC_SPEAKER_REGS_H */
