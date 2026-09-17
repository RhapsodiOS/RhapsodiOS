/*
 * Geometry.h - Geometry support methods for IOFloppyDisk
 *
 * Category methods for disk geometry calculations and cache management
 */

#import <driverkit/return.h>
#import <driverkit/driverTypes.h>

/* Geometry lookup tables (Geometry.m) */
extern unsigned int fdDiskInfo[];
extern unsigned int fdDensityInfo[];
extern unsigned int fdDensitySectsize[];
extern unsigned int *fdGetSectSizeInfo(unsigned int density);

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
+ (unsigned int)capacityFromSize:(unsigned int)diskSize;

/*
 * Class method: Get geometry from capacity.
 *
 * Parameters:
 *   capacity - Disk capacity value
 *
 * Returns:
 *   Pointer to geometry structure for the given capacity
 */
+ (void *)geometryOfCapacity:(unsigned int)capacity;

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
+ (IOReturn)sizeListFromCapacities:(unsigned int)capacities
                           sizeList:(unsigned int *)sizeList;

/*
 * Calculate blocks remaining to end of cylinder from given block number.
 */
- (unsigned)blocksToEndOfCylinderFromBlockNumber:(unsigned)blockNumber;

/*
 * Get cache pointer from block number.
 */
- (void *)cachePointerFromBlockNumber:(unsigned)blockNumber;

/*
 * Get cache pointer from cylinder number.
 */
- (void *)cachePointerFromCylinderNumber:(unsigned)cylinderNumber;

/*
 * Calculate cylinder number from block number and get head/sector.
 */
- (unsigned)cylinderFromBlockNumber:(unsigned)blockNumber
                                   :(unsigned *)head
                                   :(unsigned *)sector;

@end

/* End of Geometry.h */
