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
#import <driverkit/i386/driverTypes.h>
#import <driverkit/IODirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <mach/message.h>
#import <sys/types.h>

struct buf;
struct queue_entry;

/*
 * The four register ivars hold I/O port addresses but are typed `char *`,
 * as the reference does (ivar encoding `*`, accessor encoding `r*`).
 * inb()/outb() want an IOEISAPortAddress, and the reference narrows to
 * 16 bits at every port access.
 */
#define PP_PORT(reg)	((IOEISAPortAddress)(unsigned int)(reg))

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

/*
 * Command buffer, 28 bytes.  The layout is the reference's, read from the
 * argument encoding of -cmdBufExec: —
 * `^{?=@i*ic{?=^{queue_entry}^{queue_entry}}}`.  The struct is anonymous and
 * the two links are typed `struct queue_entry *`, so the buffers are chained
 * by their base address and reached through `link`.
 */
typedef struct {
    id              conditionLock;      // +0x00  NXConditionLock
    int             commandType;        // +0x04  0 = write, 1 = shut down
    char           *dataPtr;            // +0x08  unused by the reference
    int             returnCode;         // +0x0c
    char            errorFlag;          // +0x10
    struct {
        struct queue_entry *next;       // +0x14
        struct queue_entry *prev;       // +0x18
    } link;
} PPCommandBuffer;

@interface IOParallelPort : IODirectDevice
{
    /*
     * 27 ivars, in the reference's order, at the reference's offsets:
     * IODirectDevice ends at 0x128 and the class is 404 bytes.
     *
     * @public because the reference's _strobeChar and interrupt handler read
     * these registers, `writing` and physbuf straight out of the instance
     * rather than through accessors.  Protection is not recorded in
     * __instance_vars, so this is invisible in the binary.
     */
    @public
    BOOL            inUse;                  // 0x128
    BOOL            writing;                // 0x129
    char           *configRegister;         // 0x12c
    char           *dataRegister;           // 0x130
    unsigned char   dataRegisterData;       // 0x134  never read by the reference
    char           *statusRegister;         // 0x138
    char           *controlRegister;        // 0x13c
    unsigned char   controlRegisterDefaults;// 0x140
    unsigned int    busyMaxRetries;         // 0x144
    unsigned int    busyRetryInterval;      // 0x148
    int             autofeedOutput;         // 0x14c
    unsigned int    IOThreadDelay;          // 0x150
    unsigned int    intHandlerDelay;        // 0x154
    unsigned int    minPhys;                // 0x158
    unsigned int    blockSize;              // 0x15c
    int             ioTimeout;              // 0x160
    id              ioQueueLock;            // 0x164  NXConditionLock
    struct {
        struct queue_entry *next;           // 0x168  head
        struct queue_entry *prev;           // 0x16c  tail
    } ioQueue;
    void           *ioTaskThread;           // 0x170
    struct buf     *physbuf;                // 0x174
    msg_header_t   *interruptMessage;       // 0x178  8192-byte receive buffer
    int             majorDevNum;            // 0x17c
    int             minorDevNum;            // 0x180
    void           *dataBuffer;             // 0x184
    id              sizeLock;               // 0x188  NXLock
    BOOL            waitForever;            // 0x18c
    unsigned int    statusWord;             // 0x190
}

// Class methods
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

// Initialization and probe
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (BOOL)probeForController;
- (IOReturn)initDevice;
- (IOReturn)printerInit;
- free;

// Register access
- (const char *)dataRegister;
- setDataRegister:(const char *)reg;
- (const char *)statusRegister;
- setStatusRegister:(const char *)reg;
- (const char *)controlRegister;
- setControlRegister:(const char *)reg;
- (const char *)configRegister;
- setConfigRegister:(const char *)reg;

// Register contents
- (unsigned char)controlRegisterContents;
- (unsigned char)controlRegisterDefaults;
- (unsigned char)statusRegisterContents;
- (unsigned int)statusWord;
- setStatusWord:(unsigned int)word;

// Port I/O operations
- (IOReturn)readFromPort;
- (IOReturn)writeToPort;

// Device properties
- (BOOL)isInitialized;
- (BOOL)isInUse;
- setInUse:(BOOL)flag;
- (BOOL)waitForever;
- setWaitForever:(BOOL)flag;
- (int)autofeedOutput;
- setAutofeedOutput:(int)flag;

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
- (struct buf *)physbuf;
- setPhysbuf:(struct buf *)buf;

// Timing and retries
- (unsigned int)busyMaxRetries;
- setBusyMaxRetries:(unsigned int)retries;
- (unsigned int)busyRetryInterval;
- setBusyRetryInterval:(unsigned int)interval;
- (int)ioTimeout;
- setIoTimeout:(int)timeout;
- (unsigned int)intHandlerDelay;
- setIntHandlerDelay:(unsigned int)delay;
- (unsigned int)IOThreadDelay;
- setIOThreadDelay:(unsigned int)delay;

// Interrupt handling
- (IOReturn)attachInterruptPort;
- (msg_header_t *)interruptMessage;
- setInterruptMessage:(msg_header_t *)msg;
- (BOOL)getHandler:(IOInterruptHandler *)handler
            level:(unsigned int *)ipl
         argument:(unsigned int *)arg
     forInterrupt:(unsigned int)localInterrupt;

// Device waiting
- (BOOL)_waitForDevice:(BOOL)wait isReady:(BOOL *)isReady;

// Command buffer operations
- (PPCommandBuffer *)cmdBufAlloc;
- (void)cmdBufFree:(PPCommandBuffer *)buf;
- (void)cmdBufExec:(PPCommandBuffer *)buf;
- (void)cmdBufComplete:(PPCommandBuffer *)buf;
- (void *)waitForCmdBuf;

// Parameter handling
- (IOReturn)getIntValues:(unsigned int *)values
            forParameter:(IOParameterName)parameterName
                   count:(unsigned int *)count;

// Message handling
- (IOReturn)msgTypeToIOReturn:(int)msgType;

@end

#endif /* _BSD_DEV_I386_IOPARALLELPORT_H_ */
