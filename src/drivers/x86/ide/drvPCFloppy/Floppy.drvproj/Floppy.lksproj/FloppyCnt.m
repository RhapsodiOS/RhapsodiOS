/*
 * FloppyCnt.m - Floppy Controller class implementation
 *
 * Floppy disk controller class for PC floppy controller hardware
 */

#import "FloppyCnt.h"
#import "IOFloppyDrive.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <kern/lock.h>
#import <mach/mach_interface.h>

/*
 * Forward declaration of the floppy controller thread function
 */
static void _FloppyControllerThread(void *arg);

/*
 * Global controller unit counter
 */
static int _fcUnitNum = 0;

// External CMOS lock variable (referenced in decompiled code)
extern int __xxx;

/*
 * _floppyDriveType - Read floppy drive type from CMOS
 * From decompiled code: reads CMOS to determine drive type.
 *
 * This function reads the CMOS RAM location 0x10 which contains the
 * floppy drive type information. The high nibble contains drive 0 type,
 * and the low nibble contains drive 1 type.
 *
 * Parameters:
 *   driveNumber - Drive number (0 or 1)
 *
 * Returns:
 *   Drive type code:
 *     0 = No drive present
 *     1 = 360KB 5.25" (not supported, returns 0)
 *     2 = 1.2MB 5.25" (not supported, returns 0)
 *     3 = 720KB 3.5"
 *     4 = 1.44MB 3.5"
 *     5+ = Invalid (returns 0)
 *
 * CMOS ports:
 *   0x70 = CMOS address port
 *   0x71 = CMOS data port
 *   Address 0x10 = Floppy drive types
 */
static unsigned char _floppyDriveType(int driveNumber)
{
	unsigned char driveTypeByte;
	unsigned char driveType;

	// Select CMOS register 0x10 (floppy drive types)
	outb(0x70, 0x10);

	// Lock for CMOS access (increment lock counter)
	// LOCK prefix ensures atomic increment
	LOCK();
	__xxx++;
	UNLOCK();

	// Read drive type byte from CMOS
	driveTypeByte = inb(0x71);

	// Extract drive type based on drive number
	if (driveNumber == 0) {
		// Drive 0: high nibble
		driveType = driveTypeByte >> 4;
	} else if (driveNumber == 1) {
		// Drive 1: low nibble
		driveType = driveTypeByte & 0x0F;
	} else {
		// Invalid drive number
		driveType = 0;
	}

	// Check for 5.25" drives (not supported)
	if ((driveType != 0) && (driveType < 3)) {
		IOLog("Warning fd%d: 5 1/4 inch. Drives Not Supported\n", driveNumber);
		driveType = 0;
	}

	// Validate drive type (must be 0-4)
	if (driveType >= 5) {
		driveType = 0;
	}

	return driveType;
}

/*
 * _numFloppyDrives - Get number of floppy drives from CMOS
 * From decompiled code: reads CMOS to determine how many drives are present.
 *
 * This function reads the CMOS RAM location 0x14 which contains the
 * number of floppy drives installed. It validates that the count is
 * reasonable (1-2 drives).
 *
 * Returns:
 *   true (1) if valid number of drives detected (1 or 2)
 *   false (0) if no drives or invalid count
 *
 * CMOS ports:
 *   0x70 = CMOS address port
 *   0x71 = CMOS data port
 *   Address 0x14 = Equipment byte (bits 6-7 = number of floppies - 1)
 */
static BOOL _numFloppyDrives(void)
{
	unsigned char equipmentByte;
	unsigned char numDrives;

	// Select CMOS register 0x14 (equipment byte)
	outb(0x70, 0x14);

	// Lock for CMOS access (increment lock counter)
	LOCK();
	__xxx++;
	UNLOCK();

	// Read equipment byte from CMOS
	equipmentByte = inb(0x71);

	// Extract number of drives from bits 6-7
	// Value in bits 6-7 represents (number of drives - 1)
	// So we need to add 1 to get actual count
	numDrives = (equipmentByte >> 6) + 1;

	// Validate drive count (must be 1, 2, or 3)
	// Note: byte cast of numDrives ensures we're comparing as unsigned
	if ((unsigned char)numDrives < 3) {
		// Additional check: make sure it's not 0xFF (invalid/no drives)
		// equipmentByte >> 6 should not be 0xFF
		return (equipmentByte >> 6) != 0xFF;
	}

	// Invalid count (0 or > 3)
	return NO;
}

