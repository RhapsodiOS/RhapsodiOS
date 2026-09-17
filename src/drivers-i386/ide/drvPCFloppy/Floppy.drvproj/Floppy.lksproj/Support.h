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
- (void)releaseCache;

/*
 * Set up cylinder cache.
 */
- (BOOL)setUpCache;

@end

/* End of Support.h */
