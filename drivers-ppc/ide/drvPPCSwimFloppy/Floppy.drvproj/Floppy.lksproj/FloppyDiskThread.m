/*
 * FloppyDiskThread.m - FloppyDisk Thread category implementation
 *
 * Thread-based operations for floppy disk
 */

#import "FloppyDisk.h"
#import <driverkit/return.h>
#import <driverkit/debugging.h>
#import <string.h>
#import <objc/objc-runtime.h>

// Import structures from FloppyDiskInt.m
typedef struct _FdBuffer {
    void *reserved1;           // offset 0x00: command code
    void *reserved2;           // offset 0x04: I/O request pointer
    unsigned int actualLength; // offset 0x08: actual bytes transferred
    void *reserved4;           // offset 0x0c
    void *reserved5;           // offset 0x10: parameter pointer
    void *reserved6;           // offset 0x14
    id conditionLock;          // offset 0x18: NXConditionLock
    void *callback;            // offset 0x1c: callback parameter
    int flags;                 // offset 0x20: operation flags
    void *reserved7;           // offset 0x24
    int status;                // offset 0x28: I/O completion status
    struct _FdBuffer *prev;    // offset 0x2c: previous buffer
    struct _FdBuffer *next;    // offset 0x30: next buffer
} FdBuffer;

typedef struct _QueueHead {
    FdBuffer *first;
    FdBuffer *last;
} QueueHead;

// Command operation names for logging
static const char *_fdOpValues[] = {
    "FD_SEND_CMD", "FD_READ", "FD_WRITE", "FD_UNKNOWN3", "FD_EJECT",
    "FD_ABORT_ALL", "FD_UNKNOWN6", "FD_SET_DENSITY", "FD_SET_SECT_SIZE",
    "FD_SET_GAP", "FD_SET_INNER_RETRY", "FD_SET_OUTER_RETRY", "FD_GET_INNER_RETRY",
    "FD_GET_OUTER_RETRY", "FD_GET_FORMAT", "FD_UPDATE_PARAMS", "FD_TERMINATE",
    "FD_MOTOR_OFF_CHECK"
};

// Floppy disk result status names
static const char *_fdrValues[] = {
    "Success", "Retry", "Reserved", "Reserved", "Fatal", "Reserved",
    "Partial", "Reserved", "Reserved", "Reserved", "Reserved", "Reserved",
    "Reserved", "Reserved", "Reserved", "Reserved", "Reserved", "Reserved",
    "Reserved", "Fatal"
};

// Density value names
static const char *_densityValues[] = {
    "Auto", "500kbps", "300kbps", "1Mbps"
};

// Density info table: {density, capacity, isFormatted}
static int _fdDensityInfo[] = {
    1, 0xb4000, 1,   // 500kbps MFM: 720KB, formatted
    2, 0x168000, 1,  // 300kbps GCR: 1.44MB, formatted
    3, 0x168000, 1,  // 1Mbps MFM: 1.44MB, formatted
    0, 0, 0          // End marker
};

// Sector size info tables for different densities
// Format: {sectSize, gap, sectorsPerTrack, field4}

// 500kbps MFM (density 1) - 720KB format
static int _fdSectSizeInfo_500kbps[] = {
    0x200, 0x1b, 9, 2,    // 512 bytes, gap 0x1b, 9 sectors, code 2
    0, 0, 0, 0            // End marker
};

// 300kbps GCR (density 2) - 1.44MB format
static int _fdSectSizeInfo_300kbps[] = {
    0x200, 0x1b, 18, 2,   // 512 bytes, gap 0x1b, 18 sectors, code 2
    0, 0, 0, 0            // End marker
};

// 1Mbps MFM (density 3) - 1.44MB format
static int _fdSectSizeInfo_1Mbps[] = {
    0x200, 0x1b, 18, 2,   // 512 bytes, gap 0x1b, 18 sectors, code 2
    0, 0, 0, 0            // End marker
};

