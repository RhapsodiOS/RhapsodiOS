/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
//#define SEQUENCE_HACK
//#define MAGIC
//#warning SEQUENCE_HACK enabled!
//#warning MAGIC enabled!

/* NeXT Audio Transform Coder.
   by Julius O. Smith
   August 6, 1991
*/

typedef unsigned char byte;

#define WRITE_FRAME 1
//#define MAX_FRAME_EXPONENT (25) /* cut-off at 50dB - 6 * MFE */
#define MAX_FRAME_EXPONENT (16)
#define FRAME_EXPONENT_SIZE 2	/* in bytes. FIXME --- 11 bits wasted here */
#define MAX_EXPONENT (15)	/* adds to frameExponent */
#define MAX_POS_INT (32767)
#define MANTISSA_SIZE (4)
#define ROUND (0)		/* rounding gives worse error! */
#define MAG_TRUNC (1)		/* theory: err must never increase spectrum */

#define INLINE_MATH		/* See /usr/include/math.h */

#define DCT dctnz_from_hfft
#define DST dstnz_from_hfft
#define IDCT idctnz_from_ihfft
#define IDST idstnz_from_ihfft

#define DEBUG2 0

#ifdef DEBUG
#define INLINE
#define REGISTER
#define PLOT(buf,size,name) \
    if (frameNumber==WRITE_FRAME) \
    	writeDATA_TYPEs(buf,size,name)
#define PLOT2(buf,size,name) \
    if (DEBUG2 && frameNumber==WRITE_FRAME) \
    	writeDATA_TYPEs(buf,size,name)
#define PLOT_INTS(buf,size,name) \
    if (frameNumber==WRITE_FRAME) \
    	writeInts(buf,size,name)
#define PLOT_HEX(buf,size,name) \
    if (frameNumber==WRITE_FRAME) \
    	writeIntsInHex(buf,size,name)
#else
#define DEBUG2 0
#ifdef PROFILE
#define INLINE
#else
#define INLINE inline
#endif
#define REGISTER register
#define PLOT(buf,size,name)
#define PLOT2(buf,size,name)
#define PLOT_INTS(buf,size,name)
#define PLOT_HEX(buf,size,name)
#endif

/* Include files */
#import <stdio.h>
#import <c.h>			/* MAX,MIN */
#import <stdlib.h>		/* malloc */
#import <math.h>
#import <string.h>		/* bcopy */

#ifndef LIBSYS_VERSION
#import <SoundKit/sound.h>
#endif

#ifndef ATC_MAGIC
#define ATC_MAGIC ((unsigned short)0x5555)
#endif  ATC_MAGIC

#define MAGIC_SIZE 0		/* all in bytes */
#define FRAME_LENGTH_SIZE 1
#define FRAME_PEAK_SIZE 1

#import <mach/mach_error.h>

/* Constants */
#define	LG2_FRAME_SIZE 9		/* good FFT size for 44kHz fs */
#define	FRAME_SIZE 512			/* good FFT size for 44kHz fs */
#define	NSPEC ((FRAME_SIZE>>1)+1) 	/* number of dct/dst points */
#define NPRESENCES ((NSPEC-1)/(8*sizeof(ushort))) /* fs/2 never present */
#define	SAMPLING_RATE 44100
#define	FRAME_STEP (FRAME_SIZE >> 1)	/* frame step size */
#define	OVERLAP_SIZE	(FRAME_SIZE-FRAME_STEP)
#define FLOOR(x) floor(x)
#define FREQ_TO_BIN(f) ((double)f * (double)FRAME_SIZE / (double)SAMPLING_RATE)
#define BIN_TO_FREQ(i) ((double)i * (double)SAMPLING_RATE / (double)FRAME_SIZE)

#import <sys/types.h>		/* for ushort */

