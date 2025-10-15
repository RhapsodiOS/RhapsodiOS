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
 * NXSoundIn.m
 *
 * Interface to sound recording resources.
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved. 
 */

#import "NXSoundIn.h"
#import "audio.h"

@implementation NXSoundIn

/*
 * Look up the sound-in device port.
 * Returns PORT_NULL if look up fails.
 * Only sent by NXSoundDevice -initOnHost (private in 3.1).
 */
+ (port_t)lookUpDevicePortOnHost:(NSString *)hostName
{
    port_t devPort;
    kern_return_t kerr;

    kerr = _NXAudioSoundinLookup([hostName cString], &devPort);
    if (kerr == KERN_SUCCESS)
	return devPort;
    else
	return PORT_NULL;
}

@end

/*

Created by Mike Minnick 07/12/91.

Modification History:

01/22/92/mtm	3.1 changes.
 10/7/93 aozer	Changed to use NSString.

*/
