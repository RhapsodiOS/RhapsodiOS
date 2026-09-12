/* Copyright (c) 1996-1998 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * IBMThinkPad760ED.m -- driver for the Trident Cyber938x graphics
 * controller as it is wired up in the IBM ThinkPad 560 and 760E/760ED.
 *
 * Two firmware interfaces do most of the work. The panel geometry, the
 * refresh rate, the display device selection and the machine's own
 * identity come from IBM's SMAPI system management call, entered through
 * `smapi_asm' at the port CMOS 0x7E/0x7F names. The display mode is set
 * through the video BIOS, Trident's own call when the chip was positively
 * identified and the VESA one otherwise. The driver programs the hardware
 * directly only to size its memory, to unlock the sequencer, to turn
 * linear addressing on and to load the palette.
 */
#import <string.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import "IBMThinkPad760ED.h"

/* The register block `vidBIOS' hands to the real-mode BIOS, in the order
 * the emulator keeps its registers.
 */

typedef struct {
    unsigned int eax, ecx, edx, ebx;
    unsigned int esp, ebp, esi, edi;
    unsigned int eip, eflags;
    unsigned int es, cs, ss, ds, fs, gs;
} biosRegs;

/* Reassert 5-5-5 direct colour in the hidden DAC command register every
 * half second. System management mode reprograms that register behind the
 * driver's back when the panel state changes, and nothing else in the
 * driver ever writes it, so the only way to keep a 15-bit mode looking
 * right is to keep putting it back.
 *
 * The loop never exits. `revertToVGAMode' parks the thread by clearing
 * the flag and waits for the 2 that acknowledges it; `enterLinearMode'
 * restarts the same thread rather than forking a second one.
 */

static void set555Mode(volatile char *enable)
{
    for (;;) {
	if (*enable == 1) {
	    /* Four reads of the pixel mask arm the hidden register. */
	    inb(0x3C6);
	    inb(0x3C6);
	    inb(0x3C6);
	    inb(0x3C6);
	    outb(0x3C6, 0x10);
	} else {
	    *enable = 2;
	}
	IOSleep(500);
    }
}

/* The parameters of the modes the panel and the Trident BIOS between them
 * can produce.
 */

static const ThinkPad760EDMode mode_640_8_60 = { 1, 0, 0x101, 0x5D };
static const ThinkPad760EDMode mode_640_8_75 = { 1, 2, 0x101, 0x5D };
static const ThinkPad760EDMode mode_640_15_60 = { 1, 0, 0x110, 0x74 };
static const ThinkPad760EDMode mode_640_15_75 = { 1, 2, 0x110, 0x74 };
static const ThinkPad760EDMode mode_800_8_60 = { 2, 0, 0x103, 0x5E };
static const ThinkPad760EDMode mode_800_8_75 = { 2, 2, 0x103, 0x5E };
static const ThinkPad760EDMode mode_800_15_60 = { 2, 0, 0x113, 0x76 };
static const ThinkPad760EDMode mode_800_15_75 = { 2, 2, 0x113, 0x76 };
static const ThinkPad760EDMode mode_1024_8_60 = { 3, 0, 0x105, 0x62 };
static const ThinkPad760EDMode mode_1024_8_75 = { 3, 2, 0x105, 0x62 };
static const ThinkPad760EDMode mode_1024_15_60 = { 3, 0, 0x116, 0x78 };
static const ThinkPad760EDMode mode_1024_15_75 = { 3, 2, 0x116, 0x78 };
static const ThinkPad760EDMode mode_1280_8_60 = { 4, 0, 0x107, 0x64 };
static const ThinkPad760EDMode mode_1280_8_75 = { 4, 2, 0x107, 0x64 };

const int defaultMode = 0;
const int modeTableCount = 14;

/* The modes this driver offers. `memorySize', `scanRate', `screenWidth',
 * `screenHeight' and `modeUnavailableFlag' are filled in by
 * `updateModeTable' and `frameBuffer' by `setPendingDisplayMode:', which
 * is why this table is not const.
 */