@implementation FloppyController

/*
 * Initialize the floppy controller from device description.
 * From decompiled code: sets up controller, registers drives, initializes DMA.
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
	id lock;
	IOReturn result;
	BOOL isEISA;
	IOReturn threadResult;

	// Call superclass initialization
	if ([super initFromDeviceDescription:deviceDescription] == nil) {
		return nil;
	}

	// Enable all interrupts
	if ([self enableAllInterrupts] == NO) {
		return [self free];
	}

	// Allocate and initialize the command lock (NXConditionLock initialized with 0)
	lock = [[NXConditionLock alloc] initWith:0];
	_fcCmdLock = lock;

	if (_fcCmdLock == nil) {
		return [self free];
	}

	// Get the interrupt port
	_fdcInterruptPort = [self interruptPort];

	// Check if EISA is present
	isEISA = [self isEISAPresent];

	if (!isEISA) {
		// Allocate conventional memory for DMA buffer (page-aligned)
		// Uses page_size for both size and alignment
		extern unsigned int page_size;
		_dmaBuffer = _alloc_cnvmem(page_size, page_size);

		if (_dmaBuffer == NULL) {
			return [self free];
		}

		// Clear the DMA buffer
		bzero(_dmaBuffer, page_size);
	}

	// Initialize controller state fields
	_field_13a = 0;
	_field_13b = 0;

	// Set bit 1 of flags (0x02)
	_flags = _flags | 0x02;

	// Clear bit 3 of flags (0xf7 mask clears bit 3)
	_flags = _flags & 0xf7;

	_field_139 = 0;

	// Clear bit 2 of flags (0xfb mask clears bit 2)
	_flags = _flags & 0xfb;

	// Set field_140 to 0xffff
	_field_140 = 0xffff;

	// Clear bit 0 of flags (0xfe mask clears bit 0)
	_flags = _flags & 0xfe;

	// Initialize request queue (circular linked list)
	// _requestQueue points to offset 300 (self + 300)
	// The queue is initialized as a circular list pointing to itself
	_requestQueue = (id)((char *)self + 300);
	_queueHead = (id)((char *)self + 300);

	// Reset the i82077 floppy controller
	result = [self i82077Reset:0];

	if (result != IO_R_SUCCESS) {
		return [self free];
	}

	// Fork the floppy controller thread
	threadResult = _IOForkThread(_FloppyControllerThread, self);

	// Clear bit 4 of flags
	_flags = _flags & 0xef;

	// Set bit 4 if thread creation succeeded
	if (threadResult != 0) {
		_flags = _flags | 0x10;
	}

	// Check if thread was created successfully (bit 4 set)
	if ((_flags & 0x10) != 0) {
		return self;  // Success
	}

	// Thread creation failed
	return [self free];
}

/*
 * Free the controller and all resources.
 * From decompiled code: sends exit request to thread, waits for completion, then frees resources.
 */
- free
{
	RequestNode *exitRequest;
	id exitLock;
	RequestNode *queueHead;
	RequestNode *lastNode;

	// Check if controller thread is running (bit 4 of _flags)
	if ((_flags & 0x10) != 0) {
		// Allocate an exit request node (size 0x10 bytes)
		exitRequest = (RequestNode *)IOMalloc(0x10);

		// Set cmdParams to 0 to signal thread exit
		exitRequest->cmdParams = NULL;

		// Allocate a condition lock initialized with condition 1 (locked)
		exitLock = [[NXConditionLock alloc] initWith:1];
		exitRequest->lock = exitLock;

		// Lock the command lock to add the exit request
		[_fcCmdLock lock];

		// Get the last node in the queue
		lastNode = (RequestNode *)_requestQueue;
		queueHead = (RequestNode *)((char *)self + 300);

		// Add exit request to the end of the queue
		if (queueHead == lastNode) {
			// Queue is empty, point queue head to the new node
			_queueHead = (id)exitRequest;
		} else {
			// Add after the last node
			lastNode->prev = (struct _RequestNode *)exitRequest;
		}

		// Link the exit request into the circular list
		exitRequest->next = (struct _RequestNode *)lastNode;
		exitRequest->prev = (struct _RequestNode *)queueHead;

		// Update _requestQueue to point to the new last node
		_requestQueue = (id)exitRequest;

		// Unlock with condition 1 to wake up the thread
		[_fcCmdLock unlockWith:1];

		// Wait for the thread to process the exit request (condition 0)
		[exitLock lockWhen:0];

		// Unlock and free the exit lock
		[exitLock unlock];
		[exitLock free];

		// Free the exit request node
		IOFree(exitRequest, 0x10);
	}

	// Free the command lock
	[_fcCmdLock free];

	// Call superclass free
	return [super free];
}