static const char *_getOpName(unsigned int opCode)
{
    if (opCode < sizeof(_fdOpValues) / sizeof(_fdOpValues[0])) {
        return _fdOpValues[opCode];
    }
    return "FD_UNKNOWN";
}

static const char *_getStatusName(unsigned int statusCode, const char **values)
{
    if (statusCode < 20) {
        return values[statusCode];
    }
    return "Unknown";
}

static int *_fdGetSectSizeInfo(unsigned int density)
{
    switch (density) {
    case 1:
        return _fdSectSizeInfo_500kbps;
    case 2:
        return _fdSectSizeInfo_300kbps;
    case 3:
        return _fdSectSizeInfo_1Mbps;
    default:
        return _fdSectSizeInfo_500kbps;  // Default to 720KB format
    }
}

extern void _IOExitThread(void);

@implementation FloppyDisk(Thread)

/*
 * Dispatch floppy disk command
 * Main command dispatcher for the floppy thread
 */
- (void)_fdCmdDispatch:(void *)command
{
    FdBuffer *fdBuf = (FdBuffer *)command;
    IOReturn result = IO_R_SUCCESS;
    unsigned int cmdCode;
    FdBuffer *currentBuf, *nextBuf, *prevBuf;
    QueueHead *queueHead;
    const char *cmdName;

    cmdCode = (unsigned int)fdBuf->reserved1;
    cmdName = _getOpName(cmdCode);

    IOLog("fdCmdDispatch: fdBuf 0x%x cmd = %s\n", (unsigned int)fdBuf, cmdName);

    switch (cmdCode) {
    case 0:  // FD_SEND_CMD - Send command to controller
        result = [self _fdSendCmd:(unsigned char *)fdBuf->reserved2];
        break;

    case 1:  // FD_READ - Read operation
    case 2:  // FD_WRITE - Write operation
        result = [self _fdRwCommon:fdBuf];
        break;

    case 4:  // FD_EJECT - Eject disk
        result = [self _fdEjectInt];
        break;

    case 5:  // FD_ABORT_ALL - Abort all pending requests
        [_queueLock lock];

        // Get queue head
        queueHead = &_priorityQueue;

        // Walk through all buffers in the priority queue
        if ((FdBuffer *)queueHead != queueHead->first) {
            currentBuf = queueHead->first;

            do {
                nextBuf = currentBuf->next;
                prevBuf = currentBuf->prev;

                // Remove from linked list
                if ((FdBuffer *)queueHead == prevBuf) {
                    queueHead->last = nextBuf;
                } else {
                    prevBuf->next = nextBuf;
                }

                if ((FdBuffer *)queueHead == nextBuf) {
                    queueHead->first = prevBuf;
                } else {
                    nextBuf->prev = prevBuf;
                }

                [_queueLock unlock];

                // Set error status (IO_R_NO_DISK = -1102 = 0xfffffbb2)
                currentBuf->status = (IOReturn)0xfffffbb2;

                // If there's an associated I/O request, mark it as error
                if (currentBuf->reserved2 != NULL) {
                    *((unsigned int *)currentBuf->reserved2 + 0x10) = 0x14;
                }

                // Complete the I/O
                [self _fdIoComplete:currentBuf];

                [_queueLock lock];

            } while ((FdBuffer *)queueHead != queueHead->first);
        }

        [_queueLock unlock];
        break;

    case 6:  // No operation
        break;

    case 7:  // FD_SET_DENSITY - Set media density
        result = [self _setDensityInt:*(unsigned int *)fdBuf->reserved5];
        break;

    case 8:  // FD_SET_SECT_SIZE - Set sector size
        result = [self _setSectSizeInt:*(unsigned int *)fdBuf->reserved5];
        break;

    case 9:  // FD_SET_GAP - Set gap length
        result = [self _setGapInt:*(unsigned int *)fdBuf->reserved5];
        break;

    case 10:  // FD_SET_INNER_RETRY - Set inner retry count
        _innerRetry = *(unsigned int *)fdBuf->reserved5;
        break;

    case 11:  // FD_SET_OUTER_RETRY - Set outer retry count
        _outerRetry = *(unsigned int *)fdBuf->reserved5;
        break;

    case 12:  // FD_GET_INNER_RETRY - Get inner retry count
    case 13:  // FD_GET_OUTER_RETRY - Get outer retry count
        *(unsigned int *)fdBuf->reserved5 = _innerRetry;
        break;

    case 14:  // FD_GET_FORMAT - Get format information
        IOLog("FDC_GET_FORMAT: in FloppyDiskThread.m\n");
        // Copy format info from offset 0x1b8 (52 bytes = 0x34)
        bcopy((char *)self + 0x1b8, fdBuf->reserved5, 0x34);
        break;

    case 15:  // FD_UPDATE_PARAMS - Update physical parameters
        result = [self _updatePhysicalParametersInt];
        break;

    case 16:  // FD_TERMINATE - Terminate I/O thread
        fdBuf->status = 0;
        IOLog("fdCmdDispatch: TERMINATING IO THREAD\n");
        [self _fdIoComplete:fdBuf];
        _IOExitThread();
        // Never returns
        break;

    case 17:  // FD_MOTOR_OFF_CHECK - Check motor off condition
        [self _motorOffCheck];
        break;

    default:
        IOLog("%s: Bogus fdBuf->command in fdCmdDispatch\n", [self name]);
        IOLog("FloppyThread\n");
        break;
    }

    // Handle completion
    if ((fdBuf->flags & 0x20000000) == 0) {
        // Synchronous operation - set status and complete
        fdBuf->status = result;
        IOLog("fdCmdDispatch: DONE: cmd = %s status = %s\n",
              cmdName, [self stringFromReturn:result]);
        [self _fdIoComplete:fdBuf];
    } else {
        // Asynchronous operation - free buffer
        IOLog("fdCmdDispatch: ASYNC; DONE: cmd = %s\n", cmdName);
        [self _freeFdBuf:(id)fdBuf];
    }
}

