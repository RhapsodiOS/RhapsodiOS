/*
 * PS2Controller.m
 * PS/2 Keyboard Controller Driver
 */

#import "PS2Controller.h"
#import "PS2Keyboard.h"
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

/*
 * Controller state.  None of this lives in the instance: the driver keeps a
 * single controller and reaches its state through file-scope storage.
 */
static id _controller;
static id _mouse;
static unsigned char lastSent;
static int pendingAck;          /* Set when we are waiting for an ACK */

/* Keyboard data queues */
static PS2QueueHead keyboardQueue;
static PS2QueueHead keyboardFreeQueue;
PS2QueueElement keyboardQueueElements[KEYBOARD_QUEUE_SIZE];

/* The heads double as the list sentinels */
#define KBD_QUEUE       ((PS2QueueElement *)&keyboardQueue)
#define KBD_FREE_QUEUE  ((PS2QueueElement *)&keyboardFreeQueue)

/* Keyboard object and interrupt-time data handling mode */
static id keyboardObject;
static BOOL manualDataHandling;

/* Two words allocated with kalloc: [0] saved SPL, [1] spinlock flag */
static volatile int *controller_lock;

/* Internal helpers */
static void lock_controller(void);
static void unlock_controller(void);
static unsigned char reallyGetKeyboardData(void);
static void enqueueKeyboardData(unsigned char data);
static BOOL isEscape(unsigned short key, EscapeSequence *escape);
static void resetEscapes(void);
static void undoEscape(EscapeSequence *escape);
static BOOL doEscape(unsigned char data);
static void interruptHandler(void *identity, void *state, unsigned int arg);

/*
 * Structure of exported controller functions - provides access to PS/2
 * controller functionality for the keyboard and mouse drivers.
 */
struct controller_funcs exported_funcs = {
    sendControllerCommand,
    getKeyboardData,
    getKeyboardDataIfPresent,
    clearOutputBuffer,
    sendControllerData,
    sendMouseCommand,
    getMouseData,
    getMouseDataIfPresent
};

/* Key sequences that spell out the mini-monitor escapes */

static KeySequenceEntry lalt_ralt_numlock = {
    3, 0,
    { 0x38, 0x00,   /* Left Alt */
      0x38, 0x01,   /* Right Alt (extended) */
      0x45, 0x00,   /* Num Lock */
      0x00, 0x00 }
};

static KeySequenceEntry ralt_lalt_numlock = {
    3, 0,
    { 0x38, 0x01,   /* Right Alt (extended) */
      0x38, 0x00,   /* Left Alt */
      0x45, 0x00,   /* Num Lock */
      0x00, 0x00 }
};

static KeySequenceEntry lalt_numlock = {
    2, 0,
    { 0x38, 0x00,   /* Left Alt */
      0x45, 0x00,   /* Num Lock */
      0x00, 0x00,
      0x00, 0x00 }
};

static KeySequenceEntry ralt_numlock = {
    2, 0,
    { 0x38, 0x01,   /* Right Alt (extended) */
      0x45, 0x00,   /* Num Lock */
      0x00, 0x00,
      0x00, 0x00 }
};

/*
 * Escape table.  Each entry groups the alternative key sequences that trigger
 * the same action; a NULL callback terminates the table.
 */
static EscapeSequence escapes[] = {
    /* Alt + Num Lock, either Alt - restart */
    { { &lalt_numlock, &ralt_numlock, NULL, NULL, NULL, NULL },
      (EscapeCallback)mini_mon, (void *)"restart", (void *)"Restart", NULL,
      NULL, NULL },

    /* Both Alts + Num Lock - drop into the mini-monitor */
    { { &lalt_ralt_numlock, &ralt_lalt_numlock, NULL, NULL, NULL, NULL },
      (EscapeCallback)mini_mon, (void *)"", (void *)"Mini-Monitor", NULL,
      NULL, NULL },

    /* Terminator */
    { { NULL, NULL, NULL, NULL, NULL, NULL },
      NULL, NULL, NULL, NULL, NULL, NULL }
};

/* Helper function: Lock the controller for atomic operations */
static void lock_controller(void)
{
    int savedSPL;
    int lockValue;
    volatile int *lockPtr;

    /* Set interrupt priority level to 6 -- IPLDMA/IPLCLOCK/IPLSCHED in
     * <kernserv/i386/spl.h>, not IPLBIO, which is 3 -- and save old level
     */
    savedSPL = spln(6);

    /* Point to the lock flag at controller_lock[1] */
    lockPtr = &controller_lock[1];

    do {
        /* Busy wait while the lock is held */
        while (*lockPtr != 0) {
            /* Spin */
        }

        /* Atomic test-and-set; xchg carries an implicit bus lock */
        asm volatile("xchgl %0, %1"
                     : "=r" (lockValue), "=m" (*lockPtr)
                     : "0" (1)
                     : "memory");

        /* If we read 1, someone else got the lock first, retry */
    } while (lockValue == 1);

    /* Store the saved SPL in controller_lock[0] */
    controller_lock[0] = savedSPL;
}

