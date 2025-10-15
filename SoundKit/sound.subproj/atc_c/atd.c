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
/* atd.c - Transform Decoder.
 *
 *	Currently supports only SND_FORMAT_LINEAR_16.
 *	If the sound is multi-channel, only the first channel is filtered
 *	and the outputs sound is mono.
 *
 *	Usage:  atc <inputSoundFile> <outputSoundFile>
 *
 *	Reference: 	J. P. Princen and A. B. Bradley, 
 *			"Analysis/Synthesis Filter Bank Design Based on
 *			Time Domain Aliasing Cancellation,"
 *			IEEE ASSP-34#5, Oct. 1986, pp. 1153-1161.
 */

#import "datatype.h"
#import "atc.h"
//#import "cb.h"
#import <cb.h>
#import <architecture/byte_order.h>

/*
 *  Globals
 */

/*** FIXME: Want synchronization to work in 3.1 ***/
#ifndef LIBSYS_VERSION
static double playingSpeed = 1.0;
static int normalTime = 0;
static int desiredTime = 0;
static int playedTime = 0;
static int timeIndicator = 0;	/* (-) if running behind, (+) if ahead */
#endif

/*
 * ------------------------------ Utilities ----------------------------------
 */

#import "atc_globals.c"
#import "hfft.c"
#import "static_utilities.c"
#import "unquantization.c"

/*
 * ---------------------------- processSpectrum ------------------------------
 */

static void processSpectrum(DATA_TYPE *spec, byte **inPtr, 
			    int frameNumber, int frameSizeOut)
{
    int i;
    int nspec = (frameSizeOut>>1)+1; /* NSPEC = (FRAME_SIZE>>1)+1 */
    byte *sip = *inPtr;
    byte *ip = *inPtr;
    int frameLengthInBytes;
    unsigned short *presencesPtr;
    unsigned short *mantissasPtr;
    int numMantissas;

#ifdef MAGIC
    unsigned short s;
    s = *((unsigned short *)ip)++;
    if (s != ATC_MAGIC) {
#if DEBUG
        fprintf(stderr,"Frame %d has bad magic number = 0x%X\n",
		frameNumber,s);
#endif
	for (i=0;i<FRAME_SIZE/2;i++) /* try to resynch */
	  if (*((unsigned short *)ip)++ == ATC_MAGIC)
	    break;
    }      
#endif

    frameLengthInBytes = *ip++;
    frameExponent = *ip++;

    if (frameExponent >= MAX_FRAME_EXPONENT) { /* silent frame */
	int i;
	for (i=0; i<nspec; i++)
	  spec[i] = 0;
	*inPtr = ip;
	return;
    }

    unpackExponents(exponents,ip,NCB); /* FIXME: may need not unpack all */
    PLOT_HEX(exponents,NCB,"exponentsUP");
    ip += (NCB>>1);

    presencesPtr = (short *)ip;
    for (i = 0; i < NPRESENCES; i++)
	presencesPtr[i] = NXSwapBigShortToHost(presencesPtr[i]);
    ip += NPRESENCES*sizeof(short);

    mantissasPtr = (unsigned short *)ip;
    numMantissas = frameLengthInBytes - 2 - (NCB>>1) - (NPRESENCES<<1);
    for (i = 0; i < numMantissas>>1; i++)
	mantissasPtr[i] = NXSwapBigShortToHost(mantissasPtr[i]);

#ifndef MANTISSAS_FIXED
    createMantissaSizes(mantissaSizes,exponents,presencesPtr);
    ip = unpackFixedMantissas(ispec,ip,presencesPtr,mantissaSizes,nspec);
#else
    ip = unpackMantissas(ispec,ip,presencesPtr,mantissaSizes,nspec);
#endif

    PLOT_HEX(ispec,nspec,"mantissasUP");

#ifdef DEBUG
    if (((ip - *inPtr) != frameLengthInBytes) && (frameSizeOut==FRAME_SIZE))
      fprintf(stderr,"Frame %d has bad frame bytecount = %d! "
	      "Found %d bytes\n",
	      frameNumber,frameLengthInBytes,(int)(ip - *inPtr));
#endif
    
    *inPtr = sip + frameLengthInBytes; /* advance to next frame */

    /*
     * Denormalize.
     */
    for (i=0; i<NCB; i++) {
	int w,*p;
	int ndx = cbLo[i];
	if (ndx >= nspec)
	  break;
	p = &(ispec[ndx]);
	w = cbWidth[i];
	rightShiftInts(p,w,exponents[i]+frameExponent);
    }
    PLOT_HEX(ispec,nspec,"ispecQ");

    /*
     * Convert back to DATA_TYPE.
     */
#if 0
    /* Old version */
    DATA_TYPEsFromInts(spec,ispec,nspec);
    scaleDATA_TYPEs(spec,(FRAME_SIZE/(pow(2,31)-1.0)),nspec);
    PLOT(spec,nspec,"specQ");
#else
    for (i=0; i<nspec; i++) {
	spec[i] = INT_LSHIFTED_TO_DATA(ispec[i],LG2_FRAME_SIZE);
    }
#endif

}

