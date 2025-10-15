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
 * Copyright (c) 2025 by RhapsodiOS Project, All rights reserved.
 *
 * Register definitions for the Sun GEM Gigabit Ethernet Controller
 * Based on Sun GEM/GMAC and Apple UniNorth GMAC implementations
 *
 * HISTORY
 *
 */

#ifndef _GEMENETREGISTERS_H
#define _GEMENETREGISTERS_H

/*
 * Global Registers (offset 0x0000)
 */
#define GREG_SEBSTATE		0x0000UL	/* SEB State Register */
#define GREG_CFG		0x0004UL	/* Configuration Register */
#define GREG_STAT		0x000CUL	/* Status Register */
#define GREG_IMASK		0x0010UL	/* Interrupt Mask Register */
#define GREG_IACK		0x0014UL	/* Interrupt ACK Register */
#define GREG_STAT2		0x001CUL	/* Alias of Status Register */
#define GREG_PCIESTAT		0x1000UL	/* PCI Error Status Register */
#define GREG_PCIEMASK		0x1004UL	/* PCI Error Mask Register */
#define GREG_BIFCFG		0x1008UL	/* BIF Configuration Register */
#define GREG_BIFDIAG		0x100CUL	/* BIF Diagnostic Register */
#define GREG_SWRST		0x1010UL	/* Software Reset Register */

/* GREG_SEBSTATE bits */
#define GREG_SEBSTATE_ARB	0x00000003	/* Arbitration state */
#define GREG_SEBSTATE_RXWON	0x00000004	/* RX won arbitration */

/* GREG_CFG bits */
#define GREG_CFG_IBURST		0x00000001	/* Infinite burst enable */
#define GREG_CFG_TXDMALIM	0x0000003E	/* TX DMA limit */
#define GREG_CFG_RXDMALIM	0x000007C0	/* RX DMA limit */

/* GREG_STAT interrupt status bits */
#define GREG_STAT_TXINTME	0x00000001	/* TX INTME frame transmitted */
#define GREG_STAT_TXALL		0x00000002	/* All TX frames transmitted */
#define GREG_STAT_TXDONE	0x00000004	/* One TX frame transmitted */
#define GREG_STAT_RXDONE	0x00000010	/* One RX frame received */
#define GREG_STAT_RXNOBUF	0x00000020	/* No free RX buffers */
#define GREG_STAT_RXTAGERR	0x00000040	/* RX tag error */
#define GREG_STAT_PCS		0x00002000	/* PCS interrupt */
#define GREG_STAT_TXMAC		0x00004000	/* TX MAC interrupt */
#define GREG_STAT_RXMAC		0x00008000	/* RX MAC interrupt */
#define GREG_STAT_MAC		0x00010000	/* MAC control interrupt */
#define GREG_STAT_MIF		0x00020000	/* MIF interrupt */
#define GREG_STAT_PCIERR	0x00040000	/* PCI error interrupt */
#define GREG_STAT_ABNORMAL	(GREG_STAT_RXNOBUF | GREG_STAT_RXTAGERR | \
				 GREG_STAT_PCS | GREG_STAT_TXMAC | \
				 GREG_STAT_RXMAC | GREG_STAT_MAC | \
				 GREG_STAT_MIF | GREG_STAT_PCIERR)
#define GREG_STAT_NAPI		(GREG_STAT_TXALL | GREG_STAT_RXDONE | \
				 GREG_STAT_ABNORMAL)

/* GREG_SWRST bits */
#define GREG_SWRST_TXRST	0x00000001	/* TX reset */
#define GREG_SWRST_RXRST	0x00000002	/* RX reset */
#define GREG_SWRST_RSTOUT	0x00000004	/* Reset out */
#define GREG_SWRST_CACHESIZE	0x00FF0000	/* Cache line size */
#define GREG_SWRST_CACHE_SHIFT	16

/*
 * TX DMA Registers (offset 0x2000)
 */
