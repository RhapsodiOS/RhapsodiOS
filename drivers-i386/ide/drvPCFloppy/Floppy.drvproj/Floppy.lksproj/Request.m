/*
 * Request.m - Request management methods for IOFloppyDisk
 *
 * Category methods for I/O request processing and subrequest management
 */

#import "IOFloppyDisk.h"
#import "Request.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IOFloppyDisk(Request)

/*
 * Abort all subrequests on a cylinder.
 * From decompiled code: aborts all pending I/O operations on a cylinder.
 */
- (void)_abortSubrequestsOnCylinder:(unsigned)cylinderNumber
{
	void *cacheMetadata;
	int cylinderOffset;
	int *queueHead;
	int *subrequest;
	int *prevPtr;
	int *nextPtr;
	int *linkPtr;
	id parentRequest;
	id lockObject;
	
	// Get cache metadata pointer from offset 0x13c
	cacheMetadata = *(void **)((char *)self + 0x13c);
	
	// Calculate offset to this cylinder's metadata (0x14 bytes per cylinder)
	cylinderOffset = cylinderNumber * 0x14;
	
	// Get queue head pointer (at offset +8 in cylinder metadata)
	queueHead = (int *)((char *)cacheMetadata + cylinderOffset + 8);
	
	// Process all subrequests in the queue
	while (*(int **)((char *)cacheMetadata + cylinderOffset + 8) != queueHead) {
		// Get first subrequest from queue
		subrequest = *(int **)((char *)cacheMetadata + cylinderOffset + 8);
		
		// Get prev and next pointers from subrequest
		prevPtr = (int *)subrequest[3];  // offset 0x0c
		nextPtr = (int *)subrequest[4];  // offset 0x10
		
		// Unlink from queue - update prev->next
		linkPtr = (int *)queueHead;
		if ((int *)((char *)cacheMetadata + cylinderOffset + 8) != prevPtr) {
			linkPtr = prevPtr + 3;  // Point to next field at offset 0x0c
		}
		*(int **)((char *)linkPtr + 4) = nextPtr;
		
		// Unlink from queue - update next->prev
		if (nextPtr != queueHead) {
			nextPtr = nextPtr + 3;  // Point to prev field
		}
		*nextPtr = (int)prevPtr;
		
		// Get parent request from offset 0x08 in subrequest
		parentRequest = (id)subrequest[2];
		
		// Set abort flag in parent request at offset 0x0c
		*((unsigned char *)parentRequest + 0x0c) = 1;
		
		// Get lock object from parent request at offset 0x18
		lockObject = *(id *)((char *)parentRequest + 0x18);
		
		// Lock and unlock with status 1 (aborted)
		[lockObject lock];
		[lockObject unlockWith:1];
		
		// Update pointer to cache metadata (in case it changed)
		cacheMetadata = *(void **)((char *)self + 0x13c);
	}
}

/*
 * Check cylinder state for a subrequest.
 * From decompiled code: checks if cylinder is ready for I/O.
 */
