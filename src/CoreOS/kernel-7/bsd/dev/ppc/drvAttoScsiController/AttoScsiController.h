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

/* AttoScsiController.h created by russb2 on Sat 30-May-1998 */

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
#import "AttoScsiSRB.h"

#import "AttoScsiScript.h"

@interface AttoScsiController : IOSCSIController
{
    AdapterInterface            *adapter;
    AdapterInterface		*adapterPhys;

    Target 			targets[MAX_SCSI_TARGETS];
    u_int32_t              	tags[MAX_SCSI_TAG/32];
    u_int32_t			nexusArrayVirt[MAX_SCSI_TAG];

    u_int8_t			mailBoxIndex;

    u_int32_t			initiatorID;

    u_int8_t			istatReg;
    u_int8_t			dstatReg;
    u_int16_t			sistReg;

    u_int32_t			scriptRestartAddr;

    NXLock			*srbPendingQLock;
    queue_head_t		srbPendingQ;

    NXConditionLock		*srbPoolGrowLock;
    u_int32_t			srbPoolGrow;

    NXLock			*srbPoolLock;
    queue_head_t		srbPool;
    u_int32_t			srbSeqNum;
    u_int32_t			resetSeqNum;
    
    NXLock			*resetQuiesceSem;
    u_int32_t			resetQuiesceTimer;

    NXLock			*cmdQTagSem;
    NXLock                      *abortBdrSem;

@public
    u_int8_t			interrupt;
@protected
    port_t			interruptPortKern;

    SRB				*resetSRB;
    SRB				*abortSRB;
    u_int32_t			abortSRBTimeout;
    SRB				*abortCurrentSRB;
    u_int32_t			abortCurrentSRBTimeout;

    u_int32_t			chipType;
    u_int32_t			chipClockRate;
    u_int16_t			DeviceID;

    volatile u_int8_t		*chipBaseAddr;
    u_int8_t			*chipBaseAddrPhys;
    
    volatile u_int8_t		*chipRamAddr;
    u_int8_t			*chipRamAddrPhys;

    u_int16_t			Flags;
    u_int16_t			MaxSyncOffset;
    u_int16_t			MinSyncPeriod;
    u_int16_t			MinSEPeriod;
    u_int8_t			Scntl3Reset;
}
@end

@interface AttoScsiController(Init)
+ (BOOL)  	probe:(IOPCIDevice *)deviceDescription;
+ 		initialize;
- (void)	registerHandlerForIRQ:(int)irq;
- 		initFromDeviceDescription:(IOPCIDevice *) deviceDescription;
- (BOOL)  	AttoScsiInit:(IOPCIDevice *)deviceDescription;
- (BOOL)  	AttoScsiInitPCI:(IOPCIDevice *)deviceDescription;
- (BOOL)  	AttoScsiInitVars;
- (BOOL)  	AttoScsiInitScript;
- (void)  	AttoScsiLoadScript:(u_int32_t *)scriptPgm count:(u_int32_t)scriptWords;
- (BOOL)  	AttoScsiInitChip;

@end

@interface AttoScsiController(Client)
- (sc_status_t) executeRequest:(IOSCSIRequest *)scsiReq  buffer:(void *)buffer  client:(vm_task_t)client;
- (sc_status_t) executeRequest:(IOSCSIRequest *)scsiReq  ioMemoryDescriptor: (IOMemoryDescriptor *) ioMemoryDescriptor;
- (sc_status_t) resetSCSIBus;
- (void)	getDMAAlignment:(IODMAAlignment *)alignment;
- (int) 	numberOfTargets;
- (void) 	AttoScsiCalcMsgs: (SRB *)srb;
- (void) 	AttoScsiSendCommand: (SRB *) srb;
- (u_int32_t) 	AttoScsiAllocTag:(SRB *)srb CmdQueue:(BOOL)fCmdQueue;
- (void) 	AttoScsiFreeTag:(SRB *)srb;
- (SRB *) 	AttoScsiAllocSRB;
- (void) 	AttoScsiFreeSRB:(SRB *)srb;
- (void)  	AttoScsiGrowSRBPool;
- (BOOL) 	AttoScsiUpdateSGList:(SRB *)srb;
- (BOOL) 	AttoScsiUpdateSGListVirt: (SRB *) srb;
- (BOOL) 	AttoScsiUpdateSGListDesc: (SRB *) srb;


