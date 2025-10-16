/*
 * VoodooVSAFB.m -- driver for 3Dfx Voodoo3 display adapter
 *
 * Copyright (c) 2025 RhapsodiOS Project
 * All rights reserved.
 *
 * Created for RhapsodiOS
 */

#import "VoodooVSAFB.h"
#include <stdio.h>

#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

/*
 * Mode table for supported display modes
 * All modes are 32-bit RGB:888/32 format
 */
static const IODisplayInfo modeTable[] = {
	{
		/* 640 x 480, RGB:888/32 */
		640, 480, 640, 2560, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	},
	{
		/* 800 x 600, RGB:888/32 */
		800, 600, 800, 3200, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	},
	{
		/* 1024 x 768, RGB:888/32 */
		1024, 768, 1024, 4096, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	},
	{
		/* 1152 x 864, RGB:888/32 */
		1152, 864, 1152, 4608, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	},
	{
		/* 1280 x 960, RGB:888/32 */
		1280, 960, 1280, 5120, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	},
	{
		/* 1280 x 1024, RGB:888/32 */
		1280, 1024, 1280, 5120, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	},
	{
		/* 1600 x 1200, RGB:888/32 */
		1600, 1200, 1600, 6400, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
};

#define modeTableCount (sizeof(modeTable) / sizeof(IODisplayInfo))
#define defaultMode 2  /* Default to 1024x768 */

@implementation VoodooVSAFB

/*
 * Probe for existence of the 3Dfx Voodoo3 device.
 *
 * This method performs the following steps:
 * 1. Get PCI configuration information for the device
 * 2. Verify the device ID matches a Voodoo3 variant
 * 3. Get the memory-mapped register base and frame buffer info
 * 4. Set memory ranges in the device description
 * 5. Allocate and initialize driver instance
 */
+ (BOOL)probe: deviceDescription
{
	CARD32 registerBase;
	CARD32 frameBufferBase;
	CARD32 frameBufferSize;
	IORange *oldRange, newRange[3];
	int numRanges;
	VoodooVSAFB *newDriver;
	IOPCIDeviceDescription *pciDevice;

	VSALog("VoodooVSAFB: Probing for 3Dfx Voodoo3 device.\n");

	/* Verify this is a PCI device */
	if (![deviceDescription respondsTo:@selector(getPCIConfigData:)]) {
		VSALog("VoodooVSAFB: Not a PCI device.\n");
		return NO;
	}

	pciDevice = (IOPCIDeviceDescription *)deviceDescription;

	/* Get register base and framebuffer info from PCI config */
	if ([self getRegisterBase: &registerBase
			   frameBufferBase: &frameBufferBase
			   frameBufferSize: &frameBufferSize
		 withDeviceDescription: deviceDescription] != IO_R_SUCCESS) {
		IOLog("VoodooVSAFB: Could not get memory ranges from PCI config.\n");
		return NO;
	}

	VSALog("VoodooVSAFB: Register base: 0x%08x\n", registerBase);
	VSALog("VoodooVSAFB: Framebuffer base: 0x%08x\n", frameBufferBase);
	VSALog("VoodooVSAFB: Framebuffer size: 0x%08x\n", frameBufferSize);

	/* Get existing memory ranges */
	oldRange = [deviceDescription memoryRangeList];
	numRanges = [deviceDescription numMemoryRanges];

	if (numRanges == 3) {
		int i;
		int ret;

		/* Copy existing ranges */
		for (i = 0; i < numRanges; i++) {
			newRange[i] = oldRange[i];
		}

		/* Set register space (BAR0) */
		newRange[REG_MEMRANGE].start = registerBase;
		newRange[REG_MEMRANGE].size = VOODOO_VSA_REG_SIZE;

		/* Set frame buffer (BAR1) */
		newRange[FB_MEMRANGE].start = frameBufferBase;
		newRange[FB_MEMRANGE].size = frameBufferSize;

		ret = [deviceDescription setMemoryRangeList:newRange num:3];
		if (ret) {
			IOLog("VoodooVSAFB: Can't set memory range.\n");
			return NO;
		}
	} else {
		IOLog("VoodooVSAFB: Incorrect number of address ranges: %d.\n", numRanges);
		return NO;
	}

	/* Allocate and initialize driver instance */
	newDriver = [[self alloc] initFromDeviceDescription: deviceDescription];

	if (newDriver == NULL) {
		IOLog("VoodooVSAFB probe: Problem initializing instance.\n");
		return NO;
	}

	[newDriver setDeviceKind: "Linear Framebuffer"];
	[newDriver registerDevice];

	IOLog("VoodooVSAFB: Display initialized and ready.\n");
	return YES;
}

/*
 * Initialize the device driver and driver instance.
 *
 * Steps:
 * 1. Call [super init...]
 * 2. Map the register space and frame buffer into memory
 * 3. Detect video memory size
 * 4. Select display mode based on user configuration
 * 5. Initialize display info structure
 * 6. Set up video mode parameters
 */
- initFromDeviceDescription: deviceDescription
{
	IODisplayInfo *displayInfo;
	const IORange *range;
	BOOL validModes[modeTableCount];
	int loop;
	const char *accelString;
	IOConfigTable *configuration;
	int maxWidth, maxHeight;

	IOLog("VoodooVSAFB: initFromDeviceDescription.\n");

	if ([super initFromDeviceDescription:deviceDescription] == nil) {
		return [super free];
	}

	registers = NULL;

	/* Get memory ranges from device description */
	range = [deviceDescription memoryRangeList];

	VSALog("VoodooVSAFB: Register range: 0x%08x-0x%08x\n",
		range[REG_MEMRANGE].start,
		range[REG_MEMRANGE].start + range[REG_MEMRANGE].size);

	VSALog("VoodooVSAFB: Framebuffer range: 0x%08x-0x%08x\n",
		range[FB_MEMRANGE].start,
		range[FB_MEMRANGE].start + range[FB_MEMRANGE].size);

	/* Map register space */
	if ([self mapMemoryRange: REG_MEMRANGE
						  to: (vm_address_t *)&registers
				   findSpace: YES
					   cache: IO_CacheOff] != IO_R_SUCCESS) {
		IOLog("VoodooVSAFB: Problem mapping register space.\n");
		return [super free];
	}

	registerSize = range[REG_MEMRANGE].size;
	fbPhysicalBase = range[FB_MEMRANGE].start;
	fbSize = range[FB_MEMRANGE].size;

	VSALog("VoodooVSAFB: Registers mapped at 0x%08x\n", (unsigned int)registers);

	/* Voodoo3 supports up to 1600x1200 */
	maxWidth = VOODOO_VSA_MAX_WIDTH;
	maxHeight = VOODOO_VSA_MAX_HEIGHT;

	VSALog("VoodooVSAFB: Max resolution: %dx%d\n", maxWidth, maxHeight);

	/* Get the acceleration flag from the config table */
	configuration = [deviceDescription configTable];
	accelString = [configuration valueForStringKey: VOODOO_VSA_ACCEL_KEY];

	if (accelString != NULL && !strcmp(VOODOO_VSA_ACCEL_ENABLED, accelString)) {
		acceleration = ACCELERATION_2D;
		VSALog("VoodooVSAFB: 2D acceleration enabled\n");
	} else {
		acceleration = NO_ACCELERATION;
		VSALog("VoodooVSAFB: 2D acceleration disabled\n");
	}

	/* Check which display modes are valid */
	for (loop = 0; loop < modeTableCount; loop++) {
		if ((modeTable[loop].width > maxWidth) ||
		    (modeTable[loop].height > maxHeight)) {
			validModes[loop] = NO;
		} else {
			validModes[loop] = YES;
		}
	}

	/* Select mode based on user preferences */
	selectedMode = [self selectMode:modeTable
							  count: modeTableCount
							  valid: validModes];

	if (selectedMode < 0) {
		IOLog("VoodooVSAFB: Cannot use requested display mode, using default.\n");
		selectedMode = defaultMode;
	}

	/* Get display info and set it from selected mode */
	displayInfo = [self displayInfo];
	*displayInfo = modeTable[selectedMode];

	/* Store current mode parameters */
	currentWidth = displayInfo->width;
	currentHeight = displayInfo->height;
	currentDepth = 32;  /* Always 32-bit for now */
	currentRefresh = displayInfo->refreshRate;

	VSALog("VoodooVSAFB: Selected mode: %dx%d @ %dHz\n",
		currentWidth, currentHeight, currentRefresh);

	/* Map frame buffer */
	if ([self mapMemoryRange: FB_MEMRANGE
						  to: (vm_address_t *)&(displayInfo->frameBuffer)
				   findSpace: YES
					   cache: IO_DISPLAY_CACHE_WRITETHROUGH] != IO_R_SUCCESS) {
		IOLog("VoodooVSAFB: Problem mapping framebuffer.\n");
		return [super free];
	}

	if (displayInfo->frameBuffer == 0) {
		IOLog("VoodooVSAFB: Couldn't map frame buffer memory!\n");
		return [super free];
	}

	VSALog("VoodooVSAFB: Framebuffer mapped at 0x%08x\n",
		(unsigned int)displayInfo->frameBuffer);

	IOLog("VoodooVSAFB: Initialized.\n");
	[self logInfo];

	return self;
}

/*
 * Configure display to enter linear framebuffer mode.
 *
 * 1. Initialize the DAC
 * 2. Set up video timing
 * 3. Enable the display
 */
- (void)enterLinearMode
{
	IOLog("VoodooVSAFB: enterLinearMode.\n");

	/* Initialize the DAC */
	[self initializeDAC];

	/* Set up video mode */
	[self setupVideoMode];

	/* Enable display output */
	[self enableDisplay];

	VSALog("VoodooVSAFB: Linear mode enabled.\n");
}

/*
 * Set display back to VGA mode.
 */
- (void)revertToVGAMode
{
	IOLog("VoodooVSAFB: revertToVGAMode.\n");

	/* Disable display */
	[self disableDisplay];

	[super revertToVGAMode];
}

@end
