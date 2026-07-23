/*
 * Bsd.m - BSD device interface support for IOFloppyDisk
 *
 * Category methods for BSD device node attachment
 */

#import "IOFloppyDisk.h"
#import "Bsd.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <sys/buf.h>
#import <sys/uio.h>

// External BSD functions
extern int physio(int (*strategy)(struct buf *), struct buf *bp, dev_t dev, int flags,
                  u_int (*minphys)(struct buf *), struct uio *uio, int blocksize);
extern vm_map_t IOVmTaskForBuf(struct buf *bp);

// Forward declaration for detached disk identification
static id _identifyDetachedDiskIdFromBsdDev(dev_t dev);

/*
 * _HandleBsdIoctl - BSD ioctl handler
 * From decompiled code: handles ioctl commands from BSD layer.
 *
 * This function implements various ioctl commands for floppy disk control,
 * including getting/setting geometry, formatting, ejecting, and label operations.
 *
 * Parameters:
 *   dev  - BSD device number
 *   cmd  - ioctl command code
 *   data - Pointer to data buffer for command
 *
 * Returns:
 *   0 on success, errno on error
 *
 * Supported ioctl commands:
 *   DKIOCGGEOM (0x40346601)  - Get geometry
 *   DKIOCSGEOM (0x80046602)  - Set geometry
 *   DKIOCFORMAT (0xc0606600) - Format disk
 *   DKIOCEJECT (0x20006415)  - Eject disk
 *   And many more...
 */