#define TXDMA_KICK		0x2000UL	/* TX kick register */
#define TXDMA_CFG		0x2004UL	/* TX configuration */
#define TXDMA_DBLOW		0x2008UL	/* TX desc base low */
#define TXDMA_DBHI		0x200CUL	/* TX desc base high */
#define TXDMA_FWPTR		0x2014UL	/* TX FIFO write pointer */
#define TXDMA_FSWPTR		0x2018UL	/* TX FIFO shadow write ptr */
#define TXDMA_FRPTR		0x201CUL	/* TX FIFO read pointer */
#define TXDMA_FSRPTR		0x2020UL	/* TX FIFO shadow read ptr */
#define TXDMA_PCNT		0x2024UL	/* TX FIFO packet counter */
#define TXDMA_SMACHINE		0x2028UL	/* TX state machine */
#define TXDMA_DPLOW		0x2030UL	/* TX data pointer low */
#define TXDMA_DPHI		0x2034UL	/* TX data pointer high */
#define TXDMA_TXDONE		0x2100UL	/* TX completion register */
#define TXDMA_FADDR		0x2104UL	/* TX FIFO address */
#define TXDMA_FTAG		0x2108UL	/* TX FIFO tag */
#define TXDMA_DLOW		0x210CUL	/* TX FIFO data low */
#define TXDMA_DHIT1		0x2110UL	/* TX FIFO data high t1 */
#define TXDMA_DHIT0		0x2114UL	/* TX FIFO data high t0 */
#define TXDMA_FSZ		0x2118UL	/* TX FIFO size */

/* TXDMA_CFG bits */
#define TXDMA_CFG_ENABLE	0x00000001	/* Enable TX DMA */
#define TXDMA_CFG_RINGSZ	0x0000001E	/* TX ring size */
#define TXDMA_CFG_RINGSZ_32	(0 << 1)
#define TXDMA_CFG_RINGSZ_64	(1 << 1)
#define TXDMA_CFG_RINGSZ_128	(2 << 1)
#define TXDMA_CFG_RINGSZ_256	(3 << 1)
#define TXDMA_CFG_RINGSZ_512	(4 << 1)
#define TXDMA_CFG_RINGSZ_1K	(5 << 1)
#define TXDMA_CFG_RINGSZ_2K	(6 << 1)
#define TXDMA_CFG_RINGSZ_4K	(7 << 1)
#define TXDMA_CFG_RINGSZ_8K	(8 << 1)
#define TXDMA_CFG_PIOSEL	0x00000020	/* PIO select */
#define TXDMA_CFG_FTHRESH	0x001FFC00	/* TX FIFO threshold */
#define TXDMA_CFG_PMODE		0x00200000	/* Pace mode */

/*
 * RX DMA Registers (offset 0x4000)
 */
#define RXDMA_CFG		0x4000UL	/* RX configuration */
#define RXDMA_DBLOW		0x4004UL	/* RX desc base low */
#define RXDMA_DBHI		0x4008UL	/* RX desc base high */
#define RXDMA_FWPTR		0x400CUL	/* RX FIFO write pointer */
#define RXDMA_FSWPTR		0x4010UL	/* RX FIFO shadow write ptr */
#define RXDMA_FRPTR		0x4014UL	/* RX FIFO read pointer */
#define RXDMA_PCNT		0x4018UL	/* RX FIFO packet counter */
#define RXDMA_SMACHINE		0x401CUL	/* RX state machine */
#define RXDMA_PTHRESH		0x4020UL	/* RX pause threshold */
#define RXDMA_DPLOW		0x4024UL	/* RX data pointer low */
#define RXDMA_DPHI		0x4028UL	/* RX data pointer high */
#define RXDMA_KICK		0x4100UL	/* RX kick register */
#define RXDMA_DONE		0x4104UL	/* RX completion register */
#define RXDMA_BLANK		0x4108UL	/* RX blanking register */
#define RXDMA_FADDR		0x410CUL	/* RX FIFO address */
#define RXDMA_FTAG		0x4110UL	/* RX FIFO tag */
#define RXDMA_DLOW		0x4114UL	/* RX FIFO data low */
#define RXDMA_DHIT1		0x4118UL	/* RX FIFO data high t1 */
#define RXDMA_DHIT0		0x411CUL	/* RX FIFO data high t0 */
#define RXDMA_FSZ		0x4120UL	/* RX FIFO size */

