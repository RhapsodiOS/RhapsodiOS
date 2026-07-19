/*
 * PS2Keyboard.h
 * PS/2 Keyboard Driver
 */

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <objc/Object.h>
#import <objc/NXLock.h>
#import "PS2Controller.h"

/* Keyboard event structure - 16 bytes (4 ints) */
typedef struct {
    unsigned int timestamp_high;
    unsigned int timestamp_low;
    unsigned int keyCode;
    unsigned int flags;
} PS2KeyboardEvent;

#define MAX_KEYBOARD_EVENTS 16

@interface PS2Keyboard : IODevice
{
    id controller;                          /* Offset 0x108 */
    int eventCount;                         /* Offset 0x10c */
    PS2KeyboardEvent eventQueue[MAX_KEYBOARD_EVENTS];  /* Offset 0x110 - event buffer */
    int interfaceID;                        /* Offset 0x210 */
    int handlerID;                          /* Offset 0x214 */
    id keyboardOwner;                       /* Offset 0x218 */
    id desiredOwner;                        /* Offset 0x21c */
    NXLock *ownerLock;                      /* Offset 0x220 */
    BOOL alphaLockLED;
}

/* Class methods */
+ (int)deviceStyle;
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
+ (Protocol **)requiredProtocols;

/* Instance initialization */
- initWithController:(id)controllerInstance;

/* Keyboard ownership management */
- (BOOL)becomeOwner:(id)owner;
- (BOOL)desireOwnership:(id)owner;
- (int)relinquishOwnership:(id)owner;

/* Keyboard event handling */
- (void)interruptOccurred;
- (void)dispatchKeyboardEvents;
- (void)enqueueKeyEvent:(unsigned int)keyCode
              goingDown:(BOOL)goingDown
                 atTime:(unsigned long long)timestamp;

/* Configuration */
- (BOOL)readConfigTable:(IOConfigTable *)configTable;
- (void)setAlphaLockFeedback:(BOOL)on;

/* Identification */
- (int)handlerId;
- (int)interfaceId;

@end
