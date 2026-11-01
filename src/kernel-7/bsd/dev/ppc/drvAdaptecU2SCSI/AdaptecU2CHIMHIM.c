#include "AdaptecU2CHIMPrivate.h"

unsigned int SCSIHGetConfiguration(AdaptecU2HHCB *hhcb)
{
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135);
    hhcb->flags = (hhcb->flags & ~0x4000) | ((control & 1) << 14);
    if (control & 64) {
        control &= 190;
        OSMWriteUExact8(*hhcb->ioHandle, 135, control);
    }
    SCSIhSetupEnvironment(hhcb);
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    SCSIhPrepareConfig(hhcb);
    hhcb->firmware->getConfig(hhcb);
    SCSIhGetHardwareConfiguration(hhcb);
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
    asm volatile ("sync" : : : "memory");
    return 0;
}

void SCSIHGetMemoryTable(unsigned char firmwareMode, unsigned char scbCount,
                        AdaptecU2MemoryDescriptor *table)
{
    const AdaptecU2FirmwareDescriptor *firmware = SCSIFirmware[firmwareMode];
    table[1].byte02 = 1;
    table[0].category = 1;
    table[1].category = 1;
    table[0].byte02 = table[2].byte02 = table[4].byte02 = 0;
    table[2].category = table[4].category = 0;
    table[0].alignmentMask = 255;
    table[2].alignmentMask = table[4].alignmentMask = 3;
    table[0].granularity = 0;
    table[1].alignmentMask = firmware->word04 - 1;
    table[1].granularity = firmware->word04;
    table[2].granularity = table[4].granularity = 0;
    table[0].size = 8 * (scbCount + 1);
    table[2].size = 4 * scbCount;
    table[0].minimumSize = table[0].size;
    table[1].size = scbCount * firmware->word04;
    table[2].minimumSize = table[2].size;
    table[1].minimumSize = 4 * firmware->word04;
    table[4].minimumSize = table[4].size;
}

unsigned int SCSIHApplyMemoryTable(AdaptecU2HHCB *hhcb,
                                  const AdaptecU2MemoryDescriptor *table)
{
    unsigned char count;
    hhcb->qout = table[0].address;
    hhcb->activeHiobs = (AdaptecU2HIOB **)table[2].address;
    hhcb->scbBuffers = table[1].address;
    count = table[1].size / SCSIFirmware[hhcb->firmwareMode]->word04;
    if (count < hhcb->numberScbs) {
        if (count <= 3) return 1;
        hhcb->numberScbs = count;
    }
    return 0;
}

int SCSIHInitialize(AdaptecU2HHCB *hhcb)
{
    SCSIhWriteHCNTRL(hhcb, 4);
    if (hhcb->hardware->seqStretchWorkaround)
        hhcb->hardware->seqStretchWorkaround(hhcb);
    if (hhcb->firmware->configureScbRam)
        hhcb->firmware->configureScbRam(hhcb);
    if (hhcb->firmware->setupSequencer(hhcb)) return -1;
    SCSIhResetChannelHardware(hhcb);
    hhcb->firmware->resetSoftware(hhcb);
    SCSIhInitializeHardware(hhcb);
    if (hhcb->flags & 0x40000000) {
        SCSIhResetScsi(hhcb);
        SCSIhDelayCount500us(hhcb, 4000);
    }
    SCSIhStartToRunSequencer(hhcb);
    asm volatile ("sync" : : : "memory");
    return 0;
}

void SCSIHSetupHardware(AdaptecU2HHCB *hhcb)
{
    hhcb->hardware = SCSIHardware[hhcb->hardwareMode];
}

void SCSIHSetUnitHandle(AdaptecU2HHCB *hhcb, AdaptecU2UnitControl *unit,
                       unsigned char target, unsigned char lun)
{
    unit->hhcb = hhcb;
    unit->target = target;
    unit->lun = lun;
    unit->device = &hhcb->devices[target];
}

void SCSIHFreeUnitHandle(AdaptecU2UnitHandleArgument unusedHandle)
{
}

