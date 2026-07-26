/*
 * IODiskNEW.h - Interface for generic Disk class (NEW implementation)
 *
 * Based on IODisk.h
 */

#import <driverkit/return.h>
#import <driverkit/IODevice.h>
#import <bsd/sys/disktab.h>
#import <kernserv/clock_timer.h>

@interface IODiskNEW : IODevice
{
@private
	id		_nextLogicalDisk;	// next LogicalDisk object in chain
	unsigned	_blockSize;		// in bytes
	unsigned	_diskSize;		// in blockSize's
	BOOL		_removable;		// removable media device
	BOOL		_formatted;		// disk is formatted
	BOOL		_isPhysical;		// this is NOT a logical disk
	BOOL		_writeProtected;
#ifdef	KERNEL
	void		*_devAndIdInfo;		// provides dev_t to id mapping (IODevAndIdInfoNEW *)
#endif	KERNEL
	id		_LogicalDiskLock;	// NXLock for serialization
	id		_drive;			// associated drive object

	int		_IODiskNEW_reserved[4];
}

/*
 * Register instance with current name space.
 */

/*
 * Public methods to get disk parameters (from decompiled code).
 */
- (unsigned)blockSize;
- (unsigned)diskSize;
- drive;
- (IOReturn)eject;
- (int)errnoFromReturn : (IOReturn)rtn;
- free;
- (BOOL)isFormatted;
- (BOOL)isPhysical;
- (BOOL)isRemovable;
- (BOOL)isWriteProtected;
- (IOReturn)getIntValues : (unsigned *)parameterArray
	     forParameter : (IOParameterName)parameterName
		    count : (unsigned *)count;
- (void)lockLogicalDisks;
- nextLogicalDisk;
- registerDevice;
- (void)setBlockSize : (unsigned)size;
- (void)setDiskSize : (unsigned)size;
- (void)setDrive : driveId;
- (void)setFormatted : (BOOL)formattedFlag;
- (void)setFormattedInternal : (BOOL)formattedFlag;
- (void)setIsPhysical : (BOOL)isPhysical;
- (void)setLogicalDisk : diskId;
- (void)setRemovable : (BOOL)removableFlag;
- (void)setWriteProtected : (BOOL)writeProtectFlag;
- (const char *)stringFromReturn : (IOReturn)rtn;
- (void)unlockLogicalDisks;

/*
 * Private methods to get and set disk parameters.
 */

/*
 * Eject method.
 */

/*
 * Get/set parameters used by subclasses.
 */

/*
 * Drive association.
 */

/*
 * For gathering cumulative statistics.
 */

/*
 * Register a connection with LogicalDisk.
 */

/*
 * Lock/Unlock device for LogicalDisk-specific methods.
 */

/*
 * Convert an IOReturn to text.
 */

/*
 * Convert an IOReturn to errno.
 */

/*
 * Free method.
 */

@end

/* End of IODiskNEW interface. */
