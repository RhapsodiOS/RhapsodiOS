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

#import "AdaptecU2SCSIPrivate.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/ppc/IOPCIDevice.h>
#import <kernserv/prototypes.h>
#import <mach/mach_interface.h>
#import <mach/mach_traps.h>
#import <mach/vm_param.h>
#import <machdep/ppc/interrupts.h>
#import <machdep/ppc/machspl.h>
#import <machkit/NXLock.h>
#import <string.h>

extern kern_return_t msg_send_from_kernel(msg_header_t *, int, int);

static msg_header_t request_message = {
    0, 1, sizeof(msg_header_t), MSG_TYPE_NORMAL, PORT_NULL, PORT_NULL,
    IO_COMMAND_MSG
};
/* Initialized so that, as in the reference, it is placed in __data. */
queue_head_t adapterQ[64] = { { 0 } };

@implementation AdaptecU2SCSI

+ initialize
{
    int i;

    for (i = 0; i < 64; i++)
        queue_init(&adapterQ[i]);
    return self;
}

+ (BOOL)probe:deviceDescription
{
    UInt32 command;

    if ([deviceDescription numInterrupts] != 1)
        return NO;
    [deviceDescription configReadLong:4 value:&command];
    [deviceDescription configWriteLong:4 value:command | 3];
    return [[self alloc] initFromDeviceDescription:deviceDescription] != nil;
}

- (void)registerHandlerForIRQ:(int)irq
{
    AdaptecU2AdapterQueueEntry *entry;

    interrupt = irq;
    if (queue_empty(&adapterQ[irq]))
        (*pmac_register_int)((*pmac_int_to_number)(irq), SPLBIO,
                             AU2Handler, self);
    for (entry = (AdaptecU2AdapterQueueEntry *)queue_first(&adapterQ[interrupt]);
         !queue_end(&adapterQ[interrupt], (queue_entry_t)entry);
         entry = (AdaptecU2AdapterQueueEntry *)queue_next(&entry->link))
        if (entry->controller == self)
            return;
    entry = IOMalloc(sizeof(*entry));
    entry->controller = self;
    queue_enter(&adapterQ[interrupt], entry, AdaptecU2AdapterQueueEntry *, link);
}

- initFromDeviceDescription:deviceDescription
{
    unsigned char initializationMemory[1000];
    id conditionLock;
    kern_return_t result;

    initializationTSH = initializationMemory;
    threadStarted = NO;
    initTime = YES;
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        IOLog("AdaptecU2SCSI: super initFromDeviceDescription failed.\n");
        return [super free];
    }
    numActiveIOBs = 0;
    autoConfigActive = 0;
    resetActive = 0;
    frozen = 0;
    threadStarted = YES;
    [self resetStats];
    outstandingCount = 0;
    queue_init(&iobQ);
    queue_init(&handleQ);
    queue_init(&commandQ);
    bzero(pAttachedTarget, sizeof(pAttachedTarget));

    commandLock = [[NXLock alloc] init];
    NXLock_lock = (id (*)(id, SEL))[commandLock methodFor:@selector(lock)];
    NXLock_unlock = (id (*)(id, SEL))[commandLock methodFor:@selector(unlock)];
    conditionLock = [[NXConditionLock alloc] init];
    NXConditionLock_initWith =
        (id (*)(id, SEL, int))[conditionLock methodFor:@selector(initWith:)];
    NXConditionLock_free = (id (*)(id, SEL))[conditionLock methodFor:@selector(free)];
    NXConditionLock_lock = (id (*)(id, SEL))[conditionLock methodFor:@selector(lock)];
    NXConditionLock_lockWhen =
        (id (*)(id, SEL, int))[conditionLock methodFor:@selector(lockWhen:)];
    NXConditionLock_unlockWith =
        (id (*)(id, SEL, int))[conditionLock methodFor:@selector(unlockWith:)];
    [conditionLock free];

    interruptPortKern = (int)IOConvertPort([self interruptPort],
                                           IO_KernelIOTask, IO_Kernel);
    result = port_set_backlog((task_t)task_self(), [self interruptPort], 16);
    if (result)
        IOLog("%s: error %d on port_set_backlog()\n", [self name], result);

    SCSIGetFunctionPointers(&HIMFunc, sizeof(HIMFunc));
    if ([self getWorkingMemoryForCHIM] && [self findAdapter]) {
        IOLog("AdaptecU2SCSI: Adaptec SCSI Adapter found.\n");
        [self registerHandlerForIRQ:[deviceDescription interrupt]];
        if ([self initAdapter] && [self scanAdapter]) {
            [self registerDevice];
            initTime = NO;
            return self;
        }
    }
    return [self free];
}

