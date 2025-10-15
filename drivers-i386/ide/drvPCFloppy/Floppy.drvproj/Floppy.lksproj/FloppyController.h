/*
 * FloppyController.h
 * PC Floppy Disk Controller Driver
 */

#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/IODirectDevice.h>
#import <driverkit/IODevice.h>

@interface FloppyController : IODirectDevice
{
    IOEISADeviceDescription *_deviceDescription;
    unsigned int _irqLevel;
    unsigned int _dmaChannel;
    unsigned int _ioPortBase;
    unsigned int _ioPortSize;

    // Controller state
    BOOL _motorOn;
    unsigned int _currentDrive;
    unsigned int _timeout;

    // Geometry information
    unsigned int _sectorsPerTrack;
    unsigned int _heads;
    unsigned int _cylinders;
    unsigned int _sectorSize;

    // DMA buffer
    vm_address_t _dmaBuffer;
    unsigned int _dmaBufferSize;

    // Drive instances
    id _drives[4];

    // Thread support
    id _operationThread;
    id _timeoutThread;

    // Queue support
    id _queueOperation;
    id _queueOperationAscending;
    id _queueOperationDecending;

    // Locks
    id _lock;
    id _spinLock;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

- (IOReturn)getHandler:(IOEISAInterruptHandler *)handler
                level:(unsigned int *)ipl
             argument:(unsigned int *)arg
          forInterrupt:(unsigned int)localInterrupt;

- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)floppyInterrupt;

// Controller operations
- (IOReturn)resetController;
- (IOReturn)doMotorOn:(unsigned int)drive;
- (IOReturn)doMotorOff:(unsigned int)drive;
- (IOReturn)doSeek:(unsigned int)drive cylinder:(unsigned int)cyl;
- (IOReturn)doRecalibrate:(unsigned int)drive;
- (IOReturn)doConfigure;
- (IOReturn)doSpecify;

// I/O operations
- (IOReturn)doRead:(unsigned int)drive
          cylinder:(unsigned int)cyl
              head:(unsigned int)head
            sector:(unsigned int)sec
            buffer:(void *)buffer
            length:(unsigned int)length;

- (IOReturn)doWrite:(unsigned int)drive
           cylinder:(unsigned int)cyl
               head:(unsigned int)head
             sector:(unsigned int)sec
             buffer:(void *)buffer
             length:(unsigned int)length;

- (IOReturn)doFormat:(unsigned int)drive
            cylinder:(unsigned int)cyl
                head:(unsigned int)head;

// Command operations
- (IOReturn)sendCmd:(unsigned char *)cmd length:(unsigned int)length;
- (IOReturn)getCmdResult:(unsigned char *)result length:(unsigned int)length;
- (IOReturn)fdSendByte:(unsigned char)byte;
- (IOReturn)fdGetByte:(unsigned char *)byte;

// Status operations
- (IOReturn)getDriveStatus:(unsigned int)drive;
- (IOReturn)senseInterrupt;
- (IOReturn)readStatus;

// DMA operations
- (IOReturn)setupDMA:(vm_address_t)buffer length:(unsigned int)length write:(BOOL)write;
- (IOReturn)dmaPlan:(vm_address_t)buffer length:(unsigned int)length write:(BOOL)write;

// Timeout operations
- (void)setTimeout:(unsigned int)ms;
- (void)cancelTimeout;

// Thread operations
- (void)operationThread:(id)arg;

// Geometry
- (unsigned int)sectorsPerTrack;
- (unsigned int)headsPerCylinder;
- (unsigned int)cylindersPerDisk;
- (unsigned int)blockSize;
- (unsigned int)sizeInSectors;
- (unsigned int)sizeFromCapacities;

// Drive management
- (void)registerDrive:(id)drive atUnit:(unsigned int)unit;
- (id)getDrive:(unsigned int)unit;

// Additional operations
- (IOReturn)attachToBlockDevice;
- (const char *)driverName;
- (IOReturn)getDevicePath:(char *)path maxLength:(int)maxLength unit:(int)unit;

@end
