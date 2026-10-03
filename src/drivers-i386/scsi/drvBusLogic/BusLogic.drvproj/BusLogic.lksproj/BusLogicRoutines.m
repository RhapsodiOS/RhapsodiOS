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
#import <string.h>
#import "BusLogicTypes.h"
#import "BusLogicInline.h"

#define BL_TIMEOUT_MS	1000

/*
 * Tell the board to go look at the outgoing mailboxes. The board must not
 * be busy taking command parameters when the command byte is written.
 */
void blc_start_scsi(IOEISAPortAddress portBase)
{
	bl_stat_reg_t stat;

	do {
		stat = bl_get_stat(portBase);
	} while (stat.cmd_param_busy);

	bl_put_cmd(portBase, BL_CMD_START_SCSI);
}

/*
 * Reset the BusLogic board.
 */
BOOL blc_reset_board(IOEISAPortAddress portBase)
{
	unsigned char stat;

	/* Issue hard reset and allow the adapter to restart. */
	outb(portBase + BL_CTRL_REG_OFF, 0x80);
	IOSleep(1000);

	do {
		IOSleep(10);
		stat = inb(portBase + BL_STAT_REG_OFF);
	} while ((stat & 0x30) != 0x30);

	/* Clear the reset interrupt before issuing adapter commands. */
	outb(portBase + BL_CTRL_REG_OFF, 0x20);

	return TRUE;
}

/*
 * Send command to board with optional data in/out.
 */
BOOL blc_probe_cmd(IOEISAPortAddress portBase, unsigned char cmd,
		  unsigned char *dataOut, int dataOutLen,
		  unsigned char *dataIn, int dataInLen,
		  BOOL expectResponse)
{
	bl_stat_reg_t stat;
	bl_intr_reg_t intr;
	int i, j;

	/* Wait for the command parameter register to become ready. */
	for (i = 0; i < BL_TIMEOUT_MS * 100; i++) {
		stat = bl_get_stat(portBase);
		if (!stat.cmd_param_busy)
			break;
	}
	if (stat.cmd_param_busy)
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

			dataIn[i] = inb(portBase + BL_CMD_REG_OFF);
		}
	}

	if (expectResponse) {
		for (i = 0; i < BL_TIMEOUT_MS * 100; i++) {
			intr = bl_get_intr(portBase);
			if (intr.cmd_complete)
				break;
		}
		if (!intr.cmd_complete)
			return FALSE;

		stat = bl_get_stat(portBase);
		if (stat.cmd_invalid)
			return FALSE;
	}

	return TRUE;
}

/*
 * Release the board's mailbox lock.
 *
 * The two-byte lock structure is read back with board command 0x28 and, if
 * the board accepts that command, written out again with command 0x29 and a
 * cleared status byte. BusLogicTypes.h spells those two opcodes
 * BL_CMD_SET_PREEMPT_TIME and BL_CMD_SET_TIMEOFF; those names do not
 * describe this use, but they are the opcodes involved. A board which
 * rejects the read simply has no lock to release.
 */
void blc_unlock_mb(IOEISAPortAddress portBase)
{
	bl_mb_lock_t mbLock;

	if (!blc_probe_cmd(portBase, BL_CMD_SET_PREEMPT_TIME, NULL, 0,
			  (unsigned char *)&mbLock, sizeof(mbLock), TRUE))
		return;

	mbLock.mb_status = 0;
	(void)blc_probe_cmd(portBase, BL_CMD_SET_TIMEOFF,
			   (unsigned char *)&mbLock, sizeof(mbLock),
			   NULL, 0, TRUE);
}

/*
 * Setup mailbox area.
 */
BOOL blc_setup_mb_area(IOEISAPortAddress portBase,
		      struct bl_mb_area *mbArea,
		      struct ccb *ccbArray,
		      struct ccb **freeList)
{
	bl_cmd_init_t initCmd;
	vm_offset_t physAddr;
	struct ccb *ccb;
	int i;

	/* Get physical address of mailbox area */
	if (IOPhysicalFromVirtual(IOVmTaskSelf(),
				  (unsigned)mbArea,
				  &physAddr)) {
		IOLog("BusLogic: Can't get physical address of mailbox area\n");
		return FALSE;
	}

	/* Drop any mailbox lock left over from a previous owner */
	blc_unlock_mb(portBase);

	/* Initialize the adapter's extended mailboxes. */
	initCmd.mb_cnt = BL_MB_CNT;
	bl_put_32(physAddr, initCmd.mb_area_addr);

	if (!blc_probe_cmd(portBase, BL_CMD_INIT_EXT_MBOX,
			  (unsigned char *)&initCmd, sizeof(initCmd),
			  NULL, 0, TRUE)) {
		IOLog("BusLogic: Extended mailbox init failed\n");
		return FALSE;
	}

	/* Read the firmware version and enable round-robin mailbox scanning. */
	{
		bl_inquiry_t inquiry;
		unsigned char enableRoundRobin = 1;

		if (!blc_probe_cmd(portBase, BL_CMD_INQUIRY, NULL, 0,
				  (unsigned char *)&inquiry, sizeof(inquiry), TRUE)) {
			IOLog("BusLogic: Inquiry command failed\n");
			return FALSE;
		}
		if (inquiry.firmware_version[0] > 0x33 ||
		    (inquiry.firmware_version[0] == 0x33 &&
		     inquiry.firmware_version[1] > 0x32)) {
			if (!blc_probe_cmd(portBase, BL_CMD_ROUND_ROBIN,
					  &enableRoundRobin, 1, NULL, 0, TRUE)) {
				IOLog("BusLogic: Round-robin command failed\n");
				return FALSE;
			}
		}
	}

	bzero(ccbArray, sizeof(struct ccb) * BL_QUEUE_SIZE);
	bzero(mbArea->mb_out, sizeof(mbArea->mb_out) +
	      sizeof(mbArea->mb_in));
	mbArea->next_out = mbArea->out_start = mbArea->mb_out;
	mbArea->out_end = mbArea->mb_out + BL_MB_CNT - 1;
	mbArea->next_in = mbArea->in_start = mbArea->mb_in;
	mbArea->in_end = mbArea->mb_in + BL_MB_CNT - 1;

	/* Cache each CCB's physical address and chain the free CCBs. */
	*freeList = NULL;
	for (i = 0, ccb = ccbArray; i < BL_QUEUE_SIZE; i++, ccb++) {
		ccb->in_use = FALSE;
		if (IOPhysicalFromVirtual(IOVmTaskSelf(),
					  (unsigned)ccb,
					  &physAddr)) {
			IOLog("BusLogic: Can't get physical address of CCB\n");
			return FALSE;
		}
		ccb->physical_addr = physAddr;
		ccb->free_next = *freeList;
		*freeList = ccb;
	}

	return TRUE;
}

