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
 * NXSound_Private.h
 *
 * PRIVATE header file for nxsound objects.
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved. 
 */

#import "NXSoundDevice.h"
#import "NXSoundStream.h"

/*
 * Macro to set _lastError based on _kernelError.
 */
#define	setLastError()	\
    (_kernelError == _NXAUDIO_SUCCESS ? \
     (_lastError = NX_SoundDeviceErrorNone) : \
     (_lastError = [NXSoundDevice _convertToSoundDeviceError:_kernelError]))

/*
 * NXSoundDevice private interface.
 */
@interface NXSoundDevice(NXSoundDevicePrivate)
+ (NXSoundDeviceError)_convertToSoundDeviceError:(kern_return_t)kernelError;
+ (port_t)lookUpDevicePortOnHost:(NSString *)hostName;
@end

/*
 * NXSoundStream private interface.
 */
@interface NXSoundStream(NXSoundStreamPrivate)
- _replyToDelegateStatus:(int)status forBuffer:(int)tag;
- _replyToDelegateRecordedData:(void *)data size:(unsigned int)bytes
                     forBuffer:(int)tag;

@end

