/*
 * Geometry.m - Geometry support methods for IOFloppyDisk
 *
 * Category methods for disk geometry calculations and cache management
 */

#import "IOFloppyDisk.h"
#import "Geometry.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IOFloppyDisk(Geometry)

/*
 * Calculate blocks remaining to end of cylinder from given block number.
 * From decompiled code: calculates how many blocks until end of current cylinder.
 */
- (unsigned)_blocksToEndOfCylinderFromBlockNumber:(unsigned)blockNumber
{
	id driveObject;
	unsigned *geometryArray;
	unsigned blocksPerCylinder;
	unsigned adjustedBlockNumber;
	
	// Get drive object from offset 0x14c
	driveObject = *(id *)((char *)self + 0x14c);
	
	// Get geometry array pointer from offset 0x18 relative to drive object
	geometryArray = *(unsigned **)((char *)driveObject + 0x18);
	
	adjustedBlockNumber = blockNumber;
	
	if (geometryArray == NULL) {
		// Fixed geometry: blocks per cylinder = numCyls * sectorsPerTrack
		// offset 0x10 and offset 0x8 from drive object
		blocksPerCylinder = *(int *)((char *)driveObject + 0x10) * 
		                    *(int *)((char *)driveObject + 0x8);
	} else {
		// Variable geometry: search array for matching range
		// Array format: [startBlock, ?, sectorsPerCyl, ...]
		while (blockNumber >= *geometryArray) {
			geometryArray += 3;  // Move to next entry (3 uints per entry)
		}
		
		// Get sectors per cylinder from array entry at index 2
		// Multiply by sectors per track from drive object
		blocksPerCylinder = geometryArray[2] * 
		                    *(int *)((char *)driveObject + 0x8);
		
		// Adjust block number relative to this geometry range
		adjustedBlockNumber = blockNumber - *geometryArray;
	}
	
	// Calculate blocks remaining to end of current cylinder
	// Formula: blocksPerCyl - (blockNum % blocksPerCyl)
	return blocksPerCylinder - (adjustedBlockNumber % blocksPerCylinder);
}

/*
 * Get cache pointer from block number.
 * From decompiled code: returns pointer to cached cylinder for given block.
 */
- (void *)_cachePointerFromBlockNumber:(unsigned)blockNumber
{
	id driveObject;
	int sectorSize;
	void *cacheBase;
	
	// Get drive object from offset 0x14c
	driveObject = *(id *)((char *)self + 0x14c);
	
	// Get sector size from offset 0x14 relative to drive object
	sectorSize = *(int *)((char *)driveObject + 0x14);
	
	// Get cache base pointer from offset 0x134
	cacheBase = *(void **)((char *)self + 0x134);
	
	// Calculate cache pointer: blockNumber * sectorSize + cacheBase
	return (void *)((char *)cacheBase + (blockNumber * sectorSize));
}

/*
 * Get cache pointer from cylinder number.
 * From decompiled code: returns pointer to cached cylinder data.
 */
- (void *)_cachePointerFromCylinderNumber:(unsigned)cylinderNumber
{
	id driveObject;
	int *geometryArray;
	int blockNumber;
	int sectorsPerTrack;
	int numHeads;
	int sectorSize;
	void *cacheBase;
	
	// Get drive object from offset 0x14c
	driveObject = *(id *)((char *)self + 0x14c);
	
	// Get geometry array pointer from offset 0x18 relative to drive object
	geometryArray = *(int **)((char *)driveObject + 0x18);
	
	// Get sectors per track from offset 0x8 relative to drive object
	sectorsPerTrack = *(int *)((char *)driveObject + 0x8);
	
	if (geometryArray == NULL) {
		// Fixed geometry: calculate block number from cylinder
		// blockNumber = cylinder * numHeads * sectorsPerTrack
		numHeads = *(int *)((char *)driveObject + 0x10);
		blockNumber = cylinderNumber * numHeads * sectorsPerTrack;
	} else {
		// Variable geometry: search for cylinder range
		// Array format: [startBlock, startCylinder, sectorsPerCyl, ...]
		while ((unsigned)geometryArray[1] <= cylinderNumber) {
			geometryArray += 3;  // Move to next entry
		}
		
		// Calculate block number within this geometry range
		// blockNumber = startBlock + (cyl - startCyl) * sectorsPerCyl * sectorsPerTrack
		blockNumber = geometryArray[0] + 
		             (cylinderNumber - geometryArray[1]) * 
		             geometryArray[2] * sectorsPerTrack;
	}
	
	// Get sector size from offset 0x14 relative to drive object
	sectorSize = *(int *)((char *)driveObject + 0x14);
	
	// Get cache base pointer from offset 0x134
	cacheBase = *(void **)((char *)self + 0x134);
	
	// Calculate cache pointer: blockNumber * sectorSize + cacheBase
	return (void *)((char *)cacheBase + (blockNumber * sectorSize));
}

/*
 * Calculate cylinder number from block number and get head/sector.
 * From decompiled code: converts LBA to CHS addressing.
 */
- (unsigned)_cylinderFromBlockNumber:(unsigned)blockNumber
                                head:(unsigned *)head
                              sector:(unsigned *)sector
{
	id driveObject;
	unsigned *geometryArray;
	unsigned sectorsPerTrack;
	unsigned numHeads;
	unsigned sectorsPerCylinder;
	unsigned long long temp;
	unsigned cylinderNumber;
	unsigned adjustedBlock;
	
	// Get drive object from offset 0x14c
	driveObject = *(id *)((char *)self + 0x14c);
	
	// Get geometry array pointer from offset 0x18 relative to drive object
	geometryArray = *(unsigned **)((char *)driveObject + 0x18);
	
	// Get sectors per track from offset 0x8 relative to drive object
	sectorsPerTrack = *(unsigned *)((char *)driveObject + 0x8);
	
	if (geometryArray == NULL) {
		// Fixed geometry conversion
		// Get number of heads from offset 0x10 relative to drive object
		numHeads = *(unsigned *)((char *)driveObject + 0x10);
		
		// Divide block number by sectors per track
		temp = (unsigned long long)blockNumber / (unsigned long long)numHeads;
		
		// Calculate head number if pointer provided
		if (head != NULL) {
			*head = (unsigned)(temp % (unsigned long long)sectorsPerTrack);
		}
		
		// Calculate sector number if pointer provided
		if (sector != NULL) {
			*sector = blockNumber % numHeads;
		}
		
		// Calculate cylinder number
		cylinderNumber = (unsigned)(temp / sectorsPerTrack);
		
	} else {
		// Variable geometry conversion
		// Search for the geometry range containing this block
		while (blockNumber < *geometryArray) {
			geometryArray += 3;  // Move to next entry
		}
		
		// Get sectors per cylinder from array entry at index 2
		sectorsPerCylinder = geometryArray[2];
		
		// Calculate adjusted block number relative to this range
		adjustedBlock = blockNumber - *geometryArray;
		
		// Divide adjusted block by sectors per cylinder
		temp = (unsigned long long)adjustedBlock / (unsigned long long)sectorsPerCylinder;
		
		// Calculate head number if pointer provided
		if (head != NULL) {
			*head = (unsigned)(temp % (unsigned long long)sectorsPerTrack);
		}
		
		// Calculate sector number if pointer provided
		if (sector != NULL) {
			*sector = adjustedBlock % sectorsPerCylinder;
		}
		
		// Calculate cylinder number (add starting cylinder from array[1])
		cylinderNumber = (unsigned)(temp / sectorsPerTrack) + geometryArray[1];
	}
	
	return cylinderNumber;
}

@end

/* End of Geometry.m */
