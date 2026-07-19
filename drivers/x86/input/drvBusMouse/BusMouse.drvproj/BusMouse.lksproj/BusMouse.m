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
 */

#import "BusMouse.h"

#import <machdep/i386/io_inline.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/i386/directDevice.h>
#import <kernserv/prototypes.h>
#import <mach/message.h>
#import <libkern/libkern.h>

#define LOCK()
#define UNLOCK()

/* Forward declarations for IODirectDevice methods */
@interface IODirectDevice (BusMousePrivate)
- (void)dispatchPointerEvent:(void *)eventData;
- (void)setResolution:(unsigned int)res;
- (void)setInverted:(BOOL)flag;
@end

/* Interrupt message structure */
typedef struct {
    msg_header_t header;
    msg_type_t type;
    int msgId;
} interrupt_msg_t;

/* Global state variables */
static unsigned int lastLeftButton = 0;
static unsigned int lastRightButton = 0;
static unsigned int higherLevelsBusy = 0;
static unsigned int summedEvent = 0;
static char accumulatedDeltaX = 0;
static char accumulatedDeltaY = 0;
static unsigned int ioPortCount = 0;

/* Event data structure */
static struct {
    unsigned int timestamp_high;
    unsigned int timestamp_low;
    unsigned char buttons;
    char deltaX;
    char deltaY;
} mouseEvent;

/* Detect IRQ from bus mouse board */
static unsigned int GetIRQFromBoard(void)
{
    unsigned char previousRead;
    unsigned char currentRead;
    unsigned char changedBits;
    unsigned int uVar;
    int iterations;

    changedBits = 0;
    previousRead = inb(0x23e);
    iterations = 0xf000;

    do {
        currentRead = inb(0x23e);
        changedBits = changedBits | (previousRead ^ currentRead);
        iterations = iterations - 1;
        previousRead = currentRead;
    } while (0 < iterations);

    if ((changedBits & 1) == 0) {
        if ((changedBits & 2) == 0) {
            if ((changedBits & 4) == 0) {
                uVar = 0;
                if ((changedBits & 8) != 0) {
                    uVar = 2;
                }
            } else {
                uVar = 3;
            }
        } else {
            uVar = 4;
        }
    } else {
        uVar = 5;
    }

    return uVar;
}

/* Mouse interrupt handler - reads hardware and posts events */
static unsigned int MouseIntHandler(unsigned int param_1, unsigned int param_2)
{
    unsigned char buttonData;
    unsigned char xLowData;
    unsigned char yLowData;
    unsigned char xHighData;
    unsigned char yHighData;
    unsigned int leftButton;
    unsigned int rightButton;
    unsigned int xMovement;
    int yMovement;
    unsigned int returnValue;
    char yDelta;

    /* Read button state */
    outb(0x23e, 0x80);
    LOCK();
    UNLOCK();
    outb(0x23e, 0x80);
    LOCK();
    UNLOCK();
    buttonData = inb(0x23c);

    leftButton = (buttonData >> 7) ^ 1;
    rightButton = ~((unsigned int)(buttonData >> 5)) & 1;

    /* Read X movement */
    outb(0x23e, 0xa0);
    LOCK();
    UNLOCK();
    xLowData = inb(0x23c);

    /* Read Y movement - low nibble */
    outb(0x23e, 0xc0);
    LOCK();
    UNLOCK();
    yLowData = inb(0x23c);

    /* Read Y movement - high nibble */
    outb(0x23e, 0xe0);
    LOCK();
    UNLOCK();
    yHighData = inb(0x23c);

    xMovement = ((xLowData & 0xf) << 4) | (buttonData & 0xf);
    yMovement = -(int)(((yHighData & 0xf) << 4) | (yLowData & 0xf));

    /* Reset to default state */
    outb(0x23e, 0);
    LOCK();
    ioPortCount = ioPortCount + 6;
    UNLOCK();

    returnValue = 0;

    /* Check if we have any changes */
    if ((xMovement != 0) || (yMovement != 0) ||
        (lastLeftButton != leftButton) || (lastRightButton != rightButton)) {

        yDelta = (char)yMovement;

        if (higherLevelsBusy == 0) {
            /* Not busy - send event immediately */
            mouseEvent.buttons = (mouseEvent.buttons & 0xfc) | (unsigned char)leftButton;
            mouseEvent.buttons = mouseEvent.buttons | ((char)rightButton * 2);
            lastRightButton = rightButton;
            lastLeftButton = leftButton;

            IOGetTimestamp((ns_time_t *)&mouseEvent);

            mouseEvent.deltaX = (char)xMovement + accumulatedDeltaX;
            mouseEvent.deltaY = accumulatedDeltaY + yDelta;

            higherLevelsBusy = 1;
            returnValue = IOSendInterrupt(param_1, param_2, IO_DEVICE_INTERRUPT_MSG);

            accumulatedDeltaX = 0;
            accumulatedDeltaY = 0;
            summedEvent = 0;
        } else {
            /* Busy - accumulate deltas */
            accumulatedDeltaX = accumulatedDeltaX + (char)xMovement;
            accumulatedDeltaY = accumulatedDeltaY + yDelta;
            returnValue = xMovement;
        }
    }

    return returnValue;
}

