#ifndef RHAPSODIOS_AHCI_PCI_H
#define RHAPSODIOS_AHCI_PCI_H

#include "AHCIRegs.h"

#define AHCI_ICH9_PCI_ID             0x29228086U
#define AHCI_PCI_CLASS_CODE          0x010601U

#define AHCI_PCI_ID_REGISTER         0x00U
#define AHCI_PCI_COMMAND_REGISTER    0x04U
#define AHCI_PCI_CLASS_REGISTER      0x08U
#define AHCI_PCI_BAR5_REGISTER       0x24U
#define AHCI_PCI_INTERRUPT_REGISTER  0x3cU

#define AHCI_PCI_COMMAND_MASK        0x0000ffffU
#define AHCI_PCI_COMMAND_MEMORY      0x00000002U
#define AHCI_PCI_COMMAND_MASTER      0x00000004U

#define AHCI_PCI_BAR_IO              0x00000001U
#define AHCI_PCI_BAR_TYPE_MASK       0x00000006U
#define AHCI_PCI_BAR_TYPE_32         0x00000000U
#define AHCI_PCI_BAR_PREFETCH        0x00000008U
#define AHCI_PCI_BAR_MEMORY_MASK     0xfffffff0U

typedef enum {
    AHCI_PCI_SUCCESS = 0,
    AHCI_PCI_BAD_ARGUMENT,
    AHCI_PCI_INVALID_BAR,
    AHCI_PCI_INVALID_INTERRUPT,
    AHCI_PCI_COMMAND_NOT_ENABLED
} AHCIPCIResult;

AHCIPCIResult AHCIPCIValidateBAR5(AHCIU32 bar5, AHCIU32 span,
                                  AHCIU32 *physicalBase);
AHCIPCIResult AHCIPCIPlanCommand(AHCIU32 originalConfig,
                                 AHCIU32 *enableWrite,
                                 AHCIU32 *restoreWrite,
                                 unsigned char *changed);
AHCIPCIResult AHCIPCIValidateCommandReadback(AHCIU32 readback);
AHCIPCIResult AHCIPCIInterruptLine(AHCIU32 interruptConfig,
                                   unsigned int *interruptLine);

#endif