/* Helper function: Unlock the controller */
static void unlock_controller(void)
{
    volatile int *lockPtr;
    int zero;

    lockPtr = &controller_lock[1];
    zero = 0;

    asm volatile("xchgl %0, %1"
                 : "=r" (zero), "=m" (*lockPtr)
                 : "0" (zero)
                 : "memory");

    /* Restore the saved interrupt priority level */
    splx(controller_lock[0]);
}

@implementation PS2Controller

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id instance;

    /* Allocate a new instance of PS2Controller */
    instance = [self alloc];

    if (instance == nil) {
        return NO;
    }

    /* Initialize global state */
    _controller = instance;
    _mouse = nil;
    pendingAck = 0;

    /* Allocate memory for the controller lock (8 bytes = 2 ints) */
    controller_lock = (volatile int *)kalloc(8);

    /* Initialize lock flag to 0 (unlocked) */
    controller_lock[1] = 0;

    /* Initialize the instance with the device description */
    instance = [instance initFromDeviceDescription:deviceDescription];

    return (instance != nil);
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

    /* Initialize keyboard free queue as a circular doubly-linked list */
    keyboardFreeQueue.prev = KBD_FREE_QUEUE;
    keyboardFreeQueue.next = KBD_FREE_QUEUE;

    /* Add all queue elements to the free queue */
    for (i = 0; i < KEYBOARD_QUEUE_SIZE; i++) {
        if (keyboardFreeQueue.next == KBD_FREE_QUEUE) {
            element = &keyboardQueueElements[i];
            keyboardFreeQueue.next = element;
            keyboardFreeQueue.prev = element;
            element->next = KBD_FREE_QUEUE;
            element->prev = KBD_FREE_QUEUE;
        } else {
            element = &keyboardQueueElements[i];
            element->prev = keyboardFreeQueue.prev;
            element->next = KBD_FREE_QUEUE;
            keyboardFreeQueue.prev = element;
            element->prev->next = element;
        }
    }

    /* Initialize keyboard data queue as a circular doubly-linked list */
    keyboardQueue.prev = KBD_QUEUE;
    keyboardQueue.next = KBD_QUEUE;

    /* Start the I/O thread for handling interrupts */
    [self startIOThread];

    return self;
}

/*
 * Is there a byte for the keyboard to read?  The software queue is answered
 * first; only when it is empty does the hardware status register decide.
 */
BOOL keyboardDataPresent(void)
{
    if (keyboardQueue.next != KBD_QUEUE) {
        return 1;
    }

    return (inb(PS2_STATUS_PORT) & 0x01);
}

/* Helper function: Read data directly from the keyboard without waiting */
static unsigned char reallyGetKeyboardData(void)
{
    unsigned char status;

    /* Wait for keyboard data to be available in the output buffer */
    while (1) {
        status = inb(PS2_STATUS_PORT);

        if ((status & PS2_STATUS_OUTPUT_FULL) != 0) {
            break;
        }

        IODelay(7);
    }

    /* Delay before reading the data */
    IODelay(7);

    return inb(PS2_DATA_PORT);
}

/* Helper function: Enqueue keyboard data to the circular buffer */
static void enqueueKeyboardData(unsigned char data)
{
    PS2QueueElement *element;
    PS2QueueElement *nextElement;
    PS2QueueElement *prevElement;
    PS2QueueElement *tempPtr;

    /* Check if we have a free element (not pointing to the queue head) */
    if (keyboardFreeQueue.next == KBD_FREE_QUEUE) {
        /* No free elements - queue is full */
        return;
    }

    /* Get a free queue element from the head of the free queue */
    element = keyboardFreeQueue.next;

    /* Remove element from free queue */
    nextElement = element->next;
    prevElement = element->prev;

    tempPtr = KBD_FREE_QUEUE;
    if (nextElement != KBD_FREE_QUEUE) {
        tempPtr = nextElement;
    }
    tempPtr->prev = prevElement;

    tempPtr = KBD_FREE_QUEUE;
    if (prevElement != KBD_FREE_QUEUE) {
        tempPtr = prevElement;
    }
    tempPtr->next = nextElement;

    /* Store the data in the element */
    element->data = data;

    /* Add element to the keyboard data queue */
    if (keyboardQueue.next == KBD_QUEUE) {
        keyboardQueue.next = element;
        keyboardQueue.prev = element;
        element->next = KBD_QUEUE;
        element->prev = KBD_QUEUE;
    } else {
        tempPtr = keyboardQueue.prev;
        element->prev = tempPtr;
        element->next = KBD_QUEUE;
        keyboardQueue.prev = element;
        tempPtr->next = element;
    }
}

