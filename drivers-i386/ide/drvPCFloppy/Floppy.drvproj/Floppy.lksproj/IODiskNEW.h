/*
 * IODiskNEW.h
 * Stub class for IODisk compatibility
 */

#import <driverkit/IODisk.h>

/*
 * IODiskNEW - Compatibility stub class
 * This class provides a compatibility shim for the floppy driver.
 * It inherits all behavior from IODisk and never probes hardware.
 */
@interface IODiskNEW : IODisk
{
    // Device state
    BOOL _blockDeviceOpen;
    BOOL _writeProtected;
    BOOL _registered;

    // Disk geometry
    unsigned int _blockSize;
    unsigned int _diskSize;

    // Logical disk chain
    id _logicalDisk;
    id _logicalDiskLock;
}

// Block device methods
- (IOReturn)setBlockDeviceOpen:(BOOL)open;
- (IOReturn)isBlockDeviceOpen;
- (IOReturn)setBlockSize:(unsigned int)size;
- (unsigned int)blockSize;

// Disk size methods
- (IOReturn)setDiskSize:(unsigned int)size;
- (unsigned int)diskSize;

// Write protection
- (BOOL)isWriteProtected;
- (IOReturn)setWriteProtected:(BOOL)protect;

// Registration
- (IOReturn)registerDevice;
- (IOReturn)unregisterDevice;

// Logical disk chain
- (IOReturn)lockLogicalDisks;
- (IOReturn)unlockLogicalDisks;
- (IOReturn)setLogicalDisk:(id)disk;

@end
