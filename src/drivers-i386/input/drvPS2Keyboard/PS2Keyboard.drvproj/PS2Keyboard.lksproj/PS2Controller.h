/*
 * PS2Controller.h
 * PS/2 Keyboard Controller Driver
 */

#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/IODirectDevice.h>
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

/* Queue head: links only, no data byte */
typedef struct _PS2QueueHead {
    struct _PS2QueueElement *next;
    struct _PS2QueueElement *prev;
} PS2QueueHead;

/* Controller access functions structure - exported to other drivers */
struct controller_funcs {
    void (*sendControllerCommand)(unsigned char command);
    unsigned char (*getKeyboardData)(void);
    BOOL (*getKeyboardDataIfPresent)(unsigned char *data);
    void (*clearOutputBuffer)(void);
    void (*sendControllerData)(unsigned char data);
    BOOL (*sendMouseCommand)(unsigned char command);
    unsigned char (*getMouseData)(void);
    BOOL (*getMouseDataIfPresent)(unsigned char *data);
};

/*
 * The protocol an indirect device requires of the PS/2 controller.
 */
@protocol PS2ControllerExported

- (void)setLEDs:(unsigned char)leds;
- (void)setManualDataHandling:(BOOL)manual;
- (void)setKeyboardObject:keyboard;
- (void)setMouseObject:mouse;

@end

@interface PS2Controller : IODirectDevice <PS2ControllerExported>
{
    /* Declared but unused; they fix the instance layout at 308 bytes. */
    int portSet;                /* Offset 296 */
    id mouseObject;             /* Offset 300 */
    int pendingLEDVal;          /* Offset 304 */
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)interruptOccurred;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)level
          argument:(unsigned int *)arg
       forInterrupt:(unsigned int)interrupt;
- (struct controller_funcs *)controllerAccessFunctions;

@end

/* Escape sequence handler callback function type */
typedef void (*EscapeCallback)(void *arg1, void *arg2, void *arg3);

/* Key sequence entry - one alternative spelling of an escape sequence */
typedef struct _KeySequenceEntry {
    int count;                  /* Offset 0: number of key pairs */
    int index;                  /* Offset 4: current index in sequence */
    unsigned char keys[8];      /* Offset 8: (scancode, extended) pairs */
} KeySequenceEntry;

/* Escape sequence structure - 48 bytes */
typedef struct _EscapeSequence {
    KeySequenceEntry *sequences[6];     /* Words 0-5: NULL-terminated */
    EscapeCallback callback;            /* Word 6: also the table terminator */
    void *arg1;                         /* Word 7 */
    void *arg2;                         /* Word 8 */
    void *arg3;                         /* Word 9 */
    KeySequenceEntry *currentSequence;  /* Word 10: sequence being matched */
    KeySequenceEntry *matchedSequence;  /* Word 11: last sequence matched */
} EscapeSequence;

/* Mini-monitor entry point (kernel debugger) */
extern void mini_mon(const char *arg1, const char *arg2, const char *arg3);

/* Controller access functions, implemented in PS2Controller.m */
void sendControllerCommand(unsigned char command);
void sendControllerData(unsigned char data);
void resendControllerData(void);
unsigned char getKeyboardData(void);
unsigned char getMouseData(void);
BOOL keyboardDataPresent(void);
BOOL getKeyboardDataIfPresent(unsigned char *data);
BOOL getMouseDataIfPresent(unsigned char *data);
void clearOutputBuffer(void);
BOOL sendMouseCommand(unsigned char command);
void disableMouse(void);
void enableMouse(void);

/* Implemented in PS2Keyboard.m */
int _PS2KeyboardNumKeysDown(void);