unsigned int SCSIHApplyDeviceTable()
{
    return 0;
}

void SCSIHDisableIRQ(AdaptecU2HHCB *hhcb)
{
    SCSIhWriteHCNTRL(hhcb, OSMReadUExact8(*hhcb->ioHandle, 135) & 253);
    asm volatile ("sync" : : : "memory");
}

void SCSIHEnableIRQ(AdaptecU2HHCB *hhcb)
{
    SCSIhWriteHCNTRL(hhcb, OSMReadUExact8(*hhcb->ioHandle, 135) | 2);
    asm volatile ("sync" : : : "memory");
}

unsigned char SCSIHPollIRQ(AdaptecU2HHCB *hhcb)
{
    unsigned char status;
    if (hhcb->hardwareFlags & 0x100000)
        status = SCSIhWWReadINTSTAT(hhcb->ioHandle);
    else status = OSMReadUExact8(*hhcb->ioHandle, 145);
    return status & 15;
}

void SCSIHQueueHIOB(AdaptecU2HIOB *hiob)
{
    AdaptecU2HHCB *hhcb = hiob->context.unit->hhcb;
    hhcb->activeHiobs[hiob->control.bytes.scbNumber] = hiob;
    hhcb->firmware->deliverScb(hhcb, hiob);
    asm volatile ("sync" : : : "memory");
}

void SCSIHQueueSpecialHIOB(AdaptecU2HIOB *hiob)
{
    AdaptecU2HHCB *hhcb;
    switch (hiob->function) {
    case 1: SCSIhAbortTask(hiob); break;
    case 2:
        SCSIhScsiBusReset(hiob->context.hhcb, hiob);
        hiob->status = 1;
        SCSIrCompleteSpecialHIOB(hiob);
        break;
    case 3:
        hhcb = hiob->context.unit->hhcb;
        hhcb->firmware->setupBDR(hhcb, hiob);
        break;
    case 4: case 8: break;
    case 6:
        hhcb = hiob->context.hhcb;
        if (!(hhcb->flags & 0x100000))
            hhcb->flags = (hhcb->flags & ~0x100000) |
                ((hhcb->flags & 0x600000) == 0x400000 ? 0x100000 : 0);
        hiob->status = 1;
        SCSIrCompleteSpecialHIOB(hiob);
        break;
    case 7: SCSIhAbortTaskSet(hiob); break;
    default: return;
    }
    asm volatile ("sync" : : : "memory");
}

unsigned int SCSIHPowerManagement(AdaptecU2HHCB *hhcb,
                                 unsigned int unusedEventWord)
{
    return SCSIHCheckHostIdle(hhcb) ? 1 : 2;
}

unsigned int SCSIHCheckHostIdle(AdaptecU2HHCB *hhcb)
{
    unsigned char i;
    for (i = 0; i < hhcb->numberScbs; ++i)
        if (hhcb->activeHiobs[i] != (AdaptecU2HIOB *)0xffffffff) return 0;
    return 1;
}

unsigned int SCSIHCheckDeviceIdle(AdaptecU2HHCB *hhcb, unsigned char target)
{
    unsigned char i;
    for (i = 0; i < hhcb->numberScbs; ++i)
        if (hhcb->activeHiobs[i] != (AdaptecU2HIOB *)0xffffffff &&
            hhcb->activeHiobs[i]->context.unit->target == target) return 0;
    return 1;
}

void SCSIHEnableExpStatus(AdaptecU2HHCB *hhcb)
{
    if (hhcb->flags & 0x20000) {
        hhcb->hardwareFlags |= 0x20000;
        SCSIhPauseAndWait(hhcb);
        hhcb->firmware->setBreakPoint(hhcb, 2);
        SCSIhUnPause(hhcb);
    }
}

void SCSIHDisableExpStatus(AdaptecU2HHCB *hhcb)
{
    if (hhcb->flags & 0x20000) {
        hhcb->hardwareFlags &= ~0x20000;
        SCSIhPauseAndWait(hhcb);
        hhcb->firmware->clearBreakPoint(hhcb, 2);
        SCSIhUnPause(hhcb);
    }
}