/*
 * ----------------------------- processFrame --------------------------------
 */
static DATA_TYPE fftBuf[FRAME_SIZE];
static DATA_TYPE dnzBuf[2*FRAME_SIZE];

static void processFrame(byte **inPtr ,short *outPtr, int frameNumber,
			 int frameSizeOut)
{
    DATA_TYPE scl;
    processSpectrum(dnzBuf,inPtr,frameNumber,frameSizeOut);

    if (frameNumber & 1)
      IDCT(fftBuf, dnzBuf, frameSizeOut);
    else
      IDST(fftBuf, dnzBuf, frameSizeOut);

    PLOT2(fftBuf,frameSizeOut,"invFFT");

    applyWindow(fftBuf,frameSizeOut);

    PLOT2(fftBuf,frameSizeOut,"windowedInvFFT");

    scl = DOUBLE_TO_DATA(2.0 * ((double)frameSizeOut)/((double)FRAME_SIZE));
    if (scl != DATA_ONE)
      scaleDATA_TYPEs(fftBuf,scl,frameSizeOut); /* comp. for 0.5 gain */

    /* Load output frame from FFT buffer */
    copyShortsFromDATA_TYPEs(outPtr,fftBuf,frameSizeOut);
}

static void processTwoFrames(byte **inPtr ,short *outPtr, int frameNumber,
			     int frameSizeOut)
{
    int i;
    DATA_TYPE scl;
    DATA_TYPE *c1 = dnzBuf;
    DATA_TYPE *c2 = dnzBuf + frameSizeOut;
    processSpectrum(c1,inPtr,frameNumber,frameSizeOut);
    processSpectrum(c2,inPtr,frameNumber,frameSizeOut);

    for (i=0; i<frameSizeOut; i++)
      *c1++ += *c2++;		/* Add stereo left and right channels */

    if (frameNumber & 1)
      IDCT(fftBuf, dnzBuf, frameSizeOut);
    else
      IDST(fftBuf, dnzBuf, frameSizeOut);

    PLOT2(fftBuf,frameSizeOut,"invFFT");

    applyWindow(fftBuf,frameSizeOut);

    PLOT2(fftBuf,frameSizeOut,"windowedInvFFT");

    /* Division by two relative to one-frame case is to avoid overflow
       in the worst-case stereo situation (same signal in L and R chans) */
    scl = DOUBLE_TO_DATA(((double)frameSizeOut)/((double)FRAME_SIZE));
    if (scl != DATA_ONE)
      scaleDATA_TYPEs(fftBuf,scl,frameSizeOut); /* comp. for 0.5 gain */

    /* Load output frame from FFT buffer */
    copyShortsFromDATA_TYPEs(outPtr,fftBuf,frameSizeOut);
}

/*
 * ------------------------- _ATCDecompressByteArray -------------------------
 */

static short *frameBuffer = 0;

