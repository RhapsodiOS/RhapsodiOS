#include "AdaptecU2CHIMPrivate.h"
#include <machdep/ppc/pmap.h>
extern void *memset(void *destination, int value, unsigned int count);

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

void SCSIhStandard64QHeadBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2SCBDescriptor *next = hiob->scb->next;
    unsigned char number = next->number;
    unsigned int busAddress = next->busAddress;
    unsigned char *virtualAddress = next->virtualAddress;
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    AdaptecU2HIOB *previous;
    if (current == hiob->control.bytes.scbNumber) {
        OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10], number);
        SCSIhSetAddressScbBA32(hhcb, 60, virtualAddress);
    } else {
        while (hhcb->activeHiobs[current] != (AdaptecU2HIOB *)0xffffffff) {
            previous = hhcb->activeHiobs[current];
            current = hhcb->firmware->obtainNextScbNum(hhcb, previous);
            if (current == hiob->control.bytes.scbNumber) {
                hhcb->firmware->updateNextScbNum(hhcb, previous, number);
                if (hhcb->firmware->updateNextScbAddress)
                    hhcb->firmware->updateNextScbAddress(hhcb, previous, busAddress);
                break;
            }
        }
    }
    SCSIhStandard64QHead(hhcb, hiob);
}

void SCSIhStandardAdvQHeadBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2SCBDescriptor *next = hiob->scb->next;
    unsigned char number = next->number;
    unsigned int busAddress = next->busAddress;
    unsigned char *virtualAddress = next->virtualAddress;
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    AdaptecU2HIOB *previous;
    if (current == hiob->control.bytes.scbNumber) {
        OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10], number);
        SCSIhSetAddressScbBA32(hhcb, 32, virtualAddress);
    } else {
        while (hhcb->activeHiobs[current] != (AdaptecU2HIOB *)0xffffffff) {
            previous = hhcb->activeHiobs[current];
            current = hhcb->firmware->obtainNextScbNum(hhcb, previous);
            if (current == hiob->control.bytes.scbNumber) {
                hhcb->firmware->updateNextScbNum(hhcb, previous, number);
                if (hhcb->firmware->updateNextScbAddress)
                    hhcb->firmware->updateNextScbAddress(hhcb, previous, busAddress);
                break;
            }
        }
    }
    SCSIhStandardAdvQHead(hhcb, hiob);
}

void SCSIhSwapping32QHeadBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char tail = hhcb->hardware->getQNewTail(hhcb);
    unsigned char number = hiob->scb->next->number;
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    AdaptecU2HIOB *previous;
    if (current == hiob->control.bytes.scbNumber) {
        OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[8], ++hhcb->qnewHead);
        return;
    }
    if (tail != hhcb->qnewHead) {
        for (;;) {
            previous = hhcb->activeHiobs[current];
            current = hhcb->firmware->obtainNextScbNum(hhcb, previous);
            if (current == hiob->control.bytes.scbNumber) {
                hhcb->firmware->updateNextScbNum(hhcb, previous, number);
                break;
            }
            if (++tail == hhcb->qnewHead)
                break;
        }
    }
    SCSIhSwapping32QHead(hhcb, hiob);
}

void SCSIhSwappingAdvQHeadBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char tail = hhcb->hardware->getQNewTail(hhcb);
    unsigned char number = hiob->scb->next->number;
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    AdaptecU2HIOB *previous;
    if (current == hiob->control.bytes.scbNumber) {
        OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[8], ++hhcb->qnewHead);
        return;
    }
    if (tail != hhcb->qnewHead) {
        for (;;) {
            previous = hhcb->activeHiobs[current];
            current = hhcb->firmware->obtainNextScbNum(hhcb, previous);
            if (current == hiob->control.bytes.scbNumber) {
                hhcb->firmware->updateNextScbNum(hhcb, previous, number);
                break;
            }
            if (++tail == hhcb->qnewHead)
                break;
        }
    }
    SCSIhSwappingAdvQHead(hhcb, hiob);
}