- (void)interruptOccurred
{
    /* Forward the interrupt notification to the keyboard object */
    [keyboardObject interruptOccurred];
}

/* Check if a key matches an escape sequence */
static BOOL isEscape(unsigned short key, EscapeSequence *escape)
{
    KeySequenceEntry **cursor;
    KeySequenceEntry *currentSeq;
    unsigned char *keyBytes;
    short extendedHalf;

    if (escape->currentSequence == NULL) {
        /* Not currently matching - try every alternative in this entry */
        extendedHalf = (short)key >> 8;
        for (cursor = escape->sequences; *cursor != NULL; cursor++) {
            currentSeq = *cursor;
            keyBytes = &currentSeq->keys[currentSeq->index * 2];

            if ((unsigned char)key == keyBytes[0] &&
                (unsigned char)extendedHalf == keyBytes[1]) {
                /* Found a matching sequence - start tracking it */
                escape->matchedSequence = currentSeq;
                escape->currentSequence = currentSeq;
                currentSeq->index = 1;

                return NO;
            }
        }
    } else {
        /* Currently matching a sequence - check the next key */
        currentSeq = escape->currentSequence;
        keyBytes = &currentSeq->keys[currentSeq->index * 2];
        extendedHalf = (short)key >> 8;

        if ((unsigned char)key == keyBytes[0] &&
            (unsigned char)extendedHalf == keyBytes[1]) {
            currentSeq->index++;

            if (currentSeq->index >= currentSeq->count) {
                /* Sequence complete */
                currentSeq->index = 0;
                escape->currentSequence = NULL;

                /* All but the last key must still be held down */
                if (_PS2KeyboardNumKeysDown() == currentSeq->count - 1) {
                    return YES;
                }
            }
        } else {
            /* Mismatch - reset sequence state */
            currentSeq->index = 0;
            escape->currentSequence = NULL;
        }
    }

    return NO;
}

/* Reset all escape sequence state */
static void resetEscapes(void)
{
    EscapeSequence *escapePtr;

    for (escapePtr = escapes; escapePtr->callback != NULL; escapePtr++) {
        if (escapePtr->currentSequence != NULL) {
            escapePtr->currentSequence->index = 0;
            escapePtr->currentSequence = NULL;
        }
    }
}

/* Undo an escape sequence by enqueueing the matching key releases */
static void undoEscape(EscapeSequence *escape)
{
    KeySequenceEntry *sequence;
    int index;
    unsigned char extended;

    sequence = escape->matchedSequence;

    if (sequence != NULL) {
        for (index = 0; index < sequence->count; index++) {
            extended = sequence->keys[index * 2 + 1];

            /* If extended flag is set, enqueue the 0xE0 prefix */
            if (extended != 0) {
                enqueueKeyboardData(0xE0);
            }

            /* Bit 7 turns the press into a release */
            enqueueKeyboardData(sequence->keys[index * 2] | 0x80);
        }
    }
}

/* Helper function: Process escape sequences (extended scancodes) */
static BOOL doEscape(unsigned char data)
{
    static unsigned char lastExtended;      /* Last byte was 0xE0 */
    static unsigned short lastKey;          /* Extended flag + scancode */
    unsigned char previousExtended;
    unsigned short currentKey;
    EscapeSequence *escapePtr;

    /* Check if this is the extended scancode prefix (0xE0) */
    if (data == 0xE0) {
        lastExtended = 1;
        return NO;
    }

    previousExtended = lastExtended;
    lastExtended = 0;

    /* Combine extended flag with scancode to form a 16-bit key value */
    currentKey = ((unsigned short)previousExtended << 8) |
                 (unsigned short)data;

    /* Ignore a repeat of the key we last looked at */
    if ((unsigned char)lastKey != data ||
        (unsigned char)((short)currentKey >> 8) != (unsigned char)(lastKey >> 8)) {
        lastKey = currentKey;

        for (escapePtr = escapes; escapePtr->callback != NULL; escapePtr++) {
            if (isEscape(currentKey, escapePtr)) {
                disableMouse();
                escapePtr->callback(escapePtr->arg1, escapePtr->arg2,
                                    escapePtr->arg3);
                enableMouse();
                undoEscape(escapePtr);
                resetEscapes();

                return YES;
            }
        }
    }

    return NO;
}

