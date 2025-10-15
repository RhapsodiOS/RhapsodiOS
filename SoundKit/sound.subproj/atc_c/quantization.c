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
#import "atc.h"
/*
 * ----------------------------- Quantization --------------------------------
 */

static INLINE void quantizeExponents(int *exponents, int n)
{
    REGISTER int i;
    REGISTER int *ep = exponents;
    for (i=n; i; i--) {
	if (*ep++ > MAX_EXPONENT)
	  *(ep-1) = MAX_EXPONENT;		/* maximum right-shift */
    }
}

static INLINE int zeroMantissasInQuietBins(int *bins,int n, int thresh)
{
    int i,v; 
    int z = 1;
    for (i=0; i<n; i++) {
	v = abs(bins[i]);
	if ( v<thresh )
	  bins[i]=0;
	else
	  z = 0;
    }
    return z;			/* nonzero if all bins are zero */
}


#ifndef LIBSYS_VERSION
static INLINE void zeroMantissasInQuietBands(int *mantissas,
					     int frameExponent,
					     int *exponents, int n)
{
    int i; 
    int max_frame_exponent = MAX_FRAME_EXPONENT - exponentShift;
    for (i=0; i<n; i++) {
	if ( (cbLo[i]+cbWidth[i]) > binWidth ) {
	    REGISTER int j;
	    REGISTER int j2 = cbLo[i]+cbWidth[i];
	    REGISTER int *mp = &(mantissas[cbLo[i]]);
#if DEBUG2
	    fprintf(stderr,"Clearing rejected bins in band %d in frame %d\n",
		    i,frameNumber);
#endif
	    for (j=cbLo[i]; j<j2; j++, mp++)
	      if (j > binWidth)
		*mp = 0;
	} else if ( (cbLo[i]) < lowBin ) {
	    REGISTER int j;
	    REGISTER int j2 = cbLo[i]+cbWidth[i];
	    REGISTER int *mp = &(mantissas[cbLo[i]]);
#if DEBUG2
	    fprintf(stderr,"Clearing highpassed bins in band %d in frame %d\n",
		    i,frameNumber);
#endif
	    for (j=cbLo[i]; j<j2; j++, mp++)
	      if (j < lowBin)
		*mp = 0;
	}

	if (frameExponent + exponents[i] < max_frame_exponent-4)
	  continue;
	else if (frameExponent + exponents[i] >= max_frame_exponent) {
	    REGISTER int j;
	    REGISTER int *mp = &(mantissas[cbLo[i]]);
#if 0
	    fprintf(stderr,"Clearing inaudible band %d in frame %d\n",
		    i,frameNumber);
#endif
	    for (j=cbWidth[i]; j; j--)
	      *mp++ = 0;
	} else if (frameExponent + exponents[i] == max_frame_exponent-1) {
	    REGISTER int j,m;
	    REGISTER int *mp = &(mantissas[cbLo[i]]);
	    for (j=cbWidth[i]; j; j--)
	      if (((m= (*mp++ & 0xC0000000)) == 0) || (m == 0xC0000000)) {
#if 0
		  fprintf(stderr,"Clearing inaudible line 0x%X at frameExponent "
			  "%d, band exp %d in frame %d\n",
			  *(mp-1),frameExponent, exponents[i], frameNumber);
#endif
		  *(mp-1) = 0;
	      }
	} else if (frameExponent + exponents[i] == max_frame_exponent-2) {
	    REGISTER int j,m;
	    REGISTER int *mp = &(mantissas[cbLo[i]]);
	    for (j=cbWidth[i]; j; j--)
	      if (((m= (*mp++ & 0xE0000000)) == 0) || (m == 0xE0000000)) {
#if 0
		  fprintf(stderr,"Clearing inaudible line 0x%X at frameExponent "
			  "%d, band exp %d in frame %d\n",
			  *(mp-1),frameExponent, exponents[i], frameNumber);
#endif
		  *(mp-1) = 0;
	      }
	}
    }
}
#endif

static INLINE void packExponents(byte *bits, int *exponents, int n)
{
    REGISTER int i,e;
    REGISTER int *ep = exponents;
    REGISTER byte *bp = bits;
    for (i=(n>>1); i; i--) {
	e = *ep++;
	*bp++ = (e<<4) | *ep++;
    }
    if (n&1)
      *bp = *ep;
}

static INLINE int quant4(int x)
{
#if ROUND
    register unsigned int xu = ((unsigned int)x);
    register unsigned int qx = xu & 0xF0000000;
    if (xu & 0x08000000 && qx != 0xF0000000)
      qx += 0x10000000;
    return (int)qx;
#else
#if MAG_TRUNC
    register unsigned int xu = ((unsigned int)x);
    register unsigned int qx = xu & 0xF0000000;
    if ((xu & 0x88000000) == 0x88000000) /* negative and err <= -0.5 LSB */
      qx += 0x10000000;		/* Note that 0xF0...0 wraps to 0 */
    return (int)qx;
#else
    return x & 0xF0000000;	/* plain truncation */
#endif
#endif
}


static INLINE void quantizeMantissas(int *mantissas, int *mantissaSizes, int n)
{
    REGISTER int m,*mp=mantissas,*ep=mp+n;
    while (mp != ep) {
	m = *mp;
#if MANTISSA_SIZE==4
	*mp++ = quant4(m);
#else
	come fix this
#endif
    }
}

static INLINE int packMantissas(unsigned int *bits, 
				ushort *presenceBits, 
				int *mantissas, 
				int *mantissaSizes, int nspec)
/* returns number of bytes occupied by mantissas */
{
    REGISTER unsigned int rightBitPtr=0,leftBitPtr;
    REGISTER unsigned short bitWord=0, m=0; /* short for DSP's sake */
    REGISTER int i;
    REGISTER int *mp = mantissas;
    REGISTER int *msp = mantissaSizes;
    REGISTER int ms;
    REGISTER int nm = 0;
    REGISTER unsigned short *bp = (unsigned short *)bits; /* for DSP's sake */

    for (i=NPRESENCES-1; i>=0; i--) /* no fs/2 */
      presenceBits[i] = 0xFFFF;	/* all present to start */
    for (i=0; i<nspec-1; i++) {
	ms = *msp++;		/* mantissa size */
	m = (*mp++ >> (32-16));	/* mantissa -- 16 for DSP's sake */
	if (m == 0 || ms == 0) { /* ms is never zero? */
	    notPresent(i,presenceBits);
	    continue;
	}
	nm += ms;		/* number of bits in all mantissas so far */
	leftBitPtr = rightBitPtr;
	rightBitPtr += ms;	/* bit 0 is considered the MSB here */
	if (rightBitPtr > 16) {	/* 16 not 32 for DSP's sake (24 ok on Turbo) */
	    leftBitPtr = 0;
	    rightBitPtr = ms;
	    *bp++ = bitWord;	/* ship it */
	    bitWord = 0;
	}
	bitWord |= (m >> leftBitPtr);
    }
    *bp++ = bitWord;	/* ship partially packed word */
    return ((nm+7) >> 3);
}



