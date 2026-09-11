/*
 * FloppyDriveInt2.h - Additional internal methods for IOFloppyDrive
 *
 * Second internal category for higher-level floppy operations
 */

#import <driverkit/return.h>

// Forward declarations
@class IOFloppyDrive;

/*
 * Internal2 methods category for IOFloppyDrive.
 */
@interface IOFloppyDrive(Internal2)

/*
 * Eject disk (internal).
 */
- (IOReturn)fdEjectInt;

/*
 * Common read/write operation.
 */
- (IOReturn)fdRwCommon : (BOOL)isRead
		    block : (unsigned)block
		 blockCnt : (unsigned)blockCnt
		   buffer : (unsigned char *)buffer
		   client : (vm_task_t)client
	     actualLength : (unsigned *)actualLength;

/*
 * Log read/write error.
 */
- (void)logRwErr : (const char *)operation
	      block : (unsigned)block
	     status : (unsigned)status
	   readFlag : (BOOL)readFlag;

/*
 * Check if motor should be turned off.
 */
- (void)motorOffCheck;

/*
 * Set disk density (internal).
 */
- (IOReturn)setDensityInt : (unsigned)density;

/*
 * Set sector size (internal).
 */
- (IOReturn)setSectSizeInt : (unsigned)sectorSize;

/*
 * Update physical parameters (internal).
 */
- (void)updatePhysicalParametersInt;

@end

/* End of FloppyDriveInt2.h */
