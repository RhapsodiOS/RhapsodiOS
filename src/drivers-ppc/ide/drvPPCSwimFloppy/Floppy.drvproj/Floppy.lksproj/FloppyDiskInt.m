/*
 * FloppyDiskInt.m - FloppyDisk Internal category implementation
 *
 * Internal methods for floppy disk operations
 */

#import "FloppyDisk.h"
#import <driverkit/return.h>
#import <driverkit/debugging.h>
#import <objc/NXLock.h>
#import <stdio.h>
#import <string.h>

// Forward declarations
@class FloppyController;
@interface FloppyController : NSObject
- (void)lock;
- (IOReturn)_fcCmdXfr:(void *)cmdBuf driveInfo:(const char *)driveInfo;
@end

/*
 * FdBuffer structure - represents a floppy disk I/O buffer
 * Total size: 0x34 (52) bytes
 */
typedef struct _FdBuffer {
    // Header fields (0x00-0x17)
    void *reserved1;           // offset 0x00
    void *reserved2;           // offset 0x04
    unsigned int actualLength; // offset 0x08: actual bytes transferred
    void *reserved4;           // offset 0x0c
    void *reserved5;           // offset 0x10
    void *reserved6;           // offset 0x14

    // Lock and callback (0x18-0x1f)
    id conditionLock;          // offset 0x18: NXConditionLock for completion
    void *callback;            // offset 0x1c: callback parameter

    // Flags and status (0x20-0x2b)
    int flags;                 // offset 0x20: operation flags
    void *reserved7;           // offset 0x24
    IOReturn status;           // offset 0x28: I/O completion status

    // Linked list pointers (0x2c-0x33)
    struct _FdBuffer *prev;    // offset 0x2c: previous buffer in queue
    struct _FdBuffer *next;    // offset 0x30: next buffer in queue
} FdBuffer;

/*
 * Floppy read/write command structure
 */
typedef struct _fd_rw_cmd {
    unsigned char reserved1;   // offset 0x00
    unsigned char reserved2;   // offset 0x01
    unsigned char cylinder;    // offset 0x02: cylinder number
    unsigned char head;        // offset 0x03: head number
    unsigned char sector;      // offset 0x04: sector number
    unsigned char reserved[4]; // offset 0x05-0x08
} fd_rw_cmd;

/*
 * Floppy drive status structure
 */
typedef struct _fd_drive_stat {
    unsigned char status;      // Status byte
} fd_drive_stat;

/*
 * Floppy read/write result status structure (7 bytes)
 */
typedef struct _fd_rw_stat {
    unsigned char st0;         // offset 0x00: Status register 0
    unsigned char st1;         // offset 0x01: Status register 1
    unsigned char st2;         // offset 0x02: Status register 2
    unsigned char cylinder;    // offset 0x03: Cylinder
    unsigned char head;        // offset 0x04: Head
    unsigned char sector;      // offset 0x05: Sector
    unsigned char sectorSize;  // offset 0x06: Sector size code
} fd_rw_stat;

/*
 * Floppy I/O request structure
 * Based on decompiled offsets
 */
typedef struct _FdIoReq {
    unsigned char reserved1[5];     // offset 0x00-0x04
    unsigned int timeout;           // offset 0x05 (+3 = 0x08): timeout value
    unsigned int reserved2;         // offset 0x09 (+3 = 0x0c)
    unsigned char reserved3[13];    // offset 0x0d-0x19
    unsigned int cmdLength;         // offset 0x19 (+3 = 0x1c): command length
    unsigned char reserved4[28];    // offset 0x1d-0x38
    unsigned int flags;             // offset 0x39 (+3 = 0x3c): operation flags
    unsigned char reserved5[4];     // offset 0x3d-0x40
    unsigned int resultLength;      // offset 0x35 (+3 = 0x38): result length
    unsigned char cmd[12];          // offset 0x09 (+3 = 0x0c): command bytes
} FdIoReq;

/*
 * Floppy command buffer structure (0x60 bytes total)
 * Used for sending commands to the floppy controller
 */
