/*
 * acpi_pm.c
 * ACPI power management from the static tables (ACPI 6.x spec, ch. 4
 * and 7).
 *
 * The FADT names the PM1 event and control registers, the SMI command
 * port that switches the chipset from legacy (SMI) to ACPI (SCI) mode,
 * the SCI's ISA irq and the reset register.  What it does not name is the
 * sleep type for S5, which lives in the DSDT's _S5 object; that is AML,
 * but a Name(_S5_, Package(...)) is a fixed byte shape, and reading the
 * two byte constants out of it is the whole of the AML touched here.
 *
 * The power button raises the SCI.  The handler asks the kernel for an
 * orderly halt the way the NMI monitor's 'h' does, so the shutdown runs
 * on a thread, not in the interrupt.
 */

#include "acpi_pm.h"
#include "chips/pcicfg.h"

#include <machdep/i386/io_inline.h>
#include <machdep/i386/intr_exported.h>
#include <sys/reboot.h>

#ifndef RB_POWERDOWN
#define RB_POWERDOWN	0
#endif

extern int printf(const char *format, ...);
extern void IODelay(unsigned int microseconds);
extern void reboot_mach(int how);

/* PM1 status and enable bits (4.8.3.1) */
#define PM1_STS_PWRBTN		0x0100
#define PM1_EN_PWRBTN		0x0100
/* PM1 control (4.8.3.2) */
#define PM1_CNT_SCI_EN		0x0001
#define PM1_CNT_SLP_EN		0x2000
#define PM1_CNT_SLP_TYP_SHIFT	10

static const i386_firmware_info_t	*fadt;
static int		enabled;
static int		have_s5;
static unsigned char	slp_typa, slp_typb;

/*
 * Find Name(_S5_, Package(N) { typa, typb, ... }) in the DSDT: NameOp,
 * the name, PackageOp, PkgLength, NumElements, then the elements, each a
 * ZeroOp, OneOp or BytePrefix byte.
 */
static void
find_s5(unsigned int dsdt_pa)
{
    const unsigned char	*dsdt, *p, *end;
    unsigned int	length, i;

    if (dsdt_pa == 0)
	return;
    dsdt = (const unsigned char *)pexpert_map_physical(dsdt_pa, 36);
    if (dsdt == 0 || dsdt[0] != 'D' || dsdt[1] != 'S' || dsdt[2] != 'D' || dsdt[3] != 'T')
	return;
    length = *(const unsigned int *)(dsdt + 4);
    if (length < 36 || length > 0x100000)
	return;
    dsdt = (const unsigned char *)pexpert_map_physical(dsdt_pa, length);
    if (dsdt == 0)
	return;

    end = dsdt + length;
    for (p = dsdt + 36; p + 12 < end; p++) {
	unsigned char	typ[2];

	if (p[0] != '_' || p[1] != 'S' || p[2] != '5' || p[3] != '_')
	    continue;
	if (p[-1] != 0x08 || p[4] != 0x12)		/* NameOp, PackageOp */
	    continue;
	p += 5;
	p += 1 + (p[0] >> 6);				/* PkgLength */
	p++;						/* NumElements */
	for (i = 0; i < 2 && p < end; i++) {
	    if (*p == 0x0A) {				/* BytePrefix */
		typ[i] = p[1];
		p += 2;
	    } else if (*p == 0x00 || *p == 0x01) {	/* ZeroOp, OneOp */
		typ[i] = *p;
		p++;
	    } else
		return;
	}
	slp_typa = typ[0] & 7;
	slp_typb = typ[1] & 7;
	have_s5 = 1;
	return;
    }
}

static unsigned short
pm1_status(unsigned int block)
{
    return (block ? inw(block) : 0);
}

static void
pm1_clear(unsigned int block, unsigned short bits)
{
    if (block)
	outw(block, bits);
}

static void
sci_handler(unsigned int which, void *state, int old_ipl)
{
    unsigned short	sts;

    sts = pm1_status(fadt->pm1a_evt) | pm1_status(fadt->pm1b_evt);

    /* Status bits clear when written with 1. */
    pm1_clear(fadt->pm1a_evt, sts);
    pm1_clear(fadt->pm1b_evt, sts);

    if (sts & PM1_STS_PWRBTN) {
	printf("acpi: power button, halting\n");
	reboot_mach(RB_HALT | RB_POWERDOWN);
    }
}

