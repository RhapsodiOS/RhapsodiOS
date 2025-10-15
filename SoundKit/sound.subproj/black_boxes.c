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
 * black_boxes.c
 *
 * Each procedure herein is called on a block by block basis from 
 * performsound.c (when converting and playing a sound on the fly),
 * or on the entire sound in one block from convertsound.c 
 * (when converting only).
 *
 * Only one black box thread is supported at a time, i.e., they
 * cannot be configured in cascade.  To combine two threads, make
 * a new composite version.
 *
 * Created for 3.0 by Julius Smith (jos@next)
 *
 * 02/11/93/jos - byte swaps for Lono
 * 03/15/94/rkd - fixed mulaw to 8-bit mono conversion
 * 03/15/94/rkd - added new threads for 16-bit to 8-bit and mulaw to 8-bit
 *		  (also stereo to mono versions.) 
 */


/* FIXME: This should be a separately compiled module with each function
   appearing in the libsys spec_sys file.  Currently, this file is included
   by performsound.c, and anything also used by convertsound gets exported
   via spec_sys.  Presently, the simple static conversion utilities below
   are duplicated in convertsound.c which wastes memory.  
   Consider an integer to index
   thread function below so that they can all be static in this context,
   and move black_box_thread() from performsound.c to here.  Need also
   the convertsound equivalent which takes the same int, defined in 
   black_boxes.h.
*/
#define LIBSYS_VERSION /* Flag to minimize ATC and resampling code */

#import <architecture/byte_order.h>
#ifdef DEBUG
#import <stdio.h>
#endif DEBUG
#import "_compression.h"
#import "mulaw.h"

/*** FIXME: This goes away when performsound.c can use mono stream to driver */
static int mono_to_stereo_thread(thread_args *targs)
{
    int i, nBytes = targs->inBlockSize;
    int n = nBytes / sizeof(short);
    short *src = targs->inPtr;
    short *dst = targs->outPtr;

    for (i=n; i; i--) {
        *dst++ = *src++;
    }

    targs->outBlockSize = n * sizeof(short);
    return 0;
}

static int float_to_soundout_thread(thread_args *targs)
{
    int i, n, nBytes = targs->inBlockSize;
    NXSwappedFloat *src = (NXSwappedFloat *)targs->inPtr;
    short *dst = targs->outPtr;
    float scale = 32768.0;

    n = nBytes / sizeof(float);
    for (i=n; i; i--)
      *dst++ = NXSwapHostShortToBig((short) scale 
                                    * NXSwapBigFloatToHost(*src++));
    targs->outBlockSize = n * sizeof(short);

    return 0;
}

static int double_to_soundout_thread(thread_args *targs)
{
    int i, n, nBytes = targs->inBlockSize;
    NXSwappedDouble *src = (NXSwappedDouble *)targs->inPtr;
    short *dst = targs->outPtr;
    double scale = 32768.0;

    n = nBytes / sizeof(double);
    for (i=n; i; i--) {
        *dst++ 
          = NXSwapHostShortToBig((short) scale 
                                 * NXSwapBigDoubleToHost(*src++));
    }
    targs->outBlockSize = n * sizeof(short);
    return 0;
}

typedef signed char linear8;

static int linear8_to_soundout_thread(thread_args *targs)
{
    int i, n, nBytes = targs->inBlockSize;
    linear8 *src = (linear8 *)targs->inPtr;
    short *dst = targs->outPtr;

    n = nBytes / sizeof(linear8);
    for (i=n; i; i--)
      *dst++ = NXSwapHostShortToBig((short) ((*src++)<<8));
    targs->outBlockSize = n * sizeof(short);
    return 0;
}

static int soundout_to_linear8_thread(thread_args *targs)
{
    int i, n, nBytes = targs->inBlockSize;
    short *src = (short *)targs->inPtr;
    linear8 *dst = (linear8 *)targs->outPtr;
    short tmp;

    n = nBytes / sizeof(short);
    for (i=n; i; i--)   {
      tmp = NXSwapBigShortToHost(*src);
      *dst = tmp >> 8;
      src++; dst++;
    }
    
    //targs->outBlockSize = n * sizeof(linear8);
    
    return 0;
}

static int stereo_8_mono_8_thread(thread_args *targs)
{
    int i, n = targs->inBlockSize;
    linear8 *src = (linear8 *)targs->inPtr;
    linear8 *dst = (linear8 *)targs->outPtr;

    n = n/ (2 * sizeof(linear8));
    
    for (i=n; i; i--)   {
      *dst = *src;
      src++; src++; dst++;
    }
    
    //targs->outBlockSize = n * sizeof(linear8); -- FIXME
    
    return 0;
}

static int soundout_to_mono_linear8_thread(thread_args *targs)
{
    int i, n = targs->inBlockSize;
    short *src = (short *)targs->inPtr;
    linear8 *dst = (linear8 *)targs->outPtr;
    short tmp;

    n = n / (2*sizeof(short));
    
    for (i=n; i; i--)   {
      tmp = NXSwapBigShortToHost(*src);
      *dst = tmp >> 8;
      src++; src++; dst++;
    }
    
    //targs->outBlockSize = n * sizeof(linear8);
    
    return 0;
}


/********************** CODEC playback support *************************/

/* formerly upsample.c (~dspdev/resample_proj/Avie_Richard).
   Upsampler utility for converting from 8013 Hz CODEC rate to 22050 Hz DAC 
   rate. The method used is sinc-table interpolation, with windowing
   and forward circulation.
   
   This is a self-contained 68040 upsampler test.  It should be
   equivalent to the Release 2.0/2.1 DSP upsampler.
   
   Compile with:
   > cc -O upsample.c -o upsample
   
   and play CODEC files via:
   
   > upsample file.snd
   
   Change N_BUF to taste to optimize buffer size.
   
   R. E. Crandall, Scientific Computation Group, NeXT, Inc.
   c 1991 NeXT Computer, Inc.  All Rights Reserved.
 */

