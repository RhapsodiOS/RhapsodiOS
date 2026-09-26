/*
 * mptable.c
 * The MP floating pointer structure and configuration table (Intel
 * MultiProcessor Specification 1.4, ch. 4).
 *
 * The MADT says where the APICs are; it does not say which I/O APIC pin a
 * PCI slot's interrupt line reaches, because ACPI puts that in the _PRT
 * method, which needs an AML interpreter.  The MP table's I/O interrupt
 * assignment entries carry the same routing statically, so that is where
 * it comes from.  A PCI bus entry's id is taken to be its PCI bus number,
 * which is how every BIOS seen so far numbers them.
 */

#include "mptable.h"

#include <string.h>

extern int printf(const char *format, ...);

#define MP_FPS_SIGNATURE	"_MP_"
#define MP_CONFIG_SIGNATURE	"PCMP"

#define MP_ENTRY_PROCESSOR	0
#define MP_ENTRY_BUS		1
#define MP_ENTRY_IOAPIC		2
#define MP_ENTRY_IOINT		3
#define MP_ENTRY_LOCALINT	4

#define MP_INT_TYPE_INT		0

#define MP_MAX_BUSES		32

typedef struct {
    char		signature[4];
    unsigned int	config;		/* physical address of the table */
    unsigned char	length;		/* in 16-byte units */
    unsigned char	revision;
    unsigned char	checksum;
    unsigned char	feature[5];	/* [0] default config, [1] bit 7 IMCR */
} mp_fps_t;

typedef struct {
    char		signature[4];
    unsigned short	length;
    unsigned char	revision;
    unsigned char	checksum;
    char		oem_id[8];
    char		product_id[12];
    unsigned int	oem_table;
    unsigned short	oem_table_size;
    unsigned short	entry_count;
    unsigned int	lapic_address;
    unsigned short	ext_length;
    unsigned char	ext_checksum;
    unsigned char	reserved;
} mp_config_t;

static mp_config_t	*config;
static unsigned char	pci_bus[MP_MAX_BUSES];	/* MP bus id -> is a PCI bus */

static unsigned char
checksum(const unsigned char *p, unsigned int length)
{
    unsigned char	sum = 0;

    while (length-- > 0)
	sum += *p++;
    return (sum);
}

static const mp_fps_t *
scan_range(unsigned int start, unsigned int end)
{
    unsigned int	p;

    for (p = start; p + sizeof (mp_fps_t) <= end; p += 16) {
	const mp_fps_t	*fps = (const mp_fps_t *)p;

	if (memcmp(fps->signature, MP_FPS_SIGNATURE, 4) == 0 &&
	    fps->length == 1 &&
	    checksum((const unsigned char *)fps, 16) == 0)
	    return (fps);
    }
    return (0);
}

static const mp_fps_t *
find_fps(void)
{
    const mp_fps_t	*fps;
    unsigned int	ebda, base_top;

    /* First KB of the EBDA, last KB of base memory, then the BIOS ROM. */
    ebda = (unsigned int)*(const unsigned short *)0x40E << 4;
    if (ebda >= 0x80000 && ebda < 0xA0000 &&
	(fps = scan_range(ebda, ebda + 1024)) != 0)
	return (fps);

    base_top = (unsigned int)*(const unsigned short *)0x413 << 10;
    if (base_top >= 0x80000 && base_top <= 0xA0000 &&
	(fps = scan_range(base_top - 1024, base_top)) != 0)
	return (fps);

    return (scan_range(0xF0000, 0x100000));
}

static unsigned int
entry_length(unsigned char type)
{
    return (type == MP_ENTRY_PROCESSOR ? 20 : 8);
}

int
mptable_discover(i386_firmware_info_t *info)
{
    const mp_fps_t	*fps;
    const unsigned char	*p, *end;
    unsigned int	i;

    fps = find_fps();
    if (fps == 0)
	return (0);

    info->mp_fps = (unsigned int)fps;
    info->imcr_present = (fps->feature[1] & 0x80) != 0;

    if (fps->feature[0] != 0 || fps->config == 0) {
	/* A default configuration carries no table; nothing to route with. */
	return (1);
    }

    config = (mp_config_t *)pexpert_map_physical(fps->config, sizeof (*config));
    if (config == 0 || memcmp(config->signature, MP_CONFIG_SIGNATURE, 4) != 0) {
	config = 0;
	return (1);
    }
    if (config->length > 4096 - (fps->config & 4095)) {
	config = (mp_config_t *)pexpert_map_physical(fps->config, config->length);
	if (config == 0)
	    return (1);
    }
    if (checksum((const unsigned char *)config, config->length) != 0) {
	printf("mptable: configuration table at %x has a bad checksum\n",
	       fps->config);
	config = 0;
	return (1);
    }
    info->mp_config = fps->config;

    /* Note which bus ids are PCI. */
    p = (const unsigned char *)config + sizeof (*config);
    end = (const unsigned char *)config + config->length;
    for (i = 0; i < config->entry_count && p + 8 <= end; i++) {
	if (p[0] == MP_ENTRY_BUS && p[1] < MP_MAX_BUSES &&
	    memcmp(p + 2, "PCI", 3) == 0)
	    pci_bus[p[1]] = 1;
	p += entry_length(p[0]);
    }
    return (1);
}

int
mptable_pci_route(int bus, int dev, int pin, unsigned char *ioapic_id,
		  unsigned int *intin, unsigned short *flags)
{
    const unsigned char	*p, *end;
    unsigned int	i;
    unsigned char	want;

    if (config == 0 || bus < 0 || bus >= MP_MAX_BUSES || !pci_bus[bus] ||
	pin < 1 || pin > 4)
	return (0);

    want = ((dev & 0x1F) << 2) | (pin - 1);

    p = (const unsigned char *)config + sizeof (*config);
    end = (const unsigned char *)config + config->length;
    for (i = 0; i < config->entry_count && p + 8 <= end; i++) {
	if (p[0] == MP_ENTRY_IOINT && p[1] == MP_INT_TYPE_INT &&
	    p[4] == bus && p[5] == want) {
	    *flags = *(const unsigned short *)(p + 2);
	    *ioapic_id = p[6];
	    *intin = p[7];
	    return (1);
	}
	p += entry_length(p[0]);
    }
    return (0);
}
