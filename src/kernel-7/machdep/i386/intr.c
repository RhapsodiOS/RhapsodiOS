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
 * Copyright (c) 1992,1993 NeXT Computer, Inc.
 *
 * Interrupt handling routines.
 *
 * HISTORY
 *
 * 26 Sep 2026
 *	The hardware moved behind an intr_controller_t so the platform
 *	expert can put the APICs in place of the 8259s: 64 irqs, the
 *	8259s serving the first 16 through the controller defined here.
 * 5 July 1993 ? at NeXT
 *	Removed software interrupt support.
 * 	Changed lower_ipl() to never raise masked_ipl.
 * 20 May 1993  Curtis Galloway at NeXT
 *	Added checking for phantom interrupts.
 * 26 August 1992 ? at NeXT
 *	Major rev for driverkit support.
 * 22 August 1992 ? at NeXT
 *	Added software interrupts.  Made all data structures static.
 * 20 Aug 1992	Joe Pasqua
 *	Added intr_enable_irq/disable_irq routines based on the enableMask.
 * 24 June 1992 ? at NeXT
 *	Rewritten to implement 'soft spls'.
 * 1 June 1992 ? at NeXT
 *	Created.
 */
 
#import <mach/mach_types.h>

#import <machdep/i386/intr_exported.h>
#import <machdep/i386/intr_internal.h>
#import <machdep/i386/intr_inline.h>
#import <machdep/i386/cpu_inline.h>

static intr_dispatch_t	dispatch_table[INTR_NIRQ];
static intr_irq_mask_t	ipl_mask[INTR_NIPL];
static intr_dispatch_t	*defer_table[INTR_NIPL];

static int		current_ipl, masked_ipl;
static intr_irq_mask_t	current_irq_mask, disabled_irq_mask;
static intr_irq_mask_t	current_elcr;

static const intr_controller_t	*controller;

#define I8259_NIRQ		16	// what the 8259 pair serves

/*
 * A specific EOI for one input of one PIC.
 */
static inline
intr_ocw2_t
specific_eoi(
    int			level
)
{
    return ((intr_ocw2_t) {
			level,		/* input on this PIC	*/
			0,		/* must be zero		*/
			TRUE,		/* EOI			*/
			TRUE,		/* specific		*/
			FALSE		/* no rotation		*/
		    });
}

/*
 * Acknowledge an interrupt.
 *
 * Specific rather than non-specific, and for a cascaded interrupt the
 * slave is acknowledged before the master's cascade input.  This is the
 * sequence Linux and NetBSD both use.
 *
 * Both details matter.  A non-specific EOI clears whichever in-service
 * bit currently has the highest priority, which is not necessarily the
 * interrupt being finished once interrupts nest.  Worse, the previous
 * code sent one to *both* PICs regardless of where the interrupt came
 * from, so finishing an interrupt on the master would also clear an
 * unrelated slave interrupt that was still in service.
 */
static inline
void
send_eoi(
    int			irq
)
{
    if (irq >= I8259_NIRQ / 2) {
	send_slave_eoi_command(specific_eoi(irq - I8259_NIRQ / 2));
	send_master_eoi_command(specific_eoi(INTR_SLAVE_IRQ));
    }
    else
	send_master_eoi_command(specific_eoi(irq));
}

static inline
void
set_elcr(
    intr_irq_mask_t		mask
)
{
    union {
	unsigned short		full;
	struct {
	    unsigned short
				half	:8,
					:8;
	} master;
	struct {
	    unsigned short
					:8,
				half	:8;
	} slave;
    } new_mask;

    new_mask.full = (unsigned short) mask.mask;
    
    if (mask.mask != current_elcr.mask) {
    	current_elcr = mask;

	set_master_elcr((intr_elcr_t) {
					    new_mask.master.half });
    
	set_slave_elcr((intr_elcr_t) {
					    new_mask.slave.half });
    }
}

/*
 * Set the interrupt masks of both PICs
 * according to the irq mask.  The
 * cascade input is never masked.
 */
