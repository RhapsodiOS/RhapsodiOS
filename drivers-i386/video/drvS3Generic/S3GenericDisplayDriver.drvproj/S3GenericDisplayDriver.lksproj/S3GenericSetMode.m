/* Copyright (c) 1993-1996 by NeXT Software, Inc.
 * All rights reserved.
 *
 * S3GenericSetMode.m -- Mode support for the S3 Generic driver.
 * Supports S3 Trio and Virge chipsets
 *
 * Author:  Derek B Clegg	21 May 1993
 * Based on work by Peter Graffagnino, 31 January 1993.
 */
#import <string.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#import "S3Generic.h"

/* The `S3GenericSetMode' category of `S3Generic'. */

@implementation S3Generic (SetMode)

- (void)reportConfiguration
{
    const char *adapterString, *busString, *memString, *dacString;

    switch (adapter) {
    case S3_805: adapterString = "86C805"; break;
    case S3_928: adapterString = "86C928"; break;
    case S3_Trio32: adapterString = "Trio32"; break;
    case S3_Trio64: adapterString = "Trio64"; break;
    case S3_Virge: adapterString = "Virge"; break;
    case S3_VirgeDX: adapterString = "VirgeDX"; break;
    case S3_VirgeGX: adapterString = "VirgeGX"; break;
    default: adapterString = "(unknown adapter)"; break;
    }

    switch (busConfiguration) {
    case S3_EISA_BUS: busString = "EISA"; break;
    case S3_LOCAL_BUS: busString = "Local"; break;
    case S3_ISA_BUS: busString = "ISA"; break;
    default: busString = "Unknown"; break;
    }

    switch (availableMemory) {
    case FOUR_MEGABYTES: memString = "4 Mb VRAM"; break;
    case THREE_MEGABYTES: memString = "3 Mb VRAM"; break;
    case TWO_MEGABYTES: memString = "2 Mb VRAM"; break;
    case ONE_MEGABYTE: memString = "1 Mb VRAM"; break;
    case ONE_MEGABYTE/2: memString = "500 Kb VRAM"; break;
    default: memString = "(unknown memory size)"; break;
    }

    switch (dac) {
    case Bt484: dacString = "Brooktree 484"; break;
    case Bt485: dacString = "Brooktree 485"; break;
    case Bt485A: dacString = "Brooktree 485A"; break;
    case ATT20C491: dacString = "AT&T 20C491 or compatible"; break;
    default: dacString = "Unknown"; break;
    }

    IOLog("%s: S3 %s; %s bus; %s; %s DAC.\n", [self name], adapterString,
	  busString, memString, dacString);
}

