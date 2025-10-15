/*
 * AMD_SCSI.m - top-level module for AMD 53C974/79C974 PCI SCSI driver. 
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */

#import "AMD_SCSI.h"
#import "AMD_Private.h"
#import "AMD_x86.h"
#import "AMD_Chip.h"
#import "AMD_ddm.h"
#import "AMD_Regs.h"
#import <mach/message.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>

static void AMDTimeout(void *arg);

/* 
 * Template for command message sent to the I/O thread.
 */
static msg_header_t cmdMessageTemplate = {
	0,					// msg_unused 
	1,					// msg_simple 
	sizeof(msg_header_t),			// msg_size 
	MSG_TYPE_NORMAL,			// msg_type 
	PORT_NULL,				// msg_local_port 
	PORT_NULL,				// msg_remote_port - TO
						// BE FILLED IN 
	IO_COMMAND_MSG				// msg_id 
};

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


@implementation AMD_SCSI

/*
 * Create and initialize one instance of AMD_SCSI. The work is done by
 * architecture- and chip-specific modules. 
 */
+ (BOOL)probe:deviceDescription
{
	AMD_SCSI *inst = [self alloc];


	if([inst archInit:deviceDescription] == nil) {
		return NO;
	}
	else {
		return YES;
	}
}

- free
{
	commandBuf cmdBuf;
	
	/*
	 * First kill the I/O thread if running. 
	 */
	if(ioThreadRunning) {
		cmdBuf.op = CO_Abort;
		cmdBuf.scsiReq = NULL;
		[self executeCmdBuf:&cmdBuf];
	}
	
	if(commandLock) {
		[commandLock free];
	}
	if(mdlFree) {
		IOFree(mdlFree, MDL_SIZE * 2 * sizeof(vm_address_t));
	}
	return [super free];
}

/*
 * Our max DMA size is 64 K, derived from using 18 MDL entries (note the 
 * first and last entries can refer to chunks as small as 4 bytes). 
 */
- (unsigned)maxTransfer
{
	return AMD_DMA_PAGE_SIZE * (MDL_SIZE - 2);
}

/*
 * Return required DMA alignment for current architecture.
 */
- (void)getDMAAlignment : (IODMAAlignment *)alignment;
{
	alignment->readStart   = AMD_READ_START_ALIGN;
	alignment->writeStart  = AMD_WRITE_START_ALIGN;
	alignment->readLength  = AMD_READ_LENGTH_ALIGN;
	alignment->writeLength = AMD_WRITE_LENGTH_ALIGN;
}

/*
 * Statistics support.
 */
- (unsigned int) numQueueSamples
{
	return totalCommands;
}


- (unsigned int) sumQueueLengths
{
	return queueLenTotal;
}


- (unsigned int) maxQueueLength
{
	return maxQueueLen;
}


- (void)resetStats
{
	totalCommands = 0;
	queueLenTotal = 0;
	maxQueueLen   = 0;
}

/*
 * Do a SCSI command, as specified by an IOSCSIRequest. All the 
 * work is done by the I/O thread.
 */
- (sc_status_t) executeRequest : (IOSCSIRequest *)scsiReq 
		    buffer : (void *)buffer 
		    client : (vm_task_t)client
{
	commandBuf cmdBuf;
	
	ddm_exp("executeRequest: cmdBuf 0x%x maxTransfer 0x%x\n", 
		&cmdBuf, scsiReq->maxTransfer,3,4,5);
	
	bzero(&cmdBuf, sizeof(commandBuf));
	cmdBuf.op      = CO_Execute;
	cmdBuf.scsiReq = scsiReq;
	cmdBuf.buffer  = buffer;
	cmdBuf.client  = client;
	scsiReq->driverStatus = SR_IOST_INVALID;
	
	[self executeCmdBuf:&cmdBuf];
	
	ddm_exp("executeRequest: cmdBuf 0x%x complete; driverStatus %s\n", 
		&cmdBuf, IOFindNameForValue(scsiReq->driverStatus, 
					IOScStatusStrings), 3,4,5);
	return cmdBuf.scsiReq->driverStatus;
}


/*
 *  Reset the SCSI bus. All the work is done by the I/O thread.
 */
- (sc_status_t)resetSCSIBus
{
	commandBuf cmdBuf;
	
	ddm_exp("resetSCSIBus: cmdBuf 0x%x\n", &cmdBuf, 2,3,4,5);

	cmdBuf.op = CO_Reset;
	cmdBuf.scsiReq = NULL;
	[self executeCmdBuf:&cmdBuf];
	ddm_exp("resetSCSIBus: cmdBuf 0x%x DONE\n", &cmdBuf, 2,3,4,5);
	return SR_IOST_GOOD;		// can not fail
}

/*
 * The following 6 methods are all called from the I/O thread in 
 * IODirectDevice. 
 */
 
/*
 * Called from the I/O thread when it receives an interrupt message.
 * Currently all work is done by chip-specific module; maybe we should 
 * put this method there....
 */
