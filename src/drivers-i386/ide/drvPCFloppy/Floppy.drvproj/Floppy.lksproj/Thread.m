/*
 * Thread.m - Operation thread support methods for IOFloppyDisk
 *
 * Category methods for background operation thread and cylinder cache management
 */

#import "IOFloppyDisk.h"
#import "Thread.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import "FloppyOperation.h"

/*
 * strlower - Convert string to lowercase in-place
 * From decompiled code: converts all uppercase ASCII characters to lowercase.
 *
 * This function converts a null-terminated string to lowercase by modifying
 * it in place. It only affects ASCII uppercase letters (A-Z), converting them
 * to lowercase (a-z) by adding 32 (0x20) to their ASCII values.
 *
 * Parameters:
 *   str - Pointer to null-terminated string to convert
 *
 * Algorithm:
 *   - Iterates through each character until null terminator
 *   - For each character, checks if it's uppercase (A-Z)
 *   - Uses the check: (char + 0xBF) < 0x1A
 *     - 'A' (0x41) + 0xBF = 0x100 (overflow), result = 0x00 < 0x1A â
 *     - 'Z' (0x5A) + 0xBF = 0x119 (overflow), result = 0x19 < 0x1A â
 *     - '[' (0x5B) + 0xBF = 0x11A (overflow), result = 0x1A NOT < 0x1A â
 *     - 'a' (0x61) + 0xBF = 0x120 (overflow), result = 0x20 NOT < 0x1A â
 *   - If uppercase, adds 32 (space character value) to convert to lowercase
 */
static void strlower(char *str)
{
	char currentChar;

	// Get first character
	currentChar = *str;

	// Loop until null terminator
	while (currentChar != '\0') {
		// Check if character is uppercase (A-Z)
		// The expression (char + 0xBF) wraps around for values 0x41-0x5A
		// After wrap, result is 0x00-0x19, which is < 0x1A
		if ((unsigned char)(*str + 0xBF) < 0x1A) {
			// Convert to lowercase by adding 32 (0x20)
			// 'A' (65) + 32 = 'a' (97)
			*str = *str + ' ';
		}

		// Move to next character
		str = str + 1;

		// Get next character
		currentChar = *str;
	}

	return;
}

/*
 * queueOperationAscending - Insert operation into queue in ascending order
 * From decompiled code: inserts operation into sorted queue (low to high).
 *
 * This function inserts an operation into a doubly-linked circular queue,
 * maintaining ascending order by cylinder number (param_2[1]). If an operation
 * for the same cylinder already exists, it frees the new operation and returns 0.
 *
 * Parameters:
 *   queueHead - Pointer to queue head (doubly-linked list)
 *   operation - Operation structure to insert (floppyOperation_t)
 *               operation->type = operation type
 *               operation->cylinder = cylinder number (sort key)
 *               operation->link.next = next pointer
 *               operation->link.prev = prev pointer
 *
 * Returns:
 *   1 - Operation inserted successfully
 *   0 - Duplicate operation found and freed
 *
 * Queue structure:
 *   - Circular doubly-linked list
 *   - queueHead[0] = first element
 *   - queueHead[1] = last element
 *   - Empty queue: queueHead[0] == queueHead
 */
static BOOL queueOperationAscending(id *queueHead, floppyOperation_t *operation)
{
	floppyOperation_t *current;
	unsigned int *lastOp;

	// Start at first element in queue
	current = (id *)*queueHead;

	// Loop through queue
	while (1) {
		// Check if we've reached the end (back to queue head)
		if (queueHead == current) {
			// Check if queue is empty (head points to itself)
			if ((id *)*queueHead == queueHead) {
				// Empty queue - insert as first element
				*queueHead = operation;
				queueHead[1] = operation;
				operation->link.next = (queue_entry_t)queueHead;
				operation->link.prev = (queue_entry_t)queueHead;
			} else {
				// Non-empty queue - append to end
				lastOp = (unsigned int *)queueHead[1];
				operation->link.prev = (queue_entry_t)lastOp;
				operation->link.next = (queue_entry_t)queueHead;
				queueHead[1] = operation;
				lastOp[8] = (unsigned int)operation;
			}
			return YES;  // Successfully inserted
		}

		// Check for duplicate (same cylinder and operation type)
		if ((current->cylinder == operation->cylinder) && (current->type == operation->type)) {
			// Duplicate found - free the new operation and return 0
			IOFree(operation, 0x28);
			return NO;
		}

		// Check if new operation's cylinder is less than current
		if (operation->cylinder < current->cylinder) {
			// Found insertion point
			if ((id *)*queueHead != queueHead) {
				// Queue not empty
				if ((id *)*queueHead == current) {
					// Insert at head
					operation->link.prev = (queue_entry_t)queueHead;
					operation->link.next = (queue_entry_t)current;
					*queueHead = operation;
				} else {
					// Insert in middle
					operation->link.next = (queue_entry_t)current;
					operation->link.prev = current->link.prev;
					((floppyOperation_t *)current->link.prev)->link.next = (queue_entry_t)operation;
				}
				((unsigned int **)current)[9] = operation;
				return YES;
			}

			// Queue is empty, insert as first element
			*queueHead = operation;
			queueHead[1] = operation;
			operation->link.next = (queue_entry_t)queueHead;
			operation->link.prev = (queue_entry_t)queueHead;
			return YES;
		}

		// Move to next element
		current = (id *)((unsigned int **)current)[8];
	}
}

