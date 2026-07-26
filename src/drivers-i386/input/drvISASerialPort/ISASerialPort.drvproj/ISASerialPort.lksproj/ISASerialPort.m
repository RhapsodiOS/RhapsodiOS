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
#import "ISASerialPortQueue.h"
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
static IOReturn activatePort(Port *port);
static IOReturn deactivatePort(Port *port);
// The four callout handlers take the Port * thread_call_allocate was given as
// its spec, and nothing else; each is cast to thread_call_func_t at its
// allocation site.
static void heartBeatTOHandler(Port *port);
static void frameTOHandler(Port *port);
static void delayTOHandler(Port *port);
static void dataLatTOHandler(Port *port);
static IOReturn executeEvent(Port *port, unsigned int eventType, unsigned int eventData,
                             unsigned int *statePtr, unsigned int *maskPtr);
static void NonFIFOIntHandler(void *identity, void *state, Port *port);
static void FIFOIntHandler(void *identity, void *state, Port *port);

/*
 * The chip table, nine rows of 20 bytes at the head of __DATA,__data.  It is
 * here rather than in the chip translation unit because IntHandler names the
 * two static interrupt handlers declared just above; the parts that only read
 * MaxBaud and FIFOsize reach it through ISASerialPortInternal.h.
 *
 * MaxBaud is half-bits per second.  Rows 2, 3 and 4 all report themselves as
 * "16450" to the "Chip Type" key even though they are three different parts,
 * and rows 5 and 6 likewise share "16550".
 */
ChipInfo Chip[9] = {
/*    MaxBaud  FIFO  IntHandler         ShortName  LongName */
    {       0,   0,  NonFIFOIntHandler, "Auto",    "Unknown"                   },
    {   38400,   0,  NonFIFOIntHandler, "8250",    "8250"                      },
    {   76800,   0,  NonFIFOIntHandler, "16450",   "8250A or 16450"            },
    {   76800,   0,  NonFIFOIntHandler, "16450",   "16C1450"                   },
    {   76800,   0,  NonFIFOIntHandler, "16450",   "16550 with defective FIFO" },
    {  230400,  16,  FIFOIntHandler,    "16550",   "16550AF/C/CF"              },
    {  230400,  16,  FIFOIntHandler,    "16550",   "16C1550"                   },
    {  921600,  32,  FIFOIntHandler,    "16650",   "ST16C650"                  },
    {  230400,   4,  NonFIFOIntHandler, "82510",   "82510"                     }
};

/*
 * MSR high nibble -> the modem bits of State.  Bits 1 and 3 swap and bits 0
 * and 2 are left alone, which turns the hardware order (CTS, DSR, RI, DCD)
 * into the driver's (CTS, DCD, RI, DSR).  Read as
 * State = (State & ~0x1E0) | (msr_state_lut[MSR >> 4] << 5).
 */
unsigned char msr_state_lut[16] = {
    0x00, 0x01, 0x08, 0x09, 0x04, 0x05, 0x0C, 0x0D,
    0x02, 0x03, 0x0A, 0x0B, 0x06, 0x07, 0x0E, 0x0F
};

/*
 * Frame timeout handler.
 * Timer callback that triggers interrupt handler when frame timeout occurs.
 * Used for detecting end of transmission or processing delayed events.
 */
static void frameTOHandler(Port *port)
{
    unsigned int oldIRQL;

    // Raise interrupt level
    oldIRQL = spl4();

    // Clear timer pending flag
    port->WaitingForTXIdle = 0;

    // The handler comes out of the chip table, not out of a FIFO test.
    Chip[port->Type].IntHandler(0, 0, port);

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Delay timeout handler.
 * Timer callback for delayed operations. Clears the delay bit from state
 * and triggers the appropriate interrupt handler.
 */
static void delayTOHandler(Port *port)
{
    unsigned int oldIRQL;

    // Raise interrupt level
    oldIRQL = spl4();

    // Clear delay state bit (0x1000) from currentState
    port->State &= ~0x1000;

    // The handler comes out of the chip table, not out of a FIFO test.
    Chip[port->Type].IntHandler(0, 0, port);

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Data latency timeout handler.
 * Handles RX queue overflow conditions and adjusts flow control based on queue levels.
 * This is called when the RX queue reaches critical levels and needs to signal overflow
 * or adjust flow control to prevent data loss.
 */
static void dataLatTOHandler(Port *port)
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
            RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                                (newState & 0xFFFF) | (changedBits << 16));
        }
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Handle PCMCIA card removal.
 * Called when the PCMCIA card is hot-removed from the system.
 */
static void PCMCIA_yanked(Port *port)
{
    // Set flag indicating card was removed
    port->PCMCIA_yanked = 1;

    // Deactivate the port to prevent further access
    deactivatePort(port);
}

/*
 * Activate the serial port.
 * Allocates ring buffers, programs the UART, enables interrupts, and sets up initial state.
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD42 on failure (unable to allocate buffers)
 */
static IOReturn activatePort(Port *port)
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
        return 0xFFFFFD42; // -702, IO_R_RESOURCE
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

    // If the part has a usable FIFO, reset it.  Type > 4 is exactly
    // Chip[Type].FIFOsize != 0.
    if (port->Type > 4) {
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
        RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
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
        RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
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
            // Below medium watermark
            port->TX.Enqueue = port->TX.LowWater;
            txState = TX_STATE_BELOW_MED;
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
        RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
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
static IOReturn deactivatePort(Port *port)
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
    // Read Port.FlowControl, offset 0xe0 from the Port
    memcpy(&eventMask, &port->FlowControl, sizeof(unsigned int));
    if (eventMask & (changedBits << 16)) {
        RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
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
        RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
                            (newState & 0xFFFF) | (changedBits << 16));
    }

    return IO_R_SUCCESS;
}

/*
 * Heartbeat timeout handler.
 * Timer callback that polls the UART by calling the interrupt handler.
 * Used for chips without reliable interrupts or for periodic monitoring.
 */
static void heartBeatTOHandler(Port *port)
{
    unsigned int oldIRQL;

    // Raise interrupt level
    oldIRQL = spl4();

    // The port must be acquired - State's sign bit - and the card still there.
    if ((int)port->State < 0 && port->PCMCIA_yanked == 0) {
        // Poll the chip unless a real interrupt has just done it for us.
        if (port->JustDoneInterrupt == 0) {
            Chip[port->Type].IntHandler(0, 0, port);
        }

        // Clear pending flag
        port->JustDoneInterrupt = 0;

        // Rearm.  HeartBeatInterval is already a tvalspec, so this needs no
        // nanosecond arithmetic and no 64-bit division.
        thread_call_enter_delayed(port->HeartBeatTOEntry,
                                  deadline_from_interval(port->HeartBeatInterval));
    }

    // Restore interrupt level
    splx(oldIRQL);
}

/*
 * Non-FIFO interrupt handler.
 * Handles all UART interrupts for 8250/16450 chips without FIFO.
 * This is called at interrupt level and must be fast.
 */