static int _HandleBsdIoctl(dev_t dev, unsigned int cmd, int *data)
{
	id drive;
	id disk;
	void *partition;
	unsigned int identifyResult;
	int driveNumber;
	id deviceInfo;
	id detachedDevice;
	unsigned char *partFlags;
	int result = 0;
	unsigned int capacity;
	int formatCapacities;
	int *buffer;
	int i;
	id operation;
	id lock;
	int queueHead;
	int lastEntry;
	BOOL isFormatted;
	BOOL isWriteProtected;
	int blockSize;
	int diskSize;
	char *driveName;
	unsigned int cmdType;
	unsigned int formatState;

	// Identify the BSD device
	identifyResult = _identifyBsdDev(dev, &drive, &disk, &partition);

	// Check for invalid device or block device (bit 0 set in partition flags)
	if (identifyResult == 0) {
		return ENXIO;  // 6
	}

	partFlags = (unsigned char *)partition;
	if ((partFlags != NULL) && ((*partFlags & 1) != 0)) {
		return ENXIO;  // Block device ioctl not allowed on raw device
	}

	// Get drive number and device info
	driveNumber = [IOFloppyDisk driveNumberOfDrive:drive];
	disk = *(id *)(0xc00c + (driveNumber * 0x34));

	// Get detached device info at offset 0x08
	deviceInfo = *(id *)(0xc008 + (driveNumber * 0x34));

	// Special handling: allow DKIOCFORMAT (0xc0606600) even without disk
	if ((deviceInfo == nil || *(int *)((char *)deviceInfo + 0x168) == 0) &&
	    (cmd != 0xc0606600) && (disk == nil)) {
		return ENXIO;
	}

	// Get the actual device info pointer
	if (identifyResult != 2) {
		disk = *(id *)(0xc00c + (driveNumber * 0x34));
	}

	// Process ioctl commands
	switch (cmd) {
	case 0x40346601:  // DKIOCGGEOM - Get geometry
		bzero(data, 0x34);

		// Get capacity from device at offset 0x164
		capacity = *(unsigned int *)((char *)deviceInfo + 0x164);

		// Set geometry based on capacity
		if (capacity == 0x100) {
			// 1.44MB
			*(unsigned char *)(data + 1) = 2;      // heads
			data[2] = 0x50;                        // cylinders (80)
			data[3] = 2;                           // (unknown)
			data[5] = 2;                           // media type
			data[8] = 0x200;                       // sector size
			data[10] = 0x12;                       // sectors per track (18)
		} else if (capacity == 0x20) {
			// 720KB
			*(unsigned char *)(data + 1) = 2;      // heads
			data[2] = 0x50;                        // cylinders (80)
			data[3] = 2;
			data[5] = 1;                           // media type
			data[8] = 0x200;                       // sector size
			data[10] = 9;                          // sectors per track
		} else if (capacity == 0x800) {
			// 2.88MB
			*(unsigned char *)(data + 1) = 2;      // heads
			data[2] = 0x50;                        // cylinders (80)
			data[3] = 2;
			data[5] = 3;                           // media type
			data[8] = 0x200;                       // sector size
			data[10] = 0x24;                       // sectors per track (36)
		} else {
			// Use geometry from device
			id geometry = *(id *)((char *)deviceInfo + 0x14c);
			if (*(int *)((char *)deviceInfo + 0x148) == 1) {
				// Default to 1.44MB
				*(unsigned char *)(data + 1) = 2;
				data[2] = 0x50;
				data[3] = 2;
				data[5] = 2;
				data[8] = 0x200;
				data[10] = 0x12;
			} else {
				*(unsigned char *)(data + 1) = *(unsigned char *)((char *)geometry + 8);
				data[2] = *(int *)((char *)geometry + 0xc);
				data[8] = *(int *)((char *)geometry + 0x14);
				data[10] = *(int *)((char *)geometry + 0x10);
				data[3] = 2;

				capacity = *(unsigned int *)((char *)deviceInfo + 0x148);
				if (capacity == 0x20) {
					data[5] = 1;
				} else if (capacity == 0x100) {
					data[5] = 2;
				} else if (capacity == 0x800) {
					data[5] = 3;
				} else {
					data[5] = 0;
				}
			}
		}

		data[4] = 0;
		data[0xc] = (unsigned char)*(unsigned char *)(data + 1) * data[10] * data[2];
		data[6] = data[0xc] * data[8];
		*data = 2;
		data[7] = 1;
		*(unsigned char *)(data + 9) = 2;
		*(unsigned char *)(data + 0xb) = 0x1b;
		*(unsigned char *)((char *)data + 0x2d) = 0x65;

		isFormatted = [deviceInfo isFormatted];
		if (isFormatted) {
			*(unsigned char *)(data + 4) |= 1;
		}

		isWriteProtected = [deviceInfo isWriteProtected];
		if (isWriteProtected) {
			*(unsigned char *)(data + 4) |= 4;
		}
		break;

	case 0x80046602:  // DKIOCSGEOM - Set geometry
		switch (*data) {
		case 1:
			*(unsigned int *)((char *)deviceInfo + 0x164) = 0x20;  // 720KB
			break;
		case 2:
			*(unsigned int *)((char *)deviceInfo + 0x164) = 0x100; // 1.44MB
			break;
		case 3:
			*(unsigned int *)((char *)deviceInfo + 0x164) = 0x800; // 2.88MB
			break;
		default:
			*(unsigned int *)((char *)deviceInfo + 0x164) = 0;
			break;
		}
		break;

	case 0x40046418:  // DKIOCBLKSIZE - Get block size
		*data = [deviceInfo blockSize];
		break;

	case 0x40046419:  // DKIOCNUMBLKS - Get number of blocks
		*data = [deviceInfo diskSize];
		break;

	case 0x40046417:  // DKIOCISFORMATTED - Is formatted?
		isFormatted = [disk isFormatted];
		*data = (int)isFormatted;
		break;

	case 0x80046417:  // DKIOCSETFORMATTED - Set formatted (not supported)
		result = -0x2c7;  // ENOTTY
		break;

	case 0x20006415:  // DKIOCEJECT - Eject disk
		[deviceInfo detachBsdDiskInterfaceFromDrive:drive];

		// Allocate eject operation (type 2)
		operation = (id)IOMalloc(0x28);
		*(unsigned int *)operation = 2;  // Type 2: eject

		// Allocate completion lock
		lock = [[objc_getClass("NXConditionLock") alloc] initWith:1];
		*(id *)((char *)operation + 0xc) = lock;

		// Lock queue and add operation
		[*(id *)((char *)deviceInfo + 0x158) lock];

		queueHead = (int)((char *)deviceInfo + 0x150);
		if (*(int *)((char *)deviceInfo + 0x150) == queueHead) {
			// Queue empty
			*(id *)((char *)deviceInfo + 0x150) = operation;
			*(id *)((char *)deviceInfo + 0x154) = operation;
			*(int *)((char *)operation + 0x20) = queueHead;
			*(int *)((char *)operation + 0x24) = queueHead;
		} else {
			// Append to queue
			lastEntry = *(int *)((char *)deviceInfo + 0x154);
			*(int *)((char *)operation + 0x24) = lastEntry;
			*(int *)((char *)operation + 0x20) = queueHead;
			*(id *)((char *)deviceInfo + 0x154) = operation;
			*(id *)(lastEntry + 0x20) = operation;
		}

		[*(id *)((char *)deviceInfo + 0x158) unlockWith:1];

		// Wait for completion
		[lock lockWhen:0];
		[lock unlock];

		// Check result
		if (*(char *)((char *)operation + 8) == 0) {
			result = [disk eject];
			if (result == 0) {
				result = -0x2d1;  // EIO
				IOLog("%s: Some unwritten data was lost, due to bad media or a missing disk.\n",
				      [deviceInfo name]);
			} else {
				[deviceInfo attachBsdDiskInterfaceToDrive:drive];
			}
		} else {
			result = [disk eject];
			if (result != 0) {
				[deviceInfo attachBsdDiskInterfaceToDrive:drive];
			}
		}

		[lock free];
		IOFree(operation, 0x28);
		break;

	case 0x4020660a:  // Get format capacities list
		// Get format capacities from device
		formatCapacities = [deviceInfo formatCapacities];

		// Allocate buffer for capacity list (at offset pointed to by data[1])
		buffer = (int *)data[1];

		// Store number of capacities in first word
		*buffer = 3;  // 3 capacities: 720KB, 1.44MB, 2.88MB

		// Fill in capacity codes
		buffer[1] = 0x20;   // 720KB (DD)
		buffer[2] = 0x100;  // 1.44MB (HD)
		buffer[3] = 0x800;  // 2.88MB (ED)
		break;

	case 0x40306405:  // Get drive info
		// Return drive name string pointer
		driveName = (char *)[deviceInfo driveName];
		*(char **)data = driveName;
		break;

	case 0x5c5c6400:  // Read disk label (not supported on floppy)
		result = EINVAL;
		break;

	case 0x9c5c6401:  // Write disk label (not supported on floppy)
		result = EINVAL;
		break;

	case 0xc0606600:  // DKIOCFORMAT - Format disk
		// This is a complex multi-state operation
		// data[0] = command type (1=start, 2=cylinder, 3=end)
		// data[1] = cylinder number (for type 2)

		cmdType = data[0];

		if (cmdType == 1) {
			// Format start - detach BSD interface
			[deviceInfo detachBsdDiskInterfaceFromDrive:drive];

			// Store format state at offset 0x168
			*(unsigned int *)((char *)deviceInfo + 0x168) = 1;

		} else if (cmdType == 2) {
			// Format cylinder
			unsigned int cylinder = data[1];
			void *formatData = (void *)data[2];

			result = [deviceInfo formatCylinder:cylinder data:formatData];

		} else if (cmdType == 3) {
			// Format end - reattach BSD interface
			formatState = *(unsigned int *)((char *)deviceInfo + 0x168);

			if (formatState != 0) {
				*(unsigned int *)((char *)deviceInfo + 0x168) = 0;
				[deviceInfo attachBsdDiskInterfaceToDrive:drive];
			}
		} else {
			result = EINVAL;
		}
		break;

	case 0x40086416:  // DKIOCISWRITABLE - Is disk writable?
		isWriteProtected = [disk isWriteProtected];
		*data = !isWriteProtected;  // Return 1 if writable, 0 if protected
		break;

	case 0x2000641a:  // DKIOCCHECKINSERT - Check for disk insertion
		// Poll for media
		[drive pollMedia];
		break;

	case 0x20006414:  // DKIOCGLABEL - Get label (not supported)
		result = EINVAL;
		break;

	case 0x80606401:  // DKIOCSLABEL - Set label (not supported)
		result = EINVAL;
		break;

	case 0x40046603:  // Get last ready state
		*data = [deviceInfo lastReadyState];
		break;

	default:
		return EINVAL;  // 0x16 = 22
	}

	// Convert error code
	if (result == 0) {
		return 0;
	}

	if (deviceInfo == nil) {
		return 0xffffffff;
	}

	return [deviceInfo errnoFromReturn:result];
}