#import <stdio.h>
#import <math.h>

#ifndef LIBSYS_VERSION
#import <SoundKit/sound.h>
#endif

#define NUM 4
#define DEN 11   /* The upsampling ratio is DEN/NUM;
                    e.g. the present case corresponds to
                    NUM/DEN ~= 8012.82/22050.  The accuracy
                    of this rational approximation 4/11 is 0.1 per cent.
                    */
#define N_BUF (8192*4)  /* Change this buffer size to optimize system
                           synchronization and/or safety margin. */
#ifndef PI
#define PI ((double)(3.1415926535897932384626433))
#endif

#define SCALE 4096
#define SHIFT   12      /* goes hand in hand with SCALE */
#define NUM_COEFFS 11

typedef unsigned char mulaw;

#ifndef LIBSYS_VERSION
static const short muLaw[256] = {
    0x8284, 0x8684, 0x8a84, 0x8e84, 0x9284, 0x9684, 0x9a84, 0x9e84, 
    0xa284, 0xa684, 0xaa84, 0xae84, 0xb284, 0xb684, 0xba84, 0xbe84, 
    0xc184, 0xc384, 0xc584, 0xc784, 0xc984, 0xcb84, 0xcd84, 0xcf84, 
    0xd184, 0xd384, 0xd584, 0xd784, 0xd984, 0xdb84, 0xdd84, 0xdf84, 
    0xe104, 0xe204, 0xe304, 0xe404, 0xe504, 0xe604, 0xe704, 0xe804, 
    0xe904, 0xea04, 0xeb04, 0xec04, 0xed04, 0xee04, 0xef04, 0xf004, 
    0xf0c4, 0xf144, 0xf1c4, 0xf244, 0xf2c4, 0xf344, 0xf3c4, 0xf444, 
    0xf4c4, 0xf544, 0xf5c4, 0xf644, 0xf6c4, 0xf744, 0xf7c4, 0xf844, 
    0xf8a4, 0xf8e4, 0xf924, 0xf964, 0xf9a4, 0xf9e4, 0xfa24, 0xfa64, 
    0xfaa4, 0xfae4, 0xfb24, 0xfb64, 0xfba4, 0xfbe4, 0xfc24, 0xfc64, 
    0xfc94, 0xfcb4, 0xfcd4, 0xfcf4, 0xfd14, 0xfd34, 0xfd54, 0xfd74, 
    0xfd94, 0xfdb4, 0xfdd4, 0xfdf4, 0xfe14, 0xfe34, 0xfe54, 0xfe74, 
    0xfe8c, 0xfe9c, 0xfeac, 0xfebc, 0xfecc, 0xfedc, 0xfeec, 0xfefc, 
    0xff0c, 0xff1c, 0xff2c, 0xff3c, 0xff4c, 0xff5c, 0xff6c, 0xff7c, 
    0xff88, 0xff90, 0xff98, 0xffa0, 0xffa8, 0xffb0, 0xffb8, 0xffc0, 
    0xffc8, 0xffd0, 0xffd8, 0xffe0, 0xffe8, 0xfff0, 0xfff8, 0x0, 
    0x7d7c, 0x797c, 0x757c, 0x717c, 0x6d7c, 0x697c, 0x657c, 0x617c, 
    0x5d7c, 0x597c, 0x557c, 0x517c, 0x4d7c, 0x497c, 0x457c, 0x417c, 
    0x3e7c, 0x3c7c, 0x3a7c, 0x387c, 0x367c, 0x347c, 0x327c, 0x307c, 
    0x2e7c, 0x2c7c, 0x2a7c, 0x287c, 0x267c, 0x247c, 0x227c, 0x207c, 
    0x1efc, 0x1dfc, 0x1cfc, 0x1bfc, 0x1afc, 0x19fc, 0x18fc, 0x17fc, 
    0x16fc, 0x15fc, 0x14fc, 0x13fc, 0x12fc, 0x11fc, 0x10fc, 0xffc, 
    0xf3c, 0xebc, 0xe3c, 0xdbc, 0xd3c, 0xcbc, 0xc3c, 0xbbc, 
    0xb3c, 0xabc, 0xa3c, 0x9bc, 0x93c, 0x8bc, 0x83c, 0x7bc, 
    0x75c, 0x71c, 0x6dc, 0x69c, 0x65c, 0x61c, 0x5dc, 0x59c, 
    0x55c, 0x51c, 0x4dc, 0x49c, 0x45c, 0x41c, 0x3dc, 0x39c, 
    0x36c, 0x34c, 0x32c, 0x30c, 0x2ec, 0x2cc, 0x2ac, 0x28c, 
    0x26c, 0x24c, 0x22c, 0x20c, 0x1ec, 0x1cc, 0x1ac, 0x18c, 
    0x174, 0x164, 0x154, 0x144, 0x134, 0x124, 0x114, 0x104, 
    0xf4, 0xe4, 0xd4, 0xc4, 0xb4, 0xa4, 0x94, 0x84, 
    0x78, 0x70, 0x68, 0x60, 0x58, 0x50, 0x48, 0x40, 
    0x38, 0x30, 0x28, 0x20, 0x18, 0x10, 0x8, 0x0
  };
#endif

#define S(x)    ((x)*SCALE)

