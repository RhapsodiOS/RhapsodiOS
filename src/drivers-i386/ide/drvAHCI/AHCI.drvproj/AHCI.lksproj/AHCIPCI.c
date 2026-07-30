#include "AHCIPCI.h"

AHCIPCIResult AHCIPCIValidateBAR5(AHCIU32 bar5, AHCIU32 span,
                                  AHCIU32 *physicalBase)
{
    AHCIU32 base;

    if (physicalBase == 0 || span == 0)
        return AHCI_PCI_BAD_ARGUMENT;
    *physicalBase = 0;
    if (bar5 == 0 || bar5 == 0xffffffffU ||
        (bar5 & AHCI_PCI_BAR_IO) != 0 ||
        (bar5 & AHCI_PCI_BAR_TYPE_MASK) != AHCI_PCI_BAR_TYPE_32 ||
        (bar5 & AHCI_PCI_BAR_PREFETCH) != 0)
        return AHCI_PCI_INVALID_BAR;
    base = bar5 & AHCI_PCI_BAR_MEMORY_MASK;
    if (base == 0 || base == AHCI_PCI_BAR_MEMORY_MASK ||
        base > 0xffffffffU - (span - 1U))
        return AHCI_PCI_INVALID_BAR;
    *physicalBase = base;
    return AHCI_PCI_SUCCESS;
}

AHCIPCIResult AHCIPCIPlanCommand(AHCIU32 originalConfig,
                                 AHCIU32 *enableWrite,
                                 AHCIU32 *restoreWrite,
                                 unsigned char *changed)
{
    AHCIU32 originalCommand;

    if (enableWrite == 0 || restoreWrite == 0 || changed == 0)
        return AHCI_PCI_BAD_ARGUMENT;
    originalCommand = originalConfig & AHCI_PCI_COMMAND_MASK;
    *enableWrite = originalCommand | AHCI_PCI_COMMAND_MEMORY |
                   AHCI_PCI_COMMAND_MASTER;
    *restoreWrite = originalCommand;
    *changed = *enableWrite != originalCommand ? 1U : 0U;
    return AHCI_PCI_SUCCESS;
}

AHCIPCIResult AHCIPCIValidateCommandReadback(AHCIU32 readback)
{
    AHCIU32 required;

    required = AHCI_PCI_COMMAND_MEMORY | AHCI_PCI_COMMAND_MASTER;
    return (readback & required) == required ?
        AHCI_PCI_SUCCESS : AHCI_PCI_COMMAND_NOT_ENABLED;
}