- (BOOL)getWorkingMemoryForCHIM
{
    bzero(initializationTSH, 1000);
    initializationTSH = HIMFunc.HIMCreateInitializationTSCB(initializationTSH);
    return initializationTSH != 0;
}

- (BOOL)findAdapter
{
    int index;
    unsigned int type, busType, mask;

    if ([[self deviceDescription] configReadLong:0 value:(UInt32 *)&productID]) {
        IOLog("AdaptecU2SCSI: Cannot get PCI config space. Aborting.\n");
        return NO;
    }
    for (index = 0; ; index++) {
        type = HIMFunc.HIMGetNextHostDeviceType(index, &busType, &mask);
        if (type == 0)
            return NO;
        if (index > 3000)
            return NO;
        if ((productID & mask) == type && busType == 0)
            break;
    }
    return YES;
}

- (BOOL)initAdapter
{
    id deviceDescription = [self deviceDescription];
    AdaptecU2PciLocation location;

    HIMFunc.HIMGetConfiguration(initializationTSH, &configuration, productID);
    if (configuration.maxInternalIOBlocks > 32)
        configuration.maxInternalIOBlocks = 32;
    if (configuration.memoryMapped != 2)
        configuration.memoryMapped = 1;
    if (configuration.maxSGDescriptors > 512)
        configuration.maxSGDescriptors = 512;
    HIMFunc.HIMSetConfiguration(initializationTSH, &configuration, productID);
    tscbSize = HIMFunc.HIMSizeAdapterTSCB(initializationTSH, productID);
    pTscb = IOMalloc(tscbSize);
    bzero(pTscb, tscbSize);
    location.words[0] = 0;
    location.words[1] = ((IOPCIDevice *)deviceDescription)->busNum;
    location.words[2] = ((IOPCIDevice *)deviceDescription)->deviceNum;
    location.words[3] = ((IOPCIDevice *)deviceDescription)->functionNum;
    adapterTSH = HIMFunc.HIMCreateAdapterTSCB(initializationTSH, pTscb,
                                              (AdaptecU2OSMContext)self,
                                              location, productID);
    HIMFunc.HIMSetupAdapterTSCB(adapterTSH, &OSMRoutines, sizeof(OSMRoutines));
    switch (HIMFunc.HIMVerifyAdapter(adapterTSH)) {
    case 0:
        IOLog("AdaptecU2SCSI: Adapter verified by HIM.\n");
        break;
    case 1:
        IOLog("AdaptecU2SCSI: HIM Failure when verifying adapter.\n");
        return NO;
    default:
        IOLog("AdaptecU2SCSI: Adapter not supported.\n");
        return NO;
    }
    if (![self allocateAdapterMemory]) {
        IOLog("AdaptecU2SCSI: Cannot allocate adapter memory.\n");
        return NO;
    }
    HIMFunc.HIMProfileAdapter(adapterTSH, &profile);
    memset(&profile.himu.bytes[28], 1, 128);
    switch (HIMFunc.HIMAdjustAdapterProfile(adapterTSH, &profile)) {
    case 0:
        break;
    case 7:
        IOLog("AdaptecU2SCSI: Illegal change made to adapter profile.\n");
        return NO;
    case 2:
        IOLog("AdaptecU2SCSI: Adapter not idle when modifying profile.\n");
        return NO;
    default:
        IOLog("AdaptecU2SCSI: Failed to modifiy adapter profile.\n");
        return NO;
    }
    iobReserveSize = profile.AP_IOBReserveSize;
    HIMFunc.HIMDisableIRQ(adapterTSH);
    if (HIMFunc.HIMInitialize(adapterTSH)) {
        IOLog("AdaptecU2SCSI: HIMInitialize failed.\n");
        return NO;
    }
    IOLog("AdaptecU2SCSI: Using IRQ: %d\n",
          (unsigned char)[deviceDescription interrupt]);
    [self createOSMIOBPool];
    HIMFunc.HIMEnableIRQ(adapterTSH);
    return YES;
}

