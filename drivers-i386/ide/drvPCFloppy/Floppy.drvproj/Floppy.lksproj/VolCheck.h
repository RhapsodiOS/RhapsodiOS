/*
 * VolCheck.h - Volume check support methods for IOFloppyDrive
 *
 * Category methods for volume checking and disk change detection
 */

#import <driverkit/return.h>

// Forward declarations
@class IOFloppyDrive;

/*
 * VolCheckSupport methods category for IOFloppyDrive.
 */
@interface IOFloppyDrive(volCheckSupport)

/*
 * Abort pending volume check request.
 */
- (void)_abortRequest;

/*
 * Handle disk became ready event.
 */
- (void)_diskBecameReady;

/*
 * Check if disk is formatted.
 */
- (BOOL)_isFormatted;

/*
 * Check if this is a physical device.
 */
- (BOOL)_isPhysical;

/*
 * Check if disk is removable.
 */
- (BOOL)_isRemovable;

/*
 * Check if disk is write protected.
 */
- (BOOL)_isWriteProtected;

/*
 * Check if manual polling is needed for disk change detection.
 */
- (BOOL)_needsManualPolling;

/*
 * Get next logical disk in chain.
 */
- (id)_nextLogicalDisk;

/*
 * Register for volume check notifications.
 */
- (IOReturn)_registerVolCheck;

/*
 * Unregister from volume check notifications.
 */
- (IOReturn)_unregisterVolCheck;

/*
 * Update physical disk parameters.
 */
- (IOReturn)_updatePhysicalParameters;

/*
 * Update ready state.
 */
- (int)_updateReadyState;

@end

/* End of VolCheck.h */
