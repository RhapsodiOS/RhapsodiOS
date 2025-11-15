/*
 * Copyright (c) 1993-1996 NeXT Software, Inc.
 *
 * AHAControllerPrivate.h - Adaptec 1542 SCSI controller private typedefs.
 *
 * HISTORY
 *
 * 13 Apr 1993	Doug Mitchell at NeXT
 *	Created.
 */

#import <machkit/NXLock.h>
#import <mach/mach_types.h>
#import <mach/message.h>
#import <driverkit/interruptMsg.h>
#import "AHAController.h"
#import "AHATypes.h"
#import <driverkit/debugging.h>

/*
 * Command to be executed by I/O thread.
 */
typedef enum { 
	AO_Execute,		// execute IOSCSIRequest
	AO_Reset,		// reset bus
	AO_Abort		// abort I/O thread
} AHAOp;

/*
 * Command struct passed from exported methods (executeRequest and 
 * resetSCSIBus) to the I/O thread. This struct is passed via commandQ.
 */
typedef struct {
	AHAOp		op;		// AO_Execute, etc.
	
	/*
	 * The following 3 fields are only valid if op == AH_Execute.
	 */
	IOSCSIRequest	*scsiReq;
	void		*buffer;	
	vm_task_t	client;
	
	sc_status_t	result;		// status upon completion
	NXConditionLock	*cmdLock;	// client waits on this
	queue_chain_t	link;		// for enqueueing on commandQ
} AHACommandBuf;

/*
 * Condition variable states for AHACommandBuf.cmdLock.
 */
#define CMD_PENDING	0
#define CMD_COMPLETE	1

/*
 * DDM masks and macros.
 */
/*
 * The index into IODDMMasks[].
 */
#define AHA_DDM_INDEX	2

#define DDM_EXPORTED	0x00000001	// exported methods
#define DDM_IOTHREAD	0x00000002	// I/O thread methods
#define DDM_INIT	0x00000004	// Initialization

#define ddm_exp(x, a, b, c, d, e) 					\
	IODEBUG(AHA_DDM_INDEX, DDM_EXPORTED, x, a, b, c, d, e)
	
#define ddm_thr(x, a, b, c, d, e) 					\
	IODEBUG(AHA_DDM_INDEX, DDM_IOTHREAD, x, a, b, c, d, e)

#define ddm_init(x, a, b, c, d, e) 					\
	IODEBUG(AHA_DDM_INDEX, DDM_INIT, x, a, b, c, d, e)


/*
 * Public low-level routines in AHARoutines.m.
 */
extern void aha_reset_board(unsigned short base, 
	unsigned char 	aha_board_id);
boolean_t aha_setup_mb_area(unsigned short base,
	struct aha_mb_area *aha_mb_area,
	struct ccb 	*aha_ccb);
extern void aha_start_scsi(unsigned short base);
extern void aha_unlock_mb(unsigned short base);
extern boolean_t aha_cmd(unsigned short	base,
	unsigned char	cmd,
	unsigned char	*args,
	int		arglen,
	unsigned char	*reply,
	int		replylen,
	boolean_t	polled
);
extern boolean_t aha_probe_cmd(
	unsigned short	base,
	unsigned char	cmd,
	unsigned char	*args,
	int		arglen,
	unsigned char	*reply,
	int		replylen,
	boolean_t	polled
);

