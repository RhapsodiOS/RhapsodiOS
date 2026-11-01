#ifndef RHAPSODIOS_AHCI_HBA_H
#define RHAPSODIOS_AHCI_HBA_H

#include "AHCIRegs.h"

typedef AHCIU32 (*AHCIHBARead)(void *context, AHCIU32 offset);
typedef void (*AHCIHBAWrite)(void *context, AHCIU32 offset, AHCIU32 value);
typedef void (*AHCIHBADelay)(void *context, unsigned int milliseconds);
typedef void (*AHCIHBABarrier)(void *context);

typedef struct {
    void *context;
    AHCIHBARead read;
    AHCIHBAWrite write;
    AHCIHBADelay delay;
    AHCIHBABarrier barrier;
} AHCIHBAOps;

typedef struct {
    AHCIU32 version;
    AHCIU32 capabilities;
    AHCIU32 capabilities2;
    AHCIU32 portsImplemented;
} AHCIHBAInfo;

typedef enum {
    AHCI_HBA_SUCCESS = 0,
    AHCI_HBA_BAD_ARGUMENT,
    AHCI_HBA_INVALID_REGISTERS,
    AHCI_HBA_INVALID_PI,
    AHCI_HBA_BOHC_TIMEOUT,
    AHCI_HBA_RESET_TIMEOUT
} AHCIHBAResult;

AHCIHBAResult AHCIHBAInitialize(const AHCIHBAOps *ops, AHCIHBAInfo *info);

#endif
