#include "AdaptecU2CHIMPrivate.h"

#define EMPTY_HIOB ((AdaptecU2HIOB *)0xffffffff)

unsigned char SCSIrGetScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    if (hhcb->freeScbs <= 1) return 255;
    --hhcb->freeScbs;
    hiob->scb = hhcb->freeHead;
    hhcb->freeHead = hhcb->freeHead->next;
    return hiob->scb->number;
}

void SCSIrReturnScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    ++hhcb->freeScbs;
    hhcb->freeTail->next = hiob->scb;
    hhcb->freeTail = hiob->scb;
}

void SCSIrDeviceQueueAppend(AdaptecU2ResourceControl *resource, AdaptecU2HIOB *hiob)
{
    volatile AdaptecU2ResourceControl *queue = resource;
    hiob->next = EMPTY_HIOB;
    if (queue->head == EMPTY_HIOB) {
        queue->tail = hiob;
        queue->head = hiob;
    }
    else {
        queue->tail->next = hiob;
        queue->tail = hiob;
    }
    ++queue->queuedCount;
}

AdaptecU2HIOB *SCSIrDeviceQueueRemove(AdaptecU2ResourceControl *resource)
{
    volatile AdaptecU2ResourceControl *queue = resource;
    AdaptecU2HIOB *hiob = queue->head;
    unsigned int limit;
    if (hiob != EMPTY_HIOB) {
        limit = (hiob->control.flags & 0x4000) ? queue->taggedLimit : queue->nonTaggedLimit;
        if (limit <= queue->activeCount - queue->queuedCount) return EMPTY_HIOB;
        if (queue->head == queue->tail) {
            queue->tail = EMPTY_HIOB;
            queue->head = EMPTY_HIOB;
        }
        else queue->head = queue->head->next;
        --queue->queuedCount;
    }
    return hiob;
}

void SCSIrHostQueueAppend(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    volatile AdaptecU2HHCB *queue = hhcb;
    hiob->next = EMPTY_HIOB;
    if (queue->hostHead == EMPTY_HIOB) {
        queue->hostTail = hiob;
        queue->hostHead = hiob;
    }
    else {
        queue->hostTail->next = hiob;
        queue->hostTail = hiob;
    }
}

AdaptecU2HIOB *SCSIrHostQueueRemove(AdaptecU2HHCB *hhcb, unsigned char unusedScbNumber)
{
    volatile AdaptecU2HHCB *queue = hhcb;
    AdaptecU2HIOB *hiob = queue->hostHead;
    if (hiob != EMPTY_HIOB) {
        if (hiob == queue->hostTail) {
            queue->hostTail = EMPTY_HIOB;
            queue->hostHead = EMPTY_HIOB;
        }
        else queue->hostHead = hiob->next;
    }
    return hiob;
}

void SCSIrFreezeDeviceQueue(AdaptecU2ResourceControl *resource, unsigned int mask)
{
    volatile AdaptecU2ResourceControl *queue = resource;
    if (!queue->freezeMask) {
        if (queue->nonTaggedLimit) {
            queue->savedNonTaggedLimit = queue->nonTaggedLimit;
            queue->nonTaggedLimit = 0;
        }
        if (queue->taggedLimit) {
            queue->savedTaggedLimit = queue->taggedLimit;
            queue->taggedLimit = 0;
        }
    }
    queue->freezeMask |= mask;
}

void SCSIrUnFreezeDeviceQueue(AdaptecU2ResourceControl *resource, unsigned int mask)
{
    volatile AdaptecU2ResourceControl *queue = resource;
    if (queue->freezeMask) {
        queue->freezeMask &= ~mask;
        if (!queue->freezeMask) {
            unsigned int nonTagged = queue->savedNonTaggedLimit;
            unsigned int tagged = queue->savedTaggedLimit;
            queue->savedNonTaggedLimit = 0;
            queue->savedTaggedLimit = 0;
            queue->nonTaggedLimit = nonTagged;
            queue->taggedLimit = tagged;
        }
    }
}

