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
 * NXPlayStream.h
 *
 * Copyright (c) 1992, NeXT Computer, Inc.  All rights reserved. 
 */

#import "NXSoundStream.h"

@interface NXPlayStream:NXSoundStream
{
    float		_leftGain;
    float		_rightGain;
    BOOL		_isDetectingPeaks;
    unsigned int	_peakHistory;
    int			_reserved1;
}

- (id)initOnDevice:(id)anObject;
- (NXSoundDeviceError)activate;
- (void)getGainLeft:(float *)leftAmp right:(float *)rightAmp;
- (NXSoundDeviceError)setGainLeft:(float)leftAmp right:(float)rightAmp;
- (NXSoundDeviceError)getPeakLeft:(float *)leftAmp
                            right:(float *)rightAmp;

// New for 3.1.
- (NXSoundDeviceError)playBuffer:(void *)data
                            size:(unsigned int)bytes
                             tag:(int)anInt;

// Obsolete - use generic parameter api.
- (NXSoundDeviceError)playBuffer:(void *)data
                            size:(unsigned int)bytes
                             tag:(int)anInt
                    channelCount:(unsigned int)channels
                    samplingRate:(float)rate
                  bufferGainLeft:(float)leftAmp right:(float)rightAmp
                    lowWaterMark:(unsigned int)lowWater
                   highWaterMark:(unsigned int)highWater;
- (NXSoundDeviceError)playBuffer:(void *)data
                            size:(unsigned int)bytes
                             tag:(int)anInt
                    channelCount:(unsigned int)channels
                    samplingRate:(float)rate;
- (BOOL)isDetectingPeaks;
- (NXSoundDeviceError)setDetectPeaks:(BOOL)flag;
- (unsigned int)peakHistory;
- (NXSoundDeviceError)setPeakHistory:(unsigned int)bufferCount;

@end

@interface NSObject(NXPlayStreamDelegate)
- (void)soundStreamDidUnderrun:(id)sender;
@end
