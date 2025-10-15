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
/* atc.c - Transform Coder.
 *
 *	Currently supports only SND_FORMAT_LINEAR_16.
 *
 *	Reference: 	J. P. Princen and A. B. Bradley, 
 *			"Analysis/Synthesis Filter Bank Design Based on
 *			Time Domain Aliasing Cancellation,"
 *			IEEE ASSP-34#5, Oct. 1986, pp. 1153-1161.
 */

#import "datatype.h"
//#import "cb.h"
#import <cb.h>
#import "atc.h"
#import <sys/stat.h>
#import <architecture/byte_order.h>

#ifndef LIBSYS_VERSION

static int writeMax = 0;
static double maxSpec[NSPEC];
static int useThreshFile = 0;
static double thresh[NSPEC];
static double thresholdShift = 0;
static double bandWidth = 0.5;
static double highPass = 0.0;
static double maxMag = 2.0;
static int exponentShift = 0;
static int binWidth = (FRAME_SIZE/2);
static int lowBin = 0;
char threshFile[100];
#endif

/*
 * ------------------------------ Utilities ----------------------------------
 */

#import "atc_globals.c"
#import "hfft.c"
#import "static_utilities.c"
#import "quantization.c"

/*
 * -------------------------- atcCompressSpectrum ----------------------------
 */

static INLINE void ba_write(void *cp, int sz, byte **ba)
{
    int i;
    byte *bp = *ba;
    for (i=sz; i; i--)
      *bp++ = *((byte *)cp)++;
    *ba = bp;
}

