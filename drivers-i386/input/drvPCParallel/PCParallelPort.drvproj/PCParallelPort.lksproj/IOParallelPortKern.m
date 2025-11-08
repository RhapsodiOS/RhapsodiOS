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
 * IOParallelPortKern.m - Kernel-level implementation for PC Parallel Port driver.
 *
 * HISTORY
 */

#ifdef KERNEL

#import "IOParallelPortKern.h"
#import <driverkit/i386/ioPorts.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/KernDevice.h>
#import <kern/time_stamp.h>
#import <kernserv/i386/spl.h>
#import <mach/message.h>
#import <sys/errno.h>
#import <sys/types.h>
#import <sys/uio.h>
#import <sys/conf.h>
#import <sys/buf.h>
#import <sys/systm.h>
#import <objc/objc.h>
#import <objc/objc-runtime.h>

// Device number extraction macros
#ifndef minor
#define minor(x)  ((int)((x) & 0xff))
#endif
#ifndef major
#define major(x)  ((int)(((x) >> 8) & 0xff))
#endif

// Interrupt message type codes
#define PP_INT_MSG_COMPLETE     0x232325
#define PP_INT_MSG_OFFLINE      0x232336
#define PP_INT_MSG_PAPER_OUT    0x232337
#define PP_INT_MSG_DEVICE_BUSY  0x232338
#define PP_INT_MSG_ERROR        0x232339

// Error return codes
#define PP_IO_ERROR             0xfffffd41  // -703
#define PP_OFFLINE_ERROR        0xfffffd1e  // -738
#define PP_PAPER_OUT_ERROR      0xfffffd1f  // -737
#define PP_TIMEOUT_ERROR        0xfffffd2a  // -726
#define PP_BUSY_ERROR           0xfffffd2b  // -725

// Message receive options and return codes
#define MSG_OPTION_RCV_LARGE    0x500
#define MSG_RCV_INTERRUPTED     -0xcf
#define MSG_RCV_TIMED_OUT       -0xcb

// Buffer flags (buf structure)
#define B_READ          0x100000  // Read operation
#define B_WRITE         0x000000  // Write operation (no flag)
#define B_DONE          0x000200  // I/O completed
#define B_ERROR         0x000800  // I/O error
#define B_BUSY          0x000400  // I/O in progress

// UIO segment flags
#define UIO_SYSSPACE    2         // Kernel address space

// Error codes (if not already defined)
#ifndef ETIMEDOUT
#define ETIMEDOUT       60        // Connection timed out
#endif
#ifndef EBUSY
#define EBUSY           16        // Device busy
#endif

// Buffer structure offsets (from decompiled code)
#define BUF_FLAGS_OFFSET    0x24  // Flags
#define BUF_ERROR_OFFSET    0x28  // Error code
#define BUF_COUNT_OFFSET    0x30  // Transfer count
#define BUF_RESID_OFFSET    0x34  // Residual count
#define BUF_DEV_OFFSET      0x38  // Device number (byte)
#define BUF_DATA_OFFSET     0x3c  // Data pointer

// Standard parallel port base addresses
static unsigned int pp_base_addrs[PP_KERN_MAX_PORTS] = {
    0x378,  // LPT1
    0x278,  // LPT2
    0x3BC,  // LPT3 (old style)
    0x0     // Reserved
};

// Port modes
static pp_mode_t pp_modes[PP_KERN_MAX_PORTS] = {
    PP_MODE_SPP, PP_MODE_SPP, PP_MODE_SPP, PP_MODE_SPP
};

// Per-port control structure (based on decompiled offsets)
typedef struct pp_port_control {
    unsigned char padding1[0x129];
    unsigned char interruptsEnabled;  // +0x129: Interrupts enabled flag
    unsigned char padding2[6];
    unsigned int dataReg;             // +0x130: Data register address
    unsigned int statusReg;           // +0x134: Status register address (used at +0x138)
    unsigned int statusRegAddr;       // +0x138: Status register I/O address
    unsigned int controlRegAddr;      // +0x13c: Control register address
    unsigned char controlRegValue;    // +0x140: Current control register value
    unsigned char padding3[0x13];
    unsigned int delayValue;          // +0x154: Delay value in microseconds
    unsigned char padding4[0x1c];
    void *deviceDescriptor;           // +0x174: Pointer to device descriptor
    unsigned char padding5[0xc];
} pp_port_control_t;

// Device descriptor structure (simplified)
typedef struct pp_device_desc {
    unsigned char padding[0x24];
    unsigned int flags;               // +0x24: Device flags
} pp_device_desc_t;

// Global data arrays (simulate offsets from decompiled code)
static pp_port_control_t *pp_port_controls[PP_KERN_MAX_PORTS] = {NULL, NULL, NULL, NULL};
static int pp_bytes_remaining[PP_KERN_MAX_PORTS] = {0, 0, 0, 0};
static unsigned char **pp_data_buffers[PP_KERN_MAX_PORTS] = {NULL, NULL, NULL, NULL};

