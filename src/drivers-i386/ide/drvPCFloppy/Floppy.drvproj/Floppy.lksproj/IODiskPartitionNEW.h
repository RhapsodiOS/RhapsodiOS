/*
 * IODiskPartitionNEW.h - Interface for NeXT-style LogicalDisk (NEW implementation)
 *
 * Based on IODiskPartition.h
 *
 * This IOLogicalDisk class handles all NeXT/Unix File system specific
 * operations pertaining to a physical disk.
 */

#import "IODiskNew.h"
#import "IOLogicalDiskNEW.h"
#import "IODiskProtocols.h"
#import <bsd/dev/disk_label.h>

#ifdef	KERNEL
#import <driverkit/kernelDiskMethods.h>
#import <bsd/dev/ldd.h>
#endif	KERNEL

@interface IODiskPartitionNEW : IOLogicalDiskNEW <IODiskPartitionExported>
{
@private
	int		_partition;		// like 3 LSB's of the old UNIX minor number
	BOOL		_labelValid;		// label is valid
	BOOL		_blockDeviceOpen;	// block device is open
	BOOL		_rawDeviceOpen;		// raw device is open
	int		_IODiskPartition_reserved[4];
}

/*
 * Class methods.
 */
+ (int)deviceStyle;
+ (const char **)requiredProtocols;
+ (BOOL)probe : deviceDescription;

/*
 * Free all attached logicalDisks.
 */
- free;

/*
 * Eject method.
 */
- (IOReturn)eject;

/*
 * Read disk label.
 */
- (IOReturn)readLabel : (disk_label_t *)label_p;

/*
 * Write disk label.
 */
- (IOReturn)writeLabel : (disk_label_t *)label_p;

/*
 * Get/set "device open" flags.
 */
- (void)setBlockDeviceOpen : (BOOL)openFlag;
- (void)setRawDeviceOpen : (BOOL)openFlag;

/*
 * Public method to check if block device is open.
 */
- (BOOL)isBlockDeviceOpen;

/*
 * Get NeXT partition offset.
 */
- (unsigned)NeXTpartitionOffset;

/*
 * Set formatted flags (override from IODiskNEW).
 */
- (IOReturn)setFormatted : (BOOL)formattedFlag;
- (void)setFormattedInternal : (BOOL)formattedFlag;

/*
 * Read/Write methods.
 */
#ifdef KERNEL
- (IOReturn)readAt : (unsigned)offset
	     length : (unsigned)length
	     buffer : (unsigned char *)buffer
       actualLength : (unsigned *)actualLength
	     client : (vm_task_t)client;

- (IOReturn)readAsyncAt : (unsigned)offset
		  length : (unsigned)length
		  buffer : (unsigned char *)buffer
		 pending : (void *)pending
		  client : (vm_task_t)client;

- (IOReturn)writeAt : (unsigned)offset
	      length : (unsigned)length
	      buffer : (unsigned char *)buffer
        actualLength : (unsigned *)actualLength
	      client : (vm_task_t)client;

- (IOReturn)writeAsyncAt : (unsigned)offset
		   length : (unsigned)length
		   buffer : (unsigned char *)buffer
		  pending : (void *)pending
		   client : (vm_task_t)client;
#endif KERNEL

@end

/*
 * Private methods category.
 */
@interface IODiskPartitionNEW(Private)

/*
 * Free all partitions.
 */
- (IOReturn)_freePartitions;

/*
 * Initialize a partition.
 */
- (IOReturn)_initPartition : (int)partition
		    disktab : (struct disktab *)dt;

/*
 * Probe for disk label.
 */
- (IOReturn)_probeLabel : (BOOL)needsLabel;

/*
 * Check if configuration is safe for destructive operations.
 */
- (IOReturn)checkSafeConfig : (const char *)operation;

/*
 * Check if any block device is open.
 */
- (BOOL)isAnyBlockDevOpen;
- (BOOL)isAnyOtherOpen;

@end
