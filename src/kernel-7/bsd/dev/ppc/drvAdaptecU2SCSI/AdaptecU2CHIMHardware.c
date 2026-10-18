#include "AdaptecU2CHIMPrivate.h"

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
