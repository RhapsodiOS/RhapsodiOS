/*
 * Copyright (c) 1993-1998 NeXT Software, Inc.
 *
 * Adaptec 6x60 SCSI controller I/O thread definitions.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created.
 */

#import <machkit/NXLock.h>
#import <mach/mach_types.h>
#import <mach/message.h>
#import <driverkit/interruptMsg.h>
#import "AIC6X60Controller.h"

/*
 * Reason for calling -commandCompleted.
 */
typedef enum {
	CS_Complete,		/* normal - controller completed command */
	CS_Timeout,		/* I/O timeout */
	CS_Reset		/* Bus was reset; abort */
} completeStatus;

/*
 * Methods executed by the I/O thread.
 */
@interface AIC6X60(IOThread)

- (void)threadExecuteRequest	: (AIC6X60CommandBuf *)cmdBuf;
- (void)threadResetBus		: (AIC6X60CommandBuf *)cmdBuf;
- (int)scbFromCmd		: (AIC6X60CommandBuf *)cmdBuf
			    scb : (struct _SCB *)scb;
- (void)commandCompleted	: (struct _SCB *)scb
			 reason : (completeStatus)status;
- (struct _SCB *)allocScb;
- (void)freeScb			: (struct _SCB *)scb;
- (void)completeDMA		: (IOEISADMABuffer *)dmaList
		         length : (unsigned)xferLen;
- (void)abortDMA		: (IOEISADMABuffer *)dmaList
		         length : (unsigned)xferLen;

@end
