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

typedef struct enet_dma_cmd_t
{
    IODBDMADescriptor	desc_seg[2];
} enet_dma_cmd_t;

typedef struct enet_txdma_cmd_t
{
    IODBDMADescriptor	desc_seg[3];
} enet_txdma_cmd_t;

/*
 * Ring buffer sizes - must match values in _allocateMemory
 */
#define TRANSMIT_RING_SIZE  128
#define RECEIVE_RING_SIZE   128

@interface UniNEnet:IOEthernet <IOPower>
{
    volatile IOPPCAddress       	ioBaseEnet;
    volatile IODBDMAChannelRegisters 	*ioBaseEnetRxDMA;
    volatile IODBDMAChannelRegisters 	*ioBaseEnetTxDMA;

    enet_addr_t				myAddress;
    IONetwork				*networkInterface;
    IONetbufQueue			*transmitQueue;
    BOOL				isPromiscuous;
    BOOL				multicastEnabled;
    BOOL				isFullDuplex;

    BOOL				resetAndEnabled;

    /*
     * Transmit DMA support
     */
    enet_txdma_cmd_t			*txDMACommands;
    u_int32_t				txDMACommandsPhys;	// Physical address of TX DMA commands
    u_int32_t				txCommandHead;
    u_int32_t				txCommandTail;
    u_int32_t				txMaxCommand;
    netbuf_t				txNetbuf[TRANSMIT_RING_SIZE];

    /*
     * Receive DMA support
     */
    enet_dma_cmd_t			*rxDMACommands;
    u_int32_t				rxDMACommandsPhys;	// Physical address of RX DMA commands
    u_int32_t				rxCommandHead;
    u_int32_t				rxCommandTail;
    u_int32_t				rxMaxCommand;
    netbuf_t				rxNetbuf[RECEIVE_RING_SIZE];

    void 				*dmaCommands;

    /*
     * MII/PHY support
     */
    unsigned char			phyId;
    BOOL				phyStatusPrev;
    BOOL				phyType;
    u_int32_t				phyMfgID;		// PHY manufacturer/model ID from MII regs 2&3

    /*
     * Debugger support
     */
    netbuf_t				debuggerPkt;
    void				*debuggerBuf;
    BOOL				rxDebuggerPkt;
    u_int32_t				rxDebuggerBytes;
    BOOL				txDebuggerPkt;

    /*
     * Power management support
     */
    unsigned long			currentPowerState;
    unsigned long			numberOfPowerStates;
    IOPMPowerState			powerStates[2];

    u_int16_t				hashTableUseCount[256];
    u_int16_t				hashTableMask[16];

    u_int8_t				chipId;
    BOOL				chipIdVerified;
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
