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
 * NXSoundDevice.m
 *
 * Superclass for sound devices.
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved. 
 */

#import "obsolete.h"
#import "NXSoundDevice.h"
#import "NXSoundOut.h"
#import "NXSoundIn.h"
#import "NXSound_Private.h"
#import "NXSoundStream.h"
#import "audio.h"
#import "audioReplyHandler.h"
#import "NXSoundThreshold_Private.h"
#import <AppKit/NSApplication.h>
#import <math.h>
#import <mach/cthreads.h>
#import <bsd/sys/types.h>
#import	<mach/mach_error.h>
#import <servers/netname.h>
#import <objc/objc-runtime.h>
#import <defaults/defaults.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSDPSContextPrivate.h>

/*
 * Factory variables.
 */
static unsigned int timeout = NX_SOUNDDEVICE_TIMEOUT_MAX;
static BOOL useSeparateThread = NO;
static port_t replyPort = PORT_NULL;
static int threadThreshold = NSModalResponseThreshold;
static cthread_t replyThread = NO_CTHREAD;
static BOOL threadInitialized = NO;

/*
 * Instance vars extension.
 */
typedef struct _instVars {
    NXSoundParameters	*retParams;
    NXSoundParameterTag	*retTags;
    NXSoundParameterTag	*retValues;
    NXSoundParameterTag	*streamEncodings;
    float	        *streamRates;
    NSString *name;
} instVars;

#define	_retParams		(((instVars *)_reserved)->retParams)
#define	_retTags		(((instVars *)_reserved)->retTags)
#define	_retValues		(((instVars *)_reserved)->retValues)
#define	_streamEncodings	(((instVars *)_reserved)->streamEncodings)
#define	_streamRates		(((instVars *)_reserved)->streamRates)
#define	_name			(((instVars *)_reserved)->name)

@implementation NXSoundDevice

/*
 * Convert dB to linear, and linear to dB.
 */
float SNDConvertDecibelsToLinear(float dB)
{
    return (float)pow(10.0, (double)dB/20.0);
}

float SNDConvertLinearToDecibels(float linear)
{
    return (float)(20.0 * log10((double)linear));
}

/*
 * PRIVATE.
 * Convert kernel error to sound device error.
 */
+ (NXSoundDeviceError)_convertToSoundDeviceError:(kern_return_t)kernelError
{
    switch (kernelError) {
      case KERN_SUCCESS:
	return NX_SoundDeviceErrorNone;
      case RCV_TIMED_OUT:
      case SEND_TIMED_OUT:
	return NX_SoundDeviceErrorTimeout;
      case NETNAME_NOT_CHECKED_IN:
	return NX_SoundDeviceErrorLookUp;
      case NETNAME_NO_SUCH_HOST:
      case NETNAME_HOST_NOT_FOUND:
	return NX_SoundDeviceErrorHost;
      case _NXAUDIO_ERR_PARAMETER:
	return NX_SoundDeviceErrorParameter;
      default:
	return NX_SoundDeviceErrorKernel;
    }
}

/*
 * Handle stream status reply messages.
 */
static kern_return_t reply_stream_status(void *arg, port_t stream_port,
					 port_t reply_port,
					 int stream_id, int tag, int status)
{
    NXSoundStream *stream = (NXSoundStream *)stream_id;

    if (!stream)
	NSLog(@"NXSoundDevice: zero stream id\n");
    else
	[stream _replyToDelegateStatus:status forBuffer:tag];
    return KERN_SUCCESS;
}

/*
 * Handle stream recorded data reply messages.
 */
static kern_return_t reply_recorded_data(void *arg, port_t stream_port,
					 port_t reply_port, int stream_id,
					 int tag, void *data, u_int bytes)
{
    NXSoundStream *stream = (NXSoundStream *)stream_id;

    if (!stream)
	NSLog(@"NXSoundDevice: zero stream id\n");
    else
	[stream _replyToDelegateRecordedData:data size:bytes forBuffer:tag];
    return KERN_SUCCESS;
}

/*
 * Driver reply handler functions sturcture.
 */
static _NXAudioReply audio_reply = {
    reply_stream_status,
    reply_recorded_data,
    0,
    0
};

