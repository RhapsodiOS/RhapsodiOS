#include <string.h>

#include "AHCICommand.h"

static void AHCIBuildH2DFIS(unsigned char fis[20], unsigned char command)
{
    memset(fis, 0, 20);
    fis[0] = 0x27;
    fis[1] = 0x80;
    fis[2] = command;
}

void AHCIBuildIdentifyFIS(unsigned char fis[20], unsigned char packet)
{
    AHCIBuildH2DFIS(fis, packet ? 0xa1 : 0xec);
}

void AHCIBuildPacketFIS(unsigned char fis[20])
{
    AHCIBuildH2DFIS(fis, 0xa0);
}

int AHCIBuildDMAFIS(unsigned char fis[20], unsigned int lba,
                    unsigned int sectors, unsigned char write,
                    unsigned char lba48)
{
    AHCIBuildH2DFIS(fis, write ? (lba48 ? 0x35 : 0xca) :
                    (lba48 ? 0x25 : 0xc8));

    if (sectors == 0 || sectors > 256)
        return -1;
    if (!lba48 && lba > 0x0fffffffU - (sectors - 1))
        return -1;

    fis[4] = (unsigned char)lba;
    fis[5] = (unsigned char)(lba >> 8);
    fis[6] = (unsigned char)(lba >> 16);
    fis[7] = (unsigned char)(0x40 | (lba48 ? 0 : (lba >> 24)));
    if (lba48)
        fis[8] = (unsigned char)(lba >> 24);
    fis[12] = (unsigned char)sectors;
    if (lba48)
        fis[13] = (unsigned char)(sectors >> 8);
    return 0;
}

void AHCIBuildFlushFIS(unsigned char fis[20], unsigned char lba48)
{
    AHCIBuildH2DFIS(fis, lba48 ? 0xea : 0xe7);
}