static
void
i8259_set_mask(
    pexpert_irq_mask_t		mask
)
{
    union {
	unsigned short		full;
	struct {
	    unsigned short
				half	:8,
					:8;
	} master;
	struct {
	    unsigned short
					:8,
				half	:8;
	} slave;
    } new_mask;
    
    new_mask.full = (unsigned short) mask & ~(unsigned short) INTR_MASK_SLAVE;

    set_master_mask((intr_ocw1_t) {
					new_mask.master.half });

    set_slave_mask((intr_ocw1_t) {
					new_mask.slave.half });
}

/*
 * Set the irq mask on whichever
 * controller is in charge.
 */
static inline
void
set_irq_mask(
    intr_irq_mask_t		mask
)
{
    intr_irq_mask_t		new_mask;
    
    new_mask.mask = mask.mask | disabled_irq_mask.mask;

    if (new_mask.mask != current_irq_mask.mask) {
	current_irq_mask = new_mask;
	(*controller->set_mask)(new_mask.mask);
    }
}

/*
 * Set the irq mask according to
 * the ipl.
 */
static inline
int
set_masked_ipl(
    int		ipl
)
{
    int		old_ipl = masked_ipl;

    if (ipl != masked_ipl) {
	set_irq_mask(ipl_mask[ipl]);
	masked_ipl = ipl;
    }
    
    return (old_ipl);
}

/*
 * Set the 'soft' ipl.
 */
static inline
int
set_ipl(
    int		ipl
)
{
    int		old_ipl = current_ipl;
	
    current_ipl = ipl;
    
    return (old_ipl);
}

/*
 * Clear the interrupt flag, and
 * return the original state of
 * the flag.
 */
boolean_t
intr_disbl(
    void
)
{
    unsigned int	efl;

    efl = eflags();
	    
    cli();
	    
    return ((efl & EFL_IF) != 0);
}

/*
 * Set or clear the interrupt
 * flag, and return the original
 * state of the flag.
 */
boolean_t
intr_enbl(
    boolean_t	enable
)
{
    unsigned int	efl;

    efl = eflags();
	    
    if (enable) sti(); else cli();
	
    return ((efl & EFL_IF) != 0);
}

static inline
void
lower_masked_ipl(
    int			ipl
)
{
    if (ipl < masked_ipl)
    	(void) set_masked_ipl(ipl);
}

static
void
lower_ipl(
    int			ipl,
    int			old_ipl
)
{
    intr_dispatch_t	**d, *i;
    
    for (d = &defer_table[old_ipl]; d > &defer_table[ipl]; d--)
	if (i = *d) {
	    *d = 0;

	    (void) set_ipl(i->ipl);
	    
	    sti();
		(*i->routine)(i->which, 0, ipl); 
	    cli();
	}
	    
    (void) set_ipl(ipl);
    
    lower_masked_ipl(ipl);
}

/*
 * External 'well known' routines.
 */

inline
int
splx(
    int		ipl
)
{
    int		old_ipl;

    cli();

    old_ipl = set_ipl(ipl);
    if (ipl < old_ipl)
	lower_ipl(ipl, old_ipl);

    sti();
    
    return (old_ipl);
}

#define	DEFINE_SPL(name, ipl)	\
int spl##name(			\
    void			\
)				\
{				\
    return (splx(ipl));		\
}

#define DEFINE_SPLNOP(name)	\
int spl##name(			\
    void			\
)				\
{				\
    return (current_ipl);	\
}

DEFINE_SPL(0,		INTR_IPL0)

DEFINE_SPL(1,		INTR_IPL1)
DEFINE_SPLNOP(tty)

DEFINE_SPL(2,		INTR_IPL2)

DEFINE_SPL(3,		INTR_IPL3)
DEFINE_SPLNOP(net)
DEFINE_SPLNOP(vm)
DEFINE_SPLNOP(imp)
DEFINE_SPLNOP(bio)
DEFINE_SPL(device,	INTR_IPL3)

DEFINE_SPL(4,		INTR_IPL4)

DEFINE_SPL(5,		INTR_IPL5)

DEFINE_SPL(6,		INTR_IPL6)
DEFINE_SPL(dma,		INTR_IPL6)
DEFINE_SPL(usclock,	INTR_IPL6)
DEFINE_SPL(sched,	INTR_IPL6)
DEFINE_SPL(clock,	INTR_IPL6)

