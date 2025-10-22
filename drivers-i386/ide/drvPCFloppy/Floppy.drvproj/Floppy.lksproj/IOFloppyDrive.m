/*
 * IOFloppyDrive.m - Main IOFloppyDrive class implementation
 *
 * Floppy disk drive class for PC floppy controller
 */

#import "IOFloppyDrive.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IOFloppyDrive

/*
 * Class method: Get device style.
 * From decompiled code: returns device style constant.
 *
 * This method indicates that floppy drives are removable media devices.
 *
 * Returns:
 *   2 - Indicates removable media device style
 */
+ (int)deviceStyle
{
	return 2;
}

/*
 * Class method: Probe for devices.
 * From decompiled code: probing is not used for floppy drives.
 *
 * Floppy drives are not probed automatically. Instead, they are
 * instantiated by the FloppyController during initialization.
 *
 * Parameters:
 *   deviceDescription - Device description to probe (unused)
 *
 * Returns:
 *   0 (false) - Probing not supported/used
 */
+ (BOOL)probe:(id)deviceDescription
{
	return 0;
}

/*
 * Check if media can be polled inexpensively.
 * From decompiled code: returns NO (floppy drives cannot poll inexpensively).
 */
- (BOOL)canPollInexpensively
{
	// Floppy drives do not support inexpensive polling
	// They require explicit status commands or motor spin-up to detect media
	return NO;
}

/*
 * Eject the floppy disk.
 * From decompiled code: calls superclass eject, then internal eject.
 */
- (IOReturn)ejectMedia
{
	// Call superclass ejectMedia
	[super ejectMedia];
	
	// Perform internal eject operations
	// - Seeks to track 79 to unload heads
	// - Turns off motor
	[self _fdEjectInt];
	
	return IO_R_SUCCESS;
}

/*
 * Get list of supported format capacities.
 * From decompiled code: returns 0x120 (same as read/write).
 */
- (IOReturn)formatCapacities
{
	// Return capacity bitmap or count
	// 0x120 = 288 decimal (same as read/write)
	return 0x120;
}

/*
 * Format a specific cylinder.
 * From decompiled code: formats all tracks in cylinder, then verifies.
 */
- (IOReturn)formatCylinder:(unsigned)cylinder
                      data:(void *)data
{
	IOReturn result;
	unsigned head;
	unsigned startingBlock;
	unsigned blocksPerCylinder;
	unsigned actualLength;
	unsigned numHeads;
	unsigned sectorsPerTrack;
	
	result = IO_R_SUCCESS;
	sectorsPerTrack = _sectorsPerTrack;  // offset 0x1a4
	numHeads = _density;                 // offset 0x180
	
	// If this is cylinder 0, recalibrate first
	if (cylinder == 0) {
		result = [self _fdRecal];
		if (result != IO_R_SUCCESS) {
			return result;
		}
	}
	
	// Format each track (head) in the cylinder
	for (head = 0; head < numHeads; head++) {
		result = [self _fdFormatTrack:cylinder head:head];
		if (result != IO_R_SUCCESS) {
			return result;  // Format failed
		}
	}
	
	// Verify the format by reading the cylinder
	if (result == IO_R_SUCCESS) {
		// Calculate starting block
		startingBlock = cylinder * sectorsPerTrack * numHeads;
		
		// Calculate blocks per cylinder
		blocksPerCylinder = numHeads * sectorsPerTrack;
		
		// Read to verify format
		result = [self _fdRwCommon:YES  // isRead = YES
				    block:startingBlock
				 blockCnt:blocksPerCylinder
				   buffer:data
				   client:kernel_map
			     actualLength:&actualLength];
	}
	
	return result;
}

/*
 * Free the drive object and resources.
 * From decompiled code: unregisters and frees buffers.
 */
- free
{
	// If bit 2 is set, unregister from volume check
	if ((_regFlags & 2) != 0) {
		[self _unregisterVolCheck];
	}
	
	// If bit 1 is set, unregister drive from IOFloppyDisk
	if ((_regFlags & 1) != 0) {
		[IOFloppyDisk unregisterDrive:self];
	}
	
	// Free bounce buffer if allocated
	if (_bounceBuffer != NULL) {
		IOFree(_bounceBufferAllocAddr, _bounceBufferAllocSize);
	}
	
	// Call superclass free
	return [super free];
}

