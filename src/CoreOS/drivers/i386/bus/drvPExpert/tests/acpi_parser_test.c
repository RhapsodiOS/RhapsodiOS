/* Host-side checks of the production parser, without firmware or port I/O. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../i386/acpi.c"

void *pexpert_map_physical(unsigned int pa, unsigned int len)
{
    (void)pa;
    (void)len;
    return 0;
}

static int failures;

static void check(int condition, const char *name)
{
    printf("%s: %s\n", condition ? "PASS" : "FAIL", name);
    if (!condition) failures++;
}

static void put32(unsigned char *p, unsigned int value)
{
    memcpy(p, &value, sizeof(value));
}

static void rsdp_checksum(unsigned char *p, unsigned int length)
{
    p[8] = 0;
    p[32] = 0;
    p[8] = (unsigned char)-checksum(p, 20);
    p[32] = (unsigned char)-checksum(p, length);
}

int main(void)
{
    unsigned char rsdp[36];
    /* Storage exceeds the declared table length, as a mapped page does. */
    unsigned int madt_words[20];
    unsigned char *madt = (unsigned char *)madt_words;
    i386_firmware_info_t info;

    memset(rsdp, 0, sizeof(rsdp));
    memcpy(rsdp, "RSD PTR ", 8);
    rsdp[15] = 2;
    put32(rsdp + 20, 36);
    rsdp_checksum(rsdp, 36);
    check(rsdp_valid(rsdp), "valid revision 2 RSDP");
    rsdp[8]++;
    check(!rsdp_valid(rsdp), "reject bad RSDP checksum");
    put32(rsdp + 20, 0);
    rsdp_checksum(rsdp, 36);
    check(!rsdp_valid(rsdp), "reject zero revision 2 RSDP length");

    memset(madt_words, 0, sizeof(madt_words));
    put32(madt + 4, 52);
    put32(madt + 36, 0xfee00000);
    madt[44] = MADT_LAPIC;
    madt[45] = 8;
    madt[47] = 3;
    madt[48] = 1;
    memset(&info, 0, sizeof(info));
    parse_madt((acpi_header_t *)madt, &info);
    check(info.cpu_count == 1 && info.lapic_ids[0] == 3,
          "enabled local APIC processor");

    put32(madt + 4, 46);
    madt[45] = 2;
    memset(&info, 0, sizeof(info));
    parse_madt((acpi_header_t *)madt, &info);
    check(info.cpu_count == 0, "reject truncated local APIC entry");

    put32(madt + 4, 60);
    madt[44] = MADT_LOCAL_X2APIC;
    madt[45] = 16;
    put32(madt + 48, 256);
    put32(madt + 52, 1);
    memset(&info, 0, sizeof(info));
    parse_madt((acpi_header_t *)madt, &info);
    check(info.cpu_count == 0,
          "exclude processor IDs unreachable by xAPIC startup");

    put32(madt + 4, 36);
    memset(&info, 0, sizeof(info));
    parse_madt((acpi_header_t *)madt, &info);
    check(info.lapic_address == 0, "reject truncated MADT header");

    put32(madt + 4, 46);
    madt[44] = MADT_IOAPIC;
    madt[45] = 2;
    memset(&info, 0, sizeof(info));
    parse_madt((acpi_header_t *)madt, &info);
    check(info.ioapic_count == 0, "reject truncated I/O APIC entry");

    madt[44] = MADT_ISO;
    memset(&info, 0, sizeof(info));
    parse_madt((acpi_header_t *)madt, &info);
    check(info.iso_count == 0, "reject truncated interrupt override");

    madt[44] = MADT_LAPIC_ADDRESS;
    put32(madt + 52, 0);
    memset(&info, 0, sizeof(info));
    parse_madt((acpi_header_t *)madt, &info);
    check(info.lapic_address == 0xfee00000,
          "reject truncated local APIC address override");

    printf("%d failures\n", failures);
    return failures ? 1 : 0;
}