DEFINE_SPL(7,		INTR_IPL7)
DEFINE_SPL(high,	INTR_IPL7)

int
spln(
    int		ipl
)
{
    return (splx(ipl));
}

int
ipltospl(
    int		ipl
)
{
    return (ipl);
}

/*
 * Return the current ipl.
 */
int
curipl(
    void
)
{
    return (current_ipl);
}

/*
 * Initialization templates.
 */

#define MASTER_ICW1	((intr_icw1_t) {				\
			    TRUE,		/* IC4 needed	*/	\
			    FALSE,		/* cascaded 	*/	\
			    0,			/* not used	*/	\
			    INTR_ICW1_EDGE_TRIG,			\
			    1			/* must be	*/	\
			})
#define MASTER_ICW2	((intr_icw2_t) {				\
			    INTR_VECT_OFF	/* index in IDT	*/	\
			})
#define MASTER_ICW3	((intr_icw3m_t) {				\
			    INTR_MASK_SLAVE	/* slave inputs */	\
			})
#define MASTER_ICW4	((intr_icw4_t) {				\
			    INTR_ICW4_8086_MODE,			\
			    FALSE,		/* no auto EOI */	\
			    INTR_ICW4_NONBUF,				\
			    FALSE		/* no SFN mode */	\
			})

#define SLAVE_ICW1	((intr_icw1_t) {				\
			    TRUE,		/* IC4 needed	*/	\
			    FALSE,		/* cascaded 	*/	\
			    0,			/* not used	*/	\
			    INTR_ICW1_EDGE_TRIG,			\
			    1			/* must be	*/	\
			})
#define SLAVE_ICW2	((intr_icw2_t) {				\
			    INTR_VECT_OFF + 8	/* index in IDT	*/	\
			})
#define SLAVE_ICW3	((intr_icw3s_t) {				\
			    INTR_SLAVE_IRQ	/* slave id	*/	\
			})
#define SLAVE_ICW4	((intr_icw4_t) {				\
			    INTR_ICW4_8086_MODE,			\
			    FALSE,		/* no auto EOI */	\
			    INTR_ICW4_NONBUF,				\
			    FALSE		/* no SFN mode */	\
			})

/*
 * Called early during system
 * initialization.  Sets up the
 * PICs, sets the ipl to IPLHI,
 * and masks all irqs.
 */
void
intr_initialize(
    void
)
{
    intr_irq_mask_t	*m;
    int			i;
    pexpert_irq_mask_t	mask;

    controller = &i8259_controller;

    cli();

    initialize_master(	MASTER_ICW1,
    			MASTER_ICW2,
			MASTER_ICW3,
			MASTER_ICW4);

    initialize_slave(	SLAVE_ICW1,
    			SLAVE_ICW2,
			SLAVE_ICW3,
			SLAVE_ICW4);

    mask = INTR_MASK_ALL;
    for (i = 0, m = ipl_mask; i++ < INTR_NIPL; m++)
	m->mask = mask;
	
    disabled_irq_mask.mask = INTR_MASK_NONE;

    set_masked_ipl(INTR_IPLHI);

    set_ipl(INTR_IPLHI);
    
    sti();
}

/*
 * Register an ISR for an irq at
 * the ipl.  Returns TRUE on success,
 * FALSE on failure.  Failure includes
 * trying to overwrite an existing ISR.
 */
boolean_t
intr_register_irq(
    int			irq,
    intr_handler_t	routine,
    unsigned int	which,
    int			ipl
)
{
    intr_irq_mask_t	*m;
    int			i;
    pexpert_irq_mask_t	mask;
    boolean_t		e;

    if (irq < 0 || irq >= INTR_NIRQ || !(*controller->irq_valid)(irq))
	return (FALSE);

    if (ipl < 0 || ipl >= INTR_NIPL)
	return (FALSE);

    if (dispatch_table[irq].routine)
	return (FALSE);

    e = intr_disbl();

    dispatch_table[irq].which	= which;
    dispatch_table[irq].routine	= routine;
    dispatch_table[irq].ipl	= ipl;

    mask = INTR_MASK_IRQ(irq);
    for (i = 0, m = ipl_mask; i < INTR_NIPL; i++, m++) {
	if (i < ipl)
	    m->mask &= ~mask;
	else
	    m->mask |= mask;
    }
    
    disabled_irq_mask.mask |= mask;

    set_irq_mask(ipl_mask[masked_ipl]);
    
    (void) intr_enbl(e);
    
    return (TRUE);
}

