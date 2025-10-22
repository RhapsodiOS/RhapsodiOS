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
 * SerialPointingDevice.m - Serial Mouse/Pointing Device Driver Implementation
 */

#import "SerialPointingDevice.h"

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/i386/directDevice.h>
#import <kernserv/prototypes.h>
#import <mach/message.h>

/* Mouse type names for logging */
static const char *mouseTypeNames[] = {
    "UNKNOWN",
    "M",
    "V3",
    "M",
    "W3",
    "C"
};

/* Protocol names for logging */
static const char *protocolList[] = {
    "UNKNOWN",
    "MS",
    "M+",
    "5B",
    "MM",
    "RB"
};

/* Global active flag to prevent multiple instances */
static BOOL active = NO;

/*
 * mainLoop - Thread function for processing serial mouse data
 */
static void mainLoop(id driver)
{
    [driver mainLoop:driver];
}

@implementation SerialPointingDevice

/*
 * detect - Detect presence of a serial pointing device
 */
- (BOOL)detect
{
    unsigned char byte;
    unsigned char version = 0;
    unsigned char supports9600 = 0;
    unsigned char supportsX = 0;
    unsigned char subtype = 0;
    unsigned char protocol = 0;
    unsigned int buttons = 0;
    unsigned char resolution = 0;
    int byteCount;
    int baudRate;

    if (verbose) {
        IOLog("%s: Attempting to detect mouse\n", [self name]);
    }

    /* Configure serial port parameters */
    [serialPortObject executeEvent:data:0x0B data:0x78];    // Set parameter
    [serialPortObject executeEvent:data:0x0F data:0x78];    // Set parameter
    [serialPortObject executeEvent:data:0x1B data:0x50];    // Set parameter
    [serialPortObject executeEvent:data:0x1F data:0x50];    // Set parameter
    [serialPortObject executeEvent:data:0x13 data:0x28];    // Set parameter
    [serialPortObject executeEvent:data:0x17 data:0x28];    // Set parameter
    [serialPortObject executeEvent:data:0x33 data:0x960];   // Set baud rate (2400 baud)
    [serialPortObject executeEvent:data:0x3B data:0x0E];    // Set parameter
    [serialPortObject executeEvent:data:0x43 data:1];       // Set parameter
    [serialPortObject executeEvent:data:0xF3 data:2];       // Set parameter
    [serialPortObject executeEvent:data:0x53 data:0];       // Set parameter

    /* Configure port state */
    [serialPortObject setState:mask:6 mask:6];              // Set DTR and RTS
    IOSleep(100);
    [serialPortObject setState:mask:0 mask:4];              // Clear RTS
    [serialPortObject executeEvent:data:5 data:1];          // Enable receiver
    [serialPortObject setState:mask:1 mask:1];              // Set state
    IOSleep(100);
    [serialPortObject setState:mask:4 mask:4];              // Set RTS
    IOSleep(300);

    /* Listen for identification bytes */
    if (verbose) {
        IOLog("%s: Listening ... {", [self name]);
    }

    /* Look for Microsoft mouse signature "M3" */
    while ([self getByte:&byte sleep:NO]) {
        byte &= 0x7F;

        if (mouseType == 0 && byte == 'M') {
            /* Found 'M' - could be Microsoft mouse */
            mouseType = 1;
            protocolType = 1;
        } else if (mouseType == 1 && byte == '3') {
            /* Found '3' after 'M' - confirmed Microsoft mouse */
            mouseType = 2;
        }
    }

    if (verbose) {
        IOLog("}\n");
    }

    /* If no Microsoft mouse detected, try other protocols */
    if (mouseType == 0) {
        /* Try different baud rates to detect Mouse Systems mouse */
        [serialPortObject executeEvent:data:0x3B data:0x10];

        baudRate = 1200;
        while (baudRate < 9600) {
            [serialPortObject executeEvent:data:0x33 data:(baudRate * 2)];
            [serialPortObject enqueueEvent:data:sleep:0x55 data:0x73 sleep:0];
            IOSleep(100);

            if ([self getByte:&byte sleep:NO]) {
                if ((byte & 0xBF) == 0x0F) {
                    /* Mouse Systems mouse detected */
                    mouseType = 5;
                    break;
                }
            }

            baudRate *= 2;
        }

        /* Configure Mouse Systems mouse if detected */
        if (mouseType == 5) {
            [serialPortObject enqueueEvent:data:sleep:0x55 data:0x55 sleep:0];
            [serialPortObject enqueueEvent:data:sleep:0x55 data:0x52 sleep:0];
            protocolType = 3;
        }
    } else {
        /* Send "*?" command to query mouse capabilities */
        if (verbose) {
            IOLog("%s: Sending *? Command {", [self name]);
        }

        [serialPortObject enqueueEvent:data:sleep:0x55 data:'*' sleep:0];
        [serialPortObject enqueueEvent:data:sleep:0x55 data:'?' sleep:0];
        IOSleep(200);

        /* Parse the response */
        byteCount = 0;
        while ([self getByte:&byte sleep:NO] && (byteCount < 4)) {
            int index = byteCount;

            /* Check for sync byte (bit 6 set) */
            if ((byte & 0x40) != 0) {
                index = 0;
            }

            byteCount = index + 1;

            switch (index) {
                case 0:
                    /* First byte: version */
                    if ((byte & 0x40) == 0) {
                        byteCount = 0;
                    } else {
                        version = byte & 0x3F;
                    }
                    break;

                case 1:
                    /* Second byte: capabilities */
                    supports9600 = (byte >> 4) & 1;
                    supportsX = (byte >> 3) & 1;
                    subtype = byte & 7;
                    break;

                case 2:
                    /* Third byte: more capabilities */
                    buttons = (byte & 0x38) >> 3;
                    protocol = byte & 7;
                    break;

                case 3:
                    /* Fourth byte: resolution */
                    resolution = byte & 0x3F;

                    /* Determine mouse type based on response */
                    if (mouseType == 1) {
                        mouseType = 3;  // Logitech
                    } else {
                        mouseType = 4;  // IntelliMouse
                    }

                    if (verbose) {
                        IOLog("[v%d, 9600=%s, x=%s, sub=%d, prot=%d, buttons=%d, res=%02x]",
                              version,
                              supports9600 ? "YES" : "NO",
                              supportsX ? "YES" : "NO",
                              subtype,
                              protocol,
                              buttons,
                              resolution);
                    }
                    break;
            }
        }

        if (verbose) {
            IOLog("}\n");
        }
    }

    /* Disable receiver if no mouse detected */
    if (mouseType == 0) {
        [serialPortObject executeEvent:data:5 data:0];
    }

    return (mouseType != 0);
}

