/*
 * Bsd.h - BSD device interface support for IOFloppyDisk
 *
 * Category methods for BSD device node attachment
 */

#import <driverkit/return.h>

// Forward declaration
@class IOFloppyDisk;

/*
 * BSD device interface methods category for IOFloppyDisk.
 */
@interface IOFloppyDisk(Bsd)

/*
 * Class method: Get block device number for a drive.
 *
 * Parameters:
 *   drive - Drive object
 *
 * Returns:
 *   Block device number (dev_t)
 */
+ (unsigned int)_blockDevOfDrive:(id)drive;

/*
 * Class method: Get character device number for a drive.
 *
 * Parameters:
 *   drive - Drive object
 *
 * Returns:
 *   Character device number (dev_t)
 */
+ (unsigned int)_characterDevOfDrive:(id)drive;

/*
 * Class method: Get drive number from drive object.
 *
 * Parameters:
 *   drive - Drive object
 *
 * Returns:
 *   Drive number (0-3)
 */
+ (unsigned int)_driveNumberOfDrive:(id)drive;

/*
 * Class method: Register a drive with the BSD device system.
 *
 * Parameters:
 *   drive - Drive object to register
 *
 * Returns:
 *   IOReturn status code
 */
+ (IOReturn)_registerDrive:(id)drive;

/*
 * Class method: Unregister a drive from the BSD device system.
 *
 * Parameters:
 *   drive - Drive object to unregister
 *
 * Returns:
 *   IOReturn status code
 */
+ (IOReturn)_unregisterDrive:(id)drive;

@end

/*
 * BsdLocal methods category for IOFloppyDisk.
 */
@interface IOFloppyDisk(BsdLocal)

/*
 * Attach BSD disk interface to a drive.
 */
- (IOReturn)_attachBsdDiskInterfaceToDrive:(id)drive;

/*
 * Detach BSD disk interface from a drive.
 */
- (IOReturn)_detachBsdDiskInterfaceFromDrive:(id)drive;

@end

/* End of Bsd.h */
