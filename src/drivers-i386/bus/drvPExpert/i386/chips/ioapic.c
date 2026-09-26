/*
 * ioapic.c
 * The 82093AA-style I/O APIC: an index register and a window register,
 * and behind them one two-dword redirection entry per input pin.
 */

#include "ioapic.h"

#define IOREGSEL	0
#define IOWIN		4		/* dword index of the window at +0x10 */

#define IOAPIC_REG_ID		0x00
#define IOAPIC_REG_VERSION	0x01
#define IOAPIC_REG_REDIR(pin)	(0x10 + 2 * (pin))

static inline unsigned int
ioapic_read(ioapic_t *ioapic, unsigned int reg)
{
    ioapic->base[IOREGSEL] = reg;
    return (ioapic->base[IOWIN]);
}

static inline void
ioapic_write(ioapic_t *ioapic, unsigned int reg, unsigned int value)
{
    ioapic->base[IOREGSEL] = reg;
    ioapic->base[IOWIN] = value;
}

void
ioapic_init(ioapic_t *ioapic)
{
    unsigned int	pin;

    ioapic->pins = ((ioapic_read(ioapic, IOAPIC_REG_VERSION) >> 16) & 0xFF) + 1;

    for (pin = 0; pin < ioapic->pins; pin++)
	ioapic_write(ioapic, IOAPIC_REG_REDIR(pin), IOAPIC_MASKED);
}

void
ioapic_set_entry(ioapic_t *ioapic, unsigned int pin, unsigned int low,
		 unsigned char dest_apic_id)
{
    if (pin >= ioapic->pins)
	return;

    /* Mask while the entry changes, and set the destination first. */
    ioapic_write(ioapic, IOAPIC_REG_REDIR(pin), low | IOAPIC_MASKED);
    ioapic_write(ioapic, IOAPIC_REG_REDIR(pin) + 1, (unsigned int)dest_apic_id << 24);
    ioapic_write(ioapic, IOAPIC_REG_REDIR(pin), low);
}

void
ioapic_set_masked(ioapic_t *ioapic, unsigned int pin, int masked)
{
    unsigned int	low;

    if (pin >= ioapic->pins)
	return;

    low = ioapic_read(ioapic, IOAPIC_REG_REDIR(pin));
    if (masked)
	low |= IOAPIC_MASKED;
    else
	low &= ~IOAPIC_MASKED;
    ioapic_write(ioapic, IOAPIC_REG_REDIR(pin), low);
}
