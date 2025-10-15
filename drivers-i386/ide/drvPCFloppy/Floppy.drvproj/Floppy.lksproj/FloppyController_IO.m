/*
 * FloppyController_IO.m
 * I/O operation implementation for FloppyController
 */

#import "FloppyController_IO.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>

// FDC I/O port offsets
#define FDC_MSR     4  // Main Status Register
#define FDC_DATA    5  // Data Register

// MSR bits
#define MSR_RQM     0x80  // Request for Master
#define MSR_DIO     0x40  // Data Input/Output
#define MSR_BUSY    0x10  // FDC Busy

// Retry limits
#define MAX_RETRIES         3   // Maximum number of retry attempts
#define MAX_RECALIBRATE     2   // Maximum recalibrate attempts

@implementation FloppyController(IO)

- (IOReturn)performRead:(unsigned int)drive
               cylinder:(unsigned int)cyl
                   head:(unsigned int)head
                 sector:(unsigned int)sec
                 buffer:(void *)buffer
                 length:(unsigned int)length
                 client:(vm_task_t)client
{
    IOReturn status;
    int retries;

    // Validate parameters
    if (buffer == NULL || length == 0) {
        return IO_R_INVALID_ARG;
    }

    // Attempt read with retry logic
    for (retries = 0; retries < MAX_RETRIES; retries++) {
        status = [self doRead:drive cylinder:cyl head:head sector:sec buffer:buffer length:length];

        if (status == IO_R_SUCCESS) {
            return IO_R_SUCCESS;
        }

        // Log retry attempt
        IOLog("FloppyController_IO: Read failed (attempt %d/%d), status=0x%x\n",
              retries + 1, MAX_RETRIES, status);

        // Attempt recovery
        if (retries < MAX_RETRIES - 1) {
            [self recoverFromError:status];
            IOSleep(100);  // Wait before retry
        }
    }

    IOLog("FloppyController_IO: Read failed after %d attempts\n", MAX_RETRIES);
    return status;
}

- (IOReturn)performWrite:(unsigned int)drive
                cylinder:(unsigned int)cyl
                    head:(unsigned int)head
                  sector:(unsigned int)sec
                  buffer:(void *)buffer
                  length:(unsigned int)length
                  client:(vm_task_t)client
{
    IOReturn status;
    int retries;

    // Validate parameters
    if (buffer == NULL || length == 0) {
        return IO_R_INVALID_ARG;
    }

    // Attempt write with retry logic
    for (retries = 0; retries < MAX_RETRIES; retries++) {
        status = [self doWrite:drive cylinder:cyl head:head sector:sec buffer:buffer length:length];

        if (status == IO_R_SUCCESS) {
            return IO_R_SUCCESS;
        }

        // Log retry attempt
        IOLog("FloppyController_IO: Write failed (attempt %d/%d), status=0x%x\n",
              retries + 1, MAX_RETRIES, status);

        // Attempt recovery
        if (retries < MAX_RETRIES - 1) {
            [self recoverFromError:status];
            IOSleep(100);  // Wait before retry
        }
    }

    IOLog("FloppyController_IO: Write failed after %d attempts\n", MAX_RETRIES);
    return status;
}

- (IOReturn)setupTransfer:(void *)buffer
                   length:(unsigned int)length
                    write:(BOOL)isWrite
                   client:(vm_task_t)client
{
    vm_address_t dmaAddr;
    IOReturn status;

    // Validate parameters
    if (buffer == NULL || length == 0) {
        return IO_R_INVALID_ARG;
    }

    // Check if length exceeds DMA buffer size
    if (length > _dmaBufferSize) {
        IOLog("FloppyController_IO: Transfer length %d exceeds DMA buffer size %d\n",
              length, _dmaBufferSize);
        return IO_R_INVALID_ARG;
    }

    // Determine DMA address
    if ((vm_address_t)buffer != _dmaBuffer) {
        dmaAddr = _dmaBuffer;
        if (isWrite) {
            // Copy data to DMA buffer for write operations
            bcopy(buffer, (void *)dmaAddr, length);
        }
    } else {
        dmaAddr = (vm_address_t)buffer;
    }

    // Setup DMA controller for transfer
    status = [self setupDMA:dmaAddr length:length write:isWrite];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_IO: Failed to setup DMA transfer\n");
    }

    return status;
}

- (IOReturn)waitForTransferComplete
{
    unsigned int i;
    unsigned char msr;

    // Wait for FDC to signal transfer completion
    // RQM=1 and DIO=1 means controller has result bytes ready
    for (i = 0; i < 10000; i++) {
        msr = inb(_ioPortBase + FDC_MSR);

        // Check if controller is ready with result data
        if ((msr & MSR_RQM) && (msr & MSR_DIO)) {
            return IO_R_SUCCESS;
        }

        // Check if controller is not busy (possible error condition)
        if (!(msr & MSR_BUSY)) {
            // Controller stopped but not ready with data - possible error
            if (i > 100) {  // Give it some time initially
                IOLog("FloppyController_IO: Controller not busy but no result ready (MSR=0x%02x)\n", msr);
                return IO_R_IO;
            }
        }

        IODelay(100);  // 100 microseconds
    }

    IOLog("FloppyController_IO: Timeout waiting for transfer complete (MSR=0x%02x)\n", msr);
    return IO_R_TIMEOUT;
}

- (IOReturn)abortTransfer
{
    IOReturn status;

    IOLog("FloppyController_IO: Aborting transfer\n");

    // Turn off motor
    [self doMotorOff:_currentDrive];

    // Reset the controller to abort any pending transfer
    status = [self resetController];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_IO: Failed to reset controller during abort\n");
        return status;
    }

    return IO_R_SUCCESS;
}

- (IOReturn)retryOperation
{
    IOReturn status;
    int i;

    IOLog("FloppyController_IO: Retrying operation on drive %d\n", _currentDrive);

    // Sense interrupt status to clear any pending interrupts
    [self senseInterrupt];

    // Recalibrate the drive before retrying
    for (i = 0; i < MAX_RECALIBRATE; i++) {
        status = [self doRecalibrate:_currentDrive];
        if (status == IO_R_SUCCESS) {
            return IO_R_SUCCESS;
        }

        IOLog("FloppyController_IO: Recalibrate attempt %d failed\n", i + 1);
        IOSleep(50);  // Brief delay between recalibrate attempts
    }

    return status;
}

- (IOReturn)recoverFromError:(IOReturn)error
{
    IOReturn status;

    IOLog("FloppyController_IO: Attempting error recovery (error=0x%x)\n", error);

    // Sense and clear any pending interrupts
    [self senseInterrupt];

    // Reset controller to known state
    status = [self resetController];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_IO: Controller reset failed during recovery\n");
        return status;
    }

    // Recalibrate the current drive
    status = [self doRecalibrate:_currentDrive];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_IO: Drive recalibrate failed during recovery\n");
        return status;
    }

    IOLog("FloppyController_IO: Error recovery complete\n");
    return IO_R_SUCCESS;
}

@end
