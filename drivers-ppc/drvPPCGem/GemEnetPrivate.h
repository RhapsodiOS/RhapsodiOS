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
 * Private definitions for the Sun GEM Gigabit Ethernet Controller
 *
 * HISTORY
 *
 */

#ifndef _GEMENETPRIVATE_H
#define _GEMENETPRIVATE_H

#import "GemEnet.h"

/*
 * Debug macros
 */
#define GEM_DEBUG		0

#if GEM_DEBUG
#define GEM_LOG(fmt, args...)	IOLog("GemEnet: " fmt, ## args)
#define GEM_TRACE(fmt, args...)	IOLog("GemEnet: %s: " fmt, __FUNCTION__, ## args)
#else
#define GEM_LOG(fmt, args...)
#define GEM_TRACE(fmt, args...)
#endif

#define GEM_ERROR(fmt, args...)	IOLog("GemEnet ERROR: " fmt, ## args)

/*
 * Chip identification
 */
#define GEM_VENDOR_APPLE	0x106B
#define GEM_VENDOR_SUN		0x108E

#define GEM_DEVICE_APPLE_GMAC	0x0021	/* UniNorth GMAC */
#define GEM_DEVICE_APPLE_GMAC2	0x0024	/* UniNorth/Pangea GMAC */
#define GEM_DEVICE_APPLE_GMAC3	0x0032	/* UniNorth 2 GMAC */
#define GEM_DEVICE_APPLE_K2	0x004C	/* K2 GMAC */
#define GEM_DEVICE_APPLE_SHASTA	0x0051	/* Shasta GMAC */
#define GEM_DEVICE_APPLE_INTREPID2 0x006B /* Intrepid 2 GMAC */

#define GEM_DEVICE_SUN_GEM	0x1101	/* Sun GEM */
#define GEM_DEVICE_SUN_ERI	0x1100	/* Sun ERI 10/100 */

/*
 * PHY register definitions (MII/GMII)
 */
#define PHY_CONTROL		0x00	/* Control Register */
#define PHY_STATUS		0x01	/* Status Register */
#define PHY_ID1			0x02	/* PHY Identifier 1 */
#define PHY_ID2			0x03	/* PHY Identifier 2 */
#define PHY_AUTONEG_ADV		0x04	/* Auto-Negotiation Advertisement */
#define PHY_AUTONEG_LP		0x05	/* Auto-Negotiation Link Partner */
#define PHY_AUTONEG_EXP		0x06	/* Auto-Negotiation Expansion */
#define PHY_AUTONEG_NP		0x07	/* Auto-Negotiation Next Page */
#define PHY_AUTONEG_LPNP	0x08	/* Auto-Negotiation Link Partner NP */
#define PHY_1000BT_CONTROL	0x09	/* 1000BASE-T Control */
#define PHY_1000BT_STATUS	0x0A	/* 1000BASE-T Status */
#define PHY_EXT_STATUS		0x0F	/* Extended Status */

/* PHY_CONTROL bits */
#define PHY_CTRL_RESET		0x8000	/* PHY reset */
#define PHY_CTRL_LOOPBACK	0x4000	/* Enable loopback */
#define PHY_CTRL_SPEED_SEL	0x2000	/* Speed select (LSB) */
#define PHY_CTRL_AUTONEG_EN	0x1000	/* Auto-negotiation enable */
#define PHY_CTRL_POWERDOWN	0x0800	/* Power down */
#define PHY_CTRL_ISOLATE	0x0400	/* Isolate */
#define PHY_CTRL_RESTART_AN	0x0200	/* Restart auto-negotiation */
#define PHY_CTRL_DUPLEX		0x0100	/* Duplex mode */
#define PHY_CTRL_COLLISION_TEST	0x0080	/* Collision test */
#define PHY_CTRL_SPEED_1000	0x0040	/* Speed select (MSB) */

/* PHY_STATUS bits */
#define PHY_STAT_100BT4		0x8000	/* 100BASE-T4 capable */
#define PHY_STAT_100BTXFD	0x4000	/* 100BASE-TX full duplex */
#define PHY_STAT_100BTXHD	0x2000	/* 100BASE-TX half duplex */
#define PHY_STAT_10BTFD		0x1000	/* 10BASE-T full duplex */
#define PHY_STAT_10BTHD		0x0800	/* 10BASE-T half duplex */
#define PHY_STAT_100BT2FD	0x0400	/* 100BASE-T2 full duplex */
#define PHY_STAT_100BT2HD	0x0200	/* 100BASE-T2 half duplex */
#define PHY_STAT_EXT_STAT	0x0100	/* Extended status */
#define PHY_STAT_AN_COMPLETE	0x0020	/* Auto-negotiation complete */
#define PHY_STAT_REMOTE_FAULT	0x0010	/* Remote fault */
#define PHY_STAT_AN_CAPABLE	0x0008	/* Auto-negotiation capable */
#define PHY_STAT_LINK_UP	0x0004	/* Link status */
#define PHY_STAT_JABBER		0x0002	/* Jabber detect */
#define PHY_STAT_EXT_CAPABLE	0x0001	/* Extended capability */