- (IOReturn)_checkCylinderStateForSubrequest:(id)subrequest
{
	void *cacheMetadata;
	unsigned cylinderNumber;
	BOOL isWrite;
	int cylinderState;
	int cylinderOffset;
	unsigned *readOperation;
	id mainQueue;
	id queueLock;
	int *queueHead;
	BOOL ready;
	
	// Get subrequest info - assuming structure with cylinder at offset 0x04
	cylinderNumber = *(unsigned *)((char *)subrequest + 0x04);
	isWrite = *(BOOL *)subrequest;  // Write flag at offset 0x00
	
	// Get cache metadata
	cacheMetadata = *(void **)((char *)self + 0x13c);
	cylinderOffset = cylinderNumber * 0x14;
	
	// Get cylinder state
	cylinderState = *(int *)((char *)cacheMetadata + cylinderOffset);
	
	ready = NO;
	
	// Check if cylinder needs to be loaded (state == 3)
	if (cylinderState == 3) {
		// Allocate read operation (0x28 = 40 bytes)
		readOperation = (unsigned *)IOMalloc(0x28);
		
		// Set operation type to 0 (read cylinder)
		readOperation[0] = 0;
		
		// Set cylinder number
		readOperation[1] = cylinderNumber;
		
		// Get queue lock
		queueLock = *(id *)((char *)self + 0x158);
		
		// Lock the queue
		[queueLock lock];
		
		// Get main operation queue head
		mainQueue = (id)((char *)self + 0x150);
		queueHead = (int *)((char *)self + 0x150);
		
		// Add operation to queue
		if (*(void **)((char *)self + 0x150) == mainQueue) {
			// Queue is empty
			*(unsigned **)((char *)self + 0x150) = readOperation;
			*(unsigned **)((char *)self + 0x154) = readOperation;
			readOperation[8] = (unsigned)queueHead;  // prev
			readOperation[9] = (unsigned)queueHead;  // next
		} else {
			// Queue has entries - append to end
			int lastEntry = *(int *)((char *)self + 0x154);
			readOperation[9] = lastEntry;  // prev
			readOperation[8] = (unsigned)queueHead;  // next
			*(unsigned **)((char *)self + 0x154) = readOperation;
			*(unsigned **)(lastEntry + 0x20) = readOperation;
		}
		
		// Unlock with status 1 (wake operation thread)
		[queueLock unlockWith:1];
		
		ready = NO;
	}
	else if (isWrite) {
		// For write operation, cylinder is ready if state == 0
		ready = (cylinderState == 0);
	}
	else {
		// For read operation
		ready = NO;
		
		// Ready if state < 2 and queue is empty
		if (cylinderState < 2) {
			queueHead = (int *)((char *)cacheMetadata + cylinderOffset + 8);
			if (*(int **)((char *)cacheMetadata + cylinderOffset + 8) == queueHead) {
				ready = YES;
			}
		}
	}
	
	return ready;
}

/*
 * Construct an I/O request.
 * From decompiled code: allocates and initializes a request structure.
 */
