/*
 * IOLogicalDiskNEW.h
 * Stub class for IOLogicalDisk compatibility
 */

#import <driverkit/IOLogicalDisk.h>

/*
 * IOLogicalDiskNEW - Compatibility stub class
 * This class provides a compatibility shim for the floppy driver.
 * It inherits all behavior from IOLogicalDisk and never probes hardware.
 */
@interface IOLogicalDiskNEW : IOLogicalDisk
{
    // Device state
    BOOL _blockDeviceOpen;
    BOOL _writeProtected;
    BOOL _registered;
    unsigned int _openCount;

    // Disk geometry
    unsigned int _blockSize;
    unsigned int _logicalBlockCount;

    // Logical disk chain
    id _nextLogicalDisk;
    id _logicalDiskLock;

    // Physical disk reference
    id _physicalDisk;

    // Transfer state
    unsigned int _maxBytesPerTransfer;
}

// Logical disk methods
- (IOReturn)registerDevice;
- (IOReturn)unregisterDevice;
- (IOReturn)setLogicalDisk:(id)disk;
- (IOReturn)lockLogicalDisks;
- (IOReturn)unlockLogicalDisks;

// Device status
- (IOReturn)setBlockDeviceOpen:(BOOL)open;
- (IOReturn)isBlockDeviceOpen;
- (BOOL)isAnyBlockDeviceOpen;
- (BOOL)isAnyOtherOpen;

// Read/write operations
- (IOReturn)readAt:(unsigned int)offset
            length:(unsigned int)length
            buffer:(void *)buffer
        actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client;

- (IOReturn)writeAt:(unsigned int)offset
             length:(unsigned int)length
             buffer:(void *)buffer
         actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client;

- (IOReturn)readAsyncAt:(unsigned int)offset
                 length:(unsigned int)length
                 buffer:(void *)buffer
                 client:(vm_task_t)client
               pending:(void *)pending;

// Device methods
- (unsigned int)deviceBytesOnce;
- (IOReturn)completeTransfer:(void *)status
              actualLength:(unsigned int)actualLength
                    client:(vm_task_t)client;

// Physical disk
- (id)setPhysicalDisk:(id)disk;
- (id)isWriteProtected;

// Geometry management
- (IOReturn)setBlockSize:(unsigned int)size;
- (unsigned int)blockSize;
- (IOReturn)setLogicalBlockCount:(unsigned int)count;
- (unsigned int)logicalBlockCount;
- (IOReturn)setWriteProtected:(BOOL)protect;
- (IOReturn)setMaxBytesPerTransfer:(unsigned int)maxBytes;

@end
