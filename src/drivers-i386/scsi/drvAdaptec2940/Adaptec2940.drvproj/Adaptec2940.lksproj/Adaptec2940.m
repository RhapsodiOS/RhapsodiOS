/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Adaptec2940.m - Adaptec 2940 PCI SCSI controller driver.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#import "Adaptec2940.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <machkit/NXLock.h>
#import <kernserv/prototypes.h>
#import <string.h>

@implementation Adaptec2940

/*
 * Probe for Adaptec 2940 hardware.
 */
+ (BOOL)probe:deviceDescription
{
	id instance = [self alloc];
	return [instance initFromDeviceDescription:deviceDescription] != nil;
}

/*
 * Initialize from device description.
 */
- initFromDeviceDescription:deviceDescription
{
	IOPCIDeviceDescription *pciDevice;
	IOReturn result;

	if ([super initFromDeviceDescription:deviceDescription] == nil) {
		return [self free];
	}

	pciDevice = (IOPCIDeviceDescription *)deviceDescription;
	[pciDevice getPCIConfigSpace:&pciConfigSpace];

	/* Get I/O base address from PCI BAR0 */
	ioBase = pciConfigSpace.BaseAddress[0] & ~0x3;

	/* Initialize controller */
	if ([self aicInitController] != IO_R_SUCCESS) {
		IOLog("%s: Controller initialization failed\n", [self name]);
		return [self free];
	}

	/* Allocate resources */
	if ([self aicAllocateResources] != IO_R_SUCCESS) {
		IOLog("%s: Resource allocation failed\n", [self name]);
		return [self free];
	}

	/* Initialize queues */
	queue_init(&commandQ);
	queue_init(&outstandingQ);
	queue_init(&pendingQ);

	commandLock = [[NXLock alloc] init];
	outstandingCount = 0;
	ioThreadRunning = NO;

	/* Reset statistics */
	maxQueueLen = 0;
	queueLenTotal = 0;
	totalCommands = 0;
	dmaLockCount = 0;

	return self;
}

/*
 * Return maximum transfer size.
 */
- (unsigned)maxTransfer
{
	return (AIC_SG_COUNT * PAGE_SIZE);
}

- (int)numberOfTargets:(int)channel
{
	return *((unsigned char *)channelInfo[channel].hostInfo +
	         A2940_CHANNEL_TARGET_COUNT_OFFSET);
}

- (char)acquireSCSIBus:(unsigned int)channel owner:(id)owner
{
	Adaptec2940ChannelInfo *info = &channelInfo[channel];

	if (channel != 0 || info->owner != nil || info->hostInfo == nil) {
		return 0;
	}
	info->owner = owner;
	return 1;
}

- (void)releaseSCSIBus:(unsigned int)channel owner:(id)owner
{
	if (channelInfo[channel].owner == owner) {
		channelInfo[channel].owner = nil;
	} else {
		IOLog("%s releaseSCSIBus: Incorrect Owner\n", [self name]);
	}
}

- (int)scsiBusId:(unsigned int)channel
{
	return *((unsigned char *)channelInfo[channel].hostInfo +
	         A2940_CHANNEL_BUS_ID_OFFSET);
}

/*
 * Free driver resources.
 */
- free
{
	[self aicFreeResources];

	if (commandLock) {
		[commandLock free];
		commandLock = nil;
	}

	return [super free];
}

- (void)resetStats
{
	queueLenTotal = 0;
	maxQueueLen = 0;
	totalCommands = 0;
}

- (unsigned int)numQueueSamples
{
	return totalCommands;
}

- (unsigned int)sumQueueLengths
{
	return queueLenTotal;
}

- (unsigned int)maxQueueLength
{
	return maxQueueLen;
}

/*
 * Interrupt handler.
 */
- (void)interruptOccurred
{
	unsigned char intstat;
	struct scb *scb;

	intstat = inb(ioBase + AIC_INTSTAT);

	if (intstat & CMDCMPLT) {
		/* Command completed */
		while (inb(ioBase + AIC_QOUTCNT)) {
			unsigned char scb_index = inb(ioBase + AIC_QOUTFIFO);
			scb = &scbArray[scb_index];
			[self processCmdComplete:scb];
		}
	}

	if (intstat & SCSIINT) {
		/* SCSI interrupt - handle errors */
		unsigned char sstat1 = inb(ioBase + AIC_SSTAT1);
		if (sstat1 & SELTO) {
			IOLog("%s: Selection timeout\n", [self name]);
		}
		if (sstat1 & SCSIPERR) {
			IOLog("%s: SCSI parity error\n", [self name]);
		}
	}

	if (intstat & SEQINT) {
		/* Sequencer interrupt */
		IOLog("%s: Sequencer interrupt\n", [self name]);
	}

	/* Clear interrupts */
	outb(ioBase + AIC_CLRINT, 0xff);
}

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
	[super receiveMsg];
}

- (void)timeoutOccurred
{
	/* Handle timeouts */
	IOLog("%s: Command timeout\n", [self name]);
}

- (void)commandRequestOccurred
{
	[self runPendingCommands];
}

/*
 * Execute SCSI request.
 */
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
			buffer:(void *)buffer
			client:(vm_task_t)client
{
	Adaptec2940CommandBuf *cmdBuf;
	IOReturn result;

	cmdBuf = (Adaptec2940CommandBuf *)IOMalloc(sizeof(Adaptec2940CommandBuf));
	if (cmdBuf == NULL) {
		return SR_IOST_MEMALL;
	}

	cmdBuf->scsiReq = scsiReq;
	cmdBuf->buffer = buffer;
	cmdBuf->client = client;
	cmdBuf->scb = NULL;

	result = [self executeCmdBuf:cmdBuf];

	if (result != IO_R_SUCCESS) {
		IOFree(cmdBuf, sizeof(Adaptec2940CommandBuf));
		return SR_IOST_HW;
	}

	return SR_IOST_GOOD;
}

/*
 * Reset SCSI bus.
 */
- (sc_status_t)resetSCSIBus
{
	IOReturn result;

	result = [self aicResetBus];

	return (result == IO_R_SUCCESS) ? SR_IOST_GOOD : SR_IOST_HW;
}

@end
