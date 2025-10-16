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
#undef abort
#endif SHLIB

/*
 * NXSoundOut.m
 *
 * Interface sound playback resources.
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved. 
 */

#import "NXSoundOut.h"
#import "NXSound_Private.h"
#import "audio.h"

@implementation NXSoundOut

/*
 * Look up the sound-out device port.
 * Returns PORT_NULL if look up fails.
 * Only sent by NXSoundDevice -initOnHost (private in 3.1).
 */
+ (port_t)lookUpDevicePortOnHost:(NSString *)hostName
{
    port_t devPort;
    kern_return_t kerr;

    kerr = _NXAudioSoundoutLookup([hostName cString], &devPort);
    if (kerr == KERN_SUCCESS)
	return devPort;
    else
	return PORT_NULL;
}

/*
 * ALL METHODS OBSOLETE FOR 3.1 -
 * replaced by generic parameter api.
 */

/*
 * PRIVATE.
 * Get sndout options.
 */
- (NXSoundDeviceError)_getSndoutOptions
{
    _kernelError = _NXAudioGetSndoutOptions(_devicePort, &_options,
					    [NXSoundDevice timeout]);
    return setLastError();
}

/*
 * Get and set options.
 */
- (BOOL)doesInsertZeros
{
    [self _getSndoutOptions];
    return (_options & _NXAUDIO_SNDOUT_ZEROFILL ? YES : NO);
}

- (NXSoundDeviceError)setInsertsZeros:(BOOL)flag
{
    if ([self _getSndoutOptions])
	return _lastError;
    else {
	if (flag)
	    _options |= _NXAUDIO_SNDOUT_ZEROFILL;
	else
	    _options &= ~_NXAUDIO_SNDOUT_ZEROFILL;
	_kernelError = _NXAudioSetSndoutOptions(_devicePort,
						_streamOwnerPort, _options,
						[NXSoundDevice timeout]);
	return setLastError();
    }
}

- (BOOL)doesRampUp
{
    [self _getSndoutOptions];
    return (_options & _NXAUDIO_SNDOUT_RAMPUP ? YES : NO);
}

- (NXSoundDeviceError)setRampsUp:(BOOL)flag
{
    if ([self _getSndoutOptions])
	return _lastError;
    else {
	if (flag)
	    _options |= _NXAUDIO_SNDOUT_RAMPUP;
	else
	    _options &= ~_NXAUDIO_SNDOUT_RAMPUP;
	_kernelError = _NXAudioSetSndoutOptions(_devicePort,
						_streamOwnerPort, _options,
						[NXSoundDevice timeout]);
	return setLastError();
    }
}

- (BOOL)doesRampDown
{
    [self _getSndoutOptions];
    return (_options & _NXAUDIO_SNDOUT_RAMPDOWN ? YES : NO);
}

- (NXSoundDeviceError)setRampsDown:(BOOL)flag
{
    if ([self _getSndoutOptions])
	return _lastError;
    else {
	if (flag)
	    _options |= _NXAUDIO_SNDOUT_RAMPDOWN;
	else
	    _options &= ~_NXAUDIO_SNDOUT_RAMPDOWN;
	_kernelError = _NXAudioSetSndoutOptions(_devicePort,
						_streamOwnerPort, _options,
						[NXSoundDevice timeout]);
	return setLastError();
    }
}

- (BOOL)doesDeemphasize
{
    [self _getSndoutOptions];
    return (_options & _NXAUDIO_SNDOUT_DEEMPHASIS ? YES : NO);
}

- (NXSoundDeviceError)setDeemphasis:(BOOL)flag
{
    if ([self _getSndoutOptions])
	return _lastError;
    else {
	if (flag)
	    _options |= _NXAUDIO_SNDOUT_DEEMPHASIS;
	else
	    _options &= ~_NXAUDIO_SNDOUT_DEEMPHASIS;
	_kernelError = _NXAudioSetSndoutOptions(_devicePort,
						_streamOwnerPort, _options,
						[NXSoundDevice timeout]);
	return setLastError();
    }
}

- (BOOL)isSpeakerMute
{
    [self _getSndoutOptions];
    return (_options & _NXAUDIO_SNDOUT_SPEAKER_ON ? NO : YES);
}

- (NXSoundDeviceError)setSpeakerMute:(BOOL)flag
{
    if ([self _getSndoutOptions])
	return _lastError;
    else {
	if (flag)
	    _options &= ~_NXAUDIO_SNDOUT_SPEAKER_ON;
	else
	    _options |= _NXAUDIO_SNDOUT_SPEAKER_ON;
	_kernelError = _NXAudioSetSndoutOptions(_devicePort,
						_streamOwnerPort, _options,
						[NXSoundDevice timeout]);
	return setLastError();
    }
}

/*
 * Get clip count.
 * Implemented in superclass for 3.1.
 */
- (unsigned int)clipCount
{
    return [super clipCount];
}

/*
 * Speaker attenuation range is -84 dB to 0 dB.
 */
- (NXSoundDeviceError)getAttenuationLeft:(float *)leftDB
                                   right:(float *)rightDB
{
    int lg, rg;

    _kernelError = _NXAudioGetSpeaker(_devicePort, &lg, &rg,
				      [NXSoundDevice timeout]);
    if (!setLastError()) {
	*leftDB = (float)lg;
	*rightDB = (float)rg;
    }
    return _lastError;
}

- (NXSoundDeviceError)setAttenuationLeft:(float)leftDB
                                   right:(float)rightDB
{
    _kernelError = _NXAudioSetSpeaker(_devicePort,
				      _streamOwnerPort,
				      (int)leftDB, (int)rightDB,
				      [NXSoundDevice timeout]);
    return setLastError();
}

@end

/*

Created by Mike Minnick 07/12/91.

Modification History:

02/10/92/mtm	Add getClipCount: (bug 18497).
03/10/92/mtm	Change getClipCount to clipCount (bug 19336).
01/22/92/mtm	3.1 changes.
 10/7/93 aozer	Changed to use NSString.
*/
