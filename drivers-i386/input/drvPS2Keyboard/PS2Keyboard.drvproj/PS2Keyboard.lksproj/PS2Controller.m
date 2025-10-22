/*
 * PS2Controller.m
 * PS/2 Keyboard Controller Driver
 */

#import "PS2Controller.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#import <kernserv/prototypes.h>
#import <kern/kdp_internal.h>
#import <mach/exception.h>

/* PS/2 Controller I/O Ports */
#define PS2_DATA_PORT    0x60  /* Data port */
#define PS2_STATUS_PORT  0x64  /* Status register (read) */
#define PS2_COMMAND_PORT 0x64  /* Command register (write) */

/* Status register bits */
#define PS2_STATUS_OUTPUT_FULL  0x01  /* Output buffer full */
#define PS2_STATUS_INPUT_FULL   0x02  /* Input buffer full */

/* Inline assembly macros for atomic operations */
#define LOCK()   __asm__ volatile ("" ::: "memory")
#define UNLOCK() __asm__ volatile ("" ::: "memory")

/* Forward declarations */
void interruptHandler(void *identity, void *state, unsigned int arg);

/* Static/global variables */
static id __mouse = nil;
static id ___controller = nil;  /* Note: triple underscore in original */
static unsigned char __escapeState = 0;
static volatile int *_controller_lock = NULL;  /* Pointer - allocated with kalloc */
static unsigned char _lastSent = 0;
static unsigned int _portAccessCount = 0;
static volatile int _portCountLock = 0;
static int _pendingAck = 0;  /* Flag indicating we're waiting for an ACK */

/* Escape sequence tracking */
static unsigned char _lastExtended = 0;   /* Tracks if last byte was 0xE0 */
static unsigned short _lastKey = 0;       /* Last key (extended flag + scancode) */

/* Key sequence definitions for escape sequences */

/* Left Alt + Num Lock sequence */
static KeySequenceEntry _lalt_numlock_seq = {
    NULL,  /* next */
    0,     /* index */
    { 0x38, 0x00,   /* Left Alt (scancode 0x38, not extended) */
      0x45, 0x00 }  /* Num Lock (scancode 0x45, not extended) */
};

static KeySequenceEntry *_lalt_numlock[] = {
    &_lalt_numlock_seq,
    NULL  /* Terminator */
};

/* Right Alt + Num Lock sequence */
static KeySequenceEntry _ralt_numlock_seq = {
    NULL,  /* next */
    0,     /* index */
    { 0x38, 0x01,   /* Right Alt (scancode 0x38, extended) */
      0x45, 0x00 }  /* Num Lock (scancode 0x45, not extended) */
};

static KeySequenceEntry *_ralt_numlock[] = {
    &_ralt_numlock_seq,
    NULL  /* Terminator */
};

/* Left Alt + Right Alt + Num Lock sequence */
static KeySequenceEntry _lalt_ralt_numlock_seq = {
    NULL,  /* next */
    0,     /* index */
    { 0x38, 0x00,   /* Left Alt (scancode 0x38, not extended) */
      0x38, 0x01,   /* Right Alt (scancode 0x38, extended) */
      0x45, 0x00 }  /* Num Lock (scancode 0x45, not extended) */
};

static KeySequenceEntry *_lalt_ralt_numlock[] = {
    &_lalt_ralt_numlock_seq,
    NULL  /* Terminator */
};

/* Right Alt + Left Alt + Num Lock sequence */
static KeySequenceEntry _ralt_lalt_numlock_seq = {
    NULL,  /* next */
    0,     /* index */
    { 0x38, 0x01,   /* Right Alt (scancode 0x38, extended) */
      0x38, 0x00,   /* Left Alt (scancode 0x38, not extended) */
      0x45, 0x00 }  /* Num Lock (scancode 0x45, not extended) */
};

