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

@interface SYM53c8(IOThread)

- (int)threadExecuteRequest	: (struct _scsireq *)req;
- (void)threadResetSCSIBus;

@end
