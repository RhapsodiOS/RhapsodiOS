/*
 * VoodooVSAFBRegisters.m -- register access methods for 3Dfx Voodoo3 driver
 *
 * Copyright (c) 2025 RhapsodiOS Project
 * All rights reserved.
 */

#import "VoodooVSAFB.h"
#import <driverkit/i386/IOPCIDeviceDescription.h>

@implementation VoodooVSAFB (Registers)

/*
 * Get register base and framebuffer info from PCI configuration space
 */
+ (IOReturn)getRegisterBase: (CARD32 *)registerBase
			frameBufferBase: (CARD32 *)fbBase
			frameBufferSize: (CARD32 *)fbSize
	  withDeviceDescription: deviceDescription
{
	IOPCIDeviceDescription *pciDevice;
	IOPCIConfigSpace configSpace;
	unsigned int size;

	if (![deviceDescription respondsTo:@selector(getPCIConfigData:)]) {
		return IO_R_UNSUPPORTED;
	}

	pciDevice = (IOPCIDeviceDescription *)deviceDescription;

	/* Get PCI configuration space */
	size = sizeof(IOPCIConfigSpace);
	if ([pciDevice getPCIConfigData: (unsigned char *)&configSpace
						   maxLength: size
						actualLength: &size] != IO_R_SUCCESS) {
		return IO_R_ERROR;
	}

	/* BAR0 contains the register space (16MB) */
	*registerBase = configSpace.BaseAddress[0] & 0xFFFFFFF0;

	/* BAR1 contains the frame buffer */
	*fbBase = configSpace.BaseAddress[1] & 0xFFFFFFF0;

	/* Voodoo3 variants have different memory sizes:
	 * Voodoo3 2000 - 8MB or 16MB
	 * Voodoo3 3000 - 16MB
	 * We'll detect this from the device ID or assume 16MB */
	CARD16 deviceID = configSpace.DeviceID;

	if (deviceID == VOODOO_VSA_2000_DEVICE_ID) {
		/* Voodoo3 2000 typically has 16MB, but could be 8MB */
		*fbSize = 16 * 1024 * 1024;
	} else {
		/* Voodoo3 3000 and Banshee have 16MB */
		*fbSize = 16 * 1024 * 1024;
	}

	VSALog("VoodooVSAFB: Device ID 0x%04x\n", deviceID);

	return IO_R_SUCCESS;
}

/*
 * Read a register value
 */
- (CARD32) readRegister: (int) offset
{
	if (registers == NULL) {
		return 0;
	}
	return registers[offset / 4];
}

/*
 * Write a register value
 */
- (void) writeRegister: (int) offset value: (CARD32) value
{
	if (registers == NULL) {
		return;
	}
	registers[offset / 4] = value;
}

/*
 * Initialize the DAC (Digital-to-Analog Converter)
 */
- (void) initializeDAC
{
	CARD32 dacMode;

	VSALog("VoodooVSAFB: Initializing DAC\n");

	/* Set up basic DAC mode */
	dacMode = [self readRegister: VOODOO_VSA_DACMODE];

	/* Clear 2X mode for standard operation */
	dacMode &= ~VOODOO_VSA_DACMODE_2X;

	[self writeRegister: VOODOO_VSA_DACMODE value: dacMode];
}

/*
 * Initialize the PLL (Phase-Locked Loop) for pixel clock generation
 */
- (void) initializePLL: (int) pixelClock
{
	CARD32 pllCtrl0, pllCtrl1;
	int n, m, k, p;

	VSALog("VoodooVSAFB: Initializing PLL for %d kHz pixel clock\n", pixelClock);

	/*
	 * Calculate PLL parameters
	 * Frequency = Reference * (N+2) / ((M+2) * 2^K)
	 * Reference frequency is typically 14.318 MHz
	 *
	 * For simplicity, we'll use pre-calculated values for common modes
	 */

	if (pixelClock <= 25175) {
		/* 640x480@60Hz */
		n = 5; m = 2; k = 3; p = 0;
	} else if (pixelClock <= 40000) {
		/* 800x600@60Hz */
		n = 9; m = 2; k = 3; p = 0;
	} else if (pixelClock <= 65000) {
		/* 1024x768@60Hz */
		n = 14; m = 2; k = 3; p = 0;
	} else if (pixelClock <= 81600) {
		/* 1152x864@60Hz */
		n = 18; m = 2; k = 3; p = 0;
	} else if (pixelClock <= 108000) {
		/* 1280x960/1024@60Hz */
		n = 23; m = 2; k = 3; p = 0;
	} else {
		/* 1600x1200@60Hz */
		n = 34; m = 2; k = 3; p = 0;
	}

	/* Build PLL control values */
	pllCtrl0 = ((m & 0x3f) << 0) | ((n & 0xff) << 8) | ((k & 0x3) << 16);
	pllCtrl1 = (p & 0x3);

	/* Write PLL registers */
	[self writeRegister: VOODOO_VSA_PLLCTRL0 value: pllCtrl0];
	[self writeRegister: VOODOO_VSA_PLLCTRL1 value: pllCtrl1];

	/* Wait for PLL to stabilize */
	IOSleep(10);
}

