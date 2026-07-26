/*
 * FloppyDriveInt.h - Internal methods for IOFloppyDrive
 *
 * Internal category methods for low-level floppy controller operations
 */

#import <driverkit/return.h>

// Forward declarations
@class IOFloppyDrive;

/*
 * Internal methods category for IOFloppyDrive.
 */
@interface IOFloppyDrive(Internal)

/*
 * Allocate disk structure.
 */
- (IOReturn)allocateDisk;

/*
 * Format a track.
 */
- (IOReturn)fdFormatTrack : (unsigned)track
		       head : (unsigned)head;

/*
 * Generate read/write command.
 */
- (IOReturn)fdGenRwCmd : (unsigned)startBlock
	       blockCount : (unsigned)blockCount
		 fdIoReq : (void *)fdIoReq
		 readFlag : (BOOL)readFlag;

/*
 * Get floppy controller status.
 */
- (IOReturn)fdGetStatus : (unsigned char *)status;

/*
 * Convert logical block to physical cylinder/head/sector.
 */
- (IOReturn)fdLogToPhys : (unsigned)logicalBlock
		     cmdp : (void *)cmdp;

/*
 * Read sector ID.
 */
- (IOReturn)fdReadId : (unsigned)head
		statp : (unsigned char *)statp;

/*
 * Recalibrate drive (seek to track 0).
 */
- (IOReturn)fdRecal;

/*
 * Seek to specific track and head.
 */
- (IOReturn)fdSeek : (unsigned)track
		 head : (unsigned)head;

/*
 * Send command to floppy controller.
 */
- (IOReturn)fdSendCmd : (unsigned char *)cmd;

/*
 * Raw read from disk (internal).
 */
- (IOReturn)rawReadInt : (unsigned)startSector
	       sectCount : (unsigned)sectCount
		  buffer : (unsigned char *)buffer;

/*
 * Read/write block count operation.
 */
- (IOReturn)rwBlockCount : (unsigned)startBlock
	       blockCount : (unsigned)blockCount;

/*
 * Update drive ready state (internal).
 */
- (void)updateReadyStateInt;

@end

/* End of FloppyDriveInt.h */