/*
 * _HandleBsdOpen - BSD open handler
 * From decompiled code: handles open operations from BSD layer.
 *
 * This function is called when a user process opens a floppy device node.
 * It validates the device, polls for media if needed, and sets the open flag.
 *
 * Parameters:
 *   dev - BSD device number
 *
 * Returns:
 *   0 on success, ENXIO (6) on error
 */
static int _HandleBsdOpen(dev_t dev)
{
	id drive;
	id disk;
	void *partition;
	unsigned int identifyResult;
	BOOL mediaPresent;
	unsigned char *partFlags;

	// Identify the BSD device
	identifyResult = _identifyBsdDev(dev, &drive, &disk, &partition);

	// Check if device is invalid or result > 2
	if ((identifyResult == 0) || (identifyResult > 2)) {
		return ENXIO;  // No such device (6)
	}

	// If no disk object, try polling for media
	if (disk == nil) {
		mediaPresent = [drive pollMedia];
		if (!mediaPresent) {
			return ENXIO;  // No media
		}

		// Re-identify after polling (disk may now be available)
		_identifyBsdDev(dev, &drive, &disk, &partition);
	}

	// If result is 2 (normal case), set the open flag
	if (identifyResult == 2) {
		partFlags = (unsigned char *)partition;

		// Check partition flags bit 0 to determine device type
		if ((partFlags != NULL) && ((*partFlags & 1) == 0)) {
			// Raw device - set raw open flag
			[disk setRawDeviceOpen:YES];
		} else {
			// Block device - set block open flag
			[disk setBlockDeviceOpen:YES];
		}
	}

	return 0;  // Success
}

/*
 * _HandleBsdClose - BSD close handler
 * From decompiled code: handles close operations from BSD layer.
 *
 * This function is called when a user process closes a floppy device node.
 * It clears the open flag on the disk object.
 *
 * Parameters:
 *   dev - BSD device number
 *
 * Returns:
 *   0 on success, ENXIO (6) on error
 */
static int _HandleBsdClose(dev_t dev)
{
	id drive;
	id disk;
	void *partition;
	unsigned int identifyResult;
	unsigned char *partFlags;

	// Identify the BSD device
	identifyResult = _identifyBsdDev(dev, &drive, &disk, &partition);

	// Special case: if result is 1, just return success
	if (identifyResult == 1) {
		return 0;
	}

	// Check for invalid device or wrong result code
	if ((identifyResult == 0) || (identifyResult != 2)) {
		return ENXIO;  // No such device (6)
	}

	// If no disk object, try to get detached disk
	if (disk == nil) {
		disk = _identifyDetachedDiskIdFromBsdDev(dev);
	}

	// If we have a disk object, clear the open flag
	if (disk != nil) {
		partFlags = (unsigned char *)partition;

		// Check partition flags bit 0 to determine device type
		if ((partFlags != NULL) && ((*partFlags & 1) == 0)) {
			// Raw device - clear raw open flag
			[disk setRawDeviceOpen:NO];
		} else {
			// Block device - clear block open flag
			[disk setBlockDeviceOpen:NO];
		}
	}

	return 0;  // Success
}

/*
 * fdminphys - Limit transfer size for floppy I/O
 * From decompiled code: returns the buffer's byte count field.
 *
 * This function is used as the minphys callback for physio operations.
 * It returns the transfer size from the buffer structure, effectively
 * setting the maximum transfer size per I/O operation.
 *
 * Parameters:
 *   bp - Buffer structure pointer (struct buf *)
 *
 * Returns:
 *   Transfer size in bytes (from b_bcount field at offset 0x30)
 *
 * Note: The b_bcount field is at offset 0x30 in the buf structure.
 */
static u_int fdminphys(struct buf *bp)
{
	// Return the byte count from the buffer structure
	// b_bcount is at offset 0x30 in struct buf
	return bp->b_bcount;
}

/*
 * _identifyBsdDev - Identify BSD device components from dev_t
 * From decompiled code: extracts drive, disk, and partition from device number.
 *
 * This function decodes a BSD device number (dev_t) into its component parts:
 * the drive object, disk object, and partition information.
 *
 * Parameters:
 *   dev        - BSD device number (dev_t)
 *   driveOut   - Output pointer for drive object
 *   diskOut    - Output pointer for disk object
 *   partOut    - Output pointer for partition info flags
 *
 * Returns:
 *   0 = Invalid device
 *   1 = Valid drive, but disk not attached or wrong major
 *   2 = Valid drive and disk attached
 *
 * Device number format:
 *   dev & 0xFF = minor number
 *   minor >> 3 = drive number (0-7)
 *   minor & 7 = partition (0 or 1)
 *   dev >> 8 = major number
 */
