/*
 * IODiskNew.m - Implementation for generic Disk class (NEW implementation)
 *
 * Based on IODisk.m
 */

#import "IODiskNew.h"
#import <driverkit/generalFuncs.h>
#import <string.h>
#import <machkit/NXLock.h>
#import <driverkit/kernelDriver.h>

@implementation IODiskNEW

/*
 * Public block size getter.
 * From decompiled code: returns *(unsigned int *)(self + 0x10c)
 */
- (unsigned)blockSize
{
	return _blockSize;
}

/*
 * Public disk size getter.
 * From decompiled code: returns *(unsigned int *)(self + 0x110)
 */
- (unsigned)diskSize
{
	return _diskSize;
}

/*
 * Public drive getter.
 * From decompiled code: returns *(ID *)(self + 0x120)
 */
- drive
{
	return _drive;
}

/*
 * Public eject method.
 * From decompiled code: calls IOPanic and returns 0xfffffd39
 * Note: Ejecting from kernel space is illegal and will panic the system.
 */
- (IOReturn)eject
{
	IOPanic("IODisk eject in kernel illegal\n");
	return (IOReturn)0xfffffd39;
}

/*
 * Public errno conversion method.
 * From decompiled code: converts IOReturn codes to errno values.
 * Handles specific disk-related error codes before calling super.
 */
- (int)errnoFromReturn : (IOReturn)rtn
{
	// Check for IO_R_INVALID_ARG (0xfffffbb3 = -1101)
	if (rtn == (IOReturn)0xfffffbb3) {
		return 0x16;  // 22 = EINVAL
	}
	
	// Check error codes less than -1100
	if ((int)rtn < -0x44c) {  // -0x44c = -1100
		// Check for IO_R_NO_DEVICE (0xfffffbb2 = -1102)
		if (rtn == (IOReturn)0xfffffbb2) {
			return 6;  // ENXIO - No such device or address
		}
	} else if (rtn == (IOReturn)0xfffffbb4) {  // -1100
		return 6;  // ENXIO
	}
	
	// Delegate to superclass for other error codes
	return [super errnoFromReturn:rtn];
}

/*
 * Public free method.
 * From decompiled code: frees any chained logical disks before freeing self.
 * Note: Original decompiled code doesn't show super free call.
 */
- free
{
	id nextDisk;
	
	// Get the next logical disk in chain
	nextDisk = [self nextLogicalDisk];
	if (nextDisk != nil) {
		// Free the chained disk
		[nextDisk free];
		// Clear the reference
		[self setLogicalDisk:nil];
	}
	
	// Note: Decompiled code shows return here without calling super free
	// This may be because the actual freeing happens elsewhere
	return self;
}

/*
 * Public formatted flag getter.
 * From decompiled code: returns *(char *)(self + 0x115)
 */
- (BOOL)isFormatted
{
	return _formatted;
}

/*
 * Public physical disk flag getter.
 * From decompiled code: returns *(char *)(self + 0x116)
 */
- (BOOL)isPhysical
{
	return _isPhysical;
}

/*
 * Public removable flag getter.
 * From decompiled code: returns *(char *)(self + 0x114)
 */
- (BOOL)isRemovable
{
	return _removable;
}

/*
 * Public write protected flag getter.
 * From decompiled code: returns *(char *)(self + 0x117)
 */
- (BOOL)isWriteProtected
{
	return _writeProtected;
}

/*
 * Get integer values for parameter.
 * From decompiled code: handles "IOIsADisk" and "IOIsAPhysicalDisk" queries.
 */
- (IOReturn)getIntValues : (unsigned *)parameterArray
	     forParameter : (IOParameterName)parameterName
		    count : (unsigned *)count
{
	// Check for "IOIsADisk" parameter (10 characters)
	if (strcmp(parameterName, "IOIsADisk") == 0) {
		*count = 0;
		return IO_R_SUCCESS;
	}
	
	// Check for "IOIsAPhysicalDisk" parameter (18 characters)
	if (strcmp(parameterName, "IOIsAPhysicalDisk") == 0) {
		*count = 1;
		*parameterArray = (unsigned)(_isPhysical != 0);
		return IO_R_SUCCESS;
	}
	
	// Delegate to superclass for other parameters
	return [super getIntValues:parameterArray 
		      forParameter:parameterName 
			     count:count];
}

