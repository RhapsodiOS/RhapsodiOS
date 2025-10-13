/*
 * Copyright (c) 1992-1998 NeXT Software, Inc.
 *
 * Adaptec AIC-6X60 SCSI controller driver.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created from Adaptec 1542B driver.
 */

#import <sys/types.h>
#import <bsd/sys/param.h>
#import <objc/Object.h>
#import <kernserv/queue.h>
#import <kernserv/prototypes.h>
#import <driverkit/return.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/scsiTypes.h>
#import <bsd/dev/scsireg.h>
#import	"scsivar.h"
#import <mach/message.h>
#import <mach/port.h>
#import <mach/mach_interface.h>
#import <machkit/NXLock.h>
#import <kernserv/ns_timer.h>
#import <driverkit/i386/ioPorts.h>

#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/IOSCSIController.h>
#import "AIC6X60Controller.h"
#import "AIC6X60Types.h"
#import "AIC6X60Inline.h"
#import "AIC6X60Thread.h"

extern unsigned ffs(unsigned mask);

/*
 * Template for command message sent to the I/O thread.
 */
static msg_header_t AIC6X60MessageTemplate = {
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
 * Private methods implemented in this file.
 */
@interface AIC6X60Controller(PrivateMethods)
- (BOOL) probeAtPortBase 	: (IOEISAPortAddress) portBase;
- (IOReturn)executeCmdBuf	: (AIC6X60CommandBuf *)cmdBuf;
@end


@implementation AIC6X60Controller

/*
 *  Probe, configure board, and init new instance.
 */
+ (BOOL)probe:deviceDescription
{
	AIC6X60Controller	*aic = [self alloc];
	IORange		ioPort;

	ddm_init("AIC6X60Controller probe\n", 1,2,3,4,5);
	aic->ioThreadRunning = NO;

	/*
	 *  Check that we have some IO Ports assigned, and probe using the
	 *  first IO Port.
	 *  -probeAtPortBase returns TRUE if there's an AIC Controller present.
	 */
	if ([deviceDescription numPortRanges] < 1) {
		IOLog("AIC6X60Controller: can't determine port base!\n");
	    	[aic free];
		return NO;
	}
	ioPort = [deviceDescription portRangeList][0];
	if (![aic probeAtPortBase:ioPort.start]) {
		IOLog("Adaptec6x60 Not Found at port 0x%x\n", ioPort.start);
	    	[aic free];
		return NO;
	}
	return ([aic initFromDeviceDescription:deviceDescription] ? YES : NO);
}

- initFromDeviceDescription:deviceDescription
{
	unsigned Lun;
	kern_return_t krtn;

	ddm_init("AIC6X60Controller initFromDeviceDescription\n", 1,2,3,4,5);

	queue_init(&outstandingQ);
	queue_init(&pendingQ);
	queue_init(&commandQ);
	commandLock      = [[NXLock alloc] init];
	outstandingCount = 0;
	dmaLockCount     = 0;
	numFreeCcbs      = AIC_QUEUE_SIZE;

	/*
	 * Note the I/O thread provided by IOSCSIController is running
	 * upon return from the following method.
	 */
	if ([super initFromDeviceDescription:deviceDescription] == nil)
		return [self free];
	interruptPortKern = IOConvertPort([self interruptPort],
		IO_KernelIOTask,
		IO_Kernel);
	ioThreadRunning = YES;

	/*
	 *  Check the channel and irq we just found against what's in our
	 *  device description.  If they don't match, print a nasty warning
	 *  message and fail.
	 */
	if ([deviceDescription numInterrupts] < 1 ||
	    [deviceDescription interrupt] != config.irq) {
		IOLog("AIC6X60Controller: Actual IRQ (%d) doesn't match "
		      "configured value (%d)!\n", config.irq,
		      ([deviceDescription numInterrupts] ?
		      	[deviceDescription interrupt] : 0));
		return [self free];
	}

	/*
	 * Allocate Mailboxes and CCB's from low 16 M of memory.
	 */
	aicMbArea = IOMallocLow(sizeof(struct aic_mb_area));
	aicCcb = IOMallocLow(sizeof(struct ccb) * AIC_QUEUE_SIZE);

	/*
	 *  Initialize driver data structures: set up the mailbox in/out area,
	 *  and initialize the CCB queues.
	 *
	 *  Note that if we fail, the call to [super free] will release (and
	 *  disable) our resources (IRQ, DMA channel, portRanges).
	 */
	if (!aic_setup_mb_area(ioBase, aicMbArea, aicCcb)) {
		IOLog("AIC6X60Controller: couldn't set up mailbox area!\n");
		return [self free];
	}

	[self resetStats];

	/*
	 * Reserve our target, enable interrupts, and go.
	 */
	for(Lun=0; Lun<SCSI_NLUNS; Lun++) {
		[self reserveTarget:config.scsi_id lun:Lun forOwner:self];
	}

	[self enableAllInterrupts];	/* turn on interrupts */

	/*
	 * Set the port queue length to the maximum size.
	 */
	krtn = port_set_backlog(task_self(), [self interruptPort],
		PORT_BACKLOG_MAX);
	if(krtn) {
		IOLog("%s: error %d on port_set_backlog()\n",
			[self name], krtn);
		/* Oh well... */
	}
	[self resetSCSIBus];
	[self registerDevice];		/* this is the last thing we do! */

	return self;
}

/*
 *  This is slightly incorrect, since we can actually handle more if some of
 *  the entries in the scatter/gather list can be more than PAGE_SIZE.  In
 *  practice, tho, they're never bigger, so we'll make this our max size.
 *  Use (AIC_SG_COUNT - 1) since requests (the first
 *  and the last) can cross page boundaries.
 */
- (unsigned)maxTransfer
{
	return (AIC_SG_COUNT - 1) * PAGE_SIZE;
}

/*
 * kill I/O thread, free up local dynamically allocated resources,
 * then have super release resources.
 */
- free
{
	AIC6X60CommandBuf cmdBuf;

	if(ioThreadRunning) {
		cmdBuf.op = AO_Abort;
		[self executeCmdBuf:&cmdBuf];
	}
	if(aicMbArea) {
		IOFreeLow(aicMbArea, sizeof(struct aic_mb_area));
	}
	if(aicCcb) {
		IOFreeLow(aicCcb, sizeof(struct ccb) * AIC_QUEUE_SIZE);
	}
	if(commandLock) {
		[commandLock free];
	}
	return [super free];
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
	AIC6X60CommandBuf cmdBuf;

	ddm_exp("executeRequest: cmdBuf 0x%x\n", &cmdBuf, 2,3,4,5);

	cmdBuf.op      = AO_Execute;
	cmdBuf.scsiReq = scsiReq;
	cmdBuf.buffer  = buffer;
	cmdBuf.client  = client;

	[self executeCmdBuf:&cmdBuf];

	ddm_exp("executeRequest: cmdBuf 0x%x complete; result %d\n",
		&cmdBuf, cmdBuf.result, 3,4,5);
	return cmdBuf.result;
}


/*
 *  Reset the SCSI bus. All the work is done by the I/O thread.
 */
- (sc_status_t)resetSCSIBus
{
	AIC6X60CommandBuf cmdBuf;

	ddm_exp("resetSCSIBus: cmdBuf 0x%x\n", &cmdBuf, 2,3,4,5);

	cmdBuf.op = AO_Reset;
	[self executeCmdBuf:&cmdBuf];
	return cmdBuf.result;
}
/*
 * The following 6 methods are all called from the I/O thread in
 * IODirectDevice.
 */

/*
 * Called from the I/O thread when it receives an interrupt message.
 */
- (void)interruptOccurred
{
	struct ccb	*ccb;
	aic_intr_reg_t	intr;
	aic_mb_t	*mb;
	int		i;

	ddm_thr("interruptOccurred\n", 1,2,3,4,5);

	intr = aic_get_intr(ioBase);
	aic_clr_intr(ioBase);

	if (!intr.mb_in_full)
		return;

	/*
	 * Find all ccb's which the controller has marked completed
	 * and commandComplete: them.
	 */
	mb = aicMbArea->mb_in;
	for (i = 0; i < AIC_MB_CNT; i++, mb++) {
		if (mb->mb_stat != AIC_MB_IN_FREE) {

			/*
			 * FIXME - need IOVirtualFromPhysical(); assume for
			 * now that we can access all physical addresses.
			 */
			ccb = (struct ccb *)aic_get_24(mb->ccb_addr);
			mb->mb_stat = AIC_MB_IN_FREE;
			queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
			ASSERT(outstandingCount != 0);
			outstandingCount--;

			[self commandCompleted:ccb reason:CS_Complete];
		}
	}

	/*
	 * Handle possible pending commands (now that we've dequeued at least
	 * one CCB).
	 */
	[self runPendingCommands];

	/*
	 * One more thing - since we probably just freed up at least one
	 * ccb, process possible entries waiting in commandQ.
	 */
	[self commandRequestOccurred];
	ddm_thr("interruptOccurred: DONE\n", 1,2,3,4,5);
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
 * Called from the I/O thread when it receives a timeout
 * message. We send these messages ourself from aicTimeout() in
 * AIC6X60Thread.m.
 */
- (void)timeoutOccurred
{
	struct ccb	*ccb, *nextCcb;
	ns_time_t	now;
	queue_head_t	*queue;
	BOOL		ccbTimedOut = NO;
	AIC6X60CommandBuf	*cmdBuf;
	IOSCSIRequest	*scsiReq;

	ddm_thr("timeoutOccurred\n", 1,2,3,4,5);

	IOGetTimestamp(&now);

	/*
	 *  Scan the list of outstanding and pending commands, and time
	 *  out any ones whose time is past.
	 */

	for (queue = &outstandingQ; queue != &pendingQ; queue = &pendingQ) {

	    ccb = (struct ccb *) queue_first(&outstandingQ);
	    while (!queue_end(&outstandingQ, (queue_entry_t) ccb)) {
	        ns_time_t	expire;

		cmdBuf  = ccb->cmdBuf;
		scsiReq = cmdBuf->scsiReq;
		expire = ccb->startTime +
		    1000000000ULL *
		    	(unsigned long long)scsiReq->timeoutLength;
	        if (now >= expire) {
			/*
			 *  Remove ccb from the oustanding queue and
			 *  complete it.
			 */
			nextCcb = (struct ccb *) queue_next(&ccb->ccbQ);
			queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
			if(queue == &outstandingQ) {
				ASSERT(outstandingCount != 0);
				outstandingCount--;
			}
			[self commandCompleted:ccb reason:CS_Timeout];
			ccb = nextCcb;
			ccbTimedOut = YES;
		}
		else {
			ccb = (struct ccb *) queue_next(&ccb->ccbQ);
		}
	    }
	}

	/*
	 * Reset bus. This also completes all I/Os in outstandingQ with
	 * status CS_Reset.
	 */
	if(ccbTimedOut) {
		[self threadResetBus:NULL];
	}
	ddm_thr("timeoutOccurred: DONE\n", 1,2,3,4,5);
}

/*
 * Process all commands in commandQ. If we run out of ccb's during this
 * method, we abort, leaving commands enqueued; these will be handled after
 * subqueuent interrupts.
 *
 * This is called either as a result of an IO_COMMAND_MSG message being
 * received by the I/O thread, or upon completion of interrupt handling. In
 * either case, it runs in the context of the I/O thread.
 */
- (void)commandRequestOccurred
{
	AIC6X60CommandBuf *cmdBuf;

	ddm_thr("commandRequestOccurred: top\n", 1,2,3,4,5);
	[commandLock lock];
	while(!queue_empty(&commandQ)) {
		cmdBuf = (AIC6X60CommandBuf *) queue_first(&commandQ);
		queue_remove(&commandQ, cmdBuf, AIC6X60CommandBuf *, link);
		[commandLock unlock];
		switch(cmdBuf->op) {
		    case AO_Reset:
		    	[self threadResetBus:cmdBuf];
			break;

		    case AO_Abort:
			/*
			 * First notify caller of completion, then
			 * self-terminate.
			 */
			[cmdBuf->cmdLock lock];
			[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
			IOExitThread();
			/* not reached */

		    case AO_Execute:
		    	if([self threadExecuteRequest:cmdBuf]) {
				/*
				 * No more CCBs available. Abort this entire
				 * method. Enqueue this request on the head
				 * of commandQ for future processing.
				 */
				[commandLock lock];
				queue_enter_first(&commandQ, cmdBuf,
					AIC6X60CommandBuf *, link);
				[commandLock unlock];
				ddm_thr("processCommandQ: no more ccbs; "
					"cmdBuf 0x%x\n", cmdBuf, 2,3,4,5);
				goto out;

			}
		}
		[commandLock lock];
	}
	[commandLock unlock];
out:
	ddm_thr("commandRequestOccurred: DONE\n", 1,2,3,4,5);
	return;
}


@end	/* methods declared in AIC6X60Controller.h */

@implementation AIC6X60Controller(PrivateMethods)

- (BOOL) probeAtPortBase:(IOEISAPortAddress) portBase
{
	aic_inquiry_t	inquiry;

	ddm_init("AIC6X60Controller probeAtPortBase\n", 1,2,3,4,5);

	ioBase = portBase;
	aic_reset_board(ioBase, aicBoardId);

	/*
	 *  Do an inquiry to find out the board id and other things that
	 *  we won't check.
	 */
	if (!aic_probe_cmd(ioBase, AIC_CMD_DO_INQUIRY, 0, 0,
	    (unsigned char *)&inquiry, sizeof(inquiry), TRUE)) {
	    	ddm_init("  ..inquiry command failed\n", 1,2,3,4,5);
		return FALSE;
	}

	aicBoardId = inquiry.board_id;

	if (aicBoardId != AIC_6X60) {
	    	ddm_init("..bogus board ID (0x%x)\n", aicBoardId,
				2,3,4,5);
		return FALSE;
	}

	/*
	 *  Attempt to read the configuration data from the board.
	 *  If this succeeds, then we have successfully probed.
	 */
	if (!aic_probe_cmd(ioBase, AIC_CMD_GET_CONFIG, 0, 0,
	                   (unsigned char *)&config, sizeof(config), TRUE)) {
	    	ddm_init("  ..get config command failed\n", 1,2,3,4,5);

	    	return FALSE;
	}

	/*
	 *  Decode the values in the config struct.
	 */
	config.irq = ffs((unsigned int) config.irq) + 8;

	IOLog("Adaptec6x60 at port 0x%x irq %d\n",
		portBase, config.irq);
	return TRUE;
}

/*
 * Pass one AIC6X60CommandBuf to the I/O thread; wait for completion.
 * Normal completion status is in cmdBuf->status; a non-zero return
 * from this function indicates a Mach IPC error.
 *
 * This method allocates and frees cmdBuf->cmdLock.
 */
- (IOReturn)executeCmdBuf : (AIC6X60CommandBuf *)cmdBuf
{
	msg_header_t msg = AIC6X60MessageTemplate;
	kern_return_t krtn;
	IOReturn rtn = IO_R_SUCCESS;

	cmdBuf->cmdLock = [[NXConditionLock alloc] initWith:CMD_PENDING];
	[commandLock lock];
	queue_enter(&commandQ, cmdBuf, AIC6X60CommandBuf *, link);
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
	ddm_exp("executeCmdBuf: cmdBuf 0x%x complete\n",
		cmdBuf, 2,3,4,5);
out:
	[cmdBuf->cmdLock free];
	return rtn;
}

@end	/* AIC6X60Controller(PrivateMethods) */