// Global strobe counter (protected by lock)
static volatile unsigned int pp_strobe_count = 0;

// Command buffer structure (offsets from decompiled code)
typedef struct pp_cmd_buffer {
    unsigned char padding1[4];
    int commandType;              // +0x04: Command type (0=normal, 1=exit)
    unsigned char padding2[4];
    int returnCode;               // +0x0c: Return code
    unsigned char errorFlag;      // +0x10: Error flag byte
    unsigned char padding3[3];
} pp_cmd_buffer_t;

// Interrupt message structure
typedef struct pp_interrupt_msg {
    unsigned char header[4];
    int msgType;                  // +0x04: Message type
    unsigned char padding1[4];
    void *portHandle;             // +0x0c: Port handle
    unsigned char padding2[4];
    int msgData;                  // +0x14: Message data
} pp_interrupt_msg_t;

// Buffer structure (simplified, using offsets)
typedef struct pp_buffer {
    unsigned char padding1[BUF_FLAGS_OFFSET];
    unsigned int flags;           // +0x24: Buffer flags
    int errorCode;                // +0x28: Error code
    unsigned char padding2[4];
    unsigned int count;           // +0x30: Transfer count
    unsigned int resid;           // +0x34: Residual count
    unsigned char dev;            // +0x38: Device number
    unsigned char padding3[3];
    void *dataPtr;                // +0x3c: Data pointer
} pp_buffer_t;

// UIO iovec structure
typedef struct pp_iovec {
    void *iov_base;               // +0x00: Base address
    int iov_len;                  // +0x04: Length
} pp_iovec_t;

// UIO structure (simplified)
typedef struct pp_uio {
    pp_iovec_t *uio_iov;          // +0x00: Pointer to iovec array
    unsigned char padding1[0x10];
    int uio_resid;                // +0x10: Residual count
    int uio_segflg;               // +0x14: Segment flag (UIO_SYSSPACE, etc)
} pp_uio_t;

//
// Initialization
//

void pp_kern_init(void)
{
    int i;

    // Initialize all ports to SPP mode
    for (i = 0; i < PP_KERN_MAX_PORTS; i++) {
        if (pp_base_addrs[i] != 0) {
            pp_kern_reset(i);
        }
    }
}

//
// Probe for parallel port
//

int pp_kern_probe(unsigned int baseAddr)
{
    unsigned char orig_data, test_data;

    // Save original data register value
    orig_data = inb(baseAddr + PP_DATA_REG);

    // Try writing test pattern
    outb(baseAddr + PP_DATA_REG, 0xAA);
    test_data = inb(baseAddr + PP_DATA_REG);

    if (test_data != 0xAA) {
        outb(baseAddr + PP_DATA_REG, orig_data);
        return -1;
    }

    // Try another pattern
    outb(baseAddr + PP_DATA_REG, 0x55);
    test_data = inb(baseAddr + PP_DATA_REG);

    // Restore original value
    outb(baseAddr + PP_DATA_REG, orig_data);

    if (test_data != 0x55) {
        return -1;
    }

    return 0;
}

//
// Reset parallel port
//

int pp_kern_reset(unsigned int portNum)
{
    unsigned int baseAddr;

    if (portNum >= PP_KERN_MAX_PORTS)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    // Reset control register
    outb(baseAddr + PP_CONTROL_REG, PP_CONTROL_INIT);
    pp_kern_delay(50);
    outb(baseAddr + PP_CONTROL_REG, PP_CONTROL_INIT | PP_CONTROL_SELECT);

    return 0;
}

//
// Mode control
//

int pp_kern_set_mode(unsigned int portNum, pp_mode_t mode)
{
    if (portNum >= PP_KERN_MAX_PORTS)
        return -1;

    // TODO: Implement mode switching for EPP/ECP
    pp_modes[portNum] = mode;

    return 0;
}

int pp_kern_get_mode(unsigned int portNum, pp_mode_t *mode)
{
    if (portNum >= PP_KERN_MAX_PORTS || mode == NULL)
        return -1;

    *mode = pp_modes[portNum];
    return 0;
}

//
// Data I/O
//

int pp_kern_read_data(unsigned int portNum, unsigned char *data)
{
    unsigned int baseAddr;

    if (portNum >= PP_KERN_MAX_PORTS || data == NULL)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    *data = inb(baseAddr + PP_DATA_REG);
    return 0;
}

int pp_kern_write_data(unsigned int portNum, unsigned char data)
{
    unsigned int baseAddr;

    if (portNum >= PP_KERN_MAX_PORTS)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    outb(baseAddr + PP_DATA_REG, data);
    return 0;
}

//
// Status and control
//

int pp_kern_read_status(unsigned int portNum, unsigned char *status)
{
    unsigned int baseAddr;

    if (portNum >= PP_KERN_MAX_PORTS || status == NULL)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    *status = inb(baseAddr + PP_STATUS_REG);
    return 0;
}

