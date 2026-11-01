/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * Copyright (c) 1992, 1993, 1994, 1995 NeXT Computer, Inc.
 *
 * Machine dependent clock and timer routines
 * for i386 architecture.
 *
 * HISTORY
 *
 * 11 June 1995 ? at NeXT
 *	Major rewrite for new clock API - banished
 *	all occurrances of ns_time_t in favor of
 *	tvalspec_t.
 *
 * 24 March 1992 ? at NeXT
 *	Created from m68k version.
 */
 
#import <mach/mach_types.h>

#import <bsd/sys/param.h>
#import <bsd/sys/time.h>

#import <kern/clock.h>
#import <vm/vm_kern.h>

#import	<machdep/i386/timer.h>
#import <machdep/i386/timer_inline.h>
#import <machdep/i386/intr_exported.h>
#import <machdep/i386/io_inline.h>
#import <machdep/i386/cpu_inline.h>
#import <machdep/i386/aux_timer_inline.h>

static tvalspec_t	time_of_boot;	/* rel to 1/1/70 (UNIX T[0]) */
static tvalspec_t	last_calendar;	/* last calendar time handed out */

/*
 * Nanosecond event counter ;-)
 */

static struct _system_clock {
    tvalspec_t		counter;
    unsigned int	last_timer_count;
    tvalspec_t		last_stamp;	/* last stamp handed out */
    mapped_tvalspec_t	*mapped_counter;
    unsigned int	timer_const;
    unsigned int	tsc_per_tick;	/* 0: no TSC, count interrupts */
    unsigned long long	reload_tsc;	/* TSC at the reload counter counts */
} system_clock;

static tvalspec_t	system_time_stamp(void);

#define EFL_ID		0x200000	/* toggles only with CPUID */
#define CPUID_TSC	0x10

static inline unsigned long long
rdtsc(void)
{
    unsigned int	lo, hi;

    asm volatile(".byte 0x0f, 0x31" : "=a" (lo), "=d" (hi));
    return (((unsigned long long)hi << 32) | lo);
}

/*
 * TSC counts per tick, timed by the 8254's counter 2 counting down from
 * 0xFFFF as pexpert's local APIC calibration does.  Counter 2 needs no
 * interrupt, and each read sits between two TSC reads, so a sample
 * whose reads were held off, or where counter 2 ran out, is refused.
 * 0 when there is no TSC or no clean sample.
 */
static unsigned int
tsc_calibrate(void)
{
    timer_ctl_reg_t	reg;
    unsigned int	efl = eflags(), eax, edx, port61, pit, i, tries;
    unsigned long long	t0, t1, t2, t3;

    set_eflags(efl ^ EFL_ID);
    if (((eflags() ^ efl) & EFL_ID) == 0)
	return (0);
    set_eflags(efl);
    asm volatile("pushl %%ebx; cpuid; popl %%ebx"
	    : "=a" (eax), "=d" (edx) : "0" (1) : "ecx");
    if ((edx & CPUID_TSC) == 0)
	return (0);

    port61 = inb(0x61);
    outb(0x61, (port61 & ~0x02) | 0x01);	/* counter 2 gate on, speaker off */
    reg = (timer_ctl_reg_t){ 0 };
    reg.mode = TIMER_EVENTMODE;
    reg.rw = TIMER_CTL_RW_BOTH;
    reg.sel = TIMER_CNT2_SEL;
    for (tries = 0; tries < 5; tries++) {
	timer_set_ctl(reg);
	t0 = rdtsc();
	aux_timer_start();
	t1 = rdtsc();
	for (i = 0; i < 1000000; i++) {
	    t2 = rdtsc();
	    aux_timer_stop(&pit);
	    t3 = rdtsc();
	    if (pit >= system_clock.timer_const)
		break;
	}
	if (!(inb(0x61) & 0x20) && i < 1000000 &&
	    (t1 - t0) + (t3 - t2) < (t3 - t0) / 256)
	    break;
    }
    outb(0x61, port61);
    if (tries == 5)
	return (0);
    /* from the midpoint of the start pair to the midpoint of the end pair */
    return ((t2 + t3 - t0 - t1) * system_clock.timer_const / (2 * pit));
}

