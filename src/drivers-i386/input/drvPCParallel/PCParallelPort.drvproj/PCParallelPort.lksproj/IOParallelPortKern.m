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
#import "IOParallelPort.h"
#import <driverkit/i386/ioPorts.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/IODirectDevice.h>
#import <kernserv/i386/spl.h>
#import <mach/message.h>
#import <sys/errno.h>
#import <sys/types.h>
#import <sys/uio.h>
#import <sys/conf.h>
#import <sys/buf.h>
#import <sys/systm.h>

// Device number extraction macros
#ifndef minor
#define minor(x)  ((int)((x) & 0xff))
#endif

// Interrupt message type codes
#define PP_INT_MSG_COMPLETE     0x232325
#define PP_INT_MSG_OFFLINE      0x232336
#define PP_INT_MSG_PAPER_OUT    0x232337
#define PP_INT_MSG_DEVICE_BUSY  0x232338
#define PP_INT_MSG_ERROR        0x232339

/*
 * Error return codes, by value, because the IO_R_* names in
 * <driverkit/return.h> do not describe two of them: -738 has no name there at
 * all, and -737 is IO_R_MSG_TOO_LARGE, not a paper-out code.  The other three
 * values are named: -703 is IO_R_IPC_FAILURE, -726 is IO_R_TIMEOUT and -725 is
 * IO_R_BUSY.
 */
#define PP_IO_ERROR             (-703)
#define PP_OFFLINE_ERROR        (-738)
#define PP_PAPER_OUT_ERROR      (-737)
#define PP_TIMEOUT_ERROR        (-726)
#define PP_BUSY_ERROR           (-725)

// Message receive options and return codes.  0x500 is RCV_TIMEOUT|RCV_INTERRUPT
// from <mach/message.h>; it does not include RCV_LARGE, which is 0x1000.
#define MSG_OPTION_RCV_TIMEOUT_INTR     0x500
#define MSG_RCV_INTERRUPTED     (-207)
#define MSG_RCV_TIMED_OUT       (-203)

// Error codes (if not already defined)
#ifndef ETIMEDOUT
#define ETIMEDOUT       60        // Connection timed out
#endif
#ifndef EBUSY
#define EBUSY           16        // Device busy
#endif

//
// Software control structure
//

pp_softc_t pp_softc[1] = { { nil, 0, NULL } };

// Character device interface — use system enodev from <sys/systm.h>

int ppopen(dev_t dev, int flags, int devtype, void *p)
{
    IOParallelPort *port;
    IOReturn result;

    port = (IOParallelPort *)pp_softc[minor(dev)].device;

    if ([port isInUse])
        return EBUSY;

    // Accept success and the four printer conditions the caller can act on:
    // busy (-725), not ready (-726), paper out (-737) and offline (-738).
    result = [port initDevice];
    if (!(result == 0 ||
          (result >= PP_TIMEOUT_ERROR && result <= PP_BUSY_ERROR) ||
          (result >= PP_OFFLINE_ERROR && result <= PP_PAPER_OUT_ERROR)))
        return EIO;

    [port setInUse:YES];
    return 0;
}

int ppclose(dev_t dev, int flags, int devtype, void *p)
{
    IOParallelPort *port;

    port = (IOParallelPort *)pp_softc[minor(dev)].device;

    // Mark device as not in use
    [port setInUse:NO];

    return 0;
}

int ppread(dev_t dev, void *uio, int ioflag)
{
    IOParallelPort *port;
    int result;

    port = (IOParallelPort *)pp_softc[minor(dev)].device;
    if (port == nil)
        return ENXIO;

    // Lock the device for I/O
    [port lockSize];

    // Perform physical I/O (read operation - B_READ flag)
    result = physio((void *)ppstrategy, [port physbuf], dev, B_READ,
                    ppminphys, uio, [port blockSize]);

    // Unlock the device
    [port unlockSize];

    return result;
}

