/*
 * Copyright (c) 1993-1996 NeXT Software, Inc.
 *
 * Adaptec 1542 SCSI controller I/O thread definitions.
 *
 * HISTORY
 *
 * 13 Apr 1993	Doug Mitchell at NeXT
 *	Created.
 */

#import <machkit/NXLock.h>
#import <mach/mach_types.h>
#import <mach/message.h>
#import <driverkit/interruptMsg.h>
#import "AHAController.h"

/*
 * Reason for calling -commandCompleted.
 */
typedef enum {
	CS_Complete,		// normal - controller completed command
	CS_Timeout,		// I/O timeout
	CS_Reset		// Bus was reset; abort
} completeStatus;

/*
 * Methods executed by the I/O thread.
 */
@interface AHAController(IOThread)

- (int)threadExecuteRequest	: (AHACommandBuf *)cmdBuf;
- (void)threadResetBus		: (AHACommandBuf *)cmdBuf;
- (int)ccbFromCmd		: (AHACommandBuf *)cmdBuf
			    ccb : (struct ccb *)ccb;
- runPendingCommands;
- (void)commandCompleted	: (struct ccb *)ccb 
			 reason : (completeStatus)status;
- (struct ccb *)allocCcb        : (BOOL)doDMA;
- (void)freeCcb 		: (struct ccb *)ccb;
- (void)completeDMA		: (IOEISADMABuffer *)dmaList
		         length : (unsigned)xferLen;
- (void)abortDMA		: (IOEISADMABuffer *)dmaList
		         length : (unsigned)xferLen;

@end

