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
 * ISASerialPort.h - Interface for ISA Serial Port driver.
 *
 * HISTORY
 */

#ifndef _BSD_DEV_I386_ISASERIALPORT_H_
#define _BSD_DEV_I386_ISASERIALPORT_H_

#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <sys/types.h>

#import "ISASerialPortInternal.h"

#ifndef IO_R_NO_RESOURCES
#define IO_R_NO_RESOURCES IO_R_RESOURCE
#endif
#ifndef IO_R_NO_PAPER
#define IO_R_NO_PAPER (-737)
#endif

@interface ISASerialPort : IODevice
{
@public
    Port  Port;         // all per-port state, at object offset 296
    Port *port;         // &self->Port, at object offset 600
}


/*
 * Probe for device presence.
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/*
 * Acquire the serial port.
 */
- (IOReturn)acquire:(void *)refCon;

/*
 * Release the serial port.
 */
- (IOReturn)release;

/*
 * Initialize from device description.
 */
- (id)initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/*
 * Free the instance.
 */
- (void)free;

/*
 * Dequeue data from the serial port.
 */
- (IOReturn)dequeueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
               minCount:(unsigned int)minCount;

/*
 * Dequeue an event from the serial port.
 */
- (IOReturn)dequeueEvent:(unsigned int *)event
                    data:(unsigned int *)data
                   sleep:(BOOL)sleep;

/*
 * Enqueue data to the serial port.
 */
- (IOReturn)enqueueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
                  sleep:(BOOL)sleep;

/*
 * Enqueue an event to the serial port.
 */
- (IOReturn)enqueueEvent:(unsigned int)event
                    data:(unsigned int)data
                   sleep:(BOOL)sleep;

/*
 * Execute an event.
 */
- (IOReturn)executeEvent:(unsigned int)event
                    data:(unsigned int)data;

/*
 * Request an event.
 */
- (IOReturn)requestEvent:(unsigned int)event
                    data:(unsigned int *)data;

/*
 * Get the next event.
 */
- (unsigned int)nextEvent;

/*
 * Get the current state.
 */
- (unsigned int)getState;

/*
 * Set the state with mask.
 */
- (IOReturn)setState:(unsigned int)state
                mask:(unsigned int)mask;

/*
 * Watch state with mask.
 */
- (IOReturn)watchState:(unsigned int *)state
                  mask:(unsigned int)mask;

/*
 * Get character values for a parameter.
 */
- (IOReturn)getCharValues:(unsigned char *)values
             forParameter:(IOParameterName)parameter
                    count:(unsigned int *)count;

/*
 * Get interrupt handler information.
 */
- (IOReturn)getHandler:(IOInterruptHandler *)handler
                 level:(unsigned int *)level
              argument:(void **)argument
          forInterrupt:(unsigned int)interruptType;

@end

#endif /* _BSD_DEV_I386_ISASERIALPORT_H_ */
