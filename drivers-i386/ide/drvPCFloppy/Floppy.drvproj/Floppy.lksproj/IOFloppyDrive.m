/*
 * IOFloppyDrive.m
 * Floppy Drive Implementation - Proper DriverKit Pattern
 */

#import "IOFloppyDrive.h"
#import "FloppyController.h"
#import "IOFloppyDisk.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/IODiskPartition.h>
#import <driverkit/volCheck.h>
#import <kernserv/prototypes.h>
#import <mach/mach.h>
#import <bsd/sys/errno.h>

@implementation IOFloppyDrive

/*
 * Class methods for driver registration
 */

+ (BOOL)probe:(id)deviceDescription
{
    IOLog("IOFloppyDrive: Probing for floppy disk controller\n");

    // Look for floppy controller in device description
    // For now, return NO since we're loaded explicitly
    // A full implementation would:
    // 1. Check for floppy controller hardware
    // 2. Create IOFloppyDrive instances for each unit
    // 3. Return YES if any drives found

    return NO;
}

+ (IODeviceStyle)deviceStyle
{
    // Floppy drives are indirect devices (accessed through controller)
    return IO_IndirectDevice;
}

+ (Protocol **)requiredProtocols
{
    // Floppy drives require a controller that implements FloppyController protocol
    static Protocol *protocols[] = {
        @protocol(IOPhysicalDiskMethods),
        @protocol(IODiskReadingAndWriting),
        nil
    };
    return protocols;
}

/*
 * Initialization
 */

- initWithController:(FloppyController *)controller
                unit:(unsigned int)unit
{
    if ([super init] == nil) {
        return nil;
    }

    _controller = controller;
    _unit = unit;

    // Standard 1.44MB floppy geometry (cached for efficiency)
    _cylinders = 80;
    _heads = 2;
    _sectorsPerTrack = 18;

    // Use IODisk setters to configure the device
    [self setBlockSize:512];
    [self setDiskSize:_cylinders * _heads * _sectorsPerTrack];
    [self setRemovable:YES];
    [self setFormattedInternal:YES];
    [self setWriteProtected:NO];
    [self setIsPhysical:YES];
    [self setDriveName:"Sony Floppy"];
    [self setName:"fd"];
    [self setDeviceKind:"Floppy"];

    // Initialize state
    _isRegistered = NO;
    _mediaPresent = YES;
    _diskChanged = NO;
    _currentCylinder = 0;
    _currentHead = 0;
    _volCheck = nil;

    // Allocate read buffer (one track size)
    _readBufferSize = _sectorsPerTrack * 512;
    _readBuffer = IOMalloc(_readBufferSize);
    if (_readBuffer == NULL) {
        IOLog("IOFloppyDrive: Failed to allocate read buffer\n");
        [self free];
        return nil;
    }

    // Create NXLock for internal state protection
    _lock = [[NXLock alloc] init];
    if (_lock == nil) {
        IOLog("IOFloppyDrive: Failed to create lock\n");
        IOFree(_readBuffer, _readBufferSize);
        [self free];
        return nil;
    }

    // Create NXConditionLock for I/O queue management
    _ioQLock = [[NXConditionLock alloc] initWith:0];
    if (_ioQLock == nil) {
        IOLog("IOFloppyDrive: Failed to create I/O queue lock\n");
        [_lock free];
        IOFree(_readBuffer, _readBufferSize);
        [self free];
        return nil;
    }

    // Initialize I/O queue
    queue_init(&_ioQueue);
    _threadRunning = NO;
    _ioThread = (IOThread)0;

    // Register with controller
    [_controller registerDrive:self atUnit:unit];

    // Create logical disk instance
    _disk = [[IOFloppyDisk alloc] initWithController:controller
                                                unit:unit
                                        diskGeometry:NULL];
    if (_disk != nil) {
        // Connect logical disk to physical disk (IOLogicalDisk pattern)
        [_disk connectToPhysicalDisk:self];
        [_disk setPartitionBase:0];
        [_disk setPhysicalBlockSize:512];

        // Add to logical disk chain
        [self setLogicalDisk:_disk];
    }

    // Recalibrate drive to cylinder 0
    [_controller doRecalibrate:_unit];

    // Set initial ready state
    [self setLastReadyState:IO_Ready];

    // Register device with system
    [self registerDevice];

    IOLog("IOFloppyDrive: Initialized unit %d (C:%d H:%d S:%d)\n",
          unit, _cylinders, _heads, _sectorsPerTrack);

    return self;
}