/*
 * free - Clean up and free the device
 */
- free
{
    if (verbose) {
        IOLog("SerialPointingDevice: Instance being free'd.\n");
    }

    /* Clear global active flag */
    active = NO;

    /* Release serial port if acquired */
    if (serialPortObject != nil) {
        [serialPortObject release];
        serialPortObject = nil;
    }

    /* Call superclass free */
    return [super free];
}

/*
 * mouseInit: - Initialize the serial mouse/pointing device
 */
- (IOReturn)mouseInit:(IODeviceDescription *)deviceDescription
{
    IOConfigTable *configTable;
    const char *portDeviceName;
    const char *verboseStr;
    const char *invertedStr;
    const char *resolutionStr;
    IOReturn ret;
    int i;

    /* Check for duplicate instance */
    if (active) {
        IOLog("SerialPointingDevice: Duplicate instance aborting.\n");
        return IO_R_BUSY;
    }

    /* Initialize instance variables */
    active = NO;
    verbose = NO;
    inverted = NO;
    resolution = 0;
    serialPortObject = nil;
    mouseType = 0;
    protocolType = 0;
    mainLoopThread = NULL;

    /* Set device name and kind */
    [self setName:"SerialPointingDevice"];
    [self setDeviceKind:"PointingDevice"];

    /* Get configuration table */
    configTable = [[self deviceDescription] configTable];
    if (configTable == nil) {
        IOLog("%s: Missing configuration table.\n", [self name]);
        return IO_R_INVALID_ARG;
    }

    /* Check for verbose mode */
    verboseStr = [configTable valueForStringKey:"Verbose"];
    if (verboseStr != NULL) {
        verbose = YES;
        IOLog("%s: Verbose mode active.\n", [self name]);
    }

    /* Get serial port device name */
    portDeviceName = [configTable valueForStringKey:"Port Device"];
    if (portDeviceName == NULL) {
        IOLog("%s: No Serial Port specified in config table.\n", [self name]);
        return IO_R_INVALID_ARG;
    }

    /* Get the serial port object */
    ret = IOGetObjectForDeviceName(portDeviceName, &serialPortObject);
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: \"%s\" is not a registered port.\n", [self name], portDeviceName);
        return IO_R_NOT_FOUND;
    }

    /* Acquire the serial port */
    ret = [serialPortObject acquire:self];
    if (ret != IO_R_SUCCESS) {
        serialPortObject = nil;
        IOLog("%s: Serial Port \"%s\" is already in use.\n", [self name], portDeviceName);
        return IO_R_BUSY;
    }

    if (verbose) {
        IOLog("%s: Acquired port \"%s\".\n", [self name], portDeviceName);
    }

    /* Get inverted setting */
    invertedStr = [configTable valueForStringKey:"Inverted"];
    if ((invertedStr == NULL) || ((*invertedStr != 'y') && (*invertedStr != 'Y'))) {
        inverted = NO;
    } else {
        inverted = YES;
    }

    if (verbose) {
        IOLog("%s: Invert = %s\n", [self name], inverted ? "YES" : "NO");
    }

    /* Get resolution setting */
    resolutionStr = [configTable valueForStringKey:"Resolution"];
    if (resolutionStr == NULL) {
        resolution = 200;
        IOLog("%s: No resolution in config table. Defaulting to %d\n", [self name], 200);
    } else {
        resolution = atoi(resolutionStr);
        if (verbose) {
            IOLog("%s: Resolution = %d\n", [self name], resolution);
        }
    }

    /* Set active flag */
    active = YES;

    /* Try to detect the mouse (up to 3 attempts with 500ms delay) */
    for (i = 0; i < 3; i++) {
        if ([self detect]) {
            break;
        }
        IOSleep(500);
    }

    /* Check if mouse was detected */
    if (mouseType != 0) {
        IOLog("%s: Detected mouse type %s on serial port %s.\n",
              [self name], mouseTypeNames[mouseType], portDeviceName);

        /* Fork the main loop thread */
        mainLoopThread = (void *)IOForkThread((IOThreadFunc)mainLoop, self);

        return IO_R_SUCCESS;
    }

    /* No mouse detected */
    IOLog("%s: No mouse detected on serial port %s.\n", [self name], portDeviceName);
    return IO_R_NOT_FOUND;
}

