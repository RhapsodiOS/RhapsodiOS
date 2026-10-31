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
 * ISASerialPortQueue.h - the ring-buffer helper the units that touch a queue
 * share.
 *
 * This is separate from ISASerialPortInternal.h because gcc emits every static
 * defined in a translation unit whether or not that unit references it.  The
 * reference carries three copies of RX_enqueueLongEvent, at 0, 20684 and
 * 23200 -- one each in the class, the ring buffer and the flow machine, and
 * none in the chip unit.  One header included by all four units would give
 * four copies, so the definition belongs in a header the chip unit does not
 * include.  Including it at the top of a unit also puts the copy ahead of
 * everything else in that unit, which is where the reference has it.
 *
 * HISTORY
 */

#ifndef _BSD_DEV_I386_ISASERIALPORTQUEUE_H_
#define _BSD_DEV_I386_ISASERIALPORTQUEUE_H_

#import "ISASerialPortInternal.h"

/*
 * RX enqueue long event (3-word event: type + data low + data high).
 * Used for state change events and other long data events.
 *
 * The reference returns nothing and takes the event as a byte, masking it with
 * `and edx, 0FFh` at 90; every one of the eighteen call sites discards the
 * result and passes a byte-sized event.
 */
static void RX_enqueueLongEvent(Port *port, unsigned char event, unsigned int data)
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
        return;
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
}

#endif /* _BSD_DEV_I386_ISASERIALPORTQUEUE_H_ */
