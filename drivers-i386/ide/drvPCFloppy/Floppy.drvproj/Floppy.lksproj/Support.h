/*
 * Support.h - Support methods for IOFloppyDisk
 *
 * Category methods for cache management and support operations
 */

#import <driverkit/return.h>

// Forward declaration
@class IOFloppyDisk;

/*
 * Support methods category for IOFloppyDisk.
 */
@interface IOFloppyDisk(Support)

/*
 * Release cylinder cache.
 */
- (void)_releaseCache;

/*
 * Set up cylinder cache.
 */
- (BOOL)_setUpCache;

@end

/* End of Support.h */
