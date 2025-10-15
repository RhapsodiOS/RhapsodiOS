/*
 * IODriveNEW.h
 * Stub class for IODrive compatibility
 */

#import <driverkit/IODrive.h>

/*
 * IODriveNEW - Compatibility stub class
 * This class provides a compatibility shim for the floppy driver.
 * It inherits all behavior from IODrive and never probes hardware.
 */
@interface IODriveNEW : IODrive
{
    // Drive state
    BOOL _ready;
    BOOL _ejectable;
    BOOL _writeProtected;

    // Statistics
    unsigned int _openRetries;
    unsigned int _nonRetries;
    unsigned int _nonErrors;

    // Buffer management
    void *_buffer;
    unsigned int _bufferSize;

    // Disk table
    void *_disktab;

    // Associated disk
    id _disk;
}

// Drive address methods
- (unsigned int)addToBuffer:(const void *)listName;
- (id)addToDisktab:(const void *)listName;
- (BOOL)isDiskReady:(id)disk;

// Read/write operations
- (IOReturn)rwReadInt:(unsigned int)offset
               length:(unsigned int)length
               buffer:(void *)buffer
               client:(vm_task_t)client;

// Increment/decrement methods
- (IOReturn)incrementOpenRetries;
- (IOReturn)incrementNonRetries;
- (IOReturn)getIncrementNonErrors;
- (IOReturn)getIncrementNonRetries;

// Drive state management
- (IOReturn)setDriveReady:(BOOL)ready;
- (BOOL)isDriveReady;
- (IOReturn)setEjectable:(BOOL)ejectable;
- (BOOL)isEjectable;
- (IOReturn)setWriteProtected:(BOOL)protect;
- (BOOL)isWriteProtected;

// Disk management
- (IOReturn)setDisk:(id)disk;
- (id)disk;

// Statistics
- (IOReturn)resetStatistics;
- (unsigned int)openRetries;
- (unsigned int)nonRetries;
- (unsigned int)nonErrors;

@end
