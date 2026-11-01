#include "AdaptecU2CHIMPrivate.h"

unsigned int SCSIhStandardConfigureScbRam(AdaptecU2HHCB *hhcb)
{
    return SCSIHEnableExtScbRam(hhcb);
}

void SCSIhSetupEnvironment(AdaptecU2HHCB *hhcb)
{
    hhcb->hardware = SCSIHardware[hhcb->hardwareMode];
    hhcb->firmware = SCSIFirmware[hhcb->firmwareMode];
}

void SCSIhPrepareConfig(AdaptecU2HHCB *hhcb)
{
    unsigned int subsystem = OSDReadPciConfiguration(hhcb, 44), device;
    unsigned char i;
    if (hhcb->hardwareMode == 1) {
        device = OSDReadPciConfiguration(hhcb, 0);
        hhcb->deviceID = device >> 16;
        hhcb->hardwareFlags |= 0x40000;
        if (device & 0xf0000)
            hhcb->idConfiguration = (hhcb->idConfiguration & 0x800fffff) |
                ((device & 0x400000) ? 0x10000000 : 0) | 0xa0400000;
        else
            *(unsigned short *)&hhcb->idConfiguration = subsystem >> 16;
    } else {
        if (subsystem)
            hhcb->deviceID = subsystem >> 16;
        else {
            hhcb->deviceID = OSMReadUExact8(*hhcb->ioHandle, 130) << 8;
            hhcb->deviceID |= OSMReadUExact8(*hhcb->ioHandle, 131);
        }
        SCSIhGetCapability(hhcb);
    }
    hhcb->bytes02[3] = hhcb->firmware->word00;
    hhcb->bytes02[4] = 0;
    hhcb->bytes02[2] = OSDReadPciConfiguration(hhcb, 8);
    if (hhcb->flags & 0x4000) {
        hhcb->hardwareFlags |= 0x80000000;
        hhcb->flags |= 0x40000000;
        for (i = 0; i < 16; ++i)
            hhcb->devices[i].flags |= 4;
    }
}

void SCSIhGetCapability(AdaptecU2HHCB *hhcb)
{
    unsigned int family = hhcb->deviceID & 0xfff0;
    unsigned int slot;
    if (family == 0x7870 || family == 0x7550)
        hhcb->idConfiguration |= 0x300000;
    else
        hhcb->idConfiguration = (hhcb->idConfiguration & 0xffcfffff) | 0x100000;
    switch (hhcb->deviceID) {
    case 0x7873: case 0x7883: case 0x7876: case 0x7886: case 0x7893:
        hhcb->idConfiguration = (hhcb->idConfiguration & 0xfcffffff) | 0x2000000;
        break;
    default:
        hhcb->idConfiguration = (hhcb->idConfiguration & 0xfcffffff) | 0x1000000;
        break;
    }
    hhcb->bytes14[3] = 0;
    slot = OSDGetHostAddress(hhcb)->words[2];
    switch (hhcb->deviceID) {
    case 0x7872: case 0x7882:
        hhcb->idConfiguration = (hhcb->idConfiguration & 0xf3ffffff) | 0x4000000;
        if (slot != 4)
            hhcb->bytes14[3] = 1;
        break;
    case 0x7873: case 0x7883:
        hhcb->idConfiguration = (hhcb->idConfiguration & 0xf3ffffff) | 0x8000000;
        switch (slot) {
        case 2: case 8: hhcb->bytes14[3] = 1; break;
        case 3: case 12: hhcb->bytes14[3] = 2; break;
        default: break;
        }
        break;
    case 0x7876: case 0x7886:
        hhcb->idConfiguration |= 0xc000000;
        break;
    default:
        hhcb->idConfiguration &= 0xf3ffffff;
        break;
    }
    if (family == 0x7890)
        hhcb->idConfiguration = (hhcb->idConfiguration & 0xf3ffffff) | 0x4000000;
    hhcb->idConfiguration = (hhcb->idConfiguration & 0xefbfffff) | 0x400000;
    if (family == 0x7890)
        hhcb->idConfiguration |= 0x10000000;
    hhcb->idConfiguration &= 0xff7fffff;
    if ((hhcb->deviceID >= 0x7874 && hhcb->deviceID <= 0x7876) ||
        (hhcb->deviceID >= 0x7884 && hhcb->deviceID <= 0x7885))
        hhcb->idConfiguration |= 0x80000000;
    else
        hhcb->idConfiguration &= 0x7fffffff;
}