typedef struct _FdCmdBuf {
    unsigned char param[4];        // offset 0x00-0x03: parameter bytes
    unsigned int timeout;          // offset 0x04: timeout in ms
    unsigned int flag;             // offset 0x08: flag (usually 1)
    unsigned char cmd[16];         // offset 0x0c-0x1b: command bytes
    unsigned int cmdLength;        // offset 0x1c: command length
    unsigned int reserved1;        // offset 0x20
    unsigned int reserved2;        // offset 0x24
    unsigned char result[16];      // offset 0x28-0x37: result bytes
    unsigned int resultLength;     // offset 0x38: result length
    unsigned int reserved3;        // offset 0x3c
    unsigned int status;           // offset 0x40: status code
    unsigned char padding[28];     // offset 0x44-0x5f: padding to 0x60
} FdCmdBuf;

// Global variables for FloppyPluginIO
static int _DataSource = 0;
static BOOL _BusyFlag = NO;
extern int _FloppyPluginIO(unsigned int *actualLength, unsigned int length, void *buffer,
                           unsigned int offset, BOOL isWrite, unsigned int param6);
extern int _floppyMalloc(unsigned int size, void *physAddr, void *virtAddr);
extern void _fdTimer(id disk);
extern void _fdThread(id disk);

static void _GetBusyFlag(void)
{
    _BusyFlag = YES;
}

static void _ResetBusyFlag(void)
{
    _BusyFlag = NO;
}

// Command name lookup (simplified version)
static const char *_fdCommandValues[] = {
    "UNKNOWN", "UNKNOWN", "UNKNOWN", "UNKNOWN", "UNKNOWN",
    "SENSE_DRV_STATUS", "READ_DATA", "RECALIBRATE", "SENSE_INT_STATUS", "UNKNOWN",
    "READ_ID", "UNKNOWN", "UNKNOWN", "UNKNOWN", "UNKNOWN", "SEEK"
};

static const char *_fdrValues[] = {
    "SUCCESS", "ERROR", "TIMEOUT", "INVALID"
};

// Helper to get command name
static const char *_getCommandName(unsigned int cmdCode)
{
    if (cmdCode < sizeof(_fdCommandValues) / sizeof(_fdCommandValues[0])) {
        return _fdCommandValues[cmdCode];
    }
    return "UNKNOWN";
}

// Helper to get result name
static const char *_getResultName(unsigned int result)
{
    if (result < sizeof(_fdrValues) / sizeof(_fdrValues[0])) {
        return _fdrValues[result];
    }
    return "UNKNOWN";
}

@implementation FloppyDisk(Internal)

/*
 * Allocate a floppy disk buffer
 */
- (id)_allocFdBuf:(unsigned)size
{
    FdBuffer *fdBuf;

    // Allocate the buffer structure (0x34 bytes = 52 bytes)
    fdBuf = (FdBuffer *)IOMalloc(sizeof(FdBuffer));
    if (fdBuf == NULL) {
        return nil;
    }

    // Clear the structure
    bzero(fdBuf, sizeof(FdBuffer));

    // If size is 0, create a condition lock for synchronous operations
    if (size == 0) {
        fdBuf->conditionLock = [[NXConditionLock alloc] initWith:0];
        if (fdBuf->conditionLock == nil) {
            IOFree(fdBuf, sizeof(FdBuffer));
            return nil;
        }
    } else {
        // Otherwise, store the callback pointer
        fdBuf->callback = (void *)size;
    }

    return (id)fdBuf;
}

/*
 * Common device read/write operation
 */
- (IOReturn)_deviceRwCommon:(BOOL)isRead
                      block:(unsigned)block
                     length:(unsigned)length
                     buffer:(void *)buffer
                     client:(vm_task_t)client
                    pending:(void *)pending
               actualLength:(unsigned *)actualLength
{
    IOReturn status;
    unsigned int blockSize;
    unsigned int diskSize;
    unsigned int localActualLength;
    BOOL isWrite = !isRead;

    // Check if disk is ready
    status = [self _isDiskReady:nil];

    if (status == (IOReturn)0xfffffbb2) {  // IO_R_NO_DISK = -1102
        IOLog("Floppy deviceRwCommon: disk not present\n");
        return status;
    }

    if (status != IO_R_SUCCESS) {
        IOLog("%s deviceRwCommon: bogus return from isDiskReady (%s)\n",
              [self name],
              [self stringFromReturn:status]);
        return status;
    }

    // Check if disk is formatted
    if (![self isFormatted]) {
        IOLog("deviceRwCommon:unformatted\n");
        return (IOReturn)0xfffffbb3;  // IO_R_UNFORMATTED = -1101
    }

    // Get block size and disk size
    blockSize = [self blockSize];
    diskSize = [self diskSize];

    IOLog("blksize=%d,dev_size=%d\n", blockSize, diskSize);

    // Check if length is aligned to block size
    if (length != (length / blockSize) * blockSize) {
        IOLog("deviceRwCommon: unaligned length\n");
        return IO_R_INVALID;
    }

    // Set busy flag
    _GetBusyFlag();

    // Determine data source based on pending parameter
    // pending == VM_TASK_NULL means kernel space (data source 1)
    // otherwise user space (data source 2)
    if (pending == (void *)VM_TASK_NULL) {
        _DataSource = 1;
    } else {
        _DataSource = 2;
    }

    // Call the FloppyPluginIO function
    status = _FloppyPluginIO(&localActualLength, length, buffer,
                             block * blockSize, isWrite, 0);

    // Store actual length transferred
    *actualLength = localActualLength;

    // Reset busy flag
    _ResetBusyFlag();

    return status;
}

