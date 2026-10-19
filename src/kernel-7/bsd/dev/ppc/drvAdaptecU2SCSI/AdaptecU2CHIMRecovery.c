#include "AdaptecU2CHIMPrivate.h"
#include <machdep/ppc/pmap.h>

#define RECOVERY_LOAD_LE32(address, value) \
    __asm__ ("lwbrx %0,0,%1" : "=r" (value) : "r" (address) : "memory")
#define RECOVERY_STORE_LE32(address, value) \
    __asm__ volatile ("stwbrx %0,0,%1" : : "r" (value), "r" (address) : "memory")
#define RECOVERY_STORE_LE16(address, value) \
    __asm__ volatile ("sthbrx %0,0,%1" : : "r" (value), "r" (address) : "memory")

void SCSIhSetStat(AdaptecU2HIOB *hiob)
{
    volatile AdaptecU2HIOB *state = hiob;
    unsigned char host = state->hostStatus, target;
    if (host == 0) {
        target = state->targetStatus;
        if (target == 0 || target == 4 || target == 16 || target == 20) {
            state->status = 1;
            return;
        }
    }
    if (state->status != 2) {
        if (host == 4 || host == 8) {
            target = state->targetStatus;
            if (target == 0 || target == 4 || target == 16 || target == 20) {
                state->status = 1;
                return;
            }
        }
        state->status = 3;
        return;
    }
    if (host != 4 && host != 8) {
        state->status = 3;
        return;
    }
    target = state->targetStatus;
    if (target != 0 && target != 4 && target != 16 && target != 20) {
        state->hostStatus = 0;
        state->status = 3;
    }
}

void SCSIhTerminateCommand(AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    AdaptecU2HHCB *hhcb = unit->hhcb;
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control;
    hhcb->activeHiobs[hiob->control.bytes.scbNumber] = (AdaptecU2HIOB *)-1;
    SCSIhSetStat(hiob);
    if (hiob->function == 0)
        SCSIrCompleteHIOB(hiob);
    else {
        if (hiob->function == 3) {
            control = OSMReadUExact8(*handle, 135);
            if (!(control & 4))
                SCSIhPauseAndWait(hhcb);
            hhcb->firmware->xferOptAssign(hhcb, unit->target,
                (*((unsigned char *)unit->device + 4) & 0x81) ? 143 : 0);
            if (!(control & 4))
                SCSIhWriteHCNTRL(hhcb, control);
        }
        SCSIrCompleteSpecialHIOB(hiob);
    }
}

void SCSIhAbortTarget(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char scb;
    if ((SCSIhReadINTSTAT(hhcb) & 0xf0) == 0x90) {
        OSMWriteUExact8(*handle, 3, 0xf0);
        OSMReadUExact8(*handle, 6);
    }
    if (SCSIhWait4Req(hhcb) == 160) {
        scb = OSMReadUExact8(*handle, hhcb->firmware->registers[3]);
        if (scb != 255 && hiob != (AdaptecU2HIOB *)-1) {
            if (hiob->managerStatus == 5) {
                if (hhcb->firmware->removeActiveAbort)
                    hhcb->firmware->removeActiveAbort(hhcb, hiob);
                hiob->managerStatus = 8;
                return;
            }
            if (hiob->managerStatus == 6) {
                SCSIhBusDeviceReset(hhcb, hiob);
                return;
            }
            if (hiob->managerStatus == 2)
                return;
        }
    }
    SCSIhBadSeq(hhcb);
}

void SCSIhCheckLength(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned int count = 0x80000000U, residue;
    unsigned char phase, value, control;
    if ((hiob->control.flags & 0x800) && !(hiob->context.unit->resource->freezeMask & 0x20)) {
        if (hhcb->firmware->freezeHWQueue)
            hhcb->firmware->freezeHWQueue(hhcb, hiob);
    }
    phase = OSMReadUExact8(*handle, 3) & 0xe0;
    if (phase == 0xc0) {
        if (hiob->control.flags & 0x8000)
            return;
        residue = hhcb->firmware->residueCalc(hhcb, hiob);
        if (hiob->targetStatus == 2) {
            hiob->residualSense = residue;
            return;
        }
        hiob->residualLength = residue;
    } else if (!(phase & 0x80)) {
        OSMWriteUExact8(*handle, 3, phase);
        value = OSMReadUExact8(*handle, 147);
        OSMWriteUExact8(*handle, 147, (phase & 0x40) ? value & ~4 : value | 4);
        control = OSMReadUExact8(*handle, 2);
        OSMWriteUExact8(*handle, 2, control | 0x80);
        do {
            value = OSMReadUExact8(*handle, 12);
            if (value & 0x10)
                break;
            --count;
            if (value & 0x28)
                break;
        } while (count);
        hiob->residualLength = 0;
        OSMWriteUExact8(*handle, 2, control);
    }
    hiob->hostStatus = 18;
}

