/* Parsing for the ACPI 2.0 resource descriptor chain that
 * EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL.Configuration() returns.  Deliberately
 * free of EFI types so it can be host-tested without firmware. */
#ifndef _BOOTEFI_EFI_PCI_ACPI_H_
#define _BOOTEFI_EFI_PCI_ACPI_H_

/* Returned when the chain carries no usable bus-number range.  Distinct from
 * a valid maximum of 0, which a single-bus machine legitimately reports. */
#define EFI_PCI_BUS_RANGE_NONE (-1)

/* Report the highest bus number the chain's bus-number descriptor claims.
 * Reads at most maxlen bytes.  Returns 0..255, or EFI_PCI_BUS_RANGE_NONE if
 * the chain has no bus-number descriptor, is malformed, or is truncated. */
int efi_pci_bus_range_max(const unsigned char *resources, unsigned int maxlen);

#endif /* _BOOTEFI_EFI_PCI_ACPI_H_ */