boolean_t
intr_unregister_irq(
    int			irq
)
{
    intr_irq_mask_t	*m;
    int			i;
    pexpert_irq_mask_t	mask;
    boolean_t		e;

    if (irq < 0 || irq >= INTR_NIRQ)
	return (FALSE);

    if (!dispatch_table[irq].routine)
	return (FALSE);

    e = intr_disbl();

    dispatch_table[irq].which	= 0;
    dispatch_table[irq].routine	= 0;
    dispatch_table[irq].ipl	= 0;

    mask = INTR_MASK_IRQ(irq);
    for (i = 0, m = ipl_mask; i < INTR_NIPL; i++, m++) {
	m->mask |= mask;
    }

    set_irq_mask(ipl_mask[masked_ipl]);
    
    (void) intr_enbl(e);
    
    (void) intr_change_mode(irq, FALSE);
    
    return (TRUE);
}

boolean_t
intr_enable_irq(
    int		irq
)
{
    boolean_t	e;

    if (irq < 0 || irq >= INTR_NIRQ || !(*controller->irq_valid)(irq))
	return (FALSE);

    e = intr_disbl();

    disabled_irq_mask.mask &= ~INTR_MASK_IRQ(irq);
    set_irq_mask(ipl_mask[masked_ipl]);

    (void) intr_enbl(e);
    
    return (TRUE);
}

boolean_t
intr_disable_irq(
    int		irq
)
{
    boolean_t	e;

    if (irq < 0 || irq >= INTR_NIRQ || !(*controller->irq_valid)(irq))
	return (FALSE);

    e = intr_disbl();

    disabled_irq_mask.mask |= INTR_MASK_IRQ(irq);
    set_irq_mask(ipl_mask[masked_ipl]);
 
    (void) intr_enbl(e);
    
    return (TRUE);
}

boolean_t
intr_change_ipl(
    int		irq,
    int		ipl
)
{
    intr_irq_mask_t	*m;
    int			i;
    pexpert_irq_mask_t	mask;
    boolean_t		e;

    if (irq < 0 || irq >= INTR_NIRQ)
	return (FALSE);

    if (ipl < 0 || ipl >= INTR_NIPL)
	return (FALSE);

    if (dispatch_table[irq].routine == 0)
	return (FALSE);

    e = intr_disbl();

    dispatch_table[irq].ipl	= ipl;

    mask = INTR_MASK_IRQ(irq);
    for (i = 0, m = ipl_mask; i < INTR_NIPL; i++, m++) {
	if (i < ipl)
	    m->mask &= ~mask;
	else
	    m->mask |= mask;
    }

    set_irq_mask(ipl_mask[masked_ipl]);
    
    (void) intr_enbl(e);
    
    return (TRUE);
}

static
int
i8259_set_trigger(
    int		irq,
    int		level_trig
)
{
    intr_irq_mask_t	reg;
#define _T_	TRUE
#define _F_	FALSE
    static boolean_t	valid_irq[I8259_NIRQ] = {
			    _F_, _F_, _F_, _T_, _T_, _T_, _T_, _T_,
			    _F_, _T_, _T_, _T_, _T_, _F_, _T_, _T_
			};
#undef _T_
#undef _F_
    
    if (!eisa_present())
    	return (FALSE);

    if (irq < 0 || irq >= I8259_NIRQ || !valid_irq[irq])
	return (FALSE);
	
    reg = current_elcr;
    
    if (level_trig)
    	reg.mask |= INTR_MASK_IRQ(irq);
    else
    	reg.mask &= ~INTR_MASK_IRQ(irq);
	
    set_elcr(reg);
    
    return (TRUE);
}

boolean_t
intr_change_mode(
    int		irq,
    boolean_t	level_trig
)
{
    boolean_t		e, result;

    if (irq < 0 || irq >= INTR_NIRQ)
	return (FALSE);
	
    e = intr_disbl();
    
    result = (*controller->set_trigger)(irq, level_trig) ? TRUE : FALSE;
    
    (void) intr_enbl(e);
    
    return (result);
}

