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
 * NXSoundStream.h
 *
 * Copyright (c) 1992, NeXT Computer, Inc.  All rights reserved. 
 */

#import <sys/time.h>
#import <mach/mach.h>
#import "NXSoundDevice.h"
#import "NXSoundParameters.h"

// Obsolete, use struct timeval.
typedef struct timeval NXSoundStreamTime;

#define NX_SOUNDSTREAM_TIME_NULL ((struct timeval *)0)

@interface NXSoundStream : NSObject
{
    id			delegate;
    BOOL		_isActive;
    BOOL		_isPaused;
    id			_device;
    port_t		_streamPort;
    unsigned int	_delegateMessages;
    kern_return_t	_kernelError;
    NXSoundDeviceError	_lastError;
    int			_reserved;
}

// New in 3.1.
- (id)initOnDevice:(id)aDevice withParameters:(id <NXSoundParameters>)params;
- (id <NXSoundParameters>)parameters;

- (id)init;
- (id)initOnDevice:(id)anObject;
- (id)device;
- (NXSoundDeviceError)setDevice:(id)anObject;
- (port_t)streamPort;
- (BOOL)isActive;
- (NXSoundDeviceError)activate;
- (NXSoundDeviceError)deactivate;
- (BOOL)isPaused;
- (void)pause:(id)sender;
- (void)resume:(id)sender;
- (void)abort:(id)sender;
- (NXSoundDeviceError)pauseAtTime:(struct timeval *)time;
- (NXSoundDeviceError)resumeAtTime:(struct timeval *)time;
- (NXSoundDeviceError)abortAtTime:(struct timeval *)time;
- (unsigned int)bytesProcessed;
- (NXSoundDeviceError)lastError;
- (id)delegate;
- (void)setDelegate:(id)anObject;
- (void)dealloc;

@end

@interface NSObject (NXSoundStreamDelegate)
- (void)soundStream:(id)sender didStartBuffer:(int)tag;
- (void)soundStream:(id)sender didCompleteBuffer:(int)tag;
- (void)soundStreamDidPause:(id)sender;
- (void)soundStreamDidResume:(id)sender;
- (void)soundStreamDidAbort:(id)sender deviceReserved:(BOOL)flag;
@end
