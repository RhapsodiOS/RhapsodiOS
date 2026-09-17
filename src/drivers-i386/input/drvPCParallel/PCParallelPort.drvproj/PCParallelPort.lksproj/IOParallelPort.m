/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 *
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * IOParallelPort.m - Implementation for PC Parallel Port driver.
 *
 * HISTORY
 */

#import "IOParallelPort.h"
#import "IOParallelPortKern.h"
#import <driverkit/i386/ioPorts.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <driverkit/devsw.h>
#import <driverkit/generalFuncs.h>
#import <machkit/NXLock.h>
#import <sys/buf.h>
#import <sys/systm.h>
#import <string.h>

/*
 * Parallel-port specific returns.  The reference driver returns two codes that
 * <driverkit/return.h> has no name for: -737 (return.h spends that number on
 * IO_R_MSG_TOO_LARGE) and -738.  Every other code it returns is a stock
 * driverkit one - IO_R_IO (-714), IO_R_BUSY (-725), IO_R_TIMEOUT (-726).
 * Note that the reference never returns IO_R_OFFLINE (-727) or
 * IO_R_NOT_READY (-728); do not reach for those names here.
 */
#ifndef IO_R_NO_PAPER
#define IO_R_NO_PAPER (-737)
#endif
#ifndef IO_R_PRINTER_OFFLINE
#define IO_R_PRINTER_OFFLINE (-738)
#endif
/* Kernel sprintf lives in <sys/systm.h>; do not import <stdio.h> (conflicts). */
extern int sprintf(char *str, const char *fmt, ...);

@implementation IOParallelPort

//
// Class methods
//

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id instance;

    // Allocate a new instance
    instance = [self alloc];

    // Initialize it with the device description
    instance = [instance initFromDeviceDescription:deviceDescription];

    // Return YES if initialization succeeded, NO otherwise
    return (instance != nil);
}

//
// Initialization and probe
//

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOEISADeviceDescription *eisaDesc = (IOEISADeviceDescription *)deviceDescription;
    id configTable;
    const char *minorDevStr;
    const char *driverName;
    IORange *portRanges;
    BOOL validRange;
    int majorDev;
    char nameBuffer[12];

    // Call superclass initialization
    if ([super initFromDeviceDescription:deviceDescription] == nil)
        return [self free];

    // Get config table from device description
    configTable = [deviceDescription configTable];

    // Get minor device number from the config table
    minorDevStr = [configTable valueForStringKey:"Minor Device Number"];

    // Check if minor device number is "0"
    if (strcmp(minorDevStr, "0") != 0) {
        IOLog("Nonzero Minor Device Number - only one dev this version\n");
        return [self free];
    }

    // Get port ranges
    if ([eisaDesc numPortRanges] > 1) {
        IOLog("IOParallelPort not allocated: too many register ranges\n");
        return [self free];
    }

    // Get the port range list and validate address and size
    portRanges = [eisaDesc portRangeList];
    validRange = NO;
    switch (portRanges[0].start) {
    case 0x378:
    case 0x278:
        validRange = (portRanges[0].size == 8);
        break;
    case 0x3bc:
        validRange = (portRanges[0].size == 4);
        break;
    }

    if (!validRange) {
        IOLog("IOParallelPort not allocated: register range is invalid\n");
        return [self free];
    }

    // Set up register addresses
    dataRegister = (char *)portRanges[0].start;
    statusRegister = (char *)(portRanges[0].start + 1);
    controlRegister = (char *)(portRanges[0].start + 2);

    // Probe for controller
    if (![self probeForController]) {
        IOLog("IOParallelPort not allocated: controller not detected at address 0x%x\n",
              (unsigned short)portRanges[0].start);
        [configTable freeString:minorDevStr];
        return [self free];
    }

    // Add to character device switch (11 IOSwitchFunc args)
    majorDev = IOAddToCdevsw((void *)ppopen, (void *)ppclose, (void *)enodev,
                             (void *)ppwrite, (void *)ppioctl, (void *)enodev,
                             (void *)enodev, (void *)seltrue, (void *)enodev,
                             (void *)enodev, (void *)enodev);
    if (majorDev < 0) {
        IOLog("IOParallelPort: could not add to device switch\n");
        return [self free];
    }

    majorDevNum = majorDev;

    // Set device name (e.g., "pp0")
    sprintf(nameBuffer, "%s%s", "pp", minorDevStr);
    [self setName:nameBuffer];

    // Get and set driver name
    driverName = [configTable valueForStringKey:"Driver Name"];
    [self setDeviceKind:driverName];
    [configTable freeString:minorDevStr];
    [configTable freeString:driverName];

    [self setMinorDevNum:0];

    // Initialize device parameters
    busyMaxRetries = 10;
    busyRetryInterval = 1000;
    autofeedOutput = 0;
    IOThreadDelay = 1;
    intHandlerDelay = 1;
    minPhys = 0x200;       // 512 bytes
    blockSize = 0x200;     // 512 bytes
    writing = NO;

    // Publish this instance for the character device entry points
    pp_softc[0].device = self;

    // Set I/O timeout
    ioTimeout = 2000;

    // Create condition lock for the command queue and empty the queue
    ioQueueLock = [NXConditionLock new];
    ioQueue.prev = (struct queue_entry *)&ioQueue;
    ioQueue.next = (struct queue_entry *)&ioQueue;

    ioTaskThread = NULL;

    // Allocate buffers
    physbuf = (struct buf *)IOMalloc(0x80);            // 128 bytes
    interruptMessage = (msg_header_t *)IOMalloc(0x2000);  // 8192 bytes
    dataBuffer = IOMalloc(minPhys);

    // Create the buffer-size lock.  IODirectDevice's initFromDeviceDescription:
    // has already attached the interrupt port, which ran -attachInterruptPort
    // and forked the I/O thread.
    sizeLock = [[NXLock alloc] init];
    [sizeLock unlock];

    // Enable all interrupts
    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        IOLog("IOParallelPort: could not enable interrupts\n");
        return [self free];
    }

    // Register device.  -registerDevice returns nil on failure, not an IOReturn.
    if ([self registerDevice] == nil) {
        IOLog("IOParallelPort: could not register device\n");
        return [self free];
    }

    return self;
}