static unsigned int _identifyBsdDev(dev_t dev,
                                     id *driveOut,
                                     id *diskOut,
                                     void **partOut)
{
	unsigned int driveNumber;
	unsigned int partition;
	unsigned char major;
	unsigned char *flagsPtr;
	id drive;
	id disk;
	unsigned char expectedMajor;
	unsigned char *partFlags;

	// Extract drive number from minor number (bits 3-7)
	driveNumber = ((dev & 0xFF) >> 3);

	// Extract partition from minor number (bits 0-2, but only 0-1 are valid)
	partition = dev & 7;

	// Initialize outputs to NULL/0
	*partOut = NULL;
	*diskOut = NULL;
	*driveOut = NULL;

	// Validate: drive number must be 0-7, partition must be 0-1
	if ((driveNumber >= 8) || (partition >= 2)) {
		return 0;
	}

	// Get flags pointer for this drive
	flagsPtr = (unsigned char *)(0xc000 + (driveNumber * 0x34));

	// Check if drive is registered (bit 0)
	if ((*flagsPtr & 0x01) == 0) {
		return 0;  // Drive not registered
	}

	// Get drive object pointer at offset 0x04
	drive = *(id *)(0xc004 + (driveNumber * 0x34));
	*driveOut = drive;

	// Extract major number from device
	major = (unsigned char)(dev >> 8);

	// Get expected major number from offset 0x2d in drive table entry
	expectedMajor = *(unsigned char *)(0xc02d + (driveNumber * 0x34));

	// Check if major number matches (set bit 0 in partition flags if it does)
	if (expectedMajor == major) {
		// Allocate partition flags if needed
		if (*partOut == NULL) {
			*partOut = (void *)IOMalloc(1);
		}
		partFlags = (unsigned char *)*partOut;
		*partFlags |= 1;  // Set bit 0 to indicate major match
	}

	// Handle partition 1 specially
	if (partition != 1) {
		// Partition 0 or other - check if disk is attached (bit 2)
		if ((*flagsPtr & 0x02) != 0) {
			// Get disk object from table at offset 0x0c/0x10
			*diskOut = *(id *)(0xc00c + (partition * 4) + (driveNumber * 0x34));
		}
		return 2;  // Valid drive with disk
	}

	// Partition 1 - only valid if major doesn't match
	if (expectedMajor != major) {
		// Check if disk is attached (bit 2)
		if ((*flagsPtr & 0x02) != 0) {
			// Get disk object from offset 0x08
			*diskOut = *(id *)(0xc008 + (driveNumber * 0x34));
		}
		return 1;  // Valid but special case
	}

	return 0;  // Invalid combination
}

/*
 * _identifyDetachedDiskIdFromBsdDev - Get disk object from detached device
 * From decompiled code: retrieves disk object for a detached BSD device.
 *
 * This function is used to get the disk object for a device that has been
 * detached from the BSD interface. It's similar to _identifyBsdDev but only
 * returns the disk object and only works when the disk is NOT currently
 * attached (bit 2 is clear).
 *
 * Parameters:
 *   dev - BSD device number
 *
 * Returns:
 *   Disk object pointer, or NULL if invalid/attached
 *
 * Device number format:
 *   dev & 0xFF = minor number
 *   minor >> 3 = drive number (0-7)
 *   minor & 7 = partition (0 or 1)
 *   dev >> 8 = major number
 */
static id _identifyDetachedDiskIdFromBsdDev(dev_t dev)
{
	unsigned int driveNumber;
	unsigned int partition;
	unsigned char *flagsPtr;
	unsigned char expectedMajor;
	unsigned char actualMajor;
	id disk;

	// Extract drive number from minor number (bits 3-7)
	driveNumber = ((dev & 0xFF) >> 3);

	// Extract partition from minor number (bits 0-2)
	partition = dev & 7;

	// Validate: drive number must be 0-7, partition must be 0-1
	if ((driveNumber >= 8) || (partition >= 2)) {
		return NULL;
	}

	// Get flags pointer for this drive
	flagsPtr = (unsigned char *)(0xc000 + (driveNumber * 0x34));

	// Check if drive is registered (bit 0)
	if ((*flagsPtr & 0x01) == 0) {
		return NULL;  // Drive not registered
	}

	// Handle partition 1 specially
	if (partition == 1) {
		// Get expected major number from offset 0x2d
		expectedMajor = *(unsigned char *)(0xc02d + (driveNumber * 0x34));

		// Get actual major number from device
		actualMajor = (unsigned char)(dev >> 8);

		// If major numbers match, return NULL (this partition not valid)
		if (expectedMajor == actualMajor) {
			return NULL;
		}

		// Get disk object from offset 0x08
		disk = *(id *)(0xc008 + (driveNumber * 0x34));
	} else {
		// Partition 0 - get disk object from table at offset 0x0c
		disk = *(id *)(0xc00c + (partition * 4) + (driveNumber * 0x34));
	}

	// Check if disk is currently attached (bit 2)
	// Only return disk if it's NOT attached (detached)
	if ((*flagsPtr & 0x02) == 0) {
		// Disk is detached, return it
		return disk;
	}

	// Disk is attached, return NULL
	return NULL;
}

/*
 * _fakeStrategySuccess - Fake strategy routine that always succeeds
 * From decompiled code: used for handling detaching disks.
 *
 * This function is used as a strategy routine when a disk is being detached.
 * It immediately completes the transfer with success status without performing
 * any actual I/O.
 *
 * Parameters:
 *   bp - Buffer structure pointer (struct buf *)
 *
 * Returns:
 *   0 (success)
 */
static int _fakeStrategySuccess(struct buf *bp)
{
	id drive;
	id disk;
	void *partition;
	int driveNumber;
	id deviceInfo;
	dev_t dev;

	// Get device number from buffer
	dev = bp->b_dev;

	// Identify the BSD device components
	_identifyBsdDev(dev, &drive, &disk, &partition);

	// Get drive number
	driveNumber = [IOFloppyDisk driveNumberOfDrive:drive];

	// Get device info pointer
	deviceInfo = *(id *)(0xc008 + (driveNumber * 0x34));

	// Complete the transfer with success status
	[deviceInfo completeTransfer:bp
	                  withStatus:IO_R_SUCCESS
	                actualLength:bp->b_bcount];

	return 0;
}

