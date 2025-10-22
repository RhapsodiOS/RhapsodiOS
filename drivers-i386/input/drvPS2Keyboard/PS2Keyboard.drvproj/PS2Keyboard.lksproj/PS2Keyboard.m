/*
 * PS2Keyboard.m
 * PS/2 Keyboard Driver Implementation
 */

#import "PS2Keyboard.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/i386/ioPorts.h>
#import <bsd/dev/i386/PCPointer.h>
#import <kernserv/prototypes.h>
#import <objc/NXLock.h>

/* External functions from other modules */
extern void _register_keyboard_entries(void *entries);

/* Forward declarations for functions in this file */
BOOL _keyboardDataPresent(void);
PS2KeyboardEvent *_scancodeToKeyEvent(unsigned char scancode);
PS2KeyboardEvent *_NewStealKeyboardEvent(void);

 /*
 * The protocol we need as an indirect device.
 */
static Protocol *protocols[] = {
	@protocol(PS2Controller),
	@protocol(PCKeyboard),
	nil
};

/* Keyboard bit vector - tracks which keys are currently pressed
 * 128 keys tracked in 4 words (32 bits each) */
static unsigned int __kbdBitVector[4] = {0, 0, 0, 0};

/* Static event structure for scancode conversion */
static PS2KeyboardEvent _event = {0, 0, 0, 0};

/* Extended scancode counter */
static unsigned char _extendCount = 0;

/* Additional keyboard state - appears to be at a higher offset */
static unsigned char _keyboardState[32] = {0};

@implementation PS2Keyboard

/* Class Methods */

+ (int)deviceStyle
{
    /* Return the device style for this driver
     * Returns 1 for standard keyboard device */
    return 1;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id directDevice;
    id keyboardInstance;
    IOConfigTable *configTable;
    BOOL result;
    unsigned int keyboardEntries[2];

    /* Initialize result to NO */
    result = NO;

    /* Get the direct device (PS2Controller) from the device description */
    directDevice = [deviceDescription directDevice];

    /* Allocate and initialize a PS2Keyboard instance with the controller */
    keyboardInstance = [[self alloc] initWithController:directDevice];

    /* Check if instance was created successfully */
    if (keyboardInstance != nil) {
        /* Get the config table from device description */
        configTable = [deviceDescription configTable];

        /* Read configuration from the table */
        result = [keyboardInstance readConfigTable:configTable];

        if (result == NO) {
            /* Configuration failed - free the instance */
            [keyboardInstance free];
        } else {
            /* Configuration succeeded - register keyboard entries */
            keyboardEntries[0] = 0;
            keyboardEntries[1] = 0x910;  /* 2320 decimal */

            _register_keyboard_entries(keyboardEntries);
        }
    }

    return result;
}

+ (Protocol **)requiredProtocols
{
    return protocols;
}

/* Instance Methods */

- initWithController:(id)controllerInstance
{
    unsigned char commandByte;

    /* Call superclass initializer */
    [super init];

    /* Store the controller reference at offset 0x108 */
    controller = controllerInstance;

    /* Initialize owner lock */
    ownerLock = [[NXLock alloc] init];
    keyboardOwner = nil;
    desiredOwner = nil;

    /* Initialize event queue */
    eventCount = 0;

    /* Initialize IDs */
    interfaceID = 0;
    handlerID = 0;

    /* Clear any pending data from the PS/2 controller output buffer */
    clearOutputBuffer();

    /* Read the current PS/2 controller command byte */
    _sendControllerCommand(0x20);  /* Command: Read Command Byte */
    commandByte = _getKeyboardData();

    /* Write modified command byte back to controller */
    _sendControllerCommand(0x60);  /* Command: Write Command Byte */

    /* Modify command byte:
     * & 0xEF clears bit 4 (disable mouse interface)
     * | 0x41 sets bit 0 (enable keyboard interrupt) and bit 6 (translate scancodes)
     */
    _sendControllerData(commandByte & 0xEF | 0x41);

    /* Register ourselves with the controller as the keyboard object */
    [controller setKeyboardObject:self];

    /* Initialize Caps Lock LED to off */
    [self setAlphaLockFeedback:NO];

    /* Set device unit number to 0 */
    [self setUnit:0];

    /* Set device name and kind */
    [self setName:"PCKeyboard0"];
    [self setDeviceKind:"PS2Keyboard"];

    /* Register this device with the system */
    [self registerDevice];

    return self;
}

