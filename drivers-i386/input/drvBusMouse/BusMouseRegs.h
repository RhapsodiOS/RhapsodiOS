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
 * BusMouseRegs.h - ISA Bus Mouse Register Definitions
 *
 * Supports Microsoft InPort Mouse and Logitech Bus Mouse
 * Based on industry-standard PC bus mouse architecture
 */

#ifndef _BUS_MOUSE_REGS_H
#define _BUS_MOUSE_REGS_H

/* ========== Microsoft InPort Mouse ========== */

/* Standard InPort base addresses */
#define INPORT_PRIMARY          0x23C   /* Primary address */
#define INPORT_SECONDARY        0x238   /* Secondary address */
#define INPORT_IRQ              5       /* Default IRQ */

/* InPort register offsets */
#define INPORT_ADDR_REG         0       /* Address register */
#define INPORT_DATA_REG         1       /* Data register */
#define INPORT_IDENT_REG        2       /* Identification register */
#define INPORT_TEST_REG         3       /* Test register */

/* InPort internal registers (accessed via ADDR/DATA) */
#define INPORT_REG_STATUS       0       /* Status register */
#define INPORT_REG_DATA1        1       /* Data register 1 (X movement) */
#define INPORT_REG_DATA2        2       /* Data register 2 (Y movement) */
#define INPORT_REG_DATA3        3       /* Data register 3 (unused) */
#define INPORT_REG_SIGNATURE1   4       /* Signature byte 1 */
#define INPORT_REG_SIGNATURE2   5       /* Signature byte 2 */
#define INPORT_REG_MODE         7       /* Mode register */

/* InPort status register bits */
#define INPORT_STATUS_BUTTON3   0x01    /* Button 3 (middle) */
#define INPORT_STATUS_BUTTON2   0x02    /* Button 2 (right) */
#define INPORT_STATUS_BUTTON1   0x04    /* Button 1 (left) */
#define INPORT_STATUS_RESERVED  0x08    /* Reserved */
#define INPORT_STATUS_MOVEMENT  0x40    /* Movement occurred */
#define INPORT_STATUS_IRQ       0x80    /* IRQ pending */

/* InPort mode register bits */
#define INPORT_MODE_HZ0         0x00    /* Disabled */
#define INPORT_MODE_HZ30        0x01    /* 30 Hz */
#define INPORT_MODE_HZ50        0x02    /* 50 Hz */
#define INPORT_MODE_HZ100       0x03    /* 100 Hz */
#define INPORT_MODE_HZ200       0x04    /* 200 Hz */
#define INPORT_MODE_RATE_MASK   0x07    /* Rate mask */
#define INPORT_MODE_HOLD        0x20    /* Hold counter */
#define INPORT_MODE_IRQ_ENABLE  0x08    /* Enable interrupts */
#define INPORT_MODE_QUADRATURE  0x10    /* Quadrature mode */

/* InPort identification */
#define INPORT_ID_BYTE          0xDE    /* Expected ID byte */
#define INPORT_SIGNATURE_BYTE1  0x12    /* Signature byte 1 */
#define INPORT_SIGNATURE_BYTE2  0x34    /* Signature byte 2 */

/* ========== Logitech Bus Mouse ========== */

/* Standard Logitech bus mouse addresses */
#define LOGITECH_PRIMARY        0x23C   /* Primary address */
#define LOGITECH_SECONDARY      0x238   /* Secondary address */
#define LOGITECH_IRQ            5       /* Default IRQ */

/* Logitech register offsets */
#define LOGITECH_DATA_REG       0       /* Data port */
#define LOGITECH_SIGNATURE_REG  1       /* Signature port */
#define LOGITECH_CONTROL_REG    2       /* Control port */
#define LOGITECH_CONFIG_REG     3       /* Configuration port */

/* Logitech data register bits */
#define LOGITECH_DATA_BUTTON1   0x80    /* Left button */
#define LOGITECH_DATA_BUTTON2   0x40    /* Right button */
#define LOGITECH_DATA_BUTTON3   0x20    /* Middle button */
#define LOGITECH_DATA_XSIGN     0x10    /* X sign bit (1=negative) */
#define LOGITECH_DATA_YSIGN     0x08    /* Y sign bit (1=negative) */
#define LOGITECH_DATA_XDATA     0x0F    /* X movement data (low nibble) */
#define LOGITECH_DATA_YDATA     0x0F    /* Y movement data (low nibble) */

/* Logitech control register bits */
#define LOGITECH_CTRL_READ_X    0x80    /* Read X counter */
#define LOGITECH_CTRL_READ_Y    0x00    /* Read Y counter */
#define LOGITECH_CTRL_READ_LOW  0x00    /* Read low nibble */
#define LOGITECH_CTRL_READ_HIGH 0x20    /* Read high nibble */
#define LOGITECH_CTRL_RESET     0x10    /* Reset */

/* Logitech configuration register bits */
#define LOGITECH_CFG_IRQ_ENABLE 0x10    /* Enable interrupts */
#define LOGITECH_CFG_IRQ_POLARITY 0x08  /* IRQ polarity */

/* Logitech signature */
#define LOGITECH_SIGNATURE      0xA5    /* Expected signature */

/* ========== ATI XL Mouse ========== */

/* ATI mouse is compatible with Microsoft InPort */
#define ATI_PRIMARY             0x23C
#define ATI_SECONDARY           0x238
#define ATI_IRQ                 5

/* ========== Common Definitions ========== */

/* Button states */
#define BUTTON_LEFT             0x01
#define BUTTON_RIGHT            0x02
#define BUTTON_MIDDLE           0x04

/* Movement limits */
#define MAX_MOVEMENT            127     /* Maximum movement per read */
#define MIN_MOVEMENT            -128    /* Minimum movement per read */

/* Sample rates */
#define RATE_DISABLED           0       /* Interrupts disabled */
#define RATE_30HZ               30      /* 30 Hz sample rate */
#define RATE_50HZ               50      /* 50 Hz sample rate */
#define RATE_100HZ              100     /* 100 Hz sample rate */
#define RATE_200HZ              200     /* 200 Hz sample rate */

/* Reset timing */
#define RESET_DELAY             1000    /* Reset delay in microseconds */
#define RESET_TIMEOUT           10000   /* Reset timeout in microseconds */

/* Buffer sizes */
#define EVENT_QUEUE_SIZE        64      /* Mouse event queue size */

#endif /* _BUS_MOUSE_REGS_H */
