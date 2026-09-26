/*
 * mptable.h
 * Intel MultiProcessor Specification 1.4 tables.
 */

#ifndef _PEXPERT_MPTABLE_H_
#define _PEXPERT_MPTABLE_H_

#include "pexpert_i386.h"

/* Find and map the tables; fills mp_fps, mp_config and imcr_present. */
int mptable_discover(i386_firmware_info_t *info);

/*
 * The I/O APIC (by MADT id) and input pin a PCI function's INTA-INTD
 * (pin 1-4) is wired to, from the table's I/O interrupt entries.
 * Returns 0 when the table does not say.
 */
int mptable_pci_route(int bus, int dev, int pin, unsigned char *ioapic_id,
		      unsigned int *intin, unsigned short *flags);

#endif /* _PEXPERT_MPTABLE_H_ */
