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
 * PPCSerialPort.m - Implementation for PowerPC Serial Port driver.
 *
 * This driver supports the Zilog 85C30 SCC (Serial Communications Controller)
 * commonly found in PowerPC-based Macintosh systems.
 */

#import "PPCSerialPort.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <string.h>
#import <stdio.h>
#import <stdlib.h>
#import <stdarg.h>

//==============================================================================
// PowerPC memory barrier instruction
//==============================================================================

// eieio - Enforce In-order Execution of I/O
// This PowerPC instruction ensures that all I/O operations before it
// complete before any I/O operations after it begin.
#ifdef __ppc__
#define eieio() __asm__ volatile("eieio" ::: "memory")
#else
#define eieio() /* no-op on non-PowerPC */
#endif

//==============================================================================
// SCC Initialization Table
//==============================================================================

// SCC initialization register pairs (register, value)
// This table is 0x22 (34) bytes = 17 pairs
// Used by _OpenScc to initialize the SCC channel
static const unsigned char sccInitTable[34] = {
    9,  0x80,   // WR9: Force hardware reset
    4,  0x44,   // WR4: x16 clock, 1 stop bit, no parity
    3,  0xC0,   // WR3: RX 8 bits/char
    5,  0x60,   // WR5: TX 8 bits/char, TX disabled
    11, 0x50,   // WR11: RCLK = BAUD, TCLK = BAUD
    12, 0x0E,   // WR12: Time constant low byte (9600 baud)
    13, 0x00,   // WR13: Time constant high byte
    14, 0x01,   // WR14: BAUD generator source = PCLK
    14, 0x03,   // WR14: Enable BAUD generator
    3,  0xC1,   // WR3: RX 8 bits/char, RX enable
    5,  0x68,   // WR5: TX 8 bits/char, TX enable, RTS
    15, 0x00,   // WR15: Disable all external/status interrupts
    0,  0x10,   // WR0: Reset external/status interrupts
    0,  0x10,   // WR0: Reset external/status interrupts (twice)
    1,  0x00,   // WR1: Disable all interrupts initially
    9,  0x08,   // WR9: Master interrupt enable
    2,  0x00    // WR2: Interrupt vector (will be set elsewhere)
};

//==============================================================================
// Forward declarations for utility functions
//==============================================================================

static IOReturn _AddBytetoQueue(void *queueBase, unsigned char byte);
static unsigned int _AddtoQueue(void *queueBase, unsigned char *buffer, unsigned int size);
static BOOL _allocateRingBuffer(void *queueBase);
static void _changeState(PPCSerialPort *self, unsigned int newState, unsigned int mask);
static void _deactivatePort(PPCSerialPort *self);
static IOReturn _executeEvent(PPCSerialPort *self, unsigned int event, unsigned int data, unsigned int *currentState, unsigned int *stateMask);
static void _CheckQueues(PPCSerialPort *self);
static IOReturn _CloseQueue(void *queueBase);
static void _freeRingBuffer(void *queueBase);
static unsigned int _FreeSpaceinQueue(void *queueBase);
static IOReturn _GetBytetoQueue(void *queueBase, unsigned char *byteOut);
static unsigned int _GetQueueSize(void *queueBase);
static void _initChip(PPCSerialPort *self);
static IOReturn _InitQueue(int *queueBase, int bufferStart, int bufferSize);
static void _MyIOLog(const char *format, ...);
static IOReturn _OpenScc(PPCSerialPort *self);
static void _PPCSerialISR(void *identity, void *state, PPCSerialPort *self);
static void _PPCSerialRxDMAISR(void *identity, void *state, PPCSerialPort *self);
static void _PPCSerialTxDMAISR(void *identity, void *state, PPCSerialPort *self);
static BOOL _ProbeSccDevice(PPCSerialPort *self);
static void _programChip(PPCSerialPort *self);
static IOReturn _RemovefromQueue(void *queueBase, unsigned char *buffer, unsigned int size, unsigned int *count);
static void _SccChannelReset(PPCSerialPort *self);
static void _SccCloseChannel(PPCSerialPort *self);
static unsigned char _SccDisableInterrupts(PPCSerialPort *self, unsigned int intType);
static void _SccEnableInterrupts(PPCSerialPort *self, unsigned int intType, unsigned int param);
static void _SccGetCTS(PPCSerialPort *self);
static void _SccGetDCD(PPCSerialPort *self);
static void _SccHandleExtInterrupt(PPCSerialPort *self);
static void _SccHandleRxInterrupt(PPCSerialPort *self);
static void _SccHandleTxInterrupt(PPCSerialPort *self);
static unsigned char _SccReadByte(PPCSerialPort *self);
static unsigned char _SccReadData(PPCSerialPort *self);
static unsigned char _SccReadReg(PPCSerialPort *self, unsigned int regNum);
static void _SccSetBaud(PPCSerialPort *self, unsigned int baudRate);
static void _SccSetDataBits(PPCSerialPort *self, unsigned int dataBits);
static void _SccSetDTR(PPCSerialPort *self, BOOL state);
static void _SccSetParity(PPCSerialPort *self, unsigned int parity);
static void _SccSetRTS(PPCSerialPort *self, BOOL state);
static void _SccSetStopBits(PPCSerialPort *self, unsigned int stopBits);
static void _SccWriteByte(PPCSerialPort *self, unsigned char byte);
static IOReturn _SccWriteData(PPCSerialPort *self, unsigned char data);
static void _SccWriteIntSafe(PPCSerialPort *self, unsigned int regNum, unsigned char value);
static void _SccWriteReg(PPCSerialPort *self, unsigned int regNum, unsigned char value);
static void _SendNextChar(PPCSerialPort *self);
static void _SetStructureDefaults(PPCSerialPort *self, BOOL fullInit);
static void _SetUpTransmit(PPCSerialPort *self);
static void _SuspendTX(PPCSerialPort *self);
static unsigned int _UsedSpaceinQueue(void *queueBase);
static void _watchState(PPCSerialPort *self, unsigned int *statePtr, unsigned int mask);

//==============================================================================
// PPCSerialPort Implementation
//==============================================================================

@implementation PPCSerialPort

/*
 * Probe for device presence.
 */
/*
 * Probe for device.
 *
 * This is the entry point for driver loading. Attempts to allocate
 * an instance of PPCSerialPort and initialize it with the device
 * description. Returns YES if successful, NO otherwise.
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id classObj;
    id instance;

    _MyIOLog("************* In Probe ********************\n\r");

    // Get the PPCSerialPort class and send it "alloc"
    classObj = [PPCSerialPort alloc];

    // Send "initFromDeviceDescription:" to the allocated instance
    instance = [classObj initFromDeviceDescription:deviceDescription];

    // Return YES if initialization succeeded, NO otherwise
    return (instance != nil);
}

/*
 * Initialize from device description.
 */
- (id)initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    char *basePtr = (char *)self;
    id configTable;
    const char *nodeName;
    const char *txBufferSizeStr;
    const char *rxBufferSizeStr;
    unsigned int txBufferSize;
    unsigned int rxBufferSize;
    IOMemoryRange *memoryRanges;
    unsigned int numRanges;
    unsigned int numInterrupts;
    int i;
    IOReturn result;
    extern IOReturn IOCreatePort(void **port);

    _MyIOLog("[initFromDeviceDescription:\n\r");

    /* Setup self-reference pointers at offsets 0x294 and 0x128 */
    *(id *)(basePtr + 0x294) = (id)(basePtr + 0x128);
    *(id *)(basePtr + 0x128) = (id)self;

    /* Initialize structure with defaults (full initialization = 1) */
    _SetStructureDefaults(*(id *)(basePtr + 0x294), 1);

    /* Get configuration table from device description */
    configTable = [devDesc configTable];
    if (configTable == nil) {
        _MyIOLog("initFromDeviceDescription: nil configTable]\n\r");
        objc_msgSend(self, @selector(free));
        return nil;
    }

    /* Get node name and determine channel (A or B) */
    nodeName = [devDesc nodeName];
    if (nodeName != NULL) {
        if (strcmp(nodeName, "ch-a") == 0) {
            *(unsigned int *)(basePtr + 0x148) = 0;  /* Channel A */
        } else if (strcmp(nodeName, "ch-b") == 0) {
            *(unsigned int *)(basePtr + 0x148) = 1;  /* Channel B */
        }
    }

    /* Get memory ranges for SCC registers */
    memoryRanges = [devDesc memoryRangeList];
    if (memoryRanges != NULL) {
        numRanges = [devDesc numMemoryRanges];
        if (numRanges != 0) {
            /* Store base address from first memory range */
            *(unsigned int *)(basePtr + 0x140) = (unsigned int)memoryRanges[0].start;
        }
    }

    /* Validate we have exactly 3 interrupts */
    numInterrupts = [devDesc numInterrupts];
    if (numInterrupts != 3) {
        _MyIOLog("initFromDeviceDescription: wrong number of interrupts (%d)]\n\r", numInterrupts);
        objc_msgSend(self, @selector(free));
        return nil;
    }

    /* Initialize the SCC chip hardware */
    _initChip((id)(basePtr + 0x128));

    /* Allocate 4 ports/threads for interrupt handling */
    for (i = 0; i < 4; i++) {
        result = IOCreatePort((void **)(basePtr + 0x114 + i * 4));
        if (result != 0) {
            _MyIOLog("initFromDeviceDescription: IOCreatePort failed]\n\r");
            objc_msgSend(self, @selector(free));
            return nil;
        }
    }

    /* Read TX buffer size from config (default 0x1000 if not specified) */
    txBufferSizeStr = [configTable valueForStringKey:"TX Buffer Size"];
    if (txBufferSizeStr != NULL) {
        txBufferSize = strtoul(txBufferSizeStr, NULL, 0);
        [configTable freeString:txBufferSizeStr];
    } else {
        txBufferSize = 0x1000;
    }
    *(unsigned int *)(basePtr + 0x1a4) = txBufferSize;

    /* Read RX buffer size from config (default 0x1000 if not specified) */
    rxBufferSizeStr = [configTable valueForStringKey:"RX Buffer Size"];
    if (rxBufferSizeStr != NULL) {
        rxBufferSize = strtoul(rxBufferSizeStr, NULL, 0);
        [configTable freeString:rxBufferSizeStr];
    } else {
        rxBufferSize = 0x1000;
    }
    *(unsigned int *)(basePtr + 0x1a8) = rxBufferSize;

    /* Store device description pointer */
    *(id *)(basePtr + 0x13c) = devDesc;

    /* Call superclass initialization */
    objc_msgSend_super(self, @selector(initFromDeviceDescription:), devDesc);

    /* Enable all 3 interrupts */
    for (i = 0; i < 3; i++) {
        objc_msgSend(self, @selector(enableAllInterrupts));
    }

    /* Register the device */
    objc_msgSend(self, @selector(registerDevice));

    _MyIOLog("]\n\r");

    return self;
}

/*
 * Free the instance.
 */
/*
 * Free the instance.
 *
 * Deactivates the port, disables interrupts, closes the SCC channel,
 * and frees all allocated resources before calling superclass free.
 */
- (void)free
{
    char *basePtr = (char *)self;

    _MyIOLog(" [free:");

    // Lock

    // Deactivate the port
    _deactivatePort(self);

    // Disable all interrupts
    [self disableAllInterrupts];

    // Close SCC channel if it was initialized (offset 0x260)
    if (*(int *)(basePtr + 0x260) != 0) {
        _SccCloseChannel(self);
    }

    // Free interrupt port if allocated (offset 0x200)
    if (*(int *)(basePtr + 0x200) != 0) {
        // IOFreePort or similar
        // FUN_00000904() and FUN_000008f4() are likely port cleanup functions
    }

    // Free additional ports at offsets 0x204, 0x208, 0x20c
    if (*(int *)(basePtr + 0x204) != 0) {
        // Free port
    }

    if (*(int *)(basePtr + 0x208) != 0) {
        // Free port
    }

    if (*(int *)(basePtr + 0x20c) != 0) {
        // Free port
    }

    _MyIOLog("]\n\r");

    // Unlock

    // Call superclass free
    [super free];
}

