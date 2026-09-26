/*
 * lapic.c
 * The local APIC of the boot processor (Intel SDM vol. 3, ch. 10).
 *
 * Only what interrupt delivery needs: software enable, a spurious vector,
 * the local vectors masked, task priority zero, and EOI.  The timer is
 * left masked; the 8254 stays the system clock.
 */

#include "lapic.h"

#define LAPIC_ID	0x020
#define LAPIC_VERSION	0x030
#define LAPIC_TPR	0x080
#define LAPIC_EOI	0x0B0
#define LAPIC_LDR	0x0D0
#define LAPIC_DFR	0x0E0
#define LAPIC_SVR	0x0F0
#define LAPIC_ESR	0x280
#define LAPIC_ICR_LO	0x300
#define LAPIC_ICR_HI	0x310
#define LAPIC_LVT_TIMER	0x320
#define LAPIC_LVT_LINT0	0x350
#define LAPIC_LVT_LINT1	0x360
#define LAPIC_LVT_ERROR	0x370
#define LAPIC_TIMER_ICR	0x380	/* initial count */
#define LAPIC_TIMER_CCR	0x390	/* current count */
#define LAPIC_TIMER_DCR	0x3E0	/* divide configuration */

#define LAPIC_LVT_TIMER_PERIODIC	0x20000
#define LAPIC_ICR_PENDING		0x1000
#define LAPIC_TIMER_DCR_16		0x3

#define LAPIC_SVR_ENABLE	0x100
#define LAPIC_LVT_MASKED	0x10000

#define APIC_BASE_MSR		0x1B
#define APIC_BASE_ENABLE	(1 << 11)

static volatile unsigned int	*lapic;

static inline unsigned int
lapic_read(unsigned int reg)
{
    return (lapic[reg / 4]);
}

static inline void
lapic_write(unsigned int reg, unsigned int value)
{
    lapic[reg / 4] = value;
}

static unsigned int
cpuid_features(void)
{
    unsigned int	max, eax, edx;

    asm volatile("pushl %%ebx; cpuid; popl %%ebx"
		 : "=a" (max) : "0" (0) : "ecx", "edx");
    if (max < 1)
	return (0);
    asm volatile("pushl %%ebx; cpuid; popl %%ebx"
		 : "=a" (eax), "=d" (edx) : "0" (1) : "ecx");
    return (edx);
}

static int
cpuid_available(void)
{
    unsigned int	before, after;

    /* EFLAGS.ID toggles only on processors with CPUID. */
    asm volatile("pushfl; popl %0" : "=r" (before));
    asm volatile("pushl %0; popfl; pushfl; popl %0"
		 : "=r" (after) : "0" (before ^ 0x200000));
    asm volatile("pushl %0; popfl" : : "r" (before));
    return (((before ^ after) & 0x200000) != 0);
}

int
lapic_present(void)
{
    return (cpuid_available() && (cpuid_features() & LAPIC_CPUID_APIC) != 0);
}

unsigned int
lapic_physical_base(unsigned int fallback)
{
    unsigned int	lo, hi;

    if (!cpuid_available() || (cpuid_features() & LAPIC_CPUID_MSR) == 0)
	return (fallback);

    asm volatile("rdmsr" : "=a" (lo), "=d" (hi) : "c" (APIC_BASE_MSR));
    if ((lo & APIC_BASE_ENABLE) == 0) {
	lo |= APIC_BASE_ENABLE;
	asm volatile("wrmsr" : : "a" (lo), "d" (hi), "c" (APIC_BASE_MSR));
    }
    return (lo & 0xFFFFF000);
}

void
lapic_init(volatile unsigned int *base, unsigned char spurious_vector)
{
    lapic = base;

    /* Flat logical destinations, though delivery here is physical. */
    lapic_write(LAPIC_DFR, 0xFFFFFFFF);
    lapic_write(LAPIC_LDR, (lapic_read(LAPIC_LDR) & 0x00FFFFFF) | 0x01000000);

    /*
     * LINT0 carried the 8259s' INTR while the chipset was in virtual
     * wire mode; the I/O APIC replaces that path, so mask it.
     */
    lapic_write(LAPIC_LVT_TIMER, LAPIC_LVT_MASKED);
    lapic_write(LAPIC_LVT_LINT0, LAPIC_LVT_MASKED);
    lapic_write(LAPIC_LVT_LINT1, LAPIC_LVT_MASKED);
    lapic_write(LAPIC_LVT_ERROR, LAPIC_LVT_MASKED);

    lapic_write(LAPIC_SVR, LAPIC_SVR_ENABLE | spurious_vector);
    lapic_write(LAPIC_TPR, 0);

    /* Clear any error the transition raised. */
    lapic_write(LAPIC_ESR, 0);
    (void) lapic_read(LAPIC_ESR);
}

unsigned char
lapic_id(void)
{
    return (lapic_read(LAPIC_ID) >> 24);
}

void
lapic_eoi(void)
{
    lapic_write(LAPIC_EOI, 0);
}

void
lapic_timer_start(unsigned int initial_count, unsigned char vector, int periodic)
{
    lapic_write(LAPIC_TIMER_DCR, LAPIC_TIMER_DCR_16);
    lapic_write(LAPIC_LVT_TIMER,
		(unsigned int)vector | (periodic ? LAPIC_LVT_TIMER_PERIODIC : 0));
    lapic_write(LAPIC_TIMER_ICR, initial_count);
}

void
lapic_timer_stop(void)
{
    lapic_write(LAPIC_TIMER_ICR, 0);
    lapic_write(LAPIC_LVT_TIMER, LAPIC_LVT_MASKED);
}

void
lapic_timer_set_masked(int masked)
{
    unsigned int	lvt = lapic_read(LAPIC_LVT_TIMER);

    lapic_write(LAPIC_LVT_TIMER,
		masked ? (lvt | LAPIC_LVT_MASKED) : (lvt & ~LAPIC_LVT_MASKED));
}

unsigned int
lapic_timer_read(void)
{
    return (lapic_read(LAPIC_TIMER_CCR));
}

void
lapic_send_ipi(unsigned char dest_apic_id, unsigned int mode_and_vector)
{
    while (lapic_read(LAPIC_ICR_LO) & LAPIC_ICR_PENDING)
	continue;
    lapic_write(LAPIC_ICR_HI, (unsigned int)dest_apic_id << 24);
    lapic_write(LAPIC_ICR_LO, mode_and_vector);
}

int
lapic_ipi_pending(void)
{
    return ((lapic_read(LAPIC_ICR_LO) & LAPIC_ICR_PENDING) != 0);
}

void
lapic_init_secondary(unsigned char spurious_vector)
{
    /* Same registers as the boot processor's; the mapping is shared. */
    lapic_write(LAPIC_DFR, 0xFFFFFFFF);
    lapic_write(LAPIC_LDR, (lapic_read(LAPIC_LDR) & 0x00FFFFFF) | 0x01000000);
    lapic_write(LAPIC_LVT_TIMER, LAPIC_LVT_MASKED);
    lapic_write(LAPIC_LVT_LINT0, LAPIC_LVT_MASKED);
    lapic_write(LAPIC_LVT_LINT1, LAPIC_LVT_MASKED);
    lapic_write(LAPIC_LVT_ERROR, LAPIC_LVT_MASKED);
    lapic_write(LAPIC_SVR, LAPIC_SVR_ENABLE | spurious_vector);
    lapic_write(LAPIC_TPR, 0);
    lapic_write(LAPIC_ESR, 0);
    (void) lapic_read(LAPIC_ESR);
}
