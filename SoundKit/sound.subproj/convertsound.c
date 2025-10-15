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
#ifdef SHLIB
#include "shlib.h"
#endif SHLIB

#define TRY_SQUELCH 0		/* see also performsound.c */
#define LIBSYS_VERSION		/* flag to ATC and resampling code */

/*
 *	convertsound.h
 *	Written by Dana Massie and Lee Boynton
 *	Copyright 1988 NeXT, Inc.
 *
 *	Modification History:
 *	04/06/90/mtm	Added SNDCompressSound().
 *	04/08/90/mtm	Comment out "normal_exit:" and "calcHeaderSize()".
 *	07/18/90/mtm	Get rid of static array in findDSPCore().
 *	07/25/90/mtm	Implement SNDCompressSound().
 *	08/08/90/mtm	Add sample rate conversion to SNDConvertSound().
 *	10/08/90/mtm	Add downby2.c back in (bug #10407).
 *	02/04/92/jos	Rewrote SNDConvertSound().  Flushed dead squelch code.
 *	02/22/93/mtm	486 byte swap stuff for static conversion routines.
 */

#import <sys/types.h>
#import <stdlib.h>
#import <string.h>
#import <architecture/byte_order.h>
#import "sounddriver.h"
#import "accesssound.h"
#import "utilsound.h"
#import "filesound.h"
#import "convertsound.h"
#import "editsound.h"		/* for SNDCopySound() */
#import <mach/cthreads.h>	/* for pressing on without DSP */
#import "_compression.h"
#import "_atcsound.h"

/*** FIXME: Move to soundstruct.h ***/
static unsigned char *data_pointer(SNDSoundStruct *s)
{
    unsigned char *p = (unsigned char *)s;
    p += s->dataLocation;
    return p;
}

#define PAGESIZE ((int)vm_page_size)

#import "mulaw.h"
#import "black_boxes.h"

/* Note that several .c files are included at about 65% below */

/*
 * 16 bit linear to mulaw conversion
 */

#define IMULAWOFFSET	8192
#define	IMULAWTABLEN	16384
#define IMULAWMASK	16383
static unsigned char *iMuLaw = 0;

 struct mu {
    short mu,
	linear;
 };

static int compar(p1, p2)
    struct mu **p1, **p2;
{
    if ((*p1)->linear > (*p2)->linear) return 1;
    else if ((*p1)->linear == (*p2)->linear) return 0;
    else return -1;
}

static void makeIMuLawTab()
{
    int i,j,k, d1, d2;
    struct mu *mutab[256], mus[256];

    iMuLaw = (unsigned char *) malloc(IMULAWTABLEN * sizeof(unsigned char));

    for (i = 0; i < 256; ++i)
    {
	mutab[i] = &mus[i];
	mus[i].mu = i;
	mus[i].linear = muLaw[i] >> 2;
    }
    qsort(mutab, 256, sizeof(struct mu *), compar);

    for (i = 0, j = 0, k = -8192; i < 16384; ++i, ++k)
    {
	if (j < 255)
	{
	    d1 = k - mutab[j]->linear;
	    d2 = mutab[j+1]->linear - k;
	    if (d1 > 0 && d1 > d2)
		++j;
	}
	iMuLaw[i] = mutab[j]->mu;
    }
}

static unsigned char int2Mu(p)
    short p;
{
    p >>= 2; /* scale input; table size is for 14 bit number! */

#if 1
    if (p >= (IMULAWTABLEN/2))
	return iMuLaw[IMULAWTABLEN-1];
    if (p < (-IMULAWTABLEN/2))
	return iMuLaw[0];
    else
#endif
	return iMuLaw[p + IMULAWTABLEN/2];
}

/* New (private) in 3.1 */
void _SNDLinear8ToMulaw(unsigned char *dest, char *src, unsigned int count)
{
    short tmp;
    
    if (!iMuLaw) makeIMuLawTab();
    while (count--) {
    	tmp = *src << 8;
        *dest = int2Mu(tmp);
	dest++; src++;
    }
}

/*** FIXME: Move to soundstruct.h ***/
static int calcInfoSize(SNDSoundStruct *s)
{
    int size = strlen(s->info) + 1;
    if (size < 4) size = 4;
    else size = (size + 3) & ~3;
    return size;
}

// This function is currently not usesd
#if 0
static int calcHeaderSize(s)
    SNDSoundStruct *s;
{
    int size = strlen(s->info) + 1;
    if (size < 4) size = 4;
    else size = (size + 3) & 3;
    return(sizeof(SNDSoundStruct) - 4 + size);
}
#endif

/*** FIXME: The following conversion functions should be replaced
  by calls to the functions in black_boxes.c (which must get added 
  to spec_sys). ***/