- (id)_constructRequest:(IOReturn *)statusPtr
             blockStart:(unsigned)blockStart
              byteCount:(unsigned)byteCount
                 buffer:(void *)buffer
              bufferMap:(vm_task_t)bufferMap
{
	id geometry;
	unsigned sectorSize;
	unsigned numBlocks;
	unsigned diskSize;
	unsigned blockEnd;
	unsigned startCylinder;
	unsigned endCylinder;
	unsigned numCylinders;
	unsigned requestSize;
	void *request;
	void *queueHead;
	id lockObject;
	unsigned cylinder;
	unsigned subrequestIndex;
	unsigned blocksInCylinder;
	unsigned blocksThisSubrequest;
	unsigned bufferOffset;
	int subrequestOffset;
	
	// Get geometry
	geometry = *(id *)((char *)self + 0x14c);
	sectorSize = *(unsigned *)((char *)geometry + 0x14);
	diskSize = *(unsigned *)((char *)geometry + 4);
	
	// Validate: byte count must be sector-aligned
	if ((byteCount % sectorSize) != 0) {
		if (statusPtr != NULL) *statusPtr = IO_R_INVALID_ARG;
		return nil;
	}
	
	// Convert to blocks
	numBlocks = byteCount / sectorSize;
	blockEnd = (numBlocks - 1) + blockStart;
	
	// Validate: must not exceed disk size and must have at least 1 block
	if ((blockEnd >= diskSize) || (numBlocks == 0)) {
		if (statusPtr != NULL) *statusPtr = IO_R_INVALID_ARG;
		return nil;
	}
	
	// Get cylinder range
	startCylinder = [self _cylinderFromBlockNumber:blockStart head:NULL sector:NULL];
	endCylinder = [self _cylinderFromBlockNumber:blockEnd head:NULL sector:NULL];
	numCylinders = (endCylinder - startCylinder) + 1;
	
	// Calculate request size: header (0x24) + numCylinders * subrequest size (0x24)
	requestSize = numCylinders * 0x24 + 0x24;
	
	// Allocate request
	request = (void *)IOMalloc(requestSize);
	if (request == NULL) {
		if (statusPtr != NULL) *statusPtr = IO_R_NO_MEMORY;
		return nil;
	}
	
	// Initialize request header
	*(IOReturn **)request = statusPtr;                     // +0x00: status pointer
	*(unsigned *)((char *)request + 0x04) = requestSize;   // +0x04: size
	*((unsigned char *)request + 0x0c) = 0;                // +0x0c: abort flag
	
	// Allocate lock object
	lockObject = [[objc_getClass("NXConditionLock") alloc] init];
	*(id *)((char *)request + 0x18) = lockObject;          // +0x18: lock
	*(unsigned *)((char *)request + 0x20) = numCylinders;  // +0x20: num subrequests
	*(unsigned *)((char *)request + 0x1c) = 0;             // +0x1c: completed count
	
	// Initialize queue head at offset 0x10
	queueHead = (char *)request + 0x10;
	*(void **)((char *)request + 0x10) = queueHead;
	*(void **)((char *)request + 0x14) = queueHead;
	
	// Check if lock allocation succeeded
	if (lockObject == nil) {
		IOFree(request, requestSize);
		if (statusPtr != NULL) *statusPtr = IO_R_NO_MEMORY;
		return nil;
	}
	
	// Initialize lock with status 0
	[lockObject initWith:0];
	
	// Build subrequests
	subrequestIndex = 0;
	cylinder = startCylinder;
	bufferOffset = (unsigned)buffer;
	
	while (cylinder <= endCylinder) {
		subrequestOffset = subrequestIndex * 0x24;
		
		// Initialize subrequest structure:
		// +0x00: write flag (default to 0 for read - caller may override)
		*((BOOL *)((char *)request + 0x24 + subrequestOffset)) = 0;
		
		// +0x04: cylinder number
		*(unsigned *)((char *)request + 0x24 + subrequestOffset + 0x04) = 
			startCylinder + subrequestIndex;
		
		// +0x08: parent request
		*(void **)((char *)request + 0x24 + subrequestOffset + 0x08) = request;
		
		// +0x0c, +0x10: queue pointers (will be set when queued, leave uninitialized)
		
		// Calculate blocks to process for this cylinder
		blocksInCylinder = [self _blocksToEndOfCylinderFromBlockNumber:blockStart];
		
		if (blocksInCylinder < (blockEnd - blockStart) + 1) {
			blocksThisSubrequest = blocksInCylinder;
		} else {
			blocksThisSubrequest = (blockEnd - blockStart) + 1;
		}
		
		// Set subrequest parameters
		// Note: +0x0c and +0x10 are reserved for prev/next queue pointers
		*(unsigned *)((char *)request + 0x24 + subrequestOffset + 0x14) = blockStart;
		*(unsigned *)((char *)request + 0x24 + subrequestOffset + 0x18) = blocksThisSubrequest;
		*(unsigned *)((char *)request + 0x24 + subrequestOffset + 0x1c) = bufferOffset;
		*(vm_task_t *)((char *)request + 0x24 + subrequestOffset + 0x20) = bufferMap;
		
		// Update for next subrequest
		blockStart += blocksThisSubrequest;
		bufferOffset += blocksThisSubrequest * sectorSize;
		subrequestIndex++;
		cylinder = startCylinder + subrequestIndex;
	}
	
	if (statusPtr != NULL) *statusPtr = IO_R_SUCCESS;
	return request;
}

/*
 * Execute an I/O request.
 * From decompiled code: breaks request into subrequests and executes them.
 */