void SCSIhStandardGetConfig(AdaptecU2HHCB *hhcb)
{
    hhcb->numberScbs = SCSIhGetMaxHardwareScbs(hhcb);
    hhcb->byte1f = hhcb->numberScbs;
    if (hhcb->numberScbs == 255)
        hhcb->flags |= 0x20000000;
    SCSIhGetCommonConfig(hhcb);
}

unsigned char SCSIhGetMaxHardwareScbs(AdaptecU2HHCB *hhcb)
{
    unsigned int saved = 0, count = 255, enabled;
    unsigned char selected;
    int i;
    if (!(OSMReadUExact8(*hhcb->ioHandle, 135) & 4))
        SCSIhPauseAndWait(hhcb);
    enabled = SCSIHEnableExtScbRam(hhcb);
    selected = OSMReadUExact8(*hhcb->ioHandle, 144);
    OSMWriteUExact8(*hhcb->ioHandle, 144, 255);
    for (i = 0; i < 4; ++i)
        saved |= (unsigned int)OSMReadUExact8(*hhcb->ioHandle, 160 + i) << (8 * i);
    OSMWriteUExact8(*hhcb->ioHandle, 160, 221);
    OSMWriteUExact8(*hhcb->ioHandle, 161, 102);
    OSMWriteUExact8(*hhcb->ioHandle, 162, 170);
    OSMWriteUExact8(*hhcb->ioHandle, 163, 85);
    for (;;) {
        OSMWriteUExact8(*hhcb->ioHandle, 144, count >> 1);
        if (OSMReadUExact8(*hhcb->ioHandle, 160) != 221 ||
            OSMReadUExact8(*hhcb->ioHandle, 161) != 102 ||
            OSMReadUExact8(*hhcb->ioHandle, 162) != 170 ||
            OSMReadUExact8(*hhcb->ioHandle, 163) != 85)
            break;
        count = (unsigned char)(count >> 1);
    }
    OSMWriteUExact8(*hhcb->ioHandle, 144, count);
    for (i = 0; i < 4; ++i)
        OSMWriteUExact8(*hhcb->ioHandle, 160 + i, saved >> (8 * i));
    OSMWriteUExact8(*hhcb->ioHandle, 144, selected);
    if (count != 255)
        count = (unsigned char)(count + 1);
    if (!enabled)
        SCSIHDisableExtScbRam(hhcb);
    return count;
}

void SCSIhNonStandardGetConfig(AdaptecU2HHCB *hhcb)
{
    hhcb->numberScbs = 255;
    SCSIhGetCommonConfig(hhcb);
}

void SCSIhGetCommonConfig(AdaptecU2HHCB *hhcb)
{
}