- (BOOL)probeForController
{
    unsigned char readBack;
    unsigned char controlValue;
    unsigned char readValue;

    readBack = inb(PP_PORT(controlRegister));

    controlValue &= 0xFE;
    controlValue |= 0x02;
    controlValue |= 0x04;
    controlValue |= 0x08;
    controlValue |= 0x10;
    controlValue &= 0xDF;
    outb(PP_PORT(controlRegister), controlValue);

    readValue = inb(PP_PORT(controlRegister));
    if ((readValue & 0x1F) != 0x1E) {
        return NO;
    }

    controlValue &= 0xFE;
    controlValue &= 0xFD;
    controlValue |= 0x04;
    controlValue &= 0xF7;
    controlValue &= 0xEF;
    controlValue &= 0xDF;
    outb(PP_PORT(controlRegister), controlValue);

    readValue = inb(PP_PORT(controlRegister));
    if ((readValue & 0x15) != 0x04) {
        return NO;
    }

    return YES;
}

- (IOReturn)initDevice
{
    unsigned char controlValue;
    unsigned char statusValue;
    BOOL isReady;

    controlValue &= 0xFE;
    controlValue &= 0xFD;
    controlValue |= (unsigned char)((autofeedOutput & 1) << 1);
    controlValue |= 0x04;
    controlValue |= 0x08;
    controlValue &= 0xEF;
    controlValue &= 0xDF;

    outb(PP_PORT(controlRegister), controlValue);

    // Read status register (initial check)
    statusValue = inb(PP_PORT(statusRegister));

    // Wait for device to be ready (non-blocking check)
    [self _waitForDevice:NO isReady:&isReady];

    // Set control register defaults with IRQ enabled
    controlValue |= PP_CONTROL_IRQ_EN;
    controlRegisterDefaults = controlValue;

    // Write control value with IRQ enabled
    outb(PP_PORT(controlRegister), controlValue);

    // Read status register again
    statusValue = inb(PP_PORT(statusRegister));

    // Check ERROR bit (bit 3, 0x08)
    if ((statusValue & PP_STATUS_ERROR) == 0) {
        // Error line is low (printer has an error condition)
        statusWord |= PP_SW_NO_ERROR;
        statusWord &= ~PP_SW_INITIALIZED;

        // Check for paper out (bit 5, 0x20)
        if (statusValue & PP_STATUS_PAPER_OUT) {
            statusWord |= PP_SW_PAPER_OUT;
            return IO_R_NO_PAPER;  // -737
        }

        // Check for offline/not selected (bit 4, 0x10)
        if ((statusValue & PP_STATUS_SELECT) == 0) {
            statusWord |= PP_SW_OFFLINE;
            return IO_R_PRINTER_OFFLINE;  // -738
        }

        // Check for busy (bit 7, 0x80)
        if (statusValue & PP_STATUS_BUSY) {
            statusWord |= PP_SW_BUSY;
            return IO_R_BUSY;  // -725
        }

        // If device indicated ready during wait
        if (isReady) {
            return IO_R_IO;  // -714
        }

        // Device not ready
        statusWord |= PP_SW_NOT_READY;
    } else {
        // Error line is high (normal idle state)
        if (isReady) {
            statusWord |= PP_SW_INITIALIZED;
            return IO_R_SUCCESS;
        }

        // Clear all status flags
        statusWord = 0;
    }

    // Device not ready error
    return IO_R_TIMEOUT;  // -726
}

