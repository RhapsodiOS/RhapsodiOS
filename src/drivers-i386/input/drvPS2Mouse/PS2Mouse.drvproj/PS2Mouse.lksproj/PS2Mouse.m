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

/* Number of bytes in a PS/2 mouse packet */
#define MOUSE_SEQUENCE_LENGTH   3

/* Global state variables for packet processing.  The declaration order below
 * is the order these objects occupy in __DATA,__bss.
 *
 * A PCPointerEvent is 12 bytes: an 8-byte timestamp followed by a 4-byte
 * union whose buf[0..2] hold the button state and the X and Y deltas.
 */
static int indexInSequence;           /* Current byte index in the packet (0-2) */
static PCPointerEvent currentEvent;   /* Event handed to the event target */
static PCPointerEvent pendingEvent;   /* Packet arriving while one is in flight */
static PCPointerEvent summedEvent;    /* Deltas accumulated while one is in flight */
static ns_time_t lastTimeStamp;       /* Timestamp of the previous packet byte */
static BOOL seqBeingProcessed;        /* Flag: sequence is being processed */
static BOOL seqInProgress;            /* Flag: new sequence is arriving while processing */

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

/* 8042 keyboard controller commands */
#define K8042_READ_COMMAND_BYTE  0x20
#define K8042_WRITE_COMMAND_BYTE 0x60

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

static PS2ControllerFunctions *controllerFunctions;

/* Forward declarations */
static void PS2MouseIntHandler(unsigned int param_1, unsigned int param_2);

/*
 * Add two movement deltas, clamping the sum to +/-127.
 *
 * Divergence from the reference, fixed at the user's request: Apple adds the
 * raw bytes, and PCPointerEvent's dx/dy are 8-bit signed fields, so a sum past
 * 127 wraps and the cursor jumps the other way.  QEMU's PS/2 mouse sends
 * packets back to back, so they pile up behind the I/O thread and hit this
 * on nearly every fast movement.  See reconstruction/divergences.md.
 */
static unsigned char addDelta(unsigned char a, unsigned char b)
{
    int sum = (signed char)a + (signed char)b;

    if (sum > 127)
        sum = 127;
    else if (sum < -127)
        sum = -127;
    return (unsigned char)sum;
}

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
 * @return void. DriverKit discards the handler result; the reference never writes eax.
 */