/*
 * _NSSKPortProc to handle driver reply messages.
 */
static void reply_message(msg_header_t *msg, void *userData)
{
    kern_return_t kerr;

    kerr = _NXAudioReplyHandler(msg, &audio_reply);
    if (kerr)
	NSLog(@"NXSoundDevice: _NXAudioReplyHandler failed (%d): %s\n",
		   kerr, mach_error_string(kerr));
}

/*
 * Thread to receive ansynchronous driver messages when using separate thread.
 */
static any_t reply_thread(any_t args)
{
    msg_header_t *msg;
    kern_return_t kerr;

    msg = (msg_header_t *)malloc(_NXAUDIO_REPLY_INMSG_SIZE);

    while (1) {
	msg->msg_size = _NXAUDIO_REPLY_INMSG_SIZE;
	msg->msg_local_port = replyPort;
	kerr = msg_receive(msg, MSG_OPTION_NONE, 0);
	if (kerr != KERN_SUCCESS) {
	    NSLog(@"NXSoundDevice: msg_receive failed (%d):%s\n",
		       kerr, mach_error_string(kerr));
	} else {
	    kerr = _NXAudioReplyHandler(msg, &audio_reply);
	    if (kerr)
		NSLog(@"NXSoundDevice: ",
			   "_NXAudioReplyHandler failed (%d): %s\n",
			   kerr, mach_error_string(kerr));
	}
    }
    return NULL;
}

/*
 * Fork a cthread to handle driver reply messages.
 */
static kern_return_t initializeThread()
{
    kern_return_t kerr = KERN_SUCCESS;

    if (threadInitialized)
	return KERN_SUCCESS;

    kerr = port_allocate(task_self(), &replyPort);
    if (kerr)
	return kerr;
    /*
     * FIXME: this is just a patch - driver could still loose messages
     * if reply port is full.  Driver needs to be fixed to hold
     * messages in a queue and return them eventually.
     */
    kerr = port_set_backlog(task_self(), replyPort, PORT_BACKLOG_MAX);
    if (kerr)
	return kerr;

    if (useSeparateThread || !NSApp) {
	/*
	 * OBJC is only totally thread-safe if you call this.
	 */
	objc_setMultithreaded(YES);
	cthread_detach(replyThread = cthread_fork(reply_thread, (any_t)0));
    } else
	_NSSKAddPort(replyPort, (_NSSKPortProc)&reply_message,
		   _NXAUDIO_REPLY_INMSG_SIZE, 0, threadThreshold);

    threadInitialized = YES;
    return kerr;
}

/*
 * Factory methods.
 */

/*
 * Localizable strings.
 */
extern NSBundle * _NSSKBundle;

#define LSTRING_NO_ERROR [_NSSKBundle localizedStringForKey:@"No error" value:nil table:@"SoundKit"]
#define LSTRING_KERNEL_ERROR [_NSSKBundle localizedStringForKey:@"Kernel Error" value:nil table:@"SoundKit"]
#define LSTRING_TIMEOUT_ERROR [_NSSKBundle localizedStringForKey:@"Timeout" value:nil table:@"SoundKit"]
#define LSTRING_LOOKUP_ERROR [_NSSKBundle localizedStringForKey:@"Look up failed" value:nil table:@"SoundKit"]
#define LSTRING_HOST_ERROR [_NSSKBundle localizedStringForKey:@"Bad host name" value:nil table:@"SoundKit"]
#define LSTRING_NODEVICE_ERROR [_NSSKBundle localizedStringForKey:@"Stream has no device" value:nil table:@"SoundKit"]
#define LSTRING_NOTACTIVE_ERROR [_NSSKBundle localizedStringForKey:@"Stream is not active" value:nil table:@"SoundKit"]
#define LSTRING_TAG_ERROR [_NSSKBundle localizedStringForKey:@"Invalid tag" value:nil table:@"SoundKit"]
#define LSTRING_PARAM_ERROR [_NSSKBundle localizedStringForKey:@"Bad parameter or value" value:nil table:@"SoundKit"]
#define LSTRING_UNKNOWN_ERROR [_NSSKBundle localizedStringForKey:@"Unknown error" value:nil table:@"SoundKit"]

