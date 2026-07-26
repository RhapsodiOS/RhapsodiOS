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
 * ISASerialPortQueue.c - the RX and TX ring buffers.
 *
 * Plain C: none of these six functions references an Objective-C construct.
 * They appear in the order the reference links them.
 *
 * HISTORY
 */

#import "ISASerialPortInternal.h"
#import "ISASerialPortQueue.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#import <kernserv/prototypes.h>

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
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned long watchMask;
    IOReturn result;

    // If event is 0, return immediately
    if ((event & 0xFF) == 0) {
        return IO_R_SUCCESS;
    }

    do {
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
                // Write second word: bits 0-15 of data, which deliberately
                // repeats byte 0 already carried in the header cell's high byte
                *writePtr++ = (unsigned short)data;
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
                            newState = TX_STATE_CRITICAL;
                        } else {
                            port->TX.Dequeue = port->TX.HighWater;
                            newState = TX_STATE_ABOVE_HIGH;
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
                    if (newState & 0x02) {  // DTR state
                        mcrValue |= MCR_DTR;
                    }
                    if (newState & 0x04) {  // RTS state
                        mcrValue |= MCR_RTS;
                    }
                    outb(port->Base + UART_MCR, mcrValue);
                }

                // Schedule timer callback if not already pending
                if ((port->State & 0x10000000) == 0) {
                    thread_call_enter(port->FrameTOEntry);
                }

                // Notify RX queue of state change if mask matches
                if (port->FlowControl & (changedBits << 16)) {
                    RX_enqueueLongEvent(port, 0x53,
                                        (newState & 0xFFFF) | (changedBits << 16));
                }
            }

            return IO_R_SUCCESS;
        }

        // No space available
        if (!sleep) {
            return IO_R_RESOURCE;  // -702 (0xfffffd42)
        }

        // Wait for TX_ENABLED state change
        watchMask = 0;
        result = watchState(port, &watchMask, STATE_TX_ENABLED);

    } while (result == IO_R_SUCCESS);

    return result;
}

/*
 * RX dequeue event.
 * Dequeues variable-length events from the receive queue.
 * param sleep: If TRUE, wait for event; if FALSE, return immediately if empty
 */
