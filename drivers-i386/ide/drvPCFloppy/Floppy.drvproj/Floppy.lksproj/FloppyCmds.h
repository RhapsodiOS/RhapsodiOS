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
- (IOReturn)_doCmdXfr:(void *)cmdParams;

/*
 * Eject the floppy disk.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)_doEject:(void *)cmdParams;

/*
 * Turn off the drive motor.
 *
 * Parameters:
 *   driveNum - Drive number (0-3)
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)_doMotorOff:(unsigned int)driveNum;

/*
 * Turn on the drive motor.
 *
 * Parameters:
 *   driveNum - Drive number (0-3)
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)_doMotorOn:(unsigned int)driveNum;

/*
 * Send a command to the floppy controller.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)_sendCmd:(void *)cmdParams;

@end

/*
 * External DMA functions
 */
extern unsigned int _get_dma_addr(int channel);
extern unsigned int _get_dma_count(int channel);
extern void _dma_xfer_abort(void *dmaStruct);

#endif // _BSD_DEV_I386_FLOPPYCMDS_H_

#endif // DRIVER_PRIVATE

/* End of FloppyCmds.h */