static int convertLinearToMulaw(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, size, err, infosize = calcInfoSize(s1);
    short *src, tmp;
    unsigned char *dst;

    size = s1->dataSize / sizeof(short);
    err = SNDAlloc(s2,size,SND_FORMAT_MULAW_8,s1->samplingRate,
    					s1->channelCount,infosize);
    if (err) return err;
    src = (short *)data_pointer(s1);
    dst = data_pointer(*s2);
    if (!iMuLaw) makeIMuLawTab();
    for (i = 0; i < size; i++) {
	tmp = NXSwapBigShortToHost(*src++);
	*dst++ = int2Mu(tmp);
    }
    return SND_ERR_NONE;
}

static int convertMulawToLinear(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, size, max, err, infosize = calcInfoSize(s1);
    unsigned char *src;
    short *dst;

    max = s1->dataSize;
    size = max * sizeof(short);
    err = SNDAlloc(s2,size,SND_FORMAT_LINEAR_16,s1->samplingRate,
    					s1->channelCount,infosize);
    if (err) return err;
    src = data_pointer(s1);
    dst = (short *)data_pointer(*s2);
    for (i = 0; i < max; i++)
	*dst++ = NXSwapHostShortToBig(muLaw[*src++]);
    return SND_ERR_NONE;
}

static int convertFloatToLinear(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, newSize, count, err, infosize = calcInfoSize(s1);
    NXSwappedFloat *src;
    float scale = 32768.0;
    short *dst;

    count = s1->dataSize / sizeof(float);
    newSize = count * sizeof(short);
    err = SNDAlloc(s2,newSize,SND_FORMAT_LINEAR_16,s1->samplingRate,
		   s1->channelCount,infosize);
    if (err) return err;
    src = (NXSwappedFloat *)data_pointer(s1);
    dst = (short *)data_pointer(*s2);
    for (i = 0; i < count; i++)
	*dst++ = NXSwapHostShortToBig((short)
				      (scale * NXSwapBigFloatToHost(*src++)));
    return SND_ERR_NONE;
}

static int convertDoubleToLinear(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, newSize, count, err, infosize = calcInfoSize(s1);
    NXSwappedDouble *src;
    double scale = 32768.0;
    short *dst;

    count = s1->dataSize / sizeof(double);
    newSize = count * sizeof(short);
    err = SNDAlloc(s2,newSize,SND_FORMAT_LINEAR_16,s1->samplingRate,
		   s1->channelCount,infosize);
    if (err) return err;
    src = (NXSwappedDouble *)data_pointer(s1);
    dst = (short *)data_pointer(*s2);
    for (i = 0; i < count; i++)
	*dst++ = NXSwapHostShortToBig((short)
				      (scale * NXSwapBigDoubleToHost(*src++)));
    return SND_ERR_NONE;
}

static int convertLinear8ToLinear(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, newSize, count, err, infosize = calcInfoSize(s1);
    char *src;
    short *dst;

    count = s1->dataSize;
    newSize = count * sizeof(short);
    err = SNDAlloc(s2,newSize,SND_FORMAT_LINEAR_16,s1->samplingRate,
		   s1->channelCount,infosize);
    if (err) return err;
    src = (char *)data_pointer(s1);
    dst = (short *)data_pointer(*s2);
    for (i = 0; i < count; i++)
      *dst++ = NXSwapHostShortToBig((short)(*src++ << 8));
    return SND_ERR_NONE;
}

static int convertLinearToFloat(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, newSize, count, err, infosize = calcInfoSize(s1);
    short *src, tmp;
    float scale = (1.0/32768.0);
    NXSwappedFloat *dst;

    count = s1->dataSize / sizeof(short);
    newSize = count * sizeof(float);
    err = SNDAlloc(s2,newSize,SND_FORMAT_FLOAT,s1->samplingRate,
		   s1->channelCount,infosize);
    if (err) return err;
    src = (short *)data_pointer(s1);
    dst = (NXSwappedFloat *)data_pointer(*s2);
    for (i = 0; i < count; i++) {
	tmp = NXSwapBigShortToHost(*src++);
	*dst++ = NXSwapHostFloatToBig(scale * (float)tmp);
    }
    return SND_ERR_NONE;
}

static int convertLinearToDouble(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, newSize, count, err, infosize = calcInfoSize(s1);
    short *src, tmp;
    double scale = (1.0/32768.0);
    NXSwappedDouble *dst;

    count = s1->dataSize / sizeof(short);
    newSize = count * sizeof(double);
    err = SNDAlloc(s2,newSize,SND_FORMAT_DOUBLE,s1->samplingRate,
		   s1->channelCount,infosize);
    if (err) return err;
    src = (short *)data_pointer(s1);
    dst = (NXSwappedDouble *)data_pointer(*s2);
    for (i = 0; i < count; i++) {
	tmp = NXSwapBigShortToHost(*src++);
	*dst++ = NXSwapHostDoubleToBig(scale * (double)tmp);
    }
    return SND_ERR_NONE;
}