- determineConfiguration
{
    int value, lockRegisterValue;

    /* If we turn out not to be an S3, we preserve the old value
     * of the lock register. */

    lockRegisterValue = rread(VGA_CRTC_INDEX, S3_REG_LOCK1);
    rwrite(VGA_CRTC_INDEX, S3_REG_LOCK1, S3_LOCK1_KEY);

    /* Get the adapter type. */

    value = rread(VGA_CRTC_INDEX, S3_CHIP_ID_INDEX);

    switch (value & S3_CHIP_ID_MASK) {
    case S3_CHIP_ID_805:
	adapter = S3_805;
	modeTable = S3_805_ModeTable;
	modeTableCount = S3_805_ModeTableCount;
	break;
    case S3_CHIP_ID_928:
	adapter = S3_928;
	modeTable = S3_928_ModeTable;
	modeTableCount = S3_928_ModeTableCount;
	break;
    case S3_CHIP_ID_Trio32:
	adapter = S3_Trio32;
	modeTable = S3_Trio_ModeTable;
	modeTableCount = S3_Trio_ModeTableCount;
	break;
    case S3_CHIP_ID_Trio64:
	adapter = S3_Trio64;
	modeTable = S3_Trio_ModeTable;
	modeTableCount = S3_Trio_ModeTableCount;
	break;
    case S3_CHIP_ID_Virge:
	adapter = S3_Virge;
	modeTable = S3_Virge_ModeTable;
	modeTableCount = S3_Virge_ModeTableCount;
	break;
    case S3_CHIP_ID_VirgeDX:
	adapter = S3_VirgeDX;
	modeTable = S3_Virge_ModeTable;
	modeTableCount = S3_Virge_ModeTableCount;
	break;
    case S3_CHIP_ID_VirgeGX:
	adapter = S3_VirgeGX;
	modeTable = S3_Virge_ModeTable;
	modeTableCount = S3_Virge_ModeTableCount;
	break;
    default:
	IOLog("%s: Unrecognized adapter (chip ID = 0x%02X).\n", [self name], value);
	/* If we're not an S3, reset things to the way we found them.... */
	rwrite(VGA_CRTC_INDEX, S3_CHIP_ID_INDEX, value);
	rwrite(VGA_CRTC_INDEX, S3_REG_LOCK1, lockRegisterValue);
	adapter = UnknownAdapter;
	modeTable = 0;
	modeTableCount = 0;
	return nil;
	break;
    }

    /* Get the bus and memory configuration. */

    value = rread(VGA_CRTC_INDEX, S3_CONFG_REG1_INDEX);

    busConfiguration = value & S3_BUS_SELECT_MASK;

    switch (value & S3_MEM_SIZE_MASK) {
    case S3_HALF_MEG: availableMemory = ONE_MEGABYTE/2; break;
    case S3_1_MEG: availableMemory = ONE_MEGABYTE; break;
    case S3_2_MEG: availableMemory = TWO_MEGABYTES; break;
    case S3_3_MEG: availableMemory = THREE_MEGABYTES; break;
    case S3_4_MEG: availableMemory = FOUR_MEGABYTES; break;
    default:
	IOLog("%s: Unrecognized memory configuration.\n", [self name]);
	availableMemory = 0;
	return nil;
    }

    [self determineDACType];
    [self reportConfiguration];

    S3_lockRegisters();
    return self;
}

/* Select a display mode based on the adapter type, the bus configuration,
 * and the memory configuration.  Return the selected mode, or -1 if no mode
 * is valid.
 */
- selectMode
{
    int k, mode;
    const S3Mode *modeData;
    BOOL valid[modeTableCount];

    for (k = 0; k < modeTableCount; k++) {
	modeData = modeTable[k].parameters;
	valid[k] = (modeData->memSize <= availableMemory
		    && (modeData->adapter == adapter ||
		        /* Trio64 can use Trio32 modes */
		        (adapter == S3_Trio64 && modeData->adapter == S3_Trio32) ||
		        /* VirgeDX/GX can use Virge modes */
		        ((adapter == S3_VirgeDX || adapter == S3_VirgeGX) &&
		         modeData->adapter == S3_Virge)));
    }

    mode = [self selectMode:modeTable count:modeTableCount valid:valid];
    if (mode < 0) {
	IOLog("%s: Sorry, cannot use requested display mode.\n", [self name]);
	/* Select default mode based on chipset */
	if (adapter == S3_805)
	    mode = S3_805_defaultMode;
	else if (adapter == S3_928)
	    mode = S3_928_defaultMode;
	else if (adapter == S3_Trio32 || adapter == S3_Trio64)
	    mode = S3_Trio_defaultMode;
	else
	    mode = S3_Virge_defaultMode;
    }
    *[self displayInfo] = modeTable[mode];
    return self;
}

