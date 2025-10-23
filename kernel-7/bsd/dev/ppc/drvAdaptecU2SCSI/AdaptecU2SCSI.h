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
 * AdaptecU2SCSI.h - Adaptec Ultra2 SCSI Controller Driver
 * Header file with instance variable structure matching binary layout
 */

#import <driverkit/IOSCSIController.h>
#import <driverkit/scsiTypes.h>
#import <mach/mach_interface.h>

@interface AdaptecU2SCSI : IOSCSIController
{
    @public
    // Offset 0x244 - Pointer to stack buffer (points to local stack in methods)
    unsigned char *stackBuffer;

    // Offset 0x248 - PCI device/vendor ID
    unsigned int pciDeviceID;
    
    // Offset 0x24c - Padding to align to 0x25c
    unsigned char padding1[16];
    
    // Offset 0x25c - Configuration buffer
    unsigned int configBuffer[64];
    
    // Offset 0x2a0 - Working memory pointer
    void *workingMemory;
    
    // Offset 0x2a4 - Working memory size
    unsigned int workingMemorySize;
    
    // Offset 0x2a8 - HIM adapter handle
    void *himHandle;
    
    // Offset 0x2ac - Profile/parameter buffer (used for OSMIO params)
    void *profileBuffer[32];
    
    // Offset 0x320 (800 decimal) - Number of targets
    unsigned int numTargets;
    
    // Offset 0x324 - Padding
    unsigned char padding2[16];
    
    // Offset 0x334 - Copy source pointer
    void *copySource;

    // Offset 0x338 - Padding to 0x3b0
    unsigned char padding3a[120];

    // Offset 0x3b0 - Adapter's own SCSI ID
    unsigned int adapterSCSIID;

    // Offset 0x3b4 - Padding to 0x3bc
    unsigned char padding3b[8];

    // Offset 0x3bc - Profile flags
    unsigned char profileFlags[128];
    
    // Offset 0x43c - Padding to 0x47c
    unsigned char padding4[64];
    
    // Offset 0x47c - Copy destination pointer
    void *copyDest;
    
    // Offset 0x480 - Target structures array (one per target)
    void *targetStructures[16];
    
    // Offset 0x4c0 - Reserved
    unsigned int reserved1;
    
    // Offset 0x4c4 - Reserved
    unsigned int reserved2;
    
    // Offset 0x4c8 - Reserved
    unsigned int reserved3;
    
    // Offset 0x4cc - CHIM function table (0xa8 bytes = 42 function pointers)
    void *chimFunctionTable[42];
    
    // Offset 0x574 - Free IOB pool count
    unsigned int freeIOBCount;
    
    // Offset 0x578 - CHIM working memory / num samples
    void *chimWorkingMemory;
    
    // Offset 0x57c - Padding
    unsigned int padding5;
    
    // Offset 0x580 - Incoming queue (also reused as free IOB queue head/tail)
    queue_head_t incomingQueue;
    
    // Offset 0x588 - Pending queue  
    queue_head_t pendingQueue;
    
    // Offset 0x590 - Disconnected queue
    queue_head_t disconnectedQueue;
    
    // Offset 0x598 - Max queue length statistic
    unsigned int maxQueueLen;
    
    // Offset 0x59c - Sum of queue lengths statistic
    unsigned int sumQueueLengths;
    
    // Offset 0x5a0 - Active command pointer
    void *activeCommand;
    
    // Offset 0x5a4 - Adapter IRQ number
    int adapterIRQ;
    
    // Offset 0x5a8 - Incoming queue lock (NXLock)
    id incomingQueueLock;
    
    // Offset 0x5ac - Kernel interrupt port
    port_t kernelInterruptPort;
    
    // Offset 0x5b0 - I/O thread running flag
    unsigned char ioThreadRunning;
    
    // Offset 0x5b1 - Initialization complete flag
    unsigned char initComplete;
    
    // Offset 0x5b2 - Padding
    unsigned char padding6[2];
    
    // Offset 0x5b4 - Condition lock method: initWith:
    void *condLockInitWith;
    
    // Offset 0x5b8 - Condition lock method: free
    void *condLockFree;
    
    // Offset 0x5bc - Condition lock method: lock
    void *condLockLock;
    
    // Offset 0x5c0 - Condition lock method: lockWhen:
    void *condLockLockWhen;
    
    // Offset 0x5c4 - Condition lock method: unlockWith:
    void *condLockUnlockWith;
    
    // Offset 0x5c8 - Lock method pointer
    void *lockMethod;
    
    // Offset 0x5cc - Unlock method pointer
    void *unlockMethod;
}

// Initialization
- initFromDeviceDescription : deviceDescription;
- free;

// Adapter discovery and setup
- (BOOL)findAdapter;
- (BOOL)initAdapter;
- (BOOL)scanAdapter;
- (BOOL)allocateAdapterMemory;
- (BOOL)createOSMIOBPool;
- (BOOL)getWorkingMemoryForCHIM;
- (BOOL)registerHandlerForIRQ:(unsigned int)irq;

// SCSI command execution
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq;
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
                       buffer:(void *)buffer
                       client:(vm_task_t)client;
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
           ioMemoryDescriptor:(IOMemoryDescriptor *)ioMemoryDescriptor;

// Bus management
- (sc_status_t)resetSCSIBus;

// Configuration queries
- (int)numberOfTargets;
- (unsigned int)maxTransfer;

// Statistics
- (unsigned int)numQueueSamples;
- (unsigned int)sumQueueLengths;
- (unsigned int)maxQueueLength;
- (void)resetStats;

@end
