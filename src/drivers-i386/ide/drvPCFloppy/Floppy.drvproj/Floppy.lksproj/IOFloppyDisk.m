/*
 * IOFloppyDisk.m - Floppy disk device class
 *
 * Main implementation for floppy disk devices with cylinder-based caching
 */

#import "IOFloppyDisk.h"
#import "FloppyOperation.h"
#import "IOFloppyDrive.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <machkit/NXLock.h>

/*
 * Thread startup function.
 * From decompiled code: entry point for operation thread.
 *
 * This function is the entry point for the disk operation thread. It calls
 * the operationThread method which runs the main operation processing loop,
 * then exits the thread when the operation thread completes.
 *
 * Parameters:
 *   self - The IOFloppyDisk object instance
 */
void OperationThreadStartup(id self)
{
	// Call the operation thread method (runs the main loop)
	[self operationThread];

	// Exit the thread when complete
	IOExitThread();

	return;
}

// External geometry table
// Each entry is 7 words (28 bytes): capacity, diskSize, numCylinders, numHeads,
// numSectors, sectorSize, variableGeometry
extern unsigned int _FloppyGeometry[];

@implementation IOFloppyDisk

/*
 * Class method: Get device style.
 * From decompiled code: returns device style constant.
 *
 * This method indicates that floppy disks are removable media devices.
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
 * From decompiled code: probing is not used for floppy disks.
 *
 * Floppy disks are not probed automatically. Instead, they are
 * instantiated by the FloppyController when drives are detected.
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
 * Dummy method for IODisk protocol compliance.
 * From decompiled code: placeholder method that does nothing.
 */
- (void)dummyIODiskPhysicalMethod
{
	// Intentionally empty - just a placeholder for protocol compliance
	return;
}

- free
{
	id drive;
	floppyOperation_t *operation;
	id completionLock;

	// Get drive and detach BSD interface
	drive = [self drive];
	[self detachBsdDiskInterfaceFromDrive:drive];

	// If operation thread is running, shut it down
	if (_startedThread) {
		// Allocate abort operation (type 4)
		operation = (floppyOperation_t *)IOMalloc(sizeof(floppyOperation_t));
		operation->type = 4;  // Type 4: abort and exit thread

		// Allocate completion lock
		completionLock = [NXConditionLock alloc];
		[completionLock initWith:1];
		operation->completionLock = completionLock;

		// Lock queue and add operation
		[_queueLock lock];

		queue_enter(&_operationQueue, operation, floppyOperation_t *, link);

		// Unlock with status 1 (wake operation thread)
		[_queueLock unlockWith:1];

		// Wait for thread to complete
		[completionLock lockWhen:0];
		[completionLock unlock];
		[completionLock free];

		// Free operation structure
		IOFree(operation, 0x28);
	}

	// Release cache
	[self releaseCache];

	// Free queue lock
	if (_queueLock != nil) {
		[_queueLock free];
	}

	// Free operation lock
	if (_operationLock != nil) {
		[_operationLock free];
	}

	// Call super's free
	return [super free];
}


/*
 * Initialize from device description.
 * From decompiled code: sets up disk instance with geometry and drive.
 */
- initFromDeviceDescription:(id)deviceDescription
                           :(id)drive
                           :(unsigned)capacity
                           :(BOOL)writeProtected
{
	id geometry;
	BOOL isFormatted;
	unsigned driveNumber;
	char diskName[12];
	IOReturn result;
	int threadResult;

	// Call super's init
	if ([super initFromDeviceDescription:deviceDescription] == nil) {
		return [self free];
	}

	// Initialize operation queue (circular list pointing to itself)
	queue_init(&_operationQueue);

	// Clear cache pointers
	_cacheBuffer = NULL;
	_cacheSize = 0;
	_cacheMetadata = NULL;
	_metadataSize = 0;

	// Allocate operation lock (NXSpinLock)
	_operationLock = [NXSpinLock alloc];

	// Set capacity
	_capacity = capacity;

	// Get geometry for this capacity
	geometry = [IOFloppyDisk geometryOfCapacity:capacity];
	_geometry = geometry;

	// Allocate queue lock (NXConditionLock)
	_queueLock = [NXConditionLock alloc];

	// Thread not started yet
	_startedThread = 0;

	// Store device description
	_deviceDescription = deviceDescription;

	// Clear reserved fields
	_reserved1 = 0;
	_reserved2 = 0;
	_reserved3 = 0;

	// Validate allocations
	if (geometry == nil || _operationLock == nil || _queueLock == nil) {
		return [self free];
	}

	// Initialize locks
	[_operationLock init];
	[_queueLock initWith:0];

	// Set drive
	[self setDrive:drive];

	// Set disk properties
	[self setRemovable:YES];
	[self setIsPhysical:YES];
	[self setWriteProtected:writeProtected];

	// Set formatted flag (formatted if capacity != 1)
	isFormatted = (_capacity != 1);
	[self setFormattedInternal:isFormatted];

	// Set block size from geometry
	[self setBlockSize:*(unsigned *)((char *)geometry + 0x14)];

	// Set disk size from geometry
	[self setDiskSize:*(unsigned *)((char *)geometry + 4)];

	// Get drive number and create name
	driveNumber = [IOFloppyDisk driveNumberOfDrive:drive];
	sprintf(diskName, "fdsk%d", driveNumber);

	// Set unit and name
	[self setUnit:driveNumber];
	[self setName:diskName];
	[self setDeviceKind:"Floppy Disk"];

	// Set up cache
	result = [self setUpCache];
	if (!result) {
		return [self free];
	}

	// Attach BSD interface
	result = [self attachBsdDiskInterfaceToDrive:drive];
	if (!result) {
		return [self free];
	}

	// Fork operation thread
	threadResult = IOForkThread((IOThreadFunc)OperationThreadStartup, self);

	// Set the started flag from the fork result
	_startedThread = 0;
	if (threadResult != 0) {
		_startedThread = 1;
	}

	// Register device if thread started successfully
	if (_startedThread) {
		if ([self registerDevice]) {
			return self;
		}
	}

	// Failed - cleanup and return nil
	return [self free];
}