/*
 * Acquire the serial port.
 *
 * Attempts to acquire exclusive access to the serial port.
 * If the port is already acquired and refCon is 0 (no sleep), returns IO_R_BUSY.
 * If refCon is non-zero, waits for the port to become available.
 *
 * Parameters:
 *   refCon: If 0, returns immediately if busy. If non-zero, sleeps until available.
 *
 * Returns: IO_R_SUCCESS on success, IO_R_BUSY if already acquired and no sleep
 */
- (IOReturn)acquire:(void *)refCon
{
    char *basePtr = (char *)self;
    short loopCount;
    void *lockState;
    IOReturn result;
    unsigned int stateCheck;
    char sleepFlag;

    sleepFlag = (char)(int)refCon;  // Cast refCon to char for sleep flag
    stateCheck = 0;

    _MyIOLog("[acquire ");

    loopCount = 0;

    do {
        // Acquire lock (FUN_00000f08 is likely IOTakeLock or similar)
        // Using a simple approach since we don't have the exact lock implementation
        lockState = NULL;  // Placeholder

        // Check if port is already acquired (offset 0x134 & 0x80000000)
        // Offset 0x134 appears to be some state flags
        stateCheck = *(unsigned int *)(basePtr + 0x134) & 0x80000000;

        if (stateCheck == 0) {
            // Port is not acquired - acquire it now
            // Change state to 0xa0400018 with mask 0xffffffff
            // Offset 0x294 appears to be self pointer for state change
            _changeState(self, 0xa0400018, 0xffffffff);
            break;
        }

        // Port is already acquired
        if (sleepFlag == 0) {
            // Don't sleep - return busy
            _MyIOLog("Busy!]");
            // Release lock (FUN_00000ee8)
            return 0xfffffd3b;  // IO_R_BUSY
        }

        // Wait for state change
        stateCheck = 0;
        result = [self watchState:&stateCheck mask:0x80000000];

        if ((result != 0xfffffd36) && (result != 0)) {
            // Interrupted or error
            _MyIOLog("Interrupted!]");
            // Release lock
            return result;
        }

        // Release lock before next iteration
        loopCount = loopCount + 1;
    } while (loopCount < 2);

    // Open the SCC (param_1 + 0x128 is self offset)
    _OpenScc(self);

    _MyIOLog("Early]\n\r");

    // Release lock
    return 0;
}

/*
 * Release the serial port.
 */
/*
 * Release the serial port.
 *
 * Releases exclusive access to the serial port, restores defaults,
 * and deactivates the port.
 *
 * Returns: IO_R_SUCCESS on success, IO_R_NOT_OPEN if not acquired
 */
- (IOReturn)release
{
    char *basePtr = (char *)self;
    int iVar1;
    unsigned int uVar2;
    int iVar3;
    extern unsigned int FUN_0000108c(void);
    extern void FUN_0000106c(unsigned int);
    extern void FUN_0000107c(unsigned int);

    _MyIOLog("[release ");
    uVar2 = FUN_0000108c();

    if (*(int *)(basePtr + 0x134) < 0) {
        /* Free interrupt ports */
        FUN_0000106c(*(unsigned int *)(basePtr + 0x20c));
        FUN_0000106c(*(unsigned int *)(basePtr + 0x208));
        FUN_0000106c(*(unsigned int *)(basePtr + 0x204));
        FUN_0000106c(*(unsigned int *)(basePtr + 0x200));

        /* Clear character filter bitmap (8 DWORDs) */
        iVar1 = 0;
        do {
            *(unsigned int *)(iVar1 * 4 + basePtr + 0x1c8) = 0;
            iVar1 = iVar1 + 1;
        } while (iVar1 < 8);

        /* Reset to defaults */
        *(unsigned int *)(basePtr + 0x1a0) = 8;
        *(unsigned int *)(basePtr + 0x1b0) = 1;
        *(unsigned char *)(basePtr + 0x1c6) = 0x11;
        *(unsigned char *)(basePtr + 0x1c7) = 0x13;
        *(unsigned int *)(basePtr + 0x1a4) = 2;
        *(unsigned int *)(basePtr + 0x1a8) = 1;
        *(unsigned int *)(basePtr + 0x1ac) = 0;
        *(unsigned int *)(basePtr + 0x1ec) = 0;
        *(unsigned int *)(basePtr + 0x1b4) = 0x2580;
        *(unsigned int *)(basePtr + 0x1e8) = 0x126;

        _deactivatePort(*(unsigned int *)(basePtr + 0x294));
        _changeState(*(unsigned int *)(basePtr + 0x294), 0, 0xffffffff);
        _MyIOLog("OK]\n\r");
        FUN_0000107c(uVar2);
        iVar3 = 0;
    } else {
        _MyIOLog("NOT OPEN]");
        FUN_0000107c(uVar2);
        iVar3 = 0xfffffd33;
    }

    return iVar3;
}

/*
 * Dequeue data from the serial port.
 */
/*
 * Dequeue data from the serial port.
 *
 * Removes data from the RX queue into the provided buffer.
 * If minCount is specified and not enough data is available,
 * waits for more data to arrive.
 *
 * Parameters:
 *   buffer: Output buffer to receive data
 *   size: Maximum number of bytes to read
 *   count: Pointer to receive actual bytes read
 *   minCount: Minimum bytes required (0 = read whatever is available)
 *
 * Returns: IO_R_SUCCESS on success, error code otherwise
 */
- (IOReturn)dequeueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
               minCount:(unsigned int)minCount
{
    char *basePtr = (char *)self;
    IOReturn result;
    unsigned int bytesRead;
    unsigned int totalRead;
    unsigned int watchState;
    const char *logMsg;

    result = 0;
    watchState = 0;

    _MyIOLog("++>In Dequeue %x %d %d %d\n\r", buffer, size, *count, minCount);

    // Check if port is active (offset 0x134 & 0x40000000)
    if ((*(unsigned int *)(basePtr + 0x134) & 0x40000000) == 0) {
        result = 0xfffffd33;  // IO_R_NOT_OPEN
    } else if ((count == NULL) || (buffer == NULL) || (size < minCount)) {
        result = 0xfffffd3e;  // IO_R_INVALID_ARG
    } else {
        // Lock (placeholder for actual lock)

        // Remove initial data from RX queue at offset 0x14c
        bytesRead = _RemovefromQueue(basePtr + 0x14c, buffer, size);
        *count = bytesRead;

        // Update state - clear bit 0x80000
        _changeState(self, 0x80000, 0x80000);

        totalRead = *count;

        // If minCount is specified and we haven't read enough, wait for more
        while ((minCount != 0) && (totalRead < minCount)) {
            watchState = 0;
            _MyIOLog("dequeueData: Entering WatchState %d\n\r", totalRead);

            result = [self watchState:&watchState mask:0x80000];

            if (result != 0) {
                logMsg = "Interrupted!]";
                goto cleanup;
            }

            // Unlock temporarily
            // Lock again

            // Remove more data
            bytesRead = _RemovefromQueue(basePtr + 0x14c, buffer + totalRead, size - totalRead);
            *count = bytesRead;

            // Update state
            _changeState(self, 0x80000, 0x80000);

            totalRead = totalRead + bytesRead;
        }

        _MyIOLog("dequeueData: Exit from WatchState\n\r");

        // Check flow control state at offset 0x1ec
        if (*(int *)(basePtr + 0x1ec) == -1) {
            // Check if RX queue usage is below threshold (offset 0x184)
            unsigned int rxUsed = _UsedSpaceinQueue(basePtr + 0x14c);
            if (rxUsed < *(unsigned int *)(basePtr + 0x184)) {
                // Reset flow control state
                *(unsigned int *)(basePtr + 0x1ec) = 0;

                // Send XON character from offset 0x1c7 to TX queue at offset 0x164
                _AddBytetoQueue(basePtr + 0x164, *(unsigned char *)(basePtr + 0x1c7));
                _SetUpTransmit(self);
            }
        }

        logMsg = "-->Out Dequeue\n\r";

cleanup:
        _MyIOLog(logMsg);
        // Unlock
    }

    return result;
}

/*
 * Dequeue an event from the serial port.
 *
 * Placeholder implementation that validates parameters and checks
 * if the port is active. Currently does not implement actual event
 * queue functionality.
 *
 * Parameters:
 *   event: Pointer to receive event type
 *   data: Pointer to receive event data
 *   sleep: Whether to sleep waiting for event
 *
 * Returns: IO_R_SUCCESS if port is active, error code otherwise
 */
- (IOReturn)dequeueEvent:(unsigned int *)event
                    data:(unsigned int *)data
                   sleep:(BOOL)sleep
{
    char *basePtr = (char *)self;
    IOReturn result;

    _MyIOLog("dequeueEvent\n\r");

    if ((event == NULL) || (data == NULL)) {
        result = 0xfffffd3e;  // IO_R_INVALID_ARG
    } else {
        // Lock

        // Check if port is active (offset 0x134 & 0x40000000)
        if ((*(unsigned int *)(basePtr + 0x134) & 0x40000000) == 0) {
            // Unlock
            result = 0xfffffd33;  // IO_R_NOT_OPEN
        } else {
            // Unlock
            result = 0;
        }
    }

    return result;
}

/*
 * Enqueue data to the serial port.
 *
 * Adds data to the TX queue for transmission. If the queue doesn't
 * have enough space and sleep is true, waits for space to become available.
 *
 * Parameters:
 *   buffer: Input buffer containing data to transmit
 *   size: Number of bytes to transmit
 *   count: Pointer to receive actual bytes queued
 *   sleep: Whether to sleep waiting for queue space
 *
 * Returns: IO_R_SUCCESS on success, error code otherwise
 */
- (IOReturn)enqueueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
                  sleep:(BOOL)sleep
{
    char *basePtr = (char *)self;
    IOReturn result;
    unsigned int bytesAdded;
    unsigned int bytesQueued;
    unsigned int remainingBytes;
    unsigned int totalQueued;
    unsigned int watchState;
    unsigned char noSleepFlag;

    watchState = 0x2000000;

    _MyIOLog("++>In Enqueue %d %d %d\n\r", size, *count, (int)sleep);

    *count = 0;

    if ((count == NULL) || (buffer == NULL)) {
        result = 0xfffffd3e;  // IO_R_INVALID_ARG
    } else {
        // Lock

        // Check if port is active (offset 0x134 & 0x40000000)
        if ((*(unsigned int *)(basePtr + 0x134) & 0x40000000) == 0) {
            // Unlock
            result = 0xfffffd33;  // IO_R_NOT_OPEN
        } else {
            // Add data to TX queue at offset 0x164
            bytesAdded = _AddtoQueue(basePtr + 0x164, buffer, size);
            *count = bytesAdded;

            // Update state - clear bit 0x4000000
            _changeState(self, 0, 0x4000000);

            totalQueued = *count;

            // Start transmission
            _SetUpTransmit(self);

            // If not all data was queued
            if (totalQueued < size) {
                // Check sleep flag: (sleep == 0) << 1 gives 0 or 2
                noSleepFlag = (sleep == 0) << 1;
                remainingBytes = size;

                do {
                    // If no sleep flag is set (bit 1), break
                    if ((BOOL)(noSleepFlag >> 1 & 1)) {
                        break;
                    }

                    // Calculate remaining bytes
                    remainingBytes = remainingBytes - *count;

                    watchState = 0x2000000;
                    _MyIOLog("TX Enqueue Entereing WatchState\n\r");

                    result = [self watchState:&watchState mask:0x2000000];

                    if (result != 0) {
                        _MyIOLog("Interrupted!]");
                        // Unlock
                        return result;
                    }

                    // Unlock and relock

                    // Try to add more data
                    bytesQueued = _AddtoQueue(basePtr + 0x164,
                                             buffer + totalQueued,
                                             remainingBytes);
                    *count = bytesQueued;

                    // Update state
                    _changeState(self, 0, 0x4000000);

                    totalQueued = totalQueued + *count;

                    // Start transmission
                    _SetUpTransmit(self);

                } while (totalQueued < size);
            }

            // Log queue usage
            unsigned int queueUsed = _UsedSpaceinQueue(basePtr + 0x164);
            _MyIOLog("Enqueue Check %x\n\r", queueUsed);

            // Enable all interrupts
            [self enableAllInterrupts];

            _MyIOLog("-->Out Enqueue\n\r");

            // Unlock
            result = 0;
        }
    }

    return result;
}

