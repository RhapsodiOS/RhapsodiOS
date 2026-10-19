#include "AdaptecU2CHIMPrivate.h"
#include <machdep/ppc/pmap.h>

unsigned short SCSIhAIC78XXCalcScsiRate(AdaptecU2HHCB *hhcb,
                                     unsigned char period, unsigned char offset)
{
    unsigned char rate;
    if (period == 12) rate = 0;
    else if (period <= 16) rate = 16;
    else if (period <= 20) rate = 32;
    else if (period <= 25) rate = 0;
    else if (period <= 31) rate = 16;
    else if (period <= 37) rate = 32;
    else if (period <= 43) rate = 48;
    else if (period <= 50) rate = 64;
    else if (period <= 56) rate = 80;
    else if (period <= 62) rate = 96;
    else rate = 112;
    return rate | offset;
}

unsigned short SCSIhAICBayonetCalcScsiRate(AdaptecU2HHCB *hhcb,
                                       unsigned char period, unsigned char offset)
{
    unsigned int rate;
    switch (period) {
    case 10: rate = 19; break;
    case 11: rate = 20; break;
    case 12: rate = 21; break;
    default:
        if (period <= 16) rate = 22;
        else if (period <= 19) rate = 23;
        else if (period <= 25) rate = 24;
        else if (period <= 31) rate = 25;
        else if (period <= 37) rate = 26;
        else if (period <= 43) rate = 27;
        else rate = 28;
    }
    return rate | (unsigned short)(offset << 8);
}

unsigned char SCSIhAIC78XXGetXferPeriod(AdaptecU2HHCB *hhcb,
                                     AdaptecU2HIOB *hiob)
{
    AdaptecU2DeviceTable *device = hiob->context.unit->device;
    unsigned int rate = device->rate, index = (rate >> 4) & 7;
    if (device->flags & 0x8000) {
        switch (index) {
        case 0: return 12;
        case 1: return 16;
        case 2: case 3: return 19;
        default: return 25;
        }
    }
    return (unsigned char)(6 * index + ((rate & 0x40) ? 26 : 25));
}

unsigned char SCSIhAICBayonetGetXferPeriod(AdaptecU2HHCB *hhcb,
                                       AdaptecU2HIOB *hiob)
{
    unsigned char rate = hiob->context.unit->device->period, period;
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    if ((unsigned int)((rate & 0x7f) - 19) > 9)
        return 25;
    if (rate & 8) {
        period = 6 * (rate & 7) + 25;
        if (rate & 4) period = 6 * (rate & 7) + 26;
    } else {
        period = 3 * ((rate & 7) - 1);
        if ((rate & 6) == 6) ++period;
        if ((rate & 0x7f) == 19) period = 10;
        else if ((rate & 0x7f) == 20) period = 11;
        if (((OSMReadUExact8(*handle, 13) & 0x10) ||
             (OSMReadUExact8(*handle, 31) & 4)) && period <= 11)
            return 12;
    }
    return period;
}

unsigned char SCSIhStandardGetFast20Reg(AdaptecU2HHCB *hhcb,
                                     unsigned char target)
{
    unsigned char bit = target, reg;
    if (target > 7) {
        reg = hhcb->firmware->registers[18];
        bit -= 8;
    } else reg = hhcb->firmware->registers[17];
    return (unsigned char)(OSMReadUExact8(*hhcb->ioHandle, reg) & (1 << bit)) != 0;
}

unsigned char SCSIhStandardAdvGetFast20Reg(AdaptecU2HHCB *hhcb,
                                        unsigned char target)
{
    return 0;
}

unsigned char SCSIhSwappingGetFast20Reg(AdaptecU2HHCB *hhcb,
                                     unsigned char target)
{
    return (hhcb->devices[target].flags & 0x2000) != 0;
}

unsigned char SCSIhSwappingAdvGetFast20Reg(AdaptecU2HHCB *hhcb,
                                        unsigned char target)
{
    return 0;
}

unsigned char SCSIhAIC78XXGetWideScsiOffset(AdaptecU2HIOB *hiob)
{
    return 8;
}