void SCSIhBreakInterrupt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned int i;
    AdaptecU2HIOB *active;
    if (hhcb->hardwareFlags & 0x20000) {
        if (hhcb->hardwareFlags & 0x10000) {
            hhcb->firmware->clearBreakPoint(hhcb, 1);
            hhcb->firmware->setBreakPoint(hhcb, 2);
        } else {
            AdaptecU2DeviceTable *device = hiob->context.unit->device;
            unsigned char value = OSMReadUExact8(*hhcb->ioHandle, 13);
            device->flags = (device->flags & ~0x10) | (value & 0x10) | 8;
            hhcb->firmware->clearBreakPoint(hhcb, 2);
        }
    } else
        hhcb->firmware->clearBreakPoint(hhcb, 1);
    if (hhcb->hardwareFlags & 0x10000) {
        hhcb->hardwareFlags &= ~0x10000;
        for (i = 0; i < hhcb->numberScbs; ++i) {
            active = hhcb->activeHiobs[i];
            if (active != (AdaptecU2HIOB *)-1 && active->context.unit->hhcb == hhcb) {
                if (active->managerStatus == 9)
                    hhcb->firmware->activeAbort(hhcb, active);
                else if (active->managerStatus == 10) {
                    hhcb->firmware->qHeadBDR(hhcb, active);
                    active->managerStatus = 6;
                }
            }
        }
    }
}

void SCSIhSwappingRemoveActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char value = OSMReadUExact8(*handle, 0), selected;
    if ((value & 0x40) &&
        (selected = OSMReadUExact8(*handle, hhcb->firmware->registers[4])) ==
        OSMReadUExact8(*handle, hhcb->firmware->registers[3])) {
        hiob->managerStatus = 1;
        OSMWriteUExact8(*handle, 0, value & 0x33);
        OSMReadUExact8(*handle, 0);
    } else if (SCSIhSwappingRemoveAbortHIOBFromNewQ(hhcb, hiob, hiob->hostStatus))
        hiob->managerStatus = 1;
}

void SCSIhStandardRemoveActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char value = OSMReadUExact8(*handle, 0), selected;
    if ((value & 0x40) &&
        (selected = OSMReadUExact8(*handle, hhcb->firmware->registers[4])) ==
        OSMReadUExact8(*handle, hhcb->firmware->registers[3])) {
        hiob->managerStatus = 1;
        OSMWriteUExact8(*handle, 0, value & 0x33);
        OSMReadUExact8(*handle, 0);
    } else if (hhcb->firmware->searchExeQ(hhcb, hiob, hiob->hostStatus, 0))
        hiob->managerStatus = 1;
}

unsigned char SCSIhSwappingRemoveAbortHIOBFromNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char tail = hhcb->hardware->getQNewTail(hhcb);
    unsigned char current = OSMReadUExact8(*handle, hhcb->firmware->registers[10]);
    unsigned char first = current, previous = current, next;
    while (tail != hhcb->qnewHead) {
        if (current == hiob->control.bytes.scbNumber) {
            hiob->status = 2;
            hiob->hostStatus = status;
            OSMWriteUExact8(*handle, hhcb->firmware->registers[8], --hhcb->qnewHead);
            next = hhcb->firmware->obtainNextScbNum(hhcb, hhcb->activeHiobs[current]);
            if (current == first)
                OSMWriteUExact8(*handle, hhcb->firmware->registers[10], next);
            else
                hhcb->firmware->updateNextScbNum(hhcb, hhcb->activeHiobs[previous], next);
            return 1;
        }
        previous = current;
        current = hhcb->firmware->obtainNextScbNum(hhcb, hhcb->activeHiobs[current]);
        ++tail;
    }
    return 0;
}

void SCSIhStandard64RequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned int i;
    hiob->managerStatus = 7;
    for (i = 0; i < 40; ++i)
        OSMWriteUExact8(*handle, 160 + i, 0);
    OSMWriteUExact8(*handle, 172, 128);
    OSMWriteUExact8(*handle, 173, unit->target);
    OSMWriteUExact8(*handle, 199, unit->lun);
    OSMWriteUExact8(*handle, 174, 134);
    OSMWriteUExact8(*handle, 160, 3);
    OSMWriteUExact8(*handle, 161, unit->lun << 5);
    OSMWriteUExact8(*handle, 162, 0);
    OSMWriteUExact8(*handle, 163, 0);
    OSMWriteUExact8(*handle, 164, hiob->senseLength);
    OSMWriteUExact8(*handle, 165, 0);
    SCSIhSetAddressScbBA32(hhcb, 184, hiob->auxiliary.sense);
    OSMWriteUExact8(*handle, 188, hiob->senseLength);
    OSMWriteUExact8(*handle, 189, 0);
    OSMWriteUExact8(*handle, 190, 0);
    SCSIhStandardTargetClearBusy(hhcb, hiob);
    SCSIhStandard64QHead(hhcb, hiob);
}

void SCSIhStandardAdvRequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned int i;
    unsigned char target = unit->target | (hhcb->hostID << 4);
    hiob->managerStatus = 7;
    for (i = 0; i < 40; ++i)
        OSMWriteUExact8(*handle, 160 + i, 0);
    OSMWriteUExact8(*handle, 160, 128);
    OSMWriteUExact8(*handle, 161, target);
    OSMWriteUExact8(*handle, 162, unit->lun);
    OSMWriteUExact8(*handle, 166, 6);
    OSMWriteUExact8(*handle, 167, 2);
    OSMWriteUExact8(*handle, 176, 3);
    OSMWriteUExact8(*handle, 177, unit->lun << 5);
    OSMWriteUExact8(*handle, 178, 0);
    OSMWriteUExact8(*handle, 179, 0);
    OSMWriteUExact8(*handle, 180, hiob->senseLength);
    OSMWriteUExact8(*handle, 181, 0);
    SCSIhSetAddressScbBA32(hhcb, 200, hiob->auxiliary.sense);
    OSMWriteUExact8(*handle, 204, hiob->senseLength);
    OSMWriteUExact8(*handle, 205, 0);
    OSMWriteUExact8(*handle, 206, 0);
    SCSIhStandardTargetClearBusy(hhcb, hiob);
    SCSIhStandardAdvQHead(hhcb, hiob);
}

void SCSIhSwapping32RequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    volatile unsigned char *scb = hiob->scb->virtualAddress;
    unsigned short length = hiob->senseLength;
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned int address, i;
    hiob->managerStatus = 7;
    scb[3] = 134;
    scb[8] = 3;
    scb[10] = 0;
    scb[11] = 0;
    scb[9] = unit->lun << 5;
    scb[13] = 0;
    scb[1] = 128;
    scb[12] = hiob->senseLength;
    address = OSDGetBusAddress(hhcb, 1, hiob->auxiliary.sense);
    RECOVERY_STORE_LE32(scb + 20, address);
    RECOVERY_STORE_LE16(scb + 24, length);
    scb[26] = 0;
    for (i = 6; i <= 11; ++i)
        scb[i + 8] = 0;
    SCSIhSwapping32QHead(hhcb, hiob);
    SCSIhSwappingTargetClearBusy(hhcb, hiob);
    flush_cache((vm_offset_t)scb, 32);
}

void SCSIhSwappingAdvRequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    volatile unsigned char *scb = hiob->scb->virtualAddress;
    unsigned short length = hiob->senseLength;
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned int address, i;
    unsigned char control;
    scb[12] &= 15;
    hiob->managerStatus = 7;
    scb[14] = 6;
    scb[15] = 2;
    scb[24] = 3;
    scb[26] = 0;
    scb[27] = 0;
    scb[25] = unit->lun << 5;
    control = scb[13];
    scb[29] = 0;
    scb[28] = hiob->senseLength;
    scb[13] = control & ~0x40;
    scb[38] = 0;
    address = OSDGetBusAddress(hhcb, 1, hiob->auxiliary.sense);
    RECOVERY_STORE_LE32(scb + 0, address);
    RECOVERY_STORE_LE16(scb + 4, length);
    scb[6] = 0;
    for (i = 6; i <= 11; ++i)
        scb[i + 24] = 0;
    SCSIhSwappingAdvQHead(hhcb, hiob);
    SCSIhSwappingTargetClearBusy(hhcb, hiob);
    flush_cache((vm_offset_t)scb, 64);
}

unsigned int SCSIhStandard64ResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    AdaptecU2BufferDescriptor *sg;
    unsigned int residue, address, current, count, index = 0, length;
    unsigned char state, cache;
    if (OSMReadUExact8(*handle, 174) & 64)
        return 0;
    if (OSMReadUExact8(*handle, 174) & 0x1f) {
        residue = SCSIhGetEntity32FromScb(hhcb, 188) & 0xffffff;
        address = SCSIhGetAddressScbBA32(hhcb, 176);
        cache = OSMReadUExact8(*handle, 175);
        state = OSMReadUExact8(*handle, 174);
    } else {
        residue = SCSIhGetEntity32FromScb(hhcb, 160) & 0xffffff;
        state = OSMReadUExact8(*handle, 171);
        if (state)
            residue += state;
        address = SCSIhGetAddressScbBA32(hhcb, 166);
        cache = OSMReadUExact8(*handle, 165);
        state = OSMReadUExact8(*handle, 164);
    }
    if (state & 128)
        return residue;
    sg = OSDGetSGList(hiob);
    current = sg->busAddress;
    count = 0x800000;
    while (SCSIhCompareBusAddress(address, current)) {
        if (!--count)
            break;
        OSDAdjustBusAddress(hhcb, &current, 8);
        ++index;
    }
    index += cache >> 3;
    RECOVERY_LOAD_LE32(sg->virtualAddress + 8 * (index ? index - 1 : 0) + 4, length);
    if (!(length & 0x80000000)) {
        count = 0x800000;
        for (;;) {
            RECOVERY_LOAD_LE32(sg->virtualAddress + 8 * index + 4, length);
            residue += length & 0xffffff;
            if (length & 0x80000000)
                break;
            if (!--count)
                break;
            ++index;
        }
    }
    return residue;
}

