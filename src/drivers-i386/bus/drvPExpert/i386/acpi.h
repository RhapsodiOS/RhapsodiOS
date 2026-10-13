/*
 * acpi.h
 * ACPI static tables: RSDP, RSDT/XSDT, MADT, FADT, HPET, MCFG.
 * No AML, ever.
 */

#ifndef _PEXPERT_ACPI_H_
#define _PEXPERT_ACPI_H_

#include "pexpert_i386.h"

/*
 * Locate the tables (`rsdp_hint` is a physical RSDP address the booter
 * handed over, 0 to scan for one) and fill in the ACPI half of `info`.
 * Returns 1 when an RSDP was found.
 */
int acpi_discover(unsigned int rsdp_hint, i386_firmware_info_t *info);

#endif /* _PEXPERT_ACPI_H_ */
