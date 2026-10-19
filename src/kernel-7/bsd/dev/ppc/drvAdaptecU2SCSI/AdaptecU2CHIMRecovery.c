#include "AdaptecU2CHIMPrivate.h"

void SCSIhSetStat(AdaptecU2HIOB *hiob)
{
    unsigned char host = hiob->hostStatus;
    unsigned char target = hiob->targetStatus;
    if (host == 0 && (target == 0 || target == 4 || target == 16 || target == 20))
        hiob->status = 1;
    else if (hiob->status != 2) {
        if ((host == 4 || host == 8) &&
            (target == 0 || target == 4 || target == 16 || target == 20))
            hiob->status = 1;
        else
            hiob->status = 3;
    } else if (host != 4 && host != 8)
        hiob->status = 3;
    else if (target != 0 && target != 4 && target != 16 && target != 20) {
        hiob->hostStatus = 0;
        hiob->status = 3;
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
    unsigned char first = current, previous, next;
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
