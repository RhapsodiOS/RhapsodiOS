/*
 * Copyright (c) 1992 NeXT Computer, Inc.
 *
 * Interrupt handling internal definitions.
 *
 * HISTORY
 *
 * 10 July 1993 ? at NeXT
 *	Removed 'arg' from interrupt support.
 * 5 July 1993 ? at NeXT
 *	Removed software interrupt support.
 * 22 August 1992 ? at NeXT
 *	Added software interrupts.
 * 1 June 1992 ? at NeXT
 *	Created.
 */

#import <pexpert/pexpert_i386.h>

/*
 * The irq space is the platform expert's: 64 irqs on vectors 0x40-0x7F,
 * of which the 8259s serve the first 16.  The controller behind them is
 * chosen at run time (intr_set_controller).
 */
typedef struct {
    pexpert_irq_mask_t	mask;
} intr_irq_mask_t;

#define INTR_VECT_OFF		PEXPERT_VECTOR_BASE	// vector that IRQ0 corresponds to
#define INTR_NIRQ		PEXPERT_NIRQ		// number of IRQs available
#define INTR_SLAVE_IRQ		2	// IRQ of slave
#define INTR_MASK_IRQ(x)	((pexpert_irq_mask_t) 1 << (x))
#define INTR_MASK_SLAVE		INTR_MASK_IRQ(INTR_SLAVE_IRQ)
#define INTR_MASK_ALL		(~(pexpert_irq_mask_t) 0)
#define INTR_MASK_NONE		((pexpert_irq_mask_t) 0)

typedef struct {
    unsigned int	which;
    void		(*routine)();
    int			ipl;
} intr_dispatch_t;
