/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/**
 * ParallelPortDriver.m - Standard PC Parallel Port Driver Implementation
 */

#import "ParallelPortDriver.h"
#import "ParallelPortRegs.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/i386/directDevice.h>
#import <kernserv/prototypes.h>

@implementation ParallelPortDriver

/*
 * Probe for parallel port hardware
 */
+ (Boolean) probe : deviceDescription
{
    ParallelPortDriver *driver;
    UInt16 port;
    const char *portStr;

    /* Get port address from device description */
    portStr = [deviceDescription valueForStringKey:"Port"];
    if (!portStr) {
        IOLog("ParallelPort: No port address specified\n");
        return NO;
    }

    /* Parse port address */
    if (strcmp(portStr, "LPT1") == 0 || strcmp(portStr, "0x378") == 0) {
        port = LPT1_BASE;
    } else if (strcmp(portStr, "LPT2") == 0 || strcmp(portStr, "0x278") == 0) {
        port = LPT2_BASE;
    } else if (strcmp(portStr, "LPT3") == 0 || strcmp(portStr, "0x3BC") == 0) {
        port = LPT3_BASE;
    } else {
        port = strtoul(portStr, NULL, 16);
    }

    /* Verify port responds */
    outb(port + PP_DATA_REG, 0xAA);
    IODelay(10);
    if (inb(port + PP_DATA_REG) != 0xAA) {
        IOLog("ParallelPort: Port at 0x%x does not respond\n", port);
        return NO;
    }

    outb(port + PP_DATA_REG, 0x55);
    IODelay(10);
    if (inb(port + PP_DATA_REG) != 0x55) {
        IOLog("ParallelPort: Port at 0x%x does not respond\n", port);
        return NO;
    }

    IOLog("ParallelPort: Found parallel port at 0x%x\n", port);

    /* Create driver instance */
    driver = [self alloc];
    if (driver == nil) {
        return NO;
    }

    if ([driver initFromDeviceDescription:deviceDescription] == nil) {
        [driver free];
        return NO;
    }

    return YES;
}

/*
 * Initialize driver instance
 */
- initFromDeviceDescription : deviceDescription
{
    const char *portStr;
    const char *irqStr;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get port address */
    portStr = [deviceDescription valueForStringKey:"Port"];
    if (strcmp(portStr, "LPT1") == 0 || strcmp(portStr, "0x378") == 0) {
        basePort = LPT1_BASE;
        irqNumber = LPT1_IRQ;
    } else if (strcmp(portStr, "LPT2") == 0 || strcmp(portStr, "0x278") == 0) {
        basePort = LPT2_BASE;
        irqNumber = LPT2_IRQ;
    } else if (strcmp(portStr, "LPT3") == 0 || strcmp(portStr, "0x3BC") == 0) {
        basePort = LPT3_BASE;
        irqNumber = LPT3_IRQ;
    } else {
        basePort = strtoul(portStr, NULL, 16);
        irqNumber = LPT1_IRQ; /* Default */
    }

    /* Check for IRQ override */
    irqStr = [deviceDescription valueForStringKey:"IRQ"];
    if (irqStr) {
        irqNumber = atoi(irqStr);
    }

    /* Calculate ECP base if present */
    ecpBase = basePort + ECP_BASE_OFFSET;

    /* Allocate transmit buffer */
    txBufferSize = TX_BUFFER_SIZE;
    txBuffer = IOMalloc(txBufferSize);
    if (!txBuffer) {
        IOLog("ParallelPort: Failed to allocate TX buffer\n");
        [super free];
        return nil;
    }
    txHead = txTail = txCount = 0;

    /* Allocate receive buffer */
    rxBufferSize = RX_BUFFER_SIZE;
    rxBuffer = IOMalloc(rxBufferSize);
    if (!rxBuffer) {
        IOLog("ParallelPort: Failed to allocate RX buffer\n");
        IOFree(txBuffer, txBufferSize);
        [super free];
        return nil;
    }
    rxHead = rxTail = rxCount = 0;

    /* Create locks */
    txLock = [self allocLock];
    rxLock = [self allocLock];
    stateLock = [self allocLock];
    queueLock = [self allocLock];

    /* Initialize transfer queue */
    queue_init(&transferQueue);

    /* Initialize state */
    portOpen = NO;
    portBusy = NO;
    online = NO;
    currentMode = PP_MODE_SPP;
    direction = PP_DIRECTION_OUTPUT;
    irqEnabled = NO;
    dmaEnabled = NO;
    timeout = DEFAULT_TIMEOUT;
    deviceIDValid = NO;

    /* Clear statistics */
    bzero(&stats, sizeof(stats));

    /* Detect capabilities */
    [self detectCapabilities];

    /* Reset port to known state */
    [self resetPort];

    /* Register device */
    [self setName:"ParallelPort"];
    [self setDeviceKind:"Parallel Port"];
    [self setLocation:"ISA"];
    [self registerDevice];

    IOLog("ParallelPort: Initialized at 0x%x, IRQ %d\n", basePort, irqNumber);

    return self;
}