void SCSIrAdjustQueue(AdaptecU2HIOB **head, AdaptecU2HIOB **tail,
    AdaptecU2HIOB *const *previous, AdaptecU2HIOB *hiob)
{
    if (*head == *tail) {
        *tail = EMPTY_HIOB;
        *head = EMPTY_HIOB;
    }
    else if (hiob == *head) *head = hiob->next;
    else {
        (*previous)->next = hiob->next;
        if (hiob == *tail) *tail = *previous;
    }
}

void SCSIrPostAbortedHIOB(AdaptecU2HIOB *hiob, unsigned char status)
{
    --hiob->context.unit->resource->activeCount;
    hiob->status = 2;
    hiob->hostStatus = status;
    OSDCompleteHIOB(hiob);
}

unsigned char SCSIrAbortHIOBInDevQ(AdaptecU2HIOB *hiob, unsigned char status)
{
    AdaptecU2ResourceControl *resource = hiob->context.unit->resource;
    AdaptecU2HIOB *current = resource->head, *previous = current;
    while (current != EMPTY_HIOB) {
        if (current == hiob) {
            SCSIrAdjustQueue(&resource->head, &resource->tail, &previous, current);
            SCSIrPostAbortedHIOB(current, status);
            return 1;
        }
        previous = current;
        current = current->next;
    }
    return 0;
}

unsigned char SCSIrAbortHIOBInHostQ(AdaptecU2HIOB *hiob, unsigned char status)
{
    AdaptecU2HHCB *hhcb = hiob->context.unit->hhcb;
    AdaptecU2HIOB *current = hhcb->hostHead, *previous = current;
    while (current != EMPTY_HIOB) {
        if (current == hiob) {
            SCSIrAdjustQueue(&hhcb->hostHead, &hhcb->hostTail, &previous, current);
            SCSIrPostAbortedHIOB(current, status);
            return 1;
        }
        previous = current;
        current = current->next;
    }
    return 0;
}

void SCSIrClearDeviceQueue(AdaptecU2ResourceControl *resource, unsigned char status)
{
    AdaptecU2HIOB *tail = resource->tail, *hiob = resource->head;
    if (hiob != EMPTY_HIOB) {
        while (hiob != tail) {
            resource->head = resource->head->next;
            SCSIrPostAbortedHIOB(hiob, status);
            hiob = resource->head;
        }
        resource->head = resource->head->next;
        SCSIrPostAbortedHIOB(hiob, status);
        if (resource->head == EMPTY_HIOB) resource->tail = EMPTY_HIOB;
    }
}

void SCSIrClearHostQueue(AdaptecU2HHCB *hhcb, unsigned char status)
{
    AdaptecU2HIOB *tail = hhcb->hostTail, *hiob = hhcb->hostHead;
    if (hiob != EMPTY_HIOB) {
        while (hiob != tail) {
            hhcb->hostHead = hhcb->hostHead->next;
            SCSIrPostAbortedHIOB(hiob, status);
            hiob = hhcb->hostHead;
        }
        hhcb->hostHead = hhcb->hostHead->next;
        SCSIrPostAbortedHIOB(hiob, status);
        if (hhcb->hostHead == EMPTY_HIOB) hhcb->hostTail = EMPTY_HIOB;
    }
}

void SCSIrClearAllDeviceQueues(AdaptecU2HHCB *hhcb, unsigned char status)
{
    int target;
    for (target = 0; target < 16; ++target)
        SCSIrClearDeviceQueue(&hhcb->resources[target], status);
}

void SCSIrFindAndAbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2UnitControl *unit,
    unsigned char status)
{
    AdaptecU2HIOB *current = hhcb->hostHead, *previous = current;
    AdaptecU2HIOB *tail = hhcb->hostTail, *next;
    if (current != EMPTY_HIOB) {
        while (current != tail) {
            next = current->next;
            if (current->context.unit->target == unit->target) {
                SCSIrAdjustQueue(&hhcb->hostHead, &hhcb->hostTail, &previous, current);
                SCSIrPostAbortedHIOB(current, status);
            } else previous = current;
            current = next;
        }
        if (current->context.unit->target == unit->target) {
            SCSIrAdjustQueue(&hhcb->hostHead, &hhcb->hostTail, &previous, current);
            SCSIrPostAbortedHIOB(current, status);
        }
    }
}

void SCSIrAllocateScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    hiob->control.bytes.scbNumber = hhcb->firmware->getScb(hhcb, hiob);
    if (hiob->control.bytes.scbNumber == 255) SCSIrHostQueueAppend(hhcb, hiob);
    else SCSIHQueueHIOB(hiob);
}

void SCSIrDispatchQueuedHIOB(AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    AdaptecU2ResourceControl *resource = unit->resource;
    unsigned int count = 0, limit;
    AdaptecU2HIOB *queued;
    if (!resource->freezeMask) {
        queued = SCSIrDeviceQueueRemove(resource);
        if (queued != EMPTY_HIOB) {
            limit = ((queued->control.flags & 0x4000) ? resource->taggedLimit : resource->nonTaggedLimit) - 1;
            do {
                SCSIrAllocateScb(unit->hhcb, queued);
                if (++count > limit) break;
                queued = SCSIrDeviceQueueRemove(resource);
            } while (queued != EMPTY_HIOB);
        }
    }
}

void SCSIrFinishQueueFull(AdaptecU2HIOB *hiob)
{
    AdaptecU2ResourceControl *resource = hiob->context.unit->resource;
    if (resource->savedTaggedLimit > 1) resource->savedTaggedLimit >>= 1;
    SCSIrUnFreezeDeviceQueue(resource, 1);
    SCSIrDispatchQueuedHIOB(hiob);
}

void SCSIrFreeCriteria(AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    AdaptecU2ResourceControl *resource = unit->resource;
    unsigned int limit = (hiob->control.flags & 0x4000) ? resource->taggedLimit : resource->nonTaggedLimit;
    AdaptecU2HIOB *queued;
    if (!resource->freezeMask) {
        if (--resource->activeCount >= limit) {
            queued = SCSIrDeviceQueueRemove(resource);
            if (queued != EMPTY_HIOB) SCSIrAllocateScb(unit->hhcb, queued);
        }
    } else {
        --resource->activeCount;
        if (SCSIHCheckDeviceIdle(unit->hhcb, unit->target) && (resource->freezeMask & 1))
            SCSIrFinishQueueFull(hiob);
        if (resource->freezeMask && hiob->priority > 127) {
            if (--resource->recoveryCount == 0) {
                SCSIrUnFreezeDeviceQueue(unit->resource, 32);
                SCSIrDispatchQueuedHIOB(hiob);
            }
        }
    }
}

void SCSIrFreeScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2HIOB *queued = hhcb->firmware->hostQueueRemove(hhcb, hiob->control.bytes.scbNumber);
    hhcb->firmware->returnScb(hhcb, hiob);
    if (queued != EMPTY_HIOB) {
        queued->control.bytes.scbNumber = hhcb->firmware->getScb(hhcb, queued);
        if (queued->function) SCSIHQueueSpecialHIOB(queued);
        else SCSIHQueueHIOB(queued);
    }
    SCSIrFreeCriteria(hiob);
}

void SCSIrFreezeAllDeviceQueues(AdaptecU2HHCB *hhcb)
{
    int target;
    for (target = 0; target < 16; ++target) SCSIrFreezeDeviceQueue(&hhcb->resources[target], 8);
}

void SCSIrUnFreezeAllDeviceQueues(AdaptecU2HHCB *hhcb)
{
    int target;
    for (target = 0; target < 16; ++target) {
        SCSIrUnFreezeDeviceQueue(&hhcb->resources[target], 8);
        if (hhcb->resources[target].head != EMPTY_HIOB)
            SCSIrDispatchQueuedHIOB(hhcb->resources[target].head);
    }
}