- (void)interruptOccurred
{
	#if	DDM_DEBUG
	/*
	 * calculate interrupt service time if enabled.
	 */
	ns_time_t	startTime, endTime, elapsedNs;
	unsigned	elapsedUs = 0;
	
	if(IODDMMasks[AMD_DDM_INDEX] & DDM_INTR) {
		IOGetTimestamp(&startTime);
	}
	ddm_thr("interruptOccurred: TOP\n", 1,2,3,4,5);
	#endif	DDM_DEBUG

	[self hwInterrupt];
	
	#if	DDM_DEBUG
	if(IODDMMasks[AMD_DDM_INDEX] & DDM_INTR) {
		IOGetTimestamp(&endTime);
		elapsedNs = endTime - startTime;
		elapsedUs = (unsigned)((elapsedNs + 999ULL) / 1000ULL);
	}
	ddm_intr("interruptOccurred: DONE; elapsed time %d us\n", 
		elapsedUs, 2,3,4,5);
	#endif	DDM_DEBUG
}

/*
 * These three should not occur; they are here as error traps. All three are 
 * called out from the I/O thread upon receipt of messages which it should
 * not be seeing.
 */
- (void)interruptOccurredAt:(int)localNum
{
	IOLog("%s: interruptOccurredAt:%d\n", [self name], localNum);
}

- (void)otherOccurred:(int)id
{
	IOLog("%s: otherOccurred:%d\n", [self name], id);
}

- (void)receiveMsg
{
	IOLog("%s: receiveMsg\n", [self name]);
	
	/*
	 * We have to let IODirectDevice take care of this (i.e., dequeue the
	 * bogus message).
	 */
	[super receiveMsg];
}

/*
 * Used in -timeoutOccurred to determine if specified cmdBuf has timed out.
 * Returns YES if timeout, else NO.
 */
static inline BOOL
isCmdTimedOut(commandBuf *cmdBuf, ns_time_t now)
{
	IOSCSIRequest	*scsiReq;
	ns_time_t	expire;
	
	scsiReq = cmdBuf->scsiReq;
	expire  = cmdBuf->startTime + 
		(1000000000ULL * (unsigned long long)scsiReq->timeoutLength);
	return ((now > expire) ? YES : NO);
}

/*
 * Called from the I/O thread when it receives a timeout
 * message. We send these messages ourself from AMDTimeout().
 */
- (void)timeoutOccurred
{
	ns_time_t	now;
	BOOL		cmdTimedOut = NO;
	commandBuf	*cmdBuf;
	commandBuf	*nextCmdBuf;
	
	ddm_thr("timeoutOccurred: TOP\n", 1,2,3,4,5);
	IOGetTimestamp(&now);

	/*
	 *  Scan activeCmd and disconnectQ looking for tardy I/Os.
	 */
	if(activeCmd) {
		cmdBuf = activeCmd;
		if(isCmdTimedOut(cmdBuf, now)) {
			ddm_thr("activeCmd TIMEOUT, cmd 0x%x\n", 
				cmdBuf, 2,3,4,5);
			activeCmd = NULL;
			ASSERT(cmdBuf->scsiReq != NULL);
			cmdBuf->scsiReq->driverStatus = SR_IOST_IOTO;
			[self ioComplete:cmdBuf];
			cmdTimedOut = YES;
		}
	}

	cmdBuf = (commandBuf *)queue_first(&disconnectQ);
	while(!queue_end(&disconnectQ, (queue_entry_t)cmdBuf)) {
		if(isCmdTimedOut(cmdBuf, now)) {
			ddm_thr("disconnected cmd TIMEOUT, cmd 0x%x\n", 
				cmdBuf, 2,3,4,5);
		
			/*
			 *  Remove cmdBuf from disconnectQ and
			 *  complete it.
			 */
			nextCmdBuf = (commandBuf *)queue_next(&cmdBuf->link);
			queue_remove(&disconnectQ, cmdBuf, commandBuf *, link);
			ASSERT(cmdBuf->scsiReq != NULL);
			cmdBuf->scsiReq->driverStatus = SR_IOST_IOTO;
			[self ioComplete:cmdBuf];
			cmdBuf = nextCmdBuf;
			cmdTimedOut = YES;
		}
		else {
			cmdBuf = (commandBuf *)queue_next(&cmdBuf->link);
		}
	}

	/*
	 * Reset bus. This also completes all I/Os in disconnectQ with
	 * status CS_Reset.
	 */
	if(cmdTimedOut) {
		[self logRegs];
		[self threadResetBus:NULL];
	}
	ddm_thr("timeoutOccurred: DONE\n", 1,2,3,4,5);
}

/*
 * Process all commands in commandQ. At most one of these will become
 * activeCmd. The remainder of CO_Execute commands go to pendingQ. Other
 * types of commands are executed immediately.
 */
