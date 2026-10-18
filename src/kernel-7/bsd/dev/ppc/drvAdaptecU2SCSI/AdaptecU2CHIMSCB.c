#include "AdaptecU2CHIMPrivate.h"
#include <machdep/ppc/pmap.h>

#define SCB_STORE_LE16(address, value) \
    __asm__ volatile ("sthbrx %0,0,%1" : : "r" (value), "r" (address) : "memory")
#define SCB_LOAD_LE32(address, value) \
    __asm__ ("lwbrx %0,0,%1" : "=r" (value) : "r" (address) : "memory")
#define SCB_STORE_LE32(address, value) \
    __asm__ volatile ("stwbrx %0,0,%1" : : "r" (value), "r" (address) : "memory")

unsigned char SCSIhStandard64ObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    return hiob->scb->virtualAddress[38];
}

unsigned char SCSIhSwapping32ObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    return hiob->scb->virtualAddress[28];
}

unsigned char SCSIhStandardAdvObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    return hiob->scb->virtualAddress[5];
}

unsigned char SCSIhSwappingAdvObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    return hiob->scb->virtualAddress[11];
}

void SCSIhStandard64UpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)
{
    hiob->scb->virtualAddress[38] = number;
    flush_cache((vm_offset_t)hiob->scb->virtualAddress, 64);
}

void SCSIhSwapping32UpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)
{
    hiob->scb->virtualAddress[28] = number;
    flush_cache((vm_offset_t)hiob->scb->virtualAddress, 32);
}

void SCSIhStandardAdvUpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)
{
    hiob->scb->virtualAddress[5] = number;
    flush_cache((vm_offset_t)hiob->scb->virtualAddress, 64);
}

void SCSIhSwappingAdvUpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)
{
    hiob->scb->virtualAddress[11] = number;
    flush_cache((vm_offset_t)hiob->scb->virtualAddress, 64);
}

unsigned int SCSIhStandard64ObtainNextScbAddress(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    unsigned int address;
    SCB_LOAD_LE32(hiob->scb->virtualAddress + 40, address);
    return address;
}

unsigned int SCSIhStandardAdvObtainNextScbAddress(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    unsigned int address;
    SCB_LOAD_LE32(hiob->scb->virtualAddress + 32, address);
    return address;
}

void SCSIhStandard64UpdateNextScbAddress(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    SCB_STORE_LE32(scb + 40, busAddress);
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhStandardAdvUpdateNextScbAddress(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    SCB_STORE_LE32(scb + 32, busAddress);
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhStandard64UpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[35] |= 8;
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhStandardAdvUpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[0] |= 16;
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhSwapping32UpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[0] |= 8;
    flush_cache((vm_offset_t)scb, 32);
}

void SCSIhSwappingAdvUpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[38] |= 16;
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhSwapping32PatchXferOpt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2DeviceTable *device = hiob->context.unit->device;
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[29] = (unsigned char)device->option;
    if (device->flags & 0x2000) {
        scb[1] |= 4;
        flush_cache((vm_offset_t)scb, 32);
    }
}

void SCSIhStandardAdvPatchXferOpt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    SCB_STORE_LE16(hiob->scb->virtualAddress + 3, hiob->context.unit->device->option);
}

void SCSIhSwappingAdvPatchXferOpt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    SCB_STORE_LE16(hiob->scb->virtualAddress + 36, hiob->context.unit->device->option);
}

unsigned char SCSIhStandardRetrieveScb(AdaptecU2HHCB *hhcb)
{
    unsigned char number;
    if (hhcb->qout[8 * hhcb->qdoneElement + 7] != hhcb->qdonePass)
        return 255;
    number = hhcb->qout[8 * hhcb->qdoneElement];
    if (++hhcb->qdoneElement == (unsigned char)(hhcb->numberScbs + 1)) {
        hhcb->qdoneElement = 0;
        ++hhcb->qdonePass;
    }
    return number;
}

unsigned char SCSIhStandardQoutcnt(const AdaptecU2HHCB *hhcb)
{
    unsigned char pass = hhcb->qdonePass, element = hhcb->qdoneElement, count = 0;
    const unsigned char *entry = hhcb->qout + 8 * element;
    while (entry[7] == pass) {
        ++element;
        ++count;
        if (element == (unsigned char)(hhcb->numberScbs + 1)) {
            entry = hhcb->qout;
            ++pass;
            element = 0;
        } else
            entry += 8;
    }
    return count;
}

