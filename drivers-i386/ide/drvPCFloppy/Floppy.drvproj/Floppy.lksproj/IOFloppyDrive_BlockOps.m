/*
 * IOFloppyDrive_BlockOps.m
 * Block operations implementation for IOFloppyDrive
 */

#import "IOFloppyDrive_BlockOps.h"
#import "FloppyController.h"
#import <driverkit/generalFuncs.h>

// Block structure for r/w operations
typedef struct {
    unsigned int startBlock;
    unsigned int blockCount;
    void *buffer;
    unsigned int flags;
} RWBlockStruct;

// Sector size info structure
typedef struct {
    unsigned int sectorSize;
    unsigned int sectorsPerTrack;
    unsigned int heads;
    unsigned int cylinders;
} SectSizeInfo;

// Status structure
typedef struct {
    BOOL isReady;
    BOOL isWriteProtected;
    BOOL isDiskChanged;
    unsigned int errorCode;
} DriveStatus;

@implementation IOFloppyDrive(BlockOps)

- (IOReturn)rwBlockCount:(void *)blockStruct blockCount:(unsigned int *)count
{
    RWBlockStruct *bs;
    unsigned int totalBlocks;
    unsigned int maxBlocks;

    if (count == NULL) {
        IOLog("IOFloppyDrive(BlockOps): NULL count pointer\n");
        return IO_R_INVALID_ARG;
    }

    [_lock lock];
    totalBlocks = _cylinders * _heads * _sectorsPerTrack;
    [_lock unlock];

    if (blockStruct != NULL) {
        bs = (RWBlockStruct *)blockStruct;

        // Validate and calculate block count
        if (bs->startBlock >= totalBlocks) {
            IOLog("IOFloppyDrive(BlockOps): Start block %d exceeds capacity %d\n",
                  bs->startBlock, totalBlocks);
            *count = 0;
            return IO_R_INVALID_ARG;
        }

        maxBlocks = totalBlocks - bs->startBlock;
        if (bs->blockCount > maxBlocks) {
            IOLog("IOFloppyDrive(BlockOps): Limiting block count from %d to %d\n",
                  bs->blockCount, maxBlocks);
            *count = maxBlocks;
        } else {
            *count = bs->blockCount;
        }
    } else {
        *count = totalBlocks;
    }

    IOLog("IOFloppyDrive(BlockOps): R/W block count = %d (total %d)\n", *count, totalBlocks);
    return IO_R_SUCCESS;
}

- (IOReturn)fdGenCwdBlockCount:(void *)blockInfo count:(unsigned int *)count
{
    unsigned int totalBlocks;
    unsigned int sectorsPerTrack;

    if (count == NULL) {
        IOLog("IOFloppyDrive(BlockOps): NULL count pointer for genCwd\n");
        return IO_R_INVALID_ARG;
    }

    [_lock lock];
    totalBlocks = _cylinders * _heads * _sectorsPerTrack;
    sectorsPerTrack = _sectorsPerTrack;
    [_lock unlock];

    // For floppy drives, limit to one track at a time for CWD operations
    if (blockInfo != NULL) {
        RWBlockStruct *bs = (RWBlockStruct *)blockInfo;
        if (bs->blockCount > sectorsPerTrack) {
            *count = sectorsPerTrack;
            IOLog("IOFloppyDrive(BlockOps): Limiting CWD block count to track size: %d\n", *count);
        } else {
            *count = bs->blockCount;
        }
    } else {
        *count = sectorsPerTrack;
    }

    IOLog("IOFloppyDrive(BlockOps): GenCwd block count = %d\n", *count);
    return IO_R_SUCCESS;
}

- (IOReturn)genCwdBlockCount:(unsigned int *)count
{
    unsigned int totalBlocks;

    if (count == NULL) {
        IOLog("IOFloppyDrive(BlockOps): NULL count pointer\n");
        return IO_R_INVALID_ARG;
    }

    [_lock lock];
    totalBlocks = _cylinders * _heads * _sectorsPerTrack;
    [_lock unlock];

    *count = totalBlocks;

    IOLog("IOFloppyDrive(BlockOps): Total block count = %d\n", *count);
    return IO_R_SUCCESS;
}

- (IOReturn)getSectSizeInt:(unsigned int *)size
{
    unsigned int blockSize;

    if (size == NULL) {
        IOLog("IOFloppyDrive(BlockOps): NULL size pointer\n");
        return IO_R_INVALID_ARG;
    }

    [_lock lock];
    blockSize = _blockSize;
    [_lock unlock];

    *size = blockSize;

    IOLog("IOFloppyDrive(BlockOps): Sector size = %d bytes\n", *size);
    return IO_R_SUCCESS;
}

- (IOReturn)getSectSizeInfo:(void *)info
{
    SectSizeInfo *sizeInfo;

    if (info == NULL) {
        IOLog("IOFloppyDrive(BlockOps): NULL info pointer\n");
        return IO_R_INVALID_ARG;
    }

    sizeInfo = (SectSizeInfo *)info;

    [_lock lock];

    sizeInfo->sectorSize = _blockSize;
    sizeInfo->sectorsPerTrack = _sectorsPerTrack;
    sizeInfo->heads = _heads;
    sizeInfo->cylinders = _cylinders;

    [_lock unlock];

    IOLog("IOFloppyDrive(BlockOps): Sector size info - size:%d spt:%d heads:%d cyls:%d\n",
          sizeInfo->sectorSize, sizeInfo->sectorsPerTrack, sizeInfo->heads, sizeInfo->cylinders);

    return IO_R_SUCCESS;
}

