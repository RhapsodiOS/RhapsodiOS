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

#include <interrupts.h>		/* our own: names 5.6's table (CARD18-25) */
#include <families/sawtooth.h>
#include <chips/keylargo.h>
#include <chips/mpic.h>
#include <sys/systm.h>

powermac_init_t sawtooth_init = {
	configure_sawtooth,		    // configure_machine
	mpic_interrupt_initialize,	// machine_initialize_interrupts
	NO_ENTRY,			        // machine_initialize_network
	sawtooth_initialize_bats,	// machine_initialize_processors
	rtc_init,			        // machine_initialize_rtclock
	&keylargo_dbdma_channels,	// struct for dbdma channels
};

#define NSAWTOOTH_VIA1_INTERRUPTS 7
#define NSAWTOOTH_INTERRUPTS 64

/* MPIC Interrupt Mapping Table for Sawtooth
 * Format: INT_TBL(vector, priority, sense, polarity, mask, destination)
 */
static u_long sawtooth_int_mapping_tbl[] = {
    INT_TBL(  0,     8,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ0  - SCSI DMA        */
    INT_TBL(  1,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ1  - Reserved        */
    INT_TBL(  2,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ2  - IDE 0 DMA       */
    INT_TBL(  3,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ3  - IDE 1 DMA       */
    INT_TBL(  4,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ4  - SCC Tx A DMA    */
    INT_TBL(  5,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ5  - SCC Rx A DMA    */
    INT_TBL(  6,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ6  - SCC Tx B DMA    */
    INT_TBL(  7,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ7  - SCC Rx B DMA    */
    INT_TBL(  8,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ8  - Audio Out DMA   */
    INT_TBL(  9,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ9  - Audio In  DMA   */
    INT_TBL( 10,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ10 - Reserved        */
    INT_TBL( 11,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ11 - Reserved        */
    INT_TBL( 12,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ12 - SCSI Dev        */
    INT_TBL( 13,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ13 - IDE 0 Dev       */
    INT_TBL( 14,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ14 - IDE 1 Dev       */
    INT_TBL( 15,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ15 - SCC A Dev       */
    INT_TBL( 16,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ16 - SCC B Dev       */
    INT_TBL( 17,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ17 - Audio Dev       */
    INT_TBL( 18,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ18 - Reserved        */
    INT_TBL( 19,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ19 - Reserved        */
    INT_TBL( 20,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ20 - NMI             */
    INT_TBL( 21,     8,   EDGE, ACT_HI,   MASKED, 1), /* IRQ21 - PCI Slot 1      */
    INT_TBL( 22,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ22 - PCI Slot 2      */
    INT_TBL( 23,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ23 - PCI Slot 3      */
    INT_TBL( 24,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ24 - PCI Slot 4      */
    INT_TBL( 25,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ25 - VIA Cascade     */
    INT_TBL( 26,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ26 - Reserved        */
    INT_TBL( 27,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ27 - Reserved        */
    INT_TBL( 28,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ28 - Reserved        */
    INT_TBL( 29,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ29 - Reserved        */
    INT_TBL( 30,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ30 - Reserved        */
    INT_TBL( 31,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ31 - Reserved        */
    INT_TBL( 32,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ32 - Eth Tx DMA      */
    INT_TBL( 33,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ33 - Eth Rx DMA      */
    INT_TBL( 34,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ34 - Reserved        */
    INT_TBL( 35,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ35 - Reserved        */
    INT_TBL( 36,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ36 - Reserved        */
    INT_TBL( 37,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ37 - Reserved        */
    INT_TBL( 38,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ38 - Ethernet Dev    */
    INT_TBL( 39,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ39 - Reserved        */
    INT_TBL( 40,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ40 - Reserved        */
    INT_TBL( 41,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ41 - Reserved        */
    INT_TBL( 42,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ42 - Reserved        */
    INT_TBL( 43,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ43 - Reserved        */
    INT_TBL( 44,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ44 - Reserved        */
    INT_TBL( 45,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ45 - Reserved        */
    INT_TBL( 46,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ46 - Reserved        */
    INT_TBL( 47,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ47 - Reserved        */
    INT_TBL( 48,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ48 - Reserved        */
    INT_TBL( 49,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ49 - Reserved        */
    INT_TBL( 50,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ50 - Reserved        */
    INT_TBL( 51,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ51 - Reserved        */
    INT_TBL( 52,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ52 - Reserved        */
    INT_TBL( 53,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ53 - Reserved        */
    INT_TBL( 54,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ54 - Reserved        */
    INT_TBL( 55,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ55 - Reserved        */
    INT_TBL( 56,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ56 - Reserved        */
    INT_TBL( 57,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ57 - Reserved        */
    INT_TBL( 58,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ58 - Reserved        */
    INT_TBL( 59,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ59 - Reserved        */
    INT_TBL( 60,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ60 - Reserved        */
    INT_TBL( 61,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ61 - Reserved        */
    INT_TBL( 62,     8,    LVL, ACT_LOW,  MASKED, 1), /* IRQ62 - Reserved        */
    INT_TBL( 63,     8,    LVL, ACT_LOW,  MASKED, 1)  /* IRQ63 - Reserved        */
};

/* VIA1 cascaded interrupts */
struct powermac_interrupt sawtooth_via1_interrupts[NSAWTOOTH_VIA1_INTERRUPTS] = {
	{ 0,	0,	0,	-1},			/* Cascade */
	{ 0,	0,	0,	PMAC_DEV_HZTICK},
	{ 0,	0,	0,	PMAC_DEV_VIA1},
	{ 0,	0,	0,	PMAC_DEV_VIA2},         /* VIA Data */
	{ 0,	0,	0,	PMAC_DEV_VIA3},         /* VIA CLK Source */
	{ 0,	0,	0,	PMAC_DEV_TIMER2},
	{ 0,	0,	0,	PMAC_DEV_TIMER1}
};

/* KeyLargo MPIC interrupt mapping for Sawtooth (Power Mac G4 AGP Graphics)
 * This is organized by interrupt source number (0-63); the device for each
 * source matches the Mac OS X Server 1.2v3 (kernel 5.6) table.
 */
struct powermac_interrupt  sawtooth_interrupts[NSAWTOOTH_INTERRUPTS] = {
	{ 0,	0, 0, -1},            /* 0 - Unused */
	{ 0,	0, 0, -1},            /* 1 - Unused */
	{ 0,	0, 0, -1},            /* 2 - Unused */
	{ 0,	0, 0, -1},            /* 3 - Unused */
	{ 0,	0, 0, -1},            /* 4 - Unused */
	{ 0,	0, 0, PMAC_DMA_SCC_A_TX}, /* 5 - DMA SCC Channel A TX */
	{ 0,	0, 0, PMAC_DMA_SCC_A_RX}, /* 6 - DMA SCC Channel A RX */
	{ 0,	0, 0, PMAC_DMA_SCC_B_TX}, /* 7 - DMA SCC Channel B TX */
	{ 0,	0, 0, PMAC_DMA_SCC_B_RX}, /* 8 - DMA SCC Channel B RX */
	{ 0,	0, 0, PMAC_DMA_AUDIO_OUT}, /* 9 - DMA Audio Out */
	{ 0,	0, 0, PMAC_DMA_AUDIO_IN}, /* 10 - DMA Audio In */
	{ 0,	0, 0, PMAC_DMA_UIDE}, /* 11 - DMA Ultra IDE */
	{ 0,	0, 0, PMAC_DMA_IDE0}, /* 12 - DMA IDE 0 */
	{ 0,	0, 0, PMAC_DMA_IDE1}, /* 13 - DMA IDE 1 */
	{ 0,	0, 0, -1},            /* 14 - Unused */
	{ 0,	0, 0, -1},            /* 15 - Unused */
	{ 0,	0, 0, -1},            /* 16 - Unused */
	{ 0,	0, 0, -1},            /* 17 - Unused */
	{ 0,	0, 0, -1},            /* 18 - Unused */
	{ 0,	0, 0, PMAC_DEV_UIDE}, /* 19 - Ultra IDE */
	{ 0,	0, 0, PMAC_DEV_IDE0}, /* 20 - IDE 0 */
	{ 0,	0, 0, PMAC_DEV_IDE1}, /* 21 - IDE 1 */
	{ 0,	0, 0, PMAC_DEV_SCC_A}, /* 22 - SCC Channel A */
	{ 0,	0, 0, PMAC_DEV_SCC_B}, /* 23 - SCC Channel B */
	{ 0,	0, 0, PMAC_DEV_AUDIO}, /* 24 - Audio */
	{ mpic_via1_interrupt, 0, 0, -1}, /* 25 - VIA Cascade (0x19) */
	{ 0,	0, 0, -1},            /* 26 - Unused */
	{ 0,	0, 0, PMAC_DEV_USB0}, /* 27 - USB 0 */
	{ 0,	0, 0, PMAC_DEV_USB1}, /* 28 - USB 1 */
	{ 0,	0, 0, -1},            /* 29 - Unused */
	{ 0,	0, 0, -1},            /* 30 - Unused */
	{ 0,	0, 0, -1},            /* 31 - Unused */
	{ 0,	0, 0, -1},            /* 32 - Unused */
	{ 0,	0, 0, -1},            /* 33 - Unused */
	{ 0,	0, 0, -1},            /* 34 - Unused */
	{ 0,	0, 0, -1},            /* 35 - Unused */
	{ 0,	0, 0, -1},            /* 36 - Unused */
	{ 0,	0, 0, -1},            /* 37 - Unused */
	{ 0,	0, 0, PMAC_DEV_CARD18}, /* 38 - Card 18 */
	{ 0,	0, 0, PMAC_DEV_CARD19}, /* 39 - Card 19 */
	{ 0,	0, 0, PMAC_DEV_CARD20}, /* 40 - Card 20 */
	{ 0,	0, 0, PMAC_DEV_CARD21}, /* 41 - Card 21 */
	{ 0,	0, 0, PMAC_DEV_CARD22}, /* 42 - Card 22 */
	{ 0,	0, 0, PMAC_DEV_CARD23}, /* 43 - Card 23 */
	{ 0,	0, 0, PMAC_DEV_CARD24}, /* 44 - Card 24 */
	{ 0,	0, 0, PMAC_DEV_CARD25}, /* 45 - Card 25 */
	{ 0,	0, 0, PMAC_DEV_CARD0}, /* 46 - Card 0 */
	{ 0,	0, 0, PMAC_DEV_CARD1}, /* 47 - Card 1 */
	{ 0,	0, 0, PMAC_DEV_CARD2}, /* 48 - Card 2 */
	{ 0,	0, 0, PMAC_DEV_CARD3}, /* 49 - Card 3 */
	{ 0,	0, 0, PMAC_DEV_CARD4}, /* 50 - Card 4 */
	{ 0,	0, 0, PMAC_DEV_CARD5}, /* 51 - Card 5 */
	{ 0,	0, 0, PMAC_DEV_CARD6}, /* 52 - Card 6 */
	{ 0,	0, 0, PMAC_DEV_CARD7}, /* 53 - Card 7 */
	{ 0,	0, 0, PMAC_DEV_CARD8}, /* 54 - Card 8 */
	{ 0,	0, 0, PMAC_DEV_CARD9}, /* 55 - Card 9 */
	{ 0,	0, 0, PMAC_DEV_CARD10}, /* 56 - Card 10 */
	{ 0,	0, 0, PMAC_DEV_CARD11}, /* 57 - Card 11 */
	{ 0,	0, 0, PMAC_DEV_CARD12}, /* 58 - Card 12 */
	{ 0,	0, 0, PMAC_DEV_CARD13}, /* 59 - Card 13 */
	{ 0,	0, 0, PMAC_DEV_CARD14}, /* 60 - Card 14 */
	{ 0,	0, 0, PMAC_DEV_CARD15}, /* 61 - Card 15 */
	{ 0,	0, 0, PMAC_DEV_CARD16}, /* 62 - Card 16 */
	{ 0,	0, 0, PMAC_DEV_CARD17}  /* 63 - Card 17 */
};

void configure_sawtooth(void)
{
  kern_return_t result;

  mpic_interrupts = (struct powermac_interrupt *) &sawtooth_interrupts;
  mpic_via1_interrupts = (struct powermac_interrupt *) &sawtooth_via1_interrupts;
  mpic_int_mapping_tbl = (u_long *) &sawtooth_int_mapping_tbl;

  nmpic_interrupts = NSAWTOOTH_INTERRUPTS;
  nmpic_via_interrupts = NSAWTOOTH_VIA1_INTERRUPTS;
  mpic_via_cascade = 0x19;  /* VIA cascaded at interrupt 25 (0x19) */

  powermac_info.viaIRQ = 0x5a;  /* 90 decimal - VIA IRQ index */

  result = PEKeyLargoInitialize();
  if (result != KERN_SUCCESS)
    printf("KeyLargo audio services unavailable (0x%x)\n", result);
}

void sawtooth_initialize_bats()
{
#ifndef UseOpenFirmware

PEMapSegment(0x80000000,0x10000000);
PEMapSegment(0xf0000000,0x10000000);

#endif
}