- (void)_executeRequest:(id)request
{
	id operationLock;
	id geometry;
	unsigned numCylinders;
	unsigned numSubrequests;
	unsigned lastCylinder;
	unsigned subrequestIndex;
	void *subrequest;
	BOOL isReady;
	void *cacheMetadata;
	int cylinderOffset;
	int *queueHead;
	void *requestQueueHead;
	void *prevPtr;
	void *nextPtr;
	void *linkPtr;
	id requestLock;
	IOReturn result;
	unsigned remainingCount;
	BOOL abortFlag;

	// Get operation lock from offset 0x144
	operationLock = *(id *)((char *)self + 0x144);

	// Lock for critical section
	[operationLock lock];

	// Validate: check if last cylinder of last subrequest is within bounds
	numSubrequests = *(unsigned *)((char *)request + 0x20);

	// Get cylinder number from last subrequest
	// Last subrequest is at: request + 0x24 + (numSubrequests-1) * 0x24 + 0x04
	// Which equals: request + 0x24 + numSubrequests * 0x24 - 0x24 + 0x04
	//             = request + numSubrequests * 0x24 + 0x04
	lastCylinder = *(unsigned *)((char *)request + numSubrequests * 0x24 + 0x04);

	// Get number of cylinders from geometry
	geometry = *(id *)((char *)self + 0x14c);
	numCylinders = *(unsigned *)((char *)geometry + 0x0c);

	if (lastCylinder >= numCylinders) {
		// Invalid cylinder range
		[operationLock unlock];
		*(IOReturn *)((char *)request + 0x1c) = IO_R_INVALID_ARG;
		return;
	}

	// Process all subrequests - check state and either queue or prepare for execution
	for (subrequestIndex = 0; subrequestIndex < numSubrequests; subrequestIndex++) {
		// Get pointer to this subrequest
		subrequest = (char *)request + 0x24 + subrequestIndex * 0x24;

		// Check if cylinder is ready for this subrequest
		isReady = [self _checkCylinderStateForSubrequest:subrequest];

		if (!isReady) {
			// Cylinder not ready - queue subrequest on cylinder's wait queue
			unsigned cylinderNumber = *(unsigned *)((char *)subrequest + 0x04);
			cacheMetadata = *(void **)((char *)self + 0x13c);
			cylinderOffset = cylinderNumber * 0x14;
			queueHead = (int *)((char *)cacheMetadata + cylinderOffset + 8);

			// Check if queue is empty
			if (*(int **)((char *)cacheMetadata + cylinderOffset + 8) == queueHead) {
				// Empty queue - initialize as first entry
				*(void **)((char *)cacheMetadata + cylinderOffset + 8) = subrequest;
				*(void **)((char *)cacheMetadata + cylinderOffset + 0xc) = subrequest;
				*(void **)((char *)subrequest + 0x0c) = queueHead;  // prev
				*(void **)((char *)subrequest + 0x10) = queueHead;  // next
			} else {
				// Queue has entries - append to end
				void *lastEntry = *(void **)((char *)cacheMetadata + cylinderOffset + 0xc);
				*(void **)((char *)subrequest + 0x10) = lastEntry;  // prev
				*(void **)((char *)subrequest + 0x0c) = queueHead;  // next
				*(void **)((char *)cacheMetadata + cylinderOffset + 0xc) = subrequest;
				*(void **)((char *)lastEntry + 0xc) = subrequest;
			}
		} else {
			// Cylinder ready - impose state and add to request's ready queue
			[self _imposeCylinderStateForSubrequest:subrequest];

			// Get request's ready queue head (at offset 0x10)
			requestQueueHead = (char *)request + 0x10;

			// Check if ready queue is empty
			if (*(void **)((char *)request + 0x10) == requestQueueHead) {
				// Empty - initialize as first entry
				*(void **)((char *)request + 0x10) = subrequest;
				*(void **)((char *)request + 0x14) = subrequest;
				*(void **)((char *)subrequest + 0x0c) = requestQueueHead;  // prev
				*(void **)((char *)subrequest + 0x10) = requestQueueHead;  // next
			} else {
				// Append to end
				void *lastEntry = *(void **)((char *)request + 0x14);
				*(void **)((char *)subrequest + 0x10) = lastEntry;  // prev
				*(void **)((char *)subrequest + 0x0c) = requestQueueHead;  // next
				*(void **)((char *)request + 0x14) = subrequest;
				*(void **)((char *)lastEntry + 0xc) = subrequest;
			}
		}
	}

	// Execute ready subrequests
	requestQueueHead = (char *)request + 0x10;

	while (1) {
		// Process all ready subrequests
		while (*(void **)((char *)request + 0x10) != requestQueueHead) {
			// Dequeue first ready subrequest
			subrequest = *(void **)((char *)request + 0x10);
			prevPtr = *(void **)((char *)subrequest + 0x0c);
			nextPtr = *(void **)((char *)subrequest + 0x10);

			// Unlink from queue - update prev->next
			linkPtr = requestQueueHead;
			if (requestQueueHead != prevPtr) {
				linkPtr = (char *)prevPtr + 0x0c;
			}
			*(void **)((char *)linkPtr + 4) = nextPtr;

			// Unlink from queue - update next->prev
			if (requestQueueHead != nextPtr) {
				nextPtr = (char *)nextPtr + 0x0c;
			}
			*(void **)nextPtr = prevPtr;

			// Unlock before executing (allow other operations)
			[operationLock unlock];

			// Execute the subrequest
			[self _executeSubrequest:subrequest];

			// Lock again
			[operationLock lock];

			// Unimpose cylinder state
			result = [self _unimposeCylinderStateForSubrequest:subrequest];

			// If state change succeeded, pop other waiting subrequests
			if (result != 0) {
				unsigned cylinderNumber = *(unsigned *)((char *)subrequest + 0x04);
				[self _popSubrequestsOnCylinder:cylinderNumber];
			}

			// Decrement remaining count
			remainingCount = *(unsigned *)((char *)request + 0x20);
			*(unsigned *)((char *)request + 0x20) = remainingCount - 1;
		}

		// Check abort flag
		abortFlag = *((unsigned char *)request + 0x0c);
		if (abortFlag) {
			// Request was aborted
			[operationLock unlock];
			*(IOReturn *)((char *)request + 0x1c) = IO_R_IO;
			return;
		}

		// Check if all subrequests completed
		remainingCount = *(unsigned *)((char *)request + 0x20);
		if (remainingCount == 0) {
			// All done
			break;
		}

		// Still have subrequests pending but none ready - wait for notification
		[operationLock unlock];

		// Get request lock and wait for wake-up
		requestLock = *(id *)((char *)request + 0x18);
		[requestLock lockWhen:1];
		[requestLock unlockWith:0];

		// Lock again and retry
		[operationLock lock];
	}

	// Unlock and return final status
	[operationLock unlock];
}