- (IOReturn)printerInit
{
    unsigned char controlValue;

    // Get control register defaults and clear INIT bit (0x04)
    controlValue = controlRegisterDefaults & ~PP_CONTROL_INIT;

    // Write to control register with INIT low
    outb(PP_PORT(controlRegister), controlValue);

    // Wait 10 milliseconds
    IOSleep(10);

    // Set INIT bit high (restore normal operation)
    controlValue |= PP_CONTROL_INIT;
    outb(PP_PORT(controlRegister), controlValue);

    return IO_R_SUCCESS;
}

- free
{
    PPCommandBuffer *cmdBuffer;

    // If the I/O thread is running, send it the shutdown command
    if (ioTaskThread != NULL) {
        cmdBuffer = [self cmdBufAlloc];
        cmdBuffer->commandType = 1;  // Shutdown command
        [self cmdBufExec:cmdBuffer];
        [self cmdBufFree:cmdBuffer];
    }

    // Free physical buffer if allocated (128 bytes)
    if (physbuf != NULL) {
        IOFree(physbuf, 0x80);
    }

    // Free the interrupt receive buffer if allocated (8192 bytes)
    if (interruptMessage != NULL) {
        IOFree(interruptMessage, 0x2000);
    }

    // Free data buffer if allocated
    if (dataBuffer != NULL) {
        IOFree(dataBuffer, minPhys);
    }

    [sizeLock free];
    [ioQueueLock free];

    // Call superclass free
    return [super free];
}

//
// Register access
//

- (const char *)dataRegister
{
    return dataRegister;
}

- setDataRegister:(const char *)reg
{
    dataRegister = (char *)reg;
    return self;
}

- (const char *)statusRegister
{
    return statusRegister;
}

- setStatusRegister:(const char *)reg
{
    statusRegister = (char *)reg;
    return self;
}

- (const char *)controlRegister
{
    return controlRegister;
}

- setControlRegister:(const char *)reg
{
    controlRegister = (char *)reg;
    return self;
}

- (const char *)configRegister
{
    return configRegister;
}

- setConfigRegister:(const char *)reg
{
    configRegister = (char *)reg;
    return self;
}

//
// Register contents
//

- (unsigned char)controlRegisterContents
{
    // Read the current value from the hardware control register
    return inb(PP_PORT(controlRegister));
}

- (unsigned char)controlRegisterDefaults
{
    return controlRegisterDefaults;
}

- (unsigned char)statusRegisterContents
{
    // Read the current value from the hardware status register
    return inb(PP_PORT(statusRegister));
}

- (unsigned int)statusWord
{
    return statusWord;
}

- setStatusWord:(unsigned int)word
{
    statusWord = word;
    return self;
}

//
// Port I/O operations
//

- (IOReturn)readFromPort
{
    // Not implemented - always returns success
    return IO_R_SUCCESS;
}

