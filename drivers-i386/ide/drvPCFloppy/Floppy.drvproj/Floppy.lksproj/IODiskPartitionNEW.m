/*
 * IODiskPartitionNEW.m
 * Stub class implementation for IODiskPartition compatibility
 */

#import "IODiskPartitionNEW.h"
#import <driverkit/generalFuncs.h>
#import <objc/objc.h>

@implementation IODiskPartitionNEW

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    // Never probe - this is just a stub class for compatibility
    return NO;
}

- init
{
    if ([super init] == nil) {
        return nil;
    }

    // Initialize partition state
    _blockDeviceOpen = NO;
    _formattedInternal = NO;
    _openCount = 0;

    // Default partition covers entire disk (floppy has no partitions)
    _partitionBase = 0;
    _partitionSize = 2880;  // 1.44MB = 2880 sectors

    // Initialize label
    _label = (char *)malloc(32);
    if (_label != NULL) {
        strcpy(_label, "FLOPPY");
    }

    // Initialize physical disk reference
    _physicalDisk = nil;

    // Create lock
    _lock = [[NSLock alloc] init];
    if (_lock == nil) {
        if (_label != NULL) {
            free(_label);
        }
        [self free];
        return nil;
    }

    return self;
}

- (void)free
{
    // Free label
    if (_label != NULL) {
        free(_label);
        _label = NULL;
    }

    // Free lock
    if (_lock != nil) {
        [_lock free];
        _lock = nil;
    }

    return [super free];
}

- (IOReturn)readAt:(unsigned int)offset
            length:(unsigned int)length
            buffer:(void *)buffer
        actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client
{
    IOReturn status;

    // Validate parameters
    if (buffer == NULL || length == 0) {
        return IO_R_INVALID_ARG;
    }

    // Check if device is open
    [_lock lock];
    if (!_blockDeviceOpen) {
        [_lock unlock];
        IOLog("IODiskPartitionNEW: Read failed - device not open\n");
        return IO_R_NOT_OPEN;
    }

    // Validate offset within partition bounds
    if (offset >= _partitionSize) {
        [_lock unlock];
        IOLog("IODiskPartitionNEW: Read offset %d beyond partition size %d\n",
              offset, _partitionSize);
        return IO_R_INVALID_ARG;
    }

    // Clamp length to partition bounds
    if (offset + length > _partitionSize) {
        length = _partitionSize - offset;
    }

    [_lock unlock];

    // Translate partition offset to physical disk offset
    unsigned int physicalOffset = _partitionBase + offset;

    // Delegate to physical disk if available
    if (_physicalDisk != nil && [_physicalDisk respondsToSelector:@selector(readAt:length:buffer:actualLength:client:)]) {
        status = [_physicalDisk readAt:physicalOffset
                                length:length
                                buffer:buffer
                          actualLength:actualLength
                                client:client];
    } else {
        // No physical disk - return unsupported
        status = IO_R_UNSUPPORTED;
    }

    // Set actual length if requested
    if (actualLength != NULL && status == IO_R_SUCCESS) {
        *actualLength = length;
    }

    return status;
}

- (IOReturn)readAsyncAt:(unsigned int)offset
                 length:(unsigned int)length
                 buffer:(void *)buffer
                 client:(vm_task_t)client
               pending:(void *)pending
{
    // Async read not supported for floppy
    // Fall back to synchronous read
    IOLog("IODiskPartitionNEW: Async read not supported, using sync read\n");
    return [self readAt:offset length:length buffer:buffer actualLength:NULL client:client];
}

- (IOReturn)writeAt:(unsigned int)offset
             length:(unsigned int)length
             buffer:(void *)buffer
         actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client
{
    IOReturn status;

    // Validate parameters
    if (buffer == NULL || length == 0) {
        return IO_R_INVALID_ARG;
    }

    // Check if device is open
    [_lock lock];
    if (!_blockDeviceOpen) {
        [_lock unlock];
        IOLog("IODiskPartitionNEW: Write failed - device not open\n");
        return IO_R_NOT_OPEN;
    }

    // Validate offset within partition bounds
    if (offset >= _partitionSize) {
        [_lock unlock];
        IOLog("IODiskPartitionNEW: Write offset %d beyond partition size %d\n",
              offset, _partitionSize);
        return IO_R_INVALID_ARG;
    }

    // Clamp length to partition bounds
    if (offset + length > _partitionSize) {
        length = _partitionSize - offset;
    }

    [_lock unlock];

    // Translate partition offset to physical disk offset
    unsigned int physicalOffset = _partitionBase + offset;

    // Delegate to physical disk if available
    if (_physicalDisk != nil && [_physicalDisk respondsToSelector:@selector(writeAt:length:buffer:actualLength:client:)]) {
        status = [_physicalDisk writeAt:physicalOffset
                                 length:length
                                 buffer:buffer
                           actualLength:actualLength
                                 client:client];
    } else {
        // No physical disk - return unsupported
        status = IO_R_UNSUPPORTED;
    }

    // Set actual length if requested
    if (actualLength != NULL && status == IO_R_SUCCESS) {
        *actualLength = length;
    }

    return status;
}