static int convertLinearToLinear8(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, newSize, count, err, infosize = calcInfoSize(s1);
    short *src;
    char *dst;

    count = s1->dataSize / sizeof(short);
    newSize = count;
    err = SNDAlloc(s2,newSize,SND_FORMAT_LINEAR_8,s1->samplingRate,
		   s1->channelCount,infosize);
    if (err) return err;
    src = (short *)data_pointer(s1);
    dst = (char *)data_pointer(*s2);
    for (i = 0; i < count; i++)
      *dst++ = (char)(NXSwapBigShortToHost(*src++) >> 8);
    return SND_ERR_NONE;
}


#if 0
/* Not worth the memory in libsys, I don't think */
static const float muLawTofloatTable[256] = {
-0.980347, -0.949097, -0.917847, -0.886597, -0.855347, -0.824097, -0.792847,
-0.761597, -0.730347, -0.699097, -0.667847, -0.636597, -0.605347, -0.574097,
-0.542847, -0.511597, -0.488159, -0.472534, -0.456909, -0.441284, -0.425659,
-0.410034, -0.394409, -0.378784, -0.363159, -0.347534, -0.331909, -0.316284,
-0.300659, -0.285034, -0.269409, -0.253784, -0.242065, -0.234253, -0.226440,
-0.218628, -0.210815, -0.203003, -0.195190, -0.187378, -0.179565, -0.171753,
-0.163940, -0.156128, -0.148315, -0.140503, -0.132690, -0.124878, -0.119019,
-0.115112, -0.111206, -0.107300, -0.103394, -0.099487, -0.095581, -0.091675,
-0.087769, -0.083862, -0.079956, -0.076050, -0.072144, -0.068237, -0.064331,
-0.060425, -0.057495, -0.055542, -0.053589, -0.051636, -0.049683, -0.047729,
-0.045776, -0.043823, -0.041870, -0.039917, -0.037964, -0.036011, -0.034058,
-0.032104, -0.030151, -0.028198, -0.026733, -0.025757, -0.024780, -0.023804,
-0.022827, -0.021851, -0.020874, -0.019897, -0.018921, -0.017944, -0.016968,
-0.015991, -0.015015, -0.014038, -0.013062, -0.012085, -0.011353, -0.010864,
-0.010376, -0.009888, -0.009399, -0.008911, -0.008423, -0.007935, -0.007446,
-0.006958, -0.006470, -0.005981, -0.005493, -0.005005, -0.004517, -0.004028,
-0.003662, -0.003418, -0.003174, -0.002930, -0.002686, -0.002441, -0.002197,
-0.001953, -0.001709, -0.001465, -0.001221, -0.000977, -0.000732, -0.000488,
-0.000244, 0.000000, 0.980347, 0.949097, 0.917847, 0.886597, 0.855347,
0.824097, 0.792847, 0.761597, 0.730347, 0.699097, 0.667847, 0.636597, 0.605347,
0.574097, 0.542847, 0.511597, 0.488159, 0.472534, 0.456909, 0.441284, 0.425659,
0.410034, 0.394409, 0.378784, 0.363159, 0.347534, 0.331909, 0.316284, 0.300659,
0.285034, 0.269409, 0.253784, 0.242065, 0.234253, 0.226440, 0.218628, 0.210815,
0.203003, 0.195190, 0.187378, 0.179565, 0.171753, 0.163940, 0.156128, 0.148315,
0.140503, 0.132690, 0.124878, 0.119019, 0.115112, 0.111206, 0.107300, 0.103394,
0.099487, 0.095581, 0.091675, 0.087769, 0.083862, 0.079956, 0.076050, 0.072144,
0.068237, 0.064331, 0.060425, 0.057495, 0.055542, 0.053589, 0.051636, 0.049683,
0.047729, 0.045776, 0.043823, 0.041870, 0.039917, 0.037964, 0.036011, 0.034058,
0.032104, 0.030151, 0.028198, 0.026733, 0.025757, 0.024780, 0.023804, 0.022827,
0.021851, 0.020874, 0.019897, 0.018921, 0.017944, 0.016968, 0.015991, 0.015015,
0.014038, 0.013062, 0.012085, 0.011353, 0.010864, 0.010376, 0.009888, 0.009399,
0.008911, 0.008423, 0.007935, 0.007446, 0.006958, 0.006470, 0.005981, 0.005493,
0.005005, 0.004517, 0.004028, 0.003662, 0.003418, 0.003174, 0.002930, 0.002686,
0.002441, 0.002197, 0.001953, 0.001709, 0.001465, 0.001221, 0.000977, 0.000732,
0.000488, 0.000244, 0.000000};


/* not used */
static int convertMulawToFloat(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, size, max, err, infosize = calcInfoSize(s1);
    unsigned char *src;
    float *dst;

    max = s1->dataSize;
    size = max * sizeof(float);
    err = SNDAlloc(s2,size,SND_FORMAT_FLOAT,s1->samplingRate,
		   s1->channelCount,infosize);
    if (err) return err;
    src = data_pointer(s1);
    dst = (float *)data_pointer(*s2);
    for (i = 0; i < max; i++)
      *dst++ = muLawTofloatTable[*src++];
    return SND_ERR_NONE;
}