/* static short ftable[((NUM_COEFFS+1)/2)*DEN+1]; */
static const short ftable[] = {
    S(0.980690769),
    S(0.966887889),
    S(0.926211872),
    S(0.860812276),
    S(0.774114228),
    S(0.670594562),
    S(0.555492041),
    S(0.434472982),
    S(0.313276621),
    S(0.197365637),
    S(0.091606308),
    S(0.000000000),
    S(-0.074516770),
    S(-0.130192090),
    S(-0.166493050),
    S(-0.184056148),
    S(-0.184561390),
    S(-0.170543097),
    S(-0.145154685),
    S(-0.111907211),
    S(-0.074402469),
    S(-0.036080616),
    S(0.000000000),
    S(0.031336749),
    S(0.056100818),
    S(0.073194980),
    S(0.082251580),
    S(0.083575947),
    S(0.078044416),
    S(0.066969021),
    S(0.051942610),
    S(0.034678585),
    S(0.016858635),
    S(0.000000000),
    S(-0.014648880),
    S(-0.026178693),
    S(-0.034053311),
    S(-0.038108637),
    S(-0.038520185),
    S(-0.035745670),
    S(-0.030450333),
    S(-0.023423484),
    S(-0.015494560),
    S(-0.007456153),
    S(0.000000000),
    S(0.006329910),
    S(0.011164987),
    S(0.014320325),
    S(0.015785312),
    S(0.015699667),
    S(0.014319006),
    S(0.011974525),
    S(0.009031366),
    S(0.005849778),
    S(0.002752407),
    S(0.000000000),
    S(-0.002223295),
    S(-0.003814969),
    S(-0.004750427),
    S(-0.005072164),
    S(-0.004873979),
    S(-0.004282584),
    S(-0.003438900),
    S(-0.002481025),
    S(-0.001530403),
    S(-0.000682165),
    S(0.000000000),
    S(0.000484624),
    S(0.000769502),
    S(0.000875975),
    S(0.000841550),
    S(0.000712003),
};
#undef S

#ifndef LIBSYS_VERSION
static void make_sinc_table(int n)
    /* Alternative form for sinc() table. */
{
#if     0
    int j;
    int last;
    ftable[0] = SCALE;
    last = ((NUM_COEFFS+1)/2)*n;
    for (j = 1; j <= last; j++) {
        ftable[j] = (n*sin((PI*j)/n)/(PI*j))*SCALE;
    }
#endif  0
}
#endif

#define MAX_CHANS 2
static int *fsmidptr[MAX_CHANS]; /* points to middle of filter state ("now") */
static int ftime[MAX_CHANS];     /* filter time relative to output time */
static int fstate[MAX_CHANS][NUM_COEFFS]; /* filter state */

void _snd_init_upsamplecodec_thread(void) {
    int c,n;
    for (c = 0; c < MAX_CHANS; c++) {
        for (n = 0; n < NUM_COEFFS; n++)
          fstate[c][n] = 0;
        fsmidptr[c] = &fstate[c][NUM_COEFFS/2];
        ftime[c] = -(NUM_COEFFS/2); /* point at left most point */
    }
}

static void _snd_upsamplecodec_channel(mulaw *inPtr,
                                      short *outPtr,
                                      int nChans,
                                      int inCount,
                                      int outCount,
                                      int *fsmidptr,
                                      int ftime,
                                      int *fstate)
{
    register int n,val;
    register int *p,*dst;
    register const short *fptr; /* filter table pointer */
#ifdef DEBUG
    short *outPtrSave = outPtr;
    mulaw *inPtrSave = inPtr;
#endif

    for (n = 0; n < outCount; n++) {
        p = fstate;
        if (ftime == 0)
          val = *fsmidptr << SHIFT;
        else {
            /* following code is dependent on NUM_COEFFS */
            /* do points on the right. */
            fptr = &ftable[5*DEN-ftime];
            val  = *p++ * *fptr; fptr -= DEN; /* 5*DEN - ftime */
            val += *p++ * *fptr; fptr -= DEN; /* 4*DEN - ftime */
            val += *p++ * *fptr; fptr -= DEN; /* 3*DEN - ftime */
            val += *p++ * *fptr; fptr -= DEN; /* 2*DEN - ftime */
            val += *p++ * *fptr;                  /* 1*DEN - ftime */
            /* skip middle                      /@ 1*DEN - ftime */
            p++;
            /* do points on the left. */
            fptr = &ftable[DEN+ftime];
            val += *p++ * *fptr; fptr += DEN; /* 1*DEN + ftime */
            val += *p++ * *fptr; fptr += DEN; /* 2*DEN + ftime */
            val += *p++ * *fptr; fptr += DEN; /* 3*DEN + ftime */
            val += *p++ * *fptr; fptr += DEN; /* 4*DEN + ftime */
            val += *p++ * *fptr;                  /* 5*DEN + ftime */
            if (ftime < 0)
              val += *fsmidptr * ftable[-ftime];
            else
              val += *fsmidptr * ftable[ftime];
        }
        val >>= SHIFT;
        if (val > 32767)
          val = 32767;
        if (val < -32767)
          val = -32767;
        *outPtr = NXSwapHostShortToBig(val);
        outPtr += nChans;
        ftime += NUM;
        if (ftime > (DEN/2)) {
            ftime -= DEN;
            dst = fstate + (NUM_COEFFS-1);
            p = dst - 1;
            *dst-- = *p--;      /* NUM_COEFFS -1 of these!!! */
            *dst-- = *p--;
            *dst-- = *p--;
            *dst-- = *p--;
            *dst-- = *p--;
            *dst-- = *p--;
            *dst-- = *p--;
            *dst-- = *p--;
            *dst-- = *p--;
            *dst-- = *p--;
            *dst = muLaw[*inPtr];
            inPtr += nChans;
        }
    }
#ifdef DEBUG
    if ((inPtr-inPtrSave) != inCount*nChans)
      fprintf(stderr,"*** _snd_upsamplecodec_thread: " 
              "consumed %d instead of %d input samples\n",
              (int)(inPtr-inPtrSave),inCount*nChans );
    if (((outPtr - outPtrSave)) != outCount*nChans)
      fprintf(stderr,"*** _snd_upsamplecodec_thread: " 
              "computed %d instead of %d input samples\n",
              (int)(outPtr-outPtrSave),outCount*nChans );
#endif
}