void SCSIHSuppressNegotiation(AdaptecU2UnitControl *unit)
{
    AdaptecU2IOHandle *handle = unit->hhcb->ioHandle;
    unsigned char control = 4;
    if (!SCSIHCheckDeviceIdle(unit->hhcb, unit->target)) return;
    if (unit->hhcb->hardwareMode == 1) {
        control = OSMReadUExact8(*handle, 135);
        if (!(control & 4)) SCSIhPauseAndWait(unit->hhcb);
    }
    if (unit->hhcb->firmware->getOption(unit->hhcb, unit->target) == 143)
        unit->hhcb->firmware->xferOptAssign(unit->hhcb, unit->target, 0);
    if (unit->hhcb->hardwareMode == 1 && !(control & 4))
        OSMWriteUExact8(*handle, 135, control);
}

void SCSIHForceNegotiation(AdaptecU2UnitControl *unit)
{
    AdaptecU2IOHandle *handle = unit->hhcb->ioHandle;
    unsigned char control = 4;
    unsigned short option;
    if (!SCSIHCheckDeviceIdle(unit->hhcb, unit->target)) return;
    option = (unit->device->rate & 129) ? 143 : 0;
    if (unit->hhcb->hardwareMode == 1) {
        control = OSMReadUExact8(*handle, 135);
        if (!(control & 4)) SCSIhPauseAndWait(unit->hhcb);
    }
    unit->hhcb->firmware->xferOptAssign(unit->hhcb, unit->target, option);
    if (unit->hhcb->hardwareMode == 1 && !(control & 4))
        OSMWriteUExact8(*handle, 135, control);
}

unsigned int SCSIHEnableExtScbRam(AdaptecU2HHCB *hhcb)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 135);
    unsigned int value, enabled = 0;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    value = hhcb->hardware->getScbRamCtrls(hhcb);
    if (value & hhcb->hardware->ramAvailableMask) {
        enabled = !(value & hhcb->hardware->ramDisableMask);
        if (value & hhcb->hardware->ramDisableMask)
            hhcb->hardware->putScbRamCtrls(hhcb, value & ~hhcb->hardware->ramDisableMask);
        OSMWriteUExact8(*handle, 240, OSDGetHostAddress(hhcb)->words[3]);
    }
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
    return enabled;
}

unsigned int SCSIHDisableExtScbRam(AdaptecU2HHCB *hhcb)
{
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135);
    unsigned int value, enabled = 0;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    value = hhcb->hardware->getScbRamCtrls(hhcb);
    if (value & hhcb->hardware->ramAvailableMask) {
        enabled = !(value & hhcb->hardware->ramDisableMask);
        if (enabled)
            hhcb->hardware->putScbRamCtrls(hhcb, value | hhcb->hardware->ramDisableMask);
    }
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
    return enabled;
}

unsigned int SCSIHExtScbRAMAvail(AdaptecU2HHCB *hhcb)
{
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135);
    unsigned int available;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    available = (hhcb->hardware->getScbRamCtrls(hhcb) & hhcb->hardware->ramAvailableMask) != 0;
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
    return available;
}

void SCSIHReadHADDR(AdaptecU2HHCB *hhcb, unsigned char *destination)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 135);
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    destination[0] = OSMReadUExact8(*handle, 136);
    destination[1] = OSMReadUExact8(*handle, 137);
    destination[2] = OSMReadUExact8(*handle, 138);
    destination[3] = OSMReadUExact8(*handle, 139);
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
}

unsigned int SCSIHSizeSEEPROM(AdaptecU2HHCB *hhcb)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 135);
    unsigned int size = 0;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    if (!hhcb->hardwareMode) {
        OSMWriteUExact8(*handle, 30, 8);
        if (!(OSMReadUExact8(*handle, 30) & 8)) goto done;
    }
    if (!((unsigned char *)&hhcb->worddc)[3]) size = 64;
    else if (((unsigned char *)&hhcb->worddc)[3] == 1) size = 128;
done:
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
    return size;
}