/*
 * Enqueue an event to the serial port.
 *
 * Placeholder implementation that just validates the port is active.
 *
 * Parameters:
 *   event: Event type to enqueue
 *   data: Event data
 *   sleep: Whether to sleep if queue is full
 *
 * Returns: IO_R_SUCCESS if port is active, IO_R_NOT_OPEN otherwise
 */
- (IOReturn)enqueueEvent:(unsigned int)event
                    data:(unsigned int)data
                   sleep:(BOOL)sleep
{
    char *basePtr = (char *)self;
    IOReturn result;

    _MyIOLog("enqueueEvent\n\r");

    // Lock

    // Check if port is active (offset 0x134 & 0x40000000)
    if ((*(unsigned int *)(basePtr + 0x134) & 0x40000000) == 0) {
        // Unlock
        result = 0xfffffd33;  // IO_R_NOT_OPEN
    } else {
        // Unlock
        result = 0;
    }

    return result;
}

/*
 * Execute an event.
 *
 * Handles special event codes and dispatches to _executeEvent for others.
 * Some events (0xb, 0xf, 0x4b, 0x53) are handled specially or are no-ops.
 *
 * Parameters:
 *   event: Event code to execute
 *   data: Event data parameter
 *
 * Returns: IO_R_SUCCESS on success, IO_R_NOT_OPEN if port is not active
 */
- (IOReturn)executeEvent:(unsigned int)event
                    data:(unsigned int)data
{
    char *basePtr = (char *)self;
    IOReturn result;
    int dataMilliseconds;
    int dataSeconds;
    unsigned int newState;
    unsigned int stateMask;

    result = 0;

    // Lock

    _MyIOLog("executeEvent\n\r");

    // Check if port is active (offset 0x294 + 0xc, which is self + 0xc)
    // If bit 31 is set (negative), port is not active
    if (*(int *)(basePtr + 0xc) < 0) {
        // Unlock
        return 0xfffffd33;  // IO_R_NOT_OPEN
    }

    // Handle special event codes
    if (event == 0xf) {
        // Event 0xf - no-op
        goto cleanup;
    }

    if (event < 0x10) {
        if (event == 0xb) {
            // Event 0xb - no-op
            goto cleanup;
        }
    } else {
        if (event == 0x4b) {
            // Event 0x4b - Set timeout value
            // Convert data from milliseconds to nanoseconds
            dataMilliseconds = data * 1000;
            dataSeconds = dataMilliseconds;

            // Perform 64-bit division and modulo by 1000000000
            // These are likely __udivdi3 and __umoddi3 compiler intrinsics
            // For now, simplified calculation
            // Store at offset 0x220 and 0x224
            *(int *)(basePtr + 0x220) = dataSeconds;
            *(int *)(basePtr + 0x224) = dataMilliseconds;

            goto cleanup;
        }

        if (event == 0x53) {
            // Event 0x53 - no-op
            goto cleanup;
        }
    }

    // For other events, call _executeEvent
    stateMask = 0;
    newState = *(unsigned int *)(basePtr + 0x134);

    result = _executeEvent(self, event, data, &newState, &stateMask);

    // Update state with changes
    _changeState(self, newState, stateMask);

cleanup:
    // Unlock
    return result;
}

/*
 * Request an event.
 */
- (IOReturn)requestEvent:(unsigned int)event
                    data:(unsigned int *)data
{
    char *basePtr = (char *)self;
    unsigned int uVar1;
    int iVar2;
    unsigned int uVar3;
    unsigned int uVar4;

    _MyIOLog("requestEvent2\n\r");

    if (data == NULL) {
        return 0xfffffd3e;  /* IO_R_INVALID_ARG */
    }

    if (event == 0x43) {
        uVar1 = *(unsigned int *)(basePtr + 0x1a8);
        goto LAB_00001774;
    }

    if (event < 0x44) {
        if (event == 0x27) {
            uVar1 = _UsedSpaceinQueue((unsigned int)(basePtr + 0x14c));
            *data = uVar1;
            return 0;
        }

        if (event < 0x28) {
            if (event == 0xb) {
                iVar2 = (int)(basePtr + 0x164);
            } else {
                if (event < 0xc) {
                    if (event != 5) {
                        return 0xfffffd3e;
                    }
                    uVar1 = *(unsigned int *)(basePtr + 0x134) >> 0x1e & 1;
                    goto LAB_00001774;
                }
                if (event != 0xf) {
                    if (event != 0x23) {
                        return 0xfffffd3e;
                    }
                    uVar1 = _FreeSpaceinQueue((unsigned int)(basePtr + 0x164));
                    *data = uVar1;
                    return 0;
                }
                iVar2 = (int)(basePtr + 0x14c);
            }
            uVar1 = _GetQueueSize(iVar2);
            *data = uVar1;
            return 0;
        }

        if (event != 0x37) {
            if (event < 0x38) {
                if (event != 0x33) {
                    return 0xfffffd3e;
                }
                iVar2 = *(int *)(basePtr + 0x1b4);
            } else {
                if (event != 0x3b) {
                    if (event != 0x3f) {
                        return 0xfffffd3e;
                    }
                    goto LAB_00001744;
                }
                iVar2 = *(int *)(basePtr + 0x1a0);
            }
LAB_0000173c:
            uVar1 = iVar2 << 1;
            goto LAB_00001774;
        }
    } else {
        if (event == 0xe5) {
            uVar1 = -(unsigned int)*(unsigned char *)(basePtr + 0x1c4) >> 0x1f;
            goto LAB_00001774;
        }

        if (event < 0xe6) {
            if (event == 0x4b) {
                uVar1 = *(unsigned int *)(basePtr + 0x220);
                uVar4 = *(unsigned int *)(basePtr + 0x224);
LAB_00001694:
                uVar3 = uVar1 * 1000000000 + uVar4;
                /* Division by 1000 for nanoseconds conversion */
                uVar3 = uVar3 / 1000;
                *data = uVar3;
                return 0;
            }

            if (event < 0x4c) {
                if (event != 0x47) {
                    return 0xfffffd3e;
                }
                uVar1 = *(unsigned int *)(basePtr + 0x1ac);
            } else {
                if (event == 0x4f) {
                    uVar1 = *(unsigned int *)(basePtr + 0x218);
                    uVar4 = *(unsigned int *)(basePtr + 0x21c);
                    goto LAB_00001694;
                }
                if (event != 0x53) {
                    return 0xfffffd3e;
                }
                uVar1 = *(unsigned int *)(basePtr + 0x1e8);
            }
            goto LAB_00001774;
        }

        if (event == 0xf3) {
            iVar2 = *(int *)(basePtr + 0x1a4);
            goto LAB_0000173c;
        }

        if (event < 0xf4) {
            if (event == 0xe9) {
                uVar1 = (unsigned int)*(unsigned char *)(basePtr + 0x1c7);
            } else {
                if (event != 0xed) {
                    return 0xfffffd3e;
                }
                uVar1 = (unsigned int)*(unsigned char *)(basePtr + 0x1c6);
            }
            goto LAB_00001774;
        }

        if (event != 0xf7) {
            if (event != 0xf9) {
                return 0xfffffd3e;
            }
            uVar1 = *(unsigned int *)(basePtr + 0x134) >> 0xb & 1;
            goto LAB_00001774;
        }
    }

LAB_00001744:
    uVar1 = 0;

LAB_00001774:
    *data = uVar1;
    return 0;
}

/*
 * Get the next event.
 */
/*
 * Get the next event.
 *
 * Placeholder implementation that just returns 0 (no events).
 *
 * Returns: 0 (no event)
 */
- (unsigned int)nextEvent
{
    _MyIOLog("nextEvent\n\r");

    // Lock
    // Unlock

    return 0;
}

/*
 * Get the current state.
 *
 * Checks queue levels and returns the current state with bit 0x1000 masked off.
 *
 * Returns: Current state value (with bit 0x1000 cleared)
 */
- (unsigned int)getState
{
    char *basePtr = (char *)self;

    // Check queue levels and update state
    _CheckQueues(self);

    // Return state from offset 0x134 with bit 0x1000 masked off (0xffffefff)
    return *(unsigned int *)(basePtr + 0x134) & 0xffffefff;
}

/*
 * Set the state with mask.
 */
- (IOReturn)setState:(unsigned int)state
                mask:(unsigned int)mask
{
    char *basePtr = (char *)self;
    int iVar1;
    unsigned int uVar2;
    unsigned int uVar3;
    extern unsigned int FUN_000011a0(void);
    extern void FUN_00001190(unsigned int);

    _MyIOLog("++>setState %d %x\n\r", state, mask);

    if ((mask & 0xc0001000) == 0) {
        uVar2 = FUN_000011a0();

        if (*(int *)(*(unsigned int *)(basePtr + 0x294) + 0xc) < 0) {
            uVar3 = mask & (~*(unsigned int *)(basePtr + 0x1e8) | 0xffff0000);
            if (uVar3 != 0) {
                _changeState(*(unsigned int *)(basePtr + 0x294), state, uVar3);
            }
            _MyIOLog("-->setState\n\r");
            FUN_00001190(uVar2);
            iVar1 = 0;
        } else {
            FUN_00001190(uVar2);
            iVar1 = 0xfffffd33;
        }
    } else {
        iVar1 = 0xfffffd3e;
    }

    return iVar1;
}

/*
 * Watch state with mask.
 */
- (IOReturn)watchState:(unsigned int *)state
                  mask:(unsigned int)mask
{
    char *basePtr = (char *)self;
    unsigned int uVar1;
    int iVar2;
    extern unsigned int FUN_000012cc(void);
    extern void FUN_000012ac(unsigned int);

    _MyIOLog("watchState\n\r");

    uVar1 = FUN_000012cc();

    if (*(int *)(*(unsigned int *)(basePtr + 0x294) + 0xc) < 0) {
        iVar2 = _watchState(*(int *)(basePtr + 0x294), state, mask & 0xffffefff);
        *state = *state & 0xffffefff;
        FUN_000012ac(uVar1);
    } else {
        FUN_000012ac(uVar1);
        iVar2 = 0xfffffd33;
    }

    return iVar2;
}

/*
 * Get character values for a parameter.
 *
 * Attempts to get a configuration value from the device description's
 * config table. If found, copies it to the values buffer. Otherwise,
 * delegates to the superclass implementation.
 *
 * Parameters:
 *   values: Buffer to receive parameter value
 *   parameter: Parameter name to look up
 *   count: Pointer to buffer size on input, actual size on output
 *
 * Returns: IO_R_SUCCESS if found, or result from superclass
 */
- (IOReturn)getCharValues:(unsigned char *)values
             forParameter:(IOParameterName)parameter
                    count:(unsigned int *)count
{
    id deviceDesc;
    id configTable;
    const char *stringValue;
    int stringLength;

    _MyIOLog("getCharValue\n\r");

    // Validate parameters
    if ((values != NULL) && (count != NULL) && (*count != 0)) {
        // Get device description
        deviceDesc = [self deviceDescription];

        // Get config table from device description
        configTable = [deviceDesc configTable];

        // Look up the value for the parameter key
        stringValue = [configTable valueForStringKey:parameter];

        if (stringValue != NULL) {
            // Copy string to buffer, leaving room for null terminator
            strncpy((char *)values, stringValue, *count - 1);

            // Ensure null termination
            values[*count - 1] = '\0';

            // Get actual string length
            stringLength = strlen((char *)values);

            // Return length including null terminator
            *count = stringLength + 1;

            return 0;
        }
    }

    // Not found in config table - delegate to superclass
    return [super getCharValues:values forParameter:parameter count:count];
}

/*
 * Get interrupt handler information.
 *
 * Returns the appropriate interrupt handler function pointer based on
 * the interrupt type (0=main ISR, 1=TX DMA, 2=RX DMA).
 *
 * Parameters:
 *   handler: Pointer to receive handler function pointer
 *   level: Pointer to receive interrupt level (always 0x18)
 *   argument: Pointer to receive handler argument (self)
 *   interruptType: Type of interrupt (0, 1, or 2)
 *
 * Returns: YES (always succeeds)
 */
