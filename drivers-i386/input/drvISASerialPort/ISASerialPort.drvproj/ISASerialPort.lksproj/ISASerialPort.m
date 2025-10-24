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
 * ISASerialPort.m - Implementation for ISA Serial Port driver.
 *
 * HISTORY
 */

#import "ISASerialPort.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/ioPorts.h>
#import <string.h>
#import <stdio.h>
#import <stdlib.h>

// I/O port access macros
#define OUTB(port, val) outb(port, val)
#define INB(port) inb(port)

// External kernel threading and synchronization functions
extern void thread_sleep(void *event, int lock, int interruptible);
extern int thread_wait_result(void);
extern void thread_wakeup_prim(void *event, int one_thread, int result);
extern void *thread_call_allocate(void (*func)(void *), void *param);
extern void thread_call_enter(void *call);
extern void thread_call_cancel(void *call);
extern void thread_call_free(void *call);
extern void thread_call_enter_delayed(void *call, unsigned long long deadline);
extern unsigned long long deadline_from_interval(unsigned int interval_low, unsigned int interval_high);
extern unsigned int spl4(void);
extern void splx(unsigned int level);
extern void IOEnterCriticalSection(void);
extern void IOExitCriticalSection(void);
extern void *IOMalloc(unsigned int size);
extern void IOFree(void *address, unsigned int size);
extern void IOLog(const char *format, ...);

// Forward declarations for 64-bit arithmetic helper functions
unsigned long long __udivdi3(unsigned int dividend_lo, unsigned int dividend_hi,
                             unsigned int divisor_lo, unsigned int divisor_hi);
unsigned long long __umoddi3(unsigned int dividend_lo, unsigned int dividend_hi,
                             unsigned int divisor_lo, unsigned int divisor_hi);

// Chip type names - indexed by chip type
static const char *chipTypeNames[] = {
    "Auto",      // CHIP_UNKNOWN - will be auto-detected
    "8250",      // CHIP_8250
    "16450",     // CHIP_16450
    "16550",     // CHIP_16550
    "16550?",    // CHIP_UNKNOWN_FIFO
    "16550A",    // CHIP_16550A
    "16650",     // CHIP_16650
    "16750",     // CHIP_16750
    "16950"      // CHIP_16950
};

// Chip capability table - indexed by chip type
typedef struct {
    unsigned int maxBaudRate;  // Offset 0: Maximum baud rate
    unsigned int fifoSize;     // Offset 4: FIFO size (0 for non-FIFO chips)
    unsigned int reserved[3];  // 20 bytes total per entry
} ChipCapabilities;

static const ChipCapabilities chipCapTable[] = {
    { 9600,   0 },    // CHIP_UNKNOWN
    { 9600,   0 },    // CHIP_8250 - no FIFO
    { 19200,  0 },    // CHIP_16450 - no FIFO
    { 38400,  0 },    // CHIP_16550 - broken FIFO
    { 38400,  0 },    // CHIP_UNKNOWN_FIFO
    { 115200, 16 },   // CHIP_16550A - 16-byte FIFO
    { 230400, 32 },   // CHIP_16650 - 32-byte FIFO
    { 460800, 64 },   // CHIP_16750 - 64-byte FIFO
    { 921600, 128 }   // CHIP_16950 - 128-byte FIFO
};

// MSR (Modem Status Register) delta bits to state bits lookup table
// Indexed by MSR high nibble (delta bits)
// Maps MSR delta bits to currentState modem signal bits (bits 5-8)
static const unsigned char _msr_state_lut[16] = {
    0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
    0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf
};

// RX event type markers (in addition to EVENT_OVERFLOW and EVENT_STATE_CHANGE)
#define EVENT_OVERRUN_ERROR     0x68    // Overrun error event
#define EVENT_VALID_DATA        0x55    // Valid data byte marker ('U')
#define EVENT_SPECIAL_DATA      0x59    // Special/filtered data marker ('Y')
#define EVENT_PARITY_ERROR      0x61    // Parity error event
#define EVENT_FRAMING_ERROR     0x5D    // Framing error/break event (']')
#define EVENT_ERROR             0xFC    // Generic error event

//==============================================================================
// C Helper Functions (not Objective-C methods)
//==============================================================================

// Forward declarations for utility functions
static IOReturn _activatePort(ISASerialPort *self);
static IOReturn _deactivatePort(ISASerialPort *self);
static IOReturn _allocateRingBuffer(void *queueBase, ISASerialPort *self);
static void _freeRingBuffer(void *queueBase);
static IOReturn _RX_dequeueData(ISASerialPort *self, unsigned char *byteOut, BOOL sleep);
static void _heartBeatTOHandler(ISASerialPort *self);
static void _frameTOHandler(ISASerialPort *self);
static void _delayTOHandler(ISASerialPort *self);
static void _dataLatTOHandler(ISASerialPort *self);
static unsigned int _flowMachine(ISASerialPort *self);
static void _executeEvent(ISASerialPort *self, unsigned char eventType, unsigned int eventData,
                         unsigned int *statePtr, unsigned int *changedBitsPtr);
static void _NonFIFOIntHandler(void *identity, void *state, ISASerialPort *self);
static void _FIFOIntHandler(void *identity, void *state, ISASerialPort *self);

/*
 * Validate and normalize ring buffer size.
 * Returns a clamped size value between minimum and maximum limits.
 */
static unsigned int _validateRingBufferSize(unsigned int requestedSize, ISASerialPort *self)
{
    unsigned int size = requestedSize;

    // If size is 0, use default
    if (size == 0) {
        size = self->defaultRingBufferSize;
    }

    // Clamp to maximum size (256KB)
    if (size > MAX_RING_BUFFER_SIZE) {
        size = MAX_RING_BUFFER_SIZE;
    }

    // Clamp to minimum size (18 bytes)
    if (size < MIN_RING_BUFFER_SIZE) {
        size = MIN_RING_BUFFER_SIZE;
    }

    return size;
}

/*
 * Free ring buffer memory.
 * Deallocates a ring buffer (RX or TX) and resets all related pointers.
 *
 * Parameters:
 *   queueBase - Pointer to the base of queue structure (either &rxQueueCapacity or &txQueueCapacity)
 */
static void _freeRingBuffer(void *queueBase)
{
    // Queue structure layout (relative to queueBase):
    // +0x00: capacity (uint)
    // +0x04: used (uint)
    // +0x18: start (void*)
    // +0x1c: end (void*)

    unsigned int *capacity = (unsigned int *)queueBase;
    void **start = (void **)((char *)queueBase + 0x18);
    void **end = (void **)((char *)queueBase + 0x1c);

    // Check if ring buffer is allocated (check start pointer)
    if (*start != NULL) {
        // Free the buffer memory
        IOFree(*start, (unsigned int)((char *)*end - (char *)*start));
    }

    // Clear capacity and used fields
    *capacity = 0;
    *((unsigned int *)((char *)queueBase + 0x04)) = 0; // used

    // Clear all pointer fields
    *end = NULL;
    *start = NULL;
    *((void **)((char *)queueBase + 0x20)) = NULL; // write pointer
    *((void **)((char *)queueBase + 0x24)) = NULL; // read pointer

    // Clear watermark fields (offsets vary between RX and TX)
    *((unsigned int *)((char *)queueBase + 0x08)) = 0;
    *((unsigned int *)((char *)queueBase + 0x0c)) = 0;
    *((unsigned int *)((char *)queueBase + 0x10)) = 0;
}

/*
 * Frame timeout handler.
 * Timer callback that triggers interrupt handler when frame timeout occurs.
 * Used for detecting end of transmission or processing delayed events.
 */