/*
 * queueOperationDecending - Insert operation into queue in descending order
 * From decompiled code: inserts operation into sorted queue (high to low).
 *
 * This function inserts an operation into a doubly-linked circular queue,
 * maintaining descending order by cylinder number (param_2[1]). If an operation
 * for the same cylinder already exists, it frees the new operation and returns 0.
 *
 * Parameters:
 *   queueHead - Pointer to queue head (doubly-linked list)
 *   operation - Operation structure to insert (floppyOperation_t)
 *               operation->type = operation type
 *               operation->cylinder = cylinder number (sort key)
 *               operation->link.next = next pointer
 *               operation->link.prev = prev pointer
 *
 * Returns:
 *   1 - Operation inserted successfully
 *   0 - Duplicate operation found and freed
 *
 * Note: Identical to queueOperationAscending except comparison is reversed
 *       (checks if current->cylinder < operation->cylinder instead of operation->cylinder < current->cylinder)
 */
static BOOL queueOperationDecending(id *queueHead, floppyOperation_t *operation)
{
	floppyOperation_t *current;
	unsigned int *lastOp;

	// Start at first element in queue
	current = (id *)*queueHead;

	// Loop through queue
	while (1) {
		// Check if we've reached the end (back to queue head)
		if (queueHead == current) {
			// Check if queue is empty (head points to itself)
			if ((id *)*queueHead == queueHead) {
				// Empty queue - insert as first element
				*queueHead = operation;
				queueHead[1] = operation;
				operation->link.next = (queue_entry_t)queueHead;
				operation->link.prev = (queue_entry_t)queueHead;
			} else {
				// Non-empty queue - append to end
				lastOp = (unsigned int *)queueHead[1];
				operation->link.prev = (queue_entry_t)lastOp;
				operation->link.next = (queue_entry_t)queueHead;
				queueHead[1] = operation;
				lastOp[8] = (unsigned int)operation;
			}
			return YES;  // Successfully inserted
		}

		// Check for duplicate (same cylinder and operation type)
		if ((current->cylinder == operation->cylinder) && (current->type == operation->type)) {
			// Duplicate found - free the new operation and return 0
			IOFree(operation, 0x28);
			return NO;
		}

		// Check if current operation's cylinder is less than new (DESCENDING order)
		if (current->cylinder < operation->cylinder) {
			// Found insertion point
			if ((id *)*queueHead != queueHead) {
				// Queue not empty
				if ((id *)*queueHead == current) {
					// Insert at head
					operation->link.prev = (queue_entry_t)queueHead;
					operation->link.next = (queue_entry_t)current;
					*queueHead = operation;
				} else {
					// Insert in middle
					operation->link.next = (queue_entry_t)current;
					operation->link.prev = current->link.prev;
					((floppyOperation_t *)current->link.prev)->link.next = (queue_entry_t)operation;
				}
				((unsigned int **)current)[9] = operation;
				return YES;
			}

			// Queue is empty, insert as first element
			*queueHead = operation;
			queueHead[1] = operation;
			operation->link.next = (queue_entry_t)queueHead;
			operation->link.prev = (queue_entry_t)queueHead;
			return YES;
		}

		// Move to next element
		current = (id *)((unsigned int **)current)[8];
	}
}

/*
 * sweepQueueInsert - Insert operation into appropriate sweep queue
 * From decompiled code: inserts operation into ascending or descending queue based on sweep direction.
 *
 * This function implements an elevator algorithm for disk I/O scheduling. It maintains
 * two queues - one ascending and one descending - and inserts the operation into the
 * appropriate queue based on the current head position and sweep direction.
 *
 * Parameters:
 *   ascendingQueue  - Queue for ascending cylinder order
 *   descendingQueue - Queue for descending cylinder order
 *   operation       - Operation to insert
 *   currentCylinder - Current head position (cylinder number)
 *   sweepDirection  - Current sweep direction (1 = ascending, 0 = descending)
 *
 * Algorithm:
 *   - If operation cylinder <= current cylinder AND (not at same cylinder OR direction != ascending)
 *     -> Insert into ascending queue (will be processed on next upward sweep)
 *   - Otherwise
 *     -> Insert into descending queue (will be processed on current/next downward sweep)
 */
static void sweepQueueInsert(id *ascendingQueue, id *descendingQueue,
                              floppyOperation_t *operation, unsigned int currentCylinder,
                              int sweepDirection)
{
	unsigned int operationCylinder;

	// Get cylinder number from operation
	operationCylinder = operation->cylinder;

	// Determine which queue to insert into based on sweep direction and position
	if ((operationCylinder < currentCylinder) ||
	    ((operationCylinder == currentCylinder) && (sweepDirection == 1))) {
		// Operation is behind current position, or exactly under the head
		// while sweeping up (already serviced on this pass) - queue it for
		// the next downward sweep.
		queueOperationDecending(descendingQueue, operation);
		return;
	}

	// Operation is ahead of current position, or exactly under the head
	// while sweeping down - queue it for the next upward sweep.
	queueOperationAscending(ascendingQueue, operation);
	return;
}