/*
 * _HandleBsdSize - BSD partition size handler
 * From decompiled code: returns the size of a disk partition.
 *
 * This function is called by the BSD layer to get the size of a disk partition
 * in blocks. It's used for block device operations.
 *
 * Parameters:
 *   dev - BSD device number
 *
 * Returns:
 *   Number of blocks in partition, or error code (6 = ENXIO, 0 = no disk)
 */
static int _HandleBsdSize(dev_t dev)
{
	id drive;
	id disk;
	void *partition;
	unsigned int identifyResult;
	int blockSize;

	// Identify the BSD device
	identifyResult = _identifyBsdDev(dev, &drive, &disk, &partition);

	// Check for invalid device
	if (identifyResult == 0) {
		return ENXIO;  // 6
	}

	// Valid result must be less than 3
	if (identifyResult < 3) {
		// If we have a disk object, return its block size
		if (disk != NULL) {
			blockSize = [disk blockSize];
			return blockSize;
		}
		return 0;  // No disk
	}

	return ENXIO;  // Invalid result (>= 3)
}

/*
 * _HandleBsdStrategy - BSD strategy handler
 * From decompiled code: handles block I/O requests from BSD layer.
 *
 * This function is the strategy routine for block device I/O. It processes
 * buf structures and initiates async read/write operations on the disk.
 *
 * Parameters:
 *   bp - Buffer structure pointer (struct buf *)
 *
 * Returns:
 *   void (errors reported via completeTransfer)
 */
static void _HandleBsdStrategy(struct buf *bp)
{
	id drive;
	id disk;
	void *partition;
	unsigned int identifyResult;
	int result;
	BOOL isFormatted;
	vm_map_t vmTask;
	unsigned int bufFlags;
	dev_t dev;

	result = -0x2c7;  // ENOTTY

	// Get device number from buffer
	dev = bp->b_dev;

	// Identify the BSD device
	identifyResult = _identifyBsdDev(dev, &drive, &disk, &partition);

	if (identifyResult == 0) {
		result = -0x2c0;  // ENXIO (different encoding)
	} else if (identifyResult < 3) {
		// Valid device
		if (disk == NULL) {
			result = -0x44e;  // No disk present
		} else {
			// Check if disk is formatted
			isFormatted = [disk isFormatted];

			if (isFormatted) {
				// Get VM task for buffer
				vmTask = kernel_map;

				// Check buffer flags at offset 0x24
				bufFlags = *(unsigned int *)((char *)bp + 0x24);

				// If flag 0x4040000 == 0x40000, get task from buffer
				if ((bufFlags & 0x4040000) == 0x40000) {
					vmTask = IOVmTaskForBuf(bp);
				}

				// Check if this is a read or write operation
				// Flag 0x100000 (B_READ) indicates read
				if ((bufFlags & 0x100000) == 0) {
					// Write operation
					result = [disk writeAsyncAt:bp->b_blkno
					                     length:bp->b_bcount
					                     buffer:bp->b_un.b_addr
					                    pending:bp
					                     client:vmTask];
				} else {
					// Read operation
					result = [disk readAsyncAt:bp->b_blkno
					                    length:bp->b_bcount
					                    buffer:bp->b_un.b_addr
					                   pending:bp
					                    client:vmTask];
				}

				// If successful, return without completing (async operation)
				if (result == 0) {
					return;
				}
			} else {
				result = -0x44d;  // Disk not formatted
			}
		}
	}

	// Error path - complete transfer with error status
	[disk completeTransfer:bp withStatus:result actualLength:0];

	// Convert IOReturn to errno (not used, but matches decompiled code)
	[disk errnoFromReturn:result];
}

/*
 * _HandleBsdRead - BSD read handler
 * From decompiled code: handles read operations from BSD layer.
 *
 * This function is called by the BSD layer to perform read operations on
 * floppy disks. It handles both normal reads and reads during disk detachment.
 *
 * Parameters:
 *   dev - BSD device number
 *   uio - User I/O structure
 *
 * Returns:
 *   BSD error code (0 = success, errno on failure)
 */
static int _HandleBsdRead(dev_t dev, struct uio *uio)
{
	id drive;
	id disk;
	void *partition;
	unsigned int identifyResult;
	id deviceInfo;
	int driveNumber;
	int *detachCountPtr;
	int blockSize;
	BOOL isFormatted;
	int result;
	struct buf *deviceBuf;

	// Identify the BSD device
	identifyResult = _identifyBsdDev(dev, &drive, &disk, &partition);

	// Get drive number
	driveNumber = [IOFloppyDisk driveNumberOfDrive:drive];

	// Get device info pointer
	deviceInfo = *(id *)(0xc008 + (driveNumber * 0x34));

	// Check if device has a detach counter at offset 0x168
	if ((deviceInfo != nil) && (*(int *)((char *)deviceInfo + 0x168) != 0)) {
		// Device is detaching - use fake strategy
		detachCountPtr = (int *)((char *)deviceInfo + 0x168);
		(*detachCountPtr)--;

		if (*detachCountPtr == 0) {
			// Last operation - reattach BSD interface
			[deviceInfo attachBsdDiskInterfaceToDrive:drive];
		}

		// Get block size
		blockSize = [deviceInfo blockSize];

		// Get device buffer pointer
		deviceBuf = *(struct buf **)(0xc030 + (driveNumber * 0x34));

		// Perform I/O using fake strategy (always succeeds)
		result = physio((int (*)(struct buf *))_fakeStrategySuccess,
		                deviceBuf,
		                dev,
		                0x100000,  // B_READ flag
		                (u_int (*)(struct buf *))fdminphys,
		                uio,
		                blockSize);

		return result;
	}

	// Normal path - check for errors
	if ((identifyResult == 0) || (identifyResult > 2) || (disk == nil)) {
		return ENXIO;  // No such device or address (6)
	}

	// Check if disk is formatted
	isFormatted = [disk isFormatted];
	if (!isFormatted) {
		return ENXIO;  // Device not formatted (0x16 = 22 = EINVAL in some contexts)
	}

	// Get block size from disk
	blockSize = [disk blockSize];

	// Get device buffer pointer
	deviceBuf = *(struct buf **)(0xc030 + (driveNumber * 0x34));

	// Perform I/O using real strategy
	result = physio((int (*)(struct buf *))_HandleBsdStrategy,
	                deviceBuf,
	                dev,
	                0x100000,  // B_READ flag
	                (u_int (*)(struct buf *))fdminphys,
	                uio,
	                blockSize);

	return result;
}