static void atcCompressSpectrum(DATA_TYPE *spec, int nspec, byte **outPtrP)
{
    REGISTER int i;
    byte *savedOutPtr = *outPtrP;
#ifdef MAGIC
    short magic = ATC_MAGIC;
#endif
    byte frameSizeInBytes;
    PLOT(spec,nspec,"spec");
    /*
     * Convert to fixed-point
     */
#if 0
    /* Old version */
    scaleDATA_TYPEs(spec,((pow(2,31)-1.0)/FRAME_SIZE),nspec);
    intsFromDATA_TYPEs(ispec,spec,nspec);
#else
    for (i=0; i<nspec; i++) {
	ispec[i] = DATA_TO_INT_RSHIFTED(spec[i],LG2_FRAME_SIZE);
    }
#endif
    PLOT_HEX(ispec,nspec,"ispec");

    /* 
     * Find left-shift which will normalize peak spectral value.
     */
    frameExponent = intsNormalizer(ispec,nspec);

    if (frameExponent >= MAX_FRAME_EXPONENT || (frameExponent == 0)) {
	/* silent frame */

	frameExponent = MAX_FRAME_EXPONENT;
	frameSizeInBytes = FRAME_LENGTH_SIZE + FRAME_PEAK_SIZE;
#ifdef MAGIC
	ba_write(&magic,MAGIC_SIZE,outPtrP);
	frameSizeInBytes += MAGIC_SIZE;
#endif
#ifdef SEQUENCE_HACK	
	*(*outPtrP)++ = frameNumber & 0xFF;
#ifdef DEBUG
	fprintf(stderr,"\nframe %d:",frameNumber);
#endif
#else
	*(*outPtrP)++ = (byte)frameSizeInBytes;
#endif
	*(*outPtrP)++ = frameExponent;
    } else {
	/*
	 * Normalize spectrum
	 * (Could avoid this by subtracting frameExponent from CB exponents.)
	 */

	/* Inhibit frame normalization for DSP version debugging */
#if 0	
	leftShiftInts(ispec,nspec,frameExponent);
	PLOT_HEX(ispec,nspec,"ispecn");
#endif
	
	/* 
	 * Repeat for each critical band.
	 */
	
	for (i=0; i<NCB; i++) {
	    REGISTER int *p = &(ispec[cbLo[i]]);
	    REGISTER int w = cbWidth[i];
	    REGISTER int e,z;
	    REGISTER int t = pow(2,31-MAX_FRAME_EXPONENT); /* 2^15 */

	    z = zeroMantissasInQuietBins(p,w,t);
	    if (!z) {
		e = intsNormalizer(p,w);
		exponents[i] = e - frameExponent;
		leftShiftInts(p,w,e);
	    } else		/* all bins are zero */
		exponents[i] = 0;
	}
	PLOT_HEX(exponents,NCB,"exponents");
	PLOT_HEX(ispec,nspec,"mantissas");
	
	quantizeExponents(exponents,NCB);
	PLOT_HEX(exponents,NCB,"exponentsQ");
	
	/*** FIXME: Presence vector for exponents would reduce output size ***/
	
	createMantissaSizes(mantissaSizes,nspec);
	PLOT_HEX(mantissaSizes,nspec,"mantissaSizes");
	
	quantizeMantissas(ispec,mantissaSizes,nspec);
	PLOT_HEX(ispec,nspec,"mantissasQ");
	
#if 0
	zeroMantissasInQuietBands(ispec,frameExponent,exponents,NCB);
	PLOT_HEX(ispec,nspec,"mantissasZ");
#endif
	
	packExponents(exponentsP,exponents,NCB);
	PLOT_HEX((int *)exponentsP,NCB>>2,"exponentsP");
	
	nMantissas = packMantissas(mantissasP,presencesP,ispec,
				   mantissaSizes,nspec);
	if (nMantissas&1)
	  nMantissas += 1;	/* DSP wants short-alignment */
	PLOT_HEX((int *)mantissasP,nMantissas>>2,"mantissasP");
	PLOT_HEX((int *)presencesP,NPRESENCES,"presencesP");
	
	/*
	 * Write frameExponent, exponentsP, mantissasP, presencesP to disk.
	 * File Format:
	 * Total frame size in bytes (1 byte)
	 * Frame exponent (1 byte)
	 * NCB=40 4-bit exponents (NCB/2=20 bytes), ordered left-to-right
	 * NPRESENCES=256/16=16 presence words (each longword is right-to-left)
	 * Variable number of 4-bit mantissas, 0s squeezed out, right-to-left
	 * Possibly an extra byte to achieve short alignment (for DSP)
	 */
	
#ifdef MAGIC
	ba_write(&magic,MAGIC_SIZE,outPtrP);
#endif

#ifdef SEQUENCE_HACK	
	fprintf(stderr,"\nframe %d:",frameNumber);
	*(*outPtrP)++ = frameNumber & 0xFF;
#else
	frameSizeInBytes = 0;	/* updated below */
	*(*outPtrP)++ = frameSizeInBytes;
#endif
	*(*outPtrP)++ = frameExponent;
	ba_write(exponentsP,NCB>>1,outPtrP);
	for (i = 0; i < NPRESENCES; i++)
	    presencesP[i] = NXSwapHostShortToBig(presencesP[i]);
	ba_write(presencesP,NPRESENCES<<1,outPtrP);
	for (i = 0; i < nMantissas>>1; i++)
	    ((unsigned short *)mantissasP)[i] =
		NXSwapHostShortToBig(((unsigned short *)mantissasP)[i]);
	ba_write(mantissasP,nMantissas,outPtrP);
	frameSizeInBytes = *outPtrP - savedOutPtr;
#ifdef DEBUG
	if ( (*outPtrP - savedOutPtr) > 255) {
	    fprintf(stderr,"*** frame size exceeded 255.\n");
	    exit(1);
	}
#endif

#ifndef SEQUENCE_HACK	
#ifdef MAGIC
	*(savedOutPtr + MAGIC_SIZE) = frameSizeInBytes;
#else
	*savedOutPtr = frameSizeInBytes;
#endif
#endif SEQUENCE_HACK

#ifdef DEBUG
	if (frameSizeInBytes*8 != 
	    (
#ifdef MAGIC
	     16 + /* magic number */
#endif
	     8 /* frame size in bytes */
	     + 8 /* peak level (frameExponent) */
	     + 16 * NPRESENCES
	     + 4 * NCB
	     + 8 * nMantissas))
	  fprintf(stderr,"*** frame size is confused.\n");
/* 	fprintf(stderr,"%.1f ",
		((double)(nspec-1)*16.0)/(((double)frameSizeInBytes)*8.0)); */
#endif
    }
}

/*
 * --------------------------- atcCompressFrame -----------------------------
 */