/*
 * Set video timing parameters
 */
- (void) setVideoTiming: (int) width height: (int) height depth: (int) depth
{
	CARD32 vidProcCfg;
	CARD32 vidScreenSize;
	CARD32 vidDesktopStartAddr;
	CARD32 vidDesktopOverlayStride;
	int stride;
	int format;

	VSALog("VoodooVSAFB: Setting video timing %dx%d @ %d bpp\n",
		width, height, depth);

	/* Calculate stride (bytes per line) */
	stride = width * (depth / 8);

	/* Determine pixel format */
	if (depth == 8) {
		format = VOODOO_VSA_VIDFMT_8BPP;
	} else if (depth == 16) {
		format = VOODOO_VSA_VIDFMT_16BPP;
	} else if (depth == 24) {
		format = VOODOO_VSA_VIDFMT_24BPP;
	} else {
		format = VOODOO_VSA_VIDFMT_32BPP;
	}

	/* Set screen size */
	vidScreenSize = ((width - 1) << 0) | ((height - 1) << 16);
	[self writeRegister: VOODOO_VSA_VIDSCREENSIZE value: vidScreenSize];

	/* Set desktop start address (beginning of frame buffer) */
	vidDesktopStartAddr = 0;
	[self writeRegister: VOODOO_VSA_VIDDESKTOPSTARTADDR value: vidDesktopStartAddr];

	/* Set desktop stride and format */
	vidDesktopOverlayStride = (stride << 0) | (format << 0);
	[self writeRegister: VOODOO_VSA_VIDDESKTOPOVERLAYSTRIDE value: vidDesktopOverlayStride];

	/* Configure video processor */
	vidProcCfg = [self readRegister: VOODOO_VSA_VIDPROCCFG];
	vidProcCfg |= VOODOO_VSA_VIDCFG_DESK_ENABLE;  /* Enable desktop video */
	vidProcCfg |= VOODOO_VSA_VIDCFG_VIDPROC_ENABLE;  /* Enable video processor */
	[self writeRegister: VOODOO_VSA_VIDPROCCFG value: vidProcCfg];

	/* Initialize VGA compatibility registers */
	[self writeRegister: VOODOO_VSA_VGAINIT0 value: VOODOO_VSA_VGAINIT0_EXTENDED];
}

/*
 * Enable display output
 */
- (void) enableDisplay
{
	CARD32 vidProcCfg;

	VSALog("VoodooVSAFB: Enabling display\n");

	vidProcCfg = [self readRegister: VOODOO_VSA_VIDPROCCFG];
	vidProcCfg |= VOODOO_VSA_VIDCFG_VIDPROC_ENABLE;
	vidProcCfg |= VOODOO_VSA_VIDCFG_DESK_ENABLE;
	[self writeRegister: VOODOO_VSA_VIDPROCCFG value: vidProcCfg];
}

/*
 * Disable display output
 */
- (void) disableDisplay
{
	CARD32 vidProcCfg;

	VSALog("VoodooVSAFB: Disabling display\n");

	vidProcCfg = [self readRegister: VOODOO_VSA_VIDPROCCFG];
	vidProcCfg &= ~VOODOO_VSA_VIDCFG_VIDPROC_ENABLE;
	vidProcCfg &= ~VOODOO_VSA_VIDCFG_DESK_ENABLE;
	[self writeRegister: VOODOO_VSA_VIDPROCCFG value: vidProcCfg];

	/* Wait for vertical retrace before disabling */
	[self waitForVerticalRetrace];
}

@end