/*
 * _HandleBsdWrite - BSD write handler
 * From decompiled code: handles write operations from BSD layer.
 *
 * This function is called by the BSD layer to perform write operations on
 * floppy disks. It validates the device, checks if the disk is formatted,
 * and uses physio to perform the actual write.
 *
 * Parameters:
 *   dev - BSD device number
 *   uio - User I/O structure
 *
 * Returns:
 *   BSD error code (0 = success, errno on failure)
 */
static int _HandleBsdWrite(dev_t dev, struct uio *uio)
{
	id drive;
	id disk;
	void *partition;
	unsigned int identifyResult;
	BOOL isFormatted;
	int blockSize;
	int driveNumber;
	struct buf *deviceBuf;
	int result;

	// Identify the BSD device
	identifyResult = _identifyBsdDev(dev, &drive, &disk, &partition);

	// Check for errors
	if ((identifyResult == 0) || (identifyResult > 2) || (disk == NULL)) {
		return ENXIO;  // 6 - No such device or address
	}

	// Check if disk is formatted
	isFormatted = [disk isFormatted];
	if (!isFormatted) {
		return EINVAL;  // 0x16 = 22 - Invalid argument (disk not formatted)
	}

	// Get block size from disk
	blockSize = [disk blockSize];

	// Get drive number
	driveNumber = [IOFloppyDisk driveNumberOfDrive:drive];

	// Get device buffer pointer from global table
	deviceBuf = *(struct buf **)(0xc030 + (driveNumber * 0x34));

	// Perform I/O using strategy routine
	// Flag 0 = write (no B_READ flag)
	result = physio((int (*)(struct buf *))_HandleBsdStrategy,
	                deviceBuf,
	                dev,
	                0,  // 0 = write (no B_READ flag)
	                (u_int (*)(struct buf *))fdminphys,
	                uio,
	                blockSize);

	return result;
}

@implementation IOFloppyDisk(Bsd)

/*
 * Class method: Get block device number for a drive.
 * From decompiled code: returns the block device major/minor number.
 *
 * This method calculates the block device number (dev_t) for a floppy drive
 * by combining the major number (1) with a minor number based on drive number.
 *
 * Parameters:
 *   drive - Drive object
 *
 * Returns:
 *   Block device number (dev_t) combining major and minor numbers,
 *   or 0 if drive number is invalid
 *
 * Device number format:
 *   - Major number: 1 (block device major for floppy)
 *   - Minor number: driveNumber * 8
 *   - Combined: 0x100 | (driveNumber * 8)
 *   - Example: drive 0 = 0x100, drive 1 = 0x108, etc.
 */
+ (unsigned int)_blockDevOfDrive:(id)drive
{
	int driveNumber;

	// Get drive number from drive object using class method
	driveNumber = [[self class] _driveNumberOfDrive:drive];

	// If drive number is invalid (-1), return 0
	if (driveNumber == -1) {
		return 0;
	}

	// Calculate device number: major (1) in upper bits, minor = driveNumber * 8
	// 0x100 = major number 1 shifted left 8 bits
	// driveNumber << 3 = driveNumber * 8 (minor number)
	return (driveNumber << 3) | 0x100;
}

/*
 * Class method: Get character device number for a drive.
 * From decompiled code: returns the character device major/minor number.
 *
 * This method calculates the character (raw) device number (dev_t) for a
 * floppy drive by combining the major number (41 = 0x29) with a minor
 * number based on drive number.
 *
 * Parameters:
 *   drive - Drive object
 *
 * Returns:
 *   Character device number (dev_t) combining major and minor numbers,
 *   or 0 if drive number is invalid
 *
 * Device number format:
 *   - Major number: 41 (0x29) (character device major for floppy)
 *   - Minor number: driveNumber * 8
 *   - Combined: 0x2900 | (driveNumber * 8)
 *   - Example: drive 0 = 0x2900, drive 1 = 0x2908, etc.
 */
+ (unsigned int)_characterDevOfDrive:(id)drive
{
	int driveNumber;

	// Get drive number from drive object using class method
	driveNumber = [[self class] _driveNumberOfDrive:drive];

	// If drive number is invalid (-1), return 0
	if (driveNumber == -1) {
		return 0;
	}

	// Calculate device number: major (41 = 0x29) in upper bits, minor = driveNumber * 8
	// 0x2900 = major number 41 shifted left 8 bits
	// driveNumber << 3 = driveNumber * 8 (minor number)
	return (driveNumber << 3) | 0x2900;
}

/*
 * Class method: Get drive number from drive object.
 * From decompiled code: extracts drive number from drive object.
 *
 * This method searches through the global drive table to find the drive
 * object and returns its index (drive number). The table supports up to
 * 8 drives (0-7).
 *
 * Parameters:
 *   drive - Drive object to search for
 *
 * Returns:
 *   Drive number (0-7) or 0xffffffff (-1) if not found
 *
 * Global table structure:
 *   - Base address: 0xc000
 *   - Entry size: 0x34 bytes (52 bytes)
 *   - Offset 0x00: Flags byte (bit 0 = drive registered)
 *   - Offset 0x04: Drive object pointer
 *   - Up to 8 entries (indices 0-7)
 */
