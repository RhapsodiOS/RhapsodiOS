#include "AdaptecU2CHIMPrivate.h"

void SCSIhAbortTask(AdaptecU2HIOB *hiob)
{
    AdaptecU2HIOB *related = hiob->context.related;
    AdaptecU2HHCB *hhcb = related->context.unit->hhcb;
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135), i = 0;
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    if (hhcb->numberScbs) {
        while (i < hhcb->numberScbs && hhcb->activeHiobs[i] != related)
            ++i;
        if (i < hhcb->numberScbs) {
            hhcb->firmware->abortHIOB(hhcb, related, 4);
            switch (related->managerStatus) {
            case 1: hiob->status = 3; hiob->hostStatus = 38; break;
            case 2: hiob->status = 1; break;
            case 9: hiob->status = 0; hiob->hostStatus = 37; break;
            default: break;
            }
        }
    }
    if (i == hhcb->numberScbs) {
        hiob->status = 3;
        hiob->hostStatus = 36;
    }
    SCSIrCompleteSpecialHIOB(hiob);
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIhAbortTaskSet(AdaptecU2HIOB *hiob)
{
    AdaptecU2HHCB *hhcb = hiob->context.unit->hhcb;
    unsigned char target = hiob->context.unit->target;
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135), i;
    AdaptecU2HIOB *active;
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    for (i = 0; i < hhcb->numberScbs; ++i) {
        active = hhcb->activeHiobs[i];
        if (active != (AdaptecU2HIOB *)0xffffffff &&
            active->context.unit->hhcb == hhcb && active->context.unit->target == target)
            hhcb->firmware->abortHIOB(hhcb, active, 4);
    }
    hiob->status = 1;
    SCSIrCompleteSpecialHIOB(hiob);
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
}

unsigned char SCSIhCableSense(AdaptecU2HHCB *hhcb)
{
    unsigned char saved = OSMReadUExact8(*hhcb->ioHandle, 30);
    unsigned char select = 8, result = 0, first, second, value;
    unsigned int mode;
    AdaptecU2PciLocation *location;
    OSMWriteUExact8(*hhcb->ioHandle, 30, 32);
    hhcb->hardware->checkExtArbAckEnBit(hhcb);
    location = OSDGetHostAddress(hhcb);
    if ((hhcb->deviceID & 0xfff0) == 0x7890)
        select = location->words[3] ? 8 : 0;
    mode = (hhcb->hardwareFlags >> 24) & 3;
    if (mode == 0) {
        OSMWriteUExact8(*hhcb->ioHandle, 30, 40);
        OSMWriteUExact8(*hhcb->ioHandle, 29, select | 16);
        OSMWriteUExact8(*hhcb->ioHandle, 29, select);
        OSMWriteUExact8(*hhcb->ioHandle, 29, 0);
        OSMWriteUExact8(*hhcb->ioHandle, 29, select | 4);
        first = OSMReadUExact8(*hhcb->ioHandle, 29);
        OSMWriteUExact8(*hhcb->ioHandle, 29, 0);
        OSMWriteUExact8(*hhcb->ioHandle, 29, select | 48);
        OSMWriteUExact8(*hhcb->ioHandle, 29, select | 32);
        OSMWriteUExact8(*hhcb->ioHandle, 29, 32);
        OSMWriteUExact8(*hhcb->ioHandle, 29, select | 4);
        second = OSMReadUExact8(*hhcb->ioHandle, 29);
        OSMWriteUExact8(*hhcb->ioHandle, 29, 0);
        OSMWriteUExact8(*hhcb->ioHandle, 30, 0);
        if (OSMReadUExact8(*hhcb->ioHandle, 31) & 2) {
            if (!(first & 128)) result = 2;
            if (!(first & 64)) result |= 1;
            if (!(second & 64)) result |= 4;
        } else {
            if (!(first & 128)) result = 4;
            if (!(first & 64)) result |= 1;
        }
    } else if (mode == 1) {
        value = OSMReadUExact8(*hhcb->ioHandle, 27);
        OSMWriteUExact8(*hhcb->ioHandle, 27, (value & 0xcf) | 0x10);
        value = OSMReadUExact8(*hhcb->ioHandle, 29);
        SCSIhDelayCount500us(hhcb, 0);
        OSMWriteUExact8(*hhcb->ioHandle, 29, value | 12);
        value = OSMReadUExact8(*hhcb->ioHandle, 30);
        OSMWriteUExact8(*hhcb->ioHandle, 30, value | 32);
        SCSIhDelayCount500us(hhcb, 0);
        OSMWriteUExact8(*hhcb->ioHandle, 30, value & 0xdf);
        value = OSMReadUExact8(*hhcb->ioHandle, 29);
        if (!(value & 32)) result = 1;
        if (!(value & 64)) result |= 4;
    } else if (mode == 2) {
        OSMWriteUExact8(*hhcb->ioHandle, 30, 32);
        OSMWriteUExact8(*hhcb->ioHandle, 29, 2);
        result = OSMReadUExact8(*hhcb->ioHandle, 29);
        OSMWriteUExact8(*hhcb->ioHandle, 29, 0);
        OSMWriteUExact8(*hhcb->ioHandle, 30, 0);
    }
    OSMWriteUExact8(*hhcb->ioHandle, 30, saved);
    return result;
}

