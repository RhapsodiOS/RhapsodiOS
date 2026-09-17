/*
 * FloppyCntIo.h - Low-level I/O methods for FloppyController
 *
 * This category contains low-level hardware I/O methods for the floppy controller
 */

#ifdef DRIVER_PRIVATE

#ifndef _BSD_DEV_I386_FLOPPYCNTIO_H_
#define _BSD_DEV_I386_FLOPPYCNTIO_H_

#import "FloppyCnt.h"
#import <driverkit/return.h>

/*
 * I/O category for FloppyController.
 * Contains low-level hardware I/O and interrupt handling methods.
 */
@interface FloppyController(IO)

/*
 * Clear polling interrupt flag.
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)clearPollIntr;

/*
 * Send CONFIGURE command to controller.
 *
 * Parameters:
 *   configByte - Configuration byte value
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)doConfigure:(unsigned char)configByte;

/*
 * Send PERPENDICULAR MODE command.
 *
 * Parameters:
 *   perpendicularMode - Perpendicular mode value
 *   gap              - Gap length
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)doPerpendicular:(unsigned char)perpendicularMode gap:(unsigned char)gap;

/*
 * Send SPECIFY command to set controller timing.
 *
 * Parameters:
 *   density - Media density setting (1=500kbps, 2=300kbps, 3=1Mbps)
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)doSpecify:(unsigned int)density;

/*
 * Read a byte from the controller FIFO.
 *
 * Parameters:
 *   bytePtr - Pointer to store the read byte
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)fcGetByte:(unsigned char *)bytePtr;

/*
 * Send a byte to the controller FIFO.
 *
 * Parameters:
 *   byte - Byte to send
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)fcSendByte:(unsigned char)byte;

/*
 * Wait for controller interrupt.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *   timeout   - Timeout in milliseconds
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)fcWaitIntr:(void *)cmdParams timeout:(unsigned int)timeout;

/*
 * Wait for controller ready for PIO.
 *
 * Parameters:
 *   dioMask - DIO bit mask (0x40 for read, 0 for write)
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)fcWaitPio:(unsigned int)dioMask;

/*
 * Floppy interrupt handler.
 * This is called when the floppy controller generates an interrupt.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)floppyInterrupt:(void *)cmdParams;

/*
 * Flush pending interrupt messages.
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)flushIntrMsgs;

/*
 * Get drive status using SENSE DRIVE STATUS command.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)getDriveStatus:(void *)cmdParams;

/*
 * Reset the i82077 floppy controller.
 *
 * Parameters:
 *   message - Error message string or NULL/0 for silent reset
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)i82077Reset:(const char *)message;

/*
 * Recalibrate drive (seek to track 0).
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)recal;

/*
 * Seek to a specific track.
 *
 * Parameters:
 *   track   - Track (cylinder) number
 *   head    - Head number
 *   density - Density setting
 *
 * Returns:
 *   IOReturn status code
 */
- (IOReturn)seek:(unsigned int)track head:(unsigned int)head density:(unsigned int)density;

@end

#endif // _BSD_DEV_I386_FLOPPYCNTIO_H_

#endif // DRIVER_PRIVATE

/* End of FloppyCntIo.h */