unsigned int SCSIHReadSEEPROM(AdaptecU2HHCB *hhcb, unsigned short *destination,
                             unsigned int wordOffset, int wordCount)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 135);
    int i;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    if (!hhcb->hardwareMode) {
        OSMWriteUExact8(*handle, 30, 8);
        if (!(OSMReadUExact8(*handle, 30) & 8)) return 1;
    }
    OSMWriteUExact8(*handle, 30, 32);
    while (!(OSMReadUExact8(*handle, 30) & 16)) ;
    for (i = 0; i < wordCount; ++i)
        destination[i] = SCSIhReadE2Register(wordOffset + i, handle,
                                            ((unsigned char *)&hhcb->worddc)[3]);
    OSMWriteUExact8(*handle, 30, 0);
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
    return 0;
}

unsigned int SCSIHWriteSEEPROM(AdaptecU2HHCB *hhcb, unsigned int wordOffset,
                              int wordCount, const unsigned short *source)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 135);
    unsigned int enable, address;
    int bits, i;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    if (!hhcb->hardwareMode) {
        OSMWriteUExact8(*handle, 30, 8);
        if (!(OSMReadUExact8(*handle, 30) & 8)) return 1;
    }
    if (((unsigned char *)&hhcb->worddc)[3]) {
        enable = 192;
        address = wordOffset | 768;
        bits = 10;
    } else {
        enable = 48;
        address = wordOffset | 192;
        bits = 8;
    }
    OSMWriteUExact8(*handle, 30, 32);
    while (!(OSMReadUExact8(*handle, 30) & 16)) ;
    SCSIhSendE2Address(enable, bits, handle);
    for (i = 0; i < wordCount; ++i) {
        SCSIhSendE2Address(address + i, bits, handle);
        OSMWriteUExact8(*handle, 30, 32);
        SCSIhWait2usec(32, handle);
        OSMWriteUExact8(*handle, 30, 40);
        SCSIhWait2usec(40, handle);
        while (!(OSMReadUExact8(*handle, 30) & 1)) ;
        OSMWriteUExact8(*handle, 30, 32);
        SCSIhWait2usec(32, handle);
        SCSIhWriteE2Register(wordOffset + i, source[i], handle,
                             ((unsigned char *)&hhcb->worddc)[3]);
    }
    SCSIhSendE2Address(0, bits, handle);
    OSMWriteUExact8(*handle, 30, 0);
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
    return 0;
}

