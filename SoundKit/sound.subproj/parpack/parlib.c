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
/* parlib.c

   Parallel stream compression for NeXT stereo sound files.
   R. E. Crandall, Educational Technology Center
   c. 1989 NeXT, Inc.
   
   The main routines are:
   
   int parpack(FILE *outfile, SNDSoundStruct *inSound, int bitFaithful)
   int unparpack(FILE *infile, SNDSoundStruct **inSound)
  
   parpack takes an existing sound and writes it to disk in compressed format.
   It leaves a soundfile header with user format code
   SND_FORMAT_COMPRESSESED (18).  The sound starts with a subheader typdef'ed
   as SNDCompressionStruct below.
	
   The original sound must be in 16-bit linear format (SND_FORMAT_LINEAR_16),
   and can be any number of channels.
   
   parpack always right-shifts each sample by 'dropBits' before compressing.  The
   dropped bits are saved in the soundfile for use by unparpack if the
   bitFaithful argument is non-zero. 'dropBits' can be set by calling parDropBits().
   
   Verbose mode can be set by calling parVerbose().  Verbose mode prints parallel
   packing algorithm statistics.
   
   NOTE: S/N ratios for the number of dropped bits are:
         0: whatever the recording device does, > 90 db usuaslly
	 1: 90 db
	 2: 84 db
	 3: 78 db
	 4: 72 db
	 5: 66 db
	 6: 60 db
	 
   unparpack reads a soundfile in compressed form and allocates and initializes
   a new sound in 16-bit linear format (SND_FORMAT_LINEAR_16).
   
   unparpack needs no algorithm argument, since it gets this from
   the packed file itself.
   
   Both routines return -1 on error, 0 otherwise.
   
   Modification History
   	12/30/89/mtm		Interface changes and (some) code beautification.
	02/05/90/mtm		Save dropped bits in soundfile for bit-faithful.
				Removed overflow check.
	02/12/90/mtm/rec	Speed optimization pass
	02/16/90/mtm		Changed header and subheader
	03/09/90/mtm		Respect dataLocation of original sound
	03/14/90/mtm		Make code a short and pad packed buffer to nearest
				short for compatibility with DSP input in word mode.
	08/01/90/mtm		Tack residue bits to sample instead of separate buffer.
	11/26/90/mtm	Fix  bit-faithful NULL_ENCODE bug and xor score bug.
	12/03/90/mtm	Clear pad byte when compressing.
*/

#ifdef DEBUG
#import <stdio.h>
#endif DEBUG
#import <math.h>
#import <string.h>
#import <architecture/byte_order.h>

#import "../sound.h"
#import "../_compression.h"
						
// Add sign bit if negative
#define	SET_SIGN(n,s)	((n) < 0 ? (-(n)) | (s) : (n))

/* For use in bit-streaming. */
static short shortmask1[16], shortmask0[16];
static unsigned char bytemask0[8], bytemask1[8];

static int bestEncodeLength[] = {
    64,		// shift 0 - currently not used
    64,		// shift 1 - currently not used
    128,	// shift 2 - currently not used
    128,	// shift 3 - currently not used
    256,	// shift 4
    256,	// shift 5
    512,	// shift 6
    512,	// shift 7
    512		// shift 8
};
#define LEADER 		32      // Allowed tokens in encode packets
#define MAX_ENCODE_LEN 	2048+LEADER  // Must be >= highest bestEncodeLength[] value

#define	MINBITS		4	// Must drop at least 4 bits to avoid overflow check
#define	MAXBITS		8	// Must be <= highest bestEncodeLength[] index
#define	DROPMASK	(~((~0)<<dropBits))
#define	NUMDROPMASK	(~((~0)<<numDropped))

// Ugly but fast macro to return the right-justified bit-width of a short; e.g
// a = 0000001001 returns 4.
// Looping code would look something like this:
//    b = 1<<15;
//    for(k=0;k<16;k++) {
//	if(a&b)
//	    break;
//	b >>= 1;
//    }
//    return(16-k);
#define	numlow(a)	(a&(1<<15) ? 16 :		\
			 (a&(1<<14) ? 15 :		\
			  (a&(1<<13) ? 14 :		\
			   (a&(1<<12) ? 13 :		\
			    (a&(1<<11) ? 12 :		\
			     (a&(1<<10) ? 11 :		\
			      (a&(1<<9) ? 10 :		\
			       (a&(1<<8) ? 9 :		\
			        (a&(1<<7) ? 8 :		\
			         (a&(1<<6) ? 7 :	\
			          (a&(1<<5) ? 6 :	\
			           (a&(1<<4) ? 5 :	\
			            (a&(1<<3) ? 4 :	\
			             (a&(1<<2) ? 3 :	\
			              (a&(1<<1) ? 2  :	\
			               (a&1     ? 1  :	\
				        0))))))))))))))))
			       
static unsigned dropBits = MINBITS;	// Set by parDropBits()
static int verbose = FALSE;	        // Set by parVerbose()
    
static int masksSet = 0;

static void setmasks(void)
/* For use in bit-streaming. */
{	
    int j;
	    
    if (!masksSet) {
	for(j=0;j<16;j++) {
	    shortmask1[j] = 32768>>j;
	    shortmask0[j] = ~shortmask1[j];
	}
	for(j=0;j<8;j++) { 
	    bytemask1[j] = 128>>j;
	    bytemask0[j] = ~bytemask1[j];
	}
	masksSet = 1;
    }
}