/*
 * sweepQueueReorder - Reorder queues when sweep direction changes
 * From decompiled code: moves operations between queues when head changes direction.
 *
 * This function is called when the disk head changes sweep direction. It moves
 * operations that are now "behind" the current position from one queue to the other,
 * ensuring proper elevator algorithm operation.
 *
 * Parameters:
 *   ascendingQueue  - Queue for ascending cylinder order
 *   descendingQueue - Queue for descending cylinder order
 *   currentCylinder - Current head position (cylinder number)
 *   sweepDirection  - New sweep direction (1 = ascending, 0 = descending)
 *
 * Algorithm:
 *   1. Move operations from ascending queue to descending queue if they're
 *      now ahead of the current position (when sweeping up)
 *   2. Move operations from descending queue to ascending queue if they're
 *      now behind the current position (when sweeping down)
 */
static void sweepQueueReorder(id *ascendingQueue, id *descendingQueue,
                               unsigned int currentCylinder, int sweepDirection)
{
	unsigned int *operation;
	unsigned int **nextOp;
	unsigned int **prevOp;
	unsigned int **linkPtr;
	unsigned int *firstOp;

	// Process ascending queue - move operations that should be in descending queue
	operation = (unsigned int *)*ascendingQueue;
	while (operation != (unsigned int *)ascendingQueue) {
		firstOp = (unsigned int *)*ascendingQueue;

		// Check if operation should stay in ascending queue
		// Stay if: cylinder <= current AND (not same OR direction == descending)
		if ((currentCylinder <= (unsigned int)firstOp[1]) &&
		    ((firstOp[1] != currentCylinder) || (sweepDirection != 1))) {
			break;  // All remaining operations in ascending queue are correct
		}

		// Remove operation from ascending queue
		nextOp = (unsigned int **)firstOp[8];
		prevOp = (unsigned int **)firstOp[9];

		// Update next link of previous element
		linkPtr = ascendingQueue;
		if (ascendingQueue != (id *)nextOp) {
			linkPtr = (id **)(nextOp + 9);  // nextOp->prev pointer
		}
		linkPtr[1] = (id)prevOp;

		// Update prev link of next element
		linkPtr = ascendingQueue;
		if (ascendingQueue != (id *)prevOp) {
			linkPtr = (id **)(prevOp + 9);  // prevOp->prev pointer
		}
		*linkPtr = (id)nextOp;

		// Insert into descending queue
		queueOperationDecending(descendingQueue, firstOp);

		// Get next operation to check
		operation = (unsigned int *)*ascendingQueue;
	}

	// Process descending queue - move operations that should be in ascending queue
	operation = (unsigned int *)*descendingQueue;
	while (1) {
		if (operation == (unsigned int *)descendingQueue) {
			return;  // Done - reached end of descending queue
		}

		firstOp = (unsigned int *)*descendingQueue;

		// Check if operation should stay in descending queue
		// Stay if: cylinder > current OR (same AND direction == ascending)
		if ((unsigned int)firstOp[1] <= currentCylinder) {
			if (firstOp[1] != currentCylinder) {
				return;  // All remaining operations are correct
			}
			if (sweepDirection != 0) {
				return;  // At same cylinder and not descending
			}
		}

		// Remove operation from descending queue
		nextOp = (unsigned int **)firstOp[8];
		prevOp = (unsigned int **)firstOp[9];

		// Update next link of previous element
		linkPtr = descendingQueue;
		if (descendingQueue != (id *)nextOp) {
			linkPtr = (id **)(nextOp + 9);  // nextOp->prev pointer
		}
		linkPtr[1] = (id)prevOp;

		// Update prev link of next element
		linkPtr = descendingQueue;
		if (descendingQueue != (id *)prevOp) {
			linkPtr = (id **)(prevOp + 9);  // prevOp->prev pointer
		}
		*linkPtr = (id)nextOp;

		// Insert into ascending queue
		queueOperationAscending(ascendingQueue, firstOp);

		// Get next operation to check
		operation = (unsigned int *)*descendingQueue;
	}
}

@implementation IOFloppyDisk(OperationThreadLocal)

/*
 * Bring a cylinder online (read into cache).
 * From decompiled code: reads cylinder data into cache buffer.
 */
- (IOReturn)bringCylinderOnline:(unsigned)cylinderNumber
                     isFormatted:(BOOL)isFormatted
{
	void *cachePointer;
	id drive;
	IOReturn result;
	int cylinderInfoOffset;
	unsigned char *flagsPtr;
	id lockObject;
	const char *operationName;
	int unit;
	const char *diskName;

	// Get cache pointer for this cylinder
	cachePointer = [self cachePointerFromCylinderNumber:cylinderNumber];

	// Get drive object
	drive = [self drive];

	// Perform operation based on formatted flag
	if (isFormatted) {
		// Read cylinder into cache
		result = [drive readCylinder:cylinderNumber data:cachePointer];
	} else {
		// Format cylinder (also reads into cache)
		result = [drive formatCylinder:cylinderNumber data:cachePointer];
	}

	// Get lock object from offset 0x144
	lockObject = *(id *)((char *)self + 0x144);

	// Lock for critical section
	[lockObject lock];

	// Calculate offset into cylinder info array (0x14 bytes per cylinder)
	cylinderInfoOffset = cylinderNumber * 0x14;

	// Get pointer to cylinder info structure at offset 0x13c
	// Update flags at offset +0x10
	flagsPtr = (unsigned char *)(*(int *)((char *)self + 0x13c) + 0x10 + cylinderInfoOffset);

	// Clear bit 0 (pending flag)
	*flagsPtr &= 0xfe;

	// Set bit 0 if there was an error (result != IO_R_SUCCESS)
	*flagsPtr |= (result != IO_R_SUCCESS) ? 1 : 0;

	// Clear reference count or timestamp at base offset
	*(int *)(*(int *)((char *)self + 0x13c) + cylinderInfoOffset) = 0;

	// Pop/process subrequests waiting on this cylinder
	[self popSubrequestsOnCylinder:cylinderNumber];

	// Unlock
	[lockObject unlock];

	// Yield to other threads
	IOSleep(0);

	// Log error if operation failed
	if (result != IO_R_SUCCESS) {
		unit = [self unit];
		diskName = [self name];
		operationName = isFormatted ? "read" : "format";

		IOLog("%s: Unable to %s cylinder %d of disk (on drive %d).\n",
		      diskName, operationName, cylinderNumber, unit);
	}

	return result;
}