/*
 * Enqueue a floppy disk buffer
 */
- (void)_enqueueFdBuf:(id)buffer
{
    FdBuffer *fdBuf = (FdBuffer *)buffer;
    QueueHead *targetQueue;
    FdBuffer *lastBuf;
    IOReturn status;

    // Initialize status to -1 (operation pending)
    fdBuf->status = (IOReturn)0xffffffff;

    // Lock the queue
    [_queueLock lock];

    // Determine which queue to use based on flags
    // Negative flags = priority queue, else normal queue
    if (fdBuf->flags < 0) {
        targetQueue = &_priorityQueue;
    } else {
        targetQueue = &_normalQueue;
    }

    // Get the last buffer in the queue
    lastBuf = targetQueue->last;

    // Add buffer to the queue (doubly-linked list)
    if (targetQueue->first == NULL) {
        // Queue is empty, this is the first buffer
        targetQueue->first = fdBuf;
    } else {
        // Link to the previous last buffer
        lastBuf->next = fdBuf;
    }

    // Update the linked list pointers
    fdBuf->prev = lastBuf;
    fdBuf->next = NULL;
    targetQueue->last = fdBuf;

    // Unlock with value 1 (signal work available)
    [_queueLock unlockWith:1];

    // If this is a synchronous operation (no callback and bit 29 not set)
    if ((fdBuf->callback == NULL) && ((fdBuf->flags & 0x20000000) == 0)) {
        // Wait for I/O completion
        [fdBuf->conditionLock lockWhen:1];
        [fdBuf->conditionLock unlock];

        // Log completion
        IOLog("enqueueFdBuf: I/O Complete fdBuf 0x%x status %s\n",
              (unsigned int)fdBuf,
              [self stringFromReturn:fdBuf->status]);

        status = fdBuf->status;
    } else {
        // Asynchronous operation, return immediately
        status = IO_R_SUCCESS;
    }

    return;
}

/*
 * Generate read/write command
 */
- (IOReturn)_fdGenRwCmd:(unsigned)block
             blockCount:(unsigned)blockCount
               fdIoReq:(void *)fdIoReq
               readFlag:(BOOL)isRead
{
    FdIoReq *ioReq = (FdIoReq *)fdIoReq;
    unsigned char *cmdBytes = &ioReq->cmd[3];  // Points to offset 0x0c (cmd[3])
    unsigned char cmdByte;
    fd_rw_cmd rwCmd;

    IOLog("fdGenRwCmd: block 0x%x blockCount 0x%x read = %d\n",
          block, blockCount, isRead ? 1 : 0);

    // Clear the command buffer (9 bytes)
    bzero(cmdBytes, 9);

    // Convert logical block to physical cylinder/head/sector
    [self _fdLogToPhys:block cmdp:&rwCmd];

    // Extract and modify command fields
    cmdByte = rwCmd.cylinder;
    rwCmd.cylinder = cmdByte & 0x7f;  // Clear bit 7
    rwCmd.cylinder = (cmdByte & 0x3f) | ((_field_0x1d7 & 1) << 6);  // Set bit 6 based on field_0x1d7

    // Set command code: 6 for read, 5 for write
    // Preserve upper 3 bits (bits 5-7)
    cmdBytes[0] = (cmdBytes[0] & 0xe0) | (isRead ? 6 : 5);

    // Set up command fields
    cmdBytes[1] = (cmdBytes[1] & 0xf8) | ((cmdBytes[3] & 1) << 2) | 1;
    cmdBytes[5] = _gapLength;
    cmdBytes[6] = rwCmd.sector + (unsigned char)blockCount - 1;  // Last sector
    cmdBytes[7] = _sectorSize;
    cmdBytes[8] = 0xff;

    // Set timeout and other parameters
    ioReq->timeout = 20000;  // 20 second timeout
    ioReq->reserved2 = 1;
    ioReq->cmdLength = 9;
    ioReq->resultLength = 7;

    // Set flags based on read/write direction
    if (isRead) {
        ioReq->flags = ioReq->flags | 2;      // Set bit 1 for read
    } else {
        ioReq->flags = ioReq->flags & 0xfffffffd;  // Clear bit 1 for write
    }

    return IO_R_SUCCESS;
}