int
acpi_pm_enable(const i386_firmware_info_t *info)
{
    unsigned int	enable_block;
    int			i;

    if (info->fadt == 0 || info->pm1a_cnt == 0 || info->pm1a_evt == 0) {
	printf("acpi: no FADT with PM1 blocks; power management off\n");
	return (0);
    }
    fadt = info;

    if ((inw(info->pm1a_cnt) & PM1_CNT_SCI_EN) == 0) {
	if (info->smi_cmd == 0 || info->acpi_enable == 0) {
	    printf("acpi: firmware offers no way into ACPI mode\n");
	    return (0);
	}
	outb(info->smi_cmd, info->acpi_enable);
	for (i = 0; i < 300 && (inw(info->pm1a_cnt) & PM1_CNT_SCI_EN) == 0; i++)
	    IODelay(10000);
	if ((inw(info->pm1a_cnt) & PM1_CNT_SCI_EN) == 0) {
	    printf("acpi: chipset did not enter ACPI mode\n");
	    return (0);
	}
    }
    enabled = 1;

    find_s5(info->dsdt);

    /*
     * The power button: clear what is pending, take the SCI, then enable
     * the event.  The SCI is level triggered and shared by design.
     */
    pm1_clear(info->pm1a_evt, PM1_STS_PWRBTN);
    pm1_clear(info->pm1b_evt, PM1_STS_PWRBTN);

    if (intr_register_irq(info->sci_int, sci_handler, 0, INTR_IPL3)) {
	(void) intr_change_mode(info->sci_int, TRUE);
	(void) intr_enable_irq(info->sci_int);
	enable_block = info->pm1_evt_len / 2;
	if (info->pm1a_evt)
	    outw(info->pm1a_evt + enable_block,
		 inw(info->pm1a_evt + enable_block) | PM1_EN_PWRBTN);
	if (info->pm1b_evt)
	    outw(info->pm1b_evt + enable_block,
		 inw(info->pm1b_evt + enable_block) | PM1_EN_PWRBTN);
    } else
	printf("acpi: could not take irq %d for the SCI\n", info->sci_int);

    printf("acpi: ACPI mode, SCI on irq %d%s%s\n", info->sci_int,
	   have_s5 ? ", S5 known" : ", no _S5 found",
	   info->reset_reg_present ? ", reset register" : "");
    return (1);
}

void
pexpert_acpi_poweroff(void)
{
    if (!enabled || !have_s5)
	return;

    outw(fadt->pm1a_cnt, ((unsigned short)slp_typa << PM1_CNT_SLP_TYP_SHIFT) | PM1_CNT_SLP_EN);
    if (fadt->pm1b_cnt)
	outw(fadt->pm1b_cnt, ((unsigned short)slp_typb << PM1_CNT_SLP_TYP_SHIFT) | PM1_CNT_SLP_EN);

    /* The write takes a moment to act; give it one before giving up. */
    IODelay(1000000);
}

void
pexpert_acpi_reset(void)
{
    volatile unsigned char	*mem;

    if (fadt == 0 || !fadt->reset_reg_present)
	return;

    switch (fadt->reset_reg_space) {
    case 1:				/* system I/O */
	outb(fadt->reset_reg_address, fadt->reset_value);
	break;
    case 0:				/* system memory */
	if (fadt->reset_reg_address_hi != 0)
	    return;
	mem = (volatile unsigned char *)pexpert_map_physical(fadt->reset_reg_address, 1);
	if (mem == 0)
	    return;
	*mem = fadt->reset_value;
	break;
    case 2:				/* PCI configuration, bus 0 */
	(void) pcicfg_write(0, (fadt->reset_reg_address_hi >> 0) & 0x1F,
			    (fadt->reset_reg_address >> 16) & 0x7,
			    fadt->reset_reg_address & 0xFFFF, 1,
			    fadt->reset_value);
	break;
    default:
	return;
    }
    IODelay(1000000);
}