unsigned int SCSIhSwapping32ResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    AdaptecU2BufferDescriptor *sg;
    unsigned int residue, address, current, count, index = 0, length;
    unsigned char state;
    if (OSMReadUExact8(*handle, 163) & 64)
        return 0;
    if (OSMReadUExact8(*handle, 163) & 0x1f) {
        residue = SCSIhGetEntity32FromScb(hhcb, 184) & 0xffffff;
        address = SCSIhGetAddressScbBA32(hhcb, 164);
        state = OSMReadUExact8(*handle, 163);
    } else {
        residue = SCSIhGetEntity32FromScb(hhcb, 168) & 0xffffff;
        state = OSMReadUExact8(*handle, 178);
        if (state)
            residue += state;
        address = SCSIhGetAddressScbBA32(hhcb, 173);
        state = OSMReadUExact8(*handle, 172);
    }
    if (state & 128)
        return residue;
    sg = OSDGetSGList(hiob);
    current = sg->busAddress;
    count = 0x800000;
    while (SCSIhCompareBusAddress(address, current)) {
        if (!--count)
            break;
        OSDAdjustBusAddress(hhcb, &current, 8);
        ++index;
    }
    RECOVERY_LOAD_LE32(sg->virtualAddress + 8 * (index ? index - 1 : 0) + 4, length);
    if (!(length & 0x80000000)) {
        count = 0x800000;
        for (;;) {
            RECOVERY_LOAD_LE32(sg->virtualAddress + 8 * index + 4, length);
            residue += length & 0xffffff;
            if (length & 0x80000000)
                break;
            if (!--count)
                break;
            ++index;
        }
    }
    return residue;
}

unsigned int SCSIhStandardAdvResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    AdaptecU2BufferDescriptor *sg;
    unsigned int residue, address, current, count, index = 0, length;
    unsigned char state, cache;
    if (OSMReadUExact8(*handle, 167) & 1)
        return 0;
    if (OSMReadUExact8(*handle, 166) & 0x1f) {
        residue = SCSIhGetEntity32FromScb(hhcb, 204) & 0xffffff;
        address = SCSIhGetAddressScbBA32(hhcb, 168);
        cache = OSMReadUExact8(*handle, 167);
        state = OSMReadUExact8(*handle, 167);
    } else {
        residue = SCSIhGetEntity32FromScb(hhcb, 176) & 0xffffff;
        address = SCSIhGetAddressScbBA32(hhcb, 182);
        state = OSMReadUExact8(*handle, 181);
        cache = state;
    }
    if (state & 2)
        return residue;
    sg = OSDGetSGList(hiob);
    current = sg->busAddress;
    count = 0x800000;
    while (SCSIhCompareBusAddress(address, current)) {
        if (!--count)
            break;
        OSDAdjustBusAddress(hhcb, &current, 8);
        ++index;
    }
    index += cache >> 3;
    RECOVERY_LOAD_LE32(sg->virtualAddress + 8 * (index ? index - 1 : 0) + 4, length);
    if (!(length & 0x80000000)) {
        count = 0x800000;
        for (;;) {
            RECOVERY_LOAD_LE32(sg->virtualAddress + 8 * index + 4, length);
            residue += length & 0xffffff;
            if (length & 0x80000000)
                break;
            if (!--count)
                break;
            ++index;
        }
    }
    return residue;
}

unsigned int SCSIhSwappingAdvResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    AdaptecU2BufferDescriptor *sg;
    unsigned int residue, address, current, count, index = 0, length;
    unsigned char state, cache;
    if (OSMReadUExact8(*handle, 175) & 1)
        return 0;
    if (OSMReadUExact8(*handle, 174) & 0x1f) {
        residue = SCSIhGetEntity32FromScb(hhcb, 164) & 0xffffff;
        address = SCSIhGetAddressScbBA32(hhcb, 176);
        cache = OSMReadUExact8(*handle, 175);
        state = OSMReadUExact8(*handle, 175);
    } else {
        residue = SCSIhGetEntity32FromScb(hhcb, 184) & 0xffffff;
        address = SCSIhGetAddressScbBA32(hhcb, 189);
        state = OSMReadUExact8(*handle, 188);
        cache = state;
    }
    if (state & 2)
        return residue;
    sg = OSDGetSGList(hiob);
    current = sg->busAddress;
    count = 0x800000;
    while (SCSIhCompareBusAddress(address, current)) {
        if (!--count)
            break;
        OSDAdjustBusAddress(hhcb, &current, 8);
        ++index;
    }
    index += cache >> 3;
    RECOVERY_LOAD_LE32(sg->virtualAddress + 8 * (index ? index - 1 : 0) + 4, length);
    if (!(length & 0x80000000)) {
        count = 0x800000;
        for (;;) {
            RECOVERY_LOAD_LE32(sg->virtualAddress + 8 * index + 4, length);
            residue += length & 0xffffff;
            if (length & 0x80000000)
                break;
            if (!--count)
                break;
            ++index;
        }
    }
    return residue;
}

void SCSIhStandard64ActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char saved, value;
    if (hiob->control.bytes.scbNumber == OSMReadUExact8(*handle, 53)) {
        if ((OSMReadUExact8(*handle, 235) & 8) ||
            (OSMReadUExact8(*handle, 238) & 0x18) ||
            (OSMReadUExact8(*handle, 147) & 0x38)) {
            hiob->status = 0;
            hiob->managerStatus = 1;
            return;
        }
    }
    if ((OSMReadUExact8(*handle, 0) & 0x40) &&
        hiob->control.bytes.scbNumber == OSMReadUExact8(*handle, 52)) {
        hiob->managerStatus = 2;
        saved = OSMReadUExact8(*handle, 144);
        OSMWriteUExact8(*handle, 144, hiob->control.bytes.scbNumber);
        value = OSMReadUExact8(*handle, 195);
        OSMWriteUExact8(*handle, 195, value | 8);
        OSMWriteUExact8(*handle, 144, saved);
        return;
    }
    if (!SCSIhStandard64SearchExeQ(hhcb, hiob, hiob->hostStatus, 1) &&
        !SCSIhStandardSearchSeqDoneQ(hhcb, hiob, 1) &&
        !SCSIhStandardSearchDoneQ(hhcb, hiob)) {
        saved = OSMReadUExact8(*handle, 144);
        OSMWriteUExact8(*handle, 144, hiob->control.bytes.scbNumber);
        value = OSMReadUExact8(*handle, 195);
        OSMWriteUExact8(*handle, 195, value | 8);
        value = OSMReadUExact8(*handle, 172);
        OSMWriteUExact8(*handle, 172, value | 8);
        OSMWriteUExact8(*handle, 175, 0);
        OSMWriteUExact8(*handle, 176, (hiob->control.flags & 0x4000) ? 13 : 6);
        SCSIhStandard64QHead(hhcb, hiob);
        OSMWriteUExact8(*handle, 144, saved);
        hiob->managerStatus = 5;
    }
}

void SCSIhStandardAdvActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char saved, value;
    if (hiob->control.bytes.scbNumber == OSMReadUExact8(*handle, 61)) {
        if ((OSMReadUExact8(*handle, 235) & 8) ||
            (OSMReadUExact8(*handle, 238) & 0x18) ||
            (OSMReadUExact8(*handle, 147) & 0x38)) {
            hiob->status = 0;
            hiob->managerStatus = 1;
            return;
        }
    }
    if ((OSMReadUExact8(*handle, 0) & 0x40) &&
        hiob->control.bytes.scbNumber == OSMReadUExact8(*handle, 60)) {
        hiob->managerStatus = 2;
        saved = OSMReadUExact8(*handle, 144);
        OSMWriteUExact8(*handle, 144, hiob->control.bytes.scbNumber);
        value = OSMReadUExact8(*handle, 160);
        OSMWriteUExact8(*handle, 160, value | 16);
        OSMWriteUExact8(*handle, 144, saved);
        return;
    }
    if (!SCSIhStandardAdvSearchExeQ(hhcb, hiob, hiob->hostStatus, 1) &&
        !SCSIhStandardAdvSearchSeqDoneQ(hhcb, hiob, 1) &&
        !SCSIhStandardSearchDoneQ(hhcb, hiob)) {
        saved = OSMReadUExact8(*handle, 144);
        OSMWriteUExact8(*handle, 144, hiob->control.bytes.scbNumber);
        value = OSMReadUExact8(*handle, 160);
        OSMWriteUExact8(*handle, 160, value | 16);
        value = OSMReadUExact8(*handle, 160);
        OSMWriteUExact8(*handle, 160, value | 8);
        OSMWriteUExact8(*handle, 168, 0);
        OSMWriteUExact8(*handle, 169, (hiob->control.flags & 0x4000) ? 13 : 6);
        SCSIhStandardAdvQHead(hhcb, hiob);
        OSMWriteUExact8(*handle, 144, saved);
        hiob->managerStatus = 5;
    }
}

void SCSIhSwappingAdvActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char saved, value;
    if (hiob->control.bytes.scbNumber == OSMReadUExact8(*handle, 58)) {
        if ((OSMReadUExact8(*handle, 235) & 8) ||
            (OSMReadUExact8(*handle, 238) & 0x18) ||
            (OSMReadUExact8(*handle, 147) & 0x38)) {
            hiob->status = 0;
            hiob->managerStatus = 1;
            return;
        }
    }
    if ((OSMReadUExact8(*handle, 0) & 0x40) &&
        hiob->control.bytes.scbNumber == OSMReadUExact8(*handle, 57)) {
        saved = OSMReadUExact8(*handle, 144);
        OSMWriteUExact8(*handle, 144, saved ^ 1);
        value = OSMReadUExact8(*handle, 198);
        OSMWriteUExact8(*handle, 198, value | 16);
        OSMWriteUExact8(*handle, 144, saved);
        hiob->managerStatus = 2;
        return;
    }
    if ((OSMReadUExact8(*handle, 238) & 0x1c) == 0x1c) {
        if (OSMReadUExact8(*handle, 58) == hiob->control.bytes.scbNumber) {
            saved = OSMReadUExact8(*handle, 144);
            value = OSMReadUExact8(*handle, 241);
            OSMWriteUExact8(*handle, 144, value);
            value = OSMReadUExact8(*handle, 198);
            OSMWriteUExact8(*handle, 198, value | 0x10);
            OSMWriteUExact8(*handle, 144, saved);
        }
        hiob->managerStatus = 2;
        return;
    }
    if (!SCSIhStandardSearchDoneQ(hhcb, hiob)) {
        volatile unsigned char *scb = hiob->scb->virtualAddress;
        volatile unsigned char *control = scb + 38;
        value = scb[38];
        *control = value | 0x10;
        *control = value | 0x18;
        scb[16] = 0;
        scb[17] = (hiob->control.flags & 0x4000) ? 13 : 6;
        SCSIhSwappingAdvQHead(hhcb, hiob);
        flush_cache((vm_offset_t)scb, 64);
        hiob->managerStatus = 5;
    }
}

void SCSIhSwapping32ActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char saved, value;
    if ((OSMReadUExact8(*handle, 0) & 0x40) &&
        hiob->control.bytes.scbNumber == OSMReadUExact8(*handle, 86)) {
        saved = OSMReadUExact8(*handle, 144);
        OSMWriteUExact8(*handle, 144, 1);
        value = OSMReadUExact8(*handle, 160);
        OSMWriteUExact8(*handle, 160, value | 8);
        OSMWriteUExact8(*handle, 144, saved);
        hiob->managerStatus = 2;
    } else if (!SCSIhStandardSearchDoneQ(hhcb, hiob)) {
        volatile unsigned char *scb = hiob->scb->virtualAddress;
        unsigned char control;
        value = scb[0];
        control = scb[1];
        scb[0] = value | 8;
        scb[1] = control | 8;
        scb[4] = 0;
        scb[5] = (hiob->control.flags & 0x4000) ? 13 : 6;
        SCSIhSwapping32QHead(hhcb, hiob);
        flush_cache((vm_offset_t)scb, 32);
        hiob->managerStatus = 5;
    }
}

void SCSIhIntSelto(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned char value;
    if ((hiob->control.flags & 0x800) && !(unit->resource->freezeMask & 0x20)) {
        if (hhcb->firmware->freezeHWQueue)
            hhcb->firmware->freezeHWQueue(hhcb, hiob);
    }
    if (*((unsigned char *)unit->device + 4) & 0x81)
        hhcb->firmware->xferOptAssign(hhcb, unit->target, 143);
    value = OSMReadUExact8(*handle, 0);
    OSMWriteUExact8(*handle, 0, value & 0xb7);
    OSMWriteUExact8(*handle, 12, 0x88);
    if (hiob != (AdaptecU2HIOB *)-1) {
        hhcb->firmware->targetClearBusy(hhcb, hiob);
        hiob->hostStatus = 17;
        SCSIhTerminateCommand(hiob);
    }
}

