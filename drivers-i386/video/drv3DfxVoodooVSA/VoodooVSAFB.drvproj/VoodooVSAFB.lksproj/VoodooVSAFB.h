/*
 * VoodooVSAFB.h -- interface for 3Dfx Voodoo VSA framebuffer display driver
 *
 * Copyright (c) 2025 RhapsodiOS Project
 * All rights reserved.
 *
 * Created for RhapsodiOS
 */

#ifndef VOODOOVSAFB_H
#define VOODOOVSAFB_H

#import <driverkit/IOFrameBufferDisplay.h>

#include "voodooVSA_reg.h"
#include "voodooVSA_reg_ext.h"

#ifndef VOODOO_VSA_BUILD_DATE
#define VOODOO_VSA_BUILD_DATE "2025-01-01"
#endif

#define VSALog IOLog

/* Parameter for 2D acceleration control */
#define VOODOO_VSA_ACCEL_PARAM "VoodooVSAAcceleration"

/* First memory range in device description is register space */
#define REG_MEMRANGE 0

/* Second memory range is frame buffer */
#define FB_MEMRANGE 1

/* Acceleration key for IOConfigTable */
#define VOODOO_VSA_ACCEL_KEY "VoodooVSA 2D Acceleration"

/* Acceleration key values */
#define VOODOO_VSA_ACCEL_ENABLED "Enabled"
#define VOODOO_VSA_ACCEL_DISABLED "Disabled"

/* Acceleration modes */
enum voodooVSA_acceleration {
	NO_ACCELERATION,
	ACCELERATION_2D
};

@interface VoodooVSAFB:IOFrameBufferDisplay
{
	/* Memory-mapped register base */
	volatile CARD32 *registers;

	/* Register space size */
	unsigned long registerSize;

	/* Frame buffer physical address */
	CARD32 fbPhysicalBase;

	/* Frame buffer size */
	CARD32 fbSize;

	/* Mode selected by user */
	int selectedMode;

	/* 2D acceleration flag from config table */
	enum voodooVSA_acceleration acceleration;

	/* Current video timing parameters */
	int currentWidth;
	int currentHeight;
	int currentDepth;
	int currentRefresh;

	/* Hardware cursor state */
	CARD32 cursorMemoryOffset;
	int cursorHotX;
	int cursorHotY;
	BOOL cursorEnabled;

	/* Power management state */
	int powerState;
	BOOL displayStateSaved;
	CARD32 currentPixelClock;
	CARD32 savedPixelClock;

	/* Saved registers for power management */
	CARD32 savedVidProcCfg;
	CARD32 savedDACMode;
	CARD32 savedPLLCtrl0;
	CARD32 savedPLLCtrl1;
	CARD32 savedVGAInit0;
	CARD32 savedDesktopAddr;
	CARD32 savedDesktopStride;
	CARD32 savedScreenSize;
}

+ (BOOL)probe: deviceDescription;

- initFromDeviceDescription: deviceDescription;
- (void)enterLinearMode;
- (void)revertToVGAMode;

@end

@interface VoodooVSAFB (Utility)
/* Utility methods */
- (void) logInfo;
- (BOOL) setPixelEncoding: (IOPixelEncoding) pixelEncoding
				 bitsPerPixel: (int) bitsPerPixel
					 redMask: (int) redMask
				  greenMask: (int) greenMask
				   blueMask: (int) blueMask;
- (void) setupVideoMode;
- (void) waitForIdle;
- (void) waitForVerticalRetrace;
@end

@interface VoodooVSAFB (Registers)
/* VoodooVSA specific register access methods */

+ (IOReturn)getRegisterBase: (CARD32 *)registerBase
			 frameBufferBase: (CARD32 *)fbBase
			 frameBufferSize: (CARD32 *)fbSize
	 withDeviceDescription: deviceDescription;

- (CARD32) readRegister: (int) offset;
- (void) writeRegister: (int) offset value: (CARD32) value;
- (void) initializeDAC;
- (void) initializePLL: (int) pixelClock;
- (void) setVideoTiming: (int) width height: (int) height depth: (int) depth;
- (void) enableDisplay;
- (void) disableDisplay;

@end

@interface VoodooVSAFB (Cursor)
/* Hardware cursor methods */
- (BOOL) initCursor;
- (void) setCursorShape: (const unsigned char *)cursorData
				   mask: (const unsigned char *)maskData
				  width: (int)width
				 height: (int)height
				   hotX: (int)hotX
				   hotY: (int)hotY;
- (void) moveCursor: (int)x to: (int)y;
- (void) showCursor;
- (void) hideCursor;
- (void) setCursorColor0: (CARD32)color0 color1: (CARD32)color1;
@end

@interface VoodooVSAFB (Power)
/* Power management methods */
- (IOReturn) setDPMSState: (int)state;
- (int) getDPMSState;
- (BOOL) isDisplayBlanked;
- (void) blankDisplay: (BOOL)blank;
- (void) saveDisplayState;
- (void) restoreDisplayState;
- (IOReturn) enterPowerSaveMode;
- (IOReturn) exitPowerSaveMode;
@end

#endif /* VOODOOVSAFB_H */
