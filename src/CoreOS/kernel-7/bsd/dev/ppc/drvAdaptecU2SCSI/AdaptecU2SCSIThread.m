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
#import <driverkit/IOMemoryDescriptor.h>
#import <machkit/NXLock.h>
#import <mach/vm_param.h>

/* Keeps the pointer in memory for the asm's "m" operand, as the reference does. */
static __inline__ void WriteSwap32(volatile unsigned int *address, unsigned int value)
{
    __asm__ volatile ("lwz r17,%1\n\tstwbrx %0,0,r17"
                      : : "r" (value), "m" (address) : "r17", "memory");
}

/* Bit view of AdaptecU2IOB.flags; the reference assigns these as bitfields. */
typedef struct {
    unsigned int autoSense:1;
    unsigned int inboundData:1;
    unsigned int outboundData:1;
    unsigned int bit3:1;
    unsigned int bit4:1;
    unsigned int bit5:1;
    unsigned int tagEnable:1;
    unsigned int bits7:25;
} AdaptecU2IOBFlags;
#define IOBFlags(osm) (*(AdaptecU2IOBFlags *)&(osm)->iob.flags)

static __inline__ int BuildBufferSGList(AdaptecU2Command *command,
                                         AdaptecU2OSMIOB *iob)
{
    unsigned int address = (unsigned int)command->buffer;
    unsigned int remaining = command->request->maxTransfer;
    unsigned int pages, count, length, total, physical;
    AdaptecU2SGElement *sg;

    pages = (round_page(address + remaining) - trunc_page(address)) / page_size;
    sg = iob->sgAllocation;
    total = 0;
    if (pages > 512) {
        IOLog("AdaptecU2SCSI: Max DMA Count Exceeded (max: %d, request: %d)\n",
              510 * page_size, command->request->maxTransfer);
        command->result = SR_IOST_DMA;
        return NO;
    }
    for (count = 0; count < pages; count++) {
        length = round_page(address + 1) - address;
        if (length >= remaining)
            length = remaining;
        if (IOPhysicalFromVirtual(command->client, address, &physical)) {
            IOLog("AdaptecU2SCSI: Cannot get physical address.\n");
            command->result = SR_IOST_MEMF;
            return NO;
        }
        WriteSwap32((unsigned int *)sg[count].address, physical);
        WriteSwap32((unsigned int *)sg[count].lengthAndLast, length);
        total += length;
        address += length;
        remaining -= length;
    }
    *(unsigned int *)sg[count - 1].lengthAndLast |= 0x80;
    iob->iob.data.virtualAddress = (unsigned char *)sg;
    iob->iob.transferLength = total;
    iob->iob.data.size = count * sizeof(*sg);
    if (IOPhysicalFromVirtual(IOVmTaskSelf(),
            (vm_address_t)iob->iob.data.virtualAddress, &physical)) {
        IOLog("AdaptecU2SCSI: Cannot get physical address.\n");
        command->result = SR_IOST_MEMF;
        return NO;
    }
    iob->iob.data.busAddress = physical;
    return YES;
}

static __inline__ int BuildDescriptorSGList(AdaptecU2Command *command,
                                             AdaptecU2OSMIOB *iob)
{
    unsigned int position = 0, actual, physical, length, total, remaining, count;
    id descriptor = (id)command->buffer;
    AdaptecU2SGElement *sg = iob->sgAllocation;
    PhysicalRange range;

    count = 0;
    remaining = command->request->maxTransfer;
    [descriptor setPosition:0];
    total = 0;
    while (remaining != 0 && count < 512) {
        [descriptor getPhysicalRanges:1 maxByteCount:0xffffff
            newPosition:&position actualRanges:&actual physicalRanges:&range];
        if (actual != 1)
            return NO;
        physical = (unsigned int)range.address;
        length = range.length;
        WriteSwap32((unsigned int *)sg[count].address, physical);
        WriteSwap32((unsigned int *)sg[count].lengthAndLast, length);
        total += length;
        remaining -= length;
        count++;
    }
    *(unsigned int *)sg[count - 1].lengthAndLast |= 0x80;
    iob->iob.data.virtualAddress = (unsigned char *)sg;
    iob->iob.transferLength = total;
    iob->iob.data.size = count * sizeof(*sg);
    if (IOPhysicalFromVirtual(IOVmTaskSelf(),
            (vm_address_t)iob->iob.data.virtualAddress, &physical)) {
        IOLog("AdaptecU2SCSI: Cannot get physical address.\n");
        command->result = SR_IOST_MEMF;
        return NO;
    }
    iob->iob.data.busAddress = physical;
    return YES;
}