/* C interrupt handler function */
static void interruptHandler(void *identity, void *state, unsigned int arg)
{
    unsigned char status;
    unsigned char data;

    /* Nothing to do while the driver is reading the port by hand */
    if (!manualDataHandling) {
        status = inb(PS2_STATUS_PORT);

        if (status & PS2_STATUS_OUTPUT_FULL) {
            lock_controller();
            data = reallyGetKeyboardData();
            unlock_controller();

            /* If not an escape byte, enqueue the data */
            if (!doEscape(data)) {
                enqueueKeyboardData(data);
            }

            /* Send interrupt notification to the I/O thread */
            IOSendInterrupt(identity, state, 0x232325);
        }
    }
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)level
          argument:(unsigned int *)arg
       forInterrupt:(unsigned int)interrupt
{
    /* Set the interrupt handler function */
    *handler = (IOInterruptHandler)interruptHandler;

    /* Set interrupt priority level to 6 -- IPLDMA/IPLCLOCK/IPLSCHED in
     * <kernserv/i386/spl.h>, not IPLBIO, which is 3
     */
    *level = 6;

    /* Set handler argument to 0 */
    *arg = 0;

    return YES;
}

- (struct controller_funcs *)controllerAccessFunctions
{
    /* Return pointer to exported functions structure */
    return &exported_funcs;
}

- (void)setMouseObject:mouse
{
    /* Store reference to the mouse driver object in file-scope storage */
    _mouse = mouse;
}

- (void)setKeyboardObject:keyboard
{
    /* Store reference to the keyboard driver object */
    keyboardObject = keyboard;
}

- (void)setLEDs:(unsigned char)leds
{
    /* Enable manual data handling to prevent interrupt processing */
    [self setManualDataHandling:YES];

    /* Send LED command (0xED) to keyboard */
    sendControllerData(0xED);

    /* Wait for and get keyboard acknowledgment */
    getKeyboardData();

    /* Send LED state byte */
    sendControllerData(leds);

    /* Wait for and get keyboard acknowledgment */
    getKeyboardData();

    /* Restore normal interrupt processing */
    [self setManualDataHandling:NO];
}

- (void)setManualDataHandling:(BOOL)manual
{
    manualDataHandling = manual;

    if (manual) {
        /* Disable interrupts when in manual mode */
        [self disableAllInterrupts];
    } else {
        /* Re-enable interrupts when returning to normal mode */
        [self enableAllInterrupts];
    }
}

/* Helper function: Read data from the keyboard */
unsigned char getKeyboardData(void)
{
    PS2QueueElement *element;
    PS2QueueElement *nextElement;
    PS2QueueElement *prevElement;
    PS2QueueElement *tempPtr;
    unsigned char data;

    /* Lock the controller for the entire operation */
    lock_controller();

    if (keyboardQueue.next == KBD_QUEUE) {
        /* Queue is empty - read directly from hardware */
        data = reallyGetKeyboardData();
    } else {
        /* Queue has data - dequeue the first element */
        element = keyboardQueue.next;

        nextElement = element->next;
        prevElement = element->prev;

        tempPtr = KBD_QUEUE;
        if (nextElement != KBD_QUEUE) {
            tempPtr = nextElement;
        }
        tempPtr->prev = prevElement;

        tempPtr = KBD_QUEUE;
        if (prevElement != KBD_QUEUE) {
            tempPtr = prevElement;
        }
        tempPtr->next = nextElement;

        data = element->data;

        /* Return the element to the free queue */
        if (keyboardFreeQueue.next != KBD_FREE_QUEUE) {
            prevElement = keyboardFreeQueue.prev;
            element->prev = prevElement;
            element->next = KBD_FREE_QUEUE;
            keyboardFreeQueue.prev = element;
            prevElement->next = element;
        } else {
            keyboardFreeQueue.next = element;
            keyboardFreeQueue.prev = element;
            element->next = KBD_FREE_QUEUE;
            element->prev = KBD_FREE_QUEUE;
        }
    }

    unlock_controller();

    return data;
}

/* Helper function: Check if keyboard data is present and read it */
BOOL getKeyboardDataIfPresent(unsigned char *data)
{
    lock_controller();

    if (!keyboardDataPresent()) {
        unlock_controller();
        return 0;
    } else {
        unlock_controller();
        *data = getKeyboardData();
        return 1;
    }
}

