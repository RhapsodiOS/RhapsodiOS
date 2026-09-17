/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Controller.h - class definition for Symbios Logic 53C8xx driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from BusLogic driver.
 */


#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <driverkit/IOSCSIController.h>
#import <driverkit/i386/directDevice.h>
#import <kernserv/queue.h>
#import "SYM53c8Types.h"
#import "SYM53c8ControllerPrivate.h"


@interface SYM53c8 : IOSCSIController
{
	/*
	 * __OBJC,__instance_vars (16 entries). First declared ivar is
	 * +0x244; instance_size is 0x600.
	 */
	int			intPortKern;		/* +0x244 */
	unsigned int		interrupt;		/* +0x248 */
	unsigned char		path;			/* +0x24c */
	id			reqPoolLock;		/* +0x250 NXLock */
	unsigned int		availReqs;		/* +0x254 */
	struct _scsireq		*freereq;		/* +0x258 */
	struct _scsireq		reqs[SYM_REQS_COUNT];	/* +0x25c, 32 × 0x1C */
	char			levelIRQ;		/* +0x5dc */
	unsigned char		ioThreadRunning : 1;	/* +0x5dd */
	unsigned		pad : 31;		/* +0x5e0 */
	queue_head_t		commandQ;		/* +0x5e4 */
	id			commandLock;		/* +0x5ec NXLock */
	unsigned int		maxQueueLen;		/* +0x5f0 */
	unsigned int		queueLenTotal;		/* +0x5f4 */
	unsigned int		totalCommands;		/* +0x5f8 */
	unsigned int		outstandingCount;	/* +0x5fc */
}

/*
 * Standard IODirectDevice methods overridden here.
 */
+ (BOOL)probe:deviceDescription;
- initFromDeviceDescription	: deviceDescription;
- (unsigned)maxTransfer;
- free;
- (void)interruptOccurred;
- (void)commandRequestOccurred;
- (void)setPath			: (unsigned char)thePath;

/*
 * IOSCSIControllerExported methods implemented here.
 */
- (sc_status_t) executeRequest 	: (IOSCSIRequest *)scsiReq
		         buffer : (void *)buffer
		         client : (vm_task_t)client;
- (sc_status_t)resetSCSIBus;
- (unsigned)numberOfTargets;
- (void)resetStats;
- (unsigned)numQueueSamples;
- (unsigned)sumQueueLengths;
- (unsigned)maxQueueLength;

- (struct _scsireq *)allocReq;
- (void)freeReq			: (struct _scsireq *)req;
- convertReq			: (IOSCSIRequest *)scsiReq
			   ToXpt : (struct _scsireq *)req
			  buffer : (void *)buffer
			  client : (vm_task_t)client;
- (void)updateStatus		: (struct _scsireq *)req;
- (int)executeCmdBuf		: (SYMCommandBuf *)cmdBuf;
- (void)manualTURScan;

@end