/* RXDMA_CFG bits */
#define RXDMA_CFG_ENABLE	0x00000001	/* Enable RX DMA */
#define RXDMA_CFG_RINGSZ	0x0000001E	/* RX ring size */
#define RXDMA_CFG_RINGSZ_32	(0 << 1)
#define RXDMA_CFG_RINGSZ_64	(1 << 1)
#define RXDMA_CFG_RINGSZ_128	(2 << 1)
#define RXDMA_CFG_RINGSZ_256	(3 << 1)
#define RXDMA_CFG_RINGSZ_512	(4 << 1)
#define RXDMA_CFG_RINGSZ_1K	(5 << 1)
#define RXDMA_CFG_RINGSZ_2K	(6 << 1)
#define RXDMA_CFG_RINGSZ_4K	(7 << 1)
#define RXDMA_CFG_RINGSZ_8K	(8 << 1)
#define RXDMA_CFG_FBOFF		0x00001C00	/* First byte offset */
#define RXDMA_CFG_CKSUM		0x00002000	/* Checksum enable */
#define RXDMA_CFG_FTHRESH	0x07000000	/* RX FIFO threshold */

/* RXDMA_BLANK bits */
#define RXDMA_BLANK_INTR_TIME	0x000001FF	/* Interrupt blanking time */
#define RXDMA_BLANK_INTR_PACKETS 0x000001FE00	/* Interrupt blanking packets */

/*
 * MAC Core Registers (offset 0x6000)
 */
