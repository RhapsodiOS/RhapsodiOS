/*
 * Copyright (c) 1993-1998 NeXT Software, Inc.
 *
 * AIC6X60Thread.m - I/O thread methods for Adaptec 6x60 driver.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created from Adaptec 1542B driver.
 */

#import "AIC6X60Thread.h"
#import "AIC6X60Types.h"
#import "AIC6X60ControllerPrivate.h"
#import "scsivar.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>
#import <kernserv/queue.h>
#import <bsd/dev/scsireg.h>

extern int HIM6X60QueueSCB(struct _HACB *hacb, struct _SCB *scb);
extern int HIM6X60ResetBus(struct _HACB *hacb, int abort);
extern void himTimeout(struct _SCB *scb);

@implementation AIC6X60(IOThread)

/*
 * I/O thread version of -executeRequest:buffer:client.
 * allocScb, fill the SCB, IOScheduleFunc(himTimeout), HIM6X60QueueSCB.
 * If the SCB pool is empty, enqueue cmdBuf on pendingQ (self+0x1068).
 */
- (void)threadExecuteRequest	: (AIC6X60CommandBuf *)cmdBuf
{
	struct _SCB	*scb;
	IOSCSIRequest	*scsiReq = cmdBuf->scsiReq;

	scb = [self allocScb];
	if (scb == NULL) {
		queue_enter(&pendingQ, cmdBuf, AIC6X60CommandBuf *, link);
		return;
	}
	if ([self scbFromCmd:cmdBuf scb:scb]) {
		[cmdBuf->cmdLock lock];
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
		[self freeScb:scb];
		return;
	}

	scb->timeout_Port = interruptPortKern;
	IOScheduleFunc((IOThreadFunc)himTimeout, scb, scsiReq->timeoutLength);
	if (HIM6X60QueueSCB(&hacb, scb))
		[self commandCompleted:scb reason:CS_Complete];
	totalCommands++;
}

/*
 * I/O thread version of -resetSCSIBus.
 * cmdBuf == NULL is the timeout-recovery call from timeoutOccurred.
 */
- (void)threadResetBus : (AIC6X60CommandBuf *)cmdBuf
{
	if (!HIM6X60ResetBus(&hacb, scsiBus))
		IOLog("Reset of SCSI Bus failed...\n");
	IOLog("Resetting SCSI Bus...\n");
	IOSleep(10000);
	if (cmdBuf) {
		cmdBuf->result = SR_IOST_GOOD;
		[cmdBuf->cmdLock lock];
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
	}
}

/*
 * Build an SCB from the specified AIC6X60CommandBuf. Returns non-zero
 * on command reject; driverStatus and cmdBuf->result are SR_IOST_CMDREJ.
 */
- (int) scbFromCmd:(AIC6X60CommandBuf *)cmdBuf scb:(struct _SCB *)scb
{
	IOSCSIRequest		*scsiReq = cmdBuf->scsiReq;
	unsigned char		*cdb = (unsigned char *)&scsiReq->cdb;
	unsigned int		cmdlen;
	unsigned int		cdb_ctrl;
	unsigned int		opgroup;

	opgroup = SCSI_OPGROUP(cdb[0]);
	switch (opgroup) {

	    case OPGROUP_0:
		cmdlen = 6;
		cdb_ctrl = cdb[5];
		break;

	    case OPGROUP_1:
	    case OPGROUP_2:
		cmdlen = 10;
		cdb_ctrl = cdb[9];
		break;

	    case OPGROUP_5:
		cmdlen = 12;
		cdb_ctrl = cdb[11];
		break;

	    case OPGROUP_6:
		if (scsiReq->cdbLength)
			cmdlen = scsiReq->cdbLength;
		else
			cmdlen = 6;
		cdb_ctrl = 0;
		break;

	    case OPGROUP_7:
		if (scsiReq->cdbLength)
			cmdlen = scsiReq->cdbLength;
		else
			cmdlen = 10;
		cdb_ctrl = 0;
		break;

	    default:
		scsiReq->driverStatus = SR_IOST_CMDREJ;
		cmdBuf->result = SR_IOST_CMDREJ;
		return -1;
	}

	if (cdb_ctrl & CTRL_LINKFLAG) {
		scsiReq->driverStatus = SR_IOST_CMDREJ;
		cmdBuf->result = SR_IOST_CMDREJ;
		return -1;
	}

	if (cdb[0] == C6OP_MODESELECT)
		scsiReq->read = 0;

	scb->dataLength = scsiReq->maxTransfer;
	scb->cdb = cdb;
	scb->cdbLength = cmdlen;
	scb->function = 0;
	scb->flags = 0;
	scb->senseData = (unsigned char *)&scsiReq->senseData;
	scb->senseDataLength = 0x1A;
	scb->dataPointer = cmdBuf->buffer;
	if (scb->dataLength != 0) {
		if (scsiReq->read)
			scb->flags |= 0x40;
		else
			scb->flags |= 0x80;
	}
	if ((scsiReq->disconnect & 1) == 0)
		scb->flags |= 0x04;
	scb->targetID = scsiReq->target;
	scb->lun = scsiReq->lun;
	scb->osRequestBlock = cmdBuf;
	scb->scsiBus = 0;
	scb->queueTag = 0;
	IOGetTimestamp(&scb->startTime);
	return 0;
}