static KeySequenceEntry *_ralt_lalt_numlock[] = {
    &_ralt_lalt_numlock_seq,
    NULL  /* Terminator */
};

/* Escape sequences array - defines special key combinations and their actions */
static EscapeSequence _escapes[] = {
    /* Left Alt + Num Lock - Enter mini-monitor with "restart" */
    { _lalt_numlock, NULL, NULL, NULL, NULL, NULL,
      (EscapeCallback)mini_mon, (void *)"restart", NULL, NULL,
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL },

    /* Right Alt + Num Lock - Enter mini-monitor with "Restart" */
    { _ralt_numlock, NULL, NULL, NULL, NULL, NULL,
      (EscapeCallback)mini_mon, (void *)"Restart", NULL, NULL,
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL },

    /* Left Alt + Right Alt + Num Lock - Enter mini-monitor */
    { _lalt_ralt_numlock, NULL, NULL, NULL, NULL, NULL,
      (EscapeCallback)mini_mon, NULL, NULL, NULL,
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL },

    /* Right Alt + Left Alt + Num Lock - Enter mini-monitor with "Mini-Monitor" */
    { _ralt_lalt_numlock, NULL, NULL, NULL, NULL, NULL,
      (EscapeCallback)mini_mon, (void *)"", (void *)"", (void *)"Mini-Monitor",
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL },

    /* Terminator - all zeros */
    { NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL }
};

/* Static structure of exported controller functions - provides access to
 * PS/2 controller functionality for keyboard and mouse drivers */
static PS2ControllerFunctions _exported_funcs = {
    _sendControllerCommand,
    _getKeyboardData,
    _getKeyboardDataIfPresent,
    clearOutputBuffer,
    _sendControllerData,
    _sendMouseCommand,
    _getMouseData,
    _getMouseDataIfPresent
};

@implementation PS2Controller

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id instance;
    BOOL result;

    /* Allocate a new instance of PS2Controller */
    instance = [self alloc];

    if (instance == nil) {
        return NO;
    }

    /* Initialize global variables */
    __mouse = nil;
    _pendingAck = 0;
    ___controller = instance;

    /* Allocate memory for controller lock (8 bytes = 2 ints) */
    _controller_lock = (volatile int *)kalloc(8);

    /* Initialize lock flag to 0 (unlocked) */
    _controller_lock[1] = 0;

    /* Initialize the instance with the device description */
    instance = [instance initFromDeviceDescription:deviceDescription];

    /* Return YES if initialization succeeded, NO otherwise */
    result = (instance != nil);

    return result;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    int i;
    PS2QueueElement *element;

    /* Call superclass initializer */
    [super initFromDeviceDescription:deviceDescription];

    /* Set device name and kind */
    [self setName:"PS2Controller"];
    [self setDeviceKind:"PS2Controller"];

    /* Register this device */
    [self registerDevice];

    /* Store controller reference for interrupt handler */
    ___controller = self;

    /* Initialize keyboard free queue as a circular doubly-linked list */
    keyboardFreeQueue.next = &keyboardFreeQueue;
    keyboardFreeQueue.prev = &keyboardFreeQueue;

    /* Add all queue elements to the free queue */
    for (i = 0; i < KEYBOARD_QUEUE_SIZE; i++) {
        element = &keyboardQueueElements[i];

        /* Insert element at the tail of the free queue */
        element->next = &keyboardFreeQueue;
        element->prev = keyboardFreeQueue.prev;
        keyboardFreeQueue.prev->next = element;
        keyboardFreeQueue.prev = element;
    }

    /* Initialize keyboard data queue as a circular doubly-linked list */
    keyboardQueue.next = &keyboardQueue;
    keyboardQueue.prev = &keyboardQueue;

    /* Initialize escape state */
    __escapeState = 0;

    /* Start the I/O thread for handling interrupts */
    [self startIOThread];

    return self;
}

