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

    // Initialize state (only what's not provided by superclass)
    _isRegistered = NO;
    _isOpen = NO;
    _blockDeviceOpen = NO;
    _rawDeviceOpen = NO;

    // Initialize cache
    _cachePointer = NULL;
    _cacheUnderNumber = 0;

    // Initialize request handling
    _operationThread = nil;
    _pendingRequest = NULL;

    // Create lock for thread safety (use NXLock, not NSLock)
    _lock = [[NXLock alloc] init];
    if (_lock == nil) {
        IOLog("IOFloppyDisk: Failed to create lock\n");
        [self free];
        return nil;
    }

    // Set superclass properties
    [self setBlockSize:_blockSize];
    [self setDiskSize:_capacity];
    [self setRemovable:YES];
    [self setFormattedInternal:YES];

    IOLog("IOFloppyDisk: Initialized disk %d (C:%d H:%d S:%d, capacity:%d blocks)\n",
          unit, _cylinders, _heads, _sectorsPerTrack, _capacity);

    return self;
}

- (void)free
{
    // Clean up lock
    if (_lock != nil) {
        [_lock free];
        _lock = nil;
    }

    // Clean up cache
    if (_cachePointer != NULL) {
        IOFree(_cachePointer, _blockSize);
        _cachePointer = NULL;
    }

    // Clean up pending request
    if (_pendingRequest != NULL) {
        IOFree(_pendingRequest, sizeof(void *));
        _pendingRequest = NULL;
    }

    return [super free];
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

    // Use IODisk's isWriteProtected method
    if ([self isWriteProtected]) {
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

// These methods are provided by IODisk superclass
// Keep these for compatibility but delegate to super

- (BOOL)isWriteProtected
{
    return [super isWriteProtected];
}

- (BOOL)isRemovable
{
    return [super isRemovable];
}

- (BOOL)isPhysical
{
    return [super isPhysical];
}

- (BOOL)isFormatted
{
    return [super isFormatted];
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

    // Use IODisk's isWriteProtected method
    if ([self isWriteProtected]) {
        return IO_R_NOT_WRITABLE;
    }

    // Format each track
    for (cyl = 0; cyl < _cylinders; cyl++) {
        for (head = 0; head < _heads; head++) {
            // Format track would go here
            // This would call controller doFormat method
        }
    }

    // Use IODisk's setFormattedInternal method
    [self setFormattedInternal:YES];
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

    // Use IODisk's isWriteProtected method
    if ([self isWriteProtected]) {
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
    // Use IODisk's setRemovable method
    [super setRemovable:removable];
    return IO_R_SUCCESS;
}

- (IOReturn)registerDevice
{
    [_lock lock];

    if (_isRegistered) {
        [_lock unlock];
        IOLog("IOFloppyDisk: Device already registered\n");
        return IO_R_SUCCESS;
    }

    // Call superclass registration
    [super registerDevice];

    _isRegistered = YES;
    IOLog("IOFloppyDisk: Device %d registered\n", _diskNumber);

    [_lock unlock];
    return IO_R_SUCCESS;
}

- (IOReturn)unregisterDevice
{
    [_lock lock];

    if (!_isRegistered) {
        [_lock unlock];
        IOLog("IOFloppyDisk: Device not registered\n");
        return IO_R_SUCCESS;
    }

    // Ensure device is closed before unregistering
    if (_isOpen) {
        IOLog("IOFloppyDisk: Closing device before unregister\n");
        _isOpen = NO;
    }

    // Call superclass unregistration
    [super unregisterDevice];

    _isRegistered = NO;
    IOLog("IOFloppyDisk: Device %d unregistered\n", _diskNumber);

    [_lock unlock];
    return IO_R_SUCCESS;
}

- (IOReturn)logicalDisk
{
    // Return logical disk reference
    return IO_R_SUCCESS;
}

- (IOReturn)unlockLogicalDisk
{
    if (_lock != nil) {
        [_lock unlock];
        IOLog("IOFloppyDisk: Logical disk unlocked\n");
    }
    return IO_R_SUCCESS;
}

- (IOReturn)lockLogicalDisk
{
    if (_lock != nil) {
        [_lock lock];
        IOLog("IOFloppyDisk: Logical disk locked\n");
    }
    return IO_R_SUCCESS;
}

- (IOReturn)setFormatted:(BOOL)formatted
{
    // Use IODisk's setFormattedInternal method
    [super setFormattedInternal:formatted];
    return IO_R_SUCCESS;
}

- (IOReturn)setFormattedInternal:(BOOL)formatted
{
    // Delegate to IODisk
    return [super setFormattedInternal:formatted];
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
        // Use IODisk methods
        *ready = [self isFormatted] && ![self isWriteProtected];
    }
    return IO_R_SUCCESS;
}

// IOLogicalDisk inherited methods
- (BOOL)isOpen
{
    BOOL result;

    [_lock lock];
    result = _isOpen;
    [_lock unlock];

    return result;
}

- (BOOL)isAnyOtherOpen
{
    // Check if any other logical disks in chain are open
    // Use IODisk's nextLogicalDisk method
    id nextDisk = [self nextLogicalDisk];
    if (nextDisk != nil && [nextDisk respondsToSelector:@selector(isOpen)]) {
        return [nextDisk isOpen];
    }
    return NO;
}

- (IOReturn)connectToPhysicalDisk:(id)physicalDisk
{
    // Delegate to IOLogicalDisk superclass
    IOReturn result = [super connectToPhysicalDisk:physicalDisk];

    if (result == IO_R_SUCCESS) {
        IOLog("IOFloppyDisk: Connected to physical disk %s\n",
              [[physicalDisk name] cString]);
    }

    return result;
}

- (void)setPartitionBase:(unsigned)partBase
{
    // Delegate to IOLogicalDisk superclass
    [super setPartitionBase:partBase];

    IOLog("IOFloppyDisk: Partition base set to %d\n", partBase);
}

- (id)physicalDisk
{
    // Use IOLogicalDisk's physicalDisk method, fall back to _drive if nil
    id result = [super physicalDisk];

    if (result == nil) {
        result = _drive;
    }

    return result;
}

- (void)setPhysicalBlockSize:(unsigned)size
{
    [_lock lock];
    _blockSize = size;
    [_lock unlock];

    IOLog("IOFloppyDisk: Physical block size set to %d\n", size);
}

- (u_int)physicalBlockSize
{
    unsigned int result;

    [_lock lock];
    result = _blockSize;
    [_lock unlock];

    return result;
}

- (BOOL)isInstanceOpen
{
    return [self isOpen];
}

- (void)setInstanceOpen:(BOOL)isOpen
{
    [_lock lock];
    _isOpen = isOpen;
    [_lock unlock];

    if (isOpen) {
        IOLog("IOFloppyDisk: Instance opened\n");
    } else {
        IOLog("IOFloppyDisk: Instance closed\n");
    }
}

// IODisk inherited methods that may need override
- (void)setLogicalDisk:(id)diskId
{
    // Delegate to IODisk superclass
    [super setLogicalDisk:diskId];

    if (diskId != nil) {
        IOLog("IOFloppyDisk: Next logical disk set to %s\n",
              [[diskId name] cString]);
    } else {
        IOLog("IOFloppyDisk: Next logical disk cleared\n");
    }
}

- (void)lockLogicalDisks
{
    if (_lock != nil) {
        [_lock lock];
    }
}

- (void)unlockLogicalDisks
{
    if (_lock != nil) {
        [_lock unlock];
    }
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
    // Handle disk becoming ready - use IODisk method
    [self setFormattedInternal:YES];
    return IO_R_SUCCESS;
}

- (IODiskReadyState)updateReadyState
{
    // Update and return ready state - use IODisk method
    if (![self isFormatted]) {
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

// Partition/Label methods (IODiskPartition protocol)

- (IOReturn)readLabel:(disk_label_t *)label_p
{
    if (label_p == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Floppies don't typically have NeXT disk labels
    // Return IO_R_NO_LABEL to indicate no label present
    IOLog("IOFloppyDisk: Read label - no label on floppy\n");
    return IO_R_NO_LABEL;
}

- (IOReturn)writeLabel:(disk_label_t *)label_p
{
    if (label_p == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Check write protection
    if ([self isWriteProtected]) {
        return IO_R_NOT_WRITABLE;
    }

    // Floppies don't support NeXT disk labels
    IOLog("IOFloppyDisk: Write label - unsupported on floppy\n");
    return IO_R_UNSUPPORTED;
}

- (BOOL)isBlockDeviceOpen
{
    BOOL result;

    [_lock lock];
    result = _blockDeviceOpen;
    [_lock unlock];

    return result;
}

- (void)setBlockDeviceOpen:(BOOL)openFlag
{
    [_lock lock];
    _blockDeviceOpen = openFlag;
    _isOpen = _blockDeviceOpen || _rawDeviceOpen;
    [_lock unlock];

    IOLog("IOFloppyDisk: Block device %s (disk %d)\n",
          openFlag ? "opened" : "closed", _diskNumber);
}

- (BOOL)isRawDeviceOpen
{
    BOOL result;

    [_lock lock];
    result = _rawDeviceOpen;
    [_lock unlock];

    return result;
}

- (void)setRawDeviceOpen:(BOOL)openFlag
{
    [_lock lock];
    _rawDeviceOpen = openFlag;
    _isOpen = _blockDeviceOpen || _rawDeviceOpen;
    [_lock unlock];

    IOLog("IOFloppyDisk: Raw device %s (disk %d)\n",
          openFlag ? "opened" : "closed", _diskNumber);
}

// Legacy label methods (kept for compatibility)

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