- (BOOL)allocateAdapterMemory
{
    unsigned int index, size, category, minimumSize, granularity, alignmentMask;
    unsigned char *memory;

    for (index = 0; (size = HIMFunc.HIMCheckMemoryNeeded(initializationTSH,
             adapterTSH, productID, index, &category, &minimumSize,
             &granularity, &alignmentMask)); index++) {
        if (size + alignmentMask > page_size && category != 0) {
            size = minimumSize;
            if (size + alignmentMask > page_size) {
                IOLog("AdaptecU2SCSI: Cannot allocate locked memory.\n");
                return NO;
            }
        }
        if (category == 0)
            memory = IOMalloc(size + alignmentMask);
        else
            memory = AdptMallocContiguous(size + alignmentMask);
        if (memory == 0) {
            IOLog("AdaptecU2SCSI: Memory allocation failed.\n");
            return NO;
        }
        bzero(memory, size + alignmentMask);
        if (HIMFunc.HIMSetMemoryPointer(adapterTSH, index, category,
                (unsigned char *)(((unsigned int)memory + alignmentMask) & ~alignmentMask),
                size)) {
            IOLog("AdaptecU2SCSI: Could not set memory pointer.\n");
            return NO;
        }
    }
    return YES;
}

- (void)createOSMIOBPool
{
    int i;
    AdaptecU2OSMIOB *iob;

    numIOBs = 0;
    i = 0;
    while (i++ < 16) {
        iob = _allocOSMIOB(profile);
        queue_enter(&iobQ, iob, AdaptecU2OSMIOB *, link);
    }
}

- (BOOL)scanAdapter
{
    AdaptecU2Command reset, probe;
    IOSCSIRequest request;
    unsigned int target;

    reset.operation = 2;
    if ([self executeRequest:&reset])
        return NO;
    for (target = 0; target < profile.AP_MaxTargets; target++) {
        request.target = target;
        request.lun = 0;
        probe.operation = 1;
        probe.request = &request;
        if ([self executeRequest:&probe])
            return NO;
    }
    return reset.result == 0;
}

- (void)resetStats
{
    queueLenTotal = 0;
    maxQueueLen = 0;
}

- (unsigned int)sumQueueLengths
{
    return queueLenTotal;
}

- (unsigned int)maxQueueLength
{
    return maxQueueLen;
}

- (unsigned int)numQueueSamples
{
    return numActiveIOBs;
}

- (int)numberOfTargets
{
    return profile.AP_MaxTargets;
}

- (unsigned int)maxTransfer
{
    return 510 * page_size;
}