- (void)setKeyboardObject:keyboard
{
    /* Store reference to the keyboard driver object */
    keyboardObject = keyboard;
}

- (void)setMouseObject:mouse
{
    /* Store reference to the mouse driver object in static variable */
    __mouse = mouse;
}

- (void)setManualDataHandling:(BOOL)manual
{
    /* Store the manual data handling flag */
    manualDataHandling = manual;

    if (manual) {
        /* Disable interrupts when in manual mode */
        [self disableAllInterrupts];
    } else {
        /* Re-enable interrupts when returning to normal mode */
        [self enableAllInterrupts];
    }
}

- (void)setLEDs:(unsigned char)leds
{
    /* Enable manual data handling to prevent interrupt processing */
    [self setManualDataHandling:YES];

    /* Send LED command (0xED) to keyboard */
    _sendControllerData(0xED);

    /* Wait for and get keyboard acknowledgment */
    _getKeyboardData();

    /* Send LED state byte */
    _sendControllerData(leds);

    /* Wait for and get keyboard acknowledgment */
    _getKeyboardData();

    /* Restore normal interrupt processing */
    [self setManualDataHandling:NO];
}

- (void)interruptOccurred
{
    /* Forward the interrupt notification to the keyboard object */
    [keyboardObject interruptOccurred];
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)level
          argument:(unsigned int *)arg
       forInterrupt:(unsigned int)interrupt
{
    /* Set the interrupt handler function */
    *handler = (IOInterruptHandler)interruptHandler;

    /* Set interrupt priority level to 6 (IPL_BIO) */
    *level = 6;

    /* Set handler argument to 0 */
    *arg = 0;

    /* Return YES to indicate success */
    return YES;
}

- (PS2ControllerFunctions *)controllerAccessFunctions
{
    /* Return pointer to exported functions structure */
    return &_exported_funcs;
}

@end

/* Helper function: Lock the controller for atomic operations */
void _lock_controller(void)
{
    int savedSPL;
    int lockValue;
    volatile int *lockPtr;

    /* Set interrupt priority level to 6 (IPL_BIO) and save old level */
    savedSPL = spln(6);

    /* Point to the lock flag at _controller_lock[1] */
    lockPtr = &_controller_lock[1];

    /* Test-and-set spinlock with hardware lock prefix */
    do {
        /* Busy wait while lock is held */
        while (*lockPtr != 0) {
            /* Spin */
        }

        /* Atomic test-and-set using hardware lock */
        LOCK();
        lockValue = *lockPtr;     /* Read current value */
        *lockPtr = 1;             /* Set lock to 1 */
        UNLOCK();

        /* If we read 1, someone else got the lock first, retry */
    } while (lockValue == 1);

    /* Store the saved SPL in _controller_lock[0] */
    _controller_lock[0] = savedSPL;
}

/* Helper function: Unlock the controller */
void _unlock_controller(void)
{
    /* Clear the lock flag atomically */
    LOCK();
    _controller_lock[1] = 0;
    UNLOCK();

    /* Restore the saved interrupt priority level */
    splx(_controller_lock[0]);
}

/* Helper function: Read data directly from the keyboard without waiting */
unsigned char _reallyGetKeyboardData(void)
{
    unsigned char status;
    unsigned char data;

    /* Wait for keyboard data to be available in the output buffer */
    while (1) {
        /* Read status register from port 100 (0x64) */
        status = inb(PS2_STATUS_PORT);

        /* Check if output buffer is full (bit 0 set) */
        if ((status & 1) != 0) {
            /* Data is available */
            break;
        }

        /* Delay before checking again */
        IODelay(7);
    }

    /* Delay before reading the data */
    IODelay(7);

    /* Read and return the data from port 0x60 */
    data = inb(PS2_DATA_PORT);

    return data;
}

