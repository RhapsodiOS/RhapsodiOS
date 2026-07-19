/*
 * IOLogicalDiskNEW.m - Implementation for LogicalDisk class (NEW implementation)
 *
 * Base class for logical disk operations (partitions, etc.)
 */

#import "IOLogicalDiskNEW.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IOLogicalDiskNEW

/*
 * Connect to physical disk.
 * From decompiled code: connects to physical disk and copies its properties.
 */
- (IOReturn)connectToPhysicalDisk : diskId
{
	BOOL removable;
	BOOL formatted;
	BOOL writeProtected;
	id devAndIdInfo;
	
	// Store physical disk reference (offset 0x134)
	_physicalDisk = diskId;
	
	// This is a logical disk, not a physical disk
	[self setIsPhysical:NO];
	
	// Copy properties from physical disk
	removable = [diskId isRemovable];
	[self setRemovable:removable];
	
	formatted = [diskId isFormatted];
	[self setFormattedInternal:formatted];
	
	writeProtected = [diskId isWriteProtected];
	[self setWriteProtected:writeProtected];
	
	// Initialize logical disk chain to nil
	[self setLogicalDisk:nil];
	
	// Copy device and ID info from physical disk
	devAndIdInfo = [diskId devAndIdInfo];
	[self setDevAndIdInfo:devAndIdInfo];
	
	return IO_R_SUCCESS;
}

/*
 * Free method.
 * From decompiled code: frees next logical disk in chain, then calls super.
 */
- _free
{
	id nextDisk;
	
	// Get next logical disk in chain
	nextDisk = [self nextLogicalDisk];
	
	// Free the next disk if it exists (recursively frees entire chain)
	if (nextDisk != nil) {
		[nextDisk free];
	}
	
	// Call superclass free
	return [super free];
}

/*
 * Get physical disk.
 * From decompiled code: returns physical disk at offset 0x134.
 */
- _physicalDisk
{
	return _physicalDisk;  // offset 0x134
}

/*
 * Check if instance is open.
 * From decompiled code: returns flag at offset 0x13c.
 */
- (BOOL)_isInstanceOpen
{
	return _instanceOpen;  // offset 0x13c
}

/*
 * Set instance open flag.
 * From decompiled code: sets flag at offset 0x13c.
 */
- (void)_setInstanceOpen : (BOOL)openFlag
{
	_instanceOpen = (openFlag != 0);  // offset 0x13c
}

/*
 * Check if disk is open.
 * From decompiled code: checks if this instance or any in the chain is open.
 */
- (BOOL)_isOpen
{
	BOOL instanceOpen;
	id nextDisk;
	
	// Check if this instance is open
	instanceOpen = [self isInstanceOpen];
	if (instanceOpen) {
		return YES;
	}
	
	// Check if there's a next logical disk
	nextDisk = [self nextLogicalDisk];
	if (nextDisk == nil) {
		return NO;
	}
	
	// Recursively check if next disk (or any in its chain) is open
	return [nextDisk isOpen];
}

/*
 * Check if any other instance is open.
 * From decompiled code: iterates through logical disk chain checking for open instances.
 */
- (BOOL)_isAnyOtherOpen
{
	id disk;
	BOOL isOpen;
	
	// Start with physical disk
	disk = _physicalDisk;
	
	// Iterate through all logical disks
	while (1) {
		// Get next logical disk
		disk = [disk nextLogicalDisk];
		
		// If no more disks, none are open
		if (disk == nil) {
			return NO;
		}
		
		// Skip self
		if (disk == self) {
			continue;
		}
		
		// Check if this disk is open
		isOpen = [disk isInstanceOpen];
		if (isOpen) {
			return YES;
		}
	}
}

/*
 * Set partition base offset.
 * From decompiled code: sets base at offset 0x138.
 */
- (void)_setPartitionBase : (unsigned)base
{
	_partitionBase = base;  // offset 0x138
}

#ifdef KERNEL

/*
 * Read at offset.
 * From decompiled code: validates params, then delegates to physical disk.
 */
- (IOReturn)_readAt : (unsigned)offset
	     length : (unsigned)length
	     buffer : (unsigned char *)buffer
       actualLength : (unsigned *)actualLength
	     client : (vm_task_t)client
{
	unsigned deviceOffset;
	unsigned bytesToMove;
	IOReturn result;

	// Validate parameters and calculate offsets
	result = [self __diskParamCommon:offset
	                          length:length
	                    deviceOffset:&deviceOffset
	                     bytesToMove:&bytesToMove];
	if (result != IO_R_SUCCESS) {
		if (actualLength) {
			*actualLength = 0;
		}
		return result;
	}

	// Delegate to physical disk (offset already calculated in deviceOffset)
	return [_physicalDisk _readAt:deviceOffset
	                       length:bytesToMove
	                       buffer:buffer
	                 actualLength:actualLength
	                       client:client];
}

/*
 * Read asynchronously at offset.
 * From decompiled code: validates params, then delegates to physical disk.
 */
