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
#import <kern/thread_call.h>
#import <mach/vm_param.h>
#import <string.h>

static const IONamedValue event_names[] = {
    { 4, "OSM freeze event occured." },
    { 5, "OSM unfreeze event occured." },
    { 1, "IO channel reset event occured." },
    { 2, "Auto config required event occured." },
    { 3, "HA event failed." },
    { 6, "Nexus TSH threshold event occured." },
    { 7, "EC IOB threshold event occured." },
    { 0, NULL }
};

void OSMEvent(AdaptecU2OSMContext context, unsigned int event,
              unsigned int unusedWord, ...)
{
    AdaptecU2SCSI *controller = (AdaptecU2SCSI *)context;
    AdaptecU2OSMIOB *iob;
    unsigned int i;

    switch (event) {
    case 4:
        controller->frozen = 1;
        break;
    case 5:
        controller->frozen = 0;
        for (i = 0; i < controller->profile.AP_MaxTargets; i++)
            if (controller->pAttachedTarget[i])
                SendIOBsMaybe(controller->pAttachedTarget[i]);
        break;
    case 1:
    case 2:
        iob = AllocOSMIOB(controller);
        iob->owner.controller = controller;
        iob->iob.function = 6;
        iob->iob.command = 0;
        iob->iob.post = PostRoutineEventPAC;
        iob->iob.taskSet.adapter = controller->adapterTSH;
        controller->autoConfigActive = 1;
        controller->numActiveIOBs++;
        controller->HIMFunc.HIMQueueIOB(&iob->iob);
        break;
    case 3:
        iob = AllocOSMIOB(controller);
        iob->owner.controller = controller;
        iob->iob.function = 5;
        iob->iob.command = 0;
        iob->iob.post = PostRoutineEventResetHW;
        iob->iob.taskSet.adapter = controller->adapterTSH;
        controller->resetActive = 1;
        controller->numActiveIOBs++;
        controller->HIMFunc.HIMQueueIOB(&iob->iob);
        break;
    case 6:
    case 7:
    default:
        IOLog("AdaptecU2SCSI: OSMEvent: %s\n",
              IOFindNameForValue(event, event_names));
        break;
    }
}

void SendIOBsMaybe(AdaptecU2AttachedTarget *target)
{
    AdaptecU2SCSI *controller = target->controller;
    AdaptecU2OSMIOB *iob;

    while (!queue_empty(&target->waiting) && controller->frozen != 1 &&
           controller->autoConfigActive != 1 && controller->resetActive != 1) {
        iob = (AdaptecU2OSMIOB *)queue_first(&target->waiting);
        queue_remove(&target->waiting, iob, AdaptecU2OSMIOB *, link);
        if (iob->iob.command->request->timeoutLength)
            IOScheduleFunc(AdaptecU2SCSITimeout, iob,
                           iob->iob.command->request->timeoutLength);
        controller->numActiveIOBs++;
        controller->HIMFunc.HIMQueueIOB(&iob->iob);
        queue_enter(&target->active, iob, AdaptecU2OSMIOB *, link);
    }
}

void EnqueueOsmIOB(AdaptecU2OSMIOB *iob, AdaptecU2AttachedTarget *target)
{
    queue_enter(&target->waiting, iob, AdaptecU2OSMIOB *, link);
    SendIOBsMaybe(target);
}

void HandleHIMFrozen(AdaptecU2OSMIOB *iob)
{
    AdaptecU2AttachedTarget *target = iob->owner.target;
    AdaptecU2OSMIOB *unfreeze = AllocOSMIOB(target->controller);

    unfreeze->owner.target = target;
    unfreeze->iob.function = 11;
    unfreeze->iob.post = PostUnfreezeHIMQueue;
    unfreeze->iob.taskSet = iob->iob.taskSet;
    queue_enter(&target->waiting, unfreeze, AdaptecU2OSMIOB *, link);
    SendIOBsMaybe(target);
}

unsigned int PostUnfreezeHIMQueue(AdaptecU2IOB *iob)
{
    AdaptecU2OSMIOB *osm = (AdaptecU2OSMIOB *)iob;
    AdaptecU2AttachedTarget *target = osm->owner.target;
    AdaptecU2SCSI *controller = target->controller;

    controller->numActiveIOBs--;
    queue_remove(&target->active, osm, AdaptecU2OSMIOB *, link);
    if (iob->status == 1)
        FreeOSMIOB(controller, osm);
    else
        IOPanic("AdaptecU2SCSI; Cannot unfreeze target queue.\n");
    return 0;
}