/*
 * Execute a subrequest.
 * From decompiled code: performs I/O for a single subrequest.
 */
- (IOReturn)_executeSubrequest:(id)subrequest
{
	unsigned cylinderNumber;
	void *cacheMetadata;
	unsigned char *flagsPtr;
	void *cachePointer;
	id geometry;
	unsigned sectorSize;
	unsigned blockCount;
	unsigned byteCount;
	int wireResult;
	BOOL isWrite;
	void *buffer;
	vm_task_t bufferMap;
	unsigned blockStart;
	id parentRequest;

	// Get cylinder number and check for errors
	cylinderNumber = *(unsigned *)((char *)subrequest + 0x04);
	cacheMetadata = *(void **)((char *)self + 0x13c);

	// Get pointer to cylinder flags
	flagsPtr = (unsigned char *)((char *)cacheMetadata + cylinderNumber * 0x14 + 0x10);

	// Check if error flag is set (bit 0)
	if ((*flagsPtr & 1) != 0) {
		// Cylinder has an error - fail the operation
		parentRequest = *(id *)((char *)subrequest + 0x08);
		*(IOReturn *)((char *)parentRequest + 0x1c) = IO_R_IO_ERROR;
		return IO_R_IO_ERROR;
	}

	// Get block start and calculate cache pointer
	blockStart = *(unsigned *)((char *)subrequest + 0x14);
	cachePointer = [self _cachePointerFromBlockNumber:blockStart];

	// Get sector size and block count to calculate byte count
	geometry = *(id *)((char *)self + 0x14c);
	sectorSize = *(unsigned *)((char *)geometry + 0x14);
	blockCount = *(unsigned *)((char *)subrequest + 0x18);
	byteCount = sectorSize * blockCount;

	// Wire the cache memory
	wireResult = vm_wire(kern_serv_kernel_task_port(),
	                      kernel_map,
	                      (vm_address_t)cachePointer,
	                      byteCount,
	                      VM_PROT_READ | VM_PROT_WRITE);

	if (wireResult != KERN_SUCCESS) {
		// Wiring failed
		parentRequest = *(id *)((char *)subrequest + 0x08);
		*(IOReturn *)((char *)parentRequest + 0x1c) = IO_R_VM_FAILURE;
		return IO_R_VM_FAILURE;
	}

	// Get write flag and buffer info
	isWrite = *(BOOL *)subrequest;
	buffer = *(void **)((char *)subrequest + 0x1c);
	bufferMap = *(vm_task_t *)((char *)subrequest + 0x20);

	// Perform the copy operation
	if (!isWrite) {
		// Read operation: copy from cache to user buffer
		vm_map_copy_overwrite(bufferMap,
		                       (vm_address_t)buffer,
		                       (vm_map_copy_t)cachePointer,
		                       FALSE);
	} else {
		// Write operation: copy from user buffer to cache
		vm_map_copy_overwrite(kernel_map,
		                       (vm_address_t)cachePointer,
		                       (vm_map_copy_t)buffer,
		                       FALSE);
	}

	// Unwire the cache memory
	vm_wire(kern_serv_kernel_task_port(),
	        kernel_map,
	        (vm_address_t)cachePointer,
	        byteCount,
	        VM_PROT_NONE);

	return IO_R_SUCCESS;
}