/*
 * Rerun genstrings if you change this.
 */
+ (NSString *)textForError:(NXSoundDeviceError)errorCode
{
    /*
     * Create bundle if [NXApp new] not run.
     * ??? We should just have a _NSSKBundle() function in the kit... -aozer
     */
    if (!_NSSKBundle) {
        _NSSKBundle = [NSBundle bundleForClass:[NXSoundDevice class]];
    }

    switch (errorCode) {
      case NX_SoundDeviceErrorNone:
	return(LSTRING_NO_ERROR);
      case NX_SoundDeviceErrorKernel:
	return(LSTRING_KERNEL_ERROR);
      case NX_SoundDeviceErrorTimeout:
	return(LSTRING_TIMEOUT_ERROR);
      case NX_SoundDeviceErrorLookUp:
	return(LSTRING_LOOKUP_ERROR);
      case NX_SoundDeviceErrorHost:
	return(LSTRING_HOST_ERROR);
      case NX_SoundDeviceErrorNoDevice:
	return(LSTRING_NODEVICE_ERROR);
      case NX_SoundDeviceErrorNotActive:
	return(LSTRING_NOTACTIVE_ERROR);
      case NX_SoundDeviceErrorTag:
	return(LSTRING_TAG_ERROR);
      case NX_SoundDeviceErrorParameter:
	return(LSTRING_PARAM_ERROR);
      default:
	return(LSTRING_UNKNOWN_ERROR);
    }
}

+ (unsigned int)timeout
{
    return timeout;
}

+ setTimeout:(unsigned int)milliseconds
{
    timeout = milliseconds;
    return self;
}

+ (port_t)replyPort
{
    return replyPort;
}

+ (BOOL)isUsingSeparateThread
{
    return useSeparateThread;
}

+ setUseSeparateThread:(BOOL)flag
{
    /*
     * Currently can't change thread type after first instance
     * is inited.
     */
    if (flag == useSeparateThread)
	return self;
    else if (threadInitialized)
	return nil;
    else
	useSeparateThread = flag;
    return self;
}

+ (cthread_t)replyThread
{
    return replyThread;
}

+ (int)threadThreshold
{
    return threadThreshold;
}

+ setThreadThreshold:(int)threshold
{
    if (threadInitialized)
	return nil;
    else
	threadThreshold = threshold;
    return self;
}

/*
 * Initialize on local or remote host.
 * Returns nil if sound resources cannot be accessed.
 */
- (id)init
{
    NSString * hostName = (NSApp && [[NSProcessInfo processInfo] processName]) ? [[NSUserDefaults standardUserDefaults] objectForKey:@"NSHost"] : nil;
    return [self initOnHost:hostName ? hostName : @""];
}

- initOnHost:(NSString *)hostName
{
    [super init];

    /* Instance variable extension */
    (instVars *)_reserved = (instVars *)calloc(1, sizeof(instVars));

    _kernelError = port_allocate(task_self(), &_streamOwnerPort);
    if (_kernelError != KERN_SUCCESS) {
	NSLog(@"NXSoundDevice: port_allocate failed (%d), %s\n",
		   _kernelError, mach_error_string(_kernelError));
	 [self release];
	return nil;
    }
    _devicePort = [[self class] lookUpDevicePortOnHost:hostName];
    if (_devicePort) {
	_kernelError = initializeThread();
	setLastError();
    } else
	_lastError = NX_SoundDeviceErrorLookUp;
    /*
     * No way to check _lastError from API because we must return
     * nil - most likely means could not look up host on remote machine.
     */
    if (_lastError) {
	 [self release];
	return nil;
    } else {
	_host = [hostName copyWithZone:(NSZone *)[self zone]];
	return self;
    }
}

/*
 * Get host name.
 */
- (NSString *)host
{
    return _host;
}

/*
 * Get ports.
 */
- (port_t)devicePort
{
    return _devicePort;
}

- (port_t)streamOwnerPort
{
    return _streamOwnerPort;
}

/*
 * Get and set exclusive use.
 */