/*
 * Where the fraction of a tick comes from: a countdown that reloads at
 * timer_const on every tick interrupt.  The 8254's counter 0 by default;
 * the platform expert can offer the local APIC timer instead.
 */
static unsigned int
timer_read_count(void)
{
    timer_latch(TIMER_CNT0_SEL);
    return (timer_read(TIMER_CNT0_SEL));
}

static unsigned int	(*tick_source_read)(void) = timer_read_count;

/*
 * Reloads of the tick source since the one system_clock.counter has
 * counted.  The TSC keeps counting while the processor is held off and
 * the reloads' interrupts merge, so it can tell two reloads from one.
 * Sets *count to the source's count and *reload to the TSC at its
 * latest reload, or 0 if the read was held off; returns -1 when the
 * TSC cannot tell.  Call at splclock.
 */
static int
tick_reloads(
    unsigned int	*count,
    unsigned long long	*reload
)
{
    unsigned int	per = system_clock.tsc_per_tick;
    unsigned long long	t0, t1, since;

    *reload = 0;
    if (per == 0) {
	*count = (*tick_source_read)();
	return (-1);
    }
    t0 = rdtsc();
    *count = (*tick_source_read)();
    t1 = rdtsc();
    if (t1 - t0 > per / 16)
	return (-1);
    *reload = t0 + (t1 - t0) / 2 -
	(unsigned long long)(system_clock.timer_const - *count) * per /
		system_clock.timer_const;
    if (system_clock.reload_tsc == 0)
	return (-1);
    since = *reload - system_clock.reload_tsc + per / 2;
    if ((long long)since < 0)
	return (0);
    return (since / per);
}

unsigned int
clock_set_tick_source(
    unsigned int	(*read_count)(void),
    unsigned int	counts_per_second
)
{
    unsigned int	count_per_tick;
    int			s;

    count_per_tick = counts_per_second / TICKS_PER_SEC;
    if ((counts_per_second % TICKS_PER_SEC) >= (TICKS_PER_SEC / 2))
    	count_per_tick++;

    s = splclock();
    tick_source_read = read_count;
    system_clock.timer_const = count_per_tick;
    system_clock.last_timer_count = count_per_tick;
    system_clock.reload_tsc = 0;	/* the next tick sets it */
    splx(s);

    return (count_per_tick);
}

static struct _system_timer {
    boolean_t		is_set;
    tvalspec_t		expire_time;
    timer_func_t	expire_func;
} system_timer;

struct _interrupt_location {
    unsigned int	eip;
    int			rpl;
    int			ipl;
};

static void machine_hardclock(
		struct _interrupt_location	*loc);

static boolean_t	hardclock_enabled;

void
system_timer_dispatch(
    unsigned int		irq,
    void			*_state,
    int				ipl
)
{
    thread_saved_state_t	*state = (thread_saved_state_t *)_state;
    tvalspec_t			now;
    struct _interrupt_location	loc;
    unsigned int		count;
    unsigned long long		reload;
    int				n;

    // count every reload since the last tick, not this interrupt: held
    // off, two reloads raise one interrupt, or a counted one raises its own
    n = tick_reloads(&count, &reload);
    if (reload)
	system_clock.reload_tsc = reload;
    else if (system_clock.reload_tsc)
	system_clock.reload_tsc += system_clock.tsc_per_tick;
    if (n < 0)
	n = 1;
    while (n-- > 0)
	ADD_TVALSPEC_NSEC(&system_clock.counter, NSEC_PER_TICK);
    system_clock.last_timer_count = system_clock.timer_const;

    if (state) {
	loc.eip	= state->frame.eip;

	if (!(state->frame.eflags & EFL_VM))
	    loc.rpl = state->frame.cs.rpl;
	else
	    loc.rpl = USER_PRIV;

	loc.ipl = ipl;
    }
    else {
	loc.eip = 0x00000000;
	loc.rpl = KERN_PRIV;
	loc.ipl = ipl;
    }
    
    if (hardclock_enabled)
    	machine_hardclock(&loc);

    now = system_time_stamp();
    
    if (system_timer.is_set &&
    	CMP_TVALSPEC(&system_timer.expire_time, &now) <= 0) {
	    system_timer.is_set = FALSE;
	    (*system_timer.expire_func)(now);
    }
}

