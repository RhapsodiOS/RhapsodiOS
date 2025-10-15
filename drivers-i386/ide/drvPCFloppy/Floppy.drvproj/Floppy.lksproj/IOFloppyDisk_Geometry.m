/*
 * IOFloppyDisk_Geometry.m
 * Geometry and capacity implementation for IOFloppyDisk
 */

#import "IOFloppyDisk_Geometry.h"
#import <driverkit/generalFuncs.h>

// Block structure for r/w operations
typedef struct {
    unsigned int startBlock;
    unsigned int blockCount;
    void *buffer;
} BlockStruct;

// Current working directory structure
typedef struct {
    unsigned int cylinder;
    unsigned int head;
    unsigned int sector;
    unsigned int blockSize;
} CwdStruct;

@implementation IOFloppyDisk(Geometry)

- (unsigned int)cylinderFromBlockNumber:(unsigned int)blockNum
{
    unsigned int sectorsPerCylinder;
    unsigned int cylinder;

    [_lock lock];

    if (_heads == 0 || _sectorsPerTrack == 0) {
        [_lock unlock];
        IOLog("IOFloppyDisk(Geometry): Invalid geometry (heads:%d spt:%d)\n",
              _heads, _sectorsPerTrack);
        return 0;
    }

    sectorsPerCylinder = _heads * _sectorsPerTrack;
    cylinder = blockNum / sectorsPerCylinder;

    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Block %d -> Cylinder %d\n", blockNum, cylinder);
    return cylinder;
}

- (unsigned int)headFromBlockNumber:(unsigned int)blockNum
{
    unsigned int head;

    [_lock lock];

    if (_sectorsPerTrack == 0 || _heads == 0) {
        [_lock unlock];
        IOLog("IOFloppyDisk(Geometry): Invalid geometry (heads:%d spt:%d)\n",
              _heads, _sectorsPerTrack);
        return 0;
    }

    head = (blockNum / _sectorsPerTrack) % _heads;

    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Block %d -> Head %d\n", blockNum, head);
    return head;
}

- (unsigned int)sectorFromBlockNumber:(unsigned int)blockNum
{
    unsigned int sector;

    [_lock lock];

    if (_sectorsPerTrack == 0) {
        [_lock unlock];
        IOLog("IOFloppyDisk(Geometry): Invalid geometry (spt:%d)\n", _sectorsPerTrack);
        return 1;  // Return 1 as sectors are 1-based
    }

    // Sectors are 1-based on floppy disks
    sector = (blockNum % _sectorsPerTrack) + 1;

    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Block %d -> Sector %d\n", blockNum, sector);
    return sector;
}

- (void *)cachePointerFromCylinderNumber:(unsigned int)cylNum
{
    void *pointer;

    [_lock lock];

    // Check if cylinder is within valid range
    if (cylNum >= _cylinders) {
        [_lock unlock];
        IOLog("IOFloppyDisk(Geometry): Invalid cylinder %d (max %d)\n",
              cylNum, _cylinders - 1);
        return NULL;
    }

    // Update cache under number for this cylinder
    _cacheUnderNumber = cylNum;

    // Return cached pointer (or NULL if no cache)
    pointer = _cachePointer;

    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Cache pointer for cylinder %d = %p\n",
          cylNum, pointer);

    return pointer;
}

- (unsigned int)cacheUnderNumberForBlockNumber:(unsigned int)blockNum
{
    unsigned int trackNumber;

    [_lock lock];

    if (_sectorsPerTrack == 0) {
        [_lock unlock];
        IOLog("IOFloppyDisk(Geometry): Invalid geometry (spt:%d)\n", _sectorsPerTrack);
        return 0;
    }

    // Track number is the cache unit for floppy disks
    trackNumber = blockNum / _sectorsPerTrack;

    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Block %d -> Track %d\n", blockNum, trackNumber);
    return trackNumber;
}

- (unsigned int)sizeListFromCapacities
{
    unsigned int sizeInBytes;

    [_lock lock];
    sizeInBytes = _capacity * _blockSize;
    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Size from capacities = %d bytes\n", sizeInBytes);
    return sizeInBytes;
}

- (unsigned int)capacityFromSize
{
    unsigned int capacity;

    [_lock lock];
    capacity = _capacity;
    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Capacity = %d blocks\n", capacity);
    return capacity;
}

- (unsigned long long)diskSizeInBytes
{
    unsigned long long sizeInBytes;

    [_lock lock];
    sizeInBytes = (unsigned long long)_capacity * _blockSize;
    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Disk size = %llu bytes\n", sizeInBytes);
    return sizeInBytes;
}

- (unsigned int)rwBlockCount:(void *)blockStruct
{
    BlockStruct *bs;
    unsigned int count;

    if (blockStruct == NULL) {
        IOLog("IOFloppyDisk(Geometry): NULL block struct\n");
        return 0;
    }

    bs = (BlockStruct *)blockStruct;

    // Validate block range
    [_lock lock];

    if (bs->startBlock >= _capacity) {
        [_lock unlock];
        IOLog("IOFloppyDisk(Geometry): Start block %d exceeds capacity %d\n",
              bs->startBlock, _capacity);
        return 0;
    }

    // Calculate maximum blocks we can transfer
    count = bs->blockCount;
    if (bs->startBlock + count > _capacity) {
        count = _capacity - bs->startBlock;
        IOLog("IOFloppyDisk(Geometry): Limiting block count from %d to %d\n",
              bs->blockCount, count);
    }

    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): R/W block count = %d\n", count);
    return count;
}

- (unsigned int)genCwdBlockCount:(void *)blockStruct
{
    BlockStruct *bs;
    unsigned int count;

    if (blockStruct == NULL) {
        IOLog("IOFloppyDisk(Geometry): NULL block struct for genCwd\n");
        return 0;
    }

    bs = (BlockStruct *)blockStruct;

    [_lock lock];

    // For floppy, limit to one track at a time
    count = bs->blockCount;
    if (count > _sectorsPerTrack) {
        count = _sectorsPerTrack;
        IOLog("IOFloppyDisk(Geometry): Limiting genCwd block count to track size: %d\n",
              count);
    }

    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): GenCwd block count = %d\n", count);
    return count;
}

- (unsigned int)fdGenCwd:(void *)cwd
{
    CwdStruct *cwdStruct;
    unsigned int result;

    if (cwd == NULL) {
        IOLog("IOFloppyDisk(Geometry): NULL cwd structure\n");
        return IO_R_INVALID_ARG;
    }

    cwdStruct = (CwdStruct *)cwd;

    [_lock lock];

    // Fill in current working directory information
    cwdStruct->cylinder = 0;  // Start at cylinder 0
    cwdStruct->head = 0;      // Start at head 0
    cwdStruct->sector = 1;    // Sectors are 1-based
    cwdStruct->blockSize = _blockSize;

    result = IO_R_SUCCESS;

    [_lock unlock];

    IOLog("IOFloppyDisk(Geometry): Generated CWD - C:%d H:%d S:%d BS:%d\n",
          cwdStruct->cylinder, cwdStruct->head, cwdStruct->sector, cwdStruct->blockSize);

    return result;
}

@end
