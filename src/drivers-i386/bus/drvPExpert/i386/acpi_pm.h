/*
 * acpi_pm.h
 * ACPI power management from the FADT: enable, power button, power off,
 * reset.
 */

#ifndef _PEXPERT_ACPI_PM_H_
#define _PEXPERT_ACPI_PM_H_

#include "pexpert_i386.h"

/* Put the chipset in ACPI mode and arm the power button; 1 on success. */
int acpi_pm_enable(const i386_firmware_info_t *info);

#endif /* _PEXPERT_ACPI_PM_H_ */
