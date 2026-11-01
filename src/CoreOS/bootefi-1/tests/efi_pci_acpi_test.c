/* Host test for the UEFI loader's ACPI bus-range parser.  Pure byte buffers:
 * no firmware, no EFI types, no boot-2 headers. */
#include <stdio.h>
#include <string.h>

#include "efi_pci_acpi.h"

#define DESC_LEN 46
#define END_LEN   2

static int failures;

static void check(const char *name, int got, int want)
{
    if (got != want) {
        printf("FAIL %s: got %d want %d\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

/* One QWORD Address Space Descriptor: tag 0x8a, 2-byte payload length 0x2b,
 * ResType at +3, AddrRangeMin at +14, AddrRangeMax at +22 (both 8 bytes,
 * little-endian).  ACPI 2.0. */
static unsigned int put_desc(unsigned char *buf, unsigned char restype,
                             unsigned long long min, unsigned long long max)
{
    unsigned int i;

    memset(buf, 0, DESC_LEN);
    buf[0] = 0x8a;
    buf[1] = 0x2b;
    buf[2] = 0x00;
    buf[3] = restype;
    for (i = 0; i < 8; i++)
        buf[14 + i] = (unsigned char)(min >> (8 * i));
    for (i = 0; i < 8; i++)
        buf[22 + i] = (unsigned char)(max >> (8 * i));
    return DESC_LEN;
}

static unsigned int put_end(unsigned char *buf)
{
    buf[0] = 0x79;
    buf[1] = 0x00;
    return END_LEN;
}

int main(void)
{
    unsigned char buf[256];
    unsigned int n;

    /* Bus descriptor first in the chain. */
    n = put_desc(buf, 2, 0, 255);
    n += put_end(buf + n);
    check("bus_only", efi_pci_bus_range_max(buf, n), 255);

    /* Memory (0) and I/O (1) descriptors ahead of the bus descriptor. */
    n = put_desc(buf, 0, 0xc0000000ULL, 0xdfffffffULL);
    n += put_desc(buf + n, 1, 0, 0xffff);
    n += put_desc(buf + n, 2, 0, 63);
    n += put_end(buf + n);
    check("bus_after_mem_and_io", efi_pci_bus_range_max(buf, n), 63);

    /* A single-bus machine reports max 0 -- not the sentinel. */
    n = put_desc(buf, 2, 0, 0);
    n += put_end(buf + n);
    check("single_bus_is_zero", efi_pci_bus_range_max(buf, n), 0);

    /* No bus descriptor at all. */
    n = put_desc(buf, 0, 0, 0xffff);
    n += put_end(buf + n);
    check("no_bus_descriptor", efi_pci_bus_range_max(buf, n),
          EFI_PCI_BUS_RANGE_NONE);

    /* Truncated mid-descriptor: the payload runs past maxlen. */
    n = put_desc(buf, 2, 0, 255);
    check("truncated_descriptor", efi_pci_bus_range_max(buf, n - 10),
          EFI_PCI_BUS_RANGE_NONE);

    /* No end tag and no bus descriptor: the walk must stop at maxlen. */
    n = put_desc(buf, 0, 0, 0xffff);
    check("no_end_tag", efi_pci_bus_range_max(buf, n),
          EFI_PCI_BUS_RANGE_NONE);

    /* An unrecognised tag byte aborts rather than being walked past. */
    n = put_desc(buf, 2, 0, 255);
    buf[0] = 0x47;
    check("unknown_tag", efi_pci_bus_range_max(buf, n),
          EFI_PCI_BUS_RANGE_NONE);

    /* A range maximum too wide for a PCI bus number is not usable. */
    n = put_desc(buf, 2, 0, 0x1ffULL);
    n += put_end(buf + n);
    check("bus_max_too_wide", efi_pci_bus_range_max(buf, n),
          EFI_PCI_BUS_RANGE_NONE);

    /* A null chain. */
    check("null_chain", efi_pci_bus_range_max(0, 64),
          EFI_PCI_BUS_RANGE_NONE);

    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