/*
 * Eject floppy disk internal
 */
- (IOReturn)_fdEjectInt
{
    BOOL isFatal = NO;
    int retryCount = 0;
    IOReturn result;
    unsigned char cmdBuf[96];
    unsigned int *statusPtr;

    while (1) {
        // Check if we've exceeded retry count
        if (_innerRetry < retryCount) {
            // All seek retries done, send eject command
            bzero(cmdBuf, 96);
            *(unsigned int *)(cmdBuf + 0x38) = 2;  // Eject command code

            result = [self _fdSendCmd:cmdBuf];

            if (result == IO_R_SUCCESS) {
                // Get status from command buffer
                statusPtr = (unsigned int *)(cmdBuf + 0x08);
                result = *statusPtr;
            }

            IOLog("fdEjectInt: returning %s\n", [self stringFromReturn:result]);

            // Set ready state: YES if success, NO if failure
            [self setLastReadyState:(result == IO_R_SUCCESS) ? YES : NO];

            return result;
        }

        // Try to seek to cylinder 0x4f (79)
        result = [self _fdSeek:0x4f head:0];

        if (result != IO_R_SUCCESS) {
            // Check if this is the last retry
            if (retryCount == _innerRetry) {
                isFatal = YES;
            }

            IOLog("%s seek: %s; %s\n",
                  [self name],
                  [self stringFromReturn:result],
                  isFatal ? "FATAL" : "RETRYING");

            if (isFatal) {
                return result;
            }
        }

        retryCount++;
    }
}

/*
 * Common read/write operation
 */