- (BOOL)becomeOwner:(id)owner
{
    int result;
    const char *ownerName;
    const char *selfName;

    /* Lock to ensure thread-safe ownership changes */
    [ownerLock lock];

    if (keyboardOwner == nil) {
        /* No current owner - grant ownership immediately */
        keyboardOwner = owner;
        result = 0;  /* Success */
    } else {
        /* Already have an owner - need to request relinquishment */

        /* Check if current owner responds to relinquishOwnershipRequest: */
        if (![keyboardOwner respondsTo:@selector(relinquishOwnershipRequest:)]) {
            /* Owner doesn't support relinquishment protocol - log error */
            ownerName = [keyboardOwner name];
            selfName = [self name];
            IOLog("%s: owner %s does not respond to relinquishOwnershipRequest:\n",
                  selfName, ownerName);
            result = 0xFFFFFD2B;  /* -725 decimal - error code */
        } else {
            /* Ask current owner to relinquish ownership */
            result = [keyboardOwner relinquishOwnershipRequest:self];
        }

        /* If relinquishment succeeded, grant ownership to new owner */
        if (result == 0) {
            keyboardOwner = owner;
        }
    }

    /* Unlock */
    [ownerLock unlock];

    return (result == 0);
}

- (BOOL)desireOwnership:(id)owner
{
    int result;

    /* Lock to ensure thread-safe access */
    [ownerLock lock];

    /* Check if no one has desired ownership yet, or if this is the same owner */
    if (desiredOwner == nil || desiredOwner == owner) {
        /* Grant or maintain desired ownership */
        desiredOwner = owner;
        result = 0;  /* Success */
    } else {
        /* Someone else already desires ownership */
        result = 0xFFFFFD2B;  /* -725 decimal - conflict error */
    }

    /* Unlock */
    [ownerLock unlock];

    return (result == 0);
}

- (int)relinquishOwnership:(id)owner
{
    int result;

    /* Lock to ensure thread-safe ownership changes */
    [ownerLock lock];

    /* Check if the owner parameter matches the current owner */
    if (keyboardOwner == owner) {
        /* Owner matches - relinquish ownership */
        result = 0;  /* Success */
        keyboardOwner = nil;
    } else {
        /* Owner doesn't match - return error */
        result = 0xFFFFFD2B;  /* -725 decimal - not owner error */
    }

    /* Unlock */
    [ownerLock unlock];

    /* If relinquishment succeeded and there's a desired owner waiting */
    if ((result == 0) && (desiredOwner != nil) && (desiredOwner != owner)) {
        /* Check if desired owner responds to canBecomeOwner: */
        if (![desiredOwner respondsTo:@selector(canBecomeOwner:)]) {
            /* Desired owner doesn't support the protocol - log error */
            IOLog("%s: desiredOwner does not respond to canBecomeOwner:\n",
                  [self name]);
        } else {
            /* Notify the desired owner that it can now become owner */
            [desiredOwner canBecomeOwner:self];
        }
    }

    return result;
}

