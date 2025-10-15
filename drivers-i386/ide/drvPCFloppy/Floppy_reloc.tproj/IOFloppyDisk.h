/*
 * IOFloppyDisk.h
 * Floppy Disk Partition/Logical Disk Interface
 */

#import <driverkit/IODisk.h>
#import <driverkit/IOLogicalDisk.h>
#import <driverkit/IODiskPartition.h>

@class IOFloppyDrive;

@interface IOFloppyDisk : IOLogicalDisk
{
    IOFloppyDrive *_drive;
    unsigned int _diskNumber;

    // Geometry
    unsigned int _cylinders;
    unsigned int _heads;
    unsigned int _sectorsPerTrack;
    unsigned int _blockSize;
    unsigned int _capacity;

    // State
    BOOL _isPhysical;
    BOOL _isWriteProtected;
    BOOL _isRemovable;
    BOOL _isFormatted;

    // Cache support
    void *_cachePointer;
    unsigned int _cacheUnderNumber;
}

- initWithController:(id)controller
                unit:(unsigned int)unit
        diskGeometry:(void *)geometry;

// Disk operations
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
                 pending:(void *)pending
                 client:(vm_task_t)client;

- (IOReturn)writeAsyncAt:(unsigned int)offset
                  length:(unsigned int)length
                  buffer:(void *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client;

// Status
- (BOOL)isWriteProtected;
- (BOOL)isRemovable;
- (BOOL)isPhysical;
- (BOOL)isFormatted;

// Geometry
- (unsigned int)diskSize;
- (unsigned int)blockSize;
- (unsigned int)cylindersPerDisk;
- (unsigned int)sizeList;
- (unsigned int)sizeListFromCapacities;

// Cache operations
- (void *)cachePointerFromUnderNumber:(unsigned int)underNumber;

// Format
- (IOReturn)formatMedia;
- (IOReturn)formatCylinder:(unsigned int)cylinder
                      head:(unsigned int)head
                      data:(void *)data;

// Eject
- (IOReturn)ejectMedia;
- (IOReturn)updatePhysicalParameters;

// Partition support
- (IOReturn)nextLogicalDisk;
- (IOReturn)setRemovable:(BOOL)removable;
- (IOReturn)registerDevice;
- (IOReturn)unregisterDevice;
- (IOReturn)logicalDisk;
- (IOReturn)unlockLogicalDisk;
- (IOReturn)lockLogicalDisk;
- (IOReturn)setBlockDeviceOpen;
- (IOReturn)setBlockDeviceOpen:(BOOL)open;

// Format internal
- (IOReturn)setFormatted:(BOOL)formatted;
- (IOReturn)setFormattedInternal:(BOOL)formatted;
- (IOReturn)isBlockDeviceOpen;

// Drive relationship
- (void)setDrive:(IOFloppyDrive *)drive;

// Additional operations
- (IOReturn)getGeometry:(void *)geometry;
- (IOReturn)setGeometry:(void *)geometry;
- (IOReturn)getCapacity:(unsigned long long *)capacity;
- (IOReturn)readBlock:(unsigned int)blockNumber
               buffer:(void *)buffer
               client:(vm_task_t)client;
- (IOReturn)writeBlock:(unsigned int)blockNumber
                buffer:(void *)buffer
                client:(vm_task_t)client;
- (IOReturn)completeTransfer:(void *)transfer
                      status:(IOReturn)status
                actualLength:(unsigned int)actualLength;
- (IOReturn)pendingRequest:(void **)request;
- (const char *)driverName;
- (IOReturn)isDiskReady:(BOOL *)ready;

// IOLogicalDisk inherited methods
- (BOOL)isOpen;
- (BOOL)isAnyOtherOpen;
- (IOReturn)connectToPhysicalDisk:(id)physicalDisk;
- (void)setPartitionBase:(unsigned)partBase;
- (id)physicalDisk;
- (void)setPhysicalBlockSize:(unsigned)size;
- (u_int)physicalBlockSize;
- (BOOL)isInstanceOpen;
- (void)setInstanceOpen:(BOOL)isOpen;

// IODisk inherited methods
- (void)setLogicalDisk:(id)diskId;
- (void)lockLogicalDisks;
- (void)unlockLogicalDisks;
- (const char *)stringFromReturn:(IOReturn)rtn;
- (IOReturn)errnoFromReturn:(IOReturn)rtn;
- (IOReturn)eject;
- (IOReturn)abortRequest;
- (IOReturn)diskBecameReady;
- (IODiskReadyState)updateReadyState;
- (BOOL)needsManualPolling;
- (IOReturn)kernelDeviceInfo:(void *)info;

// Partition/Label methods
- (IOReturn)virtualLabel;
- (IOReturn)getLabel:(void *)label;
- (IOReturn)setLabel:(void *)label;

@end