- (IOReturn)writeToPort
{
    PPCommandBuffer *cmdBuffer;
    IOReturn returnCode;
    unsigned int status;

    // Mark a write as being in progress; the interrupt handler gates on this
    writing = YES;

    // Allocate command buffer
    cmdBuffer = [self cmdBufAlloc];

    // Set command type to 0 (write operation)
    cmdBuffer->commandType = 0;

    // Clear error flag
    cmdBuffer->errorFlag = 0;

    // Execute the command
    [self cmdBufExec:cmdBuffer];

    // Success unless an arm below propagates the command's return code
    returnCode = IO_R_SUCCESS;

    // Get current status word and clear bits 1-5 (0x3e)
    status = [self statusWord] & ~0x3E;

    // Set status bits based on the command's return code.  The arms are
    // selected by value: our IO_R_* comments state the expansion.
    switch (cmdBuffer->returnCode) {
    case IO_R_TIMEOUT:  // -726
        status |= PP_SW_NOT_READY;  // 0x10
        [self setStatusWord:status];
        break;

    case IO_R_PRINTER_OFFLINE:  // -738
        status |= PP_SW_OFFLINE;  // 0x08
        [self setStatusWord:status];
        break;

    case IO_R_NO_PAPER:  // -737
        status |= PP_SW_PAPER_OUT;  // 0x04
        [self setStatusWord:status];
        break;

    case IO_R_BUSY:  // -725
        status |= PP_SW_BUSY;  // 0x02
        [self setStatusWord:status];
        break;

    case IO_R_SUCCESS:  // 0
        [self setStatusWord:status];
        break;

    case IO_R_IO:  // -714
        status |= PP_SW_NO_ERROR;  // 0x20
        [self setStatusWord:status];
        returnCode = cmdBuffer->returnCode;
        break;

    default:
        // For unknown errors, keep the return code and leave the status word
        returnCode = cmdBuffer->returnCode;
        break;
    }

    // If error flag is set, add NO_ERROR bit
    if (cmdBuffer->errorFlag != 0) {
        [self setStatusWord:[self statusWord] | PP_SW_NO_ERROR];
    }

    // Free command buffer
    [self cmdBufFree:cmdBuffer];

    // The write is over
    writing = NO;

    return returnCode;
}

//
// Device properties
//

- (BOOL)isInitialized
{
    // Check if PP_SW_INITIALIZED bit (0x01) is set in statusWord
    return (statusWord & PP_SW_INITIALIZED) ? YES : NO;
}

- (BOOL)isInUse
{
    return inUse;
}

- setInUse:(BOOL)flag
{
    inUse = flag;
    return self;
}

- (BOOL)waitForever
{
    return waitForever;
}

- setWaitForever:(BOOL)flag
{
    waitForever = flag;
    return self;
}

- (int)autofeedOutput
{
    return autofeedOutput;
}

- setAutofeedOutput:(int)flag
{
    autofeedOutput = flag;
    return self;
}

//
// Device numbers
//

- (int)majorDevNum
{
    return majorDevNum;
}

- setMajorDevNum:(int)num
{
    majorDevNum = num;
    return self;
}

- (int)minorDevNum
{
    return minorDevNum;
}

- setMinorDevNum:(int)num
{
    minorDevNum = num;
    return self;
}

//
// Buffer management
//

- (unsigned int)blockSize
{
    return blockSize;
}

- setBlockSize:(unsigned int)size
{
    // Only reallocate if the size actually changes
    if (blockSize != size) {
        // Lock for thread safety
        [self lockSize];

        // Free old data buffer
        IOFree(dataBuffer, minPhys);

        // Set new sizes
        minPhys = size;
        blockSize = size;

        // Allocate new buffer
        dataBuffer = IOMalloc(minPhys);

        // Unlock
        [self unlockSize];
    }

    return self;
}

- lockSize
{
    [sizeLock lock];
    return self;
}

- unlockSize
{
    [sizeLock unlock];
    return self;
}

- (unsigned int)minPhys
{
    return minPhys;
}

- setMinPhys:(unsigned int)size
{
    // Only reallocate if the size actually changes
    if (minPhys != size) {
        // Lock for thread safety
        [self lockSize];

        // Free old data buffer
        IOFree(dataBuffer, minPhys);

        // Set new sizes
        minPhys = size;
        blockSize = size;

        // Allocate new buffer
        dataBuffer = IOMalloc(minPhys);

        // Unlock
        [self unlockSize];
    }

    return self;
}

- (void *)dataBuffer
{
    return dataBuffer;
}

- (struct buf *)physbuf
{
    return physbuf;
}

- setPhysbuf:(struct buf *)buf
{
    physbuf = buf;
    return self;
}

