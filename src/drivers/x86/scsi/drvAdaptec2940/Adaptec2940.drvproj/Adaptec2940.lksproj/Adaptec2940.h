/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Adaptec2940.h - class definition for Adaptec 2940 PCI SCSI driver.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */


#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <driverkit/IOSCSIController.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import "Adaptec2940Private.h"
#import "Adaptec2940Types.h"


@interface Adaptec2940 : IOSCSIController
{
	/*
	 * Hardware info.
	 */
	struct adaptec2940_config 	config;		/* config info from device */
	IOPCIConfigSpace		pciConfigSpace;
	unsigned char 			scsiId;
	BOOL				ioThreadRunning;
	unsigned int			ioBase;		/* base IO port address */

	/*
	 * Command control blocks and mailbox areas.
	 * Dynamically allocated.
	 */
	struct scb			*scbArray;
	int				numFreeScbs;	/* number of free SCBs */

	/*
	 * Three queues:
	 *
	 * commandQ:	 contains Adaptec2940CommandBuf's to be executed by the
	 *		 I/O thread. Enqueued by exported methods (via
	 *		 -executeCmdBuf); dequeued by the I/O thread in
	 *		 -commandRequestOccurred.
	 *
	 * outstandingQ: contains scb's on which the controller is
	 * 		 currently operating. The number of scb's in
	 *		 outstandingQ is outstandingCount. Scb's are
	 *		 enqueued here by -runPendingCommands.
	 *
	 * pendingQ:	 contains scb's which the I/O thread is holding
	 *		 on to because outstandingCount == AIC_QUEUE_SIZE.
	 *		 Scb's are enqueued here by -threadExecuteRequest:.
	 *
	 */
	queue_head_t	commandQ;		/* list of waiting
						 * Adaptec2940CommandBuf's */
	id		commandLock;		/* NXLock; protects commandQ */
	queue_head_t	outstandingQ;		/* list of running cmds */
	unsigned int	outstandingCount;	/* length of outstandingQ */
	queue_head_t	pendingQ;

	/*
	 * Local reference count for reserveDMALock.
	 */
	unsigned	dmaLockCount;

	/*
	 * Statistics counters.
	 */
	unsigned int	maxQueueLen;
	unsigned int	queueLenTotal;
	unsigned int	totalCommands;

	port_t		interruptPortKern;	/* kernel version of
						 * interruptPort */
}

/*
 * Standard IODirectDevice methods overridden here.
 */
+ (BOOL)probe:deviceDescription;
- initFromDeviceDescription	: deviceDescription;
- (unsigned)maxTransfer;
- free;
- (void)interruptOccurred;
- (void)interruptOccurredAt:(int)localNum;
- (void)otherOccurred:(int)id;
- (void)receiveMsg;
- (void)timeoutOccurred;
- (void)commandRequestOccurred;

/*
 * IOSCSIControllerExported methods implemented here.
 */
- (sc_status_t) executeRequest 	: (IOSCSIRequest *)scsiReq
		         buffer : (void *)buffer
		         client : (vm_task_t)client;
- (sc_status_t)resetSCSIBus;

@end


