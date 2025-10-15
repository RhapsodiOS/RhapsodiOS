/*
 * IOFloppyDrive_Internal.m
 * Internal implementation for IOFloppyDrive
 */

#import "IOFloppyDrive_Internal.h"
#import "FloppyController.h"
#import <driverkit/generalFuncs.h>

// Sector size info structure
typedef struct {
    unsigned int sectorSize;
    unsigned int sectorsPerTrack;
    unsigned int heads;
    unsigned int cylinders;
    unsigned int totalSectors;
} InternalSectSizeInfo;

// Block info structure
typedef struct {
    unsigned int startBlock;
    unsigned int blockCount;
    unsigned int blockSize;
    void *buffer;
} BlockInfo;

// Sector info structure
typedef struct {
    unsigned int cylinder;
    unsigned int head;
    unsigned int sector;
    unsigned int sectorSize;
    void *buffer;
    unsigned int flags;
} SectorInfo;

// Current working directory structure
typedef struct {
    unsigned int cylinder;
    unsigned int head;
    unsigned int sector;
    unsigned int blockSize;
    unsigned int blockCount;
} CwdInfo;

// Disk allocation info
typedef struct {
    unsigned int totalBlocks;
    unsigned int blockSize;
    void *buffer;
    unsigned int bufferSize;
} DiskAllocInfo;

@implementation IOFloppyDrive(Internal)

- (IOReturn)setSectSizeInt:(unsigned int)size
{
    if (size == 0 || (size & (size - 1)) != 0) {
        IOLog("IOFloppyDrive(Internal): Invalid sector size %d (must be power of 2)\n", size);
        return IO_R_INVALID_ARG;
    }

    [_lock lock];
    _blockSize = size;
    [_lock unlock];

    IOLog("IOFloppyDrive(Internal): Set sector size to %d bytes\n", size);
    return IO_R_SUCCESS;
}

- (IOReturn)setSectSizeInfo:(void *)sizeInfo
{
    InternalSectSizeInfo *info;

    if (sizeInfo == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL size info pointer\n");
        return IO_R_INVALID_ARG;
    }

    info = (InternalSectSizeInfo *)sizeInfo;

    // Validate sector size
    if (info->sectorSize == 0 || (info->sectorSize & (info->sectorSize - 1)) != 0) {
        IOLog("IOFloppyDrive(Internal): Invalid sector size %d\n", info->sectorSize);
        return IO_R_INVALID_ARG;
    }

    [_lock lock];

    _blockSize = info->sectorSize;
    _sectorsPerTrack = info->sectorsPerTrack;
    _heads = info->heads;
    _cylinders = info->cylinders;

    [_lock unlock];

    IOLog("IOFloppyDrive(Internal): Set geometry - size:%d spt:%d heads:%d cyls:%d\n",
          info->sectorSize, info->sectorsPerTrack, info->heads, info->cylinders);

    return IO_R_SUCCESS;
}

- (unsigned int)getSectSizeInt
{
    unsigned int blockSize;

    [_lock lock];
    blockSize = _blockSize;
    [_lock unlock];

    IOLog("IOFloppyDrive(Internal): Get sector size = %d bytes\n", blockSize);
    return blockSize;
}

