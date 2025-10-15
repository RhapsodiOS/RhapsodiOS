/*
 * FloppyController_Device.m
 * Device management implementation for FloppyController
 */

#import "FloppyController_Device.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>

// FDC I/O port offsets
#define FDC_MSR     4  // Main Status Register
#define FDC_DATA    5  // Data Register

// MSR bits
#define MSR_RQM     0x80  // Request for Master
#define MSR_DIO     0x40  // Data Input/Output
#define MSR_BUSY    0x10  // FDC Busy

// FDC Commands
#define FDC_CMD_PERPENDICULAR 0x12  // Perpendicular mode command
#define FDC_CMD_SENSE_INT     0x08  // Sense interrupt status

@implementation FloppyController(Device)

- (IOReturn)getDmaStart:(void **)start
{
    if (start == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Return pointer to DMA buffer start address
    *start = (void *)_dmaBuffer;

    return IO_R_SUCCESS;
}

- (IOReturn)dmaDestruct:(void *)dmaInfo
{
    // Cleanup DMA resources if needed
    // For now, DMA buffer is managed by controller lifecycle
    // and freed in the -free method
    return IO_R_SUCCESS;
}

- (IOReturn)fcGetByte:(unsigned char *)byte
{
    return [self fdGetByte:byte];
}

- (IOReturn)fcSendByte:(unsigned char)byte
{
    return [self fdSendByte:byte];
}

- (IOReturn)fcWaitInt:(unsigned int)timeout
{
    unsigned int i;
    unsigned char msr;

    // Wait for interrupt/completion indicated by MSR
    // RQM set and DIO set means controller has data ready
    for (i = 0; i < timeout; i++) {
        msr = inb(_ioPortBase + FDC_MSR);

        // Check if controller is ready with data to read
        if ((msr & MSR_RQM) && (msr & MSR_DIO)) {
            return IO_R_SUCCESS;
        }

        IODelay(100);  // 100 microseconds
    }

    IOLog("FloppyController_Device: Timeout waiting for interrupt (MSR=0x%02x)\n", msr);
    return IO_R_TIMEOUT;
}

- (IOReturn)timeoutThread:(void *)arg
{
    // Timeout thread handler
    [self timeoutOccurred];
    return IO_R_SUCCESS;
}

- (IOReturn)thappyTimeout:(void *)arg
{
    // Alternative timeout handler name
    return [self timeoutThread:arg];
}

- (IOReturn)floppy_timeout:(unsigned int)ms
{
    [self setTimeout:ms];
    return IO_R_SUCCESS;
}

- (IOReturn)doPerpendicular:(unsigned int)gap
{
    unsigned char cmd[2];
    IOReturn status;
    int i;

    // Wait for controller ready
    for (i = 0; i < 1000; i++) {
        if (inb(_ioPortBase + FDC_MSR) & MSR_RQM) {
            break;
        }
        IODelay(1);
    }

    if (!(inb(_ioPortBase + FDC_MSR) & MSR_RQM)) {
        IOLog("FloppyController_Device: Timeout before PERPENDICULAR command\n");
        return IO_R_TIMEOUT;
    }

    // PERPENDICULAR MODE command (for 2.88MB drives)
    // Bit 0-1 = gap (00=normal, 01-11=perpendicular with different settings)
    cmd[0] = FDC_CMD_PERPENDICULAR;
    cmd[1] = gap & 0x03;  // Only bits 0-1 are valid

    status = [self sendCmd:cmd length:2];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Device: Failed to send PERPENDICULAR command\n");
    }

    return status;
}

- (IOReturn)flushIntFlags:(unsigned int *)flags
{
    unsigned char st0, cyl;
    int i;
    IOReturn status;

    // Flush any pending interrupts by issuing SENSE INTERRUPT STATUS
    // commands until the controller is clear
    for (i = 0; i < 4; i++) {
        // Wait for ready
        if (!(inb(_ioPortBase + FDC_MSR) & MSR_RQM)) {
            break;  // No more pending interrupts
        }

        // Send SENSE INTERRUPT command
        status = [self fdSendByte:FDC_CMD_SENSE_INT];
        if (status != IO_R_SUCCESS) {
            break;
        }

        // Read ST0
        status = [self fdGetByte:&st0];
        if (status != IO_R_SUCCESS) {
            break;
        }

        // Read current cylinder
        status = [self fdGetByte:&cyl];
        if (status != IO_R_SUCCESS) {
            break;
        }

        // Check if this was a valid interrupt status
        if ((st0 & 0xC0) == 0x80) {
            // Invalid command - no more pending interrupts
            break;
        }
    }

    // Return the last ST0 value as flags if requested
    if (flags != NULL) {
        *flags = st0;
    }

    return IO_R_SUCCESS;
}

@end