int pp_kern_read_control(unsigned int portNum, unsigned char *control)
{
    unsigned int baseAddr;

    if (portNum >= PP_KERN_MAX_PORTS || control == NULL)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    *control = inb(baseAddr + PP_CONTROL_REG);
    return 0;
}

int pp_kern_write_control(unsigned int portNum, unsigned char control)
{
    unsigned int baseAddr;

    if (portNum >= PP_KERN_MAX_PORTS)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    outb(baseAddr + PP_CONTROL_REG, control);
    return 0;
}

//
// State management
//

int pp_kern_get_state(unsigned int portNum, pp_port_state_t *state)
{
    unsigned int baseAddr;

    if (portNum >= PP_KERN_MAX_PORTS || state == NULL)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    state->data = inb(baseAddr + PP_DATA_REG);
    state->status = inb(baseAddr + PP_STATUS_REG);
    state->control = inb(baseAddr + PP_CONTROL_REG);
    state->reserved = 0;

    return 0;
}

int pp_kern_set_state(unsigned int portNum, const pp_port_state_t *state)
{
    unsigned int baseAddr;

    if (portNum >= PP_KERN_MAX_PORTS || state == NULL)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    outb(baseAddr + PP_DATA_REG, state->data);
    outb(baseAddr + PP_CONTROL_REG, state->control);

    return 0;
}

//
// Timing utilities
//

void pp_kern_delay(unsigned int microseconds)
{
    // Simple delay loop - could be improved with proper timing
    volatile unsigned int i;
    for (i = 0; i < microseconds * 10; i++)
        ;
}

//
// Wait for busy signal
//

int pp_kern_wait_busy(unsigned int portNum, unsigned int timeout_ms)
{
    unsigned int baseAddr;
    unsigned char status;
    unsigned int timeout_loops;

    if (portNum >= PP_KERN_MAX_PORTS)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    timeout_loops = timeout_ms * 100;

    while (timeout_loops--) {
        status = inb(baseAddr + PP_STATUS_REG);
        if (!(status & PP_STATUS_BUSY))
            return 0;
        pp_kern_delay(10);
    }

    return -1;  // Timeout
}

//
// Strobe operation
//

int pp_kern_strobe(unsigned int portNum)
{
    unsigned int baseAddr;
    unsigned char control;

    if (portNum >= PP_KERN_MAX_PORTS)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    control = inb(baseAddr + PP_CONTROL_REG);

    // Assert strobe
    outb(baseAddr + PP_CONTROL_REG, control | PP_CONTROL_STROBE);
    pp_kern_delay(1);

    // Deassert strobe
    outb(baseAddr + PP_CONTROL_REG, control & ~PP_CONTROL_STROBE);

    return 0;
}

//
// Interrupt control
//

int pp_kern_enable_interrupts(unsigned int portNum)
{
    unsigned int baseAddr;
    unsigned char control;

    if (portNum >= PP_KERN_MAX_PORTS)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    control = inb(baseAddr + PP_CONTROL_REG);
    outb(baseAddr + PP_CONTROL_REG, control | PP_CONTROL_IRQ_EN);

    return 0;
}

int pp_kern_disable_interrupts(unsigned int portNum)
{
    unsigned int baseAddr;
    unsigned char control;

    if (portNum >= PP_KERN_MAX_PORTS)
        return -1;

    baseAddr = pp_base_addrs[portNum];
    if (baseAddr == 0)
        return -1;

    control = inb(baseAddr + PP_CONTROL_REG);
    outb(baseAddr + PP_CONTROL_REG, control & ~PP_CONTROL_IRQ_EN);

    return 0;
}

//
// Software control structure
//

void *pp_softc = NULL;

//
// Standard error functions
//

int enodev(void)
{
    // Return "operation not supported by device" error
    return ENODEV;
}

int seltrue(void)
{
    // Always returns true for select operations
    return 1;
}

//
// Character device interface
//

int ppopen(dev_t dev, int flags, int devtype, void *p)
{
    // TODO: Implement device open
    // - Extract minor device number
    // - Check if port is available
    // - Initialize port hardware
    // - Set up software control structure
    return 0;
}

int ppclose(dev_t dev, int flags, int devtype, void *p)
{
    int portNum;
    id portObject;
    SEL sel;

    // Extract minor device number (port number)
    portNum = minor(dev);

    if (portNum >= PP_KERN_MAX_PORTS)
        return ENXIO;

    // Get the port object
    portObject = (id)pp_port_controls[portNum];
    if (portObject == NULL)
        return ENXIO;

    // Mark device as not in use
    sel = sel_getUid("setInUse:");
    objc_msgSend(portObject, sel, 0);

    return 0;
}

