/*
 * Copyright (c) 1996 NeXT Software, Inc.
 *
 * BusLogicThread.h - I/O thread methods for BusLogic driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from Adaptec 1542 driver.
 */

#import "BusLogicController.h"
#import "BusLogicControllerPrivate.h"

@interface BLController(IOThread)

- (int)threadExecuteRequest	: (BLCommandBuf *)cmdBuf;
- (void)threadResetBus		: (BLCommandBuf *)cmdBuf;
- (int)ccbFromCmd		: (BLCommandBuf *)cmdBuf
				  ccb:(struct ccb *)ccb;
- runPendingCommands;
- (void)commandCompleted	: (struct ccb *)ccb
			  reason : (completeStatus)reason;
- (struct ccb *)allocCcb	: (BOOL)doDMA;
- (void)freeCcb			: (struct ccb *)ccb;
- (void)completeDMA		: (IOEISADMABuffer *)dmaList
			  length : (unsigned int)xferLen;
- (void)abortDMA		: (IOEISADMABuffer *)dmaList
			  length : (unsigned int)xferLen;

@end