static void PS2MouseIntHandler(unsigned int param_1, unsigned int param_2)
{
    int status;
    unsigned char dataByte;
    ns_time_t newStamp;

    /* Read a byte from the PS/2 controller
     * This calls the controller's readDataPort method or equivalent.
     * In the decompiled code, this was via a function table at offset 0x1c
     */
    status = controllerFunctions->readMouseByte(&dataByte);
    if (status == 0) {
        /* No data available */
        return;
    }

    /* Check for self-test passed response (0xAA) at start of sequence */
    if ((dataByte == PS2_RESP_SELF_TEST_OK) && (indexInSequence == 0)) {
        /* Mouse was reset - log message and re-enable data reporting */
        IOLog("PS2Mouse: mouse reset\n");

        /* Flush/read any pending data and re-enable mouse data reporting
         * In decompiled code: func_list[0x18] = read byte, func_list[0x14] = send command
         */
        controllerFunctions->readMouseByteSimple();
        controllerFunctions->sendMouseCommand(PS2_CMD_ENABLE);
        return;
    }

    /* Get current timestamp for timeout detection */
    IOGetTimestamp(&newStamp);

    /* If we are mid-sequence and more than 250ms elapsed since the previous
     * byte, the packet cannot be trusted - resync.
     */
    if ((indexInSequence != 0) &&
        ((newStamp - lastTimeStamp) > PACKET_TIMEOUT_NS)) {
        indexInSequence = 0;

        /* If this is another self-test response after timeout, re-enable */
        if (dataByte == PS2_RESP_SELF_TEST_OK) {
            IOLog("PS2Mouse: mouse reset after resync\n");
            controllerFunctions->readMouseByteSimple();
            controllerFunctions->sendMouseCommand(PS2_CMD_ENABLE);
            return;
        }
    }

    /* Update timestamp for next iteration */
    lastTimeStamp = newStamp;

    /* Divergence from the reference, fixed at the user's request: the first
     * byte of every packet has bit 3 set.  Drop a byte that fails this at
     * the start of a packet, so a byte lost from the stream resyncs within a
     * packet or two instead of reading deltas as buttons until the mouse
     * goes idle.  See reconstruction/divergences.md.
     */
    if ((indexInSequence == 0) && !(dataByte & 0x08)) {
        return;
    }

    /* Process the byte based on current state */
    if (seqBeingProcessed == 0) {
        /* Not currently processing a sequence */
        if (seqInProgress == 0) {
            /* Not collecting a new sequence either - this is the normal path
             * Store byte in the current event
             */
            currentEvent.data.buf[indexInSequence] = dataByte;
            indexInSequence++;

            if (indexInSequence < MOUSE_SEQUENCE_LENGTH) {
                /* Need more bytes to complete packet */
                return;
            }

            /* Packet complete - fold in the accumulated movement deltas */
            currentEvent.data.buf[1] = addDelta(currentEvent.data.buf[1], summedEvent.data.buf[1]);
            currentEvent.data.buf[2] = addDelta(currentEvent.data.buf[2], summedEvent.data.buf[2]);
        } else {
            /* A new sequence was in progress while we were processing
             * Store byte in the pending event
             */
            pendingEvent.data.buf[indexInSequence] = dataByte;
            indexInSequence++;

            if (indexInSequence != MOUSE_SEQUENCE_LENGTH) {
                /* Need more bytes */
                return;
            }

            /* Pending packet complete - copy to current, folding in the deltas */
            currentEvent.data.buf[0] = pendingEvent.data.buf[0];
            currentEvent.data.buf[1] = addDelta(summedEvent.data.buf[1], pendingEvent.data.buf[1]);
            currentEvent.data.buf[2] = addDelta(summedEvent.data.buf[2], pendingEvent.data.buf[2]);
        }

        /* Save timestamp and send interrupt to higher level */
        currentEvent.timeStamp = newStamp;

        /* Send interrupt notification - 0x232325 is the magic number for mouse events */
        IOSendInterrupt(param_1, param_2, 0x232325);

        /* Mark sequence as being processed */
        seqBeingProcessed = 1;

        /* Reset accumulators and sequence index */
        summedEvent.data.buf[2] = 0;
        summedEvent.data.buf[1] = 0;
        indexInSequence = 0;
    } else {
        /* A sequence is being processed - start collecting the next one
         * Set flag to indicate sequence in progress
         */
        seqInProgress = 1;

        /* Store byte in the pending event */
        pendingEvent.data.buf[indexInSequence] = dataByte;
        indexInSequence++;

        if (indexInSequence == MOUSE_SEQUENCE_LENGTH) {
            /* Complete packet received while processing
             * Accumulate the deltas for when processing finishes
             */
            summedEvent.data.buf[1] = addDelta(summedEvent.data.buf[1], pendingEvent.data.buf[1]);
            summedEvent.data.buf[2] = addDelta(summedEvent.data.buf[2], pendingEvent.data.buf[2]);

            /* Reset for next packet */
            indexInSequence = 0;
            seqInProgress = 0;
        }
    }

    return;
}

@implementation PS2Mouse

