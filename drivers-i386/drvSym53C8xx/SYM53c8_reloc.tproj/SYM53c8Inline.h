/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Inline.h - Inline routines for Symbios Logic 53C8xx driver.
 *
 * HISTORY
 *
 * Oct 1998	Created.
 */

#import <driverkit/i386/ioPorts.h>
#import "SYM53c8Types.h"

/*
 * Register access routines.
 */
static __inline__ unsigned char
sym_read_reg(IOEISAPortAddress portBase, unsigned int offset)
{
	return inb(portBase + offset);
}

static __inline__ void
sym_write_reg(IOEISAPortAddress portBase, unsigned int offset, unsigned char value)
{
	outb(portBase + offset, value);
}

static __inline__ unsigned int
sym_read_reg32(IOEISAPortAddress portBase, unsigned int offset)
{
	return inl(portBase + offset);
}

static __inline__ void
sym_write_reg32(IOEISAPortAddress portBase, unsigned int offset, unsigned int value)
{
	outl(portBase + offset, value);
}

/*
 * ISTAT register access
 */
static __inline__ unsigned char
sym_get_istat(IOEISAPortAddress portBase)
{
	return sym_read_reg(portBase, SYM_ISTAT_OFF);
}

static __inline__ void
sym_put_istat(IOEISAPortAddress portBase, unsigned char value)
{
	sym_write_reg(portBase, SYM_ISTAT_OFF, value);
}

/*
 * DSTAT register access
 */
static __inline__ unsigned char
sym_get_dstat(IOEISAPortAddress portBase)
{
	return sym_read_reg(portBase, SYM_DSTAT_OFF);
}

/*
 * SIST0/1 register access
 */
static __inline__ unsigned char
sym_get_sist0(IOEISAPortAddress portBase)
{
	return sym_read_reg(portBase, SYM_SIST0_OFF);
}

static __inline__ unsigned char
sym_get_sist1(IOEISAPortAddress portBase)
{
	return sym_read_reg(portBase, SYM_SIST1_OFF);
}

/*
 * DSP (SCRIPTS Pointer) access
 */
static __inline__ unsigned int
sym_get_dsp(IOEISAPortAddress portBase)
{
	return sym_read_reg32(portBase, SYM_DSP_OFF);
}

static __inline__ void
sym_put_dsp(IOEISAPortAddress portBase, unsigned int value)
{
	sym_write_reg32(portBase, SYM_DSP_OFF, value);
}

/*
 * DSA (Data Structure Address) access
 */
static __inline__ unsigned int
sym_get_dsa(IOEISAPortAddress portBase)
{
	return sym_read_reg32(portBase, SYM_DSA_OFF);
}

static __inline__ void
sym_put_dsa(IOEISAPortAddress portBase, unsigned int value)
{
	sym_write_reg32(portBase, SYM_DSA_OFF, value);
}

/*
 * Software reset
 */
static __inline__ void
sym_soft_reset(IOEISAPortAddress portBase)
{
	sym_put_istat(portBase, SYM_ISTAT_SRST);
	IODelay(100);
	sym_put_istat(portBase, 0);
	IODelay(1000);
}

/*
 * Clear interrupts
 */
static __inline__ void
sym_clear_intr(IOEISAPortAddress portBase)
{
	volatile unsigned char dstat, sist0, sist1;

	/* Reading these registers clears the interrupts */
	dstat = sym_get_dstat(portBase);
	sist0 = sym_get_sist0(portBase);
	sist1 = sym_get_sist1(portBase);
}

/*
 * Wait for chip to be idle
 */
static __inline__ BOOL
sym_wait_idle(IOEISAPortAddress portBase, int timeout_ms)
{
	unsigned char istat;
	int i;

	for (i = 0; i < timeout_ms * 100; i++) {
		istat = sym_get_istat(portBase);
		if (!(istat & (SYM_ISTAT_DIP | SYM_ISTAT_SIP)))
			return TRUE;
		IODelay(10);
	}
	return FALSE;
}

/*
 * Start SCRIPTS execution
 */
static __inline__ void
sym_start_scripts(IOEISAPortAddress portBase, unsigned int addr)
{
	sym_put_dsp(portBase, addr);
}

