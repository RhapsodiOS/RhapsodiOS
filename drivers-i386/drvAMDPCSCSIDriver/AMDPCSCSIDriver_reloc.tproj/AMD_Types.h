/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_Types.h - private structs and #defines for AMD 53C974 SCSI driver. 
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */

#import <driverkit/scsiTypes.h>
#import <machkit/NXLock.h>
#import <kernserv/queue.h>
#import <driverkit/debugging.h>
#import "bringup.h"

/*
 * Operation flags and options.
 */

/*
 * Renegotiate sync transfer parameters on each request sense command to 
 * recover from target power cycles.
 */
#define SYNC_RENEGOT_ON_REQ_SENSE	1

/*
 * Enable get/setIntValues methods.
 */
#define AMD_ENABLE_GET_SET	DEBUG

/*
 * Bus type. Only BT_PCI supported for now.
 */
typedef enum {
	BT_ISA,
	BT_EISA,
	BT_VL,
	BT_PCI,
} BusType;

/*
 * Command to be executed by I/O thread.
 */
typedef enum { 
	CO_Execute,		// execute IOSCSIRequest
	CO_Reset,		// reset bus
	CO_Abort		// abort I/O thread
} cmdOp;

/*
 * Command struct passed to I/O thread.
 */
typedef struct _commandBuf {

	/*
	 * Fields valid when commandBuf is passed to I/O thread.
	 */
	cmdOp		op;		// EO_Execute, etc.
	
	/*
	 * The following 3 fields are only valid if op == CO_Execute.
	 */
	IOSCSIRequest	*scsiReq;
	void		*buffer;	
	vm_task_t	client;
	
	/*
	 * Remainder is used only by I/O thread.
	 */
	NXConditionLock	*cmdLock;	// client waits on this
	queue_chain_t	link;		// for enqueueing on commandQ
	port_t		timeoutPort;	// for timeout messages
	unsigned char	queueTag;	// QUEUE_TAG_NONTAGGED if cmd 
					//    queueing disabled for this cmd
	
	/*
	 * SCSI bus state variables.
	 */
	vm_offset_t	currentPtr;		// current DMA pointer
	int		currentByteCount;	// counts down to 0 from 
						//   scsiReq.maxTransfer
	vm_offset_t 	savedPtr;		// for SCSI disconnect state
	int		savedByteCount;		// ditto
	unsigned	discEnable:1,		// disconnects enabled for
						//   THIS command
						
	/*
	 * The active flag indicates that activeArray[][] and activeCount 
	 * have been updated to include this command, and that 
	 * IOScheduleFunc() has been called.
	 */
			active:1,
			pad:30;
	unsigned char	cdbLength;
	unsigned char	selectCmd;		// SCMD_SELECT_ATN_3, etc.
	
	
	/*
	 * Statistics support.
	 */
	ns_time_t	startTime;		// time cmd started
	ns_time_t	disconnectTime;		// time of last disconnect
	
	/*
	 * If non-NULL, cmdPendingSense indicates that THIS cmdBuf is an 
	 * autosense op for command in cmdPendingSense. DMA sense data 
	 * goes to buffer in this cmdBuf; unalignedSense is what has to 
	 * be IOFreed.
	 */
	struct _commandBuf	*cmdPendingSense;
	void			*unalignedSense;
	
} commandBuf;

/*
 * Condition variable states for commandBuf.cmdLock.
 */
#define CMD_PENDING	0
#define CMD_COMPLETE	1

/*
 * Size of Memory Descriptor List. Each MDL entry refers to a max of 4K
 * bytes. The first and last entries can refer to as little as four bytes.
 */
#define MDL_SIZE	18

/*
 * Size of message byte array.
 */
#define AMD_MSG_SIZE	16

/*
 * Value of queueTag for nontagged commands. This value is never used for 
 * the tag for tagged commands.
 */
#define QUEUE_TAG_NONTAGGED	0

/*
 * Per-target info.
 * 
 * maxQueue is set to a non-zero value when we reach a target's queue size
 * limit, detected by a STAT_QUEUE_FULL status. A value of zero means we
 * have not reached the target's limit and we are free to queue additional
 * commands (if allowed by the overall cmdQueueEnable flag).
 *
 * syncXferPeriod and syncXferOffset are set to non-zero during sync  
 * transfer negotiation. Units of syncXferPeriod is NANOSECONDS, which
 * differs from both the chip's register format (dependent on clock 
 * frequency and fast SCSI/fast clock enables) and the SCSI bus's format
 * (which is 4 ns per unit).
 *
 * cmdQueueDisable and syncDisable have a default (initial) value of 
 * zero regardless of the driver's overall cmdQueueEnable and syncModeEnable
 * flags. They are set to one when a target explicitly tells us that the
 * indicated feature is unsupported. 
 *
 * syncNegotNeeded, when set, indicates that sync negotiation is required
 * (typically after a reset).
 */
typedef struct {
	unsigned char	maxQueue;
	unsigned char	syncXferPeriod;
	unsigned char	syncXferOffset;
	unsigned char	cmdQueueDisable:1,
			syncDisable:1,
			syncNegotNeeded:1,
			pad:5;
} perTargetData;

/*
 * The rest of this file is private to the AMD_Chip category, but 
 * it needs to be visible here to allow AMD_Chip to have its own 
 * instance variables. 
 */
 
/*
 * Values for scState instance variable.
 */
typedef enum {
	SCS_UNINITIALIZED,		// initial state
        SCS_DISCONNECTED,		// disconnected
        SCS_SELECTING,			// SELECT command issued 
        SCS_INITIATOR,			// following target SCSI phase 
        SCS_COMPLETING,			// initiator cmd cmplt in progress 
        SCS_DMAING,			// dma is in progress 
        SCS_ACCEPTINGMSG,		// MSGACCEPTED cmd in progress 
        SCS_SENDINGMSG,			// MSG_OUT phase in progress 
        SCS_GETTINGMSG,			// transfer msg in progress 
	SCS_SENDINGCMD,			// command out in progress
} scState_t;

/*
 * The message out state machine works as follows:
 * 1. When the driver wishes to send a message out, it:
 *    -- places the message in currMsgOut[]
 *    -- places the number of message bytes in currMsgOutCnt
 *    -- asserts ATN 
 *    -- sets msgOutState to MOS_WAITING
 *    All of the above are done by -messageOut for single-byte messages.
 * 2. When bus phase = PHASE_MSGOUT, the message in currMsgOut[] is 
 *    sent to the target in -fsmPhaseChange. msgOutState is then
 *    set to MOS_SAWMSGOUT.
 * 3. On the next phase change to other than PHASE_MSGOUT or PHASE_MSGIN,
 *    msgOutState is set to MOS_NONE and currMsgOutCnt is set to 0.
 */
 
/* 
 *  Values for msgOutState instance variable.
 */
typedef enum {
        MOS_NONE,			// no message to send 
        MOS_WAITING,			// have msg, awaiting MSG OUT phase 
        MOS_SAWMSGOUT			// sent msg, check for retry 
} msgOutState_t;

/*
 * Values for SDTR Negotiation State instance variable.
 */
typedef enum {
	SNS_NONE,			// quiescent
	SNS_TARGET_INIT,		// target initiated SDTR
	SNS_HOST_INIT_NEEDED,		// host initiated SDTR needed
	SNS_HOST_INIT,			// host initiated SDTR in progress
} SDTR_State_t;

/*
 * FIXME - this should be added to scsireg.h
 */
#define STAT_QUEUE_FULL		0x28	// queue full status

