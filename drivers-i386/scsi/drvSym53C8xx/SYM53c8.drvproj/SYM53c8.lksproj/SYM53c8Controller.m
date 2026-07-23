/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * Symbios Logic NCR 53C8xx SCSI controller driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from BusLogic driver.
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
#import <mach/message.h>
#import <mach/port.h>
#import <mach/mach_interface.h>
#import <machkit/NXLock.h>
#import <kernserv/ns_timer.h>
#import <driverkit/i386/ioPorts.h>

#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDevice.h>
#import <driverkit/IOSCSIController.h>
#import "SYM53c8Controller.h"
#import "SYM53c8Types.h"
#import "SYM53c8Inline.h"
#import "SYM53c8Thread.h"

extern unsigned ffs(unsigned mask);
extern BOOL sym_reset_chip(IOEISAPortAddress portBase);
extern BOOL sym_init_chip(IOEISAPortAddress portBase, struct sym_config *config);

/*
 * Template for command message sent to the I/O thread.
 */
static msg_header_t SYMMessageTemplate = {
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
@interface SYM53c8Controller(PrivateMethods)
- (BOOL) probeChip;
- (IOReturn)executeCmdBuf	: (SYMCommandBuf *)cmdBuf;
@end


@implementation SYM53c8Controller

/*
 *  Probe, configure chip, and init new instance.
 */
+ (BOOL)probe:deviceDescription
{
	SYM53c8Controller	*sym = [self alloc];
	IORange			ioPort;
	IOPCIDevice		*pciDev;

	ddm_init("SYM53c8Controller probe\n", 1,2,3,4,5);
	sym->ioThreadRunning = NO;

	/*
	 * This is a PCI device, get the PCI device object
	 */
	pciDev = [deviceDescription directDevice];
	if (!pciDev) {
		IOLog("SYM53c8Controller: No PCI device!\n");
		[sym free];
		return NO;
	}
	sym->pciDevice = pciDev;

	/*
	 *  Check that we have some IO Ports assigned
	 */
	if ([deviceDescription numPortRanges] < 1) {
		IOLog("SYM53c8Controller: can't determine port base!\n");
	    	[sym free];
		return NO;
	}
	ioPort = [deviceDescription portRangeList][0];
	sym->ioBase = ioPort.start;
	sym->config.io_base = ioPort.start;
	sym->config.io_size = ioPort.size;

	if (![sym probeChip]) {
		IOLog("Symbios 53C8xx Not Found at port 0x%x\n", ioPort.start);
	    	[sym free];
		return NO;
	}
	return ([sym initFromDeviceDescription:deviceDescription] ? YES : NO);
}

- initFromDeviceDescription:deviceDescription
{
	unsigned Lun;
	kern_return_t krtn;
	int i;

	ddm_init("SYM53c8Controller initFromDeviceDescription\n", 1,2,3,4,5);

	queue_init(&outstandingQ);
	queue_init(&pendingQ);
	queue_init(&commandQ);
	commandLock      = [[NXLock alloc] init];
	outstandingCount = 0;
	numFreeCcbs      = SYM_QUEUE_SIZE;

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
	 *  Check the irq we just found against what's in our
	 *  device description.  If they don't match, print a nasty warning
	 *  message and fail.
	 */
	if ([deviceDescription numInterrupts] < 1) {
		IOLog("SYM53c8Controller: No IRQ assigned!\n");
		return [self free];
	}

	config.irq = [deviceDescription interrupt];

	/*
	 * Allocate CCB's from low 16 M of memory (for DMA compatibility)
	 */
	symCcb = IOMallocLow(sizeof(struct ccb) * SYM_QUEUE_SIZE);
	if (!symCcb) {
		IOLog("SYM53c8Controller: couldn't allocate CCBs!\n");
		return [self free];
	}

	/*
	 * Initialize CCB pool
	 */
	for (i = 0; i < SYM_QUEUE_SIZE; i++) {
		symCcb[i].in_use = FALSE;
	}

	/*
	 * Allocate SCRIPTS program area
	 */
	scriptsVirt = (unsigned int *)IOMallocLow(4096);
	if (!scriptsVirt) {
		IOLog("SYM53c8Controller: couldn't allocate SCRIPTS!\n");
		return [self free];
	}
	scriptsPhys = (unsigned int *)kvtophys((vm_offset_t)scriptsVirt);

	/*
	 * Initialize the chip
	 */
	if (!sym_init_chip(ioBase, &config)) {
		IOLog("SYM53c8Controller: couldn't initialize chip!\n");
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
 *  Maximum transfer size based on scatter/gather list
 */
- (unsigned)maxTransfer
{
	return (SYM_SG_COUNT - 1) * PAGE_SIZE;
}

/*
 * kill I/O thread, free up local dynamically allocated resources,
 * then have super release resources.
 */
- free
{
	SYMCommandBuf cmdBuf;

	if(ioThreadRunning) {
		cmdBuf.op = SO_Abort;
		[self executeCmdBuf:&cmdBuf];
	}
	if(symCcb) {
		IOFreeLow(symCcb, sizeof(struct ccb) * SYM_QUEUE_SIZE);
	}
	if(scriptsVirt) {
		IOFreeLow(scriptsVirt, 4096);
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
	SYMCommandBuf cmdBuf;

	ddm_exp("executeRequest: cmdBuf 0x%x\n", &cmdBuf, 2,3,4,5);

	cmdBuf.op      = SO_Execute;
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
	SYMCommandBuf cmdBuf;

	ddm_exp("resetSCSIBus: cmdBuf 0x%x\n", &cmdBuf, 2,3,4,5);

	cmdBuf.op = SO_Reset;
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
	unsigned char	istat, dstat, sist0, sist1;

	ddm_thr("interruptOccurred\n", 1,2,3,4,5);

	istat = sym_get_istat(ioBase);

	/* Check for DMA interrupt */
	if (istat & SYM_ISTAT_DIP) {
		dstat = sym_get_dstat(ioBase);

		if (dstat & SYM_DSTAT_SIR) {
			/* SCRIPTS interrupt - command completed */
			[self handleScriptsInterrupt];
		}
		else if (dstat & (SYM_DSTAT_IID | SYM_DSTAT_ABRT | SYM_DSTAT_BF)) {
			/* DMA error */
			IOLog("%s: DMA error, DSTAT=0x%x\n", [self name], dstat);
			[self handleDMAError:dstat];
		}
	}

	/* Check for SCSI interrupt */
	if (istat & SYM_ISTAT_SIP) {
		sist0 = sym_get_sist0(ioBase);
		sist1 = sym_get_sist1(ioBase);

		if (sist0 & SYM_SIST0_RST) {
			IOLog("%s: SCSI bus reset detected\n", [self name]);
			[self handleBusReset];
		}
		else if (sist0 & SYM_SIST0_STO) {
			[self handleSelectionTimeout];
		}
		else if (sist0 & SYM_SIST0_PAR) {
			IOLog("%s: Parity error\n", [self name]);
			[self handleParityError];
		}
		else {
			IOLog("%s: SCSI interrupt, SIST0=0x%x SIST1=0x%x\n",
				[self name], sist0, sist1);
		}
	}

	/*
	 * Handle possible pending commands
	 */
	[self runPendingCommands];

	/*
	 * Process possible entries waiting in commandQ.
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
 * message.
 */
- (void)timeoutOccurred
{
	struct ccb	*ccb, *nextCcb;
	ns_time_t	now;
	queue_head_t	*queue;
	BOOL		ccbTimedOut = NO;
	SYMCommandBuf	*cmdBuf;
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
 * subsequent interrupts.
 *
 * This is called either as a result of an IO_COMMAND_MSG message being
 * received by the I/O thread, or upon completion of interrupt handling. In
 * either case, it runs in the context of the I/O thread.
 */
- (void)commandRequestOccurred
{
	SYMCommandBuf *cmdBuf;

	ddm_thr("commandRequestOccurred: top\n", 1,2,3,4,5);
	[commandLock lock];
	while(!queue_empty(&commandQ)) {
		cmdBuf = (SYMCommandBuf *) queue_first(&commandQ);
		queue_remove(&commandQ, cmdBuf, SYMCommandBuf *, link);
		[commandLock unlock];
		switch(cmdBuf->op) {
		    case SO_Reset:
		    	[self threadResetBus:cmdBuf];
			break;

		    case SO_Abort:
			/*
			 * First notify caller of completion, then
			 * self-terminate.
			 */
			[cmdBuf->cmdLock lock];
			[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
			IOExitThread();
			/* not reached */

		    case SO_Execute:
		    	if([self threadExecuteRequest:cmdBuf]) {
				/*
				 * No more CCBs available. Abort this entire
				 * method. Enqueue this request on the head
				 * of commandQ for future processing.
				 */
				[commandLock lock];
				queue_enter_first(&commandQ, cmdBuf,
					SYMCommandBuf *, link);
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


@end	/* methods declared in SYM53c8Controller.h */

@implementation SYM53c8Controller(PrivateMethods)

- (BOOL) probeChip
{
	unsigned char	istat;

	ddm_init("SYM53c8Controller probeChip\n", 1,2,3,4,5);

	/* Try to read ISTAT register */
	istat = sym_get_istat(ioBase);

	/* Reset the chip */
	sym_soft_reset(ioBase);

	/* Try reading again */
	istat = sym_get_istat(ioBase);
	if (istat == 0xFF) {
		ddm_init("  ..chip not present\n", 1,2,3,4,5);
		return FALSE;
	}

	/* Set default configuration */
	config.scsi_id = 7;		/* Default adapter ID */
	config.max_target = 7;		/* Standard SCSI */
	config.max_lun = 8;

	IOLog("Symbios 53C8xx at port 0x%x\n", ioBase);
	return TRUE;
}

/*
 * Pass one SYMCommandBuf to the I/O thread; wait for completion.
 * Normal completion status is in cmdBuf->status; a non-zero return
 * from this function indicates a Mach IPC error.
 *
 * This method allocates and frees cmdBuf->cmdLock.
 */
- (IOReturn)executeCmdBuf : (SYMCommandBuf *)cmdBuf
{
	msg_header_t msg = SYMMessageTemplate;
	kern_return_t krtn;
	IOReturn rtn = IO_R_SUCCESS;

	cmdBuf->cmdLock = [[NXConditionLock alloc] initWith:CMD_PENDING];
	[commandLock lock];
	queue_enter(&commandQ, cmdBuf, SYMCommandBuf *, link);
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

@end	/* SYM53c8Controller(PrivateMethods) */


