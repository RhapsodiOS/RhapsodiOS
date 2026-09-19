/* See efi_pci_acpi.h.  Parsed byte-wise rather than through a packed struct:
 * the descriptor's 8-byte fields are unaligned, and byte access keeps this
 * free of compiler-specific packing pragmas and host-testable as plain C. */
#include "efi_pci_acpi.h"

/* ACPI 2.0 tag bytes. */
#define ACPI_QWORD_ADDRESS_SPACE_DESC 0x8a
#define ACPI_END_TAG                  0x79

/* Tag byte plus a 2-byte count of the bytes that follow it. */
#define ACPI_DESC_HEADER_LEN 3

/* Offsets from the tag byte. */
#define ACPI_RES_TYPE_OFFSET      3
#define ACPI_ADDR_RANGE_MAX_OFF  22

/* Smallest payload that still contains all 8 bytes of AddrRangeMax.  The
 * standard QWORD descriptor declares 0x2b; this only rejects short ones. */
#define ACPI_MIN_PAYLOAD_LEN \
	(ACPI_ADDR_RANGE_MAX_OFF + 8 - ACPI_DESC_HEADER_LEN)

/* ResType 2 is bus-number space. */
#define ACPI_RES_TYPE_BUS 2

int efi_pci_bus_range_max(const unsigned char *resources, unsigned int maxlen)
{
	unsigned int offset = 0;

	if (resources == 0)
		return EFI_PCI_BUS_RANGE_NONE;

	/* offset advances by at least ACPI_MIN_PAYLOAD_LEN each pass, so the
	 * maxlen bound terminates the walk; no separate iteration cap needed. */
	while (offset < maxlen) {
		unsigned int payload;

		if (resources[offset] == ACPI_END_TAG)
			return EFI_PCI_BUS_RANGE_NONE;
		if (resources[offset] != ACPI_QWORD_ADDRESS_SPACE_DESC)
			return EFI_PCI_BUS_RANGE_NONE;
		if (offset + ACPI_DESC_HEADER_LEN > maxlen)
			return EFI_PCI_BUS_RANGE_NONE;

		payload = (unsigned int)resources[offset + 1] |
			  ((unsigned int)resources[offset + 2] << 8);
		if (payload < ACPI_MIN_PAYLOAD_LEN)
			return EFI_PCI_BUS_RANGE_NONE;
		if (offset + ACPI_DESC_HEADER_LEN + payload > maxlen)
			return EFI_PCI_BUS_RANGE_NONE;

		if (resources[offset + ACPI_RES_TYPE_OFFSET] ==
		    ACPI_RES_TYPE_BUS) {
			unsigned int i;

			/* Only the low byte can be a PCI bus number.  Anything
			 * wider means this is not a range we can hand to
			 * scanBus(), whose maxBusNum is an unsigned char. */
			for (i = 1; i < 8; i++) {
				if (resources[offset +
					      ACPI_ADDR_RANGE_MAX_OFF + i] != 0)
					return EFI_PCI_BUS_RANGE_NONE;
			}
			return (int)resources[offset + ACPI_ADDR_RANGE_MAX_OFF];
		}

		offset += ACPI_DESC_HEADER_LEN + payload;
	}

	return EFI_PCI_BUS_RANGE_NONE;
}