/*
 * Clear all pending operations on the queue.
 * From decompiled code: removes all queued I/O operations.
 */
- (void)clearOperationsOnQueue:(id)queue
{
	unsigned int *queueEntry;
	unsigned int *prevPtr;
	unsigned int *nextPtr;
	unsigned int *linkPtr;
	unsigned int operationType;
	id lockObject;

	// Process all entries in the queue
	while (1) {
		// Check if queue is empty (head points to itself)
		if (*(void **)queue == queue) {
			return;
		}

		// Get first entry in queue
		queueEntry = *(unsigned int **)queue;

		// Get prev and next pointers (at offsets 0x20 and 0x24)
		prevPtr = (unsigned int *)queueEntry[8];  // offset 0x20 (8 * 4)
		nextPtr = (unsigned int *)queueEntry[9];  // offset 0x24 (9 * 4)

		// Unlink entry from queue - update prev->next
		// prevPtr actually holds the entry's *next* link (offset 0x20); when
		// it is not the queue head itself, its prev field (offset 0x24, i.e.
		// index 9) must be retargeted - that is 8 words, not 4, past prevPtr.
		linkPtr = (unsigned int *)queue;
		if (queue != prevPtr) {
			linkPtr = prevPtr + 8;  // Point to prev field (offset 0x24)
		}
		*(unsigned int **)((char *)linkPtr + 4) = nextPtr;

		// Unlink entry from queue - update next->prev
		// nextPtr actually holds the entry's *prev* link (offset 0x24); when
		// it is not the queue head itself, its next field (offset 0x20, i.e.
		// index 8) must be retargeted - that is 8 words past nextPtr.
		linkPtr = (unsigned int *)queue;
		if (queue != nextPtr) {
			linkPtr = nextPtr + 8;  // Point to next field (offset 0x20)
		}
		*(unsigned int **)linkPtr = prevPtr;

		// Get operation type from offset 0
		operationType = *queueEntry;

		// Process based on operation type
		if (operationType <= 1) {
			// Type 0 or 1: Free the operation structure (0x28 = 40 bytes)
			IOFree(queueEntry, 0x28);
		}
		else if (operationType == 2) {
			// Type 2: Clear flag and unlock
			// Clear byte at offset 0x08
			*((unsigned char *)queueEntry + 0x08) = 0;

			// Get lock object from offset 0x0c and unlock with status 0
			lockObject = (id)queueEntry[3];
			[lockObject unlockWith:0];
		}
		else if (operationType == 4) {
			// Type 4: Unlock object
			// Get lock object from offset 0x10 and unlock with status 0
			lockObject = (id)queueEntry[4];
			[lockObject unlockWith:0];
		}
		// Continue to next entry
	}
}

/*
 * Commit dirty cylinder to disk.
 * From decompiled code: writes modified cylinder data back to disk.
 */
- (IOReturn)commitDirtyCylinder:(unsigned)cylinderNumber
{
	id lockObject;
	unsigned char *flagsPtr;
	void *cachePointer;
	id drive;
	IOReturn result;
	int unit;
	const char *diskName;

	// Get lock object from offset 0x144
	lockObject = *(id *)((char *)self + 0x144);

	// Lock for critical section
	[lockObject lock];

	// Calculate pointer to flags byte (offset 0x13c + 0x10 + cylinderNumber * 0x14)
	flagsPtr = (unsigned char *)(*(int *)((char *)self + 0x13c) + 0x10 + cylinderNumber * 0x14);

	// Clear bit 1 (dirty flag - 0xfd = ~0x02)
	*flagsPtr &= 0xfd;

	// Unlock
	[lockObject unlock];

	// Get cache pointer for this cylinder
	cachePointer = [self cachePointerFromCylinderNumber:cylinderNumber];

	// Get drive object
	drive = [self drive];

	// Write cylinder from cache to disk
	result = [drive writeCylinder:cylinderNumber data:cachePointer];

	// Handle write failure
	if (result != IO_R_SUCCESS) {
		unit = [self unit];
		diskName = [self name];

		IOLog("%s: Unable to commit cylinder %d to disk (on drive %d).\n",
		      diskName, cylinderNumber, unit);

		// Lock again to restore dirty flag
		[lockObject lock];

		// Set bit 1 (dirty flag) back since write failed
		flagsPtr = (unsigned char *)(*(int *)((char *)self + 0x13c) + 0x10 + cylinderNumber * 0x14);
		*flagsPtr |= 2;

		// Unlock
		[lockObject unlock];
	}

	return result;
}

