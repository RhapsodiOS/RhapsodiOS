/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_Chip.h - chip (53C974/79C974) specific methods for AMD SCSI driver
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */
 
#import "AMD_SCSI.h"
#import "AMD_Types.h"

@interface AMD_SCSI(Chip)

/*
 * Public methods called by other categories of AMD_SCSI.
 */
 
/*
 * One-time-only init and probe. Returns YES if a functioning chip is 
 * found, else returns NO. -hwReset must be called subsequent to this 
 * to enable operation of the chip.
 */ 
- (BOOL)probeChip;

/*
 * Reusable 53C974 init function. This includes a SCSI reset.
 * Handling of ioComplete of active and disconnected commands must be done
 * elsewhere. Returns non-zero on error. 
 */
- (int)hwReset : (const char *)reason;

/*
 * reset SCSI bus.
 */
- (void)scsiReset;

/*
 * Prepare for power down. 
 */
- (void) powerDown;

/*
 * Return values from -hwStart.
 */
typedef enum {
	HWS_OK,			// command started successfully
	HWS_REJECT,		// command rejected, try another
	HWS_BUSY,		// hardware not ready for command
} hwStartReturn;

/*
 * Start a SCSI transaction for the command in activeCmd. ActiveCmd must be 
 * NULL. A return of HWS_REJECT indicates that caller may try again
 * with another command; HWS_BUSY indicates a condition other than
 * (activeCmd != NULL) which prevents the processing of the command. The
 * command will have been enqueued on pendingQ in the latter case. The
 * command will have been ioComplete'd in the HWS_REJECT case.
 */
- (hwStartReturn)hwStart : (commandBuf *)cmdBuf;

/*
 * SCSI device interrupt handler.
 */
- (void)hwInterrupt;

- (void)logRegs;

@end

extern IONamedValue scsiMsgValues[];

#ifdef	DDM_DEBUG
extern IONamedValue scsiPhaseValues[];
#endif	DDM_DEBUG

#ifdef	DEBUG
extern IONamedValue scStateValues[];
#endif	DEBUG

/* end of AMD_Chip.h */
