/*
 * IOFloppyDisk.h - Floppy disk device class
 *
 * Main class for floppy disk devices with cylinder-based caching
 */

#import "IODriveNEW.h"
#import <driverkit/return.h>
#import <mach/vm_types.h>

// Forward declarations
@class IOFloppyDrive;

// Thread startup function
void _OperationThreadStartup(id self);

/*
 * IOFloppyDisk - Floppy disk device with cylinder caching
 *
 * Extends IODriveNEW to provide cylinder-based caching for floppy disks.
 * Uses a background operation thread for read-ahead and write-behind operations.
 */
@interface IOFloppyDisk : IODriveNEW
{
	// Cache management (offsets 0x134-0x140)
	void *_cacheBuffer;              // offset 0x134: cache data buffer
	unsigned _cacheSize;             // offset 0x138: cache buffer size
	void *_cacheMetadata;            // offset 0x13c: cylinder metadata array
	unsigned _metadataSize;          // offset 0x140: metadata size

	// Synchronization (offset 0x144)
	id _operationLock;               // offset 0x144: lock for cache operations

	// Disk state (offsets 0x148-0x14c)
	int _capacity;                   // offset 0x148: capacity/format state
	id _geometry;                    // offset 0x14c: geometry object

	// Operation queue (offsets 0x150-0x158)
	void *_queueHead;                // offset 0x150: operation queue head
	void *_queueTail;                // offset 0x154: operation queue tail
	id _queueLock;                   // offset 0x158: queue lock

	// Thread management (offset 0x15c)
	int _operationThreadPort;        // offset 0x15c: operation thread port

	// Device info (offset 0x160)
	id _deviceDescription;           // offset 0x160: device description

	// Reserved/additional fields (offsets 0x164-0x16c)
	unsigned _reserved1;             // offset 0x164
	unsigned _reserved2;             // offset 0x168
	unsigned _reserved3;             // offset 0x16c
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
 *   0 (false) - probing not used for floppy disks
 */
+ (BOOL)probe:(id)deviceDescription;

/*
 * Dummy method for IODisk protocol compliance.
 */
- (void)_dummyIODiskPhysicalMethod;

/*
 * Free the disk object and release resources.
 */
- free;

/*
 * Initialize from device description.
 */
- initFromDeviceDescription:(id)deviceDescription
                      drive:(id)drive
                   capacity:(unsigned)capacity
             writeProtected:(BOOL)writeProtected;

/*
 * Asynchronous read operation.
 */
- (IOReturn)readAsyncAt:(unsigned)offset
                 length:(unsigned)length
                 buffer:(void *)buffer
                pending:(void *)pending
                 client:(vm_task_t)client;

/*
 * Synchronous read operation.
 */
- (IOReturn)readAt:(unsigned)offset
            length:(unsigned)length
            buffer:(void *)buffer
      actualLength:(unsigned *)actualLength
            client:(vm_task_t)client;

/*
 * Asynchronous write operation.
 */
- (IOReturn)writeAsyncAt:(unsigned)offset
                  length:(unsigned)length
                  buffer:(void *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client;

/*
 * Synchronous write operation.
 */
- (IOReturn)writeAt:(unsigned)offset
             length:(unsigned)length
             buffer:(void *)buffer
       actualLength:(unsigned *)actualLength
             client:(vm_task_t)client;

@end

// Import category headers
#import "Bsd.h"
#import "Geometry.h"
#import "Request.h"
#import "Support.h"
#import "Thread.h"

/* End of IOFloppyDisk.h */