static void setMaxShortBits(register int *numBits, register int n)
//  Sets the maximum number of bits needed to code n
{
    register int lowBits;
    
    /*
     * Old overflow check was:
     *    if (n > 32767)
     *        *numBits = 16;
     *	  else {code below}
     */
     
    lowBits = 1 + numlow(n);	// need 1 for the sign bit
    if (lowBits > *numBits)
	*numBits = lowBits;
}

static int crunch(unsigned char *bdat, short *sdat, int num, int numBits)
//  Extracts numBits from each short in sdat and crunches them together into bdat
{
    register short *mdat;
    register unsigned char *ndat;
    register int bcount = 0;
    register int j, bphase = -1, sphase = -1;
    register short *s1;
    int off = 16-numBits, tot = num*numBits;
	
    mdat = sdat;
    ndat = bdat;
    s1 = shortmask1 + off;
    if(!numBits) return(0);
    for(j=0;j<tot;j++) {
	if(++bphase>=8) {
	    bphase=0;
	    ++bcount;
	    ++ndat;
	}
	if(++sphase>=numBits) {
	    sphase=0;
	    ++mdat;
        }
	if((*mdat) & s1[sphase])
	    *ndat |= bytemask1[bphase];
	else
	    *ndat &= bytemask0[bphase];
    }
    for(j=bphase+1;j<8;j++)
        *ndat &= bytemask0[j]; 
    return(1+bcount);
}

static void uncrunch(short *sdat, unsigned char *bdat, int num, int numBits)
//  Extracts numBits at a time from bdat and expands them into sdat
{
    register short *mdat;
    register unsigned char *ndat;
    register int j, sphase = -1, bphase = -1;
    register short *s1, *s0;
    int off = 16-numBits, tot = num*numBits;
	
    mdat = sdat;
    ndat = bdat;
    s1 = shortmask1 + off;
    s0 = shortmask0 + off;
    bzero((char *)sdat, num*sizeof(short));
    if (!numBits)
        return;
	
    for (j=0;j<tot;j++) {
	if (++bphase>=8) {
            bphase=0;
	    ++ndat;
        }
	if (++sphase>=numBits) {
	   sphase=0;
	   ++mdat;
        }
	if ((*ndat) & bytemask1[bphase])
	    *mdat |= s1[sphase];
	else
	    *mdat &= s0[sphase];
    }
}

static int packtry(register short *dat, int num, int bitFaithful, int *numBits)
/* Pass through the micro-algorithms, returning the winner. */
{
	register int a, b, e, f, g=0, h=0, i=0, j;
	int least=16;
	int winningCode = 0;
	int max[NUM_ENCODES];	// max[NULL_ENCODE] not used
	    
	for (j = XOR_ENCODE; j < NUM_ENCODES; j++)
	  	max[j] = 0;
		
	for(j=0;j<num-1;j++) {	
		e = dat[j];
		f = dat[j+1];
		/* Commence XOR encoding */
		if(max[XOR_ENCODE] < 16) {
			a = e^f;
			b = numlow(a & ~((~0)<<(16-dropBits)));
			// no sign bit needed
			if(b>max[XOR_ENCODE]) max[XOR_ENCODE] = b;
		}
		/* Commence D1 encoding */
		if(max[D1_ENCODE] < 16) { 
			a = abs(e-f);
			setMaxShortBits(&max[D1_ENCODE], a);
		}
		/* Commence D2 encoding */
		if(j<num-2) {
		    g = dat[j+2];
		    if(max[D2_ENCODE] < 16) { 
		        a = abs(e - (f<<1) + g);
			setMaxShortBits(&max[D2_ENCODE], a);
		    }
		}
		/* Commence D3 encoding */
		if(j<num-3) {
		    h = dat[j+3];
		    if(max[D3_ENCODE] < 16) { 
			a = abs(e - f - f - f + g + g + g - h);
			setMaxShortBits(&max[D3_ENCODE], a);
		    }
		}
		/* Commence D4 encoding */
		if(j<num-4) {
		    i = dat[j+4];
		    if(max[D4_ENCODE] < 16) { 
			a = abs(e - (f<<2) + (g<<1) + (g<<2) - (h<<2)+ i);
			setMaxShortBits(&max[D4_ENCODE], a);
		    }
		 }
		/* Commence D3_11 encoding */
		if(j<num-3) {
		   if(max[D3_11_ENCODE] < 16) { 
			a = abs(e- f + g -h);
			setMaxShortBits(&max[D3_11_ENCODE], a);
		    }
		}
		/* Commence D3_22 encoding */
		if(j<num-3) {
		   if(max[D3_22_ENCODE] < 16) { 
			a = abs(e - f - f +g + g - h);
			setMaxShortBits(&max[D3_22_ENCODE], a);
		    }
		}
		/* Commence D4_222 encoding */
		if(j<num-4) {
		   if(max[D4_222_ENCODE] < 16) { 
			a = abs(e - (f<<1) +(g<<1) - (h<<1) + i);
			setMaxShortBits(&max[D4_222_ENCODE], a);
		    }
		}
		/* Commence D4_343 encoding */
		if(j<num-4) {
		   if(max[D4_343_ENCODE] < 16) { 
			a = abs(e - f - (f<<1) +(g<<2) - h - (h<<1) + i);
			setMaxShortBits(&max[D4_343_ENCODE], a);
		    }
		}
		/* Commence D4_101 encoding */
		if(j<num-4) {
		   if(max[D4_101_ENCODE] < 16) { 
			a = abs(e - f - h + i);
			setMaxShortBits(&max[D4_101_ENCODE], a);
		    }
		}
	}
	
	for (j = XOR_ENCODE; j < NUM_ENCODES; j++) {
	    if (max[j] < least) {
	        winningCode = j;
		least = max[j];
	    }
	}

	if (bitFaithful)
	    least += dropBits;
	if (least >= 16) {
	    least = 16;
	    winningCode = 0;
	}

	// Note: null encode implies no unpacking, so numBits must
	// be 16 (rather than 16-MINBITS).  If MINBITS > 0, null encode is useful
	// only for debugging.
	
	*numBits = least;
	return(winningCode);
}	