unsigned char SCSIhAIC78XXAutoTermCable(AdaptecU2HHCB *hhcb)
{
    unsigned char cables = SCSIhCableSense(hhcb), result;
    if (OSMReadUExact8(*hhcb->ioHandle, 31) & 2) {
        if (cables & 4)
            result = ((cables & 1) == (cables & 2)) ? 8 : 0;
        else
            result = (!(cables & 1) || !(cables & 2)) ? 8 : 0;
        if ((cables & 7) == 6)
            return result & 0xef;
        return result | 16;
    }
    return (!(cables & 4) || !(cables & 1)) ? 8 : 0;
}

void SCSIhAICBayonetWaitForBusStable(AdaptecU2HHCB *hhcb)
{
    unsigned char previous = OSMReadUExact8(*hhcb->ioHandle, 24) & 128, current;
    unsigned int count = 8000;
    for (;;) {
        if (OSMReadUExact8(*hhcb->ioHandle, 31) & 12)
            break;
        current = (OSMReadUExact8(*hhcb->ioHandle, 24) >> 1) & 64;
        if ((current != 0) != ((previous & 128) != 0)) {
            previous = (current != 0) << 7;
            if (!--count)
                break;
        }
    }
}

void SCSIhSwapping32SetBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask)
{
    unsigned char value = OSMReadUExact8(*hhcb->ioHandle, 96);
    OSMWriteUExact8(*hhcb->ioHandle, 96, value | 8);
    if (mask & 1)
        value = (unsigned char)(hhcb->firmware->word20 + 4) >> 2;
    else if (mask & 2)
        value = hhcb->firmware->word34 >> 2;
    else
        return;
    OSMWriteUExact8(*hhcb->ioHandle, 103, value);
    OSMWriteUExact8(*hhcb->ioHandle, 104, 0);
}

void SCSIhStandard64SetBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask)
{
    unsigned char value = OSMReadUExact8(*hhcb->ioHandle, 96);
    OSMWriteUExact8(*hhcb->ioHandle, 96, value | 8);
    if (mask & 1)
        value = (unsigned char)(hhcb->firmware->word24 + 4) >> 2;
    else if (mask & 2)
        value = hhcb->firmware->word34 >> 2;
    else
        return;
    OSMWriteUExact8(*hhcb->ioHandle, 103, value);
    OSMWriteUExact8(*hhcb->ioHandle, 104, 0);
}

void SCSIhSwappingAdvSetBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask)
{
    unsigned char value;
    if (mask & 1)
        value = OSMReadUExact8(*hhcb->ioHandle, 73) | 1;
    else if (mask & 2)
        value = OSMReadUExact8(*hhcb->ioHandle, 73) | 2;
    else
        return;
    OSMWriteUExact8(*hhcb->ioHandle, 73, value);
}

void SCSIhStandardAdvSetBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask)
{
    unsigned char value;
    if (mask & 1)
        value = OSMReadUExact8(*hhcb->ioHandle, 74) | 1;
    else if (mask & 2)
        value = OSMReadUExact8(*hhcb->ioHandle, 74) | 2;
    else
        return;
    OSMWriteUExact8(*hhcb->ioHandle, 74, value);
}

void SCSIhSwapping32ClearBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask)
{
    OSMWriteUExact8(*hhcb->ioHandle, 104, 128);
}

