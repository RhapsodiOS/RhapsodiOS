/*
 * Copyright (c) 1996 NeXT Software, Inc.
 *
 * BusLogicThread.m - I/O thread methods for BusLogic driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from Adaptec 1542 driver.
 */

#import "BusLogicThread.h"
#import "BusLogicTypes.h"
#import "BusLogicInline.h"
#import "BusLogicControllerPrivate.h"
#import "scsivar.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <sys/param.h>

static void blTimeout(void *arg);

#define AUTO_SENSE_ENABLE	1

/*
 * Template for timeout message.
 */
static msg_header_t timeoutMsgTemplate = {
	0,					// msg_unused
	1,					// msg_simple
	sizeof(msg_header_t),			// msg_size
	MSG_TYPE_NORMAL,			// msg_type
	PORT_NULL,				// msg_local_port
	PORT_NULL,				// msg_remote_port - TO
						// BE FILLED IN
	IO_TIMEOUT_MSG				// msg_id
};

@implementation BLController(IOThread)

/*
 * I/O thread version of -executeRequest:buffer:client.
 * The approximate logic is:
 *	Build up an internal ccb describing this request
 *	Put it on the queue of pending commands
 *	Run as many pending commands as possible
 *
 * Returns non-zero if no ccb was available for the command. This case
 * must be handled gracefully by the caller by enqueueing the request on
 * commandQ.
 */
- (int)threadExecuteRequest	: (BLCommandBuf *)cmdBuf
{
	struct ccb	*ccb;
	IOSCSIRequest	*scsiReq = cmdBuf->scsiReq;

	ddm_thr("threadExecuteRequest cmdBuf 0x%x\n", cmdBuf, 2,3,4,5);

	ccb = [self allocCcb:(scsiReq->maxTransfer ? YES : NO)];
	if(ccb == NULL) {
		return 1;
	}
	if([self ccbFromCmd:cmdBuf ccb:ccb]) {
		/*
		 * Command reject. Error status is in
		 * cmdBuf->scsiReq->driverStatus.
		 * Notify caller and clean up.
		 */
		[self freeCcb:ccb];
		[cmdBuf->cmdLock lock];
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
		return 0;
	}

	/*
	 *  Make sure we'll be able to time this command out.  This should be
	 *  rare, so we don't particularly care about how efficient it is.
	 */
	ccb->timeoutPort = interruptPortKern;
	IOScheduleFunc(blTimeout, ccb, scsiReq->timeoutLength);

	/*
	 * Stick this command on the list of pending ones, and run them.
	 */
	queue_enter(&pendingQ, ccb, struct ccb *, ccbQ);
	[self runPendingCommands];
	return 0;

}

/*
 * I/O thread version of -resetSCSIBus.
 * We also interpret this to mean we should reset the board.
 * cmdBuf == NULL indicates a call from within the I/O thread for
 * a reason other than -resetSCSIBus (e.g., timeout recovery).
 */
- (void)threadResetBus : (BLCommandBuf *)cmdBuf
{

	bl_ctrl_reg_t	ctrl = { 0 };
    	struct ccb *ccb;
	queue_head_t *q;

	ddm_thr("threadResetBus\n", 1,2,3,4,5);

	/*
	 * Abort all outstanding and pending commands.
	 */
	for(q=&outstandingQ; q!=&pendingQ; q=&pendingQ)	{
		while(!queue_empty(q)) {
			ccb = (struct ccb *)queue_first(q);
			queue_remove(q, ccb, struct ccb *, ccbQ);
			if(q == &outstandingQ) {
				ASSERT(outstandingCount != 0);
				outstandingCount--;
			}
			[self commandCompleted:ccb reason:CS_Reset];
		}
	}

	/*
	 * Now reset the hardware.
	 */
	bl_reset_board(ioBase, blBoardId);
	bl_setup_mb_area(ioBase, blMbArea, blCcb);

	ctrl.scsi_rst = 1;
	bl_put_ctrl(ioBase, ctrl);

	IOLog("Resetting SCSI Bus...\n");
	IOSleep(10000);

	/*
	 * Notify caller of completion if appropriate.
	 */
	if(cmdBuf) {
		ddm_thr("threadResetBus: I/O complete on cmdBuf 0x%x\n",
			cmdBuf, 2,3,4,5);
		cmdBuf->result = SR_IOST_GOOD;
		[cmdBuf->cmdLock lock];
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
	}
}

