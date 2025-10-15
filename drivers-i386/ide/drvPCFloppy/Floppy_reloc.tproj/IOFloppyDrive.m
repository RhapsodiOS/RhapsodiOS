/*
 * IOFloppyDrive.m
 * Floppy Drive Interface
 */

#import "IOFloppyDrive.h"
#import "FloppyController.h"
#import "IOFloppyDisk.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/IODiskPartition.h>
#import <mach/mach.h>
#import <bsd/sys/errno.h>

@implementation IOFloppyDrive

- initWithController:(FloppyController *)controller
                unit:(unsigned int)unit
{
    if ([super init] == nil) {
        return nil;
    }

    _controller = controller;
    _unit = unit;

    // Standard 1.44MB floppy geometry
    _cylinders = 80;
    _heads = 2;
    _sectorsPerTrack = 18;
    _blockSize = 512;

    // Initialize state
    _isReady = NO;
    _mediaPresent = YES;  // Assume media present initially
    _writeProtected = NO;
    _lastReadState = 0;

    // Allocate read buffer
    _readBufferSize = 18 * 512;  // One track
    _readBuffer = IOMalloc(_readBufferSize);
    if (_readBuffer == NULL) {
        [self free];
        return nil;
    }

    // Register with controller
    [_controller registerDrive:self atUnit:unit];

    // Create disk instance
    _disk = [[IOFloppyDisk alloc] initWithController:controller
                                                unit:unit
                                        diskGeometry:NULL];
    if (_disk != nil) {
        [_disk setDrive:self];
    }

    // Recalibrate drive
    [_controller doRecalibrate:_unit];

    _isReady = YES;

    [self setName:"FloppyDrive"];
    [self setDeviceKind:"Floppy"];
    [self setRemovable:YES];

    return self;
}

- (void)free
{
    if (_readBuffer != NULL) {
        IOFree(_readBuffer, _readBufferSize);
    }
    if (_disk != nil) {
        [_disk free];
    }
    return [super free];
}

