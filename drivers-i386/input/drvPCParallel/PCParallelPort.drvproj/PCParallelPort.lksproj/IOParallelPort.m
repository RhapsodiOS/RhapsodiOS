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
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <driverkit/devsw.h>
#import <driverkit/generalFuncs.h>
#import <objc/objc.h>
#import <objc/objc-runtime.h>
#import <string.h>
#import <stdio.h>

// Global pointer to parallel port software control structure
static void *pp_softc = NULL;

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
    id configTable;
    const char *deviceName;
    const char *minorDevStr;
    const char *driverName;
    const char *location;
    unsigned int numRanges;
    IORange *portRanges;
    unsigned int baseAddr;
    unsigned int rangeSize;
    int majorDev;
    char nameBuffer[12];
    IOReturn result;

    // Call superclass initialization
    if ([super initFromDeviceDescription:deviceDescription] == nil)
        return nil;

    // Get config table from device description
    configTable = [deviceDescription configTable];

    // Get device name (like "ParallelPort0")
    deviceName = [deviceDescription name];

    // Extract minor device number (last character)
    minorDevStr = deviceName + strlen(deviceName) - 1;

    // Check if minor device number is "0"
    if (strcmp(minorDevStr, "0") != 0) {
        IOLog("Nonzero Minor Device Number - only one dev this version\n");
        [self free];
        return nil;
    }

    // Get port ranges
    numRanges = [deviceDescription numPortRanges];
    if (numRanges >= 2) {
        IOLog("IOParallelPort not allocated: too many register ranges\n");
        [self free];
        return nil;
    }

    // Get the port range list
    portRanges = [deviceDescription portRangeList];
    baseAddr = portRanges[0].start;
    rangeSize = portRanges[0].size;

    // Validate port address and size
    if ((baseAddr == 0x378 && rangeSize == 8) ||
        (baseAddr == 0x278 && rangeSize == 8) ||
        (baseAddr == 0x3bc && rangeSize == 4)) {
        // Valid port configuration

        // Set up register addresses
        dataReg = baseAddr;
        statusReg = baseAddr + 1;
        controlReg = baseAddr + 2;

        // Probe for controller
        if ([self probeForController] != IO_R_SUCCESS) {
            IOLog("IOParallelPort: parallel port at 0x%x not found\n", baseAddr);
            [configTable freeString:(char *)deviceName];
            [self free];
            return nil;
        }

        // Add to character device switch
        majorDev = IOAddToCdevsw((void *)ppopen, (void *)ppclose, (void *)enodev,
                                 (void *)ppwrite, (void *)ppioctl, (void *)enodev);
        if (majorDev < 0) {
            IOLog("IOParallelPort: could not add to device switch\n");
            [self free];
            return nil;
        }

        majorDevNum = majorDev;

        // Set device name (e.g., "pp0")
        sprintf(nameBuffer, "%s%s", "pp", minorDevStr);
        [self setName:nameBuffer];

        // Get and set driver name
        driverName = [configTable valueForStringKey:"Driver Name"];
        [self setDriverName:driverName];
        [configTable freeString:(char *)driverName];

        // Set location
        location = [configTable valueForStringKey:"Location"];
        [self setLocation:location];
        [configTable freeString:(char *)location];

        // Initialize device parameters
        busyMaxRetries = 10;
        busyRetryInterval = 1000;
        autofeedOutput = NO;
        waitForever = NO;
        initialized = NO;
        blockSize = 0x200;     // 512 bytes
        minPhys = 0x200;       // 512 bytes
        inUse = NO;

        // Set global software control pointer
        pp_softc = (void *)self;

        // Set I/O timeout
        ioTimeout = 2000;

        // Create condition lock for command queue
        cmdBufLock = [objc_getClass("NXConditionLock") new];

        // Initialize command queue (circular linked list)
        cmdBufTail = (PPCommandBuffer *)&cmdBufHead;
        cmdBufHead = (PPCommandBuffer *)&cmdBufHead;

        threadID = 0;

        // Allocate buffers
        physbuf = IOMalloc(0x80);      // 128 bytes
        cmdBuf = IOMalloc(0x2000);     // 8192 bytes
        dataBuffer = IOMalloc(blockSize);

        // Create interrupt port
        result = [self attachInterruptPort];
        if (result != IO_R_SUCCESS) {
            IOLog("IOParallelPort: could not enable interrupts\n");
            [self free];
            return nil;
        }

        interruptPortHandle = [self interruptPort];

        // Set interrupt message type
        [self setInterruptMessage:0x54e];

        // Enable all interrupts
        result = [self enableAllInterrupts];
        if (result != IO_R_SUCCESS) {
            IOLog("IOParallelPort: could not enable interrupts\n");
            [self free];
            return nil;
        }

        // Register device
        result = [self registerDevice];
        if (result != IO_R_SUCCESS) {
            IOLog("IOParallelPort: could not register device\n");
            [self free];
            return nil;
        }

        return self;
    }

    // Invalid port range
    IOLog("IOParallelPort not allocated: register range is invalid\n");
    [self free];
    return nil;
}

