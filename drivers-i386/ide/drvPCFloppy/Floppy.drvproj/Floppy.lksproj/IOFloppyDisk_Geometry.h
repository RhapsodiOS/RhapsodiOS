/*
 * IOFloppyDisk_Geometry.h
 * Geometry and capacity methods for IOFloppyDisk
 */

#import "IOFloppyDisk.h"

/*
 * Geometry category for IOFloppyDisk
 * Contains geometry accessor and calculation methods
 */
@interface IOFloppyDisk(Geometry)

// Geometry accessors with various naming conventions
- (unsigned int)cylinderFromBlockNumber:(unsigned int)blockNum;
- (unsigned int)headFromBlockNumber:(unsigned int)blockNum;
- (unsigned int)sectorFromBlockNumber:(unsigned int)blockNum;

// Cache methods from cylinder number
- (void *)cachePointerFromCylinderNumber:(unsigned int)cylNum;
- (unsigned int)cacheUnderNumberForBlockNumber:(unsigned int)blockNum;

// Size and capacity methods with different naming
- (unsigned int)sizeListFromCapacities;
- (unsigned int)capacityFromSize;
- (unsigned long long)diskSizeInBytes;

// Block count methods
- (unsigned int)rwBlockCount:(void *)blockStruct;
- (unsigned int)genCwdBlockCount:(void *)blockStruct;
- (unsigned int)fdGenCwd:(void *)cwd;

@end
