/*
 * IOLogicalDiskNEW.m
 * Stub class implementation for IOLogicalDisk compatibility
 */

#import "IOLogicalDiskNEW.h"
#import <driverkit/generalFuncs.h>
#import <objc/objc.h>

@implementation IOLogicalDiskNEW

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

    // Initialize device state
    _blockDeviceOpen = NO;
    _writeProtected = NO;
    _registered = NO;
    _openCount = 0;

    // Default geometry (1.44MB floppy)
    _blockSize = 512;
    _logicalBlockCount = 2880;  // 1.44MB = 2880 sectors

    // Initialize logical disk chain
    _nextLogicalDisk = nil;
    _logicalDiskLock = nil;

    // Initialize physical disk reference
    _physicalDisk = nil;

    // Default max bytes per transfer (one track)
    _maxBytesPerTransfer = 18 * 512;  // 18 sectors/track * 512 bytes

    return self;
}

- (void)free
{
    // Clean up logical disk lock if allocated
    if (_logicalDiskLock != nil) {
        [_logicalDiskLock free];
        _logicalDiskLock = nil;
    }

    return [super free];
}

- (IOReturn)registerDevice
{
    if (_registered) {
        IOLog("IOLogicalDiskNEW: Device already registered\n");
        return IO_R_SUCCESS;
    }

    // Call superclass registration
    [super registerDevice];

    _registered = YES;
    IOLog("IOLogicalDiskNEW: Device registered\n");

    return IO_R_SUCCESS;
}

- (IOReturn)unregisterDevice
{
    if (!_registered) {
        IOLog("IOLogicalDiskNEW: Device not registered\n");
        return IO_R_SUCCESS;
    }

    // Ensure device is closed before unregistering
    if (_blockDeviceOpen) {
        IOLog("IOLogicalDiskNEW: Closing device before unregister\n");
        [self setBlockDeviceOpen:NO];
    }

    // Call superclass unregistration
    [super unregisterDevice];

    _registered = NO;
    IOLog("IOLogicalDiskNEW: Device unregistered\n");

    return IO_R_SUCCESS;
}

- (IOReturn)setLogicalDisk:(id)disk
{
    // Lock before modifying chain
    [self lockLogicalDisks];

    _nextLogicalDisk = disk;

    if (disk != nil) {
        IOLog("IOLogicalDiskNEW: Next logical disk set to %s\n",
              [[disk name] cString]);
    } else {
        IOLog("IOLogicalDiskNEW: Next logical disk cleared\n");
    }

    [self unlockLogicalDisks];

    return IO_R_SUCCESS;
}

- (IOReturn)lockLogicalDisks
{
    // Create lock if needed
    if (_logicalDiskLock == nil) {
        _logicalDiskLock = [[NSLock alloc] init];
        if (_logicalDiskLock == nil) {
            IOLog("IOLogicalDiskNEW: Failed to create logical disk lock\n");
            return IO_R_NO_MEMORY;
        }
    }

    [_logicalDiskLock lock];
    return IO_R_SUCCESS;
}

- (IOReturn)unlockLogicalDisks
{
    if (_logicalDiskLock == nil) {
        IOLog("IOLogicalDiskNEW: Logical disk lock not initialized\n");
        return IO_R_INVALID;
    }

    [_logicalDiskLock unlock];
    return IO_R_SUCCESS;
}

- (IOReturn)setBlockDeviceOpen:(BOOL)open
{
    [self lockLogicalDisks];

    if (open) {
        if (_openCount == 0) {
            _blockDeviceOpen = YES;
            IOLog("IOLogicalDiskNEW: Block device opened\n");
        }
        _openCount++;
    } else {
        if (_openCount > 0) {
            _openCount--;
        }
        if (_openCount == 0) {
            _blockDeviceOpen = NO;
            IOLog("IOLogicalDiskNEW: Block device closed\n");
        }
    }

    [self unlockLogicalDisks];

    return IO_R_SUCCESS;
}

- (IOReturn)isBlockDeviceOpen
{
    BOOL result;

    [self lockLogicalDisks];
    result = _blockDeviceOpen;
    [self unlockLogicalDisks];

    return result ? YES : NO;
}

- (BOOL)isAnyBlockDeviceOpen
{
    BOOL result;

    [self lockLogicalDisks];
    result = _blockDeviceOpen;
    [self unlockLogicalDisks];

    return result;
}