- (IOReturn)readAsyncAt:(unsigned)offset
                 length:(unsigned)length
                 buffer:(unsigned char *)buffer
                pending:(void *)pending
                 client:(vm_task_t)client
{
	id request;
	IOReturn result;

	// Construct request (status pointer = NULL for async)
	request = [self constructRequest:NULL
	                       blockStart:offset
	                        byteCount:length
	                           buffer:buffer
	                        bufferMap:client];

	if (request == nil) {
		return IO_R_NO_MEMORY;
	}

	// Execute the request
	result = [self executeRequest:request];

	// If successful, complete the transfer
	if (result == IO_R_SUCCESS) {
		[self completeTransfer:pending
		           withStatus:IO_R_SUCCESS
		         actualLength:length];
	}

	// Free the request
	[self freeRequest:request];

	return result;
}


- (IOReturn)readAt:(unsigned)offset
            length:(unsigned)length
            buffer:(unsigned char *)buffer
      actualLength:(unsigned *)actualLength
            client:(vm_task_t)client
{
	id request;
	IOReturn result;

	// Construct request (status pointer = NULL)
	request = [self constructRequest:NULL
	                       blockStart:offset
	                        byteCount:length
	                           buffer:buffer
	                        bufferMap:client];

	if (request == nil) {
		return IO_R_NO_MEMORY;
	}

	// Execute the request
	result = [self executeRequest:request];

	// If successful, set actual length
	if (result == IO_R_SUCCESS) {
		if (actualLength != NULL) {
			*actualLength = length;
		}
	}

	// Free the request
	[self freeRequest:request];

	return result;
}

- (IOReturn)writeAsyncAt:(unsigned)offset
                  length:(unsigned)length
                  buffer:(unsigned char *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client
{
	id drive;
	unsigned writeCapacities;
	id request;
	IOReturn result;

	// Get drive and check write capabilities
	drive = [self drive];
	writeCapacities = [drive writeCapacities];

	// Check if current capacity is writable
	if ((_capacity & writeCapacities) == 0) {
		// Capacity not supported for writing
		return IO_R_UNSUPPORTED;
	}

	// Check write protection
	if ([self isWriteProtected]) {
		return IO_R_NOT_WRITABLE;
	}

	// Construct request (status pointer = (IOReturn *)1 for write flag)
	request = [self constructRequest:(IOReturn *)1
	                       blockStart:offset
	                        byteCount:length
	                           buffer:buffer
	                        bufferMap:client];

	if (request == nil) {
		return IO_R_NO_MEMORY;
	}

	// Execute the request
	result = [self executeRequest:request];

	// If successful, complete the transfer
	if (result == IO_R_SUCCESS) {
		[self completeTransfer:pending
		           withStatus:IO_R_SUCCESS
		         actualLength:length];
	}

	// Free the request
	[self freeRequest:request];

	return result;
}


- (IOReturn)writeAt:(unsigned)offset
             length:(unsigned)length
             buffer:(unsigned char *)buffer
       actualLength:(unsigned *)actualLength
             client:(vm_task_t)client
{
	id drive;
	unsigned writeCapacities;
	id request;
	IOReturn result;

	// Get drive and check write capabilities
	drive = [self drive];
	writeCapacities = [drive writeCapacities];

	// Check if current capacity is writable
	if ((_capacity & writeCapacities) == 0) {
		// Capacity not supported for writing
		return IO_R_UNSUPPORTED;
	}

	// Check write protection
	if ([self isWriteProtected]) {
		return IO_R_NOT_WRITABLE;
	}

	// Construct request (status pointer = (IOReturn *)1 for write flag)
	request = [self constructRequest:(IOReturn *)1
	                       blockStart:offset
	                        byteCount:length
	                           buffer:buffer
	                        bufferMap:client];

	if (request == nil) {
		return IO_R_NO_MEMORY;
	}

	// Execute the request
	result = [self executeRequest:request];

	// If successful, set actual length
	if (result == IO_R_SUCCESS) {
		if (actualLength != NULL) {
			*actualLength = length;
		}
	}

	// Free the request
	[self freeRequest:request];

	return result;
}

@end

/* End of IOFloppyDisk.m */
