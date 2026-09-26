/*
 * acpi.c
 * ACPI static tables (ACPI 6.x spec, ch. 5.2): the RSDP is found in the
 * EBDA or the BIOS ROM area, it names the RSDT or XSDT, and that lists the
 * tables.  Everything read here is plain structure parsing; the MADT is
 * the one that matters for interrupts.
 *
 * Tables live in memory the kernel has not mapped, so each is mapped as it
 * is read.  Those mappings are permanent, which is fine: they total a few
 * pages and the tables are consulted again later.
 */

#include "acpi.h"

#include <string.h>

extern int printf(const char *format, ...);

#define RSDP_SIGNATURE		"RSD PTR "
#define RSDP_V1_LENGTH		20

/* MADT entry types (5.2.12) */
#define MADT_LAPIC		0
#define MADT_IOAPIC		1
#define MADT_ISO		2
#define MADT_LAPIC_NMI		4
#define MADT_LAPIC_ADDRESS	5
#define MADT_LOCAL_X2APIC	9

typedef struct {
    char		signature[4];
    unsigned int	length;
    unsigned char	revision;
    unsigned char	checksum;
    char		oem_id[6];
    char		oem_table_id[8];
    unsigned int	oem_revision;
    unsigned int	creator_id;
    unsigned int	creator_revision;
} acpi_header_t;

static unsigned char
checksum(const unsigned char *p, unsigned int length)
{
    unsigned char	sum = 0;

    while (length-- > 0)
	sum += *p++;
    return (sum);
}

/*
 * Map an ACPI table and check it.  The header is mapped first so the
 * length is known, then the whole table.
 */
static acpi_header_t *
map_table(unsigned int pa, const char *want)
{
    acpi_header_t	*h;

    if (pa == 0)
	return (0);
    h = (acpi_header_t *)pexpert_map_physical(pa, sizeof (*h));
    if (h == 0)
	return (0);
    if (want != 0 && memcmp(h->signature, want, 4) != 0)
	return (0);
    if (h->length < sizeof (*h) || h->length > 0x100000)
	return (0);
    if (h->length > 4096 - (pa & 4095)) {
	h = (acpi_header_t *)pexpert_map_physical(pa, h->length);
	if (h == 0)
	    return (0);
    }
    if (checksum((const unsigned char *)h, h->length) != 0) {
	printf("acpi: %c%c%c%c at %x has a bad checksum\n",
	       h->signature[0], h->signature[1], h->signature[2],
	       h->signature[3], pa);
	return (0);
    }
    return (h);
}

static int
rsdp_valid(const unsigned char *p)
{
    if (memcmp(p, RSDP_SIGNATURE, 8) != 0)
	return (0);
    if (checksum(p, RSDP_V1_LENGTH) != 0)
	return (0);
    /* Revision 2 adds the XSDT pointer and a second checksum. */
    if (p[15] >= 2 && checksum(p, *(const unsigned int *)(p + 20)) != 0)
	return (0);
    return (1);
}

/*
 * The first megabyte is mapped at its own address, so the EBDA and the
 * BIOS ROM area can be read directly, as the EISA and PCMCIA buses do.
 */
static unsigned int
scan_for_rsdp(void)
{
    unsigned int	ebda, p;

    ebda = (unsigned int)*(const unsigned short *)0x40E << 4;
    if (ebda >= 0x80000 && ebda < 0xA0000) {
	for (p = ebda; p < ebda + 1024; p += 16)
	    if (rsdp_valid((const unsigned char *)p))
		return (p);
    }
    for (p = 0xE0000; p < 0x100000; p += 16)
	if (rsdp_valid((const unsigned char *)p))
	    return (p);
    return (0);
}

static void
parse_madt(acpi_header_t *madt, i386_firmware_info_t *info)
{
    const unsigned char	*p, *end;
    unsigned char	type, length;

    info->lapic_address = *(const unsigned int *)((const unsigned char *)madt + 36);
    info->madt_flags = *(const unsigned int *)((const unsigned char *)madt + 40);

    p = (const unsigned char *)madt + 44;
    end = (const unsigned char *)madt + madt->length;

    while (p + 2 <= end) {
	type = p[0];
	length = p[1];
	if (length < 2 || p + length > end)
	    break;

	switch (type) {
	case MADT_LAPIC:
	    if (p[4] & 1) {		/* enabled */
		if (info->cpu_count < PEXPERT_MAX_CPUS)
		    info->lapic_ids[info->cpu_count] = p[3];
		info->cpu_count++;
	    }
	    break;

	case MADT_LOCAL_X2APIC:
	    /* Only ids that fit an xAPIC destination are reachable here. */
	    if (*(const unsigned int *)(p + 8) & 1) {
		unsigned int	id = *(const unsigned int *)(p + 4);

		if (info->cpu_count < PEXPERT_MAX_CPUS && id < 256)
		    info->lapic_ids[info->cpu_count] = id;
		info->cpu_count++;
	    }
	    break;

	case MADT_IOAPIC:
	    if (info->ioapic_count < PEXPERT_MAX_IOAPICS) {
		pexpert_ioapic_t	*io = &info->ioapics[info->ioapic_count++];

		io->id = p[2];
		io->address = *(const unsigned int *)(p + 4);
		io->gsi_base = *(const unsigned int *)(p + 8);
		io->pins = 0;
	    }
	    break;

	case MADT_ISO:
	    if (info->iso_count < PEXPERT_MAX_ISA_OVERRIDES) {
		pexpert_iso_t	*iso = &info->isos[info->iso_count++];

		iso->isa_irq = p[3];
		iso->gsi = *(const unsigned int *)(p + 4);
		iso->flags = *(const unsigned short *)(p + 8);
	    }
	    break;

	case MADT_LAPIC_ADDRESS:
	    /* 64-bit override; only the low half is reachable here. */
	    if (*(const unsigned int *)(p + 8) == 0)
		info->lapic_address = *(const unsigned int *)(p + 4);
	    break;

	default:
	    break;
	}
	p += length;
    }
}