void SCSIrPostDoneQueue(AdaptecU2HHCB *hhcb)
{
    unsigned char tail = hhcb->doneTail;
    while (hhcb->doneHead != tail) {
        hhcb->doneTail = tail + 1;
        if (hhcb->doneTail == hhcb->numberScbs) hhcb->doneTail = 0;
        OSDCompleteHIOB(hhcb->doneHiobs[tail]);
        tail = hhcb->doneTail;
    }
}

void SCSIrStandardRemoveScbs(AdaptecU2HHCB *hhcb)
{
    hhcb->scbDescriptors[1].next = &hhcb->scbDescriptors[3];
    --hhcb->freeScbs;
}

AdaptecU2SCBDescriptor *SCSIRGetFreeHead(AdaptecU2HHCB *hhcb)
{
    return hhcb->freeHead;
}

void SCSIRSetUnitHandle(AdaptecU2HHCB *hhcb, AdaptecU2UnitControl *unit,
    unsigned char target, unsigned char lun)
{
    SCSIHSetUnitHandle(hhcb, unit, target, lun);
    unit->resource = &hhcb->resources[target];
}

void SCSIRFreeUnitHandle(AdaptecU2UnitHandleArgument unusedHandle)
{
    SCSIHFreeUnitHandle(unusedHandle);
}

unsigned int SCSIRCheckHostIdle(AdaptecU2HHCB *hhcb)
{
    int target;
    if (hhcb->hostHead != EMPTY_HIOB) return 0;
    for (target = 0; target < 16; ++target)
        if (hhcb->resources[target].head != EMPTY_HIOB) return 0;
    return SCSIHCheckHostIdle(hhcb);
}

unsigned int SCSIRCheckDeviceIdle(AdaptecU2HHCB *hhcb, unsigned char target)
{
    AdaptecU2HIOB *hiob = hhcb->hostHead;
    while (hiob != EMPTY_HIOB) {
        if (hiob->context.unit->target == target) return 0;
        hiob = hiob->next;
    }
    if (hhcb->resources[target].head != EMPTY_HIOB) return 0;
    return SCSIHCheckDeviceIdle(hhcb, target);
}

unsigned int SCSIRPowerManagement(AdaptecU2HHCB *hhcb, unsigned int unusedEventWord)
{
    if (SCSIRCheckHostIdle(hhcb)) return SCSIHPowerManagement(hhcb, unusedEventWord);
    return 2;
}

void SCSIRGetMemoryTable(unsigned char firmwareMode, unsigned char scbCount,
    AdaptecU2MemoryDescriptor *table)
{
    volatile AdaptecU2MemoryDescriptor *descriptor = table;
    SCSIHGetMemoryTable(firmwareMode, scbCount, table);
    descriptor[5].byte02 = 0;
    descriptor[5].category = 0;
    descriptor[5].alignmentMask = 3;
    descriptor[5].size = scbCount * 20;
    descriptor[5].minimumSize = scbCount * 20;
    descriptor[5].granularity = 0;
    descriptor[3].byte02 = 0;
    descriptor[3].category = 0;
    descriptor[3].alignmentMask = 3;
    descriptor[3].size = scbCount * 4;
    descriptor[3].minimumSize = scbCount * 4;
    descriptor[3].granularity = 0;
}

unsigned int SCSIRGetConfiguration(AdaptecU2HHCB *hhcb)
{
    unsigned char limit;
    SCSIHGetConfiguration(hhcb);
    limit = hhcb->firmware->registers[24];
    hhcb->taggedLimit = 4;
    hhcb->nonTaggedLimit = limit;
    return 0;
}

unsigned int SCSIRApplyMemoryTable(AdaptecU2HHCB *hhcb, const AdaptecU2MemoryDescriptor *table)
{
    hhcb->doneHiobs = (AdaptecU2HIOB **)table[3].address;
    hhcb->scbDescriptors = (AdaptecU2SCBDescriptor *)table[5].address;
    return SCSIHApplyMemoryTable(hhcb, table);
}