int ppread(dev_t dev, void *uio, int ioflag)
{
    int portNum;
    id portObject;
    SEL sel;
    void *physbuf;
    unsigned int blockSize;
    int result;

    // Extract minor device number (port number)
    portNum = minor(dev);

    if (portNum >= PP_KERN_MAX_PORTS)
        return ENXIO;

    // Get the port object
    portObject = (id)pp_port_controls[portNum];
    if (portObject == NULL)
        return ENXIO;

    // Lock the device for I/O
    sel = sel_getUid("lockSize");
    objc_msgSend(portObject, sel);

    // Get block size
    sel = sel_getUid("blockSize");
    blockSize = (unsigned int)objc_msgSend(portObject, sel);

    // Get physical buffer
    sel = sel_getUid("physbuf");
    physbuf = (void *)objc_msgSend(portObject, sel);

    // Perform physical I/O (read operation - B_READ flag)
    result = physio(ppstrategy, physbuf, dev, B_READ,
                    (unsigned int (*)(void *))ppminphys, uio, blockSize);

    // Unlock the device
    sel = sel_getUid("unlockSize");
    objc_msgSend(portObject, sel);

    return result;
}

int ppwrite(dev_t dev, void *uio, int ioflag)
{
    int portNum;
    id portObject;
    SEL sel;
    pp_uio_t *uioPtr = (pp_uio_t *)uio;
    pp_iovec_t *iov;
    void *physbuf;
    unsigned int blockSize;
    int result;
    char isInitialized;
    int initResult;
    BOOL dataCopied = NO;
    void *tempBuffer = NULL;
    int copySize = 0;
    int savedSegflg;
    void *savedBase;
    int savedLen;

    // Extract minor device number (port number)
    portNum = minor(dev);

    if (portNum >= PP_KERN_MAX_PORTS)
        return ENXIO;

    // Get the port object
    portObject = (id)pp_port_controls[portNum];
    if (portObject == NULL)
        return ENXIO;

    // Check if device is initialized
    sel = sel_getUid("isInitialized");
    isInitialized = (char)objc_msgSend(portObject, sel);

    if (!isInitialized) {
        // Initialize the device
        sel = sel_getUid("initDevice");
        initResult = (int)objc_msgSend(portObject, sel);

        // Check for errors that should terminate
        if (initResult != 0) {
            // Map specific errors to success (ignore them)
            if (initResult >= PP_TIMEOUT_ERROR && initResult <= -0x2d4) {
                // In range -726 to -724, continue
            } else if ((initResult >= PP_OFFLINE_ERROR && initResult <= PP_PAPER_OUT_ERROR) ||
                       (initResult >= -0x2e3 && initResult <= -0x2e0)) {
                // In range -738 to -737 or -739 to -736, continue
            } else if (initResult == 0) {
                // Success
            } else {
                // Other errors - return EIO
                return EIO;
            }
        }
    }

    // Check if data is in user space (not kernel space)
    if (uioPtr->uio_segflg != UIO_SYSSPACE) {
        iov = uioPtr->uio_iov;
        copySize = iov->iov_len;

        // Limit copy size to 0x8000 (32KB)
        if (copySize > 0x8000) {
            copySize = 0x8000;
        }

        // Allocate temporary kernel buffer
        tempBuffer = IOMalloc(copySize);
        if (tempBuffer == NULL) {
            return ENOMEM;
        }

        // Copy data from user space to kernel space
        copyin(iov->iov_base, tempBuffer, copySize);

        // Save original values
        savedSegflg = uioPtr->uio_segflg;
        savedBase = iov->iov_base;
        savedLen = iov->iov_len;

        // Update to kernel space
        uioPtr->uio_segflg = UIO_SYSSPACE;
        iov->iov_base = tempBuffer;
        iov->iov_len = copySize;

        dataCopied = YES;
    }

    // Lock the device for I/O
    sel = sel_getUid("lockSize");
    objc_msgSend(portObject, sel);

    // Zero out physical buffer (0x80 = 128 bytes)
    sel = sel_getUid("physbuf");
    physbuf = (void *)objc_msgSend(portObject, sel);
    bzero(physbuf, 0x80);

    // Get block size
    sel = sel_getUid("blockSize");
    blockSize = (unsigned int)objc_msgSend(portObject, sel);

    // Perform physical I/O (write operation - no B_READ flag, so 0)
    result = physio(ppstrategy, physbuf, dev, 0,
                    (unsigned int (*)(void *))ppminphys, uio, blockSize);

    // Unlock the device
    sel = sel_getUid("unlockSize");
    objc_msgSend(portObject, sel);

    // If we copied data, restore original values and free temp buffer
    if (dataCopied) {
        iov = uioPtr->uio_iov;

        // Restore original UIO settings
        uioPtr->uio_segflg = savedSegflg;
        iov->iov_base = savedBase;
        iov->iov_len = savedLen;

        // Free temporary buffer
        IOFree(tempBuffer, copySize);

        // Update residual count to reflect bytes transferred
        uioPtr->uio_resid += (savedLen - copySize);
    }

    return result;
}

