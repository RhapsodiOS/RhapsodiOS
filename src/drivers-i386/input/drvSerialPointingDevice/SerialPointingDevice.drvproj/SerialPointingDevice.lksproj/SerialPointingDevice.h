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
#import <driverkit/generalFuncs.h>
#import <kernserv/queue.h>
#import <bsd/dev/i386/PCPointer.h>
#import <bsd/dev/i386/PCPointerDefs.h>

/*
 * target (0x128), resolution (0x12c) and inverted (0x130) are inherited from
 * PCPointer, which also reserves 0x134-0x143.  This class adds only the six
 * ivars below, giving an instance size of 356 (0x164).
 */
@interface SerialPointingDevice : PCPointer
{
@private
    BOOL verbose;                   /* 0x144 */
    void *mainThread;               /* 0x148 */
    int mouseType;                  /* 0x14c - mouse hardware type */
    int protocol;                   /* 0x150 - protocol handler ID */
    id portDevice;                  /* 0x154 */
    PCPointerEvent pointerEvent;    /* 0x158 */
}

/* Detection and initialization */
- (BOOL)detect;
- free;

/* Configuration */
- (BOOL)mouseInit:(IODeviceDescription *)deviceDescription;

/* Parameters */
- (IOReturn)getIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count;

- (IOReturn)setIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned)count;

- (int)getResolution;

/* Event target */
- (BOOL)setEventTarget:(id)eventTarget;

/* Serial communication */
- (BOOL)getByte:(char *)byte sleep:(BOOL)shouldSleep;
- (IOThreadFunc)mainLoop:(id)arg;

/* Protocol handlers */
- (void)MSProtocol;
- (void)MMProtocol;
- (void)MPlusProtocol;
- (void)FiveBProtocol;
- (void)RBProtocol;
- (void)UnknownProtocol;

@end

#endif /* _SERIAL_POINTING_DEVICE_H */
