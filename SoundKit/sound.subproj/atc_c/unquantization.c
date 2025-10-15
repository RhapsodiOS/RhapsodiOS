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
static INLINE void unpackExponents(int *exponents, byte *bits, int n)
{
    REGISTER int i;
    REGISTER byte b;
    REGISTER int *ep = exponents;
    REGISTER byte *bp = bits;
    for (i=(n>>1); i; i--) {
	b = *bp++;
	*ep++ = (b>>4);
	*ep++ = b & 0xF;
    }
    if (n&1)
      *ep = *bp;
}

#if MANTISSA_SIZE>16
	come fix this
#endif
static int bitFieldMaskLJ[17] = {0,0x8000, /* 16 bit for DSP's sake */
				  0xC000, 
				  0xE000, 
				  0xF000, 
				  0xF800, 
				  0xFC00, 
				  0xFE00, 
				  0xFF00,
				  0xFF80,
				  0xFFC0,
				  0xFFE0,
				  0xFFF0,
				  0xFFF8,
				  0xFFFC,
				  0xFFFE,
				  0xFFFF};

#if 0
static INLINE byte *unpackFixedMantissas(int *mantissas, 
				   byte *bits, 
				   ushort *presenceBits, 
				   int *mantissaSizes, int nspec)
{
    REGISTER unsigned int i,j,mantissa;
    REGISTER unsigned int *mp = (unsigned int *)mantissas;
    REGISTER unsigned short *bp = (unsigned short *) bits; /* short for DSP */
    REGISTER unsigned short bitWord=0; /* short for DSP */
    static int mpw = (16/MANTISSA_SIZE);

#ifdef DEBUG
    if (MANTISSA_SIZE != 4) {
	fprintf(stderr,"unpackFixedMantissas: Designed for 4-bit mantissas\n");
	exit(1);
    }
#endif

    bitWord = *bp++;		/* word of packed mantissas */
    j = 1;			/* mantissa number within word */
    mantissa = bitWord & 0xF000; /* first mantissa *** 4 BIT MANT. ONLY *** */
    for (i=0;i<nspec-1;i++) {
	if (!present(i,presenceBits)) {
	    *mp++ = 0;
	} else {
	    *mp++ = mantissa << 16;
	    if (j==mpw) {
		bitWord = *bp++; /* next word of packed mantissas */
		j=1;
	    } else {
		bitWord <<= MANTISSA_SIZE;
		j += 1;
	    }		
	    mantissa = bitWord & 0xF000; /* next mantissa */
	}
    }
    *mp++ = 0;			/* fs/2 */
    if (j>1)
      bp++;			/* short aligned */
    return (byte *)bp;
}
#endif 0


static INLINE byte *unpackMantissas(int *mantissas, 
				   byte *bits, 
				   ushort *presenceBits, 
				   int *mantissaSizes, int nspec)
/*
 * This routine is known to work for fixed 4-bit mantissas.
 * The explicit 4-bit fixed version above was added later as
 * an optimization for 3.1 (12/12/92/jos).
 */
{
    REGISTER unsigned int i,leftBitPtr,rightBitPtr=0;
    REGISTER unsigned int *mp = (unsigned int *)mantissas;
    REGISTER int *msp = mantissaSizes;
    REGISTER int ms;
    REGISTER unsigned short *bp = (unsigned short *) bits; /* short for DSP */
    REGISTER unsigned short bitWord=0; /* short for DSP */
    byte *fbp;

    bitWord = *bp++; /* word of packed mantissas */
    for (i=0;i<nspec-1;i++) {
	ms = *msp++;		/* mantissa size */
	if (!present(i,presenceBits)) {
	    *mp++ = 0;
	} else {
	    leftBitPtr = rightBitPtr;
	    rightBitPtr += ms;
	    if (rightBitPtr > 16) {
		leftBitPtr = 0;
		rightBitPtr = ms;
		bitWord = *bp++; /* word of packed mantissas */
	    }
	    *mp++ = ((bitWord << leftBitPtr) & bitFieldMaskLJ[ms])
	      << (32-16); /* 16 for DSP's sake */
	}
    }
    *mp++ = 0;			/* fs/2 */
    bp--;
    fbp = (((byte *)bp) + (((rightBitPtr+15) >> 4) << 1));
    return fbp;
}



