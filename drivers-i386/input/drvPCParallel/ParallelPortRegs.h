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
 * ParallelPortRegs.h - Standard PC Parallel Port Register Definitions
 *
 * Supports standard parallel ports (LPT1-LPT3) with SPP, EPP, and ECP modes
 * Based on IEEE 1284 standard and PC parallel port architecture
 */

#ifndef _PARALLEL_PORT_REGS_H
#define _PARALLEL_PORT_REGS_H

/* ========== Parallel Port Register Offsets ========== */

/* Standard Parallel Port (SPP) mode registers */
#define PP_DATA_REG             0       /* Data Register (R/W) */
#define PP_STATUS_REG           1       /* Status Register (R) */
#define PP_CONTROL_REG          2       /* Control Register (R/W) */

/* EPP (Enhanced Parallel Port) mode registers */
#define PP_EPP_ADDR             3       /* EPP Address Register (R/W) */
#define PP_EPP_DATA             4       /* EPP Data Register (R/W) */

/* ECP (Extended Capabilities Port) mode registers */
#define PP_ECP_DATA_FIFO        0x400   /* ECP Data FIFO (R/W) */
#define PP_ECP_CONFIG_A         0x400   /* ECP Config Register A */
#define PP_ECP_CONFIG_B         0x401   /* ECP Config Register B */
#define PP_ECP_ECR              0x402   /* Extended Control Register */

/* ========== Data Register (Offset 0) ========== */
/* 8-bit bidirectional data register */
#define DATA_D0                 0x01    /* Data bit 0 */
#define DATA_D1                 0x02    /* Data bit 1 */
#define DATA_D2                 0x04    /* Data bit 2 */
#define DATA_D3                 0x08    /* Data bit 3 */
#define DATA_D4                 0x10    /* Data bit 4 */
#define DATA_D5                 0x20    /* Data bit 5 */
#define DATA_D6                 0x40    /* Data bit 6 */
#define DATA_D7                 0x80    /* Data bit 7 */

/* ========== Status Register (Offset 1) ========== */
/* Read-only status bits */
#define STATUS_BUSY             0x80    /* Busy (inverted, 0=busy, 1=ready) */
#define STATUS_ACK              0x40    /* Acknowledge (active low) */
#define STATUS_PAPER_OUT        0x20    /* Paper Out */
#define STATUS_SELECT           0x10    /* Select In */
#define STATUS_ERROR            0x08    /* Error (active low) */
#define STATUS_IRQ              0x04    /* IRQ Status (ECP/EPP) */
#define STATUS_RESERVED_1       0x02    /* Reserved */
#define STATUS_RESERVED_0       0x01    /* Reserved */

/* Status bit helpers */
#define STATUS_READY            (~STATUS_BUSY)  /* Ready when not busy */

/* ========== Control Register (Offset 2) ========== */
/* Read/Write control bits */
#define CONTROL_STROBE          0x01    /* Strobe (active low) */
#define CONTROL_AUTOFEED        0x02    /* Auto Line Feed (active low) */
#define CONTROL_INIT            0x04    /* Initialize Printer (active low) */
#define CONTROL_SELECT_IN       0x08    /* Select Printer (active high) */
#define CONTROL_IRQ_ENABLE      0x10    /* Enable IRQ via ACK line */
#define CONTROL_DIRECTION       0x20    /* Data Direction (1=input, 0=output) */
#define CONTROL_RESERVED_6      0x40    /* Reserved */
#define CONTROL_RESERVED_7      0x80    /* Reserved */

/* ========== Extended Control Register (ECP mode) ========== */
/* ECP mode control and configuration */
#define ECR_MODE_MASK           0xE0    /* Mode select mask */
#define ECR_MODE_SPP            0x00    /* Standard Parallel Port mode */
#define ECR_MODE_PS2            0x20    /* PS/2 Bidirectional mode */
#define ECR_MODE_FIFO_TEST      0x40    /* FIFO Test mode */
#define ECR_MODE_ECP            0x60    /* ECP mode */
#define ECR_MODE_EPP            0x80    /* EPP mode */
#define ECR_MODE_RESERVED       0xA0    /* Reserved */
#define ECR_MODE_TEST           0xC0    /* Test mode */
#define ECR_MODE_CONFIG         0xE0    /* Configuration mode */

#define ECR_ERR_INTR_SERVICE    0x10    /* ECP service interrupt */
#define ECR_DMA_ENABLE          0x08    /* DMA enable */
#define ECR_SERVICE_INTR        0x04    /* Service interrupt */
#define ECR_FIFO_FULL           0x02    /* FIFO full */
#define ECR_FIFO_EMPTY          0x01    /* FIFO empty */

/* ========== EPP Address Register ========== */
/* EPP address strobe register - writes generate address strobe */

/* ========== EPP Data Register ========== */
/* EPP data strobe register - writes generate data strobe */

/* ========== Timing Constants ========== */
/* All timing values in nanoseconds unless noted */
#define STROBE_WIDTH            1000    /* Strobe pulse width (1 µs) */
#define DATA_SETUP              500     /* Data setup time */
#define DATA_HOLD               500     /* Data hold time */
#define ACK_WIDTH               5000    /* ACK pulse width (5 µs) */
#define BUSY_WAIT               1000    /* Busy wait time (1 µs) */

/* Timeout values in microseconds */
#define TIMEOUT_READY           1000000 /* 1 second */
#define TIMEOUT_ACK             100000  /* 100 ms */
#define TIMEOUT_BUSY            10000   /* 10 ms */

/* ========== FIFO Sizes ========== */
#define ECP_FIFO_SIZE           16      /* ECP FIFO depth (typical) */
#define EPP_TIMEOUT             10      /* EPP timeout threshold */

/* ========== Port Speed Ratings ========== */
#define SPP_MAX_RATE            150000  /* 150 KB/s (SPP mode) */
#define EPP_MAX_RATE            2000000 /* 2 MB/s (EPP mode) */
#define ECP_MAX_RATE            2000000 /* 2 MB/s (ECP mode) */

#endif /* _PARALLEL_PORT_REGS_H */
