/*
 * RivaFBCursor.m -- Hardware cursor support
 */

#import "RivaFB.h"
#include <stdio.h>
#include <string.h>

@implementation RivaFB (Cursor)

/*
 * Initialize hardware cursor
 */
- (void) initCursor
{
    RivaLog("RivaFB: Initializing hardware cursor\n");

    /* Allocate cursor memory at end of framebuffer */
    /* Reserve last 4KB of framebuffer for cursor data */
    cursorOffset = rivaHW.fbSize - (4 * 1024);

    /* Disable cursor initially */
    cursorEnabled = NO;
    cursorX = 0;
    cursorY = 0;

    /* Disable hardware cursor */
    [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_CURSOR_CONFIG value: 0];

    /* Set cursor data offset in framebuffer */
    [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_CURSOR_PLANE0_OFFSET value: cursorOffset];

    /* Clear cursor memory */
    CARD32 *cursorMem = rivaHW.fbBase + (cursorOffset / 4);
    for (int i = 0; i < RIVA_CURSOR_SIZE / 4; i++) {
        cursorMem[i] = 0;
    }

    RivaLog("RivaFB: Hardware cursor initialized at offset 0x%08x\n", cursorOffset);
}

/*
 * Set cursor position
 */
- (void) setCursorPosition: (int)x : (int)y
{
    CARD32 pos;

    cursorX = x;
    cursorY = y;

    /* Pack position into register format */
    pos = ((x & 0xFFFF) << 16) | (y & 0xFFFF);

    /* Write to cursor position register */
    [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_CURSOR_POS value: pos];
}

/*
 * Show or hide cursor
 */
- (void) showCursor: (BOOL)show
{
    CARD32 config;

    cursorEnabled = show;

    if (show) {
        /* Enable cursor with 32x32 ARGB format */
        config = NV_PRAMDAC_CURSOR_CONFIG_ENABLE |
                 NV_PRAMDAC_CURSOR_CONFIG_FORMAT_32x32_ARGB;
        [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_CURSOR_CONFIG value: config];
        RivaLog("RivaFB: Hardware cursor enabled\n");
    } else {
        /* Disable cursor */
        [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_CURSOR_CONFIG value: 0];
        RivaLog("RivaFB: Hardware cursor disabled\n");
    }
}

/*
 * Set cursor image
 * image should be 32x32 pixels in ARGB format (4 bytes per pixel)
 */
- (void) setCursorImage: (const CARD32 *)image
{
    CARD32 *cursorMem;

    if (!image) {
        RivaLog("RivaFB: setCursorImage: NULL image pointer\n");
        return;
    }

    /* Get pointer to cursor memory in framebuffer */
    cursorMem = rivaHW.fbBase + (cursorOffset / 4);

    /* Copy cursor image to framebuffer */
    for (int i = 0; i < (RIVA_CURSOR_WIDTH * RIVA_CURSOR_HEIGHT); i++) {
        cursorMem[i] = image[i];
    }

    RivaLog("RivaFB: Cursor image updated\n");
}

/*
 * DriverKit cursor methods override
 * These provide default software cursor fallback if hardware cursor fails
 */
- hideCursor: (int) token
{
    if (cursorEnabled) {
        [self showCursor: NO];
    }
    return [super hideCursor: token];
}

- moveCursor: (Point *)cursorLoc
          frame: (int) frame
{
    if (cursorEnabled) {
        [self setCursorPosition: cursorLoc->x : cursorLoc->y];
    }
    return [super moveCursor: cursorLoc frame: frame];
}

- showCursor: (Point *)cursorLocation
       frame: (int) frame
{
    if (!cursorEnabled) {
        [self showCursor: YES];
    }
    if (cursorEnabled) {
        [self setCursorPosition: cursorLocation->x : cursorLocation->y];
    }
    return [super showCursor: cursorLocation frame: frame];
}

@end