- (BOOL)isReserved
{
    port_t owner;

    _kernelError = _NXAudioGetExclusiveUser(_devicePort, &owner, timeout);
    if (!setLastError() && (owner == _streamOwnerPort))
	return YES;
    else
	return NO;
}

- (NXSoundDeviceError)setReserved:(BOOL)flag
{
    if (flag) {
	_kernelError = _NXAudioSetExclusiveUser(_devicePort, _streamOwnerPort,
						timeout);
	return setLastError();
    } else if ([self isReserved]) {
	_kernelError = _NXAudioSetExclusiveUser(_devicePort, PORT_NULL,
						timeout);
	return setLastError();
    } else
	return (_lastError = NX_SoundDeviceErrorNone);
}

/*
 * PRIVATE.
 * Get buffer options.
 */
- (NXSoundDeviceError)_getBufferOptions
{
    _kernelError = _NXAudioGetBufferOptions(_devicePort, &_bufferSize,
					    &_bufferCount, timeout);
    return setLastError();
}

/*
 * Get and set options.
 */
- (unsigned int)bufferSize
{
    [self _getBufferOptions];
    return _bufferSize;
}

- (NXSoundDeviceError)setBufferSize:(unsigned int)bytes
{
    if ([self _getBufferOptions])
	return _lastError;
    else {
	_kernelError = _NXAudioSetBufferOptions(_devicePort,
						_streamOwnerPort, bytes,
						_bufferCount, timeout);
	return setLastError();
    }
}

- (unsigned int)bufferCount
{
    [self _getBufferOptions];
    return _bufferCount;
}

- (NXSoundDeviceError)setBufferCount:(unsigned int)count
{
    if ([self _getBufferOptions])
	return _lastError;
    else {
	_kernelError = _NXAudioSetBufferOptions(_devicePort,
						_streamOwnerPort,
						_bufferSize,
						count, timeout);
	return setLastError();
    }
}

/*
 * Synchronized stream control.
 */
- (void)pauseStreams:sender
{
    _kernelError = _NXAudioControlStreams(_devicePort, _streamOwnerPort,
					  _NXAUDIO_STREAM_PAUSE, timeout);
    setLastError();
}

- (void)resumeStreams:sender
{
    _kernelError = _NXAudioControlStreams(_devicePort, _streamOwnerPort,
					  _NXAUDIO_STREAM_RESUME, timeout);
    setLastError();
}

- (void)abortStreams:sender
{
    _kernelError = _NXAudioControlStreams(_devicePort, _streamOwnerPort,
					  _NXAUDIO_STREAM_ABORT, timeout);
    setLastError();
}

/*
 * PRIVATE.
 * Get peak options.
 */
- (NXSoundDeviceError)_getPeakOptions
{
    _kernelError = _NXAudioGetDevicePeakOptions(_devicePort,
						&_isDetectingPeaks,
						&_peakHistory, timeout);
    return setLastError();
}

/*
 * Peak detection.
 * Default is NO peak detection.
 */
- (BOOL)isDetectingPeaks
{
    [self _getPeakOptions];
    return (BOOL)_isDetectingPeaks;
}

- (NXSoundDeviceError)setDetectPeaks:(BOOL)flag
{
    if ([self _getPeakOptions])
	return _lastError;
    else {
	_kernelError = _NXAudioSetDevicePeakOptions(_devicePort,
						    _streamOwnerPort,
						    (u_int)flag, _peakHistory,
						    timeout);
	return setLastError();
    }
}

- (unsigned int)peakHistory
{
    [self _getPeakOptions];
    return _peakHistory;
}

- (NXSoundDeviceError)setPeakHistory:(unsigned int)peakBufCount
{
    if ([self _getPeakOptions])
	return _lastError;
    else {
	_kernelError = _NXAudioSetDevicePeakOptions(_devicePort,
						    _streamOwnerPort,
						    _isDetectingPeaks,
						    peakBufCount, timeout);
	return setLastError();
    }
}

- (NXSoundDeviceError)getPeakLeft:(float *)leftAmp
                            right:(float *)rightAmp
{
    u_int magLeft, magRight;

    _kernelError = _NXAudioGetDevicePeak(_devicePort, &magLeft, &magRight,
					 timeout);
    if (!setLastError()) {
	*leftAmp = (float)magLeft / 32767.0;
	*rightAmp = (float)magRight / 32767.0;
    }
    return _lastError;
}