- (IOReturn)_fdRwCommon:(void *)ioReq
{
    FdBuffer *fdBuf = (FdBuffer *)ioReq;
    unsigned int startBlock, blockCount, remainingBlocks;
    void *buffer;
    unsigned int blockSize;
    BOOL isRead;
    int innerRetryCount = 0;
    int outerRetryCount = 0;
    BOOL hasRetried = NO;
    IOReturn result;
    unsigned char cmdBuf[96];
    int maxBlocks;
    int statusCode;
    unsigned int actualTransfer;
    unsigned int startTime[2], endTime[2];
    const char *methodName;

    // Extract parameters from FdBuffer structure
    startBlock = fdBuf->actualLength;           // Starting block number
    remainingBlocks = (unsigned int)fdBuf->reserved4;  // Block count
    buffer = fdBuf->reserved5;                  // Buffer pointer
    blockSize = _blockSize;                     // Block size (at offset 0x1d8)
    isRead = ((unsigned int)fdBuf->reserved1 == 1);  // 1=READ, 2=WRITE

    IOLog("fdRwCommon: block 0x%x count 0x%x\n", startBlock, remainingBlocks);

    // Get start timestamp
    IOGetTimestamp(startTime);

transfer_loop:
    while (remainingBlocks > 0) {
        // Get max blocks we can transfer (limited by track boundary)
        maxBlocks = [self _rwBlockCount:startBlock blockCount:remainingBlocks];

        // Generate read/write command
        [self _fdGenRwCmd:startBlock
               blockCount:maxBlocks
                 fdIoReq:cmdBuf
                readFlag:isRead];

        // Set up command buffer fields
        *(unsigned int *)(cmdBuf + 0x08) = 1;                    // Command type
        *(unsigned int *)(cmdBuf + 0x24) = maxBlocks * blockSize; // Transfer size
        *(void **)(cmdBuf + 0x20) = buffer;                      // Buffer pointer
        *(unsigned int *)(cmdBuf + 0x14) = (unsigned int)fdBuf->reserved6; // Client parameter

        // Send command to controller
        result = [self _fdSendCmd:cmdBuf];

        // Get status and actual transfer from command buffer
        statusCode = *(int *)(cmdBuf + 0x40);
        actualTransfer = *(unsigned int *)(cmdBuf + 0x48);

        // Adjust for partial transfers (status 6 with non-zero transfer)
        if ((statusCode == 6) && (actualTransfer != 0)) {
            actualTransfer = actualTransfer - blockSize;
        }

        // Update counters based on actual transfer
        remainingBlocks -= actualTransfer / blockSize;
        startBlock += actualTransfer / blockSize;
        buffer = (void *)((char *)buffer + actualTransfer);

        // Check if async operation (bit 30 = 0x40000000)
        if ((fdBuf->flags & 0x40000000) == 0) {
            // Synchronous operation - handle errors and retries
            if (result != IO_R_SUCCESS) {
                statusCode = 4;  // Force error status
            }

            switch (statusCode) {
            case 0:
                // Success - check if this was after retries
                if (hasRetried) {
                    IOLog("fdRwCommon: RETRY SUCCEEDED\n");
                    hasRetried = NO;
                    innerRetryCount = 0;
                    outerRetryCount = 0;

                    // Increment retry statistics
                    if (hasRetried) {
                        if (isRead) {
                            methodName = "incrementReadRetries";
                        } else {
                            methodName = "incrementWriteRetries";
                        }
                        objc_msgSend(self, sel_getUid(methodName));
                    }
                }
                // Continue to next block
                goto transfer_loop;

            case 1:   // Retriable errors
            case 6:
            case 7:
            case 8:
            case 9:
            case 0xb:
            case 0xc:
            case 0xe:
            case 0xf:
            case 0x10:
            case 0x13:
                // Mark that we're retrying
                if (!hasRetried) {
                    hasRetried = YES;
                }

                innerRetryCount++;

                if (innerRetryCount == _innerRetry) {
                    // Inner retry limit reached
                    outerRetryCount++;

                    if (outerRetryCount == _outerRetry) {
                        // Outer retry limit reached - fatal error
                        [self _logRwErr:(void *)"FATAL" block:startBlock status:statusCode readFlag:isRead];
                        goto error_exit;
                    }

                    // Recalibrate and reset inner retry
                    [self _logRwErr:(void *)"RECALIBRATING" block:startBlock status:statusCode readFlag:isRead];
                    [self _fdRecal];
                    innerRetryCount = 0;
                } else {
                    // Still have inner retries left
                    [self _logRwErr:(void *)"RETRYING" block:startBlock status:statusCode readFlag:isRead];
                }

                // Increment retry statistics
                if (hasRetried) {
                    if (isRead) {
                        methodName = "incrementReadRetries";
                    } else {
                        methodName = "incrementWriteRetries";
                    }
                    objc_msgSend(self, sel_getUid(methodName));
                }
                goto transfer_loop;  // Retry the operation

            default:
                // Non-retriable error - fatal
                [self _logRwErr:(void *)"FATAL" block:startBlock status:statusCode readFlag:isRead];
                goto error_exit;
            }
        }
    }

error_exit:
    // Set actual transfer size at offset 0x24
    *(unsigned int *)((char *)fdBuf + 0x24) =
        ((unsigned int)fdBuf->reserved4 - remainingBlocks) * blockSize;

    // Convert status code to IOReturn
    if (statusCode == 0) {
        result = IO_R_SUCCESS;
    } else {
        result = IO_R_IO;  // Generic I/O error
    }

    // Set status at offset 0x28
    fdBuf->status = result;

    if (statusCode == 0) {
        // Success - update performance metrics
        IOGetTimestamp(endTime);

        if (isRead) {
            methodName = "addToBytesRead:totalTime:latentTime:";
            objc_msgSend(self, sel_getUid(methodName),
                        *(unsigned int *)((char *)fdBuf + 0x24),
                        endTime[0] - (startTime[0] + (endTime[1] < startTime[1])),
                        endTime[1] - startTime[1],
                        0, 0);
        } else {
            methodName = "addToBytesWritten:totalTime:latentTime:";
            objc_msgSend(self, sel_getUid(methodName),
                        *(unsigned int *)((char *)fdBuf + 0x24),
                        endTime[0] - (startTime[0] + (endTime[1] < startTime[1])),
                        endTime[1] - startTime[1],
                        0, 0);
        }
    } else {
        // Error - increment error statistics
        if (isRead) {
            methodName = "incrementReadErrors";
        } else {
            methodName = "incrementWriteErrors";
        }
        objc_msgSend(self, sel_getUid(methodName));
    }

    IOLog("fdRwCommon: returning %s\n", [self stringFromReturn:result]);
    return result;
}