static void atcCompressFrame(int dataSize,short *inPtr, 
			     byte **outPtrP, int chans)
{
    static DATA_TYPE fftBuf[FRAME_SIZE];
    static DATA_TYPE dnzBuf[FRAME_SIZE];
    int i,crud;

    for (i=0; i<chans; i++) {
	/* Load FFT buffer from input frame */
	if (chans == 1)
	  copyDATA_TYPEsFromShorts(fftBuf,inPtr,dataSize);
	else
	  copyDATA_TYPEsFromInterleavedShorts(fftBuf,inPtr+i,chans,dataSize);

	crud = FRAME_SIZE - dataSize;
	if (crud != 0)
	  zeroDATA_TYPEs(fftBuf+dataSize,crud);

	PLOT(fftBuf,FRAME_SIZE,"buffer");

	applyWindow(fftBuf,FRAME_SIZE);
	
	PLOT(fftBuf,FRAME_SIZE,"windowedBuffer");
	
#if FFT_TEST
	fft_hermitian(fftBuf, FRAME_SIZE);
	fft_inverse_hermitian(fftBuf, FRAME_SIZE);
#else
	
#if !SLOW_TEST
	fft_hermitian(fftBuf, FRAME_SIZE);
#endif
	
	PLOT(fftBuf,FRAME_SIZE,"hfft");

	if (frameNumber & 1) {
	    DCT(dnzBuf,fftBuf,FRAME_SIZE);
	    PLOT(dnzBuf,NSPEC,"hfftdct");
	} else {
	    DST(dnzBuf,fftBuf,FRAME_SIZE);
	    PLOT(dnzBuf,NSPEC,"hfftdst");
	}
	
#ifndef LIBSYS_VERSION

	if (writeMax) {
	    int i;
	    double m;
	    for (i=0;i<NSPEC;i++) {
		m = fabs(DATA_TO_DOUBLE(dnzBuf[i]));
		if (m > maxSpec[i])
		  maxSpec[i] = m;
	    }
	}
	
	if (useThreshFile) {
	    int i;
	    double m;
	    for (i=0;i<NSPEC;i++) {
		m = abs(DATA_TO_DOUBLE(dnzBuf[i]));
		if (m < thresh[i])
		  dnzBuf[i] = 0;
	    }
	}
#endif
	dnzBuf[NSPEC-1] = 0;	/* Make sure it's really 0 */
	atcCompressSpectrum(dnzBuf,NSPEC,outPtrP);

#endif
    }

    frameNumber++;
}

/*
 * ------------------------- atcCompressByteArray ----------------------------
 */
static int atcCompressByteArray(short *inPtr, byte **outPtrP, 
				boolean_t firstBlock, 
				SNDSoundStruct *inputSound)
{
    int inSampleCount = inputSound->dataSize/2;
    short *inFramePtr;
    byte *savedOutPtr=0;
    int sizeDone=0;
    int chans = inputSound->channelCount;
    int stepSize = FRAME_STEP * chans;
    int dataSize;

#if __LITTLE_ENDIAN__
    inFramePtr=inPtr;
    for (sizeDone=0; sizeDone < inSampleCount; sizeDone++)
      *inFramePtr++ = NXSwapShort(*inFramePtr);
#endif __LITTLE_ENDIAN__

    /* This strange custom of writing the subheader at this level is relied
       upon by libsound:black_boxes.c (and compress.c, performsound.c) */
    if (firstBlock) {
	SNDCompressionSubheader subheader;
	subheader.originalSize = inputSound->dataSize;
	subheader.method = SND_CFORMAT_ATC;
	subheader.numDropped = 0;
	subheader.encodeLength = 0;
	subheader.reserved = 0;
	savedOutPtr = *outPtrP;
	ba_write(&subheader,sizeof(SNDCompressionSubheader),outPtrP);
    }

    /* 
     * Compress each frame of the input signal 
     */
    for (sizeDone=0, inFramePtr=inPtr;
	 sizeDone < inSampleCount; 
	 sizeDone += stepSize, inFramePtr += stepSize)
    {
	dataSize = MIN(FRAME_SIZE,(inSampleCount-sizeDone));
#if 0
        if (sizeDone == 0)
	  fprintf(stderr,"ATC compression in C...");
	if ((((sizeDone+1)/stepSize)%(44100/FRAME_SIZE))==0)
	  fprintf(stderr,".");
#endif
        atcCompressFrame(dataSize,inFramePtr,outPtrP,chans);
    }

#ifdef DEBUG
    sizeDone = (*outPtrP)-savedOutPtr; 
    if (sizeDone & 1)
      fprintf(stderr,"*** odd number of bytes computed!");
#endif DEBUG

    return (*outPtrP)-savedOutPtr;
}


#ifdef TEST_PROGRAM
/*
 * --------------------------- atcCompressSound ------------------------------
 */
/*
 * atcCompressSound
 *	Apply a "black box" to the input sound
 *	in the frequency domain and write results to the output sound.
 */

static unsigned char *data_pointer(SNDSoundStruct *s)
{
    unsigned char *p = (unsigned char *)s;
    p += s->dataLocation;
    return p;
}

static int atcCompressSound(SNDSoundStruct *inputSound, 
			    SNDSoundStruct **outputSoundP)
{
    SNDSoundStruct *outputSound;
    byte *outPtr;
    int bytesDone=0;
    int headerSize = inputSound->dataLocation;
    short *inPtr,*sp;
    int i,offset;

    SNDCopySound(outputSoundP,inputSound); /* uses vm_copy() */
    outputSound = *outputSoundP;
    outPtr = ((byte *)outputSound)+outputSound->dataLocation;

    inPtr = (short *)inputSound; /* header not skipped for DMA w/o copy */
    offset = headerSize;	/* shorts */
    for (i=0,sp=inPtr;i<offset;i++)
      *sp++ = 0;		/* zero header and process it as signal */

    bytesDone = atcCompressByteArray(inPtr, &outPtr, TRUE, outputSound);
    
    outputSound->dataFormat = SND_FORMAT_COMPRESSED;
    outputSound->dataSize = bytesDone; /* includes header */
    return 0;
}