static void NonFIFOIntHandler(void *identity, void *state, Port *port)
{
    unsigned int matchBits;
    unsigned char lsr, msr;
    unsigned char dataByte;
    unsigned char eventType;
    unsigned int eventData;
    unsigned int newState, changedBits;
    unsigned char mcrValue;
    BOOL continueLoop;
    unsigned char timerNeeded;
    unsigned short dataWord;
    unsigned short *readPtr;

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
        if ((lsr & 0x02) && (newState & STATE_RX_GATE)) {
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
                PCMCIA_yanked(port);
                return;
            }

            // Process received data if RX enabled
            if (newState & STATE_RX_GATE) {
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

                    // Enqueue parity error with data.  The byte OR'd in is the
                    // post-RBRmask eventData, not the raw RBR read: reference
                    // 16521 loads byte ptr [ebp+var_8], the same slot 16567
                    // masks on the RX_Parity == 6 path.
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_PARITY_ERROR | (eventData << 8);
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
                    if ((port->FlowControl & 0x80008) != 0) {
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
                        *writePtr++ = (unsigned short)eventType | (eventData << 8);
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
                        *writePtr++ = EVENT_FRAMING_ERROR | (eventData << 8);
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
            // The preserved low bits come from port->State, not from the local
            // copy: reference 16906 masks the local with 0xFFF0FFE9 first and
            // only then reads the struct field at 16913.  The XON/XOFF handling
            // above may already have moved bit 3 of the local.
            unsigned int rxState = port->State & 0x17E;

            if (port->RX.Count < port->RX.LowWater) {
                port->RX.Dequeue = 0;
                if (port->RX.Count == 0) {
                    rxState |= RX_STATE_EMPTY;
                    port->RX.Enqueue = 0;
                } else {
                    rxState |= RX_STATE_BELOW_LOW;
                    port->RX.Enqueue = port->RX.LowWater;
                }

                // Turn ON flow control signals (queue draining).  Reference
                // 16971/16988/17052: an exclusive chain, not three independent
                // tests - with FlowControl == 0x14 only bit 2 is set and the
                // RXOstate machine is not reached.
                if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                    rxState |= STATE_RTS;
                } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                    rxState |= 0x10;
                    if (port->RXOstate == -1) {
                        port->RXOstate = 2;
                    } else if (port->RXOstate == 1) {
                        port->RXOstate = -2;
                    }
                } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
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

                // Turn OFF flow control signals (queue filling).  Reference
                // 17131/17144/17212, the same exclusive chain.
                if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                    rxState &= ~STATE_RTS;
                } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                    rxState &= ~0x10;
                    if (port->RXOstate == -2 || port->RXOstate == 0) {
                        port->RXOstate = 1;
                    } else if (port->RXOstate == 2) {
                        port->RXOstate = -1;
                    }
                } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
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
            if (newState & STATE_DTR) mcrValue |= MCR_DTR;
            if (newState & STATE_RTS) mcrValue |= MCR_RTS;
            OUTB(port->Base + UART_MCR, mcrValue);
        }

        // Handle Modem Status Register changes
        msr = INB(port->Base + UART_MSR);
        if (msr & 0x0F) {  // Any delta bits set
            port->Stats.mdmInts++;
            // Update modem signal state bits (5-8) using lookup table
            newState = (newState & 0xFFFFFE1F) | (msr_state_lut[msr >> 4] << 5);
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
                                unsigned int preventMask;
                                preventMask = (port->FlowControl & 0x168) | 0x20000000;
                                if ((preventMask & ~newState) == 0) {
                                    unsigned char wordLen;
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

                                executeEvent(port, eventType, eventData, &newState, &changedBits);
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

                port->RXOstate = -port->RXOstate;
            }
        }

        // Re-read LSR for next iteration
        lsr = INB(port->Base + UART_LSR);

        // Continue if an event was executed, else consult IIR.  The IIR read
        // must be short-circuited: reference 18179 tests the executed-event
        // flag first and only falls through to the IIR read at 18189 when it is
        // clear.  Reading IIR clears a pending THRE interrupt, so an
        // unconditional read here silently drops a transmit interrupt.
    } while (continueLoop || ((INB(port->Base + UART_IIR) & 0x01) == 0));

    // Check for break condition change
    if ((lsr & 0x60) == 0x20) {
        timerNeeded = 1;
    }

    // Schedule timer if needed
    if ((timerNeeded != 0) && (port->WaitingForTXIdle == 0)) {
        port->WaitingForTXIdle = 1;
        thread_call_enter_delayed(port->FrameTOEntry,
                                  deadline_from_interval(port->FrameInterval));
    }

    // Update TX watermark state
    if (port->TX.Count <= port->TX.Dequeue) {
        unsigned int txState;

        // Reference 18294-18416.  Count <= LowWater takes the empty/below-med
        // arm; HighWater < Count takes the above-high arm and reports CRITICAL
        // once Count passes Size - 3.  Both branch senses and both level
        // constants were previously one rung out.
        if (port->TX.Count <= port->TX.LowWater) {
            port->TX.Dequeue = 0;
            if (port->TX.Count == 0) {
                port->TX.Enqueue = 0;
                txState = TX_STATE_EMPTY;
            } else {
                port->TX.Enqueue = port->TX.LowWater;
                txState = TX_STATE_BELOW_MED;
            }
        } else if (port->TX.HighWater < port->TX.Count) {
            port->TX.Enqueue = port->TX.Size - 3;
            if (port->TX.Count > (port->TX.Size - 3)) {
                port->TX.Dequeue = port->TX.Size;
                txState = TX_STATE_CRITICAL;
            } else {
                port->TX.Dequeue = port->TX.HighWater;
                txState = TX_STATE_ABOVE_HIGH;
            }
        } else {
            port->TX.Enqueue = port->TX.HighWater;
            port->TX.Dequeue = port->TX.LowWater;
            txState = TX_STATE_BELOW_HIGH;
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

    /*
     * Enqueue the state-change event if the mask matches.  The reference writes
     * the three cells INLINE here rather than calling RX_enqueueLongEvent:
     * fourteen sites in its class translation unit write this event, twelve of
     * them call the out-of-line helper at 0, and the two that do not are
     * _NonFIFOIntHandler at 18486-18664 and _FIFOIntHandler at 16014-16192,
     * both of which spell out the capacity check and the 0x6C overflow path in
     * full.  matchBits carries no low-half bits, so the reference simply ORs the
     * two halves together at 18492 / 16020 with no extra masking.
     */
    matchBits = (changedBits << 16) & port->FlowControl;
    if (matchBits != 0) {
        unsigned int eventValue = (newState & 0xFFFF) | matchBits;
        unsigned short *writePtr;

        if ((port->RX.Size - port->RX.Count) > 2) {
            writePtr = (unsigned short *)port->RX.Input;

            *writePtr++ = EVENT_STATE_CHANGE;
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;

            *writePtr++ = (unsigned short)eventValue;
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;

            *writePtr++ = (unsigned short)(eventValue >> 16);
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;
        } else if (port->RX.Count < port->RX.Size) {
            writePtr = (unsigned short *)port->RX.Input;
            *writePtr++ = EVENT_OVERFLOW;
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;
        } else {
            port->RX.OverRun = 1;
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
static void FIFOIntHandler(void *identity, void *state, Port *port)
{
    unsigned int matchBits;
    unsigned char lsr, msr;
    unsigned char dataByte;
    unsigned char eventType;
    unsigned int eventData;
    unsigned int newState, changedBits;
    unsigned char mcrValue;
    BOOL continueLoop, firstRXInt, firstTHRInt;
    unsigned char timerNeeded;
    unsigned short dataWord;
    unsigned short *readPtr;
    int fifoRemaining;
    int overrunCounter;

    // Check if FIFO is actually enabled
    if ((port->FCRimage & FCR_FIFO_ENABLE) == 0) {
        // FIFO not enabled - use non-FIFO handler
        NonFIFOIntHandler(identity, state, port);
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
                PCMCIA_yanked(port);
                return;
            }

            // Process received data if RX enabled
            if (newState & STATE_RX_GATE) {
                unsigned char errorBits;
                // Update statistics on first RX interrupt
                if (firstRXInt && (lsr & 0x01)) {
                    firstRXInt = FALSE;
                    port->Stats.rxInts++;
                }

                port->Stats.rxChars++;

                // Check for overrun error and update counter
                if ((lsr & 0x02) && (overrunCounter == 0)) {
                    overrunCounter = Chip[port->Type].FIFOsize;
                }

                errorBits = lsr & 0x1C;  // Parity, Framing, Break errors

                if (errorBits == 0x04) {
                    // Parity error - check for software flow control character
                    if (port->RX_Parity == 6) {  // Software flow control mode
                        // Mask data with RX FIFO mask
                        eventData = dataByte & port->RBRmask;
                        goto process_flow_control_char_fifo;
                    }

                    // Enqueue parity error with data.  The byte OR'd in is the
                    // post-RBRmask eventData, not the raw RBR read: reference
                    // 13361 loads byte ptr [ebp+var_8], the same slot 13407
                    // masks on the RX_Parity == 6 path.
                    //
                    // All four full-queue arms share one site in the reference,
                    // 13684, which sets RX.OverRun and then jumps straight back
                    // to the drain-loop top at 13691 - so the overrun countdown
                    // below does NOT run when the queue is full.
                    if (port->RX.Count >= port->RX.Size) {
                        port->RX.OverRun = 1;
                        continue;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_PARITY_ERROR | (eventData << 8);
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
                    if ((port->FlowControl & 0x80008) != 0) {
                        // Software flow control enabled
                        if (eventData == port->XONchar) {
                            newState |= 0x08;
                            changedBits |= 0x08;
                            goto data_processed_fifo;
                        } else if (eventData == port->XOFFchar) {
                            newState &= ~0x08;
                            changedBits |= 0x08;
                            goto data_processed_fifo;
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
                        continue;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = (unsigned short)eventType | (eventData << 8);
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
                        continue;
                    } else {
                        unsigned short *writePtr = (unsigned short *)port->RX.Input;
                        *writePtr++ = EVENT_FRAMING_ERROR | (eventData << 8);
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
                        continue;
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

                // Check for end of overrun sequence.  An XON/XOFF match above
                // lands here too: reference 13442 and 13480 jump to 13728, not
                // past it.
data_processed_fifo:
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
            // The preserved low bits come from port->State, not from the local
            // copy: reference 13830 masks the local with 0xFFF0FFE9 first and
            // only then reads the struct field at 13837.
            unsigned int rxState = port->State & 0x17E;

            if (port->RX.Count < port->RX.LowWater) {
                port->RX.Dequeue = 0;
                if (port->RX.Count == 0) {
                    rxState |= RX_STATE_EMPTY;
                    port->RX.Enqueue = 0;
                } else {
                    rxState |= RX_STATE_BELOW_LOW;
                    port->RX.Enqueue = port->RX.LowWater;
                }

                // Reference 13895/13912/13976: an exclusive chain, not three
                // independent tests.
                if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                    rxState |= STATE_RTS;
                } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                    rxState |= 0x10;
                    if (port->RXOstate == -1) {
                        port->RXOstate = 2;
                    } else if (port->RXOstate == 1) {
                        port->RXOstate = -2;
                    }
                } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
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

                // Reference 14055/14068/14136, the same exclusive chain.
                if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                    rxState &= ~STATE_RTS;
                } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                    rxState &= ~0x10;
                    if (port->RXOstate == -2 || port->RXOstate == 0) {
                        port->RXOstate = 1;
                    } else if (port->RXOstate == 2) {
                        port->RXOstate = -1;
                    }
                } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                    rxState &= ~STATE_DTR;
                }
            } else {
                port->RX.Enqueue = port->RX.HighWater;
                port->RX.Dequeue = port->RX.LowWater;
            }

            newState = (newState & 0xFFF0FFE9) | rxState;
            changedBits |= ((newState ^ port->State) & 0xF0016);

            mcrValue = MCR_OUT2;
            if (newState & STATE_DTR) mcrValue |= MCR_DTR;
            if (newState & STATE_RTS) mcrValue |= MCR_RTS;
            OUTB(port->Base + UART_MCR, mcrValue);
        }

        // Handle Modem Status Register changes
        msr = INB(port->Base + UART_MSR);
        newState = (newState & 0xFFFFFE1F) | (msr_state_lut[msr >> 4] << 5);
        changedBits |= ((newState ^ port->State) & 0x1E0);

        /*
         * Handle the transmitter.  Reference 14277-14287: entered when THRE is
         * set OR the burst counter is still non-zero, because once the FIFO's
         * depth is known the handler keeps stuffing without re-reading THRE.
         *
         * fifoRemaining is the reference's edi.  Every arm that cannot transmit
         * zeroes it (15328) and every arm that can leaves it holding the number
         * of FIFO slots still free, which is what the loop-bottom test at 15708
         * re-enters the whole handler on.
         */
        if ((lsr & 0x20) || (fifoRemaining != 0)) {
            if (firstTHRInt) {
                firstTHRInt = FALSE;
                port->Stats.txInts++;
            }

            // Check hardware flow control state
            if ((port->FlowControl & FLOW_HW_ENABLED) && (port->RXOstate > 0)) {
                // Hardware flow control active - send XON/XOFF
                if (port->RXOstate == 2) {
                    port->Stats.txChars++;
                    OUTB(port->Base + UART_THR, port->XONchar);
                } else {
                    port->Stats.txChars++;
                    OUTB(port->Base + UART_THR, port->XOFFchar);
                }

                port->RXOstate = -port->RXOstate;

                if (fifoRemaining != 0) {
                    fifoRemaining--;
                }
            } else if (newState & 0x1000) {
                // Transmission suspended by event 0x4B
                fifoRemaining = 0;
            } else {
                char peekChar;
                // Peek at next TX queue entry
                char *peekPtr = (char *)port->TX.Output;
                if ((char *)peekPtr >= port->TX.End) {
                    peekPtr = (char *)port->TX.Base;
                }
                peekChar = (port->TX.Count != 0) ? *peekPtr : '\0';

                if (peekChar == 0) {
                    fifoRemaining = 0;
                } else if (peekChar != 'U') {
                    // Head is a non-data event.  Reference 15336-15344: the
                    // burst counter is cleared unconditionally, and the timer is
                    // armed only when the transmitter is not yet idle.
                    fifoRemaining = 0;
                    if ((lsr & 0x40) == 0) {
                        timerNeeded = 1;
                    } else {
                        unsigned char wordLen;
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

                        executeEvent(port, eventType, eventData, &newState, &changedBits);
                        continueLoop = TRUE;
                    }
                } else {
                    // Head is a data byte.  Check for conditions that prevent
                    // transmission.
                    unsigned int preventMask;
                    preventMask = (port->FlowControl & 0x168) | 0x20000000;

                    if ((preventMask & ~newState) != 0) {
                        fifoRemaining = 0;
                    } else {
                        if ((lsr & 0x40) != 0) {
                            // TEMT set - the FIFO is empty, so its whole depth
                            // is available (reference 14510).
                            fifoRemaining = Chip[port->Type].FIFOsize;
                            timerNeeded = 0;
                            if (port->WaitingForTXIdle != 0) {
                                thread_call_cancel(port->FrameTOEntry);
                                port->WaitingForTXIdle = 0;
                            }
                        } else if (lsr & 0x20) {
                            // TEMT clear but THRE set: only start a burst when
                            // the cell after the head is data too (reference
                            // 14572-14622).  Without the THRE test this arm can
                            // be reached on a re-entry carrying a live burst
                            // counter and would write THR with no room.
                            char peek2Char;
                            char *peek2Ptr = (char *)((unsigned short *)port->TX.Output + 1);
                            if ((char *)peek2Ptr >= port->TX.End) {
                                peek2Ptr = (char *)port->TX.Base;
                            }
                            peek2Char = (port->TX.Count > 1) ? *peek2Ptr : '\0';

                            if (peek2Char == 'U') {
                                unsigned char wordLen;
                                fifoRemaining = Chip[port->Type].FIFOsize - 1;
                                timerNeeded = 0;
                                if (port->WaitingForTXIdle != 0) {
                                    thread_call_cancel(port->FrameTOEntry);
                                    port->WaitingForTXIdle = 0;
                                }

                                // Dequeue and transmit the head
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
                            }
                        }

                        // Reference 14967: the four sub-paths above converge
                        // here, and an empty burst budget is what arms the frame
                        // timer.
                        if (fifoRemaining == 0) {
                            timerNeeded = 1;
                        } else {
                            for (;;) {
                                unsigned char wordLen;

                                peekPtr = (char *)port->TX.Output;
                                if ((char *)peekPtr >= port->TX.End) {
                                    peekPtr = (char *)port->TX.Base;
                                }
                                peekChar = (port->TX.Count != 0) ? *peekPtr : '\0';

                                // Reference 15020 leaves the burst counter
                                // non-zero on this break, which is what makes
                                // the loop-bottom test re-enter the handler.
                                if (peekChar != 'U') {
                                    break;
                                }

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

                                if (--fifoRemaining == 0) {
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Continue while work remains, else consult IIR.  The IIR read must be
        // short-circuited: reference 15692/15702/15710 test the three flags
        // first and only fall through to the read at 15716 when all are clear.
        // Reading IIR clears a pending THRE interrupt.
    } while (continueLoop || (overrunCounter != 0) || (fifoRemaining != 0) ||
             ((INB(port->Base + UART_IIR) & 0x01) == 0));

    // Check for break condition change
    if ((lsr & 0x60) == 0x20) {
        timerNeeded = 1;
    }

    // Schedule timer if needed
    if ((timerNeeded != 0) && (port->WaitingForTXIdle == 0)) {
        port->WaitingForTXIdle = 1;
        thread_call_enter_delayed(port->FrameTOEntry,
                                  deadline_from_interval(port->FrameInterval));
    }

    // Update TX watermark state
    if (port->TX.Count <= port->TX.Dequeue) {
        unsigned int txState;

        // Reference 18294-18416.  Count <= LowWater takes the empty/below-med
        // arm; HighWater < Count takes the above-high arm and reports CRITICAL
        // once Count passes Size - 3.  Both branch senses and both level
        // constants were previously one rung out.
        if (port->TX.Count <= port->TX.LowWater) {
            port->TX.Dequeue = 0;
            if (port->TX.Count == 0) {
                port->TX.Enqueue = 0;
                txState = TX_STATE_EMPTY;
            } else {
                port->TX.Enqueue = port->TX.LowWater;
                txState = TX_STATE_BELOW_MED;
            }
        } else if (port->TX.HighWater < port->TX.Count) {
            port->TX.Enqueue = port->TX.Size - 3;
            if (port->TX.Count > (port->TX.Size - 3)) {
                port->TX.Dequeue = port->TX.Size;
                txState = TX_STATE_CRITICAL;
            } else {
                port->TX.Dequeue = port->TX.HighWater;
                txState = TX_STATE_ABOVE_HIGH;
            }
        } else {
            port->TX.Enqueue = port->TX.HighWater;
            port->TX.Dequeue = port->TX.LowWater;
            txState = TX_STATE_BELOW_HIGH;
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

    /*
     * Enqueue the state-change event if the mask matches.  The reference writes
     * the three cells INLINE here rather than calling RX_enqueueLongEvent:
     * fourteen sites in its class translation unit write this event, twelve of
     * them call the out-of-line helper at 0, and the two that do not are
     * _NonFIFOIntHandler at 18486-18664 and _FIFOIntHandler at 16014-16192,
     * both of which spell out the capacity check and the 0x6C overflow path in
     * full.  matchBits carries no low-half bits, so the reference simply ORs the
     * two halves together at 18492 / 16020 with no extra masking.
     */
    matchBits = (changedBits << 16) & port->FlowControl;
    if (matchBits != 0) {
        unsigned int eventValue = (newState & 0xFFFF) | matchBits;
        unsigned short *writePtr;

        if ((port->RX.Size - port->RX.Count) > 2) {
            writePtr = (unsigned short *)port->RX.Input;

            *writePtr++ = EVENT_STATE_CHANGE;
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;

            *writePtr++ = (unsigned short)eventValue;
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;

            *writePtr++ = (unsigned short)(eventValue >> 16);
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;
        } else if (port->RX.Count < port->RX.Size) {
            writePtr = (unsigned short *)port->RX.Input;
            *writePtr++ = EVENT_OVERFLOW;
            if ((char *)writePtr >= port->RX.End) {
                writePtr = (unsigned short *)port->RX.Base;
            }
            port->RX.Input = (char *)writePtr;
            port->RX.Count++;
        } else {
            port->RX.OverRun = 1;
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
 * Recompute the RX half of the reported state from the RX queue's occupancy.
 *
 * Three call sites inline this in the reference (events 0x17, 0x1F and 0x2F),
 * and each one clears the RX level and flow bits out of *statePtr, rebuilds
 * them from Port.State's low bits, and reports 0xF0016 as touched.  The
 * watermarks Enqueue and Dequeue are the next levels at which a state change
 * must be raised, which is why every arm rewrites both.
 */
static inline void RX_updateState(Port *port, unsigned int *statePtr,
                                  unsigned int *maskPtr)
{
    unsigned int rxState;

    *statePtr &= 0xFFF0FFE9;
    rxState = port->State & 0x17E;

    if (port->RX.Count < port->RX.LowWater) {
        port->RX.Dequeue = 0;

        if (port->RX.Count == 0) {
            rxState |= RX_STATE_EMPTY;
            port->RX.Enqueue = 0;
        } else {
            rxState |= RX_STATE_BELOW_LOW;
            port->RX.Enqueue = port->RX.LowWater;
        }

        // Room again: assert whichever signal this port throttles with.
        if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
            rxState |= STATE_RTS;
        } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
            rxState |= 0x10;
            if (port->RXOstate == -1) {
                port->RXOstate = 2;
            } else if (port->RXOstate == 1) {
                port->RXOstate = -2;
            }
        } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
            rxState |= STATE_DTR;
        }

    } else if (port->RX.HighWater < port->RX.Count) {
        port->RX.Enqueue = port->RX.Size - 3;

        if (port->RX.Count > port->RX.Size - 3) {
            rxState |= RX_STATE_CRITICAL;
            port->RX.Dequeue = port->RX.Size;
        } else {
            rxState |= RX_STATE_ABOVE_HIGH;
            port->RX.Dequeue = port->RX.HighWater;
        }

        // Filling up: drop the same signal to apply back pressure.
        if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
            rxState &= ~STATE_RTS;
        } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
            rxState &= ~0x10;
            if (port->RXOstate == -2 || port->RXOstate == 0) {
                port->RXOstate = 1;
            } else if (port->RXOstate == 2) {
                port->RXOstate = -1;
            }
        } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
            rxState &= ~STATE_DTR;
        }

    } else {
        port->RX.Enqueue = port->RX.HighWater;
        port->RX.Dequeue = port->RX.LowWater;
    }

    *statePtr |= rxState;
    *maskPtr |= 0xF0016;
}

/*
 * Recompute the TX half of the reported state.  Inlined at events 0x13, 0x1B
 * and 0x28.  Note the first comparison: the TX arm takes the empty/below-med
 * path when Count is less than OR EQUAL to LowWater, where the RX arm above
 * uses a strict less-than.  The reference's two tests really do differ.
 */
static inline void TX_updateState(Port *port, unsigned int *statePtr,
                                  unsigned int *maskPtr)
{
    unsigned int txState;

    *statePtr &= 0xF87FFFFF;

    if (port->TX.Count <= port->TX.LowWater) {
        port->TX.Dequeue = 0;

        if (port->TX.Count == 0) {
            port->TX.Enqueue = 0;
            txState = TX_STATE_EMPTY;
        } else {
            port->TX.Enqueue = port->TX.LowWater;
            txState = TX_STATE_BELOW_MED;
        }

    } else if (port->TX.HighWater < port->TX.Count) {
        port->TX.Enqueue = port->TX.Size - 3;

        if (port->TX.Count > port->TX.Size - 3) {
            port->TX.Dequeue = port->TX.Size;
            txState = TX_STATE_CRITICAL;
        } else {
            port->TX.Dequeue = port->TX.HighWater;
            txState = TX_STATE_ABOVE_HIGH;
        }

    } else {
        port->TX.Enqueue = port->TX.HighWater;
        port->TX.Dequeue = port->TX.LowWater;
        txState = TX_STATE_BELOW_HIGH;
    }

    *statePtr |= txState;
    *maskPtr |= TX_STATE_MASK;
}

/*
 * executeEvent - Execute an event command on the serial port
 *
 * The event machine behind -executeEvent:data:.  It does NOT compute a final
 * state itself: *statePtr arrives holding Port.State and *maskPtr holding
 * zero, each case edits the bits it owns in *statePtr and records them in
 * *maskPtr, and the caller merges the two.  Anything this function does not
 * touch therefore keeps its current value.
 *
 * Every arm that changes a line parameter calls programChip unconditionally;
 * none of them recomputes DLRimage or LCRimage, because programChip derives
 * both from the fields set here.
 *
 * Parameters:
 *   port - Pointer to the port's state block
 *   eventType - Event type identifier (determines action to take)
 *   eventData - Event-specific data parameter
 *   statePtr - In/out: the state being assembled
 *   maskPtr - Out: which bits of *statePtr this call is reporting
 *
 * Returns IO_R_SUCCESS, IO_R_NOT_OPEN when the port is not acquired, or
 * 0xFFFFFD3E (IO_R_INVALID_ARG) for an unknown event or an out-of-range value.
 */
static IOReturn executeEvent(Port *port, unsigned int eventType,
                             unsigned int eventData, unsigned int *statePtr,
                             unsigned int *maskPtr)
{
    IOReturn result;
    unsigned int tempValue;
    unsigned char mcrValue;
    unsigned long long intervalNS;
    tvalspec_t interval;

    result = IO_R_SUCCESS;

    // Every event needs the port acquired; State's sign bit is that flag.
    if ((int)port->State >= 0) {
        return 0xFFFFFD33;
    }

    switch (eventType) {
    case 0x05:  // Activate / deactivate the port
        if ((unsigned char)eventData != 0) {
            result = activatePort(port);
        } else {
            deactivatePort(port);
        }
        break;

    case 0x13:  // TX low watermark
        port->TX.LowWater = eventData;
        if (eventData > port->TX.HighWater - 3) {
            port->TX.LowWater = port->TX.HighWater - 3;
        }
        if (port->TX.LowWater <= 2) {
            port->TX.LowWater = 3;
        }
        TX_updateState(port, statePtr, maskPtr);
        break;

    case 0x17:  // RX low watermark
        port->RX.LowWater = eventData;
        if (eventData > port->RX.HighWater - 3) {
            port->RX.LowWater = port->RX.HighWater - 3;
        }
        if (port->RX.LowWater <= 2) {
            port->RX.LowWater = 3;
        }
        RX_updateState(port, statePtr, maskPtr);
        break;

    case 0x1B:  // TX high watermark.  The reference stores the requested value
                // into RX.HighWater here and then clamps TX.HighWater against
                // TX.Size, which is an original bug; it is reproduced rather
                // than corrected (see divergences.md).
        port->RX.HighWater = eventData;
        if (port->TX.HighWater > port->TX.Size - 3) {
            port->TX.HighWater = port->TX.Size - 3;
        }
        if (port->TX.HighWater <= 5) {
            port->TX.HighWater = 6;
        }
        if (port->TX.LowWater > port->TX.HighWater - 3) {
            port->TX.LowWater = port->TX.HighWater - 3;
        }
        TX_updateState(port, statePtr, maskPtr);
        break;

    case 0x1F:  // RX high watermark
        port->RX.HighWater = eventData;
        if (eventData > port->RX.Size - 3) {
            port->RX.HighWater = port->RX.Size - 3;
        }
        if (port->RX.HighWater <= 5) {
            port->RX.HighWater = 6;
        }
        if (port->RX.LowWater > port->RX.HighWater - 3) {
            port->RX.LowWater = port->RX.HighWater - 3;
        }
        RX_updateState(port, statePtr, maskPtr);
        break;

    case 0x28:  // Flush the TX queue
        port->TX.Output = port->TX.Base;
        port->TX.Input = port->TX.Base;
        port->TX.Count = 0;
        if (port->Type > 4) {
            outb(port->Base + UART_FCR, port->FCRimage | FCR_XMIT_RESET);
        }
        TX_updateState(port, statePtr, maskPtr);
        break;

    case 0x2F:  // Flush the RX queue
        port->RX.Output = port->RX.Base;
        port->RX.Input = port->RX.Base;
        port->RX.OverRun = 0;
        port->RX.Count = 0;
        if (port->Type > 4) {
            outb(port->Base + UART_FCR, port->FCRimage | FCR_RCVR_RESET);
        }
        RX_updateState(port, statePtr, maskPtr);
        break;

    case 0x33:  // Baud rate, in half-bits per second
        if (eventData <= 99 || Chip[port->Type].MaxBaud < eventData) {
            result = 0xFFFFFD3E;
            break;
        }
        port->BaudRate = eventData;
        programChip(port);
        break;

    case 0x37:  // Reserved: accepted only as a no-op
    case 0x3F:
    case 0xF7:
        if (eventData != 0) {
            result = 0xFFFFFD3E;
        }
        break;

    case 0x3B:  // Character length, half-bit units, 10..16 even
        if (eventData - 10 > 6 || (eventData & 1) != 0) {
            result = 0xFFFFFD3E;
            break;
        }
        port->CharLength = eventData;
        programChip(port);
        break;

    case 0x43:  // Parity, PARITY_NONE..PARITY_SPACE
        if (eventData == 0 || eventData > PARITY_SPACE) {
            result = 0xFFFFFD3E;
            break;
        }
        port->TX_Parity = eventData;
        port->RX_Parity = 0;
        programChip(port);
        break;

    case 0x47:  // RX parity checking: off, or 6 for "report errors"
        if (eventData != 0 && eventData != 6) {
            result = 0xFFFFFD3E;
            break;
        }
        port->RX_Parity = eventData;
        break;

    case 0x4B:  // Arm the delay timer, microseconds
        if (eventData != 0) {
            if (eventData > 0x418937) {
                eventData = 0x418937;
            }
            *statePtr |= 0x1000;
            intervalNS = (unsigned long long)(eventData * 1000);
            interval.tv_sec = intervalNS / 1000000000;
            interval.tv_nsec = intervalNS % 1000000000;
            thread_call_enter_delayed(port->DelayTOEntry,
                                      deadline_from_interval(interval));
        }
        break;

    case 0x4F:  // Data-latency interval, microseconds in, sec/nsec out
        intervalNS = (unsigned long long)(eventData * 1000);
        port->DataLatInterval.tv_sec = intervalNS / 1000000000;
        port->DataLatInterval.tv_nsec = intervalNS % 1000000000;
        break;

    case 0x53:  // Externally driven flow-signal change
        // Only the bits this port does not manage itself may be driven from
        // outside, hence the mask against ~FlowControl.
        tempValue = ((eventData >> 16) & 0x16) & ~port->FlowControl;
        *maskPtr |= tempValue;
        *statePtr &= ~tempValue;
        *statePtr |= tempValue & eventData;

        if ((tempValue & 0x10) != 0) {
            port->RXOstate = (eventData & 0x10) ? 2 : 1;
        }

        mcrValue = MCR_OUT2;
        if (*statePtr & STATE_DTR) {
            mcrValue |= MCR_DTR;
        }
        if (*statePtr & STATE_RTS) {
            mcrValue |= MCR_RTS;
        }
        outb(port->Base + UART_MCR, mcrValue);
        break;

    case 0x55:  // Unmark a character in the special-character bitmap
        port->SWspecial[eventData >> 5] &= ~(1 << (eventData & 0x1F));
        break;

    case 0x59:  // Mark a character in the special-character bitmap
        port->SWspecial[eventData >> 5] |= 1 << (eventData & 0x1F);
        break;

    case 0xE5:  // Minimum-latency mode: no FIFO trigger delay
        port->MinLatency = (eventData != 0);
        port->DLRimage = 0;
        programChip(port);
        break;

    case 0xE9:  // XOFF character
        port->XOFFchar = (unsigned char)eventData;
        break;

    case 0xED:  // XON character
        port->XONchar = (unsigned char)eventData;
        break;

    case 0xF3:  // Stop bits, half-bit units, 2..4
        if (eventData - 2 > 2) {
            result = 0xFFFFFD3E;
            break;
        }
        port->StopBits = eventData;
        programChip(port);
        break;

    case 0xF9:  // Break state, driven straight at the LCR
        *statePtr &= ~0x800;
        if ((unsigned char)eventData != 0) {
            port->LCRimage |= 0x40;
            tempValue = 0x800;
        } else {
            port->LCRimage &= ~0x40;
            tempValue = 0;
        }
        outb(port->Base + UART_LCR, port->LCRimage);
        *statePtr |= tempValue;
        *maskPtr |= 0x800;
        break;

    default:
        result = 0xFFFFFD3E;
        break;
    }

    return result;
}

/*
 * The 64-bit division helpers.  gcc lowers an ordinary `unsigned long long'
 * divide or modulo into a call to __udivdi3 or __umoddi3; on this system those
 * live in /usr/lib/libcc.a, which is a PowerPC archive and cannot be linked
 * for -arch i386, so the driver carries its own.  The reference does the same,
 * defining both locally at 23800 and 24064.
 *
 * The names carry one underscore, not two: a C function called __udivdi3
 * compiles to the symbol ___udivdi3, which is not the symbol a lowered divide
 * relocates against, so such a definition is never called.  _udivdi3 emits
 * __udivdi3, which is.
 *
 * Neither body may use 64-bit division, because gcc would lower that straight
 * back into a call to the function being defined.  What follows is libgcc2.c's
 * __udivmoddi4 with longlong.h's i386 macros, which is what the reference's two
 * bodies are: no call instructions, five `divl', one `mull', one `bsrl'.
 */
#define udiv_qrnnd(q, r, n1, n0, d)                                     \
    asm ("divl %4"                                                      \
         : "=a" (q), "=d" (r)                                           \
         : "0" (n0), "1" (n1), "rm" (d))

#define umul_ppmm(w1, w0, u, v)                                         \
    asm ("mull %3"                                                      \
         : "=a" (w0), "=d" (w1)                                         \
         : "%0" (u), "rm" (v))

#define sub_ddmmss(sh, sl, ah, al, bh, bl)                              \
    asm ("subl %5,%1\n\tsbbl %3,%0"                                     \
         : "=r" (sh), "=&r" (sl)                                        \
         : "0" (ah), "g" (bh), "1" (al), "g" (bl))

#define count_leading_zeros(count, x)                                   \
    do {                                                                \
        unsigned int __cbtmp;                                           \
        asm ("bsrl %1,%0" : "=r" (__cbtmp) : "rm" (x));                 \
        (count) = __cbtmp ^ 31;                                         \
    } while (0)

typedef union {
    struct { unsigned int low, high; } s;
    unsigned long long ll;
} DIunion;

static inline unsigned long long
udivmoddi4(unsigned long long n, unsigned long long d, unsigned long long *rp)
{
    DIunion ww, nn, dd, rr;
    unsigned int d0, d1, n0, n1, n2;
    unsigned int q0, q1;
    unsigned int b, bm;

    nn.ll = n;
    dd.ll = d;

    d0 = dd.s.low;
    d1 = dd.s.high;
    n0 = nn.s.low;
    n1 = nn.s.high;

    if (d1 == 0) {
        if (d0 > n1) {
            /* 0q = nn / 0D -- remainder in n0 */
            udiv_qrnnd(q0, n0, n1, n0, d0);
            q1 = 0;
        } else {
            /* qq = NN / 0d -- remainder in n0 */
            if (d0 == 0) {
                d0 = 1 / d0;    /* divide intentionally by zero */
            }
            udiv_qrnnd(q1, n1, 0, n1, d0);
            udiv_qrnnd(q0, n0, n1, n0, d0);
        }

        if (rp != 0) {
            rr.s.low = n0;
            rr.s.high = 0;
            *rp = rr.ll;
        }
    } else {
        if (d1 > n1) {
            /* 00 = nn / DD -- remainder in n1n0 */
            q0 = 0;
            q1 = 0;

            if (rp != 0) {
                rr.s.low = n0;
                rr.s.high = n1;
                *rp = rr.ll;
            }
        } else {
            /* 0q = NN / dd */
            count_leading_zeros(bm, d1);
            if (bm == 0) {
                /*
                 * n1 >= d1 and the top bit of d1 is set, so the top bit of n1
                 * is set too and the quotient digit is 0 or 1.  A necessary
                 * special case, not an optimisation: shift counts of 32 are
                 * undefined.
                 */
                if (n1 > d1 || n0 >= d0) {
                    q0 = 1;
                    sub_ddmmss(n1, n0, n1, n0, d1, d0);
                } else {
                    q0 = 0;
                }

                q1 = 0;

                if (rp != 0) {
                    rr.s.low = n0;
                    rr.s.high = n1;
                    *rp = rr.ll;
                }
            } else {
                unsigned int m1, m0;

                /* Normalise. */
                b = 32 - bm;

                d1 = (d1 << bm) | (d0 >> b);
                d0 = d0 << bm;
                n2 = n1 >> b;
                n1 = (n1 << bm) | (n0 >> b);
                n0 = n0 << bm;

                udiv_qrnnd(q0, n1, n2, n1, d1);
                umul_ppmm(m1, m0, q0, d0);

                if (m1 > n1 || (m1 == n1 && m0 > n0)) {
                    q0--;
                    sub_ddmmss(m1, m0, m1, m0, d1, d0);
                }

                q1 = 0;

                /* Remainder in (n1n0 - m1m0) >> bm. */
                if (rp != 0) {
                    sub_ddmmss(n1, n0, n1, n0, m1, m0);
                    rr.s.low = (n1 << b) | (n0 >> bm);
                    rr.s.high = n1 >> bm;
                    *rp = rr.ll;
                }
            }
        }
    }

    ww.s.low = q0;
    ww.s.high = q1;
    return ww.ll;
}

unsigned long long _udivdi3(unsigned long long n, unsigned long long d)
{
    return udivmoddi4(n, d, (unsigned long long *)0);
}

unsigned long long _umoddi3(unsigned long long u, unsigned long long v)
{
    unsigned long long w;

    (void)udivmoddi4(u, v, &w);

    return w;
}

@implementation ISASerialPort

/*
 * Probe for device presence.
 * Attempts to create an instance with the device description to verify device compatibility.
 *
 * The instance is deliberately NOT freed: initFromDeviceDescription: has already
 * called registerDevice, so the object probe built is the live driver and freeing
 * it would tear down the device that was just published (Finding 85).
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
    IOConfigTable *configTable;
    // numPortRanges, numChannels and portRangeList are IOEISADeviceDescription's,
    // not IODeviceDescription's.  Sending them to the declared parameter type
    // leaves the compiler assuming an id return, which is how the range check
    // below came to compare a pointer against an integer.
    IOEISADeviceDescription *eisaDescription;
    const char *instanceStr, *chipTypeStr, *busTypeStr;
    const char *txBufStr, *rxBufStr, *chipClockStr, *heartBeatStr;
    long instance;
    IORange *portRanges;
    unsigned int *irqList;
    unsigned int chipType;
    unsigned int masterClock;
    unsigned int heartBeatUS;
    unsigned long long heartBeatNS;
    unsigned int i;
    char portName[32];
    id result;

    // ivar 1 points at ivar 0, and ivar 0's first word points back at us.  The
    // raw offsets below are the reference's, which is why the class has to
    // subclass IODirectDevice: Port sits at 296 (0x128) and port at 600 (0x258)
    // only once IODirectDevice's 32 bytes are in front of them.
    self->port = &self->Port;
    self->Port.Self = self;

    // Initialize all fields at specific offsets to zero, in the reference's
    // order (300-819).  0x1cc is written twice, at 330 and again at 427; that
    // is the reference's own redundancy and is kept.
    *(unsigned int *)((char *)self + 300) = 0;      // 0x12c - Port.Instance
    *(void **)((char *)self + 0x130) = NULL;        // Port.PortName
    *(unsigned int *)((char *)self + 0x1b4) = 0;    // Port.IRQ
    *(unsigned int *)((char *)self + 0x1cc) = 0;
    *(unsigned int *)((char *)self + 0x1d0) = 0;
    *(unsigned int *)((char *)self + 0x1dc) = 0x1c2000;  // Port.MasterClock = 1843200
    *(unsigned short *)((char *)self + 0x1d4) = 0;
    *(unsigned char *)((char *)self + 0x1d6) = 0;
    *(unsigned char *)((char *)self + 0x1d7) = 0;
    *(unsigned char *)((char *)self + 0x1d8) = 0;
    *(unsigned char *)((char *)self + 0x1d9) = 0;
    *(unsigned int *)((char *)self + 0x1b8) = 0;    // Port.Type, the Chip[] row index
    *(unsigned int *)((char *)self + 0x1b0) = 0;    // Port.Base
    *(unsigned int *)((char *)self + 0x1bc) = 0;
    *(unsigned int *)((char *)self + 0x1cc) = 0;
    *(unsigned int *)((char *)self + 0x1c0) = 0;
    *(unsigned int *)((char *)self + 0x1c4) = 0;
    *(unsigned int *)((char *)self + 0x1c8) = 0;
    *(unsigned char *)((char *)self + 0x1e1) = 0;
    *(unsigned char *)((char *)self + 0x1e0) = 0;
    *(unsigned char *)((char *)self + 0x1e3) = 0;   // Port.PCMCIA
    *(unsigned char *)((char *)self + 0x1e4) = 0;
    *(unsigned char *)((char *)self + 0x1e5) = 0x11;  // xonChar
    *(unsigned char *)((char *)self + 0x1e6) = 0x13;  // xoffChar
    *(unsigned int *)((char *)self + 0x208) = 0;    // Port.FlowControl
    *(unsigned int *)((char *)self + 0x20c) = 0;
    *(void **)((char *)self + 0x210) = NULL;        // timer callout 1
    *(void **)((char *)self + 0x214) = NULL;        // timer callout 2
    *(void **)((char *)self + 0x220) = NULL;
    *(unsigned int *)((char *)self + 0x224) = 0;
    *(unsigned int *)((char *)self + 0x228) = 0;    // Port.DataLatInterval.tv_sec
    *(unsigned int *)((char *)self + 0x22c) = 0;    // Port.DataLatInterval.tv_nsec
    *(unsigned int *)((char *)self + 0x230) = 0;    // Port.CharLatInterval.tv_sec
    *(unsigned int *)((char *)self + 0x234) = 0;    // Port.CharLatInterval.tv_nsec
    *(unsigned int *)((char *)self + 0x238) = 0;    // Port.HeartBeatInterval.tv_sec
    *(unsigned int *)((char *)self + 0x23c) = 0;    // Port.HeartBeatInterval.tv_nsec
    *(unsigned int *)((char *)self + 0x134) = 0x60c0000;  // Port.State
    *(unsigned int *)((char *)self + 0x138) = 0;
    *(unsigned int *)((char *)self + 0x13c) = 0;
    *(unsigned int *)((char *)self + 0x208) = 0x126;   // Port.FlowControl
    *(unsigned int *)((char *)self + 0x1a4) = 0x4b0;   // Port.TX.DefaultSize = 1200
    *(unsigned int *)((char *)self + 0x194) = 0;
    *(unsigned int *)((char *)self + 0x198) = 0;
    *(unsigned int *)((char *)self + 0x19c) = 0;
    *(unsigned int *)((char *)self + 400) = 0;
    *(unsigned int *)((char *)self + 0x178) = 0;
    *(unsigned int *)((char *)self + 0x17c) = 0;
    *(unsigned int *)((char *)self + 0x16c) = 0x4b0;   // Port.RX.DefaultSize = 1200
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

    // Every key this driver reads comes out of the Instance table, reached
    // through the device description's config table.  Without one there is
    // nothing to configure from.
    configTable = [deviceDescription configTable];
    if (configTable == nil) {
        IOLog("ISASerialPort: Invalid Config Table\n");
        return [self free];
    }

    // "Instance" is the port number.  It feeds Port.Instance and names the
    // device, which is why the reference reads it before anything else and
    // does not guard against its absence.
    instanceStr = [configTable valueForStringKey:"Instance"];
    instance = strtol(instanceStr, NULL, 10);
    self->Port.Instance = instance;

    // Create port name like "ISASerialPort0"
    sprintf(portName, "ISASerialPort%d", (int)instance);
    [self setName:portName];
    [self setDeviceKind:"Serial"];
    self->Port.PortName = (char *)[self name];

    // The shape of the description itself: exactly one port range, exactly one
    // interrupt and no DMA channels.  All three are checked before any of them
    // is read, and they share one log string.
    eisaDescription = (IOEISADeviceDescription *)deviceDescription;
    if ([eisaDescription numPortRanges] != 1 ||
        [deviceDescription numInterrupts] != 1 ||
        [eisaDescription numChannels] != 0) {
        IOLog("%s: Invalid configuration\n", [self name]);
        return [self free];
    }

    portRanges = [eisaDescription portRangeList];
    self->Port.Base = portRanges[0].start;

    // Check that base port is aligned and size is 8
    if ((self->Port.Base & 3) != 0 || portRanges[0].size != 8) {
        IOLog("%s: Invalid Port configuration\n", [self name]);
        return [self free];
    }

    // Get and validate IRQ
    irqList = (unsigned int *)[deviceDescription interruptList];
    self->Port.IRQ = irqList[0];

    // "Chip Type" names a part, and is matched against the nine ShortNames in
    // Chip[].  Row 0 is "Auto", which means "detect it", so a match there is
    // silently ignored and leaves Type at 0 for the probe below.
    chipTypeStr = [configTable valueForStringKey:"Chip Type"];
    if (chipTypeStr != NULL) {
        for (i = 0; i < 9; i++) {
            if (strcmp(Chip[i].ShortName, chipTypeStr) == 0) {
                break;
            }
        }

        if (i == 9) {
            IOLog("%s: Ignoring invalid Chip Type \"%s\" from Instance table\n",
                  [self name], chipTypeStr);
        } else if (i != 0) {
            self->Port.Type = i;
            IOLog("%s: Using Chip Type \"%s\" from Instance table\n",
                  [self name], chipTypeStr);
        }
    }

    // Auto-detect chip type if not specified
    if (self->Port.Type == 0) {
        chipType = identifyChip(self->port);
        self->Port.Type = chipType;
        if (chipType == 0) {
            IOLog("%s: Unable to determine chip type at I/O base 0x%x\n",
                  [self name], self->Port.Base);
            return [self free];
        }
    }

    // "Bus Type" of "PCMCIA" marks the port as removable, which is what
    // PCMCIA_yanked and the banner's prefix key off.
    //
    // This is strcmp, not strncmp.  Reference 1499-1521 is
    // mov ecx,7 / cld / repz cmpsb / jnz, with no call: the compiler's inline
    // expansion of strcmp against a string literal, where the 7 is
    // strlen("PCMCIA") + 1 and not a caller-supplied count.  Reading the 7 as
    // an explicit length put _strncmp in our import list, and the reference
    // imports _strcmp and _strncpy but never _strncmp.
    busTypeStr = [configTable valueForStringKey:"Bus Type"];
    if (busTypeStr != NULL && strcmp(busTypeStr, "PCMCIA") == 0) {
        self->Port.PCMCIA = 1;
    }

    // Initialize chip with default settings
    initChip(self->port);

    // The four callout entries, each bound to its own handler with &self->Port
    // as the parameter.  FrameTOEntry and DataLatTOEntry are not spare slots:
    // the reference allocates them against frameTOHandler and dataLatTOHandler.
    self->Port.FrameTOEntry =
        thread_call_allocate((thread_call_func_t)frameTOHandler, self->port);
    self->Port.DataLatTOEntry =
        thread_call_allocate((thread_call_func_t)dataLatTOHandler, self->port);
    self->Port.DelayTOEntry =
        thread_call_allocate((thread_call_func_t)delayTOHandler, self->port);
    self->Port.HeartBeatTOEntry =
        thread_call_allocate((thread_call_func_t)heartBeatTOHandler, self->port);

    if (self->Port.FrameTOEntry == NULL ||
        self->Port.DataLatTOEntry == NULL ||
        self->Port.DelayTOEntry == NULL ||
        self->Port.HeartBeatTOEntry == NULL) {
        IOLog("%s: Unable to allocate callout entries\n", [self name]);
        return [self free];
    }

    // "TX Buffer Size" and "RX Buffer Size" are in characters, while the ring
    // buffers count 2-byte cells, so the requested size doubles on its way to
    // validateRingBufferSize.  Each key feeds its own queue's DefaultSize and
    // is validated against its own queue: crossing them over would silently
    // apply one direction's default to the other.
    txBufStr = [configTable valueForStringKey:"TX Buffer Size"];
    self->Port.TX.DefaultSize = 0x4b0;  // Default 1200
    if (txBufStr != NULL) {
        self->Port.TX.DefaultSize = validateRingBufferSize(
            (unsigned int)strtol(txBufStr, NULL, 10) * 2, &self->Port.TX);
    }

    rxBufStr = [configTable valueForStringKey:"RX Buffer Size"];
    self->Port.RX.DefaultSize = 0x4b0;  // Default 1200
    if (rxBufStr != NULL) {
        self->Port.RX.DefaultSize = validateRingBufferSize(
            (unsigned int)strtol(rxBufStr, NULL, 10) * 2, &self->Port.RX);
    }

    // "Chip Clock" is the UART's input clock in hz and feeds MasterClock, from
    // which programChip derives the divisor.  Anything under 1000 is discarded
    // in favour of the 1.8432 MHz a standard part runs at.
    chipClockStr = [configTable valueForStringKey:"Chip Clock"];
    masterClock = 0;
    if (chipClockStr != NULL) {
        masterClock = (unsigned int)strtol(chipClockStr, NULL, 10);
    }
    if (masterClock > 999) {
        self->Port.MasterClock = masterClock;
        IOLog("%s: Master Clock set to %ld hz.\n", [self name], (long)masterClock);
    } else {
        self->Port.MasterClock = 0x1c2000;  // Default 1843200
    }

    // "Heart Beat Interval" is in microseconds and defaults to 11000.  It is
    // clamped so that the nanosecond product still fits in 32 bits, then split
    // into the seconds/nanoseconds pair heartBeatTOHandler rearms from.
    heartBeatStr = [configTable valueForStringKey:"Heart Beat Interval"];
    if (heartBeatStr != NULL) {
        heartBeatUS = (unsigned int)strtol(heartBeatStr, NULL, 10);
        IOLog("%s: Heart Beat Interval set to %ld us.\n",
              [self name], (long)heartBeatUS);
    } else {
        heartBeatUS = 11000;
    }
    if (heartBeatUS > 0x418937) {
        heartBeatUS = 0x418937;     // 4294967 us, the most that survives * 1000
    }
    heartBeatNS = (unsigned long long)(heartBeatUS * 1000);
    self->Port.HeartBeatInterval.tv_sec = heartBeatNS / 1000000000;
    self->Port.HeartBeatInterval.tv_nsec = heartBeatNS % 1000000000;

    // "Enable MSR Interrupts" is a bare presence flag: with it the IER mask
    // keeps every bit, without it the modem-status interrupt enable (0x04) is
    // masked off for the life of the port.
    if ([configTable valueForStringKey:"Enable MSR Interrupts"] != NULL) {
        self->Port.IERmask = 0xff;
        IOLog("%s: MSR Interrupts enabled.\n", [self name]);
    } else {
        self->Port.IERmask = 0xfb;
    }

    // Call superclass init.  Its result, not self, is what this method returns.
    result = [super initFromDeviceDescription:deviceDescription];
    if (result == nil) {
        return [self free];
    }

    // enableAllInterrupts is IODirectDevice's, returns an IOReturn, and is what
    // actually attaches the handler getHandler:level:argument:forInterrupt:
    // hands out.  registerDevice then publishes the port.
    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        IOLog("%s: Unable to enable interrupts\n", [self name]);
        return [self free];
    }

    [self registerDevice];

    // The PCMCIA marker is a prefix on the chip name, not a suffix on the line.
    IOLog("%s: Base=0x%04x, IRQ=%d, Type=%s%s, FIFO=%d\n",
          [self name],
          self->Port.Base,
          self->Port.IRQ,
          (self->Port.PCMCIA ? "PCMCIA/" : ""),
          Chip[self->Port.Type].LongName,
          Chip[self->Port.Type].FIFOsize);

    return result;
}

/*
 * Free the instance.
 * Cleans up all resources and deallocates the instance.
 */
- free
{
    unsigned int oldIRQL;
    void **timer1Ptr, **timer2Ptr, **timer3Ptr, **timer4Ptr;

    // Raise interrupt level
    oldIRQL = spl4();

    // Deactivate the port (disables interrupts, frees ring buffers)
    deactivatePort(self->port);

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
    return [super free];
}

/*
 * Acquire the serial port.
 * Sets up default serial port parameters and prepares the port for use.
 *
 * Parameters:
 *   sleep - NO: fail if the port is already open; YES: wait for it to close
 *
 * Returns:
 *   IO_R_SUCCESS (0) on success
 *   0xFFFFFD3B if PCMCIA card was removed
 *   0xFFFFFD36 or other errors from watchState if interrupted while sleeping
 */
- (IOReturn)acquire:(BOOL)sleep
{
    unsigned int oldIRQL;
    unsigned long checkMask;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned char msrValue;
    unsigned int flowState;
    unsigned int msrStateBits;
    unsigned int eventMask;
    IOReturn result;
    int i;

    // Acquisition state tracking
    // Port.State's sign bit (0x80000000) is the acquired flag
    checkMask = 0;

    // Loop until acquired or error
    while (1) {
        // Raise interrupt level
        oldIRQL = spl4();

        // Check if PCMCIA card was removed
        if (self->Port.PCMCIA_yanked != 0) {
            splx(oldIRQL);
            return 0xFFFFFD3B; // -709, the PCMCIA-card-removed return
        }

        // Check if port is already acquired (bit 0x80000000 of checkMask/state)
        checkMask = self->Port.State & 0x80000000;

        if (checkMask == 0) {
            unsigned int rxWaterHigh;
            unsigned int txWaterHigh;
            // Port not acquired - proceed with acquisition

            // Set initial state to 0xA0400018
            // 0xA0400018 = acquired (0x80000000) | 0x20000000 | STATE_RX_GATE
            // (0x00400000) | 0x18.  It carries neither STATE_ACTIVE nor
            // STATE_RX_ENABLED; the receive gate the handlers test is the
            // 0x00400000 bit.
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
                RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
                                    (changedBits << 16) | 0x18);
            }

            // Clear character filter bitmap (8 words at offset 0x1e8)
            for (i = 0; i < 8; i++) {
                self->Port.SWspecial[i] = 0;
            }

            // Reset every line parameter to its default.  This is the
            // reference's block at 4853-5047, in its order; programChip at the
            // end of it derives DLRimage, LCRimage and FCRimage from these.
            self->Port.CharLength = 16;       // half-bit units: 16 == 8 data bits
            self->Port.BreakLength = 2;
            self->Port.XONchar = 0x11;        // DC1 (XON)
            self->Port.XOFFchar = 0x13;       // DC3 (XOFF)
            self->Port.StopBits = 2;          // half-bit units: 2 == 1 stop bit
            self->Port.TX_Parity = PARITY_NONE;
            self->Port.RX_Parity = 0;
            self->Port.BaudRate = 0x4b00;     // half-bits/s: 19200 == 9600 bps
            self->Port.RXOstate = 0;
            // 0x126 belongs to FlowControl (offset 0x208), NOT to MasterClock
            // (0x1dc): the reference stores it to [edi+208h] at 4937, and
            // MasterClock only ever receives 0x1c2000 or the "Chip Clock" key.
            // Putting it in MasterClock made programChip's
            // MasterClock / (BaudRate << 3) divide to zero on every acquire.
            self->Port.FlowControl = 0x126;
            self->Port.MinLatency = 0;

            // Both rings start at their configured default size, and both
            // watermarks are derived from it: high = (2 * Size) / 3, low = high
            // / 2.  The Size assignment is not optional - initFromDeviceDescription:
            // leaves Size zero, so skipping it leaves every watermark at zero and
            // the first received byte trips the above-high-water arm forever.
            self->Port.RX.Size = self->Port.RX.DefaultSize;
            rxWaterHigh = (self->Port.RX.Size * 2) / 3;
            self->Port.RX.HighWater = rxWaterHigh;
            self->Port.RX.LowWater = rxWaterHigh >> 1;
            self->Port.RX.OverRun = 0;

            self->Port.TX.Size = self->Port.TX.DefaultSize;
            txWaterHigh = (self->Port.TX.Size * 2) / 3;
            self->Port.TX.HighWater = txWaterHigh;
            self->Port.TX.LowWater = txWaterHigh >> 1;

            self->Port.DLRimage = 0;

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
            msrStateBits = msr_state_lut[msrValue >> 4];

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
                RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
                                    ((oldState & 0xFE09) | (flowState & 0x1F6) | (msrStateBits << 5)) |
                                   (changedBits << 16));
            }

            // Start heartbeat timer if interval is set
            // Check if Port.HeartBeatInterval is non-zero
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
            // -709 IO_R_EXCLUSIVE_ACCESS: the port is already held. The reference shares
            // this return site with the PCMCIA-removed path at 5405; the value is the same,
            // the meaning here is not.
            return 0xFFFFFD3B;
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
    unsigned int rxWaterHigh, txWaterHigh;
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

        // Set default configuration values.  Offsets are named from the header,
        // not from the original decompilation, which had these crossed.
        *(unsigned int *)((char *)self + 0x1bc) = 0x10;     // Port.CharLength, 16 == 8 data bits
        *(unsigned int *)((char *)self + 0x1cc) = 2;        // Port.BreakLength
        *(unsigned char *)((char *)self + 0x1e5) = 0x11;    // Port.XONchar, DC1
        *(unsigned char *)((char *)self + 0x1e6) = 0x13;    // Port.XOFFchar, DC3
        *(unsigned int *)((char *)self + 0x1c0) = 2;        // Port.StopBits, 2 == 1 stop bit
        *(unsigned int *)((char *)self + 0x1c4) = 1;        // Port.TX_Parity, PARITY_NONE
        *(unsigned int *)((char *)self + 0x1c8) = 0;        // Port.RX_Parity
        *(unsigned int *)((char *)self + 0x20c) = 0;        // Port.RXOstate
        *(unsigned int *)((char *)self + 0x1d0) = 0x4b00;   // Port.BaudRate, 19200 half-bits/s
        *(unsigned int *)((char *)self + 0x208) = 0x126;    // Port.FlowControl

        // RX ring: Size from DefaultSize, then high = (2 * Size) / 3 and
        // low = high / 2.  0x140 is Port.RX.Size and 0x16c is Port.RX.DefaultSize.
        *(int *)((char *)self + 0x140) = *(int *)((char *)self + 0x16c);
        rxWaterHigh = (unsigned int)(*(int *)((char *)self + 0x16c) * 2) / 3;
        *(unsigned int *)((char *)self + 0x148) = rxWaterHigh;       // Port.RX.HighWater
        *(unsigned int *)((char *)self + 0x14c) = rxWaterHigh >> 1;  // Port.RX.LowWater
        *(unsigned int *)((char *)self + 0x168) = 0;                 // Port.RX.OverRun

        // TX ring: the same, from 0x1a4 = Port.TX.DefaultSize into
        // 0x178 = Port.TX.Size.
        *(int *)((char *)self + 0x178) = *(int *)((char *)self + 0x1a4);
        txWaterHigh = (unsigned int)(*(int *)((char *)self + 0x1a4) * 2) / 3;
        *(unsigned int *)((char *)self + 0x180) = txWaterHigh;       // Port.TX.HighWater
        *(unsigned int *)((char *)self + 0x184) = txWaterHigh >> 1;  // Port.TX.LowWater

        // Program chip with default settings (pass value at offset 600)
        programChip(*(Port **)((char *)self + 600));

        // Deactivate port (pass value at offset 600)
        deactivatePort(*(Port **)((char *)self + 600));

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
            RX_enqueueLongEvent(selfPtr, 0x53, changedBits << 16);
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

    // Validate parameters
    if (count == NULL || buffer == NULL || size < minCount) {
        return 0xFFFFFD3E; // Invalid argument
    }

    // Port.DataLatInterval: 0x228 is tv_sec, 0x22c is tv_nsec
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

        // Arm the data-latency timer after the first byte.  DataLatTOEntry
        // (Port+0xEC), not DelayTOEntry (Port+0xF0): the reference reads
        // [edx+0ECh] at 9327 and 9374, and 0xEC is the entry
        // initFromDeviceDescription: bound to dataLatTOHandler.  Arming
        // DelayTOEntry here would run delayTOHandler instead - clearing State
        // bit 0x1000 and driving the interrupt handler - and would clobber any
        // delay timer event 0x4B had set (Finding 90).
        if (timerScheduled > 0) {
            thread_call_enter_delayed(
                self->Port.DataLatTOEntry,
                deadline_from_interval(self->Port.DataLatInterval));
            timerScheduled = -1;  // Mark as scheduled
        }
    }

    // Cancel the data-latency timer if it was armed
    if (timerScheduled < 0) {
        thread_call_cancel(self->Port.DataLatTOEntry);
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
- (IOReturn)dequeueEvent:(unsigned long *)event
                    data:(unsigned long *)data
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
    unsigned long checkMask;
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
                    txState = TX_STATE_BELOW_MED;
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
                RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
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
- (IOReturn)enqueueEvent:(unsigned long)event
                    data:(unsigned long)data
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
 *   Other errors from executeEvent
 */
- (IOReturn)executeEvent:(unsigned long)event
                    data:(unsigned long)data
{
    unsigned int oldIRQL;
    IOReturn result;
    unsigned int changedBits, newState;
    unsigned int oldState;
    unsigned char mcrValue;
    unsigned int flowState;
    unsigned int eventMask;
    unsigned int validatedSize;
    unsigned long long charLatNS;

    result = IO_R_SUCCESS;

    // Raise interrupt level
    oldIRQL = spl4();

    // Check if port is acquired (bit 0x80000000 of currentState must be set)
    if ((self->Port.State & 0x80000000) == 0) {
        splx(oldIRQL);
        return 0xFFFFFD33; // Port not acquired
    }

    switch (event) {
    case 0x0F:
        // Resize the RX ring: 0x140 is Port.RX.Size, 0x148/0x14c its high and
        // low watermarks.  Only while the port is inactive.
        if ((self->Port.State & 0x40000000) != 0) {
            result = 0xFFFFFD2B;
        } else {
            validatedSize = validateRingBufferSize(data, &self->Port.RX);
            self->Port.RX.Size = validatedSize;

            if (self->Port.RX.HighWater > validatedSize - 3) {
                self->Port.RX.HighWater = validatedSize - 3;
            }
            if (self->Port.RX.LowWater > self->Port.RX.HighWater - 3) {
                self->Port.RX.LowWater = self->Port.RX.HighWater - 3;
            }
        }
        break;

    case 0x0B:
        // Resize the TX ring: 0x178 is Port.TX.Size, 0x180/0x184 its high and
        // low watermarks.  The queue handed to validateRingBufferSize is
        // &Port.RX in BOTH arms; that is what the reference does at 7024, and
        // it is reproduced rather than corrected (see divergences.md).
        if ((self->Port.State & 0x40000000) != 0) {
            result = 0xFFFFFD2B;
        } else {
            validatedSize = validateRingBufferSize(data, &self->Port.RX);
            self->Port.TX.Size = validatedSize;

            if (self->Port.TX.HighWater > validatedSize - 3) {
                self->Port.TX.HighWater = validatedSize - 3;
            }
            if (self->Port.TX.LowWater > self->Port.TX.HighWater - 3) {
                self->Port.TX.LowWater = self->Port.TX.HighWater - 3;
            }
        }
        break;

    case 0x4B:
        // Character-latency interval, microseconds in, seconds/nanoseconds out.
        // 0x230/0x234 is Port.CharLatInterval, NOT HeartBeatInterval (0x238);
        // verified against the reference at 6889/6898.  Unlike the two other
        // microsecond inputs - initFromDeviceDescription: and _executeEvent's
        // own 0x4B - the reference does NOT clamp to 0x418937 here (6816-6831
        // is an unguarded lea/shl chain), so `data * 1000` can wrap in 32 bits.
        // The clamp is deliberately not added: it is not in the reference.
        charLatNS = (unsigned long long)(data * 1000);
        self->Port.CharLatInterval.tv_sec = charLatNS / 1000000000;
        self->Port.CharLatInterval.tv_nsec = charLatNS % 1000000000;
        break;

    case 0x53:
        // External state change event.  0x208 is Port.FlowControl.
        changedBits = (data ^ self->Port.FlowControl) & 0x16;
        self->Port.FlowControl = data & 0xFFFF017E;

        // If flow control bits changed
        if (changedBits != 0) {
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
                RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
                                    (newState & 0xFFFF) | (changedBits << 16));
            }
        }
        break;

    default:
        // Everything else goes to the shared event machine, which reports the
        // bits it touched through the mask and the new values through state.
        changedBits = 0;
        newState = self->Port.State;

        result = executeEvent(self->port, event, data, &newState, &changedBits);

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
            RX_enqueueLongEvent(self->port, EVENT_STATE_CHANGE,
                                (newState & 0xFFFF) | (changedBits << 16));
        }
        break;
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
- (IOReturn)requestEvent:(unsigned long)event
                    data:(unsigned long *)data
{
    unsigned long long timeValue;
    unsigned int result;

    // Check if data pointer is valid
    if (data == NULL) {
        return 0xFFFFFD3E;
    }

    // Handle different query types based on event low byte
    switch (event & 0xFF) {
        case 0x05: // Port.State bit 30 (0x40000000), the port-active flag
            *data = (*(unsigned int *)((char *)self + 0x134) >> 30) & 1;
            return 0;

        case 0x0B: // Port.TX.Size (0x178)
            *data = *(unsigned int *)((char *)self + 0x178);
            return 0;

        case 0x0F: // Port.RX.Size (0x140)
            *data = *(unsigned int *)((char *)self + 0x140);
            return 0;

        case 0x13: // Port.TX.LowWater (0x184)
            *data = *(unsigned int *)((char *)self + 0x184);
            return 0;

        case 0x17: // Port.RX.LowWater (0x14c)
            *data = *(unsigned int *)((char *)self + 0x14c);
            return 0;

        case 0x1B: // Port.TX.HighWater (0x180)
            *data = *(unsigned int *)((char *)self + 0x180);
            return 0;

        case 0x1F: // Port.RX.HighWater (0x148)
            *data = *(unsigned int *)((char *)self + 0x148);
            return 0;

        case 0x23: // Port.TX.Size - Port.TX.Count, the free space in TX
            *data = *(int *)((char *)self + 0x178) - *(int *)((char *)self + 0x17c);
            return 0;

        case 0x27: // Port.RX.Size - Port.TX.Count.  The reference really does
                   // mix the two queues here (7932-7938); reproduced.
            *data = *(int *)((char *)self + 0x140) - *(int *)((char *)self + 0x17c);
            return 0;

        case 0x33: // Port.BaudRate (0x1d0)
            *data = *(unsigned int *)((char *)self + 0x1d0);
            return 0;

        case 0x37: // Always returns 0
            *data = 0;
            return 0;

        case 0x3B: // Port.CharLength (0x1bc)
            *data = *(unsigned int *)((char *)self + 0x1bc);
            return 0;

        case 0x3F: // Always returns 0
            *data = 0;
            return 0;

        case 0x43: // Port.TX_Parity (0x1c4)
            *data = *(unsigned int *)((char *)self + 0x1c4);
            return 0;

        case 0x47: // Port.RX_Parity (0x1c8)
            *data = *(unsigned int *)((char *)self + 0x1c8);
            return 0;

        // The two interval queries are the inverse of what events 0x4B and 0x4F
        // set: seconds and nanoseconds back to microseconds.  The tvalspec must
        // be read as its two fields - tv_sec widened and scaled, tv_nsec sign-
        // extended and added - and not as one little-endian 64-bit word, which
        // would be tv_sec | (tv_nsec << 32).  Reference 7704-7808: mul by
        // 3B9ACA00h on tv_sec, cdq on tv_nsec, add/adc, then __udivdi3 by 1000.
        case 0x4B: // Port.CharLatInterval (0x230/0x234), NOT HeartBeatInterval (0x238)
            timeValue = (unsigned long long)self->Port.CharLatInterval.tv_sec * 1000000000ULL
                        + (long long)(int)self->Port.CharLatInterval.tv_nsec;
            result = (unsigned int)(timeValue / 1000);
            *data = result;
            return 0;

        case 0x4F: // Port.DataLatInterval (0x228/0x22c)
            timeValue = (unsigned long long)self->Port.DataLatInterval.tv_sec * 1000000000ULL
                        + (long long)(int)self->Port.DataLatInterval.tv_nsec;
            result = (unsigned int)(timeValue / 1000);
            *data = result;
            return 0;

        case 0x53: // Port.FlowControl (0x208)
            *data = *(unsigned int *)((char *)self + 0x208);
            return 0;

        case 0xE5: // Port.MinLatency (0x1e0), reported as 0 or 1
            *data = (unsigned int)(*(char *)((char *)self + 0x1e0) != 0);
            return 0;

        case 0xE9: // Port.XOFFchar (0x1e6)
            *data = (unsigned int)*(unsigned char *)((char *)self + 0x1e6);
            return 0;

        case 0xED: // Port.XONchar (0x1e5)
            *data = (unsigned int)*(unsigned char *)((char *)self + 0x1e5);
            return 0;

        case 0xF3: // Port.StopBits (0x1c0)
            *data = *(unsigned int *)((char *)self + 0x1c0);
            return 0;

        case 0xF7: // Always returns 0
            *data = 0;
            return 0;

        case 0xF9: // Port.State bit 11 (0x800), the break flag event 0xF9 sets
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
- (unsigned long)nextEvent
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
- (unsigned long)getState
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
 *   0xFFFFFD3E (IO_R_INVALID_ARG) if reserved state bits are set
 *   0xFFFFFD33 if port not acquired
 */
- (IOReturn)setState:(unsigned long)state
                mask:(unsigned long)mask
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
        // Calculate effective mask: clear bits not in Port.FlowControl (0x208)
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
            // Check Port.FlowControl (0xe0 from the Port) against changed bits << 16
            if ((*(unsigned int *)((char *)selfPtr + 0xe0) & (changedBits << 16)) != 0) {
                RX_enqueueLongEvent(selfPtr, 0x53, (newState & 0xffff) | (changedBits << 16));
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
- (IOReturn)watchState:(unsigned long *)state
                  mask:(unsigned long)mask
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
    const char *stringValue;

    // Validate parameters
    if (values == NULL || count == NULL || *count == 0) {
        return [super getCharValues:values forParameter:parameter count:count];
    }

    // valueForStringKey: already returns the string, so the whole lookup is one
    // chain of three messages with no intermediate checks: messaging nil returns
    // nil, so a missing device description or config table falls out here too.
    stringValue = [[[self deviceDescription] configTable]
                       valueForStringKey:parameter];
    if (stringValue == NULL) {
        return [super getCharValues:values forParameter:parameter count:count];
    }

    // Copy string to buffer (leave room for null terminator)
    strncpy((char *)values, stringValue, *count - 1);
    values[*count - 1] = '\0';

    // Report the length including the null terminator
    *count = strlen((char *)values) + 1;
    return IO_R_SUCCESS;
}

/*
 * Get interrupt handler information.
 * Returns the interrupt handler function, IRQ level, and argument for this device.
 *
 * Parameters:
 *   handler - Output: pointer to interrupt handler function
 *   level - Output: IRQ level (always 3 for ISA serial ports)
 *   argument - Output: argument to pass to handler (the Port *)
 *   interruptType - Type of interrupt (unused for serial ports)
 *
 * Returns:
 *   YES - handler is valid
 */
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)level
          argument:(unsigned int *)argument
      forInterrupt:(unsigned int)interruptType
{
    // The handler comes out of the chip table, not out of a FIFO test: the
    // 82510 (row 8) reports a four-byte FIFO and still uses NonFIFOIntHandler,
    // so Type > 4 would hand that part the wrong handler.
    *handler = (IOInterruptHandler)Chip[self->Port.Type].IntHandler;

    // Set IRQ level to 3
    *level = 3;

    // Pass value at offset 0x258 as the argument
    // (This is the interrupt handler context pointer)
    *argument = (unsigned int)self->port;

    return YES;
}

@end