int ppioctl(dev_t dev, unsigned long cmd, void *data, int flag, void *p)
{
    int portNum;
    id portObject;
    SEL sel;
    unsigned int *uintData = (unsigned int *)data;
    unsigned int value;
    unsigned char byteValue;
    int timeout;

    // Extract minor device number (port number)
    portNum = minor(dev);

    if (portNum >= PP_KERN_MAX_PORTS)
        return ENXIO;

    // Get the port object
    portObject = (id)pp_port_controls[portNum];
    if (portObject == NULL)
        return ENXIO;

    // Process ioctl command
    switch (cmd) {
        // SET operations (write to device)
        case PP_IOCTL_SET_INT_HANDLER_DELAY:
            sel = sel_getUid("setIntHandlerDelay:");
            objc_msgSend(portObject, sel, *uintData);
            return 0;

        case PP_IOCTL_SET_MIN_PHYS:
            sel = sel_getUid("setMinPhys:");
            objc_msgSend(portObject, sel, *uintData);
            return 0;

        case PP_IOCTL_SET_IO_THREAD_DELAY:
            sel = sel_getUid("setIOThreadDelay:");
            objc_msgSend(portObject, sel, *uintData);
            return 0;

        case PP_IOCTL_SET_BLOCK_SIZE:
            sel = sel_getUid("setBlockSize:");
            objc_msgSend(portObject, sel, *uintData);
            return 0;

        case PP_IOCTL_SET_BUSY_RETRY_INTERVAL:
            sel = sel_getUid("setBusyRetryInterval:");
            objc_msgSend(portObject, sel, *uintData);
            return 0;

        case PP_IOCTL_SET_BUSY_MAX_RETRIES:
            sel = sel_getUid("setBusyMaxRetries:");
            objc_msgSend(portObject, sel, *uintData);
            return 0;

        case PP_IOCTL_SET_TIMEOUT:
            // Special handling for timeout setting
            value = *uintData;
            if (value == 0xFFFFFFFF) {
                // Wait forever mode
                sel = sel_getUid("setBusyMaxRetries:");
                objc_msgSend(portObject, sel, 10);

                sel = sel_getUid("setBusyRetryInterval:");
                objc_msgSend(portObject, sel, 1000);

                sel = sel_getUid("setIoTimeout:");
                objc_msgSend(portObject, sel, 2000);

                sel = sel_getUid("setWaitForever:");
                objc_msgSend(portObject, sel, 1);
            } else {
                // Timeout in seconds
                sel = sel_getUid("setBusyMaxRetries:");
                objc_msgSend(portObject, sel, 1);

                timeout = value * 1000;  // Convert to milliseconds

                sel = sel_getUid("setBusyRetryInterval:");
                objc_msgSend(portObject, sel, timeout);

                sel = sel_getUid("setIoTimeout:");
                objc_msgSend(portObject, sel, timeout);

                sel = sel_getUid("setWaitForever:");
                objc_msgSend(portObject, sel, 0);
            }
            return 0;

        // GET operations (read from device)
        case PP_IOCTL_GET_INT_HANDLER_DELAY:
            sel = sel_getUid("intHandlerDelay");
            value = (unsigned int)objc_msgSend(portObject, sel);
            *uintData = value;
            return 0;

        case PP_IOCTL_GET_MIN_PHYS:
            sel = sel_getUid("minPhys");
            value = (unsigned int)objc_msgSend(portObject, sel);
            *uintData = value;
            return 0;

        case PP_IOCTL_GET_IO_THREAD_DELAY:
            sel = sel_getUid("IOThreadDelay");
            value = (unsigned int)objc_msgSend(portObject, sel);
            *uintData = value;
            return 0;

        case PP_IOCTL_GET_BLOCK_SIZE:
            sel = sel_getUid("blockSize");
            value = (unsigned int)objc_msgSend(portObject, sel);
            *uintData = value;
            return 0;

        case PP_IOCTL_GET_BUSY_RETRY_INTERVAL:
            sel = sel_getUid("busyRetryInterval");
            value = (unsigned int)objc_msgSend(portObject, sel);
            *uintData = value;
            return 0;

        case PP_IOCTL_GET_BUSY_MAX_RETRIES:
            sel = sel_getUid("busyMaxRetries");
            value = (unsigned int)objc_msgSend(portObject, sel);
            *uintData = value;
            return 0;

        case PP_IOCTL_GET_STATUS_WORD:
            sel = sel_getUid("statusWord");
            value = (unsigned int)objc_msgSend(portObject, sel);
            *uintData = value;
            return 0;

        case PP_IOCTL_GET_STATUS_REG_CONTENTS:
            sel = sel_getUid("statusRegisterContents");
            byteValue = (unsigned char)objc_msgSend(portObject, sel);
            *uintData = byteValue & 0xFF;
            return 0;

        case PP_IOCTL_GET_CONTROL_REG_CONTENTS:
            sel = sel_getUid("controlRegisterContents");
            byteValue = (unsigned char)objc_msgSend(portObject, sel);
            *uintData = byteValue & 0xFF;
            return 0;

        case PP_IOCTL_GET_CONTROL_REG_DEFAULTS:
            sel = sel_getUid("controlRegisterDefaults");
            byteValue = (unsigned char)objc_msgSend(portObject, sel);
            *uintData = byteValue & 0xFF;
            return 0;

        default:
            // Unknown ioctl command
            return EINVAL;
    }
}

