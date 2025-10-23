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
 * AttoScsiRegs.h - Atto SCSI Controller Register Definitions
 */

/* SCSI Control Register 1 */
#define SCNTL1_SIZE   0x01
#define SCNTL1        0x00000001
   #define    SCNTL1_RST   0x08    /* SCSI Reset */

/* SCSI Control Register 2 */
#define SCNTL2_SIZE   0x01
#define SCNTL2        0x00000002
   #define    SCNTL2_WSS   0x20    /* Wide SCSI Send */

/* SCSI Control Register 3 */
#define SCNTL3_SIZE   0x01
#define SCNTL3        0x00000003
   #define    SCNTL3_EWS   0x08    /* Enable Wide SCSI */

/* SCSI Transfer Register */
#define SXFER_SIZE    0x01
#define SXFER         0x00000005

/* SCSI Output Data Latch */
#define SODL_SIZE     0x01
#define SODL          0x0000000D

/* SCSI Chip ID */
#define SCID_SIZE     0x01
#define SCID          0x0000000F
   #define    SCID_MASK    0x0F    /* SCSI ID mask */

/* SCSI Status 0 */
#define SSTAT0_SIZE   0x01
#define SSTAT0        0x00000020

/* DMA Byte Counter */
#define DBC_SIZE      0x04
#define DBC           0x00000024

/* Chip Test Register 3 */
#define CTEST3_SIZE   0x01
#define CTEST3        0x0000001B
   #define    CTEST3_CLF   0x04    /* Clear DMA FIFO */

/* Chip Test Register 4 */
#define CTEST4_SIZE   0x01
#define CTEST4        0x0000001A

/* Chip Test Register 5 */
#define CTEST5_SIZE   0x01
#define CTEST5        0x0000004E
   #define    CTEST5_DFS   0x40    /* DMA FIFO Size bit */

/* DMA FIFO Register */
#define DFIFO_SIZE    0x01
#define DFIFO         0x0000004F
   #define    DFIFO_FLF    0x02    /* Flush DMA FIFO */
   #define    DFIFO_BO     0x40    /* FIFO Byte Offset mask */

/* DMA Status Register */
#define DSTAT_SIZE    0x01
#define DSTAT         0x0000000C

/* Interrupt Status Register */
#define ISTAT_SIZE    0x01
#define ISTAT         0x00000014
#define ISTAT_INIT    0x00
   #define    ABRT         0x80    /* Abort Operation      */
   #define    RST          0x40    /* Software reset       */
   #define    SIGP         0x20    /* Signal process       */
   #define    SEM          0x10    /* Semaphore            */
   #define    ISTAT_CON    0x08    /* Connected to target  */
   #define    INTF         0x04    /* Interrupt on the fly */
   #define    SIP          0x02    /* SCSI Interrupt Pending */
   #define    DIP          0x01    /* DMA Interrupt Pending  */

/* DMA Script Pointer Register */
#define DSP_SIZE      0x04
#define DSP           0x0000002C

/* DMA Script Pointer Save Register */
#define DSPS_SIZE     0x04
#define DSPS          0x00000030

/* SCSI Interrupt Status Register */
#define SIST_SIZE     0x02
#define SIST          0x00000042

/* Miscellaneous defines */
#define kAbortScriptTimeoutMS    50
#define kSCSITimerIntervalMS     250
