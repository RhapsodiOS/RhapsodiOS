/*
 * VolCheck.h - Volume check support methods for IOFloppyDrive
 *
 * Category methods for volume checking and disk change detection
 */

#import <driverkit/return.h>
#import "IODiskProtocols.h"

// Forward declarations
@class IOFloppyDrive;

/*
 * VolCheckSupport methods category for IOFloppyDrive.
 */
@interface IOFloppyDrive(volCheckSupport) <IODriveVolCheckSupport>

/*
 * Abort pending volume check request.
 */
- (void)abortRequest;

/*
 * Handle disk became ready event.
 */
- (void)diskBecameReady;

/*
 * Check if disk is formatted.
 */
- (BOOL)isFormatted;

/*
 * Check if this is a physical device.
 */
- (BOOL)isPhysical;

/*
 * Check if disk is removable.
 */
- (BOOL)isRemovable;

/*
 * Check if disk is write protected.
 */
- (BOOL)isWriteProtected;

/*
 * Check if manual polling is needed for disk change detection.
 */
- (BOOL)needsManualPolling;

/*
 * Get next logical disk in chain.
 */
- (id)nextLogicalDisk;

/*
 * Register for volume check notifications.
 */
- (IOReturn)registerVolCheck;

/*
 * Unregister from volume check notifications.
 */
- (IOReturn)unregisterVolCheck;

/*
 * Update physical disk parameters.
 */
- (IOReturn)updatePhysicalParameters;

/*
 * Update ready state.
 */
- (int)updateReadyState;

@end

/* End of VolCheck.h */