/*
 * The 8259 pair as a controller.
 */

static
int
i8259_irq_valid(
    int		irq
)
{
    return (irq >= 0 && irq < I8259_NIRQ && irq != INTR_SLAVE_IRQ);
}

static
void
i8259_eoi(
    int		irq
)
{
    send_eoi(irq);
}

/*
 * Check for phantom interrupt.
 *
 * A spurious interrupt leaves no in-service bit set in the PIC that
 * reported it, which is how it is recognised here.  The master and
 * slave cases are not symmetric.
 *
 * A spurious IRQ 7 needs no acknowledgement: the master has nothing
 * in service.  A spurious IRQ 15 does, because the master already
 * acknowledged the cascade and set its IRQ 2 in-service bit before
 * the slave reported the interrupt as spurious.  Returning without
 * clearing that bit leaves the cascade permanently in service, and
 * the master then refuses every later slave interrupt (IRQ 8-15)
 * while continuing to deliver the higher-priority IRQ 0.
 */
static
int
i8259_is_spurious(
    int		irq
)
{
    if (irq == INTR_MASTER_PHANTOM_IRQ &&
		(get_master_isr() & INTR_PHANTOM_IRQ_MASK) == 0)
	return (TRUE);
    if (irq == INTR_SLAVE_PHANTOM_IRQ &&
		(get_slave_isr() & INTR_PHANTOM_IRQ_MASK) == 0) {
	send_master_eoi_command(specific_eoi(INTR_SLAVE_IRQ));
	return (TRUE);
    }
    return (FALSE);
}

static const intr_controller_t	i8259_controller = {
    "8259",
    i8259_irq_valid,
    i8259_set_mask,
    i8259_eoi,
    i8259_is_spurious,
    i8259_set_trigger
};

/*
 * Hand the irqs to another controller,
 * the platform expert's APICs.  The old
 * one is left with everything masked.
 */
void
intr_set_controller(
    const intr_controller_t	*new_controller
)
{
    boolean_t	e;

    e = intr_disbl();

    (*controller->set_mask)(INTR_MASK_ALL);
    controller = new_controller;
    (*controller->set_mask)(current_irq_mask.mask);

    (void) intr_enbl(e);
}

struct {
    unsigned int	intr;
    unsigned int	defer;
    unsigned int	phantom;
} intr_cnt;

/*
 * The system interrupt handler.
 */
void
intr_handler(
    void			*_state
)
{
    thread_saved_state_t	*state = (thread_saved_state_t *)_state;
    int				irq = state->trapno - INTR_VECT_OFF;
    intr_dispatch_t		*i;
    int				old_masked_ipl;

    intr_cnt.intr++;

    /*
     * Check for phantom interrupt.
     * The controller knows how to
     * recognise and acknowledge one.
     */
    if (irq < 0 || irq >= INTR_NIRQ || (*controller->is_spurious)(irq)) {
	 intr_cnt.phantom++;
	 return;
    }

    i = &dispatch_table[irq];

    /*
     * Mask this interrupt before
     * acknowledging so that level
     * triggered inputs work.
     */
    old_masked_ipl = set_masked_ipl(i->ipl);

    /*
     * Acknowledge it.
     */
    (*controller->eoi)(irq);

    /*
     * Leave this interrupt
     * disabled if it isn't
     * currently registered.
     * N.B.: This should never
     * happen.
     */
    if (i->routine == 0)	
	printf("intr: dropped IRQ %d\n", irq);
    else
    /*
     * If this interrupt isn't
     * disallowed via spl(),
     * handle it now.
     */
    if (current_ipl < i->ipl) {
	int	old_ipl		= set_ipl(i->ipl);
		
	sti(); (*i->routine)(i->which, state, old_ipl); cli();
	
	(void) set_ipl(old_ipl);
	(void) set_masked_ipl(old_masked_ipl);
    }
    /*
     * Otherwise, leave it masked
     * and defer it until later.
     */
    else {
	intr_cnt.defer++;
		
    	defer_table[i->ipl] = i;
    }
}