static void _frameTOHandler(ISASerialPort *self)
{
    unsigned int oldIRQL;

    // Raise interrupt level
    oldIRQL = spl4();

    // Clear timer pending flag
    self->timerPending = 0;

    // Call appropriate interrupt handler based on chip type
    // The function pointer table is indexed by chipType * 5
    if (self->hasFIFO) {
        // Call FIFO interrupt handler (stub for now)
        // _FIFOIntHandler(0, 0, self);
    } else {
        _NonFIFOIntHandler(0, 0, self);
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Delay timeout handler.
 * Timer callback for delayed operations. Clears the delay bit from state
 * and triggers the appropriate interrupt handler.
 */
static void _delayTOHandler(ISASerialPort *self)
{
    unsigned int oldIRQL;

    // Raise interrupt level
    oldIRQL = spl4();

    // Clear delay state bit (0x1000) from currentState
    self->currentState &= ~0x1000;

    // Call appropriate interrupt handler based on chip type
    if (self->hasFIFO) {
        _FIFOIntHandler(0, 0, self);
    } else {
        _NonFIFOIntHandler(0, 0, self);
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Data latency timeout handler.
 * Handles RX queue overflow conditions and adjusts flow control based on queue levels.
 * This is called when the RX queue reaches critical levels and needs to signal overflow
 * or adjust flow control to prevent data loss.
 */
static void _dataLatTOHandler(ISASerialPort *self)
{
    unsigned int oldIRQL;
    unsigned int spaceFree;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned int eventMask;

    // Raise interrupt level
    oldIRQL = spl4();

    // Calculate free space in RX queue
    spaceFree = self->rxQueueCapacity - self->rxQueueUsed;

    // Check if we have less than 3 bytes of space available
    if (spaceFree < 3) {
        // Queue is nearly full or completely full
        if (self->rxQueueCapacity <= self->rxQueueUsed) {
            // Queue is completely full - set overflow flag
            self->rxQueueOverflow = 1;
        } else {
            // Nearly full - write overflow marker event (0x6c)
            *(unsigned short *)self->rxQueueWrite = EVENT_OVERFLOW;
            // No advance needed, fall through to common advance code
        }
    } else {
        // We have at least 3 bytes available - write a 3-word event
        // Event type 0x4f (likely "queue has room" notification)
        *(unsigned short *)self->rxQueueWrite = 0x4f;
        self->rxQueueWrite = (char *)self->rxQueueWrite + 2;
        if (self->rxQueueWrite >= self->rxQueueEnd) {
            self->rxQueueWrite = self->rxQueueStart;
        }
        self->rxQueueUsed++;

        // Write first zero word
        *(unsigned short *)self->rxQueueWrite = 0;
        self->rxQueueWrite = (char *)self->rxQueueWrite + 2;
        if (self->rxQueueWrite >= self->rxQueueEnd) {
            self->rxQueueWrite = self->rxQueueStart;
        }
        self->rxQueueUsed++;

        // Write second zero word
        *(unsigned short *)self->rxQueueWrite = 0;
        // Fall through to common advance code
    }

    // Common: advance write pointer for final word
    self->rxQueueWrite = (char *)self->rxQueueWrite + 2;
    if (self->rxQueueWrite >= self->rxQueueEnd) {
        self->rxQueueWrite = self->rxQueueStart;
    }
    self->rxQueueUsed++;

    // Now update state based on queue levels
    if (self->rxQueueUsed <= self->rxQueueTarget) {
        // Queue is below or at target level
        // Start with base state (keep certain bits)
        newState = self->currentState & 0x17E;

        if (self->rxQueueUsed < self->rxQueueLowWater) {
            // Below low watermark
            self->rxQueueWatermark = 0;

            if (self->rxQueueUsed == 0) {
                // Queue is empty
                newState |= RX_STATE_EMPTY;
                self->rxQueueTarget = 0;
            } else {
                // Below low watermark but not empty
                newState |= RX_STATE_BELOW_LOW;
                self->rxQueueTarget = self->rxQueueLowWater;
            }

            // Update flow control based on mode
            if ((self->flowControlMode & FLOW_RTS_ENABLED) == 0) {
                if ((self->flowControlMode & FLOW_HW_ENABLED) == 0) {
                    if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                        newState |= STATE_DTR;
                    }
                } else {
                    // Hardware flow control enabled
                    newState |= STATE_RTS;
                    if (self->flowControlState == -1) {
                        self->flowControlState = 2;
                    } else if (self->flowControlState == 1) {
                        self->flowControlState = -2;
                    }
                }
            } else {
                // RTS flow control enabled
                newState |= STATE_RTS;
            }

        } else if (self->rxQueueHighWater < self->rxQueueUsed) {
            // Above high watermark - apply back pressure
            self->rxQueueTarget = self->rxQueueCapacity - 3;

            if (self->rxQueueCapacity - 3 < self->rxQueueUsed) {
                // Critical level (capacity - 3 or more used)
                newState |= RX_STATE_CRITICAL;
                self->rxQueueWatermark = self->rxQueueCapacity;
            } else {
                // Above high watermark
                newState |= RX_STATE_ABOVE_HIGH;
                self->rxQueueWatermark = self->rxQueueHighWater;
            }

            // Update flow control - turn OFF DTR/RTS to signal back pressure
            if ((self->flowControlMode & FLOW_RTS_ENABLED) == 0) {
                if ((self->flowControlMode & FLOW_HW_ENABLED) == 0) {
                    if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                        newState &= ~STATE_DTR;
                    }
                } else {
                    // Hardware flow control - clear RTS
                    newState &= ~STATE_RTS;
                    if ((self->flowControlState == -2) || (self->flowControlState == 0)) {
                        self->flowControlState = 1;
                    } else if (self->flowControlState == 2) {
                        self->flowControlState = -1;
                    }
                }
            } else {
                // RTS flow control - clear RTS
                newState &= ~STATE_RTS;
            }

        } else {
            // Between low and high watermarks - maintain current target
            self->rxQueueTarget = self->rxQueueHighWater;
            self->rxQueueWatermark = self->rxQueueLowWater;
        }

        // Update current state, preserving specific bits
        oldState = self->currentState;
        newState = (oldState & 0xFFF0FFE9) | (newState & 0xF0016);
        changedBits = oldState ^ newState;
        self->currentState = newState;

        // Wake up any threads waiting on state changes
        if (self->watchStateMask & changedBits) {
            thread_wakeup_prim(&self->watchStateMask, 0, 4);
        }

        // Update DTR/RTS hardware signals if they changed
        if (changedBits & STATE_FLOW_MASK) {
            mcrValue = MCR_OUT2;
            if (newState & STATE_DTR) {
                mcrValue |= MCR_DTR;
            }
            if (newState & STATE_RTS) {
                mcrValue |= MCR_RTS;
            }
            outb(self->basePort + UART_MCR, mcrValue);
            // Atomic increment of statistics counter (LOCK/UNLOCK omitted)
        }

        // Trigger timer callout if not paused
        if ((self->statusFlags & 0x10) == 0) {
            thread_call_enter(self->timerCallout);
        }

        // Enqueue state change event if any watched state bits changed
        memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
        if (eventMask & (changedBits << 16)) {
            _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                               (newState & 0xFFFF) | (changedBits << 16));
        }
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Flow control state machine.
 * Calculates the new port state based on current flow control configuration.
 * Returns the updated state value with flow control bits set appropriately.
 */
static unsigned int _flowMachine(ISASerialPort *self)
{
    unsigned int newState = self->currentState;

    // Check if RTS or hardware flow control is enabled
    if ((self->flowControlMode & (FLOW_RTS_ENABLED | FLOW_HW_ENABLED)) == 0) {
        // Only DTR flow control (if enabled)
        if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
            // Check if queue above high watermark or status flag not set
            if ((self->rxQueueHighWater < self->rxQueueUsed) ||
                ((self->statusFlags & 0x40) == 0)) {
                // De-assert DTR
                newState &= ~STATE_DTR;
            } else {
                // Assert DTR
                newState |= STATE_DTR;
            }
        }
    } else {
        // RTS and/or hardware flow control enabled

        // Handle DTR if enabled
        if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
            if ((self->statusFlags & 0x40) == 0) {
                // De-assert DTR
                newState &= ~STATE_DTR;
            } else {
                // Assert DTR
                newState |= STATE_DTR;
            }
        }

        // Handle RTS flow control
        if ((self->flowControlMode & FLOW_RTS_ENABLED) == 0) {
            // Hardware flow control only
            if ((self->flowControlMode & FLOW_HW_ENABLED) != 0) {
                if (self->rxQueueHighWater < self->rxQueueUsed) {
                    // Queue above high watermark - de-assert hardware flow control
                    newState &= ~0x10;
                    self->flowControlState = 1;
                } else {
                    // Queue below high watermark - assert hardware flow control
                    newState |= 0x10;
                    // Update flow control state if conditions met
                    if ((self->flowControlState != 0) && ((self->statusFlags & 0x40) != 0)) {
                        self->flowControlState = 2;
                    }
                }
            }
        } else {
            // RTS flow control enabled
            if ((self->rxQueueHighWater < self->rxQueueUsed) ||
                ((self->statusFlags & 0x40) == 0)) {
                // De-assert RTS
                newState &= ~STATE_RTS;
            } else {
                // Assert RTS
                newState |= STATE_RTS;
            }
        }
    }

    return newState;
}

/*
 * Watch state internal implementation.
 * Waits for the port state to change according to the mask.
 * Returns IO_R_SUCCESS when state changes, or error on timeout/device removal.
 */
static IOReturn _watchState(ISASerialPort *self, unsigned int *state, unsigned int mask)
{
    BOOL needsActiveCheck = NO;
    unsigned int desiredState = *state;
    unsigned int actualMask = mask;
    unsigned int changedBits;
    int waitResult;
    IOReturn result;

    // If neither high bits are set in mask, add STATE_ACTIVE bit
    if ((mask & 0xC0000000) == 0) {
        desiredState &= ~STATE_ACTIVE;  // Clear active bit from desired state
        actualMask |= STATE_ACTIVE;     // Add active bit to mask
        needsActiveCheck = YES;
    }

    do {
        // Check which state bits have changed from desired
        // (~currentState ^ desiredState) gives bits that differ
        changedBits = (~self->currentState ^ desiredState) & actualMask;

        if (changedBits != 0) {
            // State has changed - return current state
            *state = self->currentState;

            // If we were checking for active state and it changed
            if (needsActiveCheck && (changedBits & STATE_ACTIVE)) {
                // Port became inactive (PCMCIA yanked or closed)
                return IO_R_NO_DEVICE;  // -714 (0xfffffd36)
            }

            return IO_R_SUCCESS;
        }

        // State hasn't changed yet - wait for it

        // Acquire lock using test-and-set loop
        while (self->watchStateLock != 0) {
            // Spin while lock is held
        }

        // Atomic test and set
        IOEnterCriticalSection();
        if (self->watchStateLock == 1) {
            IOExitCriticalSection();
            continue;  // Lost race, try again
        }
        self->watchStateLock = 1;
        IOExitCriticalSection();

        // Set the mask of bits we're watching
        self->watchStateMask |= actualMask;

        // Sleep waiting for state change
        thread_sleep(&self->watchStateMask, &self->watchStateLock, 1);  // 1 = interruptible

        // Get the result of the wait
        waitResult = thread_wait_result();

        // Loop while interrupted (result 4)
    } while (waitResult == 4);

    // Wait failed (timeout or other error)
    result = IO_R_TIMEOUT;  // -703 (0xfffffd41)

    // Cleanup: clear watch mask and wake any other waiters
    self->watchStateMask = 0;
    thread_wakeup_prim(&self->watchStateMask, 0, 4);  // 0 = all threads, 4 = interrupted result

    return result;
}

/*
 * Identify UART chip type.
 * Returns the chip type constant (CHIP_8250, CHIP_16450, etc.)
 */
static unsigned int _identifyChip(ISASerialPort *self)
{
    unsigned char val, val2, val3;
    unsigned short port = self->basePort;

    // Enable DLAB to access divisor latch and scratch register
    OUTB(port + UART_LCR, LCR_DLAB);
    IODelay(1);

    // Test scratch register with 0x5A
    OUTB(port + UART_DLL, 0x5A);
    IODelay(1);
    val = INB(port + UART_DLL);

    if (val != 0x5A) {
        return CHIP_UNKNOWN;  // No UART detected
    }

    // Test scratch register with 0xA5
    OUTB(port + UART_DLL, 0xA5);
    IODelay(1);
    val = INB(port + UART_DLL);

    if (val != 0xA5) {
        return CHIP_UNKNOWN;  // No UART detected
    }

    // Disable DLAB
    OUTB(port + UART_LCR, 0);
    IODelay(1);

    // Test scratch register at offset 7 with 0x5A
    OUTB(port + UART_SCR, 0x5A);
    IODelay(1);
    val = INB(port + UART_SCR);

    if (val != 0x5A) {
        return CHIP_8250;  // 8250 - no scratch register
    }

    // Test scratch register at offset 7 with 0xA5
    OUTB(port + UART_SCR, 0xA5);
    IODelay(1);
    val = INB(port + UART_SCR);

    if (val != 0xA5) {
        return CHIP_8250;  // 8250 - no scratch register
    }

    // Test FIFO Control Register
    OUTB(port + UART_FCR, FCR_FIFO_ENABLE | FCR_RCVR_RESET | FCR_XMIT_RESET);
    IODelay(1);

    val = INB(port + UART_IIR);
    val2 = val & 0xC0;  // Check FIFO enabled bits

    // Disable FIFO
    OUTB(port + UART_FCR, 0);
    IODelay(1);

    if (val2 == 0x00) {
        // No FIFO - could be 16450, 16550 (broken FIFO), or 16650

        // Test for 16950 (extended FIFO trigger levels)
        OUTB(port + UART_FCR, 0x60);
        IODelay(1);
        val = INB(port + UART_IIR);
        OUTB(port + UART_FCR, 0);
        IODelay(1);

        if ((val & 0x60) == 0x60) {
            return CHIP_16950;  // 16950
        }

        // Test for 16650 (EFR register)
        OUTB(port + UART_MCR, 0x80);
        IODelay(1);
        val = INB(port + UART_MCR);
        OUTB(port + UART_MCR, 0);
        IODelay(1);

        if ((val & 0x80) == 0x80) {
            return CHIP_16550;  // 16550 with broken FIFO
        }

        return CHIP_16450;  // 16450 - no FIFO
    }
    else if (val2 == 0x40) {
        // FIFO enabled but not working properly
        return CHIP_UNKNOWN_FIFO;
    }
    else if (val2 == 0x80) {
        // FIFO working - could be 16550A, 16650, or 16750

        // Test for 16750 (64-byte FIFO)
        OUTB(port + UART_LCR, 0);
        IODelay(1);
        OUTB(port + UART_SCR, 0xDE);
        IODelay(1);
        OUTB(port + UART_LCR, LCR_DLAB);
        IODelay(1);
        OUTB(port + UART_SCR, 0xA9);
        IODelay(1);

        val = INB(port + UART_SCR);
        OUTB(port + UART_LCR, 0);
        IODelay(1);
        val2 = INB(port + UART_SCR);

        if (val2 == 0xDE && val == 0xA9) {
            return CHIP_16750;  // 16750
        }

        // Test for 16650 (sleep mode support)
        val = INB(port + UART_MCR);
        OUTB(port + UART_MCR, 0);
        IODelay(1);

        if ((val & 0x80) == 0x80) {
            return CHIP_16650;  // 16650
        }

        return CHIP_16550A;  // 16550A
    }

    return CHIP_16550A;  // Default to 16550A if we got here
}

/*
 * Initialize UART chip with default settings.
 * Sets up 8N1 (8 data bits, no parity, 1 stop bit) at 19200 baud.
 */
static IOReturn _initChip(ISASerialPort *self)
{
    // Set default serial port parameters
    self->dataBits = 16;          // 8 data bits (encoded as 16)
    self->stopBits = 2;           // 1 stop bit (encoded as 2)
    self->parity = PARITY_NONE;   // No parity
    self->flowControl = 0;        // No flow control
    self->baudRate = 19200;       // 19200 baud (0x4b00)
    self->divisor = 0;            // Will be calculated by _programChip
    self->fcrValue = 0;           // FIFO control value

    // Only initialize if we detected a valid chip
    if (self->chipType != CHIP_UNKNOWN) {
        // Reset Line Control Register
        OUTB(self->basePort + UART_LCR, 0);
        IODelay(1);

        // Disable all interrupts
        OUTB(self->basePort + UART_IER, 0);
        IODelay(1);

        // Reset Modem Control Register
        OUTB(self->basePort + UART_MCR, 0);
        IODelay(1);

        // Program the chip with default settings
        _programChip(self);
    }

    return IO_R_SUCCESS;
}

/*
 * Program UART chip with current settings.
 * Configures data bits, stop bits, parity, baud rate, and FIFO.
 */
static IOReturn _programChip(ISASerialPort *self)
{
    unsigned char lcr = 0;
    unsigned short newDivisor;
    int totalBits;
    int charTime;
    int triggerLevel;

    // Validate and normalize data bits (must be 10, 12, 14, or 16)
    if (self->dataBits < 10) {
        self->dataBits = 10;
    } else if (self->dataBits > 16) {
        self->dataBits = 16;
    }
    self->dataBits &= 0xFFFFFFFE;  // Make even

    // Set data bits in LCR and RX FIFO mask
    switch (self->dataBits) {
        case 10:  // 5 data bits
            lcr = 0;
            self->rxFIFOMask = 0x1F;  // 31 bytes
            break;
        case 12:  // 6 data bits
            lcr = 1;
            self->rxFIFOMask = 0x3F;  // 63 bytes
            break;
        case 14:  // 7 data bits
            lcr = 2;
            self->rxFIFOMask = 0x7F;  // 127 bytes
            break;
        case 16:  // 8 data bits
            lcr = 3;
            self->rxFIFOMask = 0xFF;  // 255 bytes
            break;
    }

    // Set stop bits in LCR
    if (self->stopBits < 3) {
        self->stopBits = 2;  // 1 stop bit
    } else {
        lcr |= 0x04;  // Set bit 2 for 2 stop bits
        if (self->dataBits == 10) {
            self->stopBits = 3;  // 1.5 stop bits for 5 data bits
        } else {
            self->stopBits = 4;  // 2 stop bits for 6-8 data bits
        }
    }

    // Set parity in LCR
    switch (self->parity) {
        case PARITY_ODD:
            lcr |= 0x08;  // Enable parity, odd
            break;
        case PARITY_EVEN:
            lcr |= 0x18;  // Enable parity, even
            break;
        case PARITY_MARK:
            lcr |= 0x28;  // Enable parity, mark (stick 1)
            break;
        case PARITY_SPACE:
            lcr |= 0x38;  // Enable parity, space (stick 0)
            break;
    }

    // Set break enable if flag is set
    if (self->flags & 0x08) {
        lcr |= 0x40;
    }

    // Validate baud rate against chip capabilities
    if (self->chipType < (sizeof(chipCapTable) / sizeof(ChipCapabilities))) {
        if (self->baudRate > chipCapTable[self->chipType].maxBaudRate) {
            self->baudRate = chipCapTable[self->chipType].maxBaudRate;
        }
    }
    if (self->baudRate < 100) {
        self->baudRate = 100;
    }

    // Calculate baud rate divisor
    newDivisor = (unsigned short)(self->clockRate / (self->baudRate * 8));

    // Only reprogram if divisor changed
    if (self->divisor != newDivisor) {
        // Calculate character time in nanoseconds
        totalBits = self->dataBits + self->stopBits;
        if (self->parity != PARITY_NONE) {
            totalBits += 2;  // Add parity bit
        } else {
            totalBits += 4;  // Add extra for timing
        }

        // Character time = (totalBits * 1000000000) / baudRate
        charTime = (1000000000 / self->baudRate) * totalBits;
        self->charTimeNS = charTime / 1000000000;
        self->charTimeFracNS = charTime % 1000000000;

        // Set DLAB to access divisor registers
        OUTB(self->basePort + UART_LCR, lcr | LCR_DLAB);
        IODelay(1);

        self->divisor = newDivisor;

        // Program divisor latch
        OUTB(self->basePort + UART_DLL, (unsigned char)self->divisor);
        IODelay(1);
        OUTB(self->basePort + UART_DLM, (unsigned char)(self->divisor >> 8));
        IODelay(1);

        // Program FIFO based on chip type
        switch (self->chipType) {
            case CHIP_UNKNOWN_FIFO:
            case CHIP_16550:
                // These chips have broken FIFOs, disable them
                self->fcrValue = 0;
                OUTB(self->basePort + UART_FCR, 0);
                IODelay(1);
                break;

            case CHIP_16550A:
            case CHIP_16650:
                if (self->forceFIFODisable) {
                    self->fcrValue = FCR_FIFO_ENABLE;
                } else {
                    // Calculate optimal FIFO trigger level
                    // Time for 16 chars at current baud rate
                    triggerLevel = (charTime * -3 + 10000000) / charTime;

                    // Adjust trigger to give at least 2ms margin
                    while ((17 - triggerLevel) * charTime < 2000000 && triggerLevel > 0) {
                        triggerLevel--;
                    }

                    if (triggerLevel < 4) {
                        self->fcrValue = FCR_FIFO_ENABLE;  // 1 byte trigger
                    } else if (triggerLevel < 8) {
                        self->fcrValue = FCR_FIFO_ENABLE | FCR_TRIGGER_4;  // 4 byte trigger
                    } else {
                        self->fcrValue = FCR_FIFO_ENABLE | FCR_TRIGGER_8;  // 8 byte trigger
                    }
                }
                OUTB(self->basePort + UART_FCR, self->fcrValue);
                IODelay(1);
                break;

            case CHIP_16750:
                if (self->forceFIFODisable) {
                    self->fcrValue = 0;
                } else {
                    // Calculate optimal FIFO trigger level for 64-byte FIFO
                    triggerLevel = (charTime * -3 + 10000000) / charTime;

                    while ((17 - triggerLevel) * charTime < 2000000 && triggerLevel > 0) {
                        triggerLevel--;
                    }

                    if (triggerLevel < 0 && self->baudRate < 19200) {
                        self->fcrValue = 0;  // Disable FIFO for very slow speeds
                    } else if (triggerLevel < 16) {
                        self->fcrValue = FCR_FIFO_ENABLE;  // 1 byte trigger
                    } else if (triggerLevel < 24) {
                        self->fcrValue = FCR_FIFO_ENABLE | FCR_TRIGGER_4;  // 16 byte trigger
                    } else {
                        self->fcrValue = FCR_FIFO_ENABLE | FCR_TRIGGER_8;  // 32 byte trigger
                    }
                }
                OUTB(self->basePort + UART_FCR, self->fcrValue);
                IODelay(1);
                break;

            default:
                // No FIFO support
                self->fcrValue = 0;
                break;
        }
    }

    // Clear DLAB and set final LCR value
    OUTB(self->basePort + UART_LCR, lcr);
    IODelay(1);

    self->lcrValue = lcr;

    return IO_R_SUCCESS;
}

/*
 * Handle PCMCIA card removal.
 * Called when the PCMCIA card is hot-removed from the system.
 */
static void _PCMCIA_yanked(ISASerialPort *self)
{
    // Set flag indicating card was removed
    self->pcmciaYanked = 1;

    // Deactivate the port to prevent further access
    _deactivatePort(self);
}

/*
 * Activate the serial port.
 * Allocates ring buffers, programs the UART, enables interrupts, and sets up initial state.
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD42 on failure (unable to allocate buffers)
 */
static IOReturn _activatePort(ISASerialPort *self)
{
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned int txState, rxState;
    unsigned int eventMask;

    // Check if already active (statusFlags bit 0x40)
    if ((self->statusFlags & 0x40) != 0) {
        // Already active
        return IO_R_SUCCESS;
    }

    // Check if PCMCIA card has been removed
    if (self->pcmciaYanked != 0) {
        return 0xFFFFFD42; // Error: device not available
    }

    // Allocate TX ring buffer (at offset 0x50)
    if (_allocateRingBuffer((char *)self + 0x50, self) == 0) {
        return 0xFFFFFD42; // Allocation failed
    }

    // Allocate RX ring buffer (at offset 0x18)
    if (_allocateRingBuffer((char *)self + 0x18, self) == 0) {
        // Free TX buffer and fail
        _freeRingBuffer((char *)self + 0x50);
        return 0xFFFFFD42; // Allocation failed
    }

    // Clear statistics counters
    self->interruptCount = 0;       // offset 0x118
    self->thrEmptyIntCount = 0;     // offset 0x11c
    self->dataReadyIntCount = 0;    // offset 0x120
    self->msrIntCount = 0;          // offset 0x124
    self->bytesTransmitted = 0;     // offset 0x128
    self->bytesReceived = 0;        // offset 0x12c

    // Program the UART chip with current settings
    _programChip(self);

    // If chip has FIFO (chipType > CHIP_16550), reset FIFO
    if (self->chipType > CHIP_16550) {
        // Write FCR with reset bits (0x06 = RCVR_RESET | XMIT_RESET)
        outb(self->basePort + UART_FCR, self->fcrValue | 0x06);
        // Atomic increment of statistics counter (LOCK/UNLOCK omitted)
    }

    // Set STATE_ACTIVE flag (0x40000000)
    oldState = self->currentState;
    newState = oldState | STATE_ACTIVE;
    changedBits = oldState ^ newState;
    self->currentState = newState;

    // Wake up any threads waiting on state changes
    if (self->watchStateMask & changedBits) {
        thread_wakeup_prim(&self->watchStateMask, 0, 4);
    }

    // Update DTR/RTS hardware signals if they changed
    if (changedBits & STATE_FLOW_MASK) {
        mcrValue = MCR_OUT2;
        if (oldState & STATE_DTR) {
            mcrValue |= MCR_DTR;
        }
        if (oldState & STATE_RTS) {
            mcrValue |= MCR_RTS;
        }
        outb(self->basePort + UART_MCR, mcrValue);
        // Atomic increment of statistics counter
    }

    // Trigger timer callout if not paused
    if ((self->statusFlags & 0x10) == 0) {
        thread_call_enter(self->timerCallout);
    }

    // Enqueue state change event if watched
    memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                           (oldState & 0xFFFF) | (changedBits << 16));
    }

    // Recalculate flow control state
    unsigned int flowState = _flowMachine(self);

    // Update state with flow control bits
    oldState = self->currentState;
    newState = (oldState & 0xFFFFFFE9) | (flowState & 0x16);
    changedBits = oldState ^ newState;
    self->currentState = newState;

    // Wake up threads if state changed
    if (self->watchStateMask & changedBits) {
        thread_wakeup_prim(&self->watchStateMask, 0, 4);
    }

    // Update DTR/RTS if they changed
    if (changedBits & STATE_FLOW_MASK) {
        mcrValue = MCR_OUT2;
        if (flowState & STATE_DTR) {
            mcrValue |= MCR_DTR;
        }
        if (flowState & STATE_RTS) {
            mcrValue |= MCR_RTS;
        }
        outb(self->basePort + UART_MCR, mcrValue);
        // Atomic increment
    }

    // Trigger timer callout
    if ((self->statusFlags & 0x10) == 0) {
        thread_call_enter(self->timerCallout);
    }

    // Enqueue flow control state change event
    memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                           (oldState & 0xFFE9) | (flowState & 0x16) | (changedBits << 16));
    }

    // Calculate initial TX queue state based on current usage
    if (self->txQueueMedWater < self->txQueueUsed) {
        // Used > medWater
        if (self->txQueueLowWater < self->txQueueUsed) {
            // Used > lowWater (above high watermark)
            self->txQueueHighWater = self->txQueueCapacity - 3;
            if (self->txQueueCapacity - 3 < self->txQueueUsed) {
                // Critical level
                self->txQueueTarget = self->txQueueCapacity;
                txState = 0x1800000;
            } else {
                // Above high
                self->txQueueTarget = self->txQueueLowWater;
                txState = 0x1000000;
            }
        } else {
            // medWater < used <= lowWater
            self->txQueueHighWater = self->txQueueLowWater;
            self->txQueueTarget = self->txQueueMedWater;
            txState = 0;
        }
    } else {
        // Used <= medWater
        self->txQueueTarget = 0;
        if (self->txQueueUsed == 0) {
            // Empty
            self->txQueueHighWater = 0;
            txState = TX_STATE_EMPTY;
        } else {
            // Below low watermark
            self->txQueueHighWater = self->txQueueMedWater;
            txState = TX_STATE_BELOW_LOW;
        }
    }

    // Calculate initial RX queue state based on current usage
    rxState = self->currentState & 0x17E;

    if (self->rxQueueUsed < self->rxQueueLowWater) {
        // Below low watermark
        self->rxQueueWatermark = 0;
        if (self->rxQueueUsed == 0) {
            // Empty
            rxState |= RX_STATE_EMPTY;
            self->rxQueueTarget = 0;
        } else {
            // Below low watermark but not empty
            rxState |= RX_STATE_BELOW_LOW;
            self->rxQueueTarget = self->rxQueueLowWater;
        }

        // Enable flow control (ready to receive)
        if ((self->flowControlMode & FLOW_RTS_ENABLED) == 0) {
            if ((self->flowControlMode & FLOW_HW_ENABLED) == 0) {
                if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                    rxState |= STATE_DTR;
                }
            } else {
                rxState |= STATE_RTS;
                if (self->flowControlState == -1) {
                    self->flowControlState = 2;
                } else if (self->flowControlState == 1) {
                    self->flowControlState = -2;
                }
            }
        } else {
            rxState |= STATE_RTS;
        }

    } else if (self->rxQueueHighWater < self->rxQueueUsed) {
        // Above high watermark
        self->rxQueueTarget = self->rxQueueCapacity - 3;
        if (self->rxQueueCapacity - 3 < self->rxQueueUsed) {
            // Critical
            rxState |= RX_STATE_CRITICAL;
            self->rxQueueWatermark = self->rxQueueCapacity;
        } else {
            // Above high
            rxState |= RX_STATE_ABOVE_HIGH;
            self->rxQueueWatermark = self->rxQueueHighWater;
        }

        // Disable flow control (apply back pressure)
        if ((self->flowControlMode & FLOW_RTS_ENABLED) == 0) {
            if ((self->flowControlMode & FLOW_HW_ENABLED) == 0) {
                if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                    rxState &= ~STATE_DTR;
                }
            } else {
                rxState &= ~STATE_RTS;
                if ((self->flowControlState == -2) || (self->flowControlState == 0)) {
                    self->flowControlState = 1;
                } else if (self->flowControlState == 2) {
                    self->flowControlState = -1;
                }
            }
        } else {
            rxState &= ~STATE_RTS;
        }

    } else {
        // Between low and high watermarks
        self->rxQueueTarget = self->rxQueueHighWater;
        self->rxQueueWatermark = self->rxQueueLowWater;
    }

    // Combine TX and RX states and update currentState
    oldState = self->currentState;
    newState = (oldState & 0xF870FFE9) | txState | (rxState & 0x78F0016);
    changedBits = oldState ^ newState;
    self->currentState = newState;

    // Wake up threads
    if (self->watchStateMask & changedBits) {
        thread_wakeup_prim(&self->watchStateMask, 0, 4);
    }

    // Update DTR/RTS
    if (changedBits & STATE_FLOW_MASK) {
        mcrValue = MCR_OUT2;
        if (rxState & STATE_DTR) {
            mcrValue |= MCR_DTR;
        }
        if (rxState & STATE_RTS) {
            mcrValue |= MCR_RTS;
        }
        outb(self->basePort + UART_MCR, mcrValue);
        // Atomic increment
    }

    // Trigger timer callout
    if ((self->statusFlags & 0x10) == 0) {
        thread_call_enter(self->timerCallout);
    }

    // Enqueue state change event
    memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                           (newState & 0xFFFF) | (changedBits << 16));
    }

    // Final timer callout trigger
    if ((self->statusFlags & 0x10) == 0) {
        thread_call_enter(self->timerCallout);
    }

    // Enable UART interrupts (write lower 4 bits of ierValue)
    outb(self->basePort + UART_IER, self->ierValue & 0x0F);
    // Atomic increment

    return IO_R_SUCCESS;
}

/*
 * Deactivate the serial port.
 * Shuts down the UART, disables interrupts, frees ring buffers, and updates state.
 */
static IOReturn _deactivatePort(ISASerialPort *self)
{
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;

    // Only deactivate if port is currently active (bit 0x40 in statusFlags)
    if ((self->statusFlags & 0x40) == 0) {
        return IO_R_SUCCESS;
    }

    // Disable most UART interrupts (keep only bit 3 if set)
    outb(self->basePort + UART_IER, self->ierValue & 0x08);

    // Update some statistics or state counter (exact purpose unclear from decompilation)
    // This appears to be an atomic increment of a global counter
    // LOCK/UNLOCK pattern omitted for simplicity

    // Clear STATE_ACTIVE bit (0x40000000) from current state
    oldState = self->currentState;
    newState = oldState & ~STATE_ACTIVE;
    changedBits = oldState ^ newState;
    self->currentState = newState;

    // Wake up any threads waiting on state changes
    if (self->watchStateMask & changedBits) {
        thread_wakeup_prim(&self->watchStateMask, 0, 4);
    }

    // Update DTR/RTS signals in MCR if they changed
    if (changedBits & STATE_FLOW_MASK) {
        mcrValue = MCR_OUT2; // Start with OUT2 (interrupt enable)
        if (newState & STATE_DTR) {
            mcrValue |= MCR_DTR;
        }
        if (newState & STATE_RTS) {
            mcrValue |= MCR_RTS;
        }
        outb(self->basePort + UART_MCR, mcrValue);
    }

    // Trigger timer callout if not paused (statusFlags bit 0x10)
    if ((self->statusFlags & 0x10) == 0) {
        thread_call_enter(self->timerCallout);
    }

    // Enqueue state change event if any watched state bits changed
    // Read stateEventMask as part of uint at offset 0xe0
    unsigned int eventMask;
    memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                           (newState & 0xFFFF) | (changedBits << 16));
    }

    // Free both TX and RX ring buffers
    _freeRingBuffer((char *)self + 0x50); // TX queue at offset 0x50
    _freeRingBuffer((char *)self + 0x18); // RX queue at offset 0x18

    // Recalculate flow control state
    unsigned int flowState = _flowMachine(self);

    // Update state, keeping only specific bits from flow control and clearing others
    oldState = self->currentState;
    newState = (oldState & 0xFFFFFFE9) | (flowState & 0x16);
    changedBits = oldState ^ newState;
    self->currentState = newState;

    // Wake up any threads waiting on state changes
    if (self->watchStateMask & changedBits) {
        thread_wakeup_prim(&self->watchStateMask, 0, 4);
    }

    // Update DTR/RTS signals if they changed
    if (changedBits & STATE_FLOW_MASK) {
        mcrValue = MCR_OUT2;
        if (flowState & STATE_DTR) {
            mcrValue |= MCR_DTR;
        }
        if (flowState & STATE_RTS) {
            mcrValue |= MCR_RTS;
        }
        outb(self->basePort + UART_MCR, mcrValue);
    }

    // Trigger timer callout again if not paused
    if ((self->statusFlags & 0x10) == 0) {
        thread_call_enter(self->timerCallout);
    }

    // Enqueue state change event for flow control changes if watched
    memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                           (newState & 0xFFFF) | (changedBits << 16));
    }

    return IO_R_SUCCESS;
}

/*
 * Allocate ring buffer.
 * Allocates memory for a ring buffer (RX or TX) with proper alignment.
 *
 * Parameters:
 *   queueBase - Pointer to the base of queue structure (either &rxQueueCapacity or &txQueueCapacity)
 *   self - Pointer to ISASerialPort instance (for accessing defaultRingBufferSize)
 *
 * Returns:
 *   IO_R_SUCCESS (1) on success, 0 on failure
 *
 * Queue structure layout (relative to queueBase):
 * +0x00: capacity (uint) - requested size, will be validated
 * +0x04: used (uint)
 * +0x08-0x10: watermarks
 * +0x18: start (void*) - aligned start pointer
 * +0x1c: end (void*) - end of buffer
 * +0x20: write (void*)
 * +0x24: read (void*)
 * +0x30: allocStart (void*) - raw allocated pointer (for freeing)
 */
static IOReturn _allocateRingBuffer(void *queueBase, ISASerialPort *self)
{
    unsigned int *capacity = (unsigned int *)queueBase;
    unsigned int *used = (unsigned int *)((char *)queueBase + 0x04);
    void **allocStart = (void **)((char *)queueBase + 0x30);
    void **start = (void **)((char *)queueBase + 0x18);
    void **end = (void **)((char *)queueBase + 0x1c);
    void **write = (void **)((char *)queueBase + 0x20);
    void **read = (void **)((char *)queueBase + 0x24);
    unsigned int *watermarkTarget = (unsigned int *)((char *)queueBase + 0x0c);
    unsigned int validatedSize;
    unsigned int allocSize;
    void *buffer;

    // First free any existing buffer
    _freeRingBuffer(queueBase);

    // Validate the requested size
    validatedSize = _validateRingBufferSize(*capacity, self);
    *capacity = validatedSize;

    // Calculate allocation size: capacity * 2 bytes per entry + 2 for alignment
    allocSize = (validatedSize * 2) + 2;

    // Store allocation size at offset 0x30 (temporarily, will be overwritten with pointer)
    *allocStart = (void *)allocSize;

    // Allocate memory
    buffer = IOMalloc(allocSize);
    *allocStart = buffer;

    if (buffer == NULL) {
        // Allocation failed
        return 0;
    }

    // Align start pointer to even address if needed
    if (((unsigned int)buffer & 1) == 0) {
        // Already aligned
        *start = buffer;
    } else {
        // Not aligned, advance by 1 byte
        *start = (void *)((char *)buffer + 1);
    }

    // Calculate end pointer (capacity * 2 bytes from aligned start)
    *end = (void *)((char *)*start + (validatedSize * 2));

    // Initialize read and write pointers to start
    *write = *start;
    *read = *start;

    // Clear overflow flag (at offset 0x28 from queueBase)
    *((unsigned int *)((char *)queueBase + 0x28)) = 0;

    // Clear used count
    *used = 0;

    // Set target watermark to low watermark (at offset 0x0c)
    // Low watermark is at offset 0x08
    *watermarkTarget = *((unsigned int *)((char *)queueBase + 0x08));

    // Set current watermark (at offset 0x14) to zero
    *((unsigned int *)((char *)queueBase + 0x14)) = 0;

    return IO_R_SUCCESS;
}