/*
 * Get floppy disk status
 */
- (IOReturn)_fdGetStatus:(void *)status
{
    IOReturn result;
    unsigned char cmdBuffer[0x60];
    unsigned int *timeoutPtr;
    unsigned int *cmdLengthPtr;
    fd_drive_stat *stat = (fd_drive_stat *)status;
    unsigned char *statusByte;

    IOLog("fdGetStatus\n");

    // Clear command buffer
    bzero(cmdBuffer, 0x60);

    // Set up command parameters
    // Timeout at offset 0x00 (assuming beginning of buffer)
    timeoutPtr = (unsigned int *)&cmdBuffer[0];
    *timeoutPtr = 5000;  // 5 second timeout

    // Command length at offset 0x04
    cmdLengthPtr = (unsigned int *)&cmdBuffer[4];
    *cmdLengthPtr = 5;

    // Send the status command
    result = [self _fdSendCmd:cmdBuffer];

    IOLog("fdGetStatus: returning %s\n", [self stringFromReturn:result]);

    // Copy status byte to output parameter
    // Status is stored at specific offset in response
    statusByte = &cmdBuffer[0x28];  // Approximate offset based on structure
    stat->status = *statusByte;

    return result;
}

/*
 * Floppy disk I/O completion
 */
- (void)_fdIoComplete:(void *)ioReq
{
    FdBuffer *fdBuf = (FdBuffer *)ioReq;

    IOLog("%s fdIoComplete: fdBuf 0x%x status %s\n",
          [self name],
          (unsigned int)fdBuf,
          [self stringFromReturn:fdBuf->status]);

    // Check if this is a synchronous or asynchronous operation
    if (fdBuf->callback == NULL) {
        // Synchronous operation - signal completion via condition lock
        [fdBuf->conditionLock lock];
        [fdBuf->conditionLock unlockWith:1];
    } else {
        // Asynchronous operation - call completion callback
        [self completeTransfer:fdBuf->callback
                    withStatus:fdBuf->status
                actualTransfer:fdBuf->actualLength];

        // Free the buffer
        [self _freeFdBuf:(id)fdBuf];
    }
}

/*
 * Convert logical block to physical cylinder/head/sector
 */
- (IOReturn)_fdLogToPhys:(unsigned)logicalBlock
                    cmdp:(void *)cmdp
{
    fd_rw_cmd *cmd = (fd_rw_cmd *)cmdp;
    unsigned int blocksPerCylinder;
    unsigned int cylinderNumber;

    // Calculate blocks per cylinder (sectors per track * heads)
    blocksPerCylinder = _sectorsPerTrack;

    // Calculate absolute cylinder index (block / sectors_per_track)
    cylinderNumber = logicalBlock / blocksPerCylinder;

    // Calculate cylinder and head
    cmd->cylinder = (unsigned char)(cylinderNumber / _headsPerCylinder);
    cmd->head = (unsigned char)(cylinderNumber % _headsPerCylinder);

    // Calculate sector number (1-based)
    cmd->sector = (unsigned char)(logicalBlock % blocksPerCylinder) + 1;

    return IO_R_SUCCESS;
}

/*
 * Read ID from floppy disk
 * Reads the sector ID to verify disk format
 */
