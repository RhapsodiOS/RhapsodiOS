/* Copyright (c) 1996-1998 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * IBMThinkPad760ED.h -- interface for the display driver of the IBM
 * ThinkPad 560 and 760E/760ED.
 *
 * The graphics controller is a Trident Cyber938x; the panel, the CPU and
 * the system BIOS are reached through IBM's SMAPI system management call,
 * and the mode is set through the video BIOS rather than by programming
 * the CRTC directly.
 */

#ifndef IBMTHINKPAD760ED_H__
#define IBMTHINKPAD760ED_H__

#import <driverkit/IOFrameBufferDisplay.h>

#import <objc/Object.h>
#import <driverkit/driverTypes.h>

typedef struct {
    unsigned int	eax, ecx, edx, ebx;
    unsigned int	esp, ebp, esi, edi;
    unsigned int	eip, eflags;
    unsigned int	es, cs, ss, ds, fs, gs;
} emu486regs_t;

extern int	emu486(void *lowMemBase, const emu486regs_t *inregs,
		       emu486regs_t *outregs, const char *pagePerm,
		       const char *ioPerm, unsigned int smmport);

@interface vidBIOS : Object
{
    void	       *biosStackVirtual;
    unsigned int	biosStackPhysical;
    unsigned int	lowMem;
}
- init;
- free;
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges;
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges
	smmport	: (unsigned int)smmport;
- (unsigned int)scratchSegment;
- (void *)realToVirtual:(unsigned int)segment :(unsigned int)offset;
@end

/* The register block the SMAPI trap loads before entering system
 * management mode and stores again on the way out. `smapi_asm' reads and
 * writes sixteen bits at each of the offsets 0, 4, 8, 12, 16 and 20, so
 * the six members are four bytes apart whatever width the caller uses.
 * Callers put 0x5380 in `ax', the SMAPI port in `dx', the function code in
 * `bx' and the parameter in `cx'; `si' and `di' are outputs only.
 */

struct smapiReg {
    union {
	unsigned int e;
	unsigned short x;
	struct {
	    unsigned char l, h;
	} b;
    } ax, bx, cx, dx, si, di;
};

extern void smapi_asm(struct smapiReg *r);

/* The parameters that program one display mode. The `parameters' field of
 * every `IODisplayInfo' in the mode table points at one of these. The
 * panel size is one-based here so that the `LCDWidth' instance variable,
 * which SMAPI reports zero-based, is compared as `panelSize - 1'. Neither
 * BIOS mode number is ever decoded by the driver.
 */

typedef struct {
    unsigned char panelSize;		/* 1 640x480 ... 4 1280x1024 */
    unsigned char refresh;		/* 0 60Hz, 2 75Hz */
    unsigned int vesaMode;		/* VESA BIOS mode number */
    unsigned int tvgaMode;		/* Trident BIOS mode number */
} ThinkPad760EDMode;

@interface IBMThinkPad760EDDisplayDriver : IOFrameBufferDisplay
{
    /* The entry of the mode table this display is running. */
    int modeIndex;

    /* 0 while initializing or in VGA mode, 1 in linear mode. */
    int currentState;

    /* Set when the mode is too wide for the built-in panel and needs an
     * external monitor. */
    char crtOnlyDisplay;

    /* The panel size SMAPI reports: 0 640x480, 1 800x600, 2 1024x768. */
    int LCDWidth;

    /* The viewport setting SMAPI reports, handed back to it unchanged. */
    unsigned short viewportSize;

    /* The detected display memory, in bytes. */
    unsigned int displayMemorySize;

    /* The frame buffer, physical and mapped. */
    unsigned int physicalAddress;
    void *virtualAddress;

    /* The transfer tables for this mode. `red' is the head of the single
     * allocation the three of them are carved out of. */
    int transferTableCount;
    int brightnessLevel;
    char *redTransferTable;
    char *greenTransferTable;
    char *blueTransferTable;

    /* The register block every SMAPI call goes through, and the port the
     * call is entered by. */
    struct smapiReg reg;
    unsigned short smapiPort;

    /* The video BIOS. */
    vidBIOS *bios;

    /* 1 when a Trident Cyber938x was positively identified, and its BIOS
     * can be used in place of the VESA one. */
    int BiosType;

    /* The thread that keeps the hidden DAC in 5-5-5 mode, and the byte it
     * is stopped and started with: 1 run, 0 stop, 2 stopped. */
    void *mode555_thread;
    char mode555_thread_enable;
}

- initFromDeviceDescription:deviceDescription;
- (void)updateModeTable;
- (int)selectMode;
- (int)defaultMode;
- (void)enterLinearMode;
- (void)revertToVGAMode;
- (BOOL)getModeInfo:(unsigned int)mode;
- (BOOL)determineConfiguration:deviceDescription;
- (BOOL)isValidPCIAssignedBaseAddress:(void *)address;
- (BOOL)setPCIConfiguration;
- (BOOL)setPendingDisplayMode:(int)mode;
- (unsigned int)getDisplayDeviceState;
- (void)setDisplayDeviceState:(unsigned int)state;
- (void)unlockRegisters;
- (void)lockRegisters;
- free;
- (unsigned int)displayModeCount;
- (IODisplayInfo *)displayModes;
- (unsigned int)displayMemorySize;
- (unsigned int)ramdacSpeed;
- (unsigned short)readCMOS:(unsigned char)index;
- (void)reportSystemConfiguration;
- (const char *)name;

@end

@interface IBMThinkPad760EDDisplayDriver (TransferTable)
- setTransferTable:(const unsigned int *)table count:(int)count;
- setBrightness:(int)level token:(int)t;
- (void)SetGammaValueRed:(unsigned int)r Green:(unsigned int)g
		    Blue:(unsigned int)b Level:(int)level;
- setGammaTable;
@end

#endif	/* IBMTHINKPAD760ED_H__ */