/*
 * getIntValues:forParameter:count: - Get integer parameter values
 */
- (IOReturn)getIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count
{
    int i;
    BOOL match;
    const char *param;
    const char *target;
    unsigned int value;

    /* Check for "Resolution" parameter (11 characters) */
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
        /* Return resolution value */
        value = resolution;
    } else {
        /* Check for "Inverted" parameter (9 characters) */
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
            /* Unknown parameter */
            return IO_R_INVALID_ARG;
        }

        /* Return inverted flag */
        value = (unsigned int)inverted;
    }

    *parameterArray = value;
    return IO_R_SUCCESS;
}

/*
 * setIntValues:forParameter:count: - Set integer parameter values
 */
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

    /* Check for "Resolution" parameter (11 characters) */
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
        /* Set resolution value */
        resolution = *parameterArray;

        /* Get the resolution back and update the event port */
        resolutionValue = [self getResolution];
        [mouseEventPort setResolution:resolutionValue];

        if (verbose) {
            IOLog("%s: Resolution = %d\n", [self name], resolution);
        }

        return IO_R_SUCCESS;
    }

    /* Check for "Inverted" parameter (9 characters) */
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
        /* Unknown parameter */
        return IO_R_INVALID_ARG;
    }

    /* Set inverted value */
    invertedValue = *(char *)parameterArray;
    inverted = invertedValue;
    [mouseEventPort setInverted:invertedValue];

    if (verbose) {
        IOLog("%s: Invert = %s\n", [self name], inverted ? "YES" : "NO");
    }

    return IO_R_SUCCESS;
}

/*
 * getResolution - Get the current resolution setting
 */
- (unsigned int)getResolution
{
    return resolution;
}

/*
 * setEventTarget: - Set the event target for mouse events
 */
- (void)setEventTarget:(id)target
{
    BOOL result;

    /* Call superclass method first */
    result = [super setEventTarget:target];

    /* If successful, save the target */
    if (result) {
        mouseEventPort = target;
    }

    return result;
}

/*
 * getByte:sleep: - Read a byte from the serial port
 */
- (BOOL)getByte:(unsigned char *)byte sleep:(BOOL)shouldSleep
{
    IOReturn ret;
    int eventType;
    unsigned char data;

    /* Loop while active */
    while (active) {
        /* Try to dequeue an event from the serial port */
        ret = [serialPortObject dequeueEvent:&eventType data:&data sleep:shouldSleep];

        if (ret != IO_R_SUCCESS) {
            /* Error occurred */
            return NO;
        }

        if (eventType == 0x55) {
            /* Event type 0x55 = received data byte */
            *byte = data;
            return YES;
        }

        if (eventType == 0) {
            /* No data available */
            return NO;
        }

        /* Other event types - continue looping */
    }

    /* Driver is no longer active */
    return NO;
}