- (IOReturn)rwReadInt:(void *)buffer
               offset:(unsigned int)offset
               length:(unsigned int)length
               client:(vm_task_t)client
{
    unsigned int actualLength;
    IOReturn status;

    if (buffer == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL buffer pointer\n");
        return IO_R_INVALID_ARG;
    }

    if (length == 0) {
        IOLog("IOFloppyDrive(Internal): Zero length read\n");
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDrive(Internal): Internal read - offset:%d length:%d\n", offset, length);

    status = [self readAt:offset
                   length:length
                   buffer:buffer
             actualLength:&actualLength
                   client:client];

    if (status == IO_R_SUCCESS) {
        IOLog("IOFloppyDrive(Internal): Read %d bytes successfully\n", actualLength);
    } else {
        IOLog("IOFloppyDrive(Internal): Read failed: 0x%x\n", status);
    }

    return status;
}

- (IOReturn)rwBlockCount:(void *)blockInfo
{
    BlockInfo *info;
    unsigned int totalBlocks;

    if (blockInfo == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL block info pointer\n");
        return IO_R_INVALID_ARG;
    }

    info = (BlockInfo *)blockInfo;

    [_lock lock];
    totalBlocks = _cylinders * _heads * _sectorsPerTrack;
    [_lock unlock];

    // Validate and set block count
    if (info->startBlock >= totalBlocks) {
        IOLog("IOFloppyDrive(Internal): Start block %d exceeds capacity %d\n",
              info->startBlock, totalBlocks);
        return IO_R_INVALID_ARG;
    }

    if (info->startBlock + info->blockCount > totalBlocks) {
        info->blockCount = totalBlocks - info->startBlock;
        IOLog("IOFloppyDrive(Internal): Limited block count to %d\n", info->blockCount);
    }

    IOLog("IOFloppyDrive(Internal): Block count operation - start:%d count:%d\n",
          info->startBlock, info->blockCount);

    return IO_R_SUCCESS;
}

- (IOReturn)fdSectInit:(void *)sectInfo
{
    SectorInfo *info;

    if (sectInfo == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL sector info pointer\n");
        return IO_R_INVALID_ARG;
    }

    info = (SectorInfo *)sectInfo;

    [_lock lock];

    // Initialize sector info with default values
    info->cylinder = 0;
    info->head = 0;
    info->sector = 1;  // Sectors are 1-based
    info->sectorSize = _blockSize;
    info->flags = 0;

    [_lock unlock];

    IOLog("IOFloppyDrive(Internal): Initialized sector info - C:%d H:%d S:%d size:%d\n",
          info->cylinder, info->head, info->sector, info->sectorSize);

    return IO_R_SUCCESS;
}

- (IOReturn)formatTrack:(unsigned int)head
{
    unsigned int cylinder;
    IOReturn result;

    [_lock lock];

    if (head >= _heads) {
        [_lock unlock];
        IOLog("IOFloppyDrive(Internal): Invalid head %d (max %d)\n", head, _heads - 1);
        return IO_R_INVALID_ARG;
    }

    [_lock unlock];

    IOLog("IOFloppyDrive(Internal): Formatting all tracks on head %d\n", head);

    // Check for write protection using IODisk method
    if ([self isWriteProtected]) {
        IOLog("IOFloppyDrive(Internal): Disk is write protected\n");
        return IO_R_IO_ERROR;
    }

    // Check controller availability
    if (_controller == nil) {
        IOLog("IOFloppyDrive(Internal): No controller available\n");
        return IO_R_NO_DEVICE;
    }

    // Format all cylinders for this head
    [_lock lock];
    unsigned int cylinders = _cylinders;
    [_lock unlock];

    for (cylinder = 0; cylinder < cylinders; cylinder++) {
        IOLog("IOFloppyDrive(Internal): Formatting C:%d H:%d\n", cylinder, head);

        result = [_controller doFormat:_unit
                              cylinder:cylinder
                                  head:head];
        if (result != IO_R_SUCCESS) {
            IOLog("IOFloppyDrive(Internal): Format failed at C:%d H:%d: 0x%x\n",
                  cylinder, head, result);
            return result;
        }
    }

    IOLog("IOFloppyDrive(Internal): Format completed for head %d\n", head);
    return IO_R_SUCCESS;
}

- (IOReturn)formatHead:(unsigned int)head
{
    IOLog("IOFloppyDrive(Internal): Format head %d\n", head);
    return [self formatTrack:head];
}

- (IOReturn)allocateDisk:(void *)diskInfo
{
    DiskAllocInfo *info;
    unsigned int totalBlocks;

    if (diskInfo == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL disk info pointer\n");
        return IO_R_INVALID_ARG;
    }

    info = (DiskAllocInfo *)diskInfo;

    [_lock lock];
    totalBlocks = _cylinders * _heads * _sectorsPerTrack;
    [_lock unlock];

    // Fill in disk allocation info
    info->totalBlocks = totalBlocks;
    info->blockSize = _blockSize;
    info->bufferSize = totalBlocks * _blockSize;

    // Optionally allocate buffer if requested
    if (info->buffer == NULL && info->bufferSize > 0) {
        info->buffer = IOMalloc(info->bufferSize);
        if (info->buffer == NULL) {
            IOLog("IOFloppyDrive(Internal): Failed to allocate %d bytes\n", info->bufferSize);
            return IO_R_NO_MEMORY;
        }
        IOLog("IOFloppyDrive(Internal): Allocated %d bytes at %p\n",
              info->bufferSize, info->buffer);
    }

    IOLog("IOFloppyDrive(Internal): Disk allocated - blocks:%d size:%d buffer:%p\n",
          info->totalBlocks, info->blockSize, info->buffer);

    return IO_R_SUCCESS;
}

- (IOReturn)fdGenCwd:(void *)cwd blockCount:(unsigned int)count
{
    CwdInfo *cwdInfo;

    if (cwd == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL cwd pointer\n");
        return IO_R_INVALID_ARG;
    }

    cwdInfo = (CwdInfo *)cwd;

    [_lock lock];

    // Generate current working directory info
    cwdInfo->cylinder = _currentCylinder;
    cwdInfo->head = _currentHead;
    cwdInfo->sector = 1;  // Start at sector 1
    cwdInfo->blockSize = _blockSize;
    cwdInfo->blockCount = count;

    // Limit block count to one track
    if (cwdInfo->blockCount > _sectorsPerTrack) {
        cwdInfo->blockCount = _sectorsPerTrack;
        IOLog("IOFloppyDrive(Internal): Limited cwd block count to %d\n", cwdInfo->blockCount);
    }

    [_lock unlock];

    IOLog("IOFloppyDrive(Internal): Generated CWD - C:%d H:%d S:%d count:%d\n",
          cwdInfo->cylinder, cwdInfo->head, cwdInfo->sector, cwdInfo->blockCount);

    return IO_R_SUCCESS;
}

- (IOReturn)readFlag:(unsigned int *)flag
{
    BOOL isReady;

    if (flag == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL flag pointer\n");
        return IO_R_INVALID_ARG;
    }

    // Use IODisk's lastReadyState method
    isReady = ([self lastReadyState] == IO_Ready);

    *flag = isReady ? 1 : 0;

    IOLog("IOFloppyDrive(Internal): Read flag = %d (ready:%d)\n", *flag, isReady);
    return IO_R_SUCCESS;
}

- (IOReturn)fdReadInt:(void *)sectInfo
{
    SectorInfo *info;
    IOReturn status;
    unsigned int offset;
    unsigned int actualLength;

    if (sectInfo == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL sector info pointer\n");
        return IO_R_INVALID_ARG;
    }

    info = (SectorInfo *)sectInfo;

    // Validate CHS
    [_lock lock];

    if (info->cylinder >= _cylinders) {
        [_lock unlock];
        IOLog("IOFloppyDrive(Internal): Invalid cylinder %d (max %d)\n",
              info->cylinder, _cylinders - 1);
        return IO_R_INVALID_ARG;
    }

    if (info->head >= _heads) {
        [_lock unlock];
        IOLog("IOFloppyDrive(Internal): Invalid head %d (max %d)\n",
              info->head, _heads - 1);
        return IO_R_INVALID_ARG;
    }

    if (info->sector < 1 || info->sector > _sectorsPerTrack) {
        [_lock unlock];
        IOLog("IOFloppyDrive(Internal): Invalid sector %d (range 1-%d)\n",
              info->sector, _sectorsPerTrack);
        return IO_R_INVALID_ARG;
    }

    // Convert CHS to byte offset
    unsigned int sectorsPerCylinder = _heads * _sectorsPerTrack;
    unsigned int blockNumber = (info->cylinder * sectorsPerCylinder) +
                               (info->head * _sectorsPerTrack) +
                               (info->sector - 1);  // Sectors are 1-based
    offset = blockNumber * _blockSize;

    [_lock unlock];

    IOLog("IOFloppyDrive(Internal): Reading sector C:%d H:%d S:%d (offset %d)\n",
          info->cylinder, info->head, info->sector, offset);

    // Perform the read
    if (info->buffer == NULL) {
        IOLog("IOFloppyDrive(Internal): NULL buffer in sector info\n");
        return IO_R_INVALID_ARG;
    }

    status = [self readAt:offset
                   length:info->sectorSize
                   buffer:info->buffer
             actualLength:&actualLength
                   client:IOVmTaskSelf()];

    if (status == IO_R_SUCCESS) {
        IOLog("IOFloppyDrive(Internal): Read sector successfully (%d bytes)\n", actualLength);
    } else {
        IOLog("IOFloppyDrive(Internal): Read sector failed: 0x%x\n", status);
    }

    return status;
}

@end
