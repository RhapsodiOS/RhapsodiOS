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
 * PS2Mouse.m - PS/2 Mouse Driver Implementation
 */

#import "PS2Mouse.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/KernDevice.h>

/* Global state variables for packet processing */
static int seqInProgress = 0;         /* Flag: new sequence is arriving while processing */
static int seqBeingProcessed = 0;     /* Flag: sequence is being processed */
static int indexInSequence = 0;       /* Current byte index in 3-byte packet (0-2) */
static char accumulatedDeltaX = 0;    /* Accumulated X movement */
static char accumulatedDeltaY = 0;    /* Accumulated Y movement */

/* Current packet data (being processed) */
static struct {
    unsigned char buttons;             /* Button states */
    char deltaX;                       /* X movement delta */
    char deltaY;                       /* Y movement delta */
} currentPacket;

/* Buffer for next packet (while current is being processed) */
static struct {
    unsigned char buttons;             /* Button states */
    char deltaX;                       /* X movement delta */
    char deltaY;                       /* Y movement delta */
} nextPacket;

/* Event timestamp */
static ns_time_t currentEventTime = 0;

/* Timestamp tracking for packet timeout detection */
static unsigned int lastTimeStamp_low = 0;
static int lastTimeStamp_high = 0;

/* PS/2 Mouse Commands */
#define PS2_CMD_RESET           0xFF
#define PS2_CMD_RESEND          0xFE
#define PS2_CMD_SET_DEFAULTS    0xF6
#define PS2_CMD_DISABLE         0xF5
#define PS2_CMD_ENABLE          0xF4
#define PS2_CMD_SET_SAMPLE_RATE 0xF3
#define PS2_CMD_GET_DEVICE_ID   0xF2
#define PS2_CMD_SET_REMOTE_MODE 0xF0
#define PS2_CMD_SET_WRAP_MODE   0xEE
#define PS2_CMD_RESET_WRAP_MODE 0xEC
#define PS2_CMD_READ_DATA       0xEB
#define PS2_CMD_SET_STREAM_MODE 0xEA
#define PS2_CMD_STATUS_REQUEST  0xE9
#define PS2_CMD_SET_RESOLUTION  0xE8

/* PS/2 Mouse Responses */
#define PS2_RESP_ACK            0xFA
#define PS2_RESP_SELF_TEST_OK   0xAA
#define PS2_RESP_DEVICE_ID      0x00

/* Timeout for packet sequence (250 milliseconds in nanoseconds) */
#define PACKET_TIMEOUT_NS       250000000

/* Controller function table
 * This is a pointer to a table of function pointers for accessing the PS/2 controller
 * Offsets (in bytes -> 32-bit pointers):
 *   0x14/4 = 5  : Send command to mouse (returns status)
 *   0x18/4 = 6  : Read mouse byte simple (returns byte value directly)
 *   0x1c/4 = 7  : Read mouse byte (takes pointer, returns status)
 */
typedef struct {
    void *reserved[5];
    int (*sendMouseCommand)(unsigned char cmd);      /* offset 0x14 */
    unsigned char (*readMouseByteSimple)(void);      /* offset 0x18 */
    int (*readMouseByte)(unsigned char *byte);       /* offset 0x1c */
} PS2ControllerFunctions;

static PS2ControllerFunctions *controllerFunctions = NULL;

/* Forward declarations */
static unsigned int PS2MouseIntHandler(unsigned int param_1, unsigned int param_2);

/**
 * PS2MouseIntHandler - Low-level interrupt handler for PS/2 mouse
 *
 * This function is called at interrupt level when the PS/2 mouse has data available.
 * It processes the 3-byte mouse packets, handles timeout detection, and buffers
 * packets when the higher-level handler is busy.
 *
 * PS/2 Mouse Packet Format (3 bytes):
 *   Byte 0: Y overflow | X overflow | Y sign | X sign | 1 | Middle | Right | Left
 *   Byte 1: X movement (8-bit signed)
 *   Byte 2: Y movement (8-bit signed)
 *
 * @param param_1 - Device parameter (passed to IOSendInterrupt)
 * @param param_2 - Context parameter (passed to IOSendInterrupt)
 * @return 0 on success, non-zero on error
 */
