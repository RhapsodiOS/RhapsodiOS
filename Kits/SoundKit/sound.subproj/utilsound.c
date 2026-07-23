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

/*
 *	utilsound.c
 *	Written by Lee Boynton
 *	Copyright 1988 NeXT, Inc.
 *
 *	Modification History:
 *	04/06/90/mtm	Added support for SND_FORMAT_COMPRESSED*,
 *			SND_FORMAT_DSP_COMMANDS*, and SND_FORMAT_EMPHASIZED.
 *	04/09/90/mtm	#include <mach_init.h>
 *	04/10/90/mtm	Set default compression options in SNDAlloc().
 *	10/02/91/mtm	Import location changes.
 *	10/11/91/jos	Changed default compression format to SND_CFORMAT_ATC.
 *	02/26/93/mtm	Added SNDSwapSoundToHost and SNDSwapHostToSound.
 */

#import <mach/mach.h>
#import <mach/mach_init.h>
#import <string.h>
#import <architecture/byte_order.h>
#import "performsound.h"
#import "filesound.h"
#import "utilsound.h"

static int calcHeaderSize(s)
    SNDSoundStruct *s;
{
    int size = strlen(s->info) + 1;
    if (size < 4) size = 4;
    else size = (size + 3) & 3;
    return(sizeof(SNDSoundStruct) - 4 + size);
}

static int calcFormatSize(int dataFormat)
{
    if (dataFormat == SND_FORMAT_MULAW_8 ||
        dataFormat == SND_FORMAT_LINEAR_8 ||
        dataFormat == SND_FORMAT_ALAW_8 ||
        dataFormat == SND_FORMAT_MULAW_SQUELCH ||
	dataFormat == SND_FORMAT_DELTA_MULAW_8)
	return 1;
    if (dataFormat == SND_FORMAT_LINEAR_16 ||
	dataFormat == SND_FORMAT_DSP_DATA_16 ||
	dataFormat == SND_FORMAT_DISPLAY ||
	dataFormat == SND_FORMAT_EMPHASIZED)
	return 2;
    if (dataFormat == SND_FORMAT_LINEAR_32 || 
    	dataFormat == SND_FORMAT_DSP_DATA_32 ||
    	dataFormat == SND_FORMAT_FLOAT ||
	dataFormat == SND_FORMAT_INDIRECT)
	return 4;
    if (dataFormat == SND_FORMAT_LINEAR_24 ||
	dataFormat == SND_FORMAT_DSP_DATA_24 )
	return 3;
    if (dataFormat == SND_FORMAT_DSP_CORE)
	return 0;
    if (dataFormat == SND_FORMAT_DOUBLE)
	return 8;
    return -1;
}

int SNDBytesToSamples(int byteCount, int channelCount, int dataFormat)
{
    int formatSize = calcFormatSize(dataFormat);
    if (!channelCount || !formatSize) return 0;
    return byteCount/(channelCount*formatSize);
}

int SNDSamplesToBytes(int sampleCount, int channelCount, int dataFormat)
{
    int formatSize = calcFormatSize(dataFormat);
    return sampleCount*channelCount*formatSize;
}