/*
 * RX dequeue event.
 * Dequeues variable-length events from the receive queue.
 * param sleep: If TRUE, wait for event; if FALSE, return immediately if empty
 */
static IOReturn _RX_dequeueEvent(ISASerialPort *self, unsigned char *eventType, unsigned int *eventData, BOOL sleep)
{
    unsigned short *readPtr;
    unsigned short firstWord, dataWord;
    unsigned int eventLen;
    unsigned int newState, oldState, changedBits;
    unsigned char mcrValue;
    unsigned int watchMask;
    IOReturn result;

    while (1) {
        // Check if queue has data
        if (self->rxQueueUsed != 0) {
            // Read first word (contains event type and possibly first data byte)
            readPtr = (unsigned short *)self->rxQueueRead;
            firstWord = *readPtr++;
            if ((void *)readPtr >= self->rxQueueEnd) {
                readPtr = (unsigned short *)self->rxQueueStart;
            }
            self->rxQueueRead = readPtr;
            self->rxQueueUsed--;

            // Extract event type (low byte)
            *eventType = (unsigned char)firstWord;
            eventLen = firstWord & 3;  // Length encoded in low 2 bits

            // Parse variable-length event data
            if (eventLen == 1) {
                // 1-word event: data in high byte of first word
                *eventData = (unsigned int)(firstWord >> 8);
            } else if (eventLen == 0) {
                // 0-word event: no data
                *eventData = 0;
            } else if (eventLen == 2) {
                // 2-word event: read second word
                dataWord = *readPtr++;
                if ((void *)readPtr >= self->rxQueueEnd) {
                    readPtr = (unsigned short *)self->rxQueueStart;
                }
                self->rxQueueRead = readPtr;
                self->rxQueueUsed--;
                *eventData = (unsigned int)dataWord;
            } else if (eventLen == 3) {
                // 3-word event: read second and third words
                dataWord = *readPtr++;
                if ((void *)readPtr >= self->rxQueueEnd) {
                    readPtr = (unsigned short *)self->rxQueueStart;
                }
                self->rxQueueRead = readPtr;
                self->rxQueueUsed--;
                *eventData = (unsigned int)dataWord;

                dataWord = *readPtr++;
                if ((void *)readPtr >= self->rxQueueEnd) {
                    readPtr = (unsigned short *)self->rxQueueStart;
                }
                self->rxQueueRead = readPtr;
                self->rxQueueUsed--;
                *eventData |= ((unsigned int)dataWord) << 16;
            }

            // Handle overflow condition
            if (self->rxQueueOverflow != 0) {
                self->rxQueueOverflow = 0;
                // Enqueue overflow marker
                unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                *writePtr++ = EVENT_OVERFLOW;
                if ((void *)writePtr >= self->rxQueueEnd) {
                    writePtr = (unsigned short *)self->rxQueueStart;
                }
                self->rxQueueWrite = writePtr;
                self->rxQueueUsed++;
            }

            // Update RX watermark state if queue level dropped below watermark
            if (self->rxQueueUsed <= self->rxQueueWatermark) {
                // Determine new RX state based on queue level
                newState = self->currentState & 0x0000017E;  // Preserve certain bits

                if (self->rxQueueUsed < self->rxQueueLowWater) {
                    // Below low watermark
                    self->rxQueueWatermark = 0;
                    if (self->rxQueueUsed == 0) {
                        // Queue empty
                        newState |= RX_STATE_EMPTY;
                        self->rxQueueTarget = 0;
                    } else {
                        // Below low watermark but not empty
                        newState |= RX_STATE_BELOW_LOW;
                        self->rxQueueTarget = self->rxQueueLowWater;
                    }

                    // Handle flow control - assert RTS/DTR when queue drains
                    if ((self->flowControlMode & FLOW_RTS_ENABLED) == 0) {
                        if ((self->flowControlMode & FLOW_HW_ENABLED) == 0) {
                            if (self->flowControlMode & FLOW_DTR_ENABLED) {
                                newState |= STATE_DTR;
                            }
                        } else {
                            newState |= STATE_RTS;
                            // Update flow control state machine
                            if (self->flowControlState == -1) {
                                self->flowControlState = 2;
                            } else if (self->flowControlState == 1) {
                                self->flowControlState = -2;
                            }
                        }
                    } else {
                        newState |= STATE_RTS;
                    }
                } else if (self->rxQueueUsed > self->rxQueueHighWater) {
                    // Above high watermark
                    self->rxQueueTarget = self->rxQueueCapacity - 3;
                    if (self->rxQueueUsed > (self->rxQueueCapacity - 3)) {
                        // Critical level
                        newState |= RX_STATE_CRITICAL;
                        self->rxQueueWatermark = self->rxQueueCapacity;
                    } else {
                        // Above high watermark
                        newState |= RX_STATE_ABOVE_HIGH;
                        self->rxQueueWatermark = self->rxQueueHighWater;
                    }

                    // Handle flow control - deassert RTS/DTR when queue fills
                    if ((self->flowControlMode & FLOW_RTS_ENABLED) == 0) {
                        if ((self->flowControlMode & FLOW_HW_ENABLED) == 0) {
                            if (self->flowControlMode & FLOW_DTR_ENABLED) {
                                newState &= ~STATE_DTR;
                            }
                        } else {
                            newState &= ~STATE_RTS;
                            // Update flow control state machine
                            if (self->flowControlState == -2 || self->flowControlState == 0) {
                                self->flowControlState = 1;
                            } else if (self->flowControlState == 2) {
                                self->flowControlState = -1;
                            }
                        }
                    } else {
                        newState &= ~STATE_RTS;
                    }
                } else {
                    // Between watermarks
                    self->rxQueueTarget = self->rxQueueHighWater;
                    self->rxQueueWatermark = self->rxQueueLowWater;
                }

                // Update state and detect changes
                oldState = self->currentState;
                newState = (oldState & 0xFFF0FE81) | newState;  // Preserve high bits and certain low bits
                changedBits = newState ^ oldState;
                self->currentState = newState;

                // Wake threads waiting on state changes
                if (self->watchStateMask & changedBits) {
                    thread_wakeup_prim(&self->watchStateMask, 0, 4);
                }

                // Update hardware modem control if DTR/RTS changed
                if (changedBits & STATE_FLOW_MASK) {
                    mcrValue = MCR_OUT2;  // Always keep OUT2 set
                    if (newState & STATE_DTR) {
                        mcrValue |= MCR_DTR;
                    }
                    if (newState & STATE_RTS) {
                        mcrValue |= MCR_RTS;
                    }
                    OUTB(self->basePort + UART_MCR, mcrValue);
                    IODelay(1);
                }

                // Schedule timer callback if not already pending
                if ((self->statusFlags & 0x10) == 0) {
                    thread_call_enter(self->timerCallout);
                }

                // Notify of state change if mask matches
                if (self->flowControlMode & (changedBits << 16)) {
                    _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE, (newState & 0xFFFF) | (changedBits << 16));
                }
            }

            return IO_R_SUCCESS;
        }

        // Queue is empty
        if (!sleep) {
            // Don't wait - return with event type 0
            *eventType = 0;
            return IO_R_SUCCESS;
        }

        // Wait for RX data
        watchMask = 0;
        result = _watchState(self, &watchMask, STATE_RX_ENABLED);
        if (result != IO_R_SUCCESS) {
            return result;
        }
    }
}

/*
 * RX enqueue long event (3-word event: type + data low + data high).
 * Used for state change events and other long data events.
 */
static IOReturn _RX_enqueueLongEvent(ISASerialPort *self, unsigned int event, unsigned int data)
{
    unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
    unsigned int spaceAvailable = self->rxQueueCapacity - self->rxQueueUsed;

    // Check if we have space for 3 entries
    if (spaceAvailable < 3) {
        // Not enough space for long event
        if (self->rxQueueUsed < self->rxQueueCapacity) {
            // Queue not full - enqueue overflow marker
            *writePtr++ = EVENT_OVERFLOW;
            if ((void *)writePtr >= self->rxQueueEnd) {
                writePtr = (unsigned short *)self->rxQueueStart;
            }
            self->rxQueueWrite = writePtr;
            self->rxQueueUsed++;
        } else {
            // Queue completely full - set overflow flag
            self->rxQueueOverflow = 1;
        }
        return IO_R_SUCCESS;
    }

    // Enqueue event type
    *writePtr++ = (unsigned short)event;
    if ((void *)writePtr >= self->rxQueueEnd) {
        writePtr = (unsigned short *)self->rxQueueStart;
    }
    self->rxQueueWrite = writePtr;
    self->rxQueueUsed++;

    // Enqueue data low word
    *writePtr++ = (unsigned short)data;
    if ((void *)writePtr >= self->rxQueueEnd) {
        writePtr = (unsigned short *)self->rxQueueStart;
    }
    self->rxQueueWrite = writePtr;
    self->rxQueueUsed++;

    // Enqueue data high word
    *writePtr++ = (unsigned short)(data >> 16);
    if ((void *)writePtr >= self->rxQueueEnd) {
        writePtr = (unsigned short *)self->rxQueueStart;
    }
    self->rxQueueWrite = writePtr;
    self->rxQueueUsed++;

    return IO_R_SUCCESS;
}

/*
 * TX enqueue event.
 * Enqueues data to transmit queue with variable length based on event type.
 * param event: Event type byte (low 2 bits indicate data length: 0=none, 1=1word, 2=2words, 3=3words)
 * param data: Event data (up to 4 bytes)
 * param sleep: If TRUE, wait for space; if FALSE, return error if no space
 */
static IOReturn _TX_enqueueEvent(ISASerialPort *self, unsigned int event, unsigned int data, BOOL sleep)
{
    unsigned short *writePtr;
    unsigned int spaceNeeded;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned int watchMask;
    IOReturn result;

    // If event is 0, return immediately
    if ((event & 0xFF) == 0) {
        return IO_R_SUCCESS;
    }

    do {
        // Calculate space needed based on event type (low 2 bits)
        spaceNeeded = 1 + (event & 3);  // 1-4 entries

        // Check if we have space (need at least 3 free for safety)
        if ((self->txQueueCapacity - self->txQueueUsed) > 2) {
            writePtr = (unsigned short *)self->txQueueWrite;

            // Write event type and first data byte
            *writePtr++ = (unsigned short)((event & 0xFF) | ((data & 0xFF) << 8));
            if ((void *)writePtr >= self->txQueueEnd) {
                writePtr = (unsigned short *)self->txQueueStart;
            }
            self->txQueueWrite = writePtr;
            self->txQueueUsed++;

            // Write additional words based on event type
            if ((event & 3) > 1) {
                // Write second word (bytes 1-2 of data)
                *writePtr++ = (unsigned short)(data >> 8);
                if ((void *)writePtr >= self->txQueueEnd) {
                    writePtr = (unsigned short *)self->txQueueStart;
                }
                self->txQueueWrite = writePtr;
                self->txQueueUsed++;

                if ((event & 3) == 3) {
                    // Write third word (bytes 2-3 of data)
                    *writePtr++ = (unsigned short)(data >> 16);
                    if ((void *)writePtr >= self->txQueueEnd) {
                        writePtr = (unsigned short *)self->txQueueStart;
                    }
                    self->txQueueWrite = writePtr;
                    self->txQueueUsed++;
                }
            }

            // Update TX queue watermark state
            if (self->txQueueUsed > self->txQueueHighWater) {
                // Above high watermark
                if (self->txQueueUsed > self->txQueueMedWater) {
                    if (self->txQueueUsed > self->txQueueLowWater) {
                        // Above all watermarks
                        self->txQueueHighWater = self->txQueueCapacity - 3;
                        if (self->txQueueUsed > (self->txQueueCapacity - 3)) {
                            self->txQueueTarget = self->txQueueCapacity;
                            newState = TX_STATE_ABOVE_HIGH;
                        } else {
                            self->txQueueTarget = self->txQueueLowWater;
                            newState = TX_STATE_BELOW_LOW;
                        }
                    } else {
                        // Between med and low watermarks
                        self->txQueueTarget = self->txQueueMedWater;
                        self->txQueueHighWater = self->txQueueLowWater;
                        newState = TX_STATE_BELOW_HIGH;
                    }
                } else {
                    // Below med watermark
                    self->txQueueTarget = 0;
                    if (self->txQueueUsed == 0) {
                        self->txQueueHighWater = 0;
                        newState = TX_STATE_EMPTY;
                    } else {
                        self->txQueueHighWater = self->txQueueMedWater;
                        newState = TX_STATE_BELOW_MED;
                    }
                }

                // Update state and wake waiting threads
                oldState = self->currentState;
                newState = (oldState & ~TX_STATE_MASK) | newState;
                changedBits = newState ^ oldState;
                self->currentState = newState;

                // Wake threads waiting on these state bits
                if (self->watchStateMask & changedBits) {
                    thread_wakeup_prim(&self->watchStateMask, 0, 4);
                }

                // Update hardware modem control signals if RTS/DTR changed
                if (changedBits & 0x06) {  // Bits 1-2 changed
                    mcrValue = MCR_OUT2;  // Always keep OUT2 set
                    if (oldState & 0x02) {  // DTR state
                        mcrValue |= MCR_DTR;
                    }
                    if (oldState & 0x04) {  // RTS state
                        mcrValue |= MCR_RTS;
                    }
                    OUTB(self->basePort + UART_MCR, mcrValue);
                    IODelay(1);
                }

                // Schedule timer callback if not already pending
                if ((self->statusFlags & 0x10) == 0) {
                    thread_call_enter(self->timerCallout);
                }

                // Notify RX queue of state change if mask matches
                if (self->stateChangeMask & (changedBits << 16)) {
                    _RX_enqueueLongEvent(self, 0x53, oldState | (changedBits << 16));
                }
            }

            return IO_R_SUCCESS;
        }

        // No space available
        if (!sleep) {
            return IO_R_NO_RESOURCES;  // -706 (0xfffffd3e -> -0x2c2 -> -706 decimal, but code shows -0x2be = -702)
        }

        // Wait for TX_ENABLED state change
        watchMask = 0;
        result = _watchState(self, &watchMask, STATE_TX_ENABLED);

    } while (result == IO_R_SUCCESS);

    return result;
}

/*
 * RX dequeue data byte.
 * Dequeues a single data byte from RX ring buffer.
 * Data is stored as 2-byte words: low byte = 'U' marker (0x55), high byte = actual data.
 * param byteOut: Pointer to store the dequeued byte
 * param sleep: If TRUE, wait for data; if FALSE, return error if no data
 * Returns: IO_R_SUCCESS on success, IO_R_OFFLINE if no data (and not sleeping)
 */
static IOReturn _RX_dequeueData(ISASerialPort *self, unsigned char *byteOut, BOOL sleep)
{
    unsigned short dataWord;
    unsigned short *readPtr;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned int watchMask;
    IOReturn result;

    do {
        // Check if RX queue has data
        if (self->rxQueueUsed != 0) {
            readPtr = (unsigned short *)self->rxQueueRead;

            // Verify marker byte (low byte should be 'U' = 0x55)
            if ((*(unsigned char *)readPtr) != 'U') {
                return IO_R_OFFLINE;  // -702 (-0x2be)
            }

            // Read 2-byte word from RX queue
            dataWord = *readPtr++;

            // Advance read pointer with wrapping
            if ((void *)readPtr >= self->rxQueueEnd) {
                readPtr = (unsigned short *)self->rxQueueStart;
            }
            self->rxQueueRead = readPtr;

            // Decrement used count
            self->rxQueueUsed--;

            // Extract high byte (actual data)
            *byteOut = (unsigned char)(dataWord >> 8);

            // Handle overflow recovery or normal watermark processing
            if (self->rxQueueOverflow == 0) {
                // Normal processing - update watermarks if at or below watermark
                if (self->rxQueueUsed <= self->rxQueueWatermark) {
                    // Build new state without RX state bits
                    newState = self->currentState & 0x17e;  // Keep only non-RX-state bits

                    // Check if below low watermark
                    if (self->rxQueueUsed < self->rxQueueLowWater) {
                        self->rxQueueWatermark = 0;

                        if (self->rxQueueUsed == 0) {
                            // Queue empty
                            newState |= RX_STATE_EMPTY;
                            self->rxQueueTarget = 0;
                        } else {
                            // Below low watermark
                            newState |= RX_STATE_BELOW_LOW;
                            self->rxQueueTarget = self->rxQueueLowWater;
                        }

                        // Update flow control - turn ON (assert signals when queue drains)
                        if ((self->flowControlMode & FLOW_RTS_ENABLED) != 0) {
                            newState |= STATE_RTS;
                        }
                        if ((self->flowControlMode & FLOW_HW_ENABLED) != 0) {
                            newState |= 0x10;  // Hardware flow control bit
                            // Update flow control state machine
                            if (self->flowControlState == -1) {
                                self->flowControlState = 2;
                            } else if (self->flowControlState == 1) {
                                self->flowControlState = -2;
                            }
                        }
                        if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                            newState |= STATE_DTR;
                        }
                    } else if (self->rxQueueUsed > self->rxQueueHighWater) {
                        // Above high watermark (need flow control)
                        self->rxQueueTarget = self->rxQueueCapacity - 3;

                        if (self->rxQueueUsed > (self->rxQueueCapacity - 3)) {
                            // Critical level
                            newState |= RX_STATE_CRITICAL;
                            self->rxQueueWatermark = self->rxQueueCapacity;
                        } else {
                            // Above high
                            newState |= RX_STATE_ABOVE_HIGH;
                            self->rxQueueWatermark = self->rxQueueHighWater;
                        }

                        // Update flow control - turn OFF (de-assert signals when queue fills)
                        if ((self->flowControlMode & FLOW_RTS_ENABLED) != 0) {
                            newState &= ~STATE_RTS;
                        }
                        if ((self->flowControlMode & FLOW_HW_ENABLED) != 0) {
                            newState &= ~0x10;
                            // Update flow control state machine
                            if (self->flowControlState == -2 || self->flowControlState == 0) {
                                self->flowControlState = 1;
                            } else if (self->flowControlState == 2) {
                                self->flowControlState = -1;
                            }
                        }
                        if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                            newState &= ~STATE_DTR;
                        }
                    } else {
                        // Between low and high watermarks
                        self->rxQueueTarget = self->rxQueueHighWater;
                        self->rxQueueWatermark = self->rxQueueLowWater;
                    }

                    // Update current state and calculate changed bits
                    oldState = self->currentState;
                    newState = (oldState & 0xfff0fe81) | newState;
                    changedBits = newState ^ oldState;
                    self->currentState = newState;

                    // Wake threads waiting on these state bits
                    if (self->watchStateMask & changedBits) {
                        thread_wakeup_prim(&self->watchStateMask, 0, 4);
                    }

                    // Update hardware modem control signals if DTR/RTS changed
                    if (changedBits & 0x06) {
                        mcrValue = MCR_OUT2;
                        if (newState & STATE_DTR) {
                            mcrValue |= MCR_DTR;
                        }
                        if (newState & STATE_RTS) {
                            mcrValue |= MCR_RTS;
                        }
                        OUTB(self->basePort + UART_MCR, mcrValue);
                        IOEnterCriticalSection();
                        // Increment some global counter (placeholder)
                        IOExitCriticalSection();
                    }

                    // Schedule timer callback if not already pending
                    if ((self->statusFlags & 0x10) == 0) {
                        thread_call_enter(self->timerCallout);
                    }

                    // Notify RX queue of state change if flow control mode matches
                    if ((self->flowControlMode & (changedBits >> 16)) != 0) {
                        _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                                           (newState & 0xFFFF) | (changedBits << 16));
                    }
                }
            } else {
                // Overflow recovery - re-enqueue overflow marker
                unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;

                self->rxQueueOverflow = 0;
                *writePtr++ = EVENT_OVERFLOW;

                // Advance write pointer with wrapping
                if ((void *)writePtr >= self->rxQueueEnd) {
                    writePtr = (unsigned short *)self->rxQueueStart;
                }
                self->rxQueueWrite = writePtr;
                self->rxQueueUsed++;
            }

            return IO_R_SUCCESS;
        }

        // No data available
        if (!sleep) {
            return IO_R_OFFLINE;  // -702
        }

        // Wait for RX data
        watchMask = 0;
        result = _watchState(self, &watchMask, STATE_RX_ENABLED);
        if (result != IO_R_SUCCESS) {
            return result;
        }
    } while (1);
}

/*
 * Heartbeat timeout handler.
 * Timer callback that polls the UART by calling the interrupt handler.
 * Used for chips without reliable interrupts or for periodic monitoring.
 */