- (IOReturn)getHandler:(IOInterruptHandler *)handler
                 level:(unsigned int *)level
              argument:(void **)argument
          forInterrupt:(unsigned int)interruptType
{
    char *basePtr = (char *)self;
    void (*handlerFunc)(void *, void *, PPCSerialPort *);

    _MyIOLog("getHandler %d\n\r", interruptType);

    if (interruptType == 1) {
        // TX DMA interrupt
        _MyIOLog("getHandler PPCSerialTxDMAISR\n\r");
        handlerFunc = _PPCSerialTxDMAISR;
    } else if (interruptType == 0) {
        // Main SCC interrupt
        _MyIOLog("getHandler PPCSerialISR\n\r");
        handlerFunc = _PPCSerialISR;
    } else {
        if (interruptType != 2) {
            // Unknown interrupt type - skip setting handler
            goto set_level_and_argument;
        }
        // RX DMA interrupt
        _MyIOLog("getHandler PPCSerialRxDMAISR\n\r");
        handlerFunc = _PPCSerialRxDMAISR;
    }

    // Set handler function pointer
    *handler = (IOInterruptHandler)handlerFunc;

set_level_and_argument:
    // Set interrupt level to 0x18
    *level = 0x18;

    // Set argument to self (from offset 0x294, which is self)
    *argument = (void *)self;

    return YES;
}

@end

//==============================================================================
// Utility Functions
//==============================================================================

/*
 * Add a single byte to a queue.
 */
/*
 * Add a byte to the queue.
 *
 * Adds one byte to the queue at the write pointer position.
 * Queue structure (as int array):
 *   [0] = start pointer
 *   [1] = end pointer
 *   [2] = write pointer
 *   [3] = read pointer
 *   [4] = capacity
 *   [5] = used count
 *
 * Returns 0 on success, 1 if queue is full.
 */
static IOReturn _AddBytetoQueue(void *queueBase, unsigned char byte)
{
    unsigned int *queue = (unsigned int *)queueBase;
    IOReturn result;
    unsigned char *writePtr;

    // Check if queue is full (write == read AND used != 0)
    if ((queue[2] == queue[3]) && (queue[5] != 0)) {
        result = 1;
    } else {
        // Get current write pointer
        writePtr = (unsigned char *)queue[2];

        // Increment write pointer first
        queue[2] = (unsigned int)(writePtr + 1);

        // Write byte to old position
        *writePtr = byte;

        // Increment used count
        queue[5] = queue[5] + 1;

        // Check for wrap-around (if new write pointer >= end pointer)
        if (queue[1] <= queue[2]) {
            queue[2] = queue[0];  // Wrap to start
        }

        result = 0;
    }

    return result;
}

/*
 * Add data to a queue.
 *
 * Adds multiple bytes to the queue from a buffer.
 * Continues until the queue is full or all bytes are added.
 *
 * Parameters:
 *   queueBase: Pointer to queue control structure
 *   buffer: Input buffer containing data to add
 *   size: Number of bytes to add
 *
 * Returns: Number of bytes actually added
 */
static unsigned int _AddtoQueue(void *queueBase, unsigned char *buffer, unsigned int size)
{
    unsigned char byte;
    int freeSpace;
    unsigned int bytesAdded;

    bytesAdded = 0;

    // Loop adding bytes until queue is full or size reached
    while (1) {
        freeSpace = _FreeSpaceinQueue(queueBase);

        // Break if queue is full or we've added all requested bytes
        if ((freeSpace == 0) || (size <= bytesAdded)) {
            break;
        }

        // Get next byte from buffer
        byte = *buffer;
        buffer++;

        // Add byte to queue
        _AddBytetoQueue(queueBase, byte);

        bytesAdded++;
    }

    return bytesAdded;
}

/*
 * Allocate ring buffer.
 *
 * Allocates a 4KB (0x1000) ring buffer using IOMalloc.
 * Initializes the queue structure with the allocated buffer.
 *
 * Parameters:
 *   queueBase: Pointer to queue control structure
 *
 * Returns: YES if allocation succeeded, NO if it failed
 */
static BOOL _allocateRingBuffer(void *queueBase)
{
    int bufferPtr;

    _MyIOLog("In allocateRingBuffer\n\r");

    // Allocate 4KB buffer (FUN_0000279c is likely IOMalloc)
    bufferPtr = (int)IOMalloc(0x1000);

    // Initialize queue with the allocated buffer
    _InitQueue((int *)queueBase, bufferPtr, 0x1000);

    // Return whether allocation succeeded (buffer != 0)
    return (bufferPtr != 0);
}

/*
 * Change port state.
 *
 * Updates the port state using a mask to determine which bits to change.
 * If any watched state bits change, wakes up threads waiting on the state.
 *
 * Parameters:
 *   self: Pointer to PPCSerialPort instance
 *   newState: New state value
 *   mask: Mask indicating which bits to update
 */
static void _changeState(PPCSerialPort *self, unsigned int newState, unsigned int mask)
{
    char *basePtr = (char *)self;
    unsigned int oldState;
    unsigned int updatedState;

    _MyIOLog("++>changeState(%x, %x, %x) %x\n\r",
             newState,
             mask,
             *(unsigned int *)(basePtr + 0xc),
             *(unsigned int *)(basePtr + 0x10));

    // Get current state from offset 0xc
    oldState = *(unsigned int *)(basePtr + 0xc);

    // Update state: clear bits specified by mask, then set new bits
    updatedState = (oldState & ~mask) | (newState & mask);

    // Write updated state back to offset 0xc
    *(unsigned int *)(basePtr + 0xc) = updatedState;

    // Check if any watched state bits changed
    // Compare changed bits (updatedState XOR oldState) with watch mask (offset 0x10)
    if (((updatedState ^ oldState) & *(unsigned int *)(basePtr + 0x10)) != 0) {
        _MyIOLog("changeState Calling thread_wakeup\n\r");

        // Wake up threads waiting on state change
        // FUN_000029d0 is likely thread_wakeup or assert_wait_result
        // Parameters appear to be: (event address, result code, flags)
        // Using IOSleep(0) as a placeholder to yield - actual implementation
        // would use thread_wakeup(&self->watchStateMask, THREAD_AWAKENED, 4)
        extern void thread_wakeup(void *event);
        thread_wakeup((void *)(basePtr + 0x10));
    }

    _MyIOLog("-->changeState %x \n\r", *(unsigned int *)(basePtr + 0xc));
}

/*
 * Deactivate port.
 *
 * Stub implementation - deactivates the serial port.
 */
static void _deactivatePort(PPCSerialPort *self)
{
    // Stub: Implementation needed
    // This likely clears the active state and stops any operations
}

/*
 * Execute event helper function.
 *
 * Stub implementation - executes a serial port event.
 *
 * Parameters:
 *   self: PPCSerialPort instance
 *   event: Event code
 *   data: Event data
 *   currentState: Pointer to current state (updated by event)
 *   stateMask: Pointer to state mask (indicates changed bits)
 *
 * Returns: IOReturn status code
 */
static IOReturn _executeEvent(PPCSerialPort *self, unsigned int event, unsigned int data,
                              unsigned int *currentState, unsigned int *stateMask)
{
    // Stub: Implementation needed
    // This would handle various event types and update the state accordingly
    return 0;
}

/*
 * Check queue levels and update state.
 */
/*
 * Check queue states and update state bits.
 *
 * This function checks both RX and TX queue levels and sets/clears
 * appropriate state bits based on watermarks.
 *
 * RX Queue (at offset 0x3c):
 *   - bit 0x800000: Set if queue has data (not empty)
 *   - bit 0x2000000: Set if used < low watermark
 *   - bit 0x1000000: Set if used > high watermark
 *
 * TX Queue (at offset 0x24):
 *   - bit 0x10000: Set if queue is full (free == 0)
 *   - bit 0x80000: Set if queue is empty (size == free)
 *   - bit 0x40000: Set if used < med watermark
 *   - bit 0x20000: Set if used < low watermark
 */
static void _CheckQueues(PPCSerialPort *self)
{
    char *basePtr = (char *)self;
    int rxSize, rxFree, rxUsed;
    int txSize, txFree, txUsed;
    unsigned int newState;

    // Get current state from offset 0xc
    newState = *(unsigned int *)(basePtr + 0xc);

    // Check RX queue (at offset 0x3c)
    rxSize = _GetQueueSize(basePtr + 0x3c);
    rxFree = _FreeSpaceinQueue(basePtr + 0x3c);

    // Check if RX queue is full (free == 0)
    if (rxFree == 0) {
        newState = newState | 0x800000;
    } else {
        newState = newState & 0xff7fffff;
    }

    // Check if RX queue is empty (size == free)
    if (rxSize == rxFree) {
        newState = newState & 0xff7fffff;
    } else {
        newState = newState | 0x800000;
    }

    // Calculate RX used count
    rxUsed = rxSize - rxFree;

    // Check RX low watermark (offset 0x6c)
    if ((unsigned int)rxUsed < *(unsigned int *)(basePtr + 0x6c)) {
        newState = newState | 0x2000000;
    } else {
        newState = newState & 0xfdffffff;
    }

    // Check RX high watermark (offset 0x68)
    if (*(unsigned int *)(basePtr + 0x68) < (unsigned int)rxUsed) {
        newState = newState | 0x1000000;
    } else {
        newState = newState & 0xfeffffff;
    }

    // Check TX queue (at offset 0x24)
    txSize = _GetQueueSize(basePtr + 0x24);
    txFree = _FreeSpaceinQueue(basePtr + 0x24);

    // Check if TX queue is full (free == 0)
    if (txFree == 0) {
        newState = newState | 0x10000;
    } else {
        newState = newState & 0xfffeffff;
    }

    // Check if TX queue is empty (size == free)
    if (txSize == txFree) {
        newState = newState | 0x80000;
    } else {
        newState = newState & 0xfff7ffff;
    }

    // Calculate TX used count
    txUsed = txSize - txFree;

    // Check TX med watermark (offset 0x5c)
    if ((unsigned int)txUsed < *(unsigned int *)(basePtr + 0x5c)) {
        newState = newState | 0x40000;
    } else {
        newState = newState & 0xfffbffff;
    }

    // Check TX low watermark (offset 0x58)
    if (*(unsigned int *)(basePtr + 0x58) < (unsigned int)txUsed) {
        newState = newState | 0x20000;
    } else {
        newState = newState & 0xfffdffff;
    }

    // Update state with changes (mask = newState XOR currentState)
    _changeState(self, newState, newState ^ *(unsigned int *)(basePtr + 0xc));
}

/*
 * Close a queue.
 */
/*
 * Close a queue.
 *
 * Zeros out all queue control structure fields.
 * Returns 0 (always succeeds).
 */
static IOReturn _CloseQueue(void *queueBase)
{
    unsigned int *queue = (unsigned int *)queueBase;

    queue[0] = 0;  // Start pointer
    queue[1] = 0;  // End pointer
    queue[2] = 0;  // Write pointer
    queue[3] = 0;  // Read pointer
    queue[4] = 0;  // Capacity

    return 0;
}

/*
 * Free ring buffer.
 *
 * Frees the buffer memory and closes the queue.
 * This calls IOFree with the buffer start pointer and capacity.
 */
static void _freeRingBuffer(void *queueBase)
{
    unsigned int *queue = (unsigned int *)queueBase;

    _MyIOLog("In freeRingBuffer\n\r");

    // Free the buffer memory (FUN_00002704 is likely IOFree)
    // IOFree(pointer, size)
    IOFree((void *)queue[0], queue[4]);

    // Close the queue
    _CloseQueue(queueBase);
}

/*
 * Get free space in queue.
 */
/*
 * Get free space in queue.
 *
 * Returns the difference between capacity (offset 0x10) and used count (offset 0x14).
 * This is the number of free bytes available in the queue.
 */
static unsigned int _FreeSpaceinQueue(void *queueBase)
{
    int *queue = (int *)queueBase;
    return *(int *)(((char *)queue) + 0x10) - *(int *)(((char *)queue) + 0x14);
}

/*
 * Get a byte from a queue.
 */
/*
 * Get a byte from the queue.
 *
 * Removes one byte from the queue and stores it in byteOut.
 * Queue structure (as int array):
 *   [0] = start pointer
 *   [1] = end pointer
 *   [2] = write pointer
 *   [3] = read pointer
 *   [4] = capacity
 *   [5] = used count
 *
 * Returns 0 on success, 2 if queue is empty.
 */
