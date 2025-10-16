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
 *	atcsound.h - features related to Audio Transform Compression (ATC).
 */

/*
 * In all functions below, the return value is 0 for success and
 * nonzero for failure.  A failure return generally means the feature is
 * not available (e.g., on non-NeXT hardware).
 */

int SNDGetNumberOfATCBands(int *nBandsP);
/*
 * Get number of frequency bands used by ATC (40 in release 3.0).
 * The band frequencies correspond roughly to the critical
 * bands of hearing.  Band 0 is "D.C.", meaning it is centered
 * at 0 Hz.  At higher frequencies the bands are wider and 
 * spaced farther apart.  The band width and spacing are approximately
 * 20% of the band center-frequency above 500 Hz, and uniform
 * below 500 Hz.  These remarks apply to the standard 44.1 kHz sampling rate.
 * At other sampling rates, the bands frequencies are scaled so that the same
 * number of bands covers 0 Hz to half the sampling rate, whatever it is.
 */


int SNDGetATCBandFrequencies(int nBands, float *centerFreqs);
int SNDGetATCBandwidths(int nBands, float *bandwidths);
/*
 * Get center-frequency or bandwidth in Hertz for each band used by ATC.
 * Assumes a 44.1 kHz sampling-rate.
 */


int SNDGetATCEqualizerGains(int nBands, float *gains);
int SNDSetATCEqualizerGains(int nBands, float *gains);
int SNDScaleATCEqualizerGains(int nBands, float *gainScales);
/*
 * Get/set/scale graphic-equalizer gains for ATC playback.
 * Obtain nBands from SNDGetNumberOfATCBands().  Each gain specifies a
 * factor to be multiplied times the band amplitude during sound playback.
 * The gain can be any nonnegative number, although there is an 
 * internal maximum limit. Only gains between 0.0 and 1.0 will not 
 * cause output overflow under all conditions.  If overflow occurs, the
 * result will be clipped.  The system default gain is 1.0 in each band 
 * (no equalization).  Changes take effect for the next sound played, i.e.,
 * any currently playing sound is unaffected.
 */


int SNDGetATCSquelchThresholds(int nBands, float *thresh);
int SNDSetATCSquelchThresholds(int nBands, float *thresh);

int SNDUseDefaultATCSquelchThresholds(void);
/*
 * Get/set "squelch" levels used in ATC encoding.
 * Obtain nBands from SNDGetNumberOfATCBands().  Each level specifies a
 * threshold below which sound amplitudes are set to zero.
 * Tbe band frequencies are the same as those used in the graphic equalizer.
 * 
 * The squelch thresholds trade sound quality for greater compression.
 * The higher the squelch thresholds, the greater the compression.  
 * However, setting the thresholds too high will introduce sonic artifacts.
 *
 * It is possible to use the squelch threshold to suppress noise in 
 * a recording, especially when that noise is steady, such as tape hiss
 * or static hum.
 * 
 * A squelch threshold of 1.0 is considered to be the nominal maximum.
 * Therefore, a value of 1.0 for thresh[i] 
 * implies band i is rejected almost always.  A value of -120.0
 * ensures band i is never squelched.  
 *
 * The system default squelch thresholds are set to the estimated threshold 
 * of hearing in each band, assuming a normal listening level for the sound 
 * output.  The system default can always be restored by calling
 * SNDUseDefaultATCSquelchThresholds().
 *
 * Changes take effect for the next sound encoded, i.e.,
 * any currently compressing sound is unaffected.
 */


int SNDGetATCGain(float *oLevelP);
int SNDSetATCGain(float oLevel);
/*
 * Get/set overall sound output level for ATC sound playback (in decibels).
 * A value of 1.0 means no change.  A value of 0.0 will silence any sound.
 * Note that this volume setting affects "line out" as well as the speaker
 * output.  (It is implemented as a scaling of the ATC equalizer gains.)
 * Changes take effect for the next sound played.
 */

int SNDDropATCSamples(int nSamples, int bySamples);
int SNDInsertATCSamples(int nSamples, int bySamples);
/*
 * These functions provide a crude level of support for ATC sound 
 * synchronization. By dropping or inserting samples,
 * time can be "warped" in the playback of an ATC sound.
 * To determine when to insert or drop samples, SNDSamplesProcessed()
 * can be called to obtain an estimate of how many samples have been
 * played out, and this can be compared to some other source of
 * time in units of samples at the current sampling rate.
 *
 * If bySamples is zero, the samples are inserted or dropped when
 * convenient by the algorithm (one sample per 256-sample frame).
 * Otherwise, an attempt is made to add or drop the requested number
 * of samples within bySamples samples.  Outrageous requests may produce
 * outrageous results.
 * 
 * If bySamples is negative, the drop or insert request is repeated
 * indefinitely.  It is equivalent to renewing the request every 
 * abs(bySamples) samples.  This hack can be used to effect a speed control.
 * The formula is dropSamples = (int)(((float)bySamples)*(1. - 1./speed)+0.5),
 * where speed==1.0 means no change, speed==2.0 means play twice as fast, etc.
 * 
 * Inserting or dropping samples should not cause a click in the 
 * sound, but it will cause some distortion.
 * 
 * The samples to insert or drop are selected randomly by system software
 * at the time the call is received.  An ATC sound must be actively playing
 * for these calls to have effect.
 */
