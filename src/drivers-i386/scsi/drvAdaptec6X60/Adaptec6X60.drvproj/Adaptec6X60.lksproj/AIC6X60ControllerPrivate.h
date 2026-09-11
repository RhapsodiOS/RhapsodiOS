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
 * resetSCSIBus) to the I/O thread.
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
	queue_chain_t	link;
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
 * Block transfer primitives. Each moves "count" items of the named
 * width to or from the single port "port"; the count is an item
 * count, not a byte count. Definition sites move to the sequencer.
 */
extern int repinsb(IOEISAPortAddress port, unsigned char *addr, int count);
extern int repinsw(IOEISAPortAddress port, unsigned short *addr, int count);
extern int repinsd(IOEISAPortAddress port, unsigned long *addr, int count);
extern int repoutsb(IOEISAPortAddress port, unsigned char *addr, int count);
extern int repoutsw(IOEISAPortAddress port, unsigned short *addr, int count);
extern int repoutsd(IOEISAPortAddress port, unsigned long *addr, int count);