void SCSIHReadScratchRam(AdaptecU2HHCB *hhcb, unsigned char *destination,
                         int offset, int count)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 135);
    unsigned char first;
    int i;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    first = offset + (offset > 63 ? 48 : 32);
    for (i = 0; i < count; ++i) destination[i] = OSMReadUExact8(*handle, first + i);
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIHWriteScratchRam(AdaptecU2HHCB *hhcb, int offset, int count,
                          const unsigned char *source)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char control = OSMReadUExact8(*handle, 135);
    unsigned char first;
    int i;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    first = offset + (offset > 63 ? 48 : 32);
    for (i = 0; i < count; ++i) OSMWriteUExact8(*handle, first + i, source[i]);
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIHGetHWInformation(AdaptecU2HWInformation *information, AdaptecU2HHCB *hhcb)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    AdaptecU2PciLocation *location;
    volatile unsigned int *flags = &information->flags;
    unsigned char control = OSMReadUExact8(*handle, 135), bus, device, i;
    unsigned int address, digit;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    information->identification[0] = (OSMReadUExact8(*handle, 31) & 2) ? 19 : 35;
    for (i = 0; i < 11; ++i) information->identification[2 + i] = "ADAPTEC AIC"[i];
    information->identification[1] |= hhcb->hostID;
    information->identification[13] = (hhcb->deviceID >> 12) | 48;
    information->identification[14] = ((hhcb->deviceID >> 8) & 15) | 48;
    information->identification[15] = ((hhcb->deviceID >> 4) & 15) | 48;
    information->identification[16] = (hhcb->deviceID & 15) | 48;
    location = OSDGetHostAddress(hhcb);
    bus = -1 - location->words[1];
    information->identification[19] = bus % 10 + 48;
    information->identification[18] = (bus / 10) % 10 + 48;
    information->identification[17] = (bus / 10) / 10 + 48;
    device = 31 - location->words[2];
    information->identification[21] = device % 10 + 48;
    information->identification[20] = device / 10 + 48;
    address = OSDReadPciConfiguration(hhcb, 16) & 0xfffffffe;
    for (i = 0; i < 8; ++i) {
        digit = (address >> (28 - 4 * i)) & 15;
        information->identification[22 + i] = digit <= 8 ? (digit | 48) : digit + 55;
    }
    information->identification[31] = information->identification[30] = 32;
    information->hostID = hhcb->hostID;
    information->fifoThreshold = hhcb->fifoThreshold;
    *flags = (*flags & ~0x40000000) | ((hhcb->flags >> 1) & 0x40000000);
    *flags = (*flags & ~0x30000000) | ((hhcb->flags << 10) & 0x30000000);
    *flags = (*flags & ~0x4000000) | ((hhcb->flags & 0x1000) ? 0x4000000 : 0);
    *flags = (*flags & ~0x8000000) | ((hhcb->flags & 0x800) ? 0x8000000 : 0);
    if (hhcb->hardwareMode == 0) information->fifoThreshold = hhcb->fifoThreshold;
    else if (hhcb->hardwareMode == 1) {
        if (*flags & 0x8000000) {
            information->writeThreshold = hhcb->fifoThreshold & 15;
            information->readThreshold = hhcb->fifoThreshold >> 4;
        } else information->fifoThreshold = hhcb->fifoThreshold & 15;
    }
    if (OSMReadUExact8(*handle, 31) & 2) *flags |= 0x80000000;
    else *flags &= ~0x80000000;
    for (i = 0; i < 16; ++i) {
        information->targets[i].option = hhcb->firmware->getOption(hhcb, i);
        information->targets[i].flags = (hhcb->firmware->getFast20Reg(hhcb, i) << 15) |
                                        (information->targets[i].flags & 0x7fff);
    }
    hhcb->hardware->getProfileParameters(information, hhcb);
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIHPutHWInformation(const AdaptecU2HWInformation *information, AdaptecU2HHCB *hhcb)
{
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    volatile unsigned int *flags = &hhcb->flags;
    volatile unsigned char *fifo = &hhcb->fifoThreshold;
    unsigned char control = OSMReadUExact8(*handle, 135), value;
    if (!(control & 4)) SCSIhPauseAndWait(hhcb);
    OSMWriteUExact8(*handle, hhcb->hardware->configurationRegister, information->hostID);
    hhcb->hostID = information->hostID;
    if (!hhcb->hardwareMode) *fifo = information->fifoThreshold;
    else if (hhcb->hardwareMode == 1) {
        *flags = (*flags & ~0x800) | ((information->flags & 0x8000000) ? 0x800 : 0);
        if (information->flags & 0x8000000) {
            *fifo = information->readThreshold;
            *fifo = information->writeThreshold | (16 * *fifo);
        } else {
            *fifo = information->fifoThreshold & 15;
            *fifo = information->fifoThreshold | (16 * *fifo);
        }
    }
    hhcb->hardware->updateDataFifoThrsh(hhcb);
    *flags = (*flags & ~0x1000) | ((information->flags & 0x4000000) ? 0x1000 : 0);
    *flags = (*flags & ~0x800) | ((information->flags & 0x8000000) ? 0x800 : 0);
    value = (OSMReadUExact8(*handle, 2) & 199) |
             ((information->flags >> 25) & 32) | ((information->flags >> 25) & 24);
    OSMWriteUExact8(*handle, 2, value);
    *flags = (*flags & ~0x80000000) | ((information->flags & 0x40000000) ? 0x80000000 : 0);
    *flags = (*flags & ~0xc0000) | ((information->flags >> 10) & 0xc0000);
    hhcb->hardware->putProfileParameters(information, hhcb);
    if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
}
