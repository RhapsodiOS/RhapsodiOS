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
 * SerialPointingDevice.h - Serial Mouse/Pointing Device Driver
 */

#ifndef _SERIAL_POINTING_DEVICE_H
#define _SERIAL_POINTING_DEVICE_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/IODevice.h>
#import <driverkit/IOPower.h>
#import <driverkit/IOEventSource.h>
#import <kernserv/queue.h>

/* Mouse event structure */
typedef struct {
    unsigned int timestamp_low;     // Offset 0x158
    unsigned int timestamp_high;    // Offset 0x15C
    unsigned char buttons;          // Offset 0x160
    char deltaX;                    // Offset 0x161
    char deltaY;                    // Offset 0x162
} MouseEvent;

@interface SerialPointingDevice : IODirectDevice
{
@private
    id mouseEventPort;              // Offset 0x128 - Event target
    unsigned int resolution;        // Offset 0x12C (300)
    BOOL inverted;                  // Offset 0x130
    BOOL verbose;                   // Offset 0x144
    void *mainLoopThread;           // Offset 0x148
    int mouseType;                  // Offset 0x14C (mouse hardware type)
    int protocolType;               // Offset 0x150 (protocol handler ID)
    id serialPortObject;            // Offset 0x154
    MouseEvent mouseEvent;          // Offset 0x158
}

/* Detection and initialization */
- (BOOL)detect;
- free;

/* Configuration */
- (IOReturn)mouseInit:(IODeviceDescription *)deviceDescription;

/* Parameters */
- (IOReturn)getIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count;

- (IOReturn)setIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned)count;

- (unsigned int)getResolution;

/* Event target */
- (void)setEventTarget:(id)target;

/* Serial communication */
- (BOOL)getByte:(unsigned char *)byte sleep:(BOOL)shouldSleep;
- (void)mainLoop:(id)arg;

/* Protocol handlers */
- (void)MSProtocol;
- (void)MMProtocol;
- (void)MPlusProtocol;
- (void)FiveBProtocol;
- (void)RBProtocol;
- (void)UnknownProtocol;

@end

#endif /* _SERIAL_POINTING_DEVICE_H */