- (IOReturn)probeForController
{
    unsigned char controlValue;
    unsigned char readValue;

    // Read current control register value
    controlValue = inb(controlReg);

    // Set control register to test pattern 0x1e
    // (SELECT=0x08, INIT=0x04, AUTOFEED=0x02, preserve other bits)
    controlValue = (controlValue & 0xDE) | 0x1E;
    outb(controlReg, controlValue);

    // Read back and verify
    readValue = inb(controlReg);
    if ((readValue & 0x1F) != 0x1E) {
        return IO_R_UNSUPPORTED;
    }

    // Set control register to different test pattern 0x04
    // (only INIT set, SELECT and AUTOFEED cleared)
    controlValue = (controlValue & 0xE5) | 0x04;
    outb(controlReg, controlValue);

    // Read back and verify
    readValue = inb(controlReg);
    if ((readValue & 0x15) != 0x04) {
        return IO_R_UNSUPPORTED;
    }

    // Controller found and verified
    return IO_R_SUCCESS;
}

- (IOReturn)initDevice
{
    unsigned char controlValue;
    unsigned char statusValue;
    BOOL isReady = NO;

    // Setup control register value:
    // - Set SELECT (0x08) and INIT (0x04) bits
    // - Set AUTOFEED (0x02) if enabled
    controlValue = PP_CONTROL_SELECT | PP_CONTROL_INIT;
    if (autofeedOutput) {
        controlValue |= PP_CONTROL_AUTOFEED;
    }

    // Write initial control value
    outb(controlReg, controlValue);

    // Read status register (initial check)
    statusValue = inb(statusReg);

    // Wait for device to be ready (non-blocking check)
    [self _waitForDevice:NO isReady:&isReady];

    // Set control register defaults with IRQ enabled
    controlRegDefaults = controlValue | PP_CONTROL_IRQ_EN;

    // Write control value with IRQ enabled
    outb(controlReg, controlRegDefaults);

    // Read status register again
    statusValue = inb(statusReg);

    // Check ERROR bit (bit 3, 0x08)
    if ((statusValue & PP_STATUS_ERROR) == 0) {
        // Error line is low (printer has no error condition)
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
            return IO_R_OFFLINE;  // -738
        }

        // Check for busy (bit 7, 0x80)
        if (statusValue & PP_STATUS_BUSY) {
            statusWord |= PP_SW_BUSY;
            return IO_R_BUSY;  // -725
        }

        // If device indicated ready during wait
        if (isReady) {
            return IO_R_TIMEOUT;  // -714
        }

        // Device not ready
        statusWord |= PP_SW_NOT_READY;
    } else {
        // Error line is high (normal idle state)
        if (isReady) {
            statusWord |= PP_SW_INITIALIZED;
            initialized = YES;
            return IO_R_SUCCESS;
        }

        // Clear all status flags
        statusWord = 0;
    }

    // Device not ready error
    return IO_R_NOT_READY;  // -726
}

- (void)printerInit
{
    unsigned char controlValue;

    // Get control register defaults and clear INIT bit (0x04)
    controlValue = controlRegDefaults & ~PP_CONTROL_INIT;

    // Write to control register with INIT low
    outb(controlReg, controlValue);

    // Wait 10 milliseconds
    IOSleep(10);

    // Set INIT bit high (restore normal operation)
    outb(controlReg, controlValue | PP_CONTROL_INIT);
}

