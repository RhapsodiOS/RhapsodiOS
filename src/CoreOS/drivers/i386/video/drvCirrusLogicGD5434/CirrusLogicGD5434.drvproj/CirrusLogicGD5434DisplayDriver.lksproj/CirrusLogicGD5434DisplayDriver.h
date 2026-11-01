/* Copyright (c) 1996-1998 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * CirrusLogicGD5434DisplayDriver.h -- interface for the Cirrus Logic
 * CL-GD543X and CL-GD5446 display driver.
 */

#ifndef CIRRUSLOGICGD5434DISPLAYDRIVER_H__
#define CIRRUSLOGICGD5434DISPLAYDRIVER_H__

#import <driverkit/IOFrameBufferDisplay.h>

/* The register values that program one display mode. The `parameters'
 * field of every `IODisplayInfo' in the mode tables points at one of
 * these. The four arrays are the standard VGA register files; the ten
 * scalars that follow are the Cirrus extensions.
 */

typedef struct {
    unsigned char misc;			/* Miscellaneous output (3C2) */
    unsigned char seq[4];		/* SR01 - SR04 */
    unsigned char crtc[25];		/* CR00 - CR18 */
    unsigned char attr[21];		/* AR00 - AR14 */
    unsigned char gfx[9];		/* GR00 - GR08 */
    unsigned char seq07;		/* SR07 */
    unsigned char seq0F;		/* SR0F, merged under mask 0x9F */
    unsigned char seq0E;		/* SR0E; zero means a plain VGA mode */
    unsigned char seq1E;		/* SR1E */
    unsigned char gfx0B;		/* GR0B, merged under mask 0xC0 */
    unsigned char crtc1A;		/* CR1A */
    unsigned char crtc1B;		/* CR1B */
    unsigned char seq16WhenSet;		/* SR16, SR0F bit 2 set */
    unsigned char seq16WhenClear;	/* SR16, SR0F bit 2 clear */
    unsigned char hiddenDAC;		/* Cirrus hidden DAC (3C6) */
} GD5434Mode;

@interface CirrusLogicGD5434DisplayDriver : IOFrameBufferDisplay
{
    /* The memory installed on this device. */
    unsigned int installedVRAMBytes;

    unsigned int pciBus;
    unsigned int pciAddress;

    /* Nonzero if the config table says this is a PCI device. */
    int busType;

    /* The physical address of the frame buffer. */
    unsigned int physicalAddress;

    /* The mapped frame buffer. */
    void *vram;

    /* The transfer tables for this mode. */
    unsigned char *redTransferTable;
    unsigned char *greenTransferTable;
    unsigned char *blueTransferTable;

    /* The number of entries in the transfer table. */
    int transferTableCount;

    /* The current screen brightness. */
    int brightnessLevel;

    /* 0 while initializing, 1 in linear mode, 2 in VGA mode. */
    int currentMode;

    /* 0 GD5430, 1 GD5434, 2 GD5436, 3 GD5446, 4 unknown. */
    int chipType;

    /* The table of modes for this device, and its size. */
    IODisplayInfo *modeTable;
    int modeTableCount;

    /* The mode used when the configured one is unavailable. */
    int defaultMode;
}

- initFromDeviceDescription:deviceDescription;
- (int)selectMode;
- (void)enterLinearMode;
- (void)revertToVGAMode;
- (BOOL)determineConfiguration;
- (BOOL)isValidPCIAssignedBaseAddress:(unsigned int)address;
- (BOOL)setPCIConfiguration;
- (void)setMode:(const GD5434Mode *)mode;
- (void)clearScreen;
- (const char *)name;
- (BOOL)setPendingDisplayMode:(int)mode;
- (unsigned int)displayModeCount;
- (IODisplayInfo *)displayModes;
- (unsigned int)displayMemorySize;
- (unsigned int)ramdacSpeed;

@end

@interface CirrusLogicGD5434DisplayDriver (ProgramDAC)
- setTransferTable:(const unsigned int *)table count:(int)count;
- setBrightness:(int)level token:(int)t;
- setGammaTable;
@end

#endif	/* CIRRUSLOGICGD5434DISPLAYDRIVER_H__ */
