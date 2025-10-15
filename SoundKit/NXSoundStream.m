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
 * NXSoundStream.m
 *
 * Superclass for sound streams.
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved. 
 */

#import "NXSoundStream.h"
#import "NXSoundDevice.h"
#import "NXPlayStream.h"
#import "NXRecordStream.h"
#import "NXSound_Private.h"
#import "NXSoundStream_Private.h"
#import "audio.h"
#import <mach/mach.h>
//#import <AppKit/nextstd.h>

@implementation NXSoundStream

/*
 * PRIVATE.
 * Enable stream messages to delegate.
 */
- _setDelegateMessages
{
    /*
     * Optimization - don't make driver send these messages
     * if delegate doesn't respond to them.
     */
    if (delegate) {
	if ([delegate respondsToSelector:@selector(soundStream:didStartBuffer:)])
	        _delegateMessages |= _NXAUDIO_MSG_STARTED;
	if ([delegate respondsToSelector:@selector(soundStream:didCompleteBuffer:)])
	        _delegateMessages |= _NXAUDIO_MSG_COMPLETED;
	if ([delegate respondsToSelector:@selector(soundStreamDidAbort:
					   deviceReserved:)])
	        _delegateMessages |= _NXAUDIO_MSG_ABORTED;
	if ([delegate respondsToSelector:@selector(soundStreamDidUnderrun:)] ||
	        [delegate respondsToSelector:@selector(soundStreamDidOverrun:)])
	        _delegateMessages |= _NXAUDIO_MSG_UNDERRUN;
    }
    return self;
}

/*
 * PRIVATE.
 * Reply to status message.
 */
- _replyToDelegateStatus:(int)status forBuffer:(int)tag
{
    if (status == _NXAUDIO_STATUS_PAUSED)
	_isPaused = YES;
    else if (status == _NXAUDIO_STATUS_RESUMED)
	_isPaused = NO;

    if (delegate)
	switch (status) {
	  case _NXAUDIO_STATUS_STARTED:
	    if ([delegate respondsToSelector:
		 @selector(soundStream:didStartBuffer:)])
		[delegate soundStream:self didStartBuffer:tag];
	    break;
	  case _NXAUDIO_STATUS_COMPLETED:
	    if ([delegate respondsToSelector:
		 @selector(soundStream:didCompleteBuffer:)])
		[delegate soundStream:self didCompleteBuffer:tag];
	    break;
	  case _NXAUDIO_STATUS_PAUSED:
	    if ([delegate respondsToSelector:@selector(soundStreamDidPause:)])
		[delegate soundStreamDidPause:self];
	    break;
	  case _NXAUDIO_STATUS_RESUMED:
	    if ([delegate respondsToSelector:
		 @selector(soundStreamDidResume:)])
		[delegate soundStreamDidResume:self];
	    break;
	  case _NXAUDIO_STATUS_ABORTED:
	    if ([delegate respondsToSelector:
		 @selector(soundStreamDidAbort:deviceReserved:)])
		[delegate soundStreamDidAbort:self deviceReserved:NO];
	    break;
	  case _NXAUDIO_STATUS_UNDERRUN:
	    if ([self isKindOfClass:[NXPlayStream class]] &&
		[delegate respondsToSelector:@selector(soundStreamDidUnderrun:)])
		[delegate soundStreamDidUnderrun:self];
	    else if ([self isKindOfClass:[NXRecordStream class]] &&
		     [delegate respondsToSelector:@selector(soundStreamDidOverrun:)])
		[delegate soundStreamDidOverrun:self];
	    break;
	  case _NXAUDIO_STATUS_EXCLUDED:
	    if ([delegate respondsToSelector:
		 @selector(soundStreamDidAbort:deviceReserved:)])
		[delegate soundStreamDidAbort:self deviceReserved:YES];
	    break;
	  default:
	    NSLog(@"NXSoundStream: bad status %d\n", status);
	    break;
	}
    return self;
}

/*
 * PRIVATE.
 * Reply to recorded data message.
 */
- _replyToDelegateRecordedData:(void *)data size:(unsigned int)bytes
                     forBuffer:(int)tag
{
    if ([self isKindOfClass:[NXRecordStream class]] &&
	delegate && [delegate respondsToSelector:
		     @selector(soundStream:didRecordData:size:forBuffer:)])
	[delegate soundStream:self didRecordData:data size:bytes
                    forBuffer:tag];
    else
	/*
	 * Somebody has to do it!
	 */
	vm_deallocate(task_self(), (vm_address_t)data, bytes);
    return self;
}

