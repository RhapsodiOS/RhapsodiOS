#include "AdaptecU2CHIMPrivate.h"

extern void *memset(void *, int, unsigned int);
extern void flush_cache(unsigned int, unsigned int);

void SCSIxMaximizeMemory(AdaptecU2MemoryDescriptor *destination,
                        const AdaptecU2MemoryDescriptor *source)
{
    int i;
    for (i = 0; i <= 5; ++i) {
        if (destination[i].size < source[i].size)
            destination[i].size = source[i].size;
        if (destination[i].alignmentMask < source[i].alignmentMask)
            destination[i].alignmentMask = source[i].alignmentMask;
    }
}

unsigned int SCSIxNonScamValidateLun(AdaptecU2TargetTSCB *target)
{
    return SCSIxChkLunExist(target->adapter->currentLuns, target->target, 0)
        ? 0 : 2;
}

unsigned int SCSIxApplyNVData(AdaptecU2AdapterTSCB *adapter)
{
    adapter->nvTargetMask = 0xffff;
    return 1;
}

unsigned int SCSIxBiosExist(AdaptecU2AdapterTSCB *adapter)
{
    return 0;
}

unsigned int SCSIxOptimaExist(AdaptecU2AdapterTSCB *adapter)
{
    return 0;
}

unsigned int SCSIxChkLunExist(const unsigned char *bitmap,
                             unsigned int target, unsigned int lun)
{
    unsigned int bit = (target << 6) + lun;
    return (bitmap[bit >> 3] >> (bit & 7)) & 1;
}

void SCSIxSetLunExist(unsigned char *bitmap, unsigned int target,
                     unsigned int lun)
{
    unsigned int bit = (target << 6) + lun;
    bitmap[bit >> 3] |= 1 << (bit & 7);
}

void SCSIxClearLunExist(unsigned char *bitmap, unsigned int target,
                       unsigned int lun)
{
    unsigned int bit = (target << 6) + lun;
    bitmap[bit >> 3] &= ~(1 << (bit & 7));
}

unsigned int SCSIxPostQueueSpecialIOB(AdaptecU2IOB *iob)
{
    return iob->status != 1;
}

unsigned int SCSIxGetSpeed(unsigned short rate, unsigned char fastMode)
{
    unsigned int option = rate & 0x70;
    if (fastMode) {
        if (option == 0) return 200;
        if (option == 0x10) return 160;
        if (option == 0x20) return 133;
    } else {
        if (option == 0) return 100;
        if (option == 0x10) return 80;
        if (option == 0x20) return 67;
        if (option == 0x30) return 57;
        if (option == 0x40) return 50;
        if (option == 0x50) return 44;
        if (option == 0x60) return 40;
    }
    return 36;
}

unsigned int SCSIxCalcScsiOption(unsigned int speed, unsigned int offset,
                                unsigned int width)
{
    unsigned int option = 0;
    if (speed != 200) {
        if (speed - 160 <= 39 || speed - 80 <= 19) option = 0x10;
        else if (speed - 133 <= 26 || speed - 67 <= 12) option = 0x20;
        else if (speed - 100 <= 32) option = 0;
        else if (speed - 57 <= 9) option = 0x30;
        else if (speed - 50 <= 6) option = 0x40;
        else if (speed - 44 <= 5) option = 0x50;
        else if (speed - 40 <= 3) option = 0x60;
        else if (speed - 36 <= 3) option = 0x70;
    }
    option |= offset & 15;
    return width == 16 ? (unsigned char)option | 0x80 : option;
}

unsigned char SCSIxDetermineFirmwareMode(AdaptecU2AdapterTSCB *adapter)
{
    SCSIHSetupHardware(&adapter->hhcb);
    if ((adapter->productID & 0xff80ffff) == 0x9005)
        return SCSIHExtScbRAMAvail(&adapter->hhcb) ? 4 : 5;
    if ((adapter->productID & 0xfff0ffff) == 0x78909004)
        return SCSIHExtScbRAMAvail(&adapter->hhcb) ? 0 : 3;
    return 3;
}

