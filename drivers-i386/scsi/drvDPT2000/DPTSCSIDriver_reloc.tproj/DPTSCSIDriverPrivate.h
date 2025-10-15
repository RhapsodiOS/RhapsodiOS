/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * DPTSCSIDriverPrivate.h - Private declarations for DPT SCSI driver.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#ifndef _DPTSCSIDRIVERPRIVATE_H
#define _DPTSCSIDRIVERPRIVATE_H

#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <kernserv/queue.h>
#import "DPTSCSIDriverTypes.h"

/*
 * Private methods.
 */
@interface DPTSCSIDriver(Private)

- (IOReturn)eataInitController;
- (IOReturn)eataResetBus;
- (IOReturn)eataAllocateResources;
- (void)eataFreeResources;
- (struct eata_cp *)allocCp;
- (void)freeCp:(struct eata_cp *)cp;
- (void)threadExecuteRequest:(void *)commandBuf;
- (void)runPendingCommands;
- (void)processCmdComplete:(struct eata_cp *)cp;
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
	struct eata_cp		*cp;
} DPTSCSIDriverCommandBuf;

#define DPT_QUEUE_SIZE		16
#define DPT_NUM_CPS		16

/*
 * Timeout values.
 */
#define DPT_RESET_TIMEOUT_MS	5000
#define DPT_CMD_TIMEOUT_MS	30000

#endif /* _DPTSCSIDRIVERPRIVATE_H */