- initializeMode
{
    int k, count;
    const S3Mode *mode;
    const IODisplayInfo *displayInfo;
    unsigned char crtc[VGA_CRTC_COUNT];
    unsigned char miscOutput[1];
    unsigned char xcrtc[2*S3_EXTENDED_REGISTER_MAX];
    unsigned char modeControl[S3_MODE_COUNT];
    unsigned char advFunctionControl[1];

    displayInfo = [self displayInfo];
    mode = displayInfo->parameters;

    /* Turn off the screen. */

    outb(VGA_SEQ_DATA, mode->vgaData.seqx[1] | 0x20);

    /* Sequencer. */

    for (k = 0; k < VGA_SEQ_COUNT; k++) {
	if (k == 1)
	    continue;
	outb(VGA_SEQ_INDEX, k);
	outb(VGA_SEQ_DATA, mode->vgaData.seqx[k]);
    }

    S3_unlockRegisters();

    /* Unlock the CRTC registers. */
    rrmw(VGA_CRTC_INDEX, 0x11, ~0x80, 0x00);
    rrmw(VGA_CRTC_INDEX, 0x35, ~0x30, 0x00);

    /* Set up the CRTC parameters. */

    count = [self parametersForMode:mode->name
	 forStringKey:"CRTC Registers"
	 parameters:crtc
	 count:sizeof(crtc)];
    if (count > 0) {
	IOLog("%s: Using crtc parameters from instance table.\n", [self name]);
	for (k = 0; k < count; k++)
	    rwrite(VGA_CRTC_INDEX, k, crtc[k]);
    } else {
	for (k = 0; k < VGA_CRTC_COUNT; k++)
	    rwrite(VGA_CRTC_INDEX, k, mode->vgaData.crtc[k]);
    }

    /* Initialize the address flip-flop for the attribute controller. */

    inb(VGA_INPUT_STATUS_1);
    /* Set up the attribute controller registers. */
    for (k = 0; k < VGA_ATTR_COUNT; k++) {
	outb(VGA_ATTR_INDEX, k);
	outb(VGA_ATTR_DATA, mode->vgaData.attr[k]);
    }

    /* Start the sequencer. */
    rwrite(VGA_SEQ_INDEX, 0x00, 0x03);

    /* Set up the graphics controller registers. */
    for (k = 0; k < VGA_GRFX_COUNT; k++)
	rwrite(VGA_GRFX_INDEX, k, mode->vgaData.grfx[k]);

    /* Set the miscellaneous output register (0x3C2). */

    count = [self parametersForMode:mode->name
	 forStringKey:"MiscOutput Register"
	 parameters:miscOutput
	 count:sizeof(miscOutput)];
    if (count > 0) {
	IOLog("%s: Using miscOutput parameter from instance table.\n",
	      [self name]);
	outb(VGA_MISC_OUTPUT, miscOutput[0]);
    } else {
	outb(VGA_MISC_OUTPUT, mode->vgaData.miscOutput);
    }

    /* Reset the address flip-flop for the attribute controller and
     * enable the palette. */
    inb(VGA_INPUT_STATUS_1);
    outb(VGA_ATTR_INDEX, 0x20);

    /* Set up the extended CRTC registers. */

    count = [self parametersForMode:mode->name
	 forStringKey:"XCRTC Registers"
	 parameters:xcrtc
	 count:sizeof(xcrtc)];
    if (count > 0) {
	IOLog("%s: Using extended crtc parameters from instance table.\n",
	      [self name]);
	for (k = 0; k < count && xcrtc[k] != 0; k += 2)
	    rwrite(VGA_CRTC_INDEX, xcrtc[k], xcrtc[k+1]);
    } else {
	for (k = 0; k < S3_XCRTC_COUNT && mode->xcrtc[k] != 0; k += 2)
	    rwrite(VGA_CRTC_INDEX, mode->xcrtc[k], mode->xcrtc[k+1]);
    }

    /* Set the mode control register. */
    count = [self parametersForMode:mode->name
	 forStringKey:"Mode Control Register"
	 parameters:modeControl
	 count:sizeof(modeControl)];
    if (count > 0) {
	IOLog("%s: Using mode control parameters from instance table.\n",
	      [self name]);
	for (k = 0; k < count; k += 2) {
	    if (displayInfo->refreshRate == modeControl[k]/*refreshRate*/) {
		rwrite(VGA_CRTC_INDEX, 0x42, modeControl[k+1]/*modeControl*/);
		break;
	    }
	}
	if (k >= count)
	    IOLog("%s: Warning: Unable to set the refresh rate.\n",
		  [self name]);
    } else {
	for (k = 0; k < S3_MODE_COUNT; k++) {
	    if (displayInfo->refreshRate == mode->modeControl[k].refreshRate) {
		rwrite(VGA_CRTC_INDEX, 0x42, mode->modeControl[k].modeControl);
		break;
	    }
	}
	if (k == S3_MODE_COUNT)
	    IOLog("%s: Warning: Unable to set the refresh rate.\n",
		  [self name]);
    }

    /* Unlock access to the enhanced commands registers. */
    rrmw(VGA_CRTC_INDEX, 0x40, ~0x01, 0x01);

    /* Set the advanced function control register (0x4AE8). */

    count = [self parametersForMode:mode->name
	 forStringKey:"Advanced Function Control Register"
	 parameters:advFunctionControl
	 count:sizeof(advFunctionControl)];
    if (count > 0) {
	outw(S3_ADVFUNC_CNTL, advFunctionControl[0]);
    } else {
	outw(S3_ADVFUNC_CNTL, mode->advFuncCntl);
    }

    /* Lock the register set. */
    rrmw(VGA_CRTC_INDEX, 0x40, ~0x01, 0x00);

    /* Program the DAC. */
    [self programDAC];

    /* Lock the registers. */
    S3_lockRegisters();

    /* Enable the screen */
    rrmw(VGA_SEQ_INDEX, 0x01, 0xDF, 0x00);
    return self;
}