//
// Timing and retries
//

- (unsigned int)busyMaxRetries
{
    return busyMaxRetries;
}

- setBusyMaxRetries:(unsigned int)retries
{
    busyMaxRetries = retries;
    return self;
}

- (unsigned int)busyRetryInterval
{
    return busyRetryInterval;
}

- setBusyRetryInterval:(unsigned int)interval
{
    busyRetryInterval = interval;
    return self;
}

- (int)ioTimeout
{
    return ioTimeout;
}

- setIoTimeout:(int)timeout
{
    ioTimeout = timeout;
    return self;
}

- (unsigned int)intHandlerDelay
{
    return intHandlerDelay;
}

- setIntHandlerDelay:(unsigned int)delay
{
    intHandlerDelay = delay;
    return self;
}

- (unsigned int)IOThreadDelay
{
    return IOThreadDelay;
}

- setIOThreadDelay:(unsigned int)delay
{
    IOThreadDelay = delay;
    return self;
}

//
// Interrupt handling
//

- (IOReturn)attachInterruptPort
{
    IOReturn result;

    // Call superclass implementation
    result = [super attachInterruptPort];

    if (result == IO_R_SUCCESS) {
        // Fork a thread to handle I/O operations
        ioTaskThread = IOForkThread((IOThreadFunc)IOParallelPortThread, self);
    }

    return result;
}

- (msg_header_t *)interruptMessage
{
    return interruptMessage;
}