static unsigned int PS2MouseIntHandler(unsigned int param_1, unsigned int param_2)
{
    int status;
    unsigned char dataByte;
    ns_time_t currentTime;
    unsigned int timestamp_low;
    int timestamp_high;
    BOOL timeoutOccurred;

    /* Check if controller functions are available */
    if (controllerFunctions == NULL) {
        return 0;
    }

    /* Read a byte from the PS/2 controller
     * This calls the controller's readDataPort method or equivalent.
     * In the decompiled code, this was via a function table at offset 0x1c
     */
    status = controllerFunctions->readMouseByte(&dataByte);
    if (status == 0) {
        /* No data available */
        return 0;
    }

    /* Check for self-test passed response (0xAA) at start of sequence */
    if ((dataByte == PS2_RESP_SELF_TEST_OK) && (indexInSequence == 0)) {
        /* Mouse was reset - log message and re-enable data reporting */
        IOLog("PS/2 Mouse: Self-test passed response received - re-enabling\n");

        /* Flush/read any pending data and re-enable mouse data reporting
         * In decompiled code: func_list[0x18] = read byte, func_list[0x14] = send command
         */
        controllerFunctions->readMouseByteSimple();
        controllerFunctions->sendMouseCommand(PS2_CMD_ENABLE);
        return 0;
    }

    /* Get current timestamp for timeout detection */
    IOGetTimestamp((ns_time_t *)&timestamp_low);
    timestamp_high = *((int *)&timestamp_low + 1);

    /* Check if we're in the middle of a sequence */
    if (indexInSequence != 0) {
        /* Calculate if a timeout occurred since last byte
         * Timeout logic: check if high part changed (with carry detection)
         * or if enough time passed in low part (> 250ms)
         */
        timeoutOccurred = (timestamp_high - lastTimeStamp_high !=
                          (unsigned int)(timestamp_low < lastTimeStamp_low));

        if ((timeoutOccurred) ||
            ((!timeoutOccurred) && ((timestamp_low - lastTimeStamp_low) > PACKET_TIMEOUT_NS))) {
            /* Timeout detected - reset sequence */
            indexInSequence = 0;

            /* If this is another self-test response after timeout, re-enable */
            if (dataByte == PS2_RESP_SELF_TEST_OK) {
                IOLog("PS/2 Mouse: Self-test response after timeout - re-enabling\n");
                controllerFunctions->readMouseByteSimple();
                controllerFunctions->sendMouseCommand(PS2_CMD_ENABLE);
                return 0;
            }
        }
    }

    /* Update timestamp for next iteration */
    lastTimeStamp_low = timestamp_low;
    lastTimeStamp_high = timestamp_high;

    /* Process the byte based on current state */
    if (seqBeingProcessed == 0) {
        /* Not currently processing a sequence */
        if (seqInProgress == 0) {
            /* Not collecting a new sequence either - this is the normal path
             * Store byte in current packet buffer
             */
            ((unsigned char *)&currentPacket)[indexInSequence] = dataByte;
            indexInSequence++;

            if (indexInSequence < 3) {
                /* Need more bytes to complete packet */
                return 0;
            }

            /* Packet complete - accumulate movement deltas */
            currentPacket.deltaX = currentPacket.deltaX + accumulatedDeltaX;
            currentPacket.deltaY = currentPacket.deltaY + accumulatedDeltaY;
        } else {
            /* A new sequence was in progress while we were processing
             * Store byte in next packet buffer
             */
            ((unsigned char *)&nextPacket)[indexInSequence] = dataByte;
            indexInSequence++;

            if (indexInSequence != 3) {
                /* Need more bytes */
                return 0;
            }

            /* Next packet complete - copy to current and accumulate deltas */
            currentPacket.buttons = nextPacket.buttons;
            currentPacket.deltaX = accumulatedDeltaX + nextPacket.deltaX;
            currentPacket.deltaY = accumulatedDeltaY + nextPacket.deltaY;
        }

        /* Save timestamp and send interrupt to higher level */
        currentEventTime = *(ns_time_t *)&timestamp_low;

        /* Send interrupt notification - 0x232325 is the magic number for mouse events */
        IOSendInterrupt(param_1, param_2, 0x232325);

        /* Mark sequence as being processed */
        seqBeingProcessed = 1;

        /* Reset accumulators and sequence index */
        accumulatedDeltaY = 0;
        accumulatedDeltaX = 0;
        indexInSequence = 0;
    } else {
        /* A sequence is being processed - start collecting the next one
         * Set flag to indicate sequence in progress
         */
        seqInProgress = 1;

        /* Store byte in next packet buffer */
        ((unsigned char *)&nextPacket)[indexInSequence] = dataByte;
        indexInSequence++;

        if (indexInSequence == 3) {
            /* Complete packet received while processing
             * Accumulate the deltas for when processing finishes
             */
            accumulatedDeltaX = accumulatedDeltaX + nextPacket.deltaX;
            accumulatedDeltaY = accumulatedDeltaY + nextPacket.deltaY;

            /* Reset for next packet */
            indexInSequence = 0;
            seqInProgress = 0;
        }
    }

    return 0;
}

