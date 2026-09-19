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

/*
 * How much address space BAR5 actually decodes, from the value read back
 * after writing all ones to it.  The set bits above the type field are the
 * ones the device leaves writable, so the size is the complement plus one.
 *
 * AHCI's register file is at most 0x1100 (0x100 of generic host control
 * plus 32 ports of 0x80), but a controller that implements fewer ports
 * decodes less -- QEMU's ich9-ahci decodes 4 KiB and places consecutive
 * controllers 4 KiB apart.  Mapping the 0x1100 maximum regardless made a
 * second controller's range run 0x100 bytes into the first one's
 * registers, and the kernel refused the overlapping reservation.  So take
 * whichever is smaller: what the BAR decodes, or what AHCI can use.
 */
AHCIPCIResult AHCIPCIBarLength(AHCIU32 sizeMask, AHCIU32 maximum,
                               AHCIU32 *length)
{
    AHCIU32 decoded;

    if (length == 0 || maximum == 0)
        return AHCI_PCI_BAD_ARGUMENT;
    *length = 0;

    decoded = sizeMask & AHCI_PCI_BAR_MEMORY_MASK;
    if (decoded == 0)
        return AHCI_PCI_INVALID_BAR;
    decoded = ~decoded + 1U;

    /* A BAR decodes a power-of-two span; anything else means the readback
     * was not a size probe. */
    if (decoded == 0 || (decoded & (decoded - 1U)) != 0)
        return AHCI_PCI_INVALID_BAR;
    if (decoded < AHCI_ABAR_MINIMUM_LENGTH)
        return AHCI_PCI_INVALID_BAR;

    *length = decoded < maximum ? decoded : maximum;
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

AHCIPCIResult AHCIPCIInterruptLine(AHCIU32 interruptConfig,
                                   unsigned int *interruptLine)
{
    unsigned int line;

    if (interruptLine == 0)
        return AHCI_PCI_BAD_ARGUMENT;
    line = interruptConfig & 0xffU;
    if (line < 2U || line > 15U)
        return AHCI_PCI_INVALID_INTERRUPT;
    *interruptLine = line;
    return AHCI_PCI_SUCCESS;
}
