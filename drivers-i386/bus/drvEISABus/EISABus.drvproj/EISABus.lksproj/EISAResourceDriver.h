/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * EISAResourceDriver.h
 * EISA Resource Driver Header
 */

#ifndef _EISARESOURCEDRIVER_H_
#define _EISARESOURCEDRIVER_H_

#import <driverkit/IODirectDevice.h>

/*
 * EISAResourceDriver - Manages EISA device resources
 */
@interface EISAResourceDriver : IODirectDevice
{
    @private
    char _idBuffer[512];      /* Buffer for ID strings at offset 0x128 */
    int _bufferLength;        /* Buffer length at offset 0x328 */
    BOOL _isEISA;            /* EISA vs PnP flag at offset 0x32c */
}

/*
 * Initialization
 */
- initFromDeviceDescription:deviceDescription;

/*
 * Parameter access
 */
- (IOReturn)getCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int *)count;

- (IOReturn)setCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int)count;

/*
 * Boot flag setup
 */
- setupBootFlag;

@end

#endif /* _EISARESOURCEDRIVER_H_ */