#define MAC_TXRST		0x6000UL	/* TX MAC software reset */
#define MAC_RXRST		0x6004UL	/* RX MAC software reset */
#define MAC_SNDPAUSE		0x6008UL	/* Send pause command */
#define MAC_TXSTAT		0x6010UL	/* TX MAC status */
#define MAC_RXSTAT		0x6014UL	/* RX MAC status */
#define MAC_CSTAT		0x6018UL	/* MAC control status */
#define MAC_TXMASK		0x6020UL	/* TX MAC mask */
#define MAC_RXMASK		0x6024UL	/* RX MAC mask */
#define MAC_MCMASK		0x6028UL	/* MAC control mask */
#define MAC_TXCFG		0x6030UL	/* TX MAC configuration */
#define MAC_RXCFG		0x6034UL	/* RX MAC configuration */
#define MAC_MCCFG		0x6038UL	/* MAC control configuration */
#define MAC_XIFCFG		0x603CUL	/* XIF configuration */
#define MAC_STIME		0x6040UL	/* Slot time register */
#define MAC_PASIZE		0x6044UL	/* Preamble size */
#define MAC_JAMSIZE		0x6048UL	/* JAM size */
#define MAC_ATTLIM		0x604CUL	/* Attempt limit */
#define MAC_MCTYPE		0x6050UL	/* MAC control type */
#define MAC_ADDR0		0x6080UL	/* MAC address 0 */
#define MAC_ADDR1		0x6084UL	/* MAC address 1 */
#define MAC_ADDR2		0x6088UL	/* MAC address 2 */
#define MAC_ADDR3		0x608CUL	/* MAC address 3 (filter) */
#define MAC_ADDR4		0x6090UL	/* MAC address 4 (filter) */
#define MAC_ADDR5		0x6094UL	/* MAC address 5 (filter) */
#define MAC_ADDR6		0x6098UL	/* MAC address 6 (filter) */
#define MAC_ADDR7		0x609CUL	/* MAC address 7 */
#define MAC_ADDR8		0x60A0UL	/* MAC address 8 (filter) */
#define MAC_AFILT0		0x60A4UL	/* Address filter 0 */
#define MAC_AFILT1		0x60A8UL	/* Address filter 1 */
#define MAC_AFILT2		0x60ACUL	/* Address filter 2 */
#define MAC_AF21MSK		0x60B0UL	/* Address filter 2&1 mask */
#define MAC_AF0MSK		0x60B4UL	/* Address filter 0 mask */
#define MAC_HASH0		0x60C0UL	/* Hash table 0 */
#define MAC_HASH1		0x60C4UL	/* Hash table 1 */
#define MAC_HASH2		0x60C8UL	/* Hash table 2 */
#define MAC_HASH3		0x60CCUL	/* Hash table 3 */
#define MAC_HASH4		0x60D0UL	/* Hash table 4 */
#define MAC_HASH5		0x60D4UL	/* Hash table 5 */
#define MAC_HASH6		0x60D8UL	/* Hash table 6 */
#define MAC_HASH7		0x60DCUL	/* Hash table 7 */
#define MAC_HASH8		0x60E0UL	/* Hash table 8 */
#define MAC_HASH9		0x60E4UL	/* Hash table 9 */
#define MAC_HASH10		0x60E8UL	/* Hash table 10 */
#define MAC_HASH11		0x60ECUL	/* Hash table 11 */
#define MAC_HASH12		0x60F0UL	/* Hash table 12 */
#define MAC_HASH13		0x60F4UL	/* Hash table 13 */
#define MAC_HASH14		0x60F8UL	/* Hash table 14 */
#define MAC_HASH15		0x60FCUL	/* Hash table 15 */
#define MAC_NCOLL		0x6100UL	/* Normal collision counter */
#define MAC_FASUCC		0x6104UL	/* First attempt successful */
#define MAC_ECOLL		0x6108UL	/* Excessive collision counter */
#define MAC_LCOLL		0x610CUL	/* Late collision counter */
#define MAC_DTIMER		0x6110UL	/* Defer timer */
#define MAC_PATMPS		0x6114UL	/* Peak attempts */
#define MAC_RFCTR		0x6118UL	/* RX frame counter */
#define MAC_LERR		0x611CUL	/* Length error counter */
#define MAC_AERR		0x6120UL	/* Alignment error counter */
#define MAC_FCSERR		0x6124UL	/* FCS error counter */
#define MAC_RXCVERR		0x6128UL	/* RX code violation error */
#define MAC_SMACHINE		0x612CUL	/* State machine */
#define MAC_RANDSEED		0x6130UL	/* Random number seed */

/* MAC_TXCFG bits */
#define MAC_TXCFG_ENAB		0x00000001	/* Enable TX MAC */
#define MAC_TXCFG_ICS		0x00000002	/* Ignore carrier sense */
#define MAC_TXCFG_ICOLL		0x00000004	/* Ignore collisions */
#define MAC_TXCFG_EIPG0		0x00000008	/* Enable IPG0 */
#define MAC_TXCFG_NGU		0x00000010	/* Never give up */
#define MAC_TXCFG_NGUL		0x00000020	/* Never give up limit */
#define MAC_TXCFG_NOBKOF	0x00000040	/* No backoff */
#define MAC_TXCFG_SLOWDOWN	0x00000080	/* Slow down */
#define MAC_TXCFG_NFCS		0x00000100	/* No FCS */
#define MAC_TXCFG_CARR		0x00000200	/* Carrier extension */

/* MAC_RXCFG bits */
#define MAC_RXCFG_ENAB		0x00000001	/* Enable RX MAC */
#define MAC_RXCFG_SPAD		0x00000002	/* Strip pad */
#define MAC_RXCFG_SFCS		0x00000004	/* Strip FCS */
#define MAC_RXCFG_PROM		0x00000008	/* Promiscuous mode */
#define MAC_RXCFG_PGRP		0x00000010	/* Promiscuous group */
#define MAC_RXCFG_HENABLE	0x00000020	/* Hash filter enable */
#define MAC_RXCFG_AENABLE	0x00000040	/* Address filter enable */
#define MAC_RXCFG_ERRCHK	0x00000080	/* Error check disable */
#define MAC_RXCFG_CARR		0x00000100	/* Carrier extension */

