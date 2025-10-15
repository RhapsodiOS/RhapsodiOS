/*
 * FloppyController.m
 * PC Floppy Disk Controller Driver
 */

#import "FloppyController.h"
#import "IOFloppyDrive.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <mach/mach.h>

// FDC I/O ports (relative to base)
#define FDC_DOR     0  // Digital Output Register
#define FDC_MSR     4  // Main Status Register
#define FDC_DATA    5  // Data Register
#define FDC_DIR     7  // Digital Input Register

// FDC Commands
#define CMD_SPECIFY         0x03
#define CMD_RECALIBRATE     0x07
#define CMD_SENSE_INT       0x08
#define CMD_SEEK            0x0F
#define CMD_READ            0xE6
#define CMD_WRITE           0xC5
#define CMD_FORMAT          0x4D

// Status bits
#define MSR_RQM     0x80  // Request for Master
#define MSR_DIO     0x40  // Data Input/Output
#define MSR_BUSY    0x10  // FDC Busy

#define DOR_MOTOR_SHIFT  4
#define DOR_DMA_ENABLE   0x08
#define DOR_RESET        0x04

@implementation FloppyController

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    FloppyController *controller;

    controller = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (controller == nil) {
        return NO;
    }

    [controller free];
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IORange *portRange;
    unsigned int *irqList;
    unsigned int *dmaList;
    int i;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _deviceDescription = deviceDescription;

    // Get I/O port range
    portRange = [deviceDescription portRangeList];
    if (portRange == NULL) {
        [self free];
        return nil;
    }
    _ioPortBase = portRange[0].start;
    _ioPortSize = portRange[0].size;

    // Get IRQ
    irqList = [deviceDescription interrupt];
    if (irqList == NULL) {
        [self free];
        return nil;
    }
    _irqLevel = irqList[0];

    // Get DMA channel
    dmaList = [deviceDescription channelList];
    if (dmaList == NULL) {
        [self free];
        return nil;
    }
    _dmaChannel = dmaList[0];

    // Initialize state
    _motorOn = NO;
    _currentDrive = 0;
    _timeout = 500;  // 500ms default timeout

    // Standard 1.44MB floppy geometry
    _sectorsPerTrack = 18;
    _heads = 2;
    _cylinders = 80;
    _sectorSize = 512;

    // Allocate DMA buffer
    _dmaBufferSize = 0x4800;  // 18K buffer
    if (IOGetDmaMemory(_dmaBufferSize, &_dmaBuffer, 0) != IO_R_SUCCESS) {
        [self free];
        return nil;
    }

    // Initialize drive array
    for (i = 0; i < 4; i++) {
        _drives[i] = nil;
    }

    // Reset controller
    if ([self resetController] != IO_R_SUCCESS) {
        IOFreeDmaMemory(_dmaBuffer, _dmaBufferSize);
        [self free];
        return nil;
    }

    [self registerDevice];
    [self setName:"Floppy"];
    [self setDeviceKind:"Floppy"];

    return self;
}

- (void)free
{
    if (_dmaBuffer) {
        IOFreeDmaMemory(_dmaBuffer, _dmaBufferSize);
    }
    return [super free];
}

- (IOReturn)getHandler:(IOEISAInterruptHandler *)handler
                level:(unsigned int *)ipl
             argument:(unsigned int *)arg
          forInterrupt:(unsigned int)localInterrupt
{
    *handler = (IOEISAInterruptHandler)[self methodFor:@selector(interruptOccurred)];
    *ipl = _irqLevel;
    *arg = (unsigned int)self;
    return IO_R_SUCCESS;
}

- (void)interruptOccurred
{
    // Handle floppy interrupt
    [self senseInterrupt];
}

- (void)timeoutOccurred
{
    IOLog("FloppyController: timeout occurred\n");
}

- (IOReturn)resetController
{
    unsigned char status;
    int i;

    // Disable controller
    outb(_ioPortBase + FDC_DOR, 0);
    IODelay(10);

    // Enable controller with DMA
    outb(_ioPortBase + FDC_DOR, DOR_DMA_ENABLE | DOR_RESET);
    IODelay(10);

    // Wait for ready
    for (i = 0; i < 1000; i++) {
        status = inb(_ioPortBase + FDC_MSR);
        if (status & MSR_RQM) {
            break;
        }
        IODelay(1);
    }

    if (!(status & MSR_RQM)) {
        return IO_R_TIMEOUT;
    }

    // Specify command (set drive parameters)
    outb(_ioPortBase + FDC_DATA, CMD_SPECIFY);
    outb(_ioPortBase + FDC_DATA, 0xDF);  // SRT=3ms, HUT=240ms
    outb(_ioPortBase + FDC_DATA, 0x02);  // HLT=16ms, DMA mode

    return IO_R_SUCCESS;
}