void SCSIhStandard64SetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135), saved;
    unsigned int i;
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    OSMWriteUExact8(*hhcb->ioHandle, 144, hiob->control.bytes.scbNumber);
    for (i = 0; i < 40; ++i)
        OSMWriteUExact8(*hhcb->ioHandle, 160 + i, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 172, 8);
    OSMWriteUExact8(*hhcb->ioHandle, 173, unit->target);
    OSMWriteUExact8(*hhcb->ioHandle, 199, unit->lun);
    OSMWriteUExact8(*hhcb->ioHandle, 174, 64);
    OSMWriteUExact8(*hhcb->ioHandle, 175, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 176, 12);
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
    hhcb->activeHiobs[hiob->control.bytes.scbNumber] = hiob;
    hiob->managerStatus = 10;
    hhcb->hardwareFlags |= 0x10000;
    hhcb->firmware->setBreakPoint(hhcb, 1);
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIhStandardAdvSetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned char target = unit->target | (16 * hhcb->hostID);
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135), saved;
    unsigned int i;
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    OSMWriteUExact8(*hhcb->ioHandle, 144, hiob->control.bytes.scbNumber);
    for (i = 0; i < 40; ++i)
        OSMWriteUExact8(*hhcb->ioHandle, 160 + i, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 160, 8);
    OSMWriteUExact8(*hhcb->ioHandle, 161, target);
    OSMWriteUExact8(*hhcb->ioHandle, 162, unit->lun);
    OSMWriteUExact8(*hhcb->ioHandle, 166, 1);
    OSMWriteUExact8(*hhcb->ioHandle, 168, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 169, 12);
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
    hhcb->activeHiobs[hiob->control.bytes.scbNumber] = hiob;
    hiob->managerStatus = 10;
    hhcb->hardwareFlags |= 0x10000;
    hhcb->firmware->setBreakPoint(hhcb, 1);
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIhSwapping32SetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135);
    unsigned char *scb;
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    scb = hiob->scb->virtualAddress;
    memset(scb, 0, 32);
    scb[1] = 8;
    scb[2] = unit->target;
    scb[31] = unit->lun;
    scb[3] = 64;
    scb[4] = 0;
    scb[5] = 12;
    scb[28] = hiob->scb->next->number;
    hhcb->activeHiobs[hiob->control.bytes.scbNumber] = hiob;
    flush_cache((vm_offset_t)scb, 32);
    hiob->managerStatus = 10;
    hhcb->hardwareFlags |= 0x10000;
    hhcb->firmware->setBreakPoint(hhcb, 1);
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIhSwappingAdvSetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    AdaptecU2UnitControl *unit = hiob->context.unit;
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135);
    unsigned char *scb;
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    scb = hiob->scb->virtualAddress;
    memset(scb, 0, 64);
    scb[38] = 8;
    scb[12] = unit->target;
    scb[13] = unit->lun;
    scb[14] = 1;
    scb[16] = 0;
    scb[17] = 12;
    scb[11] = hiob->scb->next->number;
    hhcb->activeHiobs[hiob->control.bytes.scbNumber] = hiob;
    flush_cache((vm_offset_t)scb, 64);
    hiob->managerStatus = 10;
    hhcb->hardwareFlags |= 0x10000;
    hhcb->firmware->setBreakPoint(hhcb, 1);
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIhStandard64ResetSoftware(AdaptecU2HHCB *hhcb)
{
    unsigned int i;
    AdaptecU2SCBDescriptor *head;
    unsigned short mask = 0;
    SCSIhCommonResetSoftware(hhcb);
    for (i = 0; i < 16; ++i)
        if (!(hhcb->devices[i].flags & 0x4000))
            mask |= 1 << i;
    OSMWriteUExact8(*hhcb->ioHandle, 48, mask);
    OSMWriteUExact8(*hhcb->ioHandle, 49, mask >> 8);
    head = SCSIRGetFreeHead(hhcb);
    SCSIhSetAddressScratchBA32(hhcb, 60, head->virtualAddress);
    OSMWriteUExact8(*hhcb->ioHandle, 68, head->number);
    OSMWriteUExact8(*hhcb->ioHandle, 58, 0);
    hhcb->qnewHead = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 59, 0);
    SCSIhSetAddressScratchBA32(hhcb, 78, hhcb->qout);
    OSMWriteUExact8(*hhcb->ioHandle, 112, 255);
    OSMWriteUExact8(*hhcb->ioHandle, 76, 0);
    hhcb->qdoneElement = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 77, 255);
    hhcb->qdonePass = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 94, 255);
    for (i = 0; i < 8 * (hhcb->numberScbs + 1); ++i)
        hhcb->qout[i] = 255;
    OSMWriteUExact8(*hhcb->ioHandle, 53, 255);
    OSMWriteUExact8(*hhcb->ioHandle, 52, 255);
    OSMWriteUExact8(*hhcb->ioHandle, 120, hhcb->numberScbs + 1);
}

