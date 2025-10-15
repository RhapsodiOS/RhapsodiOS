/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * IBM ThinkPad 760ED Display Driver
 */

#import "IBMThinkPad760EDDisplayDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@implementation IBMThinkPad760EDDisplayDriver

static IODisplayInfo defaultDisplayInfo = {
    800,                    // width
    600,                    // height
    800 * 2,                // rowBytes (16-bit color)
    60,                     // refreshRate
    16,                     // bitsPerPixel
    IO_15BitsPerPixel,      // colorSpace (RGB 555)
    "RGB:555/16",           // pixelEncoding
    0,                      // flags
    0                       // reserved
};

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    unsigned int vendorID, deviceID;

    if (![deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        return NO;
    }

    vendorID = [(IOPCIDeviceDescription *)deviceDescription vendorID];
    deviceID = [(IOPCIDeviceDescription *)deviceDescription deviceID];

    /* Check for Trident Cyber 9665 (PCI ID 0x96501023) */
    if (vendorID == 0x1023 && deviceID == 0x9650) {
        IOLog("IBMThinkPad760EDDisplayDriver: Found Trident Cyber 9665\n");
        return YES;
    }

    return NO;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    const char *memString, *ioString;
    int i;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Initialize state */
    isEnabled = NO;
    isInitialized = NO;

    /* Get memory ranges from device description */
    memString = [deviceDescription memoryRangeList];
    if (memString) {
        numMemRanges = [self stringToRange:(char *)memString
                                    ranges:&memRanges];
        IOLog("IBMThinkPad760EDDisplayDriver: Found %d memory ranges\n", numMemRanges);
    }

    /* Get I/O ranges from device description */
    ioString = [deviceDescription portRangeList];
    if (ioString) {
        numIORanges = [self stringToRange:(char *)ioString
                                   ranges:&ioRanges];
        IOLog("IBMThinkPad760EDDisplayDriver: Found %d I/O ranges\n", numIORanges);
    }

    /* Initialize default display info */
    displayInfo = defaultDisplayInfo;
    displayWidth = 800;
    displayHeight = 600;
    displayDepth = 16;
    displayRefresh = 60;
    displayRowBytes = 800 * 2;

    /* Map memory ranges */
    if (![self mapMemoryRanges]) {
        IOLog("IBMThinkPad760EDDisplayDriver: Failed to map memory ranges\n");
        [self free];
        return nil;
    }

    /* Initialize hardware */
    if (![self initHardware]) {
        IOLog("IBMThinkPad760EDDisplayDriver: Failed to initialize hardware\n");
        [self free];
        return nil;
    }

    isInitialized = YES;
    IOLog("IBMThinkPad760EDDisplayDriver: Initialized successfully\n");

    return self;
}

- (void)free
{
    [self unmapMemoryRanges];

    if (memRanges) {
        IOFree(memRanges, numMemRanges * sizeof(IORange));
        memRanges = NULL;
    }

    if (ioRanges) {
        IOFree(ioRanges, numIORanges * sizeof(IORange));
        ioRanges = NULL;
    }

    [super free];
}

- (IOReturn)getDeviceMemory:(IORange **)memory count:(unsigned int *)count
{
    if (memRanges && numMemRanges > 0) {
        *memory = memRanges;
        *count = numMemRanges;
        return IO_R_SUCCESS;
    }
    return IO_R_UNSUPPORTED;
}

- (IODisplayInfo *)displayInfo
{
    return &displayInfo;
}

- (IOReturn)selectMode:(const IODisplayInfo *)mode
{
    if (!mode) {
        return IO_R_INVALID_ARG;
    }

    /* Validate mode */
    if (mode->width != 800 || mode->height != 600) {
        IOLog("IBMThinkPad760EDDisplayDriver: Unsupported resolution %dx%d\n",
              mode->width, mode->height);
        return IO_R_UNSUPPORTED;
    }

    if (mode->bitsPerPixel != 16) {
        IOLog("IBMThinkPad760EDDisplayDriver: Unsupported depth %d\n",
              mode->bitsPerPixel);
        return IO_R_UNSUPPORTED;
    }

    /* Set display mode */
    [self setDisplayMode:mode->width height:mode->height depth:mode->bitsPerPixel];

    /* Update display info */
    displayInfo.width = mode->width;
    displayInfo.height = mode->height;
    displayInfo.bitsPerPixel = mode->bitsPerPixel;
    displayInfo.rowBytes = mode->width * (mode->bitsPerPixel / 8);
    displayInfo.refreshRate = mode->refreshRate;

    return IO_R_SUCCESS;
}