- (IOReturn)readAt:(unsigned int)offset
            length:(unsigned int)length
            buffer:(void *)buffer
        actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client
{
    unsigned int blockNumber;
    unsigned int cylinder, head, sector;
    IOReturn result;

    if (!_isReady || !_mediaPresent) {
        return IO_R_NO_MEDIA;
    }

    if (length == 0 || buffer == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Calculate CHS from offset
    blockNumber = offset / _blockSize;
    cylinder = blockNumber / (_heads * _sectorsPerTrack);
    head = (blockNumber / _sectorsPerTrack) % _heads;
    sector = (blockNumber % _sectorsPerTrack) + 1;

    if (cylinder >= _cylinders) {
        return IO_R_INVALID_ARG;
    }

    // Read from controller
    result = [_controller doRead:_unit
                        cylinder:cylinder
                            head:head
                          sector:sector
                          buffer:buffer
                          length:length];

    if (result == IO_R_SUCCESS && actualLength != NULL) {
        *actualLength = length;
    }

    return result;
}

- (IOReturn)writeAt:(unsigned int)offset
             length:(unsigned int)length
             buffer:(void *)buffer
         actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client
{
    unsigned int blockNumber;
    unsigned int cylinder, head, sector;
    IOReturn result;

    if (!_isReady || !_mediaPresent) {
        return IO_R_NO_MEDIA;
    }

    if (_writeProtected) {
        return IO_R_NOT_WRITABLE;
    }

    if (length == 0 || buffer == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Calculate CHS from offset
    blockNumber = offset / _blockSize;
    cylinder = blockNumber / (_heads * _sectorsPerTrack);
    head = (blockNumber / _sectorsPerTrack) % _heads;
    sector = (blockNumber % _sectorsPerTrack) + 1;

    if (cylinder >= _cylinders) {
        return IO_R_INVALID_ARG;
    }

    // Write to controller
    result = [_controller doWrite:_unit
                         cylinder:cylinder
                             head:head
                           sector:sector
                           buffer:buffer
                           length:length];

    if (result == IO_R_SUCCESS && actualLength != NULL) {
        *actualLength = length;
    }

    return result;
}

- (IOReturn)readAsyncAt:(unsigned int)offset
                 length:(unsigned int)length
                 buffer:(void *)buffer
                 pending:(void *)pending
                 client:(vm_task_t)client
{
    unsigned int actualLength;
    return [self readAt:offset
                 length:length
                 buffer:buffer
             actualLength:&actualLength
                 client:client];
}

- (IOReturn)writeAsyncAt:(unsigned int)offset
                  length:(unsigned int)length
                  buffer:(void *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client
{
    unsigned int actualLength;
    return [self writeAt:offset
                  length:length
                  buffer:buffer
              actualLength:&actualLength
                  client:client];
}

- (IOReturn)ejectPhysical
{
    // Turn off motor
    [_controller doMotorOff:_unit];
    return IO_R_SUCCESS;
}

- (IOReturn)formatCapacities:(unsigned long long *)capacities
                       count:(unsigned int *)count
{
    if (capacities != NULL && count != NULL && *count > 0) {
        // 1.44MB capacity
        capacities[0] = (unsigned long long)_cylinders * _heads * _sectorsPerTrack * _blockSize;
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

    if (_writeProtected) {
        return IO_R_NOT_WRITABLE;
    }

    return [_controller doFormat:_unit cylinder:cylinder head:head];
}

- (IOReturn)isDiskReady:(BOOL *)ready
{
    if (ready != NULL) {
        *ready = _isReady && _mediaPresent;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)checkForMedia
{
    IOReturn result;

    result = [_controller getDriveStatus:_unit];
    if (result == IO_R_SUCCESS) {
        _mediaPresent = YES;
    } else {
        _mediaPresent = NO;
    }

    return result;
}

- (IOReturn)updateReadyState
{
    [self checkForMedia];
    _isReady = _mediaPresent;
    return IO_R_SUCCESS;
}

- (IOReturn)incrementReadRetries
{
    _readRetries++;
    return IO_R_SUCCESS;
}

- (IOReturn)incrementOtherRetries
{
    _otherRetries++;
    return IO_R_SUCCESS;
}

- (IOReturn)incrementWriteRetries
{
    _writeRetries++;
    return IO_R_SUCCESS;
}

- (IOReturn)getIntValues:(unsigned int *)values
             forParameter:(IOParameterName)parameter
                    count:(unsigned int *)count
{
    return IO_R_UNSUPPORTED;
}

- (IOReturn)volCheckSupport
{
    return IO_R_SUCCESS;
}

- (IOReturn)volCheckUnregister
{
    return IO_R_SUCCESS;
}

- (IOReturn)volCheckRegister
{
    return IO_R_SUCCESS;
}

- (void)setLastReadState:(unsigned int)state
{
    _lastReadState = state;
}

- (FloppyController *)controller
{
    return _controller;
}

- (IOReturn)pollMedia
{
    return [self checkForMedia];
}

- (IOReturn)setMediaBad
{
    _mediaPresent = NO;
    _isReady = NO;
    return IO_R_SUCCESS;
}

- (IOReturn)canPollingBeExpensively
{
    return IO_R_SUCCESS;
}

- (IOReturn)updatePhysicalParameters
{
    // Update geometry from controller
    _cylinders = [_controller cylindersPerDisk];
    _heads = [_controller headsPerCylinder];
    _sectorsPerTrack = [_controller sectorsPerTrack];
    _blockSize = [_controller blockSize];
    return IO_R_SUCCESS;
}

- (IOReturn)getFormatted
{
    return _isReady ? IO_R_SUCCESS : IO_R_NO_MEDIA;
}

- (IOReturn)setFormatted:(BOOL)formatted
{
    // Set format status
    return IO_R_SUCCESS;
}

- (IOReturn)isFormatted
{
    return _isReady ? IO_R_SUCCESS : IO_R_NO_MEDIA;
}

- (IOReturn)setWriteProtected:(BOOL)writeProtected
{
    _writeProtected = writeProtected;
    return IO_R_SUCCESS;
}

- (IOReturn)rwCommon:(void *)block client:(vm_task_t)client
{
    // Common read/write handling
    return IO_R_SUCCESS;
}

- (IOReturn)setBlockCnt:(unsigned int)blockCnt
{
    // Set block count
    return IO_R_SUCCESS;
}

- (IOReturn)blockCount:(unsigned int *)count
{
    if (count != NULL) {
        *count = _cylinders * _heads * _sectorsPerTrack;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)fdRecal
{
    return [_controller doRecalibrate:_unit];
}

- (IOReturn)fdSeek:(unsigned int)head
{
    // Seek to specific head/cylinder
    return IO_R_SUCCESS;
}

- (IOReturn)fdOctlValues:(unsigned int *)values
            forParameter:(IOParameterName)parameter
                   count:(unsigned int *)count
{
    return IO_R_UNSUPPORTED;
}

- (IOReturn)rwBlockCount:(void *)block
{
    return IO_R_SUCCESS;
}

- (IOReturn)fdBufferCount:(unsigned int)buffer
            actualLength:(unsigned int *)actualLength
                  client:(vm_task_t)client
{
    return IO_R_SUCCESS;
}

- (IOReturn)updateStateInt
{
    return [self updateReadyState];
}

- (IOReturn)formatInfo
{
    // Return format information
    return IO_R_SUCCESS;
}

- (IOReturn)allocateDmaBuffer:(unsigned int)size
{
    // Allocate DMA buffer for transfers
    if (_readBuffer == NULL || _readBufferSize < size) {
        if (_readBuffer != NULL) {
            IOFree(_readBuffer, _readBufferSize);
        }
        _readBuffer = IOMalloc(size);
        if (_readBuffer == NULL) {
            return IO_R_NO_MEMORY;
        }
        _readBufferSize = size;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)motorCheck:(BOOL)on autoCheck:(BOOL)autoCheck
{
    // Check and control motor state
    if (on) {
        return [_controller doMotorOn:_unit];
    } else {
        return [_controller doMotorOff:_unit];
    }
}

- (IOReturn)setDensity:(unsigned int)density
{
    // Set recording density
    return IO_R_SUCCESS;
}

- (IOReturn)getDensity:(unsigned int *)density
{
    // Get current recording density
    if (density != NULL) {
        *density = 0; // Standard density
    }
    return IO_R_SUCCESS;
}

- (IOReturn)execRequest:(void *)request
{
    // Execute I/O request
    return IO_R_SUCCESS;
}

- (IOReturn)blockCnt:(unsigned int *)count
{
    return [self blockCount:count];
}

- (const char *)driverName
{
    return "IOFloppyDrive";
}

// IOPhysicalDiskMethods protocol implementation
- (void)abortRequest
{
    // Abort pending I/O requests
}

- (void)diskBecameReady
{
    // Handle disk becoming ready
    _isReady = YES;
    _mediaPresent = YES;
}

- (IODiskReadyState)updateReadyState
{
    // Update and return current ready state
    [self checkForMedia];

    if (!_mediaPresent) {
        return IO_NoDisk;
    }

    if (!_isReady) {
        return IO_NotReady;
    }

    return IO_Ready;
}

- (BOOL)needsManualPolling
{
    // Floppy drives need manual polling for media changes
    return YES;
}

- (IOReturn)isDiskReady:(BOOL)prompt
{
    IODiskReadyState state = [self updateReadyState];

    if (state == IO_NoDisk) {
        if (prompt) {
            // Could request insertion panel here
            return IO_R_NO_DISK;
        }
        return IO_R_NO_DISK;
    }

    return IO_R_SUCCESS;
}

// Additional IODisk methods
- (const char *)stringFromReturn:(IOReturn)rtn
{
    // Convert IOReturn to string
    switch (rtn) {
        case IO_R_SUCCESS: return "Success";
        case IO_R_NO_MEDIA: return "No Media";
        case IO_R_INVALID_ARG: return "Invalid Argument";
        case IO_R_NOT_WRITABLE: return "Not Writable";
        case IO_R_NO_DISK: return "No Disk";
        default: return "Unknown Error";
    }
}

- (IOReturn)errnoFromReturn:(IOReturn)rtn
{
    // Convert IOReturn to errno
    switch (rtn) {
        case IO_R_SUCCESS: return 0;
        case IO_R_NO_MEMORY: return ENOMEM;
        case IO_R_INVALID_ARG: return EINVAL;
        case IO_R_NO_MEDIA: return ENXIO;
        case IO_R_NO_DISK: return ENXIO;
        default: return EIO;
    }
}

// Floppy-specific operations
- (IOReturn)fdGetStatus:(unsigned char *)status
{
    // Get floppy drive status
    return [_controller getDriveStatus:_unit];
}

- (IOReturn)fdWrite:(unsigned int)block buffer:(void *)buffer length:(unsigned int)length
{
    // Write block to floppy
    unsigned int cylinder, head, sector;

    cylinder = block / (_heads * _sectorsPerTrack);
    head = (block / _sectorsPerTrack) % _heads;
    sector = (block % _sectorsPerTrack) + 1;

    return [_controller doWrite:_unit
                       cylinder:cylinder
                           head:head
                         sector:sector
                         buffer:buffer
                         length:length];
}

- (IOReturn)fdRead:(unsigned int)block buffer:(void *)buffer length:(unsigned int)length
{
    // Read block from floppy
    unsigned int cylinder, head, sector;

    cylinder = block / (_heads * _sectorsPerTrack);
    head = (block / _sectorsPerTrack) % _heads;
    sector = (block % _sectorsPerTrack) + 1;

    return [_controller doRead:_unit
                      cylinder:cylinder
                          head:head
                        sector:sector
                        buffer:buffer
                        length:length];
}

- (IOReturn)fdFormat:(unsigned int)cylinder head:(unsigned int)head
{
    // Format track on floppy
    return [_controller doFormat:_unit cylinder:cylinder head:head];
}

@end