/* Fixed ACPI Description Table (5.2.9); offsets are the spec's. */
static void
parse_fadt(acpi_header_t *fadt, i386_firmware_info_t *info)
{
    const unsigned char	*p = (const unsigned char *)fadt;

    if (fadt->length < 116)
	return;
    info->dsdt = *(const unsigned int *)(p + 40);
    info->sci_int = *(const unsigned short *)(p + 46);
    info->smi_cmd = *(const unsigned int *)(p + 48);
    info->acpi_enable = p[52];
    info->acpi_disable = p[53];
    info->pm1a_evt = *(const unsigned int *)(p + 56);
    info->pm1b_evt = *(const unsigned int *)(p + 60);
    info->pm1a_cnt = *(const unsigned int *)(p + 64);
    info->pm1b_cnt = *(const unsigned int *)(p + 68);
    info->pm1_evt_len = p[88];
    info->pm1_cnt_len = p[89];
    info->fadt_flags = *(const unsigned int *)(p + 112);

    /* ACPI 2.0: the reset register, and a 64-bit DSDT address. */
    if (fadt->length >= 129 && (info->fadt_flags & (1 << 10))) {
	info->reset_reg_space = p[116];
	info->reset_reg_address = *(const unsigned int *)(p + 120);
	info->reset_reg_address_hi = *(const unsigned int *)(p + 124);
	info->reset_value = p[128];
	info->reset_reg_present = 1;
    }
    if (fadt->length >= 148 && *(const unsigned int *)(p + 144) == 0 &&
	*(const unsigned int *)(p + 140) != 0)
	info->dsdt = *(const unsigned int *)(p + 140);
}

static void
parse_mcfg(acpi_header_t *mcfg, i386_firmware_info_t *info)
{
    const unsigned char	*p, *end;

    /* 44-byte header plus reserved, then 16-byte allocations (5.2.12 of the PCI Firmware spec). */
    p = (const unsigned char *)mcfg + 44;
    end = (const unsigned char *)mcfg + mcfg->length;

    while (p + 16 <= end) {
	unsigned int	base_lo = *(const unsigned int *)p;
	unsigned int	base_hi = *(const unsigned int *)(p + 4);
	unsigned short	segment = *(const unsigned short *)(p + 8);

	if (segment == 0 && base_hi == 0) {
	    info->ecam_base = base_lo;
	    info->ecam_start_bus = p[10];
	    info->ecam_end_bus = p[11];
	    return;
	}
	p += 16;
    }
}

int
acpi_discover(unsigned int rsdp_hint, i386_firmware_info_t *info)
{
    const unsigned char	*rsdp;
    acpi_header_t	*root, *table;
    unsigned int	rsdp_pa, root_pa, entry_size, count, i, pa;
    const unsigned char	*entries;

    rsdp_pa = 0;
    if (rsdp_hint != 0) {
	rsdp = (const unsigned char *)pexpert_map_physical(rsdp_hint, 36);
	if (rsdp != 0 && rsdp_valid(rsdp))
	    rsdp_pa = rsdp_hint;
	else
	    printf("acpi: booter's RSDP at %x is not one\n", rsdp_hint);
    }
    if (rsdp_pa == 0) {
	rsdp_pa = scan_for_rsdp();
	if (rsdp_pa == 0)
	    return (0);
	rsdp = (const unsigned char *)rsdp_pa;
    }

    info->rsdp = rsdp_pa;
    info->acpi_revision = rsdp[15];

    /*
     * Prefer the XSDT when the RSDP is revision 2 and it sits below 4 GB;
     * it holds 64-bit entries, and only those below 4 GB can be mapped.
     */
    root = 0;
    entry_size = 4;
    if (info->acpi_revision >= 2 && *(const unsigned int *)(rsdp + 28) == 0) {
	root_pa = *(const unsigned int *)(rsdp + 24);
	root = map_table(root_pa, "XSDT");
	entry_size = 8;
    }
    if (root == 0) {
	root_pa = *(const unsigned int *)(rsdp + 16);
	root = map_table(root_pa, "RSDT");
	entry_size = 4;
    }
    if (root == 0) {
	printf("acpi: RSDP at %x names no usable RSDT or XSDT\n", rsdp_pa);
	return (1);
    }

    entries = (const unsigned char *)root + sizeof (acpi_header_t);
    count = (root->length - sizeof (acpi_header_t)) / entry_size;

    for (i = 0; i < count; i++) {
	if (entry_size == 8) {
	    if (*(const unsigned int *)(entries + 8 * i + 4) != 0)
		continue;
	    pa = *(const unsigned int *)(entries + 8 * i);
	} else
	    pa = *(const unsigned int *)(entries + 4 * i);

	table = map_table(pa, 0);
	if (table == 0)
	    continue;

	if (memcmp(table->signature, "APIC", 4) == 0) {
	    info->madt = pa;
	    parse_madt(table, info);
	} else if (memcmp(table->signature, "FACP", 4) == 0) {
	    info->fadt = pa;
	    parse_fadt(table, info);
	} else if (memcmp(table->signature, "HPET", 4) == 0)
	    info->hpet = pa;
	else if (memcmp(table->signature, "MCFG", 4) == 0) {
	    info->mcfg = pa;
	    parse_mcfg(table, info);
	}
    }
    return (1);
}