/*
 * Log read/write error
 */
- (void)_logRwErr:(void *)ioReq
            block:(unsigned)block
           status:(IOReturn)status
         readFlag:(BOOL)isRead
{
    const char *driveName;
    const char *statusName;
    const char *operation;
    const char *message = (const char *)ioReq;  // Error message like "RETRYING", "FATAL"

    driveName = [self name];
    statusName = _getStatusName(status, _fdrValues);
    operation = isRead ? "Read" : "Write";

    IOLog("%s: Sector %d cmd = %s; %s: %s\n",
          driveName, block, operation, statusName, message);
}

/*
 * Check motor off condition
 */
- (void)_motorOffCheck
{
    int readyState;
    unsigned int currentTime[2];
    unsigned int targetTime;
    unsigned char cmdBuf[96];

    // Check if disk is present
    readyState = objc_msgSend(self, sel_getUid("lastReadyState"));

    if (readyState == 2) {
        // No disk present, skip motor off
        IOLog("motorOffCheck:  no disk; quitting\n");
        return;
    }

    // Get current timestamp
    IOGetTimestamp(currentTime);

    // Calculate target time: saved timestamp + timeout (2 seconds)
    // Timestamp is at offset 0x1a4 (high) and 0x1a8 (low)
    targetTime = *(unsigned int *)((char *)self + 0x1a4) +
                 (0x88ca6bff < *(unsigned int *)((char *)self + 0x1a8) ? 1 : 0);

    // Check if current time is before target time
    if ((currentTime[0] < targetTime) ||
        ((currentTime[0] == targetTime) &&
         (currentTime[1] < (*(unsigned int *)((char *)self + 0x1a8) + 2000000000)))) {
        // Not time yet - schedule another timer callback
        IOLog("motorOffCheck: scheduling fdTimer\n");

        // Set timer scheduled flag (bit 31 at offset 0x1ac)
        *(unsigned int *)((char *)self + 0x1ac) |= 0x80000000;

        // Schedule timer callback in 2 seconds
        extern void _fdTimer(void *arg);
        IOScheduleFunc((IOThreadFunc)_fdTimer, self, 2);
    } else {
        // Time to turn motor off - send motor off command
        bzero(cmdBuf, 96);
        *(unsigned int *)(cmdBuf + 0x38) = 4;  // Motor off command code

        [self _fdSendCmd:cmdBuf];
    }
}