IODisplayInfo ThinkPad760EDModeTable[14] = {
    /* 0 */
    { 640, 480, 640, 640, 60, 0, IO_8BitsPerPixel,
	IO_RGBColorSpace,
	"PPPPPPPP",
	0, (void *)&mode_640_8_60 },
    /* 1 */
    { 640, 480, 640, 640, 75, 0, IO_8BitsPerPixel,
	IO_RGBColorSpace,
	"PPPPPPPP",
	0, (void *)&mode_640_8_75 },
    /* 2 */
    { 640, 480, 640, 1280, 60, 0, IO_15BitsPerPixel,
	IO_RGBColorSpace,
	"-RRRRRGGGGGBBBBB",
	0, (void *)&mode_640_15_60 },
    /* 3 */
    { 640, 480, 640, 1280, 75, 0, IO_15BitsPerPixel,
	IO_RGBColorSpace,
	"-RRRRRGGGGGBBBBB",
	0, (void *)&mode_640_15_75 },
    /* 4 */
    { 800, 600, 800, 800, 60, 0, IO_8BitsPerPixel,
	IO_RGBColorSpace,
	"PPPPPPPP",
	0, (void *)&mode_800_8_60 },
    /* 5 */
    { 800, 600, 800, 800, 75, 0, IO_8BitsPerPixel,
	IO_RGBColorSpace,
	"PPPPPPPP",
	0, (void *)&mode_800_8_75 },
    /* 6 */
    { 800, 600, 800, 1600, 60, 0, IO_15BitsPerPixel,
	IO_RGBColorSpace,
	"-RRRRRGGGGGBBBBB",
	0, (void *)&mode_800_15_60 },
    /* 7 */
    { 800, 600, 800, 1600, 75, 0, IO_15BitsPerPixel,
	IO_RGBColorSpace,
	"-RRRRRGGGGGBBBBB",
	0, (void *)&mode_800_15_75 },
    /* 8 */
    { 1024, 768, 1024, 1024, 60, 0, IO_8BitsPerPixel,
	IO_RGBColorSpace,
	"PPPPPPPP",
	0, (void *)&mode_1024_8_60 },
    /* 9 */
    { 1024, 768, 1024, 1024, 75, 0, IO_8BitsPerPixel,
	IO_RGBColorSpace,
	"PPPPPPPP",
	0, (void *)&mode_1024_8_75 },
    /* 10 */
    { 1024, 768, 1024, 2048, 60, 0, IO_15BitsPerPixel,
	IO_RGBColorSpace,
	"-RRRRRGGGGGBBBBB",
	0, (void *)&mode_1024_15_60 },
    /* 11 */
    { 1024, 768, 1024, 2048, 75, 0, IO_15BitsPerPixel,
	IO_RGBColorSpace,
	"-RRRRRGGGGGBBBBB",
	0, (void *)&mode_1024_15_75 },
    /* 12 */
    { 1280, 1024, 1280, 1280, 60, 0, IO_8BitsPerPixel,
	IO_RGBColorSpace,
	"PPPPPPPP",
	0, (void *)&mode_1280_8_60 },
    /* 13 */
    { 1280, 1024, 1280, 1280, 75, 0, IO_8BitsPerPixel,
	IO_RGBColorSpace,
	"PPPPPPPP",
	0, (void *)&mode_1280_8_75 }
};

@implementation IBMThinkPad760EDDisplayDriver

/* Identify the chip, find the SMAPI port, pick a mode and map the frame
 * buffer. The chip has to be identified before the superclass sees the
 * device description, so `determineConfiguration:' runs first. Every
 * failure returns whatever `[self free]' returns.
 */