/*
 * Public lock logical disks method.
 * From decompiled code: calls [_LogicalDiskLock lock]
 */
- (void)lockLogicalDisks
{
	// Lock at offset 0x11c is _LogicalDiskLock
	[_LogicalDiskLock lock];
}

/*
 * Public next logical disk getter.
 * From decompiled code: returns *(ID *)(self + 0x108)
 */
- nextLogicalDisk
{
	return _nextLogicalDisk;  // offset 0x108
}

/*
 * Public register device method.
 * From decompiled code: only registers physical disks, initializes lock.
 */
- registerDevice
{
	id result;
	
	// Only register if this is a physical disk (offset 0x116)
	if (!_isPhysical) {
		return nil;
	}
	
	// Initialize next logical disk to nil (offset 0x108)
	_nextLogicalDisk = nil;
	
	// Create a new NXLock for logical disk operations (offset 0x11c)
	_LogicalDiskLock = [[NXLock alloc] init];
	
	// Call superclass registerDevice
	result = [super registerDevice];
	
	return result;
}

/*
 * Public set block size method.
 * From decompiled code: sets value at offset 0x10c
 */
- (void)setBlockSize : (unsigned)size
{
	_blockSize = size;  // offset 0x10c
}

/*
 * Public set disk size method.
 * From decompiled code: sets value at offset 0x110
 */
- (void)setDiskSize : (unsigned)size
{
	_diskSize = size;  // offset 0x110
}

/*
 * Public set drive method.
 * From decompiled code: sets value at offset 0x120
 */
- (void)setDrive : driveId
{
	_drive = driveId;  // offset 0x120
}

/*
 * Public set formatted method.
 * From decompiled code: calls IOPanic - illegal to call from user space
 */
- (void)setFormatted : (BOOL)formattedFlag
{
	IOPanic("setFormatted: on IODisk");
}

/*
 * Public set formatted internal method.
 * From decompiled code: sets value at offset 0x115
 */
- (void)setFormattedInternal : (BOOL)formattedFlag
{
	_formatted = (formattedFlag != 0);  // offset 0x115
}

/*
 * Public set is physical method.
 * From decompiled code: sets value at offset 0x116
 */
- (void)setIsPhysical : (BOOL)isPhysical
{
	_isPhysical = (isPhysical != 0);  // offset 0x116
}


/*
 * Public set logical disk method.
 * From decompiled code: sets value at offset 0x108, but only if currently nil
 */
- (void)setLogicalDisk : diskId
{
	// Only set if _nextLogicalDisk is currently nil
	if (_nextLogicalDisk == nil) {
		_nextLogicalDisk = diskId;  // offset 0x108
	}
}

/*
 * Public set removable method.
 * From decompiled code: sets value at offset 0x114
 */
- (void)setRemovable : (BOOL)removableFlag
{
	_removable = (removableFlag != 0);  // offset 0x114
}

/*
 * Public set write protected method.
 * From decompiled code: sets value at offset 0x117
 */
- (void)setWriteProtected : (BOOL)writeProtectFlag
{
	_writeProtected = (writeProtectFlag != 0);  // offset 0x117
}

/*
 * Public string from return method.
 * From decompiled code: looks up IOReturn in _diskIoReturnValues table
 */
- (const char *)stringFromReturn : (IOReturn)rtn
{
	// Disk-specific IOReturn values table
	// Format: { returnCode, stringPtr, terminatorFlag }
	static const struct {
		IOReturn code;
		const char *string;
		int terminator;
	} diskIoReturnValues[] = {
		// Add disk-specific return codes here if needed
		{ 0, NULL, 1 }  // Terminator entry
	};
	
	// Search through disk-specific return values
	const void *table = diskIoReturnValues;
	const int *ptr = (const int *)table;
	
	while (1) {
		if (*ptr == (int)rtn) {
			// Found matching return code, return the string
			return (const char *)*(ptr + 1);
		}
		// Check terminator (third element in each entry)
		if (*(ptr + 2) != 0) {
			break;
		}
		ptr += 2;  // Move to next entry (skip code and string pointer)
	}
	
	// Not found in disk table, delegate to superclass
	return [super stringFromReturn:rtn];
}

