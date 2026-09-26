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
 * IODeviceMaster.h
 * Device Master Interface
 */

#import <objc/Object.h>
#import <mach/mach.h>

@interface IODeviceMaster : Object
{
    port_t deviceMasterPort;
}

+ new;
- createMachPort:(port_t *)port objectNumber:(unsigned int)objNum;
- free;
- (int)getCharValues:(char **)values forParameter:(const char *)param objectNumber:(unsigned int)objNum count:(unsigned int *)count;
- (int)getIntValues:(unsigned int *)values forParameter:(const char *)param objectNumber:(unsigned int)objNum count:(unsigned int *)count;
- (int)lookUpByDeviceName:(const char *)name objectNumber:(unsigned int *)objNum deviceKind:(const char **)kind;
- (int)lookUpByObjectNumber:(unsigned int)objNum deviceKind:(const char **)kind deviceName:(const char **)name;
- (int)setCharValues:(const char **)values forParameter:(const char *)param objectNumber:(unsigned int)objNum count:(unsigned int)count;
- (int)setIntValues:(const unsigned int *)values forParameter:(const char *)param objectNumber:(unsigned int)objNum count:(unsigned int)count;

@end