void SCSIhSwappingResetSoftware(AdaptecU2HHCB *hhcb)
{
    unsigned char count = hhcb->numberScbs;
    unsigned short i;
    SCSIhCommonResetSoftware(hhcb);
    OSMWriteUExact8(*hhcb->ioHandle, 64, SCSIRGetFreeHead(hhcb)->number);
    OSMWriteUExact8(*hhcb->ioHandle, 88, 0);
    hhcb->qnewHead = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 89, 0);
    SCSIhSetAddressScratchBA32(hhcb, 72, hhcb->qout);
    OSMWriteUExact8(*hhcb->ioHandle, 90, 0);
    hhcb->qdoneElement = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 91, 255);
    hhcb->qdonePass = 0;
    SCSIhSetAddressScratchBA32(hhcb, 80, hhcb->scbBuffers);
    for (i = 0; i < 8 * (count + 1); ++i)
        hhcb->qout[i] = 255;
    OSMWriteUExact8(*hhcb->ioHandle, 87, 255);
    OSMWriteUExact8(*hhcb->ioHandle, 86, 255);
    OSMWriteUExact8(*hhcb->ioHandle, 92, count + 1);
}

void SCSIhStandardAdvResetSoftware(AdaptecU2HHCB *hhcb)
{
    unsigned int i;
    AdaptecU2SCBDescriptor *head;
    unsigned int size;
    unsigned char control;
    unsigned char count = hhcb->numberScbs;
    SCSIhCommonResetSoftware(hhcb);
    head = SCSIRGetFreeHead(hhcb);
    SCSIhSetAddressScratchBA32(hhcb, 32, head->virtualAddress);
    OSMWriteUExact8(*hhcb->ioHandle, 58, head->number);
    OSMWriteUExact8(*hhcb->ioHandle, 244, 0);
    hhcb->qnewHead = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 246, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 248, 0);
    SCSIhSetAddressScratchBA32(hhcb, 40, hhcb->qout);
    SCSIhSetAddressScratchBA32(hhcb, 48, hhcb->qout);
    OSMWriteUExact8(*hhcb->ioHandle, 56, 255);
    hhcb->qdoneElement = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 52, 0);
    hhcb->qdonePass = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 54, 255);
    for (i = 0; i < 8 * (hhcb->numberScbs + 1); ++i)
        hhcb->qout[i] = 255;
    OSMWriteUExact8(*hhcb->ioHandle, 61, 255);
    OSMWriteUExact8(*hhcb->ioHandle, 60, 255);
    size = count + 1;
    control = OSMReadUExact8(*hhcb->ioHandle, 250) & 0xf8;
    do {
        size >>= 1;
        ++control;
    } while (size);
    OSMWriteUExact8(*hhcb->ioHandle, 250, control - 3);
    OSMWriteUExact8(*hhcb->ioHandle, 74, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 77, (hhcb->hardwareFlags & 0x8000) != 0);
}

void SCSIhSwappingAdvResetSoftware(AdaptecU2HHCB *hhcb)
{
    unsigned char count = hhcb->numberScbs;
    unsigned short i;
    unsigned int size;
    unsigned char control;
    SCSIhCommonResetSoftware(hhcb);
    OSMWriteUExact8(*hhcb->ioHandle, 40, SCSIRGetFreeHead(hhcb)->number);
    OSMWriteUExact8(*hhcb->ioHandle, 244, 0);
    hhcb->qnewHead = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 246, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 248, 0);
    SCSIhSetAddressScratchBA32(hhcb, 41, hhcb->qout);
    SCSIhSetAddressScratchBA32(hhcb, 49, hhcb->qout);
    hhcb->qdoneElement = 0;
    OSMWriteUExact8(*hhcb->ioHandle, 53, 0);
    hhcb->qdonePass = 0;
    SCSIhSetAddressScratchBA32(hhcb, 32, hhcb->scbBuffers);
    for (i = 0; i < 8 * (count + 1); ++i)
        hhcb->qout[i] = 255;
    OSMWriteUExact8(*hhcb->ioHandle, 58, 255);
    OSMWriteUExact8(*hhcb->ioHandle, 57, 255);
    size = count + 1;
    control = OSMReadUExact8(*hhcb->ioHandle, 250) & 0xf8;
    do {
        size >>= 1;
        ++control;
    } while (size);
    OSMWriteUExact8(*hhcb->ioHandle, 250, control - 3);
    OSMWriteUExact8(*hhcb->ioHandle, 73, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 77, (hhcb->hardwareFlags & 0x8000) != 0);
}

unsigned char SCSIhStandardSearchSeqDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char terminate)
{
    unsigned char saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, 112);
    unsigned char previous = current, next, found = 0;
    while (current != 255) {
        OSMWriteUExact8(*hhcb->ioHandle, 144, current);
        if (current == hiob->control.bytes.scbNumber) {
            next = OSMReadUExact8(*hhcb->ioHandle, 198);
            if (current != previous) {
                OSMWriteUExact8(*hhcb->ioHandle, 144, previous);
                OSMWriteUExact8(*hhcb->ioHandle, 198, next);
            } else
                OSMWriteUExact8(*hhcb->ioHandle, 112, next);
            if (terminate) {
                hiob->status = 0;
                hiob->managerStatus = 1;
                SCSIhTerminateCommand(hiob);
            }
            found = 1;
            break;
        }
        previous = current;
        current = OSMReadUExact8(*hhcb->ioHandle, 198);
    }
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
    return found;
}

unsigned char SCSIhStandardAdvSearchSeqDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char terminate)
{
    unsigned char saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, 56);
    unsigned char previous = current, next, found = 0;
    while (current != 255) {
        OSMWriteUExact8(*hhcb->ioHandle, 144, current);
        if (current == hiob->control.bytes.scbNumber) {
            next = OSMReadUExact8(*hhcb->ioHandle, 165);
            if (current != previous) {
                OSMWriteUExact8(*hhcb->ioHandle, 144, previous);
                OSMWriteUExact8(*hhcb->ioHandle, 165, next);
            } else
                OSMWriteUExact8(*hhcb->ioHandle, 56, next);
            if (terminate) {
                hiob->status = 0;
                hiob->managerStatus = 1;
                SCSIhTerminateCommand(hiob);
            }
            found = 1;
            break;
        }
        previous = current;
        current = OSMReadUExact8(*hhcb->ioHandle, 165);
    }
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
    return found;
}

unsigned char SCSIhStandardSearchDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char current = hhcb->qdoneElement, pass = hhcb->qdonePass, observed, found = 0;
    unsigned char *entry = hhcb->qout + 8 * current;
    observed = entry[7];
    while (observed == pass) {
        if (entry[0] == hiob->control.bytes.scbNumber) {
            while (current != hhcb->qdoneElement) {
                entry = hhcb->qout + 8 * current;
                if (--current == 255)
                    current = hhcb->numberScbs;
                entry[0] = hhcb->qout[8 * current];
                entry[7] = observed;
                if (current == hhcb->numberScbs)
                    --observed;
            }
            if (++hhcb->qdoneElement == (unsigned char)(hhcb->numberScbs + 1)) {
                hhcb->qdoneElement = 0;
                ++hhcb->qdonePass;
            }
            hiob->status = 0;
            hiob->managerStatus = 1;
            SCSIhTerminateCommand(hiob);
            found = 1;
            --((unsigned char *)&hhcb->worddc)[2];
            break;
        }
        if (++current == (unsigned char)(hhcb->numberScbs + 1)) {
            current = 0;
            ++pass;
        }
        entry = hhcb->qout + 8 * current;
        observed = entry[7];
    }
    flush_cache((vm_offset_t)hhcb->qout, 8 * (hhcb->numberScbs + 1));
    return found;
}

unsigned char SCSIhStandard64SearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)
{
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    unsigned char previous = current, head = current, next;
    unsigned int address;
    AdaptecU2HIOB *active;
    while (hhcb->activeHiobs[current] != (AdaptecU2HIOB *)0xffffffff) {
        if (current == hiob->control.bytes.scbNumber) {
            hiob->status = 2;
            hiob->hostStatus = status;
            hiob->managerStatus = 2;
            if (current == head || previous == head)
                hhcb->firmware->updateAbortBitHostMem(hhcb, hiob);
            else {
                OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[8], --hhcb->qnewHead);
                active = hhcb->activeHiobs[current];
                next = hhcb->firmware->obtainNextScbNum(hhcb, active);
                address = hhcb->firmware->obtainNextScbAddress(hhcb, active);
                active = hhcb->activeHiobs[previous];
                hhcb->firmware->updateNextScbNum(hhcb, active, next);
                if (hhcb->firmware->updateNextScbAddress)
                    hhcb->firmware->updateNextScbAddress(hhcb, active, address);
                SCSIhTerminateCommand(hiob);
            }
            return 1;
        }
        previous = current;
        current = hhcb->firmware->obtainNextScbNum(hhcb, hhcb->activeHiobs[current]);
    }
    return 0;
}

unsigned char SCSIhStandardAdvSearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)
{
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    unsigned char previous = current, head = current, next;
    unsigned int address;
    AdaptecU2HIOB *active;
    while (hhcb->activeHiobs[current] != (AdaptecU2HIOB *)0xffffffff) {
        if (current == hiob->control.bytes.scbNumber) {
            hiob->status = 2;
            hiob->hostStatus = status;
            hiob->managerStatus = 2;
            if (current == head || previous == head)
                hhcb->firmware->updateAbortBitHostMem(hhcb, hiob);
            else {
                OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[8], --hhcb->qnewHead);
                active = hhcb->activeHiobs[current];
                next = hhcb->firmware->obtainNextScbNum(hhcb, active);
                address = hhcb->firmware->obtainNextScbAddress(hhcb, active);
                active = hhcb->activeHiobs[previous];
                hhcb->firmware->updateNextScbNum(hhcb, active, next);
                if (hhcb->firmware->updateNextScbAddress)
                    hhcb->firmware->updateNextScbAddress(hhcb, active, address);
                SCSIhTerminateCommand(hiob);
            }
            return 1;
        }
        previous = current;
        current = hhcb->firmware->obtainNextScbNum(hhcb, hhcb->activeHiobs[current]);
    }
    return 0;
}

unsigned char SCSIhSwappingSearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)
{
    unsigned char tail = hhcb->hardware->getQNewTail(hhcb);
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[10]);
    unsigned char previous = current, head = current, next;
    while (tail != hhcb->qnewHead) {
        if (current == hiob->control.bytes.scbNumber) {
            hiob->status = 2;
            hiob->hostStatus = status;
            hiob->managerStatus = 2;
            if (current == head || previous == head)
                hhcb->firmware->updateAbortBitHostMem(hhcb, hiob);
            else {
                OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[8], --hhcb->qnewHead);
                next = hhcb->firmware->obtainNextScbNum(hhcb, hhcb->activeHiobs[current]);
                hhcb->firmware->updateNextScbNum(hhcb, hhcb->activeHiobs[previous], next);
                SCSIhTerminateCommand(hiob);
            }
            return 1;
        }
        previous = current;
        current = hhcb->firmware->obtainNextScbNum(hhcb, hhcb->activeHiobs[current]);
        ++tail;
    }
    return 0;
}

unsigned char SCSIhStandard64SearchExeQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status, unsigned char terminate)
{
    unsigned char saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, 94);
    unsigned char previous = current, next, found = 0;
    while (current != 255) {
        OSMWriteUExact8(*hhcb->ioHandle, 144, current);
        if (current == hiob->control.bytes.scbNumber) {
            hiob->status = 2;
            hiob->hostStatus = status;
            hiob->managerStatus = 2;
            next = OSMReadUExact8(*hhcb->ioHandle, 198);
            if (current == previous)
                OSMWriteUExact8(*hhcb->ioHandle, 94, next);
            else {
                OSMWriteUExact8(*hhcb->ioHandle, 144, previous);
                OSMWriteUExact8(*hhcb->ioHandle, 198, next);
                if (current == OSMReadUExact8(*hhcb->ioHandle, 95))
                    OSMWriteUExact8(*hhcb->ioHandle, 95, previous);
            }
            if (terminate)
                SCSIhTerminateCommand(hiob);
            found = 1;
            break;
        }
        previous = current;
        current = OSMReadUExact8(*hhcb->ioHandle, 198);
    }
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
    return found;
}

unsigned char SCSIhStandardAdvSearchExeQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status, unsigned char terminate)
{
    unsigned char saved = OSMReadUExact8(*hhcb->ioHandle, 144);
    unsigned char current = OSMReadUExact8(*hhcb->ioHandle, 54);
    unsigned char previous = current, next, found = 0;
    while (current != 255) {
        OSMWriteUExact8(*hhcb->ioHandle, 144, current);
        if (current == hiob->control.bytes.scbNumber) {
            hiob->status = 2;
            hiob->hostStatus = status;
            hiob->managerStatus = 2;
            next = OSMReadUExact8(*hhcb->ioHandle, 165);
            if (current == previous)
                OSMWriteUExact8(*hhcb->ioHandle, 54, next);
            else {
                OSMWriteUExact8(*hhcb->ioHandle, 144, previous);
                OSMWriteUExact8(*hhcb->ioHandle, 165, next);
                if (current == OSMReadUExact8(*hhcb->ioHandle, 55))
                    OSMWriteUExact8(*hhcb->ioHandle, 55, previous);
            }
            if (terminate)
                SCSIhTerminateCommand(hiob);
            found = 1;
            break;
        }
        previous = current;
        current = OSMReadUExact8(*hhcb->ioHandle, 165);
    }
    OSMWriteUExact8(*hhcb->ioHandle, 144, saved);
    return found;
}

