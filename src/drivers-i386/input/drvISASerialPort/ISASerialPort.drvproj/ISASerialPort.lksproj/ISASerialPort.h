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
#import <driverkit/IODirectDevice.h>
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

/*
 * The protocol every port device conforms to, and the one the reference's
 * __OBJC,__protocol record names.  It is declared here because the only copy
 * in the tree lives in a private PortServer header this project cannot reach.
 * The twelve methods and their signatures are the reference's, read out of its
 * protocol method-description list.
 */
@protocol PortDevices

- (IOReturn)dequeueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
               minCount:(unsigned int)minCount;
- (IOReturn)enqueueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
                  sleep:(BOOL)sleep;
- (IOReturn)dequeueEvent:(unsigned long *)event
                    data:(unsigned long *)data
                   sleep:(BOOL)sleep;
- (IOReturn)enqueueEvent:(unsigned long)event
                    data:(unsigned long)data
                   sleep:(BOOL)sleep;
- (IOReturn)requestEvent:(unsigned long)event
                    data:(unsigned long *)data;
- (IOReturn)executeEvent:(unsigned long)event
                    data:(unsigned long)data;
- (unsigned long)nextEvent;
- (IOReturn)watchState:(unsigned long *)state
                  mask:(unsigned long)mask;
- (unsigned long)getState;
- (IOReturn)setState:(unsigned long)state
                mask:(unsigned long)mask;
- (IOReturn)release;
- (IOReturn)acquire:(BOOL)sleep;

@end

/*
 * IODirectDevice, not IODevice: its six ivars plus the reserved int[2] are the
 * 32 bytes that put Port at object offset 296 and make instance_size 604.
 */
@interface ISASerialPort : IODirectDevice <PortDevices>
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
- (IOReturn)acquire:(BOOL)sleep;

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
- free;

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
- (IOReturn)dequeueEvent:(unsigned long *)event
                    data:(unsigned long *)data
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
- (IOReturn)enqueueEvent:(unsigned long)event
                    data:(unsigned long)data
                   sleep:(BOOL)sleep;

/*
 * Execute an event.
 */
- (IOReturn)executeEvent:(unsigned long)event
                    data:(unsigned long)data;

/*
 * Request an event.
 */
- (IOReturn)requestEvent:(unsigned long)event
                    data:(unsigned long *)data;

/*
 * Get the next event.
 */
- (unsigned long)nextEvent;

/*
 * Get the current state.
 */
- (unsigned long)getState;

/*
 * Set the state with mask.
 */
- (IOReturn)setState:(unsigned long)state
                mask:(unsigned long)mask;

/*
 * Watch state with mask.
 */
- (IOReturn)watchState:(unsigned long *)state
                  mask:(unsigned long)mask;

/*
 * Get character values for a parameter.
 */
- (IOReturn)getCharValues:(unsigned char *)values
             forParameter:(IOParameterName)parameter
                    count:(unsigned int *)count;

/*
 * Get interrupt handler information.  IODirectDevice(IOInterrupts) declares
 * this returning BOOL with an unsigned int * argument, and so does the
 * reference.
 */
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)level
          argument:(unsigned int *)argument
      forInterrupt:(unsigned int)interruptType;

@end

#endif /* _BSD_DEV_I386_ISASERIALPORT_H_ */