void SCSIrReset(AdaptecU2HHCB *hhcb)
{
    int scb, target;
    unsigned int busAddress, size;
    volatile AdaptecU2ResourceControl *resource;
    volatile AdaptecU2HHCB *state = hhcb;
    state->doneTail = 0;
    state->doneHead = 0;
    state->hostTail = EMPTY_HIOB;
    state->hostHead = EMPTY_HIOB;
    hhcb->freeScbs = hhcb->numberScbs;
    hhcb->freeHead = hhcb->scbDescriptors;
    hhcb->freeTail = hhcb->scbDescriptors + hhcb->numberScbs - 1;
    for (scb = 0; scb < hhcb->numberScbs; ++scb) {
        hhcb->scbDescriptors[scb].number = scb;
        size = SCSIFirmware[hhcb->firmwareMode]->word04;
        hhcb->scbDescriptors[scb].virtualAddress = hhcb->scbBuffers + scb * size;
        busAddress = OSDGetBusAddress(hhcb, 1, hhcb->scbBuffers);
        OSDAdjustBusAddress(hhcb, &busAddress, scb * SCSIFirmware[hhcb->firmwareMode]->word04);
        hhcb->scbDescriptors[scb].busAddress = busAddress;
        hhcb->scbDescriptors[scb].size = SCSIFirmware[hhcb->firmwareMode]->word04;
        if (scb + 1 != hhcb->numberScbs)
            hhcb->scbDescriptors[scb].next = &hhcb->scbDescriptors[scb + 1];
    }
    hhcb->scbDescriptors[hhcb->numberScbs - 1].next = hhcb->scbDescriptors;
    if (hhcb->firmware->removeScbs) hhcb->firmware->removeScbs(hhcb);
    for (target = 0; target < 16; ++target) {
        resource = &hhcb->resources[target];
        resource->nonTaggedLimit = hhcb->nonTaggedLimit;
        resource->tail = EMPTY_HIOB;
        resource->taggedLimit = hhcb->taggedLimit;
        resource->head = EMPTY_HIOB;
        resource->activeCount = 0;
        resource->savedNonTaggedLimit = 0;
        resource->savedTaggedLimit = 0;
        resource->resetCount = 0;
        resource->abortSetCount = 0;
        resource->freezeMask = 0;
        resource->savedTail = EMPTY_HIOB;
        resource->recoveryCount = 0;
        resource->queuedCount = 0;
    }
}

int SCSIRInitialize(AdaptecU2HHCB *hhcb)
{
    SCSIrReset(hhcb);
    return SCSIHInitialize(hhcb);
}

void SCSIrCompleteHIOB(AdaptecU2HIOB *hiob)
{
    AdaptecU2HHCB *hhcb = hiob->context.unit->hhcb;
    AdaptecU2ResourceControl *resource = hiob->context.unit->resource;
    unsigned char head;
    if (hiob->status == 5) {
        SCSIrFreeScb(hhcb, hiob);
        SCSIrDeviceQueueAppend(resource, hiob);
    } else {
        if (hiob->targetStatus == 40) SCSIrFreezeDeviceQueue(resource, 1);
        SCSIrFreeScb(hhcb, hiob);
        head = hhcb->doneHead;
        hhcb->doneHead = head + 1;
        hhcb->doneHiobs[head] = hiob;
        if (hhcb->doneHead == hhcb->numberScbs) hhcb->doneHead = 0;
    }
}