void SCSIhIntFree(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char value;
    OSMWriteUExact8(*handle, 147, 1);
    value = OSMReadUExact8(*handle, 1);
    OSMWriteUExact8(*handle, 1, value | 0x1a);
    value = OSMReadUExact8(*handle, 17);
    OSMWriteUExact8(*handle, 17, value & ~8);
    OSMWriteUExact8(*handle, 4, 0);
    OSMWriteUExact8(*handle, 12, 8);
    OSMWriteUExact8(*handle, 98, hhcb->firmware->word20 >> 2);
    OSMWriteUExact8(*handle, 99, hhcb->firmware->word20 >> 10);
    if (hiob != (AdaptecU2HIOB *)-1) {
        if ((hiob->control.flags & 0x800) && !(hiob->context.unit->resource->freezeMask & 0x20)) {
            if (hhcb->firmware->freezeHWQueue)
                hhcb->firmware->freezeHWQueue(hhcb, hiob);
        }
        hhcb->firmware->targetClearBusy(hhcb, hiob);
        hiob->hostStatus = 19;
        SCSIhTerminateCommand(hiob);
    }
}

void SCSIhParityError(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char value;
    if (hiob == (AdaptecU2HIOB *)-1) {
        value = OSMReadUExact8(*handle, 2);
        OSMWriteUExact8(*handle, 2, value & ~0x20);
        OSMWriteUExact8(*handle, 2, value | 0x20);
        OSMWriteUExact8(*handle, 12, 68);
        OSMWriteUExact8(*handle, 146, 4);
        SCSIhBadSeq(hhcb);
    } else {
        if ((hiob->control.flags & 0x800) && !(hiob->context.unit->resource->freezeMask & 0x20)) {
            if (hhcb->firmware->freezeHWQueue)
                hhcb->firmware->freezeHWQueue(hhcb, hiob);
        }
        hiob->bytes28[4] = 5;
        if ((OSMReadUExact8(*handle, 3) & 0xe0) == 0xe0)
            hiob->bytes28[4] = 9;
        if ((unsigned int)hhcb->firmwareMode - 4 <= 1)
            hiob->bytes28[3] = OSMReadUExact8(*handle, 12) & 0x10;
        SCSIhWait4Req(hhcb);
        value = OSMReadUExact8(*handle, 2);
        OSMWriteUExact8(*handle, 2, value & ~0x20);
        hiob->hostStatus = 72;
    }
}

void SCSIhCheckCondition(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned int count = 0x800000;
    unsigned char status, value;
    if (hiob->managerStatus == 7) {
        hiob->hostStatus = 27;
        status = 0;
    } else {
        status = OSMReadUExact8(*handle, hhcb->firmware->registers[2]);
        hiob->targetStatus = status;
    }
    if (((hiob->control.flags & 0x800) || status == 8 || status == 40) &&
        !(hiob->context.unit->resource->freezeMask & 0x20)) {
        if (hhcb->firmware->freezeHWQueue)
            hhcb->firmware->freezeHWQueue(hhcb, hiob);
    }
    if (status == 2 && (hiob->control.flags & 0x1000)) {
        hiob->negotiationState = 0;
        hhcb->firmware->requestSense(hhcb, hiob);
    } else {
        hhcb->firmware->targetClearBusy(hhcb, hiob);
        SCSIhTerminateCommand(hiob);
    }
    if (status == 2 && (*((unsigned char *)unit->device + 4) & 0x81))
        hhcb->firmware->xferOptAssign(hhcb, unit->target, 143);
    OSMWriteUExact8(*handle, 147, 0);
    value = OSMReadUExact8(*handle, 1);
    OSMWriteUExact8(*handle, 1, (value & 0xdd) | 2);
    value = OSMReadUExact8(*handle, 17);
    OSMWriteUExact8(*handle, 17, value & ~8);
    OSMReadUExact8(*handle, 6);
    do {
        if (!(OSMReadUExact8(*handle, 11) & 0x40))
            break;
    } while (count--);
    OSMWriteUExact8(*handle, 4, 0);
    OSMWriteUExact8(*handle, 98, ((const unsigned char *)hhcb->firmware)[35] >> 2);
    OSMWriteUExact8(*handle, 99, 0);
}

void SCSIhCdbAbort(AdaptecU2HHCB *hhcb)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char phase, address, value;
    if ((OSMReadUExact8(*handle, 3) & 0xe0) != 0xe0) {
        SCSIhBadSeq(hhcb);
        return;
    }
    if (OSMReadUExact8(*handle, 18) == 3) {
        OSMWriteUExact8(*handle, 3, 0xe0);
        value = OSMReadUExact8(*handle, 1);
        OSMWriteUExact8(*handle, 1, value | 0x12);
        OSMReadUExact8(*handle, 6);
        address = ((const unsigned char *)hhcb->firmware)[19];
    } else {
        OSMWriteUExact8(*handle, 3, 0xf0);
        do {
            OSMReadUExact8(*handle, 6);
            phase = SCSIhWait4Req(hhcb);
        } while (phase == 0xe0);
        if (phase != 0xa0) {
            SCSIhBadSeq(hhcb);
            return;
        }
        OSMWriteUExact8(*handle, 3, 0xa0);
        OSMWriteUExact8(*handle, 12, 64);
        OSMWriteUExact8(*handle, 6, 7);
        SCSIhWait4Req(hhcb);
        address = ((const unsigned char *)hhcb->firmware)[47];
    }
    OSMWriteUExact8(*handle, 98, address >> 2);
    OSMWriteUExact8(*handle, 99, 0);
}

