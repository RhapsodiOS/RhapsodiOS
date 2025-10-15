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
 * NXRecordStream.m.
 *
 * Record sound data.
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved. 
 */

#import "NXRecordStream.h"
#import "NXSoundDevice.h"
#import "NXSound_Private.h"
#import "audio.h"

@implementation NXRecordStream

// Obsoleted for 3.1.
/*
 * Enqueue recording buffer.
 * Negative tags are reserved.
 */
- (NXSoundDeviceError)recordSize:(unsigned int)bytes tag:(int)tag
                    lowWaterMark:(unsigned int)lowWater
                   highWaterMark:(unsigned int)highWater
{
    _kernelError = _NXAudioRecordStream(_streamPort, bytes, tag,
					lowWater, highWater,
					[NXSoundDevice replyPort],
					_delegateMessages,
					[NXSoundDevice timeout]);
    return setLastError();
}

/*
 * Record with default water marks.  LowWaterMark
 * defaults to (48*1024) and highWaterMark defaults to (64*1024).
 */
- (NXSoundDeviceError)recordSize:(unsigned int)bytes tag:(int)tag
{
    _kernelError = _NXAudioRecordStreamData(_streamPort, bytes, tag,
					    [NXSoundDevice replyPort],
					    _delegateMessages,
					    [NXSoundDevice timeout]);
    return setLastError();
}

/*
 * Stream control.
 */
- (NXSoundDeviceError)sendRecordedDataToDelegate
{
    NXSoundStreamTime now = {0,0};

    if (!_isActive)
	return (_lastError = NX_SoundDeviceErrorNotActive);
    _kernelError = _NXAudioStreamControl(_streamPort,
					 _NXAUDIO_STREAM_RETURN_DATA,
					 now, [NXSoundDevice timeout]);
    return setLastError();
}

@end

/*

Created by Mike Minnick 07/12/91.

Modification History:

01/22/93/mtm	3.1 api.

*/