/*
 * Free an I/O request.
 * From decompiled code: releases request structure and resources.
 */
- (void)_freeRequest:(id)request
{
	id lockObject;
	unsigned requestSize;

	// Get lock object from offset 0x18
	lockObject = *(id *)((char *)request + 0x18);

	// Free the lock object
	[lockObject free];

	// Get request size from offset 0x04
	requestSize = *(unsigned *)((char *)request + 0x04);

	// Free the request structure
	IOFree(request, requestSize);
}


/*
 * Impose cylinder state for a subrequest.
 * From decompiled code: marks cylinder as needed for a subrequest.
 */
- (IOReturn)_imposeCylinderStateForSubrequest:(id)subrequest
{
	unsigned cylinderNumber;
	void *cacheMetadata;
	int cylinderOffset;
	BOOL isWrite;
	int *refCountPtr;

	// Get cylinder number
	cylinderNumber = *(unsigned *)((char *)subrequest + 0x04);

	// Get cache metadata
	cacheMetadata = *(void **)((char *)self + 0x13c);
	cylinderOffset = cylinderNumber * 0x14;

	// Get write flag
	isWrite = *(BOOL *)subrequest;

	if (!isWrite) {
		// Read operation: set state to 1 (reading) and increment reference count
		*(int *)((char *)cacheMetadata + cylinderOffset) = 1;

		// Increment reference count at offset +0x04
		refCountPtr = (int *)((char *)cacheMetadata + cylinderOffset + 4);
		(*refCountPtr)++;
	} else {
		// Write operation: set state to 2 (writing)
		*(int *)((char *)cacheMetadata + cylinderOffset) = 2;
	}

	return IO_R_SUCCESS;
}


/*
 * Pop and process subrequests waiting on a cylinder.
 * From decompiled code: processes all queued subrequests for a cylinder.
 */
- (void)_popSubrequestsOnCylinder:(unsigned)cylinderNumber
{
	void *cacheMetadata;
	int cylinderOffset;
	int *queueHead;
	void *subrequest;
	BOOL processedOne;
	BOOL isWrite;
	void *prevPtr;
	void *nextPtr;
	void *linkPtr;
	id parentRequest;
	void *parentQueueHead;
	id parentLock;

	processedOne = NO;
	cacheMetadata = *(void **)((char *)self + 0x13c);
	cylinderOffset = cylinderNumber * 0x14;
	queueHead = (int *)((char *)cacheMetadata + cylinderOffset + 8);

	// Process all subrequests in cylinder's queue
	while (*(void **)((char *)cacheMetadata + cylinderOffset + 8) != (void *)queueHead) {
		// Get first subrequest
		subrequest = *(void **)((char *)cacheMetadata + cylinderOffset + 8);

		// Check if we've already processed one and this is a write
		isWrite = *(BOOL *)subrequest;
		if (processedOne && isWrite) {
			// Don't process write after we've already done one
			return;
		}

		// Dequeue from cylinder queue
		prevPtr = *(void **)((char *)subrequest + 0x0c);
		nextPtr = *(void **)((char *)subrequest + 0x10);

		// Unlink - update prev->next
		linkPtr = queueHead;
		if ((void *)queueHead != prevPtr) {
			linkPtr = (char *)prevPtr + 0x0c;
		}
		*(void **)((char *)linkPtr + 4) = nextPtr;

		// Unlink - update next->prev
		if ((void *)queueHead != nextPtr) {
			nextPtr = (char *)nextPtr + 0x0c;
		}
		*(void **)nextPtr = prevPtr;

		// Add to parent request's ready queue
		parentRequest = *(id *)((char *)subrequest + 0x08);
		parentQueueHead = (char *)parentRequest + 0x10;

		if (*(void **)((char *)parentRequest + 0x10) == parentQueueHead) {
			// Empty queue
			*(void **)((char *)parentRequest + 0x10) = subrequest;
			*(void **)((char *)parentRequest + 0x14) = subrequest;
			*(void **)((char *)subrequest + 0x0c) = parentQueueHead;
			*(void **)((char *)subrequest + 0x10) = parentQueueHead;
		} else {
			// Append to end
			void *lastEntry = *(void **)((char *)parentRequest + 0x14);
			*(void **)((char *)subrequest + 0x10) = lastEntry;
			*(void **)((char *)subrequest + 0x0c) = parentQueueHead;
			*(void **)((char *)parentRequest + 0x14) = subrequest;
			*(void **)((char *)lastEntry + 0x0c) = subrequest;
		}

		// Impose cylinder state
		[self _imposeCylinderStateForSubrequest:subrequest];

		// Wake up parent request
		parentLock = *(id *)((char *)parentRequest + 0x18);
		[parentLock lock];
		[parentLock unlockWith:1];

		// If this is a write, stop processing
		if (isWrite) {
			return;
		}

		// Mark that we've processed one
		processedOne = YES;

		// Reload cache metadata pointer (may have changed)
		cacheMetadata = *(void **)((char *)self + 0x13c);
	}
}