static void _heartBeatTOHandler(ISASerialPort *self)
{
    unsigned int oldIRQL;
    extern unsigned int spl4(void);
    extern void splx(unsigned int);
    extern void thread_call_enter_delayed(void *call, unsigned long long deadline);
    extern unsigned long long deadline_from_interval(unsigned int interval_low, unsigned int interval_high);

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is active and not yanked
    if ((self->currentState & STATE_ACTIVE) && (self->pcmciaYanked == 0)) {
        // Call interrupt handler if heartbeat not already pending
        if (self->heartBeatPending == 0) {
            // Call appropriate interrupt handler based on FIFO capability
            if (self->hasFIFO) {
                // Call FIFO interrupt handler (stub for now)
                // _FIFOIntHandler(0, 0, self);
            } else {
                // Call non-FIFO interrupt handler (stub for now)
                // _NonFIFOIntHandler(0, 0, self);
            }
        }

        // Clear pending flag
        self->heartBeatPending = 0;

        // Schedule next heartbeat
        unsigned long long deadline = deadline_from_interval(
            (unsigned int)(self->heartBeatInterval & 0xFFFFFFFF),
            (unsigned int)(self->heartBeatInterval >> 32)
        );
        thread_call_enter_delayed(self->heartBeatCallout, deadline);
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Non-FIFO interrupt handler.
 * Handles all UART interrupts for 8250/16450 chips without FIFO.
 * This is called at interrupt level and must be fast.
 */
static void _NonFIFOIntHandler(void *identity, void *state, ISASerialPort *self)
{
    unsigned char lsr, msr, iir;
    unsigned char dataByte;
    unsigned char eventType;
    unsigned int eventData;
    unsigned int newState, changedBits;
    unsigned char mcrValue;
    BOOL continueLoop;
    unsigned char timerNeeded;
    unsigned short dataWord;
    unsigned short *readPtr;
    unsigned int stateChangeMask;

    // Initialize locals
    changedBits = 0;
    eventData = 0;
    eventType = 0;
    timerNeeded = self->timerPending;
    newState = self->currentState;

    // Read Line Status Register
    lsr = INB(self->basePort + UART_LSR);

    // Update interrupt statistics
    self->interruptCount++;
    if (lsr & 0x01) {  // Data Ready
        self->dataReadyIntCount++;
    }
    if (lsr & 0x20) {  // THR Empty
        self->thrEmptyIntCount++;
    }

    // Main interrupt processing loop
    do {
        continueLoop = FALSE;

        // Handle overrun error (LSR bit 1)
        if ((lsr & 0x02) && (newState & STATE_RX_ENABLED)) {
            if (self->rxQueueUsed < self->rxQueueCapacity) {
                // Enqueue overrun error event
                unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                *writePtr++ = EVENT_OVERRUN_ERROR;
                if ((void *)writePtr >= self->rxQueueEnd) {
                    writePtr = (unsigned short *)self->rxQueueStart;
                }
                self->rxQueueWrite = writePtr;
                self->rxQueueUsed++;
            } else {
                // Queue full - set overflow flag
                self->rxQueueOverflow = 1;
            }
        }

        // Handle data ready (LSR bit 0)
        if (lsr & 0x01) {
            // Read data byte from RBR
            dataByte = INB(self->basePort + UART_RBR);
            eventData = (unsigned int)dataByte;

            // Check for PCMCIA card removal (all 1's)
            if ((lsr == 0xFF) && (dataByte == 0xFF) && (self->pcmciaDetect != 0)) {
                _PCMCIA_yanked(self);
                return;
            }

            // Process received data if RX enabled
            if (newState & STATE_RX_ENABLED) {
                self->bytesReceived++;

                unsigned char errorBits = lsr & 0x1C;  // Parity, Framing, Break errors

                if (errorBits == 0x04) {
                    // Parity error - check for software flow control character
                    if (self->flowControl == 6) {  // Software flow control mode
                        // Mask data with RX FIFO mask
                        eventData = dataByte & self->rxFIFOMask;
                        goto process_flow_control_char;
                    }

                    // Enqueue parity error with data
                    if (self->rxQueueUsed >= self->rxQueueCapacity) {
                        self->rxQueueOverflow = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                        *writePtr++ = EVENT_PARITY_ERROR | (dataByte << 8);
                        if ((void *)writePtr >= self->rxQueueEnd) {
                            writePtr = (unsigned short *)self->rxQueueStart;
                        }
                        self->rxQueueWrite = writePtr;
                        self->rxQueueUsed++;
                    }
                } else if (errorBits == 0) {
                    // No error - normal data reception
process_flow_control_char:
                    // Check for software flow control characters
                    if ((*(unsigned int *)&self->flowControlMode & 0x80008) != 0) {
                        // Software flow control enabled
                        if (eventData == self->xonChar) {
                            newState |= 0x08;
                            changedBits |= 0x08;
                            goto data_processed;
                        } else if (eventData == self->xoffChar) {
                            newState &= ~0x08;
                            changedBits |= 0x08;
                            goto data_processed;
                        }
                    }

                    // Check if data needs special handling based on control flags
                    if ((self->controlFlags & 0x04) != 0) {
                        newState |= 0x08;
                        changedBits |= 0x08;
                    }

                    // Check character filter bitmap (256 bits)
                    if ((self->charFilterBitmap[eventData >> 5] & (1 << (eventData & 0x1F))) == 0) {
                        eventType = EVENT_VALID_DATA;  // 'U' - normal data
                    } else {
                        eventType = EVENT_SPECIAL_DATA;  // 'Y' - special/filtered data
                    }

                    // Enqueue data with marker
                    if (self->rxQueueUsed >= self->rxQueueCapacity) {
                        self->rxQueueOverflow = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                        *writePtr++ = (unsigned short)eventType | (dataByte << 8);
                        if ((void *)writePtr >= self->rxQueueEnd) {
                            writePtr = (unsigned short *)self->rxQueueStart;
                        }
                        self->rxQueueWrite = writePtr;
                        self->rxQueueUsed++;
                    }
                } else if ((errorBits == 0x08) || (errorBits == 0x0C)) {
                    // Framing error or break condition
                    if (self->rxQueueUsed >= self->rxQueueCapacity) {
                        self->rxQueueOverflow = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                        *writePtr++ = EVENT_FRAMING_ERROR | (dataByte << 8);
                        if ((void *)writePtr >= self->rxQueueEnd) {
                            writePtr = (unsigned short *)self->rxQueueStart;
                        }
                        self->rxQueueWrite = writePtr;
                        self->rxQueueUsed++;
                    }
                } else {
                    // Other error
                    if (self->rxQueueUsed >= self->rxQueueCapacity) {
                        self->rxQueueOverflow = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                        *writePtr++ = EVENT_ERROR;
                        if ((void *)writePtr >= self->rxQueueEnd) {
                            writePtr = (unsigned short *)self->rxQueueStart;
                        }
                        self->rxQueueWrite = writePtr;
                        self->rxQueueUsed++;
                    }
                }
            }
        }

data_processed:
        // Update RX watermark state if at target level and port active
        if ((self->rxQueueUsed >= self->rxQueueTarget) && (newState & STATE_ACTIVE)) {
            unsigned int rxState = newState & 0x17E;  // Keep only non-RX-state bits

            if (self->rxQueueUsed < self->rxQueueLowWater) {
                self->rxQueueWatermark = 0;
                if (self->rxQueueUsed == 0) {
                    rxState |= RX_STATE_EMPTY;
                    self->rxQueueTarget = 0;
                } else {
                    rxState |= RX_STATE_BELOW_LOW;
                    self->rxQueueTarget = self->rxQueueLowWater;
                }

                // Turn ON flow control signals (queue draining)
                if ((self->flowControlMode & FLOW_RTS_ENABLED) != 0) {
                    rxState |= STATE_RTS;
                }
                if ((self->flowControlMode & FLOW_HW_ENABLED) != 0) {
                    rxState |= 0x10;
                    if (self->flowControlState == -1) {
                        self->flowControlState = 2;
                    } else if (self->flowControlState == 1) {
                        self->flowControlState = -2;
                    }
                }
                if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                    rxState |= STATE_DTR;
                }
            } else if (self->rxQueueUsed > self->rxQueueHighWater) {
                self->rxQueueTarget = self->rxQueueCapacity - 3;
                if (self->rxQueueUsed > (self->rxQueueCapacity - 3)) {
                    rxState |= RX_STATE_CRITICAL;
                    self->rxQueueWatermark = self->rxQueueCapacity;
                } else {
                    rxState |= RX_STATE_ABOVE_HIGH;
                    self->rxQueueWatermark = self->rxQueueHighWater;
                }

                // Turn OFF flow control signals (queue filling)
                if ((self->flowControlMode & FLOW_RTS_ENABLED) != 0) {
                    rxState &= ~STATE_RTS;
                }
                if ((self->flowControlMode & FLOW_HW_ENABLED) != 0) {
                    rxState &= ~0x10;
                    if (self->flowControlState == -2 || self->flowControlState == 0) {
                        self->flowControlState = 1;
                    } else if (self->flowControlState == 2) {
                        self->flowControlState = -1;
                    }
                }
                if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                    rxState &= ~STATE_DTR;
                }
            } else {
                self->rxQueueTarget = self->rxQueueHighWater;
                self->rxQueueWatermark = self->rxQueueLowWater;
            }

            newState = (newState & 0xFFF0FFE9) | rxState;
            changedBits |= ((newState ^ self->currentState) & 0xF0016);

            // Update hardware MCR if DTR/RTS changed
            mcrValue = MCR_OUT2;
            if (rxState & STATE_DTR) mcrValue |= MCR_DTR;
            if (rxState & STATE_RTS) mcrValue |= MCR_RTS;
            OUTB(self->basePort + UART_MCR, mcrValue);

            IOEnterCriticalSection();
            // Increment some counter (placeholder for global variable)
            IOExitCriticalSection();
        }

        // Handle Modem Status Register changes
        msr = INB(self->basePort + UART_MSR);
        if (msr & 0x0F) {  // Any delta bits set
            self->msrIntCount++;
            // Update modem signal state bits (5-8) using lookup table
            newState = (newState & 0xFFFFFE1F) | (_msr_state_lut[msr >> 4] << 5);
            changedBits |= ((newState ^ self->currentState) & 0x1E0);
        }

        // Handle Transmitter Holding Register Empty (LSR bit 5)
        if (lsr & 0x20) {
            // Check hardware flow control state
            if (((self->flowControlMode & FLOW_HW_ENABLED) == 0) || (self->flowControlState < 1)) {
                // Can transmit
                if (self->txQueueUsed != 0) {
                    if ((newState & 0x1000) == 0) {  // Some state check
                        // Peek at next TX queue entry
                        char *peekPtr = (char *)self->txQueueRead;
                        if ((void *)peekPtr >= self->txQueueEnd) {
                            peekPtr = (char *)self->txQueueStart;
                        }

                        if (*peekPtr != 0) {
                            if (*peekPtr == 'U') {
                                // Data byte transmission
                                // Check for conditions that prevent transmission
                                unsigned int preventMask = *(unsigned int *)&self->flowControlMode;
                                preventMask = (preventMask & 0x168) | 0x20000000;
                                if ((preventMask & ~newState) == 0) {
                                    // Dequeue and transmit
                                    readPtr = (unsigned short *)self->txQueueRead;
                                    dataWord = *readPtr++;
                                    if ((void *)readPtr >= self->txQueueEnd) {
                                        readPtr = (unsigned short *)self->txQueueRead;
                                    }
                                    self->txQueueRead = readPtr;
                                    self->txQueueUsed--;

                                    eventType = (unsigned char)dataWord;
                                    unsigned char wordLen = eventType & 3;

                                    if (wordLen == 1) {
                                        eventData = (dataWord >> 8);
                                    } else if (wordLen == 0) {
                                        eventData = 0;
                                    } else if (wordLen == 2) {
                                        dataWord = *readPtr++;
                                        if ((void *)readPtr >= self->txQueueEnd) {
                                            readPtr = (unsigned short *)self->txQueueStart;
                                        }
                                        self->txQueueRead = readPtr;
                                        self->txQueueUsed--;
                                        eventData = dataWord;
                                    } else if (wordLen == 3) {
                                        unsigned short lowWord = *readPtr++;
                                        if ((void *)readPtr >= self->txQueueEnd) {
                                            readPtr = (unsigned short *)self->txQueueStart;
                                        }
                                        self->txQueueRead = readPtr;
                                        self->txQueueUsed--;

                                        unsigned short highWord = *readPtr++;
                                        if ((void *)readPtr >= self->txQueueEnd) {
                                            readPtr = (unsigned short *)self->txQueueStart;
                                        }
                                        self->txQueueRead = readPtr;
                                        self->txQueueUsed--;

                                        eventData = ((unsigned int)highWord << 16) | lowWord;
                                    }

                                    self->bytesTransmitted++;
                                    OUTB(self->basePort + UART_THR, (unsigned char)eventData);

                                    IOEnterCriticalSection();
                                    // Increment counter
                                    IOExitCriticalSection();
                                }
                            } else if ((lsr & 0x40) == 0) {
                                // Not ready for event processing
                                timerNeeded = 1;
                            } else {
                                // Execute dequeued event
                                timerNeeded = 0;
                                if (self->timerPending != 0) {
                                    thread_call_cancel(self->timerCallout);
                                    self->timerPending = 0;
                                }

                                // Dequeue event
                                readPtr = (unsigned short *)self->txQueueRead;
                                dataWord = *readPtr++;
                                if ((void *)readPtr >= self->txQueueEnd) {
                                    readPtr = (unsigned short *)self->txQueueStart;
                                }
                                self->txQueueRead = readPtr;
                                self->txQueueUsed--;

                                eventType = (unsigned char)dataWord;
                                unsigned char wordLen = eventType & 3;

                                if (wordLen == 1) {
                                    eventData = (dataWord >> 8);
                                } else if (wordLen == 0) {
                                    eventData = 0;
                                } else if (wordLen == 2) {
                                    dataWord = *readPtr++;
                                    if ((void *)readPtr >= self->txQueueEnd) {
                                        readPtr = (unsigned short *)self->txQueueStart;
                                    }
                                    self->txQueueRead = readPtr;
                                    self->txQueueUsed--;
                                    eventData = dataWord;
                                } else if (wordLen == 3) {
                                    unsigned short lowWord = *readPtr++;
                                    if ((void *)readPtr >= self->txQueueEnd) {
                                        readPtr = (unsigned short *)self->txQueueStart;
                                    }
                                    self->txQueueRead = readPtr;
                                    self->txQueueUsed--;

                                    unsigned short highWord = *readPtr++;
                                    if ((void *)readPtr >= self->txQueueEnd) {
                                        readPtr = (unsigned short *)self->txQueueStart;
                                    }
                                    self->txQueueRead = readPtr;
                                    self->txQueueUsed--;

                                    eventData = ((unsigned int)highWord << 16) | lowWord;
                                }

                                _executeEvent(self, eventType, eventData, &newState, &changedBits);
                                continueLoop = TRUE;
                            }
                        }
                    }
                }
            } else {
                // Hardware flow control active - send XON/XOFF
                if (self->flowControlState == 2) {
                    self->bytesTransmitted++;
                    OUTB(self->basePort + UART_THR, self->xonChar);
                } else {
                    self->bytesTransmitted++;
                    OUTB(self->basePort + UART_THR, self->xoffChar);
                }

                IOEnterCriticalSection();
                // Increment counter
                IOExitCriticalSection();

                self->flowControlState = -self->flowControlState;
            }
        }

        // Re-read LSR for next iteration
        lsr = INB(self->basePort + UART_LSR);

        // Continue if event was executed or no interrupt pending
        iir = INB(self->basePort + UART_IIR);
    } while (continueLoop || ((iir & 0x01) == 0));

    // Check for break condition change
    if ((lsr & 0x60) == 0x20) {
        timerNeeded = 1;
    }

    // Schedule timer if needed
    if ((timerNeeded != 0) && (self->timerPending == 0)) {
        self->timerPending = 1;
        unsigned long long deadline = deadline_from_interval(
            (unsigned int)(self->charTimeNS & 0xFFFFFFFF),
            (unsigned int)(self->charTimeFracNS)
        );
        thread_call_enter_delayed(self->timerCallout, deadline);
    }

    // Update TX watermark state
    if (self->txQueueUsed <= self->txQueueTarget) {
        unsigned int txState;

        if (self->txQueueUsed < self->txQueueMedWater) {
            if (self->txQueueUsed < self->txQueueLowWater) {
                self->txQueueHighWater = self->txQueueCapacity - 3;
                if (self->txQueueUsed > (self->txQueueCapacity - 3)) {
                    self->txQueueTarget = self->txQueueCapacity;
                    txState = TX_STATE_ABOVE_HIGH;
                } else {
                    self->txQueueTarget = self->txQueueLowWater;
                    txState = 0;
                }
            } else {
                self->txQueueTarget = self->txQueueMedWater;
                self->txQueueHighWater = self->txQueueLowWater;
                txState = TX_STATE_BELOW_HIGH;
            }
        } else {
            self->txQueueTarget = 0;
            if (self->txQueueUsed == 0) {
                self->txQueueHighWater = 0;
                txState = TX_STATE_EMPTY;
            } else {
                self->txQueueHighWater = self->txQueueMedWater;
                txState = TX_STATE_BELOW_MED;
            }
        }

        newState = (newState & 0xF87FFFFF) | txState;
    }

    // Update break/transmitter state bit
    if ((lsr & 0x40) == 0) {
        newState |= 0x10000000;
    } else {
        newState &= 0xEFFFFFFF;
    }

    changedBits |= (self->currentState ^ newState);

    // Enqueue state change event if mask matches
    stateChangeMask = *(unsigned int *)&self->flowControlMode;
    unsigned int matchBits = (changedBits << 16) & stateChangeMask;
    if (matchBits != 0) {
        if ((self->rxQueueCapacity - self->rxQueueUsed) < 3) {
            if (self->rxQueueUsed >= self->rxQueueCapacity) {
                self->rxQueueOverflow = 1;
            } else {
                unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                *writePtr++ = EVENT_OVERFLOW;
                if ((void *)writePtr >= self->rxQueueEnd) {
                    writePtr = (unsigned short *)self->rxQueueStart;
                }
                self->rxQueueWrite = writePtr;
                self->rxQueueUsed++;
            }
        } else {
            _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                               (newState & 0xFFFF) | (matchBits & 0xFFFF0000));
        }
    }

    // Wake threads waiting on state changes
    if (changedBits & self->watchStateMask) {
        thread_wakeup_prim(&self->watchStateMask, 0, 4);
    }

    // Store new state
    self->currentState = newState;
}

/*
 * FIFO interrupt handler.
 * Handles all UART interrupts for 16550A+ chips with FIFO.
 * This is called at interrupt level and processes multiple bytes per interrupt.
 */
