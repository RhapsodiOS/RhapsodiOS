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
 * Class method: Get capacity from disk size.
 *
 * Parameters:
 *   diskSize - Size of the disk
 *
 * Returns:
 *   Capacity value corresponding to the disk size
 */
+ (unsigned int)_capacityFromSize:(unsigned int)diskSize;

/*
 * Class method: Get geometry from capacity.
 *
 * Parameters:
 *   capacity - Disk capacity value
 *
 * Returns:
 *   Pointer to geometry structure for the given capacity
 */
+ (void *)_geometryOfCapacity:(unsigned int)capacity;

/*
 * Class method: Create size list from capacities.
 *
 * Parameters:
 *   capacities - Bitmask of capacity identifiers
 *   sizeList   - Output array to store size values (NULL-terminated)
 *
 * Returns:
 *   IOReturn status code
 */
+ (IOReturn)_sizeListFromCapacities:(unsigned int)capacities
                           sizeList:(unsigned int *)sizeList;

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
