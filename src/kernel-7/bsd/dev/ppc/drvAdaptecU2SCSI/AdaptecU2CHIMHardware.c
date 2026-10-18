#include "AdaptecU2CHIMPrivate.h"

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