- initFromDeviceDescription:deviceDescription
{
    IODisplayInfo *displayInfo;

    blueTransferTable = 0;
    greenTransferTable = 0;
    redTransferTable = 0;
    transferTableCount = 0;
    brightnessLevel = EV_SCREEN_MAX_BRIGHTNESS;
    modeIndex = 0;
    physicalAddress = 0;
    displayMemorySize = 0;
    virtualAddress = 0;
    currentState = 0;
    BiosType = 0;
    crtOnlyDisplay = 0;
    mode555_thread = 0;
    LCDWidth = 0;
    viewportSize = 0x0204;

    if ([self determineConfiguration:deviceDescription] == NO)
	return [self free];

    if ([super initFromDeviceDescription:deviceDescription] == nil)
	return [self free];

    bios = [[vidBIOS alloc] init];
    if (bios == nil) {
	IOLog("%s: vidBIOS alloc failure", [self name]);
	return [self free];
    }

    if ([self setPCIConfiguration] == NO)
	return [self free];

    smapiPort = ([self readCMOS:0x7F] << 8) | [self readCMOS:0x7E];

    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x0000;
    reg.cx.x = 0;
    smapi_asm(&reg);
    if (reg.ax.b.h != 0) {
	IOLog("%s: Unable to call SMAPI at port 0x%04x\n", [self name],
	      smapiPort);
	return [self free];
    }

    [self reportSystemConfiguration];

    /* The fallback installs the default mode's `IODisplayInfo' and stops
     * there: neither the panel nor the video BIOS is programmed for it
     * until the window server enters linear mode.
     */
    modeIndex = [self selectMode];
    if ([self setPendingDisplayMode:modeIndex] == NO) {
	IOLog("%s: Cannot use requested display mode. ", [self name]);
	IOLog("Trying default mode.\n");
	modeIndex = [self defaultMode];
    }

    physicalAddress = [deviceDescription memoryRangeList][0].start;
    virtualAddress = (void *)[self
	    mapFrameBufferAtPhysicalAddress:physicalAddress
	    length:displayMemorySize];
    if (virtualAddress == 0) {
	IOLog("%s: Error: Unable to map frame buffer\n", [self name]);
	return [self free];
    }

    displayInfo = [self displayInfo];
    *displayInfo = ThinkPad760EDModeTable[modeIndex];
    displayInfo->frameBuffer = virtualAddress;
    if (displayInfo->bitsPerPixel == IO_8BitsPerPixel)
	displayInfo->flags |= IO_DISPLAY_HAS_TRANSFER_TABLE;
    else
	displayInfo->flags |= IO_DISPLAY_NEEDS_SOFTWARE_GAMMA_CORRECTION;

    [self updateModeTable];
    return self;
}

/* Work out what each mode costs and mark the ones this much display
 * memory cannot hold. Unlike the panel test in `defaultMode', this
 * applies to every mode however wide.
 */
- (void)updateModeTable
{
    int i;

    for (i = 0; i < modeTableCount; i++) {
	ThinkPad760EDModeTable[i].memorySize =
	    ThinkPad760EDModeTable[i].rowBytes *
	    ThinkPad760EDModeTable[i].height;
	ThinkPad760EDModeTable[i].scanRate = 0;
	ThinkPad760EDModeTable[i].screenWidth = 0;
	ThinkPad760EDModeTable[i].screenHeight = 0;
	ThinkPad760EDModeTable[i].modeUnavailableFlag = 0;

	if (displayMemorySize < ThinkPad760EDModeTable[i].memorySize)
	    ThinkPad760EDModeTable[i].modeUnavailableFlag =
		IO_DISPLAY_MODE_NEEDS_MORE_MEMORY;
    }
}

/* Ask the superclass to pick the configured mode, telling it which
 * entries the display memory can actually hold. Any complaint is left to
 * `initFromDeviceDescription:'.
 */
- (int)selectMode
{
    BOOL valid[modeTableCount];
    int i;

    for (i = 0; i < modeTableCount; i++) {
	valid[i] = (displayMemorySize >=
		    ThinkPad760EDModeTable[i].rowBytes *
		    ThinkPad760EDModeTable[i].height);
    }

    return [self selectMode:ThinkPad760EDModeTable count:modeTableCount
	    valid:valid];
}