- (sc_status_t)executeRequest:(AdaptecU2Command *)command
{
    msg_header_t message = request_message;
    sc_status_t status = SR_IOST_GOOD;
    kern_return_t result;

    command->result = SR_IOST_INVALID;
    command->completionLock = NXConditionLock_initWith([NXConditionLock alloc],
                                                       @selector(initWith:), 0);
    NXLock_lock(commandLock, @selector(lock));
    queue_enter(&commandQ, command, AdaptecU2Command *, link);
    NXLock_unlock(commandLock, @selector(unlock));
    message.msg_remote_port = (port_t)interruptPortKern;
    result = msg_send_from_kernel(&message, MSG_OPTION_NONE, 0);
    if (result) {
        IOLog("%s: msg_send_from_kernel() returned %d\n", [self name], result);
        status = IO_R_IPC_FAILURE;
    } else
        NXConditionLock_lockWhen(command->completionLock, @selector(lockWhen:), 1);
    NXConditionLock_free(command->completionLock, @selector(free));
    return status;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)request
                       buffer:(void *)buffer client:(vm_task_t)client
{
    AdaptecU2Command command, probe;
    cdb_t *cdb = &request->cdb;
    unsigned int length;
    unsigned char control;

    if (request->lun) {
        command.result = SR_IOST_SELTO;
        goto done;
    }
    if (pAttachedTarget[request->target] == 0) {
        probe.operation = 1;
        probe.request = request;
        if ([self executeRequest:&probe] || probe.result) {
            command.result = SR_IOST_SELTO;
            goto done;
        }
    }
    switch (cdb->cdb_opcode & 0xe0) {
    case 0x00:
        length = 6;
        control = cdb->cdb_c6.c6_ctrl;
        break;
    case 0x20:
    case 0x40:
        length = 10;
        control = cdb->cdb_c10.c10_ctrl;
        break;
    case 0xa0:
        length = 12;
        control = cdb->cdb_c12.c12_ctrl;
        break;
    case 0xc0:
        length = request->cdbLength ? request->cdbLength : 6;
        control = 0;
        break;
    case 0xe0:
        length = request->cdbLength ? request->cdbLength : 10;
        control = 0;
        break;
    default:
        goto reject;
    }
    command.operation = 0;
    command.cdbLength = length;
    command.word08 = 0;
    command.word0c = 0;
    command.request = request;
    command.buffer = buffer;
    command.client = client;
    if ((control & 3) == 0 && [self executeRequest:&command] == 0)
        goto done;
reject:
    command.result = SR_IOST_CMDREJ;
done:
    request->driverStatus = command.result;
    return command.result;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)request
           ioMemoryDescriptor:(IOMemoryDescriptor *)descriptor
{
    return [self executeRequest:request buffer:descriptor client:(vm_task_t)-1];
}

- (sc_status_t)resetSCSIBus
{
    AdaptecU2Command command;
    sc_status_t status = SR_IOST_CMDREJ;

    command.operation = 2;
    if ([self executeRequest:&command] == 0)
        status = command.result;
    return status;
}

- free
{
    AdaptecU2IOHandle *handle, *next, *prev;
    AdaptecU2AttachedTarget *target;
    AdaptecU2AdapterQueueEntry *entry;
    AdaptecU2OSMIOB *iob;
    unsigned int i;

    while (!queue_empty(&handleQ)) {
        handle = (AdaptecU2IOHandle *)queue_first(&handleQ);
        next = handle->next;
        prev = handle->prev;
        if ((queue_entry_t)next == &handleQ)
            handleQ.prev = (queue_entry_t)prev;
        else
            next->prev = prev;
        if ((queue_entry_t)prev == &handleQ)
            handleQ.next = (queue_entry_t)next;
        else
            prev->next = next;
        IOFree(handle, sizeof(*handle));
    }
    for (i = 0; i < profile.AP_MaxTargets; i++) {
        target = pAttachedTarget[i];
        if (target) {
            CleanupWaitingQ(target);
            IOFree(target, sizeof(*target));
        }
    }
    while (!queue_empty(&iobQ)) {
        iob = (AdaptecU2OSMIOB *)queue_first(&iobQ);
        queue_remove(&iobQ, iob, AdaptecU2OSMIOB *, link);
        _freeOSMIOB(iob, profile);
    }
    for (entry = (AdaptecU2AdapterQueueEntry *)queue_first(&adapterQ[interrupt]);
         !queue_end(&adapterQ[interrupt], (queue_entry_t)entry);
         entry = (AdaptecU2AdapterQueueEntry *)queue_next(&entry->link))
        if (entry->controller == self) {
            queue_remove(&adapterQ[interrupt], entry,
                         AdaptecU2AdapterQueueEntry *, link);
            IOFree(entry, sizeof(*entry));
            break;
        }
    if (pTscb)
        IOFree(pTscb, tscbSize);
    if (commandLock)
        [commandLock free];
    return [super free];
}

@end
