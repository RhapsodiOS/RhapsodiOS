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
#import <kernserv/prototypes.h>
#import <kernserv/i386/spl.h>
#import <kern/thread_call.h>
#import <string.h>
#import <stdio.h>
#import <stdlib.h>

// I/O port access macros
#define OUTB(port, val) outb(port, val)
#define INB(port) inb(port)

// Helper utilities to bridge legacy nanosecond interval encoding with thread_call API
static inline unsigned long long
_ISASerialPortCombineParts(unsigned int low, unsigned int high)
{
    return ((unsigned long long)high << 32) | (unsigned long long)low;
}

static inline tvalspec_t
_ISASerialPortIntervalFromNanoseconds(unsigned long long nanoseconds)
{
    tvalspec_t interval;
    interval.tv_sec = (unsigned int)(nanoseconds / NSEC_PER_SEC);
    interval.tv_nsec = (clock_res_t)(nanoseconds % NSEC_PER_SEC);
    return interval;
}

static inline tvalspec_t
_ISASerialPortDeadlineFromParts(unsigned int low, unsigned int high)
{
    unsigned long long nanoseconds = _ISASerialPortCombineParts(low, high);
    return deadline_from_interval(_ISASerialPortIntervalFromNanoseconds(nanoseconds));
}

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

// Forward declarations for this translation unit's private functions.
// The eleven the driver exports are declared in ISASerialPortInternal.h.
static IOReturn _activatePort(Port *port);
static IOReturn _deactivatePort(Port *port);
static void _heartBeatTOHandler(thread_call_spec_t spec, thread_call_t call);
static void _frameTOHandler(thread_call_spec_t spec, thread_call_t call);
static void _delayTOHandler(thread_call_spec_t spec, thread_call_t call);
static void _dataLatTOHandler(Port *port);
static IOReturn _RX_enqueueLongEvent(Port *port, unsigned int event, unsigned int data);
static void _executeEvent(Port *port, unsigned char eventType, unsigned int eventData,
                         unsigned int *statePtr, unsigned int *changedBitsPtr);
static void _NonFIFOIntHandler(void *identity, void *state, Port *port);
static void _FIFOIntHandler(void *identity, void *state, Port *port);

/*
 * Validate and normalize ring buffer size.
 * Returns a clamped size value between minimum and maximum limits.
 */