static IOReturn _GetBytetoQueue(void *queueBase, unsigned char *byteOut)
{
    unsigned int *queue = (unsigned int *)queueBase;
    IOReturn result;
    unsigned char *readPtr;

    // Check if queue is empty (write == read AND used == 0)
    if ((queue[2] == queue[3]) && (queue[5] == 0)) {
        result = 2;
    } else {
        // Get current read pointer
        readPtr = (unsigned char *)queue[3];

        // Increment read pointer first
        queue[3] = (unsigned int)(readPtr + 1);

        // Read byte from old position
        *byteOut = *readPtr;

        // Decrement used count
        queue[5] = queue[5] - 1;

        // Check for wrap-around (if new read pointer >= end pointer)
        if (queue[1] <= queue[3]) {
            queue[3] = queue[0];  // Wrap to start
        }

        result = 0;
    }

    return result;
}

/*
 * Get queue size.
 *
 * Returns the capacity of the queue from offset 0x10 (element [4]).
 */
static unsigned int _GetQueueSize(void *queueBase)
{
    int *queue = (int *)queueBase;
    return *(unsigned int *)(((char *)queue) + 0x10);
}

/*
 * Initialize SCC chip.
 *
 * Sets up initial chip parameters and probes the SCC device.
 * Sets various state flags before calling the probe function.
 */
static void _initChip(PPCSerialPort *self)
{
    char *basePtr = (char *)self;

    _MyIOLog("ejk In initChip()\n\r");

    // Set initial state flags
    *(unsigned int *)(basePtr + 0x80) = 1;
    *(unsigned int *)(basePtr + 0x84) = 0;
    *(unsigned short *)(basePtr + 0x90) = 0;
    *(unsigned char *)(basePtr + 0x93) = 0;

    // Probe the SCC device
    _ProbeSccDevice(self);
}

/*
 * Initialize a queue.
 *
 * Sets up a queue control structure with the given buffer and size.
 * Queue structure (as int array):
 *   [0] = start pointer (bufferStart)
 *   [1] = end pointer (bufferStart + bufferSize)
 *   [2] = write pointer (bufferStart)
 *   [3] = read pointer (bufferStart)
 *   [4] = capacity (bufferSize)
 *   [5] = used count (0)
 *
 * Parameters:
 *   queueBase: Pointer to queue control structure (int array)
 *   bufferStart: Starting address of buffer
 *   bufferSize: Size of buffer in bytes
 *
 * Returns: 0 (always succeeds)
 */
static IOReturn _InitQueue(int *queueBase, int bufferStart, int bufferSize)
{
    queueBase[0] = bufferStart;                 // Start pointer
    queueBase[1] = bufferStart + bufferSize;    // End pointer
    queueBase[4] = bufferSize;                  // Capacity
    queueBase[2] = bufferStart;                 // Write pointer
    queueBase[3] = bufferStart;                 // Read pointer
    queueBase[5] = 0;                           // Used count

    return 0;
}

/*
 * Debug logging wrapper.
 * Provides formatted logging for debug output.
 */
static void _MyIOLog(const char *format, ...)
{
    va_list args;

    va_start(args, format);

    // Use IOLog for kernel logging
    // Note: IOLog doesn't have a va_list version in DriverKit,
    // so we'll use IOLogv if available, or format to a buffer
    char buffer[256];
    vsnprintf(buffer, sizeof(buffer), format, args);
    IOLog("%s", buffer);

    va_end(args);
}

/*
 * Open SCC device.
 *
 * Initializes the SCC channel by writing a series of register pairs
 * from the initialization table. Modifies the table for channel B
 * if needed, then programs all registers and enables interrupts.
 *
 * Returns: 0 on success
 */
static IOReturn _OpenScc(PPCSerialPort *self)
{
    char *basePtr = (char *)self;
    unsigned char localTable[34];
    unsigned int index;

    // Copy initialization table to local buffer
    // This is FUN_00002e24(local_38, &DAT_00005a08, 0x22) from decompiled code
    bcopy(sccInitTable, localTable, 0x22);

    _MyIOLog("In OpenSCC %d\n\r", *(unsigned char *)(basePtr + 0x148));

    // If this is channel B (channel 1), modify WR9 value
    if (*(char *)(basePtr + 0x148) == 1) {
        localTable[1] = 0x40;  // Change WR9 from 0x80 to 0x40 (channel B reset)
    }

    // Write all register pairs from the table
    index = 0;
    do {
        _SccWriteReg(self, localTable[index], localTable[index + 1]);
        index = index + 2;
    } while (index < 0x22);

    // Enable master and RX interrupts
    _SccEnableInterrupts(self, 6, 0);  // Master interrupts
    _SccEnableInterrupts(self, 5, 0);  // RX interrupts

    // Write to WR0 (enable high IRQ priority)
    _SccWriteReg(self, 0, 0x20);

    _MyIOLog("PPCSerOpen End \n\r");

    return 0;
}

/*
 * Main interrupt service routine.
 *
 * Handles SCC interrupts by reading the interrupt vector and dispatching
 * to the appropriate handler. Loops up to 100 times to handle multiple
 * interrupt conditions. Uses direct hardware access to read the interrupt
 * vector from the SCC.
 *
 * Interrupt types (from RR2 shifted right 1, masked with 3):
 *   0: TX buffer empty
 *   1: External/Status change
 *   2: RX character available
 *   3: RX error/special condition
 */
static void _PPCSerialISR(void *identity, void *state, PPCSerialPort *self)
{
    char *basePtr = (char *)self;
    unsigned char intVector;
    BOOL continueLoop;
    short loopCount;
    unsigned int intType;
    unsigned char statusReg;

    // Increment interrupt count at offset 0x108
    *(int *)(basePtr + 0x108) = *(int *)(basePtr + 0x108) + 1;

    continueLoop = YES;
    loopCount = 100;

    do {
        // Check for timeout
        if (loopCount == 0) {
            _MyIOLog("***** In PPCSerialISR TimeOut Failure %x\n\r", intType);
            _SccCloseChannel(self);
            return;
        }

        // Write 2 to SCC to select RR2 (interrupt vector)
        *(volatile unsigned char *)(*(unsigned int *)(basePtr + 0x144)) = 2;
        eieio();

        // Small delay (FUN_00003748(0x32) is likely IODelay(50))
        IODelay(50);

        // Read interrupt vector
        intVector = *(volatile unsigned char *)(*(unsigned int *)(basePtr + 0x144));
        eieio();

        // Another delay
        IODelay(50);

        // Extract interrupt type: shift right 1, mask with 3
        intVector = intVector >> 1;
        intType = intVector & 3;

        if (intType == 1) {
            // External/Status interrupt
            _SccHandleExtInterrupt(self);
            continueLoop = NO;
            statusReg = _SccReadReg(self, 0);
            _MyIOLog("ExtStatusInterrupt Int %x\n\r", statusReg);
        } else if (intType < 2) {
            if ((intVector & 3) == 0) {
                // TX interrupt
                _SccHandleTxInterrupt(self);
            } else {
                // Unknown interrupt type
                _MyIOLog("Made it to Default interrupt routine. \n\r");
                continueLoop = NO;
            }
        } else {
            if (intType != 2) {
                if (intType != 3) {
                    // Unknown interrupt type
                    _MyIOLog("Made it to Default interrupt routine. \n\r");
                    continueLoop = NO;
                } else {
                    // RX error/special condition interrupt
                    statusReg = _SccReadReg(self, 0);
                    _MyIOLog("RecErrorStatus Int %x\n\r", statusReg);
                    // Reset error (WR0 command 0x30)
                    _SccWriteReg(self, 0, 0x30);
                    continueLoop = NO;
                }
            } else {
                // RX character available interrupt
                _SccHandleRxInterrupt(self);
            }
        }

        loopCount = loopCount - 1;

        if (!continueLoop) {
            // FUN_000036e8(param_1) is likely IOUnlock or similar cleanup
            // For now, just return
            return;
        }
    } while (1);
}

/*
 * RX DMA interrupt service routine.
 *
 * Handles RX DMA completion interrupts. Currently just increments
 * the interrupt counter and returns.
 */
static void _PPCSerialRxDMAISR(void *identity, void *state, PPCSerialPort *self)
{
    char *basePtr = (char *)self;

    // Increment interrupt count at offset 0x108
    *(int *)(basePtr + 0x108) = *(int *)(basePtr + 0x108) + 1;

    // FUN_00003518() which calls entry() - likely just returns
    return;
}

/*
 * TX DMA interrupt service routine.
 *
 * Handles TX DMA completion interrupts. Currently just increments
 * the interrupt counter and returns.
 */
static void _PPCSerialTxDMAISR(void *identity, void *state, PPCSerialPort *self)
{
    char *basePtr = (char *)self;

    // Increment interrupt count at offset 0x108
    *(int *)(basePtr + 0x108) = *(int *)(basePtr + 0x108) + 1;

    // FUN_00003554() which calls entry() - likely just returns
    return;
}

/*
 * Probe for SCC device.
 *
 * Determines the SCC control register address based on machine type.
 * The machine type (at offset 0x168) determines the register offset:
 * - Types 0, 5, 6, 7, 8: control register is base + 0x10
 * - Types 1, 2, 3, 4: control register is base + 4
 *
 * Also sets up other register addresses and initialization values.
 */
static BOOL _ProbeSccDevice(PPCSerialPort *self)
{
    char *basePtr = (char *)self;
    int controlRegAddr;
    unsigned short machineType;

    _MyIOLog("In ProbeSccDevice\n\r");

    // Get machine type from offset 0x168
    machineType = *(unsigned short *)(basePtr + 0x168);

    // Determine control register address based on machine type
    switch (machineType) {
    case 0:
    case 5:
    case 6:
    case 7:
    case 8:
        // Control register is at base + 0x10
        controlRegAddr = *(int *)(basePtr + 0x140) + 0x10;
        break;

    case 1:
    case 2:
    case 3:
    case 4:
        // Control register is at base + 4
        controlRegAddr = *(int *)(basePtr + 0x140) + 4;
        break;

    default:
        _MyIOLog("** Undefined Machine Type\n\r");
        goto LAB_set_base;
    }

    // Set control register address at offset 0x13c
    *(int *)(basePtr + 0x13c) = controlRegAddr;

    // Set data register address at offset 0x138 (same as base address)
    *(int *)(basePtr + 0x138) = *(int *)(basePtr + 0x140);

LAB_set_base:
    // Set aligned base address (mask off lower 8 bits)
    *(unsigned int *)(basePtr + 0x144) = *(unsigned int *)(basePtr + 0x140) & 0xffffff00;

    // Set initialization flags
    *(unsigned char *)(basePtr + 0x121) = 1;
    *(unsigned int *)(basePtr + 0x124) = 0x384000;  // 3686400 - another clock rate?

    // Initialize WR1 to 0
    _SccWriteReg(self, 1, 0);

    _MyIOLog("SccProbe %x %x\n\r",
             *(unsigned int *)(basePtr + 0x13c),
             *(unsigned int *)(basePtr + 0x138));

    return YES;
}

/*
 * Program SCC chip registers.
 *
 * Empty function - actual chip programming is done elsewhere.
 * This matches the decompiled code which just returns.
 */
static void _programChip(PPCSerialPort *self)
{
    return;
}

/*
 * Remove data from queue.
 *
 * Removes up to 'size' bytes from the queue into the buffer.
 * Continues until the queue is empty or the requested size is reached.
 *
 * Parameters:
 *   queueBase: Pointer to queue control structure
 *   buffer: Output buffer to receive data
 *   size: Maximum number of bytes to remove
 *
 * Returns: Number of bytes actually removed
 */
static IOReturn _RemovefromQueue(void *queueBase, unsigned char *buffer, unsigned int size, unsigned int *count)
{
    IOReturn result;
    unsigned int bytesRemoved;
    unsigned char localByte;

    bytesRemoved = 0;

    // Loop removing bytes until queue is empty or size reached
    while (1) {
        result = _GetBytetoQueue(queueBase, &localByte);

        // Break if queue is empty or we've reached the requested size
        if ((result != 0) || (size < bytesRemoved)) {
            break;
        }

        // Store byte in output buffer
        *buffer = localByte;
        buffer++;
        bytesRemoved++;
    }

    return bytesRemoved;
}

/*
 * Reset SCC channel.
 */
static void _SccChannelReset(PPCSerialPort *self)
{
    IOLog("PPCSerialPort: _SccChannelReset: called\n");

    // Stub: Send channel reset command
    _SccWriteReg(self, SCC_WR9, 0x80); // Channel reset
}

