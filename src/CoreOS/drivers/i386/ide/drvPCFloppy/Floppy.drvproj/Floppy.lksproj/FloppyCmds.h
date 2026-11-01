/*
 * FloppyCmds.h - Command methods for FloppyController
 *
 * This category contains high-level command methods for the floppy controller
 */

#ifdef DRIVER_PRIVATE

#ifndef _BSD_DEV_I386_FLOPPYCMDS_H_
#define _BSD_DEV_I386_FLOPPYCMDS_H_

#import "FloppyCnt.h"
#import <driverkit/return.h>

/*
 * Command category for FloppyController.
 * Contains high-level command execution methods.
 */
@interface FloppyController(Cmds)

/*
 * Execute a command transfer.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)doCmdXfr:(void *)cmdParams;

/*
 * Eject the floppy disk.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)doEject:(void *)cmdParams;

/*
 * Turn off the drive motor.
 *
 * Parameters:
 *   driveNum - Drive number (0-3)
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)doMotorOff:(unsigned int)driveNum;

/*
 * Turn on the drive motor.
 *
 * Parameters:
 *   driveNum - Drive number (0-3)
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)doMotorOn:(unsigned int)driveNum;

/*
 * Send a command to the floppy controller.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)sendCmd:(void *)cmdParams;

@end

/*
 * External DMA functions
 */
extern unsigned int get_dma_addr(int channel);
extern unsigned int get_dma_count(int channel);
extern void dma_xfer_abort(void *dmaStruct);

#endif // _BSD_DEV_I386_FLOPPYCMDS_H_

#endif // DRIVER_PRIVATE

/* End of FloppyCmds.h */
