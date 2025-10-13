/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Thread.m - I/O thread methods for Symbios 53C8xx driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from BusLogic driver.
 */

#import <sys/types.h>
#import <bsd/sys/param.h>
#import <kernserv/prototypes.h>
#import <driverkit/return.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/scsiTypes.h>
#import <bsd/dev/scsireg.h>
#import <machkit/NXLock.h>
#import <kernserv/ns_timer.h>
#import <mach/message.h>

#import "SYM53c8Controller.h"
#import "SYM53c8Types.h"
#import "SYM53c8Inline.h"
#import "SYM53c8Thread.h"

@implementation SYM53c8Controller(IOThread)

/*
 * Execute a SCSI request. Called from I/O thread.
 * Returns 0 on success, non-zero if no CCBs available.
 */
- (int)threadExecuteRequest : (SYMCommandBuf *)cmdBuf
{
	struct ccb	*ccb;
	int		rtn;

	ddm_thr("threadExecuteRequest: cmdBuf 0x%x\n", cmdBuf, 2,3,4,5);

	/*
	 * Allocate a CCB
	 */
	ccb = [self allocCcb:YES];
	if (ccb == NULL) {
		ddm_thr("threadExecuteRequest: no CCBs available\n", 1,2,3,4,5);
		return -1;
	}

	/*
	 * Fill in the CCB from the command buffer
	 */
	rtn = [self ccbFromCmd:cmdBuf ccb:ccb];
	if (rtn) {
		[self freeCcb:ccb];
		[cmdBuf->cmdLock lock];
		cmdBuf->result = SR_IOST_INVALID;
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
		return 0;
	}

	/*
	 * Either queue it or execute it now
	 */
	if (outstandingCount >= SYM_QUEUE_SIZE) {
		queue_enter(&pendingQ, ccb, struct ccb *, ccbQ);
	} else {
		queue_enter(&outstandingQ, ccb, struct ccb *, ccbQ);
		outstandingCount++;
		[self runPendingCommands];
	}

	return 0;
}

/*
 * Reset the SCSI bus. Called from I/O thread.
 */
- (void)threadResetBus : (SYMCommandBuf *)cmdBuf
{
	struct ccb	*ccb;

	ddm_thr("threadResetBus\n", 1,2,3,4,5);

	/* Reset the chip */
	sym_soft_reset(ioBase);
	IODelay(250000);	/* 250ms delay */

	/* Complete all outstanding commands */
	while (!queue_empty(&outstandingQ)) {
		ccb = (struct ccb *)queue_first(&outstandingQ);
		queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
		outstandingCount--;
		[self commandCompleted:ccb reason:CS_Reset];
	}

	/* Complete all pending commands */
	while (!queue_empty(&pendingQ)) {
		ccb = (struct ccb *)queue_first(&pendingQ);
		queue_remove(&pendingQ, ccb, struct ccb *, ccbQ);
		[self commandCompleted:ccb reason:CS_Reset];
	}

	if (cmdBuf) {
		[cmdBuf->cmdLock lock];
		cmdBuf->result = SR_IOST_GOOD;
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
	}
}

/*
 * Build a CCB from a command buffer
 */
- (int)ccbFromCmd : (SYMCommandBuf *)cmdBuf ccb:(struct ccb *)ccb
{
	IOSCSIRequest	*scsiReq = cmdBuf->scsiReq;
	unsigned int	xferLen = 0;
	int		i;

	/* Clear CCB */
	bzero(ccb, sizeof(*ccb));

	/* Fill in SCSI command */
	ccb->target = scsiReq->target;
	ccb->lun = scsiReq->lun;
	bcopy(&scsiReq->cdb, &ccb->cdb, sizeof(union cdb));
	ccb->cdb_len = scsiReq->cdbLength;

	/* Set up data transfer if needed */
	if (scsiReq->maxTransfer > 0 && cmdBuf->buffer != NULL) {
		xferLen = scsiReq->maxTransfer;
		ccb->data_len = xferLen;
		ccb->data_addr = (unsigned int)kvtophys((vm_offset_t)cmdBuf->buffer);
	}

	ccb->total_xfer_len = xferLen;
	ccb->cmdBuf = cmdBuf;
	IOGetTimestamp(&ccb->startTime);

	return 0;
}

/*
 * Execute pending commands if there is room in the outstanding queue
 */
