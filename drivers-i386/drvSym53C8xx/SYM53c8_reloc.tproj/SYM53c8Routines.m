/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Routines.m - Hardware routines for Symbios 53C8xx driver.
 *
 * HISTORY
 *
 * Oct 1998	Created.
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#import "SYM53c8Types.h"
#import "SYM53c8Inline.h"

/*
 * Reset the chip
 */
BOOL sym_reset_chip(IOEISAPortAddress portBase)
{
	int i;

	/* Software reset */
	sym_soft_reset(portBase);

	/* Wait for chip to become ready */
	if (!sym_wait_idle(portBase, 1000)) {
		return FALSE;
	}

	return TRUE;
}

/*
 * Initialize the chip
 */
BOOL sym_init_chip(IOEISAPortAddress portBase, struct sym_config *config)
{
	unsigned char scid;

	/* Reset first */
	if (!sym_reset_chip(portBase)) {
		return FALSE;
	}

	/* Set SCSI ID */
	scid = (1 << config->scsi_id);
	sym_write_reg(portBase, SYM_SCID_OFF, scid);

	/* Enable parity checking */
	sym_write_reg(portBase, SYM_SCNTL0_OFF, 0x08);

	/* Set selection timeout */
	sym_write_reg(portBase, SYM_STIME0_OFF, 0x0C);

	/* Enable SCSI interrupts */
	sym_write_reg(portBase, SYM_SIEN0_OFF,
		SYM_SIST0_MA | SYM_SIST0_CMP | SYM_SIST0_STO |
		SYM_SIST0_SEL | SYM_SIST0_UDC | SYM_SIST0_RST |
		SYM_SIST0_PAR);
	sym_write_reg(portBase, SYM_SIEN1_OFF, SYM_SIST1_STO);

	/* Enable DMA interrupts */
	sym_write_reg(portBase, SYM_DIEN_OFF,
		SYM_DSTAT_ABRT | SYM_DSTAT_SSI | SYM_DSTAT_SIR |
		SYM_DSTAT_IID | SYM_DSTAT_BF | SYM_DSTAT_MDPE);

	/* Set DMA mode */
	sym_write_reg(portBase, SYM_DMODE_OFF, 0x00);

	/* Clear any pending interrupts */
	sym_clear_intr(portBase);

	return TRUE;
}