/*
 * Free driver resources
 */
- free
{
    if (portOpen) {
        [self closePort];
    }

    if (txBuffer) {
        IOFree(txBuffer, txBufferSize);
        txBuffer = NULL;
    }

    if (rxBuffer) {
        IOFree(rxBuffer, rxBufferSize);
        rxBuffer = NULL;
    }

    if (txLock) {
        [self freeLock:txLock];
    }
    if (rxLock) {
        [self freeLock:rxLock];
    }
    if (stateLock) {
        [self freeLock:stateLock];
    }

    return [super free];
}

/*
 * Detect port capabilities
 */
- (void) detectCapabilities
{
    UInt8 ecr, oldEcr;

    /* All ports support SPP */
    capabilities.hasSPP = YES;
    capabilities.maxSpeed = SPP_MAX_RATE;

    /* Test for ECP/EPP support via ECR register */
    capabilities.hasECP = NO;
    capabilities.hasEPP = NO;
    capabilities.hasFIFO = NO;
    capabilities.fifoSize = 0;

    /* Try to access ECR register */
    oldEcr = inb(ecpBase + PP_ECP_ECR);

    /* Write test pattern */
    outb(ecpBase + PP_ECP_ECR, 0x34);
    IODelay(10);
    ecr = inb(ecpBase + PP_ECP_ECR);

    if ((ecr & 0xFC) == 0x34) {
        /* ECR is present */
        capabilities.hasECP = YES;
        capabilities.hasEPP = YES;
        capabilities.hasFIFO = YES;
        capabilities.fifoSize = ECP_FIFO_SIZE;
        capabilities.maxSpeed = ECP_MAX_RATE;

        /* Restore ECR */
        outb(ecpBase + PP_ECP_ECR, oldEcr);
    }

    /* PS/2 bidirectional is generally available */
    capabilities.hasPS2 = YES;

    /* Check for IRQ support */
    capabilities.hasIRQ = YES;

    /* DMA only in ECP mode */
    capabilities.hasDMA = capabilities.hasECP;
}

/*
 * Open the parallel port
 */