/*
 * Build a ccb from the specified BLCommandBuf. Returns non-zero on error
 * (i.e., on command reject from this method). In that case, error status
 * is in cmdBuf->scsiReq->driverStatus.
 */
- (int) ccbFromCmd:(BLCommandBuf *)cmdBuf ccb:(struct ccb *)ccb
{
	IOSCSIRequest		*scsiReq = cmdBuf->scsiReq;
	union cdb		*cdbp = &scsiReq->cdb;
	int			cdb_ctrl;
	vm_offset_t		addr, phys;
	vm_size_t		len;
	unsigned int		pages;
	unsigned int		cmdlen;

	/*
	 * Figure out what kind of cdb we've been given
	 * and snag the ctrl byte
	 */
	switch (SCSI_OPGROUP(cdbp->cdb_opcode)) {

	    case OPGROUP_0:
		cmdlen = sizeof (struct cdb_6);
		cdb_ctrl = cdbp->cdb_c6.c6_ctrl;
		break;

	    case OPGROUP_1:
	    case OPGROUP_2:
		cmdlen = sizeof (struct cdb_10);
		cdb_ctrl = cdbp->cdb_c10.c10_ctrl;
		break;

	    case OPGROUP_5:
		cmdlen = sizeof (struct cdb_12);
		cdb_ctrl = cdbp->cdb_c12.c12_ctrl;
		break;

    	    /*
	     * Group 6 and 7 commands allow a user-specified CDB length.
	     */
	    case OPGROUP_6:
		if(scsiReq->cdbLength)
		 	cmdlen = scsiReq->cdbLength;
		else
			cmdlen = sizeof (struct cdb_6);
		cdb_ctrl = 0;
		break;

	    case OPGROUP_7:
		if(scsiReq->cdbLength)
		 	cmdlen = scsiReq->cdbLength;
		else
			cmdlen = sizeof (struct cdb_10);
		cdb_ctrl = 0;
		break;

	    default:
		scsiReq->driverStatus = SR_IOST_CMDREJ;
		return 1;
	}

	/*
	 * Make sure nothing unreasonable has been asked of us
	 */
	if ((cdb_ctrl & CTRL_LINKFLAG) != CTRL_NOLINK) {
		scsiReq->driverStatus = SR_IOST_CMDREJ;
		return 1;
	}

	addr = (vm_offset_t)cmdBuf->buffer;
	len = scsiReq->maxTransfer;

	if (len > 0)
		pages = (round_page(addr+len) - trunc_page(addr)) / PAGE_SIZE;
	else
		pages = 0;

	ccb->cdb		= *cdbp;
	ccb->cdb_len		= cmdlen;

	ccb->data_in		= scsiReq->read;
	ccb->data_out		= !scsiReq->read;
	ccb->target		= scsiReq->target;
	ccb->lun		= scsiReq->lun;
	#if	AUTO_SENSE_ENABLE
	ccb->reqsense_len      = sizeof(esense_reply_t);
	#else	AUTO_SENSE_ENABLE
	ccb->reqsense_len	= 1;	/* no auto reqsense */
	#endif	AUTO_SENSE_ENABLE

	/*
	 * Note BusLogic does not support command queueing. Synchronous
	 * negotiation can only be disabled by jumper. Disconnects can
	 * not be disabled.
	 */

	ccb->cmdBuf = cmdBuf;
	ccb->total_xfer_len = 0;
	IOGetTimestamp(&ccb->startTime);

	/*
	 *  Set up the DMA address and length.  If we have more than one page,
	 *  then chances are that we'll have to use scatter/gather to collect
	 *  all the physical pages into a single transfer.
	 */
	if (pages == 0) {
		bl_put_24(0, ccb->data_addr);
		bl_put_24(0, ccb->data_len);
		ccb->oper = BL_CCB_INITIATOR_RESID;
	}
	else if (pages == 1) {

		if(IOPhysicalFromVirtual(cmdBuf->client, addr, &phys)) {
			IOLog("%s: Can\'t get physical address\n",
				[self name]);
			scsiReq->driverStatus = SR_IOST_INT;
			return 1;
		}

		ccb->dmaList[0] = [self createDMABufferFor:&phys
				length:len read:scsiReq->read
				needsLowMemory:YES limitSize:NO];

		if (ccb->dmaList[0] == NULL) {
			[self abortDMA:ccb->dmaList length:len];
			scsiReq->driverStatus = SR_IOST_INT;
			return 1;
		}

		bl_put_24(phys, ccb->data_addr);
		bl_put_24(len, ccb->data_len);

		ccb->oper = BL_CCB_INITIATOR_RESID;
		ccb->total_xfer_len = len;
	}
	else {
		vm_offset_t	lastPhys = 0;
		unsigned int	sgEntry = 0;
		unsigned int	maxEntries = MIN(pages, BL_SG_COUNT);
		IOEISADMABuffer	*dmaBuf = ccb->dmaList;

		for (sgEntry=0;  sgEntry < maxEntries;  sgEntry++) {
			struct bl_sg	*sg = &ccb->sg_list[sgEntry];
			unsigned int	thisLength;

			thisLength = MIN(len, round_page(addr+1) - addr);

	   		if(IOPhysicalFromVirtual(cmdBuf->client,
					addr, &phys)) {
				IOLog("%s: Can\'t get physical address\n",
					[self name]);
				[self abortDMA:ccb->dmaList
					length:ccb->total_xfer_len];
				scsiReq->driverStatus = SR_IOST_INT;
				return 1;
			}
			*dmaBuf = [self createDMABufferFor:&phys
					length:thisLength
					read:scsiReq->read
					needsLowMemory:YES limitSize:NO];

			if (*dmaBuf == NULL) {
				[self abortDMA:ccb->dmaList
					length:ccb->total_xfer_len];
				scsiReq->driverStatus = SR_IOST_INT;
				return 1;
			}

			bl_put_24(phys, sg->addr);
			bl_put_24(thisLength, sg->len);

			ccb->total_xfer_len += thisLength;

			addr += thisLength;
			len -= thisLength;
			lastPhys = phys;
			dmaBuf++;
		}

		if(IOPhysicalFromVirtual(IOVmTaskSelf(),
				(unsigned)ccb->sg_list,
				&phys)) {
			IOLog("%s: Can\'t get physical address of ccb\n",
				[self name]);
			IOPanic("BLController");
		}
		bl_put_24(phys, ccb->data_addr);
		bl_put_24(sgEntry * sizeof(struct bl_sg), ccb->data_len);

		ccb->oper = BL_CCB_INITIATOR_RESID_SG;
	}

	return 0;
}