/* Helper function: Clear the PS/2 controller output buffer */
void clearOutputBuffer(void)
{
    unsigned char status;

    /* Lock the controller */
    _lock_controller();

    /* Read status register from port 100 (0x64) */
    status = inb(PS2_STATUS_PORT);

    /* Check if output buffer has data (bit 0) or auxiliary device data (bit 5) */
    if ((status & 0x21) != 0) {
        /* Data present - delay and read to clear the buffer */
        IODelay(7);

        /* Read and discard the data from port 0x60 */
        inb(PS2_DATA_PORT);
    }

    /* Unlock the controller */
    _unlock_controller();
}

/* Helper function: Process escape sequences (extended scancodes) */
BOOL _doEscape(unsigned char data)
{
    unsigned char previousExtended;
    unsigned short currentKey;
    EscapeSequence *escapePtr;
    EscapeSequence *nextEscape;
    BOOL isMatch;

    /* Save the previous extended state */
    previousExtended = _lastExtended;

    /* Check if this is the extended scancode prefix (0xE0) */
    if ((char)data == (char)0xE0) {  /* -0x20 in signed char = 0xE0 */
        /* Set extended flag and return - don't process this byte further */
        _lastExtended = 1;
        return NO;  /* Return 0 as in decompiled code */
    } else {
        /* Clear extended flag for next key */
        _lastExtended = 0;

        /* Combine extended flag with scancode to form 16-bit key value */
        /* CONCAT11(previousExtended, data) combines byte previousExtended
           with byte data into a 16-bit value */
        currentKey = ((unsigned short)previousExtended << 8) | (unsigned short)data;

        /* Check if this is the same as the last key - avoid duplicate processing */
        if ((_lastKey & 0xFF) != data || (_lastKey >> 8) != previousExtended) {
            /* This is a new key - update last key tracking */
            _lastKey = currentKey;

            /* Search through escape sequences array */
            escapePtr = _escapes;

            while (1) {
                /* Check for terminator (offset 0x12 in the structure) */
                nextEscape = escapePtr + 1;  /* Move to next structure */
                if (escapePtr->terminator == NULL) {
                    break;  /* End of array */
                }

                /* Check if this escape sequence matches the current key */
                isMatch = _isEscape(currentKey, escapePtr);

                if (isMatch) {
                    /* Found a match - execute the callback */
                    _disableMouse();

                    /* Call the callback function at offset 6 with args at 7, 8, 9 */
                    if (escapePtr->callback != NULL) {
                        escapePtr->callback(escapePtr->arg1, escapePtr->arg2, escapePtr->arg3);
                    }

                    _enableMouse();
                    _undoEscape(escapePtr);
                    _resetEscapes();

                    return YES;  /* Return 1 - escape was handled */
                }

                /* Move to next escape sequence (increment by structure size) */
                escapePtr = nextEscape;
            }
        }
    }

    return NO;  /* Return 0 - not an escape or no match found */
}

/* Helper function: Enqueue keyboard data to the circular buffer */
void _enqueueKeyboardData(unsigned char data)
{
    PS2QueueElement *element;
    PS2QueueElement *nextElement;
    PS2QueueElement *prevElement;
    PS2QueueElement *tempPtr;
    PS2Controller *controller = (PS2Controller *)___controller;

    if (controller == nil) {
        return;
    }

    /* Get a free queue element from the head of the free queue */
    element = controller->keyboardFreeQueue.next;

    /* Check if we have a free element (not pointing to the queue head) */
    if (element == &controller->keyboardFreeQueue) {
        /* No free elements - queue is full */
        return;
    }

    /* Remove element from free queue */
    nextElement = element->next;
    prevElement = element->prev;

    /* Update the previous element's next pointer */
    tempPtr = &controller->keyboardFreeQueue;
    if (nextElement != &controller->keyboardFreeQueue) {
        tempPtr = nextElement;
    }
    tempPtr->prev = prevElement;

    /* Update the next element's prev pointer */
    tempPtr = &controller->keyboardFreeQueue;
    if (prevElement != &controller->keyboardFreeQueue) {
        tempPtr = prevElement;
    }
    tempPtr->next = nextElement;

    /* Store the data in the element */
    element->data = data;

    /* Add element to the keyboard data queue */
    if (controller->keyboardQueue.next == &controller->keyboardQueue) {
        /* Keyboard queue is empty - initialize it with this element */
        controller->keyboardQueue.next = element;
        controller->keyboardQueue.prev = element;
        element->next = &controller->keyboardQueue;
        element->prev = &controller->keyboardQueue;
    } else {
        /* Keyboard queue has elements - add to the tail */
        element->prev = controller->keyboardQueue.prev;
        element->next = &controller->keyboardQueue;
        controller->keyboardQueue.prev->next = element;
        controller->keyboardQueue.prev = element;
    }
}

