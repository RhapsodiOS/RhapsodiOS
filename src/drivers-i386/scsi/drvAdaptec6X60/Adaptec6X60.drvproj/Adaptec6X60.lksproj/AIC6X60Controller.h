/*
 * Copyright (c) 1993-1998 NeXT Software, Inc.
 *
 * AIC6X60Controller.h - class definition for Adaptec 6x60 driver.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created.
 */


#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <driverkit/IOSCSIController.h>
#import <driverkit/i386/directDevice.h>
#import "AIC6X60ControllerPrivate.h"
#import "AIC6X60Types.h"


@interface AIC6X60 : IOSCSIController
{
	/*
	 * Layout from __OBJC,__instance_vars. instance_size 4220 / 0x107c.
	 * First driver ivar at 0x244.
	 */
	struct _HACB		hacb;			/* 0x244, sizeof 0x390 */
	unsigned char		scsiBus;		/* 0x5d4 */
	IOEISAPortAddress	ioBase;			/* 0x5d6 */
	unsigned int		totalCommands;		/* 0x5d8 */
	port_t			interruptPortKern;	/* 0x5dc */
	BOOL			ioThreadRunning;	/* 0x5e0 */
	struct _SCB		him_scb[32];		/* 0x5e4 */
	int			nextScb;		/* 0x1064 */
	queue_head_t		pendingQ;		/* 0x1068 */
	int			numFreeScbs;		/* 0x1070 */
	BOOL			dmaEnabled;		/* 0x1074 */
	void			*currentDMABuffer;	/* 0x1078 */
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