- (void)commandRequestOccurred
{
	commandBuf *cmdBuf;
	commandBuf *pendCmd;
	
	ddm_thr("commandRequestOccurred: top\n", 1,2,3,4,5);
	[commandLock lock];
	while(!queue_empty(&commandQ)) {
		cmdBuf = (commandBuf *) queue_first(&commandQ);
		queue_remove(&commandQ, cmdBuf, commandBuf *, link);
		[commandLock unlock];
		
		switch(cmdBuf->op) {
		    case CO_Reset:
		    	/* 
			 * Note all active and disconnected commands will
			 * be terminted.
			 */
		    	[self threadResetBus:"Reset Command Received"];
			[self ioComplete:cmdBuf];
			break;
			
		    case CO_Abort:
			/*
			 * 1. Abort all active, pending, and disconnected
			 *    commands.
			 * 2. Notify caller of completion.
			 * 3. Self-terminate.
			 */
			[self swAbort:SR_IOST_INT];
			pendCmd = (commandBuf *)queue_first(&pendingQ);
			while(!queue_end(&pendingQ, 
					(queue_entry_t)pendCmd)) {
				pendCmd->scsiReq->driverStatus = SR_IOST_INT;
				[self ioComplete:pendCmd];
				pendCmd = (commandBuf *)
					queue_next(&pendCmd->link);
			}
			[cmdBuf->cmdLock lock];
			[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
			IOExitThread();
			/* not reached */
			
		    case CO_Execute:
			[self threadExecuteRequest:cmdBuf];
			break;
			
		}
		[commandLock lock];
	}
	[commandLock unlock];
	ddm_thr("commandRequestOccurred: DONE\n", 1,2,3,4,5);
	return;
}

/*
 * Power management methods. All we care about is power off, when we must 
 * reset the SCSI bus due to the Compaq BIOS's lack of a SCSI reset, which
 * causes a hang if we have set up targets for sync data transfer mode.
 */
- (IOReturn)getPowerState:(PMPowerState *)state_p
{
 	ddm_exp("getPowerState called\n", 1,2,3,4,5);
   	return IO_R_UNSUPPORTED;
}

- (IOReturn)setPowerState:(PMPowerState)state
{
#ifdef DEBUG
	IOLog("%s: received setPowerState: with %x\n", [self name],
	    (unsigned)state);
#endif DEBUG
	if (state == PM_OFF) {
		// [self scsiReset];
		[self powerDown];
		return IO_R_SUCCESS;
	}
	return IO_R_UNSUPPORTED;
}

- (IOReturn)getPowerManagement:(PMPowerManagementState *)state_p
{
	ddm_exp("getPowerManagement called\n", 1,2,3,4,5);
    	return IO_R_UNSUPPORTED;
}

- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
	ddm_exp("setPowerManagement called\n", 1,2,3,4,5);
    	return IO_R_UNSUPPORTED;
}

#if	AMD_ENABLE_GET_SET

- (IOReturn)setIntValues:(unsigned *)parameterArray
	forParameter:(IOParameterName)parameterName
	count:(unsigned int)count
{
    	if(strcmp(parameterName, AMD_AUTOSENSE) == 0) {
		if (count != 1) {
			return IO_R_INVALID_ARG;
		}
		autoSenseEnable = (parameterArray[0] ? 1 : 0);
		IOLog("%s: autoSense %s\n", [self name], 
			(autoSenseEnable ? "Enabled" : "Disabled"));
		return IO_R_SUCCESS;
	}
	else if(strcmp(parameterName, AMD_CMD_QUEUE) == 0) {
		if (count != 1) {
			return IO_R_INVALID_ARG;
		}
		cmdQueueEnable = (parameterArray[0] ? 1 : 0);
		IOLog("%s: cmdQueue %s\n", [self name], 
			(cmdQueueEnable ? "Enabled" : "Disabled"));
		return IO_R_SUCCESS;
	}
	else if(strcmp(parameterName, AMD_SYNC) == 0) {
		if (count != 1) {
			return IO_R_INVALID_ARG;
		}
		syncModeEnable = (parameterArray[0] ? 1 : 0);
		IOLog("%s: syncMode %s\n", [self name], 
			(syncModeEnable ? "Enabled" : "Disabled"));
		return IO_R_SUCCESS;
	}
	else if(strcmp(parameterName, AMD_FAST_SCSI) == 0) {
		if (count != 1) {
			return IO_R_INVALID_ARG;
		}
		fastModeEnable = (parameterArray[0] ? 1 : 0);
		IOLog("%s: fastMode %s\n", [self name], 
			(fastModeEnable ? "Enabled" : "Disabled"));
		return IO_R_SUCCESS;
	}
	else if(strcmp(parameterName, AMD_RESET_TARGETS) == 0) {
		int target;
		perTargetData *perTargetPtr;
		
		if (count != 0) {
			return IO_R_INVALID_ARG;
		}
		
		/*
		 * Re-enable sync and command queueing. The
		 * disable bits persist after a reset.
		 */
		for(target=0; target<SCSI_NTARGETS; target++) {
			perTargetPtr = &perTarget[target];
			perTargetPtr->cmdQueueDisable = 0;
			perTargetPtr->syncDisable = 0;
			perTargetPtr->maxQueue = 0;
		}
		IOLog("%s: Per Target disable flags cleared\n", [self name]);
		return IO_R_SUCCESS;
	}
	else {
		return [super setIntValues:parameterArray
	    		forParameter:parameterName
	    		count:count];
	}
}

