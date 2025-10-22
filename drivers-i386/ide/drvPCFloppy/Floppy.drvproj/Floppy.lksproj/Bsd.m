/*
 * Bsd.m - BSD device interface support for IOFloppyDisk
 *
 * Category methods for BSD device node attachment
 */

#import "IOFloppyDisk.h"
#import "Bsd.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

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