/*
 * If any commands pending, and the controller's queue is not full,
 * run the new commands.
 */
- runPendingCommands
{
	unsigned int	cmdsToRun;
	struct ccb	*ccb;

	cmdsToRun = BL_QUEUE_SIZE - outstandingCount;

	while (cmdsToRun > 0 && !queue_empty(&pendingQ)) {

		/*
		 *  Dequeue pending command and add to the outstanding queue.
		 */
		ccb = (struct ccb *) queue_first(&pendingQ);
		queue_remove(&pendingQ, ccb, struct ccb *, ccbQ);
		if (!ccb)
			break;

		queue_enter(&outstandingQ, ccb, struct ccb *, ccbQ);
		outstandingCount++;

		/*
		 *  Let 'er rip...
		 */
		ccb->mb_out->mb_stat = BL_MB_OUT_START;
		bl_start_scsi(ioBase);

		/*
		 *  Accumulate some simple statistics: the max queue length
		 *  and enough info to compute a running average of the queue
		 *  length.
		 */
		maxQueueLen = MAX(maxQueueLen, outstandingCount);
		queueLenTotal += outstandingCount;
		totalCommands++;

		cmdsToRun--;
	}
	return self;
}

/*
 * A command is done.  Figure out what happened, and notify the
 * client appropriately. Called upon detection of I/O complete interrupt,
 * timeout detection, or when we reset the bus and blow off pending
 * commands.
 */
