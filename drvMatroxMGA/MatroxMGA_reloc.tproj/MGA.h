/*
 * Copyright © 1998-2007 Mirko Viviani. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. The name of the author may not be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Created by Mirko Viviani 15 Dec 1998
 */

#ifndef MGA_H__
#define MGA_H__

#import <driverkit/IOFrameBufferDisplay.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
//#import "MGAModes.h"
#import "xf86.h"
#import "xf86_PCI.h"
#import "mgax.h"
#import "mga_bios.h"
#import "vga.h"
#import "XModes.h"


#define PCI_VENDOR_MATROX	0x102B

#define PCI_CHIP_MGA2085	0x0518
#define PCI_CHIP_MGA2064	0x0519
#define PCI_CHIP_MGA1064	0x051a
#define PCI_CHIP_MGA2164	0x051b
#define PCI_CHIP_MGA2164_AGP	0x051f
#define PCI_CHIP_MGAG200_PCI	0x0520
#define PCI_CHIP_MGAG200	0x0521
#define PCI_CHIP_MGAG100_PCI	0x1000
#define PCI_CHIP_MGAG100	0x1001
#define PCI_CHIP_MGAG400	0x0525

#define MGAISG450 ( (Chipset == PCI_CHIP_MGAG400) && (ChipRev >= 0x80) )


@interface MatroxMGA:IOFrameBufferDisplay
{
	/* The adapter; either S3_805 or S3_928. */
//	S3AdapterType adapter;

	/* The memory installed on this device. */
	vm_size_t availableMemory;

	/* The type of DAC this device has. */
	int dac;

	/* The bus configuration. */
	int busConfiguration;

	/* The table of valid modes for this device. */
	const IODisplayInfo *modeTable;

	/* The count of valid modes for this device. */
	unsigned int modeTableCount;

	/* The physical address of framebuffer. */
	unsigned long videoRamAddress;

	/* YES if the fast write buffer is enabled; NO otherwise. */
	BOOL writePostingEnabled;

	/* YES if the read-ahead cache is enabled; NO otherwise. */
	BOOL readAheadCacheEnabled;

	/* The transfer tables for this mode. */
	unsigned char *redTransferTable;
	unsigned char *greenTransferTable;
	unsigned char *blueTransferTable;

	/* The number of entries in the transfer table. */
	int transferTableCount;

	/* The current screen brightness. */
	int brightnessLevel;

	/*  Saved crtcext registers.  */
	unsigned char crtcext[6];

	/*  Remember the mode we're in to avoid redundant calls to enterLinearMode.
	SoftPC asks us to do it, and we end up clearing the screen.  */
	enum {
		MODE_NONE, MODE_LINEAR, MODE_VGA,
	} currentMode;

	enum {
		DACTYPE_TVP3026 = 0,
		DACTYPE_MYSTIQUE,
		DACTYPE_GSERIES,
	} dacType;

	pciConfigPtr    MGApcr;

	MGABiosInfo		 MGABios;
	MGABios2Info	 MGABios2;

	pciTagRec		 MGAPciTag;
	int				 Chipset;
	int				 ChipRev;
	int				 MGAinterleave;
	int				 MGABppShifts[4];
	int				 MGAusefbitblt;
	int				 MGAydstorg;
	unsigned char	*MGAMMIOBase;

	MGARamdacRec	 MGAdac;
	BOOL            MGAHasSDRAM;
	BOOL            OverclockMem;
	BOOL		Overlay8Plus24;

	BOOL primaryHead;
	
	BOOL overrideStartBaseAddress;

	ScrnInfoRec		 vga256InfoRec;
	pointer			 vgaNewVideoState;
	int				 vgaBitsPerPixel;
	unsigned int    vgaIOBase;

	xrgb				 xf86weight;

	DisplayModeRec  curmode;
	pointer         vgaSaved;
}

- (void)enterLinearMode;
- (void)revertToVGAMode;
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)setFlags:(IODisplayInfo *)displayInfo withMode:(const XMode *)xmode;
- (void)setPCIIOSpaceAccess:deviceDescription enable:(BOOL)enable;
- (BOOL)fixDeviceDescriptionForPCI:deviceDescription;

@end

@interface MatroxMGA (SetMode)
- (void)reportConfiguration;
- determineConfiguration:(IODeviceDescription *)devDesc;
- selectMode;
- initializeMode;
- enableLinearFrameBuffer;
- resetVGA;
@end

@interface MatroxMGA (ProgramDAC)
- setTransferTable:(unsigned int *)table count:(int)numEntries;
- setBrightness:(int)level token:(int)t;
- setGammaTable;
@end

@interface MatroxMGA (ConfigTable)
- (const char *)valueForStringKey:(const char *)key;
- (int)parametersForMode:(const char *)modeName
	forStringKey:(const char *)key
	parameters:(char *)parameters
	count:(int)count;
- (BOOL)booleanForStringKey:(const char *)key
	withDefault:(BOOL)defaultValue;
- (unsigned int)integerForStringKey:(const char *)key
                        withDefault:(unsigned)defaultValue;
@end

@interface MatroxMGA (vga)
- (void)vgaProtect:(BOOL)on;
- (void)vgaHWRestore:(vgaHWPtr)restore;
- (void *)vgaHWSave:(vgaHWPtr)save withSize:(int)size;
- (BOOL)vgaHWInit:(DisplayModePtr)mode size:(int)size;
@end

@interface MatroxMGA (driver)
- (void)MGAReadBios;
- (int)MGACountRam:(int)blocks;
- (BOOL)MGAProbe;
- (int)TestAndSetRounding:(int)pitch;
- (int)MGALinearOffset;
- (void)MGARestore:(vgaHWPtr)restore;
- (void)MGASave:(vgaHWPtr)save;
- (void)MGAStormSync;
- (void)MGAStormEngineInit;
- (void)MGAEnterLeave:(BOOL)enter;
- (void)MGAAdjust:(int)x y:(int)y;
@end

@interface MatroxMGA (G200)
- (void)MGASetPCLK:(long)f_out;
- (BOOL)MGAG200Init:(DisplayModePtr)mode;
- (void)MGAG200Restore:(pointer)restore;
- (void)MGAG200Save:(pointer)save;
- (void)MGAG200RamdacInit;
@end

@interface MatroxMGA (M3026)
- (void)MGATi3026SetMCLK:(long)f_out;
- (void)MGATi3026SetPCLK:(long)f_out bpp:(int)bpp;
- (BOOL)MGA3026Init:(DisplayModePtr)mode;
- (void)MGA3026Restore:(pointer)restore;
- (void)MGA3026Save:(pointer)save;
- (void)MGA3026RamdacInit;
@end

@interface MatroxMGA (G450)
- (void)G450SetPLLFreq:(long) f_out;
@end


extern const IODisplayInfo MGA_ModeTable[];
extern int MGA_ModeTableCount;
extern int MGA_defaultMode;

extern const char *MGA_memory_size;
extern const char *MGA_sync_on_green;

#endif	/* MGA_H__ */