/* The highest-numbered mode that both fits in memory and matches the
 * built-in panel, or the configured default if none does. The loop keeps
 * going after a match, so the last one wins.
 */
- (int)defaultMode
{
    const ThinkPad760EDMode *parameters;
    int mode = defaultMode;
    int i;

    for (i = 0; i < modeTableCount; i++) {
	if (displayMemorySize < ThinkPad760EDModeTable[i].rowBytes *
				ThinkPad760EDModeTable[i].height)
	    continue;
	parameters = ThinkPad760EDModeTable[i].parameters;
	if (LCDWidth != parameters->panelSize - 1)
	    continue;
	mode = i;
    }
    return mode;
}

/* Put the display into linear frame buffer mode. The order is
 * load-bearing: the panel geometry and the refresh rate have to reach
 * system management before the BIOS sets the mode, and the aperture is
 * cleared before the palette is loaded so that the screen is blank rather
 * than showing the old palette against the new mode.
 */
- (void)enterLinearMode
{
    const ThinkPad760EDMode *parameters = [self displayInfo]->parameters;
    biosRegs regs;

    if (currentState == 1)
	return;
    currentState = 1;

    /* Tell system management which panel geometry is coming. */
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x100B;
    reg.cx.x = parameters->panelSize;
    smapi_asm(&reg);

    /* Set the refresh rate. */
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x1009;
    reg.cx.x = (parameters->panelSize << 8) | parameters->refresh;
    smapi_asm(&reg);
    if (reg.ax.b.h != 0)
	IOLog("%s: Unable to set refresh rate using SMAPI\n", [self name]);

    if (BiosType == 1) {
	/* Trident's own set mode call takes the mode in BH and the
	 * refresh rate in CX. It reports failure in AH.
	 */
	bzero(&regs, sizeof(regs));
	regs.eax = 0x1200;
	regs.ebx = (parameters->tvgaMode << 8) | 0x14;
	regs.ecx = [self displayInfo]->refreshRate;
	[bios int10:&regs outregs:&regs iorange:0 ionum:0 smmport:smapiPort];
	if ((regs.eax >> 8) & 0xFF)
	    IOLog("%s: TVGA BIOS SetMode failure (%04x)\n", [self name],
		  regs.eax & 0xFFFF);
    } else {
	/* The VESA call reports success as 0x004F in AX. */
	bzero(&regs, sizeof(regs));
	regs.eax = 0x4F02;
	regs.ebx = parameters->vesaMode;
	[bios int10:&regs outregs:&regs iorange:0 ionum:0 smmport:smapiPort];
	if ((regs.eax & 0xFFFF) != 0x004F)
	    IOLog("%s: Vesa BIOS SetMode failure (%04x)\n", [self name],
		  regs.eax & 0xFFFF);
    }

    /* CR21 bit 5 enables linear addressing. */
    [self unlockRegisters];
    outw(0x3D4, 0x2021);
    [self lockRegisters];

    bzero(virtualAddress, displayMemorySize);
    [self setGammaTable];

    /* A 15-bit mode on the panel needs the hidden DAC reasserting. */
    if ([self displayInfo]->bitsPerPixel == IO_15BitsPerPixel &&
	crtOnlyDisplay == 0) {
	mode555_thread_enable = 1;
	if (mode555_thread == 0) {
	    mode555_thread = IOForkThread((IOThreadFunc)set555Mode,
					  (void *)&mode555_thread_enable);
	    IOSetThreadPriority(mode555_thread, 0);
	}
    }
}

/* Get the device back into a state where it can be used as a standard VGA
 * device: stop the 5-5-5 thread, put the panel back to its 640x480
 * geometry and set BIOS mode 3.
 */
