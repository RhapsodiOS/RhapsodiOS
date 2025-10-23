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

/* AttoScsiController.h - Atto SCSI Controller Driver */

#import <bsd/sys/systm.h>
#import <bsd/include/string.h>
#import <mach/vm_param.h>
#import <machkit/NXLock.h>
#import <kernserv/ns_timer.h>
#import <kern/queue.h>
#import <driverkit/driverTypes.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/IODirectDevice.h>
#import <driverkit/ppc/IOPCIDevice.h>

#import <driverkit/IOSimpleMemoryDescriptor.h>

#import <bsd/dev/scsireg.h>
#import <driverkit/IOSCSIController.h>

#import "AttoScsiRegs.h"
#import "AttoScsiInterface.h"

#define MAX_SCSI_TARGETS    16
#define MAX_SCSI_TAG        256

typedef struct Target
{
    u_int32_t              flags;         // Target capability flags
    NXLock                 *targetLock;   // Lock for this target
} Target;

@interface AttoScsiController : IOSCSIController
{
    u_int32_t              initiatorID;

    volatile u_int8_t      *chipBaseAddr;       // Offset 0x75c
    u_int8_t               *chipBaseAddrPhys;   // Offset 0x768
    u_int8_t               *chipRamAddrPhys;
    u_int8_t               *chipRamAddrVirt;

    u_int32_t              chipType;           // Chip type identifier
    u_int32_t              chipClockRate;      // Chip clock frequency
    u_int32_t              chipFeatures;       // Chip feature flags
    u_int32_t              scntl3Value;        // SCNTL3 register value
    u_int16_t              chipCapabilities;   // Chip capability flags
    u_int16_t              syncOffset;         // Sync transfer offset value
    u_int16_t              syncOffsetSaved;    // Saved sync offset

    u_int8_t               padding_pre244[0x200];  // Padding to reach 0x244
    AdapterInterface       *adapterInterface;   // Offset 0x244 - Quick access to adapter
    u_int8_t               padding_248[4];      // Offset 0x248-0x24b
    Target                 targets[MAX_SCSI_TARGETS];  // Offset 0x24c - Target info array (16*8 = 0x80)
    u_int32_t              tagBitmap[8];        // Offset 0x2cc - Tag allocation bitmap (256 bits)
    u_int8_t               padding_post_bitmap[0x420];  // Padding to reach 0x6ec

    u_int8_t               mailBoxIndex;        // Offset 0x6ec
    u_int8_t               padding_6ed[7];      // Offset 0x6ed-0x6f3
    u_int8_t               istatReg;            // Offset 0x6f4
    u_int8_t               dstatReg;            // Offset 0x6f5
    u_int16_t              sistReg;             // Offset 0x6f6
    u_int32_t              scriptRestartAddr;   // Offset 0x6f8
    NXLock                 *queueLock;          // Offset 0x6fc
    queue_head_t           commandQueue;        // Offset 0x700 (head) and 0x704 (tail)
    NXConditionLock        *srbPoolSemaphore;   // Offset 0x708
    u_int32_t              srbPoolFlag;         // Offset 0x70c
    NXLock                 *srbPoolLock;        // Offset 0x710
    queue_head_t           srbPoolPages;        // Offset 0x714 (head) and 0x718 (tail)

    u_int32_t              resetSeqNum;         // Offset 0x71c
    u_int32_t              srbSeqNum;           // Offset 0x720
    NXLock                 *resetQuiesceSem;    // Offset 0x724
    u_int32_t              resetQuiesceTimer;   // Offset 0x728
    NXLock                 *untaggedLock;       // Offset 0x72c - Lock for untagged commands
    NXLock                 *timeoutLock;        // Offset 0x730 - Timeout processing lock
    u_int8_t               padding_734[4];      // Offset 0x734-0x737
    port_t                 interruptPortKern;   // Offset 0x738

    SRB                    *resetSRB;           // Offset 0x73c
    SRB                    *abortSRB;           // Offset 0x740
    u_int32_t              abortSRBTimeout;     // Offset 0x744

    SRB                    *abortCurrentSRB;    // Offset 0x748
    u_int32_t              abortCurrentSRBTimeout; // Offset 0x74c

    AdapterInterface       *adapter;            // Offset 0x764
    u_int8_t               padding_768[7];      // Offset 0x768-0x76e
    u_int8_t               sdtrPeriod;          // Offset 0x76f - Synchronous transfer period
    u_int8_t               padding_770;         // Offset 0x770
    u_int8_t               sdtrOffset;          // Offset 0x771 - Synchronous transfer offset
}
@end

@interface AttoScsiController(Init)
+ (id)      initialize;
+ (BOOL)    probe:(IOPCIDevice *)deviceDescription;
- (id)      initFromDeviceDescription:(IOPCIDevice *)deviceDescription;
- (BOOL)    AttoScsiInit:(IOPCIDevice *)deviceDescription;
- (BOOL)    AttoScsiInitPCI:(IOPCIDevice *)deviceDescription;
- (BOOL)    AttoScsiInitVars;
- (BOOL)    AttoScsiInitChip;
- (BOOL)    AttoScsiInitScript;
- (void)    AttoScsiLoadScript:(u_int32_t *)scriptData count:(u_int32_t)wordCount;
@end

