/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_x86.h - architecture-specific methods for AMD SCSI driver
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */

#import "AMD_SCSI.h"

@interface AMD_SCSI(Architecture)

/*
 * Perform one-time-only architecture-specific init.
 */
- archInit 			: deviceDescription;

/*
 * Ensure DMA machine is in idle quiescent state.
 */
- (void)dmaIdle;

/*
 * Start DMA transfer at activeCmd->currentPtr for activeCmd->currentByteCount.
 */
- (sc_status_t)dmaStart;

/*
 * Terminate a DMA, including FIFO flush if necessary. Returns number of 
 * bytes transferred.
 */
- (unsigned)dmaTerminate;

@end