static void _FIFOIntHandler(void *identity, void *state, ISASerialPort *self)
{
    unsigned char lsr, msr, iir;
    unsigned char dataByte;
    unsigned char eventType;
    unsigned int eventData;
    unsigned int newState, changedBits;
    unsigned char mcrValue;
    BOOL continueLoop, firstRXInt, firstTHRInt;
    unsigned char timerNeeded;
    unsigned short dataWord;
    unsigned short *readPtr;
    unsigned int stateChangeMask;
    int fifoRemaining;
    int overrunCounter;

    // Check if FIFO is actually enabled
    if ((self->fcrValue & FCR_FIFO_ENABLE) == 0) {
        // FIFO not enabled - use non-FIFO handler
        _NonFIFOIntHandler(identity, state, self);
        return;
    }

    // Initialize locals
    timerNeeded = self->timerPending;
    overrunCounter = 0;
    eventData = 0;
    changedBits = 0;
    eventType = 0;
    newState = self->currentState;
    firstTHRInt = TRUE;
    firstRXInt = TRUE;
    fifoRemaining = 0;

    // Update interrupt statistics
    self->interruptCount++;

    // Set heartbeat pending flag
    self->heartBeatPending = 1;

    // Main interrupt processing loop
    do {
        continueLoop = FALSE;

        // Process all data in RX FIFO
        while ((lsr = INB(self->basePort + UART_LSR)) & 0x01) {
            // Read data byte from RBR
            dataByte = INB(self->basePort + UART_RBR);
            eventData = (unsigned int)dataByte;

            // Check for PCMCIA card removal (all 1's)
            if ((lsr == 0xFF) && (dataByte == 0xFF) && (self->pcmciaDetect != 0)) {
                _PCMCIA_yanked(self);
                return;
            }

            // Process received data if RX enabled
            if (newState & STATE_RX_ENABLED) {
                // Update statistics on first RX interrupt
                if (firstRXInt && (lsr & 0x01)) {
                    firstRXInt = FALSE;
                    self->dataReadyIntCount++;
                }

                self->bytesReceived++;

                // Check for overrun error and update counter
                if ((lsr & 0x02) && (overrunCounter == 0)) {
                    overrunCounter = chipCapTable[self->chipType].fifoSize;
                }

                unsigned char errorBits = lsr & 0x1C;  // Parity, Framing, Break errors

                if (errorBits == 0x04) {
                    // Parity error - check for software flow control character
                    if (self->flowControl == 6) {  // Software flow control mode
                        // Mask data with RX FIFO mask
                        eventData = dataByte & self->rxFIFOMask;
                        goto process_flow_control_char_fifo;
                    }

                    // Enqueue parity error with data
                    if (self->rxQueueUsed >= self->rxQueueCapacity) {
                        self->rxQueueOverflow = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                        *writePtr++ = EVENT_PARITY_ERROR | (dataByte << 8);
                        if ((void *)writePtr >= self->rxQueueEnd) {
                            writePtr = (unsigned short *)self->rxQueueStart;
                        }
                        self->rxQueueWrite = writePtr;
                        self->rxQueueUsed++;
                    }
                } else if (errorBits == 0) {
                    // No error - normal data reception
process_flow_control_char_fifo:
                    // Check for software flow control characters
                    if ((*(unsigned int *)&self->flowControlMode & 0x80008) != 0) {
                        // Software flow control enabled
                        if (eventData == self->xonChar) {
                            newState |= 0x08;
                            changedBits |= 0x08;
                        } else if (eventData == self->xoffChar) {
                            newState &= ~0x08;
                            changedBits |= 0x08;
                        } else {
                            goto enqueue_normal_data_fifo;
                        }
                    } else {
enqueue_normal_data_fifo:
                        // Check if data needs special handling based on control flags
                        if ((self->controlFlags & 0x04) != 0) {
                            newState |= 0x08;
                            changedBits |= 0x08;
                        }

                        // Check character filter bitmap (256 bits)
                        if ((self->charFilterBitmap[eventData >> 5] & (1 << (eventData & 0x1F))) == 0) {
                            eventType = EVENT_VALID_DATA;  // 'U' - normal data
                        } else {
                            eventType = EVENT_SPECIAL_DATA;  // 'Y' - special/filtered data
                        }

                        // Enqueue data with marker
                        if (self->rxQueueUsed >= self->rxQueueCapacity) {
                            self->rxQueueOverflow = 1;
                        } else {
                            unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                            *writePtr++ = (unsigned short)eventType | (dataByte << 8);
                            if ((void *)writePtr >= self->rxQueueEnd) {
                                writePtr = (unsigned short *)self->rxQueueStart;
                            }
                            self->rxQueueWrite = writePtr;
                            self->rxQueueUsed++;
                        }
                    }
                } else if ((errorBits == 0x08) || (errorBits == 0x0C)) {
                    // Framing error or break condition
                    if (self->rxQueueUsed >= self->rxQueueCapacity) {
                        self->rxQueueOverflow = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                        *writePtr++ = EVENT_FRAMING_ERROR | (dataByte << 8);
                        if ((void *)writePtr >= self->rxQueueEnd) {
                            writePtr = (unsigned short *)self->rxQueueStart;
                        }
                        self->rxQueueWrite = writePtr;
                        self->rxQueueUsed++;
                    }
                } else {
                    // Other error
                    if (self->rxQueueUsed >= self->rxQueueCapacity) {
                        self->rxQueueOverflow = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                        *writePtr++ = EVENT_ERROR;
                        if ((void *)writePtr >= self->rxQueueEnd) {
                            writePtr = (unsigned short *)self->rxQueueStart;
                        }
                        self->rxQueueWrite = writePtr;
                        self->rxQueueUsed++;
                    }
                }

                // Check for end of overrun sequence
                if (overrunCounter != 0) {
                    overrunCounter--;
                    if (overrunCounter == 0) {
                        // Enqueue overrun error event
                        if (self->rxQueueUsed >= self->rxQueueCapacity) {
                            self->rxQueueOverflow = 1;
                        } else {
                            unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                            *writePtr++ = EVENT_OVERRUN_ERROR;
                            if ((void *)writePtr >= self->rxQueueEnd) {
                                writePtr = (unsigned short *)self->rxQueueStart;
                            }
                            self->rxQueueWrite = writePtr;
                            self->rxQueueUsed++;
                        }
                    }
                }
            }
        }

        // Update RX watermark state if at target level and port active
        if ((self->rxQueueUsed >= self->rxQueueTarget) && (newState & STATE_ACTIVE)) {
            unsigned int rxState = newState & 0x17E;

            if (self->rxQueueUsed < self->rxQueueLowWater) {
                self->rxQueueWatermark = 0;
                if (self->rxQueueUsed == 0) {
                    rxState |= RX_STATE_EMPTY;
                    self->rxQueueTarget = 0;
                } else {
                    rxState |= RX_STATE_BELOW_LOW;
                    self->rxQueueTarget = self->rxQueueLowWater;
                }

                if ((self->flowControlMode & FLOW_RTS_ENABLED) != 0) {
                    rxState |= STATE_RTS;
                }
                if ((self->flowControlMode & FLOW_HW_ENABLED) != 0) {
                    rxState |= 0x10;
                    if (self->flowControlState == -1) {
                        self->flowControlState = 2;
                    } else if (self->flowControlState == 1) {
                        self->flowControlState = -2;
                    }
                }
                if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                    rxState |= STATE_DTR;
                }
            } else if (self->rxQueueUsed > self->rxQueueHighWater) {
                self->rxQueueTarget = self->rxQueueCapacity - 3;
                if (self->rxQueueUsed > (self->rxQueueCapacity - 3)) {
                    rxState |= RX_STATE_CRITICAL;
                    self->rxQueueWatermark = self->rxQueueCapacity;
                } else {
                    rxState |= RX_STATE_ABOVE_HIGH;
                    self->rxQueueWatermark = self->rxQueueHighWater;
                }

                if ((self->flowControlMode & FLOW_RTS_ENABLED) != 0) {
                    rxState &= ~STATE_RTS;
                }
                if ((self->flowControlMode & FLOW_HW_ENABLED) != 0) {
                    rxState &= ~0x10;
                    if (self->flowControlState == -2 || self->flowControlState == 0) {
                        self->flowControlState = 1;
                    } else if (self->flowControlState == 2) {
                        self->flowControlState = -1;
                    }
                }
                if ((self->flowControlMode & FLOW_DTR_ENABLED) != 0) {
                    rxState &= ~STATE_DTR;
                }
            } else {
                self->rxQueueTarget = self->rxQueueHighWater;
                self->rxQueueWatermark = self->rxQueueLowWater;
            }

            newState = (newState & 0xFFF0FFE9) | rxState;
            changedBits |= ((newState ^ self->currentState) & 0xF0016);

            mcrValue = MCR_OUT2;
            if (rxState & STATE_DTR) mcrValue |= MCR_DTR;
            if (rxState & STATE_RTS) mcrValue |= MCR_RTS;
            OUTB(self->basePort + UART_MCR, mcrValue);

            IOEnterCriticalSection();
            IOExitCriticalSection();
        }

        // Handle Modem Status Register changes
        msr = INB(self->basePort + UART_MSR);
        newState = (newState & 0xFFFFFE1F) | (_msr_state_lut[msr >> 4] << 5);
        changedBits |= ((newState ^ self->currentState) & 0x1E0);

        // Handle Transmitter Holding Register Empty (LSR bit 5 or FIFO counter)
        if ((lsr & 0x20) || (fifoRemaining != 0)) {
            if (firstTHRInt) {
                firstTHRInt = FALSE;
                self->thrEmptyIntCount++;
            }

            // Check hardware flow control state
            if (((self->flowControlMode & FLOW_HW_ENABLED) == 0) || (self->flowControlState < 1)) {
                if ((newState & 0x1000) == 0) {
                    // Peek at next TX queue entry
                    char *peekPtr = (char *)self->txQueueRead;
                    if ((void *)peekPtr >= self->txQueueEnd) {
                        peekPtr = (char *)self->txQueueStart;
                    }
                    char peekChar = (self->txQueueUsed != 0) ? *peekPtr : '\0';

                    if (peekChar != 0) {
                        if (peekChar == 'U') {
                            // Data byte transmission
                            unsigned int preventMask = *(unsigned int *)&self->flowControlMode;
                            preventMask = (preventMask & 0x168) | 0x20000000;
                            if ((preventMask & ~newState) == 0) {
                                // Can transmit - check if TEMT set for burst mode
                                if ((lsr & 0x40) == 0) {
                                    // Transmitter not empty - peek ahead for next byte
                                    char *peek2Ptr = (char *)((unsigned short *)self->txQueueRead + 1);
                                    if ((void *)peek2Ptr >= self->txQueueEnd) {
                                        peek2Ptr = (char *)self->txQueueStart;
                                    }
                                    char peek2Char = (self->txQueueUsed >= 2) ? *peek2Ptr : '\0';

                                    if (peek2Char == 'U') {
                                        // Next is also data - setup FIFO burst
                                        fifoRemaining = chipCapTable[self->chipType].fifoSize - 1;
                                        timerNeeded = 0;
                                        if (self->timerPending != 0) {
                                            thread_call_cancel(self->timerCallout);
                                            self->timerPending = 0;
                                        }

                                        // Dequeue and transmit first byte
                                        readPtr = (unsigned short *)self->txQueueRead;
                                        dataWord = *readPtr++;
                                        if ((void *)readPtr >= self->txQueueEnd) {
                                            readPtr = (unsigned short *)self->txQueueStart;
                                        }
                                        self->txQueueRead = readPtr;
                                        self->txQueueUsed--;

                                        eventType = (unsigned char)dataWord;
                                        unsigned char wordLen = eventType & 3;

                                        if (wordLen == 1) {
                                            eventData = (dataWord >> 8);
                                        } else if (wordLen == 0) {
                                            eventData = 0;
                                        } else if (wordLen == 2) {
                                            dataWord = *readPtr++;
                                            if ((void *)readPtr >= self->txQueueEnd) {
                                                readPtr = (unsigned short *)self->txQueueStart;
                                            }
                                            self->txQueueRead = readPtr;
                                            self->txQueueUsed--;
                                            eventData = dataWord;
                                        } else if (wordLen == 3) {
                                            unsigned short lowWord = *readPtr++;
                                            if ((void *)readPtr >= self->txQueueEnd) {
                                                readPtr = (unsigned short *)self->txQueueStart;
                                            }
                                            self->txQueueRead = readPtr;
                                            self->txQueueUsed--;

                                            unsigned short highWord = *readPtr++;
                                            if ((void *)readPtr >= self->txQueueEnd) {
                                                readPtr = (unsigned short *)self->txQueueStart;
                                            }
                                            self->txQueueRead = readPtr;
                                            self->txQueueUsed--;

                                            eventData = ((unsigned int)highWord << 16) | lowWord;
                                        }

                                        self->bytesTransmitted++;
                                        OUTB(self->basePort + UART_THR, (unsigned char)eventData);

                                        IOEnterCriticalSection();
                                        IOExitCriticalSection();
                                    }
                                } else {
                                    // TEMT set - can do FIFO burst transmission
                                    fifoRemaining = chipCapTable[self->chipType].fifoSize;
                                    timerNeeded = 0;
                                    if (self->timerPending != 0) {
                                        thread_call_cancel(self->timerCallout);
                                        self->timerPending = 0;
                                    }
                                }

                                // Transmit remaining FIFO bytes
                                while (fifoRemaining != 0) {
                                    // Peek at next entry
                                    peekPtr = (char *)self->txQueueRead;
                                    if ((void *)peekPtr >= self->txQueueEnd) {
                                        peekPtr = (char *)self->txQueueStart;
                                    }
                                    peekChar = (self->txQueueUsed != 0) ? *peekPtr : '\0';

                                    if (peekChar != 'U') break;

                                    // Dequeue and transmit
                                    readPtr = (unsigned short *)self->txQueueRead;
                                    dataWord = *readPtr++;
                                    if ((void *)readPtr >= self->txQueueEnd) {
                                        readPtr = (unsigned short *)self->txQueueStart;
                                    }
                                    self->txQueueRead = readPtr;
                                    self->txQueueUsed--;

                                    eventType = (unsigned char)dataWord;
                                    unsigned char wordLen = eventType & 3;

                                    if (wordLen == 1) {
                                        eventData = (dataWord >> 8);
                                    } else if (wordLen == 0) {
                                        eventData = 0;
                                    } else if (wordLen == 2) {
                                        dataWord = *readPtr++;
                                        if ((void *)readPtr >= self->txQueueEnd) {
                                            readPtr = (unsigned short *)self->txQueueStart;
                                        }
                                        self->txQueueRead = readPtr;
                                        self->txQueueUsed--;
                                        eventData = dataWord;
                                    } else if (wordLen == 3) {
                                        unsigned short lowWord = *readPtr++;
                                        if ((void *)readPtr >= self->txQueueEnd) {
                                            readPtr = (unsigned short *)self->txQueueStart;
                                        }
                                        self->txQueueRead = readPtr;
                                        self->txQueueUsed--;

                                        unsigned short highWord = *readPtr++;
                                        if ((void *)readPtr >= self->txQueueEnd) {
                                            readPtr = (unsigned short *)self->txQueueStart;
                                        }
                                        self->txQueueRead = readPtr;
                                        self->txQueueUsed--;

                                        eventData = ((unsigned int)highWord << 16) | lowWord;
                                    }

                                    self->bytesTransmitted++;
                                    OUTB(self->basePort + UART_THR, (unsigned char)eventData);

                                    IOEnterCriticalSection();
                                    IOExitCriticalSection();

                                    fifoRemaining--;
                                }

                                goto tx_done_fifo;
                            }
                        } else if ((lsr & 0x40) != 0) {
                            // Non-data event and TEMT set - execute it
                            timerNeeded = 0;
                            if (self->timerPending != 0) {
                                thread_call_cancel(self->timerCallout);
                                self->timerPending = 0;
                            }

                            // Dequeue event
                            readPtr = (unsigned short *)self->txQueueRead;
                            dataWord = *readPtr++;
                            if ((void *)readPtr >= self->txQueueEnd) {
                                readPtr = (unsigned short *)self->txQueueStart;
                            }
                            self->txQueueRead = readPtr;
                            self->txQueueUsed--;

                            eventType = (unsigned char)dataWord;
                            unsigned char wordLen = eventType & 3;

                            if (wordLen == 1) {
                                eventData = (dataWord >> 8);
                            } else if (wordLen == 0) {
                                eventData = 0;
                            } else if (wordLen == 2) {
                                dataWord = *readPtr++;
                                if ((void *)readPtr >= self->txQueueEnd) {
                                    readPtr = (unsigned short *)self->txQueueStart;
                                }
                                self->txQueueRead = readPtr;
                                self->txQueueUsed--;
                                eventData = dataWord;
                            } else if (wordLen == 3) {
                                unsigned short lowWord = *readPtr++;
                                if ((void *)readPtr >= self->txQueueEnd) {
                                    readPtr = (unsigned short *)self->txQueueStart;
                                }
                                self->txQueueRead = readPtr;
                                self->txQueueUsed--;

                                unsigned short highWord = *readPtr++;
                                if ((void *)readPtr >= self->txQueueEnd) {
                                    readPtr = (unsigned short *)self->txQueueStart;
                                }
                                self->txQueueRead = readPtr;
                                self->txQueueUsed--;

                                eventData = ((unsigned int)highWord << 16) | lowWord;
                            }

                            _executeEvent(self, eventType, eventData, &newState, &changedBits);
                            continueLoop = TRUE;
                            goto tx_done_fifo;
                        }

                        timerNeeded = 1;
                    }
                }

tx_done_fifo:
                fifoRemaining = 0;
            } else {
                // Hardware flow control active - send XON/XOFF
                if (self->flowControlState == 2) {
                    self->bytesTransmitted++;
                    OUTB(self->basePort + UART_THR, self->xonChar);
                } else {
                    self->bytesTransmitted++;
                    OUTB(self->basePort + UART_THR, self->xoffChar);
                }

                IOEnterCriticalSection();
                IOExitCriticalSection();

                self->flowControlState = -self->flowControlState;

                if (fifoRemaining != 0) {
                    fifoRemaining--;
                }
            }
        }

        // Check for more interrupts
        iir = INB(self->basePort + UART_IIR);
    } while (continueLoop || (overrunCounter != 0) || (fifoRemaining != 0) || ((iir & 0x01) == 0));

    // Check for break condition change
    if ((lsr & 0x60) == 0x20) {
        timerNeeded = 1;
    }

    // Schedule timer if needed
    if ((timerNeeded != 0) && (self->timerPending == 0)) {
        self->timerPending = 1;
        unsigned long long deadline = deadline_from_interval(
            (unsigned int)(self->charTimeNS & 0xFFFFFFFF),
            (unsigned int)(self->charTimeFracNS)
        );
        thread_call_enter_delayed(self->timerCallout, deadline);
    }

    // Update TX watermark state
    if (self->txQueueUsed <= self->txQueueTarget) {
        unsigned int txState;

        if (self->txQueueUsed < self->txQueueMedWater) {
            if (self->txQueueUsed < self->txQueueLowWater) {
                self->txQueueHighWater = self->txQueueCapacity - 3;
                if (self->txQueueUsed > (self->txQueueCapacity - 3)) {
                    self->txQueueTarget = self->txQueueCapacity;
                    txState = TX_STATE_ABOVE_HIGH;
                } else {
                    self->txQueueTarget = self->txQueueLowWater;
                    txState = 0;
                }
            } else {
                self->txQueueTarget = self->txQueueMedWater;
                self->txQueueHighWater = self->txQueueLowWater;
                txState = TX_STATE_BELOW_HIGH;
            }
        } else {
            self->txQueueTarget = 0;
            if (self->txQueueUsed == 0) {
                self->txQueueHighWater = 0;
                txState = TX_STATE_EMPTY;
            } else {
                self->txQueueHighWater = self->txQueueMedWater;
                txState = TX_STATE_BELOW_MED;
            }
        }

        newState = (newState & 0xF87FFFFF) | txState;
    }

    // Update break/transmitter state bit
    if ((lsr & 0x40) == 0) {
        newState |= 0x10000000;
    } else {
        newState &= 0xEFFFFFFF;
    }

    changedBits |= (self->currentState ^ newState);

    // Enqueue state change event if mask matches
    stateChangeMask = *(unsigned int *)&self->flowControlMode;
    unsigned int matchBits = (changedBits << 16) & stateChangeMask;
    if (matchBits != 0) {
        if ((self->rxQueueCapacity - self->rxQueueUsed) < 3) {
            if (self->rxQueueUsed >= self->rxQueueCapacity) {
                self->rxQueueOverflow = 1;
            } else {
                unsigned short *writePtr = (unsigned short *)self->rxQueueWrite;
                *writePtr++ = EVENT_OVERFLOW;
                if ((void *)writePtr >= self->rxQueueEnd) {
                    writePtr = (unsigned short *)self->rxQueueStart;
                }
                self->rxQueueWrite = writePtr;
                self->rxQueueUsed++;
            }
        } else {
            _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                               (newState & 0xFFFF) | (matchBits & 0xFFFF0000));
        }
    }

    // Wake threads waiting on state changes
    if (changedBits & self->watchStateMask) {
        thread_wakeup_prim(&self->watchStateMask, 0, 4);
    }

    // Store new state
    self->currentState = newState;
}

/*
 * _executeEvent - Execute an event command on the serial port
 *
 * This function implements the event dispatcher for serial port control commands.
 * It handles configuration changes, queue management, and state control.
 *
 * Parameters:
 *   self - Pointer to ISASerialPort instance
 *   eventType - Event type identifier (determines action to take)
 *   eventData - Event-specific data parameter
 *   statePtr - Pointer to state value (output parameter)
 *   changedBitsPtr - Pointer to changed bits mask (output parameter)
 */
static void _executeEvent(ISASerialPort *self, unsigned char eventType,
                         unsigned int eventData, unsigned int *statePtr,
                         unsigned int *changedBitsPtr)
{
    unsigned int oldState;
    unsigned int newState;
    unsigned int changedBits;
    unsigned int tempValue;
    unsigned int bitIndex;
    unsigned int byteIndex;

    oldState = self->currentState;
    newState = oldState;
    changedBits = 0;

    switch (eventType) {
        case 0x05:  // Activate/Deactivate port
            if (eventData != 0) {
                // Activate port
                _activatePort(self);
                newState |= STATE_ACTIVE;
            } else {
                // Deactivate port
                _deactivatePort(self);
                newState &= ~STATE_ACTIVE;
            }
            changedBits = STATE_ACTIVE;
            break;

        case 0x13:  // Set TX medium watermark
            if (eventData <= self->txQueueCapacity) {
                self->txQueueMedWater = eventData;
            }
            break;

        case 0x17:  // Set RX low watermark
            if (eventData <= self->rxQueueCapacity) {
                self->rxQueueLowWater = eventData;
                // Recalculate flow control if needed
                tempValue = _flowMachine(self);
                changedBits = tempValue ^ oldState;
                newState = tempValue;
            }
            break;

        case 0x1B:  // Set TX low watermark
            if (eventData <= self->txQueueCapacity) {
                self->txQueueLowWater = eventData;
            }
            break;

        case 0x1F:  // Set RX high watermark
            if (eventData <= self->rxQueueCapacity) {
                self->rxQueueHighWater = eventData;
                // Recalculate flow control if needed
                tempValue = _flowMachine(self);
                changedBits = tempValue ^ oldState;
                newState = tempValue;
            }
            break;

        case 0x28:  // Flush TX queue
            // Reset TX ring buffer
            self->txQueueRead = self->txQueueStart;
            self->txQueueWrite = self->txQueueStart;
            self->txQueueUsed = 0;
            // Update TX state to empty
            newState = (newState & ~TX_STATE_MASK) | TX_STATE_EMPTY;
            changedBits = TX_STATE_MASK;
            break;

        case 0x2F:  // Flush RX queue
            // Reset RX ring buffer
            self->rxQueueRead = self->rxQueueStart;
            self->rxQueueWrite = self->rxQueueStart;
            self->rxQueueUsed = 0;
            self->rxQueueOverflow = 0;
            // Update RX state to empty
            newState = (newState & ~RX_STATE_MASK) | RX_STATE_EMPTY;
            changedBits = RX_STATE_MASK;
            // Recalculate flow control
            tempValue = _flowMachine(self);
            changedBits |= tempValue ^ newState;
            newState = tempValue;
            break;

        case 0x33:  // Set baud rate
            if (eventData != 0 && eventData != self->baudRate) {
                self->baudRate = eventData;
                // Calculate new divisor
                self->divisor = (unsigned short)(self->clockRate / (eventData << 3));
                if (self->divisor == 0) {
                    self->divisor = 1;
                }
                // Reprogram chip if active
                if (oldState & STATE_ACTIVE) {
                    _programChip(self);
                }
                // Calculate character time in nanoseconds
                // Character time = (dataBits + stopBits + 1 for start bit + parity) * bit_time
                // bit_time = 1000000000 / baud_rate nanoseconds
                tempValue = self->dataBits + self->stopBits + 2; // +2 for start bit and parity
                if (self->parity == PARITY_NONE) {
                    tempValue--; // No parity bit
                }
                // Calculate: (tempValue * 1000000000) / baudRate
                // Use 64-bit arithmetic to avoid overflow
                self->charTimeNS = __udivdi3(tempValue * 1000000000, 0, eventData, 0);
                self->charTimeFracNS = __umoddi3(tempValue * 1000000000, 0, eventData, 0);
            }
            break;

        case 0x3B:  // Set data bits (10=5 bits, 12=6 bits, 14=7 bits, 16=8 bits)
            if (eventData >= 10 && eventData <= 16 && (eventData & 1) == 0) {
                self->dataBits = eventData;
                // Update LCR value
                self->lcrValue = (self->lcrValue & 0xFC) | ((eventData - 10) >> 1);
                // Reprogram chip if active
                if (oldState & STATE_ACTIVE) {
                    _programChip(self);
                }
            }
            break;

        case 0x43:  // Set parity
            if (eventData >= PARITY_NONE && eventData <= PARITY_SPACE) {
                self->parity = eventData;
                // Update LCR value based on parity type
                tempValue = self->lcrValue & 0xC7; // Clear parity bits
                if (eventData != PARITY_NONE) {
                    tempValue |= 0x08; // Enable parity
                    switch (eventData) {
                        case PARITY_ODD:
                            // Odd parity: bit 4 = 0
                            break;
                        case PARITY_EVEN:
                            tempValue |= 0x10; // Even parity: bit 4 = 1
                            break;
                        case PARITY_MARK:
                            tempValue |= 0x20; // Mark parity: bit 5 = 1
                            break;
                        case PARITY_SPACE:
                            tempValue |= 0x30; // Space parity: bits 4,5 = 1
                            break;
                    }
                }
                self->lcrValue = (unsigned char)tempValue;
                // Reprogram chip if active
                if (oldState & STATE_ACTIVE) {
                    _programChip(self);
                }
            }
            break;

        case 0x47:  // Set flow control
            self->flowControl = eventData;
            // Update flow control mode flags
            self->flowControlMode &= ~(FLOW_DTR_ENABLED | FLOW_RTS_ENABLED | FLOW_HW_ENABLED);
            if (eventData & 0x02) {
                self->flowControlMode |= FLOW_DTR_ENABLED;
            }
            if (eventData & 0x04) {
                self->flowControlMode |= FLOW_RTS_ENABLED;
            }
            if (eventData & 0x10) {
                self->flowControlMode |= FLOW_HW_ENABLED;
            }
            // Recalculate flow control state
            tempValue = _flowMachine(self);
            changedBits = tempValue ^ oldState;
            newState = tempValue;
            break;

        case 0x4B:  // Set delay timeout
            // Cancel existing delay timeout if active
            if (self->delayTimeoutCallout != NULL) {
                thread_call_cancel(self->delayTimeoutCallout);
            }
            // Set new delay timeout if non-zero
            if (eventData != 0) {
                unsigned long long deadline = deadline_from_interval(eventData, 0);
                thread_call_enter_delayed(self->delayTimeoutCallout, deadline);
            }
            break;

        case 0x4F:  // Set character time override
            self->charTimeOverrideLow = eventData & 0xFFFF;
            self->charTimeOverrideHigh = (eventData >> 16) & 0xFFFF;
            break;

        case 0x53:  // External state change
            // This is used to inject external state changes
            newState = eventData;
            changedBits = newState ^ oldState;
            break;

        case 0x55:  // Unmark character (remove from filter)
            if (eventData <= 0xFF) {
                bitIndex = eventData & 0x1F;  // Bit position within word
                byteIndex = eventData >> 5;   // Word index (0-7)
                self->charFilterBitmap[byteIndex] &= ~(1 << bitIndex);
            }
            break;

        case 0x59:  // Mark character (add to filter)
            if (eventData <= 0xFF) {
                bitIndex = eventData & 0x1F;  // Bit position within word
                byteIndex = eventData >> 5;   // Word index (0-7)
                self->charFilterBitmap[byteIndex] |= (1 << bitIndex);
            }
            break;

        case 0xE5:  // Force FIFO disable
            self->forceFIFODisable = (eventData != 0) ? 1 : 0;
            // Reinitialize chip if active
            if (oldState & STATE_ACTIVE) {
                _initChip(self);
            }
            break;

        case 0xE9:  // Set XON character
            if (eventData <= 0xFF) {
                self->xonChar = (unsigned char)eventData;
            }
            break;

        case 0xED:  // Set XOFF character
            if (eventData <= 0xFF) {
                self->xoffChar = (unsigned char)eventData;
            }
            break;

        case 0xF3:  // Set stop bits (2=1 stop bit, 3+=2 stop bits)
            if (eventData >= 2 && eventData <= 4) {
                self->stopBits = eventData;
                // Update LCR value
                if (eventData == 2) {
                    self->lcrValue &= ~0x04; // 1 stop bit
                } else {
                    self->lcrValue |= 0x04;  // 2 stop bits
                }
                // Reprogram chip if active
                if (oldState & STATE_ACTIVE) {
                    _programChip(self);
                }
            }
            break;

        case 0xF9:  // Set break state
            if (eventData != 0) {
                // Set break
                self->lcrValue |= 0x40;
            } else {
                // Clear break
                self->lcrValue &= ~0x40;
            }
            // Write to LCR register if active
            if (oldState & STATE_ACTIVE) {
                outb(self->basePort + UART_LCR, self->lcrValue);
            }
            break;

        default:
            // Unknown event type - ignore
            break;
    }

    // Update state if changed
    if (newState != oldState) {
        self->currentState = newState;
    }

    // Return values through pointers
    if (statePtr != NULL) {
        *statePtr = newState;
    }
    if (changedBitsPtr != NULL) {
        *changedBitsPtr = changedBits;
    }
}