/* C interrupt handler function */
void interruptHandler(void *identity, void *state, unsigned int arg)
{
    unsigned char status;
    unsigned char data;
    BOOL isEscape;
    PS2Controller *controller = (PS2Controller *)___controller;

    if (controller == nil) {
        return;
    }

    /* Check if manual data handling is disabled and data is available */
    if (!controller->manualDataHandling) {
        /* Read status register from port 0x64 */
        status = inb(PS2_STATUS_PORT);

        /* Check if output buffer is full (bit 0 set) */
        if (status & PS2_STATUS_OUTPUT_FULL) {
            /* Lock the controller */
            _lock_controller();

            /* Read keyboard data */
            data = _reallyGetKeyboardData();

            /* Unlock the controller */
            _unlock_controller();

            /* Process escape sequences */
            isEscape = _doEscape(data);

            /* If not an escape byte, enqueue the data */
            if (!isEscape) {
                _enqueueKeyboardData(data);
            }

            /* Send interrupt notification to the I/O thread */
            IOSendInterrupt(identity, state, 0x232325);
        }
    }
}

/* Helper function: Send command to the PS/2 controller command register */
void _sendControllerCommand(unsigned char command)
{
    unsigned char status;

    /* Lock the controller for the entire operation */
    _lock_controller();

    /* Wait for the controller input buffer to be ready (not full) */
    while (1) {
        status = inb(PS2_STATUS_PORT);
        if (!(status & PS2_STATUS_INPUT_FULL)) {
            /* Input buffer is ready */
            break;
        }
        /* Delay before checking again */
        IODelay(7);
    }

    /* Additional delay before writing */
    IODelay(7);

    /* Write the command byte to the controller command port (0x64) */
    outb(PS2_COMMAND_PORT, command);

    /* Update port access counter (with its own lock) */
    LOCK();
    _portAccessCount++;
    UNLOCK();

    /* Track the last byte sent */
    _lastSent = command;

    /* Unlock the controller */
    _unlock_controller();
}

/* Helper function: Send data to the PS/2 keyboard controller */
void _sendControllerData(unsigned char data)
{
    unsigned char status;

    /* Lock the controller for the entire operation */
    _lock_controller();

    /* Wait for the controller input buffer to be ready (not full) */
    while (1) {
        status = inb(PS2_STATUS_PORT);
        if (!(status & PS2_STATUS_INPUT_FULL)) {
            /* Input buffer is ready */
            break;
        }
        /* Delay before checking again */
        IODelay(7);
    }

    /* Additional delay before writing */
    IODelay(7);

    /* Write the data byte to the controller data port (0x60) */
    outb(PS2_DATA_PORT, data);

    /* Update port access counter (with its own lock) */
    LOCK();
    _portAccessCount++;
    UNLOCK();

    /* Track the last byte sent */
    _lastSent = data;

    /* Unlock the controller */
    _unlock_controller();
}