int _snd_upsamplecodec_thread(thread_args *targs) 
{
    mulaw *inPtr = (mulaw *)targs->inPtr; /* input data pointer */
    short *outPtr = targs->outPtr; /* output data pointer */
    int chan, nChans = targs->sound->channelCount;
    int inCountPerChan = targs->inBlockSize / nChans; /* #samples / channel */
    int outCountPerChan = inCountPerChan * 11 / 4;

    targs->outBlockSize = outCountPerChan * 2 * nChans; /* 8b -> 16b */

#if DEBUG
    if(targs->outBlockSize > targs->outBlockSizeMax)
      fprintf(stderr,"_snd_upsamplecodec_thread: allocation error\n");
    if (nChans != 1 && nChans != 2) {
        fprintf(stderr,"_snd_upsamplecodec_thread: channelCount not 1 or 2\n");
        exit(1);
    }
#endif

    for (chan=0; chan<nChans; chan++)
      _snd_upsamplecodec_channel(inPtr+chan, outPtr+chan, nChans,
                                 inCountPerChan, outCountPerChan,
                                 fsmidptr[chan], ftime[chan], fstate[chan]);
    return 0;
}


#ifdef TEST_PROGRAM
void main(int argc, char **argv)
{
    SNDSoundStruct *cod_sound, *ste_sound;
    mulaw *cod_sig;
    short *ste_sig;

    int todo, lim, err, bufCount, inCount, outCount;
    if(argc<2) {
        fprintf(stderr,"Usage:\nupsample file.snd\n");
        exit(0);
    }
    err = SNDReadSoundfile(argv[1], &cod_sound);
    if (err) {
        fprintf(stderr,"*** Could not read input file '%s'\n",argv[1]);
        exit (1);
    }
    cod_sig = (mulaw *)cod_sound; 
    cod_sig += (cod_sound->dataLocation);

    SNDAlloc(&ste_sound, 2*sizeof(short)*N_BUF, SND_FORMAT_LINEAR_16,
             SND_RATE_LOW, 2, 0);
    ste_sig = (short *)((char *)ste_sound + ste_sound->dataLocation);

    todo = (DEN*(cod_sound->dataSize-1))/NUM;
    bufCount = 1;
    lim = N_BUF;
    make_sinc_table(DEN);
    _snd_init_upsamplecodec_thread();
    while(todo>0) {
        if (todo<N_BUF) {
            lim = todo; /* last loop */
            ste_sound->dataSize = 2*lim*sizeof(short);
        }
        
        inCount = NUM * (lim-1) / DEN;
        outCount = _snd_upsamplecodec_thread(cod_sig,ste_sig,inCount,lim);
        if (outCount != lim) {
            fprintf(stderr,"*** upsamplecodec returned %d "
                    "instead of %d samples\n", outCount, lim);
            ste_sound->dataSize = 2*outCount*sizeof(short);
        }
        cod_sig += inCount;

        SNDStartPlaying(ste_sound, bufCount, 0, 0, NULL, NULL);
        /* printf("bufCount = %d\n", bufCount); */
        if (bufCount > 1)
          SNDWait(bufCount-1);  /* queue max of two buffers */
        /* this means the driver has one */
        /* and we've queued one */
        /* we need to do this to prevent */
        /* the buffer from being clobbered */
        /* since we are using the same buffer */
        bufCount++;
        todo -= lim;
    }
    SNDWait(0);
    ste_sound->dataSize = 2*N_BUF*sizeof(short);
}
#endif LIBSYS_VERSION


/*********************************************************************/

#ifdef DEBUG
//#warning high quality sampling-rate conversion in C not yet integrated for NRW
#endif

#if 0
#include "resample/resamplesubs_libsys.h" 
/* assumed done by performsound.c and convertsound.c ? */
#endif

#ifdef DEBUG
static int pof,nof;             /* overflow counts */
#endif

static INLINE short intToshort(int v, int scl)
{
#define MAX_SHORT (32767)
#define MIN_SHORT (-32768)
    short out;
    int llsb = (1 << (scl-1));
    if (v & llsb)
      v += llsb;                /* round */
    v >>= scl;
    if (v>MAX_SHORT) {
#ifdef DEBUG
        if (pof == 0)
          fprintf(stderr, "*** libsound: resample: sound sample overflow\n");
        else if ((pof % 10000) == 0)
          fprintf(stderr, "*** libsound: resample: "
                  "another ten thousand overflows\n");
        pof++;
#endif
        v = MAX_SHORT;
    } else if (v < MIN_SHORT) {
#ifdef DEBUG
        if (nof == 0)
          fprintf(stderr, "*** resample: sound sample (-) overflow ***\n");
        else if ((nof % 1000) == 0)
          fprintf(stderr, "*** resample: another thousand (-) overflows **\n");
        nof++;
#endif
        v = MIN_SHORT;
    }   
    out = (short) v;
    return out;
#undef MAX_SHORT
#undef MIN_SHORT
}