- (void)interruptOccurred
{
    unsigned char scancode;
    PS2KeyboardEvent *event;
    int index;

    /* Process all available keyboard data */
    while (_keyboardDataPresent()) {
        /* Read the scancode from the keyboard */
        scancode = _getKeyboardData();

        /* Check for special PS/2 response codes */
        if (scancode == 0xFA) {
            /* ACK (0xFA = -6 in signed char) - unexpected here */
            IOLog("PS2Keyboard: Unexpected ACK from controller\n");
            continue;
        }

        if (scancode == 0xFE) {
            /* RESEND (0xFE = -2 in signed char) - controller wants resend */
            _resendControllerData();
            continue;
        }

        /* Convert scancode to keyboard event */
        event = _scancodeToKeyEvent(scancode);

        if (event != NULL) {
            /* Valid event - add to queue if not full */
            if (eventCount != MAX_KEYBOARD_EVENTS) {
                /* Get index for new event */
                index = eventCount;

                /* Copy the 4-int event structure (16 bytes) */
                eventQueue[index].timestamp_high = event->timestamp_high;
                eventQueue[index].timestamp_low = event->timestamp_low;
                eventQueue[index].keyCode = event->keyCode;
                eventQueue[index].flags = event->flags;

                /* Increment event count */
                eventCount++;
            }
        }

        /* Dispatch queued events to owner */
        [self dispatchKeyboardEvents];
    }
}

- (void)dispatchKeyboardEvents
{
    PS2KeyboardEvent localEventBuffer[MAX_KEYBOARD_EVENTS];
    int savedEventCount;
    int savedSPL;
    int i;

    /* Raise to IPL 6 (IPL_BIO) and save previous level */
    savedSPL = splx(6);

    /* Copy events from the queue to local buffer atomically */
    if (eventCount == 1) {
        /* Optimized path for single event - direct copy of 16 bytes (4 ints) */
        localEventBuffer[0].timestamp_high = eventQueue[0].timestamp_high;
        localEventBuffer[0].timestamp_low = eventQueue[0].timestamp_low;
        localEventBuffer[0].keyCode = eventQueue[0].keyCode;
        localEventBuffer[0].flags = eventQueue[0].flags;
    } else if (eventCount > 0) {
        /* Multiple events - use bcopy to copy all events */
        /* Each event is 16 bytes (4 ints), so copy eventCount * 16 bytes */
        bcopy(eventQueue, localEventBuffer, eventCount * sizeof(PS2KeyboardEvent));
    }

    /* Save event count and reset the queue */
    savedEventCount = eventCount;
    eventCount = 0;

    /* Restore previous SPL */
    splx(savedSPL);

    /* Dispatch events to the keyboard owner if one exists */
    if (keyboardOwner != nil && savedEventCount > 0) {
        for (i = 0; i < savedEventCount; i++) {
            /* Dispatch each event to the owner */
            [keyboardOwner dispatchKeyboardEvent:&localEventBuffer[i]];
        }
    }
}

- (void)enqueueKeyEvent:(unsigned int)keyCode
              goingDown:(BOOL)goingDown
                 atTime:(unsigned long long)timestamp
{
    int index;
    unsigned int flags;

    /* Check if queue is not full (max 16 events) */
    if (eventCount != MAX_KEYBOARD_EVENTS) {
        /* Get current index for new event */
        index = eventCount;

        /* Build flags from goingDown and keyCode */
        flags = goingDown ? 0 : 1;  /* 0 = key down, 1 = key up */

        /* Store event in the queue at offset 0x110 + (index * 0x10) */
        eventQueue[index].timestamp_high = (unsigned int)(timestamp >> 32);
        eventQueue[index].timestamp_low = (unsigned int)(timestamp & 0xFFFFFFFF);
        eventQueue[index].keyCode = keyCode;
        eventQueue[index].flags = flags;

        /* Increment event count */
        eventCount++;
    }
    /* If queue is full, event is dropped (no error reporting) */
}