/* Helper function: Resend the last controller data */
void _resendControllerData(void)
{
    /* Check if we're expecting an acknowledgment */
    if (_pendingAck == 0) {
        /* Unexpected RESEND - log an error */
        IOLog("PS2Controller/resendControllerData: Unexpected RESEND from controller\n");
        return;
    }

    /* Resend the last data byte that was sent */
    _sendControllerData(_lastSent);
}

/* Helper function: Read data from the PS/2 mouse */
unsigned char _getMouseData(void)
{
    unsigned char status;
    unsigned char data;

    /* Lock the controller */
    _lock_controller();

    /* Delay to allow mouse data to be ready */
    IODelay(50000);

    /* Wait for mouse data to be available
     * Check for both output buffer full (bit 0) AND auxiliary device flag (bit 5) */
    do {
        status = inb(PS2_STATUS_PORT);
    } while ((status & 0x21) == 0);  /* Wait for bits 0 and 5 to be set */

    /* Delay before reading */
    IODelay(7);

    /* Read the data from port 0x60 */
    data = inb(PS2_DATA_PORT);

    /* Unlock the controller */
    _unlock_controller();

    return data;
}

/* Helper function: Check if mouse data is present and read it if available */
/* Helper function: Check if keyboard data is present and read it */
BOOL _getKeyboardDataIfPresent(unsigned char *data)
{
    BOOL hasData;
    unsigned char keyData;

    /* Lock the controller */
    _lock_controller();

    /* Check if keyboard data is present */
    hasData = _keyboardDataPresent();

    if (!hasData) {
        /* No keyboard data available */
        _unlock_controller();
    } else {
        /* Keyboard data is available */
        _unlock_controller();

        /* Read the keyboard data */
        keyData = _getKeyboardData();
        *data = keyData;
    }

    return hasData;
}

BOOL _getMouseDataIfPresent(unsigned char *data)
{
    unsigned char status;
    BOOL mouseDataPresent;

    if (data == NULL) {
        return NO;
    }

    /* Lock the controller */
    _lock_controller();

    /* Read status register from port 0x64 (100 decimal) */
    status = inb(PS2_STATUS_PORT);

    /* Check if bit 5 (0x20) is set - indicates auxiliary device (mouse) data */
    mouseDataPresent = (status & 0x20) == 0;

    if (mouseDataPresent) {
        /* No mouse data present - unlock and return false */
        _unlock_controller();
    } else {
        /* Mouse data is present - read it */
        IODelay(7);

        /* Read the data from port 0x60 */
        *data = inb(PS2_DATA_PORT);

        _unlock_controller();
    }

    /* Return true if mouse data was present (invert the flag) */
    return !mouseDataPresent;
}

/* Helper function: Send command to the PS/2 mouse */
BOOL _sendMouseCommand(unsigned char command)
{
    unsigned char response;

    /* Send the "Write to Auxiliary Device" command (0xD4) to controller */
    _sendControllerCommand(0xD4);

    /* Send the actual mouse command as data */
    _sendControllerData(command);

    /* Read the mouse's acknowledgment response */
    response = _getMouseData();

    /* Check if response is 0xFA (acknowledgment)
     * The decompiled code checks for -6, which is 0xFA in signed char */
    return (response == 0xFA);  /* Return true if ACK received */
}

