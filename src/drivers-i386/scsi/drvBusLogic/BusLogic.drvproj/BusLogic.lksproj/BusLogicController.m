/*
 * Copyright (c) 1996 NeXT Software, Inc.
 *
 * BusLogic SCSI controller driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from Adaptec 1542 driver.
 */

#import <sys/types.h>
#import <string.h>
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
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/IOSCSIController.h>
#import "BusLogicController.h"
#import "BusLogicTypes.h"
#import "BusLogicInline.h"
#import "BusLogicThread.h"

extern unsigned ffs(unsigned mask);
extern BOOL blc_reset_board(IOEISAPortAddress portBase);
extern BOOL blc_probe_cmd(IOEISAPortAddress portBase, unsigned char cmd,
			 unsigned char *dataOut, int dataOutLen,
			 unsigned char *dataIn, int dataInLen,
			 BOOL expectResponse);
extern BOOL blc_setup_mb_area(IOEISAPortAddress portBase,
			     struct bl_mb_area *mbArea,
			     struct ccb *ccbArray,
			     struct ccb **freeList);

/*
 * PCI base address register decoding.
 */
#define PCI_NUM_BASE_ADDRESS	6
#define PCI_BASE_IO_BIT		0x01
#define PCI_BASE_IO(value)	((value) & 0xfffffffc)

static BOOL parseConfigSpace(id deviceDescription,
			     const char *title,
			     unsigned regSize,
			     IOEISAPortAddress *baseAddr);

/*
 * Template for command message sent to the I/O thread.
 */
