/* Copyright (c) 1993-1996 by NeXT Software, Inc.
 * All rights reserved.
 *
 * S3Generic.m -- driver for S3 Graphics Accelerators
 * Supports: 86C805, 86C928, Trio32, Trio64, Virge, VirgeDX, VirgeGX
 *
 * Modified to support S3 Trio and Virge chipsets
 * Created by Peter Graffagnino 1/31/93
 * Modified by Derek B Clegg	21 May 1993
 */
#import <driverkit/i386/IOEISADeviceDescription.h>
#import "S3Generic.h"

@implementation S3Generic

/* Put the display into linear framebuffer mode. This typically happens
 * when the window server starts running.
 */
- (void)enterLinearMode
{
    /* Set up the chip to use the selected mode. */
    [self initializeMode];

    /* Set the gamma-corrected gray-scale palette if necessary. */
    [self setGammaTable];

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
	IOLog("S3Generic: Invalid brightness level `%d'.\n", level);
	return nil;
    }
    brightnessLevel = level;
    [self setGammaTable];
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

    if (bpp == IO_8BitsPerPixel && cspace == IO_OneIsWhiteColorSpace) {
	for (k = 0; k < numEntries; k++) {
	    redTransferTable[k] = greenTransferTable[k] =
		blueTransferTable[k] = table[k] & 0xFF;
	}
    } else if (cspace == IO_RGBColorSpace &&
	       (bpp == IO_8BitsPerPixel ||
	        bpp == IO_15BitsPerPixel ||
	        bpp == IO_24BitsPerPixel)) {
	for (k = 0; k < numEntries; k++) {
	    redTransferTable[k] = (table[k] >> 24) & 0xFF;
	    greenTransferTable[k] = (table[k] >> 16) & 0xFF;
	    blueTransferTable[k] = (table[k] >> 8) & 0xFF;
	}
    } else {
	IOFree(redTransferTable, 3 * numEntries);
	redTransferTable = 0;
    }
    [self setGammaTable];
    return self;
}

- initFromDeviceDescription:deviceDescription
{
    IODisplayInfo *displayInfo;
    const IORange *range;
    const S3Mode *s3mode;
    const char *s;

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
    s3mode = displayInfo->parameters;
    displayInfo->flags = 0;

    /* Some S3 805 cards have a lot of flicker when write-posting or
     * read-ahead is enabled.  We disable both, but provide a way to
     * turn them on from the config table.  It's a good idea to enable
     * both if possible, since it speeds up the display a good deal.
     *
     * For Trio and Virge chipsets, we enable these by default as they
     * generally handle them better.
     */

    writePostingEnabled = [self booleanForStringKey:"WritePostingEnabled"
		       withDefault:(adapter == S3_805 ? NO : YES)];
    readAheadCacheEnabled = [self booleanForStringKey:"ReadAheadCacheEnabled"
			 withDefault:(adapter == S3_805 ? NO : YES)];

    /* Turn on s/w gamma correction.  (This is only necessary for the 555/16
     * modes.) */

    if ([self hasTransferTable])
	displayInfo->flags |= IO_DISPLAY_HAS_TRANSFER_TABLE;

    if ([self needsSoftwareGammaCorrection])
	displayInfo->flags |= IO_DISPLAY_NEEDS_SOFTWARE_GAMMA_CORRECTION;

    if (adapter == S3_805) {
	/* On the 805, always turn the cache off. */
	displayInfo->flags |= IO_DISPLAY_CACHE_OFF;
    } else {
	s = [self valueForStringKey:"DisplayCacheMode"];
	if (s != 0) {
	    if (strcmp(s, "Off") == 0)
		displayInfo->flags |= IO_DISPLAY_CACHE_OFF;
	    else if (strcmp(s, "WriteThrough") == 0)
		displayInfo->flags |= IO_DISPLAY_CACHE_WRITETHROUGH;
	    else if (strcmp(s, "CopyBack") == 0)
		displayInfo->flags |= IO_DISPLAY_CACHE_COPYBACK;
	    else
		IOLog("%s: Unrecognized value for key `DisplayCacheMode': "
		      "`%s'.\n", [self name], s);
	}
    }

    displayInfo->frameBuffer =
        (void *)[self mapFrameBufferAtPhysicalAddress:videoRamAddress
	     length:s3mode->memSize];
    if (displayInfo->frameBuffer == 0)
	return [super free];

    IOLog("%s: Initialized `%s' @ %d Hz.\n", [self name], s3mode->name,
	  displayInfo->refreshRate);

    return self;
}
@end