/* MAC_XIFCFG bits */
#define MAC_XIFCFG_TXOE		0x00000001	/* TX output enable */
#define MAC_XIFCFG_MLBACK	0x00000002	/* MAC loopback */
#define MAC_XIFCFG_SMODE	0x00000004	/* Serial mode */
#define MAC_XIFCFG_GMII		0x00000008	/* GMII mode */
#define MAC_XIFCFG_MBOE		0x00000010	/* MII/GMII output enable */
#define MAC_XIFCFG_LBBACK	0x00000020	/* Loopback bypass */
#define MAC_XIFCFG_DISE		0x00000040	/* Disable echo */
#define MAC_XIFCFG_LLED		0x00000100	/* Link LED */
#define MAC_XIFCFG_FLED		0x00000200	/* Full-duplex LED */

/*
 * MIF Registers (offset 0x6200)
 */
#define MIF_BBCLK		0x6200UL	/* Bit-bang clock */
#define MIF_BBDATA		0x6204UL	/* Bit-bang data */
#define MIF_BBOENAB		0x6208UL	/* Bit-bang output enable */
#define MIF_FRAME		0x620CUL	/* Frame/output register */
#define MIF_CFG			0x6210UL	/* Configuration register */
#define MIF_MASK		0x6214UL	/* Mask register */
#define MIF_STATUS		0x6218UL	/* Status register */
#define MIF_SMACHINE		0x621CUL	/* State machine */

/* MIF_CFG bits */
#define MIF_CFG_PSELECT		0x00000001	/* PHY select */
#define MIF_CFG_POLL		0x00000002	/* Poll enable */
#define MIF_CFG_BBMODE		0x00000004	/* Bit-bang mode */
#define MIF_CFG_PRADDR		0x000000F8	/* Poll register address */
#define MIF_CFG_MDI0		0x00000100	/* MDI_0 (status) */
#define MIF_CFG_MDI1		0x00000200	/* MDI_1 (status) */
#define MIF_CFG_PPADDR		0x00007C00	/* Poll PHY address */

/* MIF_FRAME bits */
#define MIF_FRAME_ST		0xC0000000	/* Start of frame */
#define MIF_FRAME_OP_READ	0x20000000	/* Read operation */
#define MIF_FRAME_OP_WRITE	0x10000000	/* Write operation */
#define MIF_FRAME_PHYAD		0x0F800000	/* PHY address */
#define MIF_FRAME_REGAD		0x007C0000	/* Register address */
#define MIF_FRAME_TAMSB		0x00020000	/* Turn-around MSB */
#define MIF_FRAME_TALSB		0x00010000	/* Turn-around LSB */
#define MIF_FRAME_DATA		0x0000FFFF	/* Data */

/*
 * PCS/SerDes Registers (offset 0x9000)
 */
#define PCS_MIICTRL		0x9000UL	/* PCS MII control */
#define PCS_MIISTAT		0x9004UL	/* PCS MII status */
#define PCS_MIIADV		0x9008UL	/* PCS MII advertisement */
#define PCS_MIILP		0x900CUL	/* PCS MII link partner */
#define PCS_CFG			0x9010UL	/* PCS configuration */
#define PCS_SMACHINE		0x9014UL	/* PCS state machine */
#define PCS_ISTAT		0x9018UL	/* PCS interrupt status */
#define PCS_DMODE		0x9050UL	/* Datapath mode */
#define PCS_SCTRL		0x9054UL	/* SerDes control */
#define PCS_SOS			0x9058UL	/* Shared output select */
#define PCS_SSTATE		0x905CUL	/* SerDes state */