- (void)revertToVGAMode
{
    biosRegs regs;
    int i;

    currentState = 0;

    if (mode555_thread != 0) {
	/* Ask the thread to stop and wait up to three seconds for it to
	 * say that it has. The thread itself is left alive to be reused.
	 */
	mode555_thread_enable = 0;
	for (i = 0; i < 3000; i++) {
	    if (mode555_thread_enable == 2)
		break;
	    IOSleep(1);
	}
    }

    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x100B;
    reg.cx.x = 1;
    smapi_asm(&reg);

    bzero(&regs, sizeof(regs));
    regs.eax = 3;
    [bios int10:&regs outregs:&regs iorange:0 ionum:0 smmport:smapiPort];

    [super revertToVGAMode];
}

/* Ask the VESA BIOS whether it can produce `mode'. Only bit 0 of the
 * returned mode attributes, `supported in hardware', is looked at.
 */
- (BOOL)getModeInfo:(unsigned int)mode
{
    biosRegs regs;
    unsigned int segment;
    unsigned char *buffer;

    bzero(&regs, sizeof(regs));
    regs.eax = 0x4F01;
    regs.ecx = mode;
    segment = (unsigned int)[bios scratchSegment];
    regs.es = segment;
    regs.edi = 0;
    buffer = (unsigned char *)[bios realToVirtual:segment :0];
    bzero(buffer, 256);
    [bios int10:&regs outregs:&regs iorange:0 ionum:0 smmport:smapiPort];

    if (((regs.eax & 0xFFFF) == 0x004F) && (buffer[0] & 1))
	return YES;
    return NO;
}

/* Identify the graphics chip and size its memory. The device description
 * is not needed for either.
 *
 * Bit 7 of SR08 says which sequencer protocol the chip was speaking. Clear
 * means old mode, and the SR0B read above has just switched it to new mode,
 * so SR0B is written back to restore it; set means the chip was already in
 * new mode and nothing has to be undone. Either way the chip identifier
 * read out of SR0B has to match. A chip that fails that test is still
 * driven, but through the VESA BIOS and with a conservative 1 MB.
 */
- (BOOL)determineConfiguration:deviceDescription
{
    unsigned char sr08, sr09, sr0b;

    outb(0x3C4, 0x08);
    sr08 = inb(0x3C5);
    outb(0x3C4, 0x09);
    sr09 = inb(0x3C5);
    outb(0x3C4, 0x0B);
    sr0b = inb(0x3C5);			/* the read switches to new mode */

    if ((signed char)sr08 >= 0)
	outw(0x3C4, (sr0b << 8) | 0x0B);

    outw(0x3D4, 0x042A);

    if (sr0b != 0xD3) {
	IOLog("%s: Trident Cyber938x not detected - trying anyway\n",
	      [self name]);
	IOLog("%s: Chip ID=0x%02x, Revision=0x%02x\n", [self name],
	      sr0b, sr09);
	displayMemorySize = 0x100000;
	goto report;
    }

    IOLog("%s: Detected Trident Cyber938x (rev 0x%02x)\n", [self name], sr09);
    BiosType = 1;

    /* The low three bits of CR1F give the installed DRAM. */
    outb(0x3D4, 0x1F);
    switch (inb(0x3D5) & 7) {
    case 5:
	displayMemorySize = 0x400000;
	break;

    case 7:
	displayMemorySize = 0x200000;
	break;

    default:
	displayMemorySize = 0x100000;
	break;
    }

report:
    IOLog("%s: Found %d MB DRAM\n", [self name], displayMemorySize >> 20);
    return YES;
}

/* Reject a base address the BIOS left in the low eight megabytes, where
 * main memory lives.
 */
- (BOOL)isValidPCIAssignedBaseAddress:(void *)address
{
    if ((unsigned int)address > 0x7FFFFF)
	return YES;
    return NO;
}

/* Take the frame buffer base address from PCI configuration space and
 * make the device description agree with it, or, if the assigned address
 * is unusable, make the card agree with the device description. The card
 * is stopped from decoding either space while the address moves.
 */