void SCSIhStandard64ClearBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask)
{
    OSMWriteUExact8(*hhcb->ioHandle, 104, 128);
}

void SCSIhSwappingAdvClearBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask)
{
    unsigned char value;
    if (mask & 1)
        value = OSMReadUExact8(*hhcb->ioHandle, 73) & 0xfe;
    else if (mask & 2)
        value = OSMReadUExact8(*hhcb->ioHandle, 73) & 0xfd;
    else
        return;
    OSMWriteUExact8(*hhcb->ioHandle, 73, value);
}

void SCSIhStandardAdvClearBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask)
{
    unsigned char value;
    if (mask & 1)
        value = OSMReadUExact8(*hhcb->ioHandle, 74) & 0xfe;
    else if (mask & 2)
        value = OSMReadUExact8(*hhcb->ioHandle, 74) & 0xfd;
    else
        return;
    OSMWriteUExact8(*hhcb->ioHandle, 74, value);
}

unsigned short SCSIhAIC78XXCalcScsiOption(unsigned short speed,
                                          unsigned char offset,
                                          unsigned char width)
{
    unsigned short rate = 0;
    if (speed >= 160 && speed <= 199) rate = 0x10;
    else if (speed >= 133 && speed <= 159) rate = 0x20;
    else if (speed >= 100 && speed <= 132) rate = 0;
    else if (speed >= 80 && speed <= 99) rate = 0x10;
    else if (speed >= 67 && speed <= 79) rate = 0x20;
    else if (speed >= 57 && speed <= 66) rate = 0x30;
    else if (speed >= 50 && speed <= 56) rate = 0x40;
    else if (speed >= 44 && speed <= 49) rate = 0x50;
    else if (speed >= 40 && speed <= 43) rate = 0x60;
    else if (speed >= 36 && speed <= 39) rate = 0x70;
    rate |= offset != 0;
    if (width == 16)
        rate |= 0x80;
    return rate;
}

unsigned short SCSIhAICBayonetCalcScsiOption(unsigned short speed,
                                            unsigned char offset,
                                            unsigned char width)
{
    unsigned short rate = 0;
    if (speed == 400) rate = 19;
    else if (speed >= 267 && speed <= 399) rate = 20;
    else if (speed >= 200 && speed <= 266) rate = 21;
    else if (speed >= 160 && speed <= 199) rate = 22;
    else if (speed >= 133 && speed <= 159) rate = 23;
    else if (speed >= 100 && speed <= 132) rate = 24;
    else if (speed >= 80 && speed <= 99) rate = 25;
    else if (speed >= 67 && speed <= 79) rate = 26;
    else if (speed >= 57 && speed <= 66) rate = 27;
    else if (speed >= 50 && speed <= 56) rate = 28;
    rate |= (offset << 8) & 0x7f00;
    if (width == 16)
        rate |= 0x80;
    return rate;
}

void SCSIhAIC78XXGetProfileParameters(AdaptecU2HWInformation *information,
                                      AdaptecU2HHCB *hhcb)
{
    unsigned int i;
    unsigned char current, requested, fast;
    for (i = 0; i < 16; ++i) {
        current = hhcb->firmware->getOption(hhcb, i);
        requested = hhcb->devices[i].rate;
        fast = (hhcb->devices[i].flags >> 15) & 1;
        information->targets[i].maximumSpeed = fast ? 200 : 100;
        information->targets[i].requestedSpeed = SCSIhAIC78XXGetSpeed(requested, fast);
        fast = hhcb->firmware->getFast20Reg(hhcb, i);
        information->targets[i].currentSpeed = SCSIhAIC78XXGetSpeed(current, fast);
        information->targets[i].currentOffset = current & 15;
        information->targets[i].requestedOffset = (requested & 15) ?
                                                  ((requested & 0x80) ? 8 : 15) : 0;
        information->targets[i].maximumOffset = (current & 0x80) ? 8 : 15;
        information->targets[i].maximumWidth = (OSMReadUExact8(*hhcb->ioHandle, 31) & 2) ? 16 : 8;
        information->targets[i].requestedWidth = (requested & 0x80) ? 16 : 8;
        information->targets[i].currentWidth = (current & 0x80) ? 16 : 8;
        information->targets[i].changed = 0;
    }
    information->minimumSpeed = 36;
}

