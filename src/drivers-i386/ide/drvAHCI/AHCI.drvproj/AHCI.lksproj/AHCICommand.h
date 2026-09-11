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
int AHCIBuildPacketCommand(unsigned char fis[20], unsigned char acmd[16],
                           const unsigned char *cdb,
                           unsigned int cdbLength,
                           unsigned int transferBytes,
                           unsigned char write,
                           unsigned char dmaDirSupported);
int AHCIATAPIShouldRequestSense(unsigned char opcode,
                                unsigned char ignoreChkcond);
int AHCIATAPISenseDataValid(int succeeded, unsigned int transferred);
/* Status-returning APIs may leave outputs partially written on error. */
int AHCIParseIdentify(const unsigned short id[256], AHCICapacity *out);
int AHCISelectDMACommand(unsigned int lba, unsigned int sectors,
                         unsigned char write, unsigned char lba48,
                         unsigned char *command, unsigned char *useLba48);
int AHCIBuildPRDT(AHCIPRDTEntry *prd, unsigned int maxPrds,
                  const AHCISegment *segments, unsigned int segmentCount,
                  unsigned int transferBytes);
/* AHCIInitCommandHeader leaves header zeroed when prdtCount exceeds 32. */
void AHCIInitCommandHeader(AHCICommandHeader *header, unsigned int tablePA,
                           unsigned int prdtCount, unsigned char write,
                           unsigned char atapi);

#endif
