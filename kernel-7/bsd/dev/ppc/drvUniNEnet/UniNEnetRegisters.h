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
 * Copyright (c) 1998-1999 by Apple Computer, Inc., All rights reserved.
 *
 * Interface definition for the UniN Ethernet controller. 
 *
 * HISTORY
 *
 */

 /* ---------------------------------------------------------------------------------------------
 * UniN Ethernet Controller Register Addresses
 * --------------------------------------------------------------------------------------------- */
#define kSoftwareReset      0x00011010  /* Software reset register (8-bit) */
#define kSoftwareReset1     0x00019050  /* Software reset control 1 (8-bit) */
#define kSoftwareReset2     0x00019054  /* Software reset control 2 (8-bit) */
#define kPCSMIIControl      0x00016038  /* PCS MII control (16-bit) */
#define kMacControl         0x00046008  /* MAC control register (16-bit) */
#define kMacStatus          0x00040010  /* MAC status register (32-bit) */
#define kTxMask             0x00026020  /* TX interrupt mask (16-bit) */
#define kRxMask             0x00026024  /* RX interrupt mask (16-bit) */
#define kMacControlMask     0x00016028  /* MAC control interrupt mask (8-bit) */
#define kPCSMIIStatus       0x00020004  /* PCS MII status (16-bit) */
#define kTxPauseQuanta      0x00016040  /* TX pause quanta (16-bit) */
#define kMinFrameSize       0x00016044  /* Min frame size (8-bit) */
#define kMaxBurst           0x00016048  /* Max burst size (8-bit) */
#define kTxFIFOThresh       0x0002604C  /* TX FIFO threshold (16-bit) */
#define kRxFIFOThresh       0x00026050  /* RX FIFO threshold (16-bit) */
#define kRxPauseThresh      0x00026054  /* RX pause threshold (16-bit) */
#define kRxFIFOSize         0x00026058  /* RX FIFO size (16-bit) */
#define kAttemptLimit       0x0001605C  /* TX attempt limit (8-bit) */
#define kSlotTime           0x00016060  /* Slot time (8-bit) */
#define kMinInterFrameGap   0x00026064  /* Min inter-frame gap (16-bit) */
#define kMacAddr0           0x00026080  /* MAC address word 0 (16-bit) */
#define kMacAddr1           0x00026084  /* MAC address word 1 (16-bit) */
#define kMacAddr2           0x00026088  /* MAC address word 2 (16-bit) */
#define kMacIntMask         0x00040010  /* MAC interrupt mask register (32-bit) */
#define kAddrFilter0_0      0x0002608C  /* Address filter 0 mask 0 (32-bit) */
#define kAddrFilter0_1      0x000260A4  /* Address filter 0 mask 1 (32-bit) */
#define kAddrFilter1_0      0x00026090  /* Address filter 1 mask 0 (32-bit) */
#define kAddrFilter1_1      0x000260A8  /* Address filter 1 mask 1 (32-bit) */
#define kAddrFilter2_0      0x00026094  /* Address filter 2 mask 0 (32-bit) */
#define kAddrFilter2_1      0x000260AC  /* Address filter 2 mask 1 (32-bit) */
#define kAddrFilter2_2Mask  0x00026098  /* Address filter 2/2 mask (16-bit) */
#define kHashTable0         0x000260C0  /* Hash table word 0 (32-bit) */
#define kRxConfig_HashEnable 0x0020     /* Hash table enable bit */
#define kRxConfig_Busy      0x0021      /* Busy bits */
#define kNormalCollCnt      0x0002609C  /* Normal collision counter (16-bit) */
#define kFirstCollCnt       0x000260A0  /* First collision counter (16-bit) */
#define kExcessCollCnt      0x000160B0  /* Excess collision counter (8-bit) */
#define kLateCollCnt        0x000260B4  /* Late collision counter (16-bit) */
#define kRandomSeed         0x00026130  /* Random number seed (16-bit) */
#define kTxDescBase         0x00042008  /* TX descriptor base address (32-bit) */
#define kTxDescBaseHi       0x0004200C  /* TX descriptor base hi (32-bit) */
#define kTxConfig           0x00042004  /* TX configuration (32-bit) */
#define kTxDmaConfig        0x00026030  /* TX DMA configuration (16-bit) */
#define kRxDescBase         0x00044004  /* RX descriptor base address (32-bit) */
#define kRxDescBaseHi       0x00044008  /* RX descriptor base hi (32-bit) */
#define kRxKick             0x00024100  /* RX kick register (32-bit) */
#define kRxConfig           0x00044000  /* RX configuration (32-bit) */
#define kRxDmaConfig        0x00026034  /* RX DMA configuration (16-bit) */
#define kRxDmaConfig_Promisc 0x0008     /* Promiscuous mode bit */
#define kRxBlankTime        0x00024120  /* RX blanking time (32-bit) */
#define kRxBlankConfig      0x00044020  /* RX blanking configuration (32-bit) */
#define kSystemClock        0x00011008  /* System clock configuration (32-bit) */
#define kRxPauseTime        0x00044108  /* RX pause time (32-bit) */
#define kMacConfig          0x0004048C  /* MAC configuration register (16-bit) */
#define kEnableBit          0x00000001  /* Bit 0 enables the component */
#define kDisableBit         0xFFFFFFFE  /* Mask to clear bit 0 (enable bit) */
#define kTxKick             0x00022000  /* Transmit DMA kick register */
#define kRxMacCRCErrors     0x0002611C  /* RX MAC CRC error counter (32-bit) */
#define kRxMacCodeErrors    0x00026124  /* RX MAC code violation counter (32-bit) */
#define kTxCompletion       0x00022100  /* Transmit completion register */

 /* ---------------------------------------------------------------------------------------------
 * UniN Ethernet Controller Interrupt Status Register Addresses
 * --------------------------------------------------------------------------------------------- */
#define kInterruptStatus    0x4000C  /* Interrupt status register */
#define kIntrStatus_TxComplete 0x00000001  /* Transmit completed */
#define kIntrStatus_RxComplete 0x00000010  /* Receive completed */
#define kIntrStatus_TxRxMask 0x00000011  /* TX or RX interrupt */
