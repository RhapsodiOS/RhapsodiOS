/*
 * IOFloppyDisk.h - Floppy disk device class
 *
 * Main class for floppy disk devices with cylinder-based caching
 */

#import "IODiskNew.h"
#import <driverkit/return.h>
#import <kernserv/queue.h>
#import "FloppyVm.h"
#import "IODiskProtocols.h"

// Forward declarations
@class IOFloppyDrive;

// Thread startup function
void OperationThreadStartup(id self);

/*
 * IOFloppyDisk - Floppy disk device with cylinder caching
 *
 * Extends IODiskNEW to provide cylinder-based caching for floppy disks.
 * Uses a background operation thread for read-ahead and write-behind operations.
 *
 * IODiskNEW, not IODriveNEW: the reference names IODiskNEW, this class
 * sends only IODiskNEW methods, and IODiskNEW is 308 bytes where
 * IODriveNEW is 352 -- which is what puts the ivars below at the 0x134
 * offsets their own comments already claim.
 */
@interface IOFloppyDisk : IODiskNEW <IODiskReadingAndWriting, IODiskPhysicalNEW>
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
	queue_head_t _operationQueue;    // offset 0x150: next, prev
	id _queueLock;                   // offset 0x158: queue lock

	// Thread management (offset 0x15c)
	// The reference declares this as a one-bit field, b1, and the code
	// only ever tests, sets and clears bit 0 of it.
	unsigned _startedThread:1;       // offset 0x15c: operation thread running

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
- (void)dummyIODiskPhysicalMethod;

/*
 * Free the disk object and release resources.
 */
- free;

/*
 * Initialize from device description.
 */
- initFromDeviceDescription:(id)deviceDescription
                           :(id)drive
                           :(unsigned)capacity
                           :(BOOL)writeProtected;

/*
 * Asynchronous read operation.
 */
- (IOReturn)readAsyncAt:(unsigned)offset
                 length:(unsigned)length
                 buffer:(unsigned char *)buffer
                pending:(void *)pending
                 client:(vm_task_t)client;

/*
 * Synchronous read operation.
 */
- (IOReturn)readAt:(unsigned)offset
            length:(unsigned)length
            buffer:(unsigned char *)buffer
      actualLength:(unsigned *)actualLength
            client:(vm_task_t)client;

/*
 * Asynchronous write operation.
 */
- (IOReturn)writeAsyncAt:(unsigned)offset
                  length:(unsigned)length
                  buffer:(unsigned char *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client;

/*
 * Synchronous write operation.
 */
- (IOReturn)writeAt:(unsigned)offset
             length:(unsigned)length
             buffer:(unsigned char *)buffer
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