void SCSIhAICBayonetGetProfileParameters(AdaptecU2HWInformation *information,
                                        AdaptecU2HHCB *hhcb)
{
    unsigned int i;
    unsigned short current;
    unsigned char requested;
    for (i = 0; i < 16; ++i) {
        current = hhcb->firmware->getOption(hhcb, i);
        requested = hhcb->devices[i].period;
        information->targets[i].maximumSpeed = ((requested & 127) <= 20) ? 400 :
                                                ((requested & 127) <= 23) ? 200 : 100;
        information->targets[i].requestedSpeed = SCSIhAICBayonetGetSpeed(requested, i);
        information->targets[i].currentSpeed = SCSIhAICBayonetGetSpeed(current, i);
        information->targets[i].currentOffset = (current >> 8) & 127;
        information->targets[i].maximumOffset = 127;
        information->targets[i].requestedOffset = hhcb->devices[i].offset;
        information->targets[i].maximumWidth = (OSMReadUExact8(*hhcb->ioHandle, 31) & 2) ? 16 : 8;
        information->targets[i].requestedWidth = (hhcb->devices[i].rate & 128) ? 16 : 8;
        information->targets[i].currentWidth = (current & 128) ? 16 : 8;
        information->targets[i].changed = 0;
    }
    information->minimumSpeed = 50;
}

void SCSIhAIC78XXPutProfileParameters(const AdaptecU2HWInformation *information,
                                      AdaptecU2HHCB *hhcb)
{
    unsigned int i;
    unsigned short speed;
    for (i = 0; i < 16; ++i) {
        if (information->targets[i].changed) {
            speed = information->targets[i].requestedSpeed;
            hhcb->devices[i].rate = SCSIhAIC78XXCalcScsiOption(speed,
                information->targets[i].requestedOffset, information->targets[i].requestedWidth);
            hhcb->devices[i].flags = (hhcb->devices[i].flags & 0x7fff) | ((speed > 132) << 15);
            if (SCSIHCheckDeviceIdle(hhcb, i))
                hhcb->firmware->xferOptAssign(hhcb, i, (hhcb->devices[i].rate & 0x81) ? 0x8f : 0);
        }
    }
}

void SCSIhAICBayonetPutProfileParameters(const AdaptecU2HWInformation *information,
                                        AdaptecU2HHCB *hhcb)
{
    unsigned int i;
    unsigned short option;
    unsigned char control, rate;
    for (i = 0; i < 16; ++i) {
        if (information->targets[i].changed) {
            option = SCSIhAICBayonetCalcScsiOption(information->targets[i].requestedSpeed,
                information->targets[i].requestedOffset, information->targets[i].requestedWidth);
            hhcb->devices[i].period = option;
            hhcb->devices[i].offset = option >> 8;
            hhcb->devices[i].rate = (option & 0x80) ? 0x80 : 0;
            if (hhcb->devices[i].offset & 127)
                hhcb->devices[i].rate |= 1;
            if (SCSIHCheckDeviceIdle(hhcb, i)) {
                rate = (hhcb->devices[i].rate & 0x81) ? 0x8f : 0;
                control = OSMReadUExact8(*hhcb->ioHandle, 135);
                if (!(control & 4))
                    SCSIhPauseAndWait(hhcb);
                hhcb->firmware->xferOptAssign(hhcb, i, rate);
                if (!(control & 4))
                    OSMWriteUExact8(*hhcb->ioHandle, 135, control);
            }
        }
    }
}

unsigned char SCSIhAIC78XXGetQNewTail(AdaptecU2HHCB *hhcb)
{
    return OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9]);
}

unsigned char SCSIhAICBayonetGetQNewTail(AdaptecU2HHCB *hhcb)
{
    unsigned char value = OSMReadUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9]);
    OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[9], value);
    return value;
}

void SCSIhAIC78XXUpdateCacheThEn(AdaptecU2HHCB *hhcb)
{
    unsigned char value;
    if ((hhcb->deviceID & 0xfff0) == 0x7880 && hhcb->bytes02[2] &&
        (hhcb->flags & 0x10000))
        value = OSMReadUExact8(*hhcb->ioHandle, 132) | 0x80;
    else {
        hhcb->flags &= ~0x10000U;
        value = OSMReadUExact8(*hhcb->ioHandle, 132) & 0x7f;
    }
    OSMWriteUExact8(*hhcb->ioHandle, 132, value);
}

