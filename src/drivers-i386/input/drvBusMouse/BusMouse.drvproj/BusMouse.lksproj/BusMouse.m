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
 * BusMouse.m - ISA Bus Mouse Driver Implementation
 *
 * The board occupies four ports.  0x23E is the command/control port: the
 * driver writes a selector byte there and reads the selected nibble back
 * from the data port 0x23C.  0x23D and 0x23F are used only by the probe.
 */

#import "BusMouse.h"

#import <machdep/i386/io_inline.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/i386/directDevice.h>
#import <kernserv/prototypes.h>
#import <mach/message.h>

/*
 * us_spin() busy-waits for a calibrated number of microseconds.  It has no
 * prototype in any installed header; <bsd/i386/param.h> only wraps it in the
 * DELAY() macro, which is not reachable from a driver project.
 */
extern void us_spin(unsigned int us);

/*
 * Global state.  The declaration order below is the order these objects
 * occupy in __DATA,__bss.  None of them carries an initializer: an explicitly
 * initialized static lands in __DATA,__data even when the initializer is zero.
 *
 * A PCPointerEvent is 12 bytes: an 8-byte timestamp followed by a 4-byte
 * union whose buf[0..2] hold the button state and the X and Y deltas.
 */
static int higherLevelsBusy;        /* 1 while an event is in flight */
static PCPointerEvent event;        /* Event handed to the event target */
static PCPointerEvent summedEvent;  /* Deltas accumulated while one is in flight */
static int lastRightButton;         /* Previous right button state, -1 when unknown */
static int lastLeftButton;          /* Previous left button state, -1 when unknown */

/*
 * GetIRQFromBoard - work out which IRQ line the board is strapped to.
 *
 * The interrupt request lines are visible in the low nibble of the control
 * port.  Sample the port 0xF000 times and accumulate the bits that ever
 * changed state; the lowest one that toggled names the IRQ.
 */
unsigned int GetIRQFromBoard(void)
{
    unsigned char previous;
    unsigned char current;
    unsigned char changed;
    unsigned int irq;
    unsigned char lowBits;
    int count;

    changed = 0;
    previous = inb(0x23e);
    count = 0xf000;

    do {
	current = inb(0x23e);
	changed = changed | (previous ^ current);
	previous = current;
	count = count - 1;
    } while (count > 0);

    lowBits = changed & 0x0f;

    if (changed & 1) {
	irq = 5;
    } else if (lowBits & 2) {
	irq = 4;
    } else if (lowBits & 4) {
	irq = 3;
    } else {
	irq = 0;
	if (lowBits & 8) {
	    irq = 2;
	}
    }

    return irq;
}

@implementation BusMouse

- (BOOL)validConfiguration:(IODeviceDescription *)deviceDescription
{
    unsigned char signature;
    unsigned int configuredIRQ;
    unsigned int actualIRQ;

    /* Arm the board, give it 30 milliseconds to settle, then write and read
     * back a signature byte.
     */
    outb(0x23f, 0x91);
    us_spin(30000);
    outb(0x23d, 0xa5);
    signature = inb(0x23d);

    if (signature != 0xa5) {
	IOLog("Bus Mouse : No bus mouse installed.\n");
    } else {
	configuredIRQ = [deviceDescription interrupt];
	actualIRQ = GetIRQFromBoard();
	if (configuredIRQ == actualIRQ) {
	    return YES;
	}
	IOLog("Bus Mouse : configured IRQ (%d) doesn't equal actual IRQ (%d)\n",
	      configuredIRQ, actualIRQ);
    }

    return NO;
}

/*
 * MouseIntHandler - low level interrupt handler.
 *
 * Both buttons are active low: left is bit 7 of the first data read, right is
 * bit 5.  X is split across two reads, its low nibble arriving with the button
 * byte; Y arrives as two nibbles and is negated.
 */
static void MouseIntHandler(void *identity, void *state, unsigned int arg)
{
    unsigned char buttonByte;
    unsigned char xHigh;
    unsigned char yLow;
    unsigned char yHigh;
    unsigned int left;
    unsigned int right;
    unsigned int dx;
    int dy;

    outb(0x23e, 0x80);
    outb(0x23e, 0x80);
    buttonByte = inb(0x23c);

    left = ((unsigned int)(buttonByte >> 7)) ^ 1;
    right = ~((unsigned int)(buttonByte >> 5)) & 1;

    outb(0x23e, 0xa0);
    xHigh = inb(0x23c);
    dx = ((xHigh & 0x0f) << 4) | (buttonByte & 0x0f);

    outb(0x23e, 0xc0);
    yLow = inb(0x23c) & 0x0f;

    outb(0x23e, 0xe0);
    yHigh = inb(0x23c);
    dy = -(int)(((yHigh & 0x0f) << 4) | yLow);

    outb(0x23e, 0x00);

    if (dx != 0 || dy != 0 ||
	lastLeftButton != left || lastRightButton != right) {

	if (higherLevelsBusy) {
	    /* An event is still in flight: fold the movement into the
	     * accumulator and leave the button trackers alone.
	     */
	    summedEvent.data.buf[1] += dx;
	    summedEvent.data.buf[2] += dy;
	} else {
	    event.data.values.leftButton = left;
	    event.data.values.rightButton = right;
	    lastLeftButton = left;
	    lastRightButton = right;

	    IOGetTimestamp(&event.timeStamp);

	    event.data.buf[1] = dx + summedEvent.data.buf[1];
	    event.data.buf[2] = summedEvent.data.buf[2] + dy;

	    higherLevelsBusy = 1;
	    IOSendInterrupt(identity, state, IO_DEVICE_INTERRUPT_MSG);

	    summedEvent.data.buf[1] = 0;
	    summedEvent.data.buf[2] = 0;
	    summedEvent.timeStamp = 0;
	}
    }
}

