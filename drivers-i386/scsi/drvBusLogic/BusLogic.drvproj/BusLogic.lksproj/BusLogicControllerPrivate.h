/*
 * Copyright (c) 1996 NeXT Software, Inc.
 *
 * BusLogicControllerPrivate.h - Private definitions for BusLogic driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from Adaptec 1542 driver.
 */

#import <kernserv/queue.h>
#import <machkit/NXConditionLock.h>

/*
 * Command request operations.
 */
typedef enum {
	BO_Execute,
	BO_Reset,
	BO_Abort
} BLOperation;

/*
 * Completion status.
 */
typedef enum {
	CS_Complete,
	CS_Timeout,
	CS_Reset
} completeStatus;

/*
 * States for cmdLock NXConditionLock.
 */
#define CMD_PENDING		0
#define CMD_COMPLETE		1

/*
 * A request to the I/O thread.
 */
typedef struct {
	queue_chain_t	link;
	BLOperation	op;
	IOSCSIRequest	*scsiReq;
	void		*buffer;
	vm_task_t	client;
	sc_status_t	result;
	id		cmdLock;	/* NXConditionLock */
} BLCommandBuf;