/*
 * Get read mode from configuration table.
 * From decompiled code: looks up read operation mode setting.
 */
- (int)getReadModeFromConfigTable:(id)configTable
{
	const char *modeString;
	char modeBuffer[20];
	char *foundStr;
	int readMode;
	const char *diskName;
	BOOL validMode;

	// Default to mode 1 (normal/demand)
	readMode = 1;
	validMode = NO;

	// Get "Read Mode" value from config table
	modeString = [configTable valueForStringKey:"Read Mode"];

	if (modeString != NULL) {
		// Copy to local buffer (max 20 chars)
		strncpy(modeBuffer, modeString, 0x14);
		modeBuffer[19] = '\0';

		// Convert to lowercase
		strlower(modeBuffer);

		// Check for "ahead" (read-ahead mode)
		foundStr = strstr(modeBuffer, "ahead");
		if (foundStr != NULL) {
			readMode = 0;
			validMode = YES;
		} else {
			// Check for "normal", "default", or "demand"
			foundStr = strstr(modeBuffer, "normal");
			if (foundStr == NULL) {
				foundStr = strstr(modeBuffer, "default");
			}
			if (foundStr == NULL) {
				foundStr = strstr(modeBuffer, "demand");
			}

			if (foundStr != NULL) {
				readMode = 1;
				validMode = YES;
			}
		}

		// If mode string was provided but invalid, log warning
		if (!validMode) {
			diskName = [self name];
			IOLog("%s: Unknown \"Read Mode\" setting in the configuration table.\n", diskName);
		}
	}

	return readMode;
}

/*
 * Get write mode from configuration table.
 * From decompiled code: looks up write operation mode setting.
 */
- (int)getWriteModeFromConfigTable:(id)configTable
{
	const char *modeString;
	char modeBuffer[20];
	char *foundStr;
	int writeMode;
	const char *diskName;
	BOOL validMode;

	// Default to mode 0 (normal/behind)
	writeMode = 0;
	validMode = NO;

	// Get "Write Mode" value from config table
	modeString = [configTable valueForStringKey:"Write Mode"];

	if (modeString != NULL) {
		// Copy to local buffer (max 20 chars)
		strncpy(modeBuffer, modeString, 0x14);
		modeBuffer[19] = '\0';

		// Convert to lowercase
		strlower(modeBuffer);

		// Check for "eject" (eject after write mode)
		foundStr = strstr(modeBuffer, "eject");
		if (foundStr != NULL) {
			writeMode = 3;
			validMode = YES;
		} else {
			// Check for "normal", "default", or "behind"
			foundStr = strstr(modeBuffer, "normal");
			if (foundStr == NULL) {
				foundStr = strstr(modeBuffer, "default");
			}
			if (foundStr == NULL) {
				foundStr = strstr(modeBuffer, "behind");
			}

			if (foundStr != NULL) {
				writeMode = 0;
				validMode = YES;
			} else {
				// Check for "immediate"
				foundStr = strstr(modeBuffer, "immediate");
				if (foundStr != NULL) {
					writeMode = 2;
					validMode = YES;
				} else {
					// Check for "soon"
					foundStr = strstr(modeBuffer, "soon");
					if (foundStr != NULL) {
						writeMode = 1;
						validMode = YES;
					}
				}
			}
		}

		// If mode string was provided but invalid, log warning
		if (!validMode) {
			diskName = [self name];
			IOLog("%s: Unknown \"Write Mode\" setting in the configuration table.\n", diskName);
		}
	}

	return writeMode;
}

/*
 * operationThread - Background elevator (SCAN) scheduler for cylinder I/O.
 * From decompiled code (Thread.m ref 0x7fcc-0x8a79, 135 basic blocks).
 *
 * Every request is first pulled off the single FIFO intake queue at
 * self+0x150 and re-filed into one of five internal queues:
 *
 *   ctlQueue      - plain FIFO (not cylinder-sorted). Holds operation
 *                   types 2 (eject/flush), 3 (change capacity/format) and
 *                   4 (abort + exit thread). Non-empty ctlQueue always wins
 *                   the scheduler's next pick - control operations preempt
 *                   the elevators outright.
 *   rwAscQueue,
 *   rwDescQueue   - cylinder-sorted sweep pair for type 0 (read) operations
 *                   and, when the "Write Mode" config is "soon" (mode 1),
 *                   type 1 (write) operations too.
 *   wbAscQueue,
 *   wbDescQueue   - cylinder-sorted sweep pair for write-behind: type 1
 *                   writes when "Write Mode" is "normal" (mode 0) or
 *                   "immediate" (mode 2).
 *
 * currentCylinder/sweepDirection track the (virtual) disk head position and
 * are shared by both sweep pairs, since it is the same physical head. The
 * scheduler favors the read/write-soon pair unless the write mode is
 * "immediate", in which case the write-behind pair is checked first;
 * forceReorder marks that the other pair's ordering may now be stale
 * (e.g. a normal write arrived while at rest, or an immediate write just
 * moved the head) and must be re-sorted with sweepQueueReorder before it is
 * next consulted. Write mode "eject" (mode 3) drops the write outright
 * (never queued, never committed) and an unrecognized write mode panics.
 *
 * When both sweep pairs and ctlQueue are empty, an optional read-ahead pass
 * looks for the nearest not-yet-cached cylinder (scanning forward from the
 * head, then backward) and brings it online purely speculatively; this is
 * gated by readAheadEnabled (set when "Read Mode" is "ahead" and the media
 * is formatted) or formatPending (set after a capacity change whose new
 * media still needs its remaining cylinders formatted cylinder-by-cylinder,
 * see case 3 below). Only once there is truly nothing left to do does the
 * thread block on [queueLock lockWhen:1] for new intake.
 */
