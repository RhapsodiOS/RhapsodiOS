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

#ifndef _ADAPTECU2_SCSI_H_
#define _ADAPTECU2_SCSI_H_

#import <driverkit/IOSCSIController.h>
#import <driverkit/scsiTypes.h>
#import <mach/mach_interface.h>
#include "AdaptecU2CHIM.h"

@class NXLock;
@class IOMemoryDescriptor;
typedef struct AdaptecU2AttachedTarget AdaptecU2AttachedTarget;

/* The one-argument executeRequest: selector accepts this command envelope,
 * not IOSCSIRequest. The other two selectors accept IOSCSIRequest. */
typedef struct AdaptecU2Command {
    int operation;
    unsigned long cdbLength;
    unsigned long word08;
    unsigned long word0c;
    IOSCSIRequest *request;
    id completionLock;
    int result;
    void *buffer;
    vm_task_t client;
    queue_chain_t link;
} AdaptecU2Command;

@interface AdaptecU2SCSI : IOSCSIController
{
@public
    /* These three handle ivars are ^v in the reference metadata. */
    void *initializationTSH;
    unsigned int productID;
    AdaptecU2PciLocation pciLocation;
    AdaptecU2Configuration configuration;
    void *pTscb;
    unsigned int tscbSize;
    void *adapterTSH;
    AdaptecU2AdapterProfile profile;
    unsigned int iobReserveSize;
    AdaptecU2AttachedTarget *pAttachedTarget[16];
    int autoConfigActive;
    int frozen;
    int resetActive;
    AdaptecU2HIMFunctions HIMFunc;
    int numIOBs;
    int numActiveIOBs;
    int targetProbeCount;
    queue_head_t iobQ;
    queue_head_t handleQ;
    queue_head_t commandQ;
    unsigned int maxQueueLen;
    unsigned int queueLenTotal;
    unsigned int outstandingCount;
    unsigned int interrupt;
    NXLock *commandLock;
    int interruptPortKern;
    char threadStarted;
    char initTime;
    id (*NXConditionLock_initWith)(id, SEL, int);
    id (*NXConditionLock_free)(id, SEL);
    id (*NXConditionLock_lock)(id, SEL);
    id (*NXConditionLock_lockWhen)(id, SEL, int);
    id (*NXConditionLock_unlockWith)(id, SEL, int);
    id (*NXLock_lock)(id, SEL);
    id (*NXLock_unlock)(id, SEL);
}

+ initialize;
+ (BOOL)probe:deviceDescription;
- initFromDeviceDescription:deviceDescription;
- free;
- (void)registerHandlerForIRQ:(int)irq;
- (BOOL)getWorkingMemoryForCHIM;
- (BOOL)findAdapter;
- (BOOL)initAdapter;
- (BOOL)allocateAdapterMemory;
- (void)createOSMIOBPool;
- (BOOL)scanAdapter;
- (sc_status_t)executeRequest:(AdaptecU2Command *)command;
- (sc_status_t)executeRequest:(IOSCSIRequest *)request
                       buffer:(void *)buffer client:(vm_task_t)client;
- (sc_status_t)executeRequest:(IOSCSIRequest *)request
           ioMemoryDescriptor:(IOMemoryDescriptor *)descriptor;
- (sc_status_t)resetSCSIBus;
- (int)numberOfTargets;
- (unsigned int)maxTransfer;
- (unsigned int)numQueueSamples;
- (unsigned int)sumQueueLengths;
- (unsigned int)maxQueueLength;
- (void)resetStats;
@end

@interface AdaptecU2SCSI (AdaptecU2SCSIThread)
- (void)timeoutOccurred;
- (void)threadResetSCSIBus:(AdaptecU2Command *)command;
- (void)threadExecuteRequest:(AdaptecU2Command *)command;
- (void)commandRequestOccurred;
@end

#endif