/* PHY_AUTONEG_ADV bits */
#define PHY_AN_ADV_NP		0x8000	/* Next page */
#define PHY_AN_ADV_ACK		0x4000	/* Acknowledge */
#define PHY_AN_ADV_RF		0x2000	/* Remote fault */
#define PHY_AN_ADV_ASYMPAUSE	0x0800	/* Asymmetric pause */
#define PHY_AN_ADV_PAUSE	0x0400	/* Pause */
#define PHY_AN_ADV_100BT4	0x0200	/* 100BASE-T4 */
#define PHY_AN_ADV_100BTXFD	0x0100	/* 100BASE-TX full duplex */
#define PHY_AN_ADV_100BTXHD	0x0080	/* 100BASE-TX half duplex */
#define PHY_AN_ADV_10BTFD	0x0040	/* 10BASE-T full duplex */
#define PHY_AN_ADV_10BTHD	0x0020	/* 10BASE-T half duplex */
#define PHY_AN_ADV_SELECTOR	0x001F	/* Protocol selector */

/* PHY_1000BT_CONTROL bits */
#define PHY_1000BT_CTL_MS_VAL	0x1000	/* Master/slave manual config */
#define PHY_1000BT_CTL_MS_EN	0x0800	/* Master/slave enable */
#define PHY_1000BT_CTL_PORTTYPE	0x0400	/* Port type */
#define PHY_1000BT_CTL_ADV_FD	0x0200	/* Advertise full duplex */
#define PHY_1000BT_CTL_ADV_HD	0x0100	/* Advertise half duplex */

/* PHY_1000BT_STATUS bits */
#define PHY_1000BT_STAT_MS_FAULT 0x8000	/* Master/slave fault */
#define PHY_1000BT_STAT_MS_RES	0x4000	/* Master/slave resolution */
#define PHY_1000BT_STAT_LOCAL_RX 0x2000	/* Local receiver status */
#define PHY_1000BT_STAT_REMOTE_RX 0x1000 /* Remote receiver status */
#define PHY_1000BT_STAT_LP_FD	0x0800	/* Link partner full duplex */
#define PHY_1000BT_STAT_LP_HD	0x0400	/* Link partner half duplex */
#define PHY_1000BT_STAT_IDLE_ERR 0x00FF	/* Idle error count */

/*
 * Broadcom PHY specific registers
 */
#define BCM5400_AUX_CONTROL	0x18	/* Auxiliary control */
#define BCM5400_AUX_STATUS	0x19	/* Auxiliary status */
#define BCM5400_INT_STATUS	0x1A	/* Interrupt status */
#define BCM5400_INT_MASK	0x1B	/* Interrupt mask */

/* BCM5400_AUX_STATUS bits */
#define BCM5400_AUXSTAT_LINKMODE_MASK	0x0700
#define BCM5400_AUXSTAT_LINKMODE_SHIFT	8

/*
 * Timing constants
 */
#define GEM_PHY_RESET_DELAY	10		/* PHY reset delay (ms) */
#define GEM_PHY_STABLE_DELAY	10		/* PHY stabilization delay (ms) */
#define GEM_STOP_DELAY		20		/* Stop delay (ms) */
#define GEM_LINK_POLL_INTERVAL	(2 * HZ)	/* Link polling interval */

/*
 * DMA alignment requirements
 */
#define GEM_TX_DESC_ALIGN	2048	/* TX descriptor alignment */
#define GEM_RX_DESC_ALIGN	2048	/* RX descriptor alignment */
#define GEM_TX_BUF_ALIGN	8	/* TX buffer alignment */
#define GEM_RX_BUF_ALIGN	8	/* RX buffer alignment */

/*
 * Private method declarations
 */
@interface GemEnet(Private)

/* Hardware access */
- (u_int32_t)readRegister:(unsigned int)offset;
- (void)writeRegister:(unsigned int)offset value:(u_int32_t)value;

/* Initialization and configuration */
- (BOOL)initChip;
- (BOOL)initRings;
- (void)freeRings;
- (BOOL)allocateMemory;
- (void)freeMemory;

/* PHY management */
- (BOOL)phyProbe;
- (BOOL)phyInit;
- (BOOL)phyReset;
- (u_int16_t)phyRead:(u_int8_t)reg;
- (void)phyWrite:(u_int8_t)reg value:(u_int16_t)val;
- (void)phyCheckLink;
- (BOOL)phySetupForcedMode;
- (BOOL)phySetupAutoNeg;

/* MIF (Management Interface) */
- (u_int16_t)mifReadPHY:(u_int8_t)phy reg:(u_int8_t)reg;
- (void)mifWritePHY:(u_int8_t)phy reg:(u_int8_t)reg value:(u_int16_t)val;
- (void)mifPollStart;
- (void)mifPollStop;

/* TX/RX operations */
- (void)txReset;
- (void)rxReset;
- (void)txEnable;
- (void)rxEnable;
- (void)txDisable;
- (void)rxDisable;
- (BOOL)txQueuePacket:(netbuf_t)pkt;
- (void)txComplete;
- (void)rxProcess;
- (BOOL)rxRefill;

/* Multicast/promiscuous */
- (void)setMulticastFilter;
- (u_int16_t)hashCRC:(enet_addr_t *)addr;

/* Interrupt handling */
- (void)handleInterrupt;
- (void)handleAbnormalInterrupt:(u_int32_t)status;

/* Timer */
- (void)startWatchdogTimer;
- (void)stopWatchdogTimer;

/* Utility */
- (void)dumpRegisters;
- (void)dumpDescriptors;
- (const char *)linkStateString;

@end

#endif /* _GEMENETPRIVATE_H */