/* Thread function for handling interrupts */
static void BusMouseThread(id driver)
{
    port_t interruptPort;
    interrupt_msg_t msg;
    kern_return_t ret;

    /* Get the interrupt port from the driver instance */
    interruptPort = (port_t)[driver interruptPort];

    /* Loop forever, processing interrupt messages */
    while (1) {
        /* Set up message buffer */
        msg.header.msg_size = sizeof(interrupt_msg_t);
        msg.header.msg_local_port = interruptPort;

        /* Receive interrupt message */
        ret = msg_receive(&msg.header, MSG_OPTION_NONE, 0);
        if (ret != KERN_SUCCESS) {
            IOLog("BusMouse: msg_receive failed: %d\n", ret);
            continue;
        }

        /* Check if this is an interrupt message */
        if (msg.msgId == IO_DEVICE_INTERRUPT_MSG) {
            /* Verify the port matches */
            if (msg.header.msg_local_port == interruptPort) {
                /* Call the interrupt handler */
                [driver interruptHandler];
            } else {
                IOLog("BusMouse: interrupt port mismatch\n");
            }
        }
    }
}

@implementation BusMouse

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return NO;
}

- free
{
    return [super free];
}

- (BOOL)validConfiguration:(IODeviceDescription *)deviceDescription
{
    unsigned char signature;
    unsigned int configIRQ;
    unsigned int detectedIRQ;

    /* Initialize controller */
    outb(0x23f, 0x91);
    LOCK();
    ioPortCount = ioPortCount + 1;
    UNLOCK();

    /* Delay for hardware to settle (30ms) */
    IODelay(30);

    /* Write signature */
    outb(0x23d, 0xa5);
    LOCK();
    ioPortCount = ioPortCount + 1;
    UNLOCK();

    /* Read back signature */
    signature = inb(0x23d);

    if (signature == 0xa5) {
        /* Signature matches - check IRQ */
        configIRQ = [deviceDescription interrupt];
        detectedIRQ = GetIRQFromBoard();

        if (configIRQ == detectedIRQ) {
            return YES;
        }

        IOLog("BusMouse: IRQ mismatch - config: %d, detected: %d\n", configIRQ, detectedIRQ);
    } else {
        IOLog("BusMouse: Bus mouse not detected (signature mismatch)\n");
    }

    return NO;
}

