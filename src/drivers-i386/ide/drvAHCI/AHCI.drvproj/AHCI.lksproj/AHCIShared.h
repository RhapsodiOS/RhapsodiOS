#ifndef RHAPSODIOS_AHCI_SHARED_H
#define RHAPSODIOS_AHCI_SHARED_H

#include "AHCIRegs.h"

#define AHCI_ABAR_LENGTH             0x1100U
#define AHCI_MAX_PORTS 32U

typedef struct {
    volatile unsigned char *base;
    AHCIU32 length;
} AHCIMMIOContext;

#endif
