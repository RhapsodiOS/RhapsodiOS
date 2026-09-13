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
#import <objc/Object.h>
#import <kernserv/queue.h>
#import <kernserv/prototypes.h>
#import <driverkit/return.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/scsiTypes.h>
#import <mach/message.h>
#import <mach/port.h>
#import <mach/mach_interface.h>
#import <machkit/NXLock.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/IOSCSIController.h>
#import "AIC6X60Controller.h"
#import "AIC6X60Types.h"
#import "AIC6X60Thread.h"
#import "HIM6X60.h"

extern unsigned int page_size;
extern int HIM6X60FindAdapter(unsigned int ioBase);
extern int HIM6X60GetConfiguration(struct _HACB *hacb);
extern int HIM6X60IRQ(struct _HACB *hacb);

static AIC6X60ThreadMsg HIMMessageTemplate = {
	{
		0,
		1,
		sizeof(AIC6X60ThreadMsg),
		MSG_TYPE_NORMAL,
		PORT_NULL,
		PORT_NULL,
		HIM_MESSAGE_ID
	},
	0,
	0
};

@interface AIC6X60(PrivateMethods)
- (BOOL)probeAtPortBase		: (IOEISAPortAddress)portBase;
- (IOReturn)executeCmdBuf	: (AIC6X60CommandBuf *)cmdBuf;
- (int)initDMA;
@end


@implementation AIC6X60

+ (BOOL)probe:deviceDescription
{
	AIC6X60		*aic = [self alloc];
	IORange		ioPort;

	if ([deviceDescription numPortRanges] < 1) {
		IOLog("AIC6X60: can't determine port base!\n");
		[aic free];
		return NO;
	}
	ioPort = [deviceDescription portRangeList][0];
	if (![aic probeAtPortBase:ioPort.start]) {
		IOLog("AIC6X60: can't find host adapter!\n");
		[aic free];
		return NO;
	}
	return ([aic initFromDeviceDescription:deviceDescription] ? YES : NO);
}

- initFromDeviceDescription:deviceDescription
{
	unsigned	lun;
	kern_return_t	krtn;

	if ([super initFromDeviceDescription:deviceDescription] == nil)
		return [super free];

	hacb.length = AIC_HACB_SIZE;
	if (HIM6X60GetConfiguration(&hacb) != 1) {
		IOLog("HIM6X60GetConfiguration failure\n");
		return nil;
	}
	IOLog("AIC 6X60 Driver -- Version 3.2.3\n");
	if ([self initDMA] != 0)
		return [super free];
	if ([deviceDescription numInterrupts] < 1) {
		IOLog("AIC6X60: No IRQ level specified \n");
		return [super free];
	}
	hacb.IRQ = [deviceDescription interrupt];
	IOLog("AIC6X60: controller at irq %d\n", hacb.IRQ);
	hacb.ac |= 0x01;
	hacb.ownID = 7;
	hacb.ac |= 0x80;
	queue_init(&pendingQ);
	currentDMABuffer = 0;
	hacb.controllerId = self;
	numFreeScbs = AIC_SCB_COUNT;
	hacb.ac |= 0x04;
	if (!HIM6X60Initialize(&hacb)) {
		IOLog("AIC6X60: couldn't initialize HIM!\n");
		return [super free];
	}
	IOLog("Resetting SCSI Bus...\n");
	IOSleep(10000);
	[self resetStats];
	for (lun = 0; lun <= 7; lun++)
		[self reserveTarget:hacb.ownID lun:lun forOwner:self];
	[self enableAllInterrupts];
	interruptPortKern = IOConvertPort([self interruptPort],
		IO_KernelIOTask, IO_Kernel);
	ioThreadRunning = YES;
	krtn = port_set_backlog(task_self(), [self interruptPort],
		PORT_BACKLOG_MAX);
	if (krtn) {
		IOLog("%s: error %d on port_set_backlog()\n",
			[self name], krtn);
	}
	[self registerDevice];
	return self;
}

- (unsigned)maxTransfer
{
	if (dmaEnabled)
		return 0x10000;
	return page_size;
}

- (void)getDMAAlignment:(IODMAAlignment *)alignment
{
	if (dmaEnabled) {
		alignment->readStart = 1;
		alignment->writeStart = 1;
		alignment->readLength = 1;
		alignment->writeLength = 1;
	} else {
		alignment->readStart = 0x2000;
		alignment->writeStart = 0x2000;
		alignment->readLength = 0x2000;
		alignment->writeLength = 0x2000;
	}
}

- free
{
	AIC6X60CommandBuf cmdBuf;

	if (ioThreadRunning) {
		cmdBuf.op = AO_Abort;
		[self executeCmdBuf:&cmdBuf];
	}
	return [super free];
}

- (sc_status_t)executeRequest : (IOSCSIRequest *)scsiReq
		       buffer : (void *)buffer
		       client : (vm_task_t)client
{
	AIC6X60CommandBuf cmdBuf;

	cmdBuf.op = AO_Execute;
	cmdBuf.scsiReq = scsiReq;
	cmdBuf.buffer = buffer;
	cmdBuf.client = client;
	[self executeCmdBuf:&cmdBuf];
	return cmdBuf.result;
}

- (sc_status_t)resetSCSIBus
{
	AIC6X60CommandBuf cmdBuf;

	cmdBuf.op = AO_Reset;
	[self executeCmdBuf:&cmdBuf];
	return cmdBuf.result;
}

