/*
 * Copyright (c) 1993-1996 NeXT Software, Inc.
 *
 * AHAController.h. - class definition for Adaptec 1542 driver.
 *
 * HISTORY
 *
 * 13 Apr 1993	Doug Mitchell at NeXT
 *	Created from Brian Pinkerton's Adaptec driver. 
 */
 

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <driverkit/IOSCSIController.h>
#import <driverkit/i386/directDevice.h>
#import "AHAControllerPrivate.h"
#import "AHATypes.h"


@interface AHAController : IOSCSIController 
{
	/*
	 * Hardware info.
	 */
	struct aha_config 	config;		/* config info from device */
	IOEISAPortAddress 	ioBase;		/* base IO port addr */
	unsigned char 		ahaBoardId;
	BOOL			ioThreadRunning;
	
	/*
	 * mailbox and CCB areas. Dynamically allocated from low 
	 * 16 MB of memory.
	 */  
	struct aha_mb_area	*ahaMbArea;
	struct ccb		*ahaCcb;
	int			numFreeCcbs;	/* number of free CCBs */

	/*
	 * Three queues:
	 * 
	 * commandQ:	 contains AHACommandBuf's to be executed by the 
	 *		 I/O thread. Enqueued by exported methods (via
	 *		 -executeCmdBuf); dequeued by the I/O thread in
	 *		 -commandRequestOccurred.
	 *
	 * outstandingQ: contains ccb's on which the controller is
	 * 		 currently operating. The number of ccb's in
	 *		 outstandingQ is outstandingCount. Ccb's are 
	 *		 enqueued here by -runPendingCommands. 
	 *
	 * pendingQ:	 contains ccb's which the I/O thread is holding
	 *		 on to because outstandingCount == AHA_QUEUE_SIZE.
	 *		 Ccb's are enqueued here by -threadExecuteRequest:.
	 *
	 */
	queue_head_t	commandQ;		/* list of waiting
						 * AHACommandBuf's */
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