unsigned int validateRingBufferSize(unsigned int requestedSize, Queue *q)
{
    unsigned int size = requestedSize;

    // If size is 0, use default
    if (size == 0) {
        size = q->DefaultSize;
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
 *   q - Pointer to the base of queue structure (either &rxQueueCapacity or &txQueueCapacity)
 */
void freeRingBuffer(Queue *q)
{
    // Queue structure layout (relative to q):
    // +0x00: capacity (uint)
    // +0x04: used (uint)
    // +0x18: start (void*)
    // +0x1c: end (void*)

    unsigned int *capacity = (unsigned int *)q;
    void **start = (void **)((char *)q + 0x18);
    void **end = (void **)((char *)q + 0x1c);

    // Check if ring buffer is allocated (check start pointer)
    if (*start != NULL) {
        // Free the buffer memory
        IOFree(*start, (unsigned int)((char *)*end - (char *)*start));
    }

    // Clear capacity and used fields
    *capacity = 0;
    *((unsigned int *)((char *)q + 0x04)) = 0; // used

    // Clear all pointer fields
    *end = NULL;
    *start = NULL;
    *((void **)((char *)q + 0x20)) = NULL; // write pointer
    *((void **)((char *)q + 0x24)) = NULL; // read pointer

    // Clear watermark fields (offsets vary between RX and TX)
    *((unsigned int *)((char *)q + 0x08)) = 0;
    *((unsigned int *)((char *)q + 0x0c)) = 0;
    *((unsigned int *)((char *)q + 0x10)) = 0;
}

/*
 * Frame timeout handler.
 * Timer callback that triggers interrupt handler when frame timeout occurs.
 * Used for detecting end of transmission or processing delayed events.
 */
static void _frameTOHandler(thread_call_spec_t spec, thread_call_t call)
{
    unsigned int oldIRQL;
    Port *port = (Port *)spec;
    (void)call;

    // Raise interrupt level
    oldIRQL = spl4();

    // Clear timer pending flag
    port->WaitingForTXIdle = 0;

    // Call appropriate interrupt handler based on chip type
    // The function pointer table is indexed by chipType * 5
    if ((port->Type > 4)) {
        // Call FIFO interrupt handler (stub for now)
        // _FIFOIntHandler(0, 0, port);
    } else {
        _NonFIFOIntHandler(0, 0, port);
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Delay timeout handler.
 * Timer callback for delayed operations. Clears the delay bit from state
 * and triggers the appropriate interrupt handler.
 */
static void _delayTOHandler(thread_call_spec_t spec, thread_call_t call)
{
    unsigned int oldIRQL;
    Port *port = (Port *)spec;
    (void)call;

    // Raise interrupt level
    oldIRQL = spl4();

    // Clear delay state bit (0x1000) from currentState
    port->State &= ~0x1000;

    // Call appropriate interrupt handler based on chip type
    if ((port->Type > 4)) {
        _FIFOIntHandler(0, 0, port);
    } else {
        _NonFIFOIntHandler(0, 0, port);
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
static void _dataLatTOHandler(Port *port)
{
    unsigned int oldIRQL;
    unsigned int spaceFree;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned int eventMask;

    // Raise interrupt level
    oldIRQL = spl4();

    // Calculate free space in RX queue
    spaceFree = port->RX.Size - port->RX.Count;

    // Check if we have less than 3 bytes of space available
    if (spaceFree < 3) {
        // Queue is nearly full or completely full
        if (port->RX.Size <= port->RX.Count) {
            // Queue is completely full - set overflow flag
            port->RX.OverRun = 1;
        } else {
            // Nearly full - write overflow marker event (0x6c)
            *(unsigned short *)port->RX.Input = EVENT_OVERFLOW;
            // No advance needed, fall through to common advance code
        }
    } else {
        // We have at least 3 bytes available - write a 3-word event
        // Event type 0x4f (likely "queue has room" notification)
        *(unsigned short *)port->RX.Input = 0x4f;
        port->RX.Input = (char *)port->RX.Input + 2;
        if (port->RX.Input >= port->RX.End) {
            port->RX.Input = port->RX.Base;
        }
        port->RX.Count++;

        // Write first zero word
        *(unsigned short *)port->RX.Input = 0;
        port->RX.Input = (char *)port->RX.Input + 2;
        if (port->RX.Input >= port->RX.End) {
            port->RX.Input = port->RX.Base;
        }
        port->RX.Count++;

        // Write second zero word
        *(unsigned short *)port->RX.Input = 0;
        // Fall through to common advance code
    }

    // Common: advance write pointer for final word
    port->RX.Input = (char *)port->RX.Input + 2;
    if (port->RX.Input >= port->RX.End) {
        port->RX.Input = port->RX.Base;
    }
    port->RX.Count++;

    // Now update state based on queue levels
    if (port->RX.Count <= port->RX.Enqueue) {
        // Queue is below or at target level
        // Start with base state (keep certain bits)
        newState = port->State & 0x17E;

        if (port->RX.Count < port->RX.LowWater) {
            // Below low watermark
            port->RX.Dequeue = 0;

            if (port->RX.Count == 0) {
                // Queue is empty
                newState |= RX_STATE_EMPTY;
                port->RX.Enqueue = 0;
            } else {
                // Below low watermark but not empty
                newState |= RX_STATE_BELOW_LOW;
                port->RX.Enqueue = port->RX.LowWater;
            }

            // Update flow control based on mode
            if ((port->FlowControl & FLOW_RTS_ENABLED) == 0) {
                if ((port->FlowControl & FLOW_HW_ENABLED) == 0) {
                    if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                        newState |= STATE_DTR;
                    }
                } else {
                    // Hardware flow control enabled
                    newState |= STATE_RTS;
                    if (port->RXOstate == -1) {
                        port->RXOstate = 2;
                    } else if (port->RXOstate == 1) {
                        port->RXOstate = -2;
                    }
                }
            } else {
                // RTS flow control enabled
                newState |= STATE_RTS;
            }

        } else if (port->RX.HighWater < port->RX.Count) {
            // Above high watermark - apply back pressure
            port->RX.Enqueue = port->RX.Size - 3;

            if (port->RX.Size - 3 < port->RX.Count) {
                // Critical level (capacity - 3 or more used)
                newState |= RX_STATE_CRITICAL;
                port->RX.Dequeue = port->RX.Size;
            } else {
                // Above high watermark
                newState |= RX_STATE_ABOVE_HIGH;
                port->RX.Dequeue = port->RX.HighWater;
            }

            // Update flow control - turn OFF DTR/RTS to signal back pressure
            if ((port->FlowControl & FLOW_RTS_ENABLED) == 0) {
                if ((port->FlowControl & FLOW_HW_ENABLED) == 0) {
                    if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                        newState &= ~STATE_DTR;
                    }
                } else {
                    // Hardware flow control - clear RTS
                    newState &= ~STATE_RTS;
                    if ((port->RXOstate == -2) || (port->RXOstate == 0)) {
                        port->RXOstate = 1;
                    } else if (port->RXOstate == 2) {
                        port->RXOstate = -1;
                    }
                }
            } else {
                // RTS flow control - clear RTS
                newState &= ~STATE_RTS;
            }

        } else {
            // Between low and high watermarks - maintain current target
            port->RX.Enqueue = port->RX.HighWater;
            port->RX.Dequeue = port->RX.LowWater;
        }

        // Update current state, preserving specific bits
        oldState = port->State;
        newState = (oldState & 0xFFF0FFE9) | (newState & 0xF0016);
        changedBits = oldState ^ newState;
        port->State = newState;

        // Wake up any threads waiting on state changes
        if (port->WatchStateMask & changedBits) {
            thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
            outb(port->Base + UART_MCR, mcrValue);
            // Atomic increment of statistics counter (LOCK/UNLOCK omitted)
        }

        // Trigger timer callout if not paused
        if ((port->State & 0x10000000) == 0) {
            thread_call_enter(port->FrameTOEntry);
        }

        // Enqueue state change event if any watched state bits changed
        memcpy(&eventMask, &port->FlowControl, sizeof(unsigned int));
        if (eventMask & (changedBits << 16)) {
            _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                               (newState & 0xFFFF) | (changedBits << 16));
        }
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Identify UART chip type.
 * Returns the chip type constant (CHIP_8250, CHIP_16450, etc.)
 */
int identifyChip(Port *port)
{
    unsigned char val, val2, val3;
    unsigned int base = port->Base;

    // Enable DLAB to access divisor latch and scratch register
    OUTB(base + UART_LCR, LCR_DLAB);
    IODelay(1);

    // Test scratch register with 0x5A
    OUTB(base + UART_DLL, 0x5A);
    IODelay(1);
    val = INB(base + UART_DLL);

    if (val != 0x5A) {
        return CHIP_UNKNOWN;  // No UART detected
    }

    // Test scratch register with 0xA5
    OUTB(base + UART_DLL, 0xA5);
    IODelay(1);
    val = INB(base + UART_DLL);

    if (val != 0xA5) {
        return CHIP_UNKNOWN;  // No UART detected
    }

    // Disable DLAB
    OUTB(base + UART_LCR, 0);
    IODelay(1);

    // Test scratch register at offset 7 with 0x5A
    OUTB(base + UART_SCR, 0x5A);
    IODelay(1);
    val = INB(base + UART_SCR);

    if (val != 0x5A) {
        return CHIP_8250;  // 8250 - no scratch register
    }

    // Test scratch register at offset 7 with 0xA5
    OUTB(base + UART_SCR, 0xA5);
    IODelay(1);
    val = INB(base + UART_SCR);

    if (val != 0xA5) {
        return CHIP_8250;  // 8250 - no scratch register
    }

    // Test FIFO Control Register
    OUTB(base + UART_FCR, FCR_FIFO_ENABLE | FCR_RCVR_RESET | FCR_XMIT_RESET);
    IODelay(1);

    val = INB(base + UART_IIR);
    val2 = val & 0xC0;  // Check FIFO enabled bits

    // Disable FIFO
    OUTB(base + UART_FCR, 0);
    IODelay(1);

    if (val2 == 0x00) {
        // No FIFO - could be 16450, 16550 (broken FIFO), or 16650

        // Test for 16950 (extended FIFO trigger levels)
        OUTB(base + UART_FCR, 0x60);
        IODelay(1);
        val = INB(base + UART_IIR);
        OUTB(base + UART_FCR, 0);
        IODelay(1);

        if ((val & 0x60) == 0x60) {
            return CHIP_16950;  // 16950
        }

        // Test for 16650 (EFR register)
        OUTB(base + UART_MCR, 0x80);
        IODelay(1);
        val = INB(base + UART_MCR);
        OUTB(base + UART_MCR, 0);
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
        OUTB(base + UART_LCR, 0);
        IODelay(1);
        OUTB(base + UART_SCR, 0xDE);
        IODelay(1);
        OUTB(base + UART_LCR, LCR_DLAB);
        IODelay(1);
        OUTB(base + UART_SCR, 0xA9);
        IODelay(1);

        val = INB(base + UART_SCR);
        OUTB(base + UART_LCR, 0);
        IODelay(1);
        val2 = INB(base + UART_SCR);

        if (val2 == 0xDE && val == 0xA9) {
            return CHIP_16750;  // 16750
        }

        // Test for 16650 (sleep mode support)
        val = INB(base + UART_MCR);
        OUTB(base + UART_MCR, 0);
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
void initChip(Port *port)
{
    // Set default serial port parameters
    port->CharLength = 16;          // 8 data bits (encoded as 16)
    port->StopBits = 2;           // 1 stop bit (encoded as 2)
    port->TX_Parity = PARITY_NONE;   // No parity
    port->RX_Parity = 0;        // No flow control
    port->BaudRate = 19200;       // 19200 baud (0x4b00)
    port->DLRimage = 0;            // Will be calculated by _programChip
    port->FCRimage = 0;           // FIFO control value

    // Only initialize if we detected a valid chip
    if (port->Type != CHIP_UNKNOWN) {
        // Reset Line Control Register
        OUTB(port->Base + UART_LCR, 0);
        IODelay(1);

        // Disable all interrupts
        OUTB(port->Base + UART_IER, 0);
        IODelay(1);

        // Reset Modem Control Register
        OUTB(port->Base + UART_MCR, 0);
        IODelay(1);

        // Program the chip with default settings
        programChip(port);
    }
}

/*
 * Program UART chip with current settings.
 * Configures data bits, stop bits, parity, baud rate, and FIFO.
 */
void programChip(Port *port)
{
    unsigned char lcr = 0;
    unsigned short newDivisor;
    int totalBits;
    int charTime;
    int triggerLevel;

    // Validate and normalize data bits (must be 10, 12, 14, or 16)
    if (port->CharLength < 10) {
        port->CharLength = 10;
    } else if (port->CharLength > 16) {
        port->CharLength = 16;
    }
    port->CharLength &= 0xFFFFFFFE;  // Make even

    // Set data bits in LCR and RX FIFO mask
    switch (port->CharLength) {
        case 10:  // 5 data bits
            lcr = 0;
            port->RBRmask = 0x1F;  // 31 bytes
            break;
        case 12:  // 6 data bits
            lcr = 1;
            port->RBRmask = 0x3F;  // 63 bytes
            break;
        case 14:  // 7 data bits
            lcr = 2;
            port->RBRmask = 0x7F;  // 127 bytes
            break;
        case 16:  // 8 data bits
            lcr = 3;
            port->RBRmask = 0xFF;  // 255 bytes
            break;
    }

    // Set stop bits in LCR
    if (port->StopBits < 3) {
        port->StopBits = 2;  // 1 stop bit
    } else {
        lcr |= 0x04;  // Set bit 2 for 2 stop bits
        if (port->CharLength == 10) {
            port->StopBits = 3;  // 1.5 stop bits for 5 data bits
        } else {
            port->StopBits = 4;  // 2 stop bits for 6-8 data bits
        }
    }

    // Set parity in LCR
    switch (port->TX_Parity) {
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
    if (port->State & 0x00000800) {
        lcr |= 0x40;
    }

    // Validate baud rate against chip capabilities
    if (port->Type < (sizeof(chipCapTable) / sizeof(ChipCapabilities))) {
        if (port->BaudRate > chipCapTable[port->Type].maxBaudRate) {
            port->BaudRate = chipCapTable[port->Type].maxBaudRate;
        }
    }
    if (port->BaudRate < 100) {
        port->BaudRate = 100;
    }

    // Calculate baud rate divisor
    newDivisor = (unsigned short)(port->MasterClock / (port->BaudRate * 8));

    // Only reprogram if divisor changed
    if (port->DLRimage != newDivisor) {
        // Calculate character time in nanoseconds
        totalBits = port->CharLength + port->StopBits;
        if (port->TX_Parity != PARITY_NONE) {
            totalBits += 2;  // Add parity bit
        } else {
            totalBits += 4;  // Add extra for timing
        }

        // Character time = (totalBits * 1000000000) / baudRate
        charTime = (1000000000 / port->BaudRate) * totalBits;
        port->FrameInterval.tv_sec = charTime / 1000000000;
        port->FrameInterval.tv_nsec = charTime % 1000000000;

        // Set DLAB to access divisor registers
        OUTB(port->Base + UART_LCR, lcr | LCR_DLAB);
        IODelay(1);

        port->DLRimage = newDivisor;

        // Program divisor latch
        OUTB(port->Base + UART_DLL, (unsigned char)port->DLRimage);
        IODelay(1);
        OUTB(port->Base + UART_DLM, (unsigned char)(port->DLRimage >> 8));
        IODelay(1);

        // Program FIFO based on chip type
        switch (port->Type) {
            case CHIP_UNKNOWN_FIFO:
            case CHIP_16550:
                // These chips have broken FIFOs, disable them
                port->FCRimage = 0;
                OUTB(port->Base + UART_FCR, 0);
                IODelay(1);
                break;

            case CHIP_16550A:
            case CHIP_16650:
                if (port->MinLatency) {
                    port->FCRimage = FCR_FIFO_ENABLE;
                } else {
                    // Calculate optimal FIFO trigger level
                    // Time for 16 chars at current baud rate
                    triggerLevel = (charTime * -3 + 10000000) / charTime;

                    // Adjust trigger to give at least 2ms margin
                    while ((17 - triggerLevel) * charTime < 2000000 && triggerLevel > 0) {
                        triggerLevel--;
                    }

                    if (triggerLevel < 4) {
                        port->FCRimage = FCR_FIFO_ENABLE;  // 1 byte trigger
                    } else if (triggerLevel < 8) {
                        port->FCRimage = FCR_FIFO_ENABLE | FCR_TRIGGER_4;  // 4 byte trigger
                    } else {
                        port->FCRimage = FCR_FIFO_ENABLE | FCR_TRIGGER_8;  // 8 byte trigger
                    }
                }
                OUTB(port->Base + UART_FCR, port->FCRimage);
                IODelay(1);
                break;

            case CHIP_16750:
                if (port->MinLatency) {
                    port->FCRimage = 0;
                } else {
                    // Calculate optimal FIFO trigger level for 64-byte FIFO
                    triggerLevel = (charTime * -3 + 10000000) / charTime;

                    while ((17 - triggerLevel) * charTime < 2000000 && triggerLevel > 0) {
                        triggerLevel--;
                    }

                    if (triggerLevel < 0 && port->BaudRate < 19200) {
                        port->FCRimage = 0;  // Disable FIFO for very slow speeds
                    } else if (triggerLevel < 16) {
                        port->FCRimage = FCR_FIFO_ENABLE;  // 1 byte trigger
                    } else if (triggerLevel < 24) {
                        port->FCRimage = FCR_FIFO_ENABLE | FCR_TRIGGER_4;  // 16 byte trigger
                    } else {
                        port->FCRimage = FCR_FIFO_ENABLE | FCR_TRIGGER_8;  // 32 byte trigger
                    }
                }
                OUTB(port->Base + UART_FCR, port->FCRimage);
                IODelay(1);
                break;

            default:
                // No FIFO support
                port->FCRimage = 0;
                break;
        }
    }

    // Clear DLAB and set final LCR value
    OUTB(port->Base + UART_LCR, lcr);
    IODelay(1);

    port->LCRimage = lcr;
}

/*
 * Handle PCMCIA card removal.
 * Called when the PCMCIA card is hot-removed from the system.
 */
static void _PCMCIA_yanked(Port *port)
{
    // Set flag indicating card was removed
    port->PCMCIA_yanked = 1;

    // Deactivate the port to prevent further access
    _deactivatePort(port);
}

/*
 * Activate the serial port.
 * Allocates ring buffers, programs the UART, enables interrupts, and sets up initial state.
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD42 on failure (unable to allocate buffers)
 */
static IOReturn _activatePort(Port *port)
{
    unsigned int flowState;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned int txState, rxState;
    unsigned int eventMask;

    // Check if already active (statusFlags bit 0x40)
    if ((port->State & 0x40000000) != 0) {
        // Already active
        return IO_R_SUCCESS;
    }

    // Check if PCMCIA card has been removed
    if (port->PCMCIA_yanked != 0) {
        return 0xFFFFFD42; // Error: device not available
    }

    // Allocate TX ring buffer (at offset 0x50)
    if (allocateRingBuffer(&port->TX) == 0) {
        return 0xFFFFFD42; // Allocation failed
    }

    // Allocate RX ring buffer (at offset 0x18)
    if (allocateRingBuffer(&port->RX) == 0) {
        // Free TX buffer and fail
        freeRingBuffer(&port->TX);
        return 0xFFFFFD42; // Allocation failed
    }

    // Clear statistics counters
    port->Stats.ints = 0;       // offset 0x118
    port->Stats.txInts = 0;     // offset 0x11c
    port->Stats.rxInts = 0;    // offset 0x120
    port->Stats.mdmInts = 0;          // offset 0x124
    port->Stats.txChars = 0;     // offset 0x128
    port->Stats.rxChars = 0;        // offset 0x12c

    // Program the UART chip with current settings
    programChip(port);

    // If chip has FIFO (chipType > CHIP_16550), reset FIFO
    if (port->Type > CHIP_16550) {
        // Write FCR with reset bits (0x06 = RCVR_RESET | XMIT_RESET)
        outb(port->Base + UART_FCR, port->FCRimage | 0x06);
        // Atomic increment of statistics counter (LOCK/UNLOCK omitted)
    }

    // Set STATE_ACTIVE flag (0x40000000)
    oldState = port->State;
    newState = oldState | STATE_ACTIVE;
    changedBits = oldState ^ newState;
    port->State = newState;

    // Wake up any threads waiting on state changes
    if (port->WatchStateMask & changedBits) {
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
        outb(port->Base + UART_MCR, mcrValue);
        // Atomic increment of statistics counter
    }

    // Trigger timer callout if not paused
    if ((port->State & 0x10000000) == 0) {
        thread_call_enter(port->FrameTOEntry);
    }

    // Enqueue state change event if watched
    memcpy(&eventMask, &port->FlowControl, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                           (oldState & 0xFFFF) | (changedBits << 16));
    }

    // Recalculate flow control state
    flowState = flowMachine(port);

    // Update state with flow control bits
    oldState = port->State;
    newState = (oldState & 0xFFFFFFE9) | (flowState & 0x16);
    changedBits = oldState ^ newState;
    port->State = newState;

    // Wake up threads if state changed
    if (port->WatchStateMask & changedBits) {
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
        outb(port->Base + UART_MCR, mcrValue);
        // Atomic increment
    }

    // Trigger timer callout
    if ((port->State & 0x10000000) == 0) {
        thread_call_enter(port->FrameTOEntry);
    }

    // Enqueue flow control state change event
    memcpy(&eventMask, &port->FlowControl, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                           (oldState & 0xFFE9) | (flowState & 0x16) | (changedBits << 16));
    }

    // Calculate initial TX queue state based on current usage
    if (port->TX.LowWater < port->TX.Count) {
        // Used > medWater
        if (port->TX.HighWater < port->TX.Count) {
            // Used > lowWater (above high watermark)
            port->TX.Enqueue = port->TX.Size - 3;
            if (port->TX.Size - 3 < port->TX.Count) {
                // Critical level
                port->TX.Dequeue = port->TX.Size;
                txState = 0x1800000;
            } else {
                // Above high
                port->TX.Dequeue = port->TX.HighWater;
                txState = 0x1000000;
            }
        } else {
            // medWater < used <= lowWater
            port->TX.Enqueue = port->TX.HighWater;
            port->TX.Dequeue = port->TX.LowWater;
            txState = 0;
        }
    } else {
        // Used <= medWater
        port->TX.Dequeue = 0;
        if (port->TX.Count == 0) {
            // Empty
            port->TX.Enqueue = 0;
            txState = TX_STATE_EMPTY;
        } else {
            // Below low watermark
            port->TX.Enqueue = port->TX.LowWater;
            txState = TX_STATE_BELOW_LOW;
        }
    }

    // Calculate initial RX queue state based on current usage
    rxState = port->State & 0x17E;

    if (port->RX.Count < port->RX.LowWater) {
        // Below low watermark
        port->RX.Dequeue = 0;
        if (port->RX.Count == 0) {
            // Empty
            rxState |= RX_STATE_EMPTY;
            port->RX.Enqueue = 0;
        } else {
            // Below low watermark but not empty
            rxState |= RX_STATE_BELOW_LOW;
            port->RX.Enqueue = port->RX.LowWater;
        }

        // Enable flow control (ready to receive)
        if ((port->FlowControl & FLOW_RTS_ENABLED) == 0) {
            if ((port->FlowControl & FLOW_HW_ENABLED) == 0) {
                if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                    rxState |= STATE_DTR;
                }
            } else {
                rxState |= STATE_RTS;
                if (port->RXOstate == -1) {
                    port->RXOstate = 2;
                } else if (port->RXOstate == 1) {
                    port->RXOstate = -2;
                }
            }
        } else {
            rxState |= STATE_RTS;
        }

    } else if (port->RX.HighWater < port->RX.Count) {
        // Above high watermark
        port->RX.Enqueue = port->RX.Size - 3;
        if (port->RX.Size - 3 < port->RX.Count) {
            // Critical
            rxState |= RX_STATE_CRITICAL;
            port->RX.Dequeue = port->RX.Size;
        } else {
            // Above high
            rxState |= RX_STATE_ABOVE_HIGH;
            port->RX.Dequeue = port->RX.HighWater;
        }

        // Disable flow control (apply back pressure)
        if ((port->FlowControl & FLOW_RTS_ENABLED) == 0) {
            if ((port->FlowControl & FLOW_HW_ENABLED) == 0) {
                if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                    rxState &= ~STATE_DTR;
                }
            } else {
                rxState &= ~STATE_RTS;
                if ((port->RXOstate == -2) || (port->RXOstate == 0)) {
                    port->RXOstate = 1;
                } else if (port->RXOstate == 2) {
                    port->RXOstate = -1;
                }
            }
        } else {
            rxState &= ~STATE_RTS;
        }

    } else {
        // Between low and high watermarks
        port->RX.Enqueue = port->RX.HighWater;
        port->RX.Dequeue = port->RX.LowWater;
    }

    // Combine TX and RX states and update currentState
    oldState = port->State;
    newState = (oldState & 0xF870FFE9) | txState | (rxState & 0x78F0016);
    changedBits = oldState ^ newState;
    port->State = newState;

    // Wake up threads
    if (port->WatchStateMask & changedBits) {
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
        outb(port->Base + UART_MCR, mcrValue);
        // Atomic increment
    }

    // Trigger timer callout
    if ((port->State & 0x10000000) == 0) {
        thread_call_enter(port->FrameTOEntry);
    }

    // Enqueue state change event
    memcpy(&eventMask, &port->FlowControl, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                           (newState & 0xFFFF) | (changedBits << 16));
    }

    // Final timer callout trigger
    if ((port->State & 0x10000000) == 0) {
        thread_call_enter(port->FrameTOEntry);
    }

    // Enable UART interrupts (write lower 4 bits of ierValue)
    outb(port->Base + UART_IER, port->IERmask & 0x0F);
    // Atomic increment

    return IO_R_SUCCESS;
}

/*
 * Deactivate the serial port.
 * Shuts down the UART, disables interrupts, frees ring buffers, and updates state.
 */
static IOReturn _deactivatePort(Port *port)
{
    unsigned int eventMask;
    unsigned int flowState;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;

    // Only deactivate if port is currently active (bit 0x40 in statusFlags)
    if ((port->State & 0x40000000) == 0) {
        return IO_R_SUCCESS;
    }

    // Disable most UART interrupts (keep only bit 3 if set)
    outb(port->Base + UART_IER, port->IERmask & 0x08);

    // Update some statistics or state counter (exact purpose unclear from decompilation)
    // This appears to be an atomic increment of a global counter
    // LOCK/UNLOCK pattern omitted for simplicity

    // Clear STATE_ACTIVE bit (0x40000000) from current state
    oldState = port->State;
    newState = oldState & ~STATE_ACTIVE;
    changedBits = oldState ^ newState;
    port->State = newState;

    // Wake up any threads waiting on state changes
    if (port->WatchStateMask & changedBits) {
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
        outb(port->Base + UART_MCR, mcrValue);
    }

    // Trigger timer callout if not paused (statusFlags bit 0x10)
    if ((port->State & 0x10000000) == 0) {
        thread_call_enter(port->FrameTOEntry);
    }

    // Enqueue state change event if any watched state bits changed
    // Read stateEventMask as part of uint at offset 0xe0
    memcpy(&eventMask, &port->FlowControl, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                           (newState & 0xFFFF) | (changedBits << 16));
    }

    // Free both TX and RX ring buffers
    freeRingBuffer(&port->TX); // TX queue at offset 0x50
    freeRingBuffer(&port->RX); // RX queue at offset 0x18

    // Recalculate flow control state
    flowState = flowMachine(port);

    // Update state, keeping only specific bits from flow control and clearing others
    oldState = port->State;
    newState = (oldState & 0xFFFFFFE9) | (flowState & 0x16);
    changedBits = oldState ^ newState;
    port->State = newState;

    // Wake up any threads waiting on state changes
    if (port->WatchStateMask & changedBits) {
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
        outb(port->Base + UART_MCR, mcrValue);
    }

    // Trigger timer callout again if not paused
    if ((port->State & 0x10000000) == 0) {
        thread_call_enter(port->FrameTOEntry);
    }

    // Enqueue state change event for flow control changes if watched
    memcpy(&eventMask, &port->FlowControl, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                           (newState & 0xFFFF) | (changedBits << 16));
    }

    return IO_R_SUCCESS;
}

/*
 * Allocate ring buffer.
 * Allocates memory for a ring buffer (RX or TX) with proper alignment.
 *
 * Parameters:
 *   q - Pointer to the base of queue structure (either &rxQueueCapacity or &txQueueCapacity)
 *   q - Pointer to the queue whose ring buffer is being allocated
 *
 * Returns:
 *   IO_R_SUCCESS (1) on success, 0 on failure
 *
 * Queue structure layout (relative to q):
 * +0x00: capacity (uint) - requested size, will be validated
 * +0x04: used (uint)
 * +0x08-0x10: watermarks
 * +0x18: start (void*) - aligned start pointer
 * +0x1c: end (void*) - end of buffer
 * +0x20: write (void*)
 * +0x24: read (void*)
 * +0x30: allocStart (void*) - raw allocated pointer (for freeing)
 */
int allocateRingBuffer(Queue *q)
{
    unsigned int *capacity = (unsigned int *)q;
    unsigned int *used = (unsigned int *)((char *)q + 0x04);
    void **allocStart = (void **)((char *)q + 0x30);
    void **start = (void **)((char *)q + 0x18);
    void **end = (void **)((char *)q + 0x1c);
    void **write = (void **)((char *)q + 0x20);
    void **read = (void **)((char *)q + 0x24);
    unsigned int *watermarkTarget = (unsigned int *)((char *)q + 0x0c);
    unsigned int validatedSize;
    unsigned int allocSize;
    void *buffer;

    // First free any existing buffer
    freeRingBuffer(q);

    // Validate the requested size
    validatedSize = validateRingBufferSize(*capacity, q);
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

    // Clear overflow flag (at offset 0x28 from q)
    *((unsigned int *)((char *)q + 0x28)) = 0;

    // Clear used count
    *used = 0;

    // Set target watermark to low watermark (at offset 0x0c)
    // Low watermark is at offset 0x08
    *watermarkTarget = *((unsigned int *)((char *)q + 0x08));

    // Set current watermark (at offset 0x14) to zero
    *((unsigned int *)((char *)q + 0x14)) = 0;

    return IO_R_SUCCESS;
}

/*
 * RX dequeue event.
 * Dequeues variable-length events from the receive queue.
 * param sleep: If TRUE, wait for event; if FALSE, return immediately if empty
 */
IOReturn RX_dequeueEvent(Port *port, unsigned char *eventType,
                         unsigned int *eventData, BOOL sleep)
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
        if (port->RX.Count != 0) {
            // Read first word (contains event type and possibly first data byte)
            readPtr = (unsigned short *)port->RX.Output;
            firstWord = *readPtr++;
            if ((char *)readPtr >= port->RX.End) {
                readPtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Output = (char *)readPtr;
            port->RX.Count--;

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
                if ((char *)readPtr >= port->RX.End) {
                    readPtr = (unsigned short *)port->RX.Base;
                }
                port->RX.Output = (char *)readPtr;
                port->RX.Count--;
                *eventData = (unsigned int)dataWord;
            } else if (eventLen == 3) {
                // 3-word event: read second and third words
                dataWord = *readPtr++;
                if ((char *)readPtr >= port->RX.End) {
                    readPtr = (unsigned short *)port->RX.Base;
                }
                port->RX.Output = (char *)readPtr;
                port->RX.Count--;
                *eventData = (unsigned int)dataWord;

                dataWord = *readPtr++;
                if ((char *)readPtr >= port->RX.End) {
                    readPtr = (unsigned short *)port->RX.Base;
                }
                port->RX.Output = (char *)readPtr;
                port->RX.Count--;
                *eventData |= ((unsigned int)dataWord) << 16;
            }

            // Handle overflow condition
            if (port->RX.OverRun != 0) {
                unsigned short *writePtr;
                port->RX.OverRun = 0;
                // Enqueue overflow marker
                writePtr = (unsigned short *)port->RX.Input;
                *writePtr++ = EVENT_OVERFLOW;
                if ((char *)writePtr >= port->RX.End) {
                    writePtr = (unsigned short *)port->RX.Base;
                }
                port->RX.Input = (char *)writePtr;
                port->RX.Count++;
            }

            // Update RX watermark state if queue level dropped below watermark
            if (port->RX.Count <= port->RX.Dequeue) {
                // Determine new RX state based on queue level
                newState = port->State & 0x0000017E;  // Preserve certain bits

                if (port->RX.Count < port->RX.LowWater) {
                    // Below low watermark
                    port->RX.Dequeue = 0;
                    if (port->RX.Count == 0) {
                        // Queue empty
                        newState |= RX_STATE_EMPTY;
                        port->RX.Enqueue = 0;
                    } else {
                        // Below low watermark but not empty
                        newState |= RX_STATE_BELOW_LOW;
                        port->RX.Enqueue = port->RX.LowWater;
                    }

                    // Handle flow control - assert RTS/DTR when queue drains
                    if ((port->FlowControl & FLOW_RTS_ENABLED) == 0) {
                        if ((port->FlowControl & FLOW_HW_ENABLED) == 0) {
                            if (port->FlowControl & FLOW_DTR_ENABLED) {
                                newState |= STATE_DTR;
                            }
                        } else {
                            newState |= STATE_RTS;
                            // Update flow control state machine
                            if (port->RXOstate == -1) {
                                port->RXOstate = 2;
                            } else if (port->RXOstate == 1) {
                                port->RXOstate = -2;
                            }
                        }
                    } else {
                        newState |= STATE_RTS;
                    }
                } else if (port->RX.Count > port->RX.HighWater) {
                    // Above high watermark
                    port->RX.Enqueue = port->RX.Size - 3;
                    if (port->RX.Count > (port->RX.Size - 3)) {
                        // Critical level
                        newState |= RX_STATE_CRITICAL;
                        port->RX.Dequeue = port->RX.Size;
                    } else {
                        // Above high watermark
                        newState |= RX_STATE_ABOVE_HIGH;
                        port->RX.Dequeue = port->RX.HighWater;
                    }

                    // Handle flow control - deassert RTS/DTR when queue fills
                    if ((port->FlowControl & FLOW_RTS_ENABLED) == 0) {
                        if ((port->FlowControl & FLOW_HW_ENABLED) == 0) {
                            if (port->FlowControl & FLOW_DTR_ENABLED) {
                                newState &= ~STATE_DTR;
                            }
                        } else {
                            newState &= ~STATE_RTS;
                            // Update flow control state machine
                            if (port->RXOstate == -2 || port->RXOstate == 0) {
                                port->RXOstate = 1;
                            } else if (port->RXOstate == 2) {
                                port->RXOstate = -1;
                            }
                        }
                    } else {
                        newState &= ~STATE_RTS;
                    }
                } else {
                    // Between watermarks
                    port->RX.Enqueue = port->RX.HighWater;
                    port->RX.Dequeue = port->RX.LowWater;
                }

                // Update state and detect changes
                oldState = port->State;
                newState = (oldState & 0xFFF0FE81) | newState;  // Preserve high bits and certain low bits
                changedBits = newState ^ oldState;
                port->State = newState;

                // Wake threads waiting on state changes
                if (port->WatchStateMask & changedBits) {
                    thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
                    OUTB(port->Base + UART_MCR, mcrValue);
                    IODelay(1);
                }

                // Schedule timer callback if not already pending
                if ((port->State & 0x10000000) == 0) {
                    thread_call_enter(port->FrameTOEntry);
                }

                // Notify of state change if mask matches
                if (port->FlowControl & (changedBits << 16)) {
                    _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE, (newState & 0xFFFF) | (changedBits << 16));
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
        result = watchState(port, &watchMask, STATE_RX_ENABLED);
        if (result != IO_R_SUCCESS) {
            return result;
        }
    }
}

/*
 * RX enqueue long event (3-word event: type + data low + data high).
 * Used for state change events and other long data events.
 */
static IOReturn _RX_enqueueLongEvent(Port *port, unsigned int event, unsigned int data)
{
    unsigned short *writePtr = (unsigned short *)port->RX.Input;
    unsigned int spaceAvailable = port->RX.Size - port->RX.Count;

    // Check if we have space for 3 entries
    if (spaceAvailable < 3) {
        // Not enough space for long event
        if (port->RX.Count < port->RX.Size) {
            // Queue not full - enqueue overflow marker
            *writePtr++ = EVENT_OVERFLOW;
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;
        } else {
            // Queue completely full - set overflow flag
            port->RX.OverRun = 1;
        }
        return IO_R_SUCCESS;
    }

    // Enqueue event type
    *writePtr++ = (unsigned short)event;
    if ((char *)writePtr >= port->RX.End) {
        writePtr = (unsigned short *)port->RX.Base;
    }
    port->RX.Input = (char *)writePtr;
    port->RX.Count++;

    // Enqueue data low word
    *writePtr++ = (unsigned short)data;
    if ((char *)writePtr >= port->RX.End) {
        writePtr = (unsigned short *)port->RX.Base;
    }
    port->RX.Input = (char *)writePtr;
    port->RX.Count++;

    // Enqueue data high word
    *writePtr++ = (unsigned short)(data >> 16);
    if ((char *)writePtr >= port->RX.End) {
        writePtr = (unsigned short *)port->RX.Base;
    }
    port->RX.Input = (char *)writePtr;
    port->RX.Count++;

    return IO_R_SUCCESS;
}

/*
 * TX enqueue event.
 * Enqueues data to transmit queue with variable length based on event type.
 * param event: Event type byte (low 2 bits indicate data length: 0=none, 1=1word, 2=2words, 3=3words)
 * param data: Event data (up to 4 bytes)
 * param sleep: If TRUE, wait for space; if FALSE, return error if no space
 */
IOReturn TX_enqueueEvent(Port *port, unsigned char event,
                         unsigned int data, BOOL sleep)
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
        if ((port->TX.Size - port->TX.Count) > 2) {
            writePtr = (unsigned short *)port->TX.Input;

            // Write event type and first data byte
            *writePtr++ = (unsigned short)((event & 0xFF) | ((data & 0xFF) << 8));
            if ((char *)writePtr >= port->TX.End) {
                writePtr = (unsigned short *)port->TX.Base;
            }
            port->TX.Input = (char *)writePtr;
            port->TX.Count++;

            // Write additional words based on event type
            if ((event & 3) > 1) {
                // Write second word (bytes 1-2 of data)
                *writePtr++ = (unsigned short)(data >> 8);
                if ((char *)writePtr >= port->TX.End) {
                    writePtr = (unsigned short *)port->TX.Base;
                }
                port->TX.Input = (char *)writePtr;
                port->TX.Count++;

                if ((event & 3) == 3) {
                    // Write third word (bytes 2-3 of data)
                    *writePtr++ = (unsigned short)(data >> 16);
                    if ((char *)writePtr >= port->TX.End) {
                        writePtr = (unsigned short *)port->TX.Base;
                    }
                    port->TX.Input = (char *)writePtr;
                    port->TX.Count++;
                }
            }

            // Update TX queue watermark state
            if (port->TX.Count > port->TX.Enqueue) {
                // Above high watermark
                if (port->TX.Count > port->TX.LowWater) {
                    if (port->TX.Count > port->TX.HighWater) {
                        // Above all watermarks
                        port->TX.Enqueue = port->TX.Size - 3;
                        if (port->TX.Count > (port->TX.Size - 3)) {
                            port->TX.Dequeue = port->TX.Size;
                            newState = TX_STATE_ABOVE_HIGH;
                        } else {
                            port->TX.Dequeue = port->TX.HighWater;
                            newState = TX_STATE_BELOW_LOW;
                        }
                    } else {
                        // Between med and low watermarks
                        port->TX.Dequeue = port->TX.LowWater;
                        port->TX.Enqueue = port->TX.HighWater;
                        newState = TX_STATE_BELOW_HIGH;
                    }
                } else {
                    // Below med watermark
                    port->TX.Dequeue = 0;
                    if (port->TX.Count == 0) {
                        port->TX.Enqueue = 0;
                        newState = TX_STATE_EMPTY;
                    } else {
                        port->TX.Enqueue = port->TX.LowWater;
                        newState = TX_STATE_BELOW_MED;
                    }
                }

                // Update state and wake waiting threads
                oldState = port->State;
                newState = (oldState & ~TX_STATE_MASK) | newState;
                changedBits = newState ^ oldState;
                port->State = newState;

                // Wake threads waiting on these state bits
                if (port->WatchStateMask & changedBits) {
                    thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
                    OUTB(port->Base + UART_MCR, mcrValue);
                    IODelay(1);
                }

                // Schedule timer callback if not already pending
                if ((port->State & 0x10000000) == 0) {
                    thread_call_enter(port->FrameTOEntry);
                }

                // Notify RX queue of state change if mask matches
                // (flowControlMode overlays stateEventMask at offset 0xe0 as uint32)
                if ((*(unsigned int *)&port->FlowControl) & (changedBits << 16)) {
                    _RX_enqueueLongEvent(port, 0x53, oldState | (changedBits << 16));
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
        result = watchState(port, &watchMask, STATE_TX_ENABLED);

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
IOReturn RX_dequeueData(Port *port, unsigned char *byteOut, BOOL sleep)
{
    unsigned short dataWord;
    unsigned short *readPtr;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned int watchMask;
    IOReturn result;

    do {
        // Check if RX queue has data
        if (port->RX.Count != 0) {
            readPtr = (unsigned short *)port->RX.Output;

            // Verify marker byte (low byte should be 'U' = 0x55)
            if ((*(unsigned char *)readPtr) != 'U') {
                return IO_R_OFFLINE;  // -702 (-0x2be)
            }

            // Read 2-byte word from RX queue
            dataWord = *readPtr++;

            // Advance read pointer with wrapping
            if ((char *)readPtr >= port->RX.End) {
                readPtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Output = (char *)readPtr;

            // Decrement used count
            port->RX.Count--;

            // Extract high byte (actual data)
            *byteOut = (unsigned char)(dataWord >> 8);

            // Handle overflow recovery or normal watermark processing
            if (port->RX.OverRun == 0) {
                // Normal processing - update watermarks if at or below watermark
                if (port->RX.Count <= port->RX.Dequeue) {
                    // Build new state without RX state bits
                    newState = port->State & 0x17e;  // Keep only non-RX-state bits

                    // Check if below low watermark
                    if (port->RX.Count < port->RX.LowWater) {
                        port->RX.Dequeue = 0;

                        if (port->RX.Count == 0) {
                            // Queue empty
                            newState |= RX_STATE_EMPTY;
                            port->RX.Enqueue = 0;
                        } else {
                            // Below low watermark
                            newState |= RX_STATE_BELOW_LOW;
                            port->RX.Enqueue = port->RX.LowWater;
                        }

                        // Update flow control - turn ON (assert signals when queue drains)
                        if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                            newState |= STATE_RTS;
                        }
                        if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                            newState |= 0x10;  // Hardware flow control bit
                            // Update flow control state machine
                            if (port->RXOstate == -1) {
                                port->RXOstate = 2;
                            } else if (port->RXOstate == 1) {
                                port->RXOstate = -2;
                            }
                        }
                        if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                            newState |= STATE_DTR;
                        }
                    } else if (port->RX.Count > port->RX.HighWater) {
                        // Above high watermark (need flow control)
                        port->RX.Enqueue = port->RX.Size - 3;

                        if (port->RX.Count > (port->RX.Size - 3)) {
                            // Critical level
                            newState |= RX_STATE_CRITICAL;
                            port->RX.Dequeue = port->RX.Size;
                        } else {
                            // Above high
                            newState |= RX_STATE_ABOVE_HIGH;
                            port->RX.Dequeue = port->RX.HighWater;
                        }

                        // Update flow control - turn OFF (de-assert signals when queue fills)
                        if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                            newState &= ~STATE_RTS;
                        }
                        if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                            newState &= ~0x10;
                            // Update flow control state machine
                            if (port->RXOstate == -2 || port->RXOstate == 0) {
                                port->RXOstate = 1;
                            } else if (port->RXOstate == 2) {
                                port->RXOstate = -1;
                            }
                        }
                        if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                            newState &= ~STATE_DTR;
                        }
                    } else {
                        // Between low and high watermarks
                        port->RX.Enqueue = port->RX.HighWater;
                        port->RX.Dequeue = port->RX.LowWater;
                    }

                    // Update current state and calculate changed bits
                    oldState = port->State;
                    newState = (oldState & 0xfff0fe81) | newState;
                    changedBits = newState ^ oldState;
                    port->State = newState;

                    // Wake threads waiting on these state bits
                    if (port->WatchStateMask & changedBits) {
                        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
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
                        OUTB(port->Base + UART_MCR, mcrValue);
                        IOEnterCriticalSection();
                        // Increment some global counter (placeholder)
                        IOExitCriticalSection();
                    }

                    // Schedule timer callback if not already pending
                    if ((port->State & 0x10000000) == 0) {
                        thread_call_enter(port->FrameTOEntry);
                    }

                    // Notify RX queue of state change if flow control mode matches
                    if ((port->FlowControl & (changedBits >> 16)) != 0) {
                        _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                                           (newState & 0xFFFF) | (changedBits << 16));
                    }
                }
            } else {
                // Overflow recovery - re-enqueue overflow marker
                unsigned short *writePtr = (unsigned short *)port->RX.Input;

                port->RX.OverRun = 0;
                *writePtr++ = EVENT_OVERFLOW;

                // Advance write pointer with wrapping
                if ((char *)writePtr >= port->RX.End) {
                    writePtr = (unsigned short *)port->RX.Base;
                }
                port->RX.Input = (char *)writePtr;
                port->RX.Count++;
            }

            return IO_R_SUCCESS;
        }

        // No data available
        if (!sleep) {
            return IO_R_OFFLINE;  // -702
        }

        // Wait for RX data
        watchMask = 0;
        result = watchState(port, &watchMask, STATE_RX_ENABLED);
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
static void _heartBeatTOHandler(thread_call_spec_t spec, thread_call_t call)
{
    unsigned int oldIRQL;
    Port *port = (Port *)spec;
    (void)call;

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is active and not yanked
    if ((port->State & STATE_ACTIVE) && (port->PCMCIA_yanked == 0)) {
        tvalspec_t deadline;
        // Call interrupt handler if heartbeat not already pending
        if (port->JustDoneInterrupt == 0) {
            // Call appropriate interrupt handler based on FIFO capability
            if ((port->Type > 4)) {
                // Call FIFO interrupt handler (stub for now)
                // _FIFOIntHandler(0, 0, port);
            } else {
                // Call non-FIFO interrupt handler (stub for now)
                // _NonFIFOIntHandler(0, 0, port);
            }
        }

        // Clear pending flag
        port->JustDoneInterrupt = 0;

        // Schedule next heartbeat
        deadline = _ISASerialPortDeadlineFromParts(
            port->HeartBeatInterval.tv_sec,
            (unsigned int)port->HeartBeatInterval.tv_nsec);
        thread_call_enter_delayed(port->HeartBeatTOEntry, deadline);
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Non-FIFO interrupt handler.
 * Handles all UART interrupts for 8250/16450 chips without FIFO.
 * This is called at interrupt level and must be fast.
 */
static void _NonFIFOIntHandler(void *identity, void *state, Port *port)
{
    unsigned int matchBits;
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
    timerNeeded = port->WaitingForTXIdle;
    newState = port->State;

    // Read Line Status Register
    lsr = INB(port->Base + UART_LSR);

    // Update interrupt statistics
    port->Stats.ints++;
    if (lsr & 0x01) {  // Data Ready
        port->Stats.rxInts++;
    }
    if (lsr & 0x20) {  // THR Empty
        port->Stats.txInts++;
    }

    // Main interrupt processing loop
    do {
        continueLoop = FALSE;

        // Handle overrun error (LSR bit 1)
        if ((lsr & 0x02) && (newState & STATE_RX_ENABLED)) {
            if (port->RX.Count < port->RX.Size) {
                // Enqueue overrun error event
                unsigned short *writePtr = (unsigned short *)port->RX.Input;
                *writePtr++ = EVENT_OVERRUN_ERROR;
                if ((char *)writePtr >= port->RX.End) {
                    writePtr = (unsigned short *)port->RX.Base;
                }
                port->RX.Input = (char *)writePtr;
                port->RX.Count++;
            } else {
                // Queue full - set overflow flag
                port->RX.OverRun = 1;
            }
        }

        // Handle data ready (LSR bit 0)
        if (lsr & 0x01) {
            // Read data byte from RBR
            dataByte = INB(port->Base + UART_RBR);
            eventData = (unsigned int)dataByte;

            // Check for PCMCIA card removal (all 1's)
            if ((lsr == 0xFF) && (dataByte == 0xFF) && (port->PCMCIA != 0)) {
                _PCMCIA_yanked(port);
                return;
            }

            // Process received data if RX enabled
            if (newState & STATE_RX_ENABLED) {
                unsigned char errorBits;
                port->Stats.rxChars++;

                errorBits = lsr & 0x1C;  // Parity, Framing, Break errors

                if (errorBits == 0x04) {
                    // Parity error - check for software flow control character
                    if (port->RX_Parity == 6) {  // Software flow control mode
                        // Mask data with RX FIFO mask
                        eventData = dataByte & port->RBRmask;
                        goto process_flow_control_char;
                    }

                    // Enqueue parity error with data
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_PARITY_ERROR | (dataByte << 8);
                        if ((char *)writePtr >= port->RX.End) {
                            writePtr = (unsigned short *)port->RX.Base;
                        }
                        port->RX.Input = (char *)writePtr;
                        port->RX.Count++;
                    }
                } else if (errorBits == 0) {
                    // No error - normal data reception
process_flow_control_char:
                    // Check for software flow control characters
                    if ((*(unsigned int *)&port->FlowControl & 0x80008) != 0) {
                        // Software flow control enabled
                        if (eventData == port->XONchar) {
                            newState |= 0x08;
                            changedBits |= 0x08;
                            goto data_processed;
                        } else if (eventData == port->XOFFchar) {
                            newState &= ~0x08;
                            changedBits |= 0x08;
                            goto data_processed;
                        }
                    }

                    // Check if data needs special handling based on control flags
                    if ((port->FlowControl & 0x00000400) != 0) {
                        newState |= 0x08;
                        changedBits |= 0x08;
                    }

                    // Check character filter bitmap (256 bits)
                    if ((port->SWspecial[eventData >> 5] & (1 << (eventData & 0x1F))) == 0) {
                        eventType = EVENT_VALID_DATA;  // 'U' - normal data
                    } else {
                        eventType = EVENT_SPECIAL_DATA;  // 'Y' - special/filtered data
                    }

                    // Enqueue data with marker
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = (unsigned short)eventType | (dataByte << 8);
                        if ((char *)writePtr >= port->RX.End) {
                            writePtr = (unsigned short *)port->RX.Base;
                        }
                        port->RX.Input = (char *)writePtr;
                        port->RX.Count++;
                    }
                } else if ((errorBits == 0x08) || (errorBits == 0x0C)) {
                    // Framing error or break condition
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_FRAMING_ERROR | (dataByte << 8);
                        if ((char *)writePtr >= port->RX.End) {
                            writePtr = (unsigned short *)port->RX.Base;
                        }
                        port->RX.Input = (char *)writePtr;
                        port->RX.Count++;
                    }
                } else {
                    // Other error
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_ERROR;
                        if ((char *)writePtr >= port->RX.End) {
                            writePtr = (unsigned short *)port->RX.Base;
                        }
                        port->RX.Input = (char *)writePtr;
                        port->RX.Count++;
                    }
                }
            }
        }