- (void)operationThread
{
	id deviceDescription;
	id configTable;
	int readMode;
	int writeMode;
	id queueLock;
	id operationLock;
	id geometry;
	unsigned numCylinders;
	unsigned cylinderNumber;
	floppyOperation_t *operation;
	unsigned operationType;
	BOOL success;

	/* The five scheduler queues; see the block comment above. */
	queue_head_t ctlQueue;
	queue_head_t rwDescQueue;
	queue_head_t rwAscQueue;
	queue_head_t wbDescQueue;
	queue_head_t wbAscQueue;

	unsigned currentCylinder;
	int sweepDirection;
	BOOL formatPending;
	BOOL forceReorder;
	BOOL readAheadEnabled;

	queue_head_t *selectedQueue;

	// Get configuration
	deviceDescription = *(id *)((char *)self + 0x160);
	configTable = [deviceDescription configTable];
	readMode = [self getReadModeFromConfigTable:configTable];
	writeMode = [self getWriteModeFromConfigTable:configTable];

	queueLock = self->_queueLock;
	operationLock = *(id *)((char *)self + 0x144);

	queue_init(&ctlQueue);
	queue_init(&rwDescQueue);
	queue_init(&rwAscQueue);
	queue_init(&wbDescQueue);
	queue_init(&wbAscQueue);

	currentCylinder = 0;
	sweepDirection = 1;
	formatPending = NO;
	forceReorder = NO;
	readAheadEnabled = (readMode == 0 && *(int *)((char *)self + 0x148) != 1) ? YES : NO;

	[queueLock lock];

	// Main operation loop. A plain [queueLock lock] always re-enters here
	// (matches the reference's var_40 flag, which is unconditionally true on
	// every pass); the idle-wait path further below performs its own
	// lock/unlockWith/lockWhen sequence and jumps directly past this lock
	// with the lock already held.
	for (;;) {
	drain:
		// Drain the intake queue - classify and re-file every pending
		// operation before doing any actual I/O. The queue lock is held for
		// the whole drain, exactly as in the reference.
		while (!queue_empty(&self->_operationQueue)) {
			queue_remove_first(&self->_operationQueue, operation, floppyOperation_t *, link);
			operationType = operation->type;

			if (operationType == 0) {
				// Read: always goes on the read/write-soon sweep pair.
				sweepQueueInsert((id *)&rwAscQueue, (id *)&rwDescQueue, operation,
				                  currentCylinder, sweepDirection);
				if (writeMode == 0) {
					forceReorder = YES;
				}
			} else if (operationType == 1) {
				// Write: routed by the configured write mode.
				switch (writeMode) {
				case 0:
					// "normal": write-behind pair.
					sweepQueueInsert((id *)&wbAscQueue, (id *)&wbDescQueue, operation,
					                  currentCylinder, sweepDirection);
					break;
				case 1:
					// "soon": shares the read pair.
					sweepQueueInsert((id *)&rwAscQueue, (id *)&rwDescQueue, operation,
					                  currentCylinder, sweepDirection);
					break;
				case 2:
					// "immediate": write-behind pair, but force a reorder
					// so it is picked up promptly.
					sweepQueueInsert((id *)&wbAscQueue, (id *)&wbDescQueue, operation,
					                  currentCylinder, sweepDirection);
					forceReorder = YES;
					break;
				case 3:
					// "eject": drop the write, never commit it.
					IOFree(operation, 0x28);
					break;
				default:
					panic("IOFloppyDisk: Unknown write mode.");
				}
			} else if (operationType <= 4) {
				// Eject/format/abort: plain FIFO, always highest priority.
				queue_enter(&ctlQueue, operation, floppyOperation_t *, link);
			} else {
				panic("IOFloppyDisk: Unknown operation type.");
			}
		}
		[queueLock unlock];

		// Pick the next queue to service: ctlQueue always wins; otherwise
		// prefer the read/write-soon pair, except when the write mode is
		// "immediate", in which case the write-behind pair is checked
		// first. Selecting from the "wrong direction" queue of a pair also
		// flips sweepDirection for next time.
		selectedQueue = 0;

		if (!queue_empty(&ctlQueue)) {
			selectedQueue = &ctlQueue;
		} else if (writeMode == 2) {
			if (sweepDirection == 1) {
				if (!queue_empty(&wbAscQueue)) {
					selectedQueue = &wbAscQueue;
				} else if (!queue_empty(&wbDescQueue)) {
					selectedQueue = &wbDescQueue;
					sweepDirection = 0;
				} else {
					if (forceReorder) {
						sweepQueueReorder((id *)&rwAscQueue, (id *)&rwDescQueue, currentCylinder, sweepDirection);
						forceReorder = NO;
					}
					if (!queue_empty(&rwAscQueue)) {
						selectedQueue = &rwAscQueue;
					} else if (!queue_empty(&rwDescQueue)) {
						selectedQueue = &rwDescQueue;
						sweepDirection = 0;
					}
				}
			} else {
				if (!queue_empty(&wbDescQueue)) {
					selectedQueue = &wbDescQueue;
				} else if (!queue_empty(&wbAscQueue)) {
					selectedQueue = &wbAscQueue;
					sweepDirection = 1;
				} else {
					if (forceReorder) {
						sweepQueueReorder((id *)&rwAscQueue, (id *)&rwDescQueue, currentCylinder, sweepDirection);
						forceReorder = NO;
					}
					if (!queue_empty(&rwDescQueue)) {
						selectedQueue = &rwDescQueue;
					} else if (!queue_empty(&rwAscQueue)) {
						selectedQueue = &rwAscQueue;
						sweepDirection = 1;
					}
				}
			}
		} else {
			if (sweepDirection == 1) {
				if (!queue_empty(&rwAscQueue)) {
					selectedQueue = &rwAscQueue;
				} else if (!queue_empty(&rwDescQueue)) {
					selectedQueue = &rwDescQueue;
					sweepDirection = 0;
				} else if (writeMode == 0 && !formatPending) {
					if (forceReorder) {
						sweepQueueReorder((id *)&wbAscQueue, (id *)&wbDescQueue, currentCylinder, sweepDirection);
						forceReorder = NO;
					}
					if (!queue_empty(&wbAscQueue)) {
						selectedQueue = &wbAscQueue;
					} else if (!queue_empty(&wbDescQueue)) {
						selectedQueue = &wbDescQueue;
						sweepDirection = 0;
					}
				}
			} else {
				if (!queue_empty(&rwDescQueue)) {
					selectedQueue = &rwDescQueue;
				} else if (!queue_empty(&rwAscQueue)) {
					selectedQueue = &rwAscQueue;
					sweepDirection = 1;
				} else if (writeMode == 0 && !formatPending) {
					if (forceReorder) {
						sweepQueueReorder((id *)&wbAscQueue, (id *)&wbDescQueue, currentCylinder, sweepDirection);
						forceReorder = NO;
					}
					if (!queue_empty(&wbDescQueue)) {
						selectedQueue = &wbDescQueue;
					} else if (!queue_empty(&wbAscQueue)) {
						selectedQueue = &wbAscQueue;
						sweepDirection = 1;
					}
				}
			}
		}

		if (selectedQueue != 0) {
			queue_remove_first(selectedQueue, operation, floppyOperation_t *, link);
			operationType = operation->type;

			switch (operationType) {
			case 0:
				// Read cylinder
				cylinderNumber = operation->cylinder;
				if (*(int *)(*(int *)((char *)self + 0x13c) + cylinderNumber * 0x14) == 3) {
					[self bringCylinderOnline:cylinderNumber isFormatted:(formatPending == NO)];
					currentCylinder = operation->cylinder;
				}
				IOFree(operation, 0x28);
				break;

			case 1:
				// Write cylinder
				cylinderNumber = operation->cylinder;
				if ((*(unsigned char *)(*(int *)((char *)self + 0x13c) + 0x10 + cylinderNumber * 0x14) & 2) != 0) {
					[self commitDirtyCylinder:cylinderNumber];
					currentCylinder = operation->cylinder;
				}
				IOFree(operation, 0x28);
				break;

			case 2:
				// Eject/format - flush all dirty cylinders
				operation->flag2 = 1;
				if (*(int *)((char *)self + 0x148) != 1) {
					geometry = *(id *)((char *)self + 0x14c);
					numCylinders = *(unsigned *)((char *)geometry + 0x0c);
					for (cylinderNumber = numCylinders; cylinderNumber > 0; cylinderNumber--) {
						int offset = (cylinderNumber - 1) * 0x14;
						unsigned char *flagsPtr;

						// If this cylinder was never brought online and the
						// media is still mid-format, bring it online first
						// (formatting it) so its dirty state is known.
						if ((*(int *)(*(int *)((char *)self + 0x13c) + offset) == 3) && formatPending) {
							[self bringCylinderOnline:(cylinderNumber - 1) isFormatted:NO];
							currentCylinder = cylinderNumber - 1;
							flagsPtr = (unsigned char *)(*(int *)((char *)self + 0x13c) + 0x10 + offset);
							if ((*flagsPtr & 1) != 0) {
								operation->flag2 = 0;
							}
						}

						flagsPtr = (unsigned char *)(*(int *)((char *)self + 0x13c) + 0x10 + offset);
						if ((*(int *)(*(int *)((char *)self + 0x13c) + offset) != 3) &&
						    ((*flagsPtr & 2) != 0)) {
							[self commitDirtyCylinder:(cylinderNumber - 1)];
							currentCylinder = cylinderNumber - 1;
							flagsPtr = (unsigned char *)(*(int *)((char *)self + 0x13c) + 0x10 + offset);
							if ((*flagsPtr & 2) != 0) {
								operation->flag2 = 0;
							}
						}
					}
				}
				[operation->lock3 unlockWith:0];
				break;

			case 3:
				// Change capacity/format
				operation->result = 0;

				// Abort all pending requests
				[operationLock lock];
				geometry = *(id *)((char *)self + 0x14c);
				numCylinders = *(unsigned *)((char *)geometry + 0x0c);
				for (cylinderNumber = 0; cylinderNumber < numCylinders; cylinderNumber++) {
					[self abortSubrequestsOnCylinder:cylinderNumber];
				}
				[operationLock unlock];

				// The old geometry is going away - every operation still
				// queued against it (control queue and both sweep pairs)
				// is now meaningless.
				[self clearOperationsOnQueue:(id)&ctlQueue];
				[self clearOperationsOnQueue:(id)&rwAscQueue];
				[self clearOperationsOnQueue:(id)&rwDescQueue];
				[self clearOperationsOnQueue:(id)&wbAscQueue];
				[self clearOperationsOnQueue:(id)&wbDescQueue];

				// Release old cache
				[self releaseCache];

				// Set new capacity
				*(unsigned *)((char *)self + 0x148) = operation->capacity;
				geometry = [IOFloppyDisk geometryOfCapacity:operation->capacity];
				*(id *)((char *)self + 0x14c) = geometry;

				[self setBlockSize:*(unsigned *)((char *)geometry + 0x14)];
				[self setDiskSize:*(unsigned *)((char *)geometry + 4)];
				[self setFormattedInternal:(*(unsigned *)((char *)self + 0x148) != 1)];

				[[self nextLogicalDisk] setFormattedInternal:[self isFormatted]];
				[[self drive] setMediaCapacity:*(unsigned *)((char *)self + 0x148)];

				// Setup new cache
				success = [self setUpCache];
				if (success) {
					[self bringCylinderOnline:0 isFormatted:NO];
					success = ((*(unsigned char *)(*(int *)((char *)self + 0x13c) + 0x10) ^ 1) & 1);
				}

				if (!success) {
					// Revert to unformatted
					*(unsigned *)((char *)self + 0x148) = 1;
					*(id *)((char *)self + 0x14c) = [IOFloppyDisk geometryOfCapacity:1];
					[self setBlockSize:0];
					[self setDiskSize:0];
					[self setFormattedInternal:NO];
					[[self nextLogicalDisk] setFormattedInternal:NO];
					[self releaseCache];
				}

				operation->result = success;

				// Reset scheduler state for the new media: head back at
				// cylinder 0 sweeping up, and formatPending mirrors whether
				// the format actually succeeded (cylinder 0 only has been
				// brought online/formatted above - the rest of the media
				// still needs bringCylinderOnline:isFormatted:NO as each
				// cylinder is first touched).
				readAheadEnabled = (readMode == 0 && *(int *)((char *)self + 0x148) != 1) ? YES : NO;
				currentCylinder = 0;
				sweepDirection = 1;
				formatPending = (BOOL)operation->result;
				forceReorder = NO;

				[operation->lock7 unlockWith:0];
				break;

			case 4:
				// Abort and exit thread
				[operationLock lock];
				geometry = *(id *)((char *)self + 0x14c);
				numCylinders = *(unsigned *)((char *)geometry + 0x0c);
				for (cylinderNumber = 0; cylinderNumber < numCylinders; cylinderNumber++) {
					[self abortSubrequestsOnCylinder:cylinderNumber];
				}
				[operationLock unlock];

				[self clearOperationsOnQueue:(id)&ctlQueue];
				[self clearOperationsOnQueue:(id)&rwAscQueue];
				[self clearOperationsOnQueue:(id)&rwDescQueue];
				[self clearOperationsOnQueue:(id)&wbAscQueue];
				[self clearOperationsOnQueue:(id)&wbDescQueue];

				// Signal completion
				[operation->completionLock unlockWith:0];
				return;

			default:
				// Unreachable: every queue above only ever holds operation
				// types validated during classification. The reference
				// binary has a defensive jump table bounds check here that
				// simply falls through to the top of the loop rather than
				// panicking, so we do the same.
				break;
			}

			[queueLock lock];
			goto drain;
		}

		// Nothing scheduled on any queue - try one speculative read-ahead
		// if enabled, otherwise fall through to the idle wait below.
		if (readAheadEnabled || formatPending) {
			BOOL found;
			unsigned scanCylinder;
			int cylinderInfoBase;

			found = NO;
			cylinderInfoBase = *(int *)((char *)self + 0x13c);
			geometry = *(id *)((char *)self + 0x14c);
			numCylinders = *(unsigned *)((char *)geometry + 0x0c);

			// Scan forward from just past the current head position.
			scanCylinder = currentCylinder + 1;
			while (scanCylinder < numCylinders) {
				if (*(int *)(cylinderInfoBase + scanCylinder * 0x14) == 3) {
					found = YES;
					break;
				}
				scanCylinder++;
			}

			// Nothing ahead: try the current cylinder, then scan backward.
			if (!found) {
				scanCylinder = currentCylinder;
				if (*(int *)(cylinderInfoBase + scanCylinder * 0x14) == 3) {
					found = YES;
				} else {
					while (scanCylinder != 0) {
						scanCylinder--;
						if (*(int *)(cylinderInfoBase + scanCylinder * 0x14) == 3) {
							found = YES;
							break;
						}
					}
				}
			}

			if (found) {
				[self bringCylinderOnline:scanCylinder isFormatted:(formatPending == NO)];
				currentCylinder = scanCylinder;
			} else {
				// No cylinder anywhere still needs loading - stop trying.
				readAheadEnabled = NO;
				formatPending = NO;
			}

			[queueLock lock];
			goto drain;
		}

		// Truly idle: block until new work is queued.
		[queueLock lock];
		if (queue_empty(&self->_operationQueue)) {
			[queueLock unlockWith:0];
			[queueLock lockWhen:1];
		}
		goto drain;
	}
}

@end

/* End of Thread.m */