- (void)free
{
    PPCommandBuffer *cmdBuffer;

    // If I/O thread is running, send shutdown command
    if (threadID != 0) {
        cmdBuffer = (PPCommandBuffer *)[self cmdBufAlloc];
        if (cmdBuffer != NULL) {
            cmdBuffer->commandType = 1;  // Shutdown command
            [self cmdBufExec:cmdBuffer];
            [self cmdBufFree:cmdBuffer];
        }
    }

    // Free physical buffer if allocated (128 bytes)
    if (physbuf != NULL) {
        IOFree(physbuf, 0x80);
        physbuf = NULL;
    }

    // Free command buffer if allocated (8192 bytes)
    if (cmdBuf != NULL) {
        IOFree(cmdBuf, 0x2000);
        cmdBuf = NULL;
    }

    // Free data buffer if allocated
    if (dataBuffer != NULL) {
        IOFree(dataBuffer, blockSize);
        dataBuffer = NULL;
    }

    // Free interrupt port handle if exists
    if (interruptPortHandle != NULL) {
        [interruptPortHandle free];
        interruptPortHandle = NULL;
    }

    // Free command buffer lock
    if (cmdBufLock != nil) {
        [cmdBufLock free];
        cmdBufLock = nil;
    }

    // Call superclass free
    [super free];
}

//
// Register access
//

- (unsigned int)dataRegister
{
    return dataReg;
}

- setDataRegister:(unsigned int)reg
{
    dataReg = reg;
    return self;
}

- (unsigned int)statusRegister
{
    return statusReg;
}

- setStatusRegister:(unsigned int)reg
{
    statusReg = reg;
    return self;
}

- (unsigned int)controlRegister
{
    return controlReg;
}

- setControlRegister:(unsigned int)reg
{
    controlReg = reg;
    return self;
}

- (unsigned int)configRegister
{
    return configReg;
}

- setConfigRegister:(unsigned int)reg
{
    configReg = reg;
    return self;
}

//
// Register contents
//

- (unsigned char)controlRegisterContents
{
    // Read the current value from the hardware control register
    return inb(controlReg);
}

- (unsigned char)controlRegisterDefaults
{
    return controlRegDefaults;
}

- (unsigned char)statusRegisterContents
{
    // Read the current value from the hardware status register
    return inb(statusReg);
}

- (unsigned short)statusWord
{
    return statusWord;
}

- setStatusWord:(unsigned short)word
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
    unsigned short status;

    // Mark device as in use
    inUse = YES;

    // Allocate command buffer
    cmdBuffer = (PPCommandBuffer *)[self cmdBufAlloc];

    // Set command type to 0 (write operation)
    cmdBuffer->commandType = 0;

    // Clear error flag
    cmdBuffer->errorFlag = 0;

    // Execute the command
    [self cmdBufExec:cmdBuffer];

    // Get current status word and clear bits 1-5 (0x3e)
    status = [self statusWord];
    status = status & 0xFFC1;  // Keep only bits 0, 6, 7, and 8+

    // Set status bits based on return code
    returnCode = cmdBuffer->returnCode;

    switch (returnCode) {
    case IO_R_NOT_READY:  // -726 (0xfffffd2a = -0x2d6)
        status |= PP_SW_NOT_READY;  // 0x10
        break;

    case IO_R_OFFLINE:  // -738 (0xfffffd1e = -0x2e2)
        status |= PP_SW_OFFLINE;  // 0x08
        break;

    case IO_R_NO_PAPER:  // -737 (0xfffffd1f = -0x2e1)
        status |= PP_SW_PAPER_OUT;  // 0x04
        break;

    case IO_R_TIMEOUT:  // -714 (0xfffffd36 = -0x2ca)
        status |= PP_SW_NO_ERROR;  // 0x20
        returnCode = cmdBuffer->returnCode;  // Keep original return code
        break;

    case IO_R_BUSY:  // -725 (0xfffffd2b = -0x2d5)
        status |= PP_SW_BUSY;  // 0x02
        break;

    case IO_R_SUCCESS:  // 0
        // No additional status bits
        break;

    default:
        // For unknown errors, keep return code
        returnCode = cmdBuffer->returnCode;
        break;
    }

    // Update status word
    [self setStatusWord:status];

    // If error flag is set, add NO_ERROR bit
    if (cmdBuffer->errorFlag != 0) {
        status = [self statusWord];
        [self setStatusWord:status | PP_SW_NO_ERROR];
    }

    // Free command buffer
    [self cmdBufFree:cmdBuffer];

    // Mark device as not in use
    inUse = NO;

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

