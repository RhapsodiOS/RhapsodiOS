/*
 * PS2Keyboard.h
 * PS/2 Keyboard Driver
 */

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <objc/Object.h>
#import <bsd/dev/i386/PCKeyboardDefs.h>
#import "PS2Controller.h"

/* Keyboard event structure - 16 bytes */
typedef struct {
    ns_time_t timeStamp;
    unsigned int keyCode;
    BOOL goingDown;
} PS2KeyboardEvent;

#define MAX_KEYBOARD_EVENTS 16

@interface PS2Keyboard : IODevice <PCKeyboardExported>
{
    id controller;                          /* Offset 0x108 */
    unsigned int numEvents;                 /* Offset 0x10c */
    PS2KeyboardEvent pendingEvents[MAX_KEYBOARD_EVENTS];  /* Offset 0x110 */
    unsigned int interfaceId;               /* Offset 0x210 */
    unsigned int handlerId;                 /* Offset 0x214 */
    id _owner;                              /* Offset 0x218 */
    id _desiredOwner;                       /* Offset 0x21c */
    id _ownerLock;                          /* Offset 0x220 - never assigned */
}

/* Class methods */
+ (int)deviceStyle;
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
+ (Protocol **)requiredProtocols;

/* Instance initialization */
- initWithController:(id)controllerInstance;

/* Keyboard event handling */
- (void)interruptOccurred;
- (void)dispatchKeyboardEvents;
- (void)enqueueKeyEvent:(int)keyCode
              goingDown:(BOOL)goingDown
                 atTime:(unsigned long long)timestamp;

/* Configuration */
- (BOOL)readConfigTable:(IOConfigTable *)configTable;
- (void)setAlphaLockFeedback:(BOOL)on;

/* Identification */
- (int)handlerId;
- (int)interfaceId;

@end

/* Implemented in PS2Keyboard.m */
PS2KeyboardEvent *scancodeToKeyEvent(unsigned char scancode);

/* Implemented in PS2Controller.m */
PS2KeyboardEvent *NewStealKeyboardEvent(void);