/*
 * Execute a command transfer with the floppy controller.
 * From decompiled code: queues request for controller thread, waits for completion.
 *
 * This is the public interface that queues the request to be processed by
 * the controller thread, then waits for completion.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameter structure
 */
- (IOReturn)_fcCmdXfr:(void *)cmdParams
{
	RequestNode *request;
	id requestLock;
	RequestNode *queueHead;
	RequestNode *lastNode;

	// Set return status field in cmdParams to 2 (pending)
	// Offset calculation: (int)&cmdParams->field10_0x3d + 3 = cmdParams + 0x40
	*(unsigned int *)((char *)cmdParams + 0x40) = 2;

	// Allocate a request node (size 0x10 bytes)
	request = (RequestNode *)IOMalloc(0x10);

	if (request == NULL) {
		return IO_R_NO_MEMORY;
	}

	// Set the command parameters
	request->cmdParams = cmdParams;

	// Allocate a condition lock initialized with condition 1 (locked)
	requestLock = [[NXConditionLock alloc] initWith:1];
	request->lock = requestLock;

	if (requestLock == nil) {
		IOFree(request, 0x10);
		return IO_R_NO_MEMORY;
	}

	// Lock the command lock to modify the queue
	[_fcCmdLock lock];

	// Get the last node in the queue
	lastNode = (RequestNode *)_requestQueue;
	queueHead = (RequestNode *)((char *)self + 300);

	// Add request to the end of the queue
	if (queueHead == lastNode) {
		// Queue is empty, point queue head to the new node
		_queueHead = (id)request;
	} else {
		// Add after the last node
		// lastNode->prev = request (offset 0x08)
		lastNode->prev = (struct _RequestNode *)request;
	}

	// Link the request into the circular list
	request->next = (struct _RequestNode *)lastNode;
	request->prev = (struct _RequestNode *)queueHead;

	// Update _requestQueue to point to the new last node
	_requestQueue = (id)request;

	// Unlock with condition 1 to wake up the controller thread
	[_fcCmdLock unlockWith:1];

	// Wait for the controller thread to complete the request (condition 0)
	[requestLock lockWhen:0];

	// Unlock and free the request lock
	[requestLock unlock];
	[requestLock free];

	// Free the request node
	IOFree(request, 0x10);

	return IO_R_SUCCESS;
}

/*
 * Probe for floppy controller hardware.
 * From decompiled code: validates device description, creates controller and drives.
 */
+ (BOOL)probe:(IODeviceDescription *)devDesc
{
	int numPortRanges;
	int numInterrupts;
	FloppyController *controller;
	char name[20];
	int numDrives;
	int driveIndex;
	int driveType;
	id drive;

	// Check that device description has exactly 1 port range
	numPortRanges = [devDesc numPortRanges];
	if (numPortRanges != 1) {
		IOLog("FloppyController: Invalid number of port ranges (%d).\n", numPortRanges);
		return NO;
	}

	// Check that device description has exactly 1 interrupt
	numInterrupts = [devDesc numInterrupts];
	if (numInterrupts != 1) {
		IOLog("FloppyController: Invalid number of interrupts (%d).\n", numInterrupts);
		return NO;
	}

	// Allocate and initialize the controller
	controller = [[self alloc] initFromDeviceDescription:devDesc];

	if (controller == nil) {
		IOLog("FloppyController: Failed to initialize.\n");
		return NO;
	}

	// Set controller properties
	sprintf(name, "fc%d", _fcUnitNum);
	[controller setUnit:_fcUnitNum];
	[controller setName:name];
	[controller setDeviceKind:"FloppyController"];

	// Register the controller device
	[controller registerDevice];

	// Increment global controller unit number
	_fcUnitNum = _fcUnitNum + 1;

	// Probe for floppy drives
	numDrives = _numFloppyDrives();

	for (driveIndex = 0; driveIndex < numDrives; driveIndex++) {
		// Check if drive is present
		driveType = _floppyDriveType(driveIndex);

		if (driveType != 0) {
			// Allocate and initialize the drive
			drive = [[IOFloppyDrive alloc] initFromDeviceDescription:devDesc
			                                              controller:controller
			                                                    unit:driveIndex];

			if (drive == nil) {
				IOLog("FloppyController: Failed to initialize floppy drive %d.\n",
				      driveIndex);
			}
			// Note: drive is retained by the controller, no need to store locally
		}
	}

	return YES;
}