- (BOOL)setPCIConfiguration
{
    IOPCIConfigSpace configSpace;
    IORange range[3];
    unsigned char deviceNumber, functionNumber, busNumber;
    unsigned long command;
    IOPCIDeviceDescription *deviceDescription;
    IORange *rangeList;
    int rangeCount;
    int i;

    deviceDescription = [self deviceDescription];

    if ([deviceDescription getPCIdevice:&deviceNumber
	 function:&functionNumber bus:&busNumber] != IO_R_SUCCESS) {
	IOLog("%s: Error: Unsupported PCI hardware\n", [self name]);
	return NO;
    }

    [[self class] getPCIConfigData:&command atRegister:4
     withDeviceDescription:deviceDescription];
    [[self class] setPCIConfigData:(command & ~3) atRegister:4
     withDeviceDescription:deviceDescription];

    [self getPCIConfigSpace:&configSpace];
    physicalAddress = configSpace.BaseAddress[0];
    physicalAddress &= ~0x0F;

    if ([self isValidPCIAssignedBaseAddress:(void *)physicalAddress]) {
	rangeList = [deviceDescription memoryRangeList];
	rangeCount = [deviceDescription numMemoryRanges];
	if (rangeCount != 3) {
	    IOLog("%s: Error: Incorrect number of address ranges: %d.\n",
		  [self name], rangeCount);
	    return NO;
	}

	for (i = 0; i < rangeCount; i++)
	    range[i] = rangeList[i];
	range[0].start = physicalAddress;
	if ([deviceDescription setMemoryRangeList:range num:3] !=
	    IO_R_SUCCESS) {
	    IOLog("%s: Error: Can't set memory range, using default.\n",
		  [self name]);

	    /* Go back to the ranges the BIOS assigned and adopt the base
	     * address we were trying to replace.
	     */
	    for (i = 0; i < rangeCount; i++)
		range[i] = rangeList[i];
	    physicalAddress = range[0].start;
	    if ([deviceDescription setMemoryRangeList:range num:3] !=
		IO_R_SUCCESS) {
		IOLog("%s: Error: Can't set to default range either!\n",
		      [self name]);
		return NO;
	    }
	}
    } else {
	/* The assigned base address is unusable, so tell the card about
	 * the one the device description already has.
	 */
	physicalAddress = [deviceDescription memoryRangeList][0].start;
	configSpace.BaseAddress[0] = physicalAddress;
	[self setPCIConfigSpace:&configSpace];
    }

    [[self class] setPCIConfigData:(command | 3) atRegister:4
     withDeviceDescription:deviceDescription];
    return YES;
}

/* Decide whether `mode' can be displayed, and if it can, prepare system
 * management for it. A mode wider than the built-in panel is only offered
 * when an external monitor is attached, and it takes the display over
 * completely while it is being tested. Every rejection here is silent.
 */
- (BOOL)setPendingDisplayMode:(int)mode
{
    const ThinkPad760EDMode *parameters =
	ThinkPad760EDModeTable[mode].parameters;
    unsigned int savedState = 0;
    BOOL crtOnly = NO;

    if (mode < 0)
	return NO;
    if (mode >= modeTableCount)
	return NO;
    if (ThinkPad760EDModeTable[mode].modeUnavailableFlag != 0)
	return NO;

    if (LCDWidth < (unsigned int)(parameters->panelSize - 1)) {
	crtOnly = YES;

	/* CH comes back with the attached display devices. */
	reg.ax.x = 0x5380;
	reg.dx.x = smapiPort;
	reg.bx.x = 0x0002;
	reg.cx.x = 0x0200;
	smapi_asm(&reg);
	if (reg.cx.b.h == 0)
	    return NO;
    }

    if (crtOnly) {
	savedState = [self getDisplayDeviceState];
	if (savedState != 2)
	    [self setDisplayDeviceState:2];
    }

    if ([self getModeInfo:parameters->vesaMode] == NO) {
	if (crtOnly)
	    [self setDisplayDeviceState:savedState];
	return NO;
    }

    crtOnlyDisplay = crtOnly;

    if (crtOnly) {
	reg.ax.x = 0x5380;
	reg.dx.x = smapiPort;
	reg.bx.x = 0x100D;
	reg.cx.x = 0x0101;
	smapi_asm(&reg);
    } else {
	reg.ax.x = 0x5380;
	reg.dx.x = smapiPort;
	reg.bx.x = 0x100D;
	reg.cx.x = viewportSize;
	smapi_asm(&reg);
    }

    reg.cx.x = parameters->panelSize;
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x100B;
    smapi_asm(&reg);

    ThinkPad760EDModeTable[mode].frameBuffer = virtualAddress;

    if ([super setPendingDisplayMode:mode] == NO)
	return NO;
    modeIndex = mode;
    return YES;
}