void
hardclock_init(void)
{
    hardclock_enabled = TRUE;
}

static void
machine_hardclock(
    struct _interrupt_location	*loc
)
{
    clock_interrupt(tick, (loc->rpl == USER_PRIV), (loc->ipl == 0));

    hardclock(loc->eip, STATUS_WORD(loc->rpl, loc->ipl));
}

static unsigned int	us_spin_us_const = 0x2000;

void
us_spin(
    unsigned int	us
)
{
    unsigned int	constant;
    
    while (us-- > 0) {
	constant = us_spin_us_const;

	while (constant-- > 0)
	    continue;
    }
}

void
us_spin_calibrate(void)
{
    timer_ctl_reg_t	reg;
    timer_cnt_val_t	leftover;
    int			s;
    
    reg = (timer_ctl_reg_t) { 0 };

    reg.mode = TIMER_EVENTMODE;
    reg.rw = TIMER_CTL_RW_BOTH;
    timer_set_ctl(reg);

    s = splclock();
    timer_write(TIMER_CNT0_SEL, TIMER_COUNT_MAX);
    
    us_spin(1);
    
    timer_latch(TIMER_CNT0_SEL); leftover = timer_read(TIMER_CNT0_SEL);
    splx(s);

    /*
     * Formula for spin constant is :
     *  (loopcount * timer clock speed)/ counter ticks
     */
    us_spin_us_const =
	(us_spin_us_const *
	    (TIMER_CONSTANT / (TIMER_COUNT_MAX - leftover))) / 1000000;
}

static timer_cnt_val_t
system_timer_constant(void)
{
    unsigned int	constant;
    
    constant = TIMER_CONSTANT / TICKS_PER_SEC;
    if ((TIMER_CONSTANT % TICKS_PER_SEC) >= (TICKS_PER_SEC / 2))
    	constant++;
		
    return ((timer_cnt_val_t)constant);
}

/*
 *  Initialize the clock and timer interface.
 */
void
machine_clock_init(void)
{
    timer_ctl_reg_t		reg;
    int				s;
    extern void			readtodc(unsigned int *);

    (void) intr_register_irq(0, system_timer_dispatch, 0, INTR_IPL6);
    (void) intr_enable_irq(0);

    /*
     * Initialize the RTC, and set the system's idea of time.
     */
    readtodc(&time_of_boot.tv_sec);

    /*
     * Set up the timer.
     */
    s = splclock();

    reg = (timer_ctl_reg_t){ 0 };

    reg.mode = TIMER_NDIVMODE;
    reg.rw = TIMER_CTL_RW_BOTH;
    timer_set_ctl(reg);

    // save constant for later use
    system_clock.timer_const = system_timer_constant();
    
    timer_write(TIMER_CNT0_SEL, system_clock.timer_const);
    system_clock.last_timer_count = system_clock.timer_const;

    splx(s);

    system_clock.tsc_per_tick = tsc_calibrate();
}

/*
 *  Clock functions
 */
tvalspec_t
clock_get_counter(
    clock_type_t 	which_clock
)
{
    tvalspec_t		result;
    int			s = splclock();

    // one spl section, so a tick cannot slip an adjtime step in between
    result = system_time_stamp();

    switch (which_clock) {

    case System:
	break;

    case Calendar:
    	ADD_TVALSPEC(&result, &time_of_boot);
	// a reload the tick has not counted yet lacks its adjtime step
	if (CMP_TVALSPEC(&result, &last_calendar) < 0)
	    result = last_calendar;
	else
	    last_calendar = result;
	break;

    default:
	result = TVALSPEC_ZERO;
	break;
    }
    splx(s);
    
    return (result);
}

