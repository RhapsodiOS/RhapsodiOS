/*
 * apic_intr.c
 * The APIC interrupt controller behind machdep/i386/intr.c.
 *
 * intr.c owns the dispatch table, the ipl masks and deferral; this file
 * only maps its 64 irqs onto hardware: irq 0-15 onto the ISA lines' I/O
 * APIC pins (through the MADT's interrupt source overrides), irq 16-47
 * onto the remaining pins by global system interrupt number, irq 48-62
 * onto message signalled interrupts, and 63 onto the local APIC's
 * spurious vector.  Every irq's vector is 0x40 + irq, so the IDT the
 * kernel already has serves unchanged.
 */

#include "pexpert_i386.h"
#include "chips/lapic.h"
#include "chips/ioapic.h"
#include "mptable.h"
#include "msi.h"

extern int printf(const char *format, ...);

/* MPS INTI flags (MP spec 4.3.4, MADT 5.2.12.5) */
#define INTI_POLARITY_MASK	0x3
#define INTI_POLARITY_HIGH	0x1
#define INTI_POLARITY_LOW	0x3
#define INTI_TRIGGER_MASK	0xC
#define INTI_TRIGGER_EDGE	0x4
#define INTI_TRIGGER_LEVEL	0xC

typedef struct {
    int			ioapic;		/* index into ioapics[], -1 none */
    unsigned int	pin;
    unsigned int	low;		/* redirection entry without the mask bit */
} irq_pin_t;

static ioapic_t		ioapics[PEXPERT_MAX_IOAPICS];
static int		ioapic_count;
static irq_pin_t	pins[PEXPERT_NIRQ];
static pexpert_irq_mask_t	current_masked;
static unsigned char	boot_apic_id;
static int		apic_mode;

int
pexpert_apic_mode(void)
{
    return (apic_mode);
}

static int
ioapic_index_for_gsi(unsigned int gsi, unsigned int *pin)
{
    int		i;

    for (i = 0; i < ioapic_count; i++) {
	if (gsi >= ioapics[i].gsi_base &&
	    gsi < ioapics[i].gsi_base + ioapics[i].pins) {
	    *pin = gsi - ioapics[i].gsi_base;
	    return (i);
	}
    }
    return (-1);
}

static int
ioapic_index_for_id(unsigned char id)
{
    int		i;

    for (i = 0; i < ioapic_count; i++)
	if (ioapics[i].id == id)
	    return (i);
    return (-1);
}

/*
 * Redirection entry bits for a source described by MPS INTI flags, with
 * `isa` giving the bus default where the flags say "conforms".
 */
static unsigned int
entry_bits(unsigned short flags, int isa)
{
    unsigned int	low = IOAPIC_DELIVERY_FIXED | IOAPIC_DEST_PHYSICAL;

    switch (flags & INTI_POLARITY_MASK) {
    case INTI_POLARITY_HIGH: break;
    case INTI_POLARITY_LOW:  low |= IOAPIC_ACTIVE_LOW; break;
    default:		     if (!isa) low |= IOAPIC_ACTIVE_LOW; break;
    }
    switch (flags & INTI_TRIGGER_MASK) {
    case INTI_TRIGGER_EDGE:  break;
    case INTI_TRIGGER_LEVEL: low |= IOAPIC_LEVEL; break;
    default:		     if (!isa) low |= IOAPIC_LEVEL; break;
    }
    return (low);
}

static void
assign_pin(int irq, int ioapic, unsigned int pin, unsigned int low)
{
    pins[irq].ioapic = ioapic;
    pins[irq].pin = pin;
    pins[irq].low = low | PEXPERT_VECTOR(irq);
}

/*
 * Build the irq -> pin map from the MADT: ISA irqs first, honouring the
 * overrides, then every other pin as its GSI number.
 */
static void
build_pin_map(const i386_firmware_info_t *info)
{
    int			irq, i, io;
    unsigned int	gsi, pin;
    unsigned char	taken[PEXPERT_GSI_IRQS];

    for (irq = 0; irq < PEXPERT_NIRQ; irq++)
	pins[irq].ioapic = -1;
    for (gsi = 0; gsi < PEXPERT_GSI_IRQS; gsi++)
	taken[gsi] = 0;

    for (irq = 0; irq < 16; irq++) {
	unsigned short	flags = 0;

	if (irq == 2)			/* the cascade line has no device */
	    continue;
	gsi = irq;
	for (i = 0; i < info->iso_count; i++) {
	    if (info->isos[i].isa_irq == irq) {
		gsi = info->isos[i].gsi;
		flags = info->isos[i].flags;
		break;
	    }
	}
	if (gsi >= PEXPERT_GSI_IRQS || (io = ioapic_index_for_gsi(gsi, &pin)) < 0)
	    continue;
	assign_pin(irq, io, pin, entry_bits(flags, 1));
	taken[gsi] = 1;
    }

    /*
     * The rest by GSI number.  Pins below 16 that no ISA irq claimed are
     * left unused: irq numbers below 16 mean ISA lines.
     */
    for (gsi = 16; gsi < PEXPERT_GSI_IRQS; gsi++) {
	if (taken[gsi] || (io = ioapic_index_for_gsi(gsi, &pin)) < 0)
	    continue;
	assign_pin(gsi, io, pin, entry_bits(0, 0));
    }
}

/*
 * The controller.
 */

static int
apic_irq_valid(int irq)
{
    if (irq < 0 || irq >= PEXPERT_SPURIOUS_IRQ)
	return (0);
    return (pins[irq].ioapic >= 0 || msi_irq_active(irq));
}

