/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8ControllerPrivate.h - Private definitions for Symbios driver.
 *
 * HISTORY
 *
 * Oct 1998	Created.
 */

#import <driverkit/debugging.h>
#import <machkit/NXLock.h>

/*
 * DDM masks and macros.
 *
 * SYM53c8Controller.m and SYM53c8Thread.m call ddm_init/ddm_exp/ddm_thr but
 * nothing defined them, so they compiled as implicit functions and could not
 * link.  The other SCSI drivers that use these carry the definitions in their
 * own private header -- see AHAControllerPrivate.h and
 * AIC6X60ControllerPrivate.h -- and all of them take slot 2 in IODDMMasks[].
 */
#define SYM_DDM_INDEX	2

#define DDM_EXPORTED	0x00000001	/* exported methods */
#define DDM_IOTHREAD	0x00000002	/* I/O thread methods */
#define DDM_INIT	0x00000004	/* initialization */

#define ddm_exp(x, a, b, c, d, e)					\
	IODEBUG(SYM_DDM_INDEX, DDM_EXPORTED, x, a, b, c, d, e)

#define ddm_thr(x, a, b, c, d, e)					\
	IODEBUG(SYM_DDM_INDEX, DDM_IOTHREAD, x, a, b, c, d, e)

#define ddm_init(x, a, b, c, d, e)					\
	IODEBUG(SYM_DDM_INDEX, DDM_INIT, x, a, b, c, d, e)

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

