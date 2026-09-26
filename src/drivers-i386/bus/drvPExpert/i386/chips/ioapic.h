/*
 * ioapic.h
 * The 82093AA-style I/O APIC.
 */

#ifndef _PEXPERT_CHIPS_IOAPIC_H_
#define _PEXPERT_CHIPS_IOAPIC_H_

typedef struct ioapic {
    volatile unsigned int	*base;	/* mapped registers */
    unsigned char		id;
    unsigned int		gsi_base;
    unsigned int		pins;
} ioapic_t;

/* Redirection entry bits, low dword. */
#define IOAPIC_DELIVERY_FIXED	(0 << 8)
#define IOAPIC_DEST_PHYSICAL	(0 << 11)
#define IOAPIC_ACTIVE_LOW	(1 << 13)
#define IOAPIC_LEVEL		(1 << 15)
#define IOAPIC_MASKED		(1 << 16)

/* Reads the chip's pin count into ioapic->pins and masks every pin. */
void ioapic_init(ioapic_t *ioapic);

/*
 * Program a pin: `low` carries vector, polarity, trigger and mask; the
 * interrupt is delivered to the local APIC with `dest_apic_id`.
 */
void ioapic_set_entry(ioapic_t *ioapic, unsigned int pin, unsigned int low,
		      unsigned char dest_apic_id);

void ioapic_set_masked(ioapic_t *ioapic, unsigned int pin, int masked);

#endif /* _PEXPERT_CHIPS_IOAPIC_H_ */