void SCSIhGetHardwareConfiguration(AdaptecU2HHCB *hhcb)
{
    unsigned char i, value;
    hhcb->configurationRegister = OSMReadUExact8(*hhcb->ioHandle, 133) & 0xfc;
    hhcb->maxDevices = (OSMReadUExact8(*hhcb->ioHandle, 31) & 2) ? 16 : 8;
    hhcb->flags &= 0xff9fffff;
    for (i = 0; i < hhcb->maxDevices; ++i) {
        hhcb->devices[i].rate = (OSMReadUExact8(*hhcb->ioHandle, 31) & 2) ? 0x81 : 1;
        hhcb->devices[i].flags = (hhcb->devices[i].flags & 0xb81f) | 0x4780;
    }
    SCSIhGetIDBasedConfiguration(hhcb);
    hhcb->hardwareFlags &= ~0x80000;
    hhcb->flags &= ~0x800;
    if (hhcb->hardwareFlags & 0x80000000) {
        hhcb->fifoThreshold = hhcb->hardware->setDataFifoThrshDefault(hhcb);
        hhcb->hostID = 7;
        hhcb->flags = (hhcb->flags & 0x7ff3ffff) | 0x80000000;
        hhcb->flags = (hhcb->flags & 0xfffeffff) |
            ((hhcb->hardware->defaultCacheThresholdEnable << 16) & 0x10000);
    } else {
        hhcb->fifoThreshold = hhcb->hardware->readDataFifoThrsh(hhcb);
        hhcb->hostID = OSMReadUExact8(*hhcb->ioHandle, hhcb->hardware->configurationRegister) & 15;
        value = OSMReadUExact8(*hhcb->ioHandle, 2);
        hhcb->flags = (hhcb->flags & 0x7ff3ffff) |
            (((value >> 3) & 3) << 18) | ((value & 32) ? 0x80000000 : 0);
        value = hhcb->hardware->getCacheThEn(hhcb);
        hhcb->flags = (hhcb->flags & 0xfffeffff) | ((value << 16) & 0x10000);
    }
}

void SCSIhGetIDBasedConfiguration(AdaptecU2HHCB *hhcb)
{
    unsigned int family = hhcb->deviceID & 0xfff0;
    unsigned char i, revision = hhcb->bytes02[2];
    hhcb->flags = (hhcb->flags & 0xe3ffffff) | 0x4000000;
    hhcb->flags = (hhcb->flags & 0xfc7fffff) |
        ((hhcb->idConfiguration & 0x800000) ? 0x3800000 : 0);
    if (hhcb->hardwareMode == 0) {
        hhcb->hardwareFlags &= 0xfcffffff;
        if (family == 0x7550 || family == 0x3860 || family == 0x7850 || family == 0x7860)
            hhcb->hardwareFlags |= 0x1000000;
        hhcb->flags &= ~0x1000;
    }
    if (hhcb->hardwareMode == 1) {
        if (revision == 1 && !(hhcb->deviceID & 64))
            hhcb->flags = (hhcb->flags & 0xffff5fff) | 0x2000;
        else if (!revision && !(hhcb->deviceID & 64))
            hhcb->flags |= 0xa000;
        else
            hhcb->flags &= 0xffff5fff;
        hhcb->hardwareFlags = (hhcb->hardwareFlags & 0xfeff7fff) | 0x2000000 |
            ((OSDReadPciConfiguration(hhcb, 64) & 128) ? 0x8000 : 0);
        hhcb->flags = (hhcb->flags & 0xfffdefff) | 0x1000;
        for (i = 0; i < hhcb->maxDevices; ++i) {
            switch ((hhcb->idConfiguration >> 20) & 3) {
            case 0: hhcb->devices[i].period = 19; break;
            case 1: hhcb->devices[i].period = 21; break;
            case 2: hhcb->devices[i].period = 143; break;
            case 3: hhcb->devices[i].period = 24; break;
            }
            hhcb->devices[i].offset = 127;
        }
    }
    for (i = 0; i < 16; ++i) {
        if ((hhcb->idConfiguration & 0x300000) == 0x300000)
            hhcb->devices[i].flags &= 0x7fff;
        else
            hhcb->devices[i].flags |= 0x8000;
    }
    if ((family == 0x7890 && hhcb->hardwareMode == 0) || hhcb->hardwareMode == 1)
        hhcb->hardwareFlags |= 0x40800000;
    else
        hhcb->hardwareFlags &= 0xbf7fffff;
    if ((hhcb->idConfiguration & 0x3000000) == 0x2000000)
        ((unsigned char *)&hhcb->worddc)[3] = 1;
    else if ((hhcb->idConfiguration & 0x3000000) == 0x1000000)
        ((unsigned char *)&hhcb->worddc)[3] = 0;
    if ((family == 0x7870 || family == 0x7550 || family == 0x7850 || family == 0x7860) &&
        hhcb->hardwareMode == 0)
        hhcb->hardwareFlags |= 0x300000;
}