/* The two display device enables, LCD and CRT. A value of 2 is CRT only.
 * The SMAPI result is not checked.
 */
- (unsigned int)getDisplayDeviceState
{
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x1000;
    reg.cx.x = 0;
    smapi_asm(&reg);
    return (reg.cx.x >> 8) & 3;
}

/* Select the display devices. Bit 7 of CH commits the change.
 */
- (void)setDisplayDeviceState:(unsigned int)state
{
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x1001;
    reg.cx.x = ((state & 3) | 0x80) << 8;
    smapi_asm(&reg);
}

/* Clear the protection bit in SR0E so that the extended registers can be
 * written. Bit 7 of SR08 says which of the two sequencer protocols the
 * chip is speaking; the old one has to be switched to new mode and back
 * around the write.
 */
- (void)unlockRegisters
{
    unsigned char value;

    outb(0x3C4, 0x08);
    if ((signed char)inb(0x3C5) >= 0) {
	outb(0x3C4, 0x0B);
	inb(0x3C5);
	outb(0x3C4, 0x0E);
	value = inb(0x3C5);
	outb(0x3C5, value | 0x80);
	outw(0x3C4, 0x000B);
    } else {
	outb(0x3C4, 0x0E);
	value = inb(0x3C5);
	outb(0x3C5, value | 0x80);
    }
}

/* Set the protection bit again. Otherwise identical to `unlockRegisters'.
 */
- (void)lockRegisters
{
    unsigned char value;

    outb(0x3C4, 0x08);
    if ((signed char)inb(0x3C5) >= 0) {
	outb(0x3C4, 0x0B);
	inb(0x3C5);
	outb(0x3C4, 0x0E);
	value = inb(0x3C5);
	outb(0x3C5, value & 0x7F);
	outw(0x3C4, 0x000B);
    } else {
	outb(0x3C4, 0x0E);
	value = inb(0x3C5);
	outb(0x3C5, value & 0x7F);
    }
}

/* The three transfer tables are one allocation whose head is the red one,
 * so freeing the red one frees all three.
 */
- free
{
    if (redTransferTable != 0) {
	IOFree(redTransferTable, 3 * transferTableCount);
	redTransferTable = 0;
    }
    return [super free];
}

- (unsigned int)displayModeCount
{
    return modeTableCount;
}

- (IODisplayInfo *)displayModes
{
    return ThinkPad760EDModeTable;
}

- (unsigned int)displayMemorySize
{
    return displayMemorySize;
}

- (unsigned int)ramdacSpeed
{
    return 0;
}

/* Read one CMOS byte. Bit 7 of the index masks NMI for the duration, and
 * interrupts are off so that nothing else can move the index register
 * between the two halves of the transaction. The index is left pointing
 * at the harmless shutdown status byte.
 */
- (unsigned short)readCMOS:(unsigned char)index
{
    unsigned char value;

    asm volatile("cli");
    outb(0x70, index | 0x80);
    value = inb(0x71);
    outb(0x70, 0x0F);
    inb(0x71);
    asm volatile("sti");
    return value;
}

/* Log what SMAPI has to say about the machine, and pick up the two things
 * the driver needs from it: the panel size and the current viewport
 * setting. Each query stands on its own; one that fails costs only its
 * own output.
 */