void ppstrategy(void *bp)
{
    pp_buffer_t *buf = (pp_buffer_t *)bp;
    int portNum;
    id portObject;
    SEL sel;
    int result;

    // Get port number from buffer
    portNum = buf->dev;

    if (portNum >= PP_KERN_MAX_PORTS) {
        buf->errorCode = ENXIO;
        buf->flags |= (B_DONE | B_ERROR);
        return;
    }

    // Get the port object
    portObject = (id)pp_port_controls[portNum];
    if (portObject == NULL) {
        buf->errorCode = ENXIO;
        buf->flags |= (B_DONE | B_ERROR);
        return;
    }

    // Check if this is a READ or WRITE operation
    if ((buf->flags & B_READ) == 0) {
        // WRITE operation
        // Set up the data buffer pointer and count for the port
        pp_data_buffers[portNum] = (unsigned char **)&buf->dataPtr;
        pp_bytes_remaining[portNum] = buf->count;

        // Perform the write
        sel = sel_getUid("writeToPort");
        result = (int)objc_msgSend(portObject, sel);

        // Update residual count
        buf->resid = pp_bytes_remaining[portNum];
    } else {
        // READ operation
        sel = sel_getUid("readFromPort");
        result = (int)objc_msgSend(portObject, sel);
    }

    // Mark buffer as done
    buf->flags |= B_DONE;

    if (result == 0) {
        // Success - clear error flag
        buf->flags &= ~B_ERROR;
        return;
    }

    // Error occurred - set error flag and map IOReturn to errno
    buf->flags |= B_ERROR;

    switch (result) {
        case PP_PAPER_OUT_ERROR:    // -737 (-0x2e1)
        case PP_OFFLINE_ERROR:      // -738 (-0x2e2)
            buf->errorCode = EIO;   // 0x53 (83)
            break;

        case PP_TIMEOUT_ERROR:      // -726 (-0x2d6)
            buf->errorCode = ETIMEDOUT;  // 0x3c (60)
            break;

        case PP_BUSY_ERROR:         // -725 (-0x2d5)
            buf->errorCode = EBUSY;  // 0x10 (16)
            break;

        default:
            buf->errorCode = EIO;    // 0x05 (5) - Generic I/O error
            break;
    }
}

void ppminphys(void *bp)
{
    pp_buffer_t *buf = (pp_buffer_t *)bp;
    int portNum;
    id portObject;
    SEL sel;
    unsigned int minPhysValue;
    unsigned int bufferCount;

    // Get port number from buffer
    portNum = buf->dev;

    if (portNum >= PP_KERN_MAX_PORTS)
        return;

    // Get the port object
    portObject = (id)pp_port_controls[portNum];
    if (portObject == NULL)
        return;

    // Get minPhys value from the device
    sel = sel_getUid("minPhys");
    minPhysValue = (unsigned int)objc_msgSend(portObject, sel);

    // Get current buffer count
    bufferCount = buf->count;

    // Limit to the smaller of the two
    if (bufferCount > minPhysValue) {
        buf->count = minPhysValue;
    }
}

//
// Internal helper functions
//

void IOParallelPortInterruptHandler(unsigned int param1, unsigned int param2, int portNum)
{
    pp_port_control_t *portCtrl;
    unsigned char statusByte;
    int interruptMsg = 0;
    unsigned int dataRegAddr;
    unsigned char dataByte;
    pp_device_desc_t *deviceDesc;

    // Validate port number
    if (portNum >= PP_KERN_MAX_PORTS)
        return;

    // Get port control structure
    portCtrl = pp_port_controls[portNum];
    if (portCtrl == NULL)
        return;

    // Read status register
    statusByte = inb(portCtrl->statusRegAddr);

    // Check if interrupts are enabled for this port
    if (portCtrl->interruptsEnabled == 0)
        return;

    // Decode status register to determine error condition
    if ((statusByte & 0x28) == 0x08) {
        // Error bit set, select bit clear, paper out bit clear
        if ((statusByte & 0x80) == 0) {
            // Not busy
            interruptMsg = PP_INT_MSG_DEVICE_BUSY;
        }
    } else {
        if (statusByte & 0x20) {
            // Paper out
            interruptMsg = PP_INT_MSG_PAPER_OUT;
        } else if ((statusByte & 0x10) == 0) {
            // Select bit clear (offline)
            interruptMsg = PP_INT_MSG_OFFLINE;
        } else {
            // General error
            interruptMsg = PP_INT_MSG_ERROR;
        }
    }

    // If no error, handle data transfer
    if (interruptMsg == 0) {
        deviceDesc = (pp_device_desc_t *)portCtrl->deviceDescriptor;

        if (deviceDesc != NULL && (deviceDesc->flags & 0x100000) == 0) {
            // Output mode: send next character if available
            if (pp_bytes_remaining[portNum] > 0) {
                _strobeChar(portNum, portCtrl->delayValue, 0);
                return;
            }
        } else if (deviceDesc != NULL) {
            // Input mode: read data from port
            if (pp_bytes_remaining[portNum] > 0) {
                dataRegAddr = portCtrl->dataReg;
                dataByte = inb(dataRegAddr);

                // Store byte in buffer
                **(pp_data_buffers[portNum]) = dataByte;

                // Advance buffer pointer
                (*(pp_data_buffers[portNum]))++;

                // Decrement bytes remaining
                pp_bytes_remaining[portNum]--;
            }
        }

        // Check if transfer complete
        if (pp_bytes_remaining[portNum] <= 0) {
            interruptMsg = PP_INT_MSG_COMPLETE;
        } else {
            // More data to transfer, no interrupt needed
            return;
        }
    }

    // Send interrupt message to waiting thread
    IOSendInterrupt(param1, param2, interruptMsg);
}