- (BOOL)autofeedOutput
{
    return autofeedOutput;
}

- setAutofeedOutput:(BOOL)flag
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
    // Only reallocate if size is different from current unlockSize
    if (unlockSize != size) {
        // Lock for thread safety
        [self lockSize];

        // Free old data buffer
        if (dataBuffer != NULL) {
            IOFree(dataBuffer, blockSize);
        }

        // Set new sizes
        blockSize = size;
        unlockSize = size;

        // Allocate new buffer
        dataBuffer = IOMalloc(blockSize);

        // Unlock
        [self unlockSize];
    }

    return self;
}

- lockSize
{
    // Lock the interrupt port handle and return self
    [interruptPortHandle lock];
    return self;
}

- unlockSize
{
    // Unlock the interrupt port handle and return self
    [interruptPortHandle unlock];
    return self;
}

- (unsigned int)minPhys
{
    return minPhys;
}

- setMinPhys:(unsigned int)size
{
    // Only reallocate if size is different from current blockSize
    if (blockSize != size) {
        // Lock for thread safety
        [self lockSize];

        // Free old data buffer
        if (dataBuffer != NULL) {
            IOFree(dataBuffer, blockSize);
        }

        // Set new sizes (minPhys is stored in blockSize ivar at offset 0x158)
        blockSize = size;
        unlockSize = size;

        // Allocate new buffer
        dataBuffer = IOMalloc(blockSize);

        // Unlock
        [self unlockSize];
    }

    return self;
}

- (void *)dataBuffer
{
    return dataBuffer;
}

- (void *)physbuf
{
    return physbuf;
}

- setPhysbuf:(void *)buf
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

- (unsigned int)ioTimeout
{
    return ioTimeout;
}

- setIoTimeout:(unsigned int)timeout
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
    return ioThreadDelay;
}

- setIOThreadDelay:(unsigned int)delay
{
    ioThreadDelay = delay;
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
        threadID = IOForkThread((void (*)(id))IOParallelPortThread, self);
    }

    return result;
}

- (unsigned int)interruptMessage
{
    return interruptMessage;
}

- setInterruptMessage:(unsigned int)msg
{
    interruptMessage = msg;
    return self;
}

