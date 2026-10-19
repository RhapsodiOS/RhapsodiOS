#include "AdaptecU2CHIMPrivate.h"

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