/*
 * __udivdi3 - GCC helper function for 64-bit unsigned division on 32-bit systems
 *
 * Divides a 64-bit unsigned integer by another 64-bit unsigned integer.
 * Parameters are passed as two 32-bit halves (low, high).
 *
 * Returns: 64-bit quotient as two 32-bit values
 */
unsigned long long __udivdi3(unsigned int dividend_lo, unsigned int dividend_hi,
                             unsigned int divisor_lo, unsigned int divisor_hi)
{
    unsigned long long dividend, divisor, quotient;
    unsigned int shift;
    unsigned long long temp;

    dividend = ((unsigned long long)dividend_hi << 32) | dividend_lo;
    divisor = ((unsigned long long)divisor_hi << 32) | divisor_lo;

    // Fast path: divisor high word is zero
    if (divisor_hi == 0) {
        // Check if dividend also fits in 32 bits or divisor > dividend_hi
        if (divisor_lo <= dividend_hi) {
            // Need to do 64-bit division
            if (divisor_lo == 0) {
                // Division by zero - trigger exception
                divisor_lo = 1 / 0;  // This will cause a divide-by-zero exception
            }
            // Divide high word first, then combine with low word
            unsigned int quot_hi = dividend_hi / divisor_lo;
            unsigned long long remainder_and_low = ((unsigned long long)(dividend_hi % divisor_lo) << 32) | dividend_lo;
            unsigned int quot_lo = remainder_and_low / divisor_lo;
            return ((unsigned long long)quot_hi << 32) | quot_lo;
        } else {
            // Simple 64/32 division
            return dividend / divisor_lo;
        }
    }

    // divisor_hi != 0
    if (dividend_hi < divisor_hi) {
        // Quotient is zero
        return 0;
    }

    // Find the position of the most significant bit in divisor_hi
    shift = 31;
    if (divisor_hi != 0) {
        while ((divisor_hi >> shift) == 0) {
            shift--;
        }
    }

    // If shift is 31 (divisor_hi has only low bit set), special case
    if ((shift ^ 31) == 0) {
        // Check if dividend >= divisor
        if ((dividend_hi <= divisor_hi) && (dividend_lo < divisor_lo)) {
            return 0;
        }
        return 1;
    }

    // Normalize divisor and dividend
    unsigned char norm_shift = (unsigned char)(shift ^ 31);
    unsigned char denorm_shift = 32 - norm_shift;

    // Normalize divisor
    unsigned long long norm_divisor = (divisor_hi << norm_shift) | (divisor_lo >> denorm_shift);

    // Normalize dividend
    unsigned long long norm_dividend =
        ((unsigned long long)(dividend_hi >> denorm_shift) << 32) |
        ((dividend_hi << norm_shift) | (dividend_lo >> denorm_shift));

    // Estimate quotient
    quotient = norm_dividend / norm_divisor;
    unsigned long long remainder = norm_dividend % norm_divisor;

    // Refine quotient if necessary
    unsigned long long product = ((unsigned long long)(divisor_lo << norm_shift) * quotient);
    unsigned long long rem_and_low = ((remainder << 32) | (dividend_lo << norm_shift));

    if (rem_and_low < product) {
        quotient--;
    }

    return quotient;
}

/*
 * __umoddi3 - GCC helper function for 64-bit unsigned modulo on 32-bit systems
 *
 * Computes remainder of 64-bit unsigned division.
 * Parameters are passed as two 32-bit halves (low, high).
 *
 * Returns: 64-bit remainder as two 32-bit values
 */
unsigned long long __umoddi3(unsigned int dividend_lo, unsigned int dividend_hi,
                             unsigned int divisor_lo, unsigned int divisor_hi)
{
    unsigned long long dividend, divisor;
    unsigned int shift;
    unsigned long long remainder;

    dividend = ((unsigned long long)dividend_hi << 32) | dividend_lo;
    divisor = ((unsigned long long)divisor_hi << 32) | divisor_lo;

    // Fast path: divisor high word is zero
    if (divisor_hi == 0) {
        if (dividend_hi < divisor_lo) {
            // Simple modulo
            return dividend % divisor_lo;
        } else {
            // Need to compute (dividend_hi % divisor) * 2^32 + dividend_lo) % divisor
            if (divisor_lo == 0) {
                divisor_lo = 1 / 0;  // Division by zero
            }
            unsigned long long temp = ((unsigned long long)(dividend_hi % divisor_lo) << 32) | dividend_lo;
            return temp % divisor_lo;
        }
    }

    // divisor_hi != 0
    if (divisor_hi <= dividend_hi) {
        // Find the position of the most significant bit in divisor_hi
        shift = 31;
        if (divisor_hi != 0) {
            while ((divisor_hi >> shift) == 0) {
                shift--;
            }
        }

        if ((shift ^ 31) != 0) {
            // Normalize
            unsigned char norm_shift = (unsigned char)(shift ^ 31);
            unsigned char denorm_shift = 32 - norm_shift;

            unsigned int norm_divisor_hi = (divisor_hi << norm_shift) | (divisor_lo >> denorm_shift);
            unsigned int norm_divisor_lo = divisor_lo << norm_shift;
            unsigned int norm_dividend_lo = dividend_lo << norm_shift;

            unsigned long long norm_dividend =
                ((unsigned long long)(dividend_hi >> denorm_shift) << 32) |
                ((dividend_hi << norm_shift) | (dividend_lo >> denorm_shift));

            // Estimate quotient and remainder
            unsigned int quot_estimate = (unsigned int)(norm_dividend / norm_divisor_hi);
            unsigned int rem_estimate = (unsigned int)(norm_dividend % norm_divisor_hi);

            // Compute product
            unsigned long long product = (unsigned long long)norm_divisor_lo * quot_estimate;
            unsigned long long rem_and_low = ((unsigned long long)rem_estimate << 32) | norm_dividend_lo;

            // Adjust if needed
            if (rem_and_low < product) {
                unsigned long long norm_divisor_full = ((unsigned long long)norm_divisor_hi << 32) | norm_divisor_lo;
                product = product - norm_divisor_full;
            }

            // Compute final remainder
            unsigned int rem_hi = rem_estimate - (unsigned int)(product >> 32);
            unsigned int borrow = (norm_dividend_lo < (unsigned int)product) ? 1 : 0;
            rem_hi = rem_hi - borrow;
            unsigned int rem_lo = norm_dividend_lo - (unsigned int)product;

            // Denormalize
            remainder = ((unsigned long long)(rem_hi >> norm_shift) << 32) |
                       ((rem_hi << denorm_shift) | (rem_lo >> norm_shift));
            return remainder;
        }

        // divisor is almost 2^63, check if we need to subtract
        if ((divisor_hi < dividend_hi) || (divisor_lo <= dividend_lo)) {
            // Subtract divisor from dividend
            unsigned int borrow = (dividend_lo < divisor_lo) ? 1 : 0;
            dividend_lo = dividend_lo - divisor_lo;
            dividend_hi = (dividend_hi - divisor_hi) - borrow;
        }
    }

    // Return remainder
    return ((unsigned long long)dividend_hi << 32) | dividend_lo;
}

@implementation ISASerialPort

/*
 * Probe for device presence.
 * Attempts to create an instance with the device description to verify device compatibility.
 *
 * Returns YES if device is compatible, NO otherwise.
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id instance;

    // Try to allocate and initialize an instance with this device description
    instance = [[ISASerialPort alloc] initFromDeviceDescription:deviceDescription];

    // If initialization succeeded, the device is compatible
    if (instance != nil) {
        // Free the test instance
        [instance free];
        return YES;
    }

    // Device is not compatible
    return NO;
}

/*
 * Initialize from device description.
 * Extracts configuration and initializes the serial port instance.
 */
- (id)initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    const char *portNumStr, *chipTypeStr, *portTypeStr;
    const char *rxBufStr, *txBufStr, *clockRateStr, *heartBeatStr;
    long portNum;
    unsigned int *portRanges;
    unsigned int *irqList;
    unsigned int chipType;
    unsigned int i;
    char portName[32];
    IOReturn result;
    unsigned long long hbInterval;
    unsigned int hbIntervalUS;
    BOOL disableFIFO;

    // Initialize offset 0x258 with pointer to offset 0x128
    *(void **)((char *)self + 0x258) = (char *)self + 0x128;
    *(id *)((char *)self + 0x128) = self;

    // Initialize all fields at specific offsets to zero
    *(unsigned int *)((char *)self + 300) = 0;      // 0x12c - port number
    *(void **)((char *)self + 0x130) = NULL;        // name pointer
    *(unsigned int *)((char *)self + 0x1b4) = 0;    // IRQ
    *(unsigned int *)((char *)self + 0x1cc) = 0;
    *(unsigned int *)((char *)self + 0x1d0) = 0;
    *(unsigned int *)((char *)self + 0x1dc) = 0x1c2000;  // clockRate = 1843200
    *(unsigned short *)((char *)self + 0x1d4) = 0;
    *(unsigned char *)((char *)self + 0x1d6) = 0;
    *(unsigned char *)((char *)self + 0x1d7) = 0;
    *(unsigned char *)((char *)self + 0x1d8) = 0;
    *(unsigned char *)((char *)self + 0x1d9) = 0;
    *(unsigned int *)((char *)self + 0x1b8) = 0;    // chipType (also used as hasFIFO)
    *(unsigned int *)((char *)self + 0x1b0) = 0;    // basePort
    *(unsigned int *)((char *)self + 0x1bc) = 0;
    *(unsigned int *)((char *)self + 0x1cc) = 0;
    *(unsigned int *)((char *)self + 0x1c0) = 0;
    *(unsigned int *)((char *)self + 0x1c4) = 0;
    *(unsigned int *)((char *)self + 0x1c8) = 0;
    *(unsigned char *)((char *)self + 0x1e1) = 0;
    *(unsigned char *)((char *)self + 0x1e0) = 0;
    *(unsigned char *)((char *)self + 0x1e3) = 0;   // pcmciaDetect
    *(unsigned char *)((char *)self + 0x1e4) = 0;
    *(unsigned char *)((char *)self + 0x1e5) = 0x11;  // xonChar
    *(unsigned char *)((char *)self + 0x1e6) = 0x13;  // xoffChar
    *(unsigned int *)((char *)self + 0x208) = 0;    // stateEventMask
    *(unsigned int *)((char *)self + 0x20c) = 0;
    *(void **)((char *)self + 0x210) = NULL;        // timer callout 1
    *(void **)((char *)self + 0x214) = NULL;        // timer callout 2
    *(void **)((char *)self + 0x220) = NULL;
    *(unsigned int *)((char *)self + 0x224) = 0;
    *(unsigned int *)((char *)self + 0x228) = 0;    // charTimeOverrideLow
    *(unsigned int *)((char *)self + 0x22c) = 0;    // charTimeOverrideHigh
    *(unsigned int *)((char *)self + 0x230) = 0;    // heartBeatInterval low
    *(unsigned int *)((char *)self + 0x234) = 0;    // heartBeatInterval high
    *(unsigned int *)((char *)self + 0x238) = 0;
    *(unsigned int *)((char *)self + 0x23c) = 0;
    *(unsigned int *)((char *)self + 0x134) = 0x60c0000;  // currentState
    *(unsigned int *)((char *)self + 0x138) = 0;
    *(unsigned int *)((char *)self + 0x13c) = 0;
    *(unsigned int *)((char *)self + 0x208) = 0x126;   // stateEventMask
    *(unsigned int *)((char *)self + 0x1a4) = 0x4b0;   // rxQueueCapacity default = 1200
    *(unsigned int *)((char *)self + 0x194) = 0;
    *(unsigned int *)((char *)self + 0x198) = 0;
    *(unsigned int *)((char *)self + 0x19c) = 0;
    *(unsigned int *)((char *)self + 400) = 0;
    *(unsigned int *)((char *)self + 0x178) = 0;
    *(unsigned int *)((char *)self + 0x17c) = 0;
    *(unsigned int *)((char *)self + 0x16c) = 0x4b0;   // txQueueCapacity default = 1200
    *(unsigned int *)((char *)self + 0x15c) = 0;
    *(unsigned int *)((char *)self + 0x160) = 0;
    *(unsigned int *)((char *)self + 0x164) = 0;
    *(unsigned int *)((char *)self + 0x158) = 0;
    *(unsigned int *)((char *)self + 0x140) = 0;
    *(unsigned int *)((char *)self + 0x144) = 0;
    *(unsigned int *)((char *)self + 0x168) = 0;

    // Clear character filter bitmap (8 dwords)
    for (i = 0; i < 8; i++) {
        *(unsigned int *)((char *)self + 0x1e8 + i * 4) = 0;
    }

    // Get port number from device description
    portNumStr = [deviceDescription valueForStringKey:"PortNum"];
    if (portNumStr == NULL) {
        IOLog("%s: Could not get port number from device description\n", [self name]);
        [self free];
        return nil;
    }

    portNum = strtol(portNumStr, NULL, 10);
    *(long *)((char *)self + 300) = portNum;

    // Create port name like "ISASerialPort0"
    sprintf(portName, "ISASerialPort%ld", portNum);
    [self setName:portName];
    [self setDeviceKind:"SerialPort"];
    *(const char **)((char *)self + 0x130) = [self name];

    // Get and validate Port configuration (base I/O address)
    if ([deviceDescription numPortRanges] != 1) {
        IOLog("%s: Invalid port configuration\n", [self name]);
        [self free];
        return nil;
    }

    portRanges = (unsigned int *)[deviceDescription portRangeList];
    *(unsigned int *)((char *)self + 0x1b0) = portRanges[0];  // basePort

    // Check that base port is aligned and size is 8
    if ((portRanges[0] & 3) != 0 || portRanges[1] != 8) {
        IOLog("%s: Port range 0x%04x size %d is invalid\n",
              [self name], portRanges[0], portRanges[1]);
        [self free];
        return nil;
    }

    // Get and validate IRQ
    irqList = (unsigned int *)[deviceDescription interruptList];
    *(unsigned int *)((char *)self + 0x1b4) = irqList[0];  // IRQ number

    // Get chip type from configuration if specified
    chipTypeStr = [deviceDescription valueForStringKey:"ChipType"];
    if (chipTypeStr != NULL) {
        // Try to match chip type string
        for (i = 0; i < 9; i++) {
            if (strcmp(chipTypeNames[i], chipTypeStr) == 0) {
                break;
            }
        }

        if (i == 9) {
            // Unknown chip type string
            IOLog("%s: Unknown chip type '%s'\n", [self name], chipTypeStr);
        } else {
            if (i != 0) {  // Not "Auto"
                *(unsigned int *)((char *)self + 0x1b8) = i;  // Set chipType
                IOLog("%s: Chip type forced to %s\n", [self name], chipTypeStr);
            }
        }
    }

    // Auto-detect chip type if not specified
    if (*(unsigned int *)((char *)self + 0x1b8) == 0) {
        chipType = _identifyChip(self);
        *(unsigned int *)((char *)self + 0x1b8) = chipType;
        if (chipType == 0) {
            IOLog("%s: No UART detected at base 0x%04x\n",
                  [self name], *(unsigned int *)((char *)self + 0x1b0));
            [self free];
            return nil;
        }
    }

    // Check for PCMCIA port type
    portTypeStr = [deviceDescription valueForStringKey:"PortType"];
    if (portTypeStr != NULL) {
        if (strncmp(portTypeStr, "PCMCIA", 7) == 0) {
            *(unsigned char *)((char *)self + 0x1e3) = 1;  // pcmciaDetect = TRUE
        }
    }

    // Initialize chip with default settings
    _initChip(self);

    // Allocate timer callout objects
    *(void **)((char *)self + 0x210) = thread_call_allocate(NULL, NULL);
    *(void **)((char *)self + 0x214) = thread_call_allocate(NULL, NULL);
    *(void **)((char *)self + 0x218) = thread_call_allocate(_delayTOHandler, (char *)self + 0x128);
    *(void **)((char *)self + 0x21c) = thread_call_allocate(_heartBeatTOHandler, (char *)self + 0x128);

    if (*(void **)((char *)self + 0x210) == NULL ||
        *(void **)((char *)self + 0x214) == NULL ||
        *(void **)((char *)self + 0x218) == NULL ||
        *(void **)((char *)self + 0x21c) == NULL) {
        IOLog("%s: Failed to allocate timer callouts\n", [self name]);
        [self free];
        return nil;
    }

    // Read RX buffer size from config
    rxBufStr = [deviceDescription valueForStringKey:"RXBufSize"];
    *(unsigned int *)((char *)self + 0x1a4) = 0x4b0;  // Default 1200
    if (rxBufStr != NULL) {
        unsigned int rxSize = (unsigned int)strtol(rxBufStr, NULL, 10);
        rxSize = _validateRingBufferSize(self, rxSize);
        *(unsigned int *)((char *)self + 0x1a4) = rxSize;
    }

    // Read TX buffer size from config
    txBufStr = [deviceDescription valueForStringKey:"TXBufSize"];
    *(unsigned int *)((char *)self + 0x16c) = 0x4b0;  // Default 1200
    if (txBufStr != NULL) {
        unsigned int txSize = (unsigned int)strtol(txBufStr, NULL, 10);
        txSize = _validateRingBufferSize(self, txSize);
        *(unsigned int *)((char *)self + 0x16c) = txSize;
    }

    // Read clock rate from config
    clockRateStr = [deviceDescription valueForStringKey:"ClockRate"];
    if (clockRateStr == NULL || (unsigned int)strtol(clockRateStr, NULL, 10) < 1000) {
        *(unsigned int *)((char *)self + 0x1dc) = 0x1c2000;  // Default 1843200
    } else {
        unsigned int clkRate = (unsigned int)strtol(clockRateStr, NULL, 10);
        *(unsigned int *)((char *)self + 0x1dc) = clkRate;
        IOLog("%s: Clock rate set to %d\n", [self name], clkRate);
    }

    // Read heartbeat interval from config
    heartBeatStr = [deviceDescription valueForStringKey:"HeartBeat"];
    if (heartBeatStr != NULL) {
        hbIntervalUS = (unsigned int)strtol(heartBeatStr, NULL, 10);
        IOLog("%s: Heart Beat Interval set to %ld us.\n", [self name], (long)hbIntervalUS);
        // Convert microseconds to nanoseconds (multiply by 1000)
        // Store as 64-bit value at offsets 0x230 (low) and 0x234 (high)
        hbInterval = (unsigned long long)hbIntervalUS * 1000ULL;
        *(unsigned int *)((char *)self + 0x230) = (unsigned int)hbInterval;
        *(unsigned int *)((char *)self + 0x234) = (unsigned int)(hbInterval >> 32);
    }

    // Calculate some 64-bit division values (purpose unclear from decompiled code)
    {
        unsigned int result_lo = __udivdi3(0, 0, 0, 0);
        unsigned int result_hi = __umoddi3(0, 0, 0, 0);
        *(unsigned int *)((char *)self + 0x238) = result_lo;
        *(unsigned int *)((char *)self + 0x23c) = result_hi;
    }

    // Check for FIFO disable flag
    disableFIFO = ([deviceDescription numFlagStrings] == 0);
    if (disableFIFO) {
        *(unsigned char *)((char *)self + 0x1d8) = 0xfb;  // Disable FIFO
    } else {
        *(unsigned char *)((char *)self + 0x1d8) = 0xff;  // Enable FIFO
        IOLog("%s: FIFO enabled by config\n", [self name]);
    }

    // Call superclass init
    result = [super initFromDeviceDescription:deviceDescription];
    if (!result) {
        IOLog("%s: superclass initFromDeviceDescription failed\n", [self name]);
        [self free];
        return nil;
    }

    // Register interrupts (returns 0 on success based on decompiled code)
    if ([self registerInterrupt:0] == 0) {
        IOLog("%s: Base=0x%04x, IRQ=%d, Type=%s%s, FIFO=%d\n",
              [self name],
              *(unsigned int *)((char *)self + 0x1b0),
              *(unsigned int *)((char *)self + 0x1b4),
              chipTypeNames[*(unsigned int *)((char *)self + 0x1b8)],
              (*(unsigned char *)((char *)self + 0x1e3) ? " (PCMCIA)" : ""),
              chipCapTable[*(unsigned int *)((char *)self + 0x1b8)].fifoSize);
        return self;
    }

    IOLog("%s: Failed to register interrupt\n", [self name]);
    [self free];
    return nil;
}

