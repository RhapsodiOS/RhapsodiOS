/*
 * IOFloppyDisk_Support.m
 * Support implementation for IOFloppyDisk
 */

#import "IOFloppyDisk_Support.h"
#import <driverkit/generalFuncs.h>

@implementation IOFloppyDisk(Support)

- (IOReturn)validateParameters:(unsigned int)offset length:(unsigned int)length
{
    unsigned int blockNumber;
    unsigned int numBlocks;

    if (length == 0) {
        IOLog("IOFloppyDisk(Support): Invalid length 0\n");
        return IO_R_INVALID_ARG;
    }

    // Calculate block number and count
    blockNumber = offset / _blockSize;
    numBlocks = (length + _blockSize - 1) / _blockSize;

    // Check if request is within disk capacity
    if (blockNumber + numBlocks > _capacity) {
        IOLog("IOFloppyDisk(Support): Request exceeds capacity (block %d + %d > %d)\n",
              blockNumber, numBlocks, _capacity);
        return IO_R_INVALID_ARG;
    }

    // Check for overflow
    if (offset + length < offset) {
        IOLog("IOFloppyDisk(Support): Offset + length overflow\n");
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDisk(Support): Parameters valid - offset:%d length:%d (blocks %d-%d)\n",
          offset, length, blockNumber, blockNumber + numBlocks - 1);

    return IO_R_SUCCESS;
}

- (IOReturn)convertOffset:(unsigned int)offset
               toCylinder:(unsigned int *)cyl
                     head:(unsigned int *)head
                   sector:(unsigned int *)sec
{
    unsigned int blockNumber;
    unsigned int sectorsPerCylinder;

    // Validate geometry
    if (_heads == 0 || _sectorsPerTrack == 0) {
        IOLog("IOFloppyDisk(Support): Invalid geometry (heads:%d spt:%d)\n",
              _heads, _sectorsPerTrack);
        return IO_R_INVALID;
    }

    // Calculate block number from byte offset
    blockNumber = offset / _blockSize;

    // Check bounds
    if (blockNumber >= _capacity) {
        IOLog("IOFloppyDisk(Support): Block %d exceeds capacity %d\n",
              blockNumber, _capacity);
        return IO_R_INVALID_ARG;
    }

    sectorsPerCylinder = _heads * _sectorsPerTrack;

    // Convert block number to CHS
    if (cyl) {
        *cyl = blockNumber / sectorsPerCylinder;
    }

    if (head) {
        *head = (blockNumber / _sectorsPerTrack) % _heads;
    }

    if (sec) {
        // Sectors are 1-based on floppy disks
        *sec = (blockNumber % _sectorsPerTrack) + 1;
    }

    if (cyl && head && sec) {
        IOLog("IOFloppyDisk(Support): Block %d -> C:%d H:%d S:%d\n",
              blockNumber, *cyl, *head, *sec);
    }

    return IO_R_SUCCESS;
}

- (void)invalidateCache
{
    [_lock lock];

    // Invalidate any cached data
    if (_cachePointer != NULL) {
        IOLog("IOFloppyDisk(Support): Invalidating cache\n");
        // Don't free - cache is managed elsewhere
        _cachePointer = NULL;
        _cacheUnderNumber = 0;
    }

    [_lock unlock];
}

- (void)flushCache
{
    [_lock lock];

    IOLog("IOFloppyDisk(Support): Flushing cache\n");

    // Write any cached data back to disk
    if (_cachePointer != NULL) {
        // In a full implementation, would write cached data here
        IOLog("IOFloppyDisk(Support): Writing cached data\n");

        // Then invalidate
        _cachePointer = NULL;
        _cacheUnderNumber = 0;
    }

    [_lock unlock];
}

// Additional utility methods

- (IOReturn)checkMediaPresent
{
    // Check if media is present and formatted using IODisk method
    if (![self isFormatted]) {
        IOLog("IOFloppyDisk(Support): Media not formatted\n");
        return IO_R_NO_MEDIA;
    }

    return IO_R_SUCCESS;
}

- (IOReturn)checkWritable
{
    // Check if media is writable using IODisk methods
    if ([self isWriteProtected]) {
        IOLog("IOFloppyDisk(Support): Media is write protected\n");
        return IO_R_NOT_WRITABLE;
    }

    if (![self isFormatted]) {
        IOLog("IOFloppyDisk(Support): Media not formatted\n");
        return IO_R_NO_MEDIA;
    }

    return IO_R_SUCCESS;
}

- (IOReturn)alignOffset:(unsigned int)offset
           alignedOffset:(unsigned int *)aligned
                  length:(unsigned int)length
           alignedLength:(unsigned int *)alignedLen
{
    unsigned int blockNumber;
    unsigned int numBlocks;

    if (aligned == NULL || alignedLen == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Calculate block-aligned values
    blockNumber = offset / _blockSize;
    numBlocks = (length + _blockSize - 1) / _blockSize;

    // Handle partial first block
    if (offset % _blockSize != 0) {
        // Round down to block boundary
        *aligned = blockNumber * _blockSize;
        // Increase block count to include partial block
        numBlocks++;
    } else {
        *aligned = offset;
    }

    *alignedLen = numBlocks * _blockSize;

    IOLog("IOFloppyDisk(Support): Aligned offset:%d->%d length:%d->%d\n",
          offset, *aligned, length, *alignedLen);

    return IO_R_SUCCESS;
}

- (IOReturn)calculateTransferSize:(unsigned int)offset
                           length:(unsigned int)length
                   maxTransferSize:(unsigned int *)maxSize
{
    unsigned int blockNumber;
    unsigned int blocksRemaining;
    unsigned int maxBlocks;

    if (maxSize == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Calculate current block and remaining blocks in request
    blockNumber = offset / _blockSize;
    blocksRemaining = (length + _blockSize - 1) / _blockSize;

    // Limit transfer to one track (18 sectors for 1.44MB floppy)
    maxBlocks = _sectorsPerTrack;

    // Don't cross track boundaries
    unsigned int blockInTrack = blockNumber % _sectorsPerTrack;
    unsigned int blocksUntilTrackEnd = _sectorsPerTrack - blockInTrack;

    if (blocksUntilTrackEnd < maxBlocks) {
        maxBlocks = blocksUntilTrackEnd;
    }

    // Don't exceed request size
    if (maxBlocks > blocksRemaining) {
        maxBlocks = blocksRemaining;
    }

    *maxSize = maxBlocks * _blockSize;

    IOLog("IOFloppyDisk(Support): Max transfer size = %d bytes (%d blocks)\n",
          *maxSize, maxBlocks);

    return IO_R_SUCCESS;
}

@end
