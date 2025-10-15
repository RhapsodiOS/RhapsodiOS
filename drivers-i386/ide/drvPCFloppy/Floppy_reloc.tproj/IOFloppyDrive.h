/*
 * IOFloppyDrive.h
 * Floppy Drive Interface
 */

#import <driverkit/IODrive.h>
#import <driverkit/return.h>

@class FloppyController;
@class IOFloppyDisk;

@interface IOFloppyDrive : IODrive
{
    FloppyController *_controller;
    IOFloppyDisk *_disk;
    unsigned int _unit;

    // Drive state
    BOOL _isReady;
    BOOL _mediaPresent;
    BOOL _writeProtected;
    unsigned int _lastReadState;

    // Geometry
    unsigned int _cylinders;
    unsigned int _heads;
    unsigned int _sectorsPerTrack;
    unsigned int _blockSize;

    // Cached data
    void *_readBuffer;
    unsigned int _readBufferSize;

    // Retry counters
    unsigned int _readRetries;
    unsigned int _writeRetries;
    unsigned int _otherRetries;

    // Internal state
    void *_deviceDescription;
    id _internal;
    id _internal2;
}

- initWithController:(FloppyController *)controller
                unit:(unsigned int)unit;

// Drive operations
- (IOReturn)readAt:(unsigned int)offset
            length:(unsigned int)length
            buffer:(void *)buffer
        actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client;

- (IOReturn)writeAt:(unsigned int)offset
             length:(unsigned int)length
             buffer:(void *)buffer
         actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client;

- (IOReturn)readAsyncAt:(unsigned int)offset
                 length:(unsigned int)length
                 buffer:(void *)buffer
                 pending:(void *)pending
                 client:(vm_task_t)client;

- (IOReturn)writeAsyncAt:(unsigned int)offset
                  length:(unsigned int)length
                  buffer:(void *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client;

// Media operations
- (IOReturn)ejectPhysical;
- (IOReturn)formatCapacities:(unsigned long long *)capacities
                       count:(unsigned int *)count;
- (IOReturn)formatCylinder:(unsigned int)cylinder
                      head:(unsigned int)head
                      data:(void *)data;

// Polling and media
- (IOReturn)pollMedia;
- (IOReturn)setMediaBad;
- (IOReturn)canPollingBeExpensively;

// Status
- (IOReturn)isDiskReady:(BOOL *)ready;
- (IOReturn)checkForMedia;
- (IOReturn)updateReadyState;
- (IOReturn)updatePhysicalParameters;
- (IOReturn)getIntValues:(unsigned int *)values
             forParameter:(IOParameterName)parameter
                    count:(unsigned int *)count;
- (IOReturn)getFormatted;
- (IOReturn)setFormatted:(BOOL)formatted;
- (IOReturn)isFormatted;
- (IOReturn)setWriteProtected:(BOOL)writeProtected;

// Retries
- (IOReturn)incrementReadRetries;
- (IOReturn)incrementOtherRetries;
- (IOReturn)incrementWriteRetries;

// Volume check support
- (IOReturn)volCheckSupport;
- (IOReturn)volCheckUnregister;
- (IOReturn)volCheckRegister;

// Block operations
- (IOReturn)rwCommon:(void *)block client:(vm_task_t)client;
- (IOReturn)setBlockCnt:(unsigned int)blockCnt;
- (IOReturn)blockCount:(unsigned int *)count;

// Internal operations
- (void)setLastReadState:(unsigned int)state;
- (FloppyController *)controller;
- (IOReturn)fdRecal;
- (IOReturn)fdSeek:(unsigned int)head;
- (IOReturn)fdOctlValues:(unsigned int *)values
            forParameter:(IOParameterName)parameter
                   count:(unsigned int *)count;
- (IOReturn)rwBlockCount:(void *)block;
- (IOReturn)fdBufferCount:(unsigned int)buffer
            actualLength:(unsigned int *)actualLength
                  client:(vm_task_t)client;
- (IOReturn)updateStateInt;
- (IOReturn)formatInfo;

// Floppy-specific operations
- (IOReturn)fdGetStatus:(unsigned char *)status;
- (IOReturn)fdWrite:(unsigned int)block buffer:(void *)buffer length:(unsigned int)length;
- (IOReturn)fdRead:(unsigned int)block buffer:(void *)buffer length:(unsigned int)length;
- (IOReturn)fdFormat:(unsigned int)cylinder head:(unsigned int)head;

// Additional operations
- (IOReturn)allocateDmaBuffer:(unsigned int)size;
- (IOReturn)motorCheck:(BOOL)on autoCheck:(BOOL)autoCheck;
- (IOReturn)setDensity:(unsigned int)density;
- (IOReturn)getDensity:(unsigned int *)density;
- (IOReturn)execRequest:(void *)request;
- (IOReturn)blockCnt:(unsigned int *)count;
- (const char *)driverName;

// IOPhysicalDiskMethods protocol
- (void)abortRequest;
- (void)diskBecameReady;
- (IODiskReadyState)updateReadyState;
- (BOOL)needsManualPolling;
- (IOReturn)isDiskReady:(BOOL)prompt;

// IODisk methods
- (const char *)stringFromReturn:(IOReturn)rtn;
- (IOReturn)errnoFromReturn:(IOReturn)rtn;

@end