int ppwrite(dev_t dev, void *uio, int ioflag)
{
    IOParallelPort *port;
    struct uio *uioPtr = (struct uio *)uio;
    struct iovec *iov = NULL;
    int result;
    IOReturn initResult;
    BOOL dataCopied = NO;
    void *tempBuffer = NULL;
    int copySize = 0;
    int savedSegflg = 0;
    char *savedBase;
    int savedLen;

    port = (IOParallelPort *)pp_softc[minor(dev)].device;
    if (port == nil)
        return ENXIO;

    // Check if device is initialized
    if (![port isInitialized]) {
        initResult = [port initDevice];

        // The same four printer conditions ppopen accepts mean "nothing to
        // write about"; the reference returns 0 without writing.
        if ((initResult >= PP_TIMEOUT_ERROR && initResult <= PP_BUSY_ERROR) ||
            (initResult >= PP_OFFLINE_ERROR && initResult <= PP_PAPER_OUT_ERROR))
            return 0;
        if (initResult != 0)
            return EIO;
    }

    // Check if data is in user space (not kernel space)
    if (uioPtr->uio_segflg != UIO_SYSSPACE) {
        iov = uioPtr->uio_iov;
        copySize = iov->iov_len;

        // Limit copy size to 0x8000 (32KB)
        if (copySize > 0x8000) {
            copySize = 0x8000;
        }

        // Allocate temporary kernel buffer and copy the data down
        tempBuffer = IOMalloc(copySize);
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
    [port lockSize];

    // Zero out physical buffer (0x80 = 128 bytes)
    bzero([port physbuf], 0x80);

    // Perform physical I/O (write operation - no B_READ flag, so 0)
    result = physio((void *)ppstrategy, [port physbuf], dev, 0,
                    ppminphys, uio, [port blockSize]);

    // Unlock the device
    [port unlockSize];

    // If we copied data, restore original values and free temp buffer
    if (dataCopied) {
        uioPtr->uio_segflg = savedSegflg;
        iov->iov_base = savedBase;
        iov->iov_len = savedLen;

        IOFree(tempBuffer, copySize);

        // Account for the bytes the clamp above left behind
        uioPtr->uio_resid += (iov->iov_len - copySize);
    }

    return result;
}

int ppioctl(dev_t dev, unsigned long cmd, void *data, int flag, void *p)
{
    IOParallelPort *port;
    unsigned int *uintData = (unsigned int *)data;
    int timeout;

    port = (IOParallelPort *)pp_softc[minor(dev)].device;
    if (port == nil)
        return ENXIO;

    // Process ioctl command
    switch (cmd) {
        // SET operations (write to device)
        case PP_IOCTL_SET_INT_HANDLER_DELAY:
            [port setIntHandlerDelay:*uintData];
            return 0;

        case PP_IOCTL_SET_MIN_PHYS:
            [port setMinPhys:*uintData];
            return 0;

        case PP_IOCTL_SET_IO_THREAD_DELAY:
            [port setIOThreadDelay:*uintData];
            return 0;

        case PP_IOCTL_SET_BLOCK_SIZE:
            [port setBlockSize:*uintData];
            return 0;

        case PP_IOCTL_SET_BUSY_RETRY_INTERVAL:
            [port setBusyRetryInterval:*uintData];
            return 0;

        case PP_IOCTL_SET_BUSY_MAX_RETRIES:
            [port setBusyMaxRetries:*uintData];
            return 0;

        case PP_IOCTL_SET_TIMEOUT:
            // Special handling for timeout setting
            if (*uintData == 0xFFFFFFFF) {
                // Wait forever mode
                [port setBusyMaxRetries:10];
                [port setBusyRetryInterval:1000];
                [port setIoTimeout:2000];
                [port setWaitForever:YES];
            } else {
                // Timeout in seconds
                [port setBusyMaxRetries:1];
                timeout = *uintData * 1000;  // Convert to milliseconds
                [port setBusyRetryInterval:timeout];
                [port setIoTimeout:timeout];
                [port setWaitForever:NO];
            }
            return 0;

        // GET operations (read from device)
        case PP_IOCTL_GET_INT_HANDLER_DELAY:
            *uintData = [port intHandlerDelay];
            return 0;

        case PP_IOCTL_GET_MIN_PHYS:
            *uintData = [port minPhys];
            return 0;

        case PP_IOCTL_GET_IO_THREAD_DELAY:
            *uintData = [port IOThreadDelay];
            return 0;

        case PP_IOCTL_GET_BLOCK_SIZE:
            *uintData = [port blockSize];
            return 0;

        case PP_IOCTL_GET_BUSY_RETRY_INTERVAL:
            *uintData = [port busyRetryInterval];
            return 0;

        case PP_IOCTL_GET_BUSY_MAX_RETRIES:
            *uintData = [port busyMaxRetries];
            return 0;

        case PP_IOCTL_GET_STATUS_WORD:
            *uintData = [port statusWord];
            return 0;

        case PP_IOCTL_GET_STATUS_REG_CONTENTS:
            *uintData = [port statusRegisterContents] & 0xFF;
            return 0;

        case PP_IOCTL_GET_CONTROL_REG_CONTENTS:
            *uintData = [port controlRegisterContents] & 0xFF;
            return 0;

        case PP_IOCTL_GET_CONTROL_REG_DEFAULTS:
            *uintData = [port controlRegisterDefaults] & 0xFF;
            return 0;

        default:
            // Unknown ioctl command
            return EINVAL;
    }
}

int ppstrategy(struct buf *bp)
{
    IOParallelPort *port;
    int portNum = minor(bp->b_dev);
    IOReturn result;

    port = (IOParallelPort *)pp_softc[portNum].device;
    if (port == nil) {
        bp->b_error = ENXIO;
        bp->b_flags |= (B_DONE | B_ERROR);
        return -1;
    }

    // Check if this is a READ or WRITE operation
    if ((bp->b_flags & B_READ) == 0) {
        // WRITE operation: hand the transfer to the port, by value
        pp_softc[portNum].data = (unsigned char *)bp->b_un.b_addr;
        pp_softc[portNum].count = bp->b_bcount;

        result = [port writeToPort];

        // Update residual count
        bp->b_resid = pp_softc[portNum].count;
    } else {
        // READ operation
        result = [port readFromPort];
    }

    // Mark buffer as done
    bp->b_flags |= B_DONE;

    if (result == 0) {
        // Success - clear error flag
        bp->b_flags &= ~B_ERROR;
        return 0;
    }

    // Error occurred - set error flag and map the IOReturn to an errno
    bp->b_flags |= B_ERROR;

    switch (result) {
        case PP_PAPER_OUT_ERROR:    // -737
        case PP_OFFLINE_ERROR:      // -738
            bp->b_error = 0x53;     // 83
            break;

        case PP_TIMEOUT_ERROR:      // -726
            bp->b_error = ETIMEDOUT;  // 60
            break;

        case PP_BUSY_ERROR:         // -725
            bp->b_error = EBUSY;    // 16
            break;

        default:
            bp->b_error = EIO;      // 5
            break;
    }

    return -1;
}

unsigned int ppminphys(struct buf *bp)
{
    IOParallelPort *port;
    unsigned int minPhysValue;

    port = (IOParallelPort *)pp_softc[minor(bp->b_dev)].device;

    minPhysValue = [port minPhys];

    // Clamp the caller's count without touching the buffer
    if (bp->b_bcount > minPhysValue)
        return minPhysValue;

    return bp->b_bcount;
}

//
// Internal helper functions
//

void IOParallelPortInterruptHandler(void *identity, void *state, unsigned int portNum)
{
    IOParallelPort *port;
    struct buf *physbuf;
    const char *dataRegAddr;
    unsigned int delay;
    unsigned char statusByte;
    int interruptMsg = 0;

    port = (IOParallelPort *)pp_softc[portNum].device;
    physbuf = port->physbuf;
    dataRegAddr = port->dataRegister;
    delay = port->intHandlerDelay;

    // Read status register
    statusByte = inb(PP_PORT(port->statusRegister));

    // Only a write in progress arms this handler
    if (!((IOParallelPort *)pp_softc[portNum].device)->writing)
        return;

    // Decode status register to determine error condition
    if ((statusByte & 0x28) == 0x08) {
        // Mask is ERROR|PAPER_OUT: error bit set, paper-out bit clear
        if ((char)statusByte >= 0) {
            // Busy: PP_STATUS_BUSY is inverted, so a clear bit 7 means busy
            interruptMsg = PP_INT_MSG_DEVICE_BUSY;
        }
    } else {
        if (statusByte & 0x20) {
            // Paper out
            interruptMsg = PP_INT_MSG_PAPER_OUT;
        } else if (statusByte & 0x10) {
            // Select set
            interruptMsg = PP_INT_MSG_OFFLINE;
        } else {
            // Select clear
            interruptMsg = PP_INT_MSG_ERROR;
        }
    }

    // If no error, handle data transfer
    if (interruptMsg == 0) {
        if ((physbuf->b_flags & B_READ) == 0) {
            // Output mode: send next character if available
            if (pp_softc[portNum].count > 0) {
                _strobeChar(portNum, delay, 0);
                return;
            }
        } else {
            // Input mode: advance, then store
            if (pp_softc[portNum].count != 0) {
                pp_softc[portNum].data++;
                pp_softc[portNum].count--;
                *(pp_softc[portNum].data) = inb(PP_PORT(dataRegAddr));
            }
        }

        // More data to transfer, no interrupt needed
        if (pp_softc[portNum].count > 0)
            return;

        interruptMsg = PP_INT_MSG_COMPLETE;
    }

    // Send interrupt message to waiting thread
    IOSendInterrupt(identity, state, interruptMsg);
}

/*
 * Decode a not-ready status into the command buffer's return code.  The two
 * decodes in this thread are deliberately different: the first one clears
 * errorFlag in the SELECT-set case and never yields -725.
 */
void IOParallelPortThread(void *portObject)
{
    IOParallelPort *port = (IOParallelPort *)portObject;
    msg_header_t *interruptMsg;
    PPCommandBuffer *cmdBuf;
    unsigned char statusByte;
    BOOL deviceReady;
    int msgResult;
    int timeout;
    int ioTimeout;
    int elapsedTime;

    // The interrupt receive buffer is the 8192-byte allocation made at init
    interruptMsg = [port interruptMessage];

    // Main I/O loop
    while (1) {
        // Wait for command buffer
        cmdBuf = (PPCommandBuffer *)[port waitForCmdBuf];

        // Check command type
        if (cmdBuf->commandType == 1) {
            // Exit command
            [port cmdBufComplete:cmdBuf];
            IOExitThread();
        }

        if (cmdBuf->commandType != 0) {
            // Unknown command
            goto complete_command;
        }

        // Read status register
        statusByte = inb(PP_PORT([port statusRegister]));

        // Check if device is ready (status & 0xb8 == 0x98)
        if ((statusByte & 0xb8) != 0x98) {
            // Device not ready, wait for it
            [port _waitForDevice:[port waitForever] isReady:&deviceReady];

            if (!deviceReady) {
                if ((statusByte & 0x08) == 0) {
                    cmdBuf->errorFlag = 1;
                    if (statusByte & 0x20) {
                        cmdBuf->returnCode = PP_PAPER_OUT_ERROR;
                    } else if (statusByte & 0x10) {
                        cmdBuf->errorFlag = 0;
                        cmdBuf->returnCode = PP_TIMEOUT_ERROR;
                    } else {
                        cmdBuf->returnCode = PP_OFFLINE_ERROR;
                    }
                } else {
                    cmdBuf->errorFlag = 0;
                    if (statusByte & 0x20) {
                        cmdBuf->returnCode = PP_PAPER_OUT_ERROR;
                    } else {
                        cmdBuf->returnCode = PP_TIMEOUT_ERROR;
                    }
                }

                goto complete_command;
            }
        }

        // Device is ready, perform strobe
        if (!_strobeChar([port minorDevNum], [port IOThreadDelay], 1)) {
            cmdBuf->returnCode = 0;
        } else {
            // Wait for completion interrupt
            cmdBuf->returnCode = 0;
            elapsedTime = 0;
            ioTimeout = [port ioTimeout];

            while (1) {
                // Set up interrupt message
                interruptMsg->msg_local_port = (port_t)[port interruptPort];
                interruptMsg->msg_size = 0x2000;

                // Calculate timeout (500ms or ioTimeout, whichever is smaller)
                timeout = 500;
                if (ioTimeout != 0 && ioTimeout < 500) {
                    timeout = ioTimeout;
                }

                // Receive interrupt message
                msgResult = msg_receive(interruptMsg, MSG_OPTION_RCV_TIMEOUT_INTR, timeout);

                if (msgResult == 0) {
                    // Message received successfully
                    break;
                }

                if (msgResult == MSG_RCV_INTERRUPTED) {
                    continue;
                }

                if (msgResult != MSG_RCV_TIMED_OUT) {
                    // Other error
                    IOLog("%s: msg_receive returned %d\n", [port name], msgResult);
                    cmdBuf->returnCode = PP_IO_ERROR;
                    break;
                }

                // Timeout - check if we should continue waiting
                [port _waitForDevice:[port waitForever] isReady:&deviceReady];

                if (!deviceReady) {
                    // Device not ready
                    statusByte = inb(PP_PORT([port statusRegister]));

                    cmdBuf->errorFlag = 0;
                    if ((statusByte & 0x08) == 0) {
                        cmdBuf->errorFlag = 1;
                    }

                    if (statusByte & 0x20) {
                        cmdBuf->returnCode = PP_PAPER_OUT_ERROR;
                    } else if ((statusByte & 0x10) == 0) {
                        cmdBuf->returnCode = PP_OFFLINE_ERROR;
                    } else if ((char)statusByte >= 0) {
                        cmdBuf->returnCode = PP_BUSY_ERROR;
                    } else {
                        cmdBuf->returnCode = PP_TIMEOUT_ERROR;
                    }
                    break;
                }

                elapsedTime += 500;
                if (elapsedTime >= ioTimeout) {
                    cmdBuf->returnCode = PP_TIMEOUT_ERROR;
                    break;
                }
            }

            // Convert message type to IOReturn if no error
            if (cmdBuf->returnCode == 0) {
                cmdBuf->returnCode = [port msgTypeToIOReturn:interruptMsg->msg_id];
            }
        }

complete_command:
        // Complete the command buffer
        [port cmdBufComplete:cmdBuf];
    }
}

int _strobeChar(int portNum, unsigned int delay, char useSpl)
{
    IOParallelPort *port;
    unsigned char controlRegValue;
    IOEISAPortAddress dataRegAddr;
    IOEISAPortAddress controlRegAddr;
    int savedPriority = 0;

    port = (IOParallelPort *)pp_softc[portNum].device;
    controlRegValue = port->controlRegisterDefaults;
    controlRegAddr = PP_PORT(port->controlRegister);
    dataRegAddr = PP_PORT(port->dataRegister);

    if (pp_softc[portNum].count <= 0)
        return 0;

    // Raise interrupt priority if requested
    if (useSpl != 0) {
        savedPriority = spl3();
    }

    // Re-check bytes remaining now that interrupts are blocked
    if (pp_softc[portNum].count <= 0) {
        if (useSpl != 0) {
            splx(savedPriority);
        }
        return 0;
    }

    // Write the data byte
    outb(dataRegAddr, *(pp_softc[portNum].data));
    IODelay(delay);

    // Assert strobe (set bit 0)
    controlRegValue |= PP_CONTROL_STROBE;
    outb(controlRegAddr, controlRegValue);
    IODelay(delay);

    // Deassert strobe (clear bit 0)
    controlRegValue &= ~PP_CONTROL_STROBE;
    outb(controlRegAddr, controlRegValue);
    IODelay(delay);

    // Advance the transfer
    pp_softc[portNum].data++;
    pp_softc[portNum].count--;

    // Restore interrupt priority if we changed it
    if (useSpl != 0) {
        splx(savedPriority);
    }

    return 1;
}

#endif /* KERNEL */
