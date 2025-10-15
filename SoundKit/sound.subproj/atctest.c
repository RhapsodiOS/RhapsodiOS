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
 * atctest.c
 *
 *	Modification History:
 *	11/11/91/jos	created
 */

#include "sound.h"
#include "_atcsound.h"

#import <stdio.h>

int ckerr_cont(int err)
{
    if(err==0) {
	fprintf(stderr,"\n*** EXPECTED NONZERO ERROR RETURN\n");
	exit(1);
    } else {
	fprintf(stderr,"error code = %d (expected)\n",err);
    }
    return err;
}

int ckerr(int err)
{
    if(err==0)
      return 0;
    fprintf(stderr,"\n*** error code = %d\n",err);
    exit(1);
}

main (int argc, char *argv[])
{
    int size, err, i;
    SNDSoundStruct *s;
    int playDSP = FALSE;
    int startArg = 1;

    float agc,ogain,quality;
    int nBands;
    float cf[ATC_NBANDS];
    float bw[ATC_NBANDS];
    float eg[ATC_NBANDS];
    float st[ATC_NBANDS];

    ckerr(SNDGetATCGainNormalization(&agc));
    fprintf(stderr,"Default AGC strength = %f\n",agc);
    agc = 0.5;
    ckerr_cont(SNDSetATCGainNormalization(agc)); /* cont until implemented */
    fprintf(stderr,"After setting AGC strength to %f, ",agc);
    ckerr(SNDGetATCGainNormalization(&agc));
    fprintf(stderr,"AGC strength = %f\n\n",agc);

    ckerr(SNDGetNumberOfATCBands(&nBands));
    fprintf(stderr,"Number of ATC bands = %d\n",nBands);
    if (nBands != ATC_NBANDS) {
	fprintf(stderr,"*** which is wrong!\n");
	exit(1);
    }

    fprintf(stderr,"\n");

    ckerr(SNDGetATCBandFrequencies(nBands, cf));
    fprintf(stderr,"ATC band frequencies:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",cf[i]);
    fprintf(stderr,"\n\n");

    ckerr(SNDGetATCBandwidths(nBands, bw));
    fprintf(stderr,"ATC bandwidths:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",bw[i]);
    fprintf(stderr,"\n\n");

    ckerr(SNDGetATCEqualizerGains(nBands, eg));
    fprintf(stderr,"ATC default equalizer gains:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",eg[i]);
    fprintf(stderr,"\n");

    for(i=0;i<nBands;i++)
      eg[i] = 2.0*ATC_MAX_GAIN/((float)(i+1)) - 1.0; /* Clip on purpose */
    fprintf(stderr,"Setting ATC equalizer gains to:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",eg[i]);
    fprintf(stderr,"\n");
    
    ckerr_cont(SNDSetATCEqualizerGains(nBands, eg));
    ckerr(SNDGetATCEqualizerGains(nBands, eg));
    fprintf(stderr,"New ATC equalizer gains:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",eg[i]);
    fprintf(stderr,"\n");

    fprintf(stderr,"Squaring ATC equalizer gains by scaling by self:\n");
    ckerr_cont(SNDScaleATCEqualizerGains(nBands, eg));
    ckerr(SNDGetATCEqualizerGains(nBands, eg));
    fprintf(stderr,"New ATC equalizer gains:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",eg[i]);
    fprintf(stderr,"\n\n");
    

    ckerr(SNDGetATCSquelchThresholds(nBands, st));
    fprintf(stderr,"ATC default squelch thresholds:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",st[i]);
    fprintf(stderr,"\n");

    for(i=0;i<nBands;i++)
      st[i] = 3.0 * (((float)i)/((float)nBands)) - 1.0; /* clip on purpose */
    fprintf(stderr,"Setting ATC squelch thresholds to:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",st[i]);
    fprintf(stderr,"\n");
    
    ckerr_cont(SNDSetATCSquelchThresholds(nBands, st));
    ckerr(SNDGetATCSquelchThresholds(nBands, st));
    fprintf(stderr,"New ATC squelch thresholds:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",st[i]);
    fprintf(stderr,"\n");

    ckerr(SNDUseDefaultATCSquelchThresholds());
    ckerr(SNDGetATCSquelchThresholds(nBands, st));
    fprintf(stderr,"After reversion to default ATC squelch thresholds:\n");
    for(i=0;i<nBands;i++)
      fprintf(stderr,"%f ",st[i]);
    fprintf(stderr,"\n\n");

    ckerr(SNDGetATCGain(&ogain));
    fprintf(stderr,"Default overall gain = %f\n",ogain);
    ogain = 2.0;
    ckerr_cont(SNDSetATCGain(ogain));
    fprintf(stderr,"After setting overall gain to %f, ",ogain);
    ckerr(SNDGetATCGain(&ogain));
    fprintf(stderr,"overall gain = %f\n",ogain);
    ogain = 0.5;
    ckerr(SNDSetATCGain(ogain));
    fprintf(stderr,"After setting overall gain to %f, ",ogain);
    ckerr(SNDGetATCGain(&ogain));
    fprintf(stderr,"overall gain = %f\n\n",ogain);

    ckerr(SNDGetATCQuality(&quality));
    fprintf(stderr,"Default overall quality = %f\n",quality);
    quality = 0.5;
    ckerr_cont(SNDSetATCQuality(quality)); /* cont until implemented */
    fprintf(stderr,"After setting overall quality to %f, ",quality);
    ckerr(SNDGetATCQuality(&quality));
    fprintf(stderr,"overall quality = %f\n\n",quality);

    fprintf(stderr,"Calling synchronization functions\n");
    ckerr(SNDDropATCSamples(10,0));
    ckerr(SNDDropATCSamples(10,100));
    ckerr(SNDInsertATCSamples(10,0));
    ckerr(SNDInsertATCSamples(10,100));

    fprintf(stderr,"\n=== ALL ATC TESTS PASS ===\n");
}
