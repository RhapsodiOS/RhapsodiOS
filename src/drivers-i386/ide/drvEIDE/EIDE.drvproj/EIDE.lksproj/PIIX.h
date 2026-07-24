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
 * Intel PIIX/PIIX3/PIIX4/PIIX4E/PIIX4M PCI IDE controller.
 * PIIX = PCI-ISA-IDE-Xelerator. (USB also on newer controllers)
 *
 * Notes:
 *
 * PIIX  introduced in the "Triton" chipset.
 * PIIX3 supports different timings for Master/Slave devices on both channels.
 * PIIX4 adds support for Ultra DMA/33.
 * PIIX4E and PIIX4M are variants of PIIX4 with the same IDE capabilities.
 *
 * Be sure to download and read the PIIX errata from Intel's web site at
 * developer.intel.com. Even then, don't trust everything you read.
 *
 * HISTORY:
 * 1-Feb-1998	Joe Liu at Apple
 *	Created.
 */

/*
 * PCI ID's.
 */
#define PCI_ID_PIIX		0x12308086
#define PCI_ID_PIIX3	0x70108086
#define PCI_ID_PIIX4	0x71118086
#define PCI_ID_PIIX4E	0x71128086
#define PCI_ID_PIIX4M	0x71138086
#define PCI_ID_NONE		0xffffffff

/*
 * Decoded port addresses. Seems to be hardcoded and it does not
 * show up in the PCI configuration space memory ranges.
 */
#define PIIX_P_CMD_ADDR		0x1f0
#define PIIX_P_CTL_ADDR		0x3f4
#define PIIX_S_CMD_ADDR		0x170
#define PIIX_S_CTL_ADDR		0x374
#define PIIX_CMD_SIZE		8
#define PIIX_CTL_SIZE		4

/*
 * IRQ assignment.
 */
#define PIIX_P_IRQ			14
#define PIIX_S_IRQ			15

/*
 * PIIX PCI configuration space registers.
 * Register size (bits) in parenthesis.
 */
#define PIIX_PCICMD		0x04	// (16) PCI command register
#define PIIX_PCISTS		0x06	// (16) PCI device status register
#define PIIX_RID		0x08	// (8)  Revision identification register
#define PIIX_CLASSC		0x09	// (24) Class code register
#define PIIX_MLT		0x0d	// (8)  Master latency timer register
#define PIIX_HEDT		0x0e	// (8)  Header type register
#define PIIX_BMIBA		0x20	// (32) Bus-Master interface base address
#define PIIX_IDETIM		0x40	// (16) IDE timing registers (primary)
#define PIIX_IDETIM_S	0x42	// (16) IDE timing registers (secondary)
#define PIIX_SIDETIM	0x44	// (8)  Slave IDE timing register
#define PIIX_UDMACTL	0x48	// (8)  Ultra DMA/33 control register
#define PIIX_UDMATIM	0x4a	// (16) Ultra DMA/33 timing register

/*
 * PIIX PCI configuration space register definition.
 *
 * PIIX_IDETIM - IDE timing register.
 *
 * Address:
 * 0x40:0x41 - Primary channel
 * 0x42:0x43 - Secondary channel
 */
typedef union {
	struct {
		u_short
			time0	:1,		// fast timing bank drive select 0
			ie0		:1,		// IORDY sample point enable driver select 0
			ppe0	:1,		// prefetch and posting enable
			dte0	:1,		// DMA timing enable only
			time1	:1,		// fast timing bank driver select 1
			ie1		:1,		// IORDY sample point enable driver select 1
			ppe1	:1,		// prefetch and posting enable
			dte1	:1,		// DMA timing enable only
			rct		:2,		// recovery time
			rsvd	:2,		// RESERVED
			isp		:2,		// IORDY sample point
			sitre	:1,		// slave IDE timing register enable
			ide		:1;		// IDE decode enable
	} bits;
	u_short word;
} piix_idetim_u;

/*
 * Convert the "isp" and "rct" fields in PIIX_IDETIM register from
 * PCI clocks to their respective values, and vice-versa.
 */
#define PIIX_CLK_TO_ISP(x)		(5 - (x))
#define PIIX_ISP_TO_CLK(x)		PIIX_CLK_TO_ISP(x)
#define PIIX_CLK_TO_RCT(x)		(4 - (x))
#define PIIX_RCT_TO_CLK(x)		PIIX_CLK_TO_RCT(x)

/*
 * PIIX PCI configuration space register definition.
 *
 * PIIX_SIDETIM - Slave IDE timing register.
 *
 * Address: 0x44
 */
typedef union {
	struct {
		u_char
			prct1	:2,		// primary drive 1 recovery time
			pisp1	:2,		// primary drive 1 IORDY sample point
			srct1	:2,		// secondary drive 1 recovery time
			sisp1	:2;		// secondary drive 1 IORDY sample point
	} bits;
	u_char byte;
} piix_sidetim_u;

/*
 * PIIX PCI configuration space register definition.
 *
 * PIIX_UDMACTL - Ultra DMA/33 control register
 *
 * Address: 0x48
 */
typedef union {
	struct {
		u_char
			psde0	:1,		// enable Ultra DMA/33 for primary drive 0
			psde1	:1,		// enable Ultra DMA/33 for primary drive 1
			ssde0	:1,		// enable Ultra DMA/33 for secondary drive 0
			ssde1	:1,		// enable Ultra DMA/33 for secondary drive 1
			rsvd	:4;		// RESERVED
	} bits;
	u_char byte;
} piix_udmactl_u;

/*
 * PIIX PCI configuration space register definition.
 *
 * PIIX_UDMATIM - Ultra DMA/33 timing register
 *
 * Address: 0x4a-0x4b
 */
typedef union {
	struct {
		u_short
			pct0	:2,		// primary drive 0 cycle time
			rsvd1	:2,		// RESERVED
			pct1	:2,		// primary drive 1 cycle time
			rsvd2	:2,		// RESERVED
			sct0	:2,		// secondary drive 0 cycle time
			rsvd3	:2,		// RESERVED
			sct1	:2,		// secondary drive 1 cycle time
			rsvd4	:2;		// RESERVED
	} bits;
	u_short word;
} piix_udmatim_u;

/*
 * NOTE: the standard SFF-8038i bus-master IO space register offsets,
 * their bit definitions, and the PRD table format used to live here.
 * They are chipset-independent and have moved to IdeBMIDE.h (as
 * BMIDE_*/bmide_*). PIIX_BMIBA above is duplicated there as
 * BMIDE_BMIBA for use by the generic code.
 */
