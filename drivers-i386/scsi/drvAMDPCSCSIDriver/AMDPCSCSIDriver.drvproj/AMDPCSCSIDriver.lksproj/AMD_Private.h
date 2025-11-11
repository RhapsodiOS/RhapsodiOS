/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_SCSI.h - hardware-independent methods for AMD PCI SCSI driver.
 *
 * These methods are implemented in AMD_SCSI.m.
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */
 
#import "AMD_SCSI.h"
#import "AMD_Types.h"

@interface AMD_SCSI(Private)

/*
 * Send a command to the controller thread, and wait for its completion.
 * Only invoked by publicly exported methods in SCSIController.m.
 */
- (IOReturn)executeCmdBuf	: (commandBuf *)cmdBuf;

/*
 * Abort all active and disconnected commands with specified status. No 
 * hardware action. Currently used by threadResetBus and during processing
 * of a CO_Abort command.
 */
- (void)swAbort : (sc_status_t)status;

/*
 * I/O thread version of resetSCSIBus and executeRequest.
 */
- (void)threadResetBus 		: (const char *)reason;
- (void)threadExecuteRequest	: (commandBuf *)cmdBuf;

/*
 * Methods called by other modules in this driver. 
 */
 
/*
 * Called when a transaction associated with cmdBuf is complete. Notify 
 * waiting thread. If cmdBuf->scsiReq exists (i.e., this is not a reset
 * or an abort), scsiReq->driverStatus must be valid. If cmdBuf is activeCmd,
 * caller must remove from activeCmd.
 */
- (void)ioComplete		: (commandBuf *)cmdBuf;

/*
 * Generate autosense request for specified cmdBuf, place it 
 * at head of pendingQ.
 */
- (void)generateAutoSense : (commandBuf *)cmdBuf;

/*
 * I/O associated with activeCmd has disconnected. Place it on disconnectQ
 * and enable another transaction.
 */ 
- (void)disconnect;

/*
 * Specified target, lun, and queueTag is trying to reselect. If we have 
 * a commandBuf for this TLQ nexus on disconnectQ, remove it, make it the
 * current activeCmd, and return YES. Else return NO.
 * A value of zero for queueTag indicates a nontagged command (zero is never
 * used as the queue tag value for a tagged command).
 */
- (BOOL)reselect 		: (unsigned char)target_id
	    		    lun : (unsigned char)lun
		       queueTag : (unsigned char)queueTag;

/*
 * Determine if activeArray[][], maxQueue[][], cmdQueueEnable, and a 
 * command's target and lun show that it's OK to start processing cmdBuf.
 * Returns YES if copacetic.
 */
- (BOOL)cmdBufOK : (commandBuf *)cmdBuf;
	    
/*
 * The bus has gone free. Start up commands in pendingQ, if any.
 */
- (void)busFree;

/*
 * Abort activeCmd (if any) and any disconnected I/Os (if any) and reset 
 * the bus due to gross hardware failure.
 * If activeCmd is valid, its scsiReq->driverStatus will be set to 'status'.
 */
- (void)hwAbort 		: (sc_status_t)status
		 	 reason : (const char *)reason;

/*
 * Called by chip level to indicate that a command has gone out to the 
 * hardware.
 */
- (void)activateCommand : (commandBuf *)cmdBuf;

/*
 * Remove specified cmdBuf from "active" status. Update activeArray,
 * activeCount, and unschedule pending timer.
 */
- (void)deactivateCmd : (commandBuf *)cmdBuf;

@end