int SCSIhStandard64SetupSequencer(AdaptecU2HHCB *hhcb)
{
    return SCSIhLoadSequencer(hhcb->ioHandle, Seq_s64, 2000);
}

int SCSIhSwapping32SetupSequencer(AdaptecU2HHCB *hhcb)
{
    return SCSIhLoadSequencer(hhcb->ioHandle, Seq_w32, 1772);
}

int SCSIhStandardAdvSetupSequencer(AdaptecU2HHCB *hhcb)
{
    return SCSIhLoadSequencer(hhcb->ioHandle, Seq_sAdv, 2072);
}

int SCSIhSwappingAdvSetupSequencer(AdaptecU2HHCB *hhcb)
{
    return SCSIhLoadSequencer(hhcb->ioHandle, Seq_wAdv, 2256);
}

void SCSIhStartToRunSequencer(AdaptecU2HHCB *hhcb)
{
    OSMWriteUExact8(*hhcb->ioHandle, 96, 48);
    OSMWriteUExact8(*hhcb->ioHandle, 98, (unsigned char)hhcb->firmware->word20);
    OSMWriteUExact8(*hhcb->ioHandle, 99, (unsigned char)hhcb->firmware->word20 >> 2);
    OSMWriteUExact8(*hhcb->ioHandle, 104, 128);
    OSMWriteUExact8(*hhcb->ioHandle, 135, 2);
    hhcb->flags &= ~0x4000;
}

void SCSIhInitializeHardware(AdaptecU2HHCB *hhcb)
{
    register unsigned int incomingCache asm("r28");
    unsigned char cache, value;
    unsigned int pci, family;
    /* The reference retains incoming r28 on the PCI cache-line default path. */
    asm volatile ("" : "=r" (incomingCache));
    cache = incomingCache;
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->hardware->configurationRegister, hhcb->hostID);
    value = OSMReadUExact8(*hhcb->ioHandle, 31) & 63;
    if (hhcb->hardwareMode == 1 && (hhcb->flags & 0x2000))
        value |= 32;
    OSMWriteUExact8(*hhcb->ioHandle, 31, value);
    hhcb->hardware->updateDataFifoThrsh(hhcb);
    OSMWriteUExact8(*hhcb->ioHandle, 1, 128);
    hhcb->hardware->updateCacheThEn(hhcb);
    hhcb->hardware->processAutoTerm(hhcb);
    value = ((hhcb->flags >> 15) & 24) + ((hhcb->flags & 0x80000000) ? 38 : 6);
    if (hhcb->flags & 0x10000000)
        value |= 1;
    OSMWriteUExact8(*hhcb->ioHandle, 2, value);
    hhcb->hardware->updateExtTerm(hhcb);
    if (hhcb->firmware->clearAllFast20Reg)
        hhcb->firmware->clearAllFast20Reg(hhcb);
    pci = OSDReadPciConfiguration(hhcb, 12);
    if (hhcb->hardwareMode == 0 && (pci & 60) == 4)
        OSDWritePciConfiguration(hhcb, 12, pci & 0xffffffc3);
    family = hhcb->deviceID & 0xfff0;
    if (family == 0x7890)
        OSDWritePciConfiguration(hhcb, 12, pci & 0xffffffc3);
    if (hhcb->hardwareMode == 0 &&
        ((family == 0x7890 && hhcb->bytes02[2] > 3) || family == 0x7880))
        cache = 0;
    else {
        switch (pci & 60) {
        case 8: cache = 31; break;
        case 16: cache = 63; break;
        case 32: cache = 127; break;
        default: break;
        }
    }
    if (family == 0x7890 && hhcb->hardwareMode == 0 && hhcb->bytes02[2] == 3) {
        pci = OSDReadPciConfiguration(hhcb, 4);
        OSDWritePciConfiguration(hhcb, 4, pci | 16);
    }
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[19], cache);
    if (hhcb->deviceID == 19) {
        pci = OSDReadPciConfiguration(hhcb, 12);
        OSDWritePciConfiguration(hhcb, 12, pci & 0xffffff00);
    }
}