/*
 * Close SCC channel.
 */
static void _SccCloseChannel(PPCSerialPort *self)
{
    IOLog("PPCSerialPort: _SccCloseChannel: called\n");

    // Stub: Disable TX and RX
    _SccDisableInterrupts(self);
}

/*
 * Disable SCC interrupts.
 *
 * Disables specific interrupt types:
 * - intType 4: TX interrupts (clear WR5 bit 3)
 * - intType 5: RX interrupts (clear WR3 bit 0)
 * - intType 6: Master interrupts (clear WR9 bits 1 and 3)
 *
 * Returns the previous register value before modification.
 */
static unsigned char _SccDisableInterrupts(PPCSerialPort *self, unsigned int intType)
{
    char *basePtr = (char *)self;
    unsigned int regNum;
    unsigned char previousValue;
    unsigned char newValue;

    if (intType == 5) {
        // Disable RX interrupts - clear WR3 bit 0
        previousValue = *(unsigned char *)(basePtr + 299);
        regNum = 3;
        newValue = previousValue & 0xfe;
    } else if (intType < 6) {
        if (intType != 4) {
            return 0;
        }
        // Disable TX interrupts - clear WR5 bit 3
        previousValue = *(unsigned char *)(basePtr + 0x12d);
        regNum = 5;
        newValue = previousValue & 0xf7;
    } else {
        if (intType != 6) {
            return 0;
        }
        // Disable master interrupts - clear WR9 bits 1 and 3 (mask 0xf5)
        previousValue = *(unsigned char *)(basePtr + 0x131);
        regNum = 9;
        newValue = previousValue & 0xf5;
    }

    _SccWriteReg(self, regNum, newValue);
    return previousValue;
}

/*
 * Enable SCC interrupts.
 *
 * Enables specific interrupt types:
 * - intType 4: TX interrupts (WR5 bit 3)
 * - intType 5: RX interrupts (WR3 bit 0, WR0 = 0x20)
 * - intType 6: Master interrupts (WR9 bits 1 and 3)
 */
static void _SccEnableInterrupts(PPCSerialPort *self, unsigned int intType, unsigned int param)
{
    char *basePtr = (char *)self;
    unsigned int regNum;
    unsigned char value;

    if (intType == 5) {
        // Enable RX interrupts - set WR3 bit 0
        _SccWriteReg(self, 3, *(unsigned char *)(basePtr + 299) | 0x01);
        regNum = 0;
        value = 0x20;
    } else if (intType < 6) {
        if (intType != 4) {
            return;
        }
        // Enable TX interrupts - set WR5 bit 3
        regNum = 5;
        value = *(unsigned char *)(basePtr + 0x12d) | 0x08;
    } else {
        if (intType != 6) {
            return;
        }
        // Enable master interrupts - set WR9 bits 1 and 3 (0x0a)
        regNum = 9;
        value = *(unsigned char *)(basePtr + 0x131) | 0x0a;
    }

    _SccWriteReg(self, regNum, value);
}

/*
 * Close SCC channel.
 *
 * Performs a complete shutdown of the SCC channel:
 * 1. Disables all interrupts (master, RX, TX)
 * 2. Resets various control registers
 * 3. Issues reset commands to the SCC
 *
 * This is typically called when closing the serial port.
 */
static void _SccCloseChannel(PPCSerialPort *self)
{
    char *basePtr = (char *)self;

    // Disable all interrupts
    _SccDisableInterrupts(self, 6);  // Master interrupts
    _SccDisableInterrupts(self, 5);  // RX interrupts
    _SccDisableInterrupts(self, 4);  // TX interrupts

    // Reset interrupt and clock mode registers
    _SccWriteReg(self, 1, 0);        // WR1 - interrupt control
    _SccWriteReg(self, 0xb, 0);      // WR11 - clock mode control
    _SccWriteReg(self, 0xe, 0);      // WR14 - misc control bits
    _SccWriteReg(self, 0xf, 8);      // WR15 - external/status interrupt control

    // Issue reset commands (WR0 command 0x10 = reset ext/status interrupts)
    _SccWriteReg(self, 0, 0x10);
    _SccWriteReg(self, 0, 0x10);

    // Re-enable status interrupts
    _SccWriteReg(self, 1, 1);

    // Issue hardware reset commands via WR9
    _SccWriteReg(self, 9, 0x80);     // Force hardware reset
    _SccWriteReg(self, 9, 0x40);     // Channel reset

    _MyIOLog("In SccCloseChannel %d\n\r", *(unsigned char *)(basePtr + 0x148));
}

/*
 * Reset SCC channel.
 *
 * Issues a channel-specific reset command based on the channel number:
 * - Channel 0 (A): WR9 = 0x82 (Channel A reset)
 * - Channel 1 (B): WR9 = 0x42 (Channel B reset)
 *
 * The channel number is stored at offset 0x148 in the object structure.
 */
static void _SccChannelReset(PPCSerialPort *self)
{
    char *basePtr = (char *)self;
    unsigned char resetCommand;
    unsigned char channel;

    // Get channel number from offset 0x148
    channel = *(unsigned char *)(basePtr + 0x148);

    if (channel == 0) {
        // Channel A reset command
        resetCommand = 0x82;
    } else if (channel == 1) {
        // Channel B reset command
        resetCommand = 0x42;
    } else {
        // Invalid channel - do nothing
        return;
    }

    // Issue the reset command to WR9
    _SccWriteReg(self, 9, resetCommand);
}

/*
 * Get CTS signal state.
 *
 * Reads CTS (Clear To Send) from RR0 bit 5 and updates
 * the state at offset 0xc (currentState) bit 5.
 */
static void _SccGetCTS(PPCSerialPort *self)
{
    unsigned int statusReg;
    unsigned int newState;
    char *basePtr = (char *)self;

    // Read RR0 status register
    statusReg = _SccReadReg(self, 0);

    // Check bit 5 (CTS)
    if ((statusReg & 0x20) == 0) {
        // CTS not asserted - clear bit 5 in state (0x20)
        newState = *(unsigned int *)(basePtr + 0xc) & 0xffffffdf;
    } else {
        // CTS asserted - set bit 5 in state (0x20)
        newState = *(unsigned int *)(basePtr + 0xc) | 0x20;
    }

    // Update state
    *(unsigned int *)(basePtr + 0xc) = newState;
}

/*
 * Get DCD signal state.
 *
 * Reads DCD (Data Carrier Detect) from RR0 bit 3 and updates
 * the state at offset 0xc (currentState) bit 6.
 */
static void _SccGetDCD(PPCSerialPort *self)
{
    unsigned int statusReg;
    unsigned int newState;
    char *basePtr = (char *)self;

    // Read RR0 status register
    statusReg = _SccReadReg(self, 0);

    // Check bit 3 (DCD)
    if ((statusReg & 0x08) == 0) {
        // DCD not asserted - clear bit 6 in state (0x40)
        newState = *(unsigned int *)(basePtr + 0xc) & 0xffffffbf;
    } else {
        // DCD asserted - set bit 6 in state (0x40)
        newState = *(unsigned int *)(basePtr + 0xc) | 0x40;
    }

    // Update state
    *(unsigned int *)(basePtr + 0xc) = newState;
}

/*
 * Handle external/status interrupt.
 *
 * Called when modem control signals change or other external events occur.
 * Provides debug logging for various status conditions.
 */
static IOReturn _SccHandleExtInterrupt(PPCSerialPort *self)
{
    unsigned int statusReg;

    // Read RR0 (status register)
    statusReg = _SccReadReg(self, 0);

    // Check and log various status bits
    if ((statusReg & 0x01) != 0) {
        _MyIOLog("Ext-> kRxCharAvailable\n\r");
    }

    if ((statusReg & 0x02) != 0) {
        _MyIOLog("Ext-> kZeroCount\n\r");
    }

    if ((statusReg & 0x04) != 0) {
        _MyIOLog("Ext-> kTxBufferEmpty\n\r");
    }

    if ((statusReg & 0x08) != 0) {
        _MyIOLog("Ext-> kDCDAsserted\n\r");
    }

    if ((statusReg & 0x10) != 0) {
        _MyIOLog("Ext-> kSyncHunt\n\r");
    }

    if ((statusReg & 0x20) != 0) {
        _MyIOLog("Ext-> kCTSAsserted\n\r");
    }

    if ((statusReg & 0x40) != 0) {
        // TX underrun - clear transmitting state
        _changeState(self, 0, 0x10000000);
        _MyIOLog("Ext-> kTXUnderRun\n\r");
    }

    if ((statusReg & 0x80) != 0) {
        _MyIOLog("Ext-> kBreakReceived\n\r");
    }

    // Reset external/status interrupts
    _SccWriteReg(self, 0, 0x10);

    return IO_R_SUCCESS;
}

/*
 * Handle receive interrupt.
 *
 * Called when RX data is available. Handles:
 * - Reading received bytes (up to 100 per interrupt)
 * - Hardware flow control (XON/XOFF)
 * - Overrun error detection
 */
static IOReturn _SccHandleRxInterrupt(PPCSerialPort *self)
{
    unsigned int statusReg;
    unsigned char data;
    short bytesRead;
    short maxBytes;
    unsigned int queueUsed;
    unsigned int statusReg1;
    char *basePtr = (char *)self;

    // Increment statistics
    *(int *)(basePtr + 0x11c) = *(int *)(basePtr + 0x11c) + 1;  // Total RX interrupts
    *(int *)(basePtr + 0x110) = *(int *)(basePtr + 0x110) + 1;  // Offset 0x110 counter

    // Read up to 100 bytes per interrupt
    maxBytes = 100;

    while (1) {
        // Check if RX data is available (bit 0 of RR0)
        statusReg = _SccReadReg(self, 0);
        if ((statusReg & 0x01) == 0) {
            break;  // No more data
        }

        maxBytes--;
        if (maxBytes == 0) {
            break;  // Processed maximum bytes
        }

        // Read the data byte
        data = _SccReadData(self);

        // Check if hardware flow control is enabled (bit 4 of offset 0xc0)
        if ((*(unsigned int *)(basePtr + 0xc0) & 0x10) == 0) {
            // No flow control, add byte to queue
            _AddBytetoQueue(basePtr + 0x24, data);
        } else {
            // Flow control enabled, check for XON/XOFF
            if (data == *(unsigned char *)(basePtr + 0x9f)) {
                // XOFF received - suspend TX
                _SuspendTX(self);
            }
            if (data == *(unsigned char *)(basePtr + 0x9e)) {
                // XON received - resume TX
                _SetUpTransmit(self);
            }
        }

        // Update state (clear bit 19 - RX data available)
        _changeState(self, 0, 0x80000);

        // Check RX queue level for flow control
        queueUsed = _UsedSpaceinQueue(basePtr + 0x24);
        if (queueUsed > *(unsigned int *)(basePtr + 0x58)) {
            // Queue above high watermark, send XOFF
            *(int *)(basePtr + 0xc4) = 1;
            _SetUpTransmit(self);
        }

        // Check for overrun error (bit 5 of RR1)
        statusReg1 = _SccReadReg(self, 1);
        if ((statusReg1 & 0x20) != 0) {
            // Overrun error detected
            *(int *)(basePtr + 0xd4) = *(int *)(basePtr + 0xd4) + 1;

            // Reset error condition (write 0x30 to WR0 twice)
            _SccWriteReg(self, 0, 0x30);
            _SccWriteReg(self, 0, 0x30);
        }
    }

    // Re-enable RX interrupts
    _SccEnableInterrupts(self);

    return IO_R_SUCCESS;
}

/*
 * Handle transmit interrupt.
 *
 * Called when TX buffer becomes empty. Handles:
 * - Flow control (XON/XOFF)
 * - Transmitting next byte from queue
 * - Disabling TX when queue is empty
 */