unsigned int SCSIxGetNextSubSystemSubVendorID(unsigned int index,
                                             unsigned int *mask)
{
    if (index <= 13) {
        *mask = SCSISubSystemSubVendorType[index][1];
        return SCSISubSystemSubVendorType[index][0];
    }
    return 0;
}

void SCSIxSetupBusScan(AdaptecU2AdapterTSCB *adapter)
{
    unsigned int i;
    memset(adapter->currentLuns, 0, 128);
    memset(&adapter->scanTarget, 0, 40);
    adapter->scanTarget.type = 2;
    adapter->scanTarget.adapter = adapter;
    if (adapter->scanTarget.target == adapter->hhcb.hostID)
        ++adapter->scanTarget.target;
    adapter->taggedTargets = 0;
    adapter->scanRetry = 0;
    if (adapter->hhcb.flags & 0x20000) {
        for (i = 0; i <= 15; ++i)
            adapter->hhcb.devices[i].flags &= 0xffe7;
        SCSIHEnableExpStatus(&adapter->hhcb);
    }
}

void SCSIxSetupLunProbe(AdaptecU2AdapterTSCB *adapter, unsigned char target,
                       unsigned char lun)
{
    unsigned int shift = target & 31;
    unsigned int mask = (0xfffffffeU << shift) |
        (shift ? 0xfffffffeU >> (32 - shift) : 0);
    SCSIxClearLunExist(adapter->currentLuns, target, lun);
    SCSIxClearLunExist(adapter->previousLuns, target, lun);
    memset(&adapter->scanTarget, 0, 40);
    adapter->scanTarget.target = target;
    adapter->scanTarget.lun = lun;
    adapter->scanTarget.type = 2;
    adapter->scanTarget.adapter = adapter;
    adapter->scanRetry = 0;
    adapter->taggedTargets &= (unsigned char)mask;
}

void SCSIxTranslateError(AdaptecU2IOB *iob, const AdaptecU2HIOB *hiob)
{
    unsigned int status;
    if (hiob->status == 2) {
        switch (hiob->hostStatus) {
        case 4: status = 64; break;
        case 5: status = 66; break;
        case 6: status = 65; break;
        case 7: status = 67; break;
        case 8: status = 69; break;
        case 9: status = 75; break;
        case 0x14: case 0x20: status = 80; break;
        default: return;
        }
    } else if (hiob->status == 3) {
        switch (hiob->hostStatus) {
        case 0: case 0x12:
            switch (hiob->targetStatus) {
            case 0: case 4: case 0x10: case 0x14:
                if (hiob->hostStatus != 0x12) { status = 1; break; }
                iob->status = 36;
                iob->residualLength = hiob->residualLength;
                return;
            case 2:
                if (!(iob->flags & 0x80000000)) iob->status = 3;
                else {
                    iob->status = 2;
                    iob->residualSense = hiob->residualSense;
                    if (iob->senseLength > 255)
                        iob->residualSense = hiob->residualSense - 255 + iob->senseLength;
                }
                if (hiob->hostStatus == 0x12)
                    iob->residualLength = hiob->residualLength;
                return;
            case 8: status = 48; break;
            case 0x18: status = 50; break;
            case 0x28: status = 49; break;
            default: status = 96; break;
            }
            break;
        case 0x11: status = 32; break;
        case 0x13: status = 34; break;
        case 0x14: case 0x20: status = 80; break;
        case 0x1b: status = 5; break;
        case 0x24: status = 72; break;
        case 0x26: status = 74; break;
        case 0x48: status = 35; break;
        default: return;
        }
    } else if (hiob->status == 0 && hiob->hostStatus == 0x25) status = 73;
    else return;
    iob->status = status;
}

