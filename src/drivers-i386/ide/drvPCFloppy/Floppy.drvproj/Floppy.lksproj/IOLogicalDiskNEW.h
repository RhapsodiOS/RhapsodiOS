/*
 * IOLogicalDiskNEW.h - Interface for LogicalDisk class (NEW implementation)
 *
 * Base class for logical disk operations (partitions, etc.)
 */

#import "IODiskNew.h"
#import "IODiskProtocols.h"

#ifdef	KERNEL
#import <driverkit/kernelDiskMethods.h>
#import <bsd/dev/ldd.h>
#endif	KERNEL

@interface IOLogicalDiskNEW : IODiskNEW <IODiskReadingAndWriting>
{
@private
	id		_physicalDisk;		// physical disk object
	unsigned	_partitionBase;		// base offset of partition
	BOOL		_instanceOpen;		// instance open flag

	int		_IOLogicalDiskNEW_reserved[4];
}

/*
 * Connect to physical disk.
 */
- (IOReturn)connectToPhysicalDisk : diskId;

/*
 * Free method.
 */
- free;

/*
 * Get physical disk.
 */
- physicalDisk;

/*
 * Check if instance is open.
 */
- (BOOL)isInstanceOpen;

/*
 * Set instance open flag.
 */
- (void)setInstanceOpen : (BOOL)openFlag;

/*
 * Check if disk is open.
 */
- (BOOL)isOpen;

/*
 * Check if any other instance is open.
 */
- (BOOL)isAnyOtherOpen;

/*
 * Set partition base offset.
 */
- (void)setPartitionBase : (unsigned)base;

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
@interface IOLogicalDiskNEW(private)

/*
 * Common disk parameter validation.
 */
- (IOReturn)_diskParamCommon : (unsigned)offset
		        length : (unsigned)length
		  deviceOffset : (unsigned *)deviceOffset
		   bytesToMove : (unsigned *)bytesToMove;

@end

/* End of IOLogicalDiskNEW interface. */