/*
 * Initialize drive from device description.
 * From decompiled code: initializes drive with default parameters and registers.
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
                 controller:(id)controller
                       unit:(unsigned)unit
{
	BOOL registered;
	int driveNumber;
	char name[20];
	IOReturn result;
	
	// Store device description, controller, and unit
	_deviceDescription = deviceDescription;    // offset 0x160
	_fdController = controller;                // offset 0x164
	_unit = unit;                              // offset 0x168
	
	// Initialize disk object pointer
	_nextLogicalDisk = nil;                    // offset 0x108
	
	// Set default parameters (720KB DD settings)
	_fdcNumber = 1;                            // offset 400
	_totalBytes = 0xb4000;                     // offset 0x194 (737,280 bytes)
	_writePrecomp = 1;                         // offset 0x198
	_sectorSize = 0x200;                       // offset 0x19c (512 bytes)
	_sectorSizeCode = 2;                       // offset 0x1a0
	_sectorsPerTrack = 9;                      // offset 0x1a4
	_readWriteGapLength = 0x1b;                // offset 0x1a8
	_formatGapLength = 0x54;                   // offset 0x1a9 (packed with 0x1a8)
	_numBlocks = 0;                            // offset 0x1ac
	_flags = 0;                                // offset 0x18c
	
	// Clear motor timer active flag
	_motorTimerActive = _motorTimerActive & 0xfe;  // offset 0x178
	
	// Allocate bounce buffer (1024 bytes = 0x400)
	vm_address_t allocAddr;
	unsigned allocSize;
	_bounceBuffer = (void *)floppyMalloc(0x400, &allocAddr, &allocSize);
	
	if (_bounceBuffer == NULL) {
		// Allocation failed
		return [self free];
	}
	
	// Store allocation info for later freeing
	_bounceBufferAllocAddr = allocAddr;
	_bounceBufferAllocSize = allocSize;
	
	// Register drive with IOFloppyDisk class
	registered = [IOFloppyDisk registerDrive:self];
	
	// Store registration status in bit 0 of _regFlags
	_regFlags = _regFlags & 0xfe;  // Clear bit 0
	_regFlags = _regFlags | (registered & 1);  // Set bit 0 if registered
	
	if (!registered) {
		// Registration failed
		return [self free];
	}
	
	// Get drive number and set up name
	driveNumber = [IOFloppyDisk driveNumberOfDrive:self];
	sprintf(name, "fd%d", driveNumber);
	
	// Set up drive properties
	[self setUnit:driveNumber];
	[self setName:name];
	[self setDeviceKind:"Floppy Drive"];
	[self setDriveName:"Floppy Drive"];
	
	// Set initial ready state to 1 (not ready)
	[self setLastReadyState:1];
	
	// Register for volume check notifications
	[self _registerVolCheck];
	
	// Set bit 2 of _regFlags (volCheck registered flag)
	_regFlags = _regFlags | 2;
	
	// Register the device with the system
	result = [self registerDevice];
	
	if (result != IO_R_SUCCESS) {
		// Registration failed
		return [self free];
	}
	
	// Success
	return self;
}

/*
 * Poll for media presence/change.
 * From decompiled code: updates ready state and allocates disk if needed.
 */
- (BOOL)pollMedia
{
	IOReturn result;
	BOOL allocated;
	
	// Update ready state
	result = [self _updateReadyStateInt];
	
	// If ready and no disk object allocated yet
	if ((result == 0) && (_nextLogicalDisk == nil)) {
		// Update physical parameters (probe geometry)
		result = [self _updatePhysicalParametersInt];
		
		if (result == 0) {
			// Set ready state to 0 (ready)
			[self setLastReadyState:0];
			
			// Allocate disk object
			allocated = [self _allocateDisk];
			
			if (allocated) {
				return YES;  // Media present and disk allocated
			}
		}
	}
	
	return NO;  // No media or error
}

/*
 * Get list of supported read capacities.
 * From decompiled code: returns 0x120.
 */
- (IOReturn)readCapacities
{
	// Return capacity bitmap or count
	// 0x120 = 288 decimal
	return 0x120;
}

/*
 * Read a specific cylinder.
 * From decompiled code: reads all sectors in cylinder using _fdRwCommon.
 */
- (IOReturn)readCylinder:(unsigned)cylinder
                    data:(void *)data
{
	IOReturn result;
	unsigned startingBlock;
	unsigned blocksPerCylinder;
	unsigned actualLength;
	
	// Calculate starting block for this cylinder
	// startBlock = cylinder * sectorsPerTrack * numHeads
	startingBlock = cylinder * _sectorsPerTrack * _density;
	
	// Calculate blocks per cylinder (sectorsPerTrack * numHeads)
	blocksPerCylinder = _density * _sectorsPerTrack;
	
	// Read the entire cylinder
	result = [self _fdRwCommon:YES  // isRead = YES
			    block:startingBlock
			 blockCnt:blocksPerCylinder
			   buffer:data
			   client:kernel_map
		     actualLength:&actualLength];
	
	return result;
}