unsigned char SCSIhAIC78XXGetNarrowScsiOffset(AdaptecU2HIOB *hiob)
{
    return 15;
}

unsigned char SCSIhAICBayonetGetScsiOffset(AdaptecU2HIOB *hiob)
{
    return hiob->context.unit->device->offset;
}

void SCSIhAIC78XXClearScsiOffset(AdaptecU2HIOB *hiob)
{
    hiob->context.unit->device->rate &= 0xf0;
}

void SCSIhAICBayonetClearScsiOffset(AdaptecU2HIOB *hiob)
{
    AdaptecU2DeviceTable *device = hiob->context.unit->device;
    unsigned char offset = device->offset & 0x80;
    device->rate &= 0xf0;
    device->offset = offset;
}

unsigned int SCSIhAIC78XXWasSyncXfer(unsigned char offset)
{
    return (offset & 15) != 0;
}

unsigned int SCSIhAICBayonetWasSyncXfer(unsigned char offset)
{
    return (offset & 0x7f) != 0;
}

unsigned char SCSIhAIC78XXSetDataFifoThrshDefault(AdaptecU2HHCB *hhcb)
{
    return 3;
}

unsigned char SCSIhAIC78XXReadDataFifoThrsh(AdaptecU2HHCB *hhcb)
{
    return OSMReadUExact8(*hhcb->ioHandle, 134) >> 6;
}

void SCSIhAIC78XXUpdateDataFifoThrsh(AdaptecU2HHCB *hhcb)
{
    OSMWriteUExact8(*hhcb->ioHandle, 134, hhcb->fifoThreshold << 6);
}

unsigned char SCSIhAICBayonetSetDataFifoThrshDefault(AdaptecU2HHCB *hhcb)
{
    return 119;
}

unsigned char SCSIhAICBayonetReadDataFifoThrsh(AdaptecU2HHCB *hhcb)
{
    return OSMReadUExact8(*hhcb->ioHandle, 251);
}

void SCSIhAICBayonetUpdateDataFifoThrsh(AdaptecU2HHCB *hhcb)
{
    OSMWriteUExact8(*hhcb->ioHandle, 251, hhcb->fifoThreshold);
}

void SCSIhSwappingClearAllFast20Reg(AdaptecU2HHCB *hhcb)
{
    unsigned short target = 0;
    do {
        hhcb->devices[target].flags &= ~0x2000;
        ++target;
    } while (target <= 15);
}

void SCSIhStandard64ClearAllFast20Reg(AdaptecU2HHCB *hhcb)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    OSMWriteUExact8(*handle, hhcb->firmware->registers[17], 0);
    OSMWriteUExact8(*handle, hhcb->firmware->registers[18], 0);
}

void SCSIhStandardAdvUpdateSGLength(AdaptecU2HHCB *hhcb, unsigned int length)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    OSMWriteUExact8(*handle, 204, length);
    OSMWriteUExact8(*handle, 205, length >> 8);
    OSMWriteUExact8(*handle, 206, length >> 16);
}

void SCSIhSwappingAdvUpdateSGLength(AdaptecU2HHCB *hhcb, unsigned int length)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    OSMWriteUExact8(*handle, 164, length);
    OSMWriteUExact8(*handle, 165, length >> 8);
    OSMWriteUExact8(*handle, 166, length >> 16);
}

void SCSIhStandardAdvUpdateSGAddress(AdaptecU2HHCB *hhcb,
                                   unsigned int busAddress)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    OSMWriteUExact8(*handle, 200, busAddress);
    OSMWriteUExact8(*handle, 201, busAddress >> 8);
    OSMWriteUExact8(*handle, 202, busAddress >> 16);
    OSMWriteUExact8(*handle, 203, busAddress >> 24);
}

void SCSIhSwappingAdvUpdateSGAddress(AdaptecU2HHCB *hhcb,
                                   unsigned int busAddress)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    OSMWriteUExact8(*handle, 160, busAddress);
    OSMWriteUExact8(*handle, 161, busAddress >> 8);
    OSMWriteUExact8(*handle, 162, busAddress >> 16);
    OSMWriteUExact8(*handle, 163, busAddress >> 24);
}