static int _ATCDecompressByteArray(byte **inPtrP, short *outPtr,
				   int outBytes, int chans, 
				   int rateShift, int makeMono,
				   int *frameNumberP)
    /* 
     * rateShift == 1 for downsampling by 2.
     * rateShift == 2 for downsampling by 4.
     * if makeMono>0, stereo is converted to mono.
     * outBytes = total number of bytes to compute at UNSHIFTED rate.
     */
{
    int frameSizeOut = FRAME_SIZE >> rateShift;
    int frameStep = (FRAME_SIZE>>(1+rateShift));
    int overlapSize = frameStep;
    int sampleStep = ((FRAME_SIZE>>1) * (makeMono ? 1 : chans)) >> rateShift;
    int overlapSamples = sampleStep; /* FIXME: not adaptive */
    int outSamps,numFrames,stopFrame;
    int i,frameNumber = *frameNumberP;
    short *outFramePtr;
    
    if (!inited)
      initializeATD();

    outBytes >>= rateShift;
    if (makeMono && chans==2)
      outBytes >>= 1;
    outSamps = outBytes >> 1;
    numFrames = outSamps / sampleStep;
    stopFrame = frameNumber + numFrames;
    
    if (!frameBuffer) {
	/* Use vm_allocate() to get page alignment and initial zeros */
	vm_allocate(task_self(),
		    (pointer_t *)&frameBuffer,
		    FRAME_SIZE * sizeof(short),1);
    }
    
    outFramePtr=outPtr;

    for ( ; frameNumber<stopFrame; frameNumber++, outFramePtr+=sampleStep)
    {
	/* Because the desired number of output samples is passed as input,
	   and not the actual number of compressed input frames, the last
	   partial block is terminated by a zero frame size, hence the 
	   tests on **inPtrP below */
	if (**inPtrP == 0) {
	    numFrames = frameNumber - 1;
	    break;
	}
	if (chans==1) {
	    processFrame(inPtrP,frameBuffer,frameNumber,frameSizeOut);
	    addShortArrays(outFramePtr, frameBuffer, overlapSize);
	    copyShortArrays(outFramePtr+overlapSize,
			    frameBuffer+overlapSize,
			    frameStep);
	} else { /* stereo */
	    if (makeMono) {
		processTwoFrames(inPtrP,frameBuffer,frameNumber,frameSizeOut);
		addShortArrays(outFramePtr, frameBuffer, overlapSize);
		copyShortArrays(outFramePtr+overlapSize,
				frameBuffer+overlapSize,
				frameStep);
	    } else {
		for (i=0; i<chans; i++) {
		    /* atc_c/atd.c */
		    processFrame(inPtrP,frameBuffer,frameNumber,frameSizeOut);
		    addToInterleavedShortArray(outFramePtr+i, chans,
					       frameBuffer, overlapSize);
		    copyToInterleavedShortArray(outFramePtr+overlapSamples+i,
						chans,
						frameBuffer+overlapSize,
						frameStep);
		}
	    }
	}
#ifndef LIBSYS_VERSION
#if DEBUG
	if (frameNumber == 4)
	  writeShorts(outPtr,5*sampleStep,"ola");
#endif
#endif
    }
    outSamps = numFrames * sampleStep;
    outBytes = outSamps << 1;
    *frameNumberP = frameNumber;
#if __LITTLE_ENDIAN__
    for (i=0,outFramePtr=outPtr; i<outSamps; i++)
      *outFramePtr++ = NXSwapShort(*outFramePtr);
#endif
    return outBytes;
}

#ifdef TEST_PROGRAM

/*
 * ----------------------------- processTime --------------------------------
 */
static int processTime(void)
/* return 0 if time right on, >0 if need to drop samples, <0 if need to add */
{
    normalTime += FRAME_STEP;
    desiredTime = round(((double)normalTime)*playingSpeed);
    playedTime  = frameNumber * FRAME_STEP;
    timeIndicator = desiredTime - playedTime;
    return timeIndicator;
}

/*
 * ----------------------------- processSound --------------------------------
 */
/*
 * processSound
 *	Apply a "black box" to the input sound
 *	in the frequency domain and write results to the output sound.
 */

