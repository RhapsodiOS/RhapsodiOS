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

/*
 * PCMCIA Common Definitions
 *
 * This header defines constants and types used by PCMCIA bus drivers
 * and device drivers for PC Card support.
 */

#ifndef _DRIVERKIT_I386_PCMCIA_H
#define _DRIVERKIT_I386_PCMCIA_H

/* PCMCIA Power State Flags */
#define PCMCIA_VCC_5V           0x01    /* 5V VCC */
#define PCMCIA_VCC_3V           0x02    /* 3.3V VCC */
#define PCMCIA_VPP1_5V          0x04    /* 5V VPP1 */
#define PCMCIA_VPP1_12V         0x08    /* 12V VPP1 */
#define PCMCIA_VPP2_5V          0x10    /* 5V VPP2 */
#define PCMCIA_VPP2_12V         0x20    /* 12V VPP2 */

/* Card voltage detection flags */
#define PCMCIA_VS1              0x01    /* Voltage Sense 1 */
#define PCMCIA_VS2              0x02    /* Voltage Sense 2 */

/* Card types based on voltage sense pins */
#define PCMCIA_CARD_TYPE_5V     0       /* 5V card (VS1=1, VS2=1) */
#define PCMCIA_CARD_TYPE_3V     1       /* 3.3V card (VS1=0, VS2=1) */
#define PCMCIA_CARD_TYPE_XV     2       /* X.V card (VS1=1, VS2=0) */
#define PCMCIA_CARD_TYPE_YV     3       /* Y.V card (VS1=0, VS2=0) */

/* PCMCIA Function Types */
#define PCMCIA_FUNC_MULTI       0x00    /* Multi-function card */
#define PCMCIA_FUNC_MEMORY      0x01    /* Memory card */
#define PCMCIA_FUNC_SERIAL      0x02    /* Serial port (modem/serial) */
#define PCMCIA_FUNC_PARALLEL    0x03    /* Parallel port */
#define PCMCIA_FUNC_FIXED_DISK  0x04    /* Fixed disk (ATA) */
#define PCMCIA_FUNC_VIDEO       0x05    /* Video adapter */
#define PCMCIA_FUNC_NETWORK     0x06    /* Network adapter */
#define PCMCIA_FUNC_AIMS        0x07    /* AIMS */
#define PCMCIA_FUNC_SCSI        0x08    /* SCSI adapter */

/* PCMCIA Socket Status Flags */
#define PCMCIA_STATUS_CARD_DETECT       0x01    /* Card detected */
#define PCMCIA_STATUS_READY             0x02    /* Card ready */
#define PCMCIA_STATUS_POWER_ON          0x04    /* Power active */
#define PCMCIA_STATUS_WRITE_PROTECT     0x08    /* Write protected */
#define PCMCIA_STATUS_BATTERY_DEAD      0x10    /* Battery dead */
#define PCMCIA_STATUS_BATTERY_WARNING   0x20    /* Battery warning */
#define PCMCIA_STATUS_CARD_IS_IO        0x40    /* Card is I/O type */
#define PCMCIA_STATUS_16BIT             0x80    /* 16-bit card */

/* PCMCIA Window Types */
#define PCMCIA_WINDOW_MEMORY            0x01    /* Memory window */
#define PCMCIA_WINDOW_IO                0x02    /* I/O window */
#define PCMCIA_WINDOW_ATTRIBUTE         0x04    /* Attribute memory */
#define PCMCIA_WINDOW_COMMON            0x08    /* Common memory */

/* PCMCIA Memory Window Flags */
#define PCMCIA_MEM_16BIT                0x01    /* 16-bit memory window */
#define PCMCIA_MEM_WRITE_PROTECT        0x02    /* Write protect */
#define PCMCIA_MEM_ATTRIBUTE            0x04    /* Attribute memory */
#define PCMCIA_MEM_ENABLED              0x08    /* Window enabled */

/* PCMCIA I/O Window Flags */
#define PCMCIA_IO_16BIT                 0x01    /* 16-bit I/O window */
#define PCMCIA_IO_WAIT_STATE            0x02    /* Wait state */
#define PCMCIA_IO_ZERO_WAIT             0x04    /* Zero wait state */
#define PCMCIA_IO_ENABLED               0x08    /* Window enabled */

/* PCMCIA Timing Modes */
#define PCMCIA_TIMING_SLOW              0x00    /* Slow timing */
#define PCMCIA_TIMING_MEDIUM            0x01    /* Medium timing */
#define PCMCIA_TIMING_FAST              0x02    /* Fast timing */

/* PCMCIA Card Interface Types */
#define PCMCIA_INTERFACE_MEMORY         0x00    /* Memory only */
#define PCMCIA_INTERFACE_IO             0x01    /* I/O and memory */

/* Maximum number of sockets typically supported */
#define PCMCIA_MAX_SOCKETS              4

/* Maximum number of windows per socket */
#define PCMCIA_MAX_MEM_WINDOWS          5       /* 5 memory windows */
#define PCMCIA_MAX_IO_WINDOWS           2       /* 2 I/O windows */

/* PCMCIA Error Codes */
#define PCMCIA_SUCCESS                  0
#define PCMCIA_ERR_INVALID_SOCKET       -1
#define PCMCIA_ERR_INVALID_WINDOW       -2
#define PCMCIA_ERR_NO_CARD              -3
#define PCMCIA_ERR_VOLTAGE_MISMATCH     -4
#define PCMCIA_ERR_TIMEOUT              -5
#define PCMCIA_ERR_RESOURCE_BUSY        -6
#define PCMCIA_ERR_OUT_OF_RESOURCES     -7

#endif /* _DRIVERKIT_I386_PCMCIA_H */