void SCSIhStandardIndexClearBusy(AdaptecU2HHCB *hhcb, unsigned char index)
{
    OSMWriteUExact8(*hhcb->ioHandle, 144, index);
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[0], 255);
}

void SCSIhSwappingIndexClearBusy(AdaptecU2HHCB *hhcb, unsigned char index)
{
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[0] + index, 255);
}

unsigned int SCSIhSwappingSearchExeQ()
{
    return 0;
}

void SCSIhStandardResetBTA(AdaptecU2HHCB *hhcb)
{
    unsigned int i, count = hhcb->byte1f;
    for (i = 0; i < count; ++i)
        SCSIhStandardIndexClearBusy(hhcb, i);
}

void SCSIhSwappingResetBTA(AdaptecU2HHCB *hhcb)
{
    unsigned int i;
    for (i = 0; i < 16; ++i)
        SCSIhSwappingIndexClearBusy(hhcb, i);
}

void SCSIhStandardTargetClearBusy(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned char saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    unsigned char index = unit->target;
    OSMWriteUExact8(*hhcb->ioHandle, 144, hiob->control.bytes.scbNumber);
    if (hhcb->flags & 0x20000000)
        index += 16 * unit->lun;
    SCSIhStandardIndexClearBusy(hhcb, index);
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
}

void SCSIhSwappingTargetClearBusy(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    SCSIhSwappingIndexClearBusy(hhcb, hiob->context.unit->target);
}

void SCSIhCommonResetSoftware(AdaptecU2HHCB *hhcb)
{
    unsigned char i;
    for (i = 0; i < hhcb->numberScbs; ++i)
        hhcb->activeHiobs[i] = (AdaptecU2HIOB *)0xffffffff;
    SCSIhCheckSyncNego(hhcb);
    if (hhcb->firmware->setupAssignScbBuffer)
        hhcb->firmware->setupAssignScbBuffer(hhcb);
}

void SCSIhSetAddressScratchBA32(AdaptecU2HHCB *hhcb, unsigned char offset,
                                 const unsigned char *virtualAddress)
{
    unsigned int busAddress = OSDGetBusAddress(hhcb, 1, virtualAddress);
    OSMWriteUExact8(*hhcb->ioHandle, offset, busAddress);
    OSMWriteUExact8(*hhcb->ioHandle, offset + 1, busAddress >> 8);
    OSMWriteUExact8(*hhcb->ioHandle, offset + 2, busAddress >> 16);
    OSMWriteUExact8(*hhcb->ioHandle, offset + 3, busAddress >> 24);
}

void SCSIhStandard64QHead(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 0), number, oldHead;
    AdaptecU2HIOB *active;
    if ((control & 64) && hiob->targetStatus == 2) {
        number = OSMReadUExact8(*hhcb->ioHandle, 52);
        active = hhcb->activeHiobs[number];
        if (active->context.unit->hhcb == hhcb &&
            active->context.unit->target == hiob->context.unit->target) {
            oldHead = OSMReadUExact8(*hhcb->ioHandle, 94);
            OSMWriteUExact8(*hhcb->ioHandle, 94, number);
            OSMWriteUExact8(*hhcb->ioHandle, 198, oldHead);
            if (oldHead == 255)
                OSMWriteUExact8(*hhcb->ioHandle, 95, number);
            OSMWriteUExact8(*hhcb->ioHandle, 0, control & 0x33);
            OSMReadUExact8(*hhcb->ioHandle, 0);
        }
    }
    OSMWriteUExact8(*hhcb->ioHandle, 144, hiob->control.bytes.scbNumber);
    oldHead = OSMReadUExact8(*hhcb->ioHandle, 94);
    OSMWriteUExact8(*hhcb->ioHandle, 94, hiob->control.bytes.scbNumber);
    OSMWriteUExact8(*hhcb->ioHandle, 198, oldHead);
    if (oldHead == 255)
        OSMWriteUExact8(*hhcb->ioHandle, 95, hiob->control.bytes.scbNumber);
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
}