- (IOReturn)_fdReadId:(unsigned)head
                statp:(void *)statp
{
    IOReturn status;
    FdCmdBuf cmdBuf;
    fd_rw_stat *stat = (fd_rw_stat *)statp;

    IOLog("fdReadId head %d\n", head);

    // Clear command buffer
    bzero(&cmdBuf, sizeof(FdCmdBuf));

    // Build READ ID command (command code 0x0A = 10)
    // Bit 7: MFM mode (keep existing bit)
    // Bits 6: from _field_0x1d7
    // Bits 0-4: command code (10)
    cmdBuf.cmd[0] = (cmdBuf.cmd[0] & 0x80) | 10 | ((_field_0x1d7 & 1) << 6);

    // Set head select in command byte 1
    // Bits 0: always 1
    // Bit 2: head select
    cmdBuf.cmd[1] = (cmdBuf.cmd[1] & 0xf8) | (((unsigned char)head << 2) & 4) | 1;

    // Set timeout and parameters
    cmdBuf.timeout = 20000;      // 20 second timeout
    cmdBuf.flag = 1;
    cmdBuf.cmdLength = 2;        // READ ID command is 2 bytes
    cmdBuf.reserved1 = 0;
    cmdBuf.reserved2 = 0;
    cmdBuf.resultLength = 7;     // Result is 7 bytes
    cmdBuf.reserved3 = 0;

    // Send the command
    status = [self _fdSendCmd:(unsigned char *)&cmdBuf];

    // If successful, check the status code
    if (status == IO_R_SUCCESS) {
        // Check if there was an error in the command execution
        if (cmdBuf.status != 0) {
            status = (IOReturn)cmdBuf.status;
        }
    }

    IOLog("fdReadId: returning %s\n", [self stringFromReturn:status]);

    // Copy result bytes to output parameter
    stat->st0 = cmdBuf.result[0];
    stat->st1 = cmdBuf.result[1];
    stat->st2 = cmdBuf.result[2];
    stat->cylinder = cmdBuf.result[3];
    stat->head = cmdBuf.result[4];
    stat->sector = cmdBuf.result[5];
    stat->sectorSize = cmdBuf.result[6];

    return status;
}

/*
 * Recalibrate floppy disk
 * Seeks the drive to track 0 to establish a known position
 */
- (IOReturn)_fdRecal
{
    IOReturn status;
    FdCmdBuf cmdBuf;

    IOLog("fdRecal\n");

    // Clear command buffer
    bzero(&cmdBuf, sizeof(FdCmdBuf));

    // Build RECALIBRATE command (command code 0x07 = 7)
    cmdBuf.cmd[0] = 7;
    cmdBuf.cmd[1] = 1;  // Drive unit (assume drive 1)

    // Set timeout and parameters
    cmdBuf.timeout = 20000;      // 20 second timeout
    cmdBuf.flag = 1;
    cmdBuf.cmdLength = 2;        // RECALIBRATE command is 2 bytes
    cmdBuf.reserved1 = 0;
    cmdBuf.reserved2 = 0;
    cmdBuf.resultLength = 2;     // Result is 2 bytes

    // Send the command
    status = [self _fdSendCmd:(unsigned char *)&cmdBuf];

    // If successful, check the status code
    if (status == IO_R_SUCCESS) {
        // Check if there was an error in the command execution
        if (cmdBuf.status != 0) {
            status = (IOReturn)cmdBuf.status;
        }
    }

    IOLog("fdRecal: returning %s\n", [self stringFromReturn:status]);

    return status;
}

/*
 * Seek to cylinder and head
 * Positions the drive head to a specific cylinder and head
 */
- (IOReturn)_fdSeek:(unsigned)cylinder
               head:(unsigned)head
{
    IOReturn status;
    FdCmdBuf cmdBuf;
    unsigned int density;

    IOLog("fdSeek head %d cyl %d\n", head, cylinder);

    // Clear command buffer
    bzero(&cmdBuf, sizeof(FdCmdBuf));

    // Build SEEK command (command code 0x0F = 15)
    cmdBuf.cmd[0] = 0x0f;
    cmdBuf.cmd[1] = (unsigned char)(((head << 2) & 4) | 1);  // Head select and drive unit
    cmdBuf.cmd[2] = (unsigned char)cylinder;

    // Get current density, default to 3 if 0
    density = [self _getCurrentDensity];
    if (density == 0) {
        density = 3;
    }
    cmdBuf.param[0] = (unsigned char)density;

    // Set timeout and parameters
    cmdBuf.timeout = 5000;       // 5 second timeout (shorter than other commands)
    cmdBuf.flag = 1;
    cmdBuf.cmdLength = 3;        // SEEK command is 3 bytes
    cmdBuf.reserved1 = 0;
    cmdBuf.reserved2 = 0;
    cmdBuf.resultLength = 2;     // Result is 2 bytes

    // Send the command
    status = [self _fdSendCmd:(unsigned char *)&cmdBuf];

    // If successful, check the status code
    if (status == IO_R_SUCCESS) {
        // Check if there was an error in the command execution
        if (cmdBuf.status != 0) {
            status = (IOReturn)cmdBuf.status;
        }
    }

    IOLog("fdSeek: returning %s\n", [self stringFromReturn:status]);

    return status;
}

