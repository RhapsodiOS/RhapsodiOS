/*
 * smp.h
 * Starting the other processors.
 */

#ifndef _PEXPERT_SMP_H_
#define _PEXPERT_SMP_H_

#include "pexpert_i386.h"

/* Start every processor the MADT lists but the boot one; returns how many came up. */
int smp_start(const i386_firmware_info_t *info, unsigned char boot_apic_id,
	      unsigned char spurious_vector);

#endif /* _PEXPERT_SMP_H_ */