static int packchannel(register unsigned char *buf, register short *dat,
		       int num, int code, int numBits, int bitFaithful, short *residue)
//  Packs num elements from dat into buf, coding each element with numBits
{
	int sign = 1;
	register int j, n=0, a, k=0;
	int numCrunch = 0;
	short *sbuf;
	int realNumBits = numBits;
	
	if (bitFaithful)
	    realNumBits -= dropBits;
	if(realNumBits > 0 )
	    sign = 1<<(realNumBits-1);

	buf[n++] = code;
	buf[n++] = numBits;
	sbuf = (short *)&buf[n];
	switch(code) {
		case NULL_ENCODE:
	                for(j=0;j<num;j++) {
			    sbuf[j] = dat[j];
			    if (bitFaithful)
			        sbuf[j] = (sbuf[j] << dropBits) | residue[k++];
			}
			n += num*2;
			break;
		case XOR_ENCODE:
			sbuf[0] = dat[0];
			n += 2;
			if (bitFaithful)
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			for(j=0;j<num-1;j++)
				dat[j] ^= dat[j+1];
			numCrunch = num - 1;
			break;
		case D1_ENCODE:
			sbuf[0] = dat[0];
			n += 2;
			if (bitFaithful)
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			for(j=0;j<num-1;j++) {
				a = dat[j]-dat[j+1];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 1;
			break;
		case D2_ENCODE:
			sbuf[0] = dat[0];
			sbuf[1] = dat[1];
			n += 4;
			if (bitFaithful) {
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			    sbuf[1] = (sbuf[1] << dropBits) | residue[k++];
			}
			for(j=0;j<num-2;j++) {
				a = dat[j] - 2*dat[j+1] + dat[j+2];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 2;
			break;
		case D3_ENCODE:
			sbuf[0] = dat[0];
			sbuf[1] = dat[1];
			sbuf[2] = dat[2];
			n += 6;
			if (bitFaithful) {
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			    sbuf[1] = (sbuf[1] << dropBits) | residue[k++];
			    sbuf[2] = (sbuf[2] << dropBits) | residue[k++];
			}
			for(j=0;j<num-3;j++) {
				a = dat[j] - 3*dat[j+1] + 3*dat[j+2] - dat[j+3];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 3;
			break;
		case D4_ENCODE:
			sbuf[0] = dat[0];
			sbuf[1] = dat[1];
			sbuf[2] = dat[2];
			sbuf[3] = dat[3];
			n += 8;
			if (bitFaithful) {
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			    sbuf[1] = (sbuf[1] << dropBits) | residue[k++];
			    sbuf[2] = (sbuf[2] << dropBits) | residue[k++];
			    sbuf[3] = (sbuf[3] << dropBits) | residue[k++];
			}
			for(j=0;j<num-4;j++) {
				a = dat[j] - 4*dat[j+1] + 6*dat[j+2]
					- 4*dat[j+3] + dat[j+4];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 4;
			break;
		case D3_11_ENCODE:
			sbuf[0] = dat[0];
			sbuf[1] = dat[1];
			sbuf[2] = dat[2];
			n += 6;
			if (bitFaithful) {
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			    sbuf[1] = (sbuf[1] << dropBits) | residue[k++];
			    sbuf[2] = (sbuf[2] << dropBits) | residue[k++];
			}
			for(j=0;j<num-3;j++) {
				a = dat[j] - dat[j+1] + dat[j+2] - dat[j+3];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 3;
			break;
		case D3_22_ENCODE:
			sbuf[0] = dat[0];
			sbuf[1] = dat[1];
			sbuf[2] = dat[2];
			n += 6;
			if (bitFaithful) {
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			    sbuf[1] = (sbuf[1] << dropBits) | residue[k++];
			    sbuf[2] = (sbuf[2] << dropBits) | residue[k++];
			}
			for(j=0;j<num-3;j++) {
				a = dat[j] - 2*dat[j+1] + 2*dat[j+2] - dat[j+3];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 3;
			break;
		case D4_222_ENCODE:
			sbuf[0] = dat[0];
			sbuf[1] = dat[1];
			sbuf[2] = dat[2];
			sbuf[3] = dat[3];
			n += 8;
			if (bitFaithful) {
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			    sbuf[1] = (sbuf[1] << dropBits) | residue[k++];
			    sbuf[2] = (sbuf[2] << dropBits) | residue[k++];
			    sbuf[3] = (sbuf[3] << dropBits) | residue[k++];
			}
			for(j=0;j<num-4;j++) {
				a = dat[j] - 2*dat[j+1] + 2*dat[j+2]
					- 2*dat[j+3] + dat[j+4];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 4;
			break;
		case D4_343_ENCODE:
			sbuf[0] = dat[0];
			sbuf[1] = dat[1];
			sbuf[2] = dat[2];
			sbuf[3] = dat[3];
			n += 8;
			if (bitFaithful) {
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			    sbuf[1] = (sbuf[1] << dropBits) | residue[k++];
			    sbuf[2] = (sbuf[2] << dropBits) | residue[k++];
			    sbuf[3] = (sbuf[3] << dropBits) | residue[k++];
			}
			for(j=0;j<num-4;j++) {
				a = dat[j] - 3*dat[j+1] + 4*dat[j+2]
					- 3*dat[j+3] + dat[j+4];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 4;
			break;
		case D4_101_ENCODE:
			sbuf[0] = dat[0];
			sbuf[1] = dat[1];
			sbuf[2] = dat[2];
			sbuf[3] = dat[3];
			n += 8;
			if (bitFaithful) {
			    sbuf[0] = (sbuf[0] << dropBits) | residue[k++];
			    sbuf[1] = (sbuf[1] << dropBits) | residue[k++];
			    sbuf[2] = (sbuf[2] << dropBits) | residue[k++];
			    sbuf[3] = (sbuf[3] << dropBits) | residue[k++];
			}
			for(j=0;j<num-4;j++) {
				a = dat[j] - dat[j+1] - dat[j+3] + dat[j+4];
				dat[j] = SET_SIGN(a, sign);
			}
			numCrunch = num - 4;
			break;
		default:
			break;
	}
	if (code != NULL_ENCODE) {
	    /* Tack on residue bits */
	    if (bitFaithful)
		for (j=0; j < numCrunch; j++)
		    dat[j] = (dat[j] << dropBits) | residue[k++];
	    n += crunch(buf+n, dat, numCrunch, numBits);
	}
	return(n);
}	
		   		
static void unpackchannel(register short *dat, register unsigned char *buf,
			  int num, int code, int numBits, int bitFaithful,
			  short *residue, int numDropped)
//  Unpacks num elements from buf into dat, decoding from numBits
{	
	register int j,a;
	register sign = 1, csign;
	int realNumBits = numBits;

	if (bitFaithful)
	    realNumBits -= numDropped;
	if(realNumBits > 0)
	    sign = 1<<(realNumBits-1);
	csign = ~sign;

	switch(code) {
		case NULL_ENCODE:
			for(j=0;j<num;j++) {
			    dat[j] = buf[2*j];
			    dat[j] = (dat[j]<<8) | buf[2*j+1];
			}
			/* this is a nop because unparpack() tacks the
			    same residue back on */
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			break;
		case XOR_ENCODE:
			dat[0] = buf[0]; 
			dat[0] = (dat[0]<<8) | buf[1];
			uncrunch(dat+1, buf+2, num-1, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=1;j<num;j++)
				dat[j] ^= dat[j-1];
			break;
		case D1_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			uncrunch(dat+1, buf+2, num-1, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=1;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a & csign);
				dat[j] = dat[j-1] - a;
			    }
			break; 
		case D2_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			dat[1] = buf[2];
			dat[1] = (dat[1]<<8) | buf[3];
			uncrunch(dat+2, buf+4, num-2, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=2;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a&csign);
				dat[j] = a + 2*dat[j-1]-dat[j-2];
			}
			break;
		case D3_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			dat[1] = buf[2];
			dat[1] = (dat[1]<<8) | buf[3];
			dat[2] = buf[4];
			dat[2] = (dat[2]<<8) | buf[5];
			uncrunch(dat+3, buf+6, num-3, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=3;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a&csign);
				dat[j] = -a + 3*dat[j-1]-3*dat[j-2]+dat[j-3];
			}
			break;
		case D4_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			dat[1] = buf[2];
			dat[1] = (dat[1]<<8) | buf[3];
			dat[2] = buf[4];
			dat[2] = (dat[2]<<8) | buf[5];
			dat[3] = buf[6];
			dat[3] = (dat[3]<<8) | buf[7];
			uncrunch(dat+4, buf+8, num-4, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=4;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a&csign);
				dat[j] = a + 4*dat[j-1]-6*dat[j-2]+4*dat[j-3]
						- dat[j-4];
			}
			break;
		case D3_11_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			dat[1] = buf[2];
			dat[1] = (dat[1]<<8) | buf[3];
			dat[2] = buf[4];
			dat[2] = (dat[2]<<8) | buf[5];
			uncrunch(dat+3, buf+6, num-3, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=3;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a&csign);
				dat[j] = -a + dat[j-1]-dat[j-2]+dat[j-3];
			}
			break;
		case D3_22_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			dat[1] = buf[2];
			dat[1] = (dat[1]<<8) | buf[3];
			dat[2] = buf[4];
			dat[2] = (dat[2]<<8) | buf[5];
			uncrunch(dat+3, buf+6, num-3, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=3;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a&csign);
				dat[j] = -a + 2*dat[j-1]-2*dat[j-2]+dat[j-3];
			}
			break;
		case D4_222_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			dat[1] = buf[2];
			dat[1] = (dat[1]<<8) | buf[3];
			dat[2] = buf[4];
			dat[2] = (dat[2]<<8) | buf[5];
			dat[3] = buf[6];
			dat[3] = (dat[3]<<8) | buf[7];
			uncrunch(dat+4, buf+8, num-4, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=4;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a&csign);
				dat[j] = a + 2*dat[j-1]-2*dat[j-2]+2*dat[j-3]
						- dat[j-4];
			}
			break;
		case D4_343_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			dat[1] = buf[2];
			dat[1] = (dat[1]<<8) | buf[3];
			dat[2] = buf[4];
			dat[2] = (dat[2]<<8) | buf[5];
			dat[3] = buf[6];
			dat[3] = (dat[3]<<8) | buf[7];
			uncrunch(dat+4, buf+8, num-4, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=4;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a&csign);
				dat[j] = a + 3*dat[j-1]-4*dat[j-2]+3*dat[j-3]
						- dat[j-4];
			}
			break;
		case D4_101_ENCODE:
			dat[0] = buf[0];
			dat[0] = (dat[0]<<8) | buf[1];
			dat[1] = buf[2];
			dat[1] = (dat[1]<<8) | buf[3];
			dat[2] = buf[4];
			dat[2] = (dat[2]<<8) | buf[5];
			dat[3] = buf[6];
			dat[3] = (dat[3]<<8) | buf[7];
			uncrunch(dat+4, buf+8, num-4, numBits);
			if (bitFaithful)
			    for (j = 0; j < num; j++) {
				residue[j] = dat[j] & NUMDROPMASK;
				dat[j] = dat[j] >> numDropped;
			    }
			for(j=4;j<num;j++) {
				a = dat[j];
				if(sign & a) a = -(a&csign);
				dat[j] = a + dat[j-1] + dat[j-3] - dat[j-4];
			}
			break;
	
	}
}	

