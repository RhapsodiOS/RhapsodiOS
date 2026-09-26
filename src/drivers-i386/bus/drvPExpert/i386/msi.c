/*
 * msi.c
 * Message signalled interrupts (PCI Local Bus spec 3.0 sec 6.8).
 *
 * A function that has the MSI or MSI-X capability writes an interrupt
 * message to the local APIC instead of asserting an INTx line, so it needs
 * no I/O APIC pin and no routing table.  Each enabled function gets one
 * vector from the pool of PEXPERT_MSI_IRQS irqs, delivered as a fixed,
 * edge triggered interrupt to the boot processor.
 */

#include "msi.h"
#include "pexpert_i386.h"

extern int printf(const char *format, ...);

#define PCI_COMMAND		0x04
#define PCI_STATUS		0x06
#define PCI_CAPABILITY_LIST	0x34
#define PCI_BAR0		0x10

#define PCI_COMMAND_INTX_DISABLE	0x0400
#define PCI_STATUS_CAP_LIST		0x0010

#define PCI_CAP_ID_MSI		0x05
#define PCI_CAP_ID_MSIX		0x11

/* MSI capability (6.8.1) */
#define MSI_CONTROL		0x02
#define MSI_ADDRESS_LO		0x04
#define MSI_ADDRESS_HI		0x08
#define MSI_CONTROL_ENABLE	0x0001
#define MSI_CONTROL_64BIT	0x0080
#define MSI_CONTROL_MASKABLE	0x0100

/* MSI-X capability (6.8.2) */
#define MSIX_CONTROL		0x02
#define MSIX_TABLE		0x04
#define MSIX_CONTROL_ENABLE	0x8000
#define MSIX_CONTROL_MASK_ALL	0x4000
#define MSIX_ENTRY_ADDRESS_LO	0
#define MSIX_ENTRY_ADDRESS_HI	1
#define MSIX_ENTRY_DATA		2
#define MSIX_ENTRY_CONTROL	3
#define MSIX_ENTRY_MASKED	1

/* Message address and data (Intel SDM vol. 3, 10.11) */
#define MSI_ADDRESS_BASE	0xFEE00000

typedef struct {
    int			used;
    int			bus, dev, fn;
    int			is_msix;
    int			cap;		/* capability offset */
    int			maskable;
    volatile unsigned int	*msix_entry;
} msi_slot_t;

static msi_slot_t	slots[PEXPERT_MSI_IRQS];
static unsigned char	dest_id;

void
msi_init(unsigned char dest_apic_id)
{
    dest_id = dest_apic_id;
}

static unsigned int
cfg_read(int bus, int dev, int fn, int off, int size)
{
    unsigned int	val = 0xFFFFFFFF;

    (void) pexpert_pci_config_read(bus, dev, fn, off, size, &val);
    return (val);
}

static void
cfg_write(int bus, int dev, int fn, int off, int size, unsigned int val)
{
    (void) pexpert_pci_config_write(bus, dev, fn, off, size, val);
}

/* Offset of capability `id`, or 0. */
static int
find_capability(int bus, int dev, int fn, unsigned char id)
{
    int		off, guard;

    if ((cfg_read(bus, dev, fn, PCI_STATUS, 2) & PCI_STATUS_CAP_LIST) == 0)
	return (0);

    off = cfg_read(bus, dev, fn, PCI_CAPABILITY_LIST, 1) & 0xFC;
    for (guard = 0; off >= 0x40 && guard < 48; guard++) {
	if ((cfg_read(bus, dev, fn, off, 1) & 0xFF) == id)
	    return (off);
	off = cfg_read(bus, dev, fn, off + 1, 1) & 0xFC;
    }
    return (0);
}

static msi_slot_t *
find_slot(int bus, int dev, int fn)
{
    int		i;

    for (i = 0; i < PEXPERT_MSI_IRQS; i++)
	if (slots[i].used && slots[i].bus == bus && slots[i].dev == dev &&
	    slots[i].fn == fn)
	    return (&slots[i]);
    return (0);
}