- (IOReturn)setFormattedInternal:(BOOL)formatted
{
    [_lock lock];
    _formattedInternal = formatted;
    [_lock unlock];

    IOLog("IODiskPartitionNEW: Formatted internal set to %s\n",
          formatted ? "YES" : "NO");

    return IO_R_SUCCESS;
}

- (IOReturn)setBlockDeviceOpen:(BOOL)open
{
    [_lock lock];

    if (open) {
        if (_openCount == 0) {
            _blockDeviceOpen = YES;
            IOLog("IODiskPartitionNEW: Block device opened\n");
        }
        _openCount++;
    } else {
        if (_openCount > 0) {
            _openCount--;
        }
        if (_openCount == 0) {
            _blockDeviceOpen = NO;
            IOLog("IODiskPartitionNEW: Block device closed\n");
        }
    }

    [_lock unlock];

    return IO_R_SUCCESS;
}

- (IOReturn)isAnyOtherOpen
{
    BOOL result;

    [_lock lock];
    result = (_openCount > 1) ? YES : NO;
    [_lock unlock];

    return result;
}

- (id)requiredProtocols
{
    // No required protocols for floppy
    return nil;
}

- (void)deviceStyle
{
    // Device style for floppy - stub implementation
}

- (id)protocolsForInsert
{
    // No special protocols needed for floppy insertion
    return nil;
}

- (const char *)diskLabel
{
    const char *result;

    [_lock lock];
    result = (_label != NULL) ? _label : "FLOPPY";
    [_lock unlock];

    return result;
}

- (id)_initPartition:(void *)disktab
{
    // Initialize partition from disktab structure
    // For floppy, we typically have no partitions (whole disk)
    if (disktab != NULL) {
        IOLog("IODiskPartitionNEW: Initializing partition from disktab\n");
        // Could parse disktab structure here if needed
    }

    return self;
}

- (void)_freePartitions
{
    // Free partition structures
    // For floppy, we don't have sub-partitions
    IOLog("IODiskPartitionNEW: Freeing partitions\n");
}

- (BOOL)checkSafeConfig
{
    BOOL result = YES;

    [_lock lock];

    // Check configuration is safe
    if (_partitionBase + _partitionSize > 2880) {
        // Partition extends beyond 1.44MB floppy size
        IOLog("IODiskPartitionNEW: WARNING - Partition extends beyond disk size\n");
        result = NO;
    }

    [_lock unlock];

    return result;
}

- (IOReturn)setPartitionBase:(unsigned int)base
{
    [_lock lock];
    _partitionBase = base;
    [_lock unlock];

    IOLog("IODiskPartitionNEW: Partition base set to %d\n", base);

    return IO_R_SUCCESS;
}

- (IOReturn)setPartitionSize:(unsigned int)size
{
    [_lock lock];
    _partitionSize = size;
    [_lock unlock];

    IOLog("IODiskPartitionNEW: Partition size set to %d sectors (%d KB)\n",
          size, (size * 512) / 1024);

    return IO_R_SUCCESS;
}

- (unsigned int)partitionBase
{
    unsigned int result;

    [_lock lock];
    result = _partitionBase;
    [_lock unlock];

    return result;
}

- (unsigned int)partitionSize
{
    unsigned int result;

    [_lock lock];
    result = _partitionSize;
    [_lock unlock];

    return result;
}

- (IOReturn)setPhysicalDisk:(id)disk
{
    [_lock lock];
    _physicalDisk = disk;
    [_lock unlock];

    if (disk != nil) {
        IOLog("IODiskPartitionNEW: Physical disk set to %s\n",
              [[disk name] cString]);
    } else {
        IOLog("IODiskPartitionNEW: Physical disk cleared\n");
    }

    return IO_R_SUCCESS;
}

- (id)physicalDisk
{
    id result;

    [_lock lock];
    result = _physicalDisk;
    [_lock unlock];

    return result;
}

@end