- (BOOL)isAnyOtherOpen
{
    BOOL result;

    [self lockLogicalDisks];
    result = (_openCount > 1) ? YES : NO;
    [self unlockLogicalDisks];

    return result;
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
    [self lockLogicalDisks];
    if (!_blockDeviceOpen) {
        [self unlockLogicalDisks];
        IOLog("IOLogicalDiskNEW: Read failed - device not open\n");
        return IO_R_NOT_OPEN;
    }

    // Validate offset within logical disk bounds
    if (offset >= _logicalBlockCount) {
        [self unlockLogicalDisks];
        IOLog("IOLogicalDiskNEW: Read offset %d beyond disk size %d\n",
              offset, _logicalBlockCount);
        return IO_R_INVALID_ARG;
    }

    // Clamp length to logical disk bounds
    if (offset + length > _logicalBlockCount) {
        length = _logicalBlockCount - offset;
    }

    [self unlockLogicalDisks];

    // Delegate to physical disk if available
    if (_physicalDisk != nil && [_physicalDisk respondsToSelector:@selector(readAt:length:buffer:actualLength:client:)]) {
        status = [_physicalDisk readAt:offset
                                length:length
                                buffer:buffer
                          actualLength:actualLength
                                client:client];
    } else {
        // No physical disk - return unsupported
        IOLog("IOLogicalDiskNEW: No physical disk available for read\n");
        status = IO_R_UNSUPPORTED;
    }

    // Set actual length if requested
    if (actualLength != NULL && status == IO_R_SUCCESS) {
        *actualLength = length;
    }

    return status;
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
    [self lockLogicalDisks];
    if (!_blockDeviceOpen) {
        [self unlockLogicalDisks];
        IOLog("IOLogicalDiskNEW: Write failed - device not open\n");
        return IO_R_NOT_OPEN;
    }

    // Check write protection
    if (_writeProtected) {
        [self unlockLogicalDisks];
        IOLog("IOLogicalDiskNEW: Write failed - device is write protected\n");
        return IO_R_IO;
    }

    // Validate offset within logical disk bounds
    if (offset >= _logicalBlockCount) {
        [self unlockLogicalDisks];
        IOLog("IOLogicalDiskNEW: Write offset %d beyond disk size %d\n",
              offset, _logicalBlockCount);
        return IO_R_INVALID_ARG;
    }

    // Clamp length to logical disk bounds
    if (offset + length > _logicalBlockCount) {
        length = _logicalBlockCount - offset;
    }

    [self unlockLogicalDisks];

    // Delegate to physical disk if available
    if (_physicalDisk != nil && [_physicalDisk respondsToSelector:@selector(writeAt:length:buffer:actualLength:client:)]) {
        status = [_physicalDisk writeAt:offset
                                 length:length
                                 buffer:buffer
                           actualLength:actualLength
                                 client:client];
    } else {
        // No physical disk - return unsupported
        IOLog("IOLogicalDiskNEW: No physical disk available for write\n");
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
    IOLog("IOLogicalDiskNEW: Async read not supported, using sync read\n");
    return [self readAt:offset length:length buffer:buffer actualLength:NULL client:client];
}

- (unsigned int)deviceBytesOnce
{
    unsigned int result;

    [self lockLogicalDisks];
    result = _maxBytesPerTransfer;
    [self unlockLogicalDisks];

    return result;
}

- (IOReturn)completeTransfer:(void *)status
              actualLength:(unsigned int)actualLength
                    client:(vm_task_t)client
{
    // Transfer completion notification
    // For floppy, we don't need to do anything special here
    IOLog("IOLogicalDiskNEW: Transfer completed, %d bytes transferred\n",
          actualLength);

    return IO_R_SUCCESS;
}

- (id)setPhysicalDisk:(id)disk
{
    [self lockLogicalDisks];
    _physicalDisk = disk;
    [self unlockLogicalDisks];

    if (disk != nil) {
        IOLog("IOLogicalDiskNEW: Physical disk set to %s\n",
              [[disk name] cString]);
    } else {
        IOLog("IOLogicalDiskNEW: Physical disk cleared\n");
    }

    return self;
}

- (id)isWriteProtected
{
    BOOL result;

    [self lockLogicalDisks];
    result = _writeProtected;
    [self unlockLogicalDisks];

    return (id)result;
}

// Additional geometry management methods

- (IOReturn)setBlockSize:(unsigned int)size
{
    // Validate block size (must be power of 2 and reasonable)
    if (size == 0 || size > 4096) {
        return IO_R_INVALID_ARG;
    }

    // Check if power of 2
    if ((size & (size - 1)) != 0) {
        return IO_R_INVALID_ARG;
    }

    [self lockLogicalDisks];
    _blockSize = size;
    [self unlockLogicalDisks];

    IOLog("IOLogicalDiskNEW: Block size set to %d bytes\n", size);

    return IO_R_SUCCESS;
}

- (unsigned int)blockSize
{
    unsigned int result;

    [self lockLogicalDisks];
    result = _blockSize;
    [self unlockLogicalDisks];

    return result;
}

- (IOReturn)setLogicalBlockCount:(unsigned int)count
{
    [self lockLogicalDisks];
    _logicalBlockCount = count;
    [self unlockLogicalDisks];

    IOLog("IOLogicalDiskNEW: Logical block count set to %d blocks (%d KB)\n",
          count, (count * _blockSize) / 1024);

    return IO_R_SUCCESS;
}

- (unsigned int)logicalBlockCount
{
    unsigned int result;

    [self lockLogicalDisks];
    result = _logicalBlockCount;
    [self unlockLogicalDisks];

    return result;
}

- (IOReturn)setWriteProtected:(BOOL)protect
{
    [self lockLogicalDisks];
    _writeProtected = protect;
    [self unlockLogicalDisks];

    if (protect) {
        IOLog("IOLogicalDiskNEW: Write protection enabled\n");
    } else {
        IOLog("IOLogicalDiskNEW: Write protection disabled\n");
    }

    return IO_R_SUCCESS;
}

- (IOReturn)setMaxBytesPerTransfer:(unsigned int)maxBytes
{
    [self lockLogicalDisks];
    _maxBytesPerTransfer = maxBytes;
    [self unlockLogicalDisks];

    IOLog("IOLogicalDiskNEW: Max bytes per transfer set to %d\n", maxBytes);

    return IO_R_SUCCESS;
}

@end