/*
 * Remove imposed cylinder state for a subrequest.
 * From decompiled code: clears cylinder state markers for a subrequest.
 */
- (IOReturn)_unimposeCylinderStateForSubrequest:(id)subrequest
{
	unsigned cylinderNumber;
	void *cacheMetadata;
	int cylinderOffset;
	BOOL isWrite;
	int *refCountPtr;
	unsigned char *flagsPtr;
	unsigned *operation;
	id queueLock;
	id mainQueue;
	int *queueHead;
	int cylinderState;

	// Get cylinder number
	cylinderNumber = *(unsigned *)((char *)subrequest + 0x04);

	// Get cache metadata
	cacheMetadata = *(void **)((char *)self + 0x13c);
	cylinderOffset = cylinderNumber * 0x14;

	// Get write flag
	isWrite = *(BOOL *)subrequest;

	if (!isWrite) {
		// Read operation: decrement reference count
		refCountPtr = (int *)((char *)cacheMetadata + cylinderOffset + 4);
		(*refCountPtr)--;

		// If reference count reaches 0, clear state
		if (*refCountPtr == 0) {
			*(int *)((char *)cacheMetadata + cylinderOffset) = 0;
		}
	} else {
		// Write operation: set dirty flag and schedule write
		
		// Set bit 1 (dirty flag) at offset +0x10
		flagsPtr = (unsigned char *)((char *)cacheMetadata + cylinderOffset + 0x10);
		*flagsPtr |= 2;

		// Clear state (set to 0)
		*(int *)((char *)cacheMetadata + cylinderOffset) = 0;

		// Allocate write operation structure (0x28 = 40 bytes)
		operation = (unsigned *)IOMalloc(0x28);

		// Set operation type to 1 (write cylinder)
		operation[0] = 1;

		// Set cylinder number
		operation[1] = cylinderNumber;

		// Get queue lock
		queueLock = *(id *)((char *)self + 0x158);

		// Lock the queue
		[queueLock lock];

		// Get main operation queue head (at offset 0x150)
		mainQueue = (id)((char *)self + 0x150);
		queueHead = (int *)((char *)self + 0x150);

		// Add operation to queue
		if (*(void **)((char *)self + 0x150) == mainQueue) {
			// Queue is empty
			*(unsigned **)((char *)self + 0x150) = operation;
			*(unsigned **)((char *)self + 0x154) = operation;
			operation[8] = (unsigned)queueHead;  // prev
			operation[9] = (unsigned)queueHead;  // next
		} else {
			// Queue has entries - append to end
			int lastEntry = *(int *)((char *)self + 0x154);
			operation[9] = lastEntry;  // prev
			operation[8] = (unsigned)queueHead;  // next
			*(unsigned **)((char *)self + 0x154) = operation;
			*(unsigned **)(lastEntry + 0x20) = operation;
		}

		// Unlock with status 1 (wake operation thread)
		[queueLock unlockWith:1];
	}

	// Return whether cylinder is now idle (state == 0)
	cylinderState = *(int *)((char *)cacheMetadata + cylinderOffset);
	return (cylinderState == 0);
}


@end

/* End of Request.m */
