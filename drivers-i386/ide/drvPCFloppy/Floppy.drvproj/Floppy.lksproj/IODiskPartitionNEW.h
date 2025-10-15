/*
 * IODiskPartitionNEW.h
 * Stub class for IODiskPartition compatibility
 */

#import <driverkit/IODiskPartition.h>

/*
 * IODiskPartitionNEW - Compatibility stub class
 * This class provides a compatibility shim for the floppy driver.
 * It inherits all behavior from IODiskPartition and never probes hardware.
 */
@interface IODiskPartitionNEW : IODiskPartition
{
    // Partition state
    BOOL _blockDeviceOpen;
    BOOL _formattedInternal;
    unsigned int _openCount;

    // Partition geometry
    unsigned int _partitionBase;    // Starting sector
    unsigned int _partitionSize;    // Size in sectors

    // Partition info
    char *_label;
    id _physicalDisk;

    // Lock for thread safety
    id _lock;
}

// Partition methods
- (IOReturn)readAt:(unsigned int)offset
            length:(unsigned int)length
            buffer:(void *)buffer
        actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client;

- (IOReturn)readAsyncAt:(unsigned int)offset
                 length:(unsigned int)length
                 buffer:(void *)buffer
                 client:(vm_task_t)client
               pending:(void *)pending;

- (IOReturn)writeAt:(unsigned int)offset
             length:(unsigned int)length
             buffer:(void *)buffer
         actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client;

- (IOReturn)setFormattedInternal:(BOOL)formatted;
- (IOReturn)setBlockDeviceOpen:(BOOL)open;
- (IOReturn)isAnyOtherOpen;
- (id)requiredProtocols;
- (void)deviceStyle;
- (id)protocolsForInsert;

// Label and partition info
- (const char *)diskLabel;
- (id)_initPartition:(void *)disktab;
- (void)_freePartitions;
- (BOOL)checkSafeConfig;

// Partition geometry setters
- (IOReturn)setPartitionBase:(unsigned int)base;
- (IOReturn)setPartitionSize:(unsigned int)size;
- (unsigned int)partitionBase;
- (unsigned int)partitionSize;

// Physical disk management
- (IOReturn)setPhysicalDisk:(id)disk;
- (id)physicalDisk;

@end