int SNDSampleCount(SNDSoundStruct *s)
{
    int i;
    if (!s || s->magic != SND_MAGIC)
	return -1;
    if (s->dataFormat == SND_FORMAT_INDIRECT) {
	SNDSoundStruct *s2, **iBlock = (SNDSoundStruct **)s->dataLocation;
	i = 0;
	while (s2 = *iBlock++)
	    i += SNDBytesToSamples(s2->dataSize,
	    				s2->channelCount,s2->dataFormat);
    } else if (s->dataFormat == SND_FORMAT_MULAW_SQUELCH) {
	unsigned char *ip = (unsigned char *)s;
	ip += s->dataLocation;
	ip += 4;  // advance past flag bytes
	i = ( *((int *) ip) );
    } else if (s->dataFormat == SND_FORMAT_DSP_CORE) {
	int temp, *ip = (int *)((int)s + s->dataLocation);
	//NOTE: a load segment is {type,addr,size,[data ... data]}
	// and a system segment is {0, 0, 5, samp_cnt_hi,samp_cnt_hi,...}
	// all words are 24 low bits in an int.
	if (NXSwapBigIntToHost(*ip++))
	    i = -1; // not a system segment -- cannot guess sample count
	else {
	    ip+= 2;  // advance past version number and segment length
	    temp = NXSwapBigIntToHost(*ip++); // get high order 24 bits of sample count
	    if (temp > 127)
		 i = -1; // too big for return value
	    else
		i = (temp<<24)+(0xffffff & NXSwapBigIntToHost(*ip)); // get low order 24 bits
	}
    } else if (s->dataFormat == SND_FORMAT_COMPRESSED ||
    	       s->dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED) {
        // Original size is first int in subheader
	i = SNDBytesToSamples(*((int *)((char *)s + s->dataLocation)),
			      s->channelCount,SND_FORMAT_LINEAR_16);
    } else if (s->dataFormat == SND_FORMAT_DSP_COMMANDS ||
    	       s->dataFormat == SND_FORMAT_DSP_COMMANDS_SAMPLES) {
        // Sample count is first int in subheader
        i = NXSwapBigIntToHost(*((int *)((char *)s + s->dataLocation)));
    } else
	i = SNDBytesToSamples(s->dataSize,s->channelCount,s->dataFormat);
    return (i < 0) ? -1 : i;
}

int SNDGetDataPointer(SNDSoundStruct *s, char **ptr, int *size, int *width)
{
    char *p;
    int i;
    if (!s || s->magic != SND_MAGIC)
	return SND_ERR_NOT_SOUND;
    if (s->dataFormat == SND_FORMAT_INDIRECT) 
	return SND_ERR_BAD_FORMAT;
    i = calcFormatSize(s->dataFormat);
    if (i < 0)
	return SND_ERR_BAD_FORMAT;
    p = (char *)s;
    p += s->dataLocation;
    *ptr = p;
    *size = s->dataSize / i;
    *width = i;
    return SND_ERR_NONE;
}


int SNDAlloc(SNDSoundStruct **s,
	     int dataSize, 
	     int dataFormat,
	     int samplingRate,
	     int channelCount,
	     int infoSize)
{
    SNDSoundStruct *pS;
    int size;
    
    size = sizeof(SNDSoundStruct) + dataSize;

    if (infoSize > 4)
	size += ((infoSize-1) & 0xfffffffc);
    if (vm_allocate(task_self(),(pointer_t *)&pS,size,1) != KERN_SUCCESS) {
	return SND_ERR_CANNOT_ALLOC;
    }
    pS->magic = SND_MAGIC;
    pS->dataLocation = size-dataSize;
    pS->dataSize = dataSize;
    pS->dataFormat = dataFormat;
    pS->samplingRate = samplingRate;
    pS->channelCount = channelCount;
    pS->info[0] = '\0';
    *s = pS;
    if (dataFormat == SND_FORMAT_COMPRESSED ||
        dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED)
      return SNDSetCompressionOptions(pS, SND_CFORMAT_ATC, 0); /* default */
    else
      return SND_ERR_NONE;
}

int SNDFree(SNDSoundStruct *s)
{
    int size;
    if (!s || s->magic != SND_MAGIC) return SND_ERR_NOT_SOUND;
    if (s->dataFormat == SND_FORMAT_INDIRECT) {
	if (vm_deallocate(task_self(),s->dataLocation,s->dataSize) != 
								KERN_SUCCESS)
	    return SND_ERR_CANNOT_FREE;
	size = calcHeaderSize(s);
	if (vm_deallocate(task_self(),(pointer_t)s,size) != KERN_SUCCESS)
	    return SND_ERR_CANNOT_FREE;
    } else {
	size = s->dataLocation + s->dataSize;
	if (vm_deallocate(task_self(),(pointer_t)s,size) != KERN_SUCCESS)
	    return SND_ERR_CANNOT_FREE;
    }
    return SND_ERR_NONE;
}

int SNDPlaySoundfile(char *path, int priority)
{
    SNDSoundStruct *s;
    int err = SNDReadSoundfile(path,&s);
    if (err) return err;
    err = SNDStartPlaying(s,(int)s,priority,1,0,(SNDNotificationFun)SNDFree);
    if (err) SNDFree(s);
    return err;
}

