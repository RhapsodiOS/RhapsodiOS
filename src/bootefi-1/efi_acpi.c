/* The ACPI root pointer, from the EFI system table's configuration tables
 * (UEFI spec 4.6).  The ACPI 2.0 GUID is preferred over the 1.0 one; both
 * name an RSDP the kernel validates itself. */
#include "efi.h"

static const EFI_GUID acpi20_guid =
    { 0x8868e871, 0xe4f1, 0x11d3, { 0xbc, 0x22, 0x00, 0x80, 0xc7, 0x3c, 0x88, 0x81 } };
static const EFI_GUID acpi10_guid =
    { 0xeb9d2d30, 0x2d88, 0x11d3, { 0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d } };

static int
guid_equal(const EFI_GUID *a, const EFI_GUID *b)
{
    int i;

    if (a->d1 != b->d1 || a->d2 != b->d2 || a->d3 != b->d3)
        return 0;
    for (i = 0; i < 8; i++)
        if (a->d4[i] != b->d4[i])
            return 0;
    return 1;
}

static unsigned int
find_table(const EFI_GUID *guid)
{
    UINTN i;

    for (i = 0; i < gST->NumberOfTableEntries; i++)
        if (guid_equal(&gST->ConfigurationTable[i].VendorGuid, guid))
            return (unsigned int)gST->ConfigurationTable[i].VendorTable;
    return 0;
}

unsigned int
efi_acpi_rsdp(void)
{
    unsigned int rsdp;

    rsdp = find_table(&acpi20_guid);
    if (rsdp == 0)
        rsdp = find_table(&acpi10_guid);
    return rsdp;
}
