/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATAController.h - class definition for the DPT EATA controller.
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc (instance_size 0x1ac,
 * superclass IODirectDevice).
 */


#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <driverkit/machine/directDevice.h>
#import <kernserv/queue.h>
#import "EATAControllerTypes.h"


@interface EATAController : IODirectDevice
{
	/*
	 * Hardware info. First declared ivar is at +0x128; IODirectDevice
	 * occupies the 0x128-byte prefix. instance_size is 0x1ac.
	 */
	struct {
		id		owner;
		char		present;
	} channelInfo[EATA_CHANNEL_COUNT];	/* +0x128, 3 × 8-byte slots */
	eata_config_t		config;		/* +0x140, 40 bytes */
	unsigned short		ioBase;		/* +0x168 */
	int			busType;	/* +0x16c */
	char			levelIRQ;	/* +0x170 */

	/*
	 * commandQ:	 EATACommandBuf's for the I/O thread. Enqueued by
	 *		 -executeCmdBuf:; dequeued in -commandRequestOccurred.
	 *
	 * outstandingQ: ccb's the controller is operating on.
	 *		 outstandingCount is the length.
	 */
	queue_head_t	commandQ;		/* +0x174 */
	queue_head_t	outstandingQ;		/* +0x17c */
	unsigned int	outstandingCount;	/* +0x184 */
	id		commandLock;		/* +0x188 NXLock */
	unsigned int	maxQueueLen;		/* +0x18c */
	unsigned int	queueLenTotal;		/* +0x190 */
	unsigned int	totalCommands;		/* +0x194 */
	unsigned int	configSgSize;		/* +0x198 */
	unsigned int	dmaLockCount;		/* +0x19c */
	struct ccb	*ccbFree;		/* +0x1a0 */
	int		interruptPortKern;	/* +0x1a4 */
	char		ioThreadRunning;	/* +0x1a8 */
}

/*
 * Standard IODirectDevice methods overridden here.
 */
+ (BOOL)probe:deviceDescription;
- initFromDeviceDescription	: deviceDescription;
- free;
- (void)interruptOccurred;
- (void)interruptOccurredAt:(int)localNum;
- (void)otherOccurred:(int)id;
- (void)receiveMsg;
- (void)timeoutOccurred;
- (void)commandRequestOccurred;

- (unsigned)numQueueSamples;
- (unsigned)sumQueueLengths;
- (unsigned)maxQueueLength;
- (void)resetStats;
- (BOOL)acquireSCSIBus:(unsigned)channel owner:owner;
- (void)releaseSCSIBus:(unsigned)channel owner:owner;
- (unsigned)maxTransfer;
- (unsigned)scsiBusId:(unsigned)channel;
- (unsigned)numberOfTargets;
- (IOReturn)executeCmdBuf:(struct EATACommandBuf *)cmdBuf;

@end

#import "EATAControllerPrivate.h"
