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
 * NXPlayStream.m
 *
 * Play sound data.
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved. 
 */

#import "NXPlayStream.h"
#import "NXSoundDevice.h"
#import "NXSound_Private.h"
#import "NXSoundStream_Private.h"
#import "audio.h"

@implementation NXPlayStream

/*
 * Override to set default parameters.
 */
- initOnDevice:anObject
{
    [super initOnDevice:anObject];
    _leftGain = _rightGain = 1.0;
    _peakHistory = 1;
    return self;
}

/*
 * Override to set parameters.
 */
- (NXSoundDeviceError)activate
{
    /* No need to override in 3.1 */
    return [super activate];
}

/*
 * Get and set stream gain.
 */
- (void)getGainLeft:(float *)leftAmp right:(float *)rightAmp
{
    if (!_isActive && _initParams) {
	if ([_initParams isParameterPresent:NX_SoundStreamGainLeft])
	    *leftAmp =
		[_initParams floatValueForParameter:NX_SoundStreamGainLeft];
	else
	    *leftAmp = _leftGain;
	if ([_initParams isParameterPresent:NX_SoundStreamGainRight])
	    *rightAmp =
		[_initParams floatValueForParameter:NX_SoundStreamGainRight];
	else
	    *rightAmp = _rightGain;
    } else {
	*leftAmp = _leftGain;
	*rightAmp = _rightGain;
    }
}

- (NXSoundDeviceError)setGainLeft:(float)leftAmp right:(float)rightAmp
{
    if (leftAmp < 0.0)
	leftAmp = 0.0;
    if (rightAmp < 0.0)
	rightAmp = 0.0;

    if (!_isActive) {
	_leftGain = leftAmp;
	_rightGain = rightAmp;
	if (_initParams) {
	    [_initParams
	        setParameter:NX_SoundStreamGainLeft toFloat:_leftGain];
	    [_initParams
	        setParameter:NX_SoundStreamGainRight toFloat:_rightGain];
	}
	return (_lastError = NX_SoundDeviceErrorNone);
    }
    _kernelError = _NXAudioSetStreamGain(_streamPort,
					 leftAmp*32768.0, rightAmp*32768.0,
					 [NXSoundDevice timeout]);
    if (!setLastError()) {
	_leftGain = leftAmp;
	_rightGain = rightAmp;
    }
    return _lastError;
}

/*
 * Peak detection.
 */
- (BOOL)isDetectingPeaks
{
    if (!_isActive && _initParams &&
	[_initParams isParameterPresent:NX_SoundStreamDetectPeaks])
	return [_initParams boolValueForParameter:NX_SoundStreamDetectPeaks];
    else
	return _isDetectingPeaks;
}

- (NXSoundDeviceError)setDetectPeaks:(BOOL)flag
{
    if ((_isDetectingPeaks && flag) ||
	(!_isDetectingPeaks && !flag))
	return (_lastError = NX_SoundDeviceErrorNone);
    if (!_isActive) {
	_isDetectingPeaks = flag;
	if (_initParams)
	    [_initParams
	        setParameter:NX_SoundStreamDetectPeaks
	        toBool:_isDetectingPeaks];
	return (_lastError = NX_SoundDeviceErrorNone);
    }
    _kernelError = _NXAudioSetStreamPeakOptions(_streamPort,
						(u_int)flag, _peakHistory,
						[NXSoundDevice timeout]);
    if (!setLastError())
	_isDetectingPeaks = flag;
    return _lastError;
}

// No longer supported.
- (unsigned int)peakHistory
{
    return _peakHistory;
}

// No longer supported.
- (NXSoundDeviceError)setPeakHistory:(unsigned int)bufferCount
{
    if (!_isActive) {
	_peakHistory = bufferCount;
	return (_lastError = NX_SoundDeviceErrorNone);
    }
    _kernelError = _NXAudioSetStreamPeakOptions(_streamPort,
						_isDetectingPeaks,
						bufferCount,
						[NXSoundDevice timeout]);
    if (!setLastError())
	_peakHistory = bufferCount;
    return _lastError;
}

- (NXSoundDeviceError)getPeakLeft:(float *)leftAmp
                            right:(float *)rightAmp
{
    u_int magLeft, magRight;

    if (!_isActive) {
	_lastError = (_lastError = NX_SoundDeviceErrorNotActive);
	return _lastError;
    }
    _kernelError = _NXAudioGetStreamPeak(_streamPort, &magLeft, &magRight,
					 [NXSoundDevice timeout]);
    if (!setLastError()) {
	*leftAmp = (float)magLeft / 32767.0;
	*rightAmp = (float)magRight / 32767.0;
    }
    return _lastError;
}

// New for 3.1.
- (NXSoundDeviceError)playBuffer:(void *)data
                            size:(unsigned int)bytes
                             tag:(int)tag
{
    if (!_isActive)
	return (_lastError = NX_SoundDeviceErrorNotActive);
    if (tag < 0)
	return (_lastError = NX_SoundDeviceErrorTag);
    if (!bytes)
	return (_lastError = NX_SoundDeviceErrorNone);

    _kernelError = _NXAudioPlayStreamData(_streamPort, (pointer_t)data,
					  bytes, tag,
					  [NXSoundDevice replyPort],
					  _delegateMessages,
					  [NXSoundDevice timeout]);
    return setLastError();
}

// Obsoleted for 3.1
/*
 * Enqueue playback buffer.
 * Negative tags are reserved.
 * Channels must be 1 or 2.
 * Sampling rate must be 44100.0 or 22050.0.
 * Stream gain is scaled by bufferGain to get final
 * amplitude.
 */
- (NXSoundDeviceError)playBuffer:(void *)data
                            size:(unsigned int)bytes
                             tag:(int)tag
                    channelCount:(unsigned int)channels
                    samplingRate:(float)rate
                  bufferGainLeft:(float)leftAmp right:(float)rightAmp
                    lowWaterMark:(unsigned int)lowWater
                   highWaterMark:(unsigned int)highWater
{
    if (!_isActive)
	return (_lastError = NX_SoundDeviceErrorNotActive);
    if (tag < 0)
	return (_lastError = NX_SoundDeviceErrorTag);
    if (!bytes)
	return (_lastError = NX_SoundDeviceErrorNone);
    if (leftAmp < 0.0)
	leftAmp = 0.0;
    if (rightAmp < 0.0)
	rightAmp = 0.0;

    _kernelError = _NXAudioPlayStream(_streamPort, (pointer_t)data,
				      bytes, tag, channels,
				      ((int)rate == 22050 ?
				       _NXAUDIO_RATE_22050 :
				       _NXAUDIO_RATE_44100),
				      leftAmp*32768.0, rightAmp*32768.0,
				      lowWater, highWater,
				      [NXSoundDevice replyPort],
				      _delegateMessages,
				      [NXSoundDevice timeout]);
    return setLastError();
}

// Obsoleted for 3.1
- (NXSoundDeviceError)playBuffer:(void *)data
                            size:(unsigned int)bytes
                             tag:(int)tag
                    channelCount:(unsigned int)channels
                    samplingRate:(float)rate
{
    return [self playBuffer:data
                       size:bytes
                        tag:tag
               channelCount:channels
               samplingRate:rate
             bufferGainLeft:1.0 right:1.0
               lowWaterMark:(512*1024)
              highWaterMark:(768*1024)];
}

@end

/*

Created by Mike Minnick 07/12/91.

Modification History:

01/22/93/mtm	3.1 api.

*/