static int resample_thread(thread_args *targs)
/*
 * Perform sampling-rate conversion on one block of sound data.
 * The total number of output bytes is returned in targs->outBlockSize.
 * The output is stereo irrespective of the input channel count.
 *
 * parameters[0] == (float) sampling_rate_conversion_factor
 * parameters[1] == (int) 0 for full quality, 1 for "fast mode"
 */
{
    int n, nBytes = targs->inBlockSize;
    int nc = targs->sound->channelCount;
    short *src0 = targs->inPtr;
    short *src = src0;
    short *dst = targs->outPtr;
    float factor = ((float *)targs->parameters)[0];
#ifdef  DEBUG
    int fastMode = ((int *)targs->parameters)[1];
#endif  DEBUG
    static short prevSamp1,prevSamp2;
    short interpConst,s;
    int v,x1,x2,x1s,x2s,y1,y2,outSamps;
    double dt;                  /* Step through input signal */ 
    static int dtb;             /* Fixed-point version of Dt */
    static int t,time;
    int endTime;                /* When time reaches endTime, block is done */
#define Np 15                   /* Number of fractional bits in time */
    static int Pmask = ((1<<Np)-1); /* Fractional bits mask */
    

    if (targs->firstBlock) {
        prevSamp1 = 0;          /* from previous block processed */
        prevSamp2 = 0;
        time = 0;               /* from previous block processed */
        dt = 1.0/factor;        /* output sampling period */
        dtb = dt*(1<<Np) + 0.5; /* Fixed-point delta T */
    }

#ifdef DEBUG
    if (!fastMode)
      fprintf(stderr,"*** libsound: resample_thread: "
              "high quality real-time sampling-rate conversion in C "
              "not implemented\n");
    /* If soundout underruns on the stereo case, 
       consider summing stereo to mono before rate conversion. */
#endif

    n = nBytes / sizeof(short) / nc; /* samples per input channel */

    endTime = ((n-1)<<Np); /* available time is 0 to n-1 samples */
        
    switch (nc) {
/*
 * MONO sampling rate conversion by linear interpolation.
 */
    case 1:
        x1s = prevSamp1; /* left sample */
        x2s = (short)NXSwapBigShortToHost(*src);         /* right sample */
        while (time < 0)
        {
            interpConst = time & Pmask; 
            x1 = x1s * ((1<<Np)-interpConst); /* do linear interpolation */
            x2 = x2s * interpConst;
            v = x1 + x2;                /* linear interpolation */
            s = intToshort(v,Np);       /* Deposit output */
            *dst++ = NXSwapHostShortToBig(s);
            time += dtb;        /* Move to next sample by time increment */
        }

        while (time < endTime)
        {
            interpConst = time & Pmask; /* fraction of sample period */
            t = (time >> Np);
            src = &src0[t]; /* Ptr to current left sample */
            x1s = (short)NXSwapBigShortToHost(*src++);   /* left sample */
            x2s = (short)NXSwapBigShortToHost(*src);     /* right sample */
            x1 = x1s * ((1<<Np)-interpConst); /* linear interpolation */
            x2 = x2s * interpConst;
            v = x1 + x2;                /* linear interpolation */
            s = intToshort(v,Np);   /* Deposit output */
            *dst++ = NXSwapHostShortToBig(s);
            time += dtb;        /* Move to next sample by time increment */
        }
        outSamps = (dst - targs->outPtr);
        t = (time >> Np);
        time -= (n << Np);      /* "mod out" input buffer length */
        if (time < 0)           /* true when dt < 1 sample period */
          prevSamp1 = NXSwapBigShortToHost(src0[t]); /* L samp for N block */
        targs->outBlockSize = outSamps * sizeof(short);
        break;
/*
 * STEREO sampling rate conversion by linear interpolation.
 */
    case 2:
        x1 = prevSamp1; /* left sample */
        x2 = (short)NXSwapBigShortToHost(*src++);       /* right sample */
        y1 = prevSamp2; /* left sample, channel 2 */
        y2 = (short)NXSwapBigShortToHost(*src);         /* right sample */
        while (time < 0)
        {
            int icc;
            interpConst = time & Pmask;
            icc = ((1<<Np)-interpConst); /* lin. interp. const. complement */
            x1 *= icc;
            x2 *= interpConst;
            v = x1 + x2;        /* linear interpolation */
            s = intToshort(v,Np); /* Deposit output */
            *dst++ = NXSwapHostShortToBig(s);
            y1 *= icc;
            y2 *= interpConst;
            v = x1 + x2;        /* linear interpolation */
            s = intToshort(v,Np); /* Deposit output */
            *dst++ = NXSwapHostShortToBig(s); /* must produce stereo output */
            time += dtb;        /* Move to next sample by time increment */
        }

        while (time < endTime)
        {
            int icc;
            interpConst = time & Pmask; /* fraction of sample period */
            src = src0 + ((time >> (Np-1)) & ~1);
            x1 = (short)NXSwapBigShortToHost(*src++); /* left sample, left chan */
            y1 = (short)NXSwapBigShortToHost(*src++); /* left sample, right chan */
            x2 = (short)NXSwapBigShortToHost(*src++); /* right sample, left chan */
            y2 = (short)NXSwapBigShortToHost(*src);   /* right sample, right chan */
            icc = ((1<<Np)-interpConst);
            x1 *= icc;
            x2 *= interpConst;
            v = x1 + x2;        /* linear interpolation */
            s = intToshort(v,Np);   /* Deposit output */
            *dst++ = NXSwapHostShortToBig(s);

            y1 *= icc;
            y2 *= interpConst;
            v = y1 + y2;        /* linear interpolation */
            s = intToshort(v,Np); /* Deposit output */
            *dst++ = NXSwapHostShortToBig(s); /* must produce stereo output */
            time += dtb;        /* Move to next sample by time increment */
        }
        outSamps = (dst - targs->outPtr);
        t = (time >> Np);
        time -= (n << Np);      /* "mod out" input buffer length */
        if (time < 0) {         /* true when dt < 1 sample period */
            src = &src0[t<<1];
            prevSamp1 = NXSwapBigShortToHost(*src++); /* L samp, L ch, n blk */
            prevSamp2 = NXSwapBigShortToHost(*src);   /* L samp, R ch, n blk */
        }
        targs->outBlockSize = outSamps * sizeof(short);
        break;
    default:
        return SND_ERR_BAD_CHANNEL;
    }
    return 0;
#undef Np
}


static int mulaw_to_soundout_thread(thread_args *targs)
{
    int i, n, nBytes = targs->inBlockSize;
    mulaw *src = (mulaw *)targs->inPtr;
    short *dst = targs->outPtr;

    n = nBytes / sizeof(mulaw);
    for (i=n; i; i--)
      *dst++ = NXSwapHostShortToBig(muLaw[*src++]);
    targs->outBlockSize = n * sizeof(short);

#if DEBUG
    if(targs->outBlockSize > targs->outBlockSizeMax)
      fprintf(stderr,"mulaw_to_soundout_thread: allocation error\n");
#endif
    return 0;
}

