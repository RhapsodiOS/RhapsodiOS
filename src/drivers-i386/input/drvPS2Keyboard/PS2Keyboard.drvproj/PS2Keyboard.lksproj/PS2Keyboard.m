/*
 * PS2Keyboard.m
 * PS/2 Keyboard Driver Implementation
 */

#import "PS2Keyboard.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <bsd/dev/i386/PCPointer.h>
#import <mach/mach_traps.h>

/*
 * Publishes the driver's keyboard entry points to the kernel.  Declared here
 * because <bsd/dev/i386/kbd_entries.h> is KERNEL_PRIVATE only.
 */
extern void register_keyboard_entries(void *list);

/*
 * The protocol we need of our direct device as an indirect device.
 */
static Protocol *protocols[] = {
	@protocol(PS2ControllerExported),
	nil
};

/* Keyboard bit vector - tracks which of the 128 keys are currently pressed */
static unsigned int _kbdBitVector[4];

@implementation PS2Keyboard

/* Class Methods */

+ (int)deviceStyle
{
    /* Indirect device */
    return 1;
}

+ (Protocol **)requiredProtocols
{
    return protocols;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id directDevice;
    id keyboardInstance;
    IOConfigTable *configTable;
    BOOL result;
    void *keyboardEntries[2];

    result = NO;

    /* Get the direct device (PS2Controller) from the device description */
    directDevice = [deviceDescription directDevice];

    /* Allocate and initialize a PS2Keyboard instance with the controller */
    keyboardInstance = [[self alloc] initWithController:directDevice];

    if (keyboardInstance != nil) {
        configTable = [deviceDescription configTable];

        result = [keyboardInstance readConfigTable:configTable];

        if (result == NO) {
            [keyboardInstance free];
        } else {
            /* struct keyboard_entries { keyboard_reboot, steal_keyboard_event } */
            keyboardEntries[0] = NULL;
            keyboardEntries[1] = (void *)NewStealKeyboardEvent;

            register_keyboard_entries(keyboardEntries);
        }
    }

    return result;
}

/* Instance Methods */

- (BOOL)readConfigTable:(IOConfigTable *)configTable
{
    const char *interfaceStr;
    const char *handlerStr;
    int interfaceValue;
    int handlerValue;

    if (configTable == nil) {
        IOLog("PS2Keyboard kbdInit: no configuration table\n");
        return NO;
    }

    /* Read "Interface" key from config table */
    interfaceStr = [configTable valueForStringKey:"Interface"];
    if (interfaceStr == NULL) {
        IOLog("PS2Keyboard kbdInit: no Interface ID; use default\n");
        interfaceValue = 3;
    } else {
        interfaceValue = PCPatoi((char *)interfaceStr);
    }

    interfaceId = interfaceValue;

    /* Read "Handler ID" key from config table */
    handlerStr = [configTable valueForStringKey:"Handler ID"];
    if (handlerStr == NULL) {
        IOLog("PS2Keyboard kbdInit: no Handler ID; use default\n");
        handlerValue = 0;
    } else {
        handlerValue = PCPatoi((char *)handlerStr);
    }

    handlerId = handlerValue;

    return YES;
}

- initWithController:(id)controllerInstance
{
    unsigned char commandByte;

    [super init];

    /* Store the controller reference at offset 0x108 */
    controller = controllerInstance;

    /* Clear any pending data from the PS/2 controller output buffer */
    clearOutputBuffer();

    /* Read the current PS/2 controller command byte */
    sendControllerCommand(0x20);  /* Command: Read Command Byte */
    commandByte = getKeyboardData();

    commandByte |= 0x40;
    commandByte &= 0xEF;
    commandByte |= 1;

    /* Write the modified command byte back to the controller */
    sendControllerCommand(0x60);  /* Command: Write Command Byte */
    sendControllerData(commandByte);

    /* Register ourselves with the controller as the keyboard object */
    [controller setKeyboardObject:self];

    /* Initialize Caps Lock LED to off */
    [self setAlphaLockFeedback:NO];

    [self setUnit:0];
    [self setName:"PCKeyboard0"];
    [self setDeviceKind:"PS2Keyboard"];

    [self registerDevice];

    return self;
}