void SCSIhAICBayonetUpdateCacheThEn(AdaptecU2HHCB *hhcb)
{
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135), value;
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    value = OSMReadUExact8(*hhcb->ioHandle, 132);
    if ((hhcb->flags & 0x18000) == 0x10000)
        value |= 0x80;
    else
        value &= 0x7f;
    OSMWriteUExact8(*hhcb->ioHandle, 132, value);
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIhStandardResetCCCtl(AdaptecU2HHCB *hhcb)
{
    OSMWriteUExact8(*hhcb->ioHandle, 238, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 235, 0);
}

void SCSIhStandardInitCCHHAddr(AdaptecU2HHCB *hhcb)
{
    OSMWriteUExact8(*hhcb->ioHandle, 228, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 229, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 230, 0);
    OSMWriteUExact8(*hhcb->ioHandle, 231, 0);
}

void SCSIhAIC78XXCheckExtArbAckEnBit(AdaptecU2HHCB *hhcb)
{
    unsigned int count = 0x800000;
    do {
        if (OSMReadUExact8(*hhcb->ioHandle, 30) & 0x10)
            break;
    } while (count--);
}

void SCSIhAICBayonetCheckExtArbAckEnBit(AdaptecU2HHCB *hhcb)
{
    unsigned int count = 0x800000;
    do {
        if (OSMReadUExact8(*hhcb->ioHandle, 30) & 0x10)
            break;
    } while (count--);
}

unsigned short SCSIhAIC78XXGetSpeed(unsigned short rate, unsigned char fastMode)
{
    if (fastMode) {
        switch (rate & 0x70) {
        case 0: return 200;
        case 0x10: return 160;
        case 0x20: return 133;
        default: return 36;
        }
    }
    switch (rate & 0x70) {
    case 0: return 100;
    case 0x10: return 80;
    case 0x20: return 67;
    case 0x30: return 57;
    case 0x40: return 50;
    case 0x50: return 44;
    case 0x60: return 40;
    default: return 36;
    }
}

unsigned short SCSIhAICBayonetGetSpeed(unsigned short rate, unsigned int unusedModeWord)
{
    unsigned short speed = 50;
    switch ((rate & 0x7f) - 19) {
    case 0: speed = 400; break;
    case 1: speed = 267; break;
    case 2: speed = 200; break;
    case 3: speed = 160; break;
    case 4: speed = 133; break;
    case 5: speed = 100; break;
    case 6: speed = 80; break;
    case 7: speed = 67; break;
    case 8: speed = 57; break;
    case 9: speed = 50; break;
    default: break;
    }
    return speed;
}

void SCSIhAIC78XXEnableIOErr(AdaptecU2HHCB *hhcb)
{
}

void SCSIhAICBayonetEnableIOErr(AdaptecU2HHCB *hhcb)
{
    unsigned char value = OSMReadUExact8(*hhcb->ioHandle, 16);
    OSMWriteUExact8(*hhcb->ioHandle, 16, value | 8);
}

unsigned int SCSIhAICBayonetGetScbRamCtrls(AdaptecU2HHCB *hhcb)
{
    return OSMReadUExact8(*hhcb->ioHandle, 132);
}

unsigned int SCSIhAIC78XXGetScbRamCtrls(AdaptecU2HHCB *hhcb)
{
    return OSDReadPciConfiguration(hhcb, 64);
}

void SCSIhAICBayonetPutScbRamCtrls(AdaptecU2HHCB *hhcb, unsigned int value)
{
    OSMWriteUExact8(*hhcb->ioHandle, 132, value);
}

void SCSIhAIC78XXPutScbRamCtrls(AdaptecU2HHCB *hhcb, unsigned int value)
{
    OSDWritePciConfiguration(hhcb, 64, value);
}

unsigned char SCSIhAIC78XXGetCacheThEn(AdaptecU2HHCB *hhcb)
{
    return (OSMReadUExact8(*hhcb->ioHandle, 132) & 0x80) != 0;
}

unsigned char SCSIhAICBayonetGetCacheThEn(AdaptecU2HHCB *hhcb)
{
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135);
    unsigned char enabled;
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    enabled = (OSMReadUExact8(*hhcb->ioHandle, 132) & 0x80) != 0;
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
    return enabled;
}

