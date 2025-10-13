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
 * Interface definition for the Sun GEM Gigabit Ethernet Controller
 *
 * HISTORY
 *
 */

#import <driverkit/kernelDriver.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/ppc/IOTreeDevice.h>
#import <driverkit/ppc/IODBDMA.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/IOPower.h>
#import <machdep/ppc/proc_reg.h>		/* eieio */
#import <bsd/net/etherdefs.h>
#import <bsd/sys/systm.h>			/* bcopy */
#import <driverkit/IOEthernetPrivate.h>		/* debugger methods */
#import <kern/kdebug.h>				/* Performance tracepoints */

#import "GemEnetRegisters.h"

typedef void  *		IOPPCAddress;

/* Descriptor ring sizes */
#define TX_RING_LENGTH		256
#define RX_RING_LENGTH		256
#define RX_RING_WRAP		(RX_RING_LENGTH - 1)
#define TX_RING_WRAP		(TX_RING_LENGTH - 1)

/* Buffer sizes */
#define RX_BUF_SIZE		2048
#define TX_BUF_SIZE		2048

/* Descriptor entry size */
#define GEM_DESC_SIZE		16

/* DMA descriptor structure for Sun GEM */
typedef struct gem_dma_desc_t
{
    volatile u_int32_t	flags;		/* Control flags and buffer length */
    volatile u_int32_t	buffer;		/* Physical buffer address */
    volatile u_int32_t	reserved[2];	/* Reserved for future use */
} gem_dma_desc_t;

/* Descriptor flags */
#define GEM_DESC_OWN		0x80000000	/* Owned by hardware */
#define GEM_DESC_SOP		0x40000000	/* Start of packet */
#define GEM_DESC_EOP		0x20000000	/* End of packet */
#define GEM_DESC_INT		0x10000000	/* Generate interrupt */
#define GEM_DESC_NOCRC		0x08000000	/* No CRC append (TX only) */
#define GEM_DESC_BUFLEN_MASK	0x00001FFF	/* Buffer length mask */

/* PHY types */
#define PHY_TYPE_UNKNOWN	0
#define PHY_TYPE_BCM5400	1
#define PHY_TYPE_BCM5401	2
#define PHY_TYPE_BCM5411	3
#define PHY_TYPE_BCM5421	4
#define PHY_TYPE_MII		5

/* Link states */
#define LINK_STATE_UNKNOWN	0
#define LINK_STATE_DOWN		1
#define LINK_STATE_UP_10MB	2
#define LINK_STATE_UP_100MB	3
#define LINK_STATE_UP_1000MB	4

@interface GemEnet:IOEthernet <IOPower>
{
    volatile IOPPCAddress       	ioBaseGem;
    volatile IOPPCAddress		ioBasePCI;

    enet_addr_t				myAddress;
    IONetwork				*networkInterface;
    IONetbufQueue			*transmitQueue;
    BOOL				isPromiscuous;
    BOOL				multicastEnabled;
    BOOL				isFullDuplex;
    BOOL				gigabitCapable;

    BOOL				resetAndEnabled;

    unsigned long			chipId;
    unsigned long			chipRevision;

    unsigned long			phyType;
    unsigned char			phyId;
    unsigned short			phyStatusPrev;
    unsigned char			linkState;

    netbuf_t				txNetbuf[TX_RING_LENGTH];
    netbuf_t				rxNetbuf[RX_RING_LENGTH];

    unsigned int			txDescHead;		/* Transmit descriptor index */
    unsigned int			txDescTail;
    unsigned int			rxDescHead;		/* Receive descriptor index */
    unsigned int			rxDescTail;

    gem_dma_desc_t *			txDescriptors;		/* TX descriptor ring ptr */
    unsigned int			txDescriptorsPhys;
    gem_dma_desc_t *			rxDescriptors;		/* RX descriptor ring ptr */
    unsigned int			rxDescriptorsPhys;

    unsigned char *			txBuffers;		/* TX buffer pool */
    unsigned int			txBuffersPhys;
    unsigned char *			rxBuffers;		/* RX buffer pool */
    unsigned int			rxBuffersPhys;

    u_int32_t				txWDInterrupts;
    u_int32_t				txWDCount;

    netbuf_t				debuggerPkt;
    u_int32_t                  		debuggerPktSize;
    u_int32_t				debuggerLockCount;

    u_int16_t				hashTableUseCount[256];
    u_int16_t         			hashTableMask[16];

    unsigned int			rxInterrupts;
    unsigned int			txInterrupts;
    unsigned int			errorInterrupts;

    /* Statistics */
    unsigned int			txPackets;
    unsigned int			rxPackets;
    unsigned int			txErrors;
    unsigned int			rxErrors;
}

+ (BOOL)probe:devDesc;
- initFromDeviceDescription:devDesc;

- free;
- (void)transmit:(netbuf_t)pkt;
- (void)serviceTransmitQueue;
- (BOOL)resetAndEnable:(BOOL)enable;

- (void)interruptOccurredAt:(int)irqNum;
- (void)timeoutOccurred;

- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;

/*
 * Kernel Debugger
 */
- (void)sendPacket:(void *)pkt length:(unsigned int)pkt_len;
- (void)receivePacket:(void *)pkt length:(unsigned int *)pkt_len timeout:(unsigned int)timeout;

/*
 * Power management methods.
 */
- (IOReturn)getPowerState:(PMPowerState *)state_p;
- (IOReturn)setPowerState:(PMPowerState)state;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state_p;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;

@end