void SCSIhAIC78XXProcessAutoTerm(AdaptecU2HHCB *hhcb)
{
    unsigned char cable;
    if (hhcb->flags & 0x4000000) {
        cable = SCSIhAIC78XXAutoTermCable(hhcb);
        hhcb->flags = (hhcb->flags & 0xe7ffffff) |
            ((cable & 8) ? 0x10000000 : 0) | ((cable & 16) ? 0x8000000 : 0);
    }
}

void SCSIhAICBayonetProcessAutoTerm(AdaptecU2HHCB *hhcb)
{
    unsigned char cable;
    if (hhcb->flags & 0x4000000) {
        cable = SCSIhCableSense(hhcb);
        hhcb->flags = (hhcb->flags & 0xe7ffffff) |
            ((cable & 8) ? 0x10000000 : 0) | ((cable & 16) ? 0x8000000 : 0);
        if (!(hhcb->flags & 0x800000))
            return;
    } else {
        if (!(hhcb->flags & 0x800000))
            return;
        cable = SCSIhCableSense(hhcb);
    }
    hhcb->flags = (hhcb->flags & 0xfcffffff) |
        ((cable & 64) ? 0x1000000 : 0) | ((cable & 32) ? 0x2000000 : 0);
}

void SCSIhAIC78XXUpdateExtTerm(AdaptecU2HHCB *hhcb)
{
    unsigned int count = 0x800000;
    unsigned char select = 8;
    if (hhcb->maxDevices == 16) {
        OSMWriteUExact8(*hhcb->ioHandle, 30, 32);
        do {
            if (OSMReadUExact8(*hhcb->ioHandle, 30) & 16)
                break;
        } while (count-- != 0);
        if ((hhcb->deviceID & 0xfff0) == 0x7890)
            select = OSDGetHostAddress(hhcb)->words[3] ? 8 : 0;
        else
            OSDGetHostAddress(hhcb);
        OSMWriteUExact8(*hhcb->ioHandle, 30, 40);
        OSMWriteUExact8(*hhcb->ioHandle, 29, select | ((hhcb->flags & 0x8000000) ? 80 : 16));
        OSMWriteUExact8(*hhcb->ioHandle, 29, select | ((hhcb->flags & 0x8000000) ? 64 : 0));
        OSMWriteUExact8(*hhcb->ioHandle, 29, 0);
        OSMWriteUExact8(*hhcb->ioHandle, 30, 0);
    }
}

void SCSIhAICBayonetUpdateExtTerm(AdaptecU2HHCB *hhcb)
{
    unsigned int count = 0x800000;
    unsigned char value = 0;
    if (hhcb->maxDevices == 16)
        value = (hhcb->flags >> 23) & 16;
    if (hhcb->flags & 0x2000000)
        value |= 32;
    if (hhcb->flags & 0x1000000)
        value |= 64;
    OSMWriteUExact8(*hhcb->ioHandle, 30, 32);
    do {
        if (OSMReadUExact8(*hhcb->ioHandle, 30) & 16)
            break;
    } while (count-- != 0);
    OSMWriteUExact8(*hhcb->ioHandle, 30, 40);
    OSMWriteUExact8(*hhcb->ioHandle, 29, value);
    OSMWriteUExact8(*hhcb->ioHandle, 29, value | 1);
    OSMWriteUExact8(*hhcb->ioHandle, 30, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 29, 0);
}