void ResetSCSIBus(AdaptecU2SCSI *controller, AdaptecU2Command *command)
{
    AdaptecU2OSMIOB *iob;

    IOLog("AdaptecU2SCSI: Resetting SCSI bus.\n");
    iob = AllocOSMIOB(controller);
    iob->owner.controller = controller;
    iob->iob.function = 4;
    iob->iob.post = PostRoutineResetHW;
    iob->iob.command = command;
    iob->iob.taskSet.adapter = controller->adapterTSH;
    controller->resetActive = 1;
    controller->numActiveIOBs++;
    controller->HIMFunc.HIMQueueIOB(&iob->iob);
}

unsigned int NormalPostRoutine(AdaptecU2IOB *iob)
{
    AdaptecU2OSMIOB *osm = (AdaptecU2OSMIOB *)iob;
    AdaptecU2AttachedTarget *target = osm->owner.target;
    AdaptecU2SCSI *controller = target->controller, *owner;
    AdaptecU2Command *command;
    sc_status_t status = SR_IOST_INT;
    unsigned char scsiStatus = 0;
    int reset = 0;
    ns_time_t now;

    controller->numActiveIOBs--;
    controller->outstandingCount--;
    queue_remove(&target->active, osm, AdaptecU2OSMIOB *, link);
    switch (iob->status) {
    case 1:
        status = SR_IOST_GOOD;
        scsiStatus = 0;
        break;
    case 3:
        status = SR_IOST_CHKSNV;
        scsiStatus = 2;
        break;
    case 2:
        status = SR_IOST_CHKSV;
        scsiStatus = 2;
        break;
    case 16:
    case 17:
        status = SR_IOST_INT;
        break;
    case 35:
        status = SR_IOST_PARITY;
        if (osm->retryCount) {
            osm->retryCount--;
            /* Divergence: the reference went on to complete and free the IOB
             * it had just requeued; keep it outstanding and stop here. */
            IOUnscheduleFunc(AdaptecU2SCSITimeout, osm);
            controller->outstandingCount++;
            queue_enter(&target->waiting, osm, AdaptecU2OSMIOB *, link);
            SendIOBsMaybe(target);
            return 0;
        }
        break;
    case 70:
        status = SR_IOST_BV;
        break;
    case 36:
        scsiStatus = 0;
        status = iob->residualLength ? SR_IOST_GOOD : SR_IOST_DMAOR;
        break;
    case 32:
        status = SR_IOST_SELTO;
        break;
    case 34:
    case 64:
    case 65:
    case 66:
    case 67:
    case 68:
    case 69:
        status = SR_IOST_TABT;
        break;
    case 48:
        scsiStatus = 8;
        HandleHIMFrozen(osm);
        break;
    case 49:
        scsiStatus = 0x28;
        HandleHIMFrozen(osm);
        break;
    case 80:
        status = SR_IOST_HW;
        reset = 1;
        break;
    default:
        status = SR_IOST_INT;
        reset = 1;
        break;
    }
    owner = osm->owner.target->controller;
    IOGetTimestamp(&now);
    command = iob->command;
    command->result = status;
    command->request->driverStatus = status;
    command->request->scsiStatus = scsiStatus;
    command->request->totalTime = now - *(ns_time_t *)osm->timestamp;
    command->request->bytesTransferred = iob->transferLength - iob->residualLength;
    IOUnscheduleFunc(AdaptecU2SCSITimeout, osm);
    FreeOSMIOB(owner, osm);
    owner->NXConditionLock_lock(command->completionLock, @selector(lock));
    owner->NXConditionLock_unlockWith(command->completionLock,
                                      @selector(unlockWith:), 1);
    if (reset == 1)
        ResetSCSIBus(controller, 0);
    return 0;
}