- (IOReturn)_readAsyncAt : (unsigned)offset
		  length : (unsigned)length
		  buffer : (unsigned char *)buffer
		 pending : (void *)pending
		  client : (vm_task_t)client
{
	unsigned deviceOffset;
	unsigned bytesToMove;
	IOReturn result;

	// Validate parameters and calculate offsets
	result = [self __diskParamCommon:offset
	                          length:length
	                    deviceOffset:&deviceOffset
	                     bytesToMove:&bytesToMove];
	if (result != IO_R_SUCCESS) {
		return result;
	}

	// Delegate to physical disk (offset already calculated in deviceOffset)
	return [_physicalDisk _readAsyncAt:deviceOffset
	                            length:bytesToMove
	                            buffer:buffer
	                           pending:pending
	                            client:client];
}

/*
 * Write at offset.
 * From decompiled code: checks write protection, validates params, then delegates to physical disk.
 */
- (IOReturn)_writeAt : (unsigned)offset
	      length : (unsigned)length
	      buffer : (unsigned char *)buffer
        actualLength : (unsigned *)actualLength
	      client : (vm_task_t)client
{
	unsigned deviceOffset;
	unsigned bytesToMove;
	IOReturn result;
	BOOL writeProtected;

	// Check if disk is write protected
	writeProtected = [self isWriteProtected];
	if (writeProtected) {
		if (actualLength) {
			*actualLength = 0;
		}
		return (IOReturn)0xfffffd31;  // IO_R_WRITE_PROTECTED
	}

	// Validate parameters and calculate offsets
	result = [self __diskParamCommon:offset
	                          length:length
	                    deviceOffset:&deviceOffset
	                     bytesToMove:&bytesToMove];
	if (result != IO_R_SUCCESS) {
		if (actualLength) {
			*actualLength = 0;
		}
		return result;
	}

	// Delegate to physical disk (offset already calculated in deviceOffset)
	return [_physicalDisk _writeAt:deviceOffset
	                        length:bytesToMove
	                        buffer:buffer
	                  actualLength:actualLength
	                        client:client];
}

/*
 * Write asynchronously at offset.
 * From decompiled code: checks write protection, validates params, then delegates to physical disk.
 */
- (IOReturn)_writeAsyncAt : (unsigned)offset
		   length : (unsigned)length
		   buffer : (unsigned char *)buffer
		  pending : (void *)pending
		   client : (vm_task_t)client
{
	unsigned deviceOffset;
	unsigned bytesToMove;
	IOReturn result;
	BOOL writeProtected;

	// Check if disk is write protected
	writeProtected = [self isWriteProtected];
	if (writeProtected) {
		return (IOReturn)0xfffffd31;  // IO_R_WRITE_PROTECTED
	}

	// Validate parameters and calculate offsets
	result = [self __diskParamCommon:offset
	                          length:length
	                    deviceOffset:&deviceOffset
	                     bytesToMove:&bytesToMove];
	if (result != IO_R_SUCCESS) {
		return result;
	}

	// Delegate to physical disk (offset already calculated in deviceOffset)
	return [_physicalDisk _writeAsyncAt:deviceOffset
	                             length:bytesToMove
	                             buffer:buffer
	                            pending:pending
	                             client:client];
}

#endif KERNEL

@end

/*
 * Category: Private
 */
@implementation IOLogicalDiskNEW(Private)

/*
 * Common disk parameter validation.
 * From decompiled code: validates parameters and calculates device offset and bytes to move.
 */
- (IOReturn)__diskParamCommon : (unsigned)offset
		        length : (unsigned)length
		  deviceOffset : (unsigned *)deviceOffset
		   bytesToMove : (unsigned *)bytesToMove
{
	const char *name;
	unsigned physicalBlockSize;
	unsigned logicalBlockSize;
	unsigned diskSize;
	unsigned blocksNeeded;
	
	// Get name for logging
	name = (const char *)[self name];
	
	// Get block sizes
	physicalBlockSize = [_physicalDisk blockSize];  // offset 0x134
	logicalBlockSize = [self blockSize];
	diskSize = [self diskSize];
	
	// Check if length is a multiple of logical block size
	if (length % logicalBlockSize != 0) {
		IOLog("%s: Bytes requested not multiple of block size
", name);
		return (IOReturn)0xfffffd3e;
	}
	
	// Calculate blocks needed
	blocksNeeded = length / logicalBlockSize;
	
	// Check if operation fits within partition bounds
	if (diskSize < offset + blocksNeeded) {
		// Operation goes past end of partition
		if (diskSize <= offset) {
			// Offset is completely out of bounds
			return (IOReturn)0xfffffd3e;
		}
		// Truncate to fit within partition
		blocksNeeded = diskSize - offset;
	}
	
	// Calculate device offset in physical blocks
	// deviceOffset = (logicalBlockSize / physicalBlockSize) * offset + partitionBase
	*deviceOffset = (logicalBlockSize / physicalBlockSize) * offset + _partitionBase;  // offset 0x138
	
	// Calculate bytes to move
	// bytesToMove = physicalBlockSize * blocksNeeded * (logicalBlockSize / physicalBlockSize)
	*bytesToMove = physicalBlockSize * blocksNeeded * (logicalBlockSize / physicalBlockSize);
	
	return IO_R_SUCCESS;
}

@end