void SCSIxQueueBusScan(AdaptecU2AdapterTSCB *adapter)
{
    AdaptecU2IOB *iob = adapter->scanIOB;
    unsigned int probe = adapter->scanOrigin->function == 19;
    unsigned int address;
    memset(iob, 0, 108);
    iob->reserve.size = 88;
    iob->reserve.virtualAddress = adapter->scanBuffer + 72;
    iob->reserve.busAddress = adapter->osm.OSMGetBusAddress(adapter->osmContext,
        1, iob->reserve.virtualAddress);
    memset(iob->reserve.virtualAddress, 0, 88);
    SCSIRSetUnitHandle(&adapter->hhcb, &adapter->scanTarget.unit,
        (unsigned char)adapter->scanTarget.target, (unsigned char)adapter->scanTarget.lun);
    iob->post = SCSIxPostBusScan;
    iob->function = 0;
    iob->taskSet.target = &adapter->scanTarget;
    iob->flags |= 0x80000000;
    iob->cdbLength = 6;
    iob->cdb = (unsigned char *)adapter->scanIOB + 108;
    iob->senseLength = 32;
    iob->taskAttribute = 0;
    iob->sense = adapter->scanBuffer + 40;
    adapter->scanTarget.flags &= ~0x80000000;
    iob->cdb[0] = 18;
    iob->cdb[1] = 0;
    iob->cdb[2] = 0;
    iob->cdb[3] = 0;
    iob->cdb[4] = 32;
    iob->cdb[5] = 0;
    iob->data.size = 8;
    iob->data.virtualAddress = adapter->scanBuffer;
    iob->data.busAddress = adapter->osm.OSMGetBusAddress(adapter->osmContext,
        1, iob->data.virtualAddress);
    address = adapter->osm.OSMGetBusAddress(adapter->osmContext, 1,
        adapter->scanBuffer + 8);
    *(unsigned int *)iob->data.virtualAddress = (address << 24) |
        ((address & 0xff00) << 8) | ((address >> 8) & 0xff00) | (address >> 24);
    *(unsigned int *)(iob->data.virtualAddress + 4) = 0x20000080;
    flush_cache((unsigned int)iob->data.virtualAddress, 64);
    if ((adapter->scanTarget.lun == 0 && !probe) || probe) {
        if ((!probe && ((adapter->hhcb.flags & 0x40000000) ||
             (adapter->hhcb.flags & 0x700000) == 0x200000)) ||
            (probe && (adapter->hhcb.devices[adapter->scanTarget.target].flags & 4))) {
            adapter->hhcb.devices[adapter->scanTarget.target].flags &= ~0x40;
            adapter->hhcb.devices[adapter->scanTarget.target].flags &= ~0x20;
            SCSIHSuppressNegotiation(&adapter->scanTarget.unit);
        } else SCSIHForceNegotiation(&adapter->scanTarget.unit);
    }
    SCSIQueueIOB(iob);
}

void SCSIxQueueSpecialIOB(AdaptecU2AdapterTSCB *adapter, unsigned int function)
{
    AdaptecU2IOB *iob = adapter->scanIOB;
    memset(iob, 0, 108);
    iob->reserve.size = 88;
    iob->reserve.virtualAddress = adapter->scanBuffer + 72;
    iob->reserve.busAddress = adapter->osm.OSMGetBusAddress(adapter->osmContext,
        1, iob->reserve.virtualAddress);
    memset(iob->reserve.virtualAddress, 0, 72);
    SCSIRSetUnitHandle(&adapter->hhcb, &adapter->scanTarget.unit,
        (unsigned char)adapter->scanTarget.target, (unsigned char)adapter->scanTarget.lun);
    iob->function = function;
    iob->taskSet.target = &adapter->scanTarget;
    iob->post = SCSIxPostQueueSpecialIOB;
    SCSIQueueIOB(iob);
}

