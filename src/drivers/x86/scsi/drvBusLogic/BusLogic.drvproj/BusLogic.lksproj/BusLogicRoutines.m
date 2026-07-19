/*
 * Copyright (c) 1996 NeXT Software, Inc.
 *
 * BusLogicRoutines.m - Hardware access routines for BusLogic driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from Adaptec 1542 driver.
 */

#import <driverkit/i386/ioPorts.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/generalFuncs.h>
#import "BusLogicTypes.h"
#import "BusLogicInline.h"

#define BL_TIMEOUT_MS	1000

/*
 * Reset the BusLogic board.
 */
BOOL bl_reset_board(IOEISAPortAddress portBase, unsigned char boardId)
{
	bl_ctrl_reg_t ctrl = { 0 };
	bl_stat_reg_t stat;
	int i;

	/* Issue hard reset */
	ctrl.hard_rst = 1;
	bl_put_ctrl(portBase, ctrl);
	IODelay(100);

	/* Wait for board to initialize */
	for (i = 0; i < BL_TIMEOUT_MS * 10; i++) {
		stat = bl_get_stat(portBase);
		if (!stat.diag_active && !stat.init_required)
			break;
		IODelay(100);
	}

	if (stat.diag_fail) {
		IOLog("BusLogic: board diagnostic failed\n");
		return FALSE;
	}

	if (!bl_wait_idle(portBase, BL_TIMEOUT_MS))
		return FALSE;

	return TRUE;
}

/*
 * Send command to board with optional data in/out.
 */
BOOL bl_probe_cmd(IOEISAPortAddress portBase, unsigned char cmd,
		  unsigned char *dataOut, int dataOutLen,
		  unsigned char *dataIn, int dataInLen,
		  BOOL expectResponse)
{
	bl_stat_reg_t stat;
	int i, j;

	/* Wait for board to be ready */
	if (!bl_wait_idle(portBase, BL_TIMEOUT_MS))
		return FALSE;

	/* Send command */
	bl_put_cmd(portBase, cmd);

	/* Send parameters if any */
	for (i = 0; i < dataOutLen; i++) {
		/* Wait for board ready */
		for (j = 0; j < BL_TIMEOUT_MS * 100; j++) {
			stat = bl_get_stat(portBase);
			if (!stat.cmd_param_busy)
				break;
			IODelay(10);
		}
		if (stat.cmd_param_busy)
			return FALSE;

		outb(portBase + BL_CMD_REG_OFF, dataOut[i]);
	}

	/* Read response if expected */
	if (expectResponse) {
		for (i = 0; i < dataInLen; i++) {
			/* Wait for data available */
			for (j = 0; j < BL_TIMEOUT_MS * 100; j++) {
				stat = bl_get_stat(portBase);
				if (stat.datain_full)
					break;
				IODelay(10);
			}
			if (!stat.datain_full)
				return FALSE;

			dataIn[i] = inb(portBase + BL_STAT_REG_OFF);
		}
	}

	/* Wait for command complete */
	if (!bl_wait_idle(portBase, BL_TIMEOUT_MS))
		return FALSE;

	/* Check for command error */
	stat = bl_get_stat(portBase);
	if (stat.cmd_invalid)
		return FALSE;

	return TRUE;
}

/*
 * Setup mailbox area.
 */
BOOL bl_setup_mb_area(IOEISAPortAddress portBase,
		      struct bl_mb_area *mbArea,
		      struct ccb *ccbArray)
{
	bl_cmd_init_t initCmd;
	vm_offset_t physAddr;
	bl_mb_t *mb;
	struct ccb *ccb;
	int i;

	/* Get physical address of mailbox area */
	if (IOPhysicalFromVirtual(IOVmTaskSelf(),
				  (unsigned)mbArea,
				  &physAddr)) {
		IOLog("BusLogic: Can't get physical address of mailbox area\n");
		return FALSE;
	}

	/* Initialize mailbox structure */
	initCmd.mb_cnt = BL_MB_CNT;
	bl_put_24(physAddr, initCmd.mb_area_addr);

	/* Send mailbox init command */
	if (!bl_probe_cmd(portBase, BL_CMD_INIT_MBOX,
			  (unsigned char *)&initCmd, sizeof(initCmd),
			  NULL, 0, FALSE)) {
		IOLog("BusLogic: Mailbox init failed\n");
		return FALSE;
	}

	/* Clear all mailboxes */
	mb = mbArea->mb_out;
	for (i = 0; i < BL_MB_CNT; i++, mb++) {
		mb->mb_stat = BL_MB_OUT_FREE;
		bl_put_24(0, mb->ccb_addr);
	}

	mb = mbArea->mb_in;
	for (i = 0; i < BL_MB_CNT; i++, mb++) {
		mb->mb_stat = BL_MB_IN_FREE;
		bl_put_24(0, mb->ccb_addr);
	}

	/* Initialize CCB array and link to mailboxes */
	ccb = ccbArray;
	mb = mbArea->mb_out;
	for (i = 0; i < BL_QUEUE_SIZE; i++, ccb++, mb++) {
		ccb->in_use = FALSE;
		ccb->mb_out = mb;

		/* Get physical address of this CCB */
		if (IOPhysicalFromVirtual(IOVmTaskSelf(),
					  (unsigned)ccb,
					  &physAddr)) {
			IOLog("BusLogic: Can't get physical address of CCB\n");
			return FALSE;
		}

		bl_put_24(physAddr, mb->ccb_addr);
	}

	return TRUE;
}