static void	processSound(SNDSoundStruct *inputSound,
			     SNDSoundStruct **outputSound, 
			     int rateShift, int makeMono)
{
    int		inputSize,inputBytes;
    int		outputSize,outputBytes;
    int		format   = inputSound->dataFormat;
    int		rate 	 = inputSound->samplingRate;
    int 	*inPtr;
    int		method;
    short 	*outPtr, *outFramePtr, *frameBuffer;
    SNDCompressionSubheader *subheader;
    int 	chans = inputSound->channelCount;
    int		sampleStep = FRAME_STEP * chans;
    int		overlapSamples = OVERLAP_SIZE * chans;

    inPtr  = (int *) ((char *) inputSound + inputSound->dataLocation);
    subheader = (SNDCompressionSubheader *)inPtr;
    ((char *)inPtr) += sizeof(SNDCompressionSubheader); /* now pts to data */
    
    inputBytes = subheader->originalSize;
    inputSize = inputBytes / sizeof(short); /* convert to samples */

    method = subheader->method;

    if ( method != SND_CFORMAT_ATC) {
        fprintf(stderr, "%s: incompatible format: "
		"Need ATC compressed format code 0x%X "
		"and found 0x%X\n",
		programName, SND_CFORMAT_ATC, method);
	exit(1);
    }

    inputSound->dataFormat = SND_FORMAT_LINEAR_16; /* for output */

    outputBytes = ceil(((double)inputBytes) / playingSpeed);
    outputBytes >>= rateShift; /* due to downsampling */
    outputBytes >>= makeMono;  /* due to stereo to mono conversion */
    outputSize = outputBytes / sizeof(short);;

    /* Allocate a new sound (uses vm_allocate() => data is pre-zeroed) */
    if (soundError = SNDAlloc(outputSound,outputBytes,format,rate,chans,4))
      soundErrorExit();
	
    outPtr = (short *) ((char *) *outputSound + (*outputSound)->dataLocation);

    if (machError != KERN_SUCCESS)
      machErrorExit();

    _ATCDecompressByteArray(&(byte *)inPtr, outPtr, 
			    outputBytes, chans, rateShift, makeMono,
			    &frameNumber);

    /* All sound signals should start and end at 0 amp to avoid driver ramp */
    *outPtr = *(outPtr+outputSize-1) = 0;
}

/*
 * --------------------------------- main ------------------------------------
 */
void main(int argc, char *argv[])
{
    SNDSoundStruct	*inputSound, 		*outputSound;
    char		*inputSoundFile,	*outputSoundFile;
    int rateShift = 0;
    int makeMono = 0;

    /* Check arguments */
    programName = argv[0];

    while (--argc && **(++argv) == '-') {
	switch (*(++(argv[0]))) {
	case 'f':
	    sscanf(*(++argv),"%d",&rateShift);
	    printf("setting rateShift = %d\n",rateShift);
	    break;
	case 'm':
	    printf("converting stereo to mono.\n");
	    makeMono = 1;
	    break;
	case 's':
	    fprintf(stderr,"Speed control not in this version\n");
	    exit(1);
	    /*** FIXME ***/
	    sscanf(*(++argv),"%lf",&playingSpeed);
	    if (playingSpeed < 0.1)
	      playingSpeed = 0.1;
	    if (playingSpeed > 10.0)
	      playingSpeed = 10.0;
	    fprintf(stderr,"Playing speed set to %f \n", playingSpeed);
	    break;
	default:
	    fprintf(stderr,"Unknown switch -%s\n",*argv);
	    exit(1);
	}
    }

    if (argc < 2) {
        fprintf(stderr, "Usage: %s "
		"<inputSoundFile> <outputSoundFile>\n",
	        programName);
	exit(1);
    }
    inputSoundFile  = argv[0];
    outputSoundFile = argv[1];
    	
    /* Read sound file */
    if (soundError = SNDReadSoundfile(inputSoundFile, &inputSound))
	soundErrorExit();
    /* Abort if unsupported format */
    if ( inputSound->dataFormat != SND_FORMAT_COMPRESSED) {
        fprintf(stderr, "%s: incompatible format: "
		"Need compressed format code 0x%X "
		"and found 0x%X\n",
		programName, SND_FORMAT_COMPRESSED, inputSound->dataFormat);
	exit(1);
    }
    inputSound->dataFormat = SND_FORMAT_LINEAR_16; /* for output */
    
    /* Filter by applying window in the frequency domain */
    processSound(inputSound, &outputSound, rateShift, makeMono);
    
    /* Write sound file */
    if (soundError = SNDWriteSoundfile(outputSoundFile, outputSound))
	soundErrorExit();

    fprintf(stderr," done.\n");
}
#endif
