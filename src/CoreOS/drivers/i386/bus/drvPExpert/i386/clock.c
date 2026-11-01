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
#include <machdep/i386/io_inline.h>
#include <machdep/i386/aux_timer_inline.h>

extern int printf(const char *format, ...);
extern void system_timer_dispatch(unsigned int irq, void *state, int ipl);

#define CALIBRATE_US		10000
#define CALIBRATE_SAMPLES	5

static unsigned int	count_per_tick;

/*
 * Local APIC counts per second over one window, timed by the 8254's
 * counter 2 counting down from 0xFFFF.  The kernel's timestamp is not
 * used: it is IRQ 0 ticks plus counter 0's fraction, and a processor
 * held off across reloads (a host descheduling a virtual CPU) loses or
 * gains whole ticks there.  Counter 2 needs no interrupt.  Each counter
 * read sits between two LAPIC reads; a sample where a pair is far apart
 * or counter 2 ran out (OUT2 high) was held off and returns 0.
 */
static unsigned int
lapic_rate(unsigned int us)
{
    timer_ctl_reg_t	reg;
    unsigned int	port61, target, pit, i;
    unsigned int	l0, l1, m0, m1;
    int			bad;

    target = (unsigned long long)us * TIMER_CONSTANT / 1000000;
    port61 = inb(0x61);
    outb(0x61, (port61 & ~0x02) | 0x01);	/* counter 2 gate on, speaker off */
    reg = (timer_ctl_reg_t){ 0 };
    reg.mode = TIMER_EVENTMODE;
    reg.rw = TIMER_CTL_RW_BOTH;
    reg.sel = TIMER_CNT2_SEL;
    timer_set_ctl(reg);

    lapic_timer_start(0xFFFFFFFF, PEXPERT_VECTOR(PEXPERT_TIMER_IRQ), 0);
    lapic_timer_set_masked(1);
    l0 = lapic_timer_read();
    aux_timer_start();
    l1 = lapic_timer_read();
    for (i = 0; i < 1000000; i++) {
	m0 = lapic_timer_read();
	aux_timer_stop(&pit);
	m1 = lapic_timer_read();
	if (pit >= target)
	    break;
    }
    lapic_timer_stop();
    bad = (inb(0x61) & 0x20) || i == 1000000 ||
	  (l0 - l1) + (m0 - m1) > (l0 - m1) / 256;
    outb(0x61, port61);
    if (bad)
	return (0);
    /* from the midpoint of the start pair to the midpoint of the end pair */
    return ((unsigned long long)((l0 - m0) + (l1 - m1)) * TIMER_CONSTANT /
	    (2 * pit));
}

/*
 * The median of five clean samples, if the middle three agree within
 * 1%; otherwise try again, and give up after three sets.
 */
static unsigned int
lapic_calibrate(void)
{
    unsigned int	s[CALIBRATE_SAMPLES], rate, n, i, j, tries;

    for (tries = 0; tries < 3; tries++) {
	for (n = 0, i = 0; n < CALIBRATE_SAMPLES && i < 4 * CALIBRATE_SAMPLES; i++) {
	    if ((rate = lapic_rate(CALIBRATE_US)) == 0)
		continue;
	    for (j = n++; j > 0 && s[j - 1] > rate; j--)
		s[j] = s[j - 1];
	    s[j] = rate;
	}
	if (n == CALIBRATE_SAMPLES && s[3] - s[1] <= s[2] / 100)
	    return (s[2]);
    }
    return (0);
}

int
lapic_clock_enable(void)
{
    unsigned int	per_second;

    if (!pexpert_apic_mode())
	return (0);

    per_second = lapic_calibrate();
    if (per_second == 0) {
	printf("pexpert: local APIC timer calibration did not settle; keeping the 8254\n");
	return (0);
    }
    if (per_second < 100000) {
	printf("pexpert: local APIC timer barely counts (%u in 10 ms); keeping the 8254\n",
	       per_second / 100);
	return (0);
    }

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
