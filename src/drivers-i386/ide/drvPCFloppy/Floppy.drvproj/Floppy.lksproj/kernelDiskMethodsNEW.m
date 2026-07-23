/*
 * kernelDiskMethodsNEW.m - Kernel disk methods implementation for IODiskNEW
 *
 * This file contains the category implementations for kernel-level disk operations.
 */

#import "kernelDiskMethodsNEW.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <bsd/sys/buf.h>

#ifdef KERNEL

/*
 * Category: kernelDiskMethods
 */
@implementation IODiskNEW(kernelDiskMethods)

/*
 * Get dev and id info.
 */
- (IODevAndIdInfoNEW *)_devAndIdInfo
{
	return (IODevAndIdInfoNEW *)_devAndIdInfo;
}

/*
 * Set dev and id info.
 */
- (void)_setDevAndIdInfo : (IODevAndIdInfoNEW *)info
{
	_devAndIdInfo = info;
}

/*
 * Get block device.
 * Returns the block device number from the device-to-id mapping structure.
 */
- (dev_t)_blockDev
{
	IODevAndIdInfoNEW *devIdInfo = (IODevAndIdInfoNEW *)_devAndIdInfo;
	
	// Return blockDev field directly from the structure
	return devIdInfo->blockDev;
}

/*
 * Get raw device.
 * Returns the raw device number from the device-to-id mapping structure.
 */
- (dev_t)_rawDev
{
	IODevAndIdInfoNEW *devIdInfo = (IODevAndIdInfoNEW *)_devAndIdInfo;
	
	// Return rawDev field directly from the structure
	return devIdInfo->rawDev;
}

/*
 * Complete transfer.
 * Completes a block I/O transfer by setting appropriate flags and errors,
 * then calling biodone() to notify the system.
 */
- (void)_completeTransfer : (void *)pending
	       withStatus : (IOReturn)status
	     actualLength : (unsigned)actualLength
{
	struct buf *bp = (struct buf *)pending;
	int errno;

	// If there was an error, set the B_ERROR flag in b_flags
	if (status != IO_R_SUCCESS) {
		bp->b_flags |= B_ERROR;
	}

	// Convert IOReturn to errno and set in buffer
	errno = [self _errnoFromReturn:status];
	bp->b_error = errno;

	// Calculate residual count (bytes not transferred)
	// b_resid = b_bcount - actualLength
	bp->b_resid = bp->b_bcount - actualLength;

	// Mark I/O operation as complete
	biodone(bp);
}

@end

/*
 * Category: kernelDiskMethodsPrivate
 */
@implementation IODiskNEW(kernelDiskMethodsPrivate)

/*
 * Register Unix disk.
 * Registers this disk object in the device-to-id mapping structure
 * at the specified partition index.
 */
- (IOReturn)_registerUnixDisk : (int)partition
{
	IODevAndIdInfoNEW *devIdInfo = (IODevAndIdInfoNEW *)_devAndIdInfo;

	// Check for valid partition number (0-6)
	if (partition > 6) {
		IOLog("%s _registerUnixDisk: Bogus partition (%d)\n",
		      [self name], partition);
		return IO_R_INVALID;
	}

	// If this is a physical disk (not a partition), register in liveId
	// Otherwise register in the partitionId array at the specified index
	if (_isPhysical) {
		devIdInfo->liveId = self;
	} else {
		devIdInfo->partitionId[partition] = self;
	}

	return IO_R_SUCCESS;
}

/*
 * Unregister Unix disk.
 * Clears this disk object from the device-to-id mapping structure
 * at the specified partition index.
 */
- (IOReturn)_unregisterUnixDisk : (int)partition
{
	IODevAndIdInfoNEW *devIdInfo = (IODevAndIdInfoNEW *)_devAndIdInfo;

	// Check for valid partition number (0-6)
	if (partition > 6) {
		IOLog("%s _unregisterUnixDisk: Bogus partition (%d)\n",
		      [self name], partition);
		return IO_R_INVALID;
	}

	// If this is a physical disk (not a partition), clear liveId
	// Otherwise clear the partitionId array at the specified index
	if (_isPhysical) {
		devIdInfo->liveId = nil;
	} else {
		devIdInfo->partitionId[partition] = nil;
	}

	return IO_R_SUCCESS;
}

@end

#endif KERNEL
