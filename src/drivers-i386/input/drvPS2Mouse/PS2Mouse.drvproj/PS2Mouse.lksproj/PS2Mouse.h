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
 * PS2Mouse.h - PS/2 Mouse Driver
 */

#ifndef _PS2_MOUSE_H
#define _PS2_MOUSE_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/IODevice.h>
#import <driverkit/IOPower.h>
#import <driverkit/IOEventSource.h>
#import <kernserv/queue.h>
#import <bsd/dev/i386/PCPointer.h>
#import <bsd/dev/i386/PCPointerDefs.h>

/*
 * target (0x128), resolution (0x12c) and inverted (0x130) are inherited from
 * PCPointer, which also reserves 0x134-0x143.  This class adds only the two
 * ivars below, giving an instance size of 332 (0x14c).
 */
@interface PS2Mouse : PCPointer
{
@private
    id controller;         /* 0x144 */
    BOOL force_detection;  /* 0x148 - attach without probing for a mouse */
}

/* Configuration */
- (BOOL)isMousePresent;
- (BOOL)readConfigTable:(IOConfigTable *)configTable;
- (BOOL)mouseInit:(IODeviceDescription *)deviceDescription;
- (BOOL)initWithController:(id)controllerDevice;
- (void)resetMouse;

/* Parameters */
- (IOReturn)getIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count;

- (IOReturn)setIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned)count;

- (int)getResolution;

/* Interrupt handling */
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt;

- (void)interruptOccurred;

@end

#endif /* _PS2_MOUSE_H */
