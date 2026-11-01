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
#import <kernserv/queue.h>
#import <machkit/NXLock.h>
#import "SYM53c8Types.h"

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
 * commandRequestOccurred switches on cmdBuf->op: 0 / 1 / 2 →
 * threadExecuteRequest: / threadResetSCSIBus / IOExitThread.
 */
typedef enum {
	SO_Execute,		/* 0 */
	SO_Reset,		/* 1 */
	SO_Abort		/* 2 */
} SYMOp;

/*
 * -[SYM53c8 executeCmdBuf:] type encoding:
 * i12@8:12^{?=i^{_scsireq}@{?=^{queue_entry}^{queue_entry}}}16
 */
typedef struct {
	int			op;		/* +0x00 */
	struct _scsireq		*req;		/* +0x04 */
	id			lock;		/* +0x08 NXConditionLock */
	queue_chain_t		link;		/* +0x0C / +0x10 */
} SYMCommandBuf;

/*
 * NXConditionLock values from the reloc methods.
 * reqLock: idle=0, complete=1, pending=2.
 * reqPoolLock: has free reqs=3, empty=4.
 * Command-buf locks are allocated initWith:2 and woken with 1.
 */
#define REQ_IDLE	0
#define CMD_COMPLETE	1
#define CMD_PENDING	2
#define POOL_HAS_REQS	3
#define POOL_EMPTY	4