/*
 * Error handling.
 */
- (NXSoundDeviceError)lastError
{
    return _lastError;
}

/*
 * Release resources and free object.
 */
- (void)dealloc
{
    if (_streamOwnerPort)
	port_deallocate(task_self(), _streamOwnerPort);
    if (_devicePort) {
	[self setReserved:NO];
	/*
	 * FIXME: can't deallocate device port because other instances
	 * may have it in the same task.  This is a port send rights leak
	 * until app exits.
	 * port_deallocate(task_self(), _devicePort);
	 */
    }
    if (_reserved) {
	if (_retParams)
	     [_retParams release];
	if (_retTags)
	    free(_retTags);
	if (_retValues)
	    free(_retValues);
	if (_streamRates)
	    free(_streamRates);
	if (_streamEncodings)
	    free(_streamEncodings);
	[_name autorelease];
	free((instVars *)_reserved);
    }
    [_host autorelease];
    [super dealloc];
}

// New in 3.1

- (NSString *)name
{
    audio_name_t devName;
    u_int count = _NXAUDIO_PARAM_MAX;

    if (_name) {
	[_name autorelease];
	_name = nil;
    }
    _kernelError = _NXAudioGetDeviceName(_devicePort, devName, &count, [NXSoundDevice timeout]);
    if (setLastError() || count == 0) {
	return @"";
    } else {
	_name = [[NSString stringWithCString:devName length:count] copyWithZone:(NSZone *)[self zone]];
	return _name;
    }
}