- (void)interruptOccurred
{
	struct _SCB	*scb;
	struct _SCB	*last;
	AIC6X60CommandBuf *cmdBuf;

	HIM6X60IRQ(&hacb);
	scb = &him_scb[0];
	last = &him_scb[AIC_SCB_COUNT - 1];
	while (scb <= last) {
		if (scb->completed && scb->in_use)
			[self commandCompleted:scb reason:CS_Complete];
		scb++;
	}
	while (!queue_empty(&pendingQ) && numFreeScbs != 0) {
		cmdBuf = (AIC6X60CommandBuf *)queue_first(&pendingQ);
		queue_remove(&pendingQ, cmdBuf, AIC6X60CommandBuf *, link);
		[self threadExecuteRequest:cmdBuf];
	}
}

- (void)otherOccurred:(int)id
{
	IOLog("AIC:otherOccurred: Received unknown message ID: %d\n", id);
	IOSleep(1000);
}

- (void)receiveMsg
{
	AIC6X60ThreadMsg	msg;
	msg_return_t		kr;
	AIC6X60CommandBuf	*cmdBuf;

	msg.header.msg_size = sizeof(msg);
	msg.header.msg_local_port = [self interruptPort];
	kr = msg_receive(&msg.header, RCV_TIMEOUT, 0);
	if (kr) {
		IOLog("AIC:receiveMsg: msg_receive returns %d\n", kr);
		return;
	}
	if (msg.header.msg_id != HIM_MESSAGE_ID)
		IOLog("AIC:receiveMsg: message->msg_id != HIM_MESSAGE_ID\n");
	cmdBuf = msg.cmdBuf;
	switch (cmdBuf->op) {
	case AO_Execute:
		[self threadExecuteRequest:cmdBuf];
		break;
	case AO_Reset:
		[self threadResetBus:cmdBuf];
		break;
	case AO_Abort:
		[cmdBuf->cmdLock lock];
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
		IOExitThread();
		break;
	default:
		IOLog("%s: Weird message; op %d\n", [self name], cmdBuf->op);
		break;
	}
}

- (void)timeoutOccurred
{
	struct _SCB	*scb;
	struct _SCB	*last;
	BOOL		timedOut;

	timedOut = NO;
	IOSleep(1000);
	scb = &him_scb[0];
	last = &him_scb[AIC_SCB_COUNT - 1];
	while (scb <= last) {
		if (scb->timedOut)
			timedOut = YES;
		scb++;
	}
	if (timedOut)
		[self threadResetBus:NULL];
}

- (void)commandRequestOccurred
{
}

@end

@implementation AIC6X60(PrivateMethods)

- (BOOL)probeAtPortBase:(IOEISAPortAddress)portBase
{
	bzero(&hacb, AIC_HACB_SIZE);
	hacb.baseAddress = portBase;
	if (!HIM6X60FindAdapter(portBase))
		return NO;
	return YES;
}

- (IOReturn)executeCmdBuf:(AIC6X60CommandBuf *)cmdBuf
{
	AIC6X60ThreadMsg	msg = HIMMessageTemplate;
	kern_return_t		krtn;
	IOReturn		rtn = IO_R_SUCCESS;

	cmdBuf->cmdLock = [[NXConditionLock alloc] initWith:CMD_PENDING];
	msg.header.msg_remote_port = interruptPortKern;
	msg.cmdBuf = cmdBuf;
	krtn = msg_send_from_kernel(&msg.header, MSG_OPTION_NONE, 0);
	if (krtn) {
		IOLog("%s: msg_send_from_kernel() returned %d\n",
			[self name], krtn);
		rtn = IO_R_IPC_FAILURE;
	} else {
		[cmdBuf->cmdLock lockWhen:CMD_COMPLETE];
	}
	[cmdBuf->cmdLock free];
	return rtn;
}

- (int)initDMA
{
	id		desc;
	unsigned int	chan;
	IOReturn	rtn;
	IOEISADMATransferWidth width;

	desc = [self deviceDescription];
	if ([desc numChannels] == 0) {
		hacb.ac &= ~0x40;
		hacb.dmaChannel = 0;
		dmaEnabled = NO;
		IOLog("AIC6X60: Not using DMA\n");
		return 0;
	}
	hacb.ac |= 0x40;
	dmaEnabled = YES;
	chan = [desc channel];
	hacb.dmaChannel = 0;
	IOLog("AIC6X60: controller at DMA channel %d\n", chan);
	rtn = [self setDMATiming:IO_Compatible forChannel:0];
	if (rtn) {
		IOLog("AIC: DMA setDMATiming FAILED! (%s)\n",
			[self stringFromReturn:rtn]);
		return 1;
	}
	rtn = [self setTransferMode:IO_Demand forChannel:0];
	if (rtn) {
		IOLog("AIC: DMA transferMode FAILED! (%s)\n",
			[self stringFromReturn:rtn]);
		return 1;
	}
	width = hacb.dmaChannel ? IO_16BitByteCount : IO_8Bit;
	rtn = [self setDMATransferWidth:width forChannel:0];
	if (rtn) {
		IOLog("AIC: DMA transferWidth FAILED! (%s)\n",
			[self stringFromReturn:rtn]);
		return 1;
	}
	rtn = [self enableChannel:0];
	if (rtn) {
		IOLog("AIC: DMA Channel enable FAILED! (%s)\n",
			[self stringFromReturn:rtn]);
		return 1;
	}
	return 0;
}

@end
