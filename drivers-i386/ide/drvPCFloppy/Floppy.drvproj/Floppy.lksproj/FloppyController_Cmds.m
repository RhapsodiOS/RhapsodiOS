/*
 * FloppyController_Cmds.m
 * FDC command implementation for FloppyController
 */

#import "FloppyController_Cmds.h"
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
#define FDC_CMD_VERSION     0x10  // Get controller version
#define FDC_CMD_LOCK        0x94  // Lock FIFO
#define FDC_CMD_UNLOCK      0x14  // Unlock FIFO
#define FDC_CMD_DUMPREG     0x0E  // Dump registers
#define FDC_CMD_PERPENDICULAR 0x12 // Perpendicular mode

@implementation FloppyController(Cmds)

- (IOReturn)fdcSendCommand:(unsigned char *)cmd length:(unsigned int)len
{
    return [self sendCmd:cmd length:len];
}

- (IOReturn)fdcGetResult:(unsigned char *)result length:(unsigned int)len
{
    return [self getCmdResult:result length:len];
}

- (IOReturn)fdcSendByte:(unsigned char)byte
{
    return [self fdSendByte:byte];
}

- (IOReturn)fdcGetByte:(unsigned char *)byte
{
    return [self fdGetByte:byte];
}

- (IOReturn)fdcWaitReady
{
    int i;
    unsigned char msr;

    // Wait for controller to be ready (RQM bit set)
    for (i = 0; i < 10000; i++) {
        msr = inb(_ioPortBase + FDC_MSR);
        if (msr & MSR_RQM) {
            return IO_R_SUCCESS;
        }
        IODelay(1);
    }

    IOLog("FloppyController_Cmds: Timeout waiting for FDC ready (MSR=0x%02x)\n", msr);
    return IO_R_TIMEOUT;
}

- (IOReturn)fdcCheckStatus
{
    unsigned char msr;

    msr = [self fdcReadStatus];

    // Check if controller is busy
    if (msr & MSR_BUSY) {
        return IO_R_BUSY;
    }

    // Check if ready for command
    if (!(msr & MSR_RQM)) {
        return IO_R_NOT_READY;
    }

    return IO_R_SUCCESS;
}

- (unsigned char)fdcReadStatus
{
    return inb(_ioPortBase + FDC_MSR);
}

- (IOReturn)fdcSpecify
{
    return [self doSpecify];
}

- (IOReturn)fdcConfigure
{
    return [self doConfigure];
}

- (IOReturn)fdcVersion:(unsigned char *)version
{
    IOReturn status;

    if (version == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Wait for controller ready
    status = [self fdcWaitReady];
    if (status != IO_R_SUCCESS) {
        return status;
    }

    // Send VERSION command
    status = [self fdcSendByte:FDC_CMD_VERSION];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Cmds: Failed to send VERSION command\n");
        return status;
    }

    // Get version byte
    status = [self fdcGetByte:version];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Cmds: Failed to read VERSION result\n");
        return status;
    }

    return IO_R_SUCCESS;
}

- (IOReturn)fdcLock
{
    unsigned char cmd[1] = { FDC_CMD_LOCK };
    unsigned char result[1];
    IOReturn status;

    // Wait for controller ready
    status = [self fdcWaitReady];
    if (status != IO_R_SUCCESS) {
        return status;
    }

    // Send LOCK command
    status = [self fdcSendCommand:cmd length:1];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Cmds: Failed to send LOCK command\n");
        return status;
    }

    // Get result (bit 4 should be set if successful)
    status = [self fdcGetResult:result length:1];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Cmds: Failed to read LOCK result\n");
        return status;
    }

    // Check if lock was successful (bit 4 = locked)
    if (!(result[0] & 0x10)) {
        IOLog("FloppyController_Cmds: LOCK command failed (result=0x%02x)\n", result[0]);
        return IO_R_IO;
    }

    return IO_R_SUCCESS;
}

- (IOReturn)fdcUnlock
{
    unsigned char cmd[1] = { FDC_CMD_UNLOCK };
    unsigned char result[1];
    IOReturn status;

    // Wait for controller ready
    status = [self fdcWaitReady];
    if (status != IO_R_SUCCESS) {
        return status;
    }

    // Send UNLOCK command
    status = [self fdcSendCommand:cmd length:1];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Cmds: Failed to send UNLOCK command\n");
        return status;
    }

    // Get result (bit 4 should be clear if successful)
    status = [self fdcGetResult:result length:1];
    if (status != IO_R_SUCCESS) {
        IOLog("FloppyController_Cmds: Failed to read UNLOCK result\n");
        return status;
    }

    // Check if unlock was successful (bit 4 = 0 means unlocked)
    if (result[0] & 0x10) {
        IOLog("FloppyController_Cmds: UNLOCK command failed (result=0x%02x)\n", result[0]);
        return IO_R_IO;
    }

    return IO_R_SUCCESS;
}

@end
