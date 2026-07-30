#ifndef RHAPSODIOS_AHCI_COMMAND_H
#define RHAPSODIOS_AHCI_COMMAND_H

#include "AHCIRegs.h"

typedef struct {
    unsigned int sectors;
    unsigned char lba48;
    unsigned char clamped;
    unsigned char logicalSectorIs512;
} AHCICapacity;

typedef struct {
    unsigned int address;
    unsigned int length;
} AHCISegment;

void AHCIBuildIdentifyFIS(unsigned char fis[20], unsigned char packet);
int AHCIBuildDMAFIS(unsigned char fis[20], unsigned int lba,
                    unsigned int sectors, unsigned char write,
                    unsigned char lba48);
void AHCIBuildFlushFIS(unsigned char fis[20], unsigned char lba48);
void AHCIBuildPacketFIS(unsigned char fis[20]);
int AHCIParseIdentify(const unsigned short id[256], AHCICapacity *out);
int AHCISelectDMACommand(unsigned int lba, unsigned int sectors,
                         unsigned char write, unsigned char lba48,
                         unsigned char *command, unsigned char *useLba48);
int AHCIBuildPRDT(AHCIPRDTEntry *prd, unsigned int maxPrds,
                  const AHCISegment *segments, unsigned int segmentCount,
                  unsigned int transferBytes);
void AHCIInitCommandHeader(AHCICommandHeader *header, unsigned int tablePA,
                           unsigned int prdtCount, unsigned char write,
                           unsigned char atapi);

#endif