@implementation AdaptecU2SCSI (AdaptecU2SCSIThread)

- (void)commandRequestOccurred
{
    AdaptecU2Command *command;

    NXLock_lock(commandLock, @selector(lock));
    while (!queue_empty(&commandQ)) {
        command = (AdaptecU2Command *)queue_first(&commandQ);
        queue_remove(&commandQ, command, AdaptecU2Command *, link);
        NXLock_unlock(commandLock, @selector(unlock));
        switch (command->operation) {
        case 2:
            [self threadResetSCSIBus:command];
            break;
        case 3:
            [command->completionLock lock];
            [command->completionLock unlockWith:1];
            IOExitThread();
        case 1:
            ProbeTarget(self, command);
            break;
        case 0:
            [self threadExecuteRequest:command];
            break;
        }
        NXLock_lock(commandLock, @selector(lock));
    }
    NXLock_unlock(commandLock, @selector(unlock));
}

- (void)threadExecuteRequest:(AdaptecU2Command *)command
{
    AdaptecU2OSMIOB *iob = AllocOSMIOB(self);
    IOSCSIRequest *request = command->request;
    AdaptecU2AttachedTarget *target;
    int ok = YES;

    if (request->maxTransfer > 0) {
        if (command->client != (vm_task_t)-1)
            ok = BuildBufferSGList(command, iob);
        else
            ok = BuildDescriptorSGList(command, iob);
    }
    if (ok) {
        target = pAttachedTarget[request->target];
        iob->iob.function = 0;
        IOBFlags(iob).autoSense = !request->ignoreChkcond;
        IOBFlags(iob).tagEnable = !request->cmdQueueDisable;
        IOBFlags(iob).inboundData = request->read;
        iob->iob.sense = (unsigned char *)&request->senseData;
        iob->iob.transportSpecific = 0;
        iob->iob.senseLength = sizeof(request->senseData);
        iob->iob.command = command;
        IOBFlags(iob).outboundData = request->read == 0;
        IOBFlags(iob).bit5 = 0;
        iob->iob.post = NormalPostRoutine;
        iob->iob.cdb = (unsigned char *)&request->cdb;
        iob->iob.taskSet.target = target->targetTSH;
        iob->iob.taskAttribute = 0;
        iob->iob.cdbLength = command->cdbLength;
        iob->owner.target = target;
        iob->interruptPort = interruptPortKern;
        if (++outstandingCount > maxQueueLen)
            maxQueueLen = outstandingCount;
        queueLenTotal += outstandingCount;
        IOGetTimestamp((ns_time_t *)iob->timestamp);
        EnqueueOsmIOB(iob, target);
    } else {
        FreeOSMIOB(self, iob);    /* Divergence: the reference leaked the IOB here. */
        NXConditionLock_lock(command->completionLock, @selector(lock));
        NXConditionLock_unlockWith(command->completionLock, @selector(unlockWith:), 1);
    }
}

- (void)threadResetSCSIBus:(AdaptecU2Command *)command
{
    ResetSCSIBus(self, command);
}

- (void)timeoutOccurred
{
    IOLog("AdaptecU2SCSI:  Timeout occurred.\n");
    ResetSCSIBus(self, 0);
}

@end