/* Helper function: Read data from the PS/2 mouse */
unsigned char getMouseData(void)
{
    unsigned char status;
    unsigned char data;

    lock_controller();

    /* Delay to allow mouse data to be ready */
    IODelay(50000);

    /* Wait for output-buffer-full or auxiliary-device data */
    do {
        status = inb(PS2_STATUS_PORT);
    } while ((status & 0x21) == 0);

    IODelay(7);

    data = inb(PS2_DATA_PORT);

    unlock_controller();

    return data;
}

/* Helper function: Check if mouse data is present and read it if available */
BOOL getMouseDataIfPresent(unsigned char *data)
{
    unsigned char status;

    lock_controller();

    status = inb(PS2_STATUS_PORT);

    /* Bit 5 (0x20) marks auxiliary device (mouse) data */
    if (!(status & 0x20)) {
        unlock_controller();
        return 0;
    } else {
        IODelay(7);

        *data = inb(PS2_DATA_PORT);

        unlock_controller();
        return 1;
    }
}

/* Helper function: Clear the PS/2 controller output buffer */
void clearOutputBuffer(void)
{
    unsigned char status;

    lock_controller();

    status = inb(PS2_STATUS_PORT);

    /* Output buffer (bit 0) or auxiliary device data (bit 5) */
    if ((status & 0x21) != 0) {
        IODelay(7);

        /* Read and discard */
        inb(PS2_DATA_PORT);
    }

    unlock_controller();
}

/* Helper function: Send data to the PS/2 keyboard controller */
void sendControllerData(unsigned char data)
{
    unsigned char status;

    lock_controller();

    /* Wait for the controller input buffer to be ready (not full) */
    while (1) {
        status = inb(PS2_STATUS_PORT);
        if (!(status & PS2_STATUS_INPUT_FULL)) {
            break;
        }
        IODelay(7);
    }

    IODelay(7);

    /* Write the data byte to the controller data port (0x60) */
    outb(PS2_DATA_PORT, data);

    /* Only data bytes are replayable on a RESEND */
    lastSent = data;

    unlock_controller();
}

/* Helper function: Resend the last controller data */
void resendControllerData(void)
{
    /* Check if we're expecting an acknowledgment */
    if (pendingAck == 0) {
        IOLog("PS2Controller/resendControllerData: Unexpected RESEND from controller\n");
        return;
    }

    sendControllerData(lastSent);
}

/* Helper function: Send command to the PS/2 controller command register */
void sendControllerCommand(unsigned char command)
{
    unsigned char status;

    lock_controller();

    /* Wait for the controller input buffer to be ready (not full) */
    while (1) {
        status = inb(PS2_STATUS_PORT);
        if (!(status & PS2_STATUS_INPUT_FULL)) {
            break;
        }
        IODelay(7);
    }

    IODelay(7);

    /* Write the command byte to the controller command port (0x64) */
    outb(PS2_COMMAND_PORT, command);

    unlock_controller();
}

/* Helper function: Send command to the PS/2 mouse */
BOOL sendMouseCommand(unsigned char command)
{
    unsigned char response;

    /* Send the Write to Auxiliary Device command (0xD4) to the controller */
    sendControllerCommand(0xD4);

    /* Send the actual mouse command as data */
    sendControllerData(command);

    /* Read the mouse's acknowledgment response */
    response = getMouseData();

    if (response != 0xFA) {
        return 0;
    } else {
        return 1;
    }
}

/* Disable mouse data reporting */
void disableMouse(void)
{
    if (_mouse != nil) {
        sendMouseCommand(0xF5);
    }
}

/* Enable mouse data reporting */
void enableMouse(void)
{
    if (_mouse != nil) {
        sendMouseCommand(0xF4);
    }
}

/*
 * Non-blocking function to "steal" a keyboard event if one is available.
 * Its address is published to the kernel by +[PS2Keyboard probe:].
 */
PS2KeyboardEvent *NewStealKeyboardEvent(void)
{
    unsigned char scancode;

    /* Try to get keyboard data if present (non-blocking) */
    if (!getKeyboardDataIfPresent(&scancode)) {
        return NULL;
    }

    /* ACK - unexpected here */
    if (scancode == 0xFA) {
        IOLog("PS2Keyboard: Unexpected ACK from controller\n");
        return NULL;
    }

    /* RESEND - the controller wants the last data byte again */
    if (scancode == 0xFE) {
        resendControllerData();
        return NULL;
    }

    return scancodeToKeyEvent(scancode);
}

@end