unsigned int ProbeTarget(AdaptecU2SCSI *controller, AdaptecU2Command *command)
{
    unsigned char target = command->request->target;
    AdaptecU2OSMIOB *iob;
    AdaptecU2TransportSpecific *transport;

    if (controller->profile.himu.words[4] != target) {
        iob = AllocOSMIOB(controller);
        iob->owner.controller = controller;
        iob->iob.function = 19;
        iob->iob.post = PostProbe;
        /* Divergence: the reference used the IOB's pointer as found, but
         * -threadExecuteRequest: clears it, so a recycled IOB wrote through NULL. */
        transport = iob->iob.transportSpecific = &iob->transport;
        iob->iob.cdb = 0;
        iob->iob.cdbLength = 0;
        iob->iob.command = command;
        iob->iob.taskSet.adapter = controller->adapterTSH;
        transport->target = target;
        transport->lun = 0;
        controller->numActiveIOBs++;
        controller->HIMFunc.HIMQueueIOB(&iob->iob);
    } else {
        command->result = SR_IOST_SELTO;
        controller->NXConditionLock_lock(command->completionLock, @selector(lock));
        controller->NXConditionLock_unlockWith(command->completionLock,
                                               @selector(unlockWith:), 1);
    }
    return 0;
}

unsigned int PostProtocolAutoConfig(AdaptecU2IOB *iob)
{
    AdaptecU2OSMIOB *osm = (AdaptecU2OSMIOB *)iob;
    AdaptecU2Command *command = iob->command;
    AdaptecU2SCSI *controller = osm->owner.controller;
    unsigned int i;

    if (iob->status == 1)
        ValidateTargets(osm);
    controller->numActiveIOBs--;
    FreeOSMIOB(controller, osm);
    controller->autoConfigActive = 0;
    if (command) {
        if (iob->status == 1)
            command->result = SR_IOST_GOOD;
        else
            command->result = SR_IOST_INVALID;
        controller->NXConditionLock_lock(command->completionLock, @selector(lock));
        controller->NXConditionLock_unlockWith(command->completionLock,
                                               @selector(unlockWith:), 1);
    }
    for (i = 0; i < controller->profile.AP_MaxTargets; i++)
        if (controller->pAttachedTarget[i])
            SendIOBsMaybe(controller->pAttachedTarget[i]);
    return 0;
}

void ValidateTargets(AdaptecU2OSMIOB *iob)
{
    AdaptecU2SCSI *controller = iob->owner.controller;
    AdaptecU2AttachedTarget *target;
    unsigned int i;

    for (i = 0; i < controller->profile.AP_MaxTargets; i++) {
        target = controller->pAttachedTarget[i];
        if (target &&
            controller->HIMFunc.HIMValidateTargetTSH(target->targetTSH) == 2) {
            CleanupWaitingQ(target);
            IOFree(target->storage, target->size);
            IOFree(target, sizeof(*target));
            controller->pAttachedTarget[i] = 0;
        }
    }
}

unsigned int PostRoutineResetHW(AdaptecU2IOB *iob)
{
    AdaptecU2OSMIOB *osm = (AdaptecU2OSMIOB *)iob;
    AdaptecU2SCSI *controller = osm->owner.controller;
    AdaptecU2Command *command = iob->command;
    AdaptecU2OSMIOB *autoConfig = AllocOSMIOB(controller);

    autoConfig->owner.controller = controller;
    autoConfig->iob.function = 6;
    autoConfig->iob.post = PostProtocolAutoConfig;
    autoConfig->iob.command = command;
    autoConfig->iob.taskSet.adapter = controller->adapterTSH;
    controller->resetActive = 0;
    controller->autoConfigActive = 1;
    controller->numActiveIOBs--;
    FreeOSMIOB(controller, osm);
    controller->numActiveIOBs++;
    controller->HIMFunc.HIMQueueIOB(&autoConfig->iob);
    return 0;
}

unsigned int PostRoutineEventResetHW(AdaptecU2IOB *iob)
{
    AdaptecU2OSMIOB *osm = (AdaptecU2OSMIOB *)iob, *autoConfig;
    AdaptecU2SCSI *controller = osm->owner.controller;

    controller->resetActive = 0;
    if (iob->status == 1) {
        controller->numActiveIOBs--;
        FreeOSMIOB(controller, osm);
        autoConfig = AllocOSMIOB(controller);
        autoConfig->owner.controller = controller;
        autoConfig->iob.function = 6;
        autoConfig->iob.post = PostRoutineEventPAC;
        autoConfig->iob.command = 0;
        autoConfig->iob.taskSet = iob->taskSet;
        controller->autoConfigActive = 1;
        controller->numActiveIOBs++;
        controller->HIMFunc.HIMQueueIOB(&autoConfig->iob);
    } else
        IOPanic("AdaptecU2SCSI: Hardware reset failed.\n");
    return 0;
}