void SCSIhSwapping32UpdateFast20HostMem(AdaptecU2HHCB *hhcb,
                                      AdaptecU2HIOB *hiob, unsigned char enabled)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    if (enabled) scb[1] |= 4;
    else scb[1] &= ~4;
    flush_cache((vm_offset_t)scb, 32);
}

void SCSIhSwapping32UpdateFast20HW(AdaptecU2HHCB *hhcb,
                                 unsigned char enabled)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char value = OSMReadUExact8(*handle, 161);
    if (enabled) value |= 4;
    else value &= ~4;
    OSMWriteUExact8(*handle, 161, value);
}

void SCSIhSwapping32UpdateXferOptionHostMem(AdaptecU2HHCB *hhcb,
                                          AdaptecU2HIOB *hiob,
                                          unsigned short option)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[29] = option;
    flush_cache((vm_offset_t)scb, 32);
}

void SCSIhStandardAdvUpdateXferOptionHostMem(AdaptecU2HHCB *hhcb,
                                           AdaptecU2HIOB *hiob,
                                           unsigned short option)
{
    unsigned char *scb = hiob->scb->virtualAddress, *address = scb + 3;
    __asm__ volatile ("sthbrx %0,0,%1" : : "r" (option), "r" (address) : "memory");
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhSwappingAdvUpdateXferOptionHostMem(AdaptecU2HHCB *hhcb,
                                           AdaptecU2HIOB *hiob,
                                           unsigned short option)
{
    unsigned char *scb = hiob->scb->virtualAddress, *address = scb + 36;
    __asm__ volatile ("sthbrx %0,0,%1" : : "r" (option), "r" (address) : "memory");
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhStandardClearFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char reg, mask, value;
    if (target > 7) {
        mask = 1 << (target - 8);
        reg = hhcb->firmware->registers[18];
    } else {
        mask = 1 << target;
        reg = hhcb->firmware->registers[17];
    }
    value = OSMReadUExact8(*handle, reg);
    OSMWriteUExact8(*handle, reg, value & (unsigned char)~mask);
    value = OSMReadUExact8(*handle, 1) & ~0x20;
    OSMWriteUExact8(*handle, 1, value);
}

void SCSIhSwappingClearFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char i, value;
    AdaptecU2HIOB *hiob;
    hhcb->devices[target].flags &= ~0x2000;
    if (hhcb->firmware->updateFast20HW)
        hhcb->firmware->updateFast20HW(hhcb, 0);
    for (i = 0; i < hhcb->numberScbs; ++i) {
        hiob = hhcb->activeHiobs[i];
        if (hiob != (AdaptecU2HIOB *)0xffffffff &&
            target == hiob->context.unit->target) {
            if (hhcb->firmware->updateFast20HostMem)
                hhcb->firmware->updateFast20HostMem(hhcb, hiob, 0);
        }
    }
    value = OSMReadUExact8(*handle, 1) & ~0x20;
    OSMWriteUExact8(*handle, 1, value);
}

void SCSIhStandardLogFast20Map(AdaptecU2HHCB *hhcb, unsigned char target,
                             unsigned char period)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 1), reg, mask, value;
    if (target > 7) {
        mask = 1 << (target - 8);
        reg = hhcb->firmware->registers[18];
    } else {
        mask = 1 << target;
        reg = hhcb->firmware->registers[17];
    }
    value = OSMReadUExact8(*handle, reg);
    if (period > 24) {
        value &= ~mask;
        control &= ~0x20;
    } else {
        value |= mask;
        control |= 0x20;
    }
    OSMWriteUExact8(*handle, reg, value);
    OSMWriteUExact8(*handle, 1, control);
}

