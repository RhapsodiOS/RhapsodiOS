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
#ifndef LIBSYS_VERSION

/* Sound error handling macro */
static void soundErrorExit() {
    fprintf(stderr, "%s: sound error: %s\n", programName, 
	    SNDSoundError(soundError));
    exit(1);
}

/* Mach error handling macro */
static void machErrorExit() {
    fprintf(stderr, "%s: mach error: %s\n", programName, 
	    mach_error_string(machError)); 
    exit(1); 
}

#endif LIBSYS_VERSION

#define MAXSHORT_I (32767)
#define MINSHORT_I (-32768)

/* Add source array to dest array, results in dest */
static void addShortArrays(short *dest, short *source, int size)
{
    int i;
    int sum;
    static int pof = 0;
    static int nof = 0;

    for (i = 0; i < size; i++) {
	sum = ((int)dest[i]) + ((int)source[i]);
	if (sum > MAXSHORT_I) {
	    if (pof == 0)
	      fprintf(stderr, "*** addShortArrays: overflow, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    else if ((pof % 1000) == 0)
	      fprintf(stderr, "*** addShortArrays: another "
		      "thousand overflows, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    sum = MAXSHORT_I;
	    pof++;
	} else if (sum < MINSHORT_I) {
	    if (nof == 0)
	      fprintf(stderr, "*** ATC: addShortArrays: (-) overflow, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    else if ((nof % 1000) == 0)
	      fprintf(stderr, "*** ATC: addShortArrays: another "
		      "thousand (-) overflows, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    nof++;
	    sum = MINSHORT_I;
	}
	dest[i] = sum;
    }
}

/* Add source array to dest array, results in dest */
static void addToInterleavedShortArray(short *dest, int skip,
				       short *source, int size)
{
    int i;
    int sum;
    static int pof = 0;
    static int nof = 0;
    short *outPtr = dest;

    for (i = 0; i < size; i++) {
	sum = ((int)*outPtr) + ((int)source[i]);
	if (sum > MAXSHORT_I) {
	    if (pof == 0)
	      fprintf(stderr, "*** addShortArrays: overflow, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    else if ((pof % 1000) == 0)
	      fprintf(stderr, "*** addShortArrays: another "
		      "thousand overflows, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    sum = MAXSHORT_I;
	    pof++;
	} else if (sum < MINSHORT_I) {
	    if (nof == 0)
	      fprintf(stderr, "*** ATC: addShortArrays: (-) overflow, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    else if ((nof % 1000) == 0)
	      fprintf(stderr, "*** ATC: addShortArrays: another "
		      "thousand (-) overflows, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    nof++;
	    sum = MINSHORT_I;
	}
	*outPtr = sum;
	outPtr += skip;
    }
}

/* Copy source array to dest array */
static void copyShortArrays(short *dest, short *source, int size)
{
    bcopy((char *)source, (char *)dest, size * sizeof(short));
}

static void copyToInterleavedShortArray(short *dest, int skip,
					short *source, int size)
{
    int i;
    short *p = dest;
    for (i=0;i<size;i++) {
	*p = *source++;
	p += skip;
    }
}

#if 0

static void copyShortArraySkip(short *dest, short *source, int skip, int size)
{
    int i;
    short *p = dest;
    for (i=0;i<size;i++) {
	*p++ = *source;
	source += skip;
    }
}

/* Convert multi-channel sound to mono by tossing extra channels */
static void	convertToMono(SNDSoundStruct **theSound)
{
    SNDSoundStruct *newSound;
    short 	*oldPtr, *newPtr;
    int		size     = (*theSound)->dataSize;
    int		format   = (*theSound)->dataFormat;
    int		rate 	 = (*theSound)->samplingRate;
    int		channels = (*theSound)->channelCount;
    int		newSize, i, j, k, s, scl;
    
    newSize = size/channels;
    if (soundError = SNDAlloc(&newSound, newSize, format, rate, 1, 4))
	soundErrorExit();
    oldPtr  = (short *) ((char *) *theSound + (*theSound)->dataLocation);
    newPtr  = (short *) ((char *) newSound + newSound->dataLocation);
#define SCALE_BITS 10
    scl = (1<<SCALE_BITS)/channels;
    for (i = 0, j = 0; i < newSize/sizeof(short); i++, j+=channels) {
	for (k=0, s=0; k<channels; k++)
	  s += (int)oldPtr[j+k];
	s *= scl;
	newPtr[i] = s >> SCALE_BITS;
    }
    if (soundError = SNDFree(*theSound))
	soundErrorExit();
    *theSound = newSound;
}
#endif

static INLINE void copyDATA_TYPEsFromShorts(DATA_TYPE *dest, short *src, int n)
{
    int i;
    DATA_TYPE *dp = dest;
    short *sp = src;
    for (i=n; i; i--)
      *dp++ = SHORT_TO_DATA(*sp++);
}

static INLINE void copyDATA_TYPEsFromInterleavedShorts(DATA_TYPE *dest, 
						    short *src, 
						    int skip, int n)
{
    int i;
    DATA_TYPE *dp = dest;
    short *sp = src;
    for (i=n; i; i--) {
	*dp++ = SHORT_TO_DATA(*sp);
	sp += skip;
    }
}

#ifndef LIBSYS_VERSION
static INLINE void copyDATA_TYPEsFromInts(DATA_TYPE *dest, int *src, int n)
{
    int i;
    DATA_TYPE *dp = dest;
    int *ip = src;
    for (i=n; i; i--)
      *dp++ = INT_TO_DATA(*ip++);
}
#endif

static INLINE void copyShortsFromDATA_TYPEs(short *dest, DATA_TYPE *src, int n)
{
    int i,id;
    DATA_TYPE d,*dp = src;
    short *sp = dest;
    int dmax = MAXSHORT_I;
    int dmin = MINSHORT_I;
    static int pof = 0;
    static int nof = 0;

    for (i=n; i; i--) {
	d = *dp++;
	id = DATA_TO_SHORT(d);
	if (id > dmax) {
	    if (pof == 0)
	      fprintf(stderr, "*** ATC: copyShortsFromDATA_TYPEs: overflow, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    else if ((pof % 1000) == 0)
	      fprintf(stderr, "*** ATC: copyShortsFromDATA_TYPEs: another "
		      "thousand overflows, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    id = dmax;
	    pof++;
	} else if (id < dmin) {
	    if (nof == 0)
	      fprintf(stderr, "*** ATC: copyShortsFromDATA_TYPEs: (-) overflow, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    else if ((nof % 1000) == 0)
	      fprintf(stderr, "*** ATC: copyShortsFromDATA_TYPEs: another "
		      "thousand (-) overflows, "
		      "index %d, frame %d\n",
		      i, frameNumber);
	    nof++;
	    id = dmin;
	}
	*sp++ = (short)id;
    }
}


static INLINE void zeroDATA_TYPEs(DATA_TYPE *buf, int n)
{
    int i;
    DATA_TYPE *bp = buf;
    for (i=n; i; i--)
      *bp++ = 0;
}

#if 0
static INLINE void zeroInterleavedDoubles(double *buf, int skip, int n)
{
    int i;
    double *bp = buf;
    for (i=n; i; i--) {
	*bp = 0.0;
	bp += skip;
    }
}
#endif

static INLINE void scaleDATA_TYPEs(DATA_TYPE *buf, DATA_TYPE scale, int n)
{
    int i;
    DATA_TYPE *bp = buf;
    DATA_TYPE tmp;
    for (i=n; i; i--) {
	tmp = MUL(*bp,scale);
	*bp++ = tmp;
    }
}

#if 0
static INLINE void intsFromDATA_TYPEs(int *ibuf, DATA_TYPE *buf, int n)
{
    int i;
    DATA_TYPE *bp = buf;
    int *ibp = ibuf;
    for (i=n; i; i--) {
	if (*bp > MAXINT) {
	    fprintf(stderr, "*** output overflow, index %d, frame %d\n",
		    i, frameNumber);
	    *bp = MAXINT;
	} else if (*bp < MININT) {
	    fprintf(stderr, "*** negative output overflow, "
		    "index %d, frame %d\n",
		    i, frameNumber);
	    *bp = MININT;
	}
	*ibp++ = DATA_TO_INT(*bp++);
    }
}

static INLINE void DATA_TYPEsFromInts(DATA_TYPE *buf, int *ibuf, int n)
{
    int i;
    DATA_TYPE *bp = buf;
    int *ibp = ibuf;
    for (i=n; i; i--)
      *bp++ = (DATA_TYPE)*ibp++;
}

static INLINE void fracsFromIntsShift(DATA_TYPE *buf, int *ibuf, 
						int scl, int n)
{
    int i;
    DATA_TYPE *bp = buf;
    int *ibp = ibuf;
    for (i=n; i; i--)
      *bp++ = (DATA_TYPE)*ibp++;
}
#endif 0


#ifndef LIBSYS_VERSION

static INLINE int round (DATA_TYPE a)
{
  return (int)ADD(a,DOUBLE_TO_DATA(0.5));
}

static INLINE int maxInt(int *ibuf, int n)
{
    int i,imax,ibi;
    int *ibp = ibuf;
    imax = *ibp++;
    for (i=n-1; i; i--) {
	ibi = *ibp++;
	if (ibi > imax)
	  imax = ibi;
    }
    return imax;
}
#endif

static INLINE int maxMagInt(int *ibuf, int n)
/* returned maximum-magnitude element, signed */
{
    int i,maxaval,maxval,val,aval;
    int *ibp = ibuf;
    maxval = *ibp++;
#   define IABS(x) (((x)<0)? -(x) : (x))
    maxaval = IABS(maxval);
    for (i=n-1; i; i--) {
	val = *ibp++;
	aval = IABS(val);
	if (aval > maxaval) {
	    maxaval = aval;
	    maxval = val;
	}
    }
    return maxval;
}

static INLINE int intsNormalizer(int *ints, int n)
/* Returns left-shifter which will normalize maximum array element */
{
    int msb = 0x40000000;	/* bit to right of sign bit */
    int leftShift = 0;
    int ipeak = maxMagInt(ints,n);
    int signBit = ((ipeak < 0) ? msb : 0);
    if (ipeak == 0)
      return 0;
    while ((ipeak & msb) == signBit) {
	ipeak <<= 1;
	leftShift++;
    }	
    return leftShift;
}

static INLINE void leftShiftInts(int *ibuf, int n, int shift)
{
    int i;
    int *ibp = ibuf;
    if (shift != 0)
      for (i=n; i; i--)
	*ibp++ <<= shift;
}

static INLINE void rightShiftInts(int *ibuf, int n, int shift)
{
    int i;
    int *ibp = ibuf;
    if (shift != 0)
      for (i=n; i; i--)
	*ibp++ >>= shift;
}

#ifdef LIBSYS_VERSION
#define writeDATA_TYPEs(buf,n,fileName)
#define writeIntsInHex(buf,n,fileName)
#else

#import <stdio.h>

static INLINE void printDATA_TYPE(FILE *fp, DATA_TYPE d)
{
#ifdef FRACTION
    fprintf(fp,"0x%08X\n",(unsigned)d);
#else
    fprintf(fp,"%22.17f\n",(double)d);
#endif
}

static void writeDATA_TYPEsSkip(DATA_TYPE *buf, int skp, int n, char *fileName)
{
    int i;
    FILE *fp;
    DATA_TYPE *bp = buf;
    char fn[1024];
    strncpy(fn,fileName,1024-3);
    strcat(fn,".m");
    fp = fopen(fn,"w");
    if (fp == NULL)
      fp = stderr;
    fprintf(stderr,"Writing %d samples to file '%s'\n",n,fn);
    fprintf(fp,"%s = [\n",fileName);	/* matlab format */
    for (i=n; i; i--) {
	printDATA_TYPE(fp,*bp);
	bp += skp;
    }
    fprintf(fp,"\n];\n");	/* matlab format */
    fclose(fp);
}

static void appendDATA_TYPEs(DATA_TYPE *buf, int n, char *fileName)
{
    int i;
    FILE *fp;
    DATA_TYPE *bp = buf;
    fp = fopen(fileName,"a");
    if (fp == NULL)
      fp = stderr;
    fprintf(stderr,"Appending %d samples to file '%s'\n",n,fileName);
    for (i=n; i; i--) 
      printDATA_TYPE(fp,*bp++);
    fclose(fp);
}

static void writeDATA_TYPEs(DATA_TYPE *buf, int n, char *fileName)
{
    writeDATA_TYPEsSkip(buf, 1, n, fileName);
}

static void writeShorts(short *buf, int n, char *fileName)
{
    DATA_TYPE dbuf[n];
    copyDATA_TYPEsFromShorts(dbuf,buf,n);
    writeDATA_TYPEs(dbuf,n,fileName);
}

static void writeInts(int *buf, int n, char *fileName)
{
    DATA_TYPE dbuf[n];
    copyDATA_TYPEsFromInts(dbuf,buf,n);
    writeDATA_TYPEs(dbuf,n,fileName);
}

static void writeIntsInHex(int *buf, int n, char *fileName)
{
    int i;
    FILE *fp;
    int *bp = buf;
    char fn[1024];
    strncpy(fn,fileName,1024-5);
    strcat(fn,".hex");
    fp = fopen(fn,"w");
    if (fp == NULL)
      fp = stderr;
    fprintf(stderr,"Writing %d hex samples to file '%s'\n",n,fileName);
    for (i=n; i; i--) {
	fprintf(fp,"0x%08X\n",(unsigned int)*bp++);
    }
    fclose(fp);
}

#endif

/*
 * ----------------------------- applyWindow ---------------------------------
 */
static INLINE void applyWindow(DATA_TYPE *buf,int n)
{
    int i;
    static DATA_TYPE *window = NULL;
    DATA_TYPE *w = window;
    DATA_TYPE tmp;
    if (!w) {					
	/* create sin window */
	double scl = M_PI/((double)n);
	double off = M_PI/(2.0*(double)n);
	w = window = malloc(n * sizeof(double));
	for (i=0;i<n;i++)
	  window[i] = DOUBLE_TO_DATA(sin(((double)i)*scl+off));
    }
    for (i=n;i;i--) {
	tmp = *buf;
	*buf++ = MUL(tmp, *w++);
    }
}

/*
 * ----------------------------- DCT --------------------------------
 */

static DATA_TYPE *coswknz=0,*sinwknz=0;
static int nwk=0;

static void createPhasors(int n)
{
    int i;
    double dn = (double)n;
    double nz = 0.5 * (dn/2.0+1.0);
//  double nz = 0.5 * (dn/2.0);
    double dang = 2.0 * M_PI * nz / dn;
    double ang = 0.0;
    DATA_TYPE *cp,*sp;

    nwk = n;
    if (coswknz) {
	free(coswknz);
	free(sinwknz);
    }
    cp = coswknz = malloc(n * sizeof(DATA_TYPE));
    sp = sinwknz = malloc(n * sizeof(DATA_TYPE));
    for (i=0;i<n;i++) {
	*cp++ = DOUBLE_TO_DATA(cos(ang));
	*sp++ = DOUBLE_TO_DATA(sin(ang));
	ang += dang;
    }
    PLOT(coswknz,n,"coswknz");
    PLOT(sinwknz,n,"sinwknz");
}

static INLINE void arrMpy(DATA_TYPE *dest, 
			  DATA_TYPE *src1, DATA_TYPE *src2, int n)
{
    int i;
    DATA_TYPE *dp = dest;
    DATA_TYPE *s1p = src1;
    DATA_TYPE *s2p = src2;
    for (i=n; i; i--)
      *dp++ = MUL(*s1p++ , *s2p++) ;
}

static INLINE void arrMpySkip(DATA_TYPE *dest, int desti, 
			      DATA_TYPE *src1, int src1i, 
			      DATA_TYPE *src2, int src2i, int n)
/* dest[i] = src1[i] * src2[i] */
{
    int i;
    DATA_TYPE *dp = dest;
    DATA_TYPE *s1p = src1;
    DATA_TYPE *s2p = src2;
    int di = desti;
    int s1i = src1i;
    int s2i = src2i;
    for (i=n; i; i--) {
	*dp = MUL(*s1p , *s2p);
	dp  += di;
	s1p += s1i;
	s2p += s2i;
    }
}

static INLINE void arrMpyNegSkip(DATA_TYPE *dest, int desti, 
				 DATA_TYPE *src1, int src1i, 
				 DATA_TYPE *src2, int src2i, int n)
/* dest[i] = - src1[i] * src2[i] */
{
    int i;
    DATA_TYPE *dp = dest;
    DATA_TYPE *s1p = src1;
    DATA_TYPE *s2p = src2;
    int di = desti;
    int s1i = src1i;
    int s2i = src2i;
    for (i=n; i; i--) {
	*dp = - MUL(*s1p , *s2p);
	dp  += di;
	s1p += s1i;
	s2p += s2i;
    }
}

#ifndef LIBSYS_VERSION
static INLINE void arrMpyAddSkip(double *dest, int desti, 
				 double *src1, int src1i, 
				 double *src2, int src2i, 
				 double *src3, int src3i, int n)
/* dest[i] = src1[i] * src2[i] + src3[i] */
{
    int i;
    double *dp = dest;
    double *s1p = src1;
    double *s2p = src2;
    double *s3p = src3;
    int di = desti;
    int s1i = src1i;
    int s2i = src2i;
    int s3i = src3i;
    for (i=n; i; i--) {
	*dp = *s1p * *s2p + *s3p;
	dp  += di;
	s1p += s1i;
	s2p += s2i;
	s3p += s3i;
    }
}
#endif

static INLINE void arrMpyAddDestSkip(DATA_TYPE *dest, int desti, 
				     DATA_TYPE *src1, int src1i, 
				     DATA_TYPE *src2, int src2i, int n)
/* dest[i] += src1[i] * src2[i] */
{
    int i;
    DATA_TYPE *dp = dest;
    DATA_TYPE *s1p = src1;
    DATA_TYPE *s2p = src2;
    int di = desti;
    int s1i = src1i;
    int s2i = src2i;
    for (i=n; i; i--) {
	*dp = ADD(*dp, MUL(*s1p , *s2p));
	dp  += di;
	s1p += s1i;
	s2p += s2i;
    }
}

static INLINE void arrMpySubDestSkip(DATA_TYPE *dest, int desti, 
				     DATA_TYPE *src1, int src1i, 
				     DATA_TYPE *src2, int src2i, int n)
/* dest[i] -= src1[i] * src2[i] */
{
    int i;
    DATA_TYPE *dp = dest;
    DATA_TYPE *s1p = src1;
    DATA_TYPE *s2p = src2;
    int di = desti;
    int s1i = src1i;
    int s2i = src2i;
    for (i=n; i; i--) {
	*dp  = SUB(*dp , MUL(*s1p , *s2p));
	dp  += di;
	s1p += s1i;
	s2p += s2i;
    }
}

/* ----------------- Fast DCT/DST based on the real-only FFT ---------------*/

static INLINE void dctnz_from_hfft(DATA_TYPE *dctBuf, 
				   DATA_TYPE *hfftBuf, int n)
/* 
 * Input is  Re(z^[0]),...,Re(z^[n/2]),Im(z^[n/2-1]),...,Im(z^[1]).
 * Output is dct[0],dct[1],...,dct[n/2].
 * The dct is even, so dct[n/2+i] = dct[n/2-i].
 */
{
    int nspec = ((n>>1) + 1);
    if (n!=nwk) 
      createPhasors(n);
    arrMpy(dctBuf,coswknz,hfftBuf,nspec);
    PLOT(dctBuf,nspec,"hfft_x_coswknz");
    arrMpyAddDestSkip(dctBuf+1,1,sinwknz+1,1,hfftBuf+n-1,-1,nspec-2);
}

static INLINE void dstnz_from_hfft(DATA_TYPE *dstBuf, 
				   DATA_TYPE *hfftBuf, int n)
/* 
 * Input is  Re(z^[0]),...,Re(z^[n/2]),Im(z^[n/2-1]),...,Im(z^[1]).
 * Output is dst[0],dst[1],...,dst[n/2].
 * The dst is odd, so dst[n/2+i] = - dst[n/2-i].
 */
{
    int nspec = ((n>>1) + 1);
    if (n!=nwk) 
      createPhasors(n);
    arrMpy(dstBuf,sinwknz,hfftBuf,nspec);
    arrMpySubDestSkip(dstBuf+1,1,coswknz+1,1,hfftBuf+n-1,-1,nspec-2);
}

static void adjustPhase(DATA_TYPE *dnzBuf)
{
    int i;
    for (i=1; i<NSPEC; i += 2)
      dnzBuf[i] = -dnzBuf[i];
}

static int tweakPhase = 0;

static void idctnz_from_ihfft(DATA_TYPE *idctnzBuf, DATA_TYPE *dctBuf, int n)
/* 
 * Input is dct[0],dct[1],...,dct[n/2].
 * Output is  idctnz[0],idctnz[1],...,idctnz[n-1] (even).
 */
{
    int nspec = ((n>>1) + 1);
    if (n!=nwk) 
      createPhasors(n);
    arrMpy(idctnzBuf,dctBuf,coswknz,nspec); /* De */
    arrMpySkip(idctnzBuf+n-1,-1,dctBuf+1,1,sinwknz+1,1,nspec-2); /* Do */
    if (tweakPhase)
      adjustPhase(idctnzBuf);
    fft_inverse_hermitian(idctnzBuf,n);
}

static void idstnz_from_ihfft(DATA_TYPE *idstnzBuf, DATA_TYPE *dstBuf, int n)
/* 
 * Input is dst[0],dst[1],...,dst[n/2].
 * Output is  idstnz[0],idstnz[1],...,idstnz[n-1] (even).
 */
{
    int nspec = ((n>>1) + 1);
    if (n!=nwk) 
      createPhasors(n);
    arrMpy(idstnzBuf,dstBuf,sinwknz,nspec); /* Se */
    arrMpyNegSkip(idstnzBuf+n-1,-1,dstBuf+1,1,coswknz+1,1,nspec-2); /* - So */
    if (tweakPhase)
      adjustPhase(idstnzBuf);
    fft_inverse_hermitian(idstnzBuf,n);
}

#ifndef LIBSYS_VERSION

/* ---------------------- Direct DCT/DST Computation ---------------------- */

static void dctnz(double *dctBuf, double *x, int n)
/* Output is dct[0],dct[1],...,dct[n-1] (even, but fully computed) */
{
    int i,k;
    double dn = (double)n;
    double nz = 0.5 * (dn/2.0+1.0);
    double twoPiOverN = 2.0 * M_PI / dn;
    double ang,dang,sum;
    for (k=0; k<n; k++) {
	dang = twoPiOverN * ((double)k);
	ang = dang * nz;
	sum = 0.0;
	for (i=0; i<n; i++) {
	    sum += x[i] * cos(ang);
	    ang += dang;
	}
	dctBuf[k] = sum;
    }
}

static void dstnz(double *dstBuf, double *x, int n)
/* Output is dst[0],dst[1],...,dst[n/2+1] */
{
    int i,k;
    double dn = (double)n;
    double nz = 0.5 * (dn/2.0+1.0);
    double twoPiOverN = 2.0 * M_PI / dn;
    double ang,dang,sum;
    for (k=0; k<n; k++) {
	dang = twoPiOverN * ((double)k);
	ang = dang * nz;
	sum = 0.0;
	for (i=0; i<n; i++) {
	    sum += x[i] * sin(ang);
	    ang += dang;
	}
	dstBuf[k] = sum;
    }
}

static void idctnz(DATA_TYPE *idctnzBuf, DATA_TYPE *dctBuf, int n)
/* 
 * Input is dct[0],dct[1],...,dct[n/2].
 * Output is  idctnz[0],idctnz[1],...,idctnz[n-1] (even).
 */
{
    int i,k;
    double dn = (double)n;
    double scl = (1.0 / dn);
    double nz = (0.5 * (dn/2.0+1.0));
    double twoPiOverN = (2.0 * M_PI / dn);
    double ang,dang;
    DATA_TYPE sum;
    for (i=0; i<n; i++) {
	dang = twoPiOverN * ((double)i+nz);
	ang = 0.0;
	sum = 0;
	for (k=0; k<n; k++) {
	    /* FIXME: Use hfft's cos[] table here */
	    sum = ADD(sum, MUL(dctBuf[k], DOUBLE_TO_DATA(cos(ang))));
	    ang += dang;
	}
	idctnzBuf[i] = MUL(sum,scl);
    }
}

static void idstnz(DATA_TYPE *idstnzBuf, DATA_TYPE *dstBuf, int n)
/* 
 * Input is dst[0],dst[1],...,dst[n/2].
 * Output is  idstnz[0],idstnz[1],...,idstnz[n-1] (even).
 */
{
    int i,k;
    double dn = (double)n;
    double scl = (1.0 / dn);
    double nz = (0.5 * (dn/2.0+1.0));
    double twoPiOverN = (2.0 * M_PI / dn);
    double ang,dang;
    DATA_TYPE sum;
    for (i=0; i<n; i++) {
	dang = twoPiOverN *((double)i + nz);
	ang = 0.0;
	sum = 0;
	for (k=0; k<n; k++) {
	    sum = ADD(sum, MUL(dstBuf[k], DOUBLE_TO_DATA(sin(ang))));
	    ang += dang;
	}
	idstnzBuf[i] = sum * scl;
    }
}

/*--------------------------------- dB ------------------------------------*/

static INLINE void dBPowerDoubles(double *d, int n)
{
    int i;
    double *dp = d;
    for (i=0; i<n; i++)
      *dp++ = 10.0 * log10(*dp);
}

static INLINE void negDoubles(double *d, int n)
{
    int i;
    double *dp = d;
    for (i=0; i<n; i++)
      *dp++ = - *dp;
}

#endif !LIBSYS_VERSION