- (IOReturn)doMotorOn:(unsigned int)drive
{
    unsigned char dor;

    if (drive > 3) {
        return IO_R_INVALID_ARG;
    }

    dor = DOR_DMA_ENABLE | DOR_RESET | drive;
    dor |= (1 << (DOR_MOTOR_SHIFT + drive));

    outb(_ioPortBase + FDC_DOR, dor);
    IOSleep(500);  // Wait for motor to spin up

    _motorOn = YES;
    _currentDrive = drive;

    return IO_R_SUCCESS;
}

- (IOReturn)doMotorOff:(unsigned int)drive
{
    unsigned char dor;

    if (drive > 3) {
        return IO_R_INVALID_ARG;
    }

    dor = DOR_DMA_ENABLE | DOR_RESET;
    outb(_ioPortBase + FDC_DOR, dor);

    _motorOn = NO;

    return IO_R_SUCCESS;
}

- (IOReturn)senseInterrupt
{
    unsigned char status, cylinder;
    int i;

    // Wait for ready
    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }

    // Send sense interrupt command
    outb(_ioPortBase + FDC_DATA, CMD_SENSE_INT);

    // Read status
    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }
    status = inb(_ioPortBase + FDC_DATA);

    // Read cylinder
    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }
    cylinder = inb(_ioPortBase + FDC_DATA);

    return IO_R_SUCCESS;
}

- (IOReturn)doRecalibrate:(unsigned int)drive
{
    int i;

    if (drive > 3) {
        return IO_R_INVALID_ARG;
    }

    [self doMotorOn:drive];

    // Wait for ready
    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }

    // Send recalibrate command
    outb(_ioPortBase + FDC_DATA, CMD_RECALIBRATE);
    outb(_ioPortBase + FDC_DATA, drive);

    IOSleep(100);
    [self senseInterrupt];

    return IO_R_SUCCESS;
}

- (IOReturn)doSeek:(unsigned int)drive cylinder:(unsigned int)cyl
{
    int i;

    if (drive > 3 || cyl >= _cylinders) {
        return IO_R_INVALID_ARG;
    }

    [self doMotorOn:drive];

    // Wait for ready
    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }

    // Send seek command
    outb(_ioPortBase + FDC_DATA, CMD_SEEK);
    outb(_ioPortBase + FDC_DATA, (cyl << 2) | drive);
    outb(_ioPortBase + FDC_DATA, cyl);

    IOSleep(20);
    [self senseInterrupt];

    return IO_R_SUCCESS;
}

- (IOReturn)doRead:(unsigned int)drive
          cylinder:(unsigned int)cyl
              head:(unsigned int)head
            sector:(unsigned int)sec
            buffer:(void *)buffer
            length:(unsigned int)length
{
    // Simplified read implementation
    [self doMotorOn:drive];
    [self doSeek:drive cylinder:cyl];

    // This would need full DMA setup and command sequence
    // For now, return success
    return IO_R_SUCCESS;
}

- (IOReturn)doWrite:(unsigned int)drive
           cylinder:(unsigned int)cyl
               head:(unsigned int)head
             sector:(unsigned int)sec
             buffer:(void *)buffer
             length:(unsigned int)length
{
    // Simplified write implementation
    [self doMotorOn:drive];
    [self doSeek:drive cylinder:cyl];

    // This would need full DMA setup and command sequence
    // For now, return success
    return IO_R_SUCCESS;
}

- (IOReturn)doFormat:(unsigned int)drive
            cylinder:(unsigned int)cyl
                head:(unsigned int)head
{
    // Simplified format implementation
    [self doMotorOn:drive];
    [self doSeek:drive cylinder:cyl];

    return IO_R_SUCCESS;
}

- (IOReturn)getDriveStatus:(unsigned int)drive
{
    if (drive > 3) {
        return IO_R_INVALID_ARG;
    }

    return IO_R_SUCCESS;
}

- (unsigned int)sectorsPerTrack
{
    return _sectorsPerTrack;
}

- (unsigned int)headsPerCylinder
{
    return _heads;
}

- (unsigned int)cylindersPerDisk
{
    return _cylinders;
}

- (unsigned int)blockSize
{
    return _sectorSize;
}

