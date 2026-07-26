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
 * ISASerialPortFlow.c - flow control state machine and state watching.
 *
 * Plain C: neither function references an Objective-C construct.
 *
 * HISTORY
 */

#import "ISASerialPortInternal.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>

/*
 * Flow control state machine.
 * Calculates the new port state based on current flow control configuration.
 * Returns the updated state value with flow control bits set appropriately.
 */
unsigned int flowMachine(Port *port)
{
    unsigned int newState = port->State;

    // Check if RTS or hardware flow control is enabled
    if ((port->FlowControl & (FLOW_RTS_ENABLED | FLOW_HW_ENABLED)) == 0) {
        // Only DTR flow control (if enabled)
        if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
            // Check if queue above high watermark or status flag not set
            if ((port->RX.HighWater < port->RX.Count) ||
                ((port->State & 0x40000000) == 0)) {
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
        if ((port->FlowControl & FLOW_DTR_ENABLED) != 0) {
            if ((port->State & 0x40000000) == 0) {
                // De-assert DTR
                newState &= ~STATE_DTR;
            } else {
                // Assert DTR
                newState |= STATE_DTR;
            }
        }

        // Handle RTS flow control
        if ((port->FlowControl & FLOW_RTS_ENABLED) == 0) {
            // Hardware flow control only
            if ((port->FlowControl & FLOW_HW_ENABLED) != 0) {
                if (port->RX.HighWater < port->RX.Count) {
                    // Queue above high watermark - de-assert hardware flow control
                    newState &= ~0x10;
                    port->RXOstate = 1;
                } else {
                    // Queue below high watermark - assert hardware flow control
                    newState |= 0x10;
                    // Update flow control state if conditions met
                    if ((port->RXOstate != 0) && ((port->State & 0x40000000) != 0)) {
                        port->RXOstate = 2;
                    }
                }
            }
        } else {
            // RTS flow control enabled
            if ((port->RX.HighWater < port->RX.Count) ||
                ((port->State & 0x40000000) == 0)) {
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
 *
 * Every exit runs the cleanup below, as the reference does: it funnels the
 * state-changed exits and the -714 exit into the same block that clears
 * WatchStateMask and wakes the other threads sleeping on it.  Returning around
 * that block leaves those waiters blocked forever.
 */
IOReturn watchState(Port *port, unsigned int *state, unsigned int mask)
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
        // (~State ^ desiredState) gives bits that differ
        changedBits = (~port->State ^ desiredState) & actualMask;

        if (changedBits != 0) {
            // State has changed - return current state
            *state = port->State;

            result = IO_R_SUCCESS;

            // If we were checking for active state and it changed
            if (needsActiveCheck && (changedBits & STATE_ACTIVE)) {
                // Port became inactive (PCMCIA yanked or closed).
                // acquire: compares against this value as its retry sentinel.
                result = IO_R_IO;  // -714 (0xfffffd36)
            }

            goto wakeWaiters;
        }

        // State hasn't changed yet - wait for it

        // Acquire lock using test-and-set loop
        while (port->WatchLock.locked != 0) {
            // Spin while lock is held
        }

        // Atomic test and set
        IOEnterCriticalSection();
        if (port->WatchLock.locked == 1) {
            IOExitCriticalSection();
            continue;  // Lost race, try again
        }
        port->WatchLock.locked = 1;
        IOExitCriticalSection();

        // Set the mask of bits we're watching
        port->WatchStateMask |= actualMask;

        // Sleep waiting for state change
        thread_sleep(&port->WatchStateMask, &port->WatchLock.locked, 1);  // 1 = interruptible

        // Get the result of the wait
        waitResult = thread_wait_result();

        // Loop while interrupted (result 4)
    } while (waitResult == 4);

    // Wait failed (timeout or other error)
    result = IO_R_IPC_FAILURE;  // -703 (0xfffffd41)

wakeWaiters:
    // Cleanup: clear watch mask and wake any other waiters
    port->WatchStateMask = 0;
    thread_wakeup_prim(&port->WatchStateMask, 0, 4);  // 0 = all threads, 4 = THREAD_RESTART

    return result;
}
