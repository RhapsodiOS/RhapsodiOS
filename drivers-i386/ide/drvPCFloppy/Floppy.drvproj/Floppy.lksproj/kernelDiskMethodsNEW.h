/*
 * kernelDiskMethodsNEW.h - Kernel disk methods for IODiskNEW
 *
 * This file contains the category declarations for kernel-level disk operations.
 */

#import "IODiskNEW.h"

#ifdef KERNEL
#import <bsd/sys/types.h>
#import <bsd/sys/disktab.h>

/*
 * The Unix-level code associated with a particular subclass of IODiskNEW
 * keeps an array of these to allow mapping from a dev_t to a IODiskNEW
 * id. One per Unix unit (a unit is a physical disk). The _devAndIdInfo
 * instance variable for an instances of a given class of IODiskNEW
 * points to the one element in a static array of IODevToIdMap's for
 * that class.
 */
typedef struct {
	id liveId;			// IODiskNEW/... for live partition
	id partitionId[NPART-1];	// for block and raw devices
	dev_t rawDev;			// used by volCheck logic
	dev_t blockDev;			// ditto
} IODevAndIdInfoNEW;

/*
 * Category for kernel disk methods.
 */
@interface IODiskNEW(kernelDiskMethods)

- (IODevAndIdInfoNEW *)_devAndIdInfo;
- (void)_setDevAndIdInfo	: (IODevAndIdInfoNEW *)info;
- (dev_t)_blockDev;
- (dev_t)_rawDev;
- (void)_completeTransfer	: (void *)pending
		withStatus	: (IOReturn)status
		actualLength	: (unsigned)actualLength;

@end

/*
 * Category for private kernel disk methods.
 */
@interface IODiskNEW(kernelDiskMethodsPrivate)

- (IOReturn)_registerUnixDisk	: (int)partition;
- (IOReturn)_unregisterUnixDisk	: (int)partition;

@end

#endif KERNEL