/*
 * Initialize on a NXSoundDevice.
 */
- (id)init
{
    return [self initOnDevice:nil];
}

- initOnDevice:anObject
{
    [super init];
    _device = anObject;
    /*
     * Must react to these messages so _isPaused is updated.
     */
    _delegateMessages = _NXAUDIO_MSG_PAUSED | _NXAUDIO_MSG_RESUMED;

    /* Instance variable extension */
    (streamVars *)_reserved = (streamVars *)calloc(1, sizeof(streamVars));

    return self;
}

// Parameter stuff new in 3.1

- initOnDevice:aDevice withParameters:(id <NXSoundParameters>)params
{
    NXSoundParameterTag *plist;
    unsigned int numParams;
    int i, intVal;
    float floatVal;

    [self initOnDevice:aDevice];
    if (!params)
	return self;
    /*
     * Copy parameters to new params object as ints.
     */
    _initParams = [[NXSoundParameters alloc] init];
    [params getParameters:&plist count:&numParams];
    for (i = 0; i < numParams; i++) {
	switch(plist[i]) {
	    /*
	     * Gains are 0 to 1.0 and need conversion to int.
	     */
	  case NX_SoundStreamGainStereo:
	  case NX_SoundStreamGainLeft:
	  case NX_SoundStreamGainRight:
	    floatVal = [params floatValueForParameter:plist[i]];
	    intVal = floatVal * 32768.0;
	    break;
	  default:
	    intVal = [params intValueForParameter:plist[i]];
	    break;
	}
	[_initParams setParameter:plist[i] toInt:intVal];
    }
    return self;
}

- (id <NXSoundParameters>)parameters
{
    audio_array_t plist, vlist;
    u_int paramCount = _NXAUDIO_PARAM_MAX;
    int i;

    if (!_isActive)
	return _initParams;

    /*
     * Lifetime of returned object is until the next time
     * this method is invoked.
     */
    if (_retParams)
	 [_retParams release];
    _retParams = [[NXSoundParameters alloc] init];

    _kernelError =
	_NXAudioGetStreamSupportedParameters(_streamPort,
					     plist, &paramCount,
					     [NXSoundDevice timeout]);
    if (setLastError() || (paramCount == 0))
	return nil;
    _kernelError =
	_NXAudioGetStreamParameters(_streamPort, plist, paramCount, vlist,
				    [NXSoundDevice timeout]);
    if (setLastError())
	return nil;

    for (i = 0; i < paramCount; i++) {
	switch(plist[i]) {
	    /*
	     * Gains are 0 to 1.0 and need conversion from int.
	     */
	  case NX_SoundStreamGainStereo:
	  case NX_SoundStreamGainLeft:
	  case NX_SoundStreamGainRight:
	    [_retParams setParameter:plist[i]
	        toFloat:(float)vlist[i] / 32768.0];
	    break;
	  default:
	    [_retParams setParameter:plist[i] toInt:vlist[i]];
	    break;
	}
    }
    return _retParams;
}
	
- device
{
    return _device;
}

- (NXSoundDeviceError)setDevice:anObject
{
    if (!_isActive) {
	_device = anObject;
	return (_lastError = NX_SoundDeviceErrorNone);
    }
    _kernelError = _NXAudioChangeStreamOwner(_streamPort,
					     [anObject streamOwnerPort],
					     [NXSoundDevice timeout]);
    if (!setLastError())
	_device = anObject;
    return _lastError;
}

/*
 * Get stream port.
 */
- (port_t)streamPort
{
    return _streamPort;
}

/*
 * Activate and deactivate.
 * Activate returns nil if stream cannot be activated.
 */
- (BOOL)isActive
{
    return _isActive;
}