/*
 * --------------------------------- main ------------------------------------
 */
void main(int argc, char *argv[])
{
    SNDSoundStruct	*inputSound,		*outputSound;
    char		*inputSoundFile,	*outputSoundFile;

    /* Check arguments */
    programName = argv[0];

    while (--argc && **(++argv) == '-') {
	switch (*(++(argv[0]))) {
	case 't':
	    sscanf(*(++argv),"%lf",&thresholdShift);
	    if (thresholdShift < -100.0)
	      thresholdShift = -100.0;
	    if (thresholdShift > 100.0)
	      thresholdShift = 100.0;
	    exponentShift = round(thresholdShift/(20.0*log10(2.0)));
	    thresholdShift = 20.0*log10(pow(2.0,exponentShift));
	    fprintf(stderr,"Threshold shift set to %f dB\n", thresholdShift);
	    break;
	case 'b':
	    sscanf(*(++argv),"%lf",&bandWidth);
	    if (bandWidth < 0.0)
	      bandWidth = 0;
	    if (bandWidth > 0.5)
	      bandWidth = 0.5;
	    binWidth = round(bandWidth * ((double)FRAME_SIZE));
	    bandWidth = binWidth / ((double)FRAME_SIZE);
	    fprintf(stderr,"Normalized Bandwidth set to "
		    "%f cycles\n", 
		    bandWidth);
	    break;
	case 'h':
	    sscanf(*(++argv),"%lf",&highPass);
	    if (highPass < 0.0)
	      highPass = 0;
	    if (highPass > 0.5)
	      highPass = 0.5;
	    lowBin = round(highPass * ((double)FRAME_SIZE));
	    highPass = lowBin / ((double)FRAME_SIZE);
	    fprintf(stderr,"Normalized highpass frequency set to "
		    "%f cycles\n", 
		    highPass);
	    break;
	case 'm': {
	    int i;
	    writeMax = 1;
	    sscanf(*(++argv),"%lf",&maxMag);
	    if (maxMag <= 0.0)
	      maxMag = 1.0;
	    fprintf(stderr,
		    "Writing %f times maximum spectral magnitude\n", maxMag);
	    for (i=0;i<NSPEC;i++)
	      maxSpec[i] = 0.0;
	    break;
	}
	case 'f': {
	    int i;
	    FILE *fp;
	    useThreshFile = 1;
	    sscanf(*(++argv),"%s",&threshFile);
	    fprintf(stderr,"Using threshold file '%s'\n",threshFile);
	    fp = fopen(threshFile,"r");
	    for (i=0;i<NSPEC;i++)
	      fscanf(fp,"%lf\n",&(thresh[i]));
	    break;
	}
	default:
	    fprintf(stderr,"Unknown switch -%s\n",*argv);
	    exit(1);
	}
    }

    if (argc < 2) {
        fprintf(stderr, "Usage: %s [-t threshDB] [-h HPFc/Fs] [-l LPFc/Fs]"
		" [-m] [-f threshFile] <inputSoundFile> <outputSoundFile>\n",
	        programName);
	exit(1);
    }
    inputSoundFile  = argv[0];
    outputSoundFile = argv[1];
    	
    /* Read sound file */
    if (soundError = SNDReadSoundfile(inputSoundFile, &inputSound))
      soundErrorExit();

    if (atcCompressSound(inputSound, &outputSound)) {
	fprintf(stderr," *** aborted.  Can't ATC compress this format.\n");
	exit(1);
    }

    if (SNDWriteSoundfile(outputSoundFile,outputSound) != SND_ERR_NONE)
      fprintf(stderr,"Could not write output soundfile '%s'\n",
	      outputSoundFile);

    fprintf(stderr," done.\n");

    if (writeMax) {
	int i;
	FILE *fp;
	char *fileName = "threshold";
	fprintf(stderr,"Writing file %s ... ",fileName);
	fp = fopen(fileName,"w");
	if (fp == NULL)
	  fp = stderr;
	for (i=0;i<NSPEC;i++)
	  fprintf(fp,"%10.7f\n",maxMag*maxSpec[i]);
	fclose(fp);
	fprintf(stderr,"done.\n");
    }
}

#endif
