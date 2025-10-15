/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * DPTSCSIDriver.m - DPT EATA ISA/EISA SCSI controller driver.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#import "DPTSCSIDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <machkit/NXLock.h>
#import <kernserv/prototypes.h>
#import <string.h>

@implementation DPTSCSIDriver

/*
 * Probe for DPT EATA hardware.
 */
+ (BOOL)probe:deviceDescription
{
	unsigned int ioBase;
	unsigned char status;
	int i;

	/* Get I/O base from device description */
	if ([deviceDescription respondsTo:@selector(portRangeList)]) {
		IORange *range = [deviceDescription portRangeList];
		if (range) {
			ioBase = range->start;
		} else {
			return NO;
		}
	} else {
		return NO;
	}

	/* Check for EATA controller presence */
	/* Read status register */
	status = inb(ioBase + EATA_STATUS);

	/* Controller should not be busy initially */
	if (status & EATA_STAT_BUSY) {
		/* Wait a bit and retry */
		IOSleep(100);
		status = inb(ioBase + EATA_STATUS);
		if (status & EATA_STAT_BUSY) {
			return NO;
		}
	}

	/* Try to read configuration */
	outb(ioBase + EATA_CMD, EATA_CMD_READ_CONFIG);

	/* Wait for command to complete */
	for (i = 0; i < 1000; i++) {
		IODelay(10);
		status = inb(ioBase + EATA_STATUS);
		if (!(status & EATA_STAT_BUSY)) {
			break;
		}
	}

	if (status & EATA_STAT_BUSY) {
		return NO;
	}

	/* Read first 4 bytes to check signature */
	unsigned char sig[4];
	sig[0] = inb(ioBase + EATA_DATA);
	sig[1] = inb(ioBase + EATA_DATA);
	sig[2] = inb(ioBase + EATA_DATA);
	sig[3] = inb(ioBase + EATA_DATA);

	/* Check for "EATA" signature */
	if (sig[0] == 'E' && sig[1] == 'A' && sig[2] == 'T' && sig[3] == 'A') {
		return YES;
	}

	return NO;
}

/*
 * Initialize from device description.
 */
- initFromDeviceDescription:deviceDescription
{
	IOReturn result;

	if ([super initFromDeviceDescription:deviceDescription] == nil) {
		return [self free];
	}

	/* Get I/O base address */
	if ([deviceDescription respondsTo:@selector(portRangeList)]) {
		IORange *range = [deviceDescription portRangeList];
		if (range) {
			ioBase = range->start;
		} else {
			return [self free];
		}
	} else {
		return [self free];
	}

	/* Get DMA channel */
	if ([deviceDescription respondsTo:@selector(channelList)]) {
		unsigned int channel = [deviceDescription channelList];
		dmaChannel = channel;
	} else {
		dmaChannel = 5;  /* Default */
	}

	/* Get IRQ level */
	if ([deviceDescription respondsTo:@selector(interrupt)]) {
		irqLevel = [deviceDescription interrupt];
	} else {
		irqLevel = 11;  /* Default */
	}

	/* Initialize controller */
	if ([self eataInitController] != IO_R_SUCCESS) {
		IOLog("%s: Controller initialization failed\n", [self name]);
		return [self free];
	}

	/* Allocate resources */
	if ([self eataAllocateResources] != IO_R_SUCCESS) {
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
	return (EATA_SG_COUNT * PAGE_SIZE);
}

/*
 * Free driver resources.
 */
- free
{
	[self eataFreeResources];

	if (commandLock) {
		[commandLock free];
		commandLock = nil;
	}

	return [super free];
}

/*
 * Interrupt handler.
 * Based on Linux eata.c interrupt handling
 */
- (void)interruptOccurred
{
	unsigned char status, auxStatus;
	struct eata_cp *cp;
	unsigned int cpAddr;

	/* Check auxiliary status register */
	auxStatus = inb(ioBase + REG_AUX_STATUS);

	if (!(auxStatus & AUX_IRQ)) {
		/* Not our interrupt */
		return;
	}

	/* Check main status register */
	status = inb(ioBase + REG_STATUS);

	if (status & STAT_IRQ) {
		/* Read CP address from address registers (low to high) */
		cpAddr = inb(ioBase + REG_LOW);
		cpAddr |= (unsigned int)inb(ioBase + REG_LM) << 8;
		cpAddr |= (unsigned int)inb(ioBase + REG_MID) << 16;
		cpAddr |= (unsigned int)inb(ioBase + REG_MSB) << 24;

		/* Validate CP address is in our array */
		if (cpAddr >= (unsigned int)cpArray &&
		    cpAddr < (unsigned int)&cpArray[DPT_NUM_CPS]) {
			int cpIndex = (cpAddr - (unsigned int)cpArray) / sizeof(struct eata_cp);
			if (cpIndex >= 0 && cpIndex < DPT_NUM_CPS) {
				cp = &cpArray[cpIndex];
				if (cp->in_use) {
					[self processCmdComplete:cp];
				}
			}
		}
	}

	/* Clear interrupt by reading status */
	(void)inb(ioBase + REG_STATUS);
}

- (void)interruptOccurredAt:(int)localNum
{
	[self interruptOccurred];
}

- (void)otherOccurred:(int)id
{
	/* Handle other notifications */
}

- (void)receiveMsg
{
	/* Handle messages */
	[self interruptOccurred];
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
	DPTSCSIDriverCommandBuf *cmdBuf;
	IOReturn result;

	cmdBuf = (DPTSCSIDriverCommandBuf *)IOMalloc(sizeof(DPTSCSIDriverCommandBuf));
	if (cmdBuf == NULL) {
		return SR_IOST_MEMALL;
	}

	cmdBuf->scsiReq = scsiReq;
	cmdBuf->buffer = buffer;
	cmdBuf->client = client;
	cmdBuf->cp = NULL;

	result = [self executeCmdBuf:cmdBuf];

	if (result != IO_R_SUCCESS) {
		IOFree(cmdBuf, sizeof(DPTSCSIDriverCommandBuf));
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

	result = [self eataResetBus];

	return (result == IO_R_SUCCESS) ? SR_IOST_GOOD : SR_IOST_HW;
}

@end
