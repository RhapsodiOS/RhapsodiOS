/*
 * VoodooVSAFBUtility.m -- utility methods for 3Dfx Voodoo3 driver
 *
 * Copyright (c) 2025 RhapsodiOS Project
 * All rights reserved.
 */

#import "VoodooVSAFB.h"
#include <string.h>

@implementation VoodooVSAFB (Utility)

/*
 * Log driver and device information
 */
- (void) logInfo
{
	IODisplayInfo *displayInfo = [self displayInfo];

	VSALog("VoodooVSAFB Driver Info:\n");
	VSALog("  Build date: %s\n", VOODOO_VSA_BUILD_DATE);
	VSALog("  Mode: %dx%d @ %dHz\n",
		displayInfo->width, displayInfo->height, displayInfo->refreshRate);
	VSALog("  Depth: %d bpp\n", currentDepth);
	VSALog("  Row bytes: %d\n", displayInfo->rowBytes);
	VSALog("  Frame buffer: 0x%08x\n", (unsigned int)displayInfo->frameBuffer);
	VSALog("  Frame buffer size: 0x%08x (%d MB)\n",
		fbSize, fbSize / (1024 * 1024));
	VSALog("  2D Acceleration: %s\n",
		acceleration == ACCELERATION_2D ? "Enabled" : "Disabled");
}

/*
 * Set pixel encoding string based on color masks
 */
- (BOOL) setPixelEncoding: (IOPixelEncoding) pixelEncoding
			 bitsPerPixel: (int) bitsPerPixel
				  redMask: (int) redMask
			   greenMask: (int) greenMask
				blueMask: (int) blueMask
{
	int i;
	int shift;
	int mask;
	char *encoding = pixelEncoding;

	/* Clear encoding string */
	for (i = 0; i < 64; i++) {
		encoding[i] = '-';
	}
	encoding[bitsPerPixel] = '\0';

	/* Set red bits */
	mask = redMask;
	shift = 0;
	while (mask && !(mask & 1)) {
		mask >>= 1;
		shift++;
	}
	i = bitsPerPixel - 1 - shift;
	while (mask & 1) {
		encoding[i--] = 'R';
		mask >>= 1;
	}

	/* Set green bits */
	mask = greenMask;
	shift = 0;
	while (mask && !(mask & 1)) {
		mask >>= 1;
		shift++;
	}
	i = bitsPerPixel - 1 - shift;
	while (mask & 1) {
		encoding[i--] = 'G';
		mask >>= 1;
	}

	/* Set blue bits */
	mask = blueMask;
	shift = 0;
	while (mask && !(mask & 1)) {
		mask >>= 1;
		shift++;
	}
	i = bitsPerPixel - 1 - shift;
	while (mask & 1) {
		encoding[i--] = 'B';
		mask >>= 1;
	}

	return YES;
}

/*
 * Set up the video mode with current parameters
 */
- (void) setupVideoMode
{
	VSALog("VoodooVSAFB: Setting up video mode %dx%d @ %d bpp\n",
		currentWidth, currentHeight, currentDepth);

	/* Set video timing registers */
	[self setVideoTiming: currentWidth height: currentHeight depth: currentDepth];

	/* Initialize PLL for pixel clock */
	/* For 1024x768@60Hz, pixel clock is approximately 65 MHz */
	/* For other modes, we'll use simple calculations */
	int pixelClock;
	if (currentWidth == 640 && currentHeight == 480) {
		pixelClock = 25175;  /* 25.175 MHz */
	} else if (currentWidth == 800 && currentHeight == 600) {
		pixelClock = 40000;  /* 40 MHz */
	} else if (currentWidth == 1024 && currentHeight == 768) {
		pixelClock = 65000;  /* 65 MHz */
	} else if (currentWidth == 1152 && currentHeight == 864) {
		pixelClock = 81600;  /* 81.6 MHz */
	} else if (currentWidth == 1280 && currentHeight == 960) {
		pixelClock = 108000; /* 108 MHz */
	} else if (currentWidth == 1280 && currentHeight == 1024) {
		pixelClock = 108000; /* 108 MHz */
	} else if (currentWidth == 1600 && currentHeight == 1200) {
		pixelClock = 162000; /* 162 MHz */
	} else {
		pixelClock = 65000;  /* Default to 65 MHz */
	}

	[self initializePLL: pixelClock];
}

/*
 * Wait for the 2D engine to become idle
 */
- (void) waitForIdle
{
	int timeout = 1000000;
	CARD32 status;

	while (timeout-- > 0) {
		status = [self readRegister: VOODOO_VSA_STATUS];
		if (!(status & VOODOO_VSA_STATUS_BUSY)) {
			return;
		}
	}

	IOLog("VoodooVSAFB: Warning - timeout waiting for 2D engine idle\n");
}

/*
 * Wait for vertical retrace
 */
- (void) waitForVerticalRetrace
{
	int timeout = 1000000;
	CARD32 status;

	/* Wait for retrace to start */
	while (timeout-- > 0) {
		status = [self readRegister: VOODOO_VSA_STATUS];
		if (status & VOODOO_VSA_STATUS_RETRACE) {
			return;
		}
	}

	IOLog("VoodooVSAFB: Warning - timeout waiting for vertical retrace\n");
}

@end