- (IOReturn)mouseInit:(IODeviceDescription *)deviceDescription
{
    BOOL valid;
    IOConfigTable *configTable;
    const char *invertedStr;
    const char *resolutionStr;

    /* Validate configuration */
    valid = [self validConfiguration:deviceDescription];
    if (!valid) {
        return IO_R_INVALID_ARG;
    }

    /* Set device name and kind */
    [self setName:"BusMouse"];
    [self setDeviceKind:"BusMouse"];

    /* Get config table */
    configTable = [[self deviceDescription] configTable];
    if (configTable == nil) {
        IOLog("BusMouse: No config table\n");
        return IO_R_INVALID_ARG;
    }

    /* Read "Inverted" parameter */
    invertedStr = [configTable valueForStringKey:"Inverted"];
    if ((invertedStr == NULL) || ((*invertedStr != 'y') && (*invertedStr != 'Y'))) {
        inverted = NO;
    } else {
        inverted = YES;
    }

    /* Read "Resolution" parameter */
    resolutionStr = [configTable valueForStringKey:"Resolution"];
    if (resolutionStr == NULL) {
        resolution = 400;
        IOLog("BusMouse: Using default resolution %d\n", 400);
    } else {
        resolution = strtoul(resolutionStr, NULL, 0);
    }

    /* Initialize global state */
    higherLevelsBusy = 0;
    accumulatedDeltaY = 0;
    accumulatedDeltaX = 0;
    summedEvent = 0;
    mouseEvent.timestamp_high = 0;
    lastLeftButton = 0xffffffff;
    lastRightButton = 0xffffffff;

    /* Enable interrupts */
    [self enableAllInterrupts];

    /* Initialize hardware */
    outb(0x23e, 0);
    LOCK();
    ioPortCount = ioPortCount + 1;
    UNLOCK();

    /* Fork interrupt handler thread */
    IOForkThread((IOThreadFunc)BusMouseThread, self);

    IOLog("BusMouse: Initialized successfully\n");

    return IO_R_SUCCESS;
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)arg
      forInterrupt:(unsigned int)localInterrupt
{
    *handler = (IOInterruptHandler)MouseIntHandler;
    *ipl = 3;
    *arg = (void *)0xdeadbeef;
    return YES;
}

- (void)interruptHandler
{
    if (mouseEventPort != nil) {
        [mouseEventPort dispatchPointerEvent:&mouseEvent];
    }
    higherLevelsBusy = 0;
}

- (IOReturn)getIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count
{
    int i;
    BOOL match;
    const char *param;
    const char *target;
    unsigned int value;

    /* Check for "Resolution" parameter */
    i = 11;
    match = YES;
    param = parameterName;
    target = "Resolution";
    do {
        if (i == 0) break;
        i = i - 1;
        match = (*param == *target);
        param = param + 1;
        target = target + 1;
    } while (match);

    if (match) {
        value = resolution;
    } else {
        /* Check for "Inverted" parameter */
        i = 9;
        match = YES;
        param = parameterName;
        target = "Inverted";
        do {
            if (i == 0) break;
            i = i - 1;
            match = (*param == *target);
            param = param + 1;
            target = target + 1;
        } while (match);

        if (!match) {
            return IO_R_INVALID_ARG;
        }
        value = (unsigned int)inverted;
    }

    *parameterArray = value;
    return IO_R_SUCCESS;
}

- (IOReturn)setIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned)count
{
    int i;
    BOOL match;
    const char *param;
    const char *target;
    unsigned int resolutionValue;
    char invertedValue;

    /* Check for "Resolution" parameter */
    i = 11;
    match = YES;
    param = parameterName;
    target = "Resolution";
    do {
        if (i == 0) break;
        i = i - 1;
        match = (*param == *target);
        param = param + 1;
        target = target + 1;
    } while (match);

    if (match) {
        resolution = *parameterArray;
        resolutionValue = [self getResolution];
        [mouseEventPort setResolution:resolutionValue];
    } else {
        /* Check for "Inverted" parameter */
        i = 9;
        match = YES;
        param = parameterName;
        target = "Inverted";
        do {
            if (i == 0) break;
            i = i - 1;
            match = (*param == *target);
            param = param + 1;
            target = target + 1;
        } while (match);

        if (!match) {
            return IO_R_INVALID_ARG;
        }

        invertedValue = *(char *)parameterArray;
        inverted = invertedValue;
        [mouseEventPort setInverted:invertedValue];
    }

    return IO_R_SUCCESS;
}

- (unsigned int)getResolution
{
    return resolution;
}

@end