unsigned int PostRoutineEventPAC(AdaptecU2IOB *iob)
{
    AdaptecU2OSMIOB *osm = (AdaptecU2OSMIOB *)iob;
    AdaptecU2SCSI *controller = osm->owner.controller;

    ValidateTargets(osm);
    controller->autoConfigActive = 0;
    controller->numActiveIOBs--;
    FreeOSMIOB(controller, osm);
    return 0;
}

unsigned int PostProbe(AdaptecU2IOB *iob)
{
    AdaptecU2OSMIOB *osm = (AdaptecU2OSMIOB *)iob;
    AdaptecU2Command *command = iob->command;
    AdaptecU2SCSI *controller = osm->owner.controller;
    unsigned char id = command->request->target;
    AdaptecU2AttachedTarget *target;
    unsigned int size;

    if (iob->status == 1) {
        size = controller->HIMFunc.HIMSizeTargetTSCB(controller->adapterTSH);
        target = IOMalloc(sizeof(*target));
        bzero(target, sizeof(*target));
        queue_init(&target->waiting);
        queue_init(&target->active);
        target->controller = controller;
        target->storage = IOMalloc(size);
        target->size = size;
        bzero(target->storage, size);
        target->targetTSH = controller->HIMFunc.HIMCreateTargetTSCB(
            controller->adapterTSH, 0xffff, target->storage);
        controller->HIMFunc.HIMProfileTarget(target->targetTSH, &target->profile);
        controller->pAttachedTarget[id] = target;
        if ((controller->productID & 0xffff0000) == 0x00500000) {
            if (target->profile.words[22] < 400)
                target->profile.words[22] = 400;
            controller->HIMFunc.HIMAdjustTargetProfile(target->targetTSH,
                                                       &target->profile);
        }
    }
    controller->numActiveIOBs--;
    FreeOSMIOB(controller, osm);
    if (command) {
        if (iob->status == 1)
            command->result = SR_IOST_GOOD;
        else
            command->result = SR_IOST_SELTO;
        controller->NXConditionLock_lock(command->completionLock, @selector(lock));
        controller->NXConditionLock_unlockWith(command->completionLock,
                                               @selector(unlockWith:), 1);
    }
    return 0;
}

void CleanupWaitingQ(AdaptecU2AttachedTarget *target)
{
    AdaptecU2SCSI *controller = target->controller;
    AdaptecU2OSMIOB *iob;
    AdaptecU2Command *command;

    while (!queue_empty(&target->waiting)) {
        iob = (AdaptecU2OSMIOB *)queue_first(&target->waiting);
        command = iob->iob.command;
        queue_remove(&target->waiting, iob, AdaptecU2OSMIOB *, link);
        controller->numActiveIOBs--;
        FreeOSMIOB(controller, iob);
        command->result = SR_IOST_IOTO;
        controller->NXConditionLock_lock(command->completionLock, @selector(lock));
        controller->NXConditionLock_unlockWith(command->completionLock,
                                               @selector(unlockWith:), 1);
    }
}

void sub_18B2A8(thread_call_spec_t context, thread_call_t call)
{
    unsigned int irq = ((AdaptecU2SCSI *)context)->interrupt;
    AdaptecU2AdapterQueueEntry *entry;
    AdaptecU2SCSI *controller;

    for (entry = (AdaptecU2AdapterQueueEntry *)queue_first(&adapterQ[irq]);
         !queue_end(&adapterQ[irq], (queue_entry_t)entry);
         entry = (AdaptecU2AdapterQueueEntry *)queue_next(&entry->link)) {
        controller = entry->controller;
        if (controller->HIMFunc.HIMFrontEndISR(controller->adapterTSH))
            controller->HIMFunc.HIMBackEndISR(controller->adapterTSH);
    }
    for (entry = (AdaptecU2AdapterQueueEntry *)queue_first(&adapterQ[irq]);
         !queue_end(&adapterQ[irq], (queue_entry_t)entry);
         entry = (AdaptecU2AdapterQueueEntry *)queue_next(&entry->link)) {
        controller = entry->controller;
        controller->HIMFunc.HIMDisableIRQ(controller->adapterTSH);
    }
    for (entry = (AdaptecU2AdapterQueueEntry *)queue_first(&adapterQ[irq]);
         !queue_end(&adapterQ[irq], (queue_entry_t)entry);
         entry = (AdaptecU2AdapterQueueEntry *)queue_next(&entry->link)) {
        controller = entry->controller;
        controller->HIMFunc.HIMEnableIRQ(controller->adapterTSH);
    }
}

