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

/*
 * The local APIC timer, driven by the bus clock divided by 16.  Counts
 * down from the initial count; in periodic mode it reloads on reaching
 * zero and raises `vector`.
 */
#define LAPIC_TIMER_DIVIDE	16
void lapic_timer_start(unsigned int initial_count, unsigned char vector, int periodic);
void lapic_timer_stop(void);
void lapic_timer_set_masked(int masked);
unsigned int lapic_timer_read(void);

/*
 * Inter-processor interrupts, in physical destination mode.  The
 * delivery modes are the SDM's (10.6.1): fixed, INIT, start-up.
 */
#define LAPIC_IPI_FIXED		0x000
#define LAPIC_IPI_INIT		0x500
#define LAPIC_IPI_STARTUP	0x600
#define LAPIC_IPI_ASSERT	0x4000
#define LAPIC_IPI_LEVEL		0x8000
void lapic_send_ipi(unsigned char dest_apic_id, unsigned int mode_and_vector);
int lapic_ipi_pending(void);

/*
 * Bring up the local APIC of a processor other than the boot one, on
 * the mapping lapic_init() was given.
 */
void lapic_init_secondary(unsigned char spurious_vector);

#endif /* _PEXPERT_CHIPS_LAPIC_H_ */