void SCSIhSetAddressScbBA32(AdaptecU2HHCB *hhcb, unsigned char offset,
                             const unsigned char *virtualAddress)
{
    unsigned int address = OSDGetBusAddress(hhcb, 1, virtualAddress);
    OSMWriteUExact8(*hhcb->ioHandle, offset, address);
    OSMWriteUExact8(*hhcb->ioHandle, offset + 1, address >> 8);
    OSMWriteUExact8(*hhcb->ioHandle, offset + 2, address >> 16);
    OSMWriteUExact8(*hhcb->ioHandle, offset + 3, address >> 24);
}

unsigned int SCSIhGetEntity32FromScb(AdaptecU2HHCB *hhcb, unsigned char offset)
{
    unsigned int value = OSMReadUExact8(*hhcb->ioHandle, offset);
    value |= (unsigned int)OSMReadUExact8(*hhcb->ioHandle, offset + 1) << 8;
    value |= (unsigned int)OSMReadUExact8(*hhcb->ioHandle, offset + 2) << 16;
    value |= (unsigned int)OSMReadUExact8(*hhcb->ioHandle, offset + 3) << 24;
    return value;
}

unsigned int SCSIhGetAddressScbBA32(AdaptecU2HHCB *hhcb, unsigned char offset)
{
    return SCSIhGetEntity32FromScb(hhcb, offset);
}

unsigned int SCSIhCompareBusAddress(unsigned int left, unsigned int right)
{
    return left != right;
}

void SCSIhAIC78XXLoadScsiRate(AdaptecU2HHCB *hhcb, unsigned short rate)
{
    OSMWriteUExact8(*hhcb->ioHandle, 4, rate);
}

void SCSIhAICBayonetLoadScsiRate(AdaptecU2HHCB *hhcb, unsigned short rate)
{
    OSMWriteUExact8(*hhcb->ioHandle, 4, rate);
    OSMWriteUExact8(*hhcb->ioHandle, 5, rate >> 8);
}

void SCSIhAIC78XXResetDFifo(AdaptecU2HHCB *hhcb)
{
    OSMWriteUExact8(*hhcb->ioHandle, 147, 1);
}

void SCSIhAICBayonetResetDFifo(AdaptecU2HHCB *hhcb)
{
    unsigned char value = OSMReadUExact8(*hhcb->ioHandle, 1);
    OSMWriteUExact8(*hhcb->ioHandle, 1, value | 0x12);
}

int SCSIhLoadSequencer(const AdaptecU2IOHandle *handle,
                         const unsigned char *program, int byteCount)
{
    unsigned char control = OSMReadUExact8(*handle, 96);
    int i;
    OSMWriteUExact8(*handle, 96, 0xb1);
    OSMWriteUExact8(*handle, 98, 0);
    OSMWriteUExact8(*handle, 99, 0);
    for (i = 0; i < byteCount; ++i)
        OSMWriteUExact8(*handle, 97, program[i]);
    OSMWriteUExact8(*handle, 96, 0xb0);
    OSMWriteUExact8(*handle, 96, 0xb1);
    OSMWriteUExact8(*handle, 98, 0);
    OSMWriteUExact8(*handle, 99, 0);
    for (i = 0; i < byteCount; ++i) {
        if (OSMReadUExact8(*handle, 97) != program[i])
            return -1;
    }
    OSMWriteUExact8(*handle, 96, 0xb0);
    OSMWriteUExact8(*handle, 96, control);
    return 0;
}

unsigned char SCSIhWait4Req(AdaptecU2HHCB *hhcb)
{
    unsigned int count = 0x800000;
    unsigned char status, signal, phase;
    for (;;) {
        do {
            if (!(OSMReadUExact8(*hhcb->ioHandle, 3) & 1))
                break;
        } while (--count);
        count = 0x800000;
        for (;;) {
            status = OSMReadUExact8(*hhcb->ioHandle, 12);
            if (status & 1)
                break;
            --count;
            if ((status & 0x28) || !count)
                return 255;
        }
        OSMWriteUExact8(*hhcb->ioHandle, 12, 4);
        signal = OSMReadUExact8(*hhcb->ioHandle, 3);
        phase = signal & 0xe0;
        if (!(signal & 0x40) || phase == 64 ||
            !(OSMReadUExact8(*hhcb->ioHandle, 12) & 4))
            return phase;
        OSMWriteUExact8(*hhcb->ioHandle, 3, phase);
        OSMReadUExact8(*hhcb->ioHandle, 6);
    }
}

