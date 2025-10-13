/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8ControllerPrivate.h - Private definitions for Symbios driver.
 *
 * HISTORY
 *
 * Oct 1998	Created.
 */

#import <machkit/NXLock.h>

/*
 * Command buffer operations
 */
typedef enum {
	SO_Execute,
	SO_Reset,
	SO_Abort
} SYMOp;

/*
 * Command buffer passed between client methods and I/O thread.
 */
typedef struct {
	SYMOp		op;
	IOSCSIRequest	*scsiReq;
	void		*buffer;
	vm_task_t	client;
	sc_status_t	result;
	id		cmdLock;	/* NXConditionLock */
	queue_chain_t	link;
} SYMCommandBuf;

/*
 * Condition states for cmdLock
 */
#define CMD_PENDING	0
#define CMD_COMPLETE	1