IOReturn RX_dequeueEvent(Port *port, unsigned char *eventType,
                         unsigned long *eventData, BOOL sleep)
{
    unsigned short *readPtr;
    unsigned short firstWord, dataWord;
    unsigned int eventLen;
    unsigned int newState, oldState, changedBits;
    unsigned char mcrValue;
    unsigned long watchMask;
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

                    // Handle flow control - assert RTS/DTR when queue drains.
                    // Exactly one arm runs: RTS wins over hardware, hardware
                    // over DTR.
                    if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                        newState |= STATE_RTS;
                    } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                        newState |= 0x10;  // Hardware flow control bit
                        // Update flow control state machine
                        if (port->RXOstate == -1) {
                            port->RXOstate = 2;
                        } else if (port->RXOstate == 1) {
                            port->RXOstate = -2;
                        }
                    } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                        newState |= STATE_DTR;
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
                    if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                        newState &= ~STATE_RTS;
                    } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                        newState &= ~0x10;
                        // Update flow control state machine
                        if (port->RXOstate == -2 || port->RXOstate == 0) {
                            port->RXOstate = 1;
                        } else if (port->RXOstate == 2) {
                            port->RXOstate = -1;
                        }
                    } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                        newState &= ~STATE_DTR;
                    }
                } else {
                    // Between watermarks
                    port->RX.Enqueue = port->RX.HighWater;
                    port->RX.Dequeue = port->RX.LowWater;
                }

                // Update state and detect changes.  The mask on newState is
                // the RX level bits plus the flow bits it may have touched;
                // the reference narrows it the same way (and eax, 0F017Eh).
                oldState = port->State;
                newState = (oldState & 0xFFF0FE81) | (newState & 0x000F017E);
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
                    outb(port->Base + UART_MCR, mcrValue);
                }

                // Schedule timer callback if not already pending
                if ((port->State & 0x10000000) == 0) {
                    thread_call_enter(port->FrameTOEntry);
                }

                // Notify of state change if mask matches
                if (port->FlowControl & (changedBits << 16)) {
                    RX_enqueueLongEvent(port, EVENT_STATE_CHANGE, (newState & 0xFFFF) | (changedBits << 16));
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
 * RX dequeue data byte.
 * Dequeues a single data byte from RX ring buffer.
 * Data is stored as 2-byte words: low byte = 'U' marker (0x55), high byte = actual data.
 * param byteOut: Pointer to store the dequeued byte
 * param sleep: If TRUE, wait for data; if FALSE, return error if no data
 * Returns: IO_R_SUCCESS on success, IO_R_RESOURCE if no data (and not sleeping)
 */
IOReturn RX_dequeueData(Port *port, unsigned char *byteOut, BOOL sleep)
{
    unsigned short dataWord;
    unsigned short *readPtr;
    unsigned int oldState, newState, changedBits;
    unsigned char mcrValue;
    unsigned long watchMask;
    IOReturn result;

    do {
        // Check if RX queue has data
        if (port->RX.Count != 0) {
            readPtr = (unsigned short *)port->RX.Output;

            // Verify marker byte (low byte should be 'U' = 0x55)
            if ((*(unsigned char *)readPtr) != 'U') {
                return IO_R_RESOURCE;  // -702 (0xfffffd42)
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

                        // Update flow control - turn ON (assert signals when
                        // queue drains).  Exactly one arm runs: RTS wins over
                        // hardware, hardware over DTR.
                        if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                            newState |= STATE_RTS;
                        } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                            newState |= 0x10;  // Hardware flow control bit
                            // Update flow control state machine
                            if (port->RXOstate == -1) {
                                port->RXOstate = 2;
                            } else if (port->RXOstate == 1) {
                                port->RXOstate = -2;
                            }
                        } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
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

                        // Update flow control - turn OFF (de-assert signals
                        // when queue fills), the same chain in reverse.
                        if ((port->FlowControl & FLOW_RTS_ENABLED) != 0) {
                            newState &= ~STATE_RTS;
                        } else if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                            newState &= ~0x10;
                            // Update flow control state machine
                            if (port->RXOstate == -2 || port->RXOstate == 0) {
                                port->RXOstate = 1;
                            } else if (port->RXOstate == 2) {
                                port->RXOstate = -1;
                            }
                        } else if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
                            newState &= ~STATE_DTR;
                        }
                    } else {
                        // Between low and high watermarks
                        port->RX.Enqueue = port->RX.HighWater;
                        port->RX.Dequeue = port->RX.LowWater;
                    }

                    // Update current state and calculate changed bits
                    oldState = port->State;
                    newState = (oldState & 0xfff0fe81) | (newState & 0x000f017e);
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
                        outb(port->Base + UART_MCR, mcrValue);
                    }

                    // Schedule timer callback if not already pending
                    if ((port->State & 0x10000000) == 0) {
                        thread_call_enter(port->FrameTOEntry);
                    }

                    // Notify RX queue of state change if flow control mode matches
                    if ((port->FlowControl & (changedBits << 16)) != 0) {
                        RX_enqueueLongEvent(port, EVENT_STATE_CHANGE,
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
            return IO_R_RESOURCE;  // -702 (0xfffffd42)
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
 * IOMalloc and IOFree are size-matched, so the block has to go back exactly as
 * it came: AllocBase and AllocSize, not Base and End - Base.  Base can sit one
 * byte inside the block, and the allocation is Size * 2 + 2 rather than
 * Size * 2.
 *
 * Size, the watermarks, Enqueue, Dequeue and DefaultSize deliberately survive:
 * allocateRingBuffer calls this first and then reads q->Size as the requested
 * size, so clearing Size would silently force every buffer to DefaultSize.
 *
 * Parameters:
 *   q - Pointer to the queue whose ring buffer is being released
 */
void freeRingBuffer(Queue *q)
{
    // The guard is on Base, not AllocBase
    if (q->Base != NULL) {
        IOFree(q->AllocBase, q->AllocSize);
    }

    q->AllocBase = NULL;
    q->Base = NULL;
    q->End = NULL;
    q->Output = NULL;
    q->Input = NULL;
    q->AllocSize = 0;
    q->OverRun = 0;
    q->Count = 0;
}

/*
 * Allocate ring buffer.
 * Allocates memory for a ring buffer (RX or TX) with proper alignment.
 *
 * Cells are 2 bytes, so the block is Size * 2 + 2: the spare 2 bytes let Base
 * be nudged up to an even address when IOMalloc returns an odd one.  AllocBase
 * and AllocSize keep the block as it was handed out so freeRingBuffer can
 * return it unchanged.
 *
 * Parameters:
 *   q - Pointer to the queue whose ring buffer is being allocated
 *
 * Returns:
 *   1 on success, 0 on failure (a BOOL, not an IOReturn)
 */
int allocateRingBuffer(Queue *q)
{
    // Release whatever is there; this leaves q->Size alone
    freeRingBuffer(q);

    // Validate the requested size, which q->Size carries in
    q->Size = validateRingBufferSize(q->Size, q);

    q->AllocSize = (q->Size * 2) + 2;
    q->AllocBase = (char *)IOMalloc(q->AllocSize);

    if (q->AllocBase == NULL) {
        return 0;
    }

    // Round the ring itself up to an even address
    if (((unsigned int)q->AllocBase & 1) != 0) {
        q->Base = q->AllocBase + 1;
    } else {
        q->Base = q->AllocBase;
    }

    q->End = q->Base + (q->Size * 2);
    q->Output = q->Base;
    q->Input = q->Base;
    q->OverRun = 0;
    q->Count = 0;

    // Report the next state change when the queue drains to the low watermark
    q->Enqueue = q->LowWater;
    q->Dequeue = 0;

    return 1;
}