- (BOOL)isMousePresent
{
    int status;
    unsigned char responseByte;

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

- (BOOL)readConfigTable:(IOConfigTable *)configTable
{
    const char *forceDetectionStr;
    const char *invertedStr;
    const char *resolutionStr;

    /* Check if a configuration table is provided */
    if (configTable == nil) {
        IOLog("PS2Mouse readConfigTable: no configuration table\n");
        return NO;
    }

    /* Read "Force Detection" parameter (offset 0x148)
     * If set to 'y' or 'Y', bypass mouse presence detection
     */
    forceDetectionStr = [configTable valueForStringKey:"Force Detection"];
    if ((forceDetectionStr != NULL) &&
        ((*forceDetectionStr == 'y') || (*forceDetectionStr == 'Y'))) {
        force_detection = YES;
    } else {
        force_detection = NO;
    }

    /* Read "Inverted" parameter (offset 0x130)
     * If set to 'y' or 'Y', invert the mouse axes
     */
    invertedStr = [configTable valueForStringKey:INVERTED];
    if ((invertedStr != NULL) &&
        ((*invertedStr == 'y') || (*invertedStr == 'Y'))) {
        inverted = YES;
    } else {
        inverted = NO;
    }

    /* Read "Resolution" parameter (offset 0x12c)
     * If not provided, use default of 0x96 (150 DPI)
     */
    resolutionStr = [configTable valueForStringKey:RESOLUTION];
    if (resolutionStr == NULL) {
        resolution = 0x96;  /* 150 DPI */
        IOLog("PS2Mouse readConfigTable: no resolution in config table.  Default is %d\n", 0x96);
    } else {
        resolution = PCPatoi((char *)resolutionStr);
    }

    return YES;
}

- (void)resetMouse
{
    /* Send SET_DEFAULTS command (0xF6)
     * This resets the mouse to default settings
     */
    controllerFunctions->sendMouseCommand(PS2_CMD_SET_DEFAULTS);

    /* Send ENABLE command (0xF4)
     * This enables data reporting from the mouse
     */
    controllerFunctions->sendMouseCommand(PS2_CMD_ENABLE);
}

- (BOOL)initWithController:(id)controllerDevice
{
    BOOL mousePresent;
    unsigned char statusByte;

    /* Check if controller exists */
    if (controllerDevice == nil) {
        IOLog("PS2Mouse: no PS2Controller present\n");
        return NO;
    }

    /* Store controller reference */
    controller = controllerDevice;

    /* Get the controller access functions (function table)
     * This returns a pointer to the function table structure
     */
    controllerFunctions = (PS2ControllerFunctions *)[controller controllerAccessFunctions];

    /* Enable manual data handling mode (bypass automatic processing) */
    [controller setManualDataHandling:YES];

    /* Drain any stale byte out of the 8042 output buffer via the function
     * table.  Slot 3 is clearOutputBuffer (see PS2Controller.h).
     */
    ((void (*)(void))controllerFunctions->reserved[3])();

    /* Check if mouse is present (only if force_detection is not set).
     * "Force Detection = Yes" means force the attach and skip detection.
     */
    if (!force_detection) {
        mousePresent = [self isMousePresent];
        if (!mousePresent) {
            /* No mouse detected - disable manual handling and fail */
            [controller setManualDataHandling:NO];
            IOLog("PS2Mouse: couldn't find a mouse!\n");
            return NO;
        }
    }

    /* Enable the auxiliary device interrupt on the 8042: read the command
     * byte, clear bit 5 (un-gate the mouse clock), set bit 1 (enable IRQ12),
     * and write it back.  Functions from the function table:
     * [0] = sendControllerCommand, write to the command port 0x64
     * [1] = getKeyboardData, read the data port 0x60
     * [4] = sendControllerData, write to the data port 0x60
     */
    ((void (*)(unsigned char))controllerFunctions->reserved[0])(K8042_READ_COMMAND_BYTE);
    statusByte = ((unsigned char (*)(void))controllerFunctions->reserved[1])();
    ((void (*)(unsigned char))controllerFunctions->reserved[0])(K8042_WRITE_COMMAND_BYTE);
    ((void (*)(unsigned char))controllerFunctions->reserved[4])((statusByte & 0xDF) | 0x02);

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

    return YES;
}

- (BOOL)mouseInit:(IODeviceDescription *)deviceDescription
{
    IOReturn result;
    id controllerObject;

    /* Initialize packet-assembly state */
    seqInProgress = 0;
    seqBeingProcessed = 0;
    indexInSequence = 0;
    summedEvent.data.buf[2] = 0;
    summedEvent.data.buf[1] = 0;

    /* Default resolution until the configuration table is read */
    resolution = 0x96;

    /* Get the PS2 keyboard controller device */
    result = IOGetObjectForDeviceName("PS2Controller", &controllerObject);
    if (result != IO_R_SUCCESS) {
        IOLog("initPointer: Can't find PS2Controller (%s)\n",
              [self stringFromReturn:result]);
        return NO;
    }

    /* Read configuration */
    if (![self readConfigTable:[deviceDescription configTable]]) {
        return NO;
    }

    /* Initialize with the controller */
    return [self initWithController:controllerObject];
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt
{
    /* Set up the low-level interrupt handler */
    *handler = (IOInterruptHandler)PS2MouseIntHandler;
    *ipl = 3;  /* Interrupt priority level */
    *arg = 0xdeadbeef;  /* Magic value passed to handler */
    return YES;
}

- (void)interruptOccurred
{
    /* This is called from a higher-level thread context after IOSendInterrupt
     * Dispatch the mouse event to the event target (PCPointer's target, 0x128)
     */
    if (target != nil) {
        /* currentEvent carries the timestamp plus the buttons and deltas */
        [target dispatchPointerEvent:&currentEvent];
    }

    /* Clear the processing flag so the interrupt handler can accept new packets */
    seqBeingProcessed = 0;
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
        /* Set the resolution value */
        resolution = *parameterArray;

        /* Get the resolution (calls getResolution method) */
        resolutionValue = [self getResolution];

        /* Update the event target with the new resolution */
        [target setResolution:resolutionValue];
    } else if (strcmp(parameterName, INVERTED) == 0) {
        /* Set the inverted flag */
        invertedValue = *(char *)parameterArray;
        inverted = invertedValue;

        /* Update the event target with the new inverted setting */
        [target setInverted:invertedValue];
    } else {
        return IO_R_UNSUPPORTED;
    }

    return IO_R_SUCCESS;
}

- (int)getResolution
{
    return resolution;
}

@end