static void
apic_set_mask(pexpert_irq_mask_t masked)
{
    pexpert_irq_mask_t	changed = masked ^ current_masked;
    int			irq;

    for (irq = 0; changed != 0 && irq < PEXPERT_NIRQ; irq++, changed >>= 1) {
	int	on;

	if ((changed & 1) == 0)
	    continue;
	on = (masked >> irq) & 1;
	if (pins[irq].ioapic >= 0)
	    ioapic_set_masked(&ioapics[pins[irq].ioapic], pins[irq].pin, on);
	else if (irq >= PEXPERT_MSI_IRQ_BASE)
	    msi_set_masked(irq, on);
    }
    current_masked = masked;
}

static void
apic_eoi(int irq)
{
    lapic_eoi();
}

static int
apic_is_spurious(int irq)
{
    /* The spurious vector is not acknowledged. */
    return (irq == PEXPERT_SPURIOUS_IRQ);
}

static int
apic_set_trigger(int irq, int level)
{
    irq_pin_t	*p;

    if (irq < 0 || irq >= PEXPERT_NIRQ || pins[irq].ioapic < 0)
	return (0);
    p = &pins[irq];
    if (level)
	p->low |= IOAPIC_LEVEL;
    else
	p->low &= ~IOAPIC_LEVEL;
    ioapic_set_entry(&ioapics[p->ioapic], p->pin,
		     p->low | (((current_masked >> irq) & 1) ? IOAPIC_MASKED : 0),
		     boot_apic_id);
    return (1);
}

static const intr_controller_t	apic_controller = {
    "APIC",
    apic_irq_valid,
    apic_set_mask,
    apic_eoi,
    apic_is_spurious,
    apic_set_trigger
};

int
pexpert_pci_intx_irq(int bus, int dev, int pin)
{
    unsigned char	id;
    unsigned int	intin;
    unsigned short	flags;
    int			io;

    if (!apic_mode)
	return (-1);
    if (!mptable_pci_route(bus, dev, pin, &id, &intin, &flags))
	return (-1);
    if ((io = ioapic_index_for_id(id)) < 0 || intin >= ioapics[io].pins)
	return (-1);
    if (ioapics[io].gsi_base + intin >= PEXPERT_GSI_IRQS)
	return (-1);
    return (ioapics[io].gsi_base + intin);
}

/*
 * Move interrupt delivery from the 8259s to the APICs.  Returns 0 and
 * leaves the 8259s in charge when the machine cannot do it.
 */
int
apic_intr_enable(const i386_firmware_info_t *info)
{
    unsigned int	lapic_pa;
    volatile unsigned int	*lapic;
    int			i, irq;

    if (info->madt == 0 || info->ioapic_count == 0) {
	printf("pexpert: no MADT with an I/O APIC; staying on the 8259s\n");
	return (0);
    }
    if (!lapic_present()) {
	printf("pexpert: processor has no local APIC; staying on the 8259s\n");
	return (0);
    }

    lapic_pa = lapic_physical_base(info->lapic_address);
    if (lapic_pa == 0)
	lapic_pa = info->lapic_address;
    lapic = (volatile unsigned int *)pexpert_map_physical(lapic_pa, 4096);
    if (lapic == 0) {
	printf("pexpert: cannot map the local APIC at %x\n", lapic_pa);
	return (0);
    }

    ioapic_count = 0;
    for (i = 0; i < info->ioapic_count; i++) {
	ioapic_t	*io = &ioapics[ioapic_count];

	io->base = (volatile unsigned int *)
			pexpert_map_physical(info->ioapics[i].address, 4096);
	if (io->base == 0) {
	    printf("pexpert: cannot map I/O APIC %d at %x\n",
		   info->ioapics[i].id, info->ioapics[i].address);
	    continue;
	}
	io->id = info->ioapics[i].id;
	io->gsi_base = info->ioapics[i].gsi_base;
	ioapic_init(io);
	ioapic_count++;
    }
    if (ioapic_count == 0)
	return (0);

    lapic_init(lapic, PEXPERT_VECTOR(PEXPERT_SPURIOUS_IRQ));
    boot_apic_id = lapic_id();
    msi_init(boot_apic_id);

    build_pin_map(info);
    for (irq = 0; irq < PEXPERT_NIRQ; irq++) {
	if (pins[irq].ioapic >= 0)
	    ioapic_set_entry(&ioapics[pins[irq].ioapic], pins[irq].pin,
			     pins[irq].low | IOAPIC_MASKED, boot_apic_id);
    }
    current_masked = ~(pexpert_irq_mask_t)0;

    /*
     * On boards with an IMCR the 8259s' INTR reaches the processor only
     * through it; point it at the APIC.  The 8259s themselves stay
     * programmed and fully masked, which intr_set_controller does.
     */
    if (info->imcr_present) {
	asm volatile("outb %b0,%w1" : : "a" (0x70), "d" (0x22));
	asm volatile("outb %b0,%w1" : : "a" (0x01), "d" (0x23));
    }

    apic_mode = 1;
    intr_set_controller(&apic_controller);

    printf("pexpert: APIC mode, local APIC %d at %x, %d I/O APIC%s",
	   boot_apic_id, lapic_pa, ioapic_count, ioapic_count == 1 ? "" : "s");
    for (i = 0; i < ioapic_count; i++)
	printf(", %d pins at gsi %d", ioapics[i].pins, ioapics[i].gsi_base);
    printf("\n");
    return (1);
}