/*
 * Public unlock logical disks method.
 * From decompiled code: calls [_LogicalDiskLock unlock]
 */
- (void)unlockLogicalDisks
{
	// Lock at offset 0x11c is _LogicalDiskLock
	[_LogicalDiskLock unlock];
}

/*
 * Register instance with current name space.
 */
- _registerDevice
{
	// TODO: Implement registration
	return self;
}

/*
 * Free method.
 */
- _free
{
	// TODO: Implement cleanup
	return [super free];
}

/*
 * Disk size getter.
 */
- (unsigned)_diskSize
{
	return _diskSize;
}

/*
 * Disk size setter.
 */
- (void)_setDiskSize : (unsigned)size
{
	_diskSize = size;
}

/*
 * Block size getter.
 */
- (unsigned)_blockSize
{
	return _blockSize;
}

/*
 * Block size setter.
 */
- (void)_setBlockSize : (unsigned)size
{
	_blockSize = size;
}

/*
 * Formatted flag getter.
 */
- (BOOL)_isFormatted
{
	return _formatted;
}

/*
 * Formatted flag setter.
 */
- (void)_setFormatted : (BOOL)formattedFlag
{
	_formatted = formattedFlag;
}

/*
 * Formatted flag setter (internal).
 */
- (void)_setFormattedInternal : (BOOL)formattedFlag
{
	_formatted = formattedFlag;
}

/*
 * Removable flag getter.
 */
- (BOOL)_isRemovable
{
	return _removable;
}

/*
 * Removable flag setter.
 */
- (void)_setRemovable : (BOOL)removableFlag
{
	_removable = removableFlag;
}

/*
 * Physical flag getter.
 */
- (BOOL)_isPhysical
{
	return _isPhysical;
}

/*
 * Physical flag setter.
 */
- (void)_setIsPhysical : (BOOL)isPhysical
{
	_isPhysical = isPhysical;
}

/*
 * Write protected flag getter.
 */
- (BOOL)_isWriteProtected
{
	return _writeProtected;
}

/*
 * Write protected flag setter.
 */
- (void)_setWriteProtected : (BOOL)writeProtectFlag
{
	_writeProtected = writeProtectFlag;
}

/*
 * Next logical disk getter.
 */
- _nextLogicalDisk
{
	return _nextLogicalDisk;
}

/*
 * Set logical disk.
 */
- (void)_setLogicalDisk : diskId
{
	_nextLogicalDisk = diskId;
}

/*
 * Drive getter.
 */
- _drive
{
	return _drive;
}

/*
 * Drive setter.
 */
- (void)_setDrive : driveId
{
	_drive = driveId;
}

/*
 * Lock logical disks.
 */
- (void)_lockLogicalDisks
{
	// TODO: Implement locking
	if (_LogicalDiskLock) {
		// [_LogicalDiskLock lock];
	}
}

/*
 * Unlock logical disks.
 */
- (void)_unlockLogicalDisks
{
	// TODO: Implement unlocking
	if (_LogicalDiskLock) {
		// [_LogicalDiskLock unlock];
	}
}

/*
 * Eject method.
 */
- (IOReturn)_eject
{
	// TODO: Implement eject
	return IO_R_SUCCESS;
}

/*
 * Get integer values for parameter.
 */
- (IOReturn)_getIntValues : (unsigned *)parameterArray
	     forParameter : (IOParameterName)parameterName
		    count : (unsigned *)count
{
	// TODO: Implement parameter retrieval
	return IO_R_UNSUPPORTED;
}

/*
 * Convert IOReturn to string.
 */
- (const char *)_stringFromReturn : (IOReturn)rtn
{
	// TODO: Implement string conversion
	return "Unknown";
}

/*
 * Convert IOReturn to errno.
 */
- (int)_errnoFromReturn : (IOReturn)rtn
{
	// TODO: Implement errno conversion
	return 0;
}

@end
