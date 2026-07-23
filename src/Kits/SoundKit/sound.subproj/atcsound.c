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
/* atcsound.c - utilities for Audio Transform Compression support */

#import <libc.h>
#include "_atcsound.h"
#define ATCSOUND_VERSION	/* Saves 320 bytes in libsys */
#import "cb.h"
#import <mach/mach.h>
#import <SoundKit/sounddriver.h>

/*
 * FIXME: Incorporate the following state into ATC encode/playback
 */
static float quality = 0.5;
static float agcStrength = 0.0;
static const int nBands = ATC_NBANDS;
static float overallVolume = 1.0;
static int insertSamples = 0;
static int insertSamplesTime = 0;

static int updateGains(void);	/* forward declaration */

static float *eqGains;
static int   *dspGains;

/*** FIXME: Determine these more accurately ***/

static float *squelch;

/* cf. atc_c/atc.h, atc_dsp/atc_h.asm
   #define MAX_FRAME_EXPONENT (16.0)
   #define DSQ ((float)pow(2.0,-MAX_FRAME_EXPONENT))
   */

static float const defaultSquelch[ATC_NBANDS] = {
    0.000058,0.000047,0.000043,0.000041,0.000035,0.000033,0.000030,0.000028,0.000025,0.000024,
    0.000023,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,
    0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,
    0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000022,0.000026,0.000029};

#if 0

static float const defaultSquelch[ATC_NBANDS] = {
    0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,
    0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,
    0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,
    0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044,0.000044};
 
/* The following causes too much burbling.  */

static float const defaultSquelch[ATC_NBANDS] = {
    0.000834,0.000456,0.000305,0.000223,0.000223,0.000223,0.000223,0.000223,0.000250,0.000223,
    0.000223,0.000223,0.000223,0.000223,0.000167,0.000167,0.000167,0.000167,0.000167,0.000167,
    0.000167,0.000204,0.000204,0.000204,0.000204,0.000223,0.000223,0.000223,0.000223,0.000223,
    0.000223,0.000250,0.000305,0.000558,0.000558,0.000456,0.000373,0.000373,0.000373,0.000373};

/* The following causes too much burbling.  For example, bob.snd is extreme.
   The birdsong, b.snd is cleaned up by it. */

static float const defaultSquelch[ATC_NBANDS] = {
    0.020812,0.002787,0.000682,0.000682,0.000682,0.000682,0.000682,0.000682,0.000682,0.000631,
    0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,
    0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,
    0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,0.000631,};

#define DSQ (0.000015258789)
static float const defaultSquelch[ATC_NBANDS] = {
    DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,
    DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,
    DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,
    DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ,DSQ};
#undef DSQ
#endif

int SNDGetATCGainNormalization(float *strengthP)
{
    *strengthP = agcStrength;
    return 0;
}

/*********************************** AGC ************************************/

int SNDSetATCGainNormalization(float strength)
{
    if (strength<0.0)
      agcStrength = 0;
    else if (strength>1.0)
      agcStrength = 1.0;
    else 
      agcStrength = strength;
    
    /* FIXME: Not implemented */
    
    return -1;
}


/********************************** BAND INFO *******************************/

int SNDGetNumberOfATCBands(int *nBandsP)
{
    *nBandsP = ATC_NBANDS;
    return 0;
}


int SNDGetATCBandFrequencies(int nBands, float *bandCenters)
{
    int i;
    for (i=0;i<nBands;i++)
      bandCenters[i] = cbCentersHz[i];
    return 0;
}

int SNDGetATCBandwidths(int nBands, float *bandWidths)
{
    int i;
    for (i=0;i<nBands;i++)
      bandWidths[i] = cbWidthsHz[i];
    return 0;
}

/********************************* OVERALL GAIN ******************************/

int SNDGetATCGain(float *oGainP)
{
    *oGainP = overallVolume;
    return 0;
}

int SNDSetATCGain(float oGain)
{
    int i;
    overallVolume = oGain;
    for (i=0;i<ATC_NBANDS;i++)
      eqGains[i] *= overallVolume;
    return updateGains();
}

/*************************** DYNAMIC DSP PARAMETERS **************************/

#define DSP_EQGAIN_OPCODE 0x10000
#define DSP_SYNCH_OPCODE 0x20000
#define DSP_PARAMETERS_HC 0x13

static int dspdata[2];
static port_t cmd_port;

/* defined in performsound.c */
void _SNDGetActiveDSPCore(char **dspcore, port_t *cmd_port);

static int dsp_connect(void)
{
    char *dspcore;
    _SNDGetActiveDSPCore(&dspcore,&cmd_port);
    if (strcmp("sndoutdecompressatc",dspcore)==0)
      return 0;
    else
      return -1;
}

static int send_dsp_data(void)
{
    return snddriver_dsp_write(cmd_port,dspdata,2,4,
			       SNDDRIVER_MED_PRIORITY);
}


static int updateDSPGains(void)
{
    int i,err;
    int dc;
    dc = ((dsp_connect()==0) ? 1 : 0);
#ifdef DEBUG
    fprintf(stderr,"Updating DSP Eq gains\n");
#endif
    for (i=0;i<ATC_NBANDS;i++) {
	int g = FLOAT_TO_UNSIGNED_DSPFIX24(eqGains[i]);
	if (dspGains[i] != g) {	/* only send actual changes */
	    dspGains[i] = g;
	    if (dc) {
		dspdata[0] = (DSP_EQGAIN_OPCODE | i);
		dspdata[1] = g;
		err = send_dsp_data();
#ifdef DEBUG
		if(err)
		  fprintf(stderr,"DSP finished while updating Eq gain %d\n",i);
#endif
	    }
	}
    }
    return 0;
}

