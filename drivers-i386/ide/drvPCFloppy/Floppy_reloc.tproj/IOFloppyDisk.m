/*
 * IOFloppyDisk.m
 * Floppy Disk Partition/Logical Disk Interface
 */

#import "IOFloppyDisk.h"
#import "IOFloppyDrive.h"
#import "FloppyController.h"
#import <driverkit/generalFuncs.h>
#import <mach/mach.h>
#import <bsd/sys/errno.h>

@implementation IOFloppyDisk

- initWithController:(id)controller
                unit:(unsigned int)unit
        diskGeometry:(void *)geometry
{
    if ([super init] == nil) {
        return nil;
    }

    _drive = nil;
    _diskNumber = unit;

    // Standard 1.44MB floppy geometry
    _cylinders = 80;
    _heads = 2;
    _sectorsPerTrack = 18;
    _blockSize = 512;
    _capacity = _cylinders * _heads * _sectorsPerTrack;

    _isPhysical = YES;
    _isWriteProtected = NO;
    _isRemovable = YES;
    _isFormatted = YES;

    [self setBlockSize:_blockSize];
    [self setDiskSize:_capacity];
    [self setRemovable:YES];
    [self setFormattedInternal:YES];

    return self;
}

- (IOReturn)readAt:(unsigned int)offset
            length:(unsigned int)length
            buffer:(void *)buffer
        actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client
{
    unsigned int blockNumber;
    unsigned int numBlocks;
    unsigned int cylinder, head, sector;
    unsigned int i;
    IOReturn result;
    void *localBuffer;

    if (length == 0 || buffer == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Calculate block number
    blockNumber = offset / _blockSize;
    numBlocks = (length + _blockSize - 1) / _blockSize;

    if (blockNumber + numBlocks > _capacity) {
        return IO_R_INVALID_ARG;
    }

    // Allocate local buffer for reading
    localBuffer = IOMalloc(numBlocks * _blockSize);
    if (localBuffer == NULL) {
        return IO_R_NO_MEMORY;
    }

    // Read each block
    for (i = 0; i < numBlocks; i++) {
        unsigned int block = blockNumber + i;

        // Convert block number to CHS
        cylinder = block / (_heads * _sectorsPerTrack);
        head = (block / _sectorsPerTrack) % _heads;
        sector = (block % _sectorsPerTrack) + 1;  // Sectors are 1-based

        // Read from drive
        if (_drive != nil) {
            result = [_drive readAt:block * _blockSize
                             length:_blockSize
                             buffer:(void *)((char *)localBuffer + (i * _blockSize))
                        actualLength:actualLength
                             client:client];

            if (result != IO_R_SUCCESS) {
                IOFree(localBuffer, numBlocks * _blockSize);
                return result;
            }
        }
    }

    // Copy to user buffer
    bcopy(localBuffer, buffer, length);
    if (actualLength != NULL) {
        *actualLength = length;
    }

    IOFree(localBuffer, numBlocks * _blockSize);
    return IO_R_SUCCESS;
}

- (IOReturn)writeAt:(unsigned int)offset
             length:(unsigned int)length
             buffer:(void *)buffer
         actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client
{
    unsigned int blockNumber;
    unsigned int numBlocks;
    unsigned int cylinder, head, sector;
    unsigned int i;
    IOReturn result;
    void *localBuffer;

    if (length == 0 || buffer == NULL) {
        return IO_R_INVALID_ARG;
    }

    if (_isWriteProtected) {
        return IO_R_NOT_WRITABLE;
    }

    // Calculate block number
    blockNumber = offset / _blockSize;
    numBlocks = (length + _blockSize - 1) / _blockSize;

    if (blockNumber + numBlocks > _capacity) {
        return IO_R_INVALID_ARG;
    }

    // Allocate local buffer
    localBuffer = IOMalloc(numBlocks * _blockSize);
    if (localBuffer == NULL) {
        return IO_R_NO_MEMORY;
    }

    // Copy from user buffer
    bcopy(buffer, localBuffer, length);

    // Write each block
    for (i = 0; i < numBlocks; i++) {
        unsigned int block = blockNumber + i;

        // Convert block number to CHS
        cylinder = block / (_heads * _sectorsPerTrack);
        head = (block / _sectorsPerTrack) % _heads;
        sector = (block % _sectorsPerTrack) + 1;

        // Write to drive
        if (_drive != nil) {
            result = [_drive writeAt:block * _blockSize
                              length:_blockSize
                              buffer:(void *)((char *)localBuffer + (i * _blockSize))
                          actualLength:actualLength
                              client:client];

            if (result != IO_R_SUCCESS) {
                IOFree(localBuffer, numBlocks * _blockSize);
                return result;
            }
        }
    }

    if (actualLength != NULL) {
        *actualLength = length;
    }

    IOFree(localBuffer, numBlocks * _blockSize);
    return IO_R_SUCCESS;
}

- (IOReturn)readAsyncAt:(unsigned int)offset
                 length:(unsigned int)length
                 buffer:(void *)buffer
                 pending:(void *)pending
                 client:(vm_task_t)client
{
    unsigned int actualLength;
    return [self readAt:offset
                 length:length
                 buffer:buffer
             actualLength:&actualLength
                 client:client];
}

- (IOReturn)writeAsyncAt:(unsigned int)offset
                  length:(unsigned int)length
                  buffer:(void *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client
{
    unsigned int actualLength;
    return [self writeAt:offset
                  length:length
                  buffer:buffer
              actualLength:&actualLength
                  client:client];
}

- (BOOL)isWriteProtected
{
    return _isWriteProtected;
}

- (BOOL)isRemovable
{
    return _isRemovable;
}

- (BOOL)isPhysical
{
    return _isPhysical;
}

- (BOOL)isFormatted
{
    return _isFormatted;
}

- (unsigned int)diskSize
{
    return _capacity;
}

- (unsigned int)blockSize
{
    return _blockSize;
}

- (IOReturn)formatMedia
{
    unsigned int cyl, head;
    IOReturn result;

    if (_isWriteProtected) {
        return IO_R_NOT_WRITABLE;
    }

    // Format each track
    for (cyl = 0; cyl < _cylinders; cyl++) {
        for (head = 0; head < _heads; head++) {
            // Format track would go here
            // This would call controller doFormat method
        }
    }

    _isFormatted = YES;
    return IO_R_SUCCESS;
}

- (IOReturn)ejectMedia
{
    // Floppy drives don't have motorized eject
    // This would just turn off the motor
    return IO_R_SUCCESS;
}

- (IOReturn)updatePhysicalParameters
{
    // Update geometry from physical disk
    return IO_R_SUCCESS;
}

- (void)setDrive:(IOFloppyDrive *)drive
{
    _drive = drive;
}

- (unsigned int)cylindersPerDisk
{
    return _cylinders;
}

- (unsigned int)sizeList
{
    return _capacity;
}

- (unsigned int)sizeListFromCapacities
{
    return _capacity * _blockSize;
}

- (void *)cachePointerFromUnderNumber:(unsigned int)underNumber
{
    // Return cached pointer for under number
    return _cachePointer;
}

- (IOReturn)formatCylinder:(unsigned int)cylinder
                      head:(unsigned int)head
                      data:(void *)data
{
    if (cylinder >= _cylinders || head >= _heads) {
        return IO_R_INVALID_ARG;
    }

    if (_isWriteProtected) {
        return IO_R_NOT_WRITABLE;
    }

    // Format specific cylinder/head
    if (_drive != nil) {
        return [_drive formatCylinder:cylinder head:head data:data];
    }

    return IO_R_SUCCESS;
}

- (IOReturn)nextLogicalDisk
{
    // Return next logical disk in partition chain
    return IO_R_SUCCESS;
}

- (IOReturn)setRemovable:(BOOL)removable
{
    _isRemovable = removable;
    return IO_R_SUCCESS;
}

- (IOReturn)registerDevice
{
    // Register with system
    return IO_R_SUCCESS;
}

- (IOReturn)unregisterDevice
{
    // Unregister from system
    return IO_R_SUCCESS;
}

- (IOReturn)logicalDisk
{
    // Return logical disk reference
    return IO_R_SUCCESS;
}

- (IOReturn)unlockLogicalDisk
{
    // Unlock disk for operations
    return IO_R_SUCCESS;
}

- (IOReturn)lockLogicalDisk
{
    // Lock disk from operations
    return IO_R_SUCCESS;
}

- (IOReturn)setBlockDeviceOpen
{
    // Mark block device as open
    return IO_R_SUCCESS;
}

- (IOReturn)setBlockDeviceOpen:(BOOL)open
{
    // Set block device open state
    return IO_R_SUCCESS;
}

- (IOReturn)setFormatted:(BOOL)formatted
{
    _isFormatted = formatted;
    return IO_R_SUCCESS;
}

- (IOReturn)setFormattedInternal:(BOOL)formatted
{
    _isFormatted = formatted;
    return IO_R_SUCCESS;
}

- (IOReturn)isBlockDeviceOpen
{
    // Check if block device is open
    return IO_R_SUCCESS;
}

- (IOReturn)getGeometry:(void *)geometry
{
    // Return disk geometry structure
    return IO_R_SUCCESS;
}

- (IOReturn)setGeometry:(void *)geometry
{
    // Set disk geometry from structure
    return IO_R_SUCCESS;
}

- (IOReturn)getCapacity:(unsigned long long *)capacity
{
    if (capacity != NULL) {
        *capacity = (unsigned long long)_capacity * _blockSize;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)readBlock:(unsigned int)blockNumber
               buffer:(void *)buffer
               client:(vm_task_t)client
{
    unsigned int actualLength;
    return [self readAt:blockNumber * _blockSize
                 length:_blockSize
                 buffer:buffer
             actualLength:&actualLength
                 client:client];
}

- (IOReturn)writeBlock:(unsigned int)blockNumber
                buffer:(void *)buffer
                client:(vm_task_t)client
{
    unsigned int actualLength;
    return [self writeAt:blockNumber * _blockSize
                  length:_blockSize
                  buffer:buffer
              actualLength:&actualLength
                  client:client];
}

- (IOReturn)completeTransfer:(void *)transfer
                      status:(IOReturn)status
                actualLength:(unsigned int)actualLength
{
    // Complete async transfer with status
    return IO_R_SUCCESS;
}

- (IOReturn)pendingRequest:(void **)request
{
    // Get pending request
    if (request != NULL) {
        *request = NULL;
    }
    return IO_R_SUCCESS;
}

- (const char *)driverName
{
    return "IOFloppyDisk";
}

- (IOReturn)isDiskReady:(BOOL *)ready
{
    if (ready != NULL) {
        *ready = _isFormatted && !_isWriteProtected;
    }
    return IO_R_SUCCESS;
}

// IOLogicalDisk inherited methods
- (BOOL)isOpen
{
    // Check if this logical disk is open
    return YES;
}

- (BOOL)isAnyOtherOpen
{
    // Check if any other logical disks in chain are open
    return NO;
}

- (IOReturn)connectToPhysicalDisk:(id)physicalDisk
{
    // Connect to physical disk device
    return IO_R_SUCCESS;
}

- (void)setPartitionBase:(unsigned)partBase
{
    // Set partition base offset
}

- (id)physicalDisk
{
    // Return physical disk
    return _drive;
}

- (void)setPhysicalBlockSize:(unsigned)size
{
    // Set physical block size
}

- (u_int)physicalBlockSize
{
    // Return physical block size
    return _blockSize;
}

- (BOOL)isInstanceOpen
{
    // Check if this instance is open
    return YES;
}

- (void)setInstanceOpen:(BOOL)isOpen
{
    // Set instance open state
}

// IODisk inherited methods that may need override
- (void)setLogicalDisk:(id)diskId
{
    // Set next logical disk in chain
}

- (void)lockLogicalDisks
{
    // Lock logical disk chain
}

- (void)unlockLogicalDisks
{
    // Unlock logical disk chain
}

- (const char *)stringFromReturn:(IOReturn)rtn
{
    // Convert IOReturn to string
    switch (rtn) {
        case IO_R_SUCCESS: return "Success";
        case IO_R_NO_MEDIA: return "No Media";
        case IO_R_INVALID_ARG: return "Invalid Argument";
        case IO_R_NOT_WRITABLE: return "Not Writable";
        default: return "Unknown Error";
    }
}

- (IOReturn)errnoFromReturn:(IOReturn)rtn
{
    // Convert IOReturn to errno
    switch (rtn) {
        case IO_R_SUCCESS: return 0;
        case IO_R_NO_MEMORY: return ENOMEM;
        case IO_R_INVALID_ARG: return EINVAL;
        case IO_R_NO_MEDIA: return ENXIO;
        default: return EIO;
    }
}

- (IOReturn)eject
{
    // Eject disk (logical disk version)
    return [self ejectMedia];
}

- (IOReturn)abortRequest
{
    // Abort pending requests
    return IO_R_SUCCESS;
}

- (IOReturn)diskBecameReady
{
    // Handle disk becoming ready
    _isFormatted = YES;
    return IO_R_SUCCESS;
}

- (IODiskReadyState)updateReadyState
{
    // Update and return ready state
    if (!_isFormatted) {
        return IO_NoDisk;
    }
    return IO_Ready;
}

- (BOOL)needsManualPolling
{
    // Floppy drives need manual polling
    return YES;
}

- (IOReturn)kernelDeviceInfo:(void *)info
{
    // Return kernel device information
    return IO_R_SUCCESS;
}

// Partition/Label methods
- (IOReturn)virtualLabel
{
    // Return virtual label for floppy (floppies don't have labels)
    return IO_R_SUCCESS;
}

- (IOReturn)getLabel:(void *)label
{
    // Get disk label (floppies typically don't have disk labels)
    return IO_R_NO_LABEL;
}

- (IOReturn)setLabel:(void *)label
{
    // Set disk label (floppies typically can't set labels)
    return IO_R_UNSUPPORTED;
}

@end