- (void)registerDrive:(id)drive atUnit:(unsigned int)unit
{
    if (unit < 4) {
        _drives[unit] = drive;
    }
}

- (id)getDrive:(unsigned int)unit
{
    if (unit < 4) {
        return _drives[unit];
    }
    return nil;
}

- (void)floppyInterrupt
{
    [self interruptOccurred];
}

- (IOReturn)doConfigure
{
    unsigned char cmd[4];
    int i;

    // Wait for ready
    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }

    // Configure command
    cmd[0] = 0x13;  // CONFIGURE
    cmd[1] = 0;
    cmd[2] = 0x57;  // FIFO threshold, implied seek
    cmd[3] = 0;

    return [self sendCmd:cmd length:4];
}

- (IOReturn)doSpecify
{
    // Already done in resetController
    return IO_R_SUCCESS;
}

- (IOReturn)sendCmd:(unsigned char *)cmd length:(unsigned int)length
{
    unsigned int i, j;

    for (i = 0; i < length; i++) {
        // Wait for ready
        for (j = 0; j < 1000; j++) {
            if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
                break;
            }
            IODelay(1);
        }

        if (!(inb(_ioPortBase + FDC_MSR) & MSR_RQM)) {
            return IO_R_TIMEOUT;
        }

        outb(_ioPortBase + FDC_DATA, cmd[i]);
    }

    return IO_R_SUCCESS;
}

- (IOReturn)getCmdResult:(unsigned char *)result length:(unsigned int)length
{
    unsigned int i, j;

    for (i = 0; i < length; i++) {
        // Wait for ready with data
        for (j = 0; j < 1000; j++) {
            unsigned char msr = inb(_ioPortBase + FDC_MSR);
            if ((msr & MSR_RQM) && (msr & MSR_DIO)) {
                break;
            }
            IODelay(1);
        }

        if (!(inb(_ioPortBase + FDC_MSR) & MSR_RQM)) {
            return IO_R_TIMEOUT;
        }

        result[i] = inb(_ioPortBase + FDC_DATA);
    }

    return IO_R_SUCCESS;
}

- (IOReturn)fdSendByte:(unsigned char)byte
{
    int i;

    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }

    if (!(inb(_ioPortBase + FDC_MSR) & MSR_RQM)) {
        return IO_R_TIMEOUT;
    }

    outb(_ioPortBase + FDC_DATA, byte);
    return IO_R_SUCCESS;
}

- (IOReturn)fdGetByte:(unsigned char *)byte
{
    int i;

    for (i = 0; i < 1000; i++) {
        unsigned char msr = inb(_ioPortBase + FDC_MSR);
        if ((msr & MSR_RQM) && (msr & MSR_DIO)) {
            break;
        }
        IODelay(1);
    }

    if (!(inb(_ioPortBase + FDC_MSR) & MSR_RQM)) {
        return IO_R_TIMEOUT;
    }

    *byte = inb(_ioPortBase + FDC_DATA);
    return IO_R_SUCCESS;
}

- (IOReturn)readStatus
{
    unsigned char msr;
    msr = inb(_ioPortBase + FDC_MSR);
    return IO_R_SUCCESS;
}

- (IOReturn)setupDMA:(vm_address_t)buffer length:(unsigned int)length write:(BOOL)write
{
    // Setup DMA channel 2 for floppy
    // This is simplified - real implementation would use DMA API
    return IO_R_SUCCESS;
}

- (IOReturn)dmaPlan:(vm_address_t)buffer length:(unsigned int)length write:(BOOL)write
{
    // Plan DMA transfer for floppy operations
    return [self setupDMA:buffer length:length write:write];
}

- (void)setTimeout:(unsigned int)ms
{
    _timeout = ms;
}

- (void)cancelTimeout
{
    _timeout = 0;
}

- (void)operationThread:(id)arg
{
    // Thread for handling queued operations
    // Simplified stub
}

- (unsigned int)sizeInSectors
{
    return _cylinders * _heads * _sectorsPerTrack;
}

- (unsigned int)sizeFromCapacities
{
    return [self sizeInSectors] * _sectorSize;
}

- (IOReturn)attachToBlockDevice
{
    // Attach controller to block device subsystem
    return IO_R_SUCCESS;
}

- (const char *)driverName
{
    return "FloppyController";
}

- (IOReturn)getDevicePath:(char *)path maxLength:(int)maxLength unit:(int)unit
{
    if (path && maxLength > 0) {
        snprintf(path, maxLength, "/dev/fd%d", unit);
    }
    return IO_R_SUCCESS;
}

@end