/*
 * mainLoop: - Main thread loop for processing serial mouse data
 */
- (void)mainLoop:(id)arg
{
    if (verbose) {
        IOLog("%s: Main thread started.\n", [self name]);
    }

    /* Main loop - runs while driver is active */
    while (active) {
        /* If no mouse detected yet, try to detect */
        if (mouseType == 0) {
            if (![self detect]) {
                /* Detection failed, sleep and retry */
                IOSleep(10000);  // Sleep 10 seconds
                continue;
            }
        }

        /* Mouse detected - log the type and protocol */
        if (verbose) {
            IOLog("%s: Detected Mouse Type %s, %s Protocol.\n",
                  [self name],
                  mouseTypeNames[mouseType],
                  protocolList[protocolType]);
        }

        /* Dispatch to appropriate protocol handler based on protocolType */
        switch (protocolType) {
            case 1:
                [self MSProtocol];
                break;
            case 2:
                [self MPlusProtocol];
                break;
            case 3:
                [self FiveBProtocol];
                break;
            case 4:
                [self MMProtocol];
                break;
            case 5:
                [self RBProtocol];
                break;
            default:
                [self UnknownProtocol];
                break;
        }
    }

    if (verbose) {
        IOLog("SerialPorintingDevice: Main thread terminated.\n");
    }
}

/*
 * MSProtocol - Handle Microsoft Serial Mouse protocol
 */
- (void)MSProtocol
{
    unsigned char byte;
    unsigned char maskedByte;
    unsigned char leftButton = 0;
    unsigned char rightButton = 0;
    unsigned int xDelta = 0;
    unsigned int yDelta = 0;
    unsigned int lastTimestampLow = 0;
    unsigned int lastTimestampHigh = 0;
    unsigned int currentTimestampLow;
    unsigned int currentTimestampHigh;
    int byteIndex = 0;
    BOOL shouldDispatch;

    if (verbose) {
        IOLog("%s: MSProtocol started\n", [self name]);
    }

    /* Main protocol loop - processes 3-byte packets */
    while (1) {
        /* Read next byte (blocking) */
        if (![self getByte:&byte sleep:YES]) {
            return;
        }

        /* Mask off high bit (7-bit data) */
        maskedByte = byte & 0x7F;

        /* Check for sync byte (bit 6 set) - resets to byte 0 */
        if ((byte & 0x40) != 0) {
            byteIndex = 0;
        }

        /* Process based on byte position */
        switch (byteIndex) {
            case 0:
                /* First byte: sync byte with button states and high movement bits */
                IOGetTimestamp((ns_time_t *)&lastTimestampLow);

                /* Must have bit 6 set to be valid sync byte */
                if ((byte & 0x40) == 0) {
                    byteIndex = 0;
                    continue;
                }

                /* Extract button states */
                leftButton = (byte >> 5) & 1;
                rightButton = (byte >> 4) & 1;

                /* Extract high bits of Y movement (bits 3-2, shift left 4) */
                yDelta = (byte & 0x0C) << 4;

                /* Extract high bits of X movement (bits 1-0, shift left 6) */
                xDelta = (byte & 0x03) << 6;

                byteIndex++;
                break;

            case 1:
                /* Second byte: low 6 bits of X movement */
                xDelta = xDelta | (maskedByte & 0x3F);
                byteIndex++;
                break;

            case 2:
                /* Third byte: low 6 bits of Y movement, complete packet */
                IOGetTimestamp((ns_time_t *)&currentTimestampLow);

                yDelta = yDelta | (maskedByte & 0x3F);

                /* Build event structure */
                mouseEvent.timestamp_low = lastTimestampLow;
                mouseEvent.timestamp_high = lastTimestampHigh;

                /* Set button states */
                mouseEvent.buttons = (mouseEvent.buttons & 0xFE) | (leftButton != 0);
                mouseEvent.buttons = (mouseEvent.buttons & 0xFD) | ((rightButton != 0) * 2);
                mouseEvent.buttons = mouseEvent.buttons & 3;

                /* Set deltas (X as-is, Y negated) */
                mouseEvent.deltaX = (char)xDelta;
                mouseEvent.deltaY = -(char)yDelta;

                /* Dispatch event if we have a target and timing is good */
                if (mouseEventPort != nil) {
                    /* Check timestamp ordering and delta */
                    shouldDispatch = NO;

                    if (currentTimestampHigh == lastTimestampHigh) {
                        /* Same high timestamp - check low timestamp delta */
                        if (currentTimestampLow - lastTimestampLow < 40000000) {
                            shouldDispatch = YES;
                        }
                    } else if (currentTimestampHigh > lastTimestampHigh) {
                        /* High timestamp advanced - always dispatch */
                        shouldDispatch = YES;
                    }

                    if (shouldDispatch) {
                        [mouseEventPort dispatchPointerEvent:&mouseEvent];
                    }
                }

                /* Reset for next packet */
                byteIndex = 0;
                break;

            default:
                byteIndex = 0;
                break;
        }
    }
}