- (IOReturn)getIntValues		: (unsigned *)parameterArray
			   forParameter : (IOParameterName)parameterName
			          count : (unsigned *)count;	// in/out
{	
	if(strcmp(parameterName, AMD_AUTOSENSE) == 0) {
		if(*count != 1) {
			return IO_R_INVALID_ARG;
		}
		parameterArray[0] = autoSenseEnable;
		return IO_R_SUCCESS;
	}
	else if(strcmp(parameterName, AMD_CMD_QUEUE) == 0) {
		if(*count != 1) {
			return IO_R_INVALID_ARG;
		}
		parameterArray[0] = cmdQueueEnable;
		return IO_R_SUCCESS;
	}
	else if(strcmp(parameterName, AMD_SYNC) == 0) {
		if(*count != 1) {
			return IO_R_INVALID_ARG;
		}
		parameterArray[0] = syncModeEnable;
		return IO_R_SUCCESS;
	}
	else if(strcmp(parameterName, AMD_FAST_SCSI) == 0) {
		if(*count != 1) {
			return IO_R_INVALID_ARG;
		}
		parameterArray[0] = fastModeEnable;
		return IO_R_SUCCESS;
	}
	else {
		return [super getIntValues : parameterArray
			forParameter : parameterName
			count : count];

	}
}					


#endif	AMD_ENABLE_GET_SET

@end	/* AMD_SCSI */

@implementation AMD_SCSI(Private)

/*
 * Private chip- and architecture-independent methods.
 */

/*
 * Pass one commandBuf to the I/O thread; wait for completion. 
 * Normal completion status is in cmdBuf->scsiReq->driverStatus; 
 * a non-zero return from this function indicates a Mach IPC error.
 *
 * This method allocates and frees cmdBuf->cmdLock.
 */
- (IOReturn)executeCmdBuf : (commandBuf *)cmdBuf
{
	msg_header_t msg = cmdMessageTemplate;
	kern_return_t krtn;
	IOReturn rtn = IO_R_SUCCESS;
	
	cmdBuf->cmdPendingSense = NULL;
	cmdBuf->active = 0;
	cmdBuf->cmdLock = [[NXConditionLock alloc] initWith:CMD_PENDING];
	[commandLock lock];
	queue_enter(&commandQ, cmdBuf, commandBuf *, link);
	[commandLock unlock];
	
	/*
	 * Create a Mach message and send it in order to wake up the 
	 * I/O thread.
	 */
	msg.msg_remote_port = interruptPortKern;
	krtn = msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0);
	if(krtn) {
		IOLog("%s: msg_send_from_kernel() returned %d\n", 
			[self name], krtn);
		rtn = IO_R_IPC_FAILURE;
		goto out;
	}
	
	/*
	 * Wait for I/O complete.
	 */
	ddm_exp("executeCmdBuf: waiting for completion on cmdBuf 0x%x\n",
		cmdBuf, 2,3,4,5);
	[cmdBuf->cmdLock lockWhen:CMD_COMPLETE];
out:
	[cmdBuf->cmdLock free];
	return rtn;
}

/*
 * Abort all active and disconnected commands with specified status. No 
 * hardware action. Currently used by threadResetBus and during processing
 * of a CO_Abort command.
 */
- (void)swAbort : (sc_status_t)status
{
	commandBuf *cmdBuf;
	commandBuf *nextCmdBuf;
	
	ddm_thr("swAbort\n", 1,2,3,4,5);
	if(activeCmd) {
		activeCmd->scsiReq->driverStatus = status;
		[self ioComplete:activeCmd];
		activeCmd = NULL;
	}
	cmdBuf = (commandBuf *)queue_first(&disconnectQ);
	while(!queue_end(&disconnectQ, (queue_entry_t)cmdBuf)) {
		queue_remove(&disconnectQ, cmdBuf, commandBuf *, link);
		nextCmdBuf = (commandBuf *)
			queue_next(&cmdBuf->link);
		cmdBuf->scsiReq->driverStatus = status;
		[self ioComplete:cmdBuf];
		cmdBuf = nextCmdBuf;
	}
#ifdef	DEBUG
	/*
	 * activeArray "should be" empty...if not, make sure it is for debug.
	 */
	{
	    int target, lun;
	    int active;
	    
	    for(target=0; target<SCSI_NTARGETS; target++) {
		for(lun=0; lun<SCSI_NLUNS; lun++) {
		    active = activeArray[target][lun];
		    if(active) {
		    	IOLog("swAbort: activeArray[%d][%d] = %d\n",
			    target, lun, active);
			activeCount -= active;
			activeArray[target][lun] = 0;
		    }
		}
	    }
	    if(activeCount != 0) {
	    	IOLog("swAbort: activeCount = %d\n", activeCount);
		activeCount = 0;
	    }
	}
#endif	DEBUG
}