- (void)interruptOccurred
{
    unsigned char scancode;
    PS2KeyboardEvent *event;
    int index;

    /* Process all available keyboard data */
    while (keyboardDataPresent()) {
        scancode = getKeyboardData();

        if (scancode == 0xFA) {
            /* ACK - unexpected here */
            IOLog("PS2Keyboard: Unexpected ACK from controller\n");
            continue;
        }

        if (scancode == 0xFE) {
            /* RESEND - the controller wants the last data byte again */
            resendControllerData();
            continue;
        }

        event = scancodeToKeyEvent(scancode);

        if (event != NULL) {
            if (numEvents == MAX_KEYBOARD_EVENTS) {
                /* Queue full - drop the event and poll again */
                continue;
            }

            index = numEvents;

            pendingEvents[index].timeStamp = event->timeStamp;
            pendingEvents[index].keyCode = event->keyCode;
            pendingEvents[index].goingDown = event->goingDown;

            numEvents++;
        }

        [self dispatchKeyboardEvents];
    }
}

- (void)dispatchKeyboardEvents
{
    PS2KeyboardEvent localEventBuffer[MAX_KEYBOARD_EVENTS];
    int savedEventCount;
    int savedSPL;
    int i;

    /* Raise to IPL 6 -- IPLDMA/IPLCLOCK/IPLSCHED in <kernserv/i386/spl.h>, not
     * IPLBIO, which is 3 -- and save previous level
     */
    savedSPL = splx(6);

    /* Copy events from the queue to the local buffer atomically */
    if (numEvents == 1) {
        localEventBuffer[0] = pendingEvents[0];
    } else {
        bcopy(pendingEvents, localEventBuffer,
              numEvents * sizeof(PS2KeyboardEvent));
    }

    savedEventCount = numEvents;
    numEvents = 0;

    splx(savedSPL);

    /* Dispatch events to the keyboard owner if one exists */
    if (_owner != nil) {
        for (i = 0; i < savedEventCount; i++) {
            [_owner dispatchKeyboardEvent:(PCKeyboardEvent *)&localEventBuffer[i]];
        }
    }
}

/* Helper function: Return the number of keys currently pressed */
int _PS2KeyboardNumKeysDown(void)
{
    int keyCount;
    int keyIndex;
    unsigned int wordIndex;
    unsigned int bitMask;

    keyCount = 0;

    for (keyIndex = 0; keyIndex < 0x80; keyIndex++) {
        wordIndex = keyIndex >> 5;
        bitMask = 1 << (keyIndex & 0x1f);

        if ((_kbdBitVector[wordIndex] & bitMask) != 0) {
            keyCount++;
        }
    }

    return keyCount;
}

- (void)enqueueKeyEvent:(int)keyCode
              goingDown:(BOOL)goingDown
                 atTime:(unsigned long long)timestamp
{
    int index;
    PS2KeyboardEvent event;

    /* Check if the queue is not full (max 16 events) */
    if (numEvents != MAX_KEYBOARD_EVENTS) {
        event.keyCode = keyCode;
        event.goingDown = goingDown;
        event.timeStamp = timestamp;
        index = numEvents;
        pendingEvents[index] = event;
        numEvents++;
    }
    /* If the queue is full, the event is dropped */
}

