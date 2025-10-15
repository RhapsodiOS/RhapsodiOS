/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * DPTSCSIDriverThread.m - Thread handling for DPT SCSI driver.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#import "DPTSCSIDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <machkit/NXLock.h>
#import <kernserv/prototypes.h>

@implementation DPTSCSIDriver(Private)

/*
 * Thread execution of request.
 */
- (void)threadExecuteRequest:(void *)commandBuf
{
	DPTSCSIDriverCommandBuf *cmdBuf = (DPTSCSIDriverCommandBuf *)commandBuf;
	IOSCSIRequest *scsiReq = cmdBuf->scsiReq;
	struct eata_cp *cp;
	unsigned int flags1 = 0;
	int i;

	/* Allocate CP */
	cp = [self allocCp];
	if (cp == NULL) {
		/* No free CPs, queue for later */
		queue_enter(&pendingQ, cmdBuf, DPTSCSIDriverCommandBuf *, link);
		return;
	}

	cmdBuf->cp = cp;
	cp->cmdBuf = cmdBuf;

	/* Build CP */
	bzero(cp, sizeof(struct eata_cp));

	/* Set SCSI address */
	cp->cp_scsi_addr = (scsiReq->target << 5) | (scsiReq->lun & 0x07);

	/* Set CDB */
	bcopy(&scsiReq->cdb, cp->cp_cdb, scsiReq->cdbLength);

	/* Set flags */
	flags1 = CP_IDENTIFY | CP_DISCONNECT;

	if (scsiReq->read) {
		flags1 |= CP_DATA_IN;
	} else if (scsiReq->maxTransfer > 0) {
		flags1 |= CP_DATA_OUT;
	}

	/* Set up scatter/gather if needed */
	if (scsiReq->maxTransfer > 0) {
		IOMemoryDescriptor *memDesc;
		IOReturn result;

		/* For now, use physical addressing */
		flags1 |= CP_PHYSICAL | CP_SCATTER;

		/* Build S/G list */
		/* This is simplified - real implementation would handle proper S/G */
		cp->sg_list[0].addr = (unsigned int)cmdBuf->buffer;
		cp->sg_list[0].len = scsiReq->maxTransfer;
		cp->cp_dataAddr = (unsigned int)cp->sg_list;
		cp->cp_dataLen = scsiReq->maxTransfer;
	} else {
		cp->cp_dataAddr = 0;
		cp->cp_dataLen = 0;
	}

	cp->cp_flags1 = flags1;
	cp->cp_flags2 = 0;
	cp->cp_flags3 = 0;

	/* Set sense buffer */
	cp->cp_sense_addr = (unsigned int)&cp->senseData;
	cp->cp_sense_len = sizeof(esense_reply_t);

	/* Set virtual CP address */
	cp->cp_virt_cp = (unsigned int)cp;

	/* Mark as in use */
	cp->in_use = TRUE;

	/* Add to outstanding queue */
	queue_enter(&outstandingQ, cp, struct eata_cp *, cpQ);
	outstandingCount++;

	/* Send CP to controller */
	outl(ioBase + EATA_CP_ADDR, (unsigned int)cp);
	outb(ioBase + EATA_CMD, EATA_CMD_SEND_CP);

	/* Update statistics */
	totalCommands++;
	if (outstandingCount > maxQueueLen) {
		maxQueueLen = outstandingCount;
	}
	queueLenTotal += outstandingCount;
}

/*
 * Run pending commands.
 */
- (void)runPendingCommands
{
	DPTSCSIDriverCommandBuf *cmdBuf;

	[commandLock lock];

	while (!queue_empty(&commandQ)) {
		queue_remove_first(&commandQ, cmdBuf, DPTSCSIDriverCommandBuf *, link);
		[commandLock unlock];

		[self threadExecuteRequest:cmdBuf];

		[commandLock lock];
	}

	[commandLock unlock];

	/* Process any pending requests */
	while (!queue_empty(&pendingQ) && (outstandingCount < DPT_QUEUE_SIZE)) {
		queue_remove_first(&pendingQ, cmdBuf, DPTSCSIDriverCommandBuf *, link);
		[self threadExecuteRequest:cmdBuf];
	}
}

/*
 * Process completed command.
 */
- (void)processCmdComplete:(struct eata_cp *)cp
{
	DPTSCSIDriverCommandBuf *cmdBuf;
	IOSCSIRequest *scsiReq;
	sc_status_t status;

	if (!cp || !cp->in_use) {
		return;
	}

	cmdBuf = (DPTSCSIDriverCommandBuf *)cp->cmdBuf;
	if (!cmdBuf) {
		[self freeCp:cp];
		return;
	}

	scsiReq = cmdBuf->scsiReq;

	/* Remove from outstanding queue */
	queue_remove(&outstandingQ, cp, struct eata_cp *, cpQ);
	outstandingCount--;

	/* Check status */
	switch (cp->cp_host_status) {
		case HS_OK:
			status = SR_IOST_GOOD;
			scsiReq->driverStatus = SR_IOST_GOOD;
			scsiReq->scsiStatus = cp->cp_scsi_status;
			break;

		case HS_SEL_TIMEOUT:
			status = SR_IOST_SELTO;
			scsiReq->driverStatus = SR_IOST_SELTO;
			break;

		case HS_CMD_TIMEOUT:
			status = SR_IOST_CMDTO;
			scsiReq->driverStatus = SR_IOST_CMDTO;
			break;

		default:
			status = SR_IOST_HW;
			scsiReq->driverStatus = SR_IOST_HW;
			break;
	}

	/* Copy sense data if available */
	if (cp->cp_sense_len > 0) {
		bcopy(&cp->senseData, &scsiReq->senseData, sizeof(esense_reply_t));
	}

	/* Set bytes transferred */
	if (scsiReq->maxTransfer > 0) {
		scsiReq->bytesTransferred = scsiReq->maxTransfer - cp->cp_dataLen;
	}

	/* Free resources */
	[self freeCp:cp];
	IOFree(cmdBuf, sizeof(DPTSCSIDriverCommandBuf));

	/* Complete request */
	[self completeRequest:scsiReq];

	/* Run more commands */
	[self runPendingCommands];
}

/*
 * Execute command buffer.
 */
- (IOReturn)executeCmdBuf:(void *)commandBuf
{
	DPTSCSIDriverCommandBuf *cmdBuf = (DPTSCSIDriverCommandBuf *)commandBuf;

	[commandLock lock];
	queue_enter(&commandQ, cmdBuf, DPTSCSIDriverCommandBuf *, link);
	[commandLock unlock];

	/* Trigger I/O thread */
	[self commandRequestOccurred];

	return IO_R_SUCCESS;
}

@end
