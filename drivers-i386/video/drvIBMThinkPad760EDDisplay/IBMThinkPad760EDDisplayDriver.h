/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * IBM ThinkPad 760ED Display Driver
 */

#import <driverkit/IODirectDevice.h>
#import <driverkit/IOFrameBufferDisplay.h>

@interface IBMThinkPad760EDDisplayDriver : IOFrameBufferDisplay
{
    IODisplayInfo displayInfo;
    IORange *memRanges;
    unsigned int numMemRanges;
    IORange *ioRanges;
    unsigned int numIORanges;

    /* Frame buffer mapping */
    vm_address_t frameBufferAddr;
    unsigned int frameBufferLength;

    /* Register mapping */
    vm_address_t registerAddr;
    unsigned int registerLength;

    /* Display configuration */
    unsigned int displayWidth;
    unsigned int displayHeight;
    unsigned int displayDepth;
    unsigned int displayRefresh;
    unsigned int displayRowBytes;

    /* Hardware state */
    BOOL isEnabled;
    BOOL isInitialized;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* IODevice overrides */
- (IOReturn)getDeviceMemory:(IORange **)memory count:(unsigned int *)count;
- (void)free;

/* IOFrameBufferDisplay overrides */
- (IODisplayInfo *)displayInfo;
- (IOReturn)selectMode:(const IODisplayInfo *)mode;
- (IOReturn)getMode:(IODisplayInfo *)mode;
- (IOReturn)enterLinearMode;
- (IOReturn)revertToVGAMode;
- (IOReturn)getBrightness:(int *)brightness;
- (IOReturn)setBrightness:(int)brightness;

/* Private methods */
- (BOOL)mapMemoryRanges;
- (void)unmapMemoryRanges;
- (BOOL)initHardware;
- (void)resetHardware;
- (void)setDisplayMode:(unsigned int)width height:(unsigned int)height depth:(unsigned int)depth;

@end