/* New for 3.1 */
int SNDSwapHostToSound(void *dest, void *src, int sampleCount,
		       int channelCount, int dataFormat)
{
    int frameCount = sampleCount*channelCount;

    switch (dataFormat) {
      case SND_FORMAT_MULAW_8:
      case SND_FORMAT_DELTA_MULAW_8:
      case SND_FORMAT_ALAW_8:
      case SND_FORMAT_LINEAR_8:
      case SND_FORMAT_DSP_DATA_8:
      case SND_FORMAT_MULAW_SQUELCH:
	if (dest != src)
	    memmove(dest, src, frameCount);
	return SND_ERR_NONE;
      case SND_FORMAT_LINEAR_16:
      case SND_FORMAT_DSP_DATA_16:
      case SND_FORMAT_DISPLAY:
      case SND_FORMAT_EMPHASIZED: {
	  short *to = (short *)dest;
	  short *from = (short *)src;
	  while (frameCount--)
	      *to++ = NXSwapHostShortToBig(*from++);
	  return SND_ERR_NONE;
      }
      case SND_FORMAT_LINEAR_32:
      case SND_FORMAT_DSP_DATA_32: {
	  int *to = (int *)dest;
	  int *from = (int *)src;
	  while (frameCount--)
	      *to++ = NXSwapHostIntToBig(*from++);
	  return SND_ERR_NONE;
      }
      case SND_FORMAT_FLOAT: {
	  NXSwappedFloat *to = (NXSwappedFloat *)dest;
	  float *from = (float *)src;
	  while (frameCount--)
	      *to++ = NXSwapHostFloatToBig(*from++);
	  return SND_ERR_NONE;
      }
      case SND_FORMAT_DOUBLE: {
	  NXSwappedDouble *to = (NXSwappedDouble *)dest;
	  double *from = (double *)src;
	  while (frameCount--)
	      *to++ = NXSwapHostDoubleToBig(*from++);
	  return SND_ERR_NONE;
      }
      default:
	return SND_ERR_BAD_FORMAT;
    }
}

/* New for 3.1 */
int SNDSwapSoundToHost(void *dest, void *src, int sampleCount,
		       int channelCount, int dataFormat)
{
    int frameCount = sampleCount*channelCount;

    switch (dataFormat) {
      case SND_FORMAT_MULAW_8:
      case SND_FORMAT_DELTA_MULAW_8:
      case SND_FORMAT_ALAW_8:
      case SND_FORMAT_LINEAR_8:
      case SND_FORMAT_DSP_DATA_8:
      case SND_FORMAT_MULAW_SQUELCH:
	if (dest != src)
	    memmove(dest, src, frameCount);
	return SND_ERR_NONE;
      case SND_FORMAT_LINEAR_16:
      case SND_FORMAT_DSP_DATA_16:
      case SND_FORMAT_DISPLAY:
      case SND_FORMAT_EMPHASIZED: {
	  short *to = (short *)dest;
	  short *from = (short *)src;
	  while (frameCount--)
	      *to++ = NXSwapBigShortToHost(*from++);
	  return SND_ERR_NONE;
      }
      case SND_FORMAT_LINEAR_32:
      case SND_FORMAT_DSP_DATA_32: {
	  int *to = (int *)dest;
	  int *from = (int *)src;
	  while (frameCount--)
	      *to++ = NXSwapBigIntToHost(*from++);
	  return SND_ERR_NONE;
      }
      case SND_FORMAT_FLOAT: {
	  float *to = (float *)dest;
	  NXSwappedFloat *from = (NXSwappedFloat *)src;
	  while (frameCount--)
	      *to++ = NXSwapBigFloatToHost(*from++);
	  return SND_ERR_NONE;
      }
      case SND_FORMAT_DOUBLE: {
	  double *to = (double *)dest;
	  NXSwappedDouble *from = (NXSwappedDouble *)src;
	  while (frameCount--)
	      *to++ = NXSwapBigDoubleToHost(*from++);
	  return SND_ERR_NONE;
      }
      default:
	return SND_ERR_BAD_FORMAT;
    }
}
