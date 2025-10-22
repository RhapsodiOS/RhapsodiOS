/*
 * VolCheck.m - Volume check support methods for IOFloppyDrive
 *
 * Category methods for volume checking and disk change detection
 */

#import "IOFloppyDrive.h"
#import "VolCheck.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IOFloppyDrive(volCheckSupport)

/*
 * Abort pending volume check request.
 * From decompiled code: empty function (no abort needed).
 */
- (void)_abortRequest
{
	// No operation required
	return;
}

/*
 * Handle disk became ready event.
 * From decompiled code: empty function (handling done elsewhere).
 */
- (void)_diskBecameReady
{
	// No operation required
	return;
}

/*
 * Check if disk is formatted.
 * From decompiled code: checks bit 0 of flags.
 */
- (BOOL)_isFormatted
{
	// Return bit 0 of flags (offset 0x18c)
	return _flags & 1;
}

/*
 * Check if this is a physical device.
 * From decompiled code: checks bit 1 of offset 0x16c.
 */
- (BOOL)_isPhysical
{
	// Check bit 1 of _regFlags
	// Returns YES (1) if bit 1 is clear, NO (0) if bit 1 is set
	if ((_regFlags & 2) == 0) {
		return YES;
	}
	return NO;
}

/*
 * Check if disk is removable.
 * From decompiled code: always returns YES.
 */
- (BOOL)_isRemovable
{
	// Floppy disks are always removable
	return YES;
}

/*
 * Check if disk is write protected.
 * From decompiled code: checks bit 2 of flags.
 */
- (BOOL)_isWriteProtected
{
	// Return bit 2 of flags (offset 0x18c)
	return _flags & 4;
}

/*
 * Check if manual polling is needed for disk change detection.
 * From decompiled code: returns opposite of canPollInexpensively.
 */
- (BOOL)_needsManualPolling
{
	BOOL canPollInexpensively;
	
	// Check if we can poll inexpensively
	canPollInexpensively = [self canPollInexpensively];
	
	// Return the opposite (need manual polling if can't poll inexpensively)
	return !canPollInexpensively;
}

/*
 * Get next logical disk in chain.
 * From decompiled code: delegates to disk object at offset 0x108.
 */
- (id)_nextLogicalDisk
{
	id diskObject;
	id nextDisk;
	
	// Get disk object from offset 0x108 (_nextLogicalDisk)
	diskObject = _nextLogicalDisk;
	
	// Call nextLogicalDisk method on the disk object
	nextDisk = [diskObject nextLogicalDisk];
	
	return nextDisk;
}

/*
 * Register for volume check notifications.
 * From decompiled code: gets character and block devices, registers with volCheck.
 */
- (IOReturn)_registerVolCheck
{
	id characterDev;
	id blockDev;
	
	// Get character device for this drive
	characterDev = [IOFloppyDisk characterDevOfDrive:self];
	
	// Get block device for this drive
	blockDev = [IOFloppyDisk blockDevOfDrive:self];
	
	// Register with volume check subsystem
	volCheckRegister(self, blockDev);
	
	return IO_R_SUCCESS;
}

/*
 * Unregister from volume check notifications.
 * From decompiled code: calls volCheckUnregister.
 */
- (IOReturn)_unregisterVolCheck
{
	// Unregister from volume check subsystem
	volCheckUnregister(self);
	
	return IO_R_SUCCESS;
}

/*
 * Update physical disk parameters.
 * From decompiled code: returns 0 (no operation).
 */
- (IOReturn)_updatePhysicalParameters
{
	// No operation required for volCheck interface
	// Actual work done by internal methods
	return IO_R_SUCCESS;
}

/*
 * Update ready state.
 * From decompiled code: polls media and returns ready state.
 */
- (int)_updateReadyState
{
	BOOL mediaPresent;
	int readyState;
	
	// Poll for media presence
	mediaPresent = [self pollMedia];
	
	// Return ready state based on poll result
	// 0 = ready, 2 = not ready
	if (mediaPresent) {
		readyState = 0;  // Ready
	} else {
		readyState = 2;  // Not ready
	}
	
	return readyState;
}

@end

/* End of VolCheck.m */
