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
	IOPCIConfigSpace pciConfig;
	unsigned int deviceID;
	IOPCIDeviceDescription *pciDevice;

	if (![deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
		return NO;
	}

	pciDevice = (IOPCIDeviceDescription *)deviceDescription;
	[pciDevice getPCIConfigSpace:&pciConfig];

	deviceID = (pciConfig.DeviceID << 16) | pciConfig.VendorID;

	/* Check for supported AIC-7xxx devices */
	switch (deviceID) {
		case AIC_7850_DEVICE_ID:
		case AIC_7860_DEVICE_ID:
		case AIC_7870_DEVICE_ID:
		case AIC_7871_DEVICE_ID:
		case AIC_7872_DEVICE_ID:
		case AIC_7873_DEVICE_ID:
		case AIC_7874_DEVICE_ID:
		case AIC_7880_DEVICE_ID:
		case AIC_7881_DEVICE_ID:
		case AIC_7882_DEVICE_ID:
		case AIC_7883_DEVICE_ID:
		case AIC_7884_DEVICE_ID:
		case AIC_7895_DEVICE_ID:
			return YES;
		default:
			return NO;
	}
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
