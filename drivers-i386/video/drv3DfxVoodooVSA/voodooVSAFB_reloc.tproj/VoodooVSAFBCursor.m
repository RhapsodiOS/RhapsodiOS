/*
 * VoodooVSAFBCursor.m -- Hardware cursor support for 3Dfx Voodoo3 driver
 *
 * Copyright (c) 2025 RhapsodiOS Project
 * All rights reserved.
 *
 * Hardware cursor implementation based on Voodoo3 specifications
 */

#import "VoodooVSAFB.h"
#include <string.h>

@implementation VoodooVSAFB (Cursor)

/*
 * Initialize hardware cursor support
 * The Voodoo3 supports a 64x64 2-bit cursor
 */
- (BOOL) initCursor
{
	CARD32 vidProcCfg;

	VSALog("VoodooVSAFB: Initializing hardware cursor\n");

	/* Allocate cursor memory at the beginning of video RAM
	 * Cursor data is 64x64 pixels, 2 bits per pixel = 1024 bytes
	 */
	cursorMemoryOffset = 0;  /* Place at start of VRAM */

	/* Clear cursor memory */
	if ([self displayInfo]->frameBuffer) {
		unsigned char *cursorMem = (unsigned char *)[self displayInfo]->frameBuffer + cursorMemoryOffset;
		bzero(cursorMem, VOODOO_VSA_CURSOR_BYTES);
	}

	/* Set cursor pattern address (offset in video memory / 1024) */
	[self writeRegister: SST_HWCURPATADDR value: (cursorMemoryOffset / 1024)];

	/* Set default cursor colors (white cursor, black border) */
	[self writeRegister: SST_HWCURC0 value: 0x00000000];  /* Color 0: Black */
	[self writeRegister: SST_HWCURC1 value: 0x00FFFFFF];  /* Color 1: White */

	/* Initially hide cursor by moving it off-screen */
	[self writeRegister: SST_HWCURLOC value: 0xFFFFFFFF];

	/* Enable X11 cursor mode in video processor config */
	vidProcCfg = [self readRegister: SST_VIDPROCCFG];
	vidProcCfg |= SST_VIDCFG_CURS_X11;
	vidProcCfg |= SST_VIDCFG_HWCURSOR_ENABLE;
	[self writeRegister: SST_VIDPROCCFG value: vidProcCfg];

	cursorHotX = 0;
	cursorHotY = 0;
	cursorEnabled = NO;

	VSALog("VoodooVSAFB: Hardware cursor initialized\n");
	return YES;
}

/*
 * Set cursor shape from bitmap data
 * The Voodoo3 uses a 2-bit per pixel format:
 *   00 = Transparent
 *   01 = Color 0 (typically black/border)
 *   10 = Color 1 (typically white/fill)
 *   11 = Inverted (XOR with background)
 */
- (void) setCursorShape: (const unsigned char *)cursorData
				   mask: (const unsigned char *)maskData
				  width: (int)width
				 height: (int)height
				  hotX: (int)hotX
				  hotY: (int)hotY
{
	unsigned char *cursorMem;
	int x, y;
	CARD8 *dest;

	if (width > VOODOO_VSA_CURSOR_SIZE || height > VOODOO_VSA_CURSOR_SIZE) {
		IOLog("VoodooVSAFB: Cursor size %dx%d exceeds maximum %dx%d\n",
			width, height, VOODOO_VSA_CURSOR_SIZE, VOODOO_VSA_CURSOR_SIZE);
		return;
	}

	cursorMem = (unsigned char *)[self displayInfo]->frameBuffer + cursorMemoryOffset;
	dest = (CARD8 *)cursorMem;

	/* Clear cursor memory */
	bzero(dest, VOODOO_VSA_CURSOR_BYTES);

	/* Convert cursor data to Voodoo3 2-bit format
	 * Input: 1-bit cursor data + 1-bit mask
	 * Output: 2-bit per pixel Voodoo3 format
	 */
	for (y = 0; y < height; y++) {
		for (x = 0; x < width; x++) {
			int byteOffset = (y * width + x) / 8;
			int bitOffset = 7 - ((y * width + x) % 8);
			int cursorBit = (cursorData[byteOffset] >> bitOffset) & 1;
			int maskBit = (maskData[byteOffset] >> bitOffset) & 1;

			/* Determine 2-bit pixel value */
			int pixelValue;
			if (!maskBit) {
				pixelValue = 0;  /* 00 = Transparent */
			} else if (cursorBit) {
				pixelValue = 2;  /* 10 = Color 1 (white) */
			} else {
				pixelValue = 1;  /* 01 = Color 0 (black/border) */
			}

			/* Write 2-bit value to destination
			 * Voodoo3 stores 4 pixels per byte (2 bits each)
			 */
			int destByteOffset = (y * VOODOO_VSA_CURSOR_SIZE + x) / 4;
			int destBitOffset = ((y * VOODOO_VSA_CURSOR_SIZE + x) % 4) * 2;
			dest[destByteOffset] |= (pixelValue << destBitOffset);
		}
	}

	/* Store hotspot */
	cursorHotX = hotX;
	cursorHotY = hotY;

	VSALog("VoodooVSAFB: Cursor shape set (%dx%d, hotspot %d,%d)\n",
		width, height, hotX, hotY);
}

/*
 * Move cursor to specified location
 */
- (void) moveCursor: (int)x to: (int)y
{
	CARD32 cursorLoc;

	/* Adjust for hotspot */
	x -= cursorHotX;
	y -= cursorHotY;

	/* Hardware cursor location register format:
	 * Bits 0-10: X coordinate (signed 11-bit)
	 * Bits 16-26: Y coordinate (signed 11-bit)
	 */
	cursorLoc = ((x & 0x7FF) << 0) | ((y & 0x7FF) << 16);

	[self writeRegister: SST_HWCURLOC value: cursorLoc];
}

/*
 * Show hardware cursor
 */
- (void) showCursor
{
	CARD32 vidProcCfg;

	if (cursorEnabled) {
		return;
	}

	vidProcCfg = [self readRegister: SST_VIDPROCCFG];
	vidProcCfg |= SST_VIDCFG_HWCURSOR_ENABLE;
	[self writeRegister: SST_VIDPROCCFG value: vidProcCfg];

	cursorEnabled = YES;
	VSALog("VoodooVSAFB: Hardware cursor enabled\n");
}

/*
 * Hide hardware cursor
 */
- (void) hideCursor
{
	CARD32 vidProcCfg;

	if (!cursorEnabled) {
		return;
	}

	vidProcCfg = [self readRegister: SST_VIDPROCCFG];
	vidProcCfg &= ~SST_VIDCFG_HWCURSOR_ENABLE;
	[self writeRegister: SST_VIDPROCCFG value: vidProcCfg];

	cursorEnabled = NO;
	VSALog("VoodooVSAFB: Hardware cursor disabled\n");
}

/*
 * Set cursor colors
 */
- (void) setCursorColor0: (CARD32)color0 color1: (CARD32)color1
{
	/* Colors are in RGB format (0x00RRGGBB) */
	[self writeRegister: SST_HWCURC0 value: color0];
	[self writeRegister: SST_HWCURC1 value: color1];

	VSALog("VoodooVSAFB: Cursor colors set (0x%08x, 0x%08x)\n", color0, color1);
}

@end