// Exported functions

#ifdef DEBUG
int parVerbose(int trueOrFalse)
//  Returns the old value
{
    int oldValue = verbose;
    verbose = trueOrFalse;
    return oldValue;
}
#endif

#ifdef LIBSYS_VERSION
static
#endif
unsigned parDropBits(unsigned numBits)
//  Returns the value actually assigned
{
    dropBits = numBits;
    if (dropBits < MINBITS)
        dropBits = MINBITS;
    else if (dropBits > MAXBITS)
        dropBits = MAXBITS;
    return dropBits;
}

#if 0
static INLINE void ba_write(void *cp, int sz, byte **ba)
/* copy sz bytes from cp to byte array ba, advancing pointer *ba */ 
{
    int i;
    byte *bp = *ba;
    for (i=sz; i; i--)
      *bp++ = *((byte *)cp)++;
    *ba = bp;
}
#endif

static int parpack_to_byte_array(byte **outPtrP, short *inPtr, 
				 SNDSoundStruct *inSound, 
				 int numShorts, int dropBits,
				 int bitFaithful)
//  Returns -1 on error, 0 otherwise
{
    register int numBuffers, i, j;
    register int numChannels = inSound->channelCount;
    register short *data;
    short aSample;
    int encodeLength = bestEncodeLength[dropBits];
    int bufferSize = encodeLength * numChannels;
    int lastBufferSize = bufferSize;
    int code, numBits, outByteCount, totalByteCount;
    short channelData[MAX_ENCODE_LEN], channelResidue[MAX_ENCODE_LEN];
    unsigned char outbuf[MAX_ENCODE_LEN * 2];
    int score[NUM_ENCODES];
//    int bufNum = 0;	/* for debugging */
        
    if (inSound->dataFormat != SND_FORMAT_LINEAR_16)
        return -1;

    if (!masksSet)
      setmasks();
    for (i = 0; i < NUM_ENCODES; i++)
        score[i] = 0;
    
    totalByteCount = 0;
    
    // Encode and write each buffer
    data = inPtr;
#ifdef DEBUG
    if (bufferSize == 0) {
	fprintf(stderr, "parlib.c: bufferSize is zero!\n");
	exit(1);
    }
#endif
    numBuffers = numShorts / bufferSize;
    if (numBuffers * bufferSize < numShorts) {
        lastBufferSize = numShorts - (numBuffers * bufferSize);
	numBuffers++;
    }
    while (numBuffers--) {
        // Pad channel data on last buffer
        if (numBuffers == 0 && lastBufferSize != bufferSize) {
	    for (i = lastBufferSize / numChannels; i < encodeLength; i++)
	        channelData[i] = 0;
	    bufferSize = lastBufferSize;
	}
	// Pack data for each channel
	for (i = 0; i < numChannels; i++) {
	    // Unweave channels and compand
	    // Save dropped bits if bit-faithful
	    if (bitFaithful)
		for (j = 0; j < bufferSize / numChannels; j++) {
		    aSample = data[(j * numChannels) + i];
		    channelResidue[j] = aSample & DROPMASK;
		    channelData[j] = aSample >> dropBits;
		}
	    else
		for (j = 0; j < bufferSize / numChannels; j++)
		    channelData[j] = data[(j * numChannels) + i] >> dropBits;
		
	    // Determine winning algorithm
	    code = packtry(channelData, encodeLength, bitFaithful, &numBits);
	    if (verbose)
	        ++score[code];
/*printf("buf %d code %d numBits %d\n", bufNum++, code, numBits);*/
	    /* Pack channel data and write to output file */
	    outByteCount = packchannel(outbuf, channelData, 
				       encodeLength, code, numBits, 
				       bitFaithful, channelResidue);
	    if (outByteCount & 1) {
		outbuf[outByteCount] = 0;
		outByteCount++;		// pad to short
	    }
	    /*printf("count=%d\n", outByteCount);*/
	    ba_write(outbuf,outByteCount,outPtrP);
	    totalByteCount += outByteCount;
	}
        data += bufferSize;
    }
#ifdef DEBUG
    if (verbose) {
        fprintf(stderr, "Scores: ");
	for (i = 0; i < NUM_ENCODES; i++)
	    fprintf(stderr, "%d ", score[i]);
	fprintf(stderr, "\n%d bytes\n", totalByteCount);
    }
#endif
    return totalByteCount;
}