void SCSIhDelayCount500us(AdaptecU2HHCB *hhcb, unsigned int count)
{
    unsigned char control, low, high, timer;
    unsigned short delay;
    unsigned int i;
    if (!count)
        return;
    control = OSMReadUExact8(*hhcb->ioHandle, 135);
    if (!(control & 4))
        SCSIhPauseAndWait(hhcb);
    delay = hhcb->hardware->delayCount;
    timer = hhcb->firmware->registers[1];
    low = OSMReadUExact8(*hhcb->ioHandle, timer);
    high = OSMReadUExact8(*hhcb->ioHandle, timer + 1);
    for (i = 0; i != count; ++i) {
        SCSIhPauseAndWait(hhcb);
        OSMWriteUExact8(*hhcb->ioHandle, timer, delay);
        OSMWriteUExact8(*hhcb->ioHandle, timer + 1, delay >> 8);
        OSMWriteUExact8(*hhcb->ioHandle, 98, (hhcb->firmware->word14 & 255) >> 2);
        OSMWriteUExact8(*hhcb->ioHandle, 99, 0);
        SCSIhUnPause(hhcb);
        do {
            while (!(OSMReadUExact8(*hhcb->ioHandle, 135) & 4))
                ;
        } while (!(SCSIhReadINTSTAT(hhcb) & 5));
        if (hhcb->hardware->seqStretchWorkaround)
            hhcb->hardware->seqStretchWorkaround(hhcb);
        OSMWriteUExact8(*hhcb->ioHandle, 12, 32);
        OSMWriteUExact8(*hhcb->ioHandle, 146, 5);
    }
    OSMWriteUExact8(*hhcb->ioHandle, timer, low);
    OSMWriteUExact8(*hhcb->ioHandle, timer + 1, high);
    if (!(control & 4))
        SCSIhWriteHCNTRL(hhcb, control);
}

void SCSIhSetupAssignScbBuffer(AdaptecU2HHCB *hhcb)
{
    hhcb->scbBusAddress = OSDGetBusAddress(hhcb, 1, hhcb->scbBuffers);
    hhcb->scbBufferSize = SCSIFirmware[hhcb->firmwareMode]->word04 * hhcb->numberScbs;
}

void SCSIhAICBayonetSeqStretchWorkaround(AdaptecU2HHCB *hhcb)
{
    OSMReadUExact8(*hhcb->ioHandle, 238);
}

void SCSIhWWWriteHCNTRL(const AdaptecU2IOHandle *handle, unsigned char value)
{
    unsigned char control;
    if (!(value & 4)) {
        control = OSMReadUExact8(*handle, 135);
        if (!(control & 4)) {
            OSMWriteUExact8(*handle, 135, control | 4);
            while (!(OSMReadUExact8(*handle, 135) & 4))
                ;
        }
        if (OSMReadUExact8(*handle, 145) & 13)
            value |= 4;
    }
    OSMWriteUExact8(*handle, 135, value);
}

void SCSIhWriteHCNTRL(AdaptecU2HHCB *hhcb, unsigned char value)
{
    if (hhcb->hardwareFlags & 0x200000)
        SCSIhWWWriteHCNTRL(hhcb->ioHandle, value);
    else
        OSMWriteUExact8(*hhcb->ioHandle, 135, value);
}

unsigned char SCSIhWWReadINTSTAT(const AdaptecU2IOHandle *handle)
{
    unsigned char control = OSMReadUExact8(*handle, 135), status;
    if (control & 4)
        return OSMReadUExact8(*handle, 145);
    OSMWriteUExact8(*handle, 135, control | 4);
    while (!(OSMReadUExact8(*handle, 135) & 4))
        ;
    status = OSMReadUExact8(*handle, 145);
    if (status & 13)
        control |= 4;
    OSMWriteUExact8(*handle, 135, control);
    return status;
}

