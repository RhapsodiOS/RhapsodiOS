/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Adaptec2940Thread.m - Thread and command execution for Adaptec 2940.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#import "Adaptec2940.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <string.h>

@implementation Adaptec2940(Private)

/*
 * Allocate an SCB.
 */
- (struct scb *)allocScb
{
	int i;
	struct scb *scb;

	for (i = 0; i < AIC_NUM_SCBS; i++) {
		scb = &scbArray[i];
		if (!scb->in_use) {
			scb->in_use = TRUE;
			numFreeScbs--;
			return scb;
		}
	}

	return NULL;
}

/*
 * Free an SCB.
 */
- (void)freeScb:(struct scb *)scb
{
	if (scb && scb->in_use) {
		scb->in_use = FALSE;
		numFreeScbs++;
	}
}

/*
 * Execute command buffer in thread context.
 */
- (void)threadExecuteRequest:(void *)commandBuf
{
	Adaptec2940CommandBuf *cmdBuf = (Adaptec2940CommandBuf *)commandBuf;
	struct scb *scb;
	IOSCSIRequest *scsiReq;
	int i;

	scsiReq = cmdBuf->scsiReq;

	/* Allocate SCB */
	scb = [self allocScb];
	if (scb == NULL) {
		/* No free SCBs - queue for later */
		queue_enter(&pendingQ, cmdBuf, Adaptec2940CommandBuf *, link);
		return;
	}

	cmdBuf->scb = scb;
	scb->cmdBuf = cmdBuf;

	/* Build SCB */
	bzero(scb, sizeof(struct scb));
	scb->in_use = TRUE;

	/* Set target/channel/lun */
	scb->tcl = (scsiReq->target << 4) | scsiReq->lun;

	/* Copy CDB */
	scb->cmdlen = scsiReq->cdbLength;
	bcopy(scsiReq->cdb, &scb->cdb, scsiReq->cdbLength);
	scb->cmdptr = (unsigned int)&scb->cdb;

	/* Setup data transfer */
	if (scsiReq->maxTransfer > 0) {
		scb->data_ptr = (unsigned int)cmdBuf->buffer;
		scb->data_count = scsiReq->maxTransfer;

		/* Build scatter/gather list if needed */
		if (scsiReq->maxTransfer > PAGE_SIZE) {
			int sg_count = 0;
			unsigned int remaining = scsiReq->maxTransfer;
			unsigned int addr = (unsigned int)cmdBuf->buffer;

			while (remaining > 0 && sg_count < AIC_SG_COUNT) {
				unsigned int len = (remaining > PAGE_SIZE) ? PAGE_SIZE : remaining;
				scb->sg_list[sg_count].addr = addr;
				scb->sg_list[sg_count].len = len;
				addr += len;
				remaining -= len;
				sg_count++;
			}

			scb->sg_count = sg_count;
			scb->sg_ptr = (unsigned int)scb->sg_list;
			scb->control = 0x08;  /* SG enable */
		} else {
			scb->sg_count = 0;
			scb->sg_ptr = 0;
			scb->control = 0;
		}
	} else {
		scb->data_ptr = 0;
		scb->data_count = 0;
		scb->sg_count = 0;
		scb->sg_ptr = 0;
		scb->control = 0;
	}

	scb->total_xfer_len = scsiReq->maxTransfer;
	scb->target_status = 0;

	/* Add to outstanding queue */
	queue_enter(&outstandingQ, scb, struct scb *, scbQ);
	outstandingCount++;

	/* Send to controller */
	outb(ioBase + AIC_QINFIFO, scb - scbArray);

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
	Adaptec2940CommandBuf *cmdBuf;

	[commandLock lock];

	/* Process commands from command queue */
	while (!queue_empty(&commandQ)) {
		queue_remove_first(&commandQ, cmdBuf, Adaptec2940CommandBuf *, link);
		[self threadExecuteRequest:cmdBuf];
	}

	/* Process pending queue if space available */
	while (!queue_empty(&pendingQ) && outstandingCount < AIC_QUEUE_SIZE) {
		queue_remove_first(&pendingQ, cmdBuf, Adaptec2940CommandBuf *, link);
		[self threadExecuteRequest:cmdBuf];
	}

	[commandLock unlock];
}

/*
 * Process completed command.
 */
- (void)processCmdComplete:(struct scb *)scb
{
	Adaptec2940CommandBuf *cmdBuf;
	IOSCSIRequest *scsiReq;
	sc_status_t status;

	if (!scb || !scb->in_use) {
		return;
	}

	cmdBuf = (Adaptec2940CommandBuf *)scb->cmdBuf;
	if (!cmdBuf) {
		[self freeScb:scb];
		return;
	}

	scsiReq = cmdBuf->scsiReq;

	/* Remove from outstanding queue */
	queue_remove(&outstandingQ, scb, struct scb *, scbQ);
	outstandingCount--;

	/* Determine status */
	if (scb->target_status == STAT_GOOD) {
		status = SR_IOST_GOOD;
		scsiReq->bytesTransferred = scb->total_xfer_len - scb->residual_data_count;
	} else if (scb->target_status == STAT_CHECK_CONDITION) {
		status = SR_IOST_CHKSV;
		scsiReq->bytesTransferred = 0;
		if (scsiReq->senseData) {
			bcopy(&scb->senseData, scsiReq->senseData, sizeof(esense_reply_t));
		}
	} else {
		status = SR_IOST_SELTO;
		scsiReq->bytesTransferred = 0;
	}

	scsiReq->driverStatus = status;

	/* Complete the request */
	[self completeRequest:scsiReq];

	/* Free resources */
	[self freeScb:scb];
	IOFree(cmdBuf, sizeof(Adaptec2940CommandBuf));

	/* Run more pending commands */
	[self runPendingCommands];
}

/*
 * Execute command buffer.
 */
- (IOReturn)executeCmdBuf:(void *)commandBuf
{
	Adaptec2940CommandBuf *cmdBuf = (Adaptec2940CommandBuf *)commandBuf;

	[commandLock lock];
	queue_enter(&commandQ, cmdBuf, Adaptec2940CommandBuf *, link);
	[commandLock unlock];

	[self runPendingCommands];

	return IO_R_SUCCESS;
}

@end