- registerDevice
{
    id result;

    [_lock lock];

    if (_isRegistered) {
        [_lock unlock];
        IOLog("IOFloppyDrive: Device already registered\n");
        return self;
    }

    [_lock unlock];

    // Call superclass to register with system
    result = [super registerDevice];

    if (result != nil) {
        [_lock lock];
        _isRegistered = YES;
        [_lock unlock];
        IOLog("IOFloppyDrive: Device %d registered as %s\n", _unit, [[self name] cString]);
    } else {
        IOLog("IOFloppyDrive: Failed to register device %d\n", _unit);
    }

    return result;
}

- (void)free
{
    // Stop I/O thread if running
    if (_threadRunning && _ioThread != (IOThread)0) {
        [_lock lock];
        _threadRunning = NO;
        [_lock unlock];

        // Wake up thread so it can exit
        [_ioQLock lock];
        [_ioQLock unlockWith:1];

        IOSleep(100);  // Give thread time to exit
    }

    // Free locks
    if (_ioQLock != nil) {
        [_ioQLock free];
        _ioQLock = nil;
    }

    if (_lock != nil) {
        [_lock free];
        _lock = nil;
    }

    // Free buffer
    if (_readBuffer != NULL) {
        IOFree(_readBuffer, _readBufferSize);
        _readBuffer = NULL;
    }

    // Free logical disk
    if (_disk != nil) {
        [_disk free];
        _disk = nil;
    }

    // Release volume check
    if (_volCheck != nil) {
        [_volCheck release];
        _volCheck = nil;
    }

    [super free];
}

/*
 * IODiskReadingAndWriting protocol implementation
 */