- setInterruptMessage:(msg_header_t *)msg
{
    interruptMessage = msg;
    return self;
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
            level:(unsigned int *)ipl
         argument:(unsigned int *)arg
     forInterrupt:(unsigned int)localInterrupt
{
    // Set the interrupt handler function
    *handler = (IOInterruptHandler)IOParallelPortInterruptHandler;

    // Set interrupt priority level to 3
    *ipl = 3;

    // The handler's third argument is the minor device number
    *arg = minorDevNum;

    return YES;
}

//
// Device waiting
//

- (BOOL)_waitForDevice:(BOOL)wait isReady:(BOOL *)isReady
{
    unsigned int tries = 0;
    unsigned char status;
    BOOL slept = NO;

    // Poll the status register for (BUSY|PAPER_OUT|SELECT|ERROR) == ready,
    // bounded by busyMaxRetries, or forever when the caller says so.
    while (busyMaxRetries > tries || wait == YES) {
        status = inb(PP_PORT(statusRegister));
        if ((status & 0xB8) == 0x98) {
            *isReady = YES;
            return slept;
        }

        IOSleep(busyRetryInterval);
        slept = YES;
        tries++;
    }

    *isReady = NO;
    return slept;
}

//
// Command buffer operations
//

- (PPCommandBuffer *)cmdBufAlloc
{
    PPCommandBuffer *cmdBuffer;

    // Allocate command buffer structure (0x1c = 28 bytes)
    cmdBuffer = (PPCommandBuffer *)IOMalloc(sizeof(PPCommandBuffer));

    // Create an NXConditionLock, lock it, then unlock with condition 0
    cmdBuffer->conditionLock = [NXConditionLock new];
    [cmdBuffer->conditionLock lock];
    [cmdBuffer->conditionLock unlockWith:0];

    return cmdBuffer;
}

- (void)cmdBufFree:(PPCommandBuffer *)cmdBuffer
{
    // Free the condition lock
    [cmdBuffer->conditionLock free];

    // Free the command buffer structure (0x1c = 28 bytes)
    IOFree(cmdBuffer, 0x1c);
}

- (void)cmdBufExec:(PPCommandBuffer *)cmdBuffer
{
    PPCommandBuffer *oldTail;

    // Lock the command queue
    [ioQueueLock lock];

    oldTail = (PPCommandBuffer *)ioQueue.prev;

    // Check if queue is empty (tail points to the queue head itself)
    if ((struct queue_entry *)&ioQueue == ioQueue.prev) {
        // Queue is empty, this becomes the first element
        ioQueue.next = (struct queue_entry *)cmdBuffer;
    } else {
        // Queue has elements, append to tail
        oldTail->link.next = (struct queue_entry *)cmdBuffer;
    }

    // Set up the new buffer's links
    cmdBuffer->link.prev = (struct queue_entry *)oldTail;
    cmdBuffer->link.next = (struct queue_entry *)&ioQueue;

    // Update tail to point to new buffer
    ioQueue.prev = (struct queue_entry *)cmdBuffer;

    // Unlock the command queue with condition 1
    [ioQueueLock unlockWith:1];

    // Wait for command to complete (lockWhen:1 waits for completion signal)
    [cmdBuffer->conditionLock lockWhen:1];

    // Unlock the command buffer
    [cmdBuffer->conditionLock unlock];
}

- (void)cmdBufComplete:(PPCommandBuffer *)cmdBuffer
{
    // Lock the command buffer's condition lock
    [cmdBuffer->conditionLock lock];

    // Unlock with condition 1 to signal completion
    [cmdBuffer->conditionLock unlockWith:1];
}

- (void *)waitForCmdBuf
{
    PPCommandBuffer *cmdBuffer;
    struct queue_entry *prevBuffer;
    struct queue_entry *nextBuffer;

    // Wait for a command buffer to be available (lockWhen:1)
    [ioQueueLock lockWhen:1];

    // Get the head of the command queue
    cmdBuffer = (PPCommandBuffer *)ioQueue.next;

    // Get previous and next pointers
    nextBuffer = cmdBuffer->link.next;
    prevBuffer = cmdBuffer->link.prev;

    // Update the queue pointers to remove this buffer
    if ((struct queue_entry *)&ioQueue == nextBuffer) {
        // This was last in queue, update tail
        ioQueue.prev = prevBuffer;
    } else {
        // Update next buffer's prev pointer
        ((PPCommandBuffer *)nextBuffer)->link.prev = prevBuffer;
    }

    if ((struct queue_entry *)&ioQueue != prevBuffer) {
        // Update previous buffer's next pointer
        ((PPCommandBuffer *)prevBuffer)->link.next = nextBuffer;
    } else {
        // This was first in queue, update head
        ioQueue.next = nextBuffer;
    }

    // Unlock with condition based on whether the queue is now empty
    if (ioQueue.next == (struct queue_entry *)&ioQueue)
        [ioQueueLock unlockWith:0];
    else
        [ioQueueLock unlockWith:1];

    return cmdBuffer;
}

//
// Parameter handling
//

- (IOReturn)getIntValues:(unsigned int *)values
            forParameter:(IOParameterName)parameterName
                   count:(unsigned int *)count
{
    unsigned int maxCount;

    // Set maxCount to the requested count, or default to 512 if 0
    maxCount = *count;
    if (maxCount == 0) {
        maxCount = 0x200;  // 512
    }

    // Check if parameter is "IOMajorDevice"
    if (strcmp(parameterName, "IOMajorDevice") == 0) {
        *values = majorDevNum;
        *count = 1;
        return IO_R_SUCCESS;
    }

    // Check if parameter is "IOMinorDevice"
    if (strcmp(parameterName, "IOMinorDevice") == 0) {
        *values = minorDevNum;
        *count = 1;
        return IO_R_SUCCESS;
    }

    // For other parameters, call superclass implementation
    return [super getIntValues:values forParameter:parameterName count:&maxCount];
}

//
// Message handling
//

//
// The PP_MSG_* names describe the interrupt message code, not the return code
// it maps to; the two do not line up.  The mapping below is the one the port
// actually implements, so the values are what matter here, not the names.
//
- (IOReturn)msgTypeToIOReturn:(int)msgType
{
    switch (msgType) {
    case PP_MSG_SUCCESS:      // 0x232325
        return IO_R_SUCCESS;  // 0

    case PP_MSG_NOT_READY:    // 0x232323
        return IO_R_TIMEOUT;  // -726 (0xfffffd2a)

    case PP_MSG_TIMEOUT:      // 0x232336
        return IO_R_IO;  // -714 (0xfffffd36)

    case PP_MSG_NO_PAPER:     // 0x232337
        return IO_R_NO_PAPER;  // -737 (0xfffffd1f)

    case PP_MSG_OFFLINE:      // 0x232339
        return IO_R_PRINTER_OFFLINE;  // -738 (0xfffffd1e)

    case PP_MSG_BUSY:         // 0x232338
        return IO_R_BUSY;  // -725 (0xfffffd2b)

    default:
        return IO_R_IO;  // -714 (0xfffffd36)
    }
}

@end