- (IOReturn)fdGetSectSizeInfo:(void *)info
{
    IOLog("IOFloppyDrive(BlockOps): Getting sector size info via fd method\n");
    return [self getSectSizeInfo:info];
}

- (IOReturn)fdGetStatus:(void *)status
{
    DriveStatus *driveStatus;
    IOReturn result;

    if (status == NULL) {
        IOLog("IOFloppyDrive(BlockOps): NULL status pointer\n");
        return IO_R_INVALID_ARG;
    }

    driveStatus = (DriveStatus *)status;

    [_lock lock];

    // Get current drive status using IODisk methods
    driveStatus->isReady = ([self lastReadyState] == IO_Ready);
    driveStatus->isWriteProtected = [self isWriteProtected];
    driveStatus->isDiskChanged = _diskChanged;
    driveStatus->errorCode = 0;

    result = IO_R_SUCCESS;

    [_lock unlock];

    IOLog("IOFloppyDrive(BlockOps): Status - ready:%d wp:%d changed:%d\n",
          driveStatus->isReady, driveStatus->isWriteProtected, driveStatus->isDiskChanged);

    return result;
}

- (IOReturn)updateStatus:(void *)status
{
    IODiskReadyState readyState;
    DriveStatus *driveStatus;
    IOReturn result;

    IOLog("IOFloppyDrive(BlockOps): Updating status\n");

    // Update ready state
    readyState = [self updateReadyState];

    if (status != NULL) {
        driveStatus = (DriveStatus *)status;

        [_lock lock];

        driveStatus->isReady = (readyState == IO_Ready);
        driveStatus->isWriteProtected = [self isWriteProtected];
        driveStatus->isDiskChanged = _diskChanged;
        driveStatus->errorCode = 0;

        [_lock unlock];

        IOLog("IOFloppyDrive(BlockOps): Updated status - ready:%d wp:%d changed:%d\n",
              driveStatus->isReady, driveStatus->isWriteProtected, driveStatus->isDiskChanged);
    }

    result = (readyState == IO_Ready) ? IO_R_SUCCESS : IO_R_NO_DEVICE;

    return result;
}

- (IOReturn)updateReadyStateInt:(void *)state
{
    IODiskReadyState readyState;

    IOLog("IOFloppyDrive(BlockOps): Updating ready state\n");

    readyState = [self updateReadyState];

    if (state != NULL) {
        *(int *)state = (int)readyState;
        IOLog("IOFloppyDrive(BlockOps): Ready state = %d\n", (int)readyState);
    }

    return IO_R_SUCCESS;
}

- (IOReturn)fdSeekHead:(unsigned int)head
{
    IOReturn status;

    [_lock lock];

    if (head >= _heads) {
        [_lock unlock];
        IOLog("IOFloppyDrive(BlockOps): Invalid head %d (max %d)\n", head, _heads - 1);
        return IO_R_INVALID_ARG;
    }

    [_lock unlock];

    IOLog("IOFloppyDrive(BlockOps): Seeking to head %d\n", head);

    // Perform seek operation (delegate to controller or internal method)
    status = [self fdSeek:head];

    if (status == IO_R_SUCCESS) {
        [_lock lock];
        _currentHead = head;
        [_lock unlock];
        IOLog("IOFloppyDrive(BlockOps): Seek to head %d succeeded\n", head);
    } else {
        IOLog("IOFloppyDrive(BlockOps): Seek to head %d failed: 0x%x\n", head, status);
    }

    return status;
}

- (IOReturn)fdSeekTrack:(unsigned int)track
{
    IOReturn status;
    unsigned int cylinder;

    [_lock lock];

    // Track is typically cylinder * heads + head
    // For a simple track number, assume it's just the cylinder
    cylinder = track / _heads;

    if (cylinder >= _cylinders) {
        [_lock unlock];
        IOLog("IOFloppyDrive(BlockOps): Invalid track %d (cylinder %d, max %d)\n",
              track, cylinder, _cylinders - 1);
        return IO_R_INVALID_ARG;
    }

    [_lock unlock];

    IOLog("IOFloppyDrive(BlockOps): Seeking to track %d (cylinder %d)\n", track, cylinder);

    // Delegate seek to controller
    if (_controller == nil) {
        IOLog("IOFloppyDrive(BlockOps): No controller available\n");
        return IO_R_NO_DEVICE;
    }

    status = [_controller doSeek:_unit cylinder:cylinder];

    if (status == IO_R_SUCCESS) {
        [_lock lock];
        _currentCylinder = cylinder;
        [_lock unlock];
        IOLog("IOFloppyDrive(BlockOps): Seek to track %d succeeded\n", track);
    } else {
        IOLog("IOFloppyDrive(BlockOps): Seek to track %d failed: 0x%x\n", track, status);
    }

    return status;
}

@end
