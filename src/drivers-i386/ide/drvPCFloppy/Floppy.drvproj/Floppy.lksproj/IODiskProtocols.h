/*
 * IODiskProtocols.h - Protocols required by IODiskPartitionNEW's
 * +requiredProtocols hook.
 *
 * Recovered from the reference binary's __OBJC,__protocol section:
 * IODiskPartitionExported, IODiskReadingAndWriting, IODiskPhysicalNEW
 * and IODriveVolCheckSupport.
 */

#import <driverkit/return.h>
#import <bsd/dev/disk_label.h>

/*
 * Public NXDisk methods. Adopted by IODiskPartitionNEW.
 */
@protocol IODiskPartitionExported

- (void)setRawDeviceOpen : (BOOL)openFlag;
- (BOOL)isRawDeviceOpen;
- (void)setBlockDeviceOpen : (BOOL)openFlag;
- (BOOL)isBlockDeviceOpen;
- (IOReturn)writeLabel : (in disk_label_t *)label_p;
- (IOReturn)readLabel : (out disk_label_t *)label_p;

@end

/*
 * Standard disk read/write protocol. Offsets are in blocks, lengths are
 * in bytes. Adopted by IOLogicalDiskNEW and IOFloppyDisk.
 */
@protocol IODiskReadingAndWriting

#ifdef KERNEL

- (IOReturn)writeAsyncAt : (unsigned)offset
		    length : (unsigned)length
		    buffer : (unsigned char *)buffer
		   pending : (void *)pending
		    client : (vm_task_t)client;

- (IOReturn)writeAt : (unsigned)offset
	      length : (unsigned)length
	      buffer : (unsigned char *)buffer
        actualLength : (unsigned *)actualLength
	      client : (vm_task_t)client;

- (IOReturn)readAsyncAt : (unsigned)offset
		   length : (unsigned)length
		   buffer : (unsigned char *)buffer
		  pending : (void *)pending
		   client : (vm_task_t)client;

- (IOReturn)readAt : (unsigned)offset
	     length : (unsigned)length
	     buffer : (unsigned char *)buffer
       actualLength : (unsigned *)actualLength
	     client : (vm_task_t)client;

#endif KERNEL

@end

/*
 * Physical-disk marker protocol. Adopted by IOFloppyDisk.
 */
@protocol IODiskPhysicalNEW

- (void)dummyIODiskPhysicalMethod;

@end

/*
 * Volume-check callbacks. Adopted by IOFloppyDrive(volCheckSupport).
 */
@protocol IODriveVolCheckSupport

- (void)diskBecameReady;
- (void)abortRequest;
- (int)updateReadyState;
- (IOReturn)updatePhysicalParameters;
- (id)nextLogicalDisk;
- (BOOL)needsManualPolling;
- (BOOL)isWriteProtected;
- (BOOL)isFormatted;
- (BOOL)isRemovable;
- (BOOL)isPhysical;

@end

/* End of IODiskProtocols.h */