void SCSIhBadSeq(AdaptecU2HHCB *hhcb)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    if ((SCSIhReadINTSTAT(hhcb) & 4) && (OSMReadUExact8(*handle, 12) & 8)) {
        OSMWriteUExact8(*handle, 98, ((const unsigned char *)hhcb->firmware)[35] >> 2);
        OSMWriteUExact8(*handle, 99, 0);
    } else {
        SCSIrAsyncEvent(hhcb, 6);
        SCSIhResetScsi(hhcb);
        SCSIhDelayCount500us(hhcb, 4000);
        SCSIhResetChannelHardware(hhcb);
        SCSIhAbortChannel(hhcb, 20);
        hhcb->firmware->resetSoftware(hhcb);
        OSMWriteUExact8(*handle, 98, ((const unsigned char *)hhcb->firmware)[35] >> 2);
        OSMWriteUExact8(*handle, 99, 0);
        OSMWriteUExact8(*handle, 146, 5);
        SCSIhWriteHCNTRL(hhcb, *((unsigned char *)hhcb + 221) & 2);
        __asm__ volatile ("sync" : : : "memory");
        SCSIrAsyncEvent(hhcb, 3);
        SCSIrAsyncEvent(hhcb, 7);
    }
}

void SCSIhIntSrst(AdaptecU2HHCB *hhcb)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned int count = 0x800000, i;
    do {
        if (!(OSMReadUExact8(*handle, 12) & 0x20))
            break;
        OSMWriteUExact8(*handle, 12, 32);
    } while (count--);
    SCSIrAsyncEvent(hhcb, 6);
    SCSIhResetChannelHardware(hhcb);
    SCSIhAbortChannel(hhcb, 7);
    hhcb->firmware->resetSoftware(hhcb);
    if (OSMReadUExact8(*handle, 3))
        SCSIhResetScsi(hhcb);
    if (hhcb->firmware->stackBugFix)
        hhcb->firmware->stackBugFix(hhcb);
    hhcb->flags = (hhcb->flags & 0xbfefffff) | 0x40000000;
    for (i = 0; i < 16; ++i)
        hhcb->devices[i].flags |= 4;
    for (i = 0; i < 4000; ++i) {
        if (SCSIhReadINTSTAT(hhcb) & 13) {
            if (hhcb->hardware->seqStretchWorkaround)
                hhcb->hardware->seqStretchWorkaround(hhcb);
            SCSIhResetChannelHardware(hhcb);
            OSMWriteUExact8(*handle, 12, 32);
            OSMWriteUExact8(*handle, 146, 5);
        }
        SCSIhDelayCount500us(hhcb, 1);
    }
    OSMWriteUExact8(*handle, 98, ((const unsigned char *)hhcb->firmware)[35] >> 2);
    OSMWriteUExact8(*handle, 99, 0);
    SCSIhWriteHCNTRL(hhcb, *((unsigned char *)hhcb + 221) & 2);
    __asm__ volatile ("sync" : : : "memory");
    SCSIrAsyncEvent(hhcb, 1);
    SCSIrAsyncEvent(hhcb, 7);
}

void SCSIhIntIOError(AdaptecU2HHCB *hhcb)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned int i;
    OSMWriteUExact8(*handle, 11, 8);
    SCSIrAsyncEvent(hhcb, 6);
    SCSIhResetScsi(hhcb);
    SCSIhResetChannelHardware(hhcb);
    SCSIhAbortChannel(hhcb, 9);
    hhcb->firmware->resetSoftware(hhcb);
    hhcb->flags = (hhcb->flags & 0xbfefffff) | 0x40000000;
    for (i = 0; i < 4000; ++i) {
        if (SCSIhReadINTSTAT(hhcb) & 13) {
            SCSIhResetChannelHardware(hhcb);
            OSMWriteUExact8(*handle, 146, 5);
        }
        SCSIhDelayCount500us(hhcb, 1);
    }
    OSMWriteUExact8(*handle, 98, ((const unsigned char *)hhcb->firmware)[35] >> 2);
    OSMWriteUExact8(*handle, 99, 0);
    SCSIhWriteHCNTRL(hhcb, *((unsigned char *)hhcb + 221) & 2);
    __asm__ volatile ("sync" : : : "memory");
    SCSIrAsyncEvent(hhcb, 8);
    SCSIrAsyncEvent(hhcb, 7);
}