- runPendingCommands
{
	struct ccb *ccb;

	while (!queue_empty(&pendingQ) && outstandingCount < SYM_QUEUE_SIZE) {
		ccb = (struct ccb *)queue_first(&pendingQ);
		queue_remove(&pendingQ, ccb, struct ccb *, ccbQ);
		queue_enter(&outstandingQ, ccb, struct ccb *, ccbQ);
		outstandingCount++;

		/* Start SCRIPTS to execute this command */
		sym_put_dsa(ioBase, (unsigned int)kvtophys((vm_offset_t)ccb));
		sym_start_scripts(ioBase, (unsigned int)scriptsPhys);
	}

	return self;
}

/*
 * Command completed
 */
- (void)commandCompleted : (struct ccb *)ccb reason : (completeStatus)reason
{
	SYMCommandBuf	*cmdBuf = ccb->cmdBuf;
	IOSCSIRequest	*scsiReq = cmdBuf->scsiReq;

	ddm_thr("commandCompleted: ccb 0x%x reason %d\n", ccb, reason, 3,4,5);

	/* Fill in completion status */
	switch (reason) {
	case CS_Complete:
		if (ccb->host_status == SYM_HOST_SUCCESS) {
			cmdBuf->result = SR_IOST_GOOD;
			scsiReq->driverStatus = SR_IOST_GOOD;
			scsiReq->scsiStatus = ccb->scsi_status;
		} else {
			cmdBuf->result = SR_IOST_CHKSV;
			scsiReq->driverStatus = SR_IOST_CHKSV;
		}
		break;

	case CS_Timeout:
		cmdBuf->result = SR_IOST_SELTO;
		scsiReq->driverStatus = SR_IOST_SELTO;
		break;

	case CS_Reset:
		cmdBuf->result = SR_IOST_BV;
		scsiReq->driverStatus = SR_IOST_BV;
		break;

	default:
		cmdBuf->result = SR_IOST_HW;
		scsiReq->driverStatus = SR_IOST_HW;
		break;
	}

	scsiReq->bytesTransferred = ccb->total_xfer_len;

	/* Free the CCB */
	[self freeCcb:ccb];

	/* Signal completion to waiting thread */
	[cmdBuf->cmdLock lock];
	[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
}

/*
 * Allocate a CCB
 */
- (struct ccb *)allocCcb : (BOOL)doDMA
{
	int i;

	for (i = 0; i < SYM_QUEUE_SIZE; i++) {
		if (!symCcb[i].in_use) {
			symCcb[i].in_use = TRUE;
			numFreeCcbs--;
			return &symCcb[i];
		}
	}
	return NULL;
}

/*
 * Free a CCB
 */
- (void)freeCcb : (struct ccb *)ccb
{
	ccb->in_use = FALSE;
	numFreeCcbs++;
}

/*
 * Handle SCRIPTS interrupt (command completion)
 */
- (void)handleScriptsInterrupt
{
	struct ccb *ccb;
	unsigned int dsa;

	/* Get the CCB that completed */
	dsa = sym_get_dsa(ioBase);
	if (dsa == 0)
		return;

	/* Find CCB in outstanding queue */
	ccb = (struct ccb *)queue_first(&outstandingQ);
	while (!queue_end(&outstandingQ, (queue_entry_t)ccb)) {
		if ((unsigned int)kvtophys((vm_offset_t)ccb) == dsa) {
			queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
			outstandingCount--;
			[self commandCompleted:ccb reason:CS_Complete];
			return;
		}
		ccb = (struct ccb *)queue_next(&ccb->ccbQ);
	}
}

/*
 * Handle DMA error
 */
- (void)handleDMAError : (unsigned char)dstat
{
	/* Reset chip and abort all commands */
	[self threadResetBus:NULL];
}

/*
 * Handle bus reset
 */
- (void)handleBusReset
{
	/* Abort all commands */
	[self threadResetBus:NULL];
}

/*
 * Handle selection timeout
 */
- (void)handleSelectionTimeout
{
	struct ccb *ccb;
	unsigned int dsa;

	/* Get the CCB that timed out */
	dsa = sym_get_dsa(ioBase);
	if (dsa == 0)
		return;

	/* Find CCB in outstanding queue */
	ccb = (struct ccb *)queue_first(&outstandingQ);
	while (!queue_end(&outstandingQ, (queue_entry_t)ccb)) {
		if ((unsigned int)kvtophys((vm_offset_t)ccb) == dsa) {
			queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
			outstandingCount--;
			ccb->host_status = SYM_HOST_SEL_TIMEOUT;
			[self commandCompleted:ccb reason:CS_Timeout];
			return;
		}
		ccb = (struct ccb *)queue_next(&ccb->ccbQ);
	}
}

/*
 * Handle parity error
 */
- (void)handleParityError
{
	/* Reset chip and abort all commands */
	[self threadResetBus:NULL];
}

@end
