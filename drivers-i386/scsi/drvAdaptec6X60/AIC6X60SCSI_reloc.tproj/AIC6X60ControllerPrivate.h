/*
 * Copyright (c) 1993-1998 NeXT Software, Inc.
 *
 * AIC6X60ControllerPrivate.h - Adaptec 6x60 SCSI controller private typedefs.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created.
 */

#import <machkit/NXLock.h>
#import <mach/mach_types.h>
#import <mach/message.h>
#import <driverkit/interruptMsg.h>
#import "AIC6X60Controller.h"
#import "AIC6X60Types.h"
#import <driverkit/debugging.h>

/*
 * Command to be executed by I/O thread.
 */
typedef enum {
	AO_Execute,		// execute IOSCSIRequest
	AO_Reset,		// reset bus
	AO_Abort		// abort I/O thread
} AIC6X60Op;

/*
 * Command struct passed from exported methods (executeRequest and
 * resetSCSIBus) to the I/O thread. This struct is passed via commandQ.
 */
typedef struct {
	AIC6X60Op	op;		// AO_Execute, etc.

	/*
	 * The following 3 fields are only valid if op == AO_Execute.
	 */
	IOSCSIRequest	*scsiReq;
	void		*buffer;
	vm_task_t	client;

	sc_status_t	result;		// status upon completion
	NXConditionLock	*cmdLock;	// client waits on this
	queue_chain_t	link;		// for enqueueing on commandQ
} AIC6X60CommandBuf;

/*
 * Condition variable states for AIC6X60CommandBuf.cmdLock.
 */
#define CMD_PENDING	0
#define CMD_COMPLETE	1

/*
 * DDM masks and macros.
 */
/*
 * The index into IODDMMasks[].
 */
#define AIC_DDM_INDEX	2

#define DDM_EXPORTED	0x00000001	// exported methods
#define DDM_IOTHREAD	0x00000002	// I/O thread methods
#define DDM_INIT	0x00000004	// Initialization

#define ddm_exp(x, a, b, c, d, e) 					\
	IODEBUG(AIC_DDM_INDEX, DDM_EXPORTED, x, a, b, c, d, e)

#define ddm_thr(x, a, b, c, d, e) 					\
	IODEBUG(AIC_DDM_INDEX, DDM_IOTHREAD, x, a, b, c, d, e)

#define ddm_init(x, a, b, c, d, e) 					\
	IODEBUG(AIC_DDM_INDEX, DDM_INIT, x, a, b, c, d, e)


/*
 * Public low-level routines in AIC6X60Routines.m.
 */
extern void aic_reset_board(unsigned short base,
	unsigned char 	aic_board_id);
boolean_t aic_setup_mb_area(unsigned short base,
	struct aic_mb_area *aic_mb_area,
	struct ccb 	*aic_ccb);
extern void aic_start_scsi(unsigned short base);
extern void aic_unlock_mb(unsigned short base);
extern boolean_t aic_cmd(unsigned short	base,
	unsigned char	cmd,
	unsigned char	*args,
	int		arglen,
	unsigned char	*reply,
	int		replylen,
	boolean_t	polled
);
extern boolean_t aic_probe_cmd(
	unsigned short	base,
	unsigned char	cmd,
	unsigned char	*args,
	int		arglen,
	unsigned char	*reply,
	int		replylen,
	boolean_t	polled
);

