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
 * Interface definition for the UniN Ethernet Controller
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

typedef void  *		IOPPCAddress;

/*
 * Ring buffer sizes - must match values in _allocateMemory
 */
#define TRANSMIT_RING_SIZE  128
#define RECEIVE_RING_SIZE   128

@interface UniNEnet:IOEthernet <IOPower>
{
    /* Base addresses - 0x174 */
    volatile IOPPCAddress       	ioBaseEnet;             /* +0x174: Ethernet controller registers */

    /* Hardware addresses - 0x178 */
    enet_addr_t				myAddress;              /* +0x178: Station MAC address (6 bytes) */
    /* 2 bytes padding to align to 4-byte boundary */

    /* Network interface - 0x180 */
    IONetwork				*networkInterface;      /* +0x180: Network interface object */
    IONetbufQueue			*transmitQueue;         /* +0x184: Transmit queue */

    /* Mode flags - 0x188 */
    BOOL				isPromiscuous;          /* +0x188: Promiscuous mode flag */
    BOOL				multicastEnabled;       /* +0x189: Multicast enabled flag */
    BOOL				isFullDuplex;           /* +0x18A: Full duplex mode flag */
    BOOL				resetAndEnabled;        /* +0x18B: Reset and enabled flag */

    /* MII/PHY support - 0x18C */
    unsigned int			phyType;                /* +0x18C: PHY manufacturer/model ID (MII ID0+ID1) */
    unsigned char			phyId;                  /* +0x190: PHY address on MII bus */
    /* 1 byte padding */
    unsigned short			phyStatusPrev;          /* +0x192: Previous PHY status (MII register 1) */
    char				linkStatusPrev;         /* +0x194: Previous link status (0=down, 1=up) */
    /* 3 bytes padding to align to 4-byte boundary */

    /* Transmit/Receive buffers - 0x198 */
    netbuf_t				txNetbuf[TRANSMIT_RING_SIZE];  /* +0x198: TX netbuf array [128] */
    netbuf_t				rxNetbuf[RECEIVE_RING_SIZE];   /* +0x398: RX netbuf array [128] */

    /* Transmit DMA ring management - 0x598 */
    u_int32_t				txCommandHead;          /* +0x598: TX command head index */
    u_int32_t				txCommandTail;          /* +0x59C: TX command tail index */
    u_int32_t				txMaxCommand;           /* +0x5A0: TX max command index */

    /* Receive DMA ring management - 0x5A4 */
    u_int32_t				rxCommandHead;          /* +0x5A4: RX command head index */
    u_int32_t				rxCommandTail;          /* +0x5A8: RX command tail index */
    u_int32_t				rxMaxCommand;           /* +0x5AC: RX max command index */

    /* DMA command buffers - 0x5B0 */
    void 				*dmaCommands;           /* +0x5B0: DMA commands buffer */
    void				*txDMACommands;         /* +0x5B4: TX DMA command descriptors */
    u_int32_t				txDMACommandsPhys;      /* +0x5B8: TX DMA physical address */
    void				*rxDMACommands;         /* +0x5BC: RX DMA command descriptors */
    u_int32_t				rxDMACommandsPhys;      /* +0x5C0: RX DMA physical address */

    /* Watchdog support - 0x5C4 */
    u_int32_t				txWDInterrupts;         /* +0x5C4: TX watchdog interrupt count */
    u_int32_t				txWDCount;              /* +0x5C8: TX watchdog count */

    /* Debugger support - 0x5CC */
    netbuf_t				debuggerPkt;            /* +0x5CC: Debugger packet buffer */
    u_int32_t				debuggerPktSize;        /* +0x5D0: Debugger packet size */

    /* Hash table for multicast filtering - 0x5D4 */
    u_int16_t				hashTableUseCount[256]; /* +0x5D4: Hash table use count */
    u_int16_t				hashTableMask[16];      /* +0x7D4: Hash table mask */
    /* Total size: 0x7F4 (2036 bytes) */
}

/*
 * Public Instance Methods
 */
- initFromDeviceDescription:(IOTreeDevice *)devDesc;
- free;

- (void)transmit:(netbuf_t)pkt;
- (void)serviceTransmitQueue;
- (BOOL)resetAndEnable:(BOOL)enable;

- (void)interruptOccurred;
- (void)timeoutOccurred;

- (void)enableMulticastMode;
- (void)disableMulticastMode;
- (void)enablePromiscuousMode;
- (void)disablePromiscuousMode;

/*
 * Multicast support
 */
- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)removeMulticastAddress:(enet_addr_t *)addr;

/*
 * Kernel debugger support
 */
- (void)sendPacket:(void *)pkt length:(unsigned int)pkt_len;
- (void)receivePacket:(void *)pkt length:(unsigned int *)pkt_len timeout:(unsigned int)timeout;

/*
 * Power management support
 */
- (IOReturn)getPowerState:(PMPowerState *)state_p;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state_p;
- (IOReturn)setPowerState:(PMPowerState)state;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;

/*
 * Transmit queue support
 */
- (int)transmitQueueSize;
- (int)transmitQueueCount;

@end
