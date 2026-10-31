/*
 * clock.c
 * The local APIC timer as the system tick.
 *
 * The kernel's machine_clock.c drives the tick from the 8254's IRQ 0 and
 * reads the 8254's counter for the fraction of a tick that has passed.
 * Both are one interrupt line and one countdown counter, which the local
 * APIC timer also is: in periodic mode it counts down from its initial
 * count, reloads, and raises its vector.  So the switch is to hand the
 * kernel a different countdown to read, and to deliver the same tick
 * handler on the timer's irq instead of IRQ 0.  The 8254 keeps counting
 * with its interrupt masked, which leaves us_spin's calibration alone.
 */

#include "pexpert_i386.h"
#include "chips/lapic.h"

#include <machdep/i386/intr_exported.h>

extern int printf(const char *format, ...);
extern void IOGetTimestamp(unsigned long long *timestamp);
extern void system_timer_dispatch(unsigned int irq, void *state, int ipl);

#define CALIBRATE_US		10000

static unsigned int	count_per_tick;

static unsigned int
lapic_ticks_in(unsigned int us)
{
    unsigned int	before, after;
    unsigned int	i;
    unsigned long long	start, now, duration = (unsigned long long)us * 1000;

    lapic_timer_start(0xFFFFFFFF, PEXPERT_VECTOR(PEXPERT_TIMER_IRQ), 0);
    lapic_timer_set_masked(1);
    IOGetTimestamp(&start);
    before = lapic_timer_read();
    for (i = 0; i < 1000000; i++) {
	IOGetTimestamp(&now);
	if (now - start >= duration)
	    break;
    }
    after = lapic_timer_read();
    lapic_timer_stop();
    if (i == 1000000)
	return (0);
    return ((unsigned long long)(before - after) * duration / (now - start));
}

int
lapic_clock_enable(void)
{
    unsigned int	per_10ms, per_second;

    if (!pexpert_apic_mode())
	return (0);

    /* Read the running 8254 clock; spin-delay calibration can drift. */
    per_10ms = lapic_ticks_in(CALIBRATE_US);
    if (per_10ms < 1000) {
	printf("pexpert: local APIC timer barely counts (%u in 10 ms); keeping the 8254\n",
	       per_10ms);
	return (0);
    }
    per_second = per_10ms * 100;

    /*
     * Same handler, new source.  Registering first then dropping IRQ 0
     * keeps a tick flowing; the fraction is taken from the new counter
     * as soon as the kernel is told.
     */
    if (!intr_register_irq(PEXPERT_TIMER_IRQ, system_timer_dispatch, 0, INTR_IPL6)) {
	printf("pexpert: could not register the local APIC timer irq\n");
	return (0);
    }
    count_per_tick = clock_set_tick_source(lapic_timer_read, per_second);
    lapic_timer_start(count_per_tick, PEXPERT_VECTOR(PEXPERT_TIMER_IRQ), 1);
    (void) intr_enable_irq(PEXPERT_TIMER_IRQ);
    (void) intr_unregister_irq(0);

    printf("pexpert: local APIC timer is the clock, %u counts per tick (%u MHz bus / %d)\n",
	   count_per_tick, (per_second / 1000000) * LAPIC_TIMER_DIVIDE,
	   LAPIC_TIMER_DIVIDE);
    return (1);
}
