/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Adaptec2940Private.h - Private declarations for Adaptec 2940 driver.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#ifndef _ADAPTEC2940PRIVATE_H
#define _ADAPTEC2940PRIVATE_H

#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <kernserv/queue.h>
#import "Adaptec2940Types.h"

/*
 * Private methods.
 */
@interface Adaptec2940(Private)

- (IOReturn)aicInitController;
- (IOReturn)aicResetBus;
- (IOReturn)aicAllocateResources;
- (void)aicFreeResources;
- (struct scb *)allocScb;
- (void)freeScb:(struct scb *)scb;
- (void)threadExecuteRequest:(void *)commandBuf;
- (void)runPendingCommands;
- (void)processCmdComplete:(struct scb *)scb;
- (IOReturn)executeCmdBuf:(void *)commandBuf;

@end

/*
 * Internal command buffer structure.
 */
typedef struct {
	queue_chain_t		link;
	IOSCSIRequest		*scsiReq;
	void			*buffer;
	vm_task_t		client;
	struct scb		*scb;
} Adaptec2940CommandBuf;

#define AIC_QUEUE_SIZE		16
#define AIC_NUM_SCBS		16

/*
 * Timeout values.
 */
#define AIC_RESET_TIMEOUT_MS	5000
#define AIC_CMD_TIMEOUT_MS	30000

#endif /* _ADAPTEC2940PRIVATE_H */