- (IOReturn) openPort
{
    [self lock:stateLock];

    if (portOpen) {
        [self unlock:stateLock];
        return IO_R_BUSY;
    }

    /* Reset port */
    [self resetPort];

    /* Mark port as open */
    portOpen = YES;

    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Close the parallel port
 */
- (IOReturn) closePort
{
    [self lock:stateLock];

    if (!portOpen) {
        [self unlock:stateLock];
        return IO_R_INVALID_ARG;
    }

    /* Flush buffers */
    [self flushTxBuffer];
    [self flushRxBuffer];

    /* Reset port */
    [self resetPort];

    /* Mark port as closed */
    portOpen = NO;

    [self unlock:stateLock];

    return IO_R_SUCCESS;
}

/*
 * Reset port to default state
 */
- (IOReturn) resetPort
{
    /* Set to SPP mode */
    if (capabilities.hasECP) {
        outb(ecpBase + PP_ECP_ECR, ECR_MODE_SPP);
    }

    /* Initialize control register */
    outb(basePort + PP_CONTROL_REG, CONTROL_INIT | CONTROL_SELECT_IN);
    IODelay(100);

    /* Clear init */
    outb(basePort + PP_CONTROL_REG, CONTROL_SELECT_IN);
    IODelay(100);

    /* Set direction to output */
    direction = PP_DIRECTION_OUTPUT;

    /* Clear data register */
    outb(basePort + PP_DATA_REG, 0);

    /* Update state */
    currentMode = PP_MODE_SPP;

    return IO_R_SUCCESS;
}

/*
 * Set port mode
 */
- (IOReturn) setMode : (ParallelPortMode) mode
{
    UInt8 ecr;

    /* Check if mode is supported */
    switch (mode) {
        case PP_MODE_SPP:
            if (!capabilities.hasSPP) return PP_IO_R_NOT_SUPPORTED;
            ecr = ECR_MODE_SPP;
            break;
        case PP_MODE_PS2:
            if (!capabilities.hasPS2) return PP_IO_R_NOT_SUPPORTED;
            ecr = ECR_MODE_PS2;
            break;
        case PP_MODE_EPP:
            if (!capabilities.hasEPP) return PP_IO_R_NOT_SUPPORTED;
            ecr = ECR_MODE_EPP;
            break;
        case PP_MODE_ECP:
            if (!capabilities.hasECP) return PP_IO_R_NOT_SUPPORTED;
            ecr = ECR_MODE_ECP;
            break;
        default:
            return PP_IO_R_INVALID_MODE;
    }

    /* Set mode via ECR if available */
    if (capabilities.hasECP) {
        outb(ecpBase + PP_ECP_ECR, ecr);
        IODelay(10);
    }

    currentMode = mode;

    return IO_R_SUCCESS;
}

/*
 * Get current port mode
 */
- (IOReturn) getMode : (ParallelPortMode *) mode
{
    if (!mode) return IO_R_INVALID_ARG;
    *mode = currentMode;
    return IO_R_SUCCESS;
}

/*
 * Set data direction
 */
- (IOReturn) setDirection : (ParallelPortDirection) dir
{
    UInt8 control;

    control = inb(basePort + PP_CONTROL_REG);

    if (dir == PP_DIRECTION_INPUT) {
        control |= CONTROL_DIRECTION;
    } else {
        control &= ~CONTROL_DIRECTION;
    }

    outb(basePort + PP_CONTROL_REG, control);
    IODelay(10);

    direction = dir;

    return IO_R_SUCCESS;
}

/*
 * Get data direction
 */
- (IOReturn) getDirection : (ParallelPortDirection *) dir
{
    if (!dir) return IO_R_INVALID_ARG;
    *dir = direction;
    return IO_R_SUCCESS;
}

/*
 * Get port capabilities
 */
- (IOReturn) getCapabilities : (ParallelPortCapabilities *) caps
{
    if (!caps) return IO_R_INVALID_ARG;
    *caps = capabilities;
    return IO_R_SUCCESS;
}

/*
 * Write a single byte (SPP mode)
 */
- (IOReturn) writeByte : (UInt8) byte
{
    UInt8 status, control;
    UInt32 timeout_count = timeout;

    /* Wait for not busy */
    while (timeout_count--) {
        status = inb(basePort + PP_STATUS_REG);
        if (status & STATUS_BUSY) {
            break;  /* Ready (inverted signal) */
        }
        IODelay(1);
    }

    if (timeout_count == 0) {
        stats.timeoutErrors++;
        return PP_IO_R_TIMEOUT;
    }

    /* Write data */
    outb(basePort + PP_DATA_REG, byte);
    IODelay(DATA_SETUP / 1000);

    /* Assert strobe */
    control = inb(basePort + PP_CONTROL_REG);
    outb(basePort + PP_CONTROL_REG, control & ~CONTROL_STROBE);
    IODelay(STROBE_WIDTH / 1000);

    /* Deassert strobe */
    outb(basePort + PP_CONTROL_REG, control | CONTROL_STROBE);
    IODelay(DATA_HOLD / 1000);

    stats.bytesWritten++;

    return IO_R_SUCCESS;
}

/*
 * Read a single byte (requires bidirectional mode)
 */
- (IOReturn) readByte : (UInt8 *) byte
{
    if (!byte) return IO_R_INVALID_ARG;

    if (direction != PP_DIRECTION_INPUT) {
        return PP_IO_R_INVALID_MODE;
    }

    *byte = inb(basePort + PP_DATA_REG);
    stats.bytesRead++;

    return IO_R_SUCCESS;
}

/*
 * Write multiple bytes
 */
- (IOReturn) writeBytes : (const UInt8 *) buffer
                  length : (UInt32) length
            bytesWritten : (UInt32 *) bytesWritten
{
    UInt32 i;
    IOReturn result;

    if (!buffer || !bytesWritten) return IO_R_INVALID_ARG;

    *bytesWritten = 0;

    for (i = 0; i < length; i++) {
        result = [self writeByte:buffer[i]];
        if (result != IO_R_SUCCESS) {
            stats.writeErrors++;
            return result;
        }
        (*bytesWritten)++;
    }

    return IO_R_SUCCESS;
}

/*
 * Read multiple bytes
 */
- (IOReturn) readBytes : (UInt8 *) buffer
                 length : (UInt32) length
               bytesRead : (UInt32 *) bytesRead
{
    UInt32 i;
    IOReturn result;

    if (!buffer || !bytesRead) return IO_R_INVALID_ARG;

    *bytesRead = 0;

    for (i = 0; i < length; i++) {
        result = [self readByte:&buffer[i]];
        if (result != IO_R_SUCCESS) {
            stats.readErrors++;
            return result;
        }
        (*bytesRead)++;
    }

    return IO_R_SUCCESS;
}

/*
 * Get port status
 */
- (IOReturn) getStatus : (ParallelPortStatus *) status
{
    UInt8 statusReg;

    if (!status) return IO_R_INVALID_ARG;

    statusReg = inb(basePort + PP_STATUS_REG);

    status->busy = !(statusReg & STATUS_BUSY);  /* Inverted */
    status->ack = (statusReg & STATUS_ACK) ? YES : NO;
    status->paperOut = (statusReg & STATUS_PAPER_OUT) ? YES : NO;
    status->selectIn = (statusReg & STATUS_SELECT) ? YES : NO;
    status->error = !(statusReg & STATUS_ERROR);  /* Inverted */
    status->online = status->selectIn && !status->busy && !status->error;

    return IO_R_SUCCESS;
}

/*
 * Query methods
 */
- (BOOL) isBusy
{
    UInt8 status = inb(basePort + PP_STATUS_REG);
    return !(status & STATUS_BUSY);
}

- (BOOL) isOnline
{
    ParallelPortStatus status;
    [self getStatus:&status];
    return status.online;
}

- (BOOL) isPaperOut
{
    UInt8 status = inb(basePort + PP_STATUS_REG);
    return (status & STATUS_PAPER_OUT) ? YES : NO;
}

- (BOOL) isError
{
    UInt8 status = inb(basePort + PP_STATUS_REG);
    return !(status & STATUS_ERROR);
}

/*
 * Control signal methods
 */
- (IOReturn) setStrobe : (BOOL) state
{
    UInt8 control = inb(basePort + PP_CONTROL_REG);
    if (state) {
        control &= ~CONTROL_STROBE;
    } else {
        control |= CONTROL_STROBE;
    }
    outb(basePort + PP_CONTROL_REG, control);
    strobe = state;
    return IO_R_SUCCESS;
}

- (IOReturn) setAutoFeed : (BOOL) state
{
    UInt8 control = inb(basePort + PP_CONTROL_REG);
    if (state) {
        control &= ~CONTROL_AUTOFEED;
    } else {
        control |= CONTROL_AUTOFEED;
    }
    outb(basePort + PP_CONTROL_REG, control);
    autoFeed = state;
    return IO_R_SUCCESS;
}

- (IOReturn) setInit : (BOOL) state
{
    UInt8 control = inb(basePort + PP_CONTROL_REG);
    if (state) {
        control &= ~CONTROL_INIT;
    } else {
        control |= CONTROL_INIT;
    }
    outb(basePort + PP_CONTROL_REG, control);
    init = state;
    return IO_R_SUCCESS;
}

- (IOReturn) setSelectOut : (BOOL) state
{
    UInt8 control = inb(basePort + PP_CONTROL_REG);
    if (state) {
        control |= CONTROL_SELECT_IN;
    } else {
        control &= ~CONTROL_SELECT_IN;
    }
    outb(basePort + PP_CONTROL_REG, control);
    selectOut = state;
    return IO_R_SUCCESS;
}

/*
 * Timeout configuration
 */
- (IOReturn) setTimeout : (UInt32) microseconds
{
    timeout = microseconds;
    return IO_R_SUCCESS;
}

- (IOReturn) getTimeout : (UInt32 *) microseconds
{
    if (!microseconds) return IO_R_INVALID_ARG;
    *microseconds = timeout;
    return IO_R_SUCCESS;
}

/*
 * Buffer control
 */
- (IOReturn) flushTxBuffer
{
    [self lock:txLock];
    txHead = txTail = txCount = 0;
    [self unlock:txLock];
    return IO_R_SUCCESS;
}

- (IOReturn) flushRxBuffer
{
    [self lock:rxLock];
    rxHead = rxTail = rxCount = 0;
    [self unlock:rxLock];
    return IO_R_SUCCESS;
}

/*
 * Interrupt handler
 */
- (void) interruptOccurred
{
    UInt8 status;

    stats.interrupts++;

    /* Read status to clear interrupt */
    status = inb(basePort + PP_STATUS_REG);

    /* Handle interrupt based on current mode */
    /* This is a placeholder - full implementation would handle
     * data transfer based on ACK signals */
}

/*
 * Statistics
 */
- (IOReturn) getStatistics : (ParallelPortStats *) pstats
{
    if (!pstats) return IO_R_INVALID_ARG;
    *pstats = stats;
    return IO_R_SUCCESS;
}

- (IOReturn) resetStatistics
{
    bzero(&stats, sizeof(stats));
    return IO_R_SUCCESS;
}

/*
 * Low-level register access
 */
- (UInt8) readDataReg
{
    return inb(basePort + PP_DATA_REG);
}

- (void) writeDataReg : (UInt8) value
{
    outb(basePort + PP_DATA_REG, value);
}

- (UInt8) readStatusReg
{
    return inb(basePort + PP_STATUS_REG);
}

- (UInt8) readControlReg
{
    return inb(basePort + PP_CONTROL_REG);
}

- (void) writeControlReg : (UInt8) value
{
    outb(basePort + PP_CONTROL_REG, value);
}

/*
 * EPP mode operations (stubs for now)
 */
- (IOReturn) eppWriteAddress : (UInt8) address
{
    if (currentMode != PP_MODE_EPP) {
        return PP_IO_R_INVALID_MODE;
    }
    outb(basePort + PP_EPP_ADDR, address);
    return IO_R_SUCCESS;
}

- (IOReturn) eppReadAddress : (UInt8 *) address
{
    if (currentMode != PP_MODE_EPP) {
        return PP_IO_R_INVALID_MODE;
    }
    if (!address) return IO_R_INVALID_ARG;
    *address = inb(basePort + PP_EPP_ADDR);
    return IO_R_SUCCESS;
}

- (IOReturn) eppWriteData : (const UInt8 *) buffer
                    length : (UInt32) length
{
    UInt32 i;
    if (currentMode != PP_MODE_EPP || !buffer) {
        return PP_IO_R_INVALID_MODE;
    }
    for (i = 0; i < length; i++) {
        outb(basePort + PP_EPP_DATA, buffer[i]);
    }
    stats.bytesWritten += length;
    return IO_R_SUCCESS;
}

- (IOReturn) eppReadData : (UInt8 *) buffer
                   length : (UInt32) length
{
    UInt32 i;
    if (currentMode != PP_MODE_EPP || !buffer) {
        return PP_IO_R_INVALID_MODE;
    }
    for (i = 0; i < length; i++) {
        buffer[i] = inb(basePort + PP_EPP_DATA);
    }
    stats.bytesRead += length;
    return IO_R_SUCCESS;
}

/*
 * ECP mode operations (stubs for now)
 */
- (IOReturn) ecpWrite : (const UInt8 *) buffer
                length : (UInt32) length
          bytesWritten : (UInt32 *) bytesWritten
{
    if (currentMode != PP_MODE_ECP) {
        return PP_IO_R_INVALID_MODE;
    }
    /* ECP implementation would use FIFO and DMA */
    return PP_IO_R_NOT_SUPPORTED;
}

- (IOReturn) ecpRead : (UInt8 *) buffer
               length : (UInt32) length
             bytesRead : (UInt32 *) bytesRead
{
    if (currentMode != PP_MODE_ECP) {
        return PP_IO_R_INVALID_MODE;
    }
    /* ECP implementation would use FIFO and DMA */
    return PP_IO_R_NOT_SUPPORTED;
}

/*
 * IEEE 1284 operations (stubs for now)
 */
- (IOReturn) negotiate1284Mode : (ParallelPortMode) mode
{
    /* IEEE 1284 negotiation sequence would go here */
    return PP_IO_R_NOT_SUPPORTED;
}

- (IOReturn) terminate1284Mode
{
    /* IEEE 1284 termination sequence would go here */
    return PP_IO_R_NOT_SUPPORTED;
}

- (IOReturn) getDeviceID : (ParallelPortDeviceID *) devID
{
    if (!devID) return IO_R_INVALID_ARG;

    if (deviceIDValid) {
        *devID = deviceID;
        return IO_R_SUCCESS;
    }

    /* IEEE 1284 device ID retrieval would go here */
    return PP_IO_R_NOT_SUPPORTED;
}

/*
 * Kernel thread and queue management
 */

- (void) minPhys : (struct buf *) bp
{
    if (bp->b_bcount > TX_BUFFER_SIZE) {
        bp->b_bcount = TX_BUFFER_SIZE;
    }
}

- (int) strategyThread
{
    [self processTransferQueue];
    return 0;
}

- (void) handleInterrupt
{
    [self interruptOccurred];
}

- (IOReturn) attachInterrupt : (UInt32) irq
{
    irqNumber = irq;
    irqEnabled = YES;
    return IO_R_SUCCESS;
}

- (void) detachInterrupt
{
    irqEnabled = NO;
}

/*
 * Buffer and transfer queue operations
 */

- (IOReturn) enqueueTransfer : (void *) transfer
{
    if (!transfer) return IO_R_INVALID_ARG;
    [self lock:queueLock];
    queue_enter(&transferQueue, transfer, void *, chain);
    [self unlock:queueLock];
    return IO_R_SUCCESS;
}

- (void *) dequeueTransfer
{
    void *transfer = NULL;
    [self lock:queueLock];
    if (!queue_empty(&transferQueue)) {
        queue_remove_first(&transferQueue, transfer, void *, chain);
    }
    [self unlock:queueLock];
    return transfer;
}

- (IOReturn) abortTransfer : (void *) transfer
{
    if (!transfer) return IO_R_INVALID_ARG;
    [self lock:queueLock];
    queue_remove(&transferQueue, transfer, void *, chain);
    [self unlock:queueLock];
    return IO_R_SUCCESS;
}

- (void) processTransferQueue
{
    void *transfer;
    while ((transfer = [self dequeueTransfer]) != NULL) {
        /* Process transfer based on type */
    }
}

/*
 * Device node operations
 */

- (IOReturn) createDeviceNode : (const char *) path
                   minorNumber : (UInt32) minor
{
    IOLog("ParallelPort: Creating device node %s (minor %d)\n", path, minor);
    return IO_R_SUCCESS;
}

- (IOReturn) removeDeviceNode
{
    return IO_R_SUCCESS;
}

/*
 * Power management
 */

- (IOReturn) setPowerState : (UInt32) state
{
    switch (state) {
        case 0:
            [self closePort];
            break;
        case 1:
            break;
        case 2:
            [self openPort];
            break;
        default:
            return IO_R_INVALID_ARG;
    }
    return IO_R_SUCCESS;
}

- (IOReturn) getPowerState : (UInt32 *) state
{
    if (!state) return IO_R_INVALID_ARG;
    *state = portOpen ? 2 : 0;
    return IO_R_SUCCESS;
}

/*
 * Lock management extensions
 */

- (id) allocLock
{
    return [super allocLock];
}

- (void) lock : (id) lockObj
{
    [super lock:lockObj];
}

- (void) unlock : (id) lockObj
{
    [super unlock:lockObj];
}

- (void) freeLock : (id) lockObj
{
    [super freeLock:lockObj];
}

@end