/*
 * Send command to floppy controller
 */
- (IOReturn)_fdSendCmd:(void *)command
{
    FdCmdBuf *cmdBuf = (FdCmdBuf *)command;
    IOReturn result;
    unsigned char density;
    const char *cmdName;
    const char *resultName;

    // Get command name for logging
    cmdName = _getCommandName(cmdBuf->cmdLength);
    IOLog("FloppyDiskInt.m:fdSendCmd:%s\n", cmdName);
    IOLog("fdSendCmd: sending %s\n", cmdName);

    // Get current density and set it in the command buffer
    density = [self _getCurrentDensity];
    if (density == 0) {
        density = 3;  // Default density
    }
    cmdBuf->param[0] = density;

    // Set unit number in the command buffer
    cmdBuf->param[5] = [self unit];

    // Lock the controller
    [_controller lock];

    // Call the controller's command transfer method
    result = [_controller _fcCmdXfr:cmdBuf driveInfo:_driveInfo];

    // Get result name for logging
    resultName = _getResultName(cmdBuf->status);
    IOLog("fdSendCmd: returning from %s status %s\n", cmdName, resultName);

    // Manage timer based on flags
    // If bit 29 (0x20000000) is NOT set in flags
    if ((cmdBuf->resultLength & 0x20000000) == 0) {
        // Clear bit 31 of timer flags and cancel timer
        _timerFlags = _timerFlags & 0x7fffffff;
        _fdTimer(self);  // Cancel timer
    }
    // If bit 31 of timer flags is NOT set
    else if ((_timerFlags & 0x80000000) == 0) {
        // Set bit 31 and start timer with 2 second delay
        _timerFlags = _timerFlags | 0x80000000;
        _fdTimer(self);  // Start timer with delay
    }

    IOLog("fdSendCmd:rtn=%d,setting to 0\n", result);

    // Always return success (0)
    return IO_R_SUCCESS;
}

/*
 * Send simple command to floppy controller
 * Wrapper for simple command execution
 */
- (IOReturn)_fdSimpleCommand:(unsigned)command
                      buffer:(void *)buffer
                  needsDisk:(BOOL)needsDisk
{
    FdBuffer *fdBuf;
    IOReturn result;
    int *bufAsInt;

    // Allocate an FdBuffer (synchronous operation, size = 0)
    fdBuf = (FdBuffer *)[self _allocFdBuf:0];
    if (fdBuf == NULL) {
        return IO_R_NO_MEMORY;
    }

    // Cast to int pointer for indexed access
    bufAsInt = (int *)fdBuf;

    // Set command in reserved1 field (offset 0x00)
    bufAsInt[0] = command;

    // Set buffer pointer in reserved5 field (offset 0x10)
    bufAsInt[4] = (int)buffer;

    // Set flags based on needsDisk parameter
    // Clear bits 31 and 29, then set bit 31 if needsDisk is true
    bufAsInt[8] = (bufAsInt[8] & 0x5fffffff) |
                  ((needsDisk ? 0xffffffff : 0) & 0x80000000);

    // Enqueue the buffer and wait for completion
    result = [self _enqueueFdBuf:(id)fdBuf];

    // Free the buffer
    [self _freeFdBuf:(id)fdBuf];

    return result;
}

/*
 * Simple I/O request
 * Wrapper for simple I/O request execution
 */