@interface AttoScsiController(Client)
- (sc_status_t) executeRequest:(IOSCSIRequest *)scsiReq  buffer:(void *)buffer  client:(vm_task_t)client;
- (sc_status_t) executeRequest:(IOSCSIRequest *)scsiReq  ioMemoryDescriptor:(IOMemoryDescriptor *)ioMemoryDescriptor;
- (sc_status_t) resetSCSIBus;
- (void)        getDMAAlignment:(IODMAAlignment *)alignment;
- (int)         numberOfTargets;
- (void)        AttoScsiGrowSRBPool;
- (SRB *)       AttoScsiAllocSRB;
- (void)        AttoScsiFreeSRB:(SRB *)srb;
- (void)        AttoScsiAllocTag:(SRB *)srb CmdQueue:(BOOL)cmdQueue;
- (void)        AttoScsiFreeTag:(SRB *)srb;
- (BOOL)        AttoScsiUpdateSGListDesc:(SRB *)srb;
- (BOOL)        AttoScsiUpdateSGListVirt:(SRB *)srb;
- (void)        AttoScsiSendCommand:(SRB *)srb;
- (void)        AttoScsiUpdateSGList:(SRB *)srb;
@end

@interface AttoScsiController(Execute)
- (void) commandRequestOccurred;
- (void) interruptOccurred;
- (int)  checkForPendingInterrupt;
- (void) timeoutOccurred;
- (void) AttoScsiAbortScript;
- (void) AttoScsiAbortBdr:(SRB *)srb;
- (void) AttoScsiAbortCurrent:(SRB *)srb;
- (void) AttoScsiClearFifo;
- (void) AttoScsiSignalScript:(SRB *)srb;
- (void) AttoScsiSCSIBusReset:(SRB *)srb;
- (void) AttoScsiProcessSCSIBusReset;
- (void) AttoScsiProcessNoNexus;
- (void) AttoScsiNegotiateWDTR:(SRB *)srb Nexus:(Nexus *)nexus;
- (void) AttoScsiNegotiateSDTR:(SRB *)srb Nexus:(Nexus *)nexus;
- (void) AttoScsiSendMsgReject:(SRB *)srb;
- (void) AttoScsiUpdateXferOffset:(SRB *)srb;
- (u_int32_t) AttoScsiCheckFifo:(SRB *)srb FifoCnt:(u_int32_t *)fifoCnt;
- (void) AttoScsiAdjustDataPtrs:(SRB *)srb Nexus:(Nexus *)nexus;
- (void) AttoScsiIssueRequestSense:(SRB *)srb;
- (BOOL) AttoScsiProcessStatus:(SRB *)srb;
- (void) AttoScsiCalcMsgs:(SRB *)srb;
- (void) AttoScsiUpdateSGList:(SRB *)srb;
- (void) AttoScsiCheckInquiryData:(SRB *)srb;
- (void) AttoScsiProcessInterrupt;
- (void) AttoScsiProcessIODone;

IOThreadFunc AttoScsiTimerReq(AttoScsiController *device);
@end

/* Period entry structure for synchronous transfer timing */
typedef struct PeriodEntry
{
    u_int8_t    period;          /* Transfer period value */
    u_int8_t    scntl3Bits;      /* SCNTL3 register bits to set */
    u_int8_t    sxferBits;       /* SXFER register bits to set */
} PeriodEntry;

PeriodEntry *GetPeriodEntry(u_int8_t wideEnabled, u_int16_t clockRate);

u_int32_t AttoScsiReadRegs( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize );
void      AttoScsiWriteRegs( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t regValue );
void      AttoScsiModRegBits( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t mask, u_int32_t value );
void      AttoScsiClearRegBits( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t clearMask );

/* Kernel function declarations */
extern kern_return_t    kmem_alloc_wired(vm_task_t task, vm_address_t *addr, vm_size_t size);
extern kern_return_t    kmem_free(vm_task_t task, vm_address_t addr, vm_size_t size);
extern kern_return_t    msg_send_from_kernel(msg_header_t *msg_header, int option, int timeout);
extern kern_return_t    IOPhysicalFromVirtual(vm_task_t task, vm_address_t virt, vm_offset_t *phys);

/* DriverKit function declarations */
extern vm_task_t        IOVmTaskSelf(void);
extern port_t           IOConvertPort(port_t port, int to_type, int from_type);
extern void             IOForkThread(IOThreadFunc func, void *arg);

extern u_int32_t        page_size;

static __inline__ u_int16_t EndianSwap16(volatile u_int16_t y)
{
    u_int16_t           result;
    volatile u_int16_t  x;

    x = y;
    __asm__ volatile("lhbrx %0, 0, %1" : "=r" (result) : "r" (&x) : "r0");
    return result;
}

static __inline__ u_int32_t EndianSwap32(u_int32_t y)
{
    u_int32_t           result;
    volatile u_int32_t  x;

    x = y;
    __asm__ volatile("lwbrx %0, 0, %1" : "=r" (result) : "r" (&x) : "r0");
    return result;
}

#ifndef eieio
#define eieio() \
        __asm__ volatile("eieio")
#endif
