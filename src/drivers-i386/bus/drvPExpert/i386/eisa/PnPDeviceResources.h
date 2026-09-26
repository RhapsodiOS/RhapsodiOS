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
 * PnPDeviceResources.h
 * PnP Device Resource Collection
 */

#ifndef _PNPDEVICERESOURCES_H_
#define _PNPDEVICERESOURCES_H_

#import <objc/Object.h>

/* PnPDeviceResources - Device resource collection */
@interface PnPDeviceResources : Object
{
    @private
    id _deviceList;                /* List of logical devices at offset 0x04 */
    char _deviceName[80];          /* Device name inline buffer at offset 0x08 (79 chars + null) */
    int _deviceNameLength;         /* Length of device name at offset 0x58 (88) */
    unsigned int _id;              /* Device ID at offset 0x5C (92) */
    unsigned int _serialNumber;    /* Serial number at offset 0x60 (96) */
    int _csn;                      /* Card Select Number at offset 0x64 (100) */
}

/*
 * Class methods
 */
+ (void)setReadPort:(unsigned short)port;
+ (void)setVerbose:(char)verboseFlag;

/*
 * Initialization
 */
- initForBuf:(void *)buffer Length:(int)length CSN:(int)csn;
- initForBufNoHeader:(void *)buffer Length:(int)length CSN:(int)csn;
- free;

/*
 * Device information
 */
- (unsigned int)ID;
- setID:(unsigned int)deviceID;
- (unsigned int)serialNumber;
- setSerialNumber:(unsigned int)serial;
- (int)csn;

/*
 * Logical devices
 */
- (int)deviceCount;
- deviceList;
- deviceWithID:(int)logicalDeviceID;

/*
 * Device name
 */
- (const char *)deviceName;
- setDeviceName:(const char *)name Length:(int)length;

/*
 * Configuration parsing
 */
- parseConfig:(void *)buffer Length:(int)length;

@end

#endif /* _PNPDEVICERESOURCES_H_ */
