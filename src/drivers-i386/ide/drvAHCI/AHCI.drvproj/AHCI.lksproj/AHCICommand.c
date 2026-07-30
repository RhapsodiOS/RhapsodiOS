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

int AHCIBuildPacketCommand(unsigned char fis[20], unsigned char acmd[16],
                           const unsigned char *cdb,
                           unsigned int cdbLength,
                           unsigned int transferBytes,
                           unsigned char write)
{
    unsigned int byteCount;

    if (fis == 0 || acmd == 0 || cdb == 0 ||
        (cdbLength != 12 && cdbLength != 16) ||
        transferBytes > 131072U)
        return -1;
    AHCIBuildPacketFIS(fis);
    memset(acmd, 0, 16);
    memcpy(acmd, cdb, cdbLength);
    if (transferBytes == 0)
        return 0;
    fis[3] = (unsigned char)(0x01U | (write ? 0U : 0x04U));
    byteCount = transferBytes > 0xffffU ? 0xffffU : transferBytes;
    fis[5] = (unsigned char)byteCount;
    fis[6] = (unsigned char)(byteCount >> 8);
    return 0;
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

int AHCIParseIdentify(const unsigned short id[256], AHCICapacity *out)
{
    unsigned int lba28;
    unsigned int lba48;

    if (id == 0 || out == 0 || (id[49] & 0x0200) == 0)
        return -1;

    lba28 = (unsigned int)id[60] | ((unsigned int)id[61] << 16);
    if (lba28 == 0)
        return -1;

    out->sectors = lba28;
    out->lba48 = 0;
    out->clamped = 0;
    out->logicalSectorIs512 = 1;

    if ((id[106] & 0xc000) == 0x4000 && (id[106] & 0x1000) != 0) {
        if (id[117] != 256 || id[118] != 0)
            return -1;
    }

    if ((id[86] & 0x0400) == 0)
        return 0;
    out->lba48 = 1;
    if (id[100] == 0 && id[101] == 0 && id[102] == 0 && id[103] == 0)
        return 0;

    if (id[102] != 0 || id[103] != 0) {
        out->sectors = 0xffffffffU;
        out->clamped = 1;
        return 0;
    }

    lba48 = (unsigned int)id[100] | ((unsigned int)id[101] << 16);
    if (lba48 != 0)
        out->sectors = lba48;
    return 0;
}

int AHCISelectDMACommand(unsigned int lba, unsigned int sectors,
                         unsigned char write, unsigned char lba48,
                         unsigned char *command, unsigned char *useLba48)
{
    if (command == 0 || useLba48 == 0 || sectors == 0 || sectors > 256)
        return -1;
    if (lba > 0xffffffffU - (sectors - 1))
        return -1;

    *useLba48 = lba > 0x0fffffffU - (sectors - 1);
    if (*useLba48 && !lba48)
        return -1;
    if (*useLba48)
        *command = write ? 0x35 : 0x25;
    else
        *command = write ? 0xca : 0xc8;
    return 0;
}

int AHCIBuildPRDT(AHCIPRDTEntry *prd, unsigned int maxPrds,
                  const AHCISegment *segments, unsigned int segmentCount,
                  unsigned int transferBytes)
{
    unsigned int index;
    unsigned int count;
    unsigned int length;
    unsigned int total;

    if (prd == 0 || segments == 0 || maxPrds == 0 || maxPrds > 32 ||
        segmentCount == 0 || transferBytes == 0 || transferBytes > 131072)
        return -1;

    count = 0;
    total = 0;
    for (index = 0; index < segmentCount; ++index) {
        if (segments[index].length == 0 ||
            (segments[index].address & 1) != 0 ||
            (segments[index].length & 1) != 0 ||
            segments[index].address > 0xffffffffU -
                                      (segments[index].length - 1) ||
            segments[index].length > transferBytes - total)
            return -1;
        total += segments[index].length;

        if (count != 0 &&
            prd[count - 1].dba < 0xffffffffU -
                                      (prd[count - 1].dbc_ioc & 0x003fffffU) &&
            prd[count - 1].dba +
                    (prd[count - 1].dbc_ioc & 0x003fffffU) + 1 ==
                segments[index].address) {
            length = (prd[count - 1].dbc_ioc & 0x003fffffU) + 1;
            if (length <= 0x00400000U - segments[index].length) {
                prd[count - 1].dbc_ioc =
                    (length + segments[index].length - 1) & 0x003fffffU;
                continue;
            }
        }

        if (count == maxPrds)
            return -1;
        prd[count].dba = segments[index].address;
        prd[count].dbau = 0;
        prd[count].reserved = 0;
        prd[count].dbc_ioc = (segments[index].length - 1) & 0x003fffffU;
        ++count;
    }

    if (total != transferBytes)
        return -1;
    for (index = 0; index < count; ++index) {
        if ((prd[index].dba & 1) != 0 || (prd[index].dbc_ioc & 1) == 0)
            return -1;
    }
    prd[count - 1].dbc_ioc |= 0x80000000U;
    return (int)count;
}

void AHCIInitCommandHeader(AHCICommandHeader *header, unsigned int tablePA,
                           unsigned int prdtCount, unsigned char write,
                           unsigned char atapi)
{
    memset(header, 0, sizeof(*header));
    if (prdtCount > 32)
        return;
    header->flags = (unsigned short)(5U | (write ? 0x40U : 0U) |
                                     (atapi ? 0x20U : 0U));
    header->prdtl = (unsigned short)prdtCount;
    header->ctba = tablePA;
}