static int parPackCompressByteArray(short *inPtr, byte **outPtrP, 
				    int numShorts,
				    boolean_t firstBlock, 
				    SNDSoundStruct *inputSound,
				    int *dspcinfo)
{
//    int size = inputSound->dataSize;
//    int headerSize = inputSound->dataLocation;
//    int sizePH = size + headerSize;
//    int inSizePH = sizePH/2;
      byte *savedOutPtr=0;
#if __LITTLE_ENDIAN__
      int sizeDone=0;
      short *inFramePtr;
#endif
//    int chans = inputSound->channelCount;
//    int stepSize = FRAME_STEP * chans;
    int comprType = dspcinfo[0];
    int numDropped = dspcinfo[1];
    int encodeLength = bestEncodeLength[dropBits];
//    int encodeLen = dspcinfo[2];
//    int channelCount = dspcinfo[3];
    int byteCountOut;
    int bitFaithful = (comprType == SND_CFORMAT_BIT_FAITHFUL ? 1 : 0);

    /* This strange custom of writing the subheader at this level is relied
       upon by libsound:black_boxes.c (and compress.c, performsound.c) */

    if (firstBlock) {
	SNDCompressionSubheader subheader;
	subheader.originalSize = inputSound->dataSize;
	subheader.method = comprType;
	subheader.numDropped = numDropped;
	subheader.encodeLength = encodeLength;
	subheader.reserved = 0;
	ba_write(&subheader,sizeof(SNDCompressionSubheader),outPtrP);
	savedOutPtr = *outPtrP;
    }

    parDropBits(numDropped);
#ifdef DEBUG
    parVerbose(1);
#endif
    byteCountOut = parpack_to_byte_array(outPtrP, inPtr, inputSound, 
				numShorts, numDropped, bitFaithful);
#ifdef DEBUG
    if (byteCountOut == -1) {
	fprintf(stderr, "parPackCompressByteArray: Cannot compress sound\n");
    }
#endif

#if __LITTLE_ENDIAN__

    sizeDone = (*outPtrP)-savedOutPtr; 

#ifdef DEBUG
    if (sizeDone & 1)
      fprintf(stderr,"*** odd number of bytes computed!");
    if (sizeDone != byteCountOut)
      fprintf(stderr,"*** output pointer not advanced or byte count wrong!");
#endif DEBUG

    inFramePtr=inPtr;
    for (; sizeDone; sizeDone -= 2)
      *inFramePtr++ = NXSwapShort(*inFramePtr);

#endif __LITTLE_ENDIAN__

    return (*outPtrP)-savedOutPtr;
}