IOThreadFunc 	AttoScsiTimerReq( AttoScsiController *device );
IOThreadFunc	AttoScsiGrowSRBPool( AttoScsiController *controller );

@end

@interface AttoScsiController(Execute)
- (void) 	commandRequestOccurred;
- (void) 	AttoScsiSignalScript:(SRB *)srb;
- (int)		checkForPendingInterrupt;
- (void) 	interruptOccurred;
- (void)        timeoutOccurred;
- (void) 	AttoScsiProcessIODone;
- (void) 	AttoScsiProcessInterrupt;
- (BOOL) 	AttoScsiProcessStatus:(SRB *)srb;
- (void) 	AttoScsiIssueRequestSense:(SRB *) srb;
- (void) 	AttoScsiAdjustDataPtrs:(SRB *) srb Nexus:(Nexus *) nexus;
- (u_int32_t) 	AttoScsiCheckFifo:(SRB *)srb FifoCnt:(u_int32_t *)pfifoCnt;
- (void) 	AttoScsiUpdateXferOffset:(SRB *) srb;
- (void)        AttoScsiProcessNoNexus;
- (void) 	AttoScsiAbortCurrent:(SRB *)srb;
- (void)	AttoScsiClearFifo;
- (void) 	AttoScsiNegotiateSDTR:(SRB *) srb Nexus:(Nexus *)nexus;
- (void) 	AttoScsiNegotiateWDTR:(SRB *) srb Nexus:(Nexus *)nexus;
- (void) 	AttoScsiSendMsgReject:(SRB *) srb;
- (void) 	AttoScsiCheckInquiryData: (SRB *)srb;
- (void) 	AttoScsiSCSIBusReset:(SRB *)srb;
- (void) 	AttoScsiProcessSCSIBusReset;
- (void) 	AttoScsiAbortBdr: (SRB *) srb;
- (void) 	AttoScsiAbortScript;



@end

u_int32_t AttoScsiReadRegs( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize );
void      AttoScsiWriteRegs( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t regValue );
void      AttoScsiClearRegBits( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t regBits );
void      AttoScsiModRegBits( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t regMask, u_int32_t regBits );

/*
 * Synchronous transfer table entry: the first entry whose period is at
 * least the target's SDTR period gives the scntl3 and sxfer settings.
 */
typedef struct PeriodEntry
{
    u_int8_t		period;
    u_int8_t		scntl3Reg;
    u_int8_t		sxferReg;
} PeriodEntry;

PeriodEntry *GetPeriodEntry( u_int8_t period, u_int16_t flags );

extern kern_return_t	kmem_alloc_wired();
extern kern_return_t	kmem_free();
extern kern_return_t 	msg_send_from_kernel(msg_header_t *,int,int);
//extern void 		call_kdp();

extern u_int32_t	page_size;

#if 0
extern u_int32_t	gRegs875, gRegs875Phys, gRam875, gRam875Phys;
#endif


static __inline__ u_int16_t EndianSwap16(volatile u_int16_t y)
{
    u_int16_t	 	result;
    volatile u_int16_t  x;

    x = y;   
    __asm__ volatile("lhbrx %0, 0, %1" : "=r" (result) : "r" (&x) : "r0");
    return result;
}

static __inline__ u_int32_t EndianSwap32(u_int32_t y)
{
    u_int32_t		 result;
    volatile u_int32_t   x;

    x = y;
    __asm__ volatile("lwbrx %0, 0, %1" : "=r" (result) : "r" (&x) : "r0");
    return result;
}

#ifndef eieio
#define eieio() \
        __asm__ volatile("eieio")
#endif
