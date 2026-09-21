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

/* 	Copyright (c) 1992 NeXT Computer, Inc.  All rights reserved. 
 *
 * FBConsole.h - FrameBuffer based console implementation definitions
 *
 *
 * HISTORY
 * 01 Sep 92	Joe Pasqua
 *      Created. 
 */

// Notes:
// * This module is the interface to a console implementation that writes
//   to a raw frame buffer. If you have such a device, you can use this
//   code to help implement your console support.
// * Currently we support 16 and 32 bpp displays.

#ifdef	DRIVER_PRIVATE

#import	<mach/boolean.h>
#import <driverkit/displayDefs.h>
#import	<bsd/dev/i386/ConsoleSupport.h>

/*
 * One VBE mode as the booter hands it over in KERNBOOTSTRUCT.  22 bytes of
 * fields, 24 with the two bytes of alignment padding at 0x12 that the
 * trailing pointer forces.  The layout is the 4.2 VBE20DisplayDriver's,
 * confirmed a second time by the field offsets VBEModeInfo2IODisplayInfo
 * itself reads (0x0019ED8C in the i386 slice of the OPENSTEP 4.2 kernel).
 */
typedef struct {
    unsigned short	modeNumber;		/* 0x00 */
    unsigned short	modeAttributes;		/* 0x02 */
    unsigned short	xResolution;		/* 0x04 */
    unsigned short	yResolution;		/* 0x06 */
    unsigned short	bytesPerScanline;	/* 0x08 */
    unsigned char	bitsPerPixel;		/* 0x0A */
    unsigned char	memoryModel;		/* 0x0B */
    unsigned char	redMaskSize;		/* 0x0C */
    unsigned char	redFieldPosition;	/* 0x0D */
    unsigned char	greenMaskSize;		/* 0x0E */
    unsigned char	greenFieldPosition;	/* 0x0F */
    unsigned char	blueMaskSize;		/* 0x10 */
    unsigned char	blueFieldPosition;	/* 0x11 */
    void		*frameBuffer;		/* 0x14 */
} VBEModeRec;

extern IOConsoleInfo *FBAllocateConsole(IODisplayInfo *display);
extern void VBEModeInfo2IODisplayInfo(VBEModeRec *mode, IODisplayInfo *info);

#endif	/* DRIVER_PRIVATE */