void SCSIhStandardAdvQHead(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 0), number, oldHead;
    AdaptecU2HIOB *active;
    if ((control & 64) && hiob->targetStatus == 2) {
        number = OSMReadUExact8(*hhcb->ioHandle, 60);
        active = hhcb->activeHiobs[number];
        if (active->context.unit->hhcb == hhcb &&
            active->context.unit->target == hiob->context.unit->target) {
            oldHead = OSMReadUExact8(*hhcb->ioHandle, 54);
            OSMWriteUExact8(*hhcb->ioHandle, 54, number);
            OSMWriteUExact8(*hhcb->ioHandle, 165, oldHead);
            if (oldHead == 255)
                OSMWriteUExact8(*hhcb->ioHandle, 55, number);
            OSMWriteUExact8(*hhcb->ioHandle, 0, control & 0x33);
            OSMReadUExact8(*hhcb->ioHandle, 0);
        }
    }
    OSMWriteUExact8(*hhcb->ioHandle, 144, hiob->control.bytes.scbNumber);
    oldHead = OSMReadUExact8(*hhcb->ioHandle, 54);
    OSMWriteUExact8(*hhcb->ioHandle, 54, hiob->control.bytes.scbNumber);
    OSMWriteUExact8(*hhcb->ioHandle, 165, oldHead);
    if (oldHead == 255)
        OSMWriteUExact8(*hhcb->ioHandle, 55, hiob->control.bytes.scbNumber);
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
}

void SCSIhSwapping32QHead(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char head = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 0), number, tail;
    AdaptecU2HIOB *active;
    if ((control & 64) && hiob->targetStatus == 2) {
        number = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[4]);
        active = hhcb->activeHiobs[number];
        if (active->context.unit->hhcb == hhcb &&
            active->context.unit->target == hiob->context.unit->target) {
            tail = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9]) - 1;
            OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9], tail);
            hhcb->firmware->updateNextScbNum(hhcb, active, head);
            OSMWriteUExact8(*hhcb->ioHandle, 0, control & 0x33);
            head = number;
            OSMReadUExact8(*hhcb->ioHandle, 0);
        }
    }
    if (head == hiob->control.bytes.scbNumber)
        return;
    hhcb->firmware->updateNextScbNum(hhcb, hiob, head);
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10], hiob->control.bytes.scbNumber);
    tail = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9]) - 1;
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9], tail);
}

void SCSIhSwappingAdvQHead(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char head = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 0), number, tail;
    AdaptecU2HIOB *active;
    unsigned char saved, next;
    unsigned int count = 0x800000;
    if ((control & 64) && hiob->targetStatus == 2) {
        number = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[4]);
        active = hhcb->activeHiobs[number];
        if (active->context.unit->hhcb == hhcb &&
            active->context.unit->target == hiob->context.unit->target) {
            tail = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9]) - 1;
            OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9], tail);
            hhcb->firmware->updateNextScbNum(hhcb, active, head);
            OSMWriteUExact8(*hhcb->ioHandle, 0, control & 0x33);
            head = number;
            OSMReadUExact8(*hhcb->ioHandle, 0);
        }
    }
    if ((OSMReadUExact8(*hhcb->ioHandle, 238) & 16) &&
        (OSMReadUExact8(*hhcb->ioHandle, 238) & 4)) {
        do {
            if (OSMReadUExact8(*hhcb->ioHandle, 238) & 64)
                break;
        } while (count-- != 0);
        saved = OSMReadUExact8(*hhcb->ioHandle, 144);
        if (saved != OSMReadUExact8(*hhcb->ioHandle, 241)) {
            active = hhcb->activeHiobs[head];
            next = hhcb->firmware->obtainNextScbNum(hhcb, active);
            hhcb->firmware->updateNextScbNum(hhcb, active, hiob->control.bytes.scbNumber);
            OSMWriteUExact8(*hhcb->ioHandle, 144, OSMReadUExact8(*hhcb->ioHandle, 241));
            OSMWriteUExact8(*hhcb->ioHandle, 171, hiob->control.bytes.scbNumber);
            OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
            if (next == hiob->control.bytes.scbNumber)
                return;
            hhcb->firmware->updateNextScbNum(hhcb, hiob, next);
        } else {
            if (head == hiob->control.bytes.scbNumber)
                return;
            hhcb->firmware->updateNextScbNum(hhcb, hiob, head);
            OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10], hiob->control.bytes.scbNumber);
        }
    } else {
    if (head == hiob->control.bytes.scbNumber)
        return;
    hhcb->firmware->updateNextScbNum(hhcb, hiob, head);
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10], hiob->control.bytes.scbNumber);
    }
    tail = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9]) - 1;
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9], tail);
}