/*
 * Set density internal
 */
- (IOReturn)_setDensityInt:(unsigned)density
{
    BOOL isAutoDensity;
    const char *densityName;
    int *densityInfo;
    int densityValue, capacityValue, formattedValue;

    // Get density name for logging
    densityName = _getStatusName(density, _densityValues);
    IOLog("setDensityInt: density %s\n", densityName);

    // Check if auto-density (0)
    isAutoDensity = (density == 0);

    if (isAutoDensity) {
        // Use saved density value at offset 0x1c4
        density = *(unsigned int *)((char *)self + 0x1c4);
    }

    // Search density info table
    densityInfo = _fdDensityInfo;
    while (*densityInfo != 0) {
        if (*densityInfo == density) {
            break;
        }
        densityInfo += 3;  // Move to next entry (3 ints per entry)
    }

    // Extract values from table
    densityValue = densityInfo[0];
    capacityValue = densityInfo[1];
    formattedValue = densityInfo[2];

    // Set instance variables
    _density = densityValue;        // offset 0x1cc
    _capacity = capacityValue;      // offset 0x1d0
    _isFormatted = formattedValue;  // offset 0x1d4

    // Update sector size with current block size
    [self _setSectSizeInt:_blockSize];

    // If auto-density, clear bit 0 at offset 0x1c8
    if (isAutoDensity) {
        *(unsigned int *)((char *)self + 0x1c8) &= 0xfffffffe;
    }

    return IO_R_SUCCESS;
}

/*
 * Set gap internal
 */
- (IOReturn)_setGapInt:(unsigned)gap
{
    IOLog("setGapInt: rwGap = %d\n", gap);

    // Set gap value as byte at offset 0x1e4
    *(unsigned char *)((char *)self + 0x1e4) = (unsigned char)gap;

    return IO_R_SUCCESS;
}

/*
 * Set sector size internal
 */
- (IOReturn)_setSectSizeInt:(unsigned)sectSize
{
    int *sectSizeInfo;
    int savedSectorsPerTrack;
    int blockSize, gap, sectorsPerTrack, sectorSizeCode;
    unsigned int totalSectors;

    IOLog("setSectSizeInt: sectSize %d\n", sectSize);

    // Get sector size info table for current density
    sectSizeInfo = _fdGetSectSizeInfo(_density);

    // Check if table is valid
    if (*sectSizeInfo == 0) {
        return IO_R_INVALID_ARG;  // 0xfffffd3e
    }

    // Search for matching sector size
    while (*sectSizeInfo != 0) {
        if (sectSize == *sectSizeInfo) {
            break;
        }
        sectSizeInfo += 4;  // Move to next entry (4 ints per entry)
    }

    // If not found, return error
    if (*sectSizeInfo == 0) {
        return IO_R_INVALID_ARG;  // 0xfffffd3e
    }

    // Save current sectors per track
    savedSectorsPerTrack = _sectorsPerTrack;  // offset 0x1e0

    // Extract values from table
    blockSize = sectSizeInfo[0];
    gap = sectSizeInfo[1];
    sectorsPerTrack = sectSizeInfo[2];
    sectorSizeCode = sectSizeInfo[3];

    // Set instance variables
    _blockSize = blockSize;              // offset 0x1d8
    _gapLength = gap;                    // offset 0x1dc
    _sectorsPerTrack = sectorsPerTrack;  // offset 0x1e0
    _sectorSizeCode = sectorSizeCode;    // offset 0x1e4

    // Restore saved sectors per track
    _sectorsPerTrack = savedSectorsPerTrack;  // offset 0x1e0

    // Calculate total sectors: heads * sectorsPerTrack * cylinders
    // heads at offset 0x1bc, cylinders at offset 0x1c0
    totalSectors = _headsPerCylinder * savedSectorsPerTrack *
                   *(unsigned int *)((char *)self + 0x1c0);
    *(unsigned int *)((char *)self + 0x1e8) = totalSectors;

    // Set bit 0, clear bit 1 at offset 0x1c8
    *(unsigned int *)((char *)self + 0x1c8) =
        (*(unsigned int *)((char *)self + 0x1c8) & 0xfffffffd) | 1;

    // Update block and disk size
    objc_msgSend(self, sel_getUid("setBlockSize:"), sectSize);
    objc_msgSend(self, sel_getUid("setDiskSize:"),
                 _headsPerCylinder * _sectorsPerTrack *
                 *(unsigned int *)((char *)self + 0x1c0));

    return IO_R_SUCCESS;
}