void SCSIrCompleteSpecialHIOB(AdaptecU2HIOB *hiob)
{
    AdaptecU2HHCB *hhcb;
    AdaptecU2ResourceControl *resource;
    switch (hiob->function) {
    case 1:
        hhcb = hiob->context.related->context.unit->hhcb;
        break;
    case 2:
        hhcb = hiob->context.hhcb;
        SCSIrUnFreezeAllDeviceQueues(hhcb);
        break;
    case 3:
        hhcb = hiob->context.unit->hhcb;
        resource = hiob->context.unit->resource;
        SCSIrFreeScb(hhcb, hiob);
        if (--resource->resetCount == 0) {
            SCSIrUnFreezeDeviceQueue(resource, 2);
            SCSIrDispatchQueuedHIOB(hiob);
        }
        break;
    case 7:
        hhcb = hiob->context.unit->hhcb;
        resource = hiob->context.unit->resource;
        if (--resource->abortSetCount == 0) {
            SCSIrUnFreezeDeviceQueue(resource, 16);
            SCSIrDispatchQueuedHIOB(hiob);
        }
        break;
    default:
        OSDCompleteSpecialHIOB(hiob);
        return;
    }
    SCSIrPostDoneQueue(hhcb);
    OSDCompleteSpecialHIOB(hiob);
}

void SCSIrScsiBusReset(AdaptecU2HIOB *hiob)
{
    AdaptecU2HHCB *hhcb = hiob->context.hhcb;
    SCSIrFreezeAllDeviceQueues(hhcb);
    SCSIrClearHostQueue(hhcb, 6);
    SCSIrClearAllDeviceQueues(hhcb, 6);
    SCSIHQueueSpecialHIOB(hiob);
}

void SCSIrBusDeviceReset(AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    AdaptecU2ResourceControl *resource = unit->resource;
    AdaptecU2HHCB *hhcb = unit->hhcb;
    if (!resource->resetCount) SCSIrFreezeDeviceQueue(resource, 2);
    SCSIrFindAndAbortHIOB(hhcb, unit, 8);
    SCSIrClearDeviceQueue(resource, 8);
    ++resource->resetCount;
    ++resource->activeCount;
    hiob->control.bytes.scbNumber = hhcb->firmware->getScb(hhcb, hiob);
    if (hiob->control.bytes.scbNumber == 255) SCSIrHostQueueAppend(hhcb, hiob);
    else SCSIHQueueSpecialHIOB(hiob);
}

void SCSIRGetHWInformation(AdaptecU2HWInformation *information, AdaptecU2HHCB *hhcb)
{
    int target;
    for (target = 0; target < 16; ++target)
        information->targets[target].queueDepth = hhcb->resources[target].freezeMask ?
            hhcb->resources[target].savedTaggedLimit : hhcb->resources[target].taggedLimit;
    SCSIHGetHWInformation(information, hhcb);
}

void SCSIRPutHWInformation(const AdaptecU2HWInformation *information, AdaptecU2HHCB *hhcb)
{
    int target;
    for (target = 0; target < 16; ++target) {
        if (hhcb->resources[target].freezeMask)
            hhcb->resources[target].savedTaggedLimit = information->targets[target].queueDepth;
        else hhcb->resources[target].taggedLimit = information->targets[target].queueDepth;
    }
    SCSIHPutHWInformation(information, hhcb);
}

void SCSIrAsyncEvent(AdaptecU2HHCB *hhcb, unsigned int event, ...)
{
    switch (event) {
    case 1:
        SCSIrClearHostQueue(hhcb, 7);
        SCSIrClearAllDeviceQueues(hhcb, 7);
        SCSIrPostDoneQueue(hhcb);
        break;
    case 3:
        SCSIrClearHostQueue(hhcb, 20);
        SCSIrClearAllDeviceQueues(hhcb, 20);
        SCSIrPostDoneQueue(hhcb);
        break;
    case 5:
        SCSIrClearHostQueue(hhcb, 5);
        SCSIrClearAllDeviceQueues(hhcb, 5);
        SCSIrPostDoneQueue(hhcb);
        break;
    case 6:
        SCSIrFreezeAllDeviceQueues(hhcb);
        break;
    case 7:
        SCSIrUnFreezeAllDeviceQueues(hhcb);
        break;
    case 8:
        SCSIrClearHostQueue(hhcb, 9);
        SCSIrClearAllDeviceQueues(hhcb, 9);
        SCSIrPostDoneQueue(hhcb);
        break;
    }
    if (event != 7) OSDAsyncEvent(hhcb, event);
}