- (id <NXSoundParameters>)parameters
{
    audio_array_t plist, vlist;
    u_int paramCount = _NXAUDIO_PARAM_MAX;
    int i;

    /*
     * Lifetime of returned object is until the next time
     * this method is invoked.
     */
    if (_retParams)
	 [_retParams release];
    _retParams = [[NXSoundParameters alloc] init];

    _kernelError =
	_NXAudioGetDeviceSupportedParameters(_devicePort,
					     plist, &paramCount,
					     [NXSoundDevice timeout]);
    if (setLastError() || (paramCount == 0))
	return nil;
    _kernelError =
	_NXAudioGetDeviceParameters(_devicePort, plist, paramCount, vlist,
				    [NXSoundDevice timeout]);
    if (setLastError())
	return nil;

    for (i = 0; i < paramCount; i++) {
	switch(plist[i]) {
	    /*
	     * Gains are 0 to 1.0 and need conversion from int.
	     */
	  case NX_SoundDeviceInputGainStereo:
	  case NX_SoundDeviceInputGainLeft:
	  case NX_SoundDeviceInputGainRight:
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

- (NXSoundDeviceError)setParameters:(id <NXSoundParameters>)params
{
    audio_array_t param_array;
    audio_array_t value_array;
    NXSoundParameterTag *plist;
    unsigned int numParams;
    int i;
    float floatVal;

    if (!params)
	return NX_SoundDeviceErrorNone;

    [params getParameters:&plist count:&numParams];
    if (numParams == 0)
	return NX_SoundDeviceErrorNone;

    for (i = 0; i < numParams; i++) {
	param_array[i] = plist[i];
	switch(plist[i]) {
	    /*
	     * Gains are 0 to 1.0 and need conversion to int.
	     */
	  case NX_SoundDeviceInputGainStereo:
	  case NX_SoundDeviceInputGainLeft:
	  case NX_SoundDeviceInputGainRight:
	    floatVal = [params floatValueForParameter:plist[i]];
	    value_array[i] = floatVal * 32768.0;
	    break;
	  default:
	    value_array[i] = [params intValueForParameter:plist[i]];
	    break;
	}
    }

    _kernelError =
	_NXAudioSetDeviceParameters(_devicePort, _streamOwnerPort,
				    param_array, numParams, value_array,
				    [NXSoundDevice timeout]);
    return setLastError();
}

- (BOOL)acceptsContinuousStreamSamplingRates
{
    int continuous, low, high;
    audio_array_t rlist;
    u_int rateCount = _NXAUDIO_PARAM_MAX;

    _kernelError =
	_NXAudioGetSamplingRates(_devicePort,
				 &continuous, &low, &high,
				 rlist, &rateCount,
				 [NXSoundDevice timeout]);
    if (setLastError())
	return NO;
    else
	return continuous;
}

- (NXSoundDeviceError)getStreamSamplingRatesLow:(float *)lowRate
    high:(float *)highRate
{
    int continuous, low, high;
    audio_array_t rlist;
    u_int rateCount = _NXAUDIO_PARAM_MAX;

    _kernelError =
	_NXAudioGetSamplingRates(_devicePort,
				 &continuous, &low, &high,
				 rlist, &rateCount,
				 [NXSoundDevice timeout]);
    if (setLastError())
	return _lastError;
    else {
	*lowRate = (float)low;
	*highRate = (float)high;
	return _lastError;
    }
}

- (NXSoundDeviceError)getStreamSamplingRates:(const float **)rates
    count:(unsigned int *)numRates;
{
    int continuous, low, high;
    audio_array_t rlist;
    int i;
    u_int rateCount = _NXAUDIO_PARAM_MAX;

    /*
     * Lifetime of returned array is until this method is called again.
     */
    if (_streamRates) {
	free(_streamRates);
	_streamRates = 0;
    }

    *numRates = 0;
    *rates = 0;
    _kernelError =
	_NXAudioGetSamplingRates(_devicePort,
				 &continuous, &low, &high,
				 rlist, &rateCount,
				 [NXSoundDevice timeout]);
    if (setLastError() || (rateCount == 0))
	return _lastError;

    _streamRates = (float *)malloc(rateCount * sizeof(float));
    for (i = 0; i < rateCount; i++)
	_streamRates[i] = rlist[i];
    *numRates = rateCount;
    *rates = _streamRates;
    return _lastError;
}

- (NXSoundDeviceError)getStreamDataEncodings:
    (const NXSoundParameterTag **)encodings
    count:(unsigned int *)numEncodings;
{
    audio_array_t elist;
    int i;
    u_int encodingsCount = _NXAUDIO_PARAM_MAX;

    /*
     * Lifetime of returned array is until this method is called again.
     */
    if (_streamEncodings) {
	free(_streamEncodings);
	_streamEncodings = 0;
    }

    *numEncodings = 0;
    *encodings = 0;
    _kernelError =
	_NXAudioGetDataEncodings(_devicePort,
				 elist, &encodingsCount,
				 [NXSoundDevice timeout]);
    if (setLastError() || (encodingsCount == 0))
	return _lastError;

    _streamEncodings =
	(NXSoundParameterTag *)malloc(encodingsCount *
				      sizeof(NXSoundParameterTag));
    for (i = 0; i < encodingsCount; i++)
	_streamEncodings[i] = elist[i];
    *numEncodings = encodingsCount;
    *encodings = _streamEncodings;
    return _lastError;
}

- (unsigned int)streamChannelCountLimit
{
    unsigned int count;

    _kernelError =
	_NXAudioGetChannelCountLimit(_devicePort, &count,
				     [NXSoundDevice timeout]);
    if (setLastError())
	return 0;
    else
	return count;
}

/*
 * Get clip count.
 */
- (unsigned int)clipCount
{
    u_int clips;

    _kernelError = _NXAudioGetClipCount(_devicePort, &clips, timeout);

    if (setLastError())
	return 0;
    else
	return clips;
}

/*
 * Support for NXSoundParameters protocol.
 */

/* Private */
- (BOOL)_getParam:(NXSoundParameterTag)ptag value:(int *)val
{
    audio_array_t param_array, value_array;

    param_array[0] = ptag;
    _kernelError =
	_NXAudioGetDeviceParameters(_devicePort,
				    param_array, 1, value_array,
				    [NXSoundDevice timeout]);
    if (setLastError())
	return NO;
    else {
	*val = value_array[0];
	return YES;
    }
}

/* Private */
- (void)_setParam:(NXSoundParameterTag)ptag toValue:(int)val
{
    audio_array_t param_array, value_array;

    param_array[0] = ptag;
    value_array[0] = val;
    _kernelError =
	_NXAudioSetDeviceParameters(_devicePort, _streamOwnerPort,
				    param_array, 1, value_array,
				    [NXSoundDevice timeout]);
    setLastError();
}

- (BOOL)boolValueForParameter:(NXSoundParameterTag)ptag
{
    int intVal;

    if ([self _getParam:ptag value:&intVal])
	return (BOOL)intVal;
    else
	return NO;
}

- (int)intValueForParameter:(NXSoundParameterTag)ptag
{
    int intVal;

    if ([self _getParam:ptag value:&intVal])
	return intVal;
    else
	return 0;
}

- (float)floatValueForParameter:(NXSoundParameterTag)ptag
{
    int intVal;

    if ([self _getParam:ptag value:&intVal]) {
	if (ptag == NX_SoundDeviceInputGainStereo ||
	    ptag == NX_SoundDeviceInputGainLeft ||
	    ptag == NX_SoundDeviceInputGainRight)
	    return (float)intVal / 32768.0;
	else
	    return (float)intVal;
    } else
	return 0.0;
}

- (void)setParameter:(NXSoundParameterTag)ptag toBool:(BOOL)flag
{
    return [self _setParam:ptag toValue:(int)flag];
}

- (void)setParameter:(NXSoundParameterTag)ptag toInt:(int)value
{
    return [self _setParam:ptag toValue:value];
}

- (void)setParameter:(NXSoundParameterTag)ptag toFloat:(float)value
{
    if (ptag == NX_SoundDeviceInputGainStereo ||
	ptag == NX_SoundDeviceInputGainLeft ||
	ptag == NX_SoundDeviceInputGainRight)
	return [self _setParam:ptag toValue:value * 32768.0];
    else
	return [self _setParam:ptag toValue:(int)value];
}

- (void)removeParameter:(NXSoundParameterTag)ptag
{
    /* Nothing to do */
    return;
}

- (BOOL)isParameterPresent:(NXSoundParameterTag)ptag
{
    int intVal;

    return [self _getParam:ptag value:&intVal];
}

- (void)getParameters:(const NXSoundParameterTag **)list
    count:(unsigned int *)numParameters
{
    audio_array_t param_array;
    u_int paramCount = _NXAUDIO_PARAM_MAX;
    int i;

    if (_retTags) {
	free(_retTags);
	_retTags = 0;
    }
    *numParameters = 0;
    *list = 0;
    _kernelError =
	_NXAudioGetDeviceSupportedParameters(_devicePort,
					     param_array, &paramCount,
					     [NXSoundDevice timeout]);
    if (setLastError() || (paramCount == 0))
	return;

    _retTags = (NXSoundParameterTag *)malloc(paramCount *
					     sizeof(NXSoundParameterTag));
    for (i = 0; i < paramCount; i++)
	_retTags[i] = param_array[i];
    *numParameters = paramCount;
    *list = _retTags;
}

- (void)getValues:(const NXSoundParameterTag **)list
    count:(unsigned int *)numValues forParameter:(NXSoundParameterTag)ptag
{
    audio_array_t value_array;
    u_int valueCount = _NXAUDIO_PARAM_MAX;
    int i;

    if (_retValues) {
	free(_retValues);
	_retValues = 0;
    }
    *numValues = 0;
    *list = 0;
    _kernelError =
	_NXAudioGetDeviceParameterValues(_devicePort, ptag,
					 value_array, &valueCount,
					 [NXSoundDevice timeout]);
    if (setLastError() || (valueCount == 0))
	return;

    _retValues = (NXSoundParameterTag *)malloc(valueCount *
					       sizeof(NXSoundParameterTag));
    for (i = 0; i < valueCount; i++)
	_retValues[i] = value_array[i];
    *numValues = valueCount;
    *list = _retValues;
}

@end

/*

Created by Mike Minnick 07/12/91.

Modification History:

02/10/92/mtm	Remove delegate API (bug 18497).
02/27/92/mtm	Call objc_setMultithreaded(YES).
03/10/92/mtm	Change delegateThread to replyThread (bug #19329)
01/20/93/mtm	3.1 api.
 10/7/93 aozer	Changed to use NSString.

*/