- (BOOL)readConfigTable:(IOConfigTable *)configTable
{
    const char *interfaceStr;
    const char *handlerStr;
    int interfaceValue;
    int handlerValue;

    /* Check if config table is valid */
    if (configTable == nil) {
        IOLog("PS2Keyboard kbdInit: no configuration table\n");
        return NO;
    }

    /* Read "Interface" key from config table */
    interfaceStr = [configTable valueForStringKey:"Interface"];
    if (interfaceStr == NULL) {
        /* No Interface key - use default value 3 */
        IOLog("PS2Keyboard kbdInit: no Interface key in config table\n");
        interfaceValue = 3;
    } else {
        /* Parse the interface value using PCPatoi */
        interfaceValue = PCPatoi(interfaceStr);
    }

    /* Store the interface ID at offset 0x210 */
    interfaceID = interfaceValue;

    /* Read "Handler ID" key from config table */
    handlerStr = [configTable valueForStringKey:"Handler ID"];
    if (handlerStr == NULL) {
        /* No Handler ID key - use default value 0 */
        IOLog("PS2Keyboard kbdInit: no Handler ID key in config table\n");
        handlerValue = 0;
    } else {
        /* Parse the handler ID value using PCPatoi */
        handlerValue = PCPatoi(handlerStr);
    }

    /* Store the handler ID at offset 0x214 */
    handlerID = handlerValue;

    return YES;
}

- (void)setAlphaLockFeedback:(BOOL)on
{
    unsigned int ledState;

    /* Build LED state byte:
     * Bit 0: Scroll Lock
     * Bit 1: Num Lock
     * Bit 2: Caps Lock
     */
    ledState = 0;
    if (on != NO) {
        ledState = 4;  /* Caps Lock bit */
    }

    /* Send LED command directly to controller */
    [controller setLEDs:ledState];
}

- (int)handlerId
{
    /* Return the handler ID for this keyboard (offset 0x214) */
    return handlerID;
}

- (int)interfaceId
{
    /* Return the interface ID for this keyboard (offset 0x210) */
    return interfaceID;
}

/* Helper function: Return the number of keys currently pressed */
int __PS2KeyboardNumKeysDown(void)
{
    int keyCount;
    int keyIndex;
    unsigned int wordIndex;
    unsigned int bitMask;

    /* Initialize counter */
    keyCount = 0;

    /* Iterate through all 128 possible key positions */
    for (keyIndex = 0; keyIndex < 0x80; keyIndex++) {
        /* Calculate which word in the bit vector (divide by 32) */
        wordIndex = keyIndex >> 5;

        /* Calculate bit mask for this key position (modulo 32) */
        bitMask = 1 << (keyIndex & 0x1f);

        /* Check if this key is currently pressed */
        if ((__kbdBitVector[wordIndex] & bitMask) != 0) {
            keyCount++;
        }
    }

    return keyCount;
}

/* Helper function: Check if keyboard data is present */
BOOL _keyboardDataPresent(void)
{
    /* Check if there's keyboard data available to read */
    /* TODO: Implement from decompiled code */
    /* This should check the PS/2 controller status register */
    unsigned char status = inb(0x64);

    /* Bit 0: Output buffer full (data available)
     * Bit 5: Auxiliary device (0 = keyboard, 1 = mouse) */
    return ((status & 0x01) != 0 && (status & 0x20) == 0);
}