- (IOReturn)getMode:(IODisplayInfo *)mode
{
    if (!mode) {
        return IO_R_INVALID_ARG;
    }

    *mode = displayInfo;
    return IO_R_SUCCESS;
}

- (IOReturn)enterLinearMode
{
    if (!isInitialized) {
        return IO_R_NOT_READY;
    }

    /* Enable linear frame buffer */
    isEnabled = YES;
    IOLog("IBMThinkPad760EDDisplayDriver: Entered linear mode\n");

    return IO_R_SUCCESS;
}

- (IOReturn)revertToVGAMode
{
    if (!isInitialized) {
        return IO_R_NOT_READY;
    }

    /* Reset to VGA mode */
    [self resetHardware];
    isEnabled = NO;
    IOLog("IBMThinkPad760EDDisplayDriver: Reverted to VGA mode\n");

    return IO_R_SUCCESS;
}

- (IOReturn)getBrightness:(int *)brightness
{
    /* Not supported */
    return IO_R_UNSUPPORTED;
}

- (IOReturn)setBrightness:(int)brightness
{
    /* Not supported */
    return IO_R_UNSUPPORTED;
}

/* Private methods */

- (BOOL)mapMemoryRanges
{
    int i;
    IOReturn ret;

    if (!memRanges || numMemRanges == 0) {
        return NO;
    }

    /* Map first range as frame buffer (linear frame buffer at 0x08000000) */
    if (numMemRanges > 0) {
        ret = [self mapMemoryRange:0
                                to:(vm_address_t *)&frameBufferAddr
                            findSpace:YES
                                cache:IO_CacheOff];
        if (ret != IO_R_SUCCESS) {
            IOLog("IBMThinkPad760EDDisplayDriver: Failed to map frame buffer\n");
            return NO;
        }
        frameBufferLength = memRanges[0].size;
        displayInfo.frameBuffer = frameBufferAddr;
        IOLog("IBMThinkPad760EDDisplayDriver: Frame buffer mapped at 0x%x (size 0x%x)\n",
              frameBufferAddr, frameBufferLength);
    }

    /* Map second range as registers (VGA registers at 0xa0000) */
    if (numMemRanges > 1) {
        ret = [self mapMemoryRange:1
                                to:(vm_address_t *)&registerAddr
                            findSpace:YES
                                cache:IO_CacheOff];
        if (ret != IO_R_SUCCESS) {
            IOLog("IBMThinkPad760EDDisplayDriver: Failed to map registers\n");
            return NO;
        }
        registerLength = memRanges[1].size;
        IOLog("IBMThinkPad760EDDisplayDriver: Registers mapped at 0x%x (size 0x%x)\n",
              registerAddr, registerLength);
    }

    return YES;
}

- (void)unmapMemoryRanges
{
    if (frameBufferAddr) {
        [self unmapMemoryRange:0 from:frameBufferAddr];
        frameBufferAddr = 0;
    }

    if (registerAddr) {
        [self unmapMemoryRange:1 from:registerAddr];
        registerAddr = 0;
    }
}

- (BOOL)initHardware
{
    /* Initialize Trident Cyber 9665 chip */

    IOLog("IBMThinkPad760EDDisplayDriver: Initializing Trident Cyber 9665\n");

    /* Set up default 800x600x16 mode */
    [self setDisplayMode:800 height:600 depth:16];

    return YES;
}

- (void)resetHardware
{
    IOLog("IBMThinkPad760EDDisplayDriver: Resetting hardware\n");
    /* Reset chip to VGA mode */
}

- (void)setDisplayMode:(unsigned int)width height:(unsigned int)height depth:(unsigned int)depth
{
    IOLog("IBMThinkPad760EDDisplayDriver: Setting mode %dx%dx%d\n", width, height, depth);

    displayWidth = width;
    displayHeight = height;
    displayDepth = depth;
    displayRowBytes = width * (depth / 8);

    /* Program Trident registers for 800x600x16 */
    /* This would involve VGA register programming */
}

@end
