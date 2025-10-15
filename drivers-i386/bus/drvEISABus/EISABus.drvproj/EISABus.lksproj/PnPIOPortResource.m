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
 * PnPIOPortResource.m
 * PnP I/O Port Resource Descriptor Implementation
 */

#import "PnPIOPortResource.h"

@implementation PnPIOPortResource

- init
{
    [super init];
    _minBase = 0;
    _maxBase = 0;
    _alignment = 1;
    _length = 0;
    _flags = 0;
    return self;
}

- free
{
    return [super free];
}

- (void)setMinBase:(unsigned int)base
{
    _minBase = base;
}

- (void)setMaxBase:(unsigned int)base
{
    _maxBase = base;
}

- (void)setAlignment:(unsigned char)align
{
    _alignment = align;
}

- (void)setLength:(unsigned char)len
{
    _length = len;
}

- (void)setFlags:(unsigned char)flags
{
    _flags = flags;
}

- (unsigned int)minBase
{
    return _minBase;
}

- (unsigned int)maxBase
{
    return _maxBase;
}

- (unsigned char)alignment
{
    return _alignment;
}

- (unsigned char)length
{
    return _length;
}

- (unsigned char)flags
{
    return _flags;
}

@end
