/*
 * PS2Controller.h
 * PS/2 Keyboard Controller Driver
 */

#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IODirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/IODevice.h>

#define KEYBOARD_QUEUE_SIZE 32

/* Queue element structure for keyboard data */
typedef struct _PS2QueueElement {
    struct _PS2QueueElement *next;
    struct _PS2QueueElement *prev;
    unsigned char data;
} PS2QueueElement;

/* Controller access functions structure - exported to other drivers */
typedef struct {
    void (*sendControllerCommand)(unsigned char command);
    unsigned char (*getKeyboardData)(void);
    BOOL (*getKeyboardDataIfPresent)(unsigned char *data);
    void (*clearOutputBuffer)(void);
    void (*sendControllerData)(unsigned char data);
    BOOL (*sendMouseCommand)(unsigned char command);
    unsigned char (*getMouseData)(void);
    BOOL (*getMouseDataIfPresent)(unsigned char *data);
} PS2ControllerFunctions;

@interface PS2Controller : IODirectDevice
{
    id keyboardObject;
    BOOL manualDataHandling;

    /* Keyboard data queues */
    PS2QueueElement keyboardFreeQueue;
    PS2QueueElement keyboardQueue;
    PS2QueueElement keyboardQueueElements[KEYBOARD_QUEUE_SIZE];
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)setKeyboardObject:keyboard;
- (void)setMouseObject:mouse;
- (void)setManualDataHandling:(BOOL)manual;
- (void)setLEDs:(unsigned char)leds;
- (void)interruptOccurred;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)level
          argument:(unsigned int *)arg
       forInterrupt:(unsigned int)interrupt;
- (PS2ControllerFunctions *)controllerAccessFunctions;

@end

/* C interrupt handler function */
void interruptHandler(void *identity, void *state, unsigned int arg);

/* Escape sequence handler callback function type */
typedef void (*EscapeCallback)(void *arg1, void *arg2, void *arg3);

/* Key sequence entry structure - represents one key in a sequence */
typedef struct _KeySequenceEntry {
    void *next;                     /* Offset 0: Next entry or NULL */
    int index;                      /* Offset 4: Current index in sequence */
    unsigned char keys[];           /* Offset 8: Array of key bytes (scancode, extended) */
} KeySequenceEntry;

/* Escape sequence structure */
typedef struct _EscapeSequence {
    KeySequenceEntry **sequences;   /* Offset 0: Array of pointers to key sequences */
    void *field1;
    void *field2;
    void *field3;
    void *field4;
    void *field5;
    EscapeCallback callback;        /* Offset 6: Callback function */
    void *arg1;                     /* Offset 7: Callback argument 1 */
    void *arg2;                     /* Offset 8: Callback argument 2 */
    void *arg3;                     /* Offset 9: Callback argument 3 */
    void *currentSequence;          /* Offset 10: Current sequence being matched */
    void *field11;                  /* Offset 11: Additional state */
    void *field12;
    void *field13;
    void *field14;
    void *field15;
    void *field16;
    void *field17;
    void *terminator;               /* Offset 0x12: NULL terminator */
} EscapeSequence;

/* Helper functions for PS/2 controller I/O */
void _sendControllerCommand(unsigned char command);
void _sendControllerData(unsigned char data);
void _resendControllerData(void);
unsigned char _getKeyboardData(void);
unsigned char _getMouseData(void);
BOOL _keyboardDataPresent(void);
BOOL _getKeyboardDataIfPresent(unsigned char *data);
BOOL _getMouseDataIfPresent(unsigned char *data);
unsigned char _reallyGetKeyboardData(void);
void _lock_controller(void);
void _unlock_controller(void);
void clearOutputBuffer(void);
BOOL _doEscape(unsigned char data);
void _enqueueKeyboardData(unsigned char data);
BOOL _sendMouseCommand(unsigned char command);

/* Mini-monitor entry point (kernel debugger) */
extern void _mini_mon(const char *arg1, const char *arg2, const char *arg3);

/* Escape sequence helper functions */
BOOL _isEscape(unsigned short key, EscapeSequence *escape);
void _disableMouse(void);
void _enableMouse(void);
void _undoEscape(EscapeSequence *escape);
void _resetEscapes(void);

/* External functions from PS2Keyboard */
int __PS2KeyboardNumKeysDown(void);