/* not used */
static int convertMulawToDouble(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	i, size, max, err, infosize = calcInfoSize(s1);
    unsigned char *src;
    double *dst;

    max = s1->dataSize;
    size = max * sizeof(double);
    err = SNDAlloc(s2,size,SND_FORMAT_DOUBLE,s1->samplingRate,
		   s1->channelCount,infosize);
    if (err) return err;
    src = data_pointer(s1);
    dst = (double *)data_pointer(*s2);
    for (i = 0; i < max; i++)
      *dst++ = (double) muLawTofloatTable[*src++];
    return SND_ERR_NONE;
}


#endif

static int convertStereoToMono(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	err, i, size, samps, infosize = calcInfoSize(s1);
    short *src, *dst;
    int tmp;

    size = s1->dataSize >> 1;
    samps = size >> 1;
    
    err = SNDAlloc(s2,size,s1->dataFormat,s1->samplingRate,1,infosize);
    if (err) return err;

    if ( !(s1->dataFormat == SND_FORMAT_LINEAR_16 ||
	   s1->dataFormat == SND_FORMAT_EMPHASIZED) )
      return SND_ERR_BAD_FORMAT;

    src = (short *)data_pointer(s1);
    dst = (short *)data_pointer(*s2);
    for (i=samps; i>0; i--) {
	tmp = (short)NXSwapBigShortToHost(*src++);
	tmp += (short)NXSwapBigShortToHost(*src++);
	tmp += tmp & 1;	/* round up if odd */
	tmp >>= 1;
	*dst++ = NXSwapHostShortToBig((short)tmp);
    }
    return SND_ERR_NONE;
}

static int convertMonoToStereo(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int	err, i, size, samps, infosize = calcInfoSize(s1);

    size = s1->dataSize << 1;
    
    err = SNDAlloc(s2,size,s1->dataFormat,s1->samplingRate,2,infosize);
    if (err) return err;

    if (s1->dataFormat == SND_FORMAT_MULAW_8 ||
	s1->dataFormat == SND_FORMAT_LINEAR_8) {
	unsigned char *src, *dst;
	src = data_pointer(s1);
	dst = data_pointer(*s2);
	samps = s1->dataSize;
	for (i=samps; i>0; i--) {
	    *dst++ = *src;
	    *dst++ = *src++;
	}
	return SND_ERR_NONE;
    } else if (s1->dataFormat == SND_FORMAT_LINEAR_16 ||
    	       s1->dataFormat == SND_FORMAT_EMPHASIZED) {
	short *src, *dst;
	src = (short *)data_pointer(s1);
	dst = (short *)data_pointer(*s2);
	samps = s1->dataSize >> 1;
	for (i=samps; i>0; i--) {
	    *dst++ = *src;
	    *dst++ = *src++;
	}
	return SND_ERR_NONE;
    } else
	return SND_ERR_BAD_FORMAT;
}

/*
 * dsp stuff
 */

static int findDSPcore(char *name, SNDSoundStruct **s)
{
    static SNDSoundStruct *lastCore=0;
    static char *lastName = NULL;
    char buf[1024];
    int err;

    if (lastName && !strcmp(lastName,name)) {
	*s = lastCore;
	err = SND_ERR_NONE;
    } else {
#ifdef DEBUG
	strcpy(buf,name);	/* Get dsp code from current directory */
#else
	strcpy(buf,"/usr/lib/sound/");
	strcat(buf,name);
#endif
	strcat(buf,".snd");
	err = SNDReadSoundfile(buf,s);
#ifdef DEBUG
	if (err) {		/* No such DSP code in current directory */
	    strcpy(buf,"/usr/lib/sound/");
	    strcat(buf,name);
	    strcat(buf,".snd");
	    err = SNDReadSoundfile(buf,s);
	}
#endif
	if (!err) {
	    if (lastCore) SNDFree(lastCore);
	    lastCore = *s;
	    if (lastName)
	      free(lastName);
	    lastName = malloc(strlen(name)+1);
	    strcpy(lastName,name);
	}
    }
    return err;
}

/* The following constants must match those in "dspsound.asm" */
#define DMASIZE 	(2048)
#define LEADPAD		(2)
#define TRAILPAD	(2)	/* not currently used */

#define READ_TAG 1
#define WRITE_TAG 2

typedef struct { 
    int timeout;
    int flush_timeout;
    char *read_ptr;
    int read_count;
    int read_done;
    port_t cmd_port;
} runDSP_data_t;

 static void runDSP_write_completed(void *arg, int tag)
{
    runDSP_data_t *data = (runDSP_data_t *)arg;
    int err;
    if (tag == WRITE_TAG) {
	err = snddriver_dsp_set_flags(data->cmd_port,
					SNDDRIVER_ICR_HF0,SNDDRIVER_ICR_HF0,
						SNDDRIVER_MED_PRIORITY);
	data->timeout = data->flush_timeout;
    }
}

 static void runDSP_read_data(void *arg, int tag, void *p, int size)
{
    runDSP_data_t *data = (runDSP_data_t *)arg;
    if (tag == READ_TAG) {
	data->read_ptr = (char *)p;
	data->read_count = size;
	data->read_done = 1;
    }
}