- (void)commandCompleted : (struct ccb *) ccb
	          reason : (completeStatus)reason
{
	ns_time_t		currentTime;
	IOSCSIRequest		*scsiReq;
	BLCommandBuf  		*cmdBuf = ccb->cmdBuf;

	ASSERT(cmdBuf != NULL);
	scsiReq = cmdBuf->scsiReq;
	ASSERT(scsiReq != NULL);

	ddm_thr("commandCompleted: ccb 0x%x cmdBuf 0x%x reason %d\n",
		ccb, cmdBuf, reason, 4,5);

	scsiReq->scsiStatus = ccb->target_status;

	switch(reason) {
	    case CS_Timeout:
	   	scsiReq->driverStatus = SR_IOST_IOTO;
		break;
	    case CS_Reset:
	    	scsiReq->driverStatus = SR_IOST_RESET;
		break;
	    case CS_Complete:
		switch (ccb->host_status) {

		/*
		 * Handle success and data overrun/underrun.  We can handle
		 * overrun/underrun as a normal case because the controller
		 * sets the data_len field to be the actual number of bytes
		 * transferred regardless of overrun.
	         */
		case BL_HOST_SUCCESS:
		case BL_HOST_DATA_OVRUN:
		    [self completeDMA:ccb->dmaList
		    	length:scsiReq->maxTransfer];
		    scsiReq->bytesTransferred = ccb->total_xfer_len -
					bl_get_24(ccb->data_len);

		    /*
		     *  Everything looks good.  Make sure the SCSI status byte
		     *  is cool before we really say everything is hunky-dory.
		     */
		    if (scsiReq->scsiStatus == STAT_GOOD)
			    scsiReq->driverStatus = SR_IOST_GOOD;
		    else if (scsiReq->scsiStatus == STAT_CHECK) {
		        if(AUTO_SENSE_ENABLE) {

			    esense_reply_t *sensePtr;

			    scsiReq->driverStatus = SR_IOST_CHKSV;

			    /*
			     * Sense data starts immediately after the actual
			     * cdb area we use, not an entire union cdb.
			     */
			    sensePtr = (esense_reply_t *)
			    	(((char *)&ccb->cdb) + ccb->cdb_len);
			    scsiReq->senseData = *sensePtr;
			}
			else {
			    scsiReq->driverStatus = SR_IOST_CHKSNV;
			}
		    }
		    else
			    scsiReq->driverStatus = ST_IOST_BADST;
		    break;

		case BL_HOST_SEL_TIMEOUT:
		    [self abortDMA:ccb->dmaList length:scsiReq->maxTransfer];
		    scsiReq->driverStatus = SR_IOST_SELTO;
		    break;

		default:
		    IOLog("BL interrupt: bad status %x\n", ccb->host_status);
		    [self abortDMA:ccb->dmaList length:scsiReq->maxTransfer];
		    scsiReq->driverStatus = SR_IOST_INVALID;
		    break;
	    }   /*  switch host_status */
	}   	/*  switch status */

	IOGetTimestamp(&currentTime);
	scsiReq->totalTime = currentTime - ccb->startTime;
	cmdBuf->result = scsiReq->driverStatus;

	/*
	 * Wake up client.
	 */
	ddm_thr("commandCompleted: I/O complete on cmdBuf 0x%x\n",
			cmdBuf, 2,3,4,5);
	[cmdBuf->cmdLock lock];
	[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];

	/*
	 * Free the CCB and clean up possible pending timeout.
	 */
	(void) IOUnscheduleFunc(blTimeout, ccb);
	[self freeCcb:ccb];
}

