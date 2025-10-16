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
/*
 * -------------------------- Global Frame State -----------------------------
 */

#import "hfft.h"		/* dspkit */

#ifndef LIBSYS_VERSION
static int 	numFrames;
static int	soundError;	/* used by soundErrorExit() macro */
static int	machError;	/* used by machErrorExit() macro */
static char	*programName;
#endif

static int frameNumber = 1;

static int inited = 0;
static int nMantissas;
static byte exponentsP[NSPEC];
static unsigned int mantissasP[NSPEC]; /* odd sizes, 0s squeezed out */
static int frameExponent;	/* overall normalization (right-shift) */
static int ispec[NSPEC];
static int exponents[NSPEC];
static int mantissaSizes[NSPEC];
static ushort presencesP[NPRESENCES];

#define MANTISSAS_FIXED
static INLINE void createMantissaSizes(int *mantissaSizes, int n)
/* 
 * FIXME: Mantissa sizes should be variable.  Need 7-8 bits for an
 * isolated sinusoidal peak.  Need fewer bits at high frequencies.
 * Need more bits in loudest critical bands.
 */
{
    int i;
    for (i=0; i<n; i++)
      mantissaSizes[i] = MANTISSA_SIZE;
}

static void initializeATD(void)
{
    createMantissaSizes(mantissaSizes,NSPEC);
}

static INLINE int present(int bitNum, ushort *presenceBits)
{
    REGISTER int word = (bitNum >> 4);
    REGISTER int bitInWord = bitNum - (word << 4); /* 0 to 15 */
    return presenceBits[word] & (1 << bitInWord);
}

static INLINE void notPresent(int bitNum, ushort *presenceBits)
{
    REGISTER int word = (bitNum >> 4);
    REGISTER int bitInWord = bitNum - (word << 4); /* 0 to 15 */
    presenceBits[word] &= ~(1 << bitInWord);
}

#ifndef LIBSYS_VERSION
static INLINE int presenceCount(ushort *presenceBits)
{
    REGISTER int i,k;
    for (i=0,k=0; i<NSPEC; i++)
      if (present(i,presenceBits))
	k++;
    return k;
}
#endif LIBSYS_VERSION

#if 0
static INLINE int floorMagnitude(double x)
{
    return ((x>0)? floor(x) : -floor(-(x)));
}
#endif