/* FIXME: Rewrite the following in terms of the above */

#ifndef LIBSYS_VERSION
int parpack(FILE *outfile, SNDSoundStruct *inSound, int bitFaithful)
//  Returns -1 on error, 0 otherwise
{
    register int numBuffers, i, j;
    register int numChannels = inSound->channelCount;
    register short *data;
    short aSample;
    SNDSoundStruct header;
    int numShorts = inSound->dataSize / sizeof(short);
    int encodeLength = bestEncodeLength[dropBits];
    int bufferSize = encodeLength * numChannels;
    int lastBufferSize = bufferSize;
    int code, numBits, outByteCount, totalByteCount;
    short channelData[MAX_ENCODE_LEN], channelResidue[MAX_ENCODE_LEN];
    unsigned char outbuf[MAX_ENCODE_LEN * 2];
    int score[NUM_ENCODES];
    SNDCompressionSubheader subheader;
//    int bufNum = 0;	/* for debugging */
        
    if (inSound->dataFormat != SND_FORMAT_LINEAR_16)
        return -1;

    setmasks();
    for (i = 0; i < NUM_ENCODES; i++)
        score[i] = 0;
    
    /* Write the soundfile header and info */
    fwrite((void *)inSound, inSound->dataLocation, 1, outfile);
    
    // Write the subheader
    subheader.originalSize = inSound->dataSize;
    subheader.method = bitFaithful;
    subheader.numDropped = dropBits;
    subheader.encodeLength = encodeLength;
    subheader.reserved = 0;
    fwrite(&subheader, sizeof(SNDCompressionSubheader), 1, outfile);
    totalByteCount = sizeof(SNDCompressionSubheader);
    
    // Encode and write each buffer
    data = (short *) ((char *)inSound + inSound->dataLocation);
    if (bufferSize == 0) {
	fprintf(stderr, "bufferSize is zero!\n");
	exit(1);
    }
    numBuffers = numShorts / bufferSize;
    if (numBuffers * bufferSize < numShorts) {
        lastBufferSize = numShorts - (numBuffers * bufferSize);
	numBuffers++;
    }
    while (numBuffers--) {
        // Pad channel data on last buffer
        if (numBuffers == 0 && lastBufferSize != bufferSize) {
	    for (i = lastBufferSize / numChannels; i < encodeLength; i++)
	        channelData[i] = 0;
	    bufferSize = lastBufferSize;
	}
	// Pack data for each channel
	for (i = 0; i < numChannels; i++) {
	    // Unweave channels and compand
	    // Save dropped bits if bit-faithful
	    if (bitFaithful)
		for (j = 0; j < bufferSize / numChannels; j++) {
		    aSample = data[(j * numChannels) + i];
		    channelResidue[j] = aSample & DROPMASK;
		    channelData[j] = aSample >> dropBits;
		}
	    else
		for (j = 0; j < bufferSize / numChannels; j++)
		    channelData[j] = data[(j * numChannels) + i] >> dropBits;
		
	    // Determine winning algorithm
	    code = packtry(channelData, encodeLength, bitFaithful, &numBits);
	    if (verbose)
	        ++score[code];
/*printf("buf %d code %d numBits %d\n", bufNum++, code, numBits);*/
	    // Pack channel data and write to output file
	    outByteCount = packchannel(outbuf, channelData, 
				       encodeLength, code, numBits, bitFaithful,
				       channelResidue);
	    if (outByteCount & 1) {
		outbuf[outByteCount] = 0;
		outByteCount++;		// pad to short
	    }
/*printf("count=%d\n", outByteCount);*/
	    fwrite(outbuf, 1, outByteCount, outfile);
	    totalByteCount += outByteCount;
	}
        data += bufferSize;
    }
    
    /* Rewrite the header with the correct dataSize and dataFormat */
    rewind(outfile);
    header = *inSound;
    header.dataSize = totalByteCount;
    header.dataFormat = SND_FORMAT_COMPRESSED;
    fwrite(&header, sizeof(SNDSoundStruct), 1, outfile);
    
    if (verbose) {
        fprintf(stderr, "Scores: ");
	for (i = 0; i < NUM_ENCODES; i++)
	    fprintf(stderr, "%d ", score[i]);
	fprintf(stderr, "\n%d bytes\n", totalByteCount);
    }
    return 0;
}
#endif


