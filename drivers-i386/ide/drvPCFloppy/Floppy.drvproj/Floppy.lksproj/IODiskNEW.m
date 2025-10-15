/*
 * IODiskNEW.m
 * Stub class implementation for IODisk compatibility
 */

#import "IODiskNEW.h"
#import <driverkit/generalFuncs.h>

@implementation IODiskNEW

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

    // Initialize state
    _blockDeviceOpen = NO;
    _writeProtected = NO;
    _registered = NO;

    // Default geometry (1.44MB floppy)
    _blockSize = 512;
    _diskSize = 2880;  // 1.44MB = 2880 sectors

    // Initialize logical disk chain
    _logicalDisk = nil;
    _logicalDiskLock = nil;

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

- (IOReturn)setBlockDeviceOpen:(BOOL)open
{
    if (open && _blockDeviceOpen) {
        // Already open
        return IO_R_BUSY;
    }

    if (!open && !_blockDeviceOpen) {
        // Already closed
        return IO_R_SUCCESS;
    }

    _blockDeviceOpen = open;

    if (open) {
        IOLog("IODiskNEW: Block device opened\n");
    } else {
        IOLog("IODiskNEW: Block device closed\n");
    }

    return IO_R_SUCCESS;
}

- (IOReturn)isBlockDeviceOpen
{
    return _blockDeviceOpen ? YES : NO;
}

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

    _blockSize = size;
    IOLog("IODiskNEW: Block size set to %d bytes\n", size);

    return IO_R_SUCCESS;
}

- (unsigned int)blockSize
{
    return _blockSize;
}

- (IOReturn)setDiskSize:(unsigned int)size
{
    // Size is in blocks/sectors
    _diskSize = size;
    IOLog("IODiskNEW: Disk size set to %d blocks (%d KB)\n",
          size, (size * _blockSize) / 1024);

    return IO_R_SUCCESS;
}

- (unsigned int)diskSize
{
    return _diskSize;
}

- (BOOL)isWriteProtected
{
    return _writeProtected;
}

- (IOReturn)setWriteProtected:(BOOL)protect
{
    _writeProtected = protect;

    if (protect) {
        IOLog("IODiskNEW: Write protection enabled\n");
    } else {
        IOLog("IODiskNEW: Write protection disabled\n");
    }

    return IO_R_SUCCESS;
}

- (IOReturn)registerDevice
{
    if (_registered) {
        IOLog("IODiskNEW: Device already registered\n");
        return IO_R_SUCCESS;
    }

    // Call superclass registration
    [super registerDevice];

    _registered = YES;
    IOLog("IODiskNEW: Device registered\n");

    return IO_R_SUCCESS;
}

- (IOReturn)unregisterDevice
{
    if (!_registered) {
        IOLog("IODiskNEW: Device not registered\n");
        return IO_R_SUCCESS;
    }

    // Ensure device is closed before unregistering
    if (_blockDeviceOpen) {
        IOLog("IODiskNEW: Closing device before unregister\n");
        [self setBlockDeviceOpen:NO];
    }

    // Call superclass unregistration
    [super unregisterDevice];

    _registered = NO;
    IOLog("IODiskNEW: Device unregistered\n");

    return IO_R_SUCCESS;
}

- (IOReturn)lockLogicalDisks
{
    // Create lock if needed
    if (_logicalDiskLock == nil) {
        _logicalDiskLock = [[NSLock alloc] init];
        if (_logicalDiskLock == nil) {
            IOLog("IODiskNEW: Failed to create logical disk lock\n");
            return IO_R_NO_MEMORY;
        }
    }

    [_logicalDiskLock lock];
    return IO_R_SUCCESS;
}

- (IOReturn)unlockLogicalDisks
{
    if (_logicalDiskLock == nil) {
        IOLog("IODiskNEW: Logical disk lock not initialized\n");
        return IO_R_INVALID;
    }

    [_logicalDiskLock unlock];
    return IO_R_SUCCESS;
}

- (IOReturn)setLogicalDisk:(id)disk
{
    // Lock before modifying chain
    [self lockLogicalDisks];

    _logicalDisk = disk;

    if (disk != nil) {
        IOLog("IODiskNEW: Logical disk set to %s\n", [[disk name] cString]);
    } else {
        IOLog("IODiskNEW: Logical disk cleared\n");
    }

    [self unlockLogicalDisks];

    return IO_R_SUCCESS;
}

@end