- (void)interruptHandler
{
    if (target != nil) {
	[target dispatchPointerEvent:&event];
    }
    higherLevelsBusy = 0;
}

/*
 * BusMouseThread - the I/O thread.  Waits for the interrupt message the low
 * level handler posts and hands it to -interruptHandler.
 */
static void BusMouseThread(id driver)
{
    kern_return_t result;
    msg_header_t msg, *msgPtr = &msg;
    port_t busMousePort = [driver interruptPort];

    while (TRUE) {
	msgPtr->msg_size = sizeof(msg);
	msgPtr->msg_local_port = busMousePort;

	result = msg_receive(msgPtr, MSG_OPTION_NONE, 0);
	if (result != RCV_SUCCESS) {
	    IOLog("BusMouseThread: msg_receive() returned %d\n", result);
	    continue;
	}
	if (msgPtr->msg_id == IO_DEVICE_INTERRUPT_MSG) {
	    if (msgPtr->msg_local_port == busMousePort)
		[driver interruptHandler];
	    else
		IOLog("BusMouseThread: Bogus msg_local_port\n");
	}
    }
}

- (BOOL)mouseInit:(IODeviceDescription *)deviceDescription
{
    IOConfigTable *configTable;
    const char *invertedStr;
    const char *resolutionStr;

    if (![self validConfiguration:deviceDescription]) {
	return NO;
    }

    [self setName:"BusMouse"];
    [self setDeviceKind:"BusMouse"];

    configTable = [[self deviceDescription] configTable];
    if (configTable == nil) {
	IOLog("BusMouse mouseInit: no configuration table\n");
	return NO;
    }

    invertedStr = [configTable valueForStringKey:INVERTED];
    if ((invertedStr != NULL) &&
	((*invertedStr == 'y') || (*invertedStr == 'Y'))) {
	inverted = YES;
    } else {
	inverted = NO;
    }

    resolutionStr = [configTable valueForStringKey:RESOLUTION];
    if (resolutionStr == NULL) {
	resolution = 400;
	IOLog("BusMouse mouseInit: no resolution in config table.  Default is %d\n",
	      400);
    } else {
	resolution = PCPatoi((char *)resolutionStr);
    }

    higherLevelsBusy = 0;
    summedEvent.data.buf[2] = 0;
    summedEvent.data.buf[1] = 0;
    summedEvent.timeStamp = 0;
    lastLeftButton = -1;
    lastRightButton = -1;

    [self enableAllInterrupts];

    outb(0x23e, 0);

    IOForkThread((IOThreadFunc)BusMouseThread, self);

    IOLog("Bus mouse running\n");

    return YES;
}

- free
{
    return [super free];
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt
{
    *handler = (IOInterruptHandler)MouseIntHandler;
    *ipl = 3;
    *arg = 0xdeadbeef;
    return YES;
}

- (int)getResolution
{
    return resolution;
}

- (IOReturn)getIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count
{
    unsigned int value;

    if (strcmp(parameterName, RESOLUTION) == 0) {
	value = resolution;
    } else if (strcmp(parameterName, INVERTED) == 0) {
	value = (unsigned int)inverted;
    } else {
	return IO_R_UNSUPPORTED;
    }

    *parameterArray = value;
    return IO_R_SUCCESS;
}

- (IOReturn)setIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned)count
{
    unsigned int resolutionValue;
    char invertedValue;

    if (strcmp(parameterName, RESOLUTION) == 0) {
	resolution = *parameterArray;
	resolutionValue = [self getResolution];
	[target setResolution:resolutionValue];
    } else if (strcmp(parameterName, INVERTED) == 0) {
	invertedValue = *(char *)parameterArray;
	inverted = invertedValue;
	[target setInverted:invertedValue];
    } else {
	return IO_R_UNSUPPORTED;
    }

    return IO_R_SUCCESS;
}

@end
