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
- (IOReturn)_fdEjectInt;

/*
 * Common read/write operation.
 */
- (IOReturn)_fdRwCommon : (BOOL)isRead
		    block : (unsigned)block
		 blockCnt : (unsigned)blockCnt
		   buffer : (unsigned char *)buffer
		   client : (vm_task_t)client
	     actualLength : (unsigned *)actualLength;

/*
 * Log read/write error.
 */
- (void)_logRwErr : (unsigned)operation
	      block : (unsigned)block
	     status : (unsigned char *)status
	   readFlag : (BOOL)readFlag;

/*
 * Check if motor should be turned off.
 */
- (void)_motorOffCheck;

/*
 * Set disk density (internal).
 */
- (IOReturn)_setDensityInt : (unsigned)density;

/*
 * Set sector size (internal).
 */
- (IOReturn)_setSectSizeInt : (unsigned)sectorSize;

/*
 * Update physical parameters (internal).
 */
- (void)_updatePhysicalParametersInt;

@end

/* End of FloppyDriveInt2.h */