@implementation PS2Mouse

- (BOOL)isMousePresent
{
    int status;
    unsigned char responseByte;

    /* Check if controller functions are available */
    if (controllerFunctions == NULL) {
        return NO;
    }

    /* Send SET_RESOLUTION command (0xE8) to the mouse
     * This should return ACK if a mouse is present
     */
    status = controllerFunctions->sendMouseCommand(PS2_CMD_SET_RESOLUTION);
    if (status != 0) {
        /* Mouse acknowledged - send resolution value of 3 */
        controllerFunctions->sendMouseCommand(3);

        /* Request status from mouse (0xE9)
         * Mouse should respond with 3 status bytes
         */
        controllerFunctions->sendMouseCommand(PS2_CMD_STATUS_REQUEST);

        /* Read 3 status bytes:
         * Byte 0: Status flags
         * Byte 1: Resolution (should be 3 if mouse is working correctly)
         * Byte 2: Sample rate
         */
        controllerFunctions->readMouseByteSimple();  /* Read byte 0 (status) */
        responseByte = controllerFunctions->readMouseByteSimple();  /* Read byte 1 (resolution) */
        controllerFunctions->readMouseByteSimple();  /* Read byte 2 (sample rate) */

        /* Check if the resolution value matches what we set (3) */
        if (responseByte == 3) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)readConfigTable:(IODeviceDescription *)deviceDescription
{
    IOConfigTable *configTable;
    const char *skipDetectionStr;
    const char *invertedStr;
    const char *resolutionStr;

    /* Check if device description is provided */
    if (deviceDescription == nil) {
        IOLog("PS2Mouse: No device description provided\n");
        return NO;
    }

    /* Get config table from device description */
    configTable = [deviceDescription configTable];

    /* Read "SkipDetection" parameter (offset 0x148)
     * If set to 'y' or 'Y', skip mouse presence detection
     */
    skipDetectionStr = [configTable valueForStringKey:"SkipDetection"];
    if ((skipDetectionStr == NULL) ||
        ((*skipDetectionStr != 'y') && (*skipDetectionStr != 'Y'))) {
        skipDetection = NO;
    } else {
        skipDetection = YES;
    }

    /* Read "Inverted" parameter (offset 0x130)
     * If set to 'y' or 'Y', invert the mouse axes
     */
    invertedStr = [configTable valueForStringKey:"Inverted"];
    if ((invertedStr == NULL) ||
        ((*invertedStr != 'y') && (*invertedStr != 'Y'))) {
        inverted = NO;
    } else {
        inverted = YES;
    }

    /* Read "Resolution" parameter (offset 300)
     * If not provided, use default of 0x96 (150 DPI)
     */
    resolutionStr = [configTable valueForStringKey:"Resolution"];
    if (resolutionStr == NULL) {
        resolution = 0x96;  /* 150 DPI */
        IOLog("PS2Mouse: Using default resolution %d\n", 0x96);
    } else {
        /* Convert string to integer using PCPatoi or equivalent */
        resolution = strtoul(resolutionStr, NULL, 0);
    }

    return YES;
}

- (IOReturn)resetMouse
{
    /* Check if controller functions are available */
    if (controllerFunctions == NULL) {
        return IO_R_NOT_ATTACHED;
    }

    /* Send SET_DEFAULTS command (0xF6)
     * This resets the mouse to default settings
     */
    controllerFunctions->sendMouseCommand(PS2_CMD_SET_DEFAULTS);

    /* Send ENABLE command (0xF4)
     * This enables data reporting from the mouse
     */
    controllerFunctions->sendMouseCommand(PS2_CMD_ENABLE);

    return IO_R_SUCCESS;
}

- (IOReturn)initWithController:(id)controllerDevice
{
    BOOL mousePresent;
    unsigned char statusByte;

    /* Check if controller exists */
    if (controllerDevice == nil) {
        IOLog("PS2Mouse: no PS2Controller present\n");
        return IO_R_NOT_ATTACHED;
    }

    /* Store controller reference */
    controller = controllerDevice;

    /* Get the controller access functions (function table)
     * This returns a pointer to the function table structure
     */
    controllerFunctions = (PS2ControllerFunctions *)[controller controllerAccessFunctions];

    /* Enable manual data handling mode (bypass automatic processing) */
    [controller setManualDataHandling:YES];

    /* Reset/initialize the mouse hardware via function table
     * This is function at index 3 in the decompiled code
     */
    if (controllerFunctions != NULL && controllerFunctions->reserved[3] != NULL) {
        ((void (*)(void))controllerFunctions->reserved[3])();
    }

    /* Check if mouse is present (only if skipDetection is not set)
     * Offset 0x148 is the skipDetection flag
     */
    if (!skipDetection) {
        mousePresent = [self isMousePresent];
        if (!mousePresent) {
            /* No mouse detected - disable manual handling and fail */
            [controller setManualDataHandling:NO];
            IOLog("PS2Mouse: couldn't find a mouse!\n");
            return IO_R_NOT_ATTACHED;
        }
    }

    /* Send reset command to auxiliary device port
     * Functions from the function table:
     * [0] = send command to command port
     * [1] = read status
     * [4] = write to data port
     */
    if (controllerFunctions != NULL) {
        /* Send command to command port (empty string means some init command) */
        if (controllerFunctions->reserved[0] != NULL) {
            ((void (*)(void))controllerFunctions->reserved[0])();
        }

        /* Read controller status byte */
        if (controllerFunctions->reserved[1] != NULL) {
            statusByte = ((unsigned char (*)(void))controllerFunctions->reserved[1])();
        } else {
            statusByte = 0;
        }

        /* Send another command */
        if (controllerFunctions->reserved[0] != NULL) {
            ((void (*)(unsigned char))controllerFunctions->reserved[0])(0x07);
        }

        /* Modify status byte and write it back
         * Clear bit 5, set bit 1: (status & 0xDF) | 0x02
         */
        if (controllerFunctions->reserved[4] != NULL) {
            ((void (*)(unsigned char))controllerFunctions->reserved[4])((statusByte & 0xDF) | 0x02);
        }
    }

    /* Reset the mouse to known state */
    [self resetMouse];

    /* Register this mouse object with the controller */
    [controller setMouseObject:self];

    /* Set device name and kind */
    [self setName:"PS2Mouse"];
    [self setDeviceKind:"PS2Mouse"];

    /* Disable manual data handling - let normal interrupt processing begin */
    [controller setManualDataHandling:NO];

    /* Enable interrupts */
    [self enableAllInterrupts];

    /* Start I/O thread with fixed priority 28 (0x1c) */
    [self startIOThreadWithFixedPriority:28];

    return IO_R_SUCCESS;
}

- (IOReturn)mouseInit:(IODeviceDescription *)deviceDescription
{
    IOReturn result;
    id controllerObject;
    IOConfigTable *configTable;
    BOOL success;
    const char *errorString;

    /* Initialize global state variables */
    seqInProgress = 0;
    seqBeingProcessed = 0;
    indexInSequence = 0;
    accumulatedDeltaX = 0;
    accumulatedDeltaY = 0;

    /* Clear packet buffers */
    currentPacket.buttons = 0;
    currentPacket.deltaX = 0;
    currentPacket.deltaY = 0;
    nextPacket.buttons = 0;
    nextPacket.deltaX = 0;
    nextPacket.deltaY = 0;

    /* Clear timestamps */
    currentEventTime = 0;
    lastTimeStamp_low = 0;
    lastTimeStamp_high = 0;

    /* Set default values for instance variables */
    resolution = 0x96;
    inverted = NO;
    skipDetection = NO;

    /* Get the PS2 keyboard controller device */
    result = IOGetObjectForDeviceName("PS2KeyboardController", &controllerObject);

    if (result == IO_R_SUCCESS) {
        /* Get config table from device description */
        configTable = [deviceDescription configTable];

        /* Read configuration */
        success = [self readConfigTable:deviceDescription];

        if (success == NO) {
            return IO_R_INVALID_ARG;
        }

        /* Initialize with the controller */
        result = [self initWithController:controllerObject];
    } else {
        /* Failed to get controller - log error */
        errorString = [self stringFromReturn:result];
        IOLog("PS2Mouse: Failed to get controller: %s\n", errorString);
        result = IO_R_NOT_ATTACHED;
    }

    return result;
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)arg
      forInterrupt:(unsigned int)localInterrupt
{
    /* Set up the low-level interrupt handler */
    *handler = (IOInterruptHandler)PS2MouseIntHandler;
    *ipl = 3;  /* Interrupt priority level */
    *arg = (void *)0xdeadbeef;  /* Magic value passed to handler */
    return YES;
}

- (void)interruptOccurred
{
    /* This is called from a higher-level thread context after IOSendInterrupt
     * Dispatch the mouse event to the event port
     *
     * In the decompiled code, this checks offset 0x128 (mouseEventPort)
     * and calls dispatchPointerEvent: with &_currentEvent
     */
    if (mouseEventPort != nil) {
        /* Dispatch the event structure which contains:
         * - currentEventTime (timestamp)
         * - currentPacket (buttons, deltaX, deltaY)
         */
        [mouseEventPort dispatchPointerEvent:&currentEventTime];
    }

    /* Clear the processing flag so the interrupt handler can accept new packets */
    seqBeingProcessed = 0;
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
        /* Set the resolution value */
        resolution = *parameterArray;

        /* Get the resolution (calls getResolution method) */
        resolutionValue = [self getResolution];

        /* Update the mouse event port with new resolution */
        if (mouseEventPort != nil) {
            [mouseEventPort setResolution:resolutionValue];
        }
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

        /* Set the inverted flag */
        invertedValue = *(char *)parameterArray;
        inverted = invertedValue;

        /* Update the mouse event port with new inverted setting */
        if (mouseEventPort != nil) {
            [mouseEventPort setInverted:invertedValue];
        }
    }

    return IO_R_SUCCESS;
}

- (unsigned int)getResolution
{
    return resolution;
}

@end
