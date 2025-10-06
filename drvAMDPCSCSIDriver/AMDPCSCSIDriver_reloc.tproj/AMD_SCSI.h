/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_SCSI.h - top-level API for AMD 53C974/79C974 PCI SCSI driver. 
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */
 
#import <driverkit/i386/directDevice.h>
#import <kernserv/queue.h>
#import <driverkit/IODirectDevice.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/driverTypes.h>
#import <driverkit/IOSCSIController.h>
#import <driverkit/IOPower.h>
#import "AMD_Types.h"

/*
 * WARNING: The AMDPCnet32NetworkDriver driver uses this class name to
 * conditionally enable some workarounds if the AMD_SCSI class is present.
 * If this class name is changed, the AMDPCnet32NetworkDriver driver must 
 * also be updated to reflect the new class name.
 */
@interface AMD_SCSI : IOSCSIController <IOPower> 
{
	IOEISAPortAddress 	ioBase;	// base IO port addr
	port_t		interruptPortKern;

	/*
	 * Commands are passed from exported methods to the I/O thread
	 * via commandQ, which is protected by commandLock.
	 * 
	 * Commands which are disconnected but not complete are kept
	 * in disconnectQ.
	 *
	 * Commands which have been dequeued from commandQ by the 
	 * I/O thread but which have not been started because a 
	 * command is currently active on the bus are kept in pendingQ.
	 *
	 * The currently active command, if any, is kept in activeCmd.
	 * Only commandBufs with op == CO_Execute are ever placed in
	 * activeCmd.
	 */
	queue_head_t	disconnectQ;	
	queue_head_t	commandQ;		
	id		commandLock;	// NXLock; protects commandQ 
	queue_head_t	pendingQ;		
	commandBuf 	*activeCmd;	// connected command (if any). NULL 
					// implies we're disconnected. 
					
	/*
	 * Option flags, accessible via instance table or setIntValues 
	 * (DEBUG only).
	 */
	unsigned	autoSenseEnable:1,
			cmdQueueEnable:1,
			syncModeEnable:1,
			fastModeEnable:1,
			extendTiming:1,
			ioThreadRunning:1,
			pad:26;
	unsigned	scsiClockRate;	// in MHz

	/*
	 * Array of active I/Os counters, one counter per lun per target.
	 * If command queueing is disabled, the max value of each counter
	 * is 1. ActiveCount is the sum of all elements in activeArray.
	 */
	unsigned char 	activeArray[SCSI_NTARGETS][SCSI_NLUNS];
	unsigned	activeCount;
		
	/*
	 * Hardware related variables used (mostly) in AMD_Chip.m.
	 */
	unsigned char	saveStatus;	// saved status on interrupt
	unsigned char	saveSeqStep;	// saved seqstep
	unsigned char	saveIntrStatus;	// saved interrupt status 
	unsigned char	hostId;		// our SCSI ID 
	scState_t 	scState;	// SCS_DISCONNECTED, etc.
	unsigned char	reselTarget;	// target attempting to reselect
	unsigned char	reselLun;	// lun       ""         ""
	
	/*
	 * commandBuf->queueTag for next I/O. This is never zero; for
	 * method calls involving a T/L/Q nexus, a queue tag of zero
	 * indicates a nontagged command.
	 */
	unsigned char	nextQueueTag;
	
	/*
	 * Per-target information.
	 */
	perTargetData 	perTarget[SCSI_NTARGETS];
	
	/*
	 * Message in/out state machine variables.
	 * Outbound messages are placed in currMsgOut[] after asserting ATN;
	 * when we see phase == PHASE_MSGOUT, these are sent to FIFO.
	 * Inbound messages are placed in currMsgIn[] and are processed
	 * when we leave phase == PHASE_MSGIN.
	 */
	unsigned char	currMsgOut[AMD_MSG_SIZE];
	unsigned	currMsgOutCnt;
	unsigned char	currMsgIn[AMD_MSG_SIZE];
	unsigned	currMsgInCnt;
	msgOutState_t	msgOutState;		//  MOS_WAITING, etc.
	
	SDTR_State_t	SDTR_State;
	
	unsigned	reselPending:1,
			pad2:31;
	
#ifdef	DEBUG
	/*
	 * Shadows of write-only registers.
	 */
	unsigned char	syncOffsetShadow;
	unsigned char	syncPeriodShadow;
#endif	DEBUG
	/*
	 * Statistics support.
	 */
	unsigned	maxQueueLen;
	unsigned	queueLenTotal;
	unsigned	totalCommands;
	
	/*
	 * DMA Memory Descriptor List.
	 */
	vm_address_t	*mdl;		// well aligned working ptr
	vm_address_t	*mdlFree;	// ptr we have to IOFree()
	unsigned	mdlPhys;	// physical address of mdl
	
	/*
	 * host bus info.
	 */
	BusType		busType;		// only BT_PCI for now
	BOOL		levelIRQ;
	unsigned char	busNumber;		// FIXME - do we need these?
	unsigned char	deviceNumber;
	unsigned char	functionNumber; 

}

+ (BOOL)probe:deviceDescription;
- free;
- (sc_status_t) executeRequest 	: (IOSCSIRequest *)scsiReq 
		         buffer : (void *)buffer 
		         client : (vm_task_t)client;
- (sc_status_t)resetSCSIBus;
- (void)resetStats;
- (unsigned)numQueueSamples;
- (unsigned)sumQueueLengths;
- (unsigned) maxQueueLength;
- (void)interruptOccurred;	
- (void)timeoutOccurred;

#if	AMD_ENABLE_GET_SET

- (IOReturn)setIntValues		: (unsigned *)parameterArray
			   forParameter : (IOParameterName)parameterName
			          count : (unsigned)count;
- (IOReturn)getIntValues		: (unsigned *)parameterArray
			   forParameter : (IOParameterName)parameterName
			          count : (unsigned *)count;	// in/out
/*
 * setIntValues parameters.
 */
#define AMD_AUTOSENSE		"AutoSense"
#define AMD_CMD_QUEUE		"CmdQueue"
#define AMD_SYNC		"Sync"
#define AMD_FAST_SCSI		"FastSCSI"
#define AMD_RESET_TARGETS	"ResetTargets"

#endif	AMD_ENABLE_GET_SET

@end


