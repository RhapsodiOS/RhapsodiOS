/*
 * IOLogicalDiskNEW.h - Interface for LogicalDisk class (NEW implementation)
 *
 * Base class for logical disk operations (partitions, etc.)
 */

#import "IODiskNEW.h"

#ifdef	KERNEL
#import <driverkit/kernelDiskMethods.h>
#import <bsd/dev/ldd.h>
#endif	KERNEL

@interface IOLogicalDiskNEW : IODiskNEW
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
- _free;

/*
 * Get physical disk.
 */
- _physicalDisk;

/*
 * Check if instance is open.
 */
- (BOOL)_isInstanceOpen;

/*
 * Set instance open flag.
 */
- (void)_setInstanceOpen : (BOOL)openFlag;

/*
 * Check if disk is open.
 */
- (BOOL)_isOpen;

/*
 * Check if any other instance is open.
 */
- (BOOL)_isAnyOtherOpen;

/*
 * Set partition base offset.
 */
- (void)_setPartitionBase : (unsigned)base;

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
@interface IOLogicalDiskNEW(Private)

/*
 * Common disk parameter validation.
 */
- (IOReturn)__diskParamCommon : (unsigned)offset
		        length : (unsigned)length
		  deviceOffset : (unsigned *)deviceOffset
		   bytesToMove : (unsigned *)bytesToMove;

@end

/* End of IOLogicalDiskNEW interface. */
