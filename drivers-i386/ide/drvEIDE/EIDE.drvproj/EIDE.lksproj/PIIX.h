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
#define PCI_ID_ICH		0x24118086	// ICH (82801AA)
#define PCI_ID_ICH0		0x24218086	// ICH0 (82801AB)
#define PCI_ID_ICH2		0x244A8086	// ICH2 (82801BA) - Mobile
#define PCI_ID_ICH2_1	0x244B8086	// ICH2 (82801BA)
#define PCI_ID_ICH3		0x248A8086	// ICH3 (82801CA) - Mobile
#define PCI_ID_ICH3_1	0x248B8086	// ICH3 (82801CA)
#define PCI_ID_ICH4		0x24CA8086	// ICH4 (82801DB) - Mobile
#define PCI_ID_ICH4_1	0x24CB8086	// ICH4 (82801DB)

#define PCI_ID_NONE		0xffffffff

/*
 * Intel 450NX PCI bridge IDs for DMA workaround detection.
 * The 450NX chipset has unreliable DMA, so we disable it when detected.
 */
#define PCI_DEVICE_ID_INTEL_82451NX	0x84ca8086

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
 * PCI Command Register bit definitions (PIIX_PCICMD)
 */
#define PCI_COMMAND_IO_ENABLE		0x0001	// I/O Space Enable (bit 0)
#define PCI_COMMAND_BUS_MASTER		0x0004	// Bus Master Enable (bit 2)
#define PCI_COMMAND_INTX_DISABLE	0x0400	// INTx Emulation Disable (bit 10)

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
#define PIIX_IOCFG		0x54	// (32) IDE I/O Configuration register

/*
 * PIIX_IOCFG register bit definitions
 *
 * For cable detection:
 */
#define PIIX_80C_PRI	0x10	// Primary channel 80-wire cable
#define PIIX_80C_SEC	0x20	// Secondary channel 80-wire cable

/*
 * For ICH UDMA clock selection (bits 8-15):
 * These bits select the UDMA clock frequency for high-speed modes.
 *
 * Format: Bits [9:8] control primary channel, bits [11:10] control secondary
 * Values: 00 = 33MHz (UDMA 0-2)
 *         01 = 66MHz (UDMA 3-4)
 *         10 = 100MHz (UDMA 5)
 */
#define PIIX_IOCFG_PRI_CLK_MASK		0x0300	// Primary channel clock mask (bits 8-9)
#define PIIX_IOCFG_SEC_CLK_MASK		0x0C00	// Secondary channel clock mask (bits 10-11)
#define PIIX_IOCFG_PRI_CLK_33		0x0000	// Primary 33MHz
#define PIIX_IOCFG_PRI_CLK_66		0x0100	// Primary 66MHz
#define PIIX_IOCFG_PRI_CLK_100		0x0200	// Primary 100MHz
#define PIIX_IOCFG_SEC_CLK_33		0x0000	// Secondary 33MHz
#define PIIX_IOCFG_SEC_CLK_66		0x0400	// Secondary 66MHz
#define PIIX_IOCFG_SEC_CLK_100		0x0800	// Secondary 100MHz
#define PIIX_IOCFG_WR_PINGPONG_EN	0x0400	// Write ping-pong enable (performance)

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
 * PIIX IO space register offsets. Base address is set in PIIX_BMIBA.
 * Register size (bits) in parenthesis.
 *
 * Note:
 * For the primary channel, the base address is stored in PIIX_BMIBA.
 * For the secondary channel, the base address is equal to
 * (PIIX_BMIBA + PIIX_BM_OFFSET).
 */
#define PIIX_BMICX		0x00	// (8) Bus master IDE command register
#define PIIX_BMISX		0x02	// (8) Bus master IDE status register
#define PIIX_BMIDTPX	0x04	// (32) Descriptor table pointer register
#define PIIX_BM_OFFSET	0x08	// offset to secondary channel registers
#define PIIX_BM_SIZE	0x08	// size of the BM registers for each channel
#define PIIX_BM_MASK	0xfff0	// mask BMIBA to get register base address

/*
 * PIIX IO space register definition.
 *
 * BMICX - Bus master IDE command register
 */
typedef union {
	struct {
		u_char
			ssbm	:1,		// start/stop bus master
			rsvd1	:2,		// RESERVED
			rwcon	:1,		// Bus master read/write control
			rsvd2	:4;		// RESERVED
	} bits;
	u_char byte;
} piix_bmicx_u;

/*
 * PIIX IO space register definition.
 *
 * PIIX_BMISX - Bus master IDE status register
 */
typedef union {
	struct {
		u_char
			bmidea	:1,		// Bus master IDE active
			err		:1,		// IDE DMA error
			ideints	:1,		// IDE interrupt status
			rsvd1	:2,		// RESERVED
			dma0cap	:1,		// drive 0 DMA capable
			dma1cap	:1,		// drive 1 DMA capable
			rsvd2	:1;		// RESERVED (hardwired to 0)
	} bits;
	u_char byte;
} piix_bmisx_u;

#define PIIX_STATUS_MASK	0x07
#define PIIX_STATUS_OK		0x04
#define PIIX_STATUS_ERROR	0x02
#define PIIX_STATUS_ACTIVE	0x01

/*
 * PIIX Bus Master alignment/boundary requirements.
 *
 * Intel nomemclature:
 * WORD  - 16-bit
 * DWord - 32-bit
 *
 * NOTE:
 * Boundary limit implies that the entire region is physically
 * contiguous.
 *
 * There is an error in the manual regarding DT alignment and boundary
 * restrictions. The "Intel 82371AB (PIIX4) Specification Update" has a
 * clarification to this issue.
 */
#define PIIX_DT_ALIGN	4			// descriptor table must be DWord aligned.
#define PIIX_DT_BOUND	(4 * 1024)	// cannot cross 4K boundary. (or 64K ?)

#define PIIX_BUF_ALIGN	4			// memory buffer must be DWord aligned.
#define PIIX_BUF_BOUND	(64 * 1024)	// cannot cross 64K boundary.
#define PIIX_BUF_LIMIT	(64 * 1024) // limited to 64K in size

/*
 * PIIX Bus Master Physical Region Descriptor (PRD) format.
 *
 */
typedef struct {
	u_int	base;				// base address
	u_int	count	:16,		// byte count
			rsvd	:15,
			eot		:1;			// final PRD indication bit
} piix_prd_t;