static unsigned int
message_data(int irq)
{
    /* Fixed delivery, edge triggered: just the vector. */
    return (PEXPERT_VECTOR(irq));
}

static unsigned int
message_address(void)
{
    /* Physical destination, no redirection hint. */
    return (MSI_ADDRESS_BASE | ((unsigned int)dest_id << 12));
}

/*
 * Map the MSI-X table's first entry: the BAR the capability names plus
 * the offset it carries.
 */
static volatile unsigned int *
map_msix_entry(int bus, int dev, int fn, int cap)
{
    unsigned int	table, bir, offset, bar, base;
    void		*p;

    table = cfg_read(bus, dev, fn, cap + MSIX_TABLE, 4);
    bir = table & 7;
    offset = table & ~7;
    if (bir > 5)
	return (0);

    bar = cfg_read(bus, dev, fn, PCI_BAR0 + 4 * bir, 4);
    if (bar & 1)			/* an I/O BAR cannot hold the table */
	return (0);
    if ((bar & 6) == 4) {		/* 64-bit BAR: the high half must be zero */
	if (cfg_read(bus, dev, fn, PCI_BAR0 + 4 * bir + 4, 4) != 0)
	    return (0);
    }
    base = bar & 0xFFFFFFF0;
    if (base == 0)
	return (0);

    p = pexpert_map_physical(base + offset, 16);
    return ((volatile unsigned int *)p);
}

int
msi_enable(int bus, int dev, int fn)
{
    msi_slot_t		*slot;
    int			i, irq, cap;
    unsigned int	control;

    if (!pexpert_apic_mode())
	return (-1);

    if ((slot = find_slot(bus, dev, fn)) != 0)
	return (PEXPERT_MSI_IRQ_BASE + (slot - slots));

    for (i = 0; i < PEXPERT_MSI_IRQS && slots[i].used; i++)
	continue;
    if (i == PEXPERT_MSI_IRQS) {
	printf("msi: no vectors left for %d:%d.%d\n", bus, dev, fn);
	return (-1);
    }
    slot = &slots[i];
    irq = PEXPERT_MSI_IRQ_BASE + i;

    if ((cap = find_capability(bus, dev, fn, PCI_CAP_ID_MSIX)) != 0) {
	volatile unsigned int	*entry = map_msix_entry(bus, dev, fn, cap);

	if (entry == 0) {
	    printf("msi: %d:%d.%d: cannot map the MSI-X table\n", bus, dev, fn);
	    cap = 0;
	} else {
	    /* Mask the whole function while the entry is written. */
	    control = cfg_read(bus, dev, fn, cap + MSIX_CONTROL, 2);
	    cfg_write(bus, dev, fn, cap + MSIX_CONTROL, 2,
		      control | MSIX_CONTROL_ENABLE | MSIX_CONTROL_MASK_ALL);

	    entry[MSIX_ENTRY_CONTROL] = MSIX_ENTRY_MASKED;
	    entry[MSIX_ENTRY_ADDRESS_LO] = message_address();
	    entry[MSIX_ENTRY_ADDRESS_HI] = 0;
	    entry[MSIX_ENTRY_DATA] = message_data(irq);
	    entry[MSIX_ENTRY_CONTROL] = 0;

	    cfg_write(bus, dev, fn, cap + MSIX_CONTROL, 2,
		      (control | MSIX_CONTROL_ENABLE) & ~MSIX_CONTROL_MASK_ALL);

	    slot->is_msix = 1;
	    slot->maskable = 1;
	    slot->msix_entry = entry;
	}
    }

    if (cap == 0) {
	if ((cap = find_capability(bus, dev, fn, PCI_CAP_ID_MSI)) == 0)
	    return (-1);

	control = cfg_read(bus, dev, fn, cap + MSI_CONTROL, 2);
	/* One vector: multiple message enable = 0. */
	control &= ~0x0071;

	cfg_write(bus, dev, fn, cap + MSI_ADDRESS_LO, 4, message_address());
	if (control & MSI_CONTROL_64BIT) {
	    cfg_write(bus, dev, fn, cap + MSI_ADDRESS_HI, 4, 0);
	    cfg_write(bus, dev, fn, cap + 0x0C, 2, message_data(irq));
	    if (control & MSI_CONTROL_MASKABLE)
		cfg_write(bus, dev, fn, cap + 0x10, 4, 0);
	} else {
	    cfg_write(bus, dev, fn, cap + 0x08, 2, message_data(irq));
	    if (control & MSI_CONTROL_MASKABLE)
		cfg_write(bus, dev, fn, cap + 0x0C, 4, 0);
	}
	cfg_write(bus, dev, fn, cap + MSI_CONTROL, 2, control | MSI_CONTROL_ENABLE);

	slot->is_msix = 0;
	slot->maskable = (control & MSI_CONTROL_MASKABLE) != 0;
	slot->msix_entry = 0;
    }

    /* The function must not also drive its INTx line. */
    cfg_write(bus, dev, fn, PCI_COMMAND, 2,
	      cfg_read(bus, dev, fn, PCI_COMMAND, 2) | PCI_COMMAND_INTX_DISABLE);

    slot->used = 1;
    slot->bus = bus;
    slot->dev = dev;
    slot->fn = fn;
    slot->cap = cap;

    printf("msi: %d:%d.%d uses %s on irq %d\n", bus, dev, fn,
	   slot->is_msix ? "MSI-X" : "MSI", irq);
    return (irq);
}