+ (unsigned int)_driveNumberOfDrive:(id)drive
{
	unsigned int driveIndex;
	unsigned char *flagsPtr;
	id *driveObjectPtr;

	driveIndex = 0;

	// Search through the global drive table
	while (1) {
		// Calculate pointer to flags byte for this entry
		// Base 0xc000 + (driveIndex * 0x34) + offset 0
		flagsPtr = (unsigned char *)(0xc000 + (driveIndex * 0x34));

		// Calculate pointer to drive object pointer for this entry
		// Base 0xc000 + (driveIndex * 0x34) + offset 4
		// offset 0x04 = 4 bytes into entry = (&DAT_0000c004)[driveIndex * 0xd]
		// Note: 0xd * 4 = 0x34 (each entry is 0x34 bytes)
		driveObjectPtr = (id *)(0xc004 + (driveIndex * 0x34));

		// Check if this entry is valid (bit 0 set) AND matches the drive object
		if (((*flagsPtr & 0x01) != 0) && (*driveObjectPtr == drive)) {
			// Found matching drive
			return driveIndex;
		}

		// Move to next entry
		driveIndex++;

		// Check if we've searched all 8 possible entries
		if (driveIndex > 7) {
			// Drive not found
			return 0xffffffff;  // -1
		}
	}
}

/*
 * Class method: Register a drive with the BSD device system.
 * From decompiled code: creates BSD device nodes for a drive.
 *
 * This method registers the drive with the BSD device layer. On the first
 * registration, it adds the floppy driver to the cdevsw and bdevsw tables.
 * It allocates a device info structure and marks the drive as registered.
 *
 * Parameters:
 *   drive - Drive object to register
 *
 * Returns:
 *   1 (true) on success, 0 (false) on failure
 *
 * Global table structure:
 *   - Base: 0xc000 (flags and state)
 *   - Base: 0xc004 (drive object pointers)
 *   - Base: 0xc030 (device info structure pointers)
 *   - Entry size: 0x34 bytes (0xd dwords)
 *
 * External functions referenced:
 *   - HandleBsdOpen (0x448)
 *   - HandleBsdClose (0x4e4)
 *   - HandleBsdRead/Write (0x5ec, 0x7f8)
 *   - HandleBsdIoctl (0x74c)
 *   - HandleBsdStrategy (0x908)
 *   - HandleBsdSize (function pointer)
 */
+ (IOReturn)_registerDrive:(id)drive
{
	extern int DrivesRegistered;  // Global counter of registered drives
	extern int enodev, nulldev, seltrue;

	unsigned int driveIndex;
	unsigned char *flagsPtr;
	id *driveObjectPtr;
	void **devInfoPtr;
	void *allocatedDevInfo;
	int result;

	// Find first available slot in drive table
	driveIndex = 0;
	while (1) {
		flagsPtr = (unsigned char *)(0xc000 + (driveIndex * 0x34));

		// Check if slot is available (bit 0 clear)
		if ((*flagsPtr & 0x01) == 0) {
			break;
		}

		// Move to next slot
		driveIndex++;

		// Check if all 8 slots are full
		if (driveIndex > 7) {
			return 0;  // No available slots
		}
	}

	// Allocate device info structure (0x80 = 128 bytes)
	allocatedDevInfo = (void *)IOMalloc(0x80);

	// Store device info pointer at offset 0x30 (base 0xc030)
	devInfoPtr = (void **)(0xc030 + (driveIndex * 0x34));
	*devInfoPtr = allocatedDevInfo;

	if (allocatedDevInfo == NULL) {
		return 0;  // Allocation failed
	}

	// Initialize field at offset 0x24 in device info structure
	*(unsigned int *)((char *)allocatedDevInfo + 0x24) = 0;

	// If this is the first drive being registered, add to devsw tables
	if (DrivesRegistered == 0) {
		// Add to character device switch table (major 41 = 0x29)
		result = IOAddToCdevswAt(
			0x29,                     // Major number 41 (character device)
			(int)&_HandleBsdOpen,     // d_open at 0x448
			(int)&_HandleBsdClose,    // d_close at 0x4e4
			(int)&_HandleBsdRead,     // d_read at 0x5ec
			(int)&_HandleBsdWrite,    // d_write at 0x74c
			(int)&_HandleBsdIoctl,    // d_ioctl at 0x908
			(int)&enodev,             // d_stop
			(int)&nulldev,            // d_reset
			(int)&seltrue,            // d_select
			(int)&enodev,             // d_mmap
			(int)&enodev,             // d_getc
			(int)&enodev              // d_putc
		);

		if (result == -1) {
			// Failed to add to cdevsw, cleanup and fail
			IOFree(allocatedDevInfo, 0x80);
			*devInfoPtr = NULL;
			return 0;
		}

		// Add to block device switch table (major 1)
		result = IOAddToBdevswAt(
			1,                         // Major number 1 (block device)
			(int)&_HandleBsdOpen,      // d_open at 0x448
			(int)&_HandleBsdClose,     // d_close at 0x4e4
			(int)&_HandleBsdStrategy,  // d_strategy at 0x7f8
			(int)&_HandleBsdIoctl,     // d_ioctl at 0x908
			(int)&enodev,              // d_dump
			(int)&_HandleBsdSize,      // d_psize
			0                          // d_flags
		);

		if (result == -1) {
			// Failed to add to bdevsw, cleanup and fail
			IORemoveFromCdevsw(0x29);
			IOFree(allocatedDevInfo, 0x80);
			*devInfoPtr = NULL;
			return 0;
		}

		// Store major numbers in class
		[self setBlockMajor:1];
		[self setCharacterMajor:0x29];

		// Increment registered drives counter
		DrivesRegistered++;
	}

	// Store drive object pointer at offset 0x04 (base 0xc004)
	driveObjectPtr = (id *)(0xc004 + (driveIndex * 0x34));
	*driveObjectPtr = drive;

	// Set bit 0 in flags to mark as registered
	flagsPtr = (unsigned char *)(0xc000 + (driveIndex * 0x34));
	*flagsPtr |= 0x01;

	return 1;  // Success
}

