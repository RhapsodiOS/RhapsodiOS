/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Thread.h - I/O thread methods for Symbios 53C8xx driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from BusLogic driver.
 */

#import "SYM53c8Controller.h"
#import "SYM53c8ControllerPrivate.h"

@interface SYM53c8Controller(IOThread)

- (int)threadExecuteRequest	: (SYMCommandBuf *)cmdBuf;
- (void)threadResetBus		: (SYMCommandBuf *)cmdBuf;
- (int)ccbFromCmd		: (SYMCommandBuf *)cmdBuf
				  ccb:(struct ccb *)ccb;
- runPendingCommands;
- (void)commandCompleted	: (struct ccb *)ccb
			  reason : (completeStatus)reason;
- (struct ccb *)allocCcb	: (BOOL)doDMA;
- (void)freeCcb			: (struct ccb *)ccb;
- (void)handleScriptsInterrupt;
- (void)handleDMAError		: (unsigned char)dstat;
- (void)handleBusReset;
- (void)handleSelectionTimeout;
- (void)handleParityError;

@end