void IOParallelPortThread(id portObject)
{
    SEL sel;
    pp_interrupt_msg_t interruptMsg;
    pp_cmd_buffer_t *cmdBuf;
    unsigned short statusRegAddr;
    unsigned char statusByte;
    char shouldWait;
    char deviceReady;
    int msgResult;
    int timeout;
    int ioTimeout;
    int elapsedTime;
    unsigned int delay;
    int portNum;
    char strobeResult;
    void *interruptPort;
    const char *deviceName;

    // Get interrupt message port from the object
    sel = sel_getUid("interruptMessage");
    objc_msgSend(portObject, sel);

    // Main I/O loop
    while (1) {
        // Wait for command buffer
        sel = sel_getUid("waitForCmdBuf");
        cmdBuf = (pp_cmd_buffer_t *)objc_msgSend(portObject, sel);

        // Check command type
        if (cmdBuf->commandType == 1) {
            // Exit command
            sel = sel_getUid("cmdBufComplete:");
            objc_msgSend(portObject, sel, cmdBuf);
            IOExitThread();
        }

        if (cmdBuf->commandType != 0) {
            // Unknown command
            goto complete_command;
        }

        // Read status register
        sel = sel_getUid("statusRegister");
        statusRegAddr = (unsigned short)objc_msgSend(portObject, sel);
        statusByte = inb(statusRegAddr);

        // Check if device is ready (status & 0xb8 == 0x98)
        if ((statusByte & 0xb8) != 0x98) {
            // Device not ready, check if we should wait
            sel = sel_getUid("waitForever");
            shouldWait = (char)objc_msgSend(portObject, sel, &deviceReady);

            sel = sel_getUid("_waitForDevice:isReady:");
            objc_msgSend(portObject, sel, (int)shouldWait);

            if (!deviceReady) {
                // Device still not ready after waiting
                sel = sel_getUid("statusRegister");
                statusRegAddr = (unsigned short)objc_msgSend(portObject, sel);
                statusByte = inb(statusRegAddr);

                cmdBuf->errorFlag = 0;

                // Decode error condition
                if ((statusByte & 0x08) == 0) {
                    cmdBuf->errorFlag = 1;
                }

                if (statusByte & 0x20) {
                    cmdBuf->returnCode = PP_PAPER_OUT_ERROR;
                } else if ((statusByte & 0x10) == 0) {
                    cmdBuf->returnCode = PP_OFFLINE_ERROR;
                } else if ((char)statusByte < 0) {
                    cmdBuf->returnCode = PP_TIMEOUT_ERROR;
                } else {
                    cmdBuf->returnCode = PP_BUSY_ERROR;
                }

                goto complete_command;
            }
        }

        // Device is ready, perform strobe
        sel = sel_getUid("IOThreadDelay");
        delay = (unsigned int)objc_msgSend(portObject, sel);

        sel = sel_getUid("minorDevNum");
        portNum = (int)objc_msgSend(portObject, sel);

        strobeResult = (char)_strobeChar(portNum, delay, 1);

        if (!strobeResult) {
            cmdBuf->returnCode = 0;
        } else {
            // Wait for completion interrupt
            cmdBuf->returnCode = 0;
            elapsedTime = 0;

            sel = sel_getUid("ioTimeout");
            ioTimeout = (int)objc_msgSend(portObject, sel);

            while (1) {
                // Set up interrupt message
                sel = sel_getUid("interruptPort");
                interruptPort = (void *)objc_msgSend(portObject, sel);

                interruptMsg.portHandle = interruptPort;
                interruptMsg.msgType = 0x2000;

                // Calculate timeout (500ms or ioTimeout, whichever is smaller)
                timeout = 500;
                if (ioTimeout != 0 && ioTimeout < 500) {
                    timeout = ioTimeout;
                }

                // Receive interrupt message
                msgResult = msg_receive(&interruptMsg, MSG_OPTION_RCV_LARGE, timeout);

                if (msgResult == 0) {
                    // Message received successfully
                    break;
                }

                if (msgResult != MSG_RCV_INTERRUPTED) {
                    if (msgResult == MSG_RCV_TIMED_OUT) {
                        // Timeout - check if we should continue waiting
                        sel = sel_getUid("waitForever");
                        shouldWait = (char)objc_msgSend(portObject, sel, &deviceReady);

                        sel = sel_getUid("_waitForDevice:isReady:");
                        objc_msgSend(portObject, sel, (int)shouldWait);

                        if (!deviceReady) {
                            // Device not ready
                            sel = sel_getUid("statusRegister");
                            statusRegAddr = (unsigned short)objc_msgSend(portObject, sel);
                            statusByte = inb(statusRegAddr);

                            cmdBuf->errorFlag = 0;

                            if ((statusByte & 0x08) == 0) {
                                cmdBuf->errorFlag = 1;
                            }

                            if (statusByte & 0x20) {
                                cmdBuf->returnCode = PP_PAPER_OUT_ERROR;
                            } else if ((statusByte & 0x10) == 0) {
                                cmdBuf->returnCode = PP_OFFLINE_ERROR;
                            } else if ((char)statusByte < 0) {
                                cmdBuf->returnCode = PP_TIMEOUT_ERROR;
                            } else {
                                cmdBuf->returnCode = PP_BUSY_ERROR;
                            }
                            break;
                        }

                        elapsedTime += 500;
                        if (elapsedTime >= ioTimeout) {
                            cmdBuf->returnCode = PP_TIMEOUT_ERROR;
                            break;
                        }
                    } else {
                        // Other error
                        sel = sel_getUid("name");
                        deviceName = (const char *)objc_msgSend(portObject, sel);
                        IOLog("%s: msg_receive returned %d\n", deviceName, msgResult);
                        cmdBuf->returnCode = PP_IO_ERROR;
                        break;
                    }
                }
            }

            // Convert message type to IOReturn if no error
            if (cmdBuf->returnCode == 0) {
                sel = sel_getUid("msgTypeToIOReturn:");
                cmdBuf->returnCode = (int)objc_msgSend(portObject, sel, interruptMsg.msgData);
            }
        }

complete_command:
        // Complete the command buffer
        sel = sel_getUid("cmdBufComplete:");
        objc_msgSend(portObject, sel, cmdBuf);
    }
}