- (void *)interruptPort
{
    return interruptPortHandle;
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
            level:(unsigned int *)ipl
         argument:(void **)arg
     forInterrupt:(unsigned int)localInterrupt
{
    // Set the interrupt handler function
    *handler = (IOInterruptHandler)IOParallelPortInterruptHandler;

    // Set interrupt priority level to 3
    *ipl = 3;

    // Set the argument to physbufArg (contains physbuf pointer value)
    *arg = (void *)physbufArg;

    return YES;
}

//
// Device waiting
//

- (void)_waitForDevice:(BOOL)waitForever isReady:(BOOL *)isReady
{
    // TODO: Implement device waiting logic
    // - If waitForever is YES, wait indefinitely for device to become ready
    // - If waitForever is NO, check device status and return immediately
    // - Set *isReady to YES if device is ready, NO otherwise
    // - Read status register and check for ready conditions

    if (isReady != NULL) {
        *isReady = NO;  // Default to not ready
    }
}

//
// Command buffer operations
//

- (void *)cmdBufAlloc
{
    PPCommandBuffer *cmdBuffer;
    id conditionLock;

    // Allocate command buffer structure (0x1c = 28 bytes)
    cmdBuffer = (PPCommandBuffer *)IOMalloc(sizeof(PPCommandBuffer));
    if (cmdBuffer == NULL)
        return NULL;

    // Create an NXConditionLock
    conditionLock = [objc_getClass("NXConditionLock") new];
    cmdBuffer->conditionLock = conditionLock;

    // Lock and then unlock with condition 0
    [conditionLock lock];
    [conditionLock unlockWith:0];

    return cmdBuffer;
}

- (void)cmdBufFree:(void *)buf
{
    PPCommandBuffer *cmdBuffer = (PPCommandBuffer *)buf;

    // Free the condition lock
    [cmdBuffer->conditionLock free];

    // Free the command buffer structure (0x1c = 28 bytes = sizeof(PPCommandBuffer))
    IOFree(buf, 0x1c);
}

- (IOReturn)cmdBufExec:(void *)buf
{
    PPCommandBuffer *cmdBuffer = (PPCommandBuffer *)buf;
    PPCommandBuffer *oldTail;

    // Lock the command queue
    [cmdBufLock lock];

    oldTail = cmdBufTail;

    // Check if queue is empty (tail points to head slot)
    if ((PPCommandBuffer *)&cmdBufHead == oldTail) {
        // Queue is empty, this becomes the first element
        cmdBufHead = cmdBuffer;
    } else {
        // Queue has elements, append to tail
        oldTail->next = cmdBuffer;
    }

    // Set up the new buffer's links
    cmdBuffer->next = (PPCommandBuffer *)&cmdBufHead;  // Back reference to queue head
    cmdBuffer->prev = oldTail;  // Previous element (or head slot if first)

    // Update tail to point to new buffer
    cmdBufTail = cmdBuffer;

    // Unlock the command queue with condition 1
    [cmdBufLock unlockWith:1];

    // Wait for command to complete (lockWhen:1 waits for completion signal)
    [cmdBuffer->conditionLock lockWhen:1];

    // Unlock the command buffer
    [cmdBuffer->conditionLock unlock];

    return IO_R_SUCCESS;
}

- (void)cmdBufComplete:(void *)buf
{
    PPCommandBuffer *cmdBuffer = (PPCommandBuffer *)buf;

    // Lock the command buffer's condition lock
    [cmdBuffer->conditionLock lock];

    // Unlock with condition 1 to signal completion
    [cmdBuffer->conditionLock unlockWith:1];
}

- (void *)waitForCmdBuf
{
    PPCommandBuffer *cmdBuffer;
    PPCommandBuffer *prevBuffer;
    PPCommandBuffer *nextBuffer;

    // Wait for a command buffer to be available (lockWhen:1)
    [cmdBufLock lockWhen:1];

    // Get the head of the command queue
    cmdBuffer = cmdBufHead;

    // Get previous and next pointers
    prevBuffer = cmdBuffer->prev;
    nextBuffer = cmdBuffer->next;

    // Update the queue pointers to remove this buffer
    if ((PPCommandBuffer *)&cmdBufHead == prevBuffer) {
        // This was first in queue, update tail
        cmdBufTail = nextBuffer;
    } else {
        // Update previous buffer's next pointer
        prevBuffer->next = nextBuffer;
    }

    if ((PPCommandBuffer *)&cmdBufHead == nextBuffer) {
        // This was last in queue, update head
        cmdBufHead = prevBuffer;
    } else {
        // Update next buffer's prev pointer
        nextBuffer->prev = prevBuffer;
    }

    // Unlock with condition based on whether queue is now empty
    // Condition 1 if queue not empty, 0 if empty
    [cmdBufLock unlockWith:(cmdBufHead != (PPCommandBuffer *)&cmdBufHead) ? 1 : 0];

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

- (IOReturn)msgTypeToIOReturn:(int)msgType
{
    switch (msgType) {
    case PP_MSG_SUCCESS:      // 0x232325
        return IO_R_SUCCESS;  // 0

    case PP_MSG_NOT_READY:    // 0x232323
        return IO_R_NOT_READY;  // -726 (0xfffffd2a)

    case PP_MSG_TIMEOUT:      // 0x232336
        return IO_R_TIMEOUT;  // -714 (0xfffffd36)

    case PP_MSG_NO_PAPER:     // 0x232337
        return IO_R_NO_PAPER;  // -737 (0xfffffd1f)

    case PP_MSG_BUSY:         // 0x232338
        return IO_R_BUSY;  // -725 (0xfffffd2b)

    case PP_MSG_OFFLINE:      // 0x232339
        return IO_R_OFFLINE;  // -738 (0xfffffd1e)

    default:
        return IO_R_TIMEOUT;  // -714 (0xfffffd36)
    }
}

@end
