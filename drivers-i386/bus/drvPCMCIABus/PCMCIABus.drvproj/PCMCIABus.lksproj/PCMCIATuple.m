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
 * PCMCIA Tuple Implementation
 */

#import "PCMCIATuple.h"
#import <libkern/libkern.h>

@implementation PCMCIATuple

/*
 * Initialize from data
 */
- initFromData:(void *)data length:(unsigned int)length
{
    void *buffer;

    [super init];

    /* Set length */
    _length = length;

    /* Allocate buffer */
    buffer = IOMalloc(length);
    _data = buffer;

    /* Copy data */
    bcopy(data, buffer, length);

    /* Set length again (matches decompiled code) */
    _length = length;

    return self;
}

/*
 * Free tuple
 */
- free
{
    /* Free data buffer */
    IOFree(_data, _length);

    /* Call superclass free */
    return [super free];
}

/*
 * Get tuple code (first byte of data)
 */
- (unsigned char)code
{
    return *((unsigned char *)_data);
}

/*
 * Get tuple data pointer
 */
- (void *)data
{
    return _data;
}

/*
 * Get tuple length
 */
- (unsigned int)length
{
    return _length;
}

@end