void SCSIrAsyncEventCommand(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob,
    unsigned int event, ...)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    volatile AdaptecU2ResourceControl *resource;
    volatile AdaptecU2HHCB *queues = hhcb;
    AdaptecU2HIOB *current, *previous;
    unsigned char target;
    if (event == 1) {
        resource = unit->resource;
        resource->savedActiveCount = resource->activeCount;
        SCSIrFreezeDeviceQueue(resource, 4);
        resource->savedTail = resource->tail;
        target = unit->target;
        resource->frozenTail = EMPTY_HIOB;
        resource->frozenHead = EMPTY_HIOB;
        previous = current = queues->hostHead;
        while (current != EMPTY_HIOB) {
            if (current->context.unit->target == target) {
                if (previous == queues->hostTail) {
                    queues->hostTail = EMPTY_HIOB;
                    queues->hostHead = EMPTY_HIOB;
                } else {
                    previous->next = current->next;
                    current = current->next;
                }
                if (resource->frozenHead == EMPTY_HIOB) {
                    resource->frozenTail = current;
                    resource->frozenHead = current;
                } else {
                    resource->frozenTail->next = current;
                    resource->frozenTail = current;
                }
            } else {
                previous = current;
                current = current->next;
            }
        }
    } else if (event == 2) {
        resource = unit->resource;
        if (resource->frozenTail != EMPTY_HIOB) {
            resource->tail->next = resource->frozenHead;
            resource->tail = resource->frozenTail;
        }
        if (resource->savedTail != EMPTY_HIOB) {
            resource->tail->next = resource->head;
            resource->head = resource->savedTail->next;
            resource->savedTail->next = EMPTY_HIOB;
            current = resource->savedTail;
            resource->savedTail = EMPTY_HIOB;
            resource->tail = current;
        }
        resource->activeCount = resource->savedActiveCount;
    }
}

void SCSIrAbortTask(AdaptecU2HIOB *hiob)
{
    AdaptecU2HIOB *related = hiob->context.related;
    if (!SCSIrAbortHIOBInHostQ(related, 4) && !SCSIrAbortHIOBInDevQ(related, 4))
        SCSIHQueueSpecialHIOB(hiob);
    else {
        hiob->status = 1;
        SCSIrCompleteSpecialHIOB(hiob);
    }
}

void SCSIrAbortTaskSet(AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    AdaptecU2ResourceControl *resource = unit->resource;
    AdaptecU2HHCB *hhcb = unit->hhcb;
    if (!resource->abortSetCount) SCSIrFreezeDeviceQueue(resource, 16);
    SCSIrFindAndAbortHIOB(hhcb, unit, 4);
    SCSIrClearDeviceQueue(resource, 4);
    ++resource->abortSetCount;
    SCSIHQueueSpecialHIOB(hiob);
}

void SCSIRQueueSpecialHIOB(AdaptecU2HIOB *hiob)
{
    unsigned char function = hiob->function;
    volatile AdaptecU2HIOB *state = hiob;
    state->status = 0;
    state->hostStatus = 0;
    state->targetStatus = 0;
    state->managerStatus = 0;
    state->negotiationState = 0;
    switch (function) {
    case 1: SCSIrAbortTask(hiob); break;
    case 2: SCSIrScsiBusReset(hiob); break;
    case 3: SCSIrBusDeviceReset(hiob); break;
    case 6: SCSIHQueueSpecialHIOB(hiob); break;
    case 7: SCSIrAbortTaskSet(hiob); break;
    case 9:
        SCSIrUnFreezeDeviceQueue(hiob->context.unit->resource, 4);
        SCSIrDispatchQueuedHIOB(hiob);
    case 4:
    case 8:
        hiob->status = 1;
        SCSIrCompleteSpecialHIOB(hiob);
        break;
    }
}
