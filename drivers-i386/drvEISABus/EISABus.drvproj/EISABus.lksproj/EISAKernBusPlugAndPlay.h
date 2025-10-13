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
 * EISAKernBusPlugAndPlay.h
 * EISA Plug and Play Support Header
 */

#ifndef _EISAKERNBUSPLUGANDPLAY_H_
#define _EISAKERNBUSPLUGANDPLAY_H_

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>

@interface EISAKernBusPlugAndPlay : IODevice
{
    @private
    void *_pnpData;
    BOOL _initialized;
    unsigned int _isolationPort;
    unsigned int _addressPort;
    unsigned int _writeDataPort;
    unsigned int _readDataPort;
    int _csn;  /* Card Select Number */
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/* PnP operations */
- (BOOL)initiatePnP;
- (BOOL)isolateCards;
- (int)assignCSN:(int)logicalDevice;
- (BOOL)configureDevice:(int)csn logical:(int)logical;

/* Resource reading */
- (void *)readResourceData:(int)csn;
- (void)freeResourceData:(void *)resources;

@end

#endif /* _EISAKERNBUSPLUGANDPLAY_H_ */