@end

/*
 * Thread category implementation
 */
@implementation FloppyController(Thread)

/*
 * Execute a command transfer in the controller thread.
 * From decompiled code: this is the actual command execution in thread context.
 *
 * This method is called by the controller thread (via _FloppyControllerThread)
 * to execute commands that have been queued via _fcCmdXfr:.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure containing:
 *               - offset 0x08: Command type (1=cmdXfr, 2=eject, 3=motorOn, 4=motorOff, 5=getStatus)
 *               - offset 0x14: Drive number
 *               - offset 0x40: Result status (return value)
 *               - offset 0x44: Error code
 *               - offset 0x48: Transferred bytes
 *               - offset 0x4c: Additional result
 *
 * Returns:
 *   0 always
 */
- (IOReturn)fcCmdXfrExecute:(void *)cmdParams
{
	unsigned int cmdType;
	unsigned char driveNum;
	BOOL needsReset;
	IOReturn result;
	unsigned char *flagsPtr;

	// Lock the command lock
	[_fcCmdLock lock];

	needsReset = YES;

	// Initialize result fields
	*(unsigned int *)((char *)cmdParams + 0x40) = 0xffffffff;  // Result status
	*(unsigned int *)((char *)cmdParams + 0x44) = 0;           // Error code
	*(unsigned int *)((char *)cmdParams + 0x48) = 0;           // Transferred bytes
	*(unsigned int *)((char *)cmdParams + 0x4c) = 0;           // Additional result

	// Check if controller needs reset (bit 0 of _flags)
	// If not set, or reset succeeds, proceed with command
	if (((_flags & 0x01) == 0) ||
	    ([self i82077Reset:0] == IO_R_SUCCESS)) {

		// Get drive number (offset 0x14)
		driveNum = *(unsigned char *)((char *)cmdParams + 0x14);

		// Get command type (offset 0x08)
		cmdType = *(unsigned int *)((char *)cmdParams + 0x08);

		// Check if drive number is valid (< 2)
		if (driveNum < 2) {
			// Execute command based on type
			switch (cmdType) {
			case 1:  // Command transfer (read/write/format)
				[self _doCmdXfr:cmdParams];
				needsReset = ((_flags & 0x01) != 0);
				[self _getDriveStatus:cmdParams];
				break;

			case 2:  // Eject
				[self _doEject:cmdParams];
				needsReset = ((_flags & 0x01) != 0);
				[self _getDriveStatus:cmdParams];
				break;

			case 3:  // Motor on
				[self _getDriveStatus:cmdParams];
				[self _doMotorOn:driveNum];
				*(unsigned int *)((char *)cmdParams + 0x40) = 0;  // Success
				needsReset = NO;
				break;

			case 4:  // Motor off
				[self _getDriveStatus:cmdParams];
				[self _doMotorOff:driveNum];

				// Clear bit 2 of flags at offset 0x4e
				flagsPtr = (unsigned char *)((char *)cmdParams + 0x4e);
				*flagsPtr &= 0xfb;

				needsReset = NO;
				*(unsigned int *)((char *)cmdParams + 0x40) = 0;  // Success
				break;

			case 5:  // Get drive status
				needsReset = NO;
				[self _getDriveStatus:cmdParams];
				*(unsigned int *)((char *)cmdParams + 0x40) = 0;  // Success
				break;

			default:
				// Unknown command type - should not happen
				break;
			}
		} else {
			// Invalid drive number
			*(unsigned int *)((char *)cmdParams + 0x40) = 5;  // IO_R_INVALID_ARG
		}

		// Check for specific error conditions and reset if needed
		result = *(int *)((char *)cmdParams + 0x40);

		if (result == 1) {  // Command timeout
			[self i82077Reset:"Command Timeout"];
		}

		if (result == 10) {  // Bad controller phase
			[self i82077Reset:"Bad Controller Phase"];
		}

		// If controller hung flag is set (bit 0), reset with appropriate message
		if ((_flags & 0x01) != 0) {
			if (needsReset) {
				[self i82077Reset:"Controller hang"];
			} else {
				[self i82077Reset:NULL];
			}
		}

		// If reset requested flag is set (bit 2), reset and clear flag
		if ((_flags & 0x04) != 0) {
			[self i82077Reset:0];
			_flags &= 0xfb;  // Clear bit 2
		}

	} else {
		// Reset failed, store the error result
		*(int *)((char *)cmdParams + 0x40) = result;
	}

	// Unlock the command lock
	[_fcCmdLock unlock];

	return 0;
}

