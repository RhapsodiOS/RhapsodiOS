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
 * This file is included by convertsound.c!!!!
 *
 * The C version should sound as good as the dsp version.
 *
 * Modification History:
 *	07/18/90/mtm	Get rid of static data in interpolate4to11().
 *	02/07/92/jos	Installed superior C version.
 *	03/15/92/jos	Copy cached DSP core files since they get freed.
 */

static int dspUpsampleCodec(SNDSoundStruct *s1, SNDSoundStruct **s2)
{
    static SNDSoundStruct *mulawCodecCore = 0;
    int	err;

    char *dstPtr;    
    int dstWidth = 2;
    int dstCount =  (s1->dataSize*11)/dstWidth;
    char *srcPtr = (char *)data_pointer(s1);
    int srcCount = s1->dataSize;
    int srcWidth = 1;
    int srcBufSize = 2048; // this is pretty arbitrary
    int headersize = s1->dataLocation;
    int negotiation_timeout = -1; //no timeout
    int flush_timeout = 100; // in milliseconds
    int conversion_timeout = 100+ 1000*SNDSampleCount(s1)/s1->samplingRate;
     // in milliseconds

    if (headersize > (LEADPAD*DMASIZE*dstWidth))
	return SND_ERR_INFO_TOO_BIG;

    if (!mulawCodecCore) {
	SNDSoundStruct *tempCore;
	err = findDSPcore("mulawcodec", &tempCore);
	if (err) return err;
	/* Must copy since findDSPcore() will free next call */
	SNDCopySound(&mulawCodecCore,tempCore);
    }
    err = SNDRunDSP(mulawCodecCore,srcPtr,srcCount,srcWidth,srcBufSize,
		    &dstPtr,&dstCount,dstWidth,
		    negotiation_timeout, flush_timeout, conversion_timeout);
    if (!err)
        makeIntoSoundStruct(dstPtr,dstCount,dstWidth,headersize,s1,s2);
    return err;
}

static int upsampleCodec(SNDSoundStruct *s1, SNDSoundStruct **s2)
/* Mono CODEC (8 kHz mu-law) to stereo sound-out (22 kHz PCM) converter */
{
    int	err, size, infosize = calcInfoSize(s1);
    int inCount, outCount;
    thread_args targs;
    unsigned char *src;
    short *dst;
    inCount = s1->dataSize;
    outCount = (inCount * 11/4) * ((*s2)->channelCount/s1->channelCount);	/* exact */
    size = outCount * sizeof(short);
    err = SNDAlloc(s2, size, SND_FORMAT_LINEAR_16, SND_RATE_LOW,
		   (*s2)->channelCount, infosize);
    if (err) return err;
    src = data_pointer(s1);
    dst = (short *)data_pointer(*s2);

    targs.inPtr = (short *)src;
    targs.outPtr = (short *)dst;
    targs.inBlockSize = inCount;
    targs.outBlockSize = outCount;	/* ignored (computed) */
    targs.sound = s1;
    targs.parameters = NULL;
    targs.firstBlock = TRUE;
    targs.lastBlock = TRUE;
    targs.discontiguous = FALSE;

    _snd_init_upsamplecodec_thread();
    err = _snd_upsamplecodec_thread(&targs); /* uses current thread */
    
    if ( s1->channelCount == 1 && (*s2)->channelCount == 2 )
    {
    	short *outPtrSrc, *outPtrDst, temp;
    	int i, nSamps = targs.outBlockSize / sizeof(short);
        outPtrDst = targs.outPtr + 2 * nSamps - 1;
        outPtrSrc = targs.outPtr +     nSamps - 1;
        for (i=0; i<nSamps; i++) 
        {
                temp = *outPtrSrc--;
                *outPtrDst-- = temp;
                *outPtrDst-- = temp;
         }
         targs.outBlockSize *= 2;
    }

    return (err == 0? SND_ERR_NONE : SND_ERR_BAD_CONFIGURATION);
}