/*
 * Unlock I/O queue lock
 */
- (void)_unlockIoQLock
{
    int readyState;
    int unlockValue;

    // Get disk ready state
    readyState = objc_msgSend(self, sel_getUid("lastReadyState"));

    // Check if both queues are empty
    // Normal queue at offset 0x18c, priority queue at offset 0x184
    // If queue is empty, first pointer points to queue head itself
    if ((_normalQueue.first == (FdBuffer *)&_normalQueue) &&
        ((_priorityQueue.first == (FdBuffer *)&_priorityQueue) || (readyState == 2))) {
        // Both queues empty OR no disk - unlock with 0
        unlockValue = 0;
    } else {
        // At least one queue has items - unlock with 1
        unlockValue = 1;
    }

    // Unlock the queue lock with appropriate value
    [_queueLock unlockWith:unlockValue];
}

/*
 * Update physical parameters internal
 */
- (IOReturn)_updatePhysicalParametersInt
{
    int isWriteProtected;
    unsigned int flags;

    IOLog("fd updatePhysicalParametersInt\n");

    // Set formatted to false initially
    objc_msgSend(self, sel_getUid("setFormattedInternal:"), 0);

    // Set busy flag in controller
    extern void _GetBusyFlag(void);
    _GetBusyFlag();

    // Get format info from controller into our format buffer at offset 0x1b8
    extern void _FloppyFormatInfo(void *formatInfo);
    _FloppyFormatInfo((char *)self + 0x1b8);

    // Copy detected density from offset 0x1c4 to current density at offset 0x1cc
    _density = *(unsigned int *)((char *)self + 0x1c4);

    // Mark as formatted
    objc_msgSend(self, sel_getUid("setFormattedInternal:"), 1);

    // Set sector size to 512 bytes
    [self _setSectSizeInt:0x200];

    // Set bit 0 at offset 0x1c8
    *(unsigned int *)((char *)self + 0x1c8) |= 1;

    // Check write protection status
    extern int _FloppyWriteProtected(void);
    isWriteProtected = _FloppyWriteProtected();

    // If 10 sectors per track, force write protected (special case)
    if (_sectorsPerTrack == 10) {
        isWriteProtected = 1;
    }

    // Set write protection state
    objc_msgSend(self, sel_getUid("setWriteProtected:"), isWriteProtected);

    // Update bit 2 at offset 0x1c8 based on write protection
    if (isWriteProtected == 0) {
        // Not write protected - clear bit 2
        flags = *(unsigned int *)((char *)self + 0x1c8) & 0xfffffffb;
    } else {
        // Write protected - set bit 2
        flags = *(unsigned int *)((char *)self + 0x1c8) | 4;
    }
    *(unsigned int *)((char *)self + 0x1c8) = flags;

    // Clear busy flag in controller
    extern void _ResetBusyFlag(void);
    _ResetBusyFlag();

    return IO_R_SUCCESS;
}

@end

/* End of FloppyDiskThread.m */