unsigned char SCSIhReadINTSTAT(AdaptecU2HHCB *hhcb)
{
    if (hhcb->hardwareFlags & 0x100000)
        return SCSIhWWReadINTSTAT(hhcb->ioHandle);
    return OSMReadUExact8(*hhcb->ioHandle, 145);
}

void SCSIhPauseAndWait(AdaptecU2HHCB *hhcb)
{
    unsigned int count = 0x800000;
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135);
    SCSIhWriteHCNTRL(hhcb, control | 4);
    do {
        if (OSMReadUExact8(*hhcb->ioHandle, 135) & 4)
            break;
    } while (--count);
    if (hhcb->hardware->seqStretchWorkaround)
        hhcb->hardware->seqStretchWorkaround(hhcb);
}

void SCSIhUnPause(AdaptecU2HHCB *hhcb)
{
    unsigned char control = OSMReadUExact8(*hhcb->ioHandle, 135);
    SCSIhWriteHCNTRL(hhcb, control & 0xfb);
}

unsigned int SCSIhScamSupportCheck()
{
    return 0;
}

void SCSIhWait2usec(unsigned char value, const AdaptecU2IOHandle *handle)
{
    int i;
    for (i = 0; i < 3; ++i) {
        while (!(OSMReadUExact8(*handle, 30) & 0x10))
            ;
        OSMWriteUExact8(*handle, 30, value);
    }
}

void SCSIhSendE2Address(unsigned int address, int bitCount,
                         const AdaptecU2IOHandle *handle)
{
    unsigned int mask = 1U << (bitCount - 1);
    unsigned char value;
    int i;
    OSMWriteUExact8(*handle, 30, 42);
    SCSIhWait2usec(42, handle);
    OSMWriteUExact8(*handle, 30, 46);
    SCSIhWait2usec(46, handle);
    OSMWriteUExact8(*handle, 30, 42);
    SCSIhWait2usec(42, handle);
    for (i = 0; i < bitCount; ++i) {
        value = (address & mask) ? 42 : 40;
        OSMWriteUExact8(*handle, 30, value);
        SCSIhWait2usec(value, handle);
        OSMWriteUExact8(*handle, 30, value | 4);
        SCSIhWait2usec(value | 4, handle);
        address *= 2;
    }
    OSMWriteUExact8(*handle, 30, 40);
    SCSIhWait2usec(40, handle);
}

unsigned short SCSIhReadE2Register(unsigned int address,
                                   const AdaptecU2IOHandle *handle,
                                   unsigned char extendedAddress)
{
    unsigned short value = 0;
    int i;
    SCSIhSendE2Address(address | (extendedAddress ? 0x200 : 0x80),
                      extendedAddress ? 10 : 8, handle);
    for (i = 0; i < 16; ++i) {
        OSMWriteUExact8(*handle, 30, 44);
        SCSIhWait2usec(44, handle);
        OSMWriteUExact8(*handle, 30, 40);
        value = (value * 2) & 0xfffe;
        if (OSMReadUExact8(*handle, 30) & 1)
            value |= 1;
        SCSIhWait2usec(40, handle);
    }
    OSMWriteUExact8(*handle, 30, 32);
    SCSIhWait2usec(32, handle);
    return value;
}

void SCSIhWriteE2Register(unsigned int address, unsigned short value,
                           const AdaptecU2IOHandle *handle,
                           unsigned char extendedAddress)
{
    unsigned char data;
    int i;
    SCSIhSendE2Address(address | (extendedAddress ? 0x100 : 0x40),
                      extendedAddress ? 10 : 8, handle);
    for (i = 0; i < 16; ++i) {
        data = (value & 0x8000) ? 42 : 40;
        OSMWriteUExact8(*handle, 30, data);
        SCSIhWait2usec(data, handle);
        OSMWriteUExact8(*handle, 30, data | 4);
        SCSIhWait2usec(data | 4, handle);
        value *= 2;
    }
    OSMWriteUExact8(*handle, 30, 40);
    SCSIhWait2usec(40, handle);
    OSMWriteUExact8(*handle, 30, 32);
    SCSIhWait2usec(32, handle);
    OSMWriteUExact8(*handle, 30, 40);
    SCSIhWait2usec(40, handle);
    while (!(OSMReadUExact8(*handle, 30) & 1))
        ;
    OSMWriteUExact8(*handle, 30, 32);
    SCSIhWait2usec(32, handle);
}
