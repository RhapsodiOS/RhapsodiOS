/*
 * lapic.h
 * The local APIC of the boot processor.
 */

#ifndef _PEXPERT_CHIPS_LAPIC_H_
#define _PEXPERT_CHIPS_LAPIC_H_

/* CPUID leaf 1 feature bits this needs. */
#define LAPIC_CPUID_MSR		(1 << 5)
#define LAPIC_CPUID_APIC	(1 << 9)

/* Whether the processor has a local APIC at all. */
int lapic_present(void);

/*
 * The physical base the APIC_BASE MSR reports (the MSR's global enable
 * is set if it was clear), or `fallback` on a processor without the MSR.
 */
unsigned int lapic_physical_base(unsigned int fallback);

/*
 * Bring the local APIC up on a mapped base: software-enable it with
 * `spurious_vector`, mask its local vectors, accept every priority.
 */
void lapic_init(volatile unsigned int *base, unsigned char spurious_vector);

unsigned char lapic_id(void);
void lapic_eoi(void);

#endif /* _PEXPERT_CHIPS_LAPIC_H_ */
