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
 * pnpMemory.h
 * PnP Memory Resource Descriptor
 */

#ifndef _PNPMEMORY_H_
#define _PNPMEMORY_H_

#import <objc/Object.h>

/* pnpMemory - Memory range resource descriptor */
@interface pnpMemory : Object
{
    @private
    unsigned int _min_base;           /* Minimum base address at offset 0x04 */
    unsigned int _max_base;           /* Maximum base address at offset 0x08 */
    unsigned int _alignment;          /* Alignment at offset 0x0c */
    unsigned int _length;             /* Length at offset 0x10 */
    unsigned char _expROM;            /* Expansion ROM flag at offset 0x14 */
    unsigned char _shadow;            /* Shadow flag at offset 0x15 */
    unsigned char _highAddressDecode; /* High address decode flag at offset 0x16 */
    unsigned char _padding;           /* Padding at offset 0x17 */
    unsigned char _ROM;               /* ROM flag at offset 0x18 */
    unsigned char _bit8;              /* 8-bit flag at offset 0x19 */
    unsigned char _bit16;             /* 16-bit flag at offset 0x1a */
    unsigned char _bit32;             /* 32-bit flag at offset 0x1b */
    unsigned char _is32;              /* 32-bit memory flag at offset 0x1c */
}

/*
 * Initialization
 */
- initFrom:(void *)buffer Length:(int)length Type:(int)type;
- initWithBase:(unsigned int)base
        Length:(unsigned int)length
         Bit16:(BOOL)bit16
         Bit32:(BOOL)bit32
      HighAddr:(BOOL)highAddr
          Is32:(BOOL)is32;

/*
 * Memory information
 */
- (unsigned int)min_base;
- (unsigned int)max_base;
- (unsigned int)alignment;
- (unsigned int)length;
- (BOOL)bit8;
- (BOOL)bit16;
- (BOOL)bit32;
- (BOOL)is32;
- (BOOL)highAddressDecode;
- (BOOL)matches:(id)otherMemory;

/*
 * Configuration
 */
- setControl:(unsigned char)control;

/*
 * Output
 */
- print;

/*
 * Configuration
 */
- writePnPConfig:(id)memoryObject Index:(int)index;

@end

#endif /* _PNPMEMORY_H_ */