/*
 * Abort all active and disconnected commands with status SR_IOST_RESET.
 * Reset hardware and SCSI bus. If there is a command in pendingQ, start
 * it up.
 */
- (void)threadResetBus : (const char *)reason
{
	[self swAbort:SR_IOST_RESET];
	[self hwReset : reason];
	[self busFree];
}

/*
 * Commence processing of the specified command. 
 *
 * If activeCmd is non-NULL or cmdBufOK says we can't process this command,
 * we just enqueue the command on the end of pendingQ. 
 */
- (void)threadExecuteRequest : (commandBuf *)cmdBuf
{
	#if	DDM_DEBUG
	unsigned char target = cmdBuf->scsiReq->target;
	unsigned char lun = cmdBuf->scsiReq->lun;
	#endif	DDM_DEBUG
	
	if(activeCmd != NULL) {
		ddm_thr("threadExecuteRequest: ACTIVE; adding 0x%x to "
			"pendingQ\n", cmdBuf, 2,3,4,5);
		queue_enter(&pendingQ, cmdBuf, commandBuf *, link);
		return;
	}	
	else if([self cmdBufOK:cmdBuf] == NO) {
		ddm_thr("threadExecuteRequest: !cmdBufOK; adding 0x%x to "
			"pendingQ\n", cmdBuf, 2,3,4,5);
		queue_enter(&pendingQ, cmdBuf, commandBuf *, link);
		return;
	}

	ddm_thr("calling hwStart: cmdBuf 0x%x activeArray[%d][%d] = %d\n",
		cmdBuf, target, lun, activeArray[target][lun], 5);
		
	switch([self hwStart:cmdBuf]) {
	    case HWS_OK:		// cool
	    case HWS_BUSY:		// h/w can't take cmd now
	    	break;
	    case HWS_REJECT:		// hw ready for new cmd
		ddm_thr("threadExecuteRequest: calling busFree\n", 1,2,3,4,5);
		[self busFree];
	}
	
	ddm_thr("threadExecuteRequest(0x%x): DONE\n", cmdBuf, 2,3,4,5);
}

/*
 * Methods called by hardware-dependent modules.
 */

#if	TEST_QUEUE_FULL
int 	testQueueFull;
#endif	TEST_QUEUE_FULL

/*
 * Called when a transaction associated with cmdBuf is complete. Notify 
 * waiting thread. If cmdBuf->scsiReq exists (i.e., this is not a reset
 * or an abort), scsiReq->driverStatus must be valid. If cmdBuf is active,
 * caller must remove from activeCmd. We decrement activeArray[][] counter
 * if appropriate.
 */
