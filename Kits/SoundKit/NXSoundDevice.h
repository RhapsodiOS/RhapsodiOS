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
 * NXSoundDevice.h
 *
 * Copyright (c) 1992, NeXT Computer, Inc.  All rights reserved. 
 */

#import <Foundation/Foundation.h>
#import <mach/cthreads.h>
#import <mach/mach.h>
#import <limits.h>
#import "NXSoundParameters.h"

#define NX_SOUNDDEVICE_TIMEOUT_MAX	UINT_MAX
#define NX_SOUNDDEVICE_ERROR_MIN	300
#define NX_SOUNDDEVICE_ERROR_MAX	399

typedef enum _NXSoundDeviceError {
    NX_SoundDeviceErrorNone = 0,
    NX_SoundDeviceErrorKernel = NX_SOUNDDEVICE_ERROR_MIN,
    NX_SoundDeviceErrorTimeout,
    NX_SoundDeviceErrorLookUp,
    NX_SoundDeviceErrorHost,
    NX_SoundDeviceErrorNoDevice,
    NX_SoundDeviceErrorNotActive,
    NX_SoundDeviceErrorTag,
    NX_SoundDeviceErrorParameter,
    NX_SoundDeviceErrorMax = NX_SOUNDDEVICE_ERROR_MAX
} NXSoundDeviceError;

extern float SNDConvertDecibelsToLinear(float dB);
extern float SNDConvertLinearToDecibels(float linear);

@interface NXSoundDevice : NSObject <NXSoundParameters>
{
    NSString *_host;
    port_t		_devicePort;
    port_t		_streamOwnerPort;
    unsigned int	_bufferSize;
    unsigned int	_bufferCount;
    unsigned int	_isDetectingPeaks;
    unsigned int	_peakHistory;
    kern_return_t	_kernelError;
    NXSoundDeviceError	_lastError;
    int			_reserved;
}
+ (NSString *)textForError:(NXSoundDeviceError)errorCode;
+ (unsigned int)timeout;
+ setTimeout:(unsigned int)milliseconds;
+ (port_t)replyPort;
+ (BOOL)isUsingSeparateThread;
+ setUseSeparateThread:(BOOL)flag;
+ (cthread_t)replyThread;
+ (int)threadThreshold;
+ setThreadThreshold:(int)threshold;

// New in 3.1.
- (id <NXSoundParameters>)parameters;
- (NXSoundDeviceError)setParameters:(id <NXSoundParameters>)params;
- (BOOL)acceptsContinuousStreamSamplingRates;
- (NXSoundDeviceError)getStreamSamplingRatesLow:(float *)lowRate
    high:(float *)highRate;
- (NXSoundDeviceError)getStreamSamplingRates:(const float **)rates
    count:(unsigned int *)numRates;
- (NXSoundDeviceError)getStreamDataEncodings:
    (const NXSoundParameterTag **)encodings
    count:(unsigned int *)numEncodings;
- (unsigned int)streamChannelCountLimit;
- (unsigned int)clipCount;
- (NSString *)name;

- (id)init;
- (id)initOnHost:(NSString *)hostName;
- (NSString *)host;
- (port_t)devicePort;
- (port_t)streamOwnerPort;
- (BOOL)isReserved;
- (NXSoundDeviceError)setReserved:(BOOL)flag;
- (void)pauseStreams:sender;
- (void)resumeStreams:sender;
- (void)abortStreams:sender;
- (NXSoundDeviceError)getPeakLeft:(float *)leftAmp
                            right:(float *)rightAmp;
- (NXSoundDeviceError)lastError;
- (void)dealloc;

// Obsolete - use generic parameter api.
- (unsigned int)bufferSize;
- (NXSoundDeviceError)setBufferSize:(unsigned int)bytes;
- (unsigned int)bufferCount;
- (NXSoundDeviceError)setBufferCount:(unsigned int)count;
- (unsigned int)peakHistory;
- (NXSoundDeviceError)setPeakHistory:(unsigned int)bufferCount;
- (BOOL)isDetectingPeaks;
- (NXSoundDeviceError)setDetectPeaks:(BOOL)flag;

@end
