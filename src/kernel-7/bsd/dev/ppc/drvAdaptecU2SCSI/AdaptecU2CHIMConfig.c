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
            hhcb->idConfiguration = (hhcb->idConfiguration & 0xffff) |
                (subsystem & 0xffff0000);
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