/* Helper function: Convert a scancode to a keyboard event */
PS2KeyboardEvent *scancodeToKeyEvent(unsigned char scancode)
{
    static PS2KeyboardEvent event;
    static unsigned char extendCount;
    unsigned char keyCode;
    unsigned char bitPosition;
    unsigned int wordIndex;
    unsigned int bitMask;
    unsigned int isKeyDown;

    /* Handle the extended scancode prefix 0xE0 */
    if (scancode == 0xE0) {
        extendCount = 1;
        return NULL;
    }

    /* Handle the extended scancode prefix 0xE1 (Pause/Break) */
    if (scancode == 0xE1) {
        if (extendCount == 0) {
            extendCount = 5;
            return NULL;
        }
    }

    /* Process extended scancodes */
    if (extendCount != 0) {
        extendCount--;

        if (extendCount != 0) {
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

    if (keyCode == 0) {
        return NULL;
    }

    /* Get the timestamp for this event */
    IOGetTimestamp((ns_time_t *)&event);

    /* Bit 7 of the scancode: 0 = key down, 1 = key up */
    isKeyDown = (scancode >> 7) ^ 1;

    /* Num Lock toggles off its own recorded state rather than the break bit */
    if (keyCode == 0x6F) {
        isKeyDown = (_kbdBitVector[0x6F >> 5] & (1 << (0x6F & 0x1F))) == 0;
    }

    event.keyCode = keyCode;

    /* Update the keyboard bit vector */
    bitPosition = (unsigned char)keyCode;
    wordIndex = keyCode >> 5;
    bitMask = 1 << (bitPosition & 0x1F);

    if (isKeyDown == 0) {
        /* Key up - clear the bit in the vector */
        _kbdBitVector[wordIndex] = _kbdBitVector[wordIndex] & ~bitMask;
    } else {
        /* Key down - reject auto-repeat of a key already held */
        if ((_kbdBitVector[wordIndex] & bitMask) != 0) {
            return NULL;
        }
        _kbdBitVector[wordIndex] = _kbdBitVector[wordIndex] | bitMask;
    }

    event.goingDown = isKeyDown;

    return &event;
}

- (int)interfaceId
{
    return interfaceId;
}

- (int)handlerId
{
    return handlerId;
}

- (void)setAlphaLockFeedback:(BOOL)on
{
    unsigned int ledState;

    /*
     * LED state byte: bit 0 Scroll Lock, bit 1 Num Lock, bit 2 Caps Lock.
     */
    ledState = 0;
    if (on != NO) {
        ledState = 4;
    }

    [controller setLEDs:ledState];
}

- (IOReturn)becomeOwner:(id)owner
{
    IOReturn result;
    const char *ownerName;
    const char *selfName;

    [_ownerLock lock];

    if (_owner == nil) {
        /* No current owner - grant ownership immediately */
        _owner = owner;
        result = 0;
    } else {
        /* Already owned - ask the owner to relinquish */
        if (![_owner respondsTo:@selector(relinquishOwnershipRequest:)]) {
            ownerName = [_owner name];
            selfName = [self name];
            IOLog("%s: owner %s does not respond to relinquishOwnershipRequest:\n",
                  selfName, ownerName);
            result = 0xFFFFFD2B;  /* -725 */
        } else {
            result = [_owner relinquishOwnershipRequest:self];
        }

        if (result == 0) {
            _owner = owner;
        }
    }

    [_ownerLock unlock];

    return result;
}

- (IOReturn)relinquishOwnership:(id)owner
{
    IOReturn result;

    [_ownerLock lock];

    if (_owner == owner) {
        result = 0;
        _owner = nil;
    } else {
        result = 0xFFFFFD2B;  /* -725 */
    }

    [_ownerLock unlock];

    /* If ownership was released and someone is waiting for it, tell them */
    if ((result == 0) && (_desiredOwner != nil) && (_desiredOwner != owner)) {
        if (![_desiredOwner respondsTo:@selector(canBecomeOwner:)]) {
            IOLog("%s: desiredOwner does not respond to canBecomeOwner:\n",
                  [self name]);
        } else {
            [_desiredOwner canBecomeOwner:self];
        }
    }

    return result;
}

- (IOReturn)desireOwnership:(id)owner
{
    IOReturn result;

    [_ownerLock lock];

    if (_desiredOwner != nil && _desiredOwner != owner) {
        /* Someone else is already next in line */
        result = 0xFFFFFD2B;  /* -725 */
    } else {
        _desiredOwner = owner;
        result = 0;
    }

    [_ownerLock unlock];

    return result;
}

@end
