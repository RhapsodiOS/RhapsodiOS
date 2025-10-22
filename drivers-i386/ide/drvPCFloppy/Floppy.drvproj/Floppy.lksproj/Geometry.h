/*
 * Geometry.h - Geometry support methods for IOFloppyDisk
 *
 * Category methods for disk geometry calculations and cache management
 */

#import <driverkit/return.h>

// Forward declaration
@class IOFloppyDisk;

/*
 * Geometry methods category for IOFloppyDisk.
 */
@interface IOFloppyDisk(Geometry)

/*
 * Calculate blocks remaining to end of cylinder from given block number.
 */
- (unsigned)_blocksToEndOfCylinderFromBlockNumber:(unsigned)blockNumber;

/*
 * Get cache pointer from block number.
 */
- (void *)_cachePointerFromBlockNumber:(unsigned)blockNumber;

/*
 * Get cache pointer from cylinder number.
 */
- (void *)_cachePointerFromCylinderNumber:(unsigned)cylinderNumber;

/*
 * Calculate cylinder number from block number and get head/sector.
 */
- (unsigned)_cylinderFromBlockNumber:(unsigned)blockNumber
                                head:(unsigned *)head
                              sector:(unsigned *)sector;

@end

/* End of Geometry.h */