/*
 * Alloc/free ccb's. These only come from the array blCcb[].
 * If we can't find one, return NULL - caller will have to try
 * again later.
 */
- (struct ccb *)allocCcb : (BOOL)doDMA
{
	struct ccb *ccb;
	int i;

	if(numFreeCcbs == 0) {
		ddm_thr("allocCcb: numFreeCcbs = 0\n", 1,2,3,4,5);
		return NULL;
	}

	/*
	 * Since numFreeCcbs is non-zero, there has to be one available
	 * in blCcb[].
	 */
	ccb = blCcb;
	while (ccb <= &blCcb[BL_QUEUE_SIZE - 1] && ccb->in_use) {
		ccb++;
	}
	if (ccb > &blCcb[BL_QUEUE_SIZE - 1]) {
		IOPanic("BLController: out of ccbs");
	}
	numFreeCcbs--;
	ccb->in_use = TRUE;

	/*
	 * Null out dmaList.
	 */
	for(i=0; i<BL_SG_COUNT; i++) {
		ccb->dmaList[i] = NULL;
	}

	/*
	 * Acquire the reentrant DMA lock. This is a nop on EISA machines.
	 *
	 * Although -reserveDMALock is reentrant for multiple threads on
	 * one device, it is *not* reentrant for one thread. Thus we should
	 * only call it if we don't already hold the lock.
	 * Also, avoid this if we're not going to do any DMA.
	 */
	if(doDMA && (++dmaLockCount == 1)) {
		ddm_thr("allocCcb: calling reserveDMALock\n", 1,2,3,4,5);
		[super reserveDMALock];
	}
	ddm_thr("allocCcb: returning 0x%x\n", ccb, 2,3,4,5);

	return ccb;
}

- (void)freeCcb : (struct ccb *)ccb
{
	BOOL	didDMA = (ccb->total_xfer_len ? YES : NO);

	ddm_thr("freeCcb: ccb 0x%x\n", ccb, 2,3,4,5);
	ccb->in_use = FALSE;
	numFreeCcbs++;
	if(didDMA && (--dmaLockCount == 0)) {
		ddm_thr("freeCcb: calling releaseDMALock\n",
			1,2,3,4,5);
		[super releaseDMALock];
	}
}

- (void) completeDMA:(IOEISADMABuffer *) dmaList length:(unsigned int) xferLen
{
	IOEISADMABuffer	*buf = &dmaList[0];
	int		i;

	for (i = 0; i < BL_SG_COUNT; i++, buf++) {
		if(*buf) {
			[self freeDMABuffer:*buf];
		}
		else {
			return;
		}
	}
}


- (void) abortDMA:(IOEISADMABuffer *) dmaList length:(unsigned int) xferLen
{
	IOEISADMABuffer	*buf = &dmaList[0];
	int		i;

	for (i = 0; i < BL_SG_COUNT; i++, buf++) {
		if(*buf) {
			[self abortDMABuffer:*buf];
		}
		else {
			return;
		}
	}
}

@end


/*
 *  Handle timeouts.  We just send a timeout message to the I/O thread
 *  so it wakes up.
 */
static void
blTimeout(void *arg)
{

	struct ccb	*ccb = arg;
	msg_header_t	msg = timeoutMsgTemplate;
	msg_return_t	mrtn;

	if(!ccb->in_use) {
		/*
		 * Race condition - this CCB got completed another way.
		 * No problem.
		 */
		return;
	}
	msg.msg_remote_port = ccb->timeoutPort;
	IOLog("BL timeout\n");
	if(mrtn = msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0)) {
		IOLog("blTimeout: msg_send_from_kernel() returned %d\n",
			mrtn);
	}
}

