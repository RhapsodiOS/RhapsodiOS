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
 * IOParallelPort.h - Interface for PC Parallel Port driver.
 *
 * HISTORY
 */

#ifndef _BSD_DEV_I386_IOPARALLELPORT_H_
#define _BSD_DEV_I386_IOPARALLELPORT_H_

#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <sys/types.h>

// Parallel Port Register Offsets
#define PP_DATA_REG      0   // Data Register (read/write)
#define PP_STATUS_REG    1   // Status Register (read)
#define PP_CONTROL_REG   2   // Control Register (read/write)
#define PP_CONFIG_REG    3   // Configuration Register (ECP/EPP mode)

// Status Register Bits
#define PP_STATUS_BUSY      0x80  // Busy (inverted)
#define PP_STATUS_ACK       0x40  // Acknowledge
#define PP_STATUS_PAPER_OUT 0x20  // Paper Out
#define PP_STATUS_SELECT    0x10  // Select
#define PP_STATUS_ERROR     0x08  // Error

// Control Register Bits
#define PP_CONTROL_DIR      0x20  // Direction (1=read, 0=write)
#define PP_CONTROL_IRQ_EN   0x10  // IRQ Enable
#define PP_CONTROL_SELECT   0x08  // Select Printer
#define PP_CONTROL_INIT     0x04  // Initialize Printer
#define PP_CONTROL_AUTOFEED 0x02  // Auto Linefeed
#define PP_CONTROL_STROBE   0x01  // Strobe

// Status Word Bits (error flags)
#define PP_SW_INITIALIZED   0x01  // Device initialized
#define PP_SW_BUSY          0x02  // Device busy
#define PP_SW_PAPER_OUT     0x04  // Paper out
#define PP_SW_OFFLINE       0x08  // Device offline/not selected
#define PP_SW_NOT_READY     0x10  // Device not ready
#define PP_SW_NO_ERROR      0x20  // No error (error line high)

// Message types for msgTypeToIOReturn
#define PP_MSG_NOT_READY    0x232323  // Device not ready
#define PP_MSG_SUCCESS      0x232325  // Success
#define PP_MSG_TIMEOUT      0x232336  // Timeout
#define PP_MSG_NO_PAPER     0x232337  // No paper
#define PP_MSG_BUSY         0x232338  // Busy
#define PP_MSG_OFFLINE      0x232339  // Offline

// Command buffer structure
typedef struct _PPCommandBuffer {
    id conditionLock;      // NXConditionLock object
    int commandType;       // Command type
    int reserved1;
    int returnCode;        // Return code
    unsigned char errorFlag;
    unsigned char reserved2[3];
    struct _PPCommandBuffer *next;  // Next in queue
    struct _PPCommandBuffer *prev;  // Previous in queue (or pointer to head)
} PPCommandBuffer;

@interface IOParallelPort : IODevice
{
    @private
    IORange         portRange;
    unsigned int    dataReg;
    unsigned int    statusReg;
    unsigned int    controlReg;
    unsigned int    configReg;

    unsigned char   controlRegContents;
    unsigned char   controlRegDefaults;
    unsigned short  statusWord;

    BOOL            autofeedOutput;
    BOOL            initialized;
    BOOL            inUse;

    int             majorDevNum;
    int             minorDevNum;

    unsigned int    blockSize;
    unsigned int    lockSize;
    unsigned int    unlockSize;
    unsigned int    minPhys;

    unsigned int    busyMaxRetries;
    unsigned int    busyRetryInterval;
    unsigned int    ioTimeout;
    unsigned int    intHandlerDelay;
    unsigned int    ioThreadDelay;

    id              cmdBufLock;        // NXConditionLock for command queue
    PPCommandBuffer *cmdBufHead;       // Head of command queue
    PPCommandBuffer *cmdBufTail;       // Tail of command queue

    unsigned int    threadID;          // Thread ID for I/O thread
    void           *physbuf;           // Physical buffer (128 bytes)
    void           *cmdBuf;            // Command buffer (8192 bytes)

    unsigned int    interruptMessage;
    unsigned int    physbufArg;        // Physbuf argument for interrupt handler
    void           *dataBuffer;        // Data buffer
    void           *interruptPortHandle;
    BOOL            waitForever;       // Wait forever flag (offset 0x18c)
}

// Class methods
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

// Initialization and probe
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (IOReturn)probeForController;
- (IOReturn)initDevice;
- (void)printerInit;
- (void)free;

// Register access
- (unsigned int)dataRegister;
- setDataRegister:(unsigned int)reg;
- (unsigned int)statusRegister;
- setStatusRegister:(unsigned int)reg;
- (unsigned int)controlRegister;
- setControlRegister:(unsigned int)reg;
- (unsigned int)configRegister;
- setConfigRegister:(unsigned int)reg;

// Register contents
- (unsigned char)controlRegisterContents;
- (unsigned char)controlRegisterDefaults;
- (unsigned char)statusRegisterContents;
- (unsigned short)statusWord;
- setStatusWord:(unsigned short)word;

// Port I/O operations
- (IOReturn)readFromPort;
- (IOReturn)writeToPort;

// Device properties
- (BOOL)isInitialized;
- (BOOL)isInUse;
- setInUse:(BOOL)flag;
- (BOOL)waitForever;
- setWaitForever:(BOOL)flag;
- (BOOL)autofeedOutput;
- setAutofeedOutput:(BOOL)flag;

// Device numbers
- (int)majorDevNum;
- setMajorDevNum:(int)num;
- (int)minorDevNum;
- setMinorDevNum:(int)num;

// Buffer management
- (unsigned int)blockSize;
- setBlockSize:(unsigned int)size;
- lockSize;
- unlockSize;
- (unsigned int)minPhys;
- setMinPhys:(unsigned int)size;
- (void *)dataBuffer;
- (void *)physbuf;
- setPhysbuf:(void *)buf;

// Timing and retries
- (unsigned int)busyMaxRetries;
- setBusyMaxRetries:(unsigned int)retries;
- (unsigned int)busyRetryInterval;
- setBusyRetryInterval:(unsigned int)interval;
- (unsigned int)ioTimeout;
- setIoTimeout:(unsigned int)timeout;
- (unsigned int)intHandlerDelay;
- setIntHandlerDelay:(unsigned int)delay;
- (unsigned int)IOThreadDelay;
- setIOThreadDelay:(unsigned int)delay;

// Interrupt handling
- (IOReturn)attachInterruptPort;
- (unsigned int)interruptMessage;
- setInterruptMessage:(unsigned int)msg;
- (void *)interruptPort;
- (BOOL)getHandler:(IOInterruptHandler *)handler
            level:(unsigned int *)ipl
         argument:(void **)arg
     forInterrupt:(unsigned int)localInterrupt;

// Device waiting
- (void)_waitForDevice:(BOOL)waitForever isReady:(BOOL *)isReady;

// Command buffer operations
- (void *)cmdBufAlloc;
- (void)cmdBufFree:(void *)buf;
- (IOReturn)cmdBufExec:(void *)buf;
- (void)cmdBufComplete:(void *)buf;
- (void *)waitForCmdBuf;

// Parameter handling
- (IOReturn)getIntValues:(unsigned int *)values
            forParameter:(IOParameterName)parameterName
                   count:(unsigned int *)count;

// Message handling
- (IOReturn)msgTypeToIOReturn:(int)msgType;

@end

#endif /* _BSD_DEV_I386_IOPARALLELPORT_H_ */
