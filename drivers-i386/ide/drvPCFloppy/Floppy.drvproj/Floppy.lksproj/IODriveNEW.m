/*
 * IODriveNEW.m
 * Stub class implementation for IODrive compatibility
 */

#import "IODriveNEW.h"
#import <driverkit/generalFuncs.h>

@implementation IODriveNEW

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    // Never probe - this is just a stub class for compatibility
    return NO;
}

- init
{
    if ([super init] == nil) {
        return nil;
    }

    // Initialize drive state
    _ready = NO;
    _ejectable = YES;  // Floppies are ejectable
    _writeProtected = NO;

    // Initialize statistics
    _openRetries = 0;
    _nonRetries = 0;
    _nonErrors = 0;

    // Initialize buffer management
    _buffer = NULL;
    _bufferSize = 0;

    // Initialize disk table
    _disktab = NULL;

    // Initialize associated disk
    _disk = nil;

    return self;
}

- (void)free
{
    // Free buffer if allocated
    if (_buffer != NULL) {
        IOMfree(_buffer, _bufferSize);
        _buffer = NULL;
        _bufferSize = 0;
    }

    // Free disk table if allocated
    if (_disktab != NULL) {
        IOMfree(_disktab, sizeof(void *));
        _disktab = NULL;
    }

    return [super free];
}

- (unsigned int)addToBuffer:(const void *)listName
{
    unsigned int newSize;
    void *newBuffer;

    if (listName == NULL) {
        IOLog("IODriveNEW: addToBuffer called with NULL listName\n");
        return 0;
    }

    // Calculate new buffer size (add space for new entry)
    newSize = _bufferSize + 256;  // Add 256 bytes for new entry

    // Allocate or reallocate buffer
    if (_buffer == NULL) {
        newBuffer = IOMalloc(newSize);
    } else {
        newBuffer = IOMalloc(newSize);
        if (newBuffer != NULL && _buffer != NULL) {
            bcopy(_buffer, newBuffer, _bufferSize);
            IOMfree(_buffer, _bufferSize);
        }
    }

    if (newBuffer == NULL) {
        IOLog("IODriveNEW: Failed to allocate buffer\n");
        return 0;
    }

    _buffer = newBuffer;
    _bufferSize = newSize;

    IOLog("IODriveNEW: Added entry to buffer, new size = %d\n", newSize);

    return newSize;
}

- (id)addToDisktab:(const void *)listName
{
    if (listName == NULL) {
        IOLog("IODriveNEW: addToDisktab called with NULL listName\n");
        return nil;
    }

    // Allocate disk table if not already allocated
    if (_disktab == NULL) {
        _disktab = IOMalloc(sizeof(void *) * 16);  // Space for 16 entries
        if (_disktab == NULL) {
            IOLog("IODriveNEW: Failed to allocate disk table\n");
            return nil;
        }
    }

    IOLog("IODriveNEW: Added entry to disk table\n");

    return self;
}

- (BOOL)isDiskReady:(id)disk
{
    if (disk == nil) {
        IOLog("IODriveNEW: isDiskReady called with nil disk\n");
        return NO;
    }

    // Store the disk reference
    _disk = disk;

    // For floppy, we check if the disk is ready
    // This would typically involve checking hardware status
    IOLog("IODriveNEW: Checking if disk %s is ready\n", [[disk name] cString]);

    return _ready;
}

- (IOReturn)rwReadInt:(unsigned int)offset
               length:(unsigned int)length
               buffer:(void *)buffer
               client:(vm_task_t)client
{
    IOReturn status;

    // Validate parameters
    if (buffer == NULL || length == 0) {
        IOLog("IODriveNEW: rwReadInt invalid parameters\n");
        return IO_R_INVALID_ARG;
    }

    // Check if drive is ready
    if (!_ready) {
        IOLog("IODriveNEW: rwReadInt failed - drive not ready\n");
        return IO_R_NO_DEVICE;
    }

    // Delegate to disk object if available
    if (_disk != nil && [_disk respondsToSelector:@selector(readAt:length:buffer:actualLength:client:)]) {
        status = [_disk readAt:offset
                        length:length
                        buffer:buffer
                  actualLength:NULL
                        client:client];

        if (status != IO_R_SUCCESS) {
            _nonErrors++;
            IOLog("IODriveNEW: rwReadInt failed, status=0x%x\n", status);
        }

        return status;
    } else {
        IOLog("IODriveNEW: No disk available for rwReadInt\n");
        return IO_R_UNSUPPORTED;
    }
}

- (IOReturn)incrementOpenRetries
{
    _openRetries++;
    IOLog("IODriveNEW: Open retries incremented to %d\n", _openRetries);
    return IO_R_SUCCESS;
}

- (IOReturn)incrementNonRetries
{
    _nonRetries++;
    IOLog("IODriveNEW: Non-retries incremented to %d\n", _nonRetries);
    return IO_R_SUCCESS;
}

- (IOReturn)getIncrementNonErrors
{
    // Return the current count of non-errors
    return _nonErrors;
}

- (IOReturn)getIncrementNonRetries
{
    // Return the current count of non-retries
    return _nonRetries;
}

// Additional drive management methods

- (IOReturn)setDriveReady:(BOOL)ready
{
    _ready = ready;

    if (ready) {
        IOLog("IODriveNEW: Drive is ready\n");
    } else {
        IOLog("IODriveNEW: Drive is not ready\n");
    }

    return IO_R_SUCCESS;
}

- (BOOL)isDriveReady
{
    return _ready;
}

- (IOReturn)setEjectable:(BOOL)ejectable
{
    _ejectable = ejectable;

    if (ejectable) {
        IOLog("IODriveNEW: Drive is ejectable\n");
    } else {
        IOLog("IODriveNEW: Drive is not ejectable\n");
    }

    return IO_R_SUCCESS;
}

- (BOOL)isEjectable
{
    return _ejectable;
}

- (IOReturn)setWriteProtected:(BOOL)protect
{
    _writeProtected = protect;

    if (protect) {
        IOLog("IODriveNEW: Drive is write protected\n");
    } else {
        IOLog("IODriveNEW: Drive is not write protected\n");
    }

    return IO_R_SUCCESS;
}

- (BOOL)isWriteProtected
{
    return _writeProtected;
}

- (IOReturn)setDisk:(id)disk
{
    _disk = disk;

    if (disk != nil) {
        IOLog("IODriveNEW: Disk set to %s\n", [[disk name] cString]);
    } else {
        IOLog("IODriveNEW: Disk cleared\n");
    }

    return IO_R_SUCCESS;
}

- (id)disk
{
    return _disk;
}

- (IOReturn)resetStatistics
{
    _openRetries = 0;
    _nonRetries = 0;
    _nonErrors = 0;

    IOLog("IODriveNEW: Statistics reset\n");

    return IO_R_SUCCESS;
}

- (unsigned int)openRetries
{
    return _openRetries;
}

- (unsigned int)nonRetries
{
    return _nonRetries;
}

- (unsigned int)nonErrors
{
    return _nonErrors;
}

@end