- (void)ioComplete:(commandBuf *)cmdBuf
{
	ns_time_t 	currentTime;
	IOSCSIRequest 	*scsiReq = cmdBuf->scsiReq;
	int 		target;
	int 		lun;
	
	if(cmdBuf->cmdPendingSense != NULL) {
		/*
		 * This was an autosense request.
		 */
		
		commandBuf *origCmdBuf = cmdBuf->cmdPendingSense;
		esense_reply_t *alignedSense = cmdBuf->buffer;
		
		ASSERT(cmdBuf->scsiReq != NULL);
		ddm_thr("autosense buf 0x%x complete for cmd 0x%x sense "
			"key 0x%x\n",
			cmdBuf, origCmdBuf, alignedSense->er_sensekey, 4,5);
		if(cmdBuf->scsiReq->driverStatus == SR_IOST_GOOD) {
			/*
			 * Copy aligned sense data to caller's buffer.
			 */
			alignedSense = cmdBuf->buffer;
			origCmdBuf->scsiReq->senseData = *alignedSense;
			origCmdBuf->scsiReq->driverStatus = SR_IOST_CHKSV;
		}
		else {
			IOLog("AMD53C974: Autosense request for target %d"
				" FAILED (%s)\n",
				cmdBuf->scsiReq->target, 
				IOFindNameForValue(scsiReq->driverStatus, 
				    IOScStatusStrings));
			origCmdBuf->scsiReq->driverStatus = SR_IOST_CHKSNV;
		}
		
		/*
		 * Free all of the allocated memory associated with 
		 * this autosense request. 
		 */
		[self deactivateCmd:cmdBuf];
		IOFree(cmdBuf->scsiReq, sizeof(*cmdBuf->scsiReq));
		IOFree(cmdBuf->unalignedSense, 
			sizeof(esense_reply_t) + (2 * AMD_READ_START_ALIGN));
		IOFree(cmdBuf, sizeof(commandBuf));
		
		/*
		 * Now complete the I/O for the original commandBuf.
		 */
		[origCmdBuf->cmdLock lock];
		[origCmdBuf->cmdLock unlockWith:YES];
		return;
	}
	if(scsiReq != NULL) {
		IOGetTimestamp(&currentTime);
		scsiReq->totalTime = currentTime - cmdBuf->startTime;
		scsiReq->bytesTransferred = 
			scsiReq->maxTransfer - cmdBuf->currentByteCount;
			
		/*
		 * Catch bad SCSI status now.
		 */
		if(scsiReq->driverStatus == SR_IOST_GOOD) {
			#if	TEST_QUEUE_FULL
			if(testQueueFull && 
			   (activeArray[scsiReq->target][scsiReq->lun] > 1)) {
				scsiReq->scsiStatus = STAT_QUEUE_FULL;
				testQueueFull = 0;
			}
			#endif	TEST_QUEUE_FULL
			switch(scsiReq->scsiStatus) {
			    case STAT_GOOD:
				break;
			    case STAT_CHECK:
				if(autoSenseEnable &&
				   (scsiReq->cdb.cdb_opcode != C6OP_TESTRDY)) {
				    /*
				     * Generate an autosense request, enqueue
				     * on pendingQ. We skip this for Test 
				     * Unit Ready commands to avoid unnecessary
				     * Req Sense ops while polling removable
				     * media drives. 
				     */
				    [self generateAutoSense:cmdBuf];
				    if(cmdBuf->active) {
					[self deactivateCmd:cmdBuf];
				    }
				    return;
				}
				else {
				    scsiReq->driverStatus = SR_IOST_CHKSNV;
				}
				break;
				
			    case STAT_QUEUE_FULL:
			        /*
				 * Avoid notifying client of this condition;
				 * update perTarget.maxQueue and place this 
				 * request on pendingQ. We'll try this 
				 * again when we ioComplete at least one
				 * command in this target's queue.
				 */
				if(cmdBuf->queueTag == QUEUE_TAG_NONTAGGED) {
				    /*
				     * Huh? We're not doing command
				     * queueing...
				     */
				    scsiReq->driverStatus = SR_IOST_BADST;
				    break;
				}
				target = scsiReq->target;
				lun = scsiReq->lun;
				if(cmdBuf->active) {
				    [self deactivateCmd:cmdBuf];
				}
				perTarget[target].maxQueue = 
					activeArray[target][lun];
				ddm_thr("Target %d QUEUE FULL, maxQueue %d\n",
					target, perTarget[target].maxQueue,
					3,4,5);
				queue_enter(&pendingQ, cmdBuf, commandBuf *,
					link);
				return;
				
			    default:
				scsiReq->driverStatus = SR_IOST_BADST;
				break;
			}
		}
	}
	if(cmdBuf->active) {
		/*
		 * Note that the active flag is false for non-CO_Execute
		 * commands and commands aborted from pendingQ.
		 */
		[self deactivateCmd:cmdBuf];
	}
	
	#if	DDM_DEBUG
	{
		const char *status;
		unsigned moved;
		
		if(scsiReq != NULL) {
		    status = IOFindNameForValue(scsiReq->driverStatus, 
		    	IOScStatusStrings);
		    moved = scsiReq->bytesTransferred;
		}
		else {
		    status = "Complete";
		    moved = 0;
		}
		ddm_thr("ioComplete: cmdBuf 0x%x status %s bytesXfr 0x%x\n", 
			cmdBuf, status, moved,4,5);
	}
	#endif	DDM_DEBUG
	
	[cmdBuf->cmdLock lock];
	[cmdBuf->cmdLock unlockWith:YES];
}

/*
 * Generate autosense request for specified cmdBuf, place it 
 * at head of pendingQ.
 */
- (void)generateAutoSense : (commandBuf *)cmdBuf
{
	IOSCSIRequest 	*scsiReq = cmdBuf->scsiReq;
	commandBuf 	*senseCmdBuf;
	IOSCSIRequest 	*senseScsiReq;
	cdb_6_t		*cdbp;
	
	senseCmdBuf  = IOMalloc(sizeof(commandBuf));
	senseScsiReq = IOMalloc(sizeof(IOSCSIRequest));
	bzero(senseCmdBuf,  sizeof(commandBuf));
	bzero(senseScsiReq, sizeof(IOSCSIRequest));
	
	/*
	 * commandBuf fields....
	 */
	senseCmdBuf->cmdPendingSense = cmdBuf;
	senseCmdBuf->op              = CO_Execute;
	senseCmdBuf->scsiReq         = senseScsiReq;
	
	/*
	 * Get aligned sense buffer.
	 */
	senseCmdBuf->unalignedSense = IOMalloc(sizeof(esense_reply_t) + 
					(2 * AMD_READ_START_ALIGN));
	senseCmdBuf->buffer         = IOAlign(void *, 
					senseCmdBuf->unalignedSense,
					AMD_READ_START_ALIGN);
	senseCmdBuf->client         = IOVmTaskSelf();
	
	/* 
	 * Now IOSCSIRequest fields for request sense.
	 */
	senseScsiReq->target        = scsiReq->target;
	senseScsiReq->lun           = scsiReq->lun;
	senseScsiReq->read          = YES;
	senseScsiReq->maxTransfer   = sizeof(esense_reply_t);
	senseScsiReq->timeoutLength = 10;
	senseScsiReq->disconnect    = 0;
	
	cdbp 			    = &senseScsiReq->cdb.cdb_c6;
	cdbp->c6_opcode 	    = C6OP_REQSENSE;
	cdbp->c6_lun 		    = scsiReq->lun;
	cdbp->c6_len 		    = sizeof(esense_reply_t);
	senseScsiReq->driverStatus  = SR_IOST_INVALID;
	
	/*
	 * This goes at the head of pendingQ; hopefully it'll be the 
	 * next command out to the bus.
	 */
	ddm_thr("generateAutoSense: autosense buf 0x%x enqueued for "
		"cmdBuf 0x%x\n", senseCmdBuf, cmdBuf, 3,4,5);
	queue_enter_first(&pendingQ, senseCmdBuf, commandBuf *, link);

}