- enableLinearFrameBuffer
{
    int lawSize;
    S3Mode *mode;
    IODisplayInfo *displayInfo;

    displayInfo = [self displayInfo];
    mode = displayInfo->parameters;

    S3_unlockRegisters();

    /* Tell the chip where the frame buffer is mapped in. */

    rwrite(VGA_CRTC_INDEX, S3_LAW_POS_LO, (videoRamAddress >> 16) & 0xFF);
    rwrite(VGA_CRTC_INDEX, S3_LAW_POS_HI, (videoRamAddress >> 24) & 0xFF);

    /* Set the linear address window size. */

    switch (mode->memSize) {
    case ONE_MEGABYTE:
	lawSize = S3_LAW_SIZE_1M;
	break;
    case TWO_MEGABYTES:
	lawSize = S3_LAW_SIZE_2M;
	break;
    case THREE_MEGABYTES:
    case FOUR_MEGABYTES:
	lawSize = S3_LAW_SIZE_4M;
	break;
    default:
	IOLog("%s: Invalid linear address window size for mode `%s'.\n",
	      [self name], mode->name);
	return nil;
    }

    /* Set the linear address window size. */
    rrmw(VGA_CRTC_INDEX, S3_LAW_CTL, ~S3_LAW_SIZE_MASK, lawSize);

    if (rread(VGA_CRTC_INDEX, S3_SYS_CNFG) & S3_8514_ACCESS_MASK) {
	/* Wait for the graphics accelerator to stop. */
	while (inw(S3_GP_STAT) & S3_GP_BUSY_MASK)
	    ;
	/* Disable 8514 register access. */
	rrmw(VGA_CRTC_INDEX, S3_SYS_CNFG, ~S3_8514_ACCESS_MASK,
	     S3_8514_DISABLE_ACCESS);
    }

    /* Turn off mmio. */
    rrmw(VGA_CRTC_INDEX, S3_EX_MCTL_1, ~S3_MMIO_ACCESS_MASK,
	 S3_DISABLE_MMIO_ACCESS);

    if (writePostingEnabled) {
	/* Enable fast write buffer (write posting into FIFO). */
	rrmw(VGA_CRTC_INDEX, S3_SYS_CNFG, ~S3_WRITE_POST_MASK,
	     S3_WRITE_POST_ENABLE);
    } else {
	/* Disable fast write buffer. */
	rrmw(VGA_CRTC_INDEX, S3_SYS_CNFG, ~S3_WRITE_POST_MASK,
	     S3_WRITE_POST_DISABLE);
    }

    if (readAheadCacheEnabled) {
	/* Enable read-ahead cache. */
	rrmw(VGA_CRTC_INDEX, S3_LAW_CTL, ~S3_PREFETCH_MASK,
	     S3_ENABLE_PREFETCH);
	/* Max out the read-ahead cache. */
	rrmw(VGA_CRTC_INDEX, S3_EX_MCTL_2, ~S3_PREFETCH_CTRL_MASK,
	     S3_PREFETCH_MAX);
    } else {
	/* Disable read-ahead cache. */
	rrmw(VGA_CRTC_INDEX, S3_LAW_CTL, ~S3_PREFETCH_MASK,
	     S3_DISABLE_PREFETCH);
    }

    /* Turn on the linear address window. */
    rrmw(VGA_CRTC_INDEX, S3_LAW_CTL, ~S3_LAW_ENABLE_MASK, S3_ENABLE_LAW);

    S3_lockRegisters();

    /* Clear the screen. */
    memset(displayInfo->frameBuffer, 0, mode->memSize);
    return self;
}

