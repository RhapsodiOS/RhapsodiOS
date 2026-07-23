/*
 * IOFloppyDrive.h - Main IOFloppyDrive class interface
 *
 * Floppy disk drive class for PC floppy controller
 */

#import <driverkit/IODrive.h>
#import <driverkit/return.h>

@interface IOFloppyDrive : IODrive
{
	// Device and controller information
	IODeviceDescription *_deviceDescription;  // offset 0x160
	id _fdController;                          // offset 0x164
	unsigned _unit;                            // offset 0x168
	unsigned char _regFlags;                   // offset 0x16c (registration/volcheck flags)

	// Motor control
	unsigned char _motorTimerActive;           // offset 0x178

	// Disk type and geometry
	unsigned char _diskType;                   // offset 0x17c
	unsigned char _density;                    // offset 0x180 (number of heads)
	unsigned _numCyls;                         // offset 0x184
	unsigned _numHeads;                        // offset 0x188
	unsigned _flags;                           // offset 0x18c (formatted, write-protected, etc.)

	// Physical parameters
	unsigned _totalBytes;                      // offset 0x194
	unsigned _writePrecomp;                    // offset 0x198
	unsigned _sectorSize;                      // offset 0x19c
	unsigned char _sectorSizeCode;             // offset 0x1a0 (N parameter for FDC)
	unsigned char _sectorsPerTrack;            // offset 0x1a4
	unsigned char _readWriteGapLength;         // offset 0x1a8
	unsigned char _formatGapLength;            // offset 0x1a9
	unsigned _numBlocks;                       // offset 0x1ac

	// Buffers
	void *_bounceBuffer;                       // DMA bounce buffer
	vm_address_t _bounceBufferAllocAddr;       // offset 0x1b4 (allocation address)
	unsigned _bounceBufferAllocSize;           // offset 0x1b8 (allocation size)

	// FDC parameters
	unsigned _fdcNumber;                       // offset 400 (FDC density setting)

	// Disk object
	id _nextLogicalDisk;                       // offset 0x108 (IOFloppyDisk object)
}

/*
 * Class method: Get device style.
 *
 * Returns:
 *   Device style constant (2 = removable media)
 */
+ (int)deviceStyle;

/*
 * Class method: Probe for devices.
 *
 * Parameters:
 *   deviceDescription - Device description to probe
 *
 * Returns:
 *   0 (false) - probing not used for floppy drives
 */
+ (BOOL)probe:(id)deviceDescription;

/*
 * Check if media can be polled inexpensively.
 */
- (BOOL)canPollInexpensively;

/*
 * Eject the floppy disk.
 */
- (IOReturn)ejectMedia;

/*
 * Get list of supported format capacities.
 */
- (IOReturn)formatCapacities;

/*
 * Format a specific cylinder.
 */
- (IOReturn)formatCylinder:(unsigned)cylinder
                      data:(void *)data;

/*
 * Free the drive object and resources.
 */
- free;

/*
 * Initialize drive from device description.
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
                 controller:(id)controller
                       unit:(unsigned)unit;

/*
 * Poll for media presence/change.
 */
- (BOOL)pollMedia;

/*
 * Get list of supported read capacities.
 */
- (IOReturn)readCapacities;

/*
 * Read a specific cylinder.
 */
- (IOReturn)readCylinder:(unsigned)cylinder
                    data:(void *)data;

/*
 * Set the media capacity.
 */
- (IOReturn)setMediaCapacity:(unsigned)capacity;

/*
 * Get list of supported write capacities.
 */
- (IOReturn)writeCapacities;

/*
 * Write a specific cylinder.
 */
- (IOReturn)writeCylinder:(unsigned)cylinder
                     data:(void *)data;

@end

/* End of IOFloppyDrive.h */