void AU2Handler(int interruptType, void *state, void *context)
{
    thread_call_func(sub_18B2A8, context, TRUE);
}

void AdaptecU2SCSITimeout(void *iob)
{
    IOLog("AdaptecU2SCSI: SCSI Timeout.\n");
    [((AdaptecU2OSMIOB *)iob)->owner.target->controller resetSCSIBus];
}

AdaptecU2OSMIOB *_allocOSMIOB(AdaptecU2AdapterProfile profile)
{
    unsigned int alignmentMask = profile.AP_AlignmentMask;
    unsigned int reserveSize = profile.AP_IOBReserveSize;
    AdaptecU2OSMIOB *iob = IOMalloc(sizeof(*iob));
    unsigned int address, physical;

    bzero(iob, sizeof(*iob));
    iob->reserveAllocation = AdptMallocContiguous(reserveSize + alignmentMask);
    iob->iob.reserve.size = reserveSize;
    address = ((unsigned int)iob->reserveAllocation + alignmentMask) & ~alignmentMask;
    iob->iob.reserve.virtualAddress = (unsigned char *)address;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), address, &physical)) {
        IOLog("AdaptecU2SCSI: Cannot get physical address.\n");
        return 0;
    }
    iob->iob.reserve.busAddress = physical;
    iob->sgAllocation = IOMalloc(page_size);
    iob->iob.transportSpecific = &iob->transport;
    return iob;
}

void _freeOSMIOB(AdaptecU2OSMIOB *iob, AdaptecU2AdapterProfile profile)
{
    AdptFreeContiguous(iob->reserveAllocation,
                       profile.AP_IOBReserveSize + profile.AP_AlignmentMask);
    IOFree(iob->sgAllocation, page_size);
    IOFree(iob, sizeof(*iob));
}

AdaptecU2OSMIOB *AllocOSMIOB(AdaptecU2SCSI *controller)
{
    AdaptecU2OSMIOB *iob;

    if (!queue_empty(&controller->iobQ)) {
        iob = (AdaptecU2OSMIOB *)queue_first(&controller->iobQ);
        queue_remove(&controller->iobQ, iob, AdaptecU2OSMIOB *, link);
    } else
        iob = _allocOSMIOB(controller->profile);
    controller->numIOBs++;
    iob->retryCount = 32;
    iob->iob.sense = iob->sense;
    iob->iob.senseLength = sizeof(iob->sense);
    iob->iob.data.virtualAddress = 0;
    iob->iob.data.busAddress = 0;
    iob->iob.data.size = 0;
    iob->iob.priority = 0;
    iob->iob.word18 = 0;
    iob->iob.word30 = 0;
    iob->iob.related = 0;
    iob->iob.status = 0;
    iob->iob.residualLength = 0;
    iob->iob.residualSense = 0;
    iob->iob.flags &= ~0x18000000;
    iob->interruptPort = controller->interruptPortKern;
    return iob;
}

void FreeOSMIOB(AdaptecU2SCSI *controller, AdaptecU2OSMIOB *iob)
{
    if (controller->numIOBs < 16)
        queue_enter(&controller->iobQ, iob, AdaptecU2OSMIOB *, link);
    else
        _freeOSMIOB(iob, controller->profile);
    controller->numIOBs--;
}

AdaptecU2OSMFunctions OSMRoutines = {
    0,
    OSMMapIOHandle,
    OSMReleaseIOHandle,
    OSMEvent,
    OSMGetBusAddress,
    OSMAdjustBusAddress,
    OSMGetNVSize,
    OSMPutNVData,
    OSMGetNVData,
    OSMReadUExact8,
    OSMReadUExact16,
    OSMReadUExact32,
    OSMReadStringUExact8,
    OSMReadStringUExact16,
    OSMReadStringUExact32,
    OSMWriteUExact8,
    OSMWriteUExact16,
    OSMWriteUExact32,
    OSMWriteStringUExact8,
    OSMWriteStringUExact16,
    OSMWriteStringUExact32,
    OSMSynchronizeRange,
    OSMWatchdog,
    OSMSaveInterruptState,
    OSMSetInterruptState,
    OSMReadPCIConfigurationDword,
    OSMReadPCIConfigurationWord,
    OSMReadPCIConfigurationByte,
    OSMWritePCIConfigurationDword,
    OSMWritePCIConfigurationWord,
    OSMWritePCIConfigurationByte
};