- resetVGA
{
    int k;
    static const unsigned char xcrtc[S3_XCRTC_COUNT] = {
	0x31, 0x85, 0x32, 0x10, 0x33, 0x00, 0x34, 0x00, 0x35, 0x00,
	0x3A, 0x85, 0x3B, 0x5A, 0x3C, 0x10, 0x40, 0x58, 0x43, 0x00,
	0x50, 0x00, 0x51, 0x00, 0x53, 0x00, 0x54, 0x38, 0x56, 0x00,
	0x57, 0x00, 0x5C, 0x31, 0x5D, 0x00, 0x5E, 0x00, 0x5F, 0x00,
	0x60, 0x07, 0x61, 0x80, 0x62, 0xA1, 0x63, 0xA1,
    };

    /* Disable the linear framebuffer. */
    S3_unlockRegisters();

    if (rread(VGA_CRTC_INDEX, S3_SYS_CNFG) & S3_8514_ACCESS_MASK) {
	/* Wait for the graphics accelerator to stop. */
	while (inw(S3_GP_STAT) & S3_GP_BUSY_MASK)
	    ;
	/* Disable 8514 register access. */
	rrmw(VGA_CRTC_INDEX, S3_SYS_CNFG, ~S3_8514_ACCESS_MASK,
	     S3_8514_DISABLE_ACCESS);
    }

    /* Turn off the linear address window. */
    rrmw(VGA_CRTC_INDEX, S3_LAW_CTL, ~S3_LAW_ENABLE_MASK, S3_DISABLE_LAW);

    /* Turn off the display. */
    rrmw(VGA_SEQ_INDEX, 0x01, 0xDF, 0x20);

    /* Unlock the CRTC registers. */
    rrmw(VGA_CRTC_INDEX, 0x35, ~0x30, 0x00);

    /* Unlock access to the enhanced commands registers. */
    rrmw(VGA_CRTC_INDEX, 0x40, ~0x01, 0x01);

    /* Set VGA mode. */
    outw(S3_ADVFUNC_CNTL, 0x02);

    /* Set the DAC for VGA mode. */
    [self resetDAC];

    /* Set up the extended CRTC registers. */
    for (k = 0; k < S3_XCRTC_COUNT && xcrtc[k] != 0; k += 2)
	rwrite(VGA_CRTC_INDEX, xcrtc[k], xcrtc[k+1]);

    VGASetMode(0x03);

    S3_lockRegisters();

    return self;
}
@end