static int unparpack_from_byte_array(byte **inPtrP, int numBytesIn,
			      short **outPtrP, int numShortsOut, 
			      int numChannels, int bitFaithful, 
			      int numDropped, int encodeLength)
/*
 * Returns -1 on error, 0 otherwise.
 * Attempts to decompress numShortsOut samples, subject to not consuming
 * more than numBytesIn of input data.  The actual number of bytes
 * decompressed can be computed by comparing *outPtrP to the value
 * it had on call.  The input pointer *inPtrP is updated to point
 * after the input data actually processed.  It is assumed to be
 * unchanged by the caller between calls.
 */
{
    int i, j, numBuffers;
    short *outPtr;
    byte *inPtr=*inPtrP;
    int code, numBits, count;
    int bufferSize, lastBufferSize;
    short channelData[MAX_ENCODE_LEN], channelResidue[MAX_ENCODE_LEN];
//    int bufNum = 0;	/* for debugging */
    static int phase = 0;
    
    if(!masksSet)
      setmasks();

    /*
     * Read and decode each buffer
     */
    outPtr = *outPtrP;
    bufferSize = lastBufferSize = encodeLength * numChannels;
#ifdef DEBUG
    if (bufferSize == 0) {
	fprintf(stderr, "bufferSize is zero!\n");
	exit(1);
    }
#endif
    numBuffers = numShortsOut / bufferSize;
    if (numBuffers * bufferSize < numShortsOut) {
        lastBufferSize = numShortsOut - (numBuffers * bufferSize);
	numBuffers++;
    }
    while (numBuffers--) {
        if (numBuffers == 0 && lastBufferSize != bufferSize)
            bufferSize = lastBufferSize;
	for (i = phase; i < numChannels; i++) {
	    /* Get the code and number of bits for this buffer */
	    if (numBytesIn < 3) {
		phase = i;
		goto okExit;
	    }
	    code = *inPtr++;
	    numBits = *inPtr++;
	    if ((unsigned)code >= NUM_ENCODES || (unsigned)numBits > 16) {
#ifdef DEBUG
	        fprintf(stderr, "Bits-dropped decompression: BOGUS DATA! "
			"code=%d, numBits=%d\n", code, numBits);
#endif
		goto errExit;
	    }
//printf("buf %d code %d numBits %d\n", bufNum++, code, numBits);
	    if ((count = bytesInBlock(code, numBits, encodeLength)) & 1)
	      count++;	/* padded to short */
	    if (numBytesIn < count+2) {
		phase = i;
		goto okExit;
	    }
	    unpackchannel(channelData, inPtr, encodeLength, code, 
			  numBits, bitFaithful, channelResidue, numDropped);
	    inPtr += count;
	    *inPtrP = inPtr;
	    numBytesIn -= (count+2);

 	    // Weave channels and expand. Restore dropped bits if bit-faithful
	    if (bitFaithful)
		for (j = 0; j < bufferSize / numChannels; j++)
		   outPtr[(j * numChannels) + i] 
		     = (channelData[j] << numDropped) | channelResidue[j];
	    else
		for (j = 0; j < bufferSize / numChannels; j++)
		   outPtr[(j * numChannels) + i] 
		     = channelData[j] << numDropped;
	}
	phase = 0;
        outPtr += bufferSize;
	*outPtrP = outPtr;
    }
 okExit:
    return 0;
 errExit:
    return -1;
}