/* Helper function: Convert scancode to keyboard event */
PS2KeyboardEvent *_scancodeToKeyEvent(unsigned char scancode)
{
    unsigned char keyCode;
    unsigned char bitPosition;
    unsigned int wordIndex;
    unsigned int bitMask;
    unsigned int isKeyDown;

    /* Handle extended scancode prefix 0xE0 */
    if (scancode == 0xE0) {
        _extendCount = 1;
        return NULL;
    }

    /* Handle extended scancode prefix 0xE1 (Pause/Break key) */
    if (scancode == 0xE1) {
        if (_extendCount == 0) {
            _extendCount = 5;
            return NULL;
        }
    }

    /* Process extended scancodes */
    if (_extendCount != 0) {
        _extendCount--;

        if (_extendCount != 0) {
            return NULL;
        }

        /* Translate extended scancodes to ADB keycodes */
        switch (scancode & 0x7F) {
            case 0x1C: keyCode = 0x62; break;  /* Keypad Enter */
            case 0x1D: keyCode = 0x60; break;  /* Right Control */
            case 0x35: keyCode = 0x63; break;  /* Keypad / */
            case 0x37: keyCode = 0x6E; break;  /* Print Screen */
            case 0x38: keyCode = 0x61; break;  /* Right Alt */
            case 0x45: keyCode = 0x6F; break;  /* Num Lock */
            case 0x47: keyCode = 0x6C; break;  /* Home */
            case 0x48: keyCode = 0x64; break;  /* Up Arrow */
            case 0x49: keyCode = 0x6A; break;  /* Page Up */
            case 0x4B: keyCode = 0x66; break;  /* Left Arrow */
            case 0x4D: keyCode = 0x67; break;  /* Right Arrow */
            case 0x4F: keyCode = 0x6D; break;  /* End */
            case 0x50: keyCode = 0x65; break;  /* Down Arrow */
            case 0x51: keyCode = 0x6B; break;  /* Page Down */
            case 0x52: keyCode = 0x68; break;  /* Insert */
            case 0x53: keyCode = 0x69; break;  /* Delete */
            case 0x5B: keyCode = 0x70; break;  /* Left Windows */
            case 0x5C: keyCode = 0x71; break;  /* Right Windows */
            case 0x5D: keyCode = 0x72; break;  /* Menu */
            default:
                return NULL;  /* Unrecognized extended key */
        }
    } else {
        /* Normal scancode - just mask off the break bit */
        keyCode = scancode & 0x7F;
    }

    /* Check if we got a valid keycode */
    if (keyCode == 0) {
        return NULL;
    }

    /* Get timestamp for this event */
    IOGetTimestamp((ns_time_t *)&_event);

    /* Determine if this is a key down (0) or key up (1) event */
    /* Bit 7 of scancode: 0 = key down, 1 = key up */
    isKeyDown = (scancode >> 7) ^ 1;

    /* Special case for Num Lock (0x6F) - check keyboard state */
    if (keyCode == 0x6F) {
        /* Check bit 7 of state byte at offset 0x18 (24) */
        isKeyDown = (_keyboardState[0x18] & 0x80) == 0;
    }

    /* Store the keycode in the event structure */
    _event.keyCode = keyCode;

    /* Update the keyboard bit vector */
    bitPosition = (unsigned char)keyCode;
    wordIndex = keyCode >> 5;
    bitMask = 1 << (bitPosition & 0x1F);

    if (isKeyDown == 0) {
        /* Key up - clear the bit in the vector */
        /* Create mask with all bits set except target bit */
        __kbdBitVector[wordIndex] = __kbdBitVector[wordIndex] & ~bitMask;
    } else {
        /* Key down - check if already pressed (ignore auto-repeat) */
        if ((__kbdBitVector[wordIndex] & bitMask) != 0) {
            return NULL;  /* Key already down, ignore */
        }
        /* Set the bit in the vector */
        __kbdBitVector[wordIndex] = __kbdBitVector[wordIndex] | bitMask;
    }

    /* Store flags in event structure */
    _event.flags = isKeyDown;

    return &_event;
}

/* Non-blocking function to "steal" a keyboard event if one is available */
PS2KeyboardEvent *_NewStealKeyboardEvent(void)
{
    unsigned char scancode;
    PS2KeyboardEvent *event;

    /* Try to get keyboard data if present (non-blocking) */
    if (!_getKeyboardDataIfPresent(&scancode)) {
        /* No keyboard data available */
        return NULL;
    }

    /* Check for ACK response (0xFA = -6 in signed char) */
    if (scancode == 0xFA) {
        IOLog("PS2Keyboard: Unexpected ACK from controller\n");
        return NULL;
    }

    /* Check for RESEND response (0xFE = -2 in signed char) */
    if (scancode == 0xFE) {
        /* Controller wants us to resend the last data */
        _resendControllerData();
        return NULL;
    }

    /* Convert scancode to keyboard event */
    event = _scancodeToKeyEvent(scancode);

    return event;
}

@end