/*
 * I/O associated with activeCmd has disconnected. Place it on disconnectQ
 * and enable another transaction.
 */ 
- (void)disconnect
{
	ddm_thr("DISCONNECT: cmdBuf 0x%x target %d lun %d tag %d\n",
		activeCmd, activeCmd->scsiReq->target,
		activeCmd->scsiReq->lun, activeCmd->queueTag, 5);
	queue_enter(&disconnectQ,
		activeCmd,
		commandBuf *,
		link);
	#if	DDM_DEBUG
	if((activeCmd->currentByteCount != activeCmd->scsiReq->maxTransfer) &&
	   (activeCmd->currentByteCount != 0)) {
	   	ddm_thr("disconnect after partial DMA (max 0x%d curr 0x%x)\n",
			activeCmd->scsiReq->maxTransfer, 
			activeCmd->currentByteCount, 3,4,5);
	}
	#endif	DDM_DEBUG
	/*
	 * Record this time so that activeCmd can be billed for
	 * disconnect latency at reselect time.
	 */
	IOGetTimestamp(&activeCmd->disconnectTime);
	activeCmd = NULL;
	/* [self busFree]; NO! fsm does this at end of hwInterrupt! */
}

/*
 * Specified target, lun, and queueTag is trying to reselect. If we have 
 * a commandBuf for this TLQ nexus on disconnectQ, remove it, make it the
 * current activeCmd, and return YES. Else return NO.
 * A value of zero for queueTag indicates a nontagged command (zero is never
 * used as the queue tag value for a tagged command).
 */
- (BOOL)reselect : (unsigned char)target_id
	     lun : (unsigned char)lun
        queueTag : (unsigned char)queueTag
{
	commandBuf *cmdBuf;
	IOSCSIRequest *scsiReq;
	ns_time_t currentTime;
	
	cmdBuf = (commandBuf *)queue_first(&disconnectQ);
	while(!queue_end(&disconnectQ, (queue_t)cmdBuf)) {
	
		scsiReq = cmdBuf->scsiReq;
		if((scsiReq->target == target_id) && 
		   (scsiReq->lun == lun) &&
		   (cmdBuf->queueTag == queueTag)) {
			ddm_thr("RESELECT: target %d lun %d tag %d FOUND;"
				"cmdBuf 0x%x\n",
				target_id, lun, queueTag, cmdBuf, 5);
			queue_remove(&disconnectQ,
				cmdBuf,
				commandBuf *,
				link);
			activeCmd = cmdBuf;
			
			/*
			 * Bill this operation for latency time.
			 */
			IOGetTimestamp(&currentTime);
			scsiReq->latentTime += 
				(currentTime - activeCmd->disconnectTime);
			return(YES);
		}
		/*
		 * Try next element in queue.
		 */
		cmdBuf = (commandBuf *)cmdBuf->link.next;
	}

	/*
	 * Hmm...this is not good! We don't want to talk to this target.
	 */	
	IOLog("%s: ILLEGAL RESELECT target %d lun %d tag %d\n",
				[self name], target_id, lun, queueTag);
	return(NO);
}

/*
 * Determine if activeArray[][], maxQueue, cmdQueueEnable, and a 
 * command's target and lun show that it's OK to start processing cmdBuf.
 * Returns YES if copacetic.
 */
- (BOOL)cmdBufOK : (commandBuf *)cmdBuf
{
	IOSCSIRequest 	*scsiReq = cmdBuf->scsiReq;
	unsigned 	target   = scsiReq->target;
	unsigned 	lun      = scsiReq->lun;
	unsigned char	active;
	unsigned char	maxQ;
	
	active = activeArray[target][lun];
	if(active == 0) {
		/*
		 * Trivial quiescent case, always OK.
		 */
		return YES;
	}
	if((cmdQueueEnable == 0) ||
	   (perTarget[target].cmdQueueDisable)) {
		/*
		 * No command queueing (either globally or for this target),
		 * only one at a time.
		 */
		return NO;
	}
	maxQ = perTarget[target].maxQueue;
	if(maxQ == 0) {
		/*
		 * We don't know what the target's limit is; go for it.
		 */
		return YES;
	}
	if(active >= maxQ) {
		/*
		 * T/L's queue full; hold off.
		 */ 
		return NO;
	}	
	else {
		return YES;
	}
}

