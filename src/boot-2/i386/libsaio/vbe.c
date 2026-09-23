/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Copyright 1993 NeXT, Inc.
 * All rights reserved.
 */
#import "io_inline.h"
#import "libsaio.h"
#import "console.h"
#import "vbe.h"
#import "kernBootStruct.h"
#import "appleClut8.h"

/*
 * Local Prototypes
 */
void setupPalette(VBEPalette *p, const unsigned char *g);

/*
 * Globals
 */
static biosBuf_t bb;
static int vbeModeCount = -1;	/* enumerateVBEModes()'s cache; 0xDEAC in 4.2 */

static char *models[] = { "Text", 
			  "CGA", 
			  "Hercules", 
			  "Planar", 
			  "Packed Pixel", 
			  "Non-Chain 4", 
			  "Direct Color", 
			  "YUV" };

/*
 * OPENSTEP 4.2 User Patch 4's mode test (boot+27424..27515): supported,
 * graphics and linear; a direct colour mode must also have equal 5- or
 * 8-bit masks and a depth of 15, 16 or 32.
 */
int
vbeModeIsUsable(VBEModeInfoBlock *minfo)
{
    int usable = 1;

    if (!(minfo->ModeAttributes & maModeIsSupportedBit))
	usable = 0;
    if (!(minfo->ModeAttributes & maLinearFrameBufferAvailBit))
	usable = 0;
    if (!(minfo->ModeAttributes & maGraphicsModeBit))
	usable = 0;
    if (minfo->MemoryModel == 6) {	/* direct colour */
	if (minfo->RedMaskSize != minfo->GreenMaskSize ||
	    minfo->RedMaskSize != minfo->BlueMaskSize)
	    usable = 0;
	if (minfo->RedMaskSize != 5 && minfo->RedMaskSize != 8)
	    usable = 0;
	if (minfo->BitsPerPixel != 15 && minfo->BitsPerPixel != 16 &&
	    minfo->BitsPerPixel != 32)
	    usable = 0;
    }
    return usable;
}

/*
 * 4.2's test for the mode list (boot+27516..27555): usable, and at least
 * 640x480.
 */
int
vbeModeIsLargeEnough(VBEModeInfoBlock *minfo)
{
    int usable = vbeModeIsUsable(minfo);

    if (minfo->YResolution < 480 || minfo->XResolution < 640)
	usable = 0;
    return usable;
}

/*
 * OPENSTEP 4.2 User Patch 4's record writer (boot+27556..27703): one
 * boot_vbe_mode from the BIOS's mode information, one store per field.
 */
void
recordVBEMode(boot_vbe_mode *rec, unsigned short mode, VBEModeInfoBlock *minfo)
{
    rec->modeNumber = mode;
    rec->modeAttributes = minfo->ModeAttributes;
    rec->xResolution = minfo->XResolution;
    rec->yResolution = minfo->YResolution;
    rec->bytesPerScanline = minfo->BytesPerScanline;
    rec->bitsPerPixel = minfo->BitsPerPixel;
    rec->memoryModel = minfo->MemoryModel;
    rec->redMaskSize = minfo->RedMaskSize;
    rec->redFieldPosition = minfo->RedFieldPosition;
    rec->greenMaskSize = minfo->GreenMaskSize;
    rec->greenFieldPosition = minfo->GreenFieldPosition;
    rec->blueMaskSize = minfo->BlueMaskSize;
    rec->blueFieldPosition = minfo->BlueFieldPosition;
    rec->frameBuffer = ADDRESS(minfo->PhysBasePtr_low,
			       minfo->PhysBasePtr_1,
			       minfo->PhysBasePtr_2,
			       minfo->PhysBasePtr_high);
}

/*
 * OPENSTEP 4.2 User Patch 4's enumerator (boot+27704..28031): fill
 * kernBootStruct->vbeModes with every usable mode of at least 640x480, once,
 * and return how many there are. No terminator is written; the array ends
 * where getKernBootStruct()'s bzero left zeros.
 */
int
enumerateVBEModes(void)
{
    VBEInfoBlock	vinfo;
    VBEModeInfoBlock	minfo;
    unsigned short	*modes;
    boot_vbe_mode	*rec;
    char		*vbeArea;
    int			count, i;

    if (vbeModeCount != -1)
	return vbeModeCount;

    vinfo.VESASignature[0] = 'V';
    vinfo.VESASignature[1] = 'B';
    vinfo.VESASignature[2] = 'E';
    vinfo.VESASignature[3] = '2';
    if (getVBEInfo(&vinfo) != errSuccess ||
	vinfo.VESAVersion < MIN_VESA_VERSION) {
	vbeModeCount = 0;
	return 0;
    }

    /*
     * Reference defect, reproduced: VideoModePtr is a real-mode segment and
     * offset, but it is used as (segment << 16) | offset. That is the right
     * address only when the segment is 0.
     */
    modes = (unsigned short *)ADDRESS(vinfo.VideoModePtr_low,
				      vinfo.VideoModePtr_1,
				      vinfo.VideoModePtr_2,
				      vinfo.VideoModePtr_high);
    rec = kernBootStruct->vbeModes;
    count = 0;
    for (i = 0; modes[i] != 0xFFFF; i++) {
	/*
	 * 4.2 measures each record from kernBootStruct + 0x1840, the start
	 * of the 0x898 bytes that end at `video` (0x20D8), and stops once
	 * the record no longer starts inside them (cmp eax,897h at
	 * boot+27911). That admits 90 records, and the 90th would overwrite
	 * video.v_baseAddr and v_display.
	 * Forced divergence: stop once the record would not end inside them,
	 * 0x898 - sizeof (boot_vbe_mode) = 0x880. Indices 0-88 pass, 89 does
	 * not: at most BOOT_VBE_MAX_MODES records.
	 */
	vbeArea = (char *)kernBootStruct + 0x1840;
	if ((unsigned long)((char *)rec - vbeArea) > 0x880)
	    break;
	if (getVBEModeInfo(modes[i], &minfo) == errSuccess &&
	    vbeModeIsLargeEnough(&minfo)) {
	    recordVBEMode(rec, modes[i], &minfo);
	    rec++;
	    count++;
	}
    }
    vbeModeCount = count;
    return count;
}