/* Helper function: Read data from the keyboard */
unsigned char _getKeyboardData(void)
{
    PS2QueueElement *element;
    PS2QueueElement *nextElement;
    PS2QueueElement *prevElement;
    unsigned char data;
    PS2Controller *controller = (PS2Controller *)___controller;

    /* Lock the controller for the entire operation */
    _lock_controller();

    if (controller == nil) {
        _unlock_controller();
        return 0;
    }

    /* Check if keyboard queue is empty (points to itself) */
    if (controller->keyboardQueue.next == &controller->keyboardQueue) {
        /* Queue is empty - read directly from hardware */
        data = _reallyGetKeyboardData();
    } else {
        /* Queue has data - dequeue the first element */
        element = controller->keyboardQueue.next;

        /* Get next and prev pointers */
        nextElement = element->next;
        prevElement = element->prev;

        /* Remove element from keyboard data queue by updating links */
        /* Update the previous element's next pointer */
        if (nextElement != &controller->keyboardQueue) {
            nextElement->prev = prevElement;
        } else {
            controller->keyboardQueue.prev = prevElement;
        }

        /* Update the next element's prev pointer */
        if (prevElement != &controller->keyboardQueue) {
            prevElement->next = nextElement;
        } else {
            controller->keyboardQueue.next = nextElement;
        }

        /* Extract the data from the element */
        data = element->data;

        /* Return the element to the free queue */
        /* Check if free queue is empty */
        if (controller->keyboardFreeQueue.next == &controller->keyboardFreeQueue) {
            /* Free queue is empty - initialize it with this element */
            controller->keyboardFreeQueue.next = element;
            controller->keyboardFreeQueue.prev = element;
            element->next = &controller->keyboardFreeQueue;
            element->prev = &controller->keyboardFreeQueue;
        } else {
            /* Free queue has elements - add to the tail */
            element->prev = controller->keyboardFreeQueue.prev;
            element->next = &controller->keyboardFreeQueue;
            controller->keyboardFreeQueue.prev->next = element;
            controller->keyboardFreeQueue.prev = element;
        }
    }

    /* Unlock the controller */
    _unlock_controller();

    return data;
}

/* Escape sequence helper functions */

/* Check if a key matches an escape sequence */
BOOL _isEscape(unsigned short key, EscapeSequence *escape)
{
    unsigned char scancodeChar;
    unsigned char extendedChar;
    KeySequenceEntry **sequenceArray;
    KeySequenceEntry *currentSeq;
    unsigned char *keyBytes;
    int numKeysDown;
    int sequenceLength;
    int currentIndex;

    if (escape == NULL) {
        return NO;
    }

    /* Extract scancode and extended flag from 16-bit key */
    scancodeChar = (unsigned char)(key & 0xFF);        /* Lower byte */
    extendedChar = (unsigned char)((key >> 8) & 0xFF); /* Upper byte */

    /* Check if we're starting a new sequence match */
    if (escape->currentSequence == NULL) {
        /* Not currently matching - search all sequences */
        sequenceArray = escape->sequences;

        /* Loop through all sequence entries until we hit NULL */
        while (*sequenceArray != NULL) {
            currentSeq = *sequenceArray;

            /* Calculate position in key sequence array
             * Offset 8 is start of keys array
             * currentSeq->index * 2 gives position (2 bytes per key)
             */
            keyBytes = (unsigned char *)currentSeq + 8 + (currentSeq->index * 2);

            /* Compare scancode and extended bytes */
            if ((keyBytes[0] == scancodeChar) && (keyBytes[1] == extendedChar)) {
                /* Found a matching sequence - set up state */
                escape->field11 = (void *)currentSeq;
                escape->currentSequence = (void *)currentSeq;

                /* Set index to 1 (we've matched first key) */
                currentSeq->index = 1;

                return NO;  /* Return 0 - sequence started but not complete */
            }

            /* Move to next sequence in array */
            sequenceArray++;
        }
    } else {
        /* Currently matching a sequence - check next key */
        currentSeq = (KeySequenceEntry *)escape->currentSequence;

        /* Calculate position of next expected key in sequence */
        keyBytes = (unsigned char *)currentSeq + 8 + (currentSeq->index * 2);

        /* Check if current key matches next expected key */
        if ((keyBytes[0] == scancodeChar) && (keyBytes[1] == extendedChar)) {
            /* Match - increment index */
            currentSeq->index++;

            /* Get sequence length from offset 0 (stored as int) */
            sequenceLength = *(int *)((unsigned char *)currentSeq + 0);

            /* Check if we've completed the sequence */
            if (currentSeq->index >= sequenceLength) {
                /* Reset index */
                currentSeq->index = 0;
                escape->currentSequence = NULL;

                /* Check if the number of keys currently held down
                 * matches the sequence length - 1 */
                numKeysDown = __PS2KeyboardNumKeysDown();
                if (numKeysDown == (sequenceLength - 1)) {
                    return YES;  /* Return 1 - sequence complete! */
                }
            }
        } else {
            /* Mismatch - reset sequence state */
            currentSeq->index = 0;
            escape->currentSequence = NULL;
        }
    }

    return NO;  /* Return 0 - no match or incomplete */
}

