/*
 * IOFloppyDrive.h
 * Floppy Drive Interface
 */

#import <driverkit/IODisk.h>
#import <driverkit/return.h>

@class FloppyController;
@class IOFloppyDisk;

@interface IOFloppyDrive : IODisk <IOPhysicalDiskMethods, IODiskReadingAndWriting>
{
@private
    FloppyController *_controller;
    IOFloppyDisk *_disk;
    unsigned int _unit;

    BOOL _isRegistered;

    // Drive state
    BOOL _mediaPresent;
    BOOL _diskChanged;

    // Geometry - cached for efficiency
    unsigned int _cylinders;
    unsigned int _heads;
    unsigned int _sectorsPerTrack;

    // Cached data
    void *_readBuffer;
    unsigned int _readBufferSize;

    // I/O thread management
    IOThread _ioThread;
    id _ioQLock;  // NXConditionLock for I/O queue
    queue_head_t _ioQueue;
    BOOL _threadRunning;

    // Current position tracking
    unsigned int _currentCylinder;
    unsigned int _currentHead;

    // Volume check support
    id _volCheck;

    // Lock for internal state
    id _lock;  // NXLock

    int _IOFloppyDrive_reserved[4];
}

/*
 * Class methods for driver registration
 */
+ (BOOL)probe:(id)deviceDescription;
+ (IODeviceStyle)deviceStyle;
+ (Protocol **)requiredProtocols;

/*
 * Initialization
 */
- initWithController:(FloppyController *)controller
                unit:(unsigned int)unit;

/*
 * Registration
 */
- registerDevice;
- free;

/*
 * IODiskReadingAndWriting protocol methods
 * (inherited from IODisk, must implement)
 */
- (IOReturn)readAt:(unsigned int)offset
            length:(unsigned int)length
            buffer:(unsigned char *)buffer
      actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client;

- (IOReturn)writeAt:(unsigned int)offset
             length:(unsigned int)length
             buffer:(unsigned char *)buffer
       actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client;

- (IOReturn)readAsyncAt:(unsigned int)offset
                 length:(unsigned int)length
                 buffer:(unsigned char *)buffer
                pending:(void *)pending
                 client:(vm_task_t)client;

- (IOReturn)writeAsyncAt:(unsigned int)offset
                  length:(unsigned int)length
                  buffer:(unsigned char *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client;

/*
 * IOPhysicalDiskMethods protocol methods
 * (required for physical disk devices)
 */
- (IOReturn)updatePhysicalParameters;
- (void)abortRequest;
- (void)diskBecameReady;
- (IOReturn)isDiskReady:(BOOL)prompt;
- (IOReturn)ejectPhysical;
- (IODiskReadyState)updateReadyState;

/*
 * Additional floppy-specific operations
 */
- (IOReturn)formatCapacities:(unsigned long long *)capacities
                       count:(unsigned int *)count;
- (IOReturn)formatCylinder:(unsigned int)cylinder
                      head:(unsigned int)head
                      data:(void *)data;

// Internal floppy operations
- (IOReturn)fdRecalibrate;
- (IOReturn)fdSeek:(unsigned int)cylinder;
- (IOReturn)fdGetStatus:(unsigned char *)status;
- (IOReturn)fdFormat:(unsigned int)cylinder head:(unsigned int)head;

// Motor control
- (IOReturn)motorOn;
- (IOReturn)motorOff;

// Controller access
- (FloppyController *)controller;
- (unsigned int)unit;

@end