- (NXSoundDeviceError)activate
{
    NXSoundParameterTag *plist;
    unsigned int numParams;
    audio_array_t param_array;
    audio_array_t value_array;
    int i;

    if (_isActive)
	return (_lastError = NX_SoundDeviceErrorNone);
    if (!_device)
	return (_lastError = NX_SoundDeviceErrorNoDevice);
    _kernelError = _NXAudioAddStream([_device devicePort], &_streamPort,
				     [_device streamOwnerPort], (int)self,
				     _NXAUDIO_STREAM_TYPE_USER,
				     [NXSoundDevice timeout]);
    if (setLastError())
	return _lastError;

    _isActive = YES;
    if (!_initParams)
	return _lastError;

    [_initParams getParameters:&plist count:&numParams];
    if (numParams == 0)
	return _lastError;
    for (i = 0; i < numParams; i++) {
	param_array[i] = plist[i];
	value_array[i] = [_initParams intValueForParameter:plist[i]];
    }

    _kernelError =
	_NXAudioSetStreamParameters(_streamPort, param_array,
				    numParams, value_array,
				    [NXSoundDevice timeout]);
    return setLastError();
}

- (NXSoundDeviceError)deactivate
{
    if (!_isActive)
	return (_lastError = NX_SoundDeviceErrorNone);

    _kernelError = _NXAudioRemoveStream(_streamPort, [NXSoundDevice timeout]);
    _streamPort = PORT_NULL;
    _isActive = _isPaused = NO;
    return setLastError();
}

/*
 * Stream control.
 */
- (BOOL)isPaused
{
    return _isPaused;
}

- (void)pause:sender
{
    NXSoundStreamTime now = {0,0};

    if (_isActive) {
	_kernelError = _NXAudioStreamControl(_streamPort,
					     _NXAUDIO_STREAM_PAUSE,
					     now, [NXSoundDevice timeout]);
	setLastError();
    }
}

- (void)resume:sender
{
    NXSoundStreamTime now = {0,0};

    if (_isActive) {
	_kernelError = _NXAudioStreamControl(_streamPort,
					     _NXAUDIO_STREAM_RESUME,
					     now, [NXSoundDevice timeout]);
	setLastError();
    }
}

- (void)abort:sender
{
    NXSoundStreamTime now = {0,0};

    if (_isActive) {
	_kernelError = _NXAudioStreamControl(_streamPort,
					     _NXAUDIO_STREAM_ABORT,
					     now, [NXSoundDevice timeout]);
	setLastError();
    }
}

- (unsigned int)bytesProcessed
{
    unsigned int bytes;

    if (!_isActive)
	return 0;

    _kernelError = _NXAudioStreamInfo(_streamPort, &bytes,
				      [NXSoundDevice timeout]);
    return setLastError() ? 0 : bytes;
}

/*
 * Error handling.
 */
- (NXSoundDeviceError)lastError
{
    return _lastError;
}

/*
 * Get and set delegate.
 */
- (id)delegate
{
    return delegate;
}

- (void)setDelegate:(id)anObject
{
    delegate = anObject;
    [self _setDelegateMessages];
}

/*
 * Release resources and free object.
 */
- (void)dealloc
{
    [self deactivate];
    if (_reserved) {
	if (_retParams)
	     [_retParams release];
	free((streamVars *)_reserved);
    }
    [super dealloc];
}

/*
 * Action at time methods changed to use struct timeval
 * for 3.1.
 */

- (NXSoundDeviceError)pauseAtTime:(struct timeval *)time
{
    struct timeval now = {0,0};

    if (!_isActive)
	return (_lastError = NX_SoundDeviceErrorNotActive);
    _kernelError = _NXAudioStreamControl(_streamPort,
					 _NXAUDIO_STREAM_PAUSE,
					 (time ? *time : now),
					 [NXSoundDevice timeout]);
    return setLastError();
}

- (NXSoundDeviceError)resumeAtTime:(struct timeval *)time
{
    struct timeval now = {0,0};

    if (!_isActive)
	return (_lastError = NX_SoundDeviceErrorNotActive);
    _kernelError = _NXAudioStreamControl(_streamPort,
					 _NXAUDIO_STREAM_RESUME,
					 (time ? *time : now),
					 [NXSoundDevice timeout]);
    return setLastError();
}

- (NXSoundDeviceError)abortAtTime:(struct timeval *)time
{
    struct timeval now = {0,0};

    if (!_isActive)
	return (_lastError = NX_SoundDeviceErrorNotActive);
    _kernelError = _NXAudioStreamControl(_streamPort,
					 _NXAUDIO_STREAM_ABORT,
					 (time ? *time : now),
					 [NXSoundDevice timeout]);
    return setLastError();
}

@end

/*

Created by Mike Minnick 07/12/91.

Modification History:

03/19/92/mtm	Fix delegate messages.
04/07/92/mtm	Send appropriate overrun/underrun message to delegate.
01/20/93/mtm	3.1 api.

*/
