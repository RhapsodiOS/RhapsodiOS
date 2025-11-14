/*
 * RivaFB.h -- interface for NVIDIA Riva framebuffer display driver
 * Supports Riva 128, TNT, and TNT2 chipsets
 */

#ifndef RIVAFB_H
#define RIVAFB_H

#import <driverkit/IOFrameBufferDisplay.h>

#include "riva_hw.h"

#ifndef RIVA_BUILD_DATE
#define RIVA_BUILD_DATE "2025-01-01"
#endif

#define RivaLog IOLog

/* Memory range indices in device description */
#define FB_MEMRANGE  0    /* Frame buffer memory range */
#define REG_MEMRANGE 1    /* Register memory range */

/* Maximum supported resolutions */
#define RIVA_MAX_WIDTH  2560
#define RIVA_MAX_HEIGHT 1600

@interface RivaFB:IOFrameBufferDisplay
{
    /* Hardware state */
    RivaHWRec rivaHW;

    /* Mode selected by user */
    int selectedMode;

    /* Register base pointers */
    CARD32 *regBase;

    /* Hardware cursor state */
    BOOL cursorEnabled;
    int cursorX;
    int cursorY;
    CARD32 cursorOffset;  /* Offset in framebuffer for cursor data */
}

+ (BOOL)probe: deviceDescription;

- initFromDeviceDescription: deviceDescription;
- (void)enterLinearMode;
- (void)revertToVGAMode;

/* Power management */
- (IOReturn)getIntValues: (unsigned int *)parameterArray
            forParameter: (IOParameterName)parameterName
                   count: (unsigned int *)count;
- (IOReturn)setIntValues: (unsigned int *)parameterArray
            forParameter: (IOParameterName)parameterName
                   count: (unsigned int)count;

@end

@interface RivaFB (Cursor)
/* Hardware cursor methods */
- (void) initCursor;
- (void) setCursorPosition: (int)x : (int)y;
- (void) showCursor: (BOOL)show;
- (void) setCursorImage: (const CARD32 *)image;
@end

@interface RivaFB (Utility)
/* Utility methods */
- (void) logInfo;
- (BOOL) setPixelEncoding: (IOPixelEncoding) pixelEncoding
             bitsPerPixel: (int) bitsPerPixel
                  redMask: (int) redMask
                greenMask: (int) greenMask
                 blueMask: (int) blueMask;
@end

@interface RivaFB (Registers)
/* Riva specific register access methods */
- (CARD32) readReg: (CARD32) offset;
- (void) writeReg: (CARD32) offset value: (CARD32) value;
- (CARD8) readVGA: (CARD16) port;
- (void) writeVGA: (CARD16) port value: (CARD8) value;
@end

#endif
