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
 * Interface for hardware dependent (relatively) code
 * for the UniN Ethernet chip
 *
 * HISTORY
 *
 */

#import "UniNEnet.h"
#import "UniNEnetMII.h"
#import "UniNEnetRegisters.h"

/*
 * UniN Ethernet hardware descriptor structures (16 bytes each, big-endian)
 * These match the exact hardware format used by the DMA engine.
 */

/* Receive descriptor (16 bytes) */
typedef struct {
    u_int16_t   reserved1;      /* Offset +0: Unused */
    u_int16_t   status;         /* Offset +2: Status/size word (bit 15=ownership, bits 14-0=size) */
    u_int32_t   flags;          /* Offset +4: Status flags */
    u_int32_t   bufferPtr;      /* Offset +8: Physical buffer address */
    u_int32_t   reserved2;      /* Offset +12: Unused */
} UniNRxDescriptor;

/* Transmit descriptor (16 bytes) */
typedef struct {
    u_int32_t   control;        /* Offset +0: Control word (size | 0xC0000000) */
    u_int32_t   interrupt;      /* Offset +4: Interrupt flag (0 or 1) */
    u_int32_t   bufferPtr;      /* Offset +8: Physical buffer address */
    u_int32_t   reserved;       /* Offset +12: Unused */
} UniNTxDescriptor;

void WriteUniNRegister(IOPPCAddress ioEnetBase, u_int32_t reg_offset, u_int32_t data);
u_int32_t ReadUniNRegister(IOPPCAddress ioEnetBase, u_int32_t reg_offset);

@interface UniNEnet (Private)
- (BOOL)_allocateMemory;
- (BOOL)_initTxRing;
- (BOOL)_initRxRing;

- (BOOL)_initChip;
- (void)_resetChip;
- (void)_disableAdapterInterrupts;
- (void)_enableAdapterInterrupts;
- (void)_setDuplexMode:(BOOL)duplexMode;

- (void)_startChip;
- (void)_stopChip;
- (void)_restartTransmitter;
- (void)_restartReceiver;
- (void)_stopTransmitDMA;
- (void)_stopReceiveDMA;
- (BOOL)_transmitPacket:(netbuf_t)packet;

- (BOOL)_receiveInterruptOccurred;
- (BOOL)_receivePackets:(BOOL)fDebugger;
- (BOOL)_transmitInterruptOccurred;
- (BOOL)_updateDescriptorFromNetBuf:(netbuf_t)nb Desc:(void *)desc ReceiveFlag:(BOOL)isReceive;

/*
 * Kernel Debugger
 */
- (void)_sendPacket:(void *)pkt length:(unsigned int)pkt_len;
- (void)_receivePacket:(void *)pkt length:(unsigned int *)pkt_len timeout:(unsigned int)timeout;
- (void)_packetToDebugger:(netbuf_t)packet;

- (void)_sendDummyPacket;
- (void)_getStationAddress:(enet_addr_t *)ea;
- (void)_addToHashTableMask:(u_int8_t *)addr;
- (void)_removeFromHashTableMask:(u_int8_t *)addr;
- (void)_updateUniNHashTableMask;
- (void)_dumpRegisters;
- (void)_monitorLinkStatus;
@end