/* Disable mouse interrupts/processing */
void _disableMouse(void)
{
    /* Check if mouse driver is present */
    if (__mouse != nil) {
        /* Send PS/2 mouse command 0xF5 (Disable Data Reporting) */
        _sendMouseCommand(0xF5);
    }
}

/* Enable mouse interrupts/processing */
void _enableMouse(void)
{
    /* Check if mouse driver is present */
    if (__mouse != nil) {
        /* Send PS/2 mouse command 0xF4 (Enable Data Reporting) */
        _sendMouseCommand(0xF4);
    }
}

/* Undo/cleanup an escape sequence */
void _undoEscape(EscapeSequence *escape)
{
    KeySequenceEntry *sequence;
    int sequenceLength;
    int index;
    unsigned char scancode;
    unsigned char extended;

    if (escape == NULL) {
        return;
    }

    /* Get the matched sequence from field11 (offset 0x2c / 44 bytes) */
    sequence = (KeySequenceEntry *)escape->field11;

    /* Check if there's a sequence to undo */
    if (sequence != NULL) {
        /* Get the sequence length from offset 0 */
        sequenceLength = *(int *)sequence;

        /* Only proceed if we have keys to undo */
        if (sequenceLength > 0) {
            /* Loop through all keys in the sequence */
            for (index = 0; index < sequenceLength; index++) {
                /* Get the scancode and extended flag from the sequence
                 * Keys array starts at offset 8
                 * Each key is 2 bytes: [scancode, extended]
                 * Offset calculation: sequence + 8 + (index * 2)
                 */
                scancode = *((unsigned char *)sequence + 8 + (index * 2));
                extended = *((unsigned char *)sequence + 8 + (index * 2) + 1);

                /* If extended flag is set, enqueue the 0xE0 prefix */
                if (extended != 0) {
                    _enqueueKeyboardData(0xE0);
                }

                /* Enqueue the key release code (scancode OR 0x80)
                 * Setting bit 7 converts key press to key release */
                _enqueueKeyboardData(scancode | 0x80);
            }
        }
    }
}

/* Reset all escape sequence state */
void _resetEscapes(void)
{
    void **escapePtr;
    void **terminatorPtr;
    void **currentSeqPtr;

    /* Reset global escape tracking state */
    _lastExtended = 0;
    _lastKey = 0;

    /* Loop through all escape sequences and reset their state */
    escapePtr = (void **)_escapes;

    do {
        /* Check if this escape has an active sequence (offset 10/0xa) */
        if (escapePtr[10] != NULL) {
            /* Get pointer to current sequence entry */
            currentSeqPtr = (void **)escapePtr[10];

            /* Reset the sequence's index to 0 (offset 4 in KeySequenceEntry) */
            currentSeqPtr[1] = 0;  /* index is at offset 4 = element 1 */

            /* Clear the current sequence pointer */
            escapePtr[10] = NULL;
        }

        /* Save pointer to terminator field (offset 0x12 = 18) */
        terminatorPtr = escapePtr + 0x12;

        /* Advance to next escape sequence entry
         * Structure stride is 0xc (12) pointer-sized elements */
        escapePtr = escapePtr + 0xc;

        /* Check if we've reached the end (terminator is NULL) */
    } while (*terminatorPtr != NULL);
}