int SNDRunDSP(SNDSoundStruct *core,
		  char *write_ptr,
		  int write_count,
		  int write_width,
		  int write_buf_size,
		  char **read_ptr,
		  int *read_count,
		  int read_width,
		  int negotiation_timeout,
		  int flush_timeout,
		  int conversion_timeout)
{
    static msg_header_t *reply_msg = 0;
    int err, protocol = 0;
    int flushed;
    int priority = 1, preempt = 0, low_water = 32*1024, high_water = 32*1024;
    port_t dev_port=PORT_NULL, owner_port=PORT_NULL;
    port_t read_port, write_port, reply_port;
    int req_size = *read_count+(DMASIZE*LEADPAD);
    int bufsize = 2048; //? should follow vm_page_size -- change dsp program!
    runDSP_data_t data =  { -1, flush_timeout, 0, 0, 0, 0 };

    snddriver_handlers_t handlers = { &data, 0, 
    		0, runDSP_write_completed, 0, 0, 0, 0, runDSP_read_data};
    if (!reply_msg)
	reply_msg = (msg_header_t *)malloc(MSG_SIZE_MAX);
    err = SNDAcquire(SND_ACCESS_DSP,priority,preempt, negotiation_timeout,
    				NULL_NEGOTIATION_FUN, (void *)0,
					&dev_port, &owner_port);
    if (err) return err;
    err = snddriver_get_dsp_cmd_port(dev_port,owner_port,
    						&data.cmd_port);
    if (err) goto kerr_exit;
    err = snddriver_stream_setup(dev_port, owner_port,
    				 SNDDRIVER_STREAM_FROM_DSP,
				 DMASIZE, read_width,
				 low_water, high_water,
				 &protocol, &read_port);
    if (err) goto kerr_exit;
    err = snddriver_stream_setup(dev_port, owner_port,
    				 SNDDRIVER_STREAM_TO_DSP,
				 write_buf_size, write_width, 
				 low_water, high_water,
				 &protocol, &write_port);
    if (err) goto kerr_exit;
    err = snddriver_dsp_protocol(dev_port, owner_port, protocol);
    if (err) goto kerr_exit;

    err = port_allocate(task_self(),&reply_port);
    if (err) goto kerr_exit;

    err = snddriver_stream_start_reading(read_port, 0, req_size, READ_TAG,
					 	0,1,0,0,0,0, reply_port);
    if (err) goto kerr_exit;
					 
    err = SNDBootDSP(dev_port,owner_port,core);
    if (err) goto err_exit;

    err = snddriver_dsp_write(data.cmd_port,&bufsize,1,4,
    						SNDDRIVER_MED_PRIORITY);
    if (err) goto err_exit;

    err = snddriver_stream_start_writing(write_port,
    					 (void *)write_ptr,write_count,
					 WRITE_TAG,
					 0,0,
					 0,1,0,0,0,0, reply_port);
    if (err) goto kerr_exit;

    data.timeout = -1;
    data.flush_timeout = flush_timeout;
    data.read_done = 0;
    flushed = 0;
    while (!data.read_done) {
	reply_msg->msg_size = MSG_SIZE_MAX;
	reply_msg->msg_local_port = reply_port;
	if (data.timeout > 0)
	    err = msg_receive(reply_msg, RCV_TIMEOUT, data.timeout);
	else if (conversion_timeout < 0)
	    err = msg_receive(reply_msg, MSG_OPTION_NONE, 0);
	else
	    err = msg_receive(reply_msg, RCV_TIMEOUT, conversion_timeout);
	if (err != KERN_SUCCESS) {
	    if (err == RCV_TIMED_OUT && !flushed) {
		err = snddriver_stream_control(read_port,READ_TAG, 
						SNDDRIVER_ABORT_STREAM);
		if (err != KERN_SUCCESS) goto kerr_exit;
		flushed = 1;
	    } else {
		err = (err == RCV_TIMED_OUT)? SND_ERR_TIMEOUT : SND_ERR_KERNEL;
		goto err_exit;
	    }
	} else {
	    err = snddriver_reply_handler(reply_msg,&handlers);
	    if (err != KERN_SUCCESS) goto kerr_exit;
	}
    }
    *read_ptr = data.read_ptr;
    *read_count = data.read_count / read_width;
 //normal_exit:
    err = SNDRelease(SND_ACCESS_DSP,dev_port,owner_port);
    return err;
 kerr_exit:
     err = SND_ERR_KERNEL;
 err_exit:
    SNDRelease(SND_ACCESS_DSP,dev_port,owner_port);
    return err;
}