- (void)reportSystemConfiguration
{
    const char *vendor;
    const char *panelType;
    const char *panelSize;

    /* System identity and firmware revisions. */
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x0000;
    reg.cx.x = 0;
    smapi_asm(&reg);
    if (reg.ax.b.h == 0) {
	IOLog("%s: System ID = 0x%04x\n", [self name], reg.bx.x);
	IOLog("%s: System BIOS revision %01x.%02x\n", [self name],
	      reg.dx.b.h + 1, reg.dx.b.l);
	if (reg.si.x != 0xFFFF)
	    IOLog("%s: System management BIOS revision %01x.%02x\n",
		  [self name], reg.si.b.h, reg.si.b.l);
	IOLog("%s: SMAPI revision %01x.%02x\n", [self name],
	      reg.di.b.h, reg.di.b.l);
    }

    /* Video BIOS revision. */
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x0008;
    reg.cx.x = 0;
    smapi_asm(&reg);
    if (reg.ax.b.h == 0)
	IOLog("%s: Video BIOS revision %01x.%02x\n", [self name],
	      reg.bx.b.h, reg.bx.b.l);

    /* Slave controller revision. */
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x0006;
    reg.cx.x = 0;
    smapi_asm(&reg);
    if (reg.ax.b.h == 0 && reg.cx.x != 0xFFFF)
	IOLog("%s: Slave controller revision %01x.%02x\n", [self name],
	      reg.cx.b.h, reg.cx.b.l);

    /* CPU identity and clocks. Either half of the clock line is `?' when
     * the firmware reports 0xFF for it.
     */
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x0001;
    reg.cx.x = 0;
    smapi_asm(&reg);
    if (reg.ax.b.h == 0) {
	switch (reg.bx.b.l) {
	case 1:
	    vendor = "Intel";
	    break;

	case 2:
	    vendor = "AMD";
	    break;

	default:
	    vendor = "Unknown";
	    break;
	}

	IOLog("%s: %s CPU Family %d, Model %d, Stepping %d\n", [self name],
	      vendor, reg.cx.b.h, reg.cx.b.l >> 4, reg.cx.b.l & 0x0F);
	IOLog("%s: CPU clock (Int/Ext) = ", [self name]);
	if (reg.dx.b.l != 0xFF)
	    IOLog("%d", reg.dx.b.l);
	else
	    IOLog("?");
	if (reg.dx.b.h != 0xFF)
	    IOLog("/%d MHz\n", reg.dx.b.h);
	else
	    IOLog("/? MHz\n");
    }

    /* The panel. This is the only place `LCDWidth' is written. */
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x0002;
    reg.cx.x = 0x0100;
    smapi_asm(&reg);
    if (reg.ax.b.h == 0) {
	switch (reg.bx.b.h) {
	case 0:
	    panelType = "Monochrome STN";
	    break;

	case 1:
	    panelType = "Monochrome TFT";
	    break;

	case 2:
	    panelType = "Color STN";
	    break;

	case 3:
	    panelType = "Color TFT";
	    break;

	default:
	    panelType = "Unknown";
	    break;
	}

	LCDWidth = reg.bx.b.l;

	switch (reg.bx.b.l) {
	case 0:
	    panelSize = "640x480";
	    break;

	case 1:
	    panelSize = "800x600";
	    break;

	case 2:
	    panelSize = "1024x768";
	    break;

	default:
	    panelSize = "Unknown";
	    break;
	}

	IOLog("%s: %s LCD (%s)\n", [self name], panelType, panelSize);
    }

    /* The viewport setting, handed back to SMAPI unchanged by
     * `setPendingDisplayMode:'.
     */
    reg.ax.x = 0x5380;
    reg.dx.x = smapiPort;
    reg.bx.x = 0x100C;
    reg.cx.x = 0;
    smapi_asm(&reg);
    if (reg.ax.b.h == 0)
	viewportSize = reg.cx.x;
}

- (const char *)name
{
    const char *name;

    name = [super name];
    return (name == 0 || *name == '\0') ? "Display0" : name;
}

@end