/*
 * A command is done. Figure out what happened, and notify the client.
 * Called from interruptOccurred (CS_Complete), QueueSCB immediate
 * completion, and the timeout/reset reason codes.
 */
- (void)commandCompleted : (struct _SCB *) scb
	          reason : (completeStatus)reason
{
	ns_time_t		currentTime;
	IOSCSIRequest		*scsiReq;
	AIC6X60CommandBuf	*cmdBuf = scb->osRequestBlock;
	unsigned char		senseValid;

	scsiReq = cmdBuf->scsiReq;
	senseValid = scb->scbStatus & 0x80;
	scb->scbStatus &= 0x7F;
	scsiReq->scsiStatus = scb->targetStatus;

	switch (reason) {
	    case CS_Timeout:
		scsiReq->driverStatus = SR_IOST_IOTO;
		break;
	    case CS_Reset:
		scsiReq->driverStatus = SR_IOST_RESET;
		break;
	    case CS_Complete:
		if (scb->timedOut) {
			scsiReq->driverStatus = SR_IOST_IOTO;
			break;
		}
		switch (scb->scbStatus) {
		    case 1:
		    case 0x12:
			scsiReq->bytesTransferred = scb->transferLength;
			if (scsiReq->scsiStatus == STAT_GOOD)
				scsiReq->driverStatus = SR_IOST_GOOD;
			else if (scsiReq->scsiStatus == STAT_CHECK)
				scsiReq->driverStatus = senseValid ?
				    SR_IOST_CHKSV : SR_IOST_CHKSNV;
			else
				scsiReq->driverStatus = SR_IOST_BADST;
			break;
		    case 4:
			if (scsiReq->scsiStatus == STAT_CHECK)
				scsiReq->driverStatus = senseValid ?
				    SR_IOST_CHKSV : SR_IOST_CHKSNV;
			else
				scsiReq->driverStatus = SR_IOST_BADST;
			break;
		    case 0x0A:
			scsiReq->driverStatus = SR_IOST_SELTO;
			break;
		    case 5:
		    case 0x13:
			scsiReq->driverStatus = SR_IOST_BADST;
			break;
		    case 0x0D:
			scsiReq->driverStatus = SR_IOST_CMDREJ;
			break;
		    case 0x0E:
			scsiReq->driverStatus = SR_IOST_RESET;
			break;
		    case 0x0F:
			scsiReq->driverStatus = SR_IOST_PARITY;
			break;
		    default:
			IOLog("AIC:commandComplete: bad status %x\n",
			    scb->scbStatus);
			scsiReq->driverStatus = SR_IOST_BADST;
			break;
		}
		break;
	}

	IOGetTimestamp(&currentTime);
	scsiReq->totalTime = currentTime - scb->startTime;
	cmdBuf->result = scsiReq->driverStatus;

	[cmdBuf->cmdLock lock];
	[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
	[self freeScb:scb];
	(void) IOUnscheduleFunc((IOThreadFunc)himTimeout, scb);
}

/*
 * Alloc/free SCBs from him_scb[]. If the pool is empty, return NULL.
 */
- (struct _SCB *)allocScb
{
	struct _SCB *scb;

	if (numFreeScbs == 0)
		return NULL;

	nextScb = (nextScb + 1) & 0x1F;
	scb = &him_scb[nextScb];
	while (scb->in_use) {
		nextScb = (nextScb + 1) & 0x1F;
		scb = &him_scb[nextScb];
	}
	if (scb > &him_scb[AIC_SCB_COUNT - 1])
		IOPanic("AIC: out of scbs");
	numFreeScbs--;
	bzero(scb, AIC_SCB_SIZE);
	scb->in_use = 1;
	scb->timedOut = 0;
	scb->completed = 0;
	scb->chain = 0;
	scb->length = AIC_SCB_SIZE;
	return scb;
}

- (void)freeScb : (struct _SCB *)scb
{
	bzero(scb, AIC_SCB_SIZE);
	numFreeScbs++;
}

- (void) completeDMA:(IOEISADMABuffer *) dmaList length:(unsigned int) xferLen
{
	IOEISADMABuffer	*buf = &dmaList[0];
	int		i;

	(void)xferLen;
	for (i = 0; i <= 0x10; i++, buf++) {
		if (*buf == NULL)
			return;
		IOLog("AIC DMA???\n");
	}
}


- (void) abortDMA:(IOEISADMABuffer *) dmaList length:(unsigned int) xferLen
{
	IOEISADMABuffer	*buf = &dmaList[0];
	int		i;

	(void)xferLen;
	for (i = 0; i <= 0x10; i++, buf++) {
		if (*buf == NULL)
			return;
		IOLog("AIC DMA???\n");
	}
}

@end
