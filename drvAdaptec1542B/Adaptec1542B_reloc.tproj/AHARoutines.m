/*
 * Copyright (c) 1992-1996 NeXT Software, Inc.
 *
 * AHARoutines.c - low-level I/O routines for Adaptec 1542 driver. 
 *
 * HISTORY
 *
 * 13 Apr 1993	Doug Mitchell at NeXT
 *	Split off from AHAController.m.
 */

#import "AHATypes.h"
#import "AHAInline.h"
#import "AHAThread.h"
#import "AHAControllerPrivate.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>


void aha_start_scsi(
	unsigned short 	base
)
{
	aha_stat_reg_t	stat;

	do {
		stat = aha_get_stat(base);
	} while (stat.dataout_full);

	aha_put_cmd(base, AHA_CMD_START_SCSI);
}


boolean_t aha_probe_cmd(
	unsigned short	base,
	unsigned char	cmd,
	unsigned char	*args,
	int		arglen,
	unsigned char	*reply,
	int		replylen,
	boolean_t	polled
)
{
	aha_stat_reg_t	stat;
	aha_intr_reg_t	intr;
	boolean_t	success = FALSE;
	int		fail_count = 100000;

	do {
		stat = aha_get_stat(base);
	} while (stat.dataout_full && fail_count--);
	if (fail_count <= 0) 
		return FALSE;

	aha_put_cmd(base, cmd);

	while (arglen-- > 0) {
		fail_count = 100000;
		do {
			intr = aha_get_intr(base);
			stat = aha_get_stat(base);
			if (intr.cmd_done && stat.cmd_err)
				goto out;
		} while (stat.dataout_full && fail_count--);
		if (fail_count <= 0) 
			return FALSE;

		aha_put_cmd(base, *args++);
	}

	while (replylen-- > 0) {
		fail_count = 100000;
		do {
			intr = aha_get_intr(base);
			stat = aha_get_stat(base);
			if (intr.cmd_done && stat.cmd_err)
				goto out;
		} while (!stat.datain_full && fail_count--);
		if (fail_count <= 0)
			return FALSE;

		*reply++ = aha_get_cmd(base);
	}
	success = TRUE;

	fail_count = 100000;
	if (polled) do {
		intr = aha_get_intr(base);
	} while (!intr.cmd_done && fail_count--);
	if (fail_count <= 0) 
		success = FALSE;

out:
	if (polled)
		aha_clr_intr(base);

	return (success);
}

boolean_t aha_cmd(
	unsigned short	base,
	unsigned char	cmd,
	unsigned char	*args,
	int		arglen,
	unsigned char	*reply,
	int		replylen,
	boolean_t	polled
)
{
	aha_stat_reg_t	stat;
	aha_intr_reg_t	intr;
	boolean_t		success = FALSE;
    
	do {
		stat = aha_get_stat(base);
	} while (stat.dataout_full);

	aha_put_cmd(base, cmd);

	while (arglen-- > 0) {
		do {
			intr = aha_get_intr(base);
			stat = aha_get_stat(base);
			if (intr.cmd_done && stat.cmd_err) 
				goto out;
		} while (stat.dataout_full);
    
		aha_put_cmd(base, *args++);
	}

	while (replylen-- > 0) {
		do {
			intr = aha_get_intr(base);
			stat = aha_get_stat(base);
			if (intr.cmd_done && stat.cmd_err)
				goto out;
		} while (!stat.datain_full);
	
		*reply++ = aha_get_cmd(base);
	}
	success = TRUE;
    
	if (polled) do {
		intr = aha_get_intr(base);
	} while (!intr.cmd_done);

out:
	if (polled)
		aha_clr_intr(base);
    
	return (success);
}


void aha_reset_board(
	unsigned short 	base, 
	unsigned char 	aha_board_id
) 
{

	aha_ctrl_reg_t	ctrl = { 0 };
	aha_stat_reg_t	stat;

	ctrl.sw_rst = 1;

	aha_put_ctrl(base, ctrl);

	/* Avoid a 174x standard mode firmware bug */
	if (aha_board_id == AHA_174xA) {
		do {
			stat = aha_get_stat(base);
		} while (!stat.idle);
		IOSleep(500);
	}
	else {
		do {
			stat = aha_get_stat(base);
		} while (!stat.idle || !stat.mb_init_needed);
	}

	aha_clr_intr(base);
}

boolean_t aha_setup_mb_area(
	unsigned short 		base,
	struct aha_mb_area 	*ahaMbArea,
	struct ccb 		*ahaCcb
)
{
	aha_cmd_init_t	init;
	int			i;
	unsigned		*mbPhysAddr;
	IOReturn		rtn;
	aha_mb_t		*mbOutVirt;
	aha_mb_t		*mbInVirt;
	struct ccb		*ccbPhys;
	struct ccb		*ccbVirt;
 
	ddm_init("AHAController aha_setup_mb_area\n", 1,2,3,4,5);
   
	rtn = IOPhysicalFromVirtual(IOVmTaskSelf(),
		(vm_address_t)ahaMbArea,
		(unsigned *)&mbPhysAddr);
	if(rtn) {
		IOLog("AHAController: Can't get physical address of "
			"ahaMbArea (%s)\n", [IODevice stringFromReturn:rtn]);
		return FALSE;
	}
	aha_unlock_mb(base);

	init.mb_cnt = AHA_MB_CNT;
	aha_put_24((vm_offset_t)mbPhysAddr, init.mb_area_addr); 

	if (!aha_cmd(base,
	    AHA_CMD_INIT, (unsigned char *)&init, sizeof (init),
	    0, 0, TRUE)) {
		IOLog("aha at %x: mb_init failed\n", base);
		return (FALSE);
	}

	/*
	 * Setup CCBs and mailboxes. The CCB pointers in the mb_out mailboxes 
	 * have to be physical addresses; the mb_out pointer in the ccb is a 
	 * virtual address.
	 */
	mbOutVirt = &ahaMbArea->mb_out[0];
	mbInVirt = &ahaMbArea->mb_in[0];
	ccbVirt = ahaCcb;
    
	for (i = 0; i < AHA_MB_CNT; i++) {
	
		mbOutVirt->mb_stat = AHA_MB_OUT_FREE;
		mbInVirt->mb_stat  = AHA_MB_IN_FREE;
		ccbVirt->mb_out    = mbOutVirt;

		rtn = IOPhysicalFromVirtual(IOVmTaskSelf(),
		    (vm_address_t)ccbVirt,
		    (unsigned *)&ccbPhys);
		if(rtn) {
		    IOLog("AHAController: Can't get physical address of "
		    "ccb (%s)\n", [IODevice stringFromReturn:rtn]);
	 	   return FALSE;
		}
		ddm_init("ccbPhys[%d] = 0x%x\n", i, ccbPhys, 3,4,5);
		
		aha_put_24((vm_offset_t) ccbPhys, mbOutVirt->ccb_addr);
	
		mbOutVirt++;
		mbInVirt++;
		ccbVirt++;
	}
    
	return (TRUE);
}

void aha_unlock_mb(
	unsigned short 	base
)
{
	aha_mb_lock_t	lock;

	/*
	 * Unlock the mailbox interface in case extended
	 * BIOS translation was used.
	 */
	if(!aha_probe_cmd(base, AHA_CMD_GET_BIOS_INFO,
	    0, 0, (unsigned char*)&lock, sizeof(lock), TRUE)) {
	    	return;
	}

	lock.mb_status = 0;
	aha_probe_cmd(base, AHA_CMD_SET_MB_ENABLE,
		(unsigned char *)&lock, sizeof(lock), 0, 0, TRUE);
}