void
clock_set_counter(
    clock_type_t 	which_clock,
    tvalspec_t 		value
)
{
    tvalspec_t		counter;
    int			s = splclock();

    counter = system_time_stamp();

    switch (which_clock) {

    case Calendar: {
	time_of_boot = value;
	SUB_TVALSPEC(&time_of_boot, &counter);
	last_calendar = value;
	splx(s);

	writetodc(&value.tv_sec);
	break;
    }

    default:
    	/* Can only set the calendar */
	splx(s);
	break;
    }
}

void
clock_adjust_counter(
    clock_type_t	which_clock,
    clock_res_t		nsec
)
{
    switch (which_clock) {

    case Calendar: {
	int		s = splclock();

	ADD_TVALSPEC_NSEC(&time_of_boot, nsec);
	splx(s);
	break;
    }

    default:
	/* Can only adjust the calendar */
	break;
    }
}

mapped_tvalspec_t *
clock_map_counter(
    clock_type_t	which_clock
)
{
    mapped_tvalspec_t	*mapped_clock;

    switch (which_clock) {
    
    case System:
    	if (!(mapped_clock = system_clock.mapped_counter)) {
	    int		s;

	    if (kmem_alloc_wired(kernel_map,
			(vm_offset_t *)&mapped_clock,
				PAGE_SIZE) != KERN_SUCCESS) {
		mapped_clock = 0;
		break;
	    }
	    s = splclock();
	    system_clock.mapped_counter = mapped_clock;
	    splx(s);
	}
	break;
    
    default:
    	mapped_clock = 0;
	break;
    }
    
    return (mapped_clock);
}

void
timer_set_expire_func(
    timer_type_t	which_timer,
    timer_func_t	expire_func
)
{
    switch (which_timer) {

    case SystemWide:
	if (!expire_func || !system_timer.expire_func) {
	    int		s = splclock();

	    system_timer.expire_func = expire_func;
	    system_timer.is_set = FALSE;
	    splx(s);
	}
	break;

    default:
    	break;
    }
}

void						
timer_set_deadline(
    timer_type_t	which_timer,
    tvalspec_t		deadline
)
{
    switch (which_timer) {

    case SystemWide:
	if (system_timer.expire_func) {
	    int		s = splclock();
    
	    system_timer.expire_time = deadline;
	    system_timer.is_set = TRUE;
	    splx(s);
	}
	break;

    default:
	break;
    }
}

/*
 * Get current clock value plus fraction of a tick.
 */
static tvalspec_t
system_time_stamp(void)
{
    unsigned int	current_timer_count, last_timer_count;
    unsigned long long	reload;
    clock_res_t		fraction;
    tvalspec_t		result;
    int			n, s = splclock();

    // take a snapshot of the whole counter state
    result = system_clock.counter;
    last_timer_count = system_clock.last_timer_count;
    n = tick_reloads(&current_timer_count, &reload);
    // once a wrap is seen, store 0 (never read in NDIV mode) so that
    // every later read counts the tick until the interrupt runs
    if (current_timer_count > last_timer_count)
	system_clock.last_timer_count = 0;
    else
	system_clock.last_timer_count = current_timer_count;

    // count reloads the tick has not; without the TSC, see one wrap
    if (n < 0)
	n = (current_timer_count > last_timer_count);
    while (n-- > 0)
	ADD_TVALSPEC_NSEC(&result, NSEC_PER_TICK);

    // convert fraction to ns; the source's count per tick spans one tick
    fraction = (system_clock.timer_const - current_timer_count);
    fraction = ((unsigned long long)fraction * NSEC_PER_TICK) /
    		system_clock.timer_const;

    ADD_TVALSPEC_NSEC(&result, fraction);

    // a second reload before the tick runs restarts the fraction; hold still
    if (CMP_TVALSPEC(&result, &system_clock.last_stamp) < 0)
	result = system_clock.last_stamp;
    else
	system_clock.last_stamp = result;
    splx(s);

    return (result);
}

unsigned int
event_get(void)
{
    return (system_time_stamp().tv_nsec);
}