- (IOReturn)_fdSimpleIoReq:(void *)ioReq
                 needsDisk:(BOOL)needsDisk
{
    FdBuffer *fdBuf;
    IOReturn result;
    unsigned int *bufAsUInt;

    // Allocate an FdBuffer (synchronous operation, size = 0)
    fdBuf = (FdBuffer *)[self _allocFdBuf:0];
    if (fdBuf == NULL) {
        return IO_R_NO_MEMORY;
    }

    // Cast to unsigned int pointer for indexed access
    bufAsUInt = (unsigned int *)fdBuf;

    // Clear reserved1 field (offset 0x00)
    bufAsUInt[0] = 0;

    // Set I/O request pointer in reserved2 field (offset 0x04)
    bufAsUInt[1] = (unsigned int)ioReq;

    // Set flags based on needsDisk parameter
    // Clear bits 31 and 29, then set bit 31 if needsDisk is true
    bufAsUInt[8] = (bufAsUInt[8] & 0x5fffffff) |
                   ((needsDisk ? 0xffffffff : 0) & 0x80000000);

    IOLog("FloppyDiskInt.m:fdSimpleIoReq:enqueing\n");

    // Enqueue the buffer and wait for completion
    result = [self _enqueueFdBuf:(id)fdBuf];

    // Free the buffer
    [self _freeFdBuf:(id)fdBuf];

    return result;
}

/*
 * Initialize floppy disk
 * Initializes the floppy disk device with default parameters
 */
- (IOReturn)_floppyInit:(id)controller
{
    IOReturn result;
    void *physAddr = NULL;
    void *virtAddr = NULL;
    char deviceName[12];
    unsigned int unit;

    IOLog("floppyInit unit %d\n", [self unit]);

    // Initialize the priority queue (circular linked list)
    _priorityQueue.first = (FdBuffer *)&_priorityQueue;
    _priorityQueue.last = (FdBuffer *)&_priorityQueue;

    // Initialize the normal queue (circular linked list)
    _normalQueue.first = (FdBuffer *)&_normalQueue;
    _normalQueue.last = (FdBuffer *)&_normalQueue;

    // Set retry counts
    _innerRetry = 3;
    _outerRetry = 3;

    // Allocate 1024 bytes for DMA buffer
    result = _floppyMalloc(0x400, &physAddr, &virtAddr);
    _buffer = virtAddr;
    if (result == 0) {
        IOLog("floppyMalloc failed;but ignoring\n");
    }

    // Set drive information
    _driveInfo = "Sony MPX-111N";

    // Initialize disk parameters for 720KB floppy
    _density = 1;                 // Density 1 = 500kbps (MFM)
    _capacity = 0xb4000;          // 720KB = 737280 bytes
    _isFormatted = 1;             // Assume formatted
    _blockSize = 0x200;           // 512 bytes per sector
    _gapLength = 0x1B;            // Gap length (27 bytes)
    _sectorsPerTrack = 9;         // 9 sectors per track
    _sectorSizeCode = 2;          // Code 2 = 512 bytes
    _field_0x1e8 = 0;
    _field_0x1c8 = 0;

    // Clear timer flag bit 31
    _timerFlags = _timerFlags & 0x7fffffff;

    // Set device name (e.g., "fd0", "fd1")
    unit = [self unit];
    sprintf(deviceName, "fd%d", unit);

    // Configure device properties
    [self setUnit:unit];
    [self setName:deviceName];
    [self setDriveName:_driveInfo];
    [self setRemovable:YES];
    [self setLastReadyState:YES];

    // Update physical parameters to detect disk
    result = [self _updatePhysicalParameters];

    if (result == (IOReturn)-0x2c0) {  // Drive not present error
        IOLog("floppyInit: drive not present\n");
        return 1;  // Return 1 to indicate drive not present
    }

    // Initialize as IODisk
    [super init];

    IOLog("floppyInit unit %d, SUCCESS\n", unit);

    return 0;  // Success
}

/*
 * Free floppy disk resources
 */
- (void)_free
{
    IOLog("floppy free\n");

    // Send motor off command (0x10)
    [self _fdSimpleCommand:0x10 buffer:NULL needsDisk:NO];

    // Free the queue lock
    [_queueLock free];

    // Call superclass free
    [super free];
}

/*
 * Free a floppy disk buffer
 */