static int mulaw_to_byte_soundout_thread(thread_args *targs)
{
    int i, n, nBytes = targs->inBlockSize;
    mulaw *src = (mulaw *)targs->inPtr;
    char *dst = (char *)targs->outPtr;

    n = nBytes / sizeof(mulaw);
    for (i=n; i; i--)
      *dst++ = muLaw[*src++] >> 8;
      
    //targs->outBlockSize = n * sizeof(char);

#if DEBUG
    if(targs->outBlockSize > targs->outBlockSizeMax)
      fprintf(stderr,"mulaw_to_soundout_thread: allocation error\n");
#endif
    return 0;
}

static int mulaw_stereo_to_byte_soundout_thread(thread_args *targs)
{
    int i, n, nBytes = targs->inBlockSize;
    mulaw *src = (mulaw *)targs->inPtr;
    char *dst = (char *)targs->outPtr;

    n = nBytes / (2*sizeof(mulaw));
    for (i=n; i; i--)	{
      *dst++ = muLaw[*src++] >> 8;
      src++;
    }
    //targs->outBlockSize = n * sizeof(char);		-- FIXME

#if DEBUG
    if(targs->outBlockSize > targs->outBlockSizeMax)
      fprintf(stderr,"mulaw_to_soundout_thread: allocation error\n");
#endif
    return 0;
}


/***************** Audio Transform Compression (ATC) support *****************/

#import "atc_c/hfft.c"

#import "atc_c/atc.c"           /* compression */

int _snd_atc_thread(thread_args *targs)
{
    int nBytes = atcCompressByteArray(targs->inPtr,
                                      (byte **)(&(targs->outPtr)),
                                      targs->firstBlock, /* => subheader */
                                      targs->sound);
#ifdef DEBUG
    if (nBytes > targs->outBlockSizeMax)
      fprintf(stderr,"*** _snd_atc_thread: output block overflow.\n");
#endif
    targs->outBlockSize = nBytes; /* return bytes computed */
    return 0;
}


/*************** Audio Transform Decompression (ATD) support ***************/

#include "atc_c/atd.c"          /* decompression */

/* 
 * ----------------- ATC decompression in C (no DSP) ----------------------
 *
 * An ATC format file consists of quantized FFT frames (alternating
 * DCT and DST).  For stereo, left and right channels are interleaved
 * on a frame by frame basis, i.e., DCT-left, DCT-right, DST-left, DST-right,
 * etc.
 *
 * On decompression, the frames are unpacked, inverse transformed, and
 * "overlap-added" into an output sound buffer.  The transform size
 * is double the frame size, so overlap is 50% of the FFT size, or one frame.
 *
 * ATC can decompress 22 kHz mono in real time on a Turbo without the DSP.
 * Stereo and/or 44 kHz must be converted to 22 kHz mono.  This is what
 * the makeMono and rateShift parameters are for.
 *
 * CONVENTIONS 
 * -----------
 * A "size" is always in bytes (except in soundstruct.h where
 *              ATC_FRAME_SIZE is half a frame, or a "step", in samples).
 * A "step" always refers to the FFT hop size = half the FFT size.
 * A "frame" is always one channel of one compressed block
 *              on input, which corresponds to an FFT's worth of output,
 *              but only one step of time advancement (50% overlap on output).
 */
#define ATC_FRAME_SAMPLES (ATC_FRAME_SIZE*2)
#define ATC_STEP_SAMPLES (ATC_FRAME_SAMPLES/2)
#define ATC_STEP_SIZE (ATC_STEP_SAMPLES*2)
#define ATC_STATE_SAMPLES (ATC_STEP_SAMPLES * 2 * 2)
/* Times 2 for possible stereo, times 2 for first and last steps in sound */

static short atd_state[ATC_STATE_SAMPLES];

/*
 * Hack to avoid thread collisions on the static input pointer in 
 * _snd_atd_thread ().   Use pointer to the sound struct as a tag to
 * find a unique index for an array of input pointers. 
 */
#define NSP 5

static int *soundPtrs [NSP] = {0, 0, 0, 0, 0};

int alloc_soundPtr (int *sp)
{
    int i;

    for (i = 0; i < NSP; i++) {
	/* XXX legacy behavior - may still avoid some race conditions. */
	if (soundPtrs [i] == sp) {
	    return i;
	}
	/* XXX End legacy test. */

	if (soundPtrs [i] == 0) {
	    soundPtrs [i] = sp;
	    return i;
	}
    }
    return -1;
}

int find_soundPtr (int *sp)
{
    int i;

    for (i=0; i < NSP; i++) {
	if (soundPtrs [i] == sp) {
	    return i;
	}
    }
    return -1;
}

int free_soundPtr (int *sp)
{
    int i;

    for (i = 0; i < NSP; i++) {
	if (sp == soundPtrs [i]) {
	    soundPtrs [i] = 0;
	    return 0;
	}
    }
    return -1;
}


