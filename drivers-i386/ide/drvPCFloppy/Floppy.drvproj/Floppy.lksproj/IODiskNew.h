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
- _registerDevice;		// nil return means failure

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
- (unsigned)_diskSize;
- (unsigned)_blockSize;
- (BOOL)_isFormatted;
- (BOOL)_isRemovable;
- (BOOL)_isPhysical;
- (BOOL)_isWriteProtected;

/*
 * Eject method.
 */
- (IOReturn)_eject;

/*
 * Get/set parameters used by subclasses.
 */
- (void)_setDiskSize		: (unsigned)size;
- (void)_setBlockSize		: (unsigned)size;
- (void)_setIsPhysical		: (BOOL)isPhysical;
- _nextLogicalDisk;
- (void)_setRemovable		: (BOOL)removableFlag;
- (void)_setWriteProtected	: (BOOL)writeProtectFlag;
- (void)_setFormattedInternal	: (BOOL)formattedFlag;
- (void)_setFormatted		: (BOOL)formattedFlag;

/*
 * Drive association.
 */
- _drive;
- (void)_setDrive		: driveId;

/*
 * For gathering cumulative statistics.
 */
- (IOReturn)_getIntValues	: (unsigned *)parameterArray
		forParameter	: (IOParameterName)parameterName
			count	: (unsigned *)count;	// in/out

/*
 * Register a connection with LogicalDisk.
 */
- (void)_setLogicalDisk		: diskId;

/*
 * Lock/Unlock device for LogicalDisk-specific methods.
 */
- (void)_lockLogicalDisks;
- (void)_unlockLogicalDisks;

/*
 * Convert an IOReturn to text.
 */
- (const char *)_stringFromReturn	: (IOReturn)rtn;

/*
 * Convert an IOReturn to errno.
 */
- (int)_errnoFromReturn		: (IOReturn)rtn;

/*
 * Free method.
 */
- _free;

@end

/* End of IODiskNEW interface. */