@end

/*
 * Request structure for the controller queue.
 * This structure represents a queued I/O request.
 */
typedef struct _RequestNode {
	void *cmdParams;        // offset 0x00: Command parameters (or 0 for exit)
	id    lock;             // offset 0x04: Lock to signal completion
	struct _RequestNode *prev;  // offset 0x08: Previous node in queue
	struct _RequestNode *next;  // offset 0x0c: Next node in queue
} RequestNode;

/*
 * Floppy controller thread.
 * This thread handles asynchronous I/O requests from a queue.
 *
 * The thread waits on the command lock (condition = 1 means work available),
 * processes all requests in the queue, then waits again.
 */
static void _FloppyControllerThread(void *arg)
{
	FloppyController *controller = (FloppyController *)arg;
	RequestNode *queueHead;
	RequestNode *currentRequest;
	RequestNode *prevNode;
	RequestNode *nextNode;
	void *cmdParams;
	id requestLock;

	// Calculate queue head address (controller + 300)
	queueHead = (RequestNode *)((char *)controller + 300);

	// Main thread loop
	while (1) {
		// Wait for work (lock when condition is 1)
		// Condition 1 means there are requests in the queue
		[controller->_fcCmdLock lockWhen:1];

		// Process all requests in the queue
		currentRequest = (RequestNode *)controller->_queueHead;

		while (currentRequest != queueHead) {
			// Get pointers from the current request
			RequestNode *node = (RequestNode *)controller->_queueHead;
			prevNode = node->prev;
			nextNode = node->next;

			// Remove this request from the queue (unlink it)
			if (queueHead == (RequestNode *)prevNode) {
				// Previous is the queue head, update _requestQueue
				controller->_requestQueue = (id)nextNode;
			} else {
				// Update previous node's next pointer
				((RequestNode *)prevNode)->next = (struct _RequestNode *)nextNode;
			}

			if (queueHead == (RequestNode *)nextNode) {
				// Next is the queue head, update _queueHead
				controller->_queueHead = (id)prevNode;
			} else {
				// Update next node's prev pointer
				((RequestNode *)nextNode)->prev = (struct _RequestNode *)prevNode;
			}

			// Unlock the command lock while processing
			[controller->_fcCmdLock unlock];

			// Get the command parameters and lock from the request
			cmdParams = node->cmdParams;
			requestLock = node->lock;

			// Check if this is an exit request (cmdParams == 0)
			if (cmdParams == NULL) {
				// Exit request - unlock the request lock and exit thread
				[requestLock unlockWith:0];
				_IOExitThread();
				return;  // Thread terminates
			}

			// Execute the command
			[controller fcCmdXfrExecute:cmdParams];

			// Signal completion to the waiting thread
			[requestLock unlockWith:0];

			// Re-acquire the command lock for next iteration
			[controller->_fcCmdLock lock];

			// Get next request
			currentRequest = (RequestNode *)controller->_queueHead;
		}

		// No more requests in queue, unlock with condition 0 (no work)
		[controller->_fcCmdLock unlockWith:0];
	}
}

/* End of FloppyCnt.m */