/*
 * Class method: Unregister a drive from the BSD device system.
 * From decompiled code: removes BSD device nodes for a drive.
 *
 * This method unregisters the drive from the BSD device layer. It frees
 * the device info structure, clears the drive table entry, and decrements
 * the registered drives counter. If this is the last drive, it removes
 * the floppy driver from the cdevsw and bdevsw tables.
 *
 * Parameters:
 *   drive - Drive object to unregister
 *
 * Returns:
 *   IO_R_SUCCESS (void in decompiled code)
 *
 * Global table structure:
 *   - Base: 0xc000 (flags and state) - cleared (0x34 bytes)
 *   - Base: 0xc030 (device info structure pointers) - freed
 */
+ (IOReturn)_unregisterDrive:(id)drive
{
	extern int DrivesRegistered;  // Global counter of registered drives

	int driveNumber;
	void **devInfoPtr;
	void *deviceInfo;

	// Get drive number from drive object
	driveNumber = [self _driveNumberOfDrive:drive];

	// If drive not found, nothing to do
	if (driveNumber == -1) {
		return IO_R_SUCCESS;
	}

	// Get device info pointer at offset 0x30 (base 0xc030)
	devInfoPtr = (void **)(0xc030 + (driveNumber * 0x34));
	deviceInfo = *devInfoPtr;

	// Free device info structure (0x80 = 128 bytes)
	IOFree(deviceInfo, 0x80);

	// Clear entire drive table entry (0x34 bytes starting at 0xc000)
	bzero((void *)(0xc000 + (driveNumber * 0x34)), 0x34);

	// Decrement registered drives counter
	DrivesRegistered--;

	// If no more drives are registered, remove from devsw tables
	if (DrivesRegistered == 0) {
		// Remove from block device switch table (major 1)
		IORemoveFromBdevsw(1);

		// Remove from character device switch table (major 41 = 0x29)
		IORemoveFromCdevsw(0x29);
	}

	return IO_R_SUCCESS;
}

@end

@implementation IOFloppyDisk(BsdLocal)

/*
 * Attach BSD disk interface to a drive.
 * From decompiled code: creates BSD device nodes (block and character devices).
 */
- (IOReturn)_attachBsdDiskInterfaceToDrive:(id)drive
{
	int driveNumber;
	int devInfoOffset;
	BOOL hasDevInfo;
	char *devInfoPtr;
	void *sourceDevInfo;
	int blockDevMajor;
	int charDevMajor;
	int blockDevMinor;
	int charDevMinor;
	unsigned char *flagsPtr;
	
	// Get drive number
	driveNumber = [[self class] driveNumberOfDrive:drive];
	
	// If invalid drive number, fail
	if (driveNumber == -1) {
		return IO_R_INVALID_ARG;
	}
	
	// Calculate offset into device info table (each entry is 0x34 bytes)
	devInfoOffset = driveNumber * 0x34;
	
	// Get pointer to device info structure (global table at 0xc008)
	devInfoPtr = (char *)0xc008 + devInfoOffset;
	
	// Check if device info already exists
	hasDevInfo = [drive _hasDevInfo];
	
	if (!hasDevInfo) {
		// Clear device info area (0x28 bytes starting at offset 0xc008)
		bzero(devInfoPtr, 0x28);
		
		// Get block device major number from class
		blockDevMajor = [[self class] blockMajor];
		
		// Calculate and store block device major/minor at offset 0xc028
		blockDevMinor = driveNumber * 8;
		*(int *)((char *)0xc028 + devInfoOffset) = (blockDevMajor << 8) | blockDevMinor;
		
		// Get character device major number from class  
		charDevMajor = [[self class] characterMajor];
		
		// Calculate and store char device major/minor at offset 0xc02c
		charDevMinor = driveNumber * 8;
		*(int *)((char *)0xc02c + devInfoOffset) = (charDevMajor << 8) | charDevMinor;
	} else {
		// Device info already exists, get existing info
		sourceDevInfo = [self _getDevInfo];
		
		// Check if it's not already the same pointer
		if (sourceDevInfo != devInfoPtr) {
			// Copy existing device info (0x28 bytes)
			bcopy(sourceDevInfo, devInfoPtr, 0x28);
		}
	}
	
	// Set device and ID info on the drive
	[self setDevAndIdInfo:devInfoPtr];
	
	// Set bit 2 in flags byte at offset 0xc000 (marks as attached)
	flagsPtr = (unsigned char *)((char *)0xc000 + devInfoOffset);
	*flagsPtr |= 2;
	
	return IO_R_SUCCESS;
}

/*
 * Detach BSD disk interface from a drive.
 * From decompiled code: removes BSD device nodes.
 */
- (IOReturn)_detachBsdDiskInterfaceFromDrive:(id)drive
{
	int driveNumber;
	unsigned char *flagsPtr;
	
	// Get drive number
	driveNumber = [[self class] driveNumberOfDrive:drive];
	
	// If invalid drive number, nothing to do
	if (driveNumber == -1) {
		return IO_R_SUCCESS;
	}
	
	// Clear bit 2 in flags byte at offset 0xc000 (marks as detached)
	flagsPtr = (unsigned char *)((char *)0xc000 + driveNumber * 0x34);
	*flagsPtr &= 0xfd;  // Clear bit 2 (0xfd = ~0x02)
	
	return IO_R_SUCCESS;
}

@end

/* End of Bsd.m */
