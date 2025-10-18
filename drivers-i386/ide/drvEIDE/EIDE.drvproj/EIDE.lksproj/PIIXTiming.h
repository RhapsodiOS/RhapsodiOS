/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Copyright 1998 by Apple Computer, Inc., All rights reserved.
 *
 * Intel PIIX/PIIX3/PIIX4 PCI IDE controller timing tables.
 *
 * HISTORY:
 * 1-Feb-1998	Joe Liu at Apple
 *	Created.
 */
#import "PIIX.h"

typedef ideTransferType_t PIIXTransferType_t;

/*
 * PIIX PIO/DMA timing table.
 */

typedef struct {
	u_char	pio_mode;
	u_char	swdma_mode;
	u_char	mwdma_mode;
	u_char	isp;	// IORDY sample point in PCI clocks
	u_char	rct;	// Recovery time in PCI clocks
	u_short	cycle;	// cycle time in ns
} PIIXTiming;

#define PIIX_TIMING_TABLE_SIZE	7

/* Timing tables are defined in IdePIIX.m */
extern const PIIXTiming PIIXTimingTable[];

/*
 * PIIX Ultra DMA timing table.
 *
 * The UDMA timing is controlled by a combination of:
 * 1. Clock selection (33/66/100 MHz) in IOCFG register (ICH only)
 * 2. Timing divider (2 bits) in UDMATIM register
 *
 * Linux driver rule: "Odd modes are UDMATIMx 01, even are 02 except UDMA0 which is 00"
 * This translates to: timing_bits = min(2 - (mode & 1), mode)
 */
typedef struct {
	u_char	mode;		// UDMA mode number (0-5)
	u_char	timing_bits;	// 2-bit value for UDMATIM register
	u_char	clock_sel;	// Clock selection: 0=33MHz, 1=66MHz, 2=100MHz
	u_short	strobe;		// Strobe period in ns
} PIIXUltraDMATiming;

/* Ultra DMA timing table is defined in IdePIIX.m */
extern const PIIXUltraDMATiming PIIXUltraDMATimingTable[];

/*
 * Calculate UDMA timing bits based on mode number.
 * Follows Linux algorithm: "Odd modes are UDMATIMx 01, even are 02 except UDMA0"
 */
static __inline__
u_char
PIIXGetUDMATimingBits(u_char mode)
{
	if (mode <= 5) {
		return PIIXUltraDMATimingTable[mode].timing_bits;
	}
	return 0;	// Default to slowest
}

/*
 * Get clock selection for UDMA mode.
 * Returns: 0 = 33MHz, 1 = 66MHz, 2 = 100MHz
 */
static __inline__
u_char
PIIXGetUDMAClockSelect(u_char mode)
{
	if (mode <= 5) {
		return PIIXUltraDMATimingTable[mode].clock_sel;
	}
	return 0;	// Default to 33MHz
}

/*
 * Given a transfer mode/type, return the index for the
 * entry in PIIXTimingTable[] which matches the mode.
 */
static __inline__
u_char
PIIXFindModeInTable(u_char mode, PIIXTransferType_t type)
{
	int i;	
	for (i = (PIIX_TIMING_TABLE_SIZE - 1); i  >= 0; i--) {
		u_char m;
		
		switch (type) {
			case IDE_TRANSFER_ULTRA_DMA:
			case IDE_TRANSFER_MW_DMA:
				m = PIIXTimingTable[i].mwdma_mode;
				break;
			case IDE_TRANSFER_SW_DMA:
				m = PIIXTimingTable[i].swdma_mode;
				break;
			case IDE_TRANSFER_PIO:
			default:
				m = PIIXTimingTable[i].pio_mode;
		}
		
		if (mode == m)
			return (i);
	}
	
	// not found, return compatible timing
	return (0);
}

/*
 * Given a transfer mode/type, return the ISP value.
 */
static __inline__
u_char
PIIXGetISPForMode(u_char mode, PIIXTransferType_t type)
{
	u_char index = PIIXFindModeInTable(mode, type);
	return (PIIX_CLK_TO_ISP(PIIXTimingTable[index].isp));
}

/*
 * Given a transfer mode/type, return the RCT value.
 */
static __inline__
u_char
PIIXGetRCTForMode(u_char mode, PIIXTransferType_t type)
{
	u_char index = PIIXFindModeInTable(mode, type);
	return (PIIX_CLK_TO_RCT(PIIXTimingTable[index].rct));
}

/*
 * Given a transfer mode/type, return the cycle time in ns.
 */
static __inline__
u_short
PIIXGetCycleForMode(u_char mode, PIIXTransferType_t type)
{
	u_char index = PIIXFindModeInTable(mode, type);	
	return (PIIXTimingTable[index].cycle);
}