/* PCS_MIICTRL bits */
#define PCS_MIICTRL_SPD		0x00000040	/* Speed selection */
#define PCS_MIICTRL_CT		0x00000080	/* Collision test */
#define PCS_MIICTRL_DUPLEX	0x00000100	/* Duplex mode */
#define PCS_MIICTRL_RAN		0x00000200	/* Restart auto-negotiation */
#define PCS_MIICTRL_ISOLATE	0x00000400	/* Isolate PHY */
#define PCS_MIICTRL_PD		0x00000800	/* Power down */
#define PCS_MIICTRL_ANE		0x00001000	/* Auto-negotiation enable */
#define PCS_MIICTRL_SS		0x00002000	/* Speed selection */
#define PCS_MIICTRL_LB		0x00004000	/* Loopback */
#define PCS_MIICTRL_RST		0x00008000	/* Reset */

/* PCS_CFG bits */
#define PCS_CFG_ENABLE		0x00000001	/* PCS enable */
#define PCS_CFG_SDO		0x00000002	/* Signal detect override */
#define PCS_CFG_SDL		0x00000004	/* Signal detect active low */
#define PCS_CFG_JS		0x00000008	/* Jitter study */
#define PCS_CFG_TO		0x00000020	/* 10ms timer override */

/* PCS_SCTRL bits */
#define PCS_SCTRL_LOOP		0x00000001	/* Loopback */
#define PCS_SCTRL_ESCD		0x00000002	/* Enable sync char det */
#define PCS_SCTRL_ENCDEC	0x00000004	/* Enable encoder/decoder */
#define PCS_SCTRL_EMP		0x00000018	/* Output emphasis */
#define PCS_SCTRL_STEST		0x000001C0	/* Self-test patterns */
#define PCS_SCTRL_PDWN		0x00000200	/* Power down */
#define PCS_SCTRL_RXA		0x00000C00	/* RX sync char aligner */
#define PCS_SCTRL_RXPD		0x00001000	/* RX detect phase detector */
#define PCS_SCTRL_TXPD		0x00002000	/* TX driver power down */

/*
 * Descriptor definitions
 */
#define GEM_TXDESC_OWN		0x8000000000000000ULL	/* Owned by hardware */
#define GEM_TXDESC_SOP		0x4000000000000000ULL	/* Start of packet */
#define GEM_TXDESC_EOP		0x2000000000000000ULL	/* End of packet */
#define GEM_TXDESC_CXSUM_START	0x001F800000000000ULL	/* Checksum start */
#define GEM_TXDESC_CXSUM_OFF	0x00007F8000000000ULL	/* Checksum offset */
#define GEM_TXDESC_CXSUM_EN	0x0000000020000000ULL	/* Checksum enable */
#define GEM_TXDESC_EOF		0x0000000010000000ULL	/* End of frame */
#define GEM_TXDESC_INT		0x0000000008000000ULL	/* Interrupt enable */
#define GEM_TXDESC_NOCRC	0x0000000004000000ULL	/* No CRC */
#define GEM_TXDESC_BUFSIZE	0x0000000000003FFFULL	/* Buffer size */

#define GEM_RXDESC_OWN		0x8000000000000000ULL	/* Owned by hardware */
#define GEM_RXDESC_HASHVAL	0x0FFFF00000000000ULL	/* Hash value */
#define GEM_RXDESC_HASHPASS	0x0000080000000000ULL	/* Hash pass */
#define GEM_RXDESC_ALTMAC	0x0000040000000000ULL	/* Alternate MAC */
#define GEM_RXDESC_BAD		0x0000020000000000ULL	/* Bad CRC */
#define GEM_RXDESC_BUFSIZE	0x0000000000003FFFULL	/* Buffer size */

/*
 * Useful constants
 */
#define GEM_MIN_MTU		60
#define GEM_MAX_MTU		9000
#define GEM_JUMBO_MTU		9000

#define GEM_TX_TIMEOUT		(5 * HZ)	/* TX timeout */
#define GEM_LINK_TIMEOUT	(4 * HZ)	/* Link timeout */

#define ALIGNED(addr, size)	(((unsigned long)(addr) & ((size) - 1)) == 0)

#endif /* _GEMENETREGISTERS_H */