unsigned int SCSIxPostBusScan(AdaptecU2IOB *iob)
{
    AdaptecU2TargetTSCB *target = iob->taskSet.target;
    AdaptecU2AdapterTSCB *adapter = target->adapter;
    unsigned int restrictLuns = 0;
    unsigned int probe = adapter->scanOrigin->function == 19;
    volatile unsigned char qualifier;
    unsigned char capabilities;
    unsigned int nextLun;
    switch (iob->status) {
    case 1: case 0x24:
        if (target->lun != 0 && !probe) {
            qualifier = adapter->scanBuffer[8];
            if (qualifier == 127) target->lun = adapter->lunCounts[target->target];
            else SCSIxSetLunExist(adapter->currentLuns, target->target, target->lun);
        } else {
            qualifier = adapter->scanBuffer[8];
            if (probe && qualifier == 127)
                target->lun = adapter->lunCounts[target->target];
            else {
                SCSIxSetLunExist(adapter->currentLuns, target->target, target->lun);
                if (!probe) adapter->hhcb.devices[target->target].flags &= ~4;
            }
            capabilities = adapter->scanBuffer[15];
            if (!(capabilities & 0x20) && !(adapter->hhcb.devices[target->target].flags & 0x20)) {
                adapter->hhcb.devices[target->target].rate &= ~0x80;
                adapter->hhcb.devices[target->target].flags &= ~0x80;
            }
            if (!(capabilities & 0x10) && !(adapter->hhcb.devices[target->target].flags & 0x40)) {
                adapter->hhcb.devices[target->target].rate &= 0xf0;
                adapter->hhcb.devices[target->target].flags &= ~0x100;
            }
            if (capabilities & 2) adapter->taggedTargets |= 1 << target->target;
        }
        if ((adapter->scanBuffer[10] & 7) <= 2) {
            restrictLuns = 1;
            if (adapter->scanBuffer[10] & 1)
                adapter->taggedTargets &= ~(1 << target->target);
        }
        goto advance;
    case 0x20:
        target->lun = adapter->lunCounts[target->target];
        goto advance;
    case 0x30:
        SCSIRFreeUnitHandle(&adapter->hhcb);
        SCSIxQueueSpecialIOB(adapter, 11);
        if (adapter->scanOrigin->function == 19) goto advance;
        break;
    case 0x42: case 0x43: case 0x4b: case 0x50:
        if (adapter->hhcb.flags & 0x20000) SCSIHDisableExpStatus(&adapter->hhcb);
        adapter->scanOrigin->status = iob->status == 0x42 ? 66 :
            iob->status == 0x50 ? 80 : 67;
        adapter->scanOrigin->post(adapter->scanOrigin);
        return 0;
    }
    if (!adapter->scanRetry) {
        SCSIRFreeUnitHandle(&adapter->hhcb);
        ++adapter->scanRetry;
        SCSIxQueueBusScan(adapter);
        return 0;
    }
advance:
    SCSIRFreeUnitHandle(&adapter->hhcb);
    nextLun = ++target->lun;
    if (probe) {
        if (adapter->hhcb.devices[target->target].flags & 4)
            SCSIHForceNegotiation(&target->unit);
        if (iob->status == 1 || iob->status == 36) {
            adapter->hhcb.devices[target->target].flags &= ~4;
            if (SCSIxChkLunExist(adapter->currentLuns, adapter->lastTarget, adapter->lastLun) ==
                SCSIxChkLunExist(adapter->previousLuns, adapter->lastTarget, adapter->lastLun))
                adapter->scanOrigin->status = qualifier == 127 ? 37 : 32;
            else adapter->scanOrigin->status = 1;
        } else adapter->scanOrigin->status = iob->status;
        adapter->scanOrigin->post(adapter->scanOrigin);
    } else {
        if (!(adapter->nvTargetMask & (1 << target->target)) ||
            (restrictLuns && nextLun > 7) || nextLun >= adapter->lunCounts[target->target]) {
            if ((adapter->hhcb.flags & 0x40000000) ||
                (adapter->hhcb.flags & 0x700000) == 0x200000)
                SCSIHForceNegotiation(&target->unit);
            target->lun = 0;
            ++target->target;
            if (target->target == adapter->hhcb.hostID) ++target->target;
        }
        if (target->target < adapter->hhcb.maxDevices) {
            adapter->scanRetry = 0;
            SCSIxQueueBusScan(adapter);
        } else {
            adapter->hhcb.flags &= ~0x40000000;
            if (adapter->hhcb.flags & 0x20000) SCSIHDisableExpStatus(&adapter->hhcb);
            adapter->scanOrigin->status = 1;
            adapter->scanOrigin->post(adapter->scanOrigin);
            if (adapter->flags & 0x40000000) OSDAsyncEvent(&adapter->hhcb, 7);
        }
    }
    return 0;
}