- (IOReturn)readAt:(unsigned int)offset
            length:(unsigned int)length
            buffer:(unsigned char *)buffer
      actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client
{
    unsigned int blockNumber;
    unsigned int cylinder, head, sector;
    unsigned int blockSize;
    IOReturn result;
    ns_time_t startTime, endTime;

    // Check ready state using IODisk's lastReadyState
    if ([self lastReadyState] != IO_Ready) {
        IOLog("IOFloppyDrive: Read failed - disk not ready (state=%d)\n",
              [self lastReadyState]);
        return IO_R_NO_DISK;
    }

    if (length == 0 || buffer == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Get timestamp for statistics
    IOGetTimestamp(&startTime);

    blockSize = [self blockSize];

    // Calculate CHS from byte offset
    blockNumber = offset / blockSize;
    cylinder = blockNumber / (_heads * _sectorsPerTrack);
    head = (blockNumber / _sectorsPerTrack) % _heads;
    sector = (blockNumber % _sectorsPerTrack) + 1;  // 1-based

    if (cylinder >= _cylinders) {
        IOLog("IOFloppyDrive: Read failed - cylinder %d out of range\n", cylinder);
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDrive: Reading C:%d H:%d S:%d length:%d\n",
          cylinder, head, sector, length);

    // Perform read via controller
    result = [_controller doRead:_unit
                        cylinder:cylinder
                            head:head
                          sector:sector
                          buffer:buffer
                          length:length];

    // Get end timestamp
    IOGetTimestamp(&endTime);

    if (result == IO_R_SUCCESS) {
        if (actualLength != NULL) {
            *actualLength = length;
        }

        // Update statistics using IODisk methods
        [self addToBytesRead:length
                   totalTime:(endTime - startTime)
                  latentTime:0];  // Latent time is 0 for synchronous I/O

        IOLog("IOFloppyDrive: Read completed successfully\n");
    } else {
        // Increment error count using IODisk method
        [self incrementReadErrors];

        IOLog("IOFloppyDrive: Read failed with error 0x%x\n", result);

        // Notify volCheck of error if media-related
        if (result == IO_R_NO_DISK || result == IO_R_OFFLINE || result == IO_R_MEDIA) {
            [self diskNotReady];
        }
    }

    return result;
}

- (IOReturn)writeAt:(unsigned int)offset
             length:(unsigned int)length
             buffer:(unsigned char *)buffer
       actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client
{
    unsigned int blockNumber;
    unsigned int cylinder, head, sector;
    unsigned int blockSize;
    IOReturn result;
    ns_time_t startTime, endTime;

    // Check ready state
    if ([self lastReadyState] != IO_Ready) {
        IOLog("IOFloppyDrive: Write failed - disk not ready (state=%d)\n",
              [self lastReadyState]);
        return IO_R_NO_DISK;
    }

    // Check write protection using IODisk method
    if ([self isWriteProtected]) {
        IOLog("IOFloppyDrive: Write failed - disk is write protected\n");
        return IO_R_NOT_WRITABLE;
    }

    if (length == 0 || buffer == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Get timestamp for statistics
    IOGetTimestamp(&startTime);

    blockSize = [self blockSize];

    // Calculate CHS from byte offset
    blockNumber = offset / blockSize;
    cylinder = blockNumber / (_heads * _sectorsPerTrack);
    head = (blockNumber / _sectorsPerTrack) % _heads;
    sector = (blockNumber % _sectorsPerTrack) + 1;  // 1-based

    if (cylinder >= _cylinders) {
        IOLog("IOFloppyDrive: Write failed - cylinder %d out of range\n", cylinder);
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDrive: Writing C:%d H:%d S:%d length:%d\n",
          cylinder, head, sector, length);

    // Perform write via controller
    result = [_controller doWrite:_unit
                         cylinder:cylinder
                             head:head
                           sector:sector
                           buffer:buffer
                           length:length];

    // Get end timestamp
    IOGetTimestamp(&endTime);

    if (result == IO_R_SUCCESS) {
        if (actualLength != NULL) {
            *actualLength = length;
        }

        // Update statistics using IODisk methods
        [self addToBytesWritten:length
                      totalTime:(endTime - startTime)
                     latentTime:0];  // Latent time is 0 for synchronous I/O

        IOLog("IOFloppyDrive: Write completed successfully\n");
    } else {
        // Increment error count using IODisk method
        [self incrementWriteErrors];

        IOLog("IOFloppyDrive: Write failed with error 0x%x\n", result);

        // Notify volCheck of error if media-related
        if (result == IO_R_NO_DISK || result == IO_R_OFFLINE || result == IO_R_MEDIA) {
            [self diskNotReady];
        }
    }

    return result;
}

- (IOReturn)readAsyncAt:(unsigned int)offset
                 length:(unsigned int)length
                 buffer:(unsigned char *)buffer
                pending:(void *)pending
                 client:(vm_task_t)client
{
    unsigned int actualLength;

    // Floppy is synchronous, so just call sync version
    // In a more sophisticated implementation, this would queue the request
    IOReturn result = [self readAt:offset
                            length:length
                            buffer:buffer
                      actualLength:&actualLength
                            client:client];

    // For async, we would normally call a completion routine here
    // but since we're doing sync I/O, just return the result
    return result;
}

- (IOReturn)writeAsyncAt:(unsigned int)offset
                  length:(unsigned int)length
                  buffer:(unsigned char *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client
{
    unsigned int actualLength;

    // Floppy is synchronous, so just call sync version
    IOReturn result = [self writeAt:offset
                             length:length
                             buffer:buffer
                       actualLength:&actualLength
                             client:client];

    return result;
}

/*
 * IOPhysicalDiskMethods protocol implementation
 */

- (IOReturn)updatePhysicalParameters
{
    IOReturn result;
    unsigned char status;

    IOLog("IOFloppyDrive: Updating physical parameters\n");

    // Check for media presence
    result = [_controller getDriveStatus:_unit];
    if (result != IO_R_SUCCESS) {
        IOLog("IOFloppyDrive: No media detected\n");
        [self setLastReadyState:IO_NoDisk];
        [_lock lock];
        _mediaPresent = NO;
        [_lock unlock];
        return IO_R_NO_DISK;
    }

    [_lock lock];
    _mediaPresent = YES;
    [_lock unlock];

    // Get geometry from controller (may vary by media type)
    _cylinders = [_controller cylindersPerDisk];
    _heads = [_controller headsPerCylinder];
    _sectorsPerTrack = [_controller sectorsPerTrack];

    // Update using IODisk setters
    [self setBlockSize:[_controller blockSize]];
    [self setDiskSize:_cylinders * _heads * _sectorsPerTrack];
    [self setFormattedInternal:YES];

    // Check write protection status
    status = [_controller getWriteProtectStatus:_unit];
    [self setWriteProtected:(status != 0)];

    IOLog("IOFloppyDrive: Parameters updated - C:%d H:%d S:%d BS:%d WP:%d\n",
          _cylinders, _heads, _sectorsPerTrack, [self blockSize],
          [self isWriteProtected]);

    return IO_R_SUCCESS;
}

- (void)abortRequest
{
    // Abort any pending I/O requests
    IOLog("IOFloppyDrive: Aborting pending requests\n");

    [_lock lock];

    // In a full implementation, we would walk the I/O queue and abort each request
    // For now, just ensure the queue is empty

    [_lock unlock];
}

- (void)diskBecameReady
{
    IOLog("IOFloppyDrive: Disk became ready on unit %d\n", _unit);

    [_lock lock];
    _mediaPresent = YES;
    _diskChanged = NO;
    [_lock unlock];

    // Update ready state using IODisk method
    [self setLastReadyState:IO_Ready];

    // Update physical parameters from new media
    [self updatePhysicalParameters];
}

- (IOReturn)isDiskReady:(BOOL)prompt
{
    IODiskReadyState state = [self updateReadyState];

    if (state == IO_NoDisk) {
        if (prompt) {
            // Request insertion panel using IODisk method
            [self requestInsertionPanelForDiskType:IO_Floppy];
            return IO_R_NO_DISK;
        }
        return IO_R_NO_DISK;
    }

    if (state == IO_NotReady) {
        return IO_R_NOT_READY;
    }

    return IO_R_SUCCESS;
}

- (IOReturn)ejectPhysical
{
    IOLog("IOFloppyDrive: Ejecting unit %d\n", _unit);

    // Notify volCheck we're ejecting using IODisk method
    [self diskIsEjecting:IO_Floppy];

    // Update state
    [_lock lock];
    _mediaPresent = NO;
    _diskChanged = YES;
    [_lock unlock];

    [self setLastReadyState:IO_Ejecting];

    // Turn off motor (ejects floppy on some drives)
    [_controller doMotorOff:_unit];

    return IO_R_SUCCESS;
}

- (IODiskReadyState)updateReadyState
{
    IOReturn result;
    IODiskReadyState newState;
    IODiskReadyState oldState;

    oldState = [self lastReadyState];

    [_lock lock];

    // Check for media presence via controller
    result = [_controller getDriveStatus:_unit];
    if (result != IO_R_SUCCESS || !_mediaPresent) {
        newState = IO_NoDisk;
        _mediaPresent = NO;
    } else {
        newState = IO_Ready;
        _mediaPresent = YES;
    }

    [_lock unlock];

    // Update last ready state using IODisk method
    [self setLastReadyState:newState];

    if (newState != oldState) {
        IOLog("IOFloppyDrive: Ready state changed from %d to %d\n", oldState, newState);
    }

    return newState;
}

/*
 * Additional floppy-specific operations
 */

- (IOReturn)formatCapacities:(unsigned long long *)capacities
                       count:(unsigned int *)count
{
    if (capacities != NULL && count != NULL && *count > 0) {
        // Return 1.44MB capacity
        capacities[0] = (unsigned long long)_cylinders * _heads *
                       _sectorsPerTrack * [self blockSize];
        *count = 1;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)formatCylinder:(unsigned int)cylinder
                      head:(unsigned int)head
                      data:(void *)data
{
    if (cylinder >= _cylinders || head >= _heads) {
        return IO_R_INVALID_ARG;
    }

    if ([self isWriteProtected]) {
        return IO_R_NOT_WRITABLE;
    }

    IOLog("IOFloppyDrive: Formatting C:%d H:%d\n", cylinder, head);

    return [_controller doFormat:_unit cylinder:cylinder head:head];
}

- (IOReturn)fdRecalibrate
{
    IOLog("IOFloppyDrive: Recalibrating unit %d\n", _unit);

    IOReturn result = [_controller doRecalibrate:_unit];

    if (result == IO_R_SUCCESS) {
        [_lock lock];
        _currentCylinder = 0;
        _currentHead = 0;
        [_lock unlock];
    }

    return result;
}

- (IOReturn)fdSeek:(unsigned int)cylinder
{
    if (cylinder >= _cylinders) {
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDrive: Seeking to cylinder %d\n", cylinder);

    IOReturn result = [_controller doSeek:_unit cylinder:cylinder];

    if (result == IO_R_SUCCESS) {
        [_lock lock];
        _currentCylinder = cylinder;
        [_lock unlock];
    }

    return result;
}

- (IOReturn)fdGetStatus:(unsigned char *)status
{
    if (status == NULL) {
        return IO_R_INVALID_ARG;
    }

    return [_controller getDriveStatus:_unit];
}

- (IOReturn)fdFormat:(unsigned int)cylinder head:(unsigned int)head
{
    return [self formatCylinder:cylinder head:head data:NULL];
}

- (IOReturn)motorOn
{
    IOLog("IOFloppyDrive: Motor on for unit %d\n", _unit);
    return [_controller doMotorOn:_unit];
}

- (IOReturn)motorOff
{
    IOLog("IOFloppyDrive: Motor off for unit %d\n", _unit);
    return [_controller doMotorOff:_unit];
}

- (FloppyController *)controller
{
    return _controller;
}

- (unsigned int)unit
{
    return _unit;
}

/*
 * IODisk method overrides
 */

- (BOOL)needsManualPolling
{
    // Floppy drives need manual polling for media change detection
    return YES;
}

- (const char *)stringFromReturn:(IOReturn)rtn
{
    // Add floppy-specific error strings, then call super
    switch (rtn) {
        case IO_R_NO_DISK:
            return "No Disk";
        case IO_R_NOT_WRITABLE:
            return "Write Protected";
        case IO_R_MEDIA:
            return "Media Error";
        default:
            return [super stringFromReturn:rtn];
    }
}

@end