void
set_linear_video_mode(unsigned short mode)
{
    VBEInfoBlock	vinfo;
    VBEModeInfoBlock	minfo;
    int 		err = 0;
    VBEPalette		palette;

    /*
     * See if VESA is around
     */
    err = getVBEInfo(&vinfo);
    if ((err != errSuccess) || (vinfo.VESAVersion != MIN_VESA_VERSION))
    {
	reallyPrint("VESA not available.  Using text mode\n");
	return;
    }

    /*
     * See if this mode is supported
     */
    err = getVBEModeInfo(mode, &minfo);
    if (!((err == errSuccess) && 
         (minfo.ModeAttributes & maModeIsSupportedBit) &&
	 (minfo.ModeAttributes & maGraphicsModeBit)    &&
	 (minfo.ModeAttributes & maLinearFrameBufferAvailBit)))
    {
	reallyPrint("Mode %d not supported\n", mode);
	return;
    }

    /*
     * Set the mode
     */
    err = setVBEMode(mode | kLinearFrameBufferBit);
    if (err != errSuccess)
    {
	reallyPrint("Error in setting mode.  Error #%d\n", err);
	return;
    }

    in_linear_mode = YES;
    screen_width = minfo.XResolution;
    screen_height = minfo.YResolution;
    bits_per_pixel = minfo.BitsPerPixel;
    frame_buffer = (unsigned char *)ADDRESS(minfo.PhysBasePtr_low, 
					   minfo.PhysBasePtr_1, 
					   minfo.PhysBasePtr_2, 
					   minfo.PhysBasePtr_high);

    /*
     * Set the palette
     */
    setupPalette(&palette, appleClut8);
    if ((err = setVBEPalette(palette)) != errSuccess)
	reallyPrint("Error in setting palette.  Error #%d\n", err);
}

void setupPalette(VBEPalette *p, const unsigned char *g)
{
    int i;
    unsigned char *source = (unsigned char *)g;

    for (i = 0; i < 256; i++) {
	(*p)[i] = 0;
	(*p)[i] |= ((unsigned long)((*source++) >> 2)) << 16;	// Red
	(*p)[i] |= ((unsigned long)((*source++) >> 2)) << 8;	// Green
	(*p)[i] |= ((unsigned long)((*source++) >> 2));	// Blue
    }

}

int getVBEInfo(void *vinfo_p)
{
	
    bb.intno = 0x10;
    bb.eax.rr = funcGetControllerInfo;
    bb.es = SEG(vinfo_p);
    bb.edi.rr = OFF(vinfo_p);
    bios(&bb);
    return(bb.eax.r.h);
}


int getVBEModeInfo(int mode, void *minfo_p)
{
    bb.intno = 0x10;
    bb.eax.rr = funcGetModeInfo;
    bb.ecx.rr = mode;
    bb.es = SEG(minfo_p);
    bb.edi.rr = OFF(minfo_p);
    bios(&bb);
    return(bb.eax.r.h);
}


int getVBEDACFormat(unsigned char *format)
{
    bb.intno = 0x10;
    bb.eax.rr = funcGetSetPaletteFormat;
    bb.ebx.r.l = subfuncGet;
    bios(&bb);
    *format = bb.ebx.r.h;
    return(bb.eax.r.h);
}

int setVBEDACFormat(unsigned char format)
{
    bb.intno = 0x10;
    bb.eax.rr = funcGetSetPaletteFormat;
    bb.ebx.r.l = subfuncSet;
    bb.ebx.r.h = format;
    bios(&bb);
    return(bb.eax.r.h);
}

int setVBEMode(unsigned short mode)
{
    bb.intno = 0x10;
    bb.eax.rr = funcSetMode;
    bb.ebx.rr = mode;
    bios(&bb);
    return(bb.eax.r.h);
}

int setVBEPalette(void *palette)
{
    bb.intno = 0x10;
    bb.eax.rr = funcGetSetPaletteData;
    bb.ebx.r.l = subfuncSet;
    bb.ecx.rr = 256;
    bb.edx.rr = 0;
    bb.es = SEG(palette);
    bb.edi.rr = OFF(palette);
    bios(&bb);
    return(bb.eax.r.h);
}

int getVBEPalette(void *palette)
{
    bb.intno = 0x10;
    bb.eax.rr = funcGetSetPaletteData;
    bb.ebx.r.l = subfuncGet;
    bb.ecx.rr = 256;
    bb.edx.rr = 0;
    bb.es = SEG(palette);
    bb.edi.rr = OFF(palette);
    bios(&bb);
    return(bb.eax.r.h);
}

int getVBECurrentMode(unsigned short *mode)
{
    bb.intno = 0x10;
    bb.eax.rr = funcGetCurrentMode;
    bios(&bb);
    *mode = bb.ebx.rr;
    return(bb.eax.r.h);
}
