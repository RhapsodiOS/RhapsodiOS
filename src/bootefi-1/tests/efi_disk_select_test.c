/* Host test for the UEFI loader's disk-selection helpers.  Pure byte
 * buffers: no firmware, no EFI types, no boot-2 headers. */
#include <stdio.h>
#include <string.h>

#include "efi_disk_select.h"

static int failures;

static void check(const char *name, unsigned long got, unsigned long want)
{
    if (got != want) {
        printf("FAIL %s: got %lu want %lu\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

static void put_entry(unsigned char *mbr, int n, unsigned char type,
                      unsigned long relsect)
{
    unsigned char *e = mbr + 446 + 16 * n;

    e[4] = type;
    e[8] = (unsigned char)relsect;
    e[9] = (unsigned char)(relsect >> 8);
    e[10] = (unsigned char)(relsect >> 16);
    e[11] = (unsigned char)(relsect >> 24);
}

static void test_label_lba(void)
{
    unsigned char mbr[512];

    memset(mbr, 0, sizeof mbr);
    check("no signature: whole-disk label", efi_label_lba(mbr), 15);

    mbr[510] = 0x55;
    mbr[511] = 0xAA;
    check("signature, empty table: whole-disk label", efi_label_lba(mbr), 15);

    put_entry(mbr, 0, 0xEF, 2048);
    put_entry(mbr, 1, 0xA7, 133120);
    check("ESP then 0xA7: 15 sectors into the 0xA7 partition",
          efi_label_lba(mbr), 133135);

    memset(mbr + 446, 0, 64);
    put_entry(mbr, 2, 0xA7, 63);
    put_entry(mbr, 3, 0xA7, 99999);
    check("the first 0xA7 entry wins", efi_label_lba(mbr), 78);
}

/* Append one device-path node; returns the offset just past it. */
static unsigned int node(unsigned char *dp, unsigned int at,
                         unsigned char type, unsigned char subtype,
                         unsigned int len)
{
    memset(dp + at, 0x5A, len);
    dp[at] = type;
    dp[at + 1] = subtype;
    dp[at + 2] = (unsigned char)len;
    dp[at + 3] = (unsigned char)(len >> 8);
    return at + len;
}

static unsigned int end_node(unsigned char *dp, unsigned int at)
{
    return node(dp, at, 0x7F, 0xFF, 4);
}

/* PciRoot/Pci(dev)/Ata -- the shape edk2 gives a PIIX3 IDE disk. */
static unsigned int disk_prefix(unsigned char *dp, unsigned char pci_dev)
{
    unsigned int at = 0;

    at = node(dp, at, 0x02, 0x01, 12);          /* ACPI: PciRoot */
    at = node(dp, at, 0x01, 0x01, 6);           /* Hardware: Pci */
    dp[at - 1] = pci_dev;
    at = node(dp, at, 0x03, 0x01, 8);           /* Messaging: Ata */
    return at;
}

static void test_dp_is_parent(void)
{
    unsigned char disk[64], part[128], other[128], cdrom[128];
    unsigned int at;

    end_node(disk, disk_prefix(disk, 1));

    at = disk_prefix(part, 1);
    at = node(part, at, 0x04, 0x01, 42);        /* Media: HardDrive */
    end_node(part, at);
    check("a partition of this disk", efi_dp_is_parent(disk, part), 1);

    at = disk_prefix(other, 2);
    at = node(other, at, 0x04, 0x01, 42);
    end_node(other, at);
    check("a partition of another disk", efi_dp_is_parent(disk, other), 0);

    at = disk_prefix(cdrom, 1);
    at = node(cdrom, at, 0x04, 0x02, 24);       /* Media: CDROM */
    end_node(cdrom, at);
    check("an El Torito entry is not an fdisk partition",
          efi_dp_is_parent(disk, cdrom), 0);

    check("a disk is not its own parent", efi_dp_is_parent(disk, disk), 0);

    disk[2] = 0;                                /* zero-length node */
    disk[3] = 0;
    check("a malformed disk path matches nothing",
          efi_dp_is_parent(disk, part), 0);
}

int main(void)
{
    test_label_lba();
    test_dp_is_parent();
    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