/* Called by dspUpsampleCodec and squelch code */
static void makeIntoSoundStruct(char *p, int size, int width, int header_size,
				SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    int nbytes = size*width;
    SNDSoundStruct *s;
    char *h = (char *)(*s2);
    char *free = p;
    int offset = (DMASIZE*LEADPAD*width) - header_size;
    p += offset;
    memmove(p,(char *)s1,header_size); //get the info string and padding
    memmove(p,h,sizeof(SNDSoundStruct)-4); // get the header itself
    s = (SNDSoundStruct *)p;
    s->dataLocation = header_size;
    s->dataSize = nbytes - offset - header_size;
    if (offset >= PAGESIZE) {
	int pageOffset = (int)p % PAGESIZE;
	int free_bytes = nbytes - offset - pageOffset;
	vm_deallocate(task_self(),(pointer_t)free,free_bytes);
    }
    *s2 = s;
}

/*
 * Put included files containing static functions right here.
 */

#if TRY_SQUELCH
#include "squelch.c"
#endif TRY_SQUELCH
#include "downby2.c"
#include "resample.c"
#import "upsamplecodec.c"
#include "compress.c"

/*
 * Exported routines.
 */

unsigned char SNDMulaw(short n)
{
    if (!iMuLaw) makeIMuLawTab();
    return int2Mu(n);
}

short SNDiMulaw(unsigned char m)
{
    return muLaw[m];
}

#if 0
/* not used at present */
static BOOL _dspIsAvailable()
{
    int err;
    port_t dev_port;
    port_t owner_port;
    err = SNDAcquire(SND_ACCESS_DSP, SNDDRIVER_LOW_PRIORITY, 0, 0,
		     NULL_NEGOTIATION_FUN, (void *)0,
		     &dev_port, &owner_port);
    if (err == SND_ERR_NONE)
      SNDRelease(SND_ACCESS_DSP, dev_port, owner_port);

    return (err == 0);
}
#endif

static int oldSNDConvertSound(SNDSoundStruct *s1, SNDSoundStruct **s)
/* This was SNDConvertSound() in release 2.1 */
{
    SNDSoundStruct *s2;
    SNDSoundStruct *dummyCore;

    s2 = *s;

    if ((s1->dataFormat == s2->dataFormat) &&
	     (s1->samplingRate == s2->samplingRate) &&
	     (s1->channelCount == s2->channelCount)) {
	return SNDCopySound(s,s1); /* vm_copy() */
    }	     

    /* CODEC to SoundOut */
    else if ( s1->samplingRate == (int)SND_RATE_CODEC &&
	     s1->dataFormat == SND_FORMAT_MULAW_8 &&
		 s2->samplingRate == (int)SND_RATE_LOW &&
		     s2->dataFormat == SND_FORMAT_LINEAR_16) {
	if (s1->channelCount == 1 && s2->channelCount == 2) {
	    if (dspUpsampleCodec(s1,s) == SND_ERR_NONE)
	      return SND_ERR_NONE; /* Failure normally means no DSP */
	    else
	      return upsampleCodec(s1,s); /* DSP-free version */
	}
    }
	
#if !TRY_SQUELCH
    else if (s1->dataFormat == SND_FORMAT_MULAW_SQUELCH ||
	     s2->dataFormat == SND_FORMAT_MULAW_SQUELCH) {
#ifdef DEBUG
	fprintf(stderr,"*** Squelch format is broken and DISABLED!!!\n");
#endif DEBUG
	/*** FIXME: dspEncodeSquelch:SNDRunDSP walks over stack ***/
	return SND_ERR_NOT_IMPLEMENTED;
    }
#else !TRY_SQUELCH
    /* CODEC to Squelched CODEC */
    else if ( s1->samplingRate == s2->samplingRate &&
	     s1->dataFormat == SND_FORMAT_MULAW_8 &&
	     s2->dataFormat == SND_FORMAT_MULAW_SQUELCH) {
	if (s1->channelCount == 1 && s2->channelCount == 1) {
	    return dspEncodeSquelch(s1,s);
	} else
	  return SND_ERR_NOT_IMPLEMENTED;
    }

    /* Squelched CODEC to CODEC */
    else if ( s1->samplingRate == s2->samplingRate &&
	     s1->dataFormat == SND_FORMAT_MULAW_SQUELCH &&
	     s2->dataFormat == SND_FORMAT_MULAW_8) {
	if (s1->channelCount == 1 && s2->channelCount == 1)
	  return dspDecodeMulawSquelch(s1,s);
	else
	  return SND_ERR_NOT_IMPLEMENTED;
    }

    /* Squelched CODEC to SoundOut */
    else if ( s1->samplingRate == (int)SND_RATE_CODEC &&
	     s1->dataFormat == SND_FORMAT_MULAW_SQUELCH &&
	     s2->samplingRate == (int)SND_RATE_LOW &&
	     s2->dataFormat == SND_FORMAT_LINEAR_16) {
	if (s1->channelCount == 1 && s2->channelCount == 2)
	  return dspUpsampleCodecSquelch(s1,s);
	else
	  return SND_ERR_NOT_IMPLEMENTED;
    }
#endif !TRY_SQUELCH

    /* Mono to stereo */
    else if (   s1->dataFormat == s2->dataFormat &&
		    s1->samplingRate == s2->samplingRate ) {
		if (s1->channelCount == 1 && s2->channelCount == 2)
		    return convertMonoToStereo(s1,s);
		else
		    return SND_ERR_NOT_IMPLEMENTED;
    }

    /* Sampling rate conversion down by factor of 2 */
    else if ((findDSPcore("resample1", &dummyCore) != SND_ERR_NONE) &&
	     s1->dataFormat == SND_FORMAT_LINEAR_16 &&
	     s2->dataFormat == SND_FORMAT_LINEAR_16 &&
	     s1->samplingRate == SND_RATE_HIGH   &&
	     s2->samplingRate == SND_RATE_LOW ) {
	if (s1->channelCount == s2->channelCount )
	    return downsampleBy2(s1,s);
	else
	    return SND_ERR_NOT_IMPLEMENTED;
    }

    /* Mu-law to linear */
    else if (s1->dataFormat == SND_FORMAT_MULAW_8 &&
	     s2->dataFormat == SND_FORMAT_LINEAR_16 &&
	     s1->channelCount == s2->channelCount &&
	     s1->samplingRate == s2->samplingRate) {
	return convertMulawToLinear(s1,s);
    }
#if 0
    /* Mu-law to float or double */
    else if (s1->dataFormat == SND_FORMAT_MULAW_8 &&
	     s1->channelCount == s2->channelCount &&
	     (s2->dataFormat == SND_FORMAT_FLOAT ||
	      s2->dataFormat == SND_FORMAT_DOUBLE) &&
	     s1->samplingRate == s2->samplingRate) {
	return (s2->dataFormat == SND_FORMAT_FLOAT ?
		convertMulawToFloat(s1,s) : 
		convertMulawToDouble(s1,s));
    }
#endif
    /* Linear to mu-law */
    else if (s2->dataFormat == SND_FORMAT_MULAW_8 &&
	     s1->channelCount == s2->channelCount &&
	     s1->dataFormat == SND_FORMAT_LINEAR_16 &&
	     s1->samplingRate == s2->samplingRate) {
	return convertLinearToMulaw(s1,s);
    }

    /* Sampling rate conversion */
    else if ((s1->dataFormat == SND_FORMAT_LINEAR_16 ||
	      s1->dataFormat == SND_FORMAT_EMPHASIZED) &&
	     s2->dataFormat == s1->dataFormat &&
	     s1->samplingRate != s2->samplingRate) {
	return 
	  (s1->samplingRate == 0 || s2->samplingRate == 0 ? SND_ERR_BAD_FORMAT:
	   resampleDSP(s1, s, 
		       (double)s2->samplingRate / (double)s1->samplingRate));
    }
    return SND_ERR_NOT_IMPLEMENTED;
    }


