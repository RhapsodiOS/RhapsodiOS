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

#include <machdep/ppc/interrupts.h>
#include <families/sawtooth.h>
#include <chips/keylargo.h>
#include <chips/mpic.h>

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
    INT_TBL(  0,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ0  - SCSI DMA        */
    INT_TBL(  1,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ1  - Reserved        */
    INT_TBL(  2,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ2  - IDE 0 DMA       */
    INT_TBL(  3,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ3  - IDE 1 DMA       */
    INT_TBL(  4,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ4  - SCC Tx A DMA    */
    INT_TBL(  5,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ5  - SCC Rx A DMA    */
    INT_TBL(  6,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ6  - SCC Tx B DMA    */
    INT_TBL(  7,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ7  - SCC Rx B DMA    */
    INT_TBL(  8,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ8  - Audio Out DMA   */
    INT_TBL(  9,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ9  - Audio In  DMA   */
    INT_TBL( 10,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ10 - Reserved        */
    INT_TBL( 11,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ11 - Reserved        */
    INT_TBL( 12,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ12 - SCSI Dev        */
    INT_TBL( 13,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ13 - IDE 0 Dev       */
    INT_TBL( 14,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ14 - IDE 1 Dev       */
    INT_TBL( 15,     4,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ15 - SCC A Dev       */
    INT_TBL( 16,     4,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ16 - SCC B Dev       */
    INT_TBL( 17,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ17 - Audio Dev       */
    INT_TBL( 18,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ18 - Reserved        */
    INT_TBL( 19,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ19 - Reserved        */
    INT_TBL( 20,     7,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ20 - NMI             */
    INT_TBL( 21,     2,    LVL, ACT_LOW,  MASKED, 1), /* IRQ21 - PCI Slot 1      */
    INT_TBL( 22,     2,    LVL, ACT_LOW,  MASKED, 1), /* IRQ22 - PCI Slot 2      */
    INT_TBL( 23,     2,    LVL, ACT_LOW,  MASKED, 1), /* IRQ23 - PCI Slot 3      */
    INT_TBL( 24,     2,    LVL, ACT_LOW,  MASKED, 1), /* IRQ24 - PCI Slot 4      */
    INT_TBL( 25,     1,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ25 - VIA Cascade     */
    INT_TBL( 26,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ26 - Reserved        */
    INT_TBL( 27,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ27 - Reserved        */
    INT_TBL( 28,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ28 - Reserved        */
    INT_TBL( 29,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ29 - Reserved        */
    INT_TBL( 30,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ30 - Reserved        */
    INT_TBL( 31,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ31 - Reserved        */
    INT_TBL( 32,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ32 - Eth Tx DMA      */
    INT_TBL( 33,     4,   EDGE, ACT_HI,   MASKED, 1), /* IRQ33 - Eth Rx DMA      */
    INT_TBL( 34,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ34 - Reserved        */
    INT_TBL( 35,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ35 - Reserved        */
    INT_TBL( 36,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ36 - Reserved        */
    INT_TBL( 37,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ37 - Reserved        */
    INT_TBL( 38,     3,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ38 - Ethernet Dev    */
    INT_TBL( 39,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ39 - Reserved        */
    INT_TBL( 40,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ40 - Reserved        */
    INT_TBL( 41,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ41 - Reserved        */
    INT_TBL( 42,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ42 - Reserved        */
    INT_TBL( 43,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ43 - Reserved        */
    INT_TBL( 44,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ44 - Reserved        */
    INT_TBL( 45,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ45 - Reserved        */
    INT_TBL( 46,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ46 - Reserved        */
    INT_TBL( 47,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ47 - Reserved        */
    INT_TBL( 48,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ48 - Reserved        */
    INT_TBL( 49,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ49 - Reserved        */
    INT_TBL( 50,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ50 - Reserved        */
    INT_TBL( 51,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ51 - Reserved        */
    INT_TBL( 52,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ52 - Reserved        */
    INT_TBL( 53,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ53 - Reserved        */
    INT_TBL( 54,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ54 - Reserved        */
    INT_TBL( 55,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ55 - Reserved        */
    INT_TBL( 56,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ56 - Reserved        */
    INT_TBL( 57,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ57 - Reserved        */
    INT_TBL( 58,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ58 - Reserved        */
    INT_TBL( 59,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ59 - Reserved        */
    INT_TBL( 60,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ60 - Reserved        */
    INT_TBL( 61,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ61 - Reserved        */
    INT_TBL( 62,     2,   EDGE, ACT_LOW,  MASKED, 1), /* IRQ62 - Reserved        */
    INT_TBL( 63,     2,   EDGE, ACT_LOW,  MASKED, 1)  /* IRQ63 - Reserved        */
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
 * This is organized by interrupt source number (0-63)
 */
struct powermac_interrupt  sawtooth_interrupts[NSAWTOOTH_INTERRUPTS] = {
	/* 0-7: DMA interrupts */
	{ 0,	0, 0, PMAC_DMA_SCSI0},	      /* 0 - DMA SCSI */
	{ 0,	0, 0, -1},                    /* 1 - Reserved */
	{ 0,	0, 0, PMAC_DMA_IDE0},         /* 2 - DMA IDE0 */
	{ 0,	0, 0, PMAC_DMA_IDE1},         /* 3 - DMA IDE1 */
	{ 0,	0, 0, PMAC_DMA_SCC_A_TX},     /* 4 - DMA SCC Channel A TX */
	{ 0,	0, 0, PMAC_DMA_SCC_A_RX},     /* 5 - DMA SCC Channel A RX */
	{ 0,	0, 0, PMAC_DMA_SCC_B_TX},     /* 6 - DMA SCC Channel B TX */
	{ 0,	0, 0, PMAC_DMA_SCC_B_RX},     /* 7 - DMA SCC Channel B RX */

	/* 8-15: Audio and device interrupts */
	{ 0,	0, 0, PMAC_DMA_AUDIO_OUT},    /* 8 - DMA Audio Out */
	{ 0,	0, 0, PMAC_DMA_AUDIO_IN},     /* 9 - DMA Audio In */
	{ 0,	0, 0, -1},                    /* 10 - Reserved */
	{ 0,	0, 0, -1},                    /* 11 - Reserved */
	{ 0,	0, 0, PMAC_DEV_SCSI0},        /* 12 - SCSI */
	{ 0,	0, 0, PMAC_DEV_IDE0},         /* 13 - IDE 0 */
	{ 0,	0, 0, PMAC_DEV_IDE1},         /* 14 - IDE 1 */
	{ 0,	0, 0, PMAC_DEV_SCC_A},        /* 15 - SCC Channel A */

	/* 16-23: SCC, Audio, VIA and PCI slots */
	{ 0,	0, 0, PMAC_DEV_SCC_B},        /* 16 - SCC Channel B */
	{ 0,	0, 0, PMAC_DEV_AUDIO},        /* 17 - Audio */
	{ 0,    0, 0, -1},                    /* 18 - Reserved */
	{ 0,	0, 0, -1},                    /* 19 - Reserved */
	{ 0, 	0, 0, PMAC_DEV_NMI},          /* 20 - NMI */
	{ 0, 	0, 0, PMAC_DEV_CARD1},        /* 21 - PCI Slot 1 */
	{ 0, 	0, 0, PMAC_DEV_CARD2},        /* 22 - PCI Slot 2 */
	{ 0, 	0, 0, PMAC_DEV_CARD3},        /* 23 - PCI Slot 3 */

	/* 24-31: More PCI slots and VIA cascade */
	{ 0, 	0, 0, PMAC_DEV_CARD4},        /* 24 - PCI Slot 4 */
	{ mpic_via1_interrupt, 0, 0, -1},     /* 25 - VIA Cascade (0x19) */
	{ 0, 	0, 0, -1},                    /* 26 - Reserved */
	{ 0, 	0, 0, -1},                    /* 27 - Reserved */
	{ 0, 	0, 0, -1},                    /* 28 - Reserved */
	{ 0, 	0, 0, -1},                    /* 29 - Reserved */
	{ 0, 	0, 0, -1},                    /* 30 - Reserved */
	{ 0, 	0, 0, -1},                    /* 31 - Reserved */
	/* 32-39: USB, FireWire, Ethernet */
	{ 0,	0, 0, PMAC_DMA_ETHERNET_TX},  /* 32 - DMA Ethernet Tx */
	{ 0,	0, 0, PMAC_DMA_ETHERNET_RX},  /* 33 - DMA Ethernet Rx */
	{ 0,	0, 0, -1},                    /* 34 - Reserved */
	{ 0,	0, 0, -1},                    /* 35 - Reserved */
	{ 0,	0, 0, -1},                    /* 36 - Reserved */
	{ 0,	0, 0, -1},                    /* 37 - Reserved */
	{ 0,	0, 0, PMAC_DEV_ETHERNET},     /* 38 - Ethernet */
	{ 0,	0, 0, -1},                    /* 39 - Reserved */

	/* 40-47: I2S, USB */
	{ 0,	0, 0, -1},                    /* 40 - Reserved */
	{ 0,	0, 0, -1},                    /* 41 - Reserved */
	{ 0,	0, 0, -1},                    /* 42 - Reserved */
	{ 0,	0, 0, -1},                    /* 43 - Reserved */
	{ 0,	0, 0, -1},                    /* 44 - Reserved */
	{ 0,	0, 0, -1},                    /* 45 - Reserved */
	{ 0,	0, 0, -1},                    /* 46 - Reserved */
	{ 0,	0, 0, -1},                    /* 47 - Reserved */

	/* 48-55: More peripherals */
	{ 0,	0, 0, -1},                    /* 48 - Reserved */
	{ 0,	0, 0, -1},                    /* 49 - Reserved */
	{ 0,	0, 0, -1},                    /* 50 - Reserved */
	{ 0,	0, 0, -1},                    /* 51 - Reserved */
	{ 0,	0, 0, -1},                    /* 52 - Reserved */
	{ 0,	0, 0, -1},                    /* 53 - Reserved */
	{ 0,	0, 0, -1},                    /* 54 - Reserved */
	{ 0,	0, 0, -1},                    /* 55 - Reserved */

	/* 56-63: Reserved */
	{ 0,	0, 0, -1},                    /* 56 - Reserved */
	{ 0,	0, 0, -1},                    /* 57 - Reserved */
	{ 0,	0, 0, -1},                    /* 58 - Reserved */
	{ 0,	0, 0, -1},                    /* 59 - Reserved */
	{ 0,	0, 0, -1},                    /* 60 - Reserved */
	{ 0,	0, 0, -1},                    /* 61 - Reserved */
	{ 0,	0, 0, -1},                    /* 62 - Reserved */
	{ 0,	0, 0, -1}                     /* 63 - Reserved */
};

void configure_sawtooth(void)
{
  mpic_interrupts = (struct powermac_interrupt *) &sawtooth_interrupts;
  mpic_via1_interrupts = (struct powermac_interrupt *) &sawtooth_via1_interrupts;
  mpic_int_mapping_tbl = (u_long *) &sawtooth_int_mapping_tbl;

  nmpic_interrupts = NSAWTOOTH_INTERRUPTS;
  nmpic_via_interrupts = NSAWTOOTH_VIA1_INTERRUPTS;
  mpic_via_cascade = 0x19;  /* VIA cascaded at interrupt 25 (0x19) */

  powermac_info.viaIRQ = 0x5a;  /* 90 decimal - VIA IRQ index */
}

void sawtooth_initialize_bats()
{
#ifndef UseOpenFirmware

PEMapSegment(0x80000000,0x10000000);
PEMapSegment(0xf0000000,0x10000000);

#endif
}