data_processed:
        // Update RX watermark state if at target level and port active
        if ((port->RX.Count >= port->RX.Enqueue) && (newState & STATE_ACTIVE)) {
            unsigned int rxState = newState & 0x17E;  // Keep only non-RX-state bits

            if (port->RX.Count < port->RX.LowWater) {
                port->RX.Dequeue = 0;
                if (port->RX.Count == 0) {
                    rxState |= RX_STATE_EMPTY;
                    port->RX.Enqueue = 0;
                } else {
                    rxState |= RX_STATE_BELOW_LOW;
                    port->RX.Enqueue = port->RX.LowWater;
                }

                // Turn ON flow control signals (queue draining)
                if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                    rxState |= STATE_RTS;
                }
                if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                    rxState |= 0x10;
                    if (port->RXOstate == -1) {
                        port->RXOstate = 2;
                    } else if (port->RXOstate == 1) {
                        port->RXOstate = -2;
                    }
                }
                if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                    rxState |= STATE_DTR;
                }
            } else if (port->RX.Count > port->RX.HighWater) {
                port->RX.Enqueue = port->RX.Size - 3;
                if (port->RX.Count > (port->RX.Size - 3)) {
                    rxState |= RX_STATE_CRITICAL;
                    port->RX.Dequeue = port->RX.Size;
                } else {
                    rxState |= RX_STATE_ABOVE_HIGH;
                    port->RX.Dequeue = port->RX.HighWater;
                }

                // Turn OFF flow control signals (queue filling)
                if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                    rxState &= ~STATE_RTS;
                }
                if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                    rxState &= ~0x10;
                    if (port->RXOstate == -2 || port->RXOstate == 0) {
                        port->RXOstate = 1;
                    } else if (port->RXOstate == 2) {
                        port->RXOstate = -1;
                    }
                }
                if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                    rxState &= ~STATE_DTR;
                }
            } else {
                port->RX.Enqueue = port->RX.HighWater;
                port->RX.Dequeue = port->RX.LowWater;
            }

            newState = (newState & 0xFFF0FFE9) | rxState;
            changedBits |= ((newState ^ port->State) & 0xF0016);

            // Update hardware MCR if DTR/RTS changed
            mcrValue = MCR_OUT2;
            if (rxState & STATE_DTR) mcrValue |= MCR_DTR;
            if (rxState & STATE_RTS) mcrValue |= MCR_RTS;
            OUTB(port->Base + UART_MCR, mcrValue);

            IOEnterCriticalSection();
            // Increment some counter (placeholder for global variable)
            IOExitCriticalSection();
        }

        // Handle Modem Status Register changes
        msr = INB(port->Base + UART_MSR);
        if (msr & 0x0F) {  // Any delta bits set
            port->Stats.mdmInts++;
            // Update modem signal state bits (5-8) using lookup table
            newState = (newState & 0xFFFFFE1F) | (_msr_state_lut[msr >> 4] << 5);
            changedBits |= ((newState ^ port->State) & 0x1E0);
        }

        // Handle Transmitter Holding Register Empty (LSR bit 5)
        if (lsr & 0x20) {
            // Check hardware flow control state
            if (((port->FlowControl & FLOW_HW_ENABLED) == 0) || (port->RXOstate < 1)) {
                // Can transmit
                if (port->TX.Count != 0) {
                    if ((newState & 0x1000) == 0) {  // Some state check
                        // Peek at next TX queue entry
                        char *peekPtr = (char *)port->TX.Output;
                        if ((char *)peekPtr >= port->TX.End) {
                            peekPtr = (char *)port->TX.Base;
                        }

                        if (*peekPtr != 0) {
                            if (*peekPtr == 'U') {
                                // Data byte transmission
                                // Check for conditions that prevent transmission
                                unsigned int preventMask = *(unsigned int *)&port->FlowControl;
                                preventMask = (preventMask & 0x168) | 0x20000000;
                                if ((preventMask & ~newState) == 0) {
                                    unsigned char wordLen;
                                    // Dequeue and transmit
                                    readPtr = (unsigned short *)port->TX.Output;
                                    dataWord = *readPtr++;
                                    if ((char *)readPtr >= port->TX.End) {
                                        readPtr = (unsigned short *)port->TX.Output;
                                    }
                                    port->TX.Output = (char *)readPtr;
                                    port->TX.Count--;

                                    eventType = (unsigned char)dataWord;
                                    wordLen = eventType & 3;

                                    if (wordLen == 1) {
                                        eventData = (dataWord >> 8);
                                    } else if (wordLen == 0) {
                                        eventData = 0;
                                    } else if (wordLen == 2) {
                                        dataWord = *readPtr++;
                                        if ((char *)readPtr >= port->TX.End) {
                                            readPtr = (unsigned short *)port->TX.Base;
                                        }
                                        port->TX.Output = (char *)readPtr;
                                        port->TX.Count--;
                                        eventData = dataWord;
                                    } else if (wordLen == 3) {
                                        unsigned short highWord;
                                        unsigned short lowWord = *readPtr++;
                                        if ((char *)readPtr >= port->TX.End) {
                                            readPtr = (unsigned short *)port->TX.Base;
                                        }
                                        port->TX.Output = (char *)readPtr;
                                        port->TX.Count--;

                                        highWord = *readPtr++;
                                        if ((char *)readPtr >= port->TX.End) {
                                            readPtr = (unsigned short *)port->TX.Base;
                                        }
                                        port->TX.Output = (char *)readPtr;
                                        port->TX.Count--;

                                        eventData = ((unsigned int)highWord << 16) | lowWord;
                                    }

                                    port->Stats.txChars++;
                                    OUTB(port->Base + UART_THR, (unsigned char)eventData);

                                    IOEnterCriticalSection();
                                    // Increment counter
                                    IOExitCriticalSection();
                                }
                            } else if ((lsr & 0x40) == 0) {
                                // Not ready for event processing
                                timerNeeded = 1;
                            } else {
                                unsigned char wordLen;
                                // Execute dequeued event
                                timerNeeded = 0;
                                if (port->WaitingForTXIdle != 0) {
                                    thread_call_cancel(port->FrameTOEntry);
                                    port->WaitingForTXIdle = 0;
                                }

                                // Dequeue event
                                readPtr = (unsigned short *)port->TX.Output;
                                dataWord = *readPtr++;
                                if ((char *)readPtr >= port->TX.End) {
                                    readPtr = (unsigned short *)port->TX.Base;
                                }
                                port->TX.Output = (char *)readPtr;
                                port->TX.Count--;

                                eventType = (unsigned char)dataWord;
                                wordLen = eventType & 3;

                                if (wordLen == 1) {
                                    eventData = (dataWord >> 8);
                                } else if (wordLen == 0) {
                                    eventData = 0;
                                } else if (wordLen == 2) {
                                    dataWord = *readPtr++;
                                    if ((char *)readPtr >= port->TX.End) {
                                        readPtr = (unsigned short *)port->TX.Base;
                                    }
                                    port->TX.Output = (char *)readPtr;
                                    port->TX.Count--;
                                    eventData = dataWord;
                                } else if (wordLen == 3) {
                                    unsigned short highWord;
                                    unsigned short lowWord = *readPtr++;
                                    if ((char *)readPtr >= port->TX.End) {
                                        readPtr = (unsigned short *)port->TX.Base;
                                    }
                                    port->TX.Output = (char *)readPtr;
                                    port->TX.Count--;

                                    highWord = *readPtr++;
                                    if ((char *)readPtr >= port->TX.End) {
                                        readPtr = (unsigned short *)port->TX.Base;
                                    }
                                    port->TX.Output = (char *)readPtr;
                                    port->TX.Count--;

                                    eventData = ((unsigned int)highWord << 16) | lowWord;
                                }

                                _executeEvent(port, eventType, eventData, &newState, &changedBits);
                                continueLoop = TRUE;
                            }
                        }
                    }
                }
            } else {
                // Hardware flow control active - send XON/XOFF
                if (port->RXOstate == 2) {
                    port->Stats.txChars++;
                    OUTB(port->Base + UART_THR, port->XONchar);
                } else {
                    port->Stats.txChars++;
                    OUTB(port->Base + UART_THR, port->XOFFchar);
                }

                IOEnterCriticalSection();
                // Increment counter
                IOExitCriticalSection();

                port->RXOstate = -port->RXOstate;
            }
        }

        // Re-read LSR for next iteration
        lsr = INB(port->Base + UART_LSR);

        // Continue if event was executed or no interrupt pending
        iir = INB(port->Base + UART_IIR);
    } while (continueLoop || ((iir & 0x01) == 0));

    // Check for break condition change
    if ((lsr & 0x60) == 0x20) {
        timerNeeded = 1;
    }

    // Schedule timer if needed
    if ((timerNeeded != 0) && (port->WaitingForTXIdle == 0)) {
        tvalspec_t deadline;
        port->WaitingForTXIdle = 1;
        deadline = _ISASerialPortDeadlineFromParts(
            port->FrameInterval.tv_sec,
            (unsigned int)port->FrameInterval.tv_nsec);
        thread_call_enter_delayed(port->FrameTOEntry, deadline);
    }

    // Update TX watermark state
    if (port->TX.Count <= port->TX.Dequeue) {
        unsigned int txState;

        if (port->TX.Count < port->TX.LowWater) {
            if (port->TX.Count < port->TX.HighWater) {
                port->TX.Enqueue = port->TX.Size - 3;
                if (port->TX.Count > (port->TX.Size - 3)) {
                    port->TX.Dequeue = port->TX.Size;
                    txState = TX_STATE_ABOVE_HIGH;
                } else {
                    port->TX.Dequeue = port->TX.HighWater;
                    txState = 0;
                }
            } else {
                port->TX.Dequeue = port->TX.LowWater;
                port->TX.Enqueue = port->TX.HighWater;
                txState = TX_STATE_BELOW_HIGH;
            }
        } else {
            port->TX.Dequeue = 0;
            if (port->TX.Count == 0) {
                port->TX.Enqueue = 0;
                txState = TX_STATE_EMPTY;
            } else {
                port->TX.Enqueue = port->TX.LowWater;
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

    changedBits |= (port->State ^ newState);

    // Enqueue state change event if mask matches
    stateChangeMask = *(unsigned int *)&port->FlowControl;
    matchBits = (changedBits << 16) & stateChangeMask;
    if (matchBits != 0) {
        if ((port->RX.Size - port->RX.Count) < 3) {
            if (port->RX.Count >= port->RX.Size) {
                port->RX.OverRun = 1;
            } else {
                unsigned short *writePtr = (unsigned short *)port->RX.Input;
                *writePtr++ = EVENT_OVERFLOW;
                if ((char *)writePtr >= port->RX.End) {
                    writePtr = (unsigned short *)port->RX.Base;
                }
                port->RX.Input = (char *)writePtr;
                port->RX.Count++;
            }
        } else {
            _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                               (newState & 0xFFFF) | (matchBits & 0xFFFF0000));
        }
    }

    // Wake threads waiting on state changes
    if (changedBits & port->WatchStateMask) {
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
    }

    // Store new state
    port->State = newState;
}

/*
 * FIFO interrupt handler.
 * Handles all UART interrupts for 16550A+ chips with FIFO.
 * This is called at interrupt level and processes multiple bytes per interrupt.
 */
static void _FIFOIntHandler(void *identity, void *state, Port *port)
{
    unsigned int matchBits;
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
    if ((port->FCRimage & FCR_FIFO_ENABLE) == 0) {
        // FIFO not enabled - use non-FIFO handler
        _NonFIFOIntHandler(identity, state, port);
        return;
    }

    // Initialize locals
    timerNeeded = port->WaitingForTXIdle;
    overrunCounter = 0;
    eventData = 0;
    changedBits = 0;
    eventType = 0;
    newState = port->State;
    firstTHRInt = TRUE;
    firstRXInt = TRUE;
    fifoRemaining = 0;

    // Update interrupt statistics
    port->Stats.ints++;

    // Set heartbeat pending flag
    port->JustDoneInterrupt = 1;

    // Main interrupt processing loop
    do {
        continueLoop = FALSE;

        // Process all data in RX FIFO
        while ((lsr = INB(port->Base + UART_LSR)) & 0x01) {
            // Read data byte from RBR
            dataByte = INB(port->Base + UART_RBR);
            eventData = (unsigned int)dataByte;

            // Check for PCMCIA card removal (all 1's)
            if ((lsr == 0xFF) && (dataByte == 0xFF) && (port->PCMCIA != 0)) {
                _PCMCIA_yanked(port);
                return;
            }

            // Process received data if RX enabled
            if (newState & STATE_RX_ENABLED) {
                unsigned char errorBits;
                // Update statistics on first RX interrupt
                if (firstRXInt && (lsr & 0x01)) {
                    firstRXInt = FALSE;
                    port->Stats.rxInts++;
                }

                port->Stats.rxChars++;

                // Check for overrun error and update counter
                if ((lsr & 0x02) && (overrunCounter == 0)) {
                    overrunCounter = chipCapTable[port->Type].fifoSize;
                }

                errorBits = lsr & 0x1C;  // Parity, Framing, Break errors

                if (errorBits == 0x04) {
                    // Parity error - check for software flow control character
                    if (port->RX_Parity == 6) {  // Software flow control mode
                        // Mask data with RX FIFO mask
                        eventData = dataByte & port->RBRmask;
                        goto process_flow_control_char_fifo;
                    }

                    // Enqueue parity error with data
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_PARITY_ERROR | (dataByte << 8);
                        if ((char *)writePtr >= port->RX.End) {
                            writePtr = (unsigned short *)port->RX.Base;
                        }
                        port->RX.Input = (char *)writePtr;
                        port->RX.Count++;
                    }
                } else if (errorBits == 0) {
                    // No error - normal data reception
process_flow_control_char_fifo:
                    // Check for software flow control characters
                    if ((*(unsigned int *)&port->FlowControl & 0x80008) != 0) {
                        // Software flow control enabled
                        if (eventData == port->XONchar) {
                            newState |= 0x08;
                            changedBits |= 0x08;
                        } else if (eventData == port->XOFFchar) {
                            newState &= ~0x08;
                            changedBits |= 0x08;
                        } else {
                            goto enqueue_normal_data_fifo;
                        }
                    } else {
enqueue_normal_data_fifo:
                        // Check if data needs special handling based on control flags
                        if ((port->FlowControl & 0x00000400) != 0) {
                            newState |= 0x08;
                            changedBits |= 0x08;
                        }

                        // Check character filter bitmap (256 bits)
                        if ((port->SWspecial[eventData >> 5] & (1 << (eventData & 0x1F))) == 0) {
                            eventType = EVENT_VALID_DATA;  // 'U' - normal data
                        } else {
                            eventType = EVENT_SPECIAL_DATA;  // 'Y' - special/filtered data
                        }

                        // Enqueue data with marker
                        if (port->RX.Count >= port->RX.Size) {
                            port->RX.OverRun = 1;
                        } else {
                            unsigned short *writePtr = (unsigned short *)port->RX.Input;
                            *writePtr++ = (unsigned short)eventType | (dataByte << 8);
                            if ((char *)writePtr >= port->RX.End) {
                                writePtr = (unsigned short *)port->RX.Base;
                            }
                            port->RX.Input = (char *)writePtr;
                            port->RX.Count++;
                        }
                    }
                } else if ((errorBits == 0x08) || (errorBits == 0x0C)) {
                    // Framing error or break condition
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_FRAMING_ERROR | (dataByte << 8);
                        if ((char *)writePtr >= port->RX.End) {
                            writePtr = (unsigned short *)port->RX.Base;
                        }
                        port->RX.Input = (char *)writePtr;
                        port->RX.Count++;
                    }
                } else {
                    // Other error
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_ERROR;
                        if ((char *)writePtr >= port->RX.End) {
                            writePtr = (unsigned short *)port->RX.Base;
                        }
                        port->RX.Input = (char *)writePtr;
                        port->RX.Count++;
                    }
                }

                // Check for end of overrun sequence
                if (overrunCounter != 0) {
                    overrunCounter--;
                    if (overrunCounter == 0) {
                        // Enqueue overrun error event
                        if (port->RX.Count >= port->RX.Size) {
                            port->RX.OverRun = 1;
                        } else {
                            unsigned short *writePtr = (unsigned short *)port->RX.Input;
                            *writePtr++ = EVENT_OVERRUN_ERROR;
                            if ((char *)writePtr >= port->RX.End) {
                                writePtr = (unsigned short *)port->RX.Base;
                            }
                            port->RX.Input = (char *)writePtr;
                            port->RX.Count++;
                        }
                    }
                }
            }
        }

        // Update RX watermark state if at target level and port active
        if ((port->RX.Count >= port->RX.Enqueue) && (newState & STATE_ACTIVE)) {
            unsigned int rxState = newState & 0x17E;

            if (port->RX.Count < port->RX.LowWater) {
                port->RX.Dequeue = 0;
                if (port->RX.Count == 0) {
                    rxState |= RX_STATE_EMPTY;
                    port->RX.Enqueue = 0;
                } else {
                    rxState |= RX_STATE_BELOW_LOW;
                    port->RX.Enqueue = port->RX.LowWater;
                }

                if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                    rxState |= STATE_RTS;
                }
                if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                    rxState |= 0x10;
                    if (port->RXOstate == -1) {
                        port->RXOstate = 2;
                    } else if (port->RXOstate == 1) {
                        port->RXOstate = -2;
                    }
                }
                if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                    rxState |= STATE_DTR;
                }
            } else if (port->RX.Count > port->RX.HighWater) {
                port->RX.Enqueue = port->RX.Size - 3;
                if (port->RX.Count > (port->RX.Size - 3)) {
                    rxState |= RX_STATE_CRITICAL;
                    port->RX.Dequeue = port->RX.Size;
                } else {
                    rxState |= RX_STATE_ABOVE_HIGH;
                    port->RX.Dequeue = port->RX.HighWater;
                }

                if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                    rxState &= ~STATE_RTS;
                }
                if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                    rxState &= ~0x10;
                    if (port->RXOstate == -2 || port->RXOstate == 0) {
                        port->RXOstate = 1;
                    } else if (port->RXOstate == 2) {
                        port->RXOstate = -1;
                    }
                }
                if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                    rxState &= ~STATE_DTR;
                }
            } else {
                port->RX.Enqueue = port->RX.HighWater;
                port->RX.Dequeue = port->RX.LowWater;
            }

            newState = (newState & 0xFFF0FFE9) | rxState;
            changedBits |= ((newState ^ port->State) & 0xF0016);

            mcrValue = MCR_OUT2;
            if (rxState & STATE_DTR) mcrValue |= MCR_DTR;
            if (rxState & STATE_RTS) mcrValue |= MCR_RTS;
            OUTB(port->Base + UART_MCR, mcrValue);

            IOEnterCriticalSection();
            IOExitCriticalSection();
        }

        // Handle Modem Status Register changes
        msr = INB(port->Base + UART_MSR);
        newState = (newState & 0xFFFFFE1F) | (_msr_state_lut[msr >> 4] << 5);
        changedBits |= ((newState ^ port->State) & 0x1E0);

        // Handle Transmitter Holding Register Empty (LSR bit 5 or FIFO counter)
        if ((lsr & 0x20) || (fifoRemaining != 0)) {
            if (firstTHRInt) {
                firstTHRInt = FALSE;
                port->Stats.txInts++;
            }

            // Check hardware flow control state
            if (((port->FlowControl & FLOW_HW_ENABLED) == 0) || (port->RXOstate < 1)) {
                if ((newState & 0x1000) == 0) {
                    char peekChar;
                    // Peek at next TX queue entry
                    char *peekPtr = (char *)port->TX.Output;
                    if ((char *)peekPtr >= port->TX.End) {
                        peekPtr = (char *)port->TX.Base;
                    }
                    peekChar = (port->TX.Count != 0) ? *peekPtr : '\0';

                    if (peekChar != 0) {
                        if (peekChar == 'U') {
                            // Data byte transmission
                            unsigned int preventMask = *(unsigned int *)&port->FlowControl;
                            preventMask = (preventMask & 0x168) | 0x20000000;
                            if ((preventMask & ~newState) == 0) {
                                // Can transmit - check if TEMT set for burst mode
                                if ((lsr & 0x40) == 0) {
                                    char peek2Char;
                                    // Transmitter not empty - peek ahead for next byte
                                    char *peek2Ptr = (char *)((unsigned short *)port->TX.Output + 1);
                                    if ((char *)peek2Ptr >= port->TX.End) {
                                        peek2Ptr = (char *)port->TX.Base;
                                    }
                                    peek2Char = (port->TX.Count >= 2) ? *peek2Ptr : '\0';

                                    if (peek2Char == 'U') {
                                        unsigned char wordLen;
                                        // Next is also data - setup FIFO burst
                                        fifoRemaining = chipCapTable[port->Type].fifoSize - 1;
                                        timerNeeded = 0;
                                        if (port->WaitingForTXIdle != 0) {
                                            thread_call_cancel(port->FrameTOEntry);
                                            port->WaitingForTXIdle = 0;
                                        }

                                        // Dequeue and transmit first byte
                                        readPtr = (unsigned short *)port->TX.Output;
                                        dataWord = *readPtr++;
                                        if ((char *)readPtr >= port->TX.End) {
                                            readPtr = (unsigned short *)port->TX.Base;
                                        }
                                        port->TX.Output = (char *)readPtr;
                                        port->TX.Count--;

                                        eventType = (unsigned char)dataWord;
                                        wordLen = eventType & 3;

                                        if (wordLen == 1) {
                                            eventData = (dataWord >> 8);
                                        } else if (wordLen == 0) {
                                            eventData = 0;
                                        } else if (wordLen == 2) {
                                            dataWord = *readPtr++;
                                            if ((char *)readPtr >= port->TX.End) {
                                                readPtr = (unsigned short *)port->TX.Base;
                                            }
                                            port->TX.Output = (char *)readPtr;
                                            port->TX.Count--;
                                            eventData = dataWord;
                                        } else if (wordLen == 3) {
                                            unsigned short highWord;
                                            unsigned short lowWord = *readPtr++;
                                            if ((char *)readPtr >= port->TX.End) {
                                                readPtr = (unsigned short *)port->TX.Base;
                                            }
                                            port->TX.Output = (char *)readPtr;
                                            port->TX.Count--;

                                            highWord = *readPtr++;
                                            if ((char *)readPtr >= port->TX.End) {
                                                readPtr = (unsigned short *)port->TX.Base;
                                            }
                                            port->TX.Output = (char *)readPtr;
                                            port->TX.Count--;

                                            eventData = ((unsigned int)highWord << 16) | lowWord;
                                        }

                                        port->Stats.txChars++;
                                        OUTB(port->Base + UART_THR, (unsigned char)eventData);

                                        IOEnterCriticalSection();
                                        IOExitCriticalSection();
                                    }
                                } else {
                                    // TEMT set - can do FIFO burst transmission
                                    fifoRemaining = chipCapTable[port->Type].fifoSize;
                                    timerNeeded = 0;
                                    if (port->WaitingForTXIdle != 0) {
                                        thread_call_cancel(port->FrameTOEntry);
                                        port->WaitingForTXIdle = 0;
                                    }
                                }

                                // Transmit remaining FIFO bytes
                                while (fifoRemaining != 0) {
                                    unsigned char wordLen;
                                    // Peek at next entry
                                    peekPtr = (char *)port->TX.Output;
                                    if ((char *)peekPtr >= port->TX.End) {
                                        peekPtr = (char *)port->TX.Base;
                                    }
                                    peekChar = (port->TX.Count != 0) ? *peekPtr : '\0';

                                    if (peekChar != 'U') break;

                                    // Dequeue and transmit
                                    readPtr = (unsigned short *)port->TX.Output;
                                    dataWord = *readPtr++;
                                    if ((char *)readPtr >= port->TX.End) {
                                        readPtr = (unsigned short *)port->TX.Base;
                                    }
                                    port->TX.Output = (char *)readPtr;
                                    port->TX.Count--;

                                    eventType = (unsigned char)dataWord;
                                    wordLen = eventType & 3;

                                    if (wordLen == 1) {
                                        eventData = (dataWord >> 8);
                                    } else if (wordLen == 0) {
                                        eventData = 0;
                                    } else if (wordLen == 2) {
                                        dataWord = *readPtr++;
                                        if ((char *)readPtr >= port->TX.End) {
                                            readPtr = (unsigned short *)port->TX.Base;
                                        }
                                        port->TX.Output = (char *)readPtr;
                                        port->TX.Count--;
                                        eventData = dataWord;
                                    } else if (wordLen == 3) {
                                        unsigned short highWord;
                                        unsigned short lowWord = *readPtr++;
                                        if ((char *)readPtr >= port->TX.End) {
                                            readPtr = (unsigned short *)port->TX.Base;
                                        }
                                        port->TX.Output = (char *)readPtr;
                                        port->TX.Count--;

                                        highWord = *readPtr++;
                                        if ((char *)readPtr >= port->TX.End) {
                                            readPtr = (unsigned short *)port->TX.Base;
                                        }
                                        port->TX.Output = (char *)readPtr;
                                        port->TX.Count--;

                                        eventData = ((unsigned int)highWord << 16) | lowWord;
                                    }

                                    port->Stats.txChars++;
                                    OUTB(port->Base + UART_THR, (unsigned char)eventData);

                                    IOEnterCriticalSection();
                                    IOExitCriticalSection();

                                    fifoRemaining--;
                                }

                                goto tx_done_fifo;
                            }
                        } else if ((lsr & 0x40) != 0) {
                            unsigned char wordLen;
                            // Non-data event and TEMT set - execute it
                            timerNeeded = 0;
                            if (port->WaitingForTXIdle != 0) {
                                thread_call_cancel(port->FrameTOEntry);
                                port->WaitingForTXIdle = 0;
                            }

                            // Dequeue event
                            readPtr = (unsigned short *)port->TX.Output;
                            dataWord = *readPtr++;
                            if ((char *)readPtr >= port->TX.End) {
                                readPtr = (unsigned short *)port->TX.Base;
                            }
                            port->TX.Output = (char *)readPtr;
                            port->TX.Count--;

                            eventType = (unsigned char)dataWord;
                            wordLen = eventType & 3;

                            if (wordLen == 1) {
                                eventData = (dataWord >> 8);
                            } else if (wordLen == 0) {
                                eventData = 0;
                            } else if (wordLen == 2) {
                                dataWord = *readPtr++;
                                if ((char *)readPtr >= port->TX.End) {
                                    readPtr = (unsigned short *)port->TX.Base;
                                }
                                port->TX.Output = (char *)readPtr;
                                port->TX.Count--;
                                eventData = dataWord;
                            } else if (wordLen == 3) {
                                unsigned short highWord;
                                unsigned short lowWord = *readPtr++;
                                if ((char *)readPtr >= port->TX.End) {
                                    readPtr = (unsigned short *)port->TX.Base;
                                }
                                port->TX.Output = (char *)readPtr;
                                port->TX.Count--;

                                highWord = *readPtr++;
                                if ((char *)readPtr >= port->TX.End) {
                                    readPtr = (unsigned short *)port->TX.Base;
                                }
                                port->TX.Output = (char *)readPtr;
                                port->TX.Count--;

                                eventData = ((unsigned int)highWord << 16) | lowWord;
                            }

                            _executeEvent(port, eventType, eventData, &newState, &changedBits);
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
                if (port->RXOstate == 2) {
                    port->Stats.txChars++;
                    OUTB(port->Base + UART_THR, port->XONchar);
                } else {
                    port->Stats.txChars++;
                    OUTB(port->Base + UART_THR, port->XOFFchar);
                }

                IOEnterCriticalSection();
                IOExitCriticalSection();

                port->RXOstate = -port->RXOstate;

                if (fifoRemaining != 0) {
                    fifoRemaining--;
                }
            }
        }

        // Check for more interrupts
        iir = INB(port->Base + UART_IIR);
    } while (continueLoop || (overrunCounter != 0) || (fifoRemaining != 0) || ((iir & 0x01) == 0));

    // Check for break condition change
    if ((lsr & 0x60) == 0x20) {
        timerNeeded = 1;
    }

    // Schedule timer if needed
    if ((timerNeeded != 0) && (port->WaitingForTXIdle == 0)) {
        tvalspec_t deadline;
        port->WaitingForTXIdle = 1;
        deadline = _ISASerialPortDeadlineFromParts(
            port->FrameInterval.tv_sec,
            (unsigned int)port->FrameInterval.tv_nsec);
        thread_call_enter_delayed(port->FrameTOEntry, deadline);
    }

    // Update TX watermark state
    if (port->TX.Count <= port->TX.Dequeue) {
        unsigned int txState;

        if (port->TX.Count < port->TX.LowWater) {
            if (port->TX.Count < port->TX.HighWater) {
                port->TX.Enqueue = port->TX.Size - 3;
                if (port->TX.Count > (port->TX.Size - 3)) {
                    port->TX.Dequeue = port->TX.Size;
                    txState = TX_STATE_ABOVE_HIGH;
                } else {
                    port->TX.Dequeue = port->TX.HighWater;
                    txState = 0;
                }
            } else {
                port->TX.Dequeue = port->TX.LowWater;
                port->TX.Enqueue = port->TX.HighWater;
                txState = TX_STATE_BELOW_HIGH;
            }
        } else {
            port->TX.Dequeue = 0;
            if (port->TX.Count == 0) {
                port->TX.Enqueue = 0;
                txState = TX_STATE_EMPTY;
            } else {
                port->TX.Enqueue = port->TX.LowWater;
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

    changedBits |= (port->State ^ newState);

    // Enqueue state change event if mask matches
    stateChangeMask = *(unsigned int *)&port->FlowControl;
    matchBits = (changedBits << 16) & stateChangeMask;
    if (matchBits != 0) {
        if ((port->RX.Size - port->RX.Count) < 3) {
            if (port->RX.Count >= port->RX.Size) {
                port->RX.OverRun = 1;
            } else {
                unsigned short *writePtr = (unsigned short *)port->RX.Input;
                *writePtr++ = EVENT_OVERFLOW;
                if ((char *)writePtr >= port->RX.End) {
                    writePtr = (unsigned short *)port->RX.Base;
                }
                port->RX.Input = (char *)writePtr;
                port->RX.Count++;
            }
        } else {
            _RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                               (newState & 0xFFFF) | (matchBits & 0xFFFF0000));
        }
    }

    // Wake threads waiting on state changes
    if (changedBits & port->WatchStateMask) {
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
    }

    // Store new state
    port->State = newState;
}

/*
 * _executeEvent - Execute an event command on the serial port
 *
 * This function implements the event dispatcher for serial port control commands.
 * It handles configuration changes, queue management, and state control.
 *
 * Parameters:
 *   port - Pointer to the port's state block
 *   eventType - Event type identifier (determines action to take)
 *   eventData - Event-specific data parameter
 *   statePtr - Pointer to state value (output parameter)
 *   changedBitsPtr - Pointer to changed bits mask (output parameter)
 */
static void _executeEvent(Port *port, unsigned char eventType,
                         unsigned int eventData, unsigned int *statePtr,
                         unsigned int *changedBitsPtr)
{
    unsigned int oldState;
    unsigned int newState;
    unsigned int changedBits;
    unsigned int tempValue;
    unsigned int bitIndex;
    unsigned int byteIndex;

    oldState = port->State;
    newState = oldState;
    changedBits = 0;

    switch (eventType) {
        case 0x05:  // Activate/Deactivate port
            if (eventData != 0) {
                // Activate port
                _activatePort(port);
                newState |= STATE_ACTIVE;
            } else {
                // Deactivate port
                _deactivatePort(port);
                newState &= ~STATE_ACTIVE;
            }
            changedBits = STATE_ACTIVE;
            break;

        case 0x13:  // Set TX medium watermark
            if (eventData <= port->TX.Size) {
                port->TX.LowWater = eventData;
            }
            break;

        case 0x17:  // Set RX low watermark
            if (eventData <= port->RX.Size) {
                port->RX.LowWater = eventData;
                // Recalculate flow control if needed
                tempValue = flowMachine(port);
                changedBits = tempValue ^ oldState;
                newState = tempValue;
            }
            break;

        case 0x1B:  // Set TX low watermark
            if (eventData <= port->TX.Size) {
                port->TX.HighWater = eventData;
            }
            break;

        case 0x1F:  // Set RX high watermark
            if (eventData <= port->RX.Size) {
                port->RX.HighWater = eventData;
                // Recalculate flow control if needed
                tempValue = flowMachine(port);
                changedBits = tempValue ^ oldState;
                newState = tempValue;
            }
            break;

        case 0x28:  // Flush TX queue
            // Reset TX ring buffer
            port->TX.Output = port->TX.Base;
            port->TX.Input = port->TX.Base;
            port->TX.Count = 0;
            // Update TX state to empty
            newState = (newState & ~TX_STATE_MASK) | TX_STATE_EMPTY;
            changedBits = TX_STATE_MASK;
            break;

        case 0x2F:  // Flush RX queue
            // Reset RX ring buffer
            port->RX.Output = port->RX.Base;
            port->RX.Input = port->RX.Base;
            port->RX.Count = 0;
            port->RX.OverRun = 0;
            // Update RX state to empty
            newState = (newState & ~RX_STATE_MASK) | RX_STATE_EMPTY;
            changedBits = RX_STATE_MASK;
            // Recalculate flow control
            tempValue = flowMachine(port);
            changedBits |= tempValue ^ newState;
            newState = tempValue;
            break;

        case 0x33:  // Set baud rate
            if (eventData != 0 && eventData != port->BaudRate) {
                port->BaudRate = eventData;
                // Calculate new divisor
                port->DLRimage = (unsigned short)(port->MasterClock / (eventData << 3));
                if (port->DLRimage == 0) {
                    port->DLRimage = 1;
                }
                // Reprogram chip if active
                if (oldState & STATE_ACTIVE) {
                    programChip(port);
                }
                // Calculate character time in nanoseconds
                // Character time = (dataBits + stopBits + 1 for start bit + parity) * bit_time
                // bit_time = 1000000000 / baud_rate nanoseconds
                tempValue = port->CharLength + port->StopBits + 2; // +2 for start bit and parity
                if (port->TX_Parity == PARITY_NONE) {
                    tempValue--; // No parity bit
                }
                // Calculate: (tempValue * 1000000000) / baudRate
                // Use 64-bit arithmetic to avoid overflow
                port->FrameInterval.tv_sec = __udivdi3(tempValue * 1000000000, 0, eventData, 0);
                port->FrameInterval.tv_nsec = __umoddi3(tempValue * 1000000000, 0, eventData, 0);
            }
            break;

        case 0x3B:  // Set data bits (10=5 bits, 12=6 bits, 14=7 bits, 16=8 bits)
            if (eventData >= 10 && eventData <= 16 && (eventData & 1) == 0) {
                port->CharLength = eventData;
                // Update LCR value
                port->LCRimage = (port->LCRimage & 0xFC) | ((eventData - 10) >> 1);
                // Reprogram chip if active
                if (oldState & STATE_ACTIVE) {
                    programChip(port);
                }
            }
            break;

        case 0x43:  // Set parity
            if (eventData >= PARITY_NONE && eventData <= PARITY_SPACE) {
                port->TX_Parity = eventData;
                // Update LCR value based on parity type
                tempValue = port->LCRimage & 0xC7; // Clear parity bits
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
                port->LCRimage = (unsigned char)tempValue;
                // Reprogram chip if active
                if (oldState & STATE_ACTIVE) {
                    programChip(port);
                }
            }
            break;

        case 0x47:  // Set flow control
            port->RX_Parity = eventData;
            // Update flow control mode flags
            port->FlowControl &= ~(FLOW_DTR_ENABLED | FLOW_RTS_ENABLED | FLOW_HW_ENABLED);
            if (eventData & 0x02) {
                port->FlowControl |= FLOW_DTR_ENABLED;
            }
            if (eventData & 0x04) {
                port->FlowControl |= FLOW_RTS_ENABLED;
            }
            if (eventData & 0x10) {
                port->FlowControl |= FLOW_HW_ENABLED;
            }
            // Recalculate flow control state
            tempValue = flowMachine(port);
            changedBits = tempValue ^ oldState;
            newState = tempValue;
            break;

        case 0x4B:  // Set delay timeout
            // Cancel existing delay timeout if active
            if (port->DelayTOEntry != NULL) {
                thread_call_cancel(port->DelayTOEntry);
            }
            // Set new delay timeout if non-zero
            if (eventData != 0) {
                tvalspec_t deadline = _ISASerialPortDeadlineFromParts(eventData, 0);
                thread_call_enter_delayed(port->DelayTOEntry, deadline);
            }
            break;

        case 0x4F:  // Set character time override
            port->DataLatInterval.tv_sec = eventData & 0xFFFF;
            port->DataLatInterval.tv_nsec = (eventData >> 16) & 0xFFFF;
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
                port->SWspecial[byteIndex] &= ~(1 << bitIndex);
            }
            break;

        case 0x59:  // Mark character (add to filter)
            if (eventData <= 0xFF) {
                bitIndex = eventData & 0x1F;  // Bit position within word
                byteIndex = eventData >> 5;   // Word index (0-7)
                port->SWspecial[byteIndex] |= (1 << bitIndex);
            }
            break;

        case 0xE5:  // Force FIFO disable
            port->MinLatency = (eventData != 0) ? 1 : 0;
            // Reinitialize chip if active
            if (oldState & STATE_ACTIVE) {
                initChip(port);
            }
            break;

        case 0xE9:  // Set XON character
            if (eventData <= 0xFF) {
                port->XONchar = (unsigned char)eventData;
            }
            break;

        case 0xED:  // Set XOFF character
            if (eventData <= 0xFF) {
                port->XOFFchar = (unsigned char)eventData;
            }
            break;

        case 0xF3:  // Set stop bits (2=1 stop bit, 3+=2 stop bits)
            if (eventData >= 2 && eventData <= 4) {
                port->StopBits = eventData;
                // Update LCR value
                if (eventData == 2) {
                    port->LCRimage &= ~0x04; // 1 stop bit
                } else {
                    port->LCRimage |= 0x04;  // 2 stop bits
                }
                // Reprogram chip if active
                if (oldState & STATE_ACTIVE) {
                    programChip(port);
                }
            }
            break;

        case 0xF9:  // Set break state
            if (eventData != 0) {
                // Set break
                port->LCRimage |= 0x40;
            } else {
                // Clear break
                port->LCRimage &= ~0x40;
            }
            // Write to LCR register if active
            if (oldState & STATE_ACTIVE) {
                outb(port->Base + UART_LCR, port->LCRimage);
            }
            break;

        default:
            // Unknown event type - ignore
            break;
    }

    // Update state if changed
    if (newState != oldState) {
        port->State = newState;
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
    unsigned char norm_shift;
    unsigned char denorm_shift;
    unsigned long long norm_divisor;
    unsigned long long norm_dividend;
    unsigned long long remainder;
    unsigned long long product;
    unsigned long long rem_and_low;
    unsigned long long dividend, divisor, quotient;
    unsigned int shift;
    unsigned long long temp;

    dividend = ((unsigned long long)dividend_hi << 32) | dividend_lo;
    divisor = ((unsigned long long)divisor_hi << 32) | divisor_lo;

    // Fast path: divisor high word is zero
    if (divisor_hi == 0) {
        // Check if dividend also fits in 32 bits or divisor > dividend_hi
        if (divisor_lo <= dividend_hi) {
            unsigned int quot_hi;
            unsigned long long remainder_and_low;
            unsigned int quot_lo;
            // Need to do 64-bit division
            if (divisor_lo == 0) {
                // Division by zero - trigger exception
                divisor_lo = 1 / 0;  // This will cause a divide-by-zero exception
            }
            // Divide high word first, then combine with low word
            quot_hi = dividend_hi / divisor_lo;
            remainder_and_low = ((unsigned long long)(dividend_hi % divisor_lo) << 32) | dividend_lo;
            quot_lo = remainder_and_low / divisor_lo;
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
    norm_shift = (unsigned char)(shift ^ 31);
    denorm_shift = 32 - norm_shift;

    // Normalize divisor
    norm_divisor = (divisor_hi << norm_shift) | (divisor_lo >> denorm_shift);

    // Normalize dividend
    norm_dividend =
        ((unsigned long long)(dividend_hi >> denorm_shift) << 32) |
        ((dividend_hi << norm_shift) | (dividend_lo >> denorm_shift));

    // Estimate quotient
    quotient = norm_dividend / norm_divisor;
    remainder = norm_dividend % norm_divisor;

    // Refine quotient if necessary
    product = ((unsigned long long)(divisor_lo << norm_shift) * quotient);
    rem_and_low = ((remainder << 32) | (dividend_lo << norm_shift));

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
            unsigned long long temp;
            // Need to compute (dividend_hi % divisor) * 2^32 + dividend_lo) % divisor
            if (divisor_lo == 0) {
                divisor_lo = 1 / 0;  // Division by zero
            }
            temp = ((unsigned long long)(dividend_hi % divisor_lo) << 32) | dividend_lo;
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
            unsigned int quot_estimate;
            unsigned int rem_estimate;
            unsigned long long product;
            unsigned long long rem_and_low;
            unsigned int rem_hi;
            unsigned int borrow;
            unsigned int rem_lo;
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
            quot_estimate = (unsigned int)(norm_dividend / norm_divisor_hi);
            rem_estimate = (unsigned int)(norm_dividend % norm_divisor_hi);

            // Compute product
            product = (unsigned long long)norm_divisor_lo * quot_estimate;
            rem_and_low = ((unsigned long long)rem_estimate << 32) | norm_dividend_lo;

            // Adjust if needed
            if (rem_and_low < product) {
                unsigned long long norm_divisor_full = ((unsigned long long)norm_divisor_hi << 32) | norm_divisor_lo;
                product = product - norm_divisor_full;
            }

            // Compute final remainder
            rem_hi = rem_estimate - (unsigned int)(product >> 32);
            borrow = (norm_dividend_lo < (unsigned int)product) ? 1 : 0;
            rem_hi = rem_hi - borrow;
            rem_lo = norm_dividend_lo - (unsigned int)product;

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
        chipType = identifyChip(self->port);
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
    initChip(self->port);

    // Allocate timer callout objects
    *(void **)((char *)self + 0x210) = thread_call_allocate(NULL, NULL);
    *(void **)((char *)self + 0x214) = thread_call_allocate(NULL, NULL);
    *(void **)((char *)self + 0x218) = thread_call_allocate(_delayTOHandler, self->port);
    *(void **)((char *)self + 0x21c) = thread_call_allocate(_heartBeatTOHandler, self->port);

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
        rxSize = validateRingBufferSize(rxSize, &self->Port.TX);
        *(unsigned int *)((char *)self + 0x1a4) = rxSize;
    }

    // Read TX buffer size from config
    txBufStr = [deviceDescription valueForStringKey:"TXBufSize"];
    *(unsigned int *)((char *)self + 0x16c) = 0x4b0;  // Default 1200
    if (txBufStr != NULL) {
        unsigned int txSize = (unsigned int)strtol(txBufStr, NULL, 10);
        txSize = validateRingBufferSize(txSize, &self->Port.RX);
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
    _deactivatePort(self->port);

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
        if (self->Port.PCMCIA_yanked != 0) {
            splx(oldIRQL);
            return 0xFFFFFD3B; // Device not available
        }

        // Check if port is already acquired (bit 0x80000000 of checkMask/state)
        checkMask = self->Port.State & 0x80000000;

        if (checkMask == 0) {
            unsigned int txLowWater;
            unsigned int rxLowWater;
            // Port not acquired - proceed with acquisition

            // Set initial state to 0xA0400018
            // This includes: STATE_ACTIVE (0x40000000), RX enabled (0x80000), and other flags
            oldState = self->Port.State;
            newState = 0xA0400018;
            changedBits = oldState ^ newState;
            self->Port.State = newState;

            // Wake up any threads waiting on state changes
            if (self->Port.WatchStateMask & changedBits) {
                thread_wakeup_prim(&self->Port.WatchStateMask, 0, 4);
            }

            // Update DTR/RTS if they changed
            if (changedBits & STATE_FLOW_MASK) {
                outb(self->Port.Base + UART_MCR, MCR_OUT2);
                // Atomic increment (LOCK/UNLOCK omitted)
            }

            // Trigger timer callout
            if ((self->Port.State & 0x10000000) == 0) {
                thread_call_enter(self->Port.FrameTOEntry);
            }

            // Enqueue state change event
            memcpy(&eventMask, &self->Port.FlowControl, sizeof(unsigned int));
            if (eventMask & (changedBits << 16)) {
                _RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
                                   (changedBits << 16) | 0x18);
            }

            // Clear character filter bitmap (8 words at offset 0x1e8)
            for (i = 0; i < 8; i++) {
                self->Port.SWspecial[i] = 0;
            }

            // Set default serial port parameters
            self->Port.CharLength = 16;         // 16 = 8 data bits (encoded as 10/12/14/16 for 5/6/7/8)
            self->Port.StopBits = 2;          // 2 = 1 stop bit
            self->Port.XONchar = 0x11;        // DC1 (XON)
            self->Port.XOFFchar = 0x13;       // DC3 (XOFF)
            self->Port.RX_Parity = 2;       // Flow control mode
            self->Port.TX_Parity = PARITY_NONE;  // No parity
            self->Port.RXOstate = 0;  // Initial flow control state
            self->Port.BaudRate = 19200;      // Default 19200 baud (0x4b00)
            self->Port.MasterClock = 0x126;     // UART clock rate (seems odd, might be scaled)
            self->Port.FlowControl = 0;   // Flow control mode flags

            // Set TX queue watermarks based on capacity
            // High watermark = capacity
            // Low watermark = (capacity * 2) / 3
            // Med watermark = low / 2
            self->Port.TX.Enqueue = self->Port.TX.Size;
            txLowWater = (self->Port.TX.Size * 2) / 3;
            self->Port.TX.HighWater = txLowWater;
            self->Port.TX.LowWater = txLowWater >> 1;

            // Clear some flag at offset 0x168 (unknown purpose)
            // *(undefined4 *)(param_1 + 0x168) = 0;

            // Set RX queue watermarks based on capacity
            // High watermark = capacity
            // Low watermark = (capacity * 2) / 3
            // Target = low watermark
            self->Port.RX.HighWater = self->Port.RX.Size;
            rxLowWater = (self->Port.RX.Size * 2) / 3;
            self->Port.RX.LowWater = rxLowWater;
            self->Port.RX.Enqueue = rxLowWater;

            // Clear some field at offset 0x1d4 (unknown)
            // *(undefined2 *)(param_1 + 0x1d4) = 0;

            // Program the UART chip
            programChip(self->port);

            // Disable most UART interrupts (keep only bit 3 if set in ierValue)
            outb(self->Port.Base + UART_IER, self->Port.IERmask & 0x08);
            // Atomic increment

            // Calculate flow control state
            flowState = flowMachine(self->port);

            // Read Modem Status Register
            msrValue = inb(self->Port.Base + UART_MSR);

            // Convert MSR delta bits to state bits using lookup table
            msrStateBits = _msr_state_lut[msrValue >> 4];

            // Update state with flow control and MSR bits
            oldState = self->Port.State;
            newState = (oldState & 0xFFFFFE09) | (flowState & 0x1F6) | (msrStateBits << 5);
            changedBits = oldState ^ newState;
            self->Port.State = newState;

            // Wake up threads
            if (self->Port.WatchStateMask & changedBits) {
                thread_wakeup_prim(&self->Port.WatchStateMask, 0, 4);
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
                outb(self->Port.Base + UART_MCR, mcrValue);
                // Atomic increment
            }

            // Trigger timer callout
            if ((self->Port.State & 0x10000000) == 0) {
                thread_call_enter(self->Port.FrameTOEntry);
            }

            // Enqueue state change event
            memcpy(&eventMask, &self->Port.FlowControl, sizeof(unsigned int));
            if (eventMask & (changedBits << 16)) {
                _RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
                                   ((oldState & 0xFE09) | (flowState & 0x1F6) | (msrStateBits << 5)) |
                                   (changedBits << 16));
            }

            // Start heartbeat timer if interval is set
            // Check if heartBeatInterval is non-zero
            if ((self->Port.HeartBeatInterval.tv_sec != 0 || self->Port.HeartBeatInterval.tv_nsec != 0)) {
                thread_call_enter(self->Port.HeartBeatTOEntry);
            } else {
                // Use frame timeout timer instead
                thread_call_enter(self->Port.FrameTOEntry);
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
 *   0xFFFFFD33 if port was not acquired
 */
- (IOReturn)release
{
    unsigned int oldIRQL;
    unsigned int i;
    unsigned int txWaterLow, txWaterMed;
    unsigned int rxWaterHigh, rxWaterLow;
    Port *selfPtr;
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
        programChip(*(Port **)((char *)self + 600));

        // Deactivate port (pass value at offset 600)
        _deactivatePort(*(Port **)((char *)self + 600));

        // Update state and wake waiting threads
        selfPtr = *(Port **)((char *)self + 600);
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
        OUTB(*(unsigned short *)((char *)*(Port **)((char *)self + 600) + 0x88) + UART_IER, 0);

        // Clear modem control register (MCR = 0)
        OUTB(*(unsigned short *)((char *)*(Port **)((char *)self + 600) + 0x88) + UART_MCR, 0);

        splx(oldIRQL);
        return IO_R_SUCCESS;
    } else {
        // Port was not acquired
        splx(oldIRQL);
        return 0xFFFFFD33;
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
    tvalspec_t deadline = { 0, 0 };

    // Validate parameters
    if (count == NULL || buffer == NULL || size < minCount) {
        return 0xFFFFFD3E; // Invalid argument
    }

    // Get character time override values (offset 0x228 = charTimeOverrideLow, 0x22c = charTimeOverrideHigh)
    charTimeLo = self->Port.DataLatInterval.tv_sec;
    charTimeHi = self->Port.DataLatInterval.tv_nsec;

    // Determine if we should schedule a timeout timer
    // Timer is scheduled if character time is set and buffer size > 1
    timerScheduled = 0;
    if (((unsigned long long)charTimeLo * 1000000000ULL + (long long)charTimeHi) != 0 && size > 1) {
        timerScheduled = 1;
    }

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is active (statusFlags at offset 0x137 & 0x40)
    if ((self->Port.State & 0x40000000) == 0) {
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
        result = RX_dequeueData(self->port, writePtr, (remainingMin != 0));

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
            deadline = _ISASerialPortDeadlineFromParts(charTimeLo, charTimeHi);
            thread_call_enter_delayed(self->Port.DelayTOEntry, deadline);
            timerScheduled = -1;  // Mark as scheduled
        }
    }

    // Cancel character timeout timer if it was scheduled
    if (timerScheduled < 0) {
        thread_call_cancel(self->Port.DelayTOEntry);
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
    if ((self->Port.State & 0x40000000) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not active
    }

    // Dequeue event from RX queue
    result = RX_dequeueEvent(self->port, &eventType, data, sleep);

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
    if ((self->Port.State & 0x40000000) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not active
    }

    remainingSize = size;
    readPtr = buffer;

    // Loop until all data is enqueued
    while (remainingSize != 0) {
        // Calculate free space in TX queue
        freeSpace = self->Port.TX.Size - self->Port.TX.Count;

        // Wait for space if queue is full
        while (freeSpace == 0) {
            if (!sleep) {
                // Not sleeping - return error
                splx(oldIRQL);
                return 0xFFFFFD42; // Queue full
            }

            // Sleep waiting for TX queue to have space (TX_STATE_EMPTY bit 0x800000)
            checkMask = 0;
            result = watchState(self->port, &checkMask, 0x800000);

            if (result != IO_R_SUCCESS) {
                splx(oldIRQL);
                return result;
            }

            // Recalculate free space after waking
            freeSpace = self->Port.TX.Size - self->Port.TX.Count;
        }

        // Calculate how much we can enqueue in this iteration
        chunkSize = remainingSize;

        // Limit by free space
        if (freeSpace < chunkSize) {
            chunkSize = freeSpace;
        }

        // Limit by distance to end of circular buffer
        // Each entry is 2 bytes, so divide by 2
        spaceToEnd = ((unsigned int)self->Port.TX.End - (unsigned int)self->Port.TX.Input) >> 1;
        if (spaceToEnd < chunkSize) {
            chunkSize = spaceToEnd;
        }

        // Update counters
        remainingSize -= chunkSize;
        self->Port.TX.Count += chunkSize;
        *count += chunkSize;

        // Enqueue bytes in TX queue format (0x55 marker + data byte)
        for (i = 0; i < chunkSize; i++) {
            // Write marker byte (0x55 = 'U')
            *(unsigned char *)self->Port.TX.Input = 0x55;
            self->Port.TX.Input = (char *)self->Port.TX.Input + 1;

            // Write data byte
            *(unsigned char *)self->Port.TX.Input = *readPtr;
            readPtr++;
            self->Port.TX.Input = (char *)self->Port.TX.Input + 1;
        }

        // Wrap write pointer if at end
        if (self->Port.TX.Input >= self->Port.TX.End) {
            self->Port.TX.Input = self->Port.TX.Base;
        }

        // Update TX state based on watermark levels
        if (self->Port.TX.Count >= self->Port.TX.Enqueue) {
            // Used >= highWater
            if (self->Port.TX.Count > self->Port.TX.LowWater) {
                // Used > medWater
                if (self->Port.TX.Count > self->Port.TX.HighWater) {
                    // Used > lowWater (critical/above high)
                    self->Port.TX.Enqueue = self->Port.TX.Size - 3;
                    if (self->Port.TX.Count > (self->Port.TX.Size - 3)) {
                        // Critical level
                        self->Port.TX.Dequeue = self->Port.TX.Size;
                        txState = 0x1800000;
                    } else {
                        // Above high watermark
                        self->Port.TX.Dequeue = self->Port.TX.HighWater;
                        txState = 0x1000000;
                    }
                } else {
                    // medWater < used <= lowWater
                    self->Port.TX.Enqueue = self->Port.TX.HighWater;
                    self->Port.TX.Dequeue = self->Port.TX.LowWater;
                    txState = 0;
                }
            } else {
                // Used <= medWater
                self->Port.TX.Dequeue = 0;
                if (self->Port.TX.Count == 0) {
                    // Empty
                    self->Port.TX.Enqueue = 0;
                    txState = TX_STATE_EMPTY;
                } else {
                    // Below medium watermark
                    self->Port.TX.Enqueue = self->Port.TX.LowWater;
                    txState = TX_STATE_BELOW_LOW;
                }
            }

            // Update current state with new TX state
            oldState = self->Port.State;
            newState = (oldState & 0xF87FFFFF) | txState;
            changedBits = oldState ^ newState;
            self->Port.State = newState;

            // Wake up threads waiting on state changes
            if (self->Port.WatchStateMask & changedBits) {
                thread_wakeup_prim(&self->Port.WatchStateMask, 0, 4);
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
                outb(self->Port.Base + UART_MCR, mcrValue);
                // Atomic increment (LOCK/UNLOCK omitted)
            }

            // Trigger timer callout
            if ((self->Port.State & 0x10000000) == 0) {
                thread_call_enter(self->Port.FrameTOEntry);
            }

            // Enqueue state change event
            memcpy(&eventMask, &self->Port.FlowControl, sizeof(unsigned int));
            if (eventMask & (changedBits << 16)) {
                _RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
                                   (oldState & 0xFFFF) | (changedBits << 16));
            }
        }

        // Trigger TX operation timer if not paused
        if ((self->Port.State & 0x10000000) == 0) {
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
    if ((self->Port.State & 0x40000000) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not active
    }

    // Enqueue event to TX queue
    // Extract event type (low byte) and pass data
    result = TX_enqueueEvent(self->port, (unsigned char)(event & 0xFF), data, sleep);

    // If successful and port not paused, trigger TX timer
    if (result == IO_R_SUCCESS && (self->Port.State & 0x10000000) == 0) {
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
    if ((self->Port.State & 0x80000000) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not acquired
    }

    // Handle special event types
    if (event == 0x0F) {
        // Set RX buffer size (offset 0x140 = txQueueCapacity in wrong place?)
        // Actually this seems to be setting a different buffer size
        // Based on offset 0x140, this is setting TX queue capacity
        if ((self->Port.State & 0x40000000) != 0) {
            // Port is active - cannot change buffer size
            result = 0xFFFFFD2B;
        } else {
            // Port not active - can change buffer size
            validatedSize = validateRingBufferSize(data, &self->Port.TX);
            // Store at offset 0x140 - this appears to be txQueueCapacity field
            self->Port.TX.Size = validatedSize;

            // Adjust high watermark if necessary
            if ((validatedSize - 3) < self->Port.TX.HighWater) {
                self->Port.TX.HighWater = validatedSize - 3;
            }

            // Adjust medium watermark if necessary
            if ((self->Port.TX.HighWater - 3) < self->Port.TX.LowWater) {
                self->Port.TX.LowWater = self->Port.TX.HighWater - 3;
            }
        }
    } else if (event == 0x0B) {
        // Set TX buffer size (offset 0x178 = rxQueueCapacity)
        // Actually setting RX queue capacity based on offset
        if ((self->Port.State & 0x40000000) != 0) {
            // Port is active - cannot change buffer size
            result = 0xFFFFFD2B;
        } else {
            // Port not active - can change buffer size
            validatedSize = validateRingBufferSize(data, &self->Port.RX);
            // Store at offset 0x178 - this is rxQueueCapacity
            self->Port.RX.Size = validatedSize;

            // Adjust high watermark if necessary
            if ((validatedSize - 3) < self->Port.RX.HighWater) {
                self->Port.RX.HighWater = validatedSize - 3;
            }

            // Adjust low watermark if necessary
            if ((self->Port.RX.HighWater - 3) < self->Port.RX.LowWater) {
                self->Port.RX.LowWater = self->Port.RX.HighWater - 3;
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
                self->Port.RXOstate = 0;
            }

            // Recalculate flow control state
            flowState = flowMachine(self->port);

            // Update current state with new flow control bits
            oldState = self->Port.State;
            newState = (oldState & 0xFFFFFFE9) | (flowState & 0x16);
            changedBits = oldState ^ newState;
            self->Port.State = newState;

            // Wake up threads
            if (self->Port.WatchStateMask & changedBits) {
                thread_wakeup_prim(&self->Port.WatchStateMask, 0, 4);
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
                outb(self->Port.Base + UART_MCR, mcrValue);
                // Atomic increment
            }

            // Trigger timer
            if ((self->Port.State & 0x10000000) == 0) {
                thread_call_enter(self->Port.FrameTOEntry);
            }

            // Enqueue state change event
            memcpy(&eventMask, &self->Port.FlowControl, sizeof(unsigned int));
            if (eventMask & (changedBits << 16)) {
                _RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
                                   ((oldState & 0xFFE9) | (flowState & 0x16)) | (changedBits << 16));
            }
        }
    } else {
        // All other events - call _executeEvent
        changedBits = 0;
        newState = self->Port.State;

        _executeEvent(self->port, (unsigned char)event, data, &newState, &changedBits);
        result = 0;

        // Update state with changes
        oldState = self->Port.State;
        newState = (changedBits & newState) | (~changedBits & oldState);
        changedBits = oldState ^ newState;
        self->Port.State = newState;

        // Wake up threads
        if (self->Port.WatchStateMask & changedBits) {
            thread_wakeup_prim(&self->Port.WatchStateMask, 0, 4);
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
            outb(self->Port.Base + UART_MCR, mcrValue);
            // Atomic increment
        }

        // Trigger timer
        if ((self->Port.State & 0x10000000) == 0) {
            thread_call_enter(self->Port.FrameTOEntry);
        }

        // Enqueue state change event
        memcpy(&eventMask, &self->Port.FlowControl, sizeof(unsigned int));
        if (eventMask & (changedBits << 16)) {
            _RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
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
    return self->Port.State & ~0x1000;
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
 *   0xFFFFFD33 if port not acquired
 */
- (IOReturn)setState:(unsigned int)state
                mask:(unsigned int)mask
{
    unsigned int oldIRQL;
    Port *selfPtr;
    unsigned int effectiveMask;
    unsigned int newState, oldState, changedBits;
    unsigned char mcrValue;

    // Check for invalid high bits (bits in 0xc000100000000000 when viewed as 64-bit)
    // In 32-bit world, this checks the high dword passed on stack
    // For now, we'll just proceed with the low 32 bits

    oldIRQL = spl4();

    // Get self pointer from offset 600
    selfPtr = *(Port **)((char *)self + 600);

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
        return 0xFFFFFD33;  // Port not acquired
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
 *   0xFFFFFD33 if port not acquired
 *   0xFFFFFD36 if interrupted while waiting
 *   Other errors from _watchState
 */
- (IOReturn)watchState:(unsigned int *)state
                  mask:(unsigned int)mask
{
    unsigned int oldIRQL;
    Port *selfPtr;
    IOReturn result;

    oldIRQL = spl4();

    // Get self pointer from offset 600
    selfPtr = *(Port **)((char *)self + 600);

    // Check if port is acquired (offset 0xc from selfPtr = currentState, check high bit)
    if (*(int *)((char *)selfPtr + 0xc) < 0) {
        // Call _watchState with masked value (mask off bit 0x1000)
        result = watchState(selfPtr, state, mask & 0xFFFFEFFF);

        // Mask the returned state value (clear bit 0x1000)
        *state = *state & 0xFFFFEFFF;

        splx(oldIRQL);
    } else {
        splx(oldIRQL);
        result = 0xFFFFFD33;  // Port not acquired
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
    configTable = [[self deviceDescription] configTable];
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
    if ((self->Port.Type > 4)) {
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