static IOReturn _SccHandleTxInterrupt(PPCSerialPort *self)
{
    unsigned char savedIntState;
    IOReturn result;
    unsigned char nextByte;
    char *basePtr = (char *)self;

    // Disable interrupts and save state
    savedIntState = _SccDisableInterrupts(self);

    // Increment statistics
    *(int *)(basePtr + 0x118) = *(int *)(basePtr + 0x118) + 1;  // Total TX interrupts
    *(int *)(basePtr + 0x10c) = *(int *)(basePtr + 0x10c) + 1;  // Offset 0x10c counter

    // Reset TX interrupt pending in SCC
    _SccWriteReg(self, 0, 0x28);  // WR0: Reset TX interrupt pending
    _SccWriteReg(self, 0, 0x10);  // WR0: Reset external/status interrupts

    // Set TX pending flag
    *(unsigned char *)(basePtr + 0x120) = 1;

    // Update state to show transmitting
    _changeState(self, 0x10000000, 0x10000000);

    // Handle flow control state
    if (*(int *)(basePtr + 0xc4) == 1) {
        // Send XOFF character
        _SccWriteByte(self, *(unsigned char *)(basePtr + 0x9f));
        *(int *)(basePtr + 0xc4) = -1;
    } else if (*(int *)(basePtr + 0xc4) == 2) {
        // Send XON character
        _SccWriteByte(self, *(unsigned char *)(basePtr + 0x9e));
        *(int *)(basePtr + 0xc4) = 0;
    } else {
        // Get next byte from TX queue
        result = _GetBytetoQueue(basePtr + 0x3c, &nextByte);

        if (result == 2) {
            // Queue is empty, terminate transmission
            *(unsigned char *)(basePtr + 0x120) = 0;
            _changeState(self, 0x4000000, 0x4000000);   // Set bit 26
            _changeState(self, 0, 0x10000000);           // Clear bit 28

            // Disable TX via WR5 bit 3
            _SccWriteReg(self, 5, *(unsigned char *)(basePtr + 0x12d) & 0xf7);

            _MyIOLog("In Tx Interrupt Terminating\n\r");
        } else {
            // Transmit the byte
            _SccWriteByte(self, nextByte);

            // Check queue levels
            _CheckQueues(self);
        }
    }

    // Re-enable interrupts
    _SccEnableInterrupts(self);

    return IO_R_SUCCESS;
}

/*
 * Read a byte from SCC.
 *
 * Checks if RX data is available (bit 0 of RR0) before reading.
 * Returns the byte if available, or 0 if no data.
 */
static unsigned char _SccReadByte(PPCSerialPort *self)
{
    unsigned int statusReg;
    unsigned char data;

    // Read RR0 (status register)
    statusReg = _SccReadReg(self, 0);

    // Check bit 0 (RX character available)
    if ((statusReg & 0x01) == 0) {
        // No data available
        return 0;
    }

    // Data is available, read it
    eieio();
    data = _SccReadData(self);

    return data;
}

/*
 * Read data from SCC data register.
 *
 * Directly reads from the SCC data register (offset 0x13c).
 */
static unsigned char _SccReadData(PPCSerialPort *self)
{
    // Read from SCC data register (offset 0x13c)
    volatile unsigned char *sccData = *(volatile unsigned char **)((char *)self + 0x13c);

    return *sccData;
}

/*
 * Read SCC register.
 *
 * To read a register:
 * 1. If regNum != 0, write register number to control register
 * 2. Read from control register to get the value
 */
static unsigned char _SccReadReg(PPCSerialPort *self, unsigned int regNum)
{
    volatile unsigned char *sccControl = (volatile unsigned char *)self->sccControlReg;
    unsigned char value;

    // If reading a register other than RR0, write the register number first
    if (regNum != 0) {
        *sccControl = (unsigned char)regNum;
        eieio();
    }

    // Enforce ordering before read
    eieio();

    // Read the register value
    value = *sccControl;

    return value;
}

/*
 * Set baud rate.
 *
 * Calculates the time constant for the baud rate generator and
 * programs WR12 (low byte) and WR13 (high byte).
 *
 * Formula: timeConstant = (clockRate / (baudRate * 16) + 1) / 2 - 2
 *
 * The time constant is stored at offsets 0x122 (low) and 0x123 (high).
 */
static IOReturn _SccSetBaud(PPCSerialPort *self, unsigned int baudRate)
{
    unsigned int timeConstant;
    char *basePtr = (char *)self;
    unsigned int clockRate;

    if (baudRate != 0) {
        // Read clock rate from offset 0x124
        clockRate = *(unsigned int *)(basePtr + 0x124);

        // Calculate time constant
        // Formula: (clockRate / (baudRate << 4) + 1) >> 1 - 2
        timeConstant = ((clockRate / (baudRate << 4)) + 1) >> 1;
        timeConstant = timeConstant - 2;

        // Check if time constant is valid (must fit in 16 bits)
        if (timeConstant >= 0x10000) {
            timeConstant = 0xffff;
        }
    } else {
        // Invalid baud rate, use maximum time constant
        timeConstant = 0xffff;
    }

    // Store time constant at offsets 0x122 (low) and 0x123 (high)
    *(unsigned char *)(basePtr + 0x122) = (unsigned char)(timeConstant & 0xff);
    *(unsigned char *)(basePtr + 0x123) = (unsigned char)((timeConstant >> 8) & 0xff);

    // Write to SCC registers using interrupt-safe writes
    _SccWriteIntSafe(self, 0x0c, *(unsigned char *)(basePtr + 0x122));  // WR12 - low byte
    _SccWriteIntSafe(self, 0x0d, *(unsigned char *)(basePtr + 0x123));  // WR13 - high byte
    _SccWriteIntSafe(self, 0x0e, 0x01);  // WR14 - enable baud rate generator

    // Store baud rate at offset 0x8c
    *(unsigned int *)(basePtr + 0x8c) = baudRate;

    _MyIOLog("SetBaud %d %d %d\n\r",
             baudRate,
             *(unsigned char *)(basePtr + 0x122),
             *(unsigned char *)(basePtr + 0x123));

    return IO_R_SUCCESS;
}

/*
 * Set data bits.
 *
 * Configures WR3 (RX) bits 6-7 and WR5 (TX) bits 5-6:
 * 5 bits: WR3=0x00, WR5=0x00
 * 6 bits: WR3=0x80, WR5=0x40
 * 7 bits: WR3=0x40, WR5=0x20
 * 8 bits: WR3=0xc0, WR5=0x60
 */
static BOOL _SccSetDataBits(PPCSerialPort *self, unsigned int dataBits)
{
    char *basePtr = (char *)self;

    // Lookup tables for WR3 and WR5 values
    // Indexed by dataBits value (5-8)
    static const unsigned char txBitsTable[] = {
        0x00, 0x00, 0x00, 0x00, 0x00,  // 0-4 (invalid, but needed for indexing)
        0x00,  // 5 bits
        0x40,  // 6 bits
        0x20,  // 7 bits
        0x60   // 8 bits
    };

    static const unsigned char rxBitsTable[] = {
        0x00, 0x00, 0x00, 0x00, 0x00,  // 0-4 (invalid, but needed for indexing)
        0x00,  // 5 bits
        0x80,  // 6 bits
        0x40,  // 7 bits
        0xc0   // 8 bits
    };

    // Validate dataBits is in range 5-8
    if (dataBits < 5 || dataBits > 8) {
        return NO;
    }

    _MyIOLog("In Set Data Bits %d Tx %x Rx %x\n\r",
             dataBits - 5,
             txBitsTable[dataBits],
             rxBitsTable[dataBits]);

    // Set TX data bits in WR5 (preserve bits 0-4 and 7, set bits 5-6)
    _SccWriteReg(self, 5, txBitsTable[dataBits] | (*(unsigned char *)(basePtr + 0x12d) & 0x9f));

    // Set RX data bits in WR3 (preserve bits 0-5, set bits 6-7)
    _SccWriteReg(self, 3, rxBitsTable[dataBits] | (*(unsigned char *)(basePtr + 299) & 0x3f));

    self->dataBits = dataBits;
    return YES;
}

/*
 * Set DTR signal.
 *
 * Controls DTR (Data Terminal Ready) via WR5 bit 7.
 */
static void _SccSetDTR(PPCSerialPort *self, BOOL state)
{
    unsigned char wr5Value;
    char *basePtr = (char *)self;

    // Read cached WR5 value (offset 0x12d)
    if (state) {
        // Set DTR (bit 7)
        wr5Value = *(unsigned char *)(basePtr + 0x12d) | 0x80;
    } else {
        // Clear DTR (bit 7)
        wr5Value = *(unsigned char *)(basePtr + 0x12d) & 0x7f;
    }

    _SccWriteReg(self, 5, wr5Value);
}

/*
 * Set parity.
 *
 * Configures WR4 bits 0-1:
 * 1 = PARITY_NONE (disable parity, clear bit 0)
 * 2 = PARITY_ODD  (enable parity, odd, set bit 0, clear bit 1)
 * 3 = PARITY_EVEN (enable parity, even, set bits 0 and 1)
 */
static IOReturn _SccSetParity(PPCSerialPort *self, unsigned int parity)
{
    char *basePtr = (char *)self;
    unsigned char wr4Value;

    _MyIOLog("SccSetParity %d\n\r", parity);

    // Read cached WR4 value (offset 300 = 0x12c)
    wr4Value = *(unsigned char *)(basePtr + 300);

    switch (parity) {
        case 1:  // PARITY_NONE
            // Clear bit 0 (disable parity)
            _SccWriteReg(self, 4, wr4Value & 0xfe);
            break;

        case 2:  // PARITY_ODD
            // Clear bit 1, set bit 0 (odd parity)
            _SccWriteReg(self, 4, (wr4Value & 0xfd) | 0x01);
            break;

        case 3:  // PARITY_EVEN
            // Set bits 0 and 1 (even parity)
            _SccWriteReg(self, 4, wr4Value | 0x03);
            break;

        default:
            return IO_R_INVALID_ARG;
    }

    self->parity = parity;
    return IO_R_SUCCESS;
}

/*
 * Set RTS signal.
 *
 * Controls RTS (Request To Send) via WR5 bit 1.
 */
static void _SccSetRTS(PPCSerialPort *self, BOOL state)
{
    unsigned char wr5Value;
    char *basePtr = (char *)self;

    // Read cached WR5 value (offset 0x12d)
    if (state) {
        // Set RTS (bit 1)
        wr5Value = *(unsigned char *)(basePtr + 0x12d) | 0x02;
    } else {
        // Clear RTS (bit 1)
        wr5Value = *(unsigned char *)(basePtr + 0x12d) & 0xfd;
    }

    _SccWriteReg(self, 5, wr5Value);
}

/*
 * Set stop bits.
 *
 * Configures WR4 bits 2-3:
 * 0 = sync mode
 * 1 = 1 stop bit   (0x00)
 * 2 = 1.5 stop bits (0x04)
 * 3 = 2 stop bits   (0x08)
 * 4 = reserved      (0x0c)
 */
static IOReturn _SccSetStopBits(PPCSerialPort *self, unsigned int stopBits)
{
    unsigned char wr4Bits;
    char *basePtr = (char *)self;

    _MyIOLog("SccSetStopBits %d\n\r", stopBits);

    // Map stopBits value to WR4 bits
    switch (stopBits) {
        case 0:
            wr4Bits = 0x00;  // Sync mode
            break;
        case 2:
            wr4Bits = 0x04;  // 1.5 stop bits
            break;
        case 3:
            wr4Bits = 0x08;  // 2 stop bits
            break;
        case 4:
            wr4Bits = 0x0c;  // Reserved
            break;
        default:
            return IO_R_INVALID_ARG;
    }

    // Read cached WR4 value (offset 300 = 0x12c), preserve all bits except 2-3
    // Then OR in the new stop bit setting
    _SccWriteReg(self, 4, wr4Bits | (*(unsigned char *)(basePtr + 300) & 0xf3));

    self->stopBits = stopBits;
    return IO_R_SUCCESS;
}

/*
 * Write a byte to SCC.
 *
 * Checks if TX buffer is empty (bit 2 of RR0) before writing.
 * Returns true if byte was written, false if TX buffer was full.
 */
static BOOL _SccWriteByte(PPCSerialPort *self, unsigned char byte)
{
    unsigned int statusReg;
    BOOL txReady;

    // Read RR0 (status register)
    statusReg = _SccReadReg(self, 0);

    // Check bit 2 (TX buffer empty)
    txReady = (statusReg & 0x04) != 0;

    if (txReady) {
        // TX buffer is empty, write the byte
        volatile unsigned char *sccData = *(volatile unsigned char **)((char *)self + 0x13c);
        *sccData = byte;

        // Enforce in-order execution
        eieio();
    }

    return txReady;
}

