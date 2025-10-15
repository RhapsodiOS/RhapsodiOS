/*
 * Copyright (c) 1992-1998 NeXT Software, Inc.
 *
 * AIC6X60Routines.c - low-level I/O routines for Adaptec 6x60 driver.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created from Adaptec 1542B driver.
 */

#import "AIC6X60Types.h"
#import "AIC6X60Inline.h"
#import "AIC6X60Thread.h"
#import "AIC6X60ControllerPrivate.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>


void aic_start_scsi(
	unsigned short 	base
)
{
	aic_stat_reg_t	stat;

	do {
		stat = aic_get_stat(base);
	} while (stat.dataout_full);

	aic_put_cmd(base, AIC_CMD_START_SCSI);
}


boolean_t aic_probe_cmd(
	unsigned short	base,
	unsigned char	cmd,
	unsigned char	*args,
	int		arglen,
	unsigned char	*reply,
	int		replylen,
	boolean_t	polled
)
{
	aic_stat_reg_t	stat;
	aic_intr_reg_t	intr;
	boolean_t	success = FALSE;
	int		fail_count = 100000;

	do {
		stat = aic_get_stat(base);
	} while (stat.dataout_full && fail_count--);
	if (fail_count <= 0)
		return FALSE;

	aic_put_cmd(base, cmd);

	while (arglen-- > 0) {
		fail_count = 100000;
		do {
			intr = aic_get_intr(base);
			stat = aic_get_stat(base);
			if (intr.cmd_done && stat.cmd_err)
				goto out;
		} while (stat.dataout_full && fail_count--);
		if (fail_count <= 0)
			return FALSE;

		aic_put_cmd(base, *args++);
	}

	while (replylen-- > 0) {
		fail_count = 100000;
		do {
			intr = aic_get_intr(base);
			stat = aic_get_stat(base);
			if (intr.cmd_done && stat.cmd_err)
				goto out;
		} while (!stat.datain_full && fail_count--);
		if (fail_count <= 0)
			return FALSE;

		*reply++ = aic_get_cmd(base);
	}
	success = TRUE;

	fail_count = 100000;
	if (polled) do {
		intr = aic_get_intr(base);
	} while (!intr.cmd_done && fail_count--);
	if (fail_count <= 0)
		success = FALSE;

out:
	if (polled)
		aic_clr_intr(base);

	return (success);
}

boolean_t aic_cmd(
	unsigned short	base,
	unsigned char	cmd,
	unsigned char	*args,
	int		arglen,
	unsigned char	*reply,
	int		replylen,
	boolean_t	polled
)
{
	aic_stat_reg_t	stat;
	aic_intr_reg_t	intr;
	boolean_t		success = FALSE;

	do {
		stat = aic_get_stat(base);
	} while (stat.dataout_full);

	aic_put_cmd(base, cmd);

	while (arglen-- > 0) {
		do {
			intr = aic_get_intr(base);
			stat = aic_get_stat(base);
			if (intr.cmd_done && stat.cmd_err)
				goto out;
		} while (stat.dataout_full);

		aic_put_cmd(base, *args++);
	}

	while (replylen-- > 0) {
		do {
			intr = aic_get_intr(base);
			stat = aic_get_stat(base);
			if (intr.cmd_done && stat.cmd_err)
				goto out;
		} while (!stat.datain_full);

		*reply++ = aic_get_cmd(base);
	}
	success = TRUE;

	if (polled) do {
		intr = aic_get_intr(base);
	} while (!intr.cmd_done);

out:
	if (polled)
		aic_clr_intr(base);

	return (success);
}


void aic_reset_board(
	unsigned short 	base,
	unsigned char 	aic_board_id
)
{

	aic_ctrl_reg_t	ctrl = { 0 };
	aic_stat_reg_t	stat;

	ctrl.sw_rst = 1;

	aic_put_ctrl(base, ctrl);

	do {
		stat = aic_get_stat(base);
	} while (!stat.idle || !stat.mb_init_needed);

	aic_clr_intr(base);
}

boolean_t aic_setup_mb_area(
	unsigned short 		base,
	struct aic_mb_area 	*aicMbArea,
	struct ccb 		*aicCcb
)
{
	aic_cmd_init_t	init;
	int			i;
	unsigned		*mbPhysAddr;
	IOReturn		rtn;
	aic_mb_t		*mbOutVirt;
	aic_mb_t		*mbInVirt;
	struct ccb		*ccbPhys;
	struct ccb		*ccbVirt;

	ddm_init("AIC6X60Controller aic_setup_mb_area\n", 1,2,3,4,5);

	rtn = IOPhysicalFromVirtual(IOVmTaskSelf(),
		(vm_address_t)aicMbArea,
		(unsigned *)&mbPhysAddr);
	if(rtn) {
		IOLog("AIC6X60Controller: Can't get physical address of "
			"aicMbArea (%s)\n", [IODevice stringFromReturn:rtn]);
		return FALSE;
	}
	aic_unlock_mb(base);

	init.mb_cnt = AIC_MB_CNT;
	aic_put_24((vm_offset_t)mbPhysAddr, init.mb_area_addr);

	if (!aic_cmd(base,
	    AIC_CMD_INIT, (unsigned char *)&init, sizeof (init),
	    0, 0, TRUE)) {
		IOLog("aic at %x: mb_init failed\n", base);
		return (FALSE);
	}

	/*
	 * Setup CCBs and mailboxes. The CCB pointers in the mb_out mailboxes
	 * have to be physical addresses; the mb_out pointer in the ccb is a
	 * virtual address.
	 */
	mbOutVirt = &aicMbArea->mb_out[0];
	mbInVirt = &aicMbArea->mb_in[0];
	ccbVirt = aicCcb;

	for (i = 0; i < AIC_MB_CNT; i++) {

		mbOutVirt->mb_stat = AIC_MB_OUT_FREE;
		mbInVirt->mb_stat  = AIC_MB_IN_FREE;
		ccbVirt->mb_out    = mbOutVirt;

		rtn = IOPhysicalFromVirtual(IOVmTaskSelf(),
		    (vm_address_t)ccbVirt,
		    (unsigned *)&ccbPhys);
		if(rtn) {
		    IOLog("AIC6X60Controller: Can't get physical address of "
		    "ccb (%s)\n", [IODevice stringFromReturn:rtn]);
	 	   return FALSE;
		}
		ddm_init("ccbPhys[%d] = 0x%x\n", i, ccbPhys, 3,4,5);

		aic_put_24((vm_offset_t) ccbPhys, mbOutVirt->ccb_addr);

		mbOutVirt++;
		mbInVirt++;
		ccbVirt++;
	}

	return (TRUE);
}

void aic_unlock_mb(
	unsigned short 	base
)
{
	aic_mb_lock_t	lock;

	/*
	 * Unlock the mailbox interface in case extended
	 * BIOS translation was used.
	 */
	if(!aic_probe_cmd(base, AIC_CMD_GET_BIOS_INFO,
	    0, 0, (unsigned char*)&lock, sizeof(lock), TRUE)) {
	    	return;
	}

	lock.mb_status = 0;
	aic_probe_cmd(base, AIC_CMD_SET_MB_ENABLE,
		(unsigned char *)&lock, sizeof(lock), 0, 0, TRUE);
}

