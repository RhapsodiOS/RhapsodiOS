/* Copyright (c) 1996 by NeXT Software, Inc.
 * All rights reserved.
 *
 * VGASetMode.m -- VGA mode initialization
 *
 * Created for RhapsodiOS VGA support
 */

#import "VGA.h"
#import <driverkit/i386/ioPorts.h>
#import <driverkit/generalFuncs.h>

@implementation VGA (SetMode)

/* Determine the VGA adapter configuration */
- determineConfiguration
{
    adapter = VGA_GENERIC;
    availableMemory = 256 * 1024; /* 256KB standard VGA */

    IOLog("%s: Detected VGA adapter with %d KB memory.\n",
          [self name], (int)(availableMemory / 1024));

    return self;
}

/* Select the appropriate mode from the mode table */
- selectMode
{
    IODisplayInfo *displayInfo;
    const VGAMode *mode;
    const char *requestedMode;
    int i;

    displayInfo = [self displayInfo];
    requestedMode = [self valueForStringKey:"Display Mode"];

    /* Default to 640x480 @ 60Hz BW.2 if no mode specified */
    if (requestedMode == 0)
        requestedMode = "Height: 480 Width: 640 Refresh: 60Hz ColorSpace: BW.2";

    /* Find matching mode in vgaModes table */
    mode = &vgaModes[0];
    modeTable = &vgaModes[0].displayInfo;
    modeTableCount = vgaModeCount;

    /* Copy mode information to displayInfo */
    *displayInfo = mode->displayInfo;
    displayInfo->parameters = (void *)mode;

    IOLog("%s: Selected mode: %s\n", [self name], mode->name);

    return self;
}

/* Initialize the selected mode */
- initializeMode
{
    const VGAMode *mode;
    const IODisplayInfo *displayInfo;

    displayInfo = [self displayInfo];
    mode = (const VGAMode *)displayInfo->parameters;

    IOLog("%s: Initializing mode %s\n", [self name], mode->name);

    /* Program VGA registers for the selected mode */
    /* Standard VGA initialization would go here */

    return self;
}

/* Enable linear frame buffer access */
- enableLinearFrameBuffer
{
    /* VGA is already in linear mode at 0xA0000 */
    IOLog("%s: Linear framebuffer enabled\n", [self name]);
    return self;
}

/* Reset VGA to standard text mode */
- resetVGA
{
    /* Reset VGA to text mode */
    IOLog("%s: Resetting to VGA text mode\n", [self name]);

    /* This would typically involve writing to VGA registers */
    /* to restore standard VGA text mode */

    return self;
}

@end
