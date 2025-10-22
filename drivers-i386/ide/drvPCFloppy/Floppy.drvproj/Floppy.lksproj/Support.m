/*
 * Support.m - Support methods for IOFloppyDisk
 *
 * Category methods for cache management and support operations
 */

#import "IOFloppyDisk.h"
#import "Support.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IOFloppyDisk(Support)

/*
 * Release cylinder cache.
 * From decompiled code: frees cylinder cache buffer and metadata.
 */
- (void)_releaseCache
{
	void *cacheBuffer;
	unsigned cacheSize;
	void *cacheMetadata;
	unsigned metadataSize;
	
	// Get cache buffer pointer and size (offsets 0x134, 0x138)
	cacheBuffer = *(void **)((char *)self + 0x134);
	cacheSize = *(unsigned *)((char *)self + 0x138);
	
	// Deallocate cache buffer if allocated
	if (cacheBuffer != NULL) {
		vm_deallocate(kern_serv_kernel_task_port(), 
		              (vm_address_t)cacheBuffer, cacheSize);
	}
	
	// Get cache metadata pointer and size (offsets 0x13c, 0x140)
	cacheMetadata = *(void **)((char *)self + 0x13c);
	metadataSize = *(unsigned *)((char *)self + 0x140);
	
	// Free metadata if allocated
	if (cacheMetadata != NULL) {
		IOFree(cacheMetadata, metadataSize);
	}
	
	// Clear all pointers and sizes
	*(void **)((char *)self + 0x134) = NULL;      // Cache buffer
	*(unsigned *)((char *)self + 0x138) = 0;      // Cache size
	*(void **)((char *)self + 0x13c) = NULL;      // Metadata
	*(unsigned *)((char *)self + 0x140) = 0;      // Metadata size
}

/*
 * Set up cylinder cache.
 * From decompiled code: allocates cylinder cache buffer and metadata.
 */
- (BOOL)_setUpCache
{
	int capacity;
	id geometry;
	int diskSize;
	int sectorSize;
	int numCylinders;
	int cacheSize;
	int metadataSize;
	void *cacheBuffer;
	void *cacheMetadata;
	unsigned cylinder;
	int cylinderOffset;
	unsigned char *flagsPtr;
	int *queuePtr;
	
	// Get capacity from offset 0x148
	capacity = *(int *)((char *)self + 0x148);
	
	// Only set up cache if disk is formatted (capacity != 1)
	if (capacity != 1) {
		// Get geometry object from offset 0x14c
		geometry = *(id *)((char *)self + 0x14c);
		
		// Calculate cache size: diskSize * sectorSize
		diskSize = *(int *)((char *)geometry + 4);      // offset 0x04
		sectorSize = *(int *)((char *)geometry + 0x14); // offset 0x14
		cacheSize = diskSize * sectorSize;
		
		// Store cache size at offset 0x138
		*(int *)((char *)self + 0x138) = cacheSize;
		
		// Allocate cache buffer using vm_allocate
		cacheBuffer = NULL;
		vm_allocate(kern_serv_kernel_task_port(),
		           (vm_address_t *)&cacheBuffer, cacheSize, TRUE);
		
		// Store cache buffer pointer at offset 0x134
		*(void **)((char *)self + 0x134) = cacheBuffer;
		
		// Calculate metadata size: numCylinders * 0x14 (20 bytes per cylinder)
		numCylinders = *(int *)((char *)geometry + 0x0c); // offset 0x0c
		metadataSize = numCylinders * 0x14;
		
		// Store metadata size at offset 0x140
		*(int *)((char *)self + 0x140) = metadataSize;
		
		// Allocate metadata using IOMalloc
		cacheMetadata = (void *)IOMalloc(metadataSize);
		
		// Store metadata pointer at offset 0x13c
		*(void **)((char *)self + 0x13c) = cacheMetadata;
		
		// Check if either allocation failed
		if (cacheBuffer == NULL || cacheMetadata == NULL) {
			// Release any allocated memory and fail
			[self _releaseCache];
			return NO;
		}
		
		// Zero the cache buffer
		bzero(cacheBuffer, cacheSize);
		
		// Initialize metadata for each cylinder
		for (cylinder = 0; cylinder < numCylinders; cylinder++) {
			cylinderOffset = cylinder * 0x14;
			
			// Set state to 3 (not loaded) at offset +0x00
			*(int *)((char *)cacheMetadata + cylinderOffset) = 3;
			
			// Clear reference/timestamp at offset +0x04
			*(int *)((char *)cacheMetadata + cylinderOffset + 4) = 0;
			
			// Get pointer to flags byte at offset +0x10
			flagsPtr = (unsigned char *)((char *)cacheMetadata + cylinderOffset + 0x10);
			
			// Clear bit 0 (error flag)
			*flagsPtr &= 0xfe;
			
			// Clear bit 1 (dirty flag)
			*flagsPtr &= 0xfd;
			
			// Initialize queue pointers at offsets +0x08 and +0x0c
			// Point to themselves (empty circular queue)
			queuePtr = (int *)((char *)cacheMetadata + cylinderOffset + 8);
			*queuePtr = (int)queuePtr;           // prev pointer
			*(queuePtr + 1) = (int)queuePtr;     // next pointer
		}
	}
	
	return YES;
}

@end

/* End of Support.m */
