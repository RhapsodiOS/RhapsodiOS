#ifndef RHAPSODIOS_AHCI_COMMAND_H
#define RHAPSODIOS_AHCI_COMMAND_H

#include "AHCIRegs.h"

void AHCIBuildIdentifyFIS(unsigned char fis[20], unsigned char packet);
int AHCIBuildDMAFIS(unsigned char fis[20], unsigned int lba,
                    unsigned int sectors, unsigned char write,
                    unsigned char lba48);
void AHCIBuildFlushFIS(unsigned char fis[20], unsigned char lba48);
void AHCIBuildPacketFIS(unsigned char fis[20]);

#endif
