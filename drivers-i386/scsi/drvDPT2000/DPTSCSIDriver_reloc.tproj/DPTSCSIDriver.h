/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * DPTSCSIDriver.h - class definition for DPT EATA ISA/EISA SCSI driver.
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
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/IODirectDevice.h>
#import "DPTSCSIDriverPrivate.h"
#import "DPTSCSIDriverTypes.h"


@interface DPTSCSIDriver : IOSCSIController
{
	/*
	 * Hardware info.
	 */
	struct dpt_config 		config;		/* config info from device */
	unsigned char 			scsiId;
	BOOL				ioThreadRunning;
	unsigned int			ioBase;		/* base IO port address */
	unsigned int			dmaChannel;	/* DMA channel */
	unsigned int			irqLevel;	/* IRQ level */

	/*
	 * Command control blocks and mailbox areas.
	 * Dynamically allocated.
	 */
	struct eata_cp			*cpArray;
	int				numFreeCps;	/* number of free CPs */

	/*
	 * Three queues:
	 *
	 * commandQ:	 contains DPTSCSIDriverCommandBuf's to be executed by the
	 *		 I/O thread. Enqueued by exported methods (via
	 *		 -executeCmdBuf); dequeued by the I/O thread in
	 *		 -commandRequestOccurred.
	 *
	 * outstandingQ: contains cp's on which the controller is
	 * 		 currently operating. The number of cp's in
	 *		 outstandingQ is outstandingCount. Cp's are
	 *		 enqueued here by -runPendingCommands.
	 *
	 * pendingQ:	 contains cp's which the I/O thread is holding
	 *		 on to because outstandingCount == DPT_QUEUE_SIZE.
	 *		 Cp's are enqueued here by -threadExecuteRequest:.
	 *
	 */
	queue_head_t	commandQ;		/* list of waiting
						 * DPTSCSIDriverCommandBuf's */
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