int SNDCompressSound(SNDSoundStruct *s1, SNDSoundStruct **s2,
		     int compressionType, int dropBits)
{
    /*
     * compressDSP compresses or decompresses based on the format code
     * of s1.  Channel count equal 1 or 2 is the only restriction.
     */
    if (s1->channelCount != 1 && s1->channelCount != 2)
	return SND_ERR_BAD_CHANNEL;
    return compressDSP(s1, s2, compressionType, dropBits);
}


int SNDConvertSound(SNDSoundStruct *s1, SNDSoundStruct **s)
{
    int err;
    SNDSoundStruct *curSound,*srcSound;
    SNDSoundStruct *s2;

#if sparc
	// Turning on alignment handling for this process
	asm("	t 6;");
#endif
   if (!s1 ||  s1->magic != SND_MAGIC)
	return SND_ERR_NOT_SOUND;

    if (!s || !(*s) || ((*s)->magic != SND_MAGIC))
      return SND_ERR_BAD_CONFIGURATION;
    
    s2 = *s;			/* copy of pointer */

    /* Compact if necessary */
    if (s1->dataFormat == SND_FORMAT_INDIRECT 
	&& s2->dataFormat != SND_FORMAT_INDIRECT ) {
	err = SNDCompactSamples(&srcSound, s1);
	if (err) return err; 
    } else {
	err = SNDCopySound(&srcSound,s1); /* vm_copy() */
	if (err) return err; 
    }

    err = oldSNDConvertSound(srcSound,s); /* handle optimized cases */
    if (err == SND_ERR_NONE) {
	SNDFree(srcSound);
	return err;
    }

    /* Convert to linear data format if not already linear.
       This is always necessary because both rate-conversion 
       and stereo-to-mono require it. Mono-to-stereo for mulaw 
       is optimized out above. */
	
    if (srcSound->dataFormat == SND_FORMAT_LINEAR_16 ||
	srcSound->dataFormat == SND_FORMAT_EMPHASIZED) {
	curSound = srcSound;
	err = 0;
    } else {
	if (srcSound->dataFormat == SND_FORMAT_COMPRESSED ||
	    srcSound->dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED)
	  err = SNDCompressSound(srcSound, &curSound, 0, 0);
	else if (srcSound->dataFormat == SND_FORMAT_MULAW_8)
	  err = convertMulawToLinear(srcSound,&curSound);
	else if (srcSound->dataFormat == SND_FORMAT_MULAW_SQUELCH) {
#if TRY_SQUELCH
	    SNDSoundStruct *tmpSound;
	    /* FIXME: Need C version and need it direct to linear */
	    err = dspDecodeMulawSquelch(srcSound,&tmpSound);
	    if (err) {
		SNDFree(tmpSound);
		return err;
	    }
	    err = convertMulawToLinear(tmpSound,&curSound);
#else
	    err = SND_ERR_NOT_IMPLEMENTED;
#endif
	}
	else if (srcSound->dataFormat == SND_FORMAT_FLOAT) 
	  err = convertFloatToLinear(srcSound,&curSound);
	else if (srcSound->dataFormat == SND_FORMAT_DOUBLE) 
	  err = convertDoubleToLinear(srcSound,&curSound);
	else if (srcSound->dataFormat == SND_FORMAT_LINEAR_8) 
	  err = convertLinear8ToLinear(srcSound,&curSound);
	else {
#ifdef DEBUG
	    fprintf(stderr, 
		    "*** SNDConvertSound: Unsupported input data format\n");
#endif
	    err = SND_ERR_NOT_IMPLEMENTED;
	}
	
	SNDFree(srcSound);
	if (err)
	  return err;
    }

    /*
     * At this point, curSound is in LINEAR_16 format.
     */

#ifdef DEBUG
    if ((curSound->dataFormat != SND_FORMAT_LINEAR_16) &&
	(curSound->dataFormat != SND_FORMAT_EMPHASIZED)) {
	fprintf(stderr, 
		"*** SNDConvertSound: Data format not "
		"normalized as expected\n");
	SNDFree(curSound);
	return SND_ERR_BAD_CONFIGURATION;
    }
#endif

    /* Convert stereo to mono, if requested */

    if (curSound->channelCount == 2 && s2->channelCount == 1) {
	SNDSoundStruct *stmp;
	err = convertStereoToMono(curSound,&stmp);
	SNDFree(curSound);
	curSound = stmp;
	if (err) return err;
    }

    /* Convert sampling rate, if needed */

    if ( s1->samplingRate !=  s2->samplingRate) {
	SNDSoundStruct *stmp;
	double fs1 = (double)s1->samplingRate;
	double fs2 = (double)s2->samplingRate;
	double conversionFactor = fs2 / fs1; 
	err = resample(curSound, &stmp, conversionFactor);
	SNDFree(curSound);
	curSound = stmp;
	if (err) return err;
    }

    /* Mono to stereo */
    if (curSound->channelCount == 1 && s2->channelCount == 2) {
	SNDSoundStruct *stmp;
	err = convertMonoToStereo(curSound,&stmp);
	SNDFree(curSound);
	curSound = stmp;
    }
    if (err) return err;

    /* Linear to any other dataFormat */

    if ((s2->dataFormat != SND_FORMAT_LINEAR_16) &&
	(s2->dataFormat != SND_FORMAT_EMPHASIZED)) 
    {
	SNDSoundStruct *stmp;

	if (s2->dataFormat == SND_FORMAT_MULAW_8)
	  err = convertLinearToMulaw(curSound,&stmp);
	else if (s2->dataFormat == SND_FORMAT_MULAW_SQUELCH) {
#if TRY_SQUELCH
	    SNDSoundStruct *tmpSound;
#ifdef DEBUG
	    fprintf(stderr,"*** Squelch format is broken and DISABLED!!!\n");
#endif
	    err = convertLinearToMulaw(curSound,&tmpSound);
	    if (err) {
		SNDFree(curSound);
		SNDFree(tmpSound);
		return err;
	    }
	    /* FIXME: Need C version and need it direct from linear */
	    err = dspEncodeSquelch(tmpSound,&stmp);
#else TRY_SQUELCH
	    /*** FIXME: dspEncodeSquelch:SNDRunDSP walks over stack ***/
	    SNDFree(curSound);
	    return SND_ERR_NOT_IMPLEMENTED;
#endif TRY_SQUELCH
	}
	else if ((s2->dataFormat == SND_FORMAT_COMPRESSED) ||
		 (s2->dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED))
	  err = SNDCompressSound(curSound,&stmp,SND_CFORMAT_ATC,0);
	else if (s2->dataFormat == SND_FORMAT_FLOAT)
	  err = convertLinearToFloat(curSound,&stmp);
	else if (s2->dataFormat == SND_FORMAT_DOUBLE)
	  err = convertLinearToDouble(curSound,&stmp);
	else if (s2->dataFormat == SND_FORMAT_LINEAR_8) 
	  err = convertLinearToLinear8(curSound,&stmp);
	else
	  err = SND_ERR_NOT_IMPLEMENTED;
	SNDFree(curSound);
	if (err) {
	    SNDFree(stmp);
	    return err;
	}
	curSound = stmp;
    }

    *s = curSound;

    return SND_ERR_NONE;
}

#if 0

CHANGE LOG

  01/19/92/jos - Generalized SNDConvertSound().

#endif