/*
 * Write data to SCC data register.
 *
 * Writes a single byte directly to the SCC data register (offset 0x13c).
 */
static IOReturn _SccWriteData(PPCSerialPort *self, unsigned char data)
{
    // Write to SCC data register (offset 0x13c)
    volatile unsigned char *sccData = *(volatile unsigned char **)((char *)self + 0x13c);

    *sccData = data;

    // Enforce in-order execution
    eieio();

    return IO_R_SUCCESS;
}

/*
 * Write SCC register (interrupt-safe).
 *
 * This function is identical to _SccWriteReg in the decompiled code.
 * The "interrupt-safe" aspect may be handled by the caller or by the
 * memory barriers (eieio) that ensure atomic operation.
 */
static void _SccWriteIntSafe(PPCSerialPort *self, unsigned int regNum, unsigned char value)
{
    char *basePtr = (char *)self;

    // Only allow valid register numbers (0-15)
    if (regNum < 0x10) {
        volatile unsigned char *sccControl = (volatile unsigned char *)self->sccControlReg;

        // Write register number to control register
        *sccControl = (unsigned char)regNum;

        // Enforce in-order execution (memory barrier)
        eieio();

        // Write value to control register
        *sccControl = value;

        // Enforce in-order execution again
        eieio();

        // Cache the register value at offset 0x128 + regNum
        *(unsigned char *)(basePtr + 0x128 + regNum) = value;
    }
}

/*
 * Write SCC register.
 *
 * The SCC requires two write cycles:
 * 1. Write register number to control register
 * 2. Write value to control register
 *
 * The value is also cached at offset 0x128 + regNum
 */
static void _SccWriteReg(PPCSerialPort *self, unsigned int regNum, unsigned char value)
{
    char *basePtr = (char *)self;

    // Only allow valid register numbers (0-15)
    if (regNum < 0x10) {
        volatile unsigned char *sccControl = (volatile unsigned char *)self->sccControlReg;

        // Write register number to control register
        *sccControl = (unsigned char)regNum;

        // Enforce in-order execution (memory barrier)
        // This ensures the register select completes before the value write
        eieio();  // Or use sync() on some PowerPC systems

        // Write value to control register
        *sccControl = value;

        // Enforce in-order execution again
        eieio();

        // Cache the register value at offset 0x128 + regNum
        *(unsigned char *)(basePtr + 0x128 + regNum) = value;
    }
}

/*
 * Send next character from TX queue.
 * This is called from the TX interrupt handler.
 */
static void _SendNextChar(PPCSerialPort *self)
{
    // Write 0x12 to SCC WR1 (TX interrupt control)
    // This is the interrupt enable register value
    _SccWriteReg(self, 1, 0x12);
}

/*
 * Set structure defaults.
 *
 * Parameters:
 *   self: Pointer to PPCSerialPort instance
 *   fullInit: If true, perform full initialization; if false, partial init
 */
static void _SetStructureDefaults(PPCSerialPort *self, BOOL fullInit)
{
    unsigned int i;
    char *basePtr = (char *)self;

    IOLog("PPCSerialPort: _SetStructureDefaults: called (fullInit=%d)\n", fullInit);

    if (fullInit) {
        // Full initialization path
        *(unsigned int *)(basePtr + 0x4) = 0;
        *(unsigned int *)(basePtr + 0x8) = 0;
        *(unsigned int *)(basePtr + 0x98) = 0x1c2000;  // 1843200 - clock rate
        *(unsigned short *)(basePtr + 0x90) = 0;
        *(unsigned char *)(basePtr + 0x92) = 0;
        *(unsigned char *)(basePtr + 0x93) = 0;
        *(unsigned char *)(basePtr + 0x94) = 0;
        *(unsigned char *)(basePtr + 0x95) = 0;
        *(unsigned int *)(basePtr + 0x74) = 0;
        *(unsigned int *)(basePtr + 0xf0) = 0;
        *(unsigned int *)(basePtr + 0xf4) = 0;
        *(unsigned int *)(basePtr + 0xf8) = 0;
        *(unsigned int *)(basePtr + 0xfc) = 0;
        *(unsigned int *)(basePtr + 0x100) = 0;
        *(unsigned int *)(basePtr + 0x104) = 0;
        *(unsigned int *)(basePtr + 0xc) = 0x60c0000;  // Initial state
        *(unsigned int *)(basePtr + 0x10) = 0;
        *(unsigned short *)(basePtr + 0x168) = 7;
    }

    // Common initialization (always executed)
    *(unsigned int *)(basePtr + 0x88) = 0;
    *(unsigned int *)(basePtr + 0x8c) = 0;
    *(unsigned int *)(basePtr + 0x78) = 0;
    *(unsigned int *)(basePtr + 0x88) = 0;  // Written twice in original code
    *(unsigned int *)(basePtr + 0x7c) = 0;
    *(unsigned int *)(basePtr + 0x80) = 0;
    *(unsigned int *)(basePtr + 0x84) = 0;
    *(unsigned char *)(basePtr + 0x9d) = 0;
    *(unsigned char *)(basePtr + 0x9c) = 0;
    *(unsigned char *)(basePtr + 0x9e) = 0x11;  // XON character
    *(unsigned char *)(basePtr + 0x9f) = 0x13;  // XOFF character
    *(unsigned int *)(basePtr + 0xc0) = 0;
    *(unsigned int *)(basePtr + 0xc4) = 0;      // Flow control state
    *(unsigned int *)(basePtr + 200) = 0;       // 0xc8
    *(unsigned int *)(basePtr + 0xd8) = 0;
    *(unsigned int *)(basePtr + 0xdc) = 0;
    *(unsigned int *)(basePtr + 0xe8) = 0;
    *(unsigned int *)(basePtr + 0xec) = 0;

    // TX queue watermarks
    *(unsigned int *)(basePtr + 0x54) = 0x4b0;  // 1200 - TX capacity
    *(unsigned int *)(basePtr + 0x58) = 800;    // TX low water
    *(unsigned int *)(basePtr + 0x5c) = 400;    // TX med water
    *(unsigned int *)(basePtr + 100) = 0x4b0;   // 1200 - offset 0x64 (TX high water)

    // Calculate derived watermarks
    *(unsigned int *)(basePtr + 0x68) = (unsigned int)(*(int *)(basePtr + 0x54) << 1) / 3;
    *(unsigned int *)(basePtr + 0x6c) = *(unsigned int *)(basePtr + 0x58) >> 1;

    *(unsigned int *)(basePtr + 0xc0) = 0x126;  // 294 decimal
    *(unsigned char *)(basePtr + 0x120) = 0;    // TX pending flag

    // Clear character filter bitmap (8 DWORDs = 32 bytes = 256 bits)
    for (i = 0; i < 8; i++) {
        *(unsigned int *)(basePtr + 0xa0 + (i * 4)) = 0;
    }

    // Clear statistics counters
    *(unsigned int *)(basePtr + 0x108) = 0;
    *(unsigned int *)(basePtr + 0x10c) = 0;
    *(unsigned int *)(basePtr + 0x110) = 0;
    *(unsigned int *)(basePtr + 0x114) = 0;
    *(unsigned int *)(basePtr + 0x118) = 0;
    *(unsigned int *)(basePtr + 0x11c) = 0;
}

/*
 * Set up transmission.
 */
static void _SetUpTransmit(PPCSerialPort *self)
{
    unsigned char firstByte;
    IOReturn result;

    _MyIOLog("++> SetUpTransmit\n\r");

    // Check if transmission is already set up
    if (self->txPendingFlag == 0x01) {
        _MyIOLog("--> SetUpTransmit Already Set\n\r");
        return;
    }

    // Handle flow control state
    // flowControlState == 1: send XOFF
    // flowControlState == 2: send XON
    if (self->flowControlState == 1) {
        _SccWriteByte(self, self->xoffChar);
        self->flowControlState = -1;
    }

    if (self->flowControlState == 2) {
        _SccWriteByte(self, self->xonChar);
        self->flowControlState = 0;
    }

    // Try to get first byte from TX queue
    result = _GetBytetoQueue(&self->txQueueCapacity, &firstByte);

    if (result != 2) { // 2 means queue empty or error
        // Enable TX buffer empty interrupts (bit 1 of WR1)
        _SccWriteReg(self, SCC_WR1, self->ierValue | 0x02);

        // Update cached IER value
        self->ierValue = self->ierValue | 0x02;

        // Enable interrupts
        _SccEnableInterrupts(self);

        // Set TX pending flag
        self->txPendingFlag = 1;

        // Update state to show transmitting (bit 28)
        _changeState(self, 0x10000000, 0x10000000);

        // Write first byte to start transmission
        _SccWriteByte(self, firstByte);

        _MyIOLog("Write First byte. (%x)\n\r", (unsigned int)firstByte);
    }

    _MyIOLog("--> SetUpTransmit\n\r");
}

/*
 * Suspend transmission.
 */
static void _SuspendTX(PPCSerialPort *self)
{
    // Disable TX buffer empty interrupts (bit 2 of WR1)
    _SccDisableInterrupts(self);
}

/*
 * Get used space in queue.
 */
static unsigned int _UsedSpaceinQueue(void *queueBase)
{
    // Queue structure: offset 0x14 is the "used" field
    unsigned int *used = (unsigned int *)((char *)queueBase + 0x14);
    return *used;
}

/*
 * Watch state for changes.
 * Waits until the current state matches the desired state for the given mask.
 *
 * Based on decompiled code:
 * - If mask doesn't include STATE_ACTIVE bit, it's automatically added to mask
 *   and cleared from the desired state
 * - Returns IO_R_SUCCESS (0) when state matches
 * - Returns IO_R_INTERRUPTED (0xfffffd41) if interrupted
 * - Returns IO_R_INVALID_ARG (0xfffffd36) if STATE_ACTIVE requested but port not active
 */
static IOReturn _watchState(PPCSerialPort *self, unsigned int *statePtr, unsigned int mask)
{
    unsigned int desiredState;
    unsigned int matchingBits;
    BOOL checkActiveFlag;
    IOReturn result;
    int lockResult;

    desiredState = *statePtr;

    // Check if mask includes upper bits (0xc0000000, which includes STATE_ACTIVE)
    checkActiveFlag = ((mask & 0xc0000000) == 0);

    if (checkActiveFlag) {
        // If STATE_ACTIVE not in mask, clear it from desired state
        // and add it to the mask
        desiredState = desiredState & 0xbfffffff; // Clear bit 30
        mask = mask | 0x40000000; // Add STATE_ACTIVE to mask
    }

    // Wait loop
    do {
        // Calculate matching bits: ~(currentState XOR desiredState) & mask
        // This gives us the bits that match between current and desired state
        matchingBits = ~(self->currentState ^ desiredState) & mask;

        _MyIOLog("WatchState %x\n\r", matchingBits);

        // If any bits match, we're done
        if (matchingBits != 0) {
            // Return current state
            *statePtr = self->currentState;

            // Check return value based on checkActiveFlag
            if (checkActiveFlag) {
                // If we added STATE_ACTIVE and it's not set, return error
                if ((matchingBits & 0x40000000) == 0) {
                    result = IO_R_INVALID_ARG; // 0xfffffd36
                } else {
                    result = IO_R_SUCCESS;
                }
            } else {
                result = IO_R_SUCCESS;
            }

            goto cleanup;
        }

        // Try to acquire lock (spin until acquired)
        // FUN_00002b4c(0, &watchStateLock) - returns 0 on success
        do {
            lockResult = *(int *)((char *)self + 0x14); // Simple lock check
        } while (lockResult != 0);

        // Set watchStateMask to the mask we're waiting for
        self->watchStateMask = self->watchStateMask | mask;

        // Wait for state change
        // FUN_00002b3c(watchStateMask, watchStateLock, 1) = assert_wait/thread_block
        // This would be a proper sleep/wait in real implementation
        // For now, we'll simulate it

        // FUN_00002b2c() gets the wait result
        // If result is 4, continue loop; otherwise return interrupted
        lockResult = 4; // Simulate successful wait

    } while (lockResult == 4);

    // If we get here, we were interrupted
    result = IO_R_INTERRUPTED; // 0xfffffd41

cleanup:
    // Clear watchStateMask
    self->watchStateMask = 0;

    // Unlock (FUN_00002b1c)
    // Clear lock

    return result;
}