- (void)_freeFdBuf:(id)buffer
{
    FdBuffer *fdBuf = (FdBuffer *)buffer;

    // Free the condition lock if it exists
    if (fdBuf->conditionLock != nil) {
        [fdBuf->conditionLock free];
    }

    // Free the buffer structure (0x34 = 52 bytes)
    IOFree(fdBuf, sizeof(FdBuffer));
}

/*
 * Get current density
 * Returns the current media density setting
 */
- (unsigned)_getCurrentDensity
{
    return _density;
}

/*
 * Initialize resources
 * Sets up controller reference and queue lock
 */
- (IOReturn)_initResources:(id)controller
{
    IOLog("floppy initResources\n");

    // Store controller reference
    _controller = controller;

    // Allocate and initialize the queue lock
    _queueLock = [[NXConditionLock alloc] initWith:0];
    if (_queueLock == nil) {
        return IO_R_NO_MEMORY;
    }

    // Start the floppy thread
    _fdThread(self);

    return IO_R_SUCCESS;
}

/*
 * Raw read internal
 * Performs a raw sector read operation
 */
- (IOReturn)_rawReadInt:(unsigned)sector
              sectCount:(unsigned)sectCount
                 buffer:(void *)buffer
{
    FdCmdBuf cmdBuf;
    IOReturn result;
    unsigned int expectedBytes;
    unsigned int actualBytes;
    IOReturn status;

    IOLog("fd rawReadInt: sect %d count %d\n", sector, sectCount);

    // Clear command buffer
    bzero(&cmdBuf, sizeof(FdCmdBuf));

    // Generate read command
    [self _fdGenRwCmd:sector
           blockCount:sectCount
             fdIoReq:&cmdBuf
             readFlag:YES];

    // Set expected byte count
    expectedBytes = sectCount * _blockSize;

    // Set buffer pointer (store in result area for DMA transfer)
    // The buffer and byte count are likely stored in specific fields
    // Based on the decompiled code, these might be at specific offsets

    // Send the command
    result = [self _fdSendCmd:(unsigned char *)&cmdBuf];

    // Get actual bytes transferred and status
    // These would be returned in the command buffer
    actualBytes = expectedBytes;  // Placeholder
    status = cmdBuf.status;

    // Check if we got the expected number of bytes
    if ((result == IO_R_SUCCESS) && (actualBytes != expectedBytes)) {
        IOLog("rawReadInt: expected %d bytes; got %d\n",
              expectedBytes, actualBytes);
        status = 0x13;  // Error code
    }

    IOLog("rawReadInt: returning %s\n", _getResultName(status));

    return status;
}

/*
 * Read/write block count
 * Calculates actual blocks to transfer, limiting to track boundaries
 */
- (IOReturn)_rwBlockCount:(unsigned)block
               blockCount:(unsigned)blockCount
{
    fd_rw_cmd rwCmd;
    unsigned int blocksToDo;

    // Convert logical block to physical CHS
    [self _fdLogToPhys:block cmdp:&rwCmd];

    // Calculate blocks to do - limit to end of track
    blocksToDo = blockCount;

    // If requested blocks would exceed the track boundary
    // (sector + blockCount > sectors per track + 1)
    if ((_sectorsPerTrack + 1) < (rwCmd.sector + blockCount)) {
        // Limit to remaining sectors on this track
        blocksToDo = (_sectorsPerTrack - rwCmd.sector) + 1;
    }

    IOLog("rwBlockCount: block 0x%x blockCount 0x%x blocksToDo 0x%x\n",
          block, blockCount, blocksToDo);

    return blocksToDo;
}

/*
 * Timer event handler
 * Called by timer to check motor off condition
 */
- (void)_timerEvent
{
    FdBuffer *fdBuf;
    unsigned int *bufAsUInt;

    // Allocate an FdBuffer (synchronous operation)
    fdBuf = (FdBuffer *)[self _allocFdBuf:0];
    if (fdBuf == NULL) {
        return;
    }

    // Cast to unsigned int pointer for indexed access
    bufAsUInt = (unsigned int *)fdBuf;

    // Set command to 0x11 (motor off timer check)
    bufAsUInt[0] = 0x11;

    // Set flags: clear bit 31, set bit 29 (async operation)
    bufAsUInt[8] = (bufAsUInt[8] & 0x7fffffff) | 0x20000000;

    // Enqueue the buffer (async, will be freed by handler)
    [self _enqueueFdBuf:(id)fdBuf];
}

@end

/* End of FloppyDiskInt.m */