static msg_header_t BLMessageTemplate = {
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
@interface BLCController(PrivateMethods)
- (BOOL) probeAtPortBase 	: (IOEISAPortAddress) portBase;
- (IOReturn)executeCmdBuf	: (BLCommandBuf *)cmdBuf;
@end


@implementation BLCController

/*
 *  Probe, configure board, and init new instance.
 */
+ (BOOL)probe:deviceDescription
{
	BLCController	*bl = [self alloc];
	id		configTable;
	const char	*cardType;
	IOEISAPortAddress portBase;

	ddm_init("BLCController probe\n", 1,2,3,4,5);
	bl->ioThreadRunning = NO;

	/*
	 *  Which bus is the board on? This decides where the I/O port base
	 *  comes from and whether we have to arbitrate for the machine's DMA
	 *  controller.
	 */
	configTable = [deviceDescription configTable];
	cardType = [configTable valueForStringKey:"Card Type"];
	if (cardType == NULL) {
		bl->busType = BL_BUS_ISA;
	}
	else {
		if (strcmp(cardType, "EISA") == 0)
			bl->busType = BL_BUS_EISA;
		else if (strcmp(cardType, "PCI") == 0)
			bl->busType = BL_BUS_PCI;
		else if (strcmp(cardType, "VL") == 0)
			bl->busType = BL_BUS_VL;
		else
			bl->busType = BL_BUS_ISA;
		[configTable freeString:cardType];
	}

	if (bl->busType == BL_BUS_PCI) {
		/*
		 *  A PCI board's port base and IRQ live in config space, and
		 *  the device description has to be retweezed to match.
		 */
		if (!parseConfigSpace(deviceDescription, "BusLogic",
				      BL_PCI_REGISTER_SPACE, &portBase)) {
			[bl free];
			return NO;
		}
	}
	else {
		/*
		 *  Check that we have some IO Ports assigned, and probe using
		 *  the first IO Port.
		 */
		if ([deviceDescription numPortRanges] < 1) {
			IOLog("BLCController: can't determine port base!\n");
			[bl free];
			return NO;
		}
		portBase = [deviceDescription portRangeList][0].start;
	}

	/*
	 *  -probeAtPortBase returns TRUE if there's a BusLogic Controller
	 *  present.
	 */
	if (![bl probeAtPortBase:portBase]) {
		IOLog("BusLogic Not Found at port 0x%x\n", portBase);
	    	[bl free];
		return NO;
	}
	return ([bl initFromDeviceDescription:deviceDescription] ? YES : NO);
}

- initFromDeviceDescription:deviceDescription
{
	unsigned Lun;
	kern_return_t krtn;

	ddm_init("BLCController initFromDeviceDescription\n", 1,2,3,4,5);

	queue_init(&outstandingQ);
	queue_init(&pendingQ);
	queue_init(&commandQ);
	commandLock      = [[NXLock alloc] init];
	outstandingCount = 0;
	dmaLockCount     = 0;
	numFreeCcbs      = BL_QUEUE_SIZE;

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
	if (config.dma_channel != 0xff) {
		if ([deviceDescription numChannels] < 1 ||
		    [deviceDescription channel] != config.dma_channel) {
			IOLog("BLCController: Actual DMA Channel (%d) doesn't match "
			      "configured value (%d)!\n", config.dma_channel,
			      ([deviceDescription numChannels] ?
				[deviceDescription channel] : 0));
			return [self free];
		}

		/* Set transfer mode 3 and enable the adapter's DMA channel. */
		if ([self setTransferMode:IO_Cascade forChannel:0] != IO_R_SUCCESS ||
		    [self enableChannel:0] != IO_R_SUCCESS) {
			IOLog("BLCController: couldn't init DMA!\n");
			return [self free];
		}
	}

	/* PCI assigns its IRQ in config space and needs no legacy check. */
	if (busType != BL_BUS_PCI &&
	    ([deviceDescription numInterrupts] < 1 ||
	     [deviceDescription interrupt] != config.irq)) {
		IOLog("BLCController: Actual IRQ (%d) doesn't match "
		      "configured value (%d)!\n", config.irq,
		      ([deviceDescription numInterrupts] ?
		[deviceDescription interrupt] : 0));
		return [self free];
	}

	/*
	 * Allocate Mailboxes and CCB's from low 16 M of memory.
	 */
	blMbArea = IOMallocLow(sizeof(struct bl_mb_area));
	blCcb = IOMallocLow(sizeof(struct ccb) * BL_QUEUE_SIZE);

	/*
	 *  Initialize driver data structures: set up the mailbox in/out area,
	 *  and initialize the CCB queues.
	 *
	 *  Note that if we fail, the call to [super free] will release (and
	 *  disable) our resources (IRQ, DMA channel, portRanges).
	 */
	if (!blc_setup_mb_area(ioBase, blMbArea, blCcb,
			       &blCcbFreeList)) {
		IOLog("BLCController: couldn't set up mailbox area!\n");
		return [self free];
	}

	[self resetStats];
	{
		id configTable = [deviceDescription configTable];
		const char *shareIRQ = [configTable valueForStringKey:"Share IRQ Levels"];
		levelIRQ = shareIRQ != NULL && strcmp(shareIRQ, "YES") == 0;
		if (shareIRQ != NULL)
			[configTable freeString:shareIRQ];
	}

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
 *  Use (BL_SG_COUNT - 1) since requests (the first
 *  and the last) can cross page boundaries.
 */
- (unsigned)maxTransfer
{
	return (BL_SG_COUNT - 1) * PAGE_SIZE;
}

/*
 * Number of targets this board can address, established by -probeAtPortBase:.
 */
- (int)numberOfTargets
{
	return targetsPerBus;
}

/*
 * kill I/O thread, free up local dynamically allocated resources,
 * then have super release resources.
 */
- free
{
	BLCommandBuf cmdBuf;

	if(ioThreadRunning) {
		cmdBuf.op = BO_Abort;
		[self executeCmdBuf:&cmdBuf];
	}
	if(blMbArea) {
		IOFreeLow(blMbArea, sizeof(struct bl_mb_area));
	}
	if(blCcb) {
		IOFreeLow(blCcb, sizeof(struct ccb) * BL_QUEUE_SIZE);
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
	BLCommandBuf cmdBuf;

	ddm_exp("executeRequest: cmdBuf 0x%x\n", &cmdBuf, 2,3,4,5);

	cmdBuf.op      = BO_Execute;
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
	BLCommandBuf cmdBuf;

	ddm_exp("resetSCSIBus: cmdBuf 0x%x\n", &cmdBuf, 2,3,4,5);

	cmdBuf.op = BO_Reset;
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
	bl_intr_reg_t	intr;
	bl_mb_t		*mb;
	int		i;

	ddm_thr("interruptOccurred\n", 1,2,3,4,5);

	intr = bl_get_intr(ioBase);
	bl_clr_intr(ioBase);

	if (intr.mb_in_full) {
		mb = blMbArea->next_in;
		for (i = 0; i < BL_MB_CNT; i++) {
			if (mb->mb_stat == BL_MB_IN_FREE)
				break;
			ccb = (struct ccb *)bl_get_32(mb->ccb_addr);
			mb->mb_stat = BL_MB_IN_FREE;
			mb++;
			if (mb > blMbArea->in_end)
				mb = blMbArea->in_start;

			queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
			ASSERT(outstandingCount != 0);
			outstandingCount--;
			[self commandCompleted:ccb reason:CS_Complete];
		}
		blMbArea->next_in = mb;
		[self runPendingCommands];
		[self commandRequestOccurred];
	}

	if (levelIRQ)
		[self enableAllInterrupts];
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
 * message. We send these messages ourself from blcTimeout() in
 * BusLogicThread.m.
 */
- (void)timeoutOccurred
{
	struct ccb	*ccb, *nextCcb;
	ns_time_t	now;
	queue_head_t	*queue;
	BOOL		ccbTimedOut = NO;
	BLCommandBuf	*cmdBuf;
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
	BLCommandBuf *cmdBuf;

	ddm_thr("commandRequestOccurred: top\n", 1,2,3,4,5);
	[commandLock lock];
	while(!queue_empty(&commandQ)) {
		cmdBuf = (BLCommandBuf *) queue_first(&commandQ);
		queue_remove(&commandQ, cmdBuf, BLCommandBuf *, link);
		[commandLock unlock];
		switch(cmdBuf->op) {
		    case BO_Reset:
		    	[self threadResetBus:cmdBuf];
			break;

		    case BO_Abort:
			/*
			 * First notify caller of completion, then
			 * self-terminate.
			 */
			[cmdBuf->cmdLock lock];
			[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
			IOExitThread();
			/* not reached */

		    case BO_Execute:
		    	if([self threadExecuteRequest:cmdBuf]) {
				/*
				 * No more CCBs available. Abort this entire
				 * method. Enqueue this request on the head
				 * of commandQ for future processing.
				 */
				[commandLock lock];
				queue_enter_first(&commandQ, cmdBuf,
					BLCommandBuf *, link);
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


@end	/* methods declared in BusLogicController.h */

@implementation BLCController(PrivateMethods)

- (BOOL) probeAtPortBase:(IOEISAPortAddress) portBase
{
	unsigned char	inquirySetup[14];

	ddm_init("BLCController probeAtPortBase\n", 1,2,3,4,5);

	ioBase = portBase;
	blc_reset_board(ioBase);

	if (!blc_probe_cmd(ioBase, BL_CMD_GET_CONFIG, NULL, 0,
			  (unsigned char *)&config, sizeof(config), TRUE)) {
		ddm_init("  ..get config command failed\n", 1,2,3,4,5);
		return FALSE;
	}

	config.irq = ffs((unsigned int)config.irq) + 8;
	config.dma_channel = ffs((unsigned int)config.dma_channel) - 1;

	bzero(inquirySetup, sizeof(inquirySetup));
	inquirySetup[0] = sizeof(inquirySetup);
	if (!blc_probe_cmd(ioBase, BL_CMD_INQUIRY_SETUP_EXT,
			  inquirySetup, 1, inquirySetup,
			  sizeof(inquirySetup), TRUE)) {
		bzero(inquirySetup, sizeof(inquirySetup));
		inquirySetup[0] = 4;
		if (!blc_probe_cmd(ioBase, BL_CMD_INQUIRY_SETUP_EXT,
				  inquirySetup, 1, inquirySetup,
				  sizeof(inquirySetup), TRUE))
			return FALSE;
	}

	blBoardId = inquirySetup[0];
	if (blBoardId != 65)
		config.dma_channel = 0xff;
	targetsPerBus = (inquirySetup[13] & 1) ? 16 : 8;

	IOLog("BusLogic controller at port 0x%x\n", portBase);
	IOLog("BusLogic: %d Targets per Bus; Host ID = %d\n",
		targetsPerBus, config.scsi_id & 0xf);

	return TRUE;

}

/*
 * Pass one BLCommandBuf to the I/O thread; wait for completion.
 * Normal completion status is in cmdBuf->status; a non-zero return
 * from this function indicates a Mach IPC error.
 *
 * This method allocates and frees cmdBuf->cmdLock.
 */
- (IOReturn)executeCmdBuf : (BLCommandBuf *)cmdBuf
{
	msg_header_t msg = BLMessageTemplate;
	kern_return_t krtn;
	IOReturn rtn = IO_R_SUCCESS;

	cmdBuf->cmdLock = [[NXConditionLock alloc] initWith:CMD_PENDING];
	[commandLock lock];
	queue_enter(&commandQ, cmdBuf, BLCommandBuf *, link);
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

@end	/* BLCController(PrivateMethods) */


/*
 * Get I/O port range and IRQ from PCI config space. Set appropriate
 * values in deviceDescription. Returns base address in *baseAddr.
 * Returns YES if successful, else NO.
 */
static BOOL parseConfigSpace(
	id deviceDescription,
	const char *title,
	unsigned regSize,		/* in bytes */
	IOEISAPortAddress *baseAddr)	/* RETURNED */
{
	IOPCIConfigSpace	configSpace;
	IORange			portRange;
	unsigned		*basePtr = 0;
	int			irq;
	int			i;
	BOOL			foundBase = NO;
	IOReturn		irtn;

	/*
	 * First get our configSpace register set.
	 */
	bzero(&configSpace, sizeof(IOPCIConfigSpace));
	if(irtn = [IODirectDevice getPCIConfigSpace:&configSpace
			withDeviceDescription:deviceDescription]) {
		IOLog("%s: Can\'t get configSpace (%s); ABORTING\n",
			title, [IODirectDevice stringFromReturn:irtn]);
		return NO;
	}
	basePtr = configSpace.BaseAddress;
	irq     = configSpace.InterruptLine;
	if((basePtr[0] == 0) || (irq == 0)) {
		IOLog("%s: Bogus config info (IRQ %d, Base 0x%x)\n",
			title, irq, (unsigned)basePtr);
		return NO;
	}

	/*
	 * Scan all 6 base address registers, make sure there is exactly one
	 * I/O address.
	 */
	for(i=0; i<PCI_NUM_BASE_ADDRESS; i++) {
	    if(basePtr[i] & PCI_BASE_IO_BIT) {
		if(foundBase) {
		    IOLog("%s: Multiple I/O Port Bases Found\n", title);
		    return NO;
		}
		foundBase = YES;
		portRange.start = PCI_BASE_IO(basePtr[i]);
	    }
	}
	if(!foundBase) {
	    	IOLog("%s: No I/O Port Base Found\n", title);
		return NO;
	}
	portRange.size = regSize;
	*baseAddr = portRange.start;

	/*
	 * OK, retweeze our device description.
	 */
	irtn = [deviceDescription setInterruptList:&irq num:1];
	if(irtn) {
		IOLog("%s: Can\'t set interruptList to IRQ %d (%s)\n",
			title, irq, [IODirectDevice stringFromReturn:irtn]);
		return NO;
	}
	irtn = [deviceDescription setPortRangeList:&portRange num:1];
	if(irtn) {
		IOLog("%s: Can\'t set portRangeList to port 0x%x (%s)\n",
			title, portRange.start,
			[IODirectDevice stringFromReturn:irtn]);
		return NO;
	}
	return YES;
}