int
msi_disable(int bus, int dev, int fn)
{
    msi_slot_t		*slot;
    unsigned int	control;

    if ((slot = find_slot(bus, dev, fn)) == 0)
	return (-1);

    if (slot->is_msix) {
	slot->msix_entry[MSIX_ENTRY_CONTROL] = MSIX_ENTRY_MASKED;
	control = cfg_read(bus, dev, fn, slot->cap + MSIX_CONTROL, 2);
	cfg_write(bus, dev, fn, slot->cap + MSIX_CONTROL, 2,
		  control & ~MSIX_CONTROL_ENABLE);
    } else {
	control = cfg_read(bus, dev, fn, slot->cap + MSI_CONTROL, 2);
	cfg_write(bus, dev, fn, slot->cap + MSI_CONTROL, 2,
		  control & ~MSI_CONTROL_ENABLE);
    }
    cfg_write(bus, dev, fn, PCI_COMMAND, 2,
	      cfg_read(bus, dev, fn, PCI_COMMAND, 2) & ~PCI_COMMAND_INTX_DISABLE);

    slot->used = 0;
    return (0);
}

int
msi_irq_active(int irq)
{
    irq -= PEXPERT_MSI_IRQ_BASE;
    return (irq >= 0 && irq < PEXPERT_MSI_IRQS && slots[irq].used);
}

void
msi_set_masked(int irq, int masked)
{
    msi_slot_t		*slot;
    int			off;

    irq -= PEXPERT_MSI_IRQ_BASE;
    if (irq < 0 || irq >= PEXPERT_MSI_IRQS || !slots[irq].used)
	return;
    slot = &slots[irq];
    if (!slot->maskable)
	return;

    if (slot->is_msix) {
	slot->msix_entry[MSIX_ENTRY_CONTROL] = masked ? MSIX_ENTRY_MASKED : 0;
	return;
    }

    /* MSI: the mask bits register follows the data register. */
    off = slot->cap +
	  ((cfg_read(slot->bus, slot->dev, slot->fn, slot->cap + MSI_CONTROL, 2)
	    & MSI_CONTROL_64BIT) ? 0x10 : 0x0C);
    cfg_write(slot->bus, slot->dev, slot->fn, off, 4, masked ? 1 : 0);
}