int _snd_atd_thread(thread_args *targs)
/* parameters[0] == (int) 0 for full quality, 1 for "fast mode" */
{
    int ipIndex = -1;
    static byte *inPtr[5] = {0, 0, 0, 0, 0};
    byte *fPtr,*endPtr;
    int i,inSize,outSize,frameSize,stepSamplesOut,stepSamplesOutChans;
    int nc = targs->sound->channelCount;
    int halfStateSamples=ATC_STEP_SAMPLES*nc; /* 1st half-frames in hdr */
    int stateSamples = halfStateSamples<<1; /* 1st & last half-frames in hdr */
    int nBytes,nSamps;
    int rateShift = targs->rateShift;
    int makeMono = targs->makeMono;
    int oneBlock = ( targs->firstBlock && targs->lastBlock );
    int old_3p0_format = 1;     /* New format not yet implemented */
    static int stepNumber;
#ifdef DEBUG
    if (targs->discontiguous)
      fprintf(stderr,"*** _snd_atd_thread: Discontiguous input unexpected\n");
#endif  
    if (targs->firstBlock) {
        /* targs->sound->dataLocation already added into inPtr: */

	/* get a location in the input pointer array for use by this sound */
	while (ipIndex == -1) {
	    ipIndex = alloc_soundPtr ((int*) targs->sound);
	    /* XXX should sleep here to avoid spin in case of congestion? */
	}
	
        inPtr[ipIndex] =
	    ((byte *)targs->inPtr) + sizeof(SNDCompressionSubheader); 
        stepNumber = 1;
        /* Unpack first and last step from "header" and place first half
           in state.  Second half goes at the end. */
        /* FIXME: Use new magic number for this sound format and 
           support both.  Old magic => old_3p0_format, otherwise identical */
#ifdef DEBUG
        if (targs->sound->dataLocation < (stateSamples*sizeof(short)
                                          + sizeof(SNDSoundStruct) 
                                          + sizeof(SNDCompressionSubheader)))
#endif
          old_3p0_format = 1;   /* first and last step not in "header" */
        
        if (old_3p0_format) {
            for (i=0; i<stateSamples; i++)
              atd_state[i] = 0; /* preload output for one step */
        } else {
            /* 
             * Copy first and last steps from the header to the overlap-add
             * state buffer atd_state[].  The first half of atd_state[]
             * is used in overlap-add on each buffer of decompression,
             * while the second half is used only at the very end.
             * If we are downsampling, we must downsample now since 
             * atd.c expects raw state info passed in the output buffer.
             */
            int skp = (1 << rateShift) * nc;
            short *sp = (short *)(((char *)targs->sound) 
                                  + targs->sound->dataLocation
                                  - stateSamples * sizeof(short));
            for (i=0; i<stateSamples; i+=nc) {
                /* Fixme: Doing unfiltered decimation when rateShift>0 */
                /* preload output for one step: */
                atd_state[i] = NXSwapBigShortToHost(*sp);
                if (nc == 2)
                  atd_state[i+1] = NXSwapBigShortToHost(*(sp+1));
                sp += skp;
            }
            if (makeMono) {
                int j;
                for (i=0; i < (stateSamples>>(rateShift+1)); i += 1) {
                    j = i<<1;
                    atd_state[i] = atd_state[j] + atd_state[j+1];
                }
            }
        }
    }

    else { /* firstBlock */
	/* find location in the input pointer array used by this sound */
	ipIndex = find_soundPtr ((int *) targs->sound);
	if (ipIndex == -1) {
#ifdef DEBUG
    	    fprintf (stderr,
		"_snd_atd_thread: Input pointer index not found\n");
#endif
	    ipIndex = 0; /* XXX No worse than before making inPtr an array. */
	}
    }


    stepSamplesOut = ATC_STEP_SAMPLES >> rateShift;
    stepSamplesOutChans = stepSamplesOut * (makeMono ? 1 : nc);

    if (oneBlock) {
       /* Happens for offline decompression (from compress.c) & short files */
        inSize = targs->inBlockSize; /* only used for checking up */
        outSize = targs->outBlockSize;
    } else {
        /* 
         * Decompression in real time on blocks (from performsound.c).
         * 
         * The inPtr computed in peformsound.c:black_box_thread() will march
         * regularly though the input data, while our input pointer (the real
         * one) will march irregularly though the compressed input data. We 
         * ignore the passed input pointer after initializing our own. 
         * THIS DEPENDS ON ALL INPUT BLOCKS BEING CONTIGUOUS IN MEMORY.
         * I.e., targs->inPtr must advance through a single long array.
         * This is presently the only thing that can happen.
         */
#ifdef DEBUG
        static char *pInPtr = 0;
        if (pInPtr != ((char *)targs->inPtr) - targs->inBlockSize) {
            if ( ! targs->firstBlock ) {
                fprintf(stderr,"*** black_boxes.c: Input blocks MUST be "
                        "contiguous for ATC decompression!\n"); }
        }
        pInPtr = (char *)targs->inPtr; 
#endif
        inSize = outSize = 0;
        endPtr = ((byte *)targs->inPtr) + targs->inBlockSize;
        for(fPtr = inPtr[ipIndex]; fPtr < endPtr; fPtr += frameSize) {
            frameSize = *fPtr;
#ifdef DEBUG
            if (frameSize == 0) {
                fprintf(stderr,"_snd_atd_thread: bad ATC format at "
                        "input offset %d, output offset %d\n",
                        (int)(fPtr-inPtr[ipIndex]), outSize);
                break;
            }
#endif
            inSize += frameSize;
            outSize += ATC_STEP_SIZE; /* per channel, before rateShift */
        }
        if (! targs->lastBlock) { /* don't process possibly partial step */
            inSize -= frameSize;
            outSize -= ATC_STEP_SIZE;
        }
#if 0
        fprintf(stderr,"std_atd_thread: inBlockSize = %d, inSize = %d, outSize = %d\n",
                targs->inBlockSize, inSize, outSize);
#endif
    }
    
    for (i=0; i<stepSamplesOutChans; i++)
      targs->outPtr[i] = atd_state[i];

    fPtr = inPtr[ipIndex];               /* for checking up */
    nBytes = _ATCDecompressByteArray(&inPtr[ipIndex],targs->outPtr,
	outSize, nc, rateShift, makeMono, &stepNumber);
    nSamps = nBytes/2;          /* total number of samples returned */
    if (targs->lastBlock) {
        int offset;
        short *dst;
        SNDCompressionSubheader *subheader;
        if (!old_3p0_format) {  /* Add in final step of sound from header */
            subheader 
              = (SNDCompressionSubheader *)((char *)targs->sound
                                            + targs->sound->dataLocation);
            /* Computation of offset does not work with time synchronization */
            offset = subheader->originalSize % (ATC_STEP_SIZE*nc);
            offset >>= rateShift;
            if (nc == 2 && makeMono)
              offset >>= 1;
            dst = &(targs->outPtr[offset]);

            if (offset + stepSamplesOutChans >= nSamps) {
#ifdef DEBUG
                fprintf(stderr,"ATC: Can't add in final step from header\n");
#endif DEBUG
            } else {
                for (i=0; i<stepSamplesOutChans; i++) { /* Final OLA */
                    *dst++ = NXSwapHostShortToBig
                        (NXSwapBigShortToHost(*dst) +
                         atd_state[stepSamplesOutChans + i]);
                }
            }
        }
    } else {                    /* middle block */
        short *src = &(targs->outPtr[nSamps]);
        for (i=0; i<stepSamplesOutChans; i++) {
            /* save for next overlap-add */
            atd_state[i] = *src++; 
        }
    }
#ifdef DEBUG
    if (nBytes&1)
      fprintf(stderr,"_ATCDecompressByteArray returned odd no. bytes\n");
    if ( !oneBlock && (nBytes*2 > targs->outBlockSizeMax)) {
        fprintf(stderr,"ATD outbuf not big enough for stereo\n");
        exit(1); }
    if (inPtr[ipIndex] != fPtr + inSize) { /* check up */
        fprintf(stderr,"*** ATD thread: inSize = %d but %d bytes scanned\n",
                inSize, (int)(inPtr[ipIndex] - fPtr)); }
#endif
    targs->outBlockSize = nBytes; /* return bytes computed */
    if (targs->lastBlock) soundPtrs [ipIndex] = 0; 
    return 0;
}