static int _parPackDecompressByteArray(byte **inPtrP, int inBytes,
				       short *outPtr,
				       int outBytes, int chans, 
				       int rateShift, int makeMono,
				       int bitFaithful, int numDropped, 
				       int encodeLength)
    /* 
     * FIXME: rateShift and makeMono are supported in a brute force way.
     *	      For ATC, they make real-time playback always possible.
     *	      It is not clear how helpful they are for this comprType.
     * rateShift == 1 for downsampling by 2.
     * rateShift == 2 for downsampling by 4.
     * if makeMono>0, stereo is converted to mono.
     * outBytes = total number of bytes to compute at UNSHIFTED rate.
     */
{
    int err, i, skip, outSamps;
    short *outPtr0 = outPtr;

    skip = ((makeMono && chans==2)? 2 : 1);
    skip <<= rateShift;

    /* FIXME: downsampling and stereo-to-mono conversion should
       occur on compressed data directly, and outSamps should
       be reduced accordingly below. Here we post-process for now. */
    outSamps = outBytes >> 1;
    err = unparpack_from_byte_array(inPtrP, inBytes, &outPtr, outSamps, 
				    chans, bitFaithful, numDropped, 
				    encodeLength);

    outBytes = (outPtr - outPtr0) << 1;

    if (skip > 1) {
	outBytes /= skip;
	outSamps = outBytes >> 1;
	for (i=0,outPtr=outPtr0; i<outSamps; i++, outPtr += skip)
	  outPtr0[i] = NXSwapHostShortToBig(*outPtr);
    } else {
#if __LITTLE_ENDIAN__
	outSamps = outBytes >> 1;
	for (i=0,outPtr=outPtr0; i<outSamps; i++)
	  *outPtr++ = NXSwapShort(*outPtr);
#endif
    }
    return outBytes;
}

/* FIXME: Rewrite the below in terms of the above */

#ifndef LIBSYS_VERSION
int unparpack(FILE *infile, SNDSoundStruct **inSound)
//  Returns -1 on error, 0 otherwise
{
    register int i, j, numBuffers, numChannels;
    register short *data;
    int numDropped, encodeLength, code, numBits, count;
    int numShorts, bufferSize, lastBufferSize;
    int bitFaithful;
    SNDSoundStruct *theSound, *s;
    unsigned char *inPtr;
    short channelData[MAX_ENCODE_LEN], channelResidue[MAX_ENCODE_LEN];
    SNDCompressionSubheader *subheader;
    int fd, serr, newInfoSize;
//    int bufNum = 0;	/* for debugging */
    
    setmasks();

    /* Read (map in) the soundfile */
    fd = fileno(infile);
    serr = SNDRead(fd, &s);
    if (serr) {
	fprintf(stderr, "Could not read input sound: %s\n",
		SNDSoundError(serr));
	return -1;
    }
    if (s->dataFormat != SND_FORMAT_COMPRESSED)
	return -1;
    subheader = (SNDCompressionSubheader *)((char *)s + s->dataLocation);
    bitFaithful = subheader->method;
    numDropped = subheader->numDropped;
    encodeLength = subheader->encodeLength;
    inPtr = (unsigned char *)((char *)subheader + sizeof(SNDCompressionSubheader));
    
    /* Allocate a new sound - FIXME: does not copy in info */
    newInfoSize = s->dataLocation - (sizeof(SNDSoundStruct) - 4);
    serr = SNDAlloc(&theSound, subheader->originalSize, SND_FORMAT_LINEAR_16,
                 s->samplingRate, s->channelCount,
		 (newInfoSize > 4 ? newInfoSize : 4));
    if (serr) {
	fprintf(stderr, "Could not allocate sound: %s\n",
		SNDSoundError(serr));
	return -1;
    }
	
    // Read and decode each buffer
    data = (short *) ((char *)theSound + theSound->dataLocation);
    numChannels = theSound->channelCount;
    bufferSize = lastBufferSize = encodeLength * numChannels;
    numShorts = theSound->dataSize / sizeof(short);
    if (bufferSize == 0) {
	fprintf(stderr, "bufferSize is zero!\n");
	exit(1);
    }
    numBuffers = numShorts / bufferSize;
    if (numBuffers * bufferSize < numShorts) {
        lastBufferSize = numShorts - (numBuffers * bufferSize);
	numBuffers++;
    }
    while (numBuffers--) {
        if (numBuffers == 0 && lastBufferSize != bufferSize)
            bufferSize = lastBufferSize;
	for (i = 0; i < numChannels; i++) {
	    // Get the code and number of bits for this buffer
	    code = *inPtr++;
	    numBits = *inPtr++;
	    if ((unsigned)code >= NUM_ENCODES || (unsigned)numBits > 16) {
	        fprintf(stderr, "BOGUS! code=%d, numBits=%d\n", code, numBits);
		goto errExit;
	    }
//printf("buf %d code %d numBits %d\n", bufNum++, code, numBits);
	    if ((count = bytesInBlock(code, numBits, encodeLength)) & 1)
	        count++;	// padded to short
	    unpackchannel(channelData, inPtr, encodeLength, code, numBits, bitFaithful,
			  channelResidue, numDropped);
	    inPtr += count;

 	    // Weave channels and expand.  Restore dropped bits if bit-faithful.
	    if (bitFaithful)
		for (j = 0; j < bufferSize / numChannels; j++)
		   data[(j * numChannels) + i] = (channelData[j] << numDropped) |
		   			         channelResidue[j];
	    else
		for (j = 0; j < bufferSize / numChannels; j++)
		   data[(j * numChannels) + i] = channelData[j] << numDropped;
	}
        data += bufferSize;
    }

    errExit:
    *inSound = theSound;
    return 0;
}
#endif
