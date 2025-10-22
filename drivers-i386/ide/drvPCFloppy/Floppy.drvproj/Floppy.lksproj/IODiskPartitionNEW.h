/*
 * IODiskPartitionNEW.h - Interface for NeXT-style LogicalDisk (NEW implementation)
 *
 * Based on IODiskPartition.h
 *
 * This IOLogicalDisk class handles all NeXT/Unix File system specific
 * operations pertaining to a physical disk.
 */

#import "IODiskNEW.h"
#import "IOLogicalDiskNEW.h"
#import <bsd/dev/disk_label.h>

#ifdef	KERNEL
#import <driverkit/kernelDiskMethods.h>
#import <bsd/dev/ldd.h>
#endif	KERNEL

@interface IODiskPartitionNEW : IOLogicalDiskNEW
{
@private
	int		_partition;		// like 3 LSB's of the old UNIX minor number
	BOOL		_labelValid;		// label is valid
	BOOL		_blockDeviceOpen;	// block device is open
	BOOL		_rawDeviceOpen;		// raw device is open
	unsigned char	_physicalPartition;	// partition index in real map
	ns_time_t	_probeTime;
	id		_partitionWaitLock;	// condition lock to wait for probe of label
	int		_IODiskPartitionNEW_reserved[4];
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
- _free;

/*
 * Eject method.
 */
- (IOReturn)_eject;

/*
 * Read disk label.
 */
- (IOReturn)_readLabel : (disk_label_t *)label_p;

/*
 * Write disk label.
 */
- (IOReturn)_writeLabel : (disk_label_t *)label_p;

/*
 * Get/set "device open" flags.
 */
- (BOOL)_isBlockDeviceOpen;
- (void)_setBlockDeviceOpen : (BOOL)openFlag;
- (BOOL)_isRawDeviceOpen;
- (void)_setRawDeviceOpen : (BOOL)openFlag;

/*
 * Public method to check if block device is open.
 */
- (BOOL)isBlockDeviceOpen;

/*
 * Get NeXT partition offset.
 */
- (unsigned)_NeXTpartitionOffset;

/*
 * Set formatted flags (override from IODiskNEW).
 */
- (IOReturn)_setFormatted : (BOOL)formattedFlag;
- (void)_setFormattedInternal : (BOOL)formattedFlag;

/*
 * Read/Write methods.
 */
#ifdef KERNEL
- (IOReturn)_readAt : (unsigned)offset
	     length : (unsigned)length
	     buffer : (unsigned char *)buffer
       actualLength : (unsigned *)actualLength
	     client : (vm_task_t)client;

- (IOReturn)_readAsyncAt : (unsigned)offset
		  length : (unsigned)length
		  buffer : (unsigned char *)buffer
		 pending : (void *)pending
		  client : (vm_task_t)client;

- (IOReturn)_writeAt : (unsigned)offset
	      length : (unsigned)length
	      buffer : (unsigned char *)buffer
        actualLength : (unsigned *)actualLength
	      client : (vm_task_t)client;

- (IOReturn)_writeAsyncAt : (unsigned)offset
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
- (IOReturn)__freePartitions;

/*
 * Initialize a partition.
 */
- (IOReturn)__initPartition : (int)partition
		    disktab : (struct disktab *)dt;

/*
 * Probe for disk label.
 */
- (IOReturn)__probeLabel : (BOOL)needsLabel;

/*
 * Check if configuration is safe for destructive operations.
 */
- (IOReturn)_checkSafeConfig : (const char *)operation;

/*
 * Check if any block device is open.
 */
- (BOOL)_isAnyBlockDevOpen;
- (BOOL)_isAnyOtherOpen;

@end
