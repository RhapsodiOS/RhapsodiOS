/*
 * Copyright (c) 1996 NeXT Software, Inc.
 *
 * BusLogicInline.h - Inline routines for BusLogic driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from Adaptec 1542 driver.
 */

#import <driverkit/i386/ioPorts.h>
#import "BusLogicTypes.h"

/*
 * Convert 24-bit address to/from BusLogic format.
 */
static __inline__ void
bl_put_24(unsigned int addr, unsigned char *ptr)
{
	ptr[0] = addr;
	ptr[1] = addr >> 8;
	ptr[2] = addr >> 16;
}

static __inline__ unsigned int
bl_get_24(unsigned char *ptr)
{
	return (ptr[0] | (ptr[1] << 8) | (ptr[2] << 16));
}

/*
 * Register access routines.
 */
static __inline__ bl_ctrl_reg_t
bl_get_ctrl(IOEISAPortAddress portBase)
{
	bl_ctrl_reg_t ctrl;

	*(unsigned char *)&ctrl = inb(portBase + BL_CTRL_REG_OFF);
	return ctrl;
}

static __inline__ void
bl_put_ctrl(IOEISAPortAddress portBase, bl_ctrl_reg_t ctrl)
{
	outb(portBase + BL_CTRL_REG_OFF, *(unsigned char *)&ctrl);
}

static __inline__ bl_stat_reg_t
bl_get_stat(IOEISAPortAddress portBase)
{
	bl_stat_reg_t stat;

	*(unsigned char *)&stat = inb(portBase + BL_STAT_REG_OFF);
	return stat;
}

static __inline__ bl_intr_reg_t
bl_get_intr(IOEISAPortAddress portBase)
{
	bl_intr_reg_t intr;

	*(unsigned char *)&intr = inb(portBase + BL_INTR_REG_OFF);
	return intr;
}

static __inline__ void
bl_clr_intr(IOEISAPortAddress portBase)
{
	bl_ctrl_reg_t ctrl;

	ctrl = bl_get_ctrl(portBase);
	ctrl.intr_clr = 1;
	bl_put_ctrl(portBase, ctrl);
}

static __inline__ void
bl_put_cmd(IOEISAPortAddress portBase, bl_cmd_reg_t cmd)
{
	outb(portBase + BL_CMD_REG_OFF, cmd);
}

static __inline__ void
bl_start_scsi(IOEISAPortAddress portBase)
{
	bl_put_cmd(portBase, BL_CMD_START_SCSI);
}

/*
 * Wait for board to be idle.
 */
static __inline__ BOOL
bl_wait_idle(IOEISAPortAddress portBase, int timeout_ms)
{
	bl_stat_reg_t stat;
	int i;

	for (i = 0; i < timeout_ms * 100; i++) {
		stat = bl_get_stat(portBase);
		if (!stat.host_busy && !stat.diag_active)
			return TRUE;
		IODelay(10);
	}
	return FALSE;
}