static int updateDSPSynch(void)
{
    int err;
    if (dsp_connect()==0) {
#ifdef DEBUG
	fprintf(stderr,"Synchronizing DSP ATC playback\n");
#endif
	if (insertSamples>0) {
	    dspdata[0] = (DSP_SYNCH_OPCODE | (insertSamplesTime & 0xFFFF));
	    dspdata[1] = insertSamples;
	    err = send_dsp_data();
	    if(err)
	      return err;
	}
    }
    return 0;
}

/******************************** EQUALIZER GAINS ****************************/

float *_SNDGetATCEGP(void)
{
    int i;
    float eg;
    if (eqGains == 0) {
	dspGains = (int *)malloc(ATC_NBANDS * sizeof(int));
	eqGains = (float *)malloc(ATC_NBANDS * sizeof(float));
	for (i=0;i<nBands;i++) {
	    eg = eqGains[i] = (1.0/ATC_MAX_GAIN);
	    dspGains[i] = FLOAT_TO_UNSIGNED_DSPFIX24(eg);
	}
    }
    return eqGains;
}


static int updateGains(void)
{
    int i;
    int clipCount = 0;
    float t;
    for (i=0;i<ATC_NBANDS;i++) {
	t = eqGains[i];
	if (t<0.0) {
	    t = 0.0;
	    clipCount++;
	    eqGains[i] = t;
	} else if (t>1.0) {
	    t = 1.0;		/* Actually 1 - 2^(-24) will be used */
	    clipCount++;
	    eqGains[i] = t;
	}
    }
    updateDSPGains();
    return clipCount;
}

int SNDGetATCEqualizerGains(int nBands, float *gains)
{
    int i;
    _SNDGetATCEGP();
    for (i=0;i<nBands;i++)
      gains[i] = eqGains[i] * ATC_MAX_GAIN;
    return 0;
}

int SNDScaleATCEqualizerGains(int nBands, float *gainScales)
{
    int i;
    _SNDGetATCEGP();
    for (i=0;i<nBands;i++)
      eqGains[i] *= gainScales[i];
    return updateGains();
}

int SNDSetATCEqualizerGains(int nBands, float *gains)
{
    int i;
    if (eqGains == 0) {
	eqGains = (float *)malloc(ATC_NBANDS * sizeof(float));
	dspGains = (int *)malloc(ATC_NBANDS * sizeof(int));
    }
    for (i=0;i<nBands;i++)
      eqGains[i] = gains[i] * (1.0/ATC_MAX_GAIN); /* normalize to [0,1] */
    overallVolume = 1.0;
    return updateGains();
}

/****************************** SQUELCH THRESHOLDS **************************/

float *_SNDGetATCSTP(void)
{
    int i;
    if (squelch == 0) {
	squelch = (float *)malloc(ATC_NBANDS * sizeof(float));
	for (i=0;i<nBands;i++)
	  squelch[i] = defaultSquelch[i];
    }
    return squelch;
}

static int clipSquelch(void)
{
    int i;
    int clipCount = 0;
    float t;
    for (i=0;i<ATC_NBANDS;i++) {
	t = squelch[i];
	if (t<0.0) {
	    t = 0.0;
	    clipCount++;
	    squelch[i] = t;
	} else if (t>1.0) {
	    t = 1.0;		/* Actually 1 - 2^(-24) will be used */
	    clipCount++;
	    squelch[i] = t;
	}
    }
    return clipCount;
}

int SNDGetATCSquelchThresholds(int nBands, float *thresh)
{
    int i;
    _SNDGetATCSTP();
    for (i=0;i<nBands;i++)
      thresh[i] = squelch[i];
    return 0;
}

int SNDSetATCSquelchThresholds(int nBands, float *thresh)
{
    int i;
    if (squelch == 0) {
	squelch = (float *)malloc(ATC_NBANDS * sizeof(float));
    }
    for (i=0;i<nBands;i++)
      squelch[i] = thresh[i];
    return clipSquelch();
}

int SNDUseDefaultATCSquelchThresholds(void)
{
    int i;
    if (squelch == 0) {
	squelch = (float *)malloc(ATC_NBANDS * sizeof(float));
    }
    for (i=0;i<nBands;i++)
      squelch[i] = defaultSquelch[i];
    return 0;
}


/******************************** QUALITY LEVEL ******************************/


int SNDGetATCQuality(float *qualityP)
{
    *qualityP = quality;
    return 0;
}

int SNDSetATCQuality(float q)
{
    if (q<0.0)
      quality = 0;
    else if (q>1.0)
      quality = 1.0;
    else 
      quality = q;
    return -1;			/* FIXME - Currently ignored */
}

/******************************* SYNCHRONIZATION *****************************/

int SNDDropATCSamples(int nSamples, int bySamples)
{
    insertSamples = - nSamples;
    insertSamplesTime = bySamples;
    return updateDSPSynch();
}

int SNDInsertATCSamples(int nSamples, int bySamples)
{
    insertSamples = nSamples;
    insertSamplesTime = bySamples;
    return updateDSPSynch();
}