/************* Bit-Faithful and Bits-Dropped Compression support ***********/
/* 
 * See the parpack subdirectory for more info on these formats.
 */

#import "parpack/parlib.c"

int _snd_old_compression_thread(thread_args *targs)
/* 
 * targs->parameters[0] == (int) compression type,
 * targs->parameters[1] == (int) num bits to drop
 * targs->parameters[2] == (int) encode length
 * targs->parameters[3] == (int) channel count
 */
{
#if 1
    int nBytes = parPackCompressByteArray(targs->inPtr,
                                      (byte **)(&(targs->outPtr)),
                                      targs->inBlockSize/2 /* shorts */,
                                      targs->firstBlock, /* => subheader */
                                      targs->sound,
                                      targs->parameters);
#else
    int nBytes = 0;
#endif

#ifdef DEBUG
    if (nBytes > targs->outBlockSizeMax)
      fprintf(stderr,"*** _snd_old_compression_thread: "
              "output block overflow.\n");
#endif
    targs->outBlockSize = nBytes; /* return bytes computed */
    return 0;
}


int _snd_old_decompression_thread(thread_args *targs)
{
    static byte *inPtr = 0;
    byte *fPtr;
    int inSize,outSize;
    int nc = targs->sound->channelCount;
    int nBytes = 0;
    int rateShift = targs->rateShift;
    int makeMono = targs->makeMono;
    int oneBlock = ( targs->firstBlock && targs->lastBlock );
    SNDCompressionSubheader *subheader;
    static int bitFaithful, numDropped, encodeLength, outBlockSize;
#ifdef DEBUG
    if (targs->discontiguous)
      fprintf(stderr,"*** _snd_old_decompression_thread: "
              "Discontiguous input unexpected\n");
#endif  
    if (targs->firstBlock) {
        /* targs->sound->dataLocation already added into inPtr: */
        subheader = (SNDCompressionSubheader *)targs->inPtr;
        inPtr = ((byte *)targs->inPtr) + sizeof(SNDCompressionSubheader); 
        bitFaithful = subheader->method;
        numDropped = subheader->numDropped;
        encodeLength = subheader->encodeLength;
        outBlockSize = targs->inBlockSize*10; /* Anything too big is ok here */
        inSize = targs->inBlockSize;
    } else {
        inSize = ((byte *)targs->inPtr + targs->inBlockSize) 
          - inPtr + sizeof(SNDCompressionSubheader); /* upper bound */
    }
    if (oneBlock) { /* offline decompression (compress.c) or short files */
        outSize = targs->outBlockSize; /* == targs->sound->originalSize */
    } else {
        outSize = MIN(targs->outBlockSizeMax,
                      MAX(outBlockSize,PARPACK_ENCODE_LENGTH));
        if (outSize == 0)
          goto done;
    }
    
    fPtr = inPtr;
#if 1
    nBytes = _parPackDecompressByteArray(&inPtr, inSize, 
                                         targs->outPtr, outSize, nc,
                                         rateShift, makeMono, bitFaithful,
                                         numDropped, encodeLength);
#else
    nBytes = 0;
#endif

    if (nBytes == 0) {
        int i;
        short *sp = targs->outPtr;
#ifdef  DEBUG
        fprintf(stderr,"_snd_old_decompression_thread: Bad input file?\n");
#endif  DEBUG
        for (i=0; outSize/2; i++)
          *sp++ = 0;
        nBytes = outSize;       /* give them zeros instead */
    }
#ifdef DEBUG
    fprintf(stderr,"_snd_old_decompression_thread: inSize = %d while "
            "%d bytes scanned\n", inSize, (int)(inPtr-fPtr));
    fprintf(stderr,"_snd_old_decompression_thread: outSize = %d with "
            "%d bytes produced by decompression\n", outSize, nBytes);
    if (nBytes&1)
      fprintf(stderr,"_parPackDecompressByteArray returned odd no. bytes\n");
    if ( !oneBlock && (nBytes > outSize)) {
        fprintf(stderr,"ParPack outbuf too big\n");
    }
#endif

 done:
    targs->outBlockSize = nBytes; /* return bytes computed */
    return 0;
}