/*
 * MMProtocol - Handle Mouse Systems protocol
 */
- (void)MMProtocol
{
    /* Disable receiver */
    [serialPortObject executeEvent:data:5 data:0];

    /* Mark driver as inactive */
    active = NO;
}

/*
 * MPlusProtocol - Handle Microsoft IntelliMouse protocol
 */
- (void)MPlusProtocol
{
    /* Delegate to MSProtocol - IntelliMouse uses same protocol */
    [self MSProtocol];
}

/*
 * FiveBProtocol - Handle 5-byte protocol (Logitech)
 */
- (void)FiveBProtocol
{
    unsigned char byte;
    unsigned char leftButton = 0;
    unsigned char rightButton = 0;
    unsigned char savedByte = 0;
    unsigned int lastTimestampLow = 0;
    unsigned int lastTimestampHigh = 0;
    unsigned int currentTimestampLow;
    unsigned int currentTimestampHigh;
    int byteIndex = 0;
    BOOL shouldDispatch;

    if (verbose) {
        IOLog("%s: FiveBProtocol started\n", [self name]);
    }

    /* Main protocol loop */
    while (1) {
        /* Read next byte (blocking) */
        if (![self getByte:&byte sleep:YES]) {
            return;
        }

        switch (byteIndex) {
            case 0:
                /* First byte: sync byte with button states */
                IOGetTimestamp((ns_time_t *)&lastTimestampLow);

                /* Check for sync byte pattern (bits 7-3 = 10000) */
                if ((byte & 0xF8) == 0x80) {
                    /* Extract button states (inverted) */
                    leftButton = ((byte >> 2) ^ 1) & 1;
                    rightButton = (byte ^ 1) & 1;
                    byteIndex++;
                }
                break;

            case 1:
            case 3:
                /* Bytes 2 and 4: store for later use */
                savedByte = byte;
                byteIndex++;
                break;

            case 2:
            case 4:
                /* Bytes 3 and 5: complete packet, dispatch event */
                IOGetTimestamp((ns_time_t *)&currentTimestampLow);

                /* Build event structure */
                mouseEvent.timestamp_low = lastTimestampLow;
                mouseEvent.timestamp_high = lastTimestampHigh;

                /* Set button states */
                mouseEvent.buttons = (mouseEvent.buttons & 0xFE) | (leftButton != 0);
                mouseEvent.buttons = (mouseEvent.buttons & 0xFD) | ((rightButton != 0) * 2);
                mouseEvent.buttons = mouseEvent.buttons & 3;

                /* Set deltas */
                mouseEvent.deltaX = savedByte;
                mouseEvent.deltaY = byte;

                /* Dispatch event if we have a target and timing is good */
                if (mouseEventPort != nil) {
                    /* Check timestamp ordering and delta */
                    shouldDispatch = NO;

                    if (currentTimestampHigh == lastTimestampHigh) {
                        /* Same high timestamp - check low timestamp delta */
                        if (currentTimestampLow - lastTimestampLow < 40000000) {
                            shouldDispatch = YES;
                        }
                    } else if (currentTimestampHigh > lastTimestampHigh) {
                        /* High timestamp advanced - always dispatch */
                        shouldDispatch = YES;
                    }

                    if (shouldDispatch) {
                        [mouseEventPort dispatchPointerEvent:&mouseEvent];
                    }
                }

                /* Update last timestamp */
                lastTimestampLow = currentTimestampLow;
                lastTimestampHigh = currentTimestampHigh;

                /* After byte 5, reset to start */
                if (byteIndex == 4) {
                    byteIndex = 0;
                } else {
                    byteIndex++;
                }
                break;

            default:
                byteIndex++;
                break;
        }
    }
}

/*
 * RBProtocol - Handle Relative Byte protocol
 */
- (void)RBProtocol
{
    /* Disable receiver */
    [serialPortObject executeEvent:data:5 data:0];

    /* Mark driver as inactive */
    active = NO;
}

/*
 * UnknownProtocol - Handle unknown/undetected protocol
 */
- (void)UnknownProtocol
{
    /* Disable receiver */
    [serialPortObject executeEvent:data:5 data:0];

    /* Mark driver as inactive */
    active = NO;
}

@end