int _strobeChar(int portNum, unsigned int delay, char useSpl)
{
    unsigned char controlRegValue;
    unsigned int dataRegAddr;
    unsigned int controlRegAddr;
    int savedPriority = 0;
    unsigned char dataByte;

    // Validate port number
    if (portNum >= PP_KERN_MAX_PORTS)
        return 0;

    // Check if there are bytes remaining to send
    if (pp_bytes_remaining[portNum] <= 0)
        return 0;

    // Get port control structure
    if (pp_port_controls[portNum] == NULL)
        return 0;

    // Read register addresses and current control value
    dataRegAddr = pp_port_controls[portNum]->dataReg;
    controlRegAddr = pp_port_controls[portNum]->controlRegAddr;
    controlRegValue = pp_port_controls[portNum]->controlRegValue;

    // Raise interrupt priority if requested
    if (useSpl != 0) {
        savedPriority = spl3();
    }

    // Double-check bytes remaining after potential sleep
    if (pp_bytes_remaining[portNum] > 0) {
        // Get the data byte from the buffer
        dataByte = **(pp_data_buffers[portNum]);

        // Write data to data register
        outb(dataRegAddr, dataByte);

        // Increment strobe counter (with lock)
        // TODO: Add proper locking mechanism
        pp_strobe_count++;

        // Delay after writing data
        IODelay(delay);

        // Assert strobe (set bit 0)
        outb(controlRegAddr, controlRegValue | 0x01);

        // Increment strobe counter
        pp_strobe_count++;

        // Delay while strobe is asserted
        IODelay(delay);

        // Deassert strobe (clear bit 0)
        outb(controlRegAddr, controlRegValue & 0xFE);

        // Increment strobe counter
        pp_strobe_count++;

        // Delay after deasserting strobe
        IODelay(delay);

        // Advance buffer pointer
        (*(pp_data_buffers[portNum]))++;

        // Decrement bytes remaining
        pp_bytes_remaining[portNum]--;

        // Restore interrupt priority if we changed it
        if (useSpl != 0) {
            splx(savedPriority);
        }

        return 1;  // Success
    }

    // Restore interrupt priority if we changed it
    if (useSpl != 0) {
        splx(savedPriority);
    }

    return 0;  // No data to send
}

#endif /* KERNEL */
