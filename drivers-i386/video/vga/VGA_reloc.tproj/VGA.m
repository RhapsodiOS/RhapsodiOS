/* Copyright (c) 1996 by NeXT Software, Inc.
 * All rights reserved.
 *
 * VGA.m -- driver for VGA Display Adapters
 * Supports: Standard VGA and SVGA compatible adapters
 *
 * Created for RhapsodiOS VGA support
 */
#import <driverkit/i386/IOEISADeviceDescription.h>
#import "VGA.h"

@implementation VGA

/* Put the display into linear framebuffer mode. This typically happens
 * when the window server starts running.
 */
- (void)enterLinearMode
{
    /* Set up the chip to use the selected mode. */
    [self initializeMode];

    /* Enter linear mode. */
    if ([self enableLinearFrameBuffer] == nil) {
	IOLog("%s: Failed to enter linear mode.\n", [self name]);
	return;
    }
}

/* Get the device out of whatever advanced linear mode it was using and back
 * into a state where it can be used as a standard VGA device.
 */
- (void)revertToVGAMode
{
    /* Reset the VGA parameters. */
    [self resetVGA];

    /* Let the superclass do whatever work it needs to do. */
    [super revertToVGAMode];
}

/* Set the brightness to `level'.
 */
- setBrightness:(int)level token:(int)t
{
    if (level < EV_SCREEN_MIN_BRIGHTNESS || level > EV_SCREEN_MAX_BRIGHTNESS) {
	IOLog("VGA: Invalid brightness level `%d'.\n", level);
	return nil;
    }
    brightnessLevel = level;
    return self;
}

/* Set the transfer tables.
 */
- setTransferTable:(const unsigned int *)table count:(int)numEntries
{
    int k;
    IOBitsPerPixel bpp;
    IOColorSpace cspace;

    if (redTransferTable != 0)
	IOFree(redTransferTable, 3 * transferTableCount);

    transferTableCount = numEntries;

    redTransferTable = IOMalloc(3 * numEntries);
    greenTransferTable = redTransferTable + numEntries;
    blueTransferTable = greenTransferTable + numEntries;

    bpp = [self displayInfo]->bitsPerPixel;
    cspace = [self displayInfo]->colorSpace;

    if (bpp == IO_2BitsPerPixel && cspace == IO_OneIsWhiteColorSpace) {
	for (k = 0; k < numEntries; k++) {
	    redTransferTable[k] = greenTransferTable[k] =
		blueTransferTable[k] = table[k] & 0xFF;
	}
    } else {
	IOFree(redTransferTable, 3 * numEntries);
	redTransferTable = 0;
    }
    return self;
}

- initFromDeviceDescription:deviceDescription
{
    IODisplayInfo *displayInfo;
    const IORange *range;
    const VGAMode *vgamode;

    if ([super initFromDeviceDescription:deviceDescription] == nil)
	return [super free];

    if ([self determineConfiguration] == nil)
	return [super free];

    if ([self selectMode] == nil)
	return [super free];

    range = [deviceDescription memoryRangeList];
    if (range == 0) {
	IOLog("%s: No memory range set.\n", [self name]);
	return [super free];
    }
    videoRamAddress = range[0].start;

    redTransferTable = greenTransferTable = blueTransferTable = 0;
    transferTableCount = 0;
    brightnessLevel = EV_SCREEN_MAX_BRIGHTNESS;

    displayInfo = [self displayInfo];
    vgamode = displayInfo->parameters;
    displayInfo->flags = 0;

    /* VGA always has transfer table and needs software gamma correction */
    displayInfo->flags |= IO_DISPLAY_HAS_TRANSFER_TABLE;
    displayInfo->flags |= IO_DISPLAY_NEEDS_SOFTWARE_GAMMA_CORRECTION;
    displayInfo->flags |= IO_DISPLAY_CACHE_OFF;

    displayInfo->frameBuffer =
        (void *)[self mapFrameBufferAtPhysicalAddress:videoRamAddress
	     length:vgamode->memSize];
    if (displayInfo->frameBuffer == 0)
	return [super free];

    IOLog("%s: Initialized `%s' @ %d Hz.\n", [self name], vgamode->name,
	  displayInfo->refreshRate);

    return self;
}
@end