/*
 * Free the instance.
 * Cleans up all resources and deallocates the instance.
 */
- (void)free
{
    unsigned int oldIRQL;
    void **timer1Ptr, **timer2Ptr, **timer3Ptr, **timer4Ptr;

    // Raise interrupt level
    oldIRQL = spl4();

    // Deactivate the port (disables interrupts, frees ring buffers)
    _deactivatePort(self);

    // Disable all interrupts at hardware level
    [self disableAllInterrupts];

    // Cancel and free timer at offset 0x210
    timer1Ptr = (void **)((char *)self + 0x210);
    if (*timer1Ptr != NULL) {
        thread_call_cancel(*timer1Ptr);
        thread_call_free(*timer1Ptr);
    }

    // Cancel and free timer at offset 0x214
    timer2Ptr = (void **)((char *)self + 0x214);
    if (*timer2Ptr != NULL) {
        thread_call_cancel(*timer2Ptr);
        thread_call_free(*timer2Ptr);
    }

    // Cancel and free timer at offset 0x218
    timer3Ptr = (void **)((char *)self + 0x218);
    if (*timer3Ptr != NULL) {
        thread_call_cancel(*timer3Ptr);
        thread_call_free(*timer3Ptr);
    }

    // Cancel and free timer at offset 0x21c
    timer4Ptr = (void **)((char *)self + 0x21c);
    if (*timer4Ptr != NULL) {
        thread_call_cancel(*timer4Ptr);
        thread_call_free(*timer4Ptr);
    }

    splx(oldIRQL);

    // Call superclass free
    [super free];
}

/*
 * Acquire the serial port.
 * Sets up default serial port parameters and prepares the port for use.
 *
 * Parameters:
 *   refCon - Reference context (used as boolean sleep flag: 0 = don't sleep, 1 = sleep if busy)
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD3B if PCMCIA card was removed
 *   0xFFFFFD36 or other errors from watchState if interrupted while sleeping
 */
- (IOReturn)acquire:(void *)refCon
{
    unsigned int oldIRQL;
    unsigned int checkMask;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned char msrValue;
    unsigned int flowState;
    unsigned int msrStateBits;
    unsigned int eventMask;
    IOReturn result;
    int i;
    BOOL sleep = (refCon != NULL);

    // Acquisition state tracking
    // Note: offset 0x134 in decompiled code - using currentState's high bit as acquired flag
    checkMask = 0;

    // Loop until acquired or error
    while (1) {
        // Raise interrupt level
        oldIRQL = spl4();

        // Check if PCMCIA card was removed
        if (self->pcmciaYanked != 0) {
            splx(oldIRQL);
            return 0xFFFFFD3B; // Device not available
        }

        // Check if port is already acquired (bit 0x80000000 of checkMask/state)
        checkMask = self->currentState & 0x80000000;

        if (checkMask == 0) {
            // Port not acquired - proceed with acquisition

            // Set initial state to 0xA0400018
            // This includes: STATE_ACTIVE (0x40000000), RX enabled (0x80000), and other flags
            oldState = self->currentState;
            newState = 0xA0400018;
            changedBits = oldState ^ newState;
            self->currentState = newState;

            // Wake up any threads waiting on state changes
            if (self->watchStateMask & changedBits) {
                thread_wakeup_prim(&self->watchStateMask, 0, 4);
            }

            // Update DTR/RTS if they changed
            if (changedBits & STATE_FLOW_MASK) {
                outb(self->basePort + UART_MCR, MCR_OUT2);
                // Atomic increment (LOCK/UNLOCK omitted)
            }

            // Trigger timer callout
            if ((self->statusFlags & 0x10) == 0) {
                thread_call_enter(self->timerCallout);
            }

            // Enqueue state change event
            memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
            if (eventMask & (changedBits << 16)) {
                _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                                   (changedBits << 16) | 0x18);
            }

            // Clear character filter bitmap (8 words at offset 0x1e8)
            for (i = 0; i < 8; i++) {
                self->charFilterBitmap[i] = 0;
            }

            // Set default serial port parameters
            self->dataBits = 16;         // 16 = 8 data bits (encoded as 10/12/14/16 for 5/6/7/8)
            self->stopBits = 2;          // 2 = 1 stop bit
            self->xonChar = 0x11;        // DC1 (XON)
            self->xoffChar = 0x13;       // DC3 (XOFF)
            self->flowControl = 2;       // Flow control mode
            self->parity = PARITY_NONE;  // No parity
            self->flowControlState = 0;  // Initial flow control state
            self->baudRate = 19200;      // Default 19200 baud (0x4b00)
            self->clockRate = 0x126;     // UART clock rate (seems odd, might be scaled)
            self->flowControlMode = 0;   // Flow control mode flags

            // Set TX queue watermarks based on capacity
            // High watermark = capacity
            // Low watermark = (capacity * 2) / 3
            // Med watermark = low / 2
            self->txQueueHighWater = self->txQueueCapacity;
            unsigned int txLowWater = (self->txQueueCapacity * 2) / 3;
            self->txQueueLowWater = txLowWater;
            self->txQueueMedWater = txLowWater >> 1;

            // Clear some flag at offset 0x168 (unknown purpose)
            // *(undefined4 *)(param_1 + 0x168) = 0;

            // Set RX queue watermarks based on capacity
            // High watermark = capacity
            // Low watermark = (capacity * 2) / 3
            // Target = low watermark
            self->rxQueueHighWater = self->rxQueueCapacity;
            unsigned int rxLowWater = (self->rxQueueCapacity * 2) / 3;
            self->rxQueueLowWater = rxLowWater;
            self->rxQueueTarget = rxLowWater;

            // Clear some field at offset 0x1d4 (unknown)
            // *(undefined2 *)(param_1 + 0x1d4) = 0;

            // Program the UART chip
            _programChip(self);

            // Disable most UART interrupts (keep only bit 3 if set in ierValue)
            outb(self->basePort + UART_IER, self->ierValue & 0x08);
            // Atomic increment

            // Calculate flow control state
            flowState = _flowMachine(self);

            // Read Modem Status Register
            msrValue = inb(self->basePort + UART_MSR);

            // Convert MSR delta bits to state bits using lookup table
            msrStateBits = _msr_state_lut[msrValue >> 4];

            // Update state with flow control and MSR bits
            oldState = self->currentState;
            newState = (oldState & 0xFFFFFE09) | (flowState & 0x1F6) | (msrStateBits << 5);
            changedBits = oldState ^ newState;
            self->currentState = newState;

            // Wake up threads
            if (self->watchStateMask & changedBits) {
                thread_wakeup_prim(&self->watchStateMask, 0, 4);
            }

            // Update DTR/RTS if changed
            if (changedBits & STATE_FLOW_MASK) {
                mcrValue = MCR_OUT2;
                if (flowState & STATE_DTR) {
                    mcrValue |= MCR_DTR;
                }
                if (flowState & STATE_RTS) {
                    mcrValue |= MCR_RTS;
                }
                outb(self->basePort + UART_MCR, mcrValue);
                // Atomic increment
            }

            // Trigger timer callout
            if ((self->statusFlags & 0x10) == 0) {
                thread_call_enter(self->timerCallout);
            }

            // Enqueue state change event
            memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
            if (eventMask & (changedBits << 16)) {
                _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                                   ((oldState & 0xFE09) | (flowState & 0x1F6) | (msrStateBits << 5)) |
                                   (changedBits << 16));
            }

            // Start heartbeat timer if interval is set
            // Check if heartBeatInterval is non-zero
            if (self->heartBeatInterval != 0) {
                thread_call_enter(self->heartBeatCallout);
            } else {
                // Use frame timeout timer instead
                thread_call_enter(self->timerCallout);
            }

            splx(oldIRQL);
            return IO_R_SUCCESS;
        }

        // Port already acquired
        if (!sleep) {
            // Not sleeping - return error immediately
            splx(oldIRQL);
            return 0xFFFFFD3B; // Device busy
        }

        // Sleep until port becomes available
        // Wait for bit 0x80000000 to clear
        result = [self watchState:&checkMask mask:0x80000000];

        splx(oldIRQL);

        // Check result of watchState
        if (result == 0xFFFFFD36) {
            // Interrupted - try again
            continue;
        }

        if (result != IO_R_SUCCESS) {
            // Error occurred
            return result;
        }

        // Loop will retry acquisition
    }

    // Should never reach here
    return 0xFFFFFD3B;
}

/*
 * Release the serial port.
 * Resets port to default configuration and clears the acquired flag.
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFFD33 if port was not acquired
 */
- (IOReturn)release
{
    unsigned int oldIRQL;
    unsigned int i;
    unsigned int txWaterLow, txWaterMed;
    unsigned int rxWaterHigh, rxWaterLow;
    ISASerialPort *selfPtr;
    unsigned int oldState, changedBits;

    oldIRQL = spl4();

    // Check if port is acquired (offset 0x134 = currentState, check if negative/high bit set)
    if (*(int *)((char *)self + 0x134) < 0) {
        // Cancel all 4 timer callouts
        thread_call_cancel(*(void **)((char *)self + 0x21c));
        thread_call_cancel(*(void **)((char *)self + 0x218));
        thread_call_cancel(*(void **)((char *)self + 0x214));
        thread_call_cancel(*(void **)((char *)self + 0x210));

        // Clear character filter bitmap (8 dwords at offset 0x1e8)
        for (i = 0; i < 8; i++) {
            *(unsigned int *)((char *)self + 0x1e8 + i * 4) = 0;
        }

        // Set default configuration values
        *(unsigned int *)((char *)self + 0x1bc) = 0x10;     // dataBits = 16 (8 data bits)
        *(unsigned int *)((char *)self + 0x1cc) = 2;        // stopBits = 2 (1 stop bit)
        *(unsigned char *)((char *)self + 0x1e5) = 0x11;    // xonChar = DC1
        *(unsigned char *)((char *)self + 0x1e6) = 0x13;    // xoffChar = DC3
        *(unsigned int *)((char *)self + 0x1c0) = 2;        // parity = ODD
        *(unsigned int *)((char *)self + 0x1c4) = 1;        // flowControl = 1
        *(unsigned int *)((char *)self + 0x1c8) = 0;
        *(unsigned int *)((char *)self + 0x20c) = 0;
        *(unsigned int *)((char *)self + 0x1d0) = 0x4b00;   // baudRate = 19200
        *(unsigned int *)((char *)self + 0x208) = 0x126;    // stateEventMask

        // Set TX buffer size and calculate watermarks
        // offset 0x140 = TX queue size, offset 0x16c = TX queue capacity default
        *(int *)((char *)self + 0x140) = *(int *)((char *)self + 0x16c);
        txWaterLow = (unsigned int)(*(int *)((char *)self + 0x16c) * 2) / 3;
        *(unsigned int *)((char *)self + 0x148) = txWaterLow;      // TX low watermark
        *(unsigned int *)((char *)self + 0x14c) = txWaterLow >> 1;  // TX med watermark
        *(unsigned int *)((char *)self + 0x168) = 0;

        // Set RX buffer size and calculate watermarks
        // offset 0x178 = RX queue size, offset 0x1a4 = RX queue capacity default
        *(int *)((char *)self + 0x178) = *(int *)((char *)self + 0x1a4);
        rxWaterHigh = (unsigned int)(*(int *)((char *)self + 0x1a4) * 2) / 3;
        *(unsigned int *)((char *)self + 0x180) = rxWaterHigh;      // RX high watermark
        *(unsigned int *)((char *)self + 0x184) = rxWaterHigh >> 1;  // RX low watermark

        // Program chip with default settings (pass value at offset 600)
        _programChip(*(ISASerialPort **)((char *)self + 600));

        // Deactivate port (pass value at offset 600)
        _deactivatePort(*(ISASerialPort **)((char *)self + 600));

        // Update state and wake waiting threads
        selfPtr = *(ISASerialPort **)((char *)self + 600);
        oldState = *(unsigned int *)((char *)selfPtr + 0xc);  // currentState at offset 0xc from selfPtr
        *(unsigned int *)((char *)selfPtr + 0xc) = 0;  // Clear state
        changedBits = oldState;  // All bits changed since we cleared to 0

        // Wake threads waiting on state changes
        if ((*(unsigned int *)((char *)selfPtr + 0x10) & changedBits) != 0) {
            thread_wakeup_prim((char *)selfPtr + 0x10, 0, 4);
        }

        // Update modem control register if DTR/RTS changed
        if ((changedBits & 6) != 0) {
            OUTB(*(unsigned short *)((char *)selfPtr + 0x88) + UART_MCR, 8);
        }

        // Trigger timer if needed
        if ((*(unsigned char *)((char *)selfPtr + 0xf) & 0x10) == 0) {
            thread_call_enter(*(void **)((char *)selfPtr + 0xe8));
        }

        // Enqueue state change event if mask matches
        if ((*(unsigned int *)((char *)selfPtr + 0xe0) & (changedBits << 16)) != 0) {
            _RX_enqueueLongEvent(selfPtr, 0x53, changedBits << 16);
        }

        // Disable UART interrupts (IER = 0)
        OUTB(*(unsigned short *)((char *)*(ISASerialPort **)((char *)self + 600) + 0x88) + UART_IER, 0);

        // Clear modem control register (MCR = 0)
        OUTB(*(unsigned short *)((char *)*(ISASerialPort **)((char *)self + 600) + 0x88) + UART_MCR, 0);

        splx(oldIRQL);
        return IO_R_SUCCESS;
    } else {
        // Port was not acquired
        splx(oldIRQL);
        return 0xFFFFFFD33;
    }
}

/*
 * Dequeue data from the serial port.
 * Reads data bytes from the RX queue with optional character timeout support.
 *
 * Parameters:
 *   buffer - Destination buffer for received data
 *   size - Size of buffer (maximum bytes to read)
 *   count - Output: number of bytes actually read
 *   minCount - Minimum bytes to read before returning (used for sleeping)
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD3E if parameters are invalid
 *   0xFFFFFD33 if port is not active
 *   Other errors from _RX_dequeueData
 */
- (IOReturn)dequeueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
               minCount:(unsigned int)minCount
{
    unsigned int oldIRQL;
    IOReturn result;
    unsigned char *writePtr;
    unsigned int remainingMin;
    int timerScheduled;
    unsigned int charTimeLo, charTimeHi;
    unsigned long long deadline;

    // Validate parameters
    if (count == NULL || buffer == NULL || size < minCount) {
        return 0xFFFFFD3E; // Invalid argument
    }

    // Get character time override values (offset 0x228 = charTimeOverrideLow, 0x22c = charTimeOverrideHigh)
    charTimeLo = self->charTimeOverrideLow;
    charTimeHi = self->charTimeOverrideHigh;

    // Determine if we should schedule a timeout timer
    // Timer is scheduled if character time is set and buffer size > 1
    timerScheduled = 0;
    if (((unsigned long long)charTimeLo * 1000000000ULL + (long long)charTimeHi) != 0 && size > 1) {
        timerScheduled = 1;
    }

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is active (statusFlags at offset 0x137 & 0x40)
    if ((self->statusFlags & 0x40) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not active
    }

    // Initialize output count
    *count = 0;
    writePtr = buffer;
    remainingMin = minCount;
    result = IO_R_SUCCESS;

    // Dequeue bytes until buffer is full or error
    while (size > 0) {
        size--;

        // Dequeue one byte from RX queue
        result = _RX_dequeueData(self, writePtr, (remainingMin != 0));

        if (result != IO_R_SUCCESS) {
            // Error occurred or no more data
            // If error is 0xFFFFFD42 (no data available), convert to success
            if (result == 0xFFFFFD42) {
                result = IO_R_SUCCESS;
            }
            break;
        }

        // Decrement remaining minimum count if non-zero
        if (remainingMin != 0) {
            remainingMin--;
        }

        // Increment count and buffer pointer
        (*count)++;
        writePtr++;

        // Schedule character timeout timer after first byte if enabled
        if (timerScheduled > 0) {
            deadline = deadline_from_interval(charTimeLo, charTimeHi);
            thread_call_enter_delayed(self->delayTimeoutCallout, deadline);
            timerScheduled = -1;  // Mark as scheduled
        }
    }

    // Cancel character timeout timer if it was scheduled
    if (timerScheduled < 0) {
        thread_call_cancel(self->delayTimeoutCallout);
    }

    splx(oldIRQL);
    return result;
}

/*
 * Dequeue an event from the serial port.
 * Retrieves an event from the RX event queue.
 *
 * Parameters:
 *   event - Output: event type (byte value)
 *   data - Output: event data (up to 32-bit value)
 *   sleep - If YES, sleep waiting for event; if NO, return immediately
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD3E if parameters are invalid
 *   0xFFFFFD33 if port is not active
 *   Other errors from _RX_dequeueEvent
 */
- (IOReturn)dequeueEvent:(unsigned int *)event
                    data:(unsigned int *)data
                   sleep:(BOOL)sleep
{
    unsigned int oldIRQL;
    IOReturn result;
    unsigned char eventType;

    // Validate parameters
    if (event == NULL || data == NULL) {
        return 0xFFFFFD3E; // Invalid argument
    }

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is active (statusFlags at offset 0x137 & 0x40)
    if ((self->statusFlags & 0x40) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not active
    }

    // Dequeue event from RX queue
    result = _RX_dequeueEvent(self, &eventType, data, sleep);

    // Convert event type from byte to unsigned int
    *event = (unsigned int)eventType;

    splx(oldIRQL);
    return result;
}

/*
 * Enqueue data to the serial port.
 * Writes data bytes to the TX queue for transmission.
 *
 * Parameters:
 *   buffer - Source buffer containing data to send
 *   size - Number of bytes to send
 *   count - Output: number of bytes actually enqueued
 *   sleep - If YES, sleep if queue is full; if NO, return immediately
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD3E if parameters are invalid
 *   0xFFFFFD33 if port is not active
 *   0xFFFFFD42 if queue is full and not sleeping
 *   Other errors from watchState
 */
- (IOReturn)enqueueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
                  sleep:(BOOL)sleep
{
    unsigned int oldIRQL;
    unsigned int remainingSize;
    unsigned char *readPtr;
    unsigned int freeSpace;
    unsigned int chunkSize;
    unsigned int spaceToEnd;
    unsigned int i;
    unsigned int checkMask;
    IOReturn result;
    unsigned int txState;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned int eventMask;
    void **txTimerPtr;

    // Validate parameters
    if (count == NULL || buffer == NULL) {
        return 0xFFFFFD3E; // Invalid argument
    }

    // Initialize output count
    *count = 0;

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is active (statusFlags at offset 0x137 & 0x40)
    if ((self->statusFlags & 0x40) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not active
    }

    remainingSize = size;
    readPtr = buffer;

    // Loop until all data is enqueued
    while (remainingSize != 0) {
        // Calculate free space in TX queue
        freeSpace = self->txQueueCapacity - self->txQueueUsed;

        // Wait for space if queue is full
        while (freeSpace == 0) {
            if (!sleep) {
                // Not sleeping - return error
                splx(oldIRQL);
                return 0xFFFFFD42; // Queue full
            }

            // Sleep waiting for TX queue to have space (TX_STATE_EMPTY bit 0x800000)
            checkMask = 0;
            result = _watchState(self, &checkMask, 0x800000);

            if (result != IO_R_SUCCESS) {
                splx(oldIRQL);
                return result;
            }

            // Recalculate free space after waking
            freeSpace = self->txQueueCapacity - self->txQueueUsed;
        }

        // Calculate how much we can enqueue in this iteration
        chunkSize = remainingSize;

        // Limit by free space
        if (freeSpace < chunkSize) {
            chunkSize = freeSpace;
        }

        // Limit by distance to end of circular buffer
        // Each entry is 2 bytes, so divide by 2
        spaceToEnd = ((unsigned int)self->txQueueEnd - (unsigned int)self->txQueueWrite) >> 1;
        if (spaceToEnd < chunkSize) {
            chunkSize = spaceToEnd;
        }

        // Update counters
        remainingSize -= chunkSize;
        self->txQueueUsed += chunkSize;
        *count += chunkSize;

        // Enqueue bytes in TX queue format (0x55 marker + data byte)
        for (i = 0; i < chunkSize; i++) {
            // Write marker byte (0x55 = 'U')
            *(unsigned char *)self->txQueueWrite = 0x55;
            self->txQueueWrite = (char *)self->txQueueWrite + 1;

            // Write data byte
            *(unsigned char *)self->txQueueWrite = *readPtr;
            readPtr++;
            self->txQueueWrite = (char *)self->txQueueWrite + 1;
        }

        // Wrap write pointer if at end
        if (self->txQueueWrite >= self->txQueueEnd) {
            self->txQueueWrite = self->txQueueStart;
        }

        // Update TX state based on watermark levels
        if (self->txQueueUsed >= self->txQueueHighWater) {
            // Used >= highWater
            if (self->txQueueUsed > self->txQueueMedWater) {
                // Used > medWater
                if (self->txQueueUsed > self->txQueueLowWater) {
                    // Used > lowWater (critical/above high)
                    self->txQueueHighWater = self->txQueueCapacity - 3;
                    if (self->txQueueUsed > (self->txQueueCapacity - 3)) {
                        // Critical level
                        self->txQueueTarget = self->txQueueCapacity;
                        txState = 0x1800000;
                    } else {
                        // Above high watermark
                        self->txQueueTarget = self->txQueueLowWater;
                        txState = 0x1000000;
                    }
                } else {
                    // medWater < used <= lowWater
                    self->txQueueHighWater = self->txQueueLowWater;
                    self->txQueueTarget = self->txQueueMedWater;
                    txState = 0;
                }
            } else {
                // Used <= medWater
                self->txQueueTarget = 0;
                if (self->txQueueUsed == 0) {
                    // Empty
                    self->txQueueHighWater = 0;
                    txState = TX_STATE_EMPTY;
                } else {
                    // Below medium watermark
                    self->txQueueHighWater = self->txQueueMedWater;
                    txState = TX_STATE_BELOW_LOW;
                }
            }

            // Update current state with new TX state
            oldState = self->currentState;
            newState = (oldState & 0xF87FFFFF) | txState;
            changedBits = oldState ^ newState;
            self->currentState = newState;

            // Wake up threads waiting on state changes
            if (self->watchStateMask & changedBits) {
                thread_wakeup_prim(&self->watchStateMask, 0, 4);
            }

            // Update DTR/RTS if they changed
            if (changedBits & STATE_FLOW_MASK) {
                mcrValue = MCR_OUT2;
                if (oldState & STATE_DTR) {
                    mcrValue |= MCR_DTR;
                }
                if (oldState & STATE_RTS) {
                    mcrValue |= MCR_RTS;
                }
                outb(self->basePort + UART_MCR, mcrValue);
                // Atomic increment (LOCK/UNLOCK omitted)
            }

            // Trigger timer callout
            if ((self->statusFlags & 0x10) == 0) {
                thread_call_enter(self->timerCallout);
            }

            // Enqueue state change event
            memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
            if (eventMask & (changedBits << 16)) {
                _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                                   (oldState & 0xFFFF) | (changedBits << 16));
            }
        }

        // Trigger TX operation timer if not paused
        if ((self->statusFlags & 0x10) == 0) {
            txTimerPtr = (void **)((char *)self + 0x210);
            thread_call_enter(*txTimerPtr);
        }
    }

    splx(oldIRQL);
    return IO_R_SUCCESS;
}