void SCSIhSwappingLogFast20Map(AdaptecU2HHCB *hhcb, unsigned char target,
                             unsigned char period)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 1), i, enabled;
    AdaptecU2HIOB *hiob;
    if (period > 24) {
        hhcb->devices[target].flags &= ~0x2000;
        control &= ~0x20;
        enabled = 0;
    } else {
        hhcb->devices[target].flags |= 0x2000;
        control |= 0x20;
        enabled = 1;
    }
    if (hhcb->firmware->updateFast20HW)
        hhcb->firmware->updateFast20HW(hhcb, enabled);
    for (i = 0; i < hhcb->numberScbs; ++i) {
        hiob = hhcb->activeHiobs[i];
        if (hiob != (AdaptecU2HIOB *)0xffffffff &&
            target == hiob->context.unit->target) {
            if (hhcb->firmware->updateFast20HostMem)
                hhcb->firmware->updateFast20HostMem(hhcb, hiob, enabled);
        }
    }
    OSMWriteUExact8(*handle, 1, control);
}

void SCSIhStandardXferOptAssign(AdaptecU2HHCB *hhcb, unsigned char target,
                               unsigned short option)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    OSMWriteUExact8(*handle, hhcb->firmware->registers[5] + target, option);
    if (hhcb->hardwareFlags & 0x80000) {
        OSMWriteUExact8(*handle, 4, option);
        hhcb->hardwareFlags &= ~0x80000;
    }
}

void SCSIhHostXferOptAssign(AdaptecU2HHCB *hhcb, unsigned char target,
                           unsigned short option)
{
    unsigned char i;
    AdaptecU2HIOB *hiob;
    if (hhcb->firmware->commonXferAssign)
        hhcb->firmware->commonXferAssign(hhcb, target, option);
    for (i = 0; i < hhcb->numberScbs; ++i) {
        hiob = hhcb->activeHiobs[i];
        if (hiob != (AdaptecU2HIOB *)0xffffffff &&
            target == hiob->context.unit->target) {
            if (hhcb->firmware->updateXferOptionHostMem)
                hhcb->firmware->updateXferOptionHostMem(hhcb, hiob, option);
        }
    }
}

unsigned short SCSIhStandardGetOption(AdaptecU2HHCB *hhcb, unsigned char target)
{
    return OSMReadUExact8(*hhcb->ioHandle,
                         hhcb->firmware->registers[5] + target);
}

unsigned short SCSIhHostGetOption(AdaptecU2HHCB *hhcb, unsigned char target)
{
    return hhcb->devices[target].option;
}

void SCSIhCheckSyncNego(AdaptecU2HHCB *hhcb)
{
    unsigned char target;
    for (target = 0; target < hhcb->maxDevices; ++target)
        hhcb->firmware->xferOptAssign(hhcb, target,
                                     (hhcb->devices[target].rate & 0x81) ? 143 : 0);
}

void SCSIhChkCondXferAssign(AdaptecU2HHCB *hhcb, unsigned char target,
                           unsigned short option)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char tail, index;
    AdaptecU2HIOB *hiob;
    if (hhcb->firmware->commonXferAssign)
        hhcb->firmware->commonXferAssign(hhcb, target, option);
    tail = hhcb->hardware->getQNewTail(hhcb);
    index = OSMReadUExact8(*handle, hhcb->firmware->registers[10]);
    for (hiob = hhcb->activeHiobs[index]; tail != hhcb->qnewHead;
         hiob = hhcb->activeHiobs[hiob->scb->next->number]) {
        if (target == hiob->context.unit->target) {
            if (hhcb->firmware->updateXferOptionHostMem)
                hhcb->firmware->updateXferOptionHostMem(hhcb, hiob, option);
        }
        ++tail;
    }
}

void SCSIhSwapping32CommonXferAssign(AdaptecU2HHCB *hhcb,
                                    unsigned char target, unsigned short option)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control, saved;
    hhcb->devices[target].option = option;
    control = OSMReadUExact8(*handle, 135);
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    saved = OSMReadUExact8(*handle, 144);
    OSMWriteUExact8(*handle, 144, 1);
    if (target == OSMReadUExact8(*handle, 162))
        OSMWriteUExact8(*handle, 189, option);
    OSMWriteUExact8(*handle, 144, saved);
    if (hhcb->hardwareFlags & 0x80000) {
        OSMWriteUExact8(*handle, 4, option);
        hhcb->hardwareFlags &= ~0x80000;
    }
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIhStandardAdvCommonXferAssign(AdaptecU2HHCB *hhcb,
                                     unsigned char target, unsigned short option)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    hhcb->devices[target].option = option;
    if (target == (OSMReadUExact8(*handle, 161) & 15)) {
        OSMWriteUExact8(*handle, 163, option);
        OSMWriteUExact8(*handle, 164, option >> 8);
    }
    if (hhcb->hardwareFlags & 0x80000) {
        hhcb->hardware->loadScsiRate(hhcb, option);
        hhcb->hardwareFlags &= ~0x80000;
    }
}