/*
 * The bus has gone free. Start up a command from pendingQ, if any, and
 * if allowed by cmdQueueEnable and activeArray[][].
 */
- (void)busFree
{
	commandBuf *cmdBuf;
	
	ASSERT(activeCmd == NULL);
	if(queue_empty(&pendingQ)) {
		ddm_thr("busFree: pendingQ empty\n", 1,2,3,4,5);
		return;
	}
	
	/*
	 * Attempt to find a commandBuf in pendingQ which we are in a position
	 * to process.
	 */
	cmdBuf = (commandBuf *)queue_first(&pendingQ);
	while(!queue_end(&pendingQ, (queue_entry_t)cmdBuf)) {
		if([self cmdBufOK:cmdBuf]) {
			queue_remove(&pendingQ, cmdBuf, commandBuf *, link);
			ddm_thr("busFree: starting pending cmd 0x%x\n", cmdBuf,
				2,3,4,5);
			[self threadExecuteRequest:cmdBuf];
			return;	
		}
		else {
			cmdBuf = (commandBuf *)queue_next(&cmdBuf->link);
		}
	}
	ddm_thr("busFree: pendingQ non-empty, no commands available\n", 
		1,2,3,4,5);
}

/*
 * Abort activeCmd (if any) and any disconnected I/Os (if any) and reset 
 * the bus due to gross hardware failure.
 * If activeCmd is valid, its scsiReq->driverStatus will be set to 'status'.
 */
- (void)hwAbort 		: (sc_status_t)status
		 	 reason : (const char *)reason
{
	if(activeCmd) {
		activeCmd->scsiReq->driverStatus = status;
		[self ioComplete:activeCmd];
		activeCmd = NULL;
	}
	[self logRegs];
	[self threadResetBus:reason];	
}

/*
 * Called by chip level to indicate that a command has gone out to the 
 * hardware.
 */
- (void)activateCommand : (commandBuf *)cmdBuf
{
	unsigned char target;
	unsigned char lun;
	
	/*
	 * Start timeout timer for this I/O. The timer request is cancelled
	 * in ioComplete.
	 */
	cmdBuf->timeoutPort = interruptPortKern;
	#if	LONG_TIMEOUT
	cmdBuf->scsiReq->timeoutLength = OUR_TIMEOUT;
	#endif	LONG_TIMEOUT
	IOScheduleFunc(AMDTimeout, cmdBuf, cmdBuf->scsiReq->timeoutLength);
	
	/*
	 * This is the only place where an activeArray[][] counter is 
	 * incremented (and, hence, the only place where cmdBuf->active is 
	 * set). The only other place activeCmd is set to non-NULL
	 * is in reselect:lun:queueTag.
	 */
	activeCmd = cmdBuf;
	target = cmdBuf->scsiReq->target;
	lun = cmdBuf->scsiReq->lun;
	activeArray[target][lun]++;
	activeCount++;
	cmdBuf->active = 1;

	/*
	 * Accumulate statistics.
	 */
	maxQueueLen = MAX(maxQueueLen, activeCount);
	queueLenTotal += activeCount;
	totalCommands++;
	ddm_thr("activateCommand: cmdBuf 0x%x target %d lun %d\n",
		cmdBuf, target, lun, 4,5);
}

/*
 * Remove specified cmdBuf from "active" status. Update activeArray,
 * activeCount, and unschedule pending timer.
 */
- (void)deactivateCmd : (commandBuf *)cmdBuf
{
	IOSCSIRequest *scsiReq = cmdBuf->scsiReq;
	int target, lun;
	
	ASSERT(scsiReq != NULL);
	target = scsiReq->target;
	lun = scsiReq->lun;
	ddm_thr("deactivate cmdBuf 0x%x target %d lun %d activeArray %d\n",
		cmdBuf, target, lun, activeArray[target][lun], 5);
	ASSERT(activeArray[target][lun] != 0);
	activeArray[target][lun]--;
	ASSERT(activeCount != 0);
	activeCount--;

	/*
	 * Cancel pending timeout request. Commands which timed out don't
	 * have a timer request pending anymore.
	 */
	if(scsiReq->driverStatus != SR_IOST_IOTO) {
		IOUnscheduleFunc(AMDTimeout, cmdBuf);
	}
	cmdBuf->active = 0;
}

@end	/* AMD_SCSI(Private) */

/*
 *  Handle timeouts.  We just send a timeout message to the I/O thread
 *  so it wakes up.
 */
static void AMDTimeout(void *arg)
{
	commandBuf 	*cmdBuf = arg;
	msg_header_t	msg = timeoutMsgTemplate;

	ddm_err("AMDTimeout: cmdBuf 0x%x target %d\n", cmdBuf,
		cmdBuf->scsiReq->target, 3,4,5);
	if(!cmdBuf->active) {
		/*
		 * Should never happen...
		 */
		IOLog("AMD53C974: Timeout on non-active cmdBuf\n");
		return;
	}
	msg.msg_remote_port = cmdBuf->timeoutPort;
	IOLog("AMD53C974: SCSI Timeout\n");
	(void) msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0);
}