/*
 * Set the media capacity.
 * From decompiled code: sets geometry parameters based on capacity type.
 */
- (IOReturn)setMediaCapacity:(unsigned)capacity
{
	// Set parameters based on capacity type
	if (capacity == 0x100) {
		// 1.44MB (HD) floppy
		_diskType = 2;              // offset 0x17c
		_density = 2;               // offset 0x180 (2 heads)
		_numCyls = 0x50;            // offset 0x184 (80 cylinders)
		_numHeads = 2;              // offset 0x188
		_fdcNumber = 2;             // offset 400 (HD density)
		_totalBytes = 0x168000;     // offset 0x194 (1,474,560 bytes)
		_writePrecomp = 1;          // offset 0x198
		_sectorSize = 0x200;        // offset 0x19c (512 bytes)
		_sectorSizeCode = 2;        // offset 0x1a0 (N=2 for 512 bytes)
		_sectorsPerTrack = 0x12;    // offset 0x1a4 (18 sectors)
		_readWriteGapLength = 0x1b; // offset 0x1a8
		_formatGapLength = 0x65;    // offset 0x1a9
	} else if (capacity == 0x20) {
		// 720KB (DD in HD drive) floppy
		_diskType = 3;              // offset 0x17c
		_density = 2;               // offset 0x180 (2 heads)
		_numCyls = 0x50;            // offset 0x184 (80 cylinders)
		_numHeads = 1;              // offset 0x188
		_fdcNumber = 1;             // offset 400 (DD density)
		_totalBytes = 0xb4000;      // offset 0x194 (737,280 bytes)
		_writePrecomp = 1;          // offset 0x198
		_sectorSize = 0x200;        // offset 0x19c (512 bytes)
		_sectorSizeCode = 2;        // offset 0x1a0
		_sectorsPerTrack = 9;       // offset 0x1a4
		_readWriteGapLength = 0x1b; // offset 0x1a8
		_formatGapLength = 0x54;    // offset 0x1a9
	} else if (capacity == 0x800) {
		// 2.88MB (ED) floppy
		_diskType = 1;              // offset 0x17c
		_density = 2;               // offset 0x180 (2 heads)
		_numCyls = 0x50;            // offset 0x184 (80 cylinders)
		_numHeads = 3;              // offset 0x188
		_fdcNumber = 3;             // offset 400 (ED density)
		_totalBytes = 0x2d0000;     // offset 0x194 (2,949,120 bytes)
		_writePrecomp = 1;          // offset 0x198
		_sectorSize = 0x200;        // offset 0x19c (512 bytes)
		_sectorSizeCode = 2;        // offset 0x1a0
		_sectorsPerTrack = 0x24;    // offset 0x1a4 (36 sectors)
		_readWriteGapLength = 0x1b; // offset 0x1a8
		_formatGapLength = 0x53;    // offset 0x1a9
	} else {
		// Unknown capacity
		return NO;
	}
	
	// Calculate total blocks (numHeads * sectorsPerTrack * numCyls)
	_numBlocks = _density * _sectorsPerTrack * _numCyls;  // offset 0x1ac
	
	// Set formatted flag (bit 0)
	_flags = _flags | 1;  // offset 0x18c
	
	return YES;
}

/*
 * Get list of supported write capacities.
 * From decompiled code: returns 0x120 (same as readCapacities).
 */
- (IOReturn)writeCapacities
{
	// Return capacity bitmap or count
	// 0x120 = 288 decimal (same as read)
	return 0x120;
}

/*
 * Write a specific cylinder.
 * From decompiled code: writes all sectors in cylinder using _fdRwCommon.
 */
- (IOReturn)writeCylinder:(unsigned)cylinder
                     data:(void *)data
{
	IOReturn result;
	unsigned startingBlock;
	unsigned blocksPerCylinder;
	unsigned actualLength;
	
	// Calculate starting block for this cylinder
	// startBlock = cylinder * sectorsPerTrack * numHeads
	startingBlock = cylinder * _sectorsPerTrack * _density;
	
	// Calculate blocks per cylinder (sectorsPerTrack * numHeads)
	blocksPerCylinder = _density * _sectorsPerTrack;
	
	// Write the entire cylinder
	result = [self _fdRwCommon:NO   // isRead = NO (write)
			    block:startingBlock
			 blockCnt:blocksPerCylinder
			   buffer:data
			   client:kernel_map
		     actualLength:&actualLength];
	
	return result;
}

@end

/* End of IOFloppyDrive.m */