void SCSIhSwappingAdvCommonXferAssign(AdaptecU2HHCB *hhcb,
                                     unsigned char target, unsigned short option)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    hhcb->devices[target].option = option;
    if (target == (OSMReadUExact8(*handle, 172) & 15)) {
        OSMWriteUExact8(*handle, 196, option);
        OSMWriteUExact8(*handle, 197, option >> 8);
    }
    if (hhcb->hardwareFlags & 0x80000) {
        hhcb->hardware->loadScsiRate(hhcb, option);
        hhcb->hardwareFlags &= ~0x80000;
    }
}

void SCSIhStandard64ModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned int address;
    int displacement;
    unsigned char control;
    if (OSMReadUExact8(*handle, 172) & 0x80)
        SCSIhHandleMsgIn(hhcb, hiob);
    else {
        displacement = *(int *)&hiob->message[1];
        address = OSMReadUExact8(*handle, 20);
        address |= OSMReadUExact8(*handle, 21) << 8;
        address |= OSMReadUExact8(*handle, 22) << 16;
        address |= (unsigned int)OSMReadUExact8(*handle, 23) << 24;
        address += displacement;
        OSMWriteUExact8(*handle, 136, address);
        OSMWriteUExact8(*handle, 137, address >> 8);
        OSMWriteUExact8(*handle, 138, address >> 16);
        OSMWriteUExact8(*handle, 139, address >> 24);
        control = OSMReadUExact8(*handle, 1) | 2;
        OSMWriteUExact8(*handle, 1, control);
        OSMReadUExact8(*handle, 6);
    }
    OSMWriteUExact8(*handle, 98, hhcb->firmware->word30 >> 2);
    OSMWriteUExact8(*handle, 99, hhcb->firmware->word30 >> 10);
}

void SCSIhSwapping32ModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned int address;
    int displacement;
    unsigned char control;
    if (OSMReadUExact8(*handle, 161) & 0x80)
        SCSIhHandleMsgIn(hhcb, hiob);
    else {
        displacement = *(int *)&hiob->message[1];
        address = OSMReadUExact8(*handle, 20);
        address |= OSMReadUExact8(*handle, 21) << 8;
        address |= OSMReadUExact8(*handle, 22) << 16;
        address |= (unsigned int)OSMReadUExact8(*handle, 23) << 24;
        address += displacement;
        OSMWriteUExact8(*handle, 136, address);
        OSMWriteUExact8(*handle, 137, address >> 8);
        OSMWriteUExact8(*handle, 138, address >> 16);
        OSMWriteUExact8(*handle, 139, address >> 24);
        control = OSMReadUExact8(*handle, 1) | 2;
        OSMWriteUExact8(*handle, 1, control);
        OSMReadUExact8(*handle, 6);
    }
    OSMWriteUExact8(*handle, 98, hhcb->firmware->word30 >> 2);
    OSMWriteUExact8(*handle, 99, hhcb->firmware->word30 >> 10);
}

void SCSIhStandardAdvModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    const AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char phase;
    OSMWriteUExact8(*handle, 3, 0xf0);
    do {
        OSMReadUExact8(*handle, 6);
        phase = SCSIhWait4Req(hhcb);
    } while (phase == 0xe0);
    if (phase != 0xa0) SCSIhBadSeq(hhcb);
    else {
        OSMWriteUExact8(*handle, 3, 0xa0);
        OSMWriteUExact8(*handle, 12, 64);
        OSMWriteUExact8(*handle, 6, 7);
        SCSIhWait4Req(hhcb);
        OSMWriteUExact8(*handle, 98, ((unsigned char)hhcb->firmware->word10) >> 2);
        OSMWriteUExact8(*handle, 99, 0);
    }
}
