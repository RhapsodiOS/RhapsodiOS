/*
 * Bsd.h - BSD device interface support for IOFloppyDisk
 *
 * Category methods for BSD device node attachment
 */

#import <driverkit/return.h>

// Forward declaration
@class IOFloppyDisk;

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
