#ifndef _PEXPERT_MACRISC_DT_H_
#define _PEXPERT_MACRISC_DT_H_

#include "macrisc_discovery.h"

/*
 * The only view of firmware that capture needs.  The kernel adapter walks
 * the flattened device tree; the host tests supply a fake tree.
 */
typedef void *PEFirmwareNode;

typedef struct {
    void *context;
    PEFirmwareNode (*root)(void *context);
    unsigned int (*childCount)(void *context, PEFirmwareNode node);
    PEFirmwareNode (*firstChild)(void *context, PEFirmwareNode node);
    PEFirmwareNode (*nextSibling)(void *context, PEFirmwareNode node);
    PEProperty (*property)(void *context, PEFirmwareNode node,
        const char *name);
} PEMacRISCFirmware;

PEMacRISCStatus PEMacRISCCapture(const PEMacRISCFirmware *firmware,
    PEMacRISCPlatform *platform, PEPlatformError *error);

/* Kernel only: capture the booted device tree into static storage. */
PEMacRISCStatus PEMacRISCDiscoverDeviceTree(PEPlatformError *error);
const PEMacRISCPlatform *PEMacRISCGetPlatform(void);
void PEMacRISCPrintFailure(PEMacRISCStatus status, PEPlatformError error);

#endif /* _PEXPERT_MACRISC_DT_H_ */