/*
 * Enqueue an event to the serial port.
 * Queues a control event to the TX event queue for processing.
 *
 * Parameters:
 *   event - Event type (low byte is used as event type)
 *   data - Event data (32-bit value)
 *   sleep - If YES, sleep if queue is full; if NO, return immediately
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD33 if port is not active
 *   Other errors from _TX_enqueueEvent
 */
- (IOReturn)enqueueEvent:(unsigned int)event
                    data:(unsigned int)data
                   sleep:(BOOL)sleep
{
    unsigned int oldIRQL;
    IOReturn result;
    void **txTimerPtr;

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is active (statusFlags at offset 0x137 & 0x40)
    if ((self->statusFlags & 0x40) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not active
    }

    // Enqueue event to TX queue
    // Extract event type (low byte) and pass data
    result = _TX_enqueueEvent(self, (unsigned char)(event & 0xFF), data, sleep);

    // If successful and port not paused, trigger TX timer
    if (result == IO_R_SUCCESS && (self->statusFlags & 0x10) == 0) {
        // Access timer at offset 0x210 (TX operation timer)
        // This is a field not yet defined in the header - likely txOperationCallout
        txTimerPtr = (void **)((char *)self + 0x210);
        thread_call_enter(*txTimerPtr);
    }

    splx(oldIRQL);
    return result;
}

/*
 * Execute an event.
 * Immediately executes a control event on the serial port.
 *
 * Parameters:
 *   event - Event type
 *   data - Event data
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD33 if port is not acquired
 *   0xFFFFFD2B if trying to change buffer size while port is active
 *   Other errors from _executeEvent
 */
- (IOReturn)executeEvent:(unsigned int)event
                    data:(unsigned int)data
{
    unsigned int oldIRQL;
    IOReturn result;
    unsigned int changedBits, newState;
    unsigned int oldState;
    unsigned char mcrValue;
    unsigned int flowState;
    unsigned int eventMask;
    unsigned int validatedSize;
    unsigned int heartbeatLo, heartbeatHi;

    result = IO_R_SUCCESS;

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is acquired (bit 0x80000000 of currentState must be set)
    if ((self->currentState & 0x80000000) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not acquired
    }

    // Handle special event types
    if (event == 0x0F) {
        // Set RX buffer size (offset 0x140 = txQueueCapacity in wrong place?)
        // Actually this seems to be setting a different buffer size
        // Based on offset 0x140, this is setting TX queue capacity
        if ((self->statusFlags & 0x40) != 0) {
            // Port is active - cannot change buffer size
            result = 0xFFFFFD2B;
        } else {
            // Port not active - can change buffer size
            validatedSize = _validateRingBufferSize(data, self);
            // Store at offset 0x140 - this appears to be txQueueCapacity field
            self->txQueueCapacity = validatedSize;

            // Adjust high watermark if necessary
            if ((validatedSize - 3) < self->txQueueLowWater) {
                self->txQueueLowWater = validatedSize - 3;
            }

            // Adjust medium watermark if necessary
            if ((self->txQueueLowWater - 3) < self->txQueueMedWater) {
                self->txQueueMedWater = self->txQueueLowWater - 3;
            }
        }
    } else if (event == 0x0B) {
        // Set TX buffer size (offset 0x178 = rxQueueCapacity)
        // Actually setting RX queue capacity based on offset
        if ((self->statusFlags & 0x40) != 0) {
            // Port is active - cannot change buffer size
            result = 0xFFFFFD2B;
        } else {
            // Port not active - can change buffer size
            validatedSize = _validateRingBufferSize(data, self);
            // Store at offset 0x178 - this is rxQueueCapacity
            self->rxQueueCapacity = validatedSize;

            // Adjust high watermark if necessary
            if ((validatedSize - 3) < self->rxQueueHighWater) {
                self->rxQueueHighWater = validatedSize - 3;
            }

            // Adjust low watermark if necessary
            if ((self->rxQueueHighWater - 3) < self->rxQueueLowWater) {
                self->rxQueueLowWater = self->rxQueueHighWater - 3;
            }
        }
    } else if (event == 0x4B) {
        // Set heartbeat interval (event 0x4B from _executeEvent)
        // Convert from microseconds to nanoseconds and store as 64-bit value
        heartbeatLo = __udivdi3(data * 1000, 0, 1000000000, 0);
        heartbeatHi = __umoddi3(data * 1000, 0, 1000000000, 0);
        // Store at offsets 0x230 and 0x234
        // These seem to be different from heartBeatInterval (0x110)
        // Likely charTimeOverrideLow/High or similar
        *((unsigned int *)((char *)self + 0x230)) = heartbeatLo;
        *((unsigned int *)((char *)self + 0x234)) = heartbeatHi;
    } else if (event == 0x53) {
        // External state change event
        // Update state event mask at offset 0x208
        changedBits = data ^ *((unsigned int *)((char *)self + 0x208));
        *((unsigned int *)((char *)self + 0x208)) = data & 0xFFFF017E;

        // If flow control bits changed
        if ((changedBits & 0x16) != 0) {
            // If hardware flow control bit (0x10) changed
            if ((changedBits & 0x10) != 0) {
                // Reset flow control state
                self->flowControlState = 0;
            }

            // Recalculate flow control state
            flowState = _flowMachine(self);

            // Update current state with new flow control bits
            oldState = self->currentState;
            newState = (oldState & 0xFFFFFFE9) | (flowState & 0x16);
            changedBits = oldState ^ newState;
            self->currentState = newState;

            // Wake up threads
            if (self->watchStateMask & changedBits) {
                thread_wakeup_prim(&self->watchStateMask, 0, 4);
            }

            // Update DTR/RTS
            if (changedBits & STATE_FLOW_MASK) {
                mcrValue = MCR_OUT2;
                if (flowState & STATE_DTR) {
                    mcrValue |= MCR_DTR;
                }
                if (flowState & STATE_RTS) {
                    mcrValue |= MCR_RTS;
                }
                outb(self->basePort + UART_MCR, mcrValue);
                // Atomic increment
            }

            // Trigger timer
            if ((self->statusFlags & 0x10) == 0) {
                thread_call_enter(self->timerCallout);
            }

            // Enqueue state change event
            memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
            if (eventMask & (changedBits << 16)) {
                _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                                   ((oldState & 0xFFE9) | (flowState & 0x16)) | (changedBits << 16));
            }
        }
    } else {
        // All other events - call _executeEvent
        changedBits = 0;
        newState = self->currentState;

        result = _executeEvent(self, (unsigned char)event, data, &newState, &changedBits);

        // Update state with changes
        oldState = self->currentState;
        newState = (changedBits & newState) | (~changedBits & oldState);
        changedBits = oldState ^ newState;
        self->currentState = newState;

        // Wake up threads
        if (self->watchStateMask & changedBits) {
            thread_wakeup_prim(&self->watchStateMask, 0, 4);
        }

        // Update DTR/RTS
        if (changedBits & STATE_FLOW_MASK) {
            mcrValue = MCR_OUT2;
            if (newState & STATE_DTR) {
                mcrValue |= MCR_DTR;
            }
            if (newState & STATE_RTS) {
                mcrValue |= MCR_RTS;
            }
            outb(self->basePort + UART_MCR, mcrValue);
            // Atomic increment
        }

        // Trigger timer
        if ((self->statusFlags & 0x10) == 0) {
            thread_call_enter(self->timerCallout);
        }

        // Enqueue state change event
        memcpy(&eventMask, &self->flowControlMode, sizeof(unsigned int));
        if (eventMask & (changedBits << 16)) {
            _RX_enqueueLongEvent(self, EVENT_STATE_CHANGE,
                               (newState & 0xFFFF) | (changedBits << 16));
        }
    }

    splx(oldIRQL);
    return result;
}

/*
 * Request an event.
 * Queries information about the port based on the event type.
 *
 * Parameters:
 *   event - Event type to query (low byte contains event code)
 *   data - Output: data value for the query
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD3E if data pointer is NULL or event type is unknown
 */
- (IOReturn)requestEvent:(unsigned int)event
                    data:(unsigned int *)data
{
    unsigned long long timeValue;
    unsigned int result;

    // Check if data pointer is valid
    if (data == NULL) {
        return 0xFFFFFD3E;
    }

    // Handle different query types based on event low byte
    switch (event & 0xFF) {
        case 0x05: // TX Enable state (bit 30 of currentState)
            *data = (*(unsigned int *)((char *)self + 0x134) >> 30) & 1;
            return 0;

        case 0x0B: // RX buffer capacity (offset 0x178)
            *data = *(unsigned int *)((char *)self + 0x178);
            return 0;

        case 0x0F: // TX buffer capacity (offset 0x140)
            *data = *(unsigned int *)((char *)self + 0x140);
            return 0;

        case 0x13: // RX low watermark (offset 0x184)
            *data = *(unsigned int *)((char *)self + 0x184);
            return 0;

        case 0x17: // TX med watermark (offset 0x14c)
            *data = *(unsigned int *)((char *)self + 0x14c);
            return 0;

        case 0x1B: // RX high watermark (offset 0x180)
            *data = *(unsigned int *)((char *)self + 0x180);
            return 0;

        case 0x1F: // TX low watermark (offset 0x148)
            *data = *(unsigned int *)((char *)self + 0x148);
            return 0;

        case 0x23: // RX available data count (RX capacity - used)
            *data = *(int *)((char *)self + 0x178) - *(int *)((char *)self + 0x17c);
            return 0;

        case 0x27: // TX free space count (TX capacity - used)
            *data = *(int *)((char *)self + 0x140) - *(int *)((char *)self + 0x17c);
            return 0;

        case 0x33: // Baud rate (offset 0x1d0)
            *data = *(unsigned int *)((char *)self + 0x1d0);
            return 0;

        case 0x37: // Always returns 0
            *data = 0;
            return 0;

        case 0x3B: // Data bits (offset 0x1bc)
            *data = *(unsigned int *)((char *)self + 0x1bc);
            return 0;

        case 0x3F: // Always returns 0
            *data = 0;
            return 0;

        case 0x43: // Flow control (offset 0x1c4)
            *data = *(unsigned int *)((char *)self + 0x1c4);
            return 0;

        case 0x47: // Flow control state? (offset 0x1c8)
            *data = *(unsigned int *)((char *)self + 0x1c8);
            return 0;

        case 0x4B: // Heartbeat interval (offset 0x230-0x234, 64-bit ns, convert to us)
            timeValue = *(unsigned long long *)((char *)self + 0x230);
            result = __udivdi3((unsigned int)(timeValue * 1000000000ULL),
                              (unsigned int)((timeValue * 1000000000ULL) >> 32),
                              1000, 0);
            *data = result;
            return 0;

        case 0x4F: // Character time override (offset 0x228-0x22c, 64-bit ns, convert to us)
            timeValue = *(unsigned long long *)((char *)self + 0x228);
            result = __udivdi3((unsigned int)(timeValue * 1000000000ULL),
                              (unsigned int)((timeValue * 1000000000ULL) >> 32),
                              1000, 0);
            *data = result;
            return 0;

        case 0x53: // State event mask (offset 0x208)
            *data = *(unsigned int *)((char *)self + 0x208);
            return 0;

        case 0xE5: // Some boolean flag (offset 0x1e0, return 0 or 1)
            *data = (unsigned int)(*(char *)((char *)self + 0x1e0) != 0);
            return 0;

        case 0xE9: // XOFF character (offset 0x1e6)
            *data = (unsigned int)*(unsigned char *)((char *)self + 0x1e6);
            return 0;

        case 0xED: // XON character (offset 0x1e5)
            *data = (unsigned int)*(unsigned char *)((char *)self + 0x1e5);
            return 0;

        case 0xF3: // Parity (offset 0x1c0)
            *data = *(unsigned int *)((char *)self + 0x1c0);
            return 0;

        case 0xF7: // Always returns 0
            *data = 0;
            return 0;

        case 0xF9: // RX Enable state (bit 11 of currentState)
            *data = (*(unsigned int *)((char *)self + 0x134) >> 11) & 1;
            return 0;

        default:
            // Unknown event type
            return 0xFFFFFD3E;
    }
}

/*
 * Get the next event.
 * Peeks at the RX queue to see if an event is available.
 *
 * Returns:
 *   Event type byte if an event is queued, 0 otherwise
 */
- (unsigned int)nextEvent
{
    unsigned int oldIRQL;
    unsigned char eventByte = 0;
    unsigned char *readPtr;

    oldIRQL = spl4();

    // Check if RX queue has any data (offset 0x144 = rxQueueUsed)
    if (*(unsigned int *)((char *)self + 0x144) != 0) {
        // Get read pointer (offset 0x164)
        readPtr = *(unsigned char **)((char *)self + 0x164);

        // Check if read pointer needs to wrap around
        // If readPtr >= rxQueueEnd (offset 0x15c), wrap by subtracting queue size
        if (readPtr >= *(unsigned char **)((char *)self + 0x15c)) {
            readPtr = readPtr - (*(int *)((char *)self + 0x140) * 2);
        }

        // Return the byte at the read position
        eventByte = *readPtr;
    }

    splx(oldIRQL);
    return (unsigned int)eventByte;
}

/*
 * Get the current state.
 * Returns the current port state word containing all status flags.
 * Note: Bit 0x1000 is masked off before returning.
 */
- (unsigned int)getState
{
    return self->currentState & ~0x1000;
}

/*
 * Set the state with mask.
 * Updates the port state using the provided mask.
 *
 * Parameters:
 *   state - New state value (64-bit, but only low 32 bits used)
 *   mask - Mask of bits to update (64-bit, but only low 32 bits used)
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFFD3E if invalid state bits are set
 *   0xFFFFFFD33 if port not acquired
 */
- (IOReturn)setState:(unsigned int)state
                mask:(unsigned int)mask
{
    unsigned int oldIRQL;
    ISASerialPort *selfPtr;
    unsigned int effectiveMask;
    unsigned int newState, oldState, changedBits;
    unsigned char mcrValue;

    // Check for invalid high bits (bits in 0xc000100000000000 when viewed as 64-bit)
    // In 32-bit world, this checks the high dword passed on stack
    // For now, we'll just proceed with the low 32 bits

    oldIRQL = spl4();

    // Get self pointer from offset 600
    selfPtr = *(ISASerialPort **)((char *)self + 600);

    // Check if port is acquired (offset 0xc from selfPtr = currentState, check high bit)
    if (*(int *)((char *)selfPtr + 0xc) < 0) {
        // Calculate effective mask: clear bits not in stateEventMask (offset 0x208)
        // But keep all high 16 bits (| 0xffff0000)
        effectiveMask = mask & (~*(unsigned int *)((char *)self + 0x208) | 0xffff0000);

        if (effectiveMask != 0) {
            // Update state with mask
            oldState = *(unsigned int *)((char *)selfPtr + 0xc);
            newState = (~effectiveMask & oldState) | (state & effectiveMask);
            changedBits = newState ^ oldState;
            *(unsigned int *)((char *)selfPtr + 0xc) = newState;

            // Wake threads waiting on state changes (watchStateMask at offset 0x10 from selfPtr)
            if ((*(unsigned int *)((char *)selfPtr + 0x10) & changedBits) != 0) {
                thread_wakeup_prim((char *)selfPtr + 0x10, 0, 4);
            }

            // Update MCR if DTR/RTS bits changed (bits 1 and 2)
            if ((changedBits & 6) != 0) {
                mcrValue = 8;  // OUT2 enabled
                if ((newState & 2) != 0) {  // DTR
                    mcrValue |= 1;
                }
                if ((newState & 4) != 0) {  // RTS
                    mcrValue |= 2;
                }
                OUTB(*(unsigned short *)((char *)selfPtr + 0x88) + UART_MCR, mcrValue);
            }

            // Trigger timer if needed (check flag at offset 0xf from selfPtr)
            if ((*(unsigned char *)((char *)selfPtr + 0xf) & 0x10) == 0) {
                thread_call_enter(*(void **)((char *)selfPtr + 0xe8));
            }

            // Enqueue state change event if monitored bits changed
            // Check stateEventMask at offset 0xe0 against changed bits shifted left 16
            if ((*(unsigned int *)((char *)selfPtr + 0xe0) & (changedBits << 16)) != 0) {
                _RX_enqueueLongEvent(selfPtr, 0x53, (newState & 0xffff) | (changedBits << 16));
            }
        }

        splx(oldIRQL);
        return IO_R_SUCCESS;
    } else {
        splx(oldIRQL);
        return 0xFFFFFFD33;  // Port not acquired
    }
}

/*
 * Watch state with mask.
 * Waits until the masked state bits change from their current values.
 *
 * Parameters:
 *   state - Pointer to receive the new state value (masked with 0xFFFFEFFF)
 *   mask - Mask of state bits to monitor (also masked with 0xFFFFEFFF)
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFFD33 if port not acquired
 *   0xFFFFFD36 if interrupted while waiting
 *   Other errors from _watchState
 */
- (IOReturn)watchState:(unsigned int *)state
                  mask:(unsigned int)mask
{
    unsigned int oldIRQL;
    ISASerialPort *selfPtr;
    IOReturn result;

    oldIRQL = spl4();

    // Get self pointer from offset 600
    selfPtr = *(ISASerialPort **)((char *)self + 600);

    // Check if port is acquired (offset 0xc from selfPtr = currentState, check high bit)
    if (*(int *)((char *)selfPtr + 0xc) < 0) {
        // Call _watchState with masked value (mask off bit 0x1000)
        result = _watchState(selfPtr, state, mask & 0xFFFFEFFF);

        // Mask the returned state value (clear bit 0x1000)
        *state = *state & 0xFFFFEFFF;

        splx(oldIRQL);
    } else {
        splx(oldIRQL);
        result = 0xFFFFFFD33;  // Port not acquired
    }

    return result;
}

/*
 * Get character values for a parameter.
 * Retrieves string values from the device description's config table.
 *
 * Parameters:
 *   values - Buffer to receive the string value
 *   parameter - Parameter name to look up
 *   count - Input: buffer size, Output: actual string length including null terminator
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   Result from superclass if parameter not found
 */
- (IOReturn)getCharValues:(unsigned char *)values
             forParameter:(IOParameterName)parameter
                    count:(unsigned int *)count
{
    id configTable;
    id paramValue;
    const char *stringValue;
    unsigned int len;
    const char *p;

    // Validate parameters
    if (values == NULL || count == NULL || *count == 0) {
        return [super getCharValues:values forParameter:parameter count:count];
    }

    // Get config table from device description
    configTable = [self->deviceDescription configTable];
    if (configTable == nil) {
        return [super getCharValues:values forParameter:parameter count:count];
    }

    // Look up parameter in config table
    paramValue = [configTable valueForStringKey:parameter];
    if (paramValue == nil) {
        return [super getCharValues:values forParameter:parameter count:count];
    }

    // Get string value
    stringValue = [paramValue stringValue];
    if (stringValue == NULL) {
        return [super getCharValues:values forParameter:parameter count:count];
    }

    // Copy string to buffer (leave room for null terminator)
    strncpy((char *)values, stringValue, *count - 1);
    values[*count - 1] = '\0';

    // Calculate actual length (including null terminator)
    // This mimics the decompiled strlen loop
    len = 0;
    p = (const char *)values;
    while (*p != '\0') {
        len++;
        p++;
    }
    len++; // Include null terminator

    *count = len;
    return IO_R_SUCCESS;
}

/*
 * Get interrupt handler information.
 * Returns the interrupt handler function, IRQ level, and argument for this device.
 *
 * Parameters:
 *   handler - Output: pointer to interrupt handler function
 *   level - Output: IRQ level (always 3 for ISA serial ports)
 *   argument - Output: argument to pass to handler (value at offset 0x258)
 *   interruptType - Type of interrupt (unused for serial ports)
 *
 * Returns:
 *   1 (true) - handler is valid
 */
- (IOReturn)getHandler:(IOInterruptHandler *)handler
                 level:(unsigned int *)level
              argument:(void **)argument
          forInterrupt:(unsigned int)interruptType
{
    // Return the appropriate interrupt handler based on FIFO capability
    // hasFIFO is at offset 0x1b8 (used as index: 0 for non-FIFO, 1 for FIFO)
    if (self->hasFIFO) {
        *handler = (IOInterruptHandler)_FIFOIntHandler;
    } else {
        *handler = (IOInterruptHandler)_NonFIFOIntHandler;
    }

    // Set IRQ level to 3
    *level = 3;

    // Pass value at offset 0x258 as the argument
    // (This is the interrupt handler context pointer)
    *argument = *(void **)((char *)self + 0x258);

    return 1; // Return true
}

@end
