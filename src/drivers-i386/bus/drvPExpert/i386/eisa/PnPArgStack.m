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
 * PnPArgStack.m
 * Argument marshalling for PnP BIOS calls
 */

#import "PnPArgStack.h"
#import "bios.h"
#import <driverkit/generalFuncs.h>

@implementation PnPArgStack

/*
 * Reference: -[PnPArgStack initWithData:Selector:] at 0x3ba8, 79 bytes.
 * Note the order: [super init], then -reset, then the two stores.
 */
- initWithData:(void *)data Selector:(unsigned short)selector
{
    [super init];
    [self reset];

    _dataBase = data;
    _selector = selector;

    return self;
}

/*
 * Reference: -[PnPArgStack reset] at 0x3bf8, 37 bytes.
 */
- reset
{
    PnPEntry_argStackBase = 0;
    PnPEntry_numArgs = 0;
    _remaining = PNPARGSTACK_DEPTH;

    return self;
}

/*
 * Reference: -[PnPArgStack push:] at 0x3c20, 84 bytes.
 *
 * The frame fills downwards, so _remaining doubles as the index of the
 * most recently pushed word.  _PnPEntry replays base[numArgs-1] first and
 * base[0] last, which reproduces the caller's push order on the real
 * stack: first pushed ends up deepest, last pushed ends up on top.
 */
- push:(unsigned short)value
{
    if (_remaining == 0) {
        IOLog("PnPArgStack: stack is full, can't push %d\n", (int)value);
    } else {
        _remaining--;
        _args[_remaining] = value;
        PnPEntry_argStackBase = &_args[_remaining];
        PnPEntry_numArgs = PNPARGSTACK_DEPTH - _remaining;
    }

    return self;
}

/*
 * Reference: -[PnPArgStack pushFarPtr:] at 0x3c74, 108 bytes.
 *
 * The range test is the reference's signed `cmp eax, 0x10000 / jle`, and
 * the offset is its 16-bit `sub ax, [ebx+0x30]`; both are reproduced as
 * written rather than tightened.
 */
- pushFarPtr:(void *)pointer
{
    int offset;

    offset = (int)((char *)pointer - (char *)_dataBase);

    if (offset > 0x10000) {
        IOLog("PnPArgStack: trying to push an address beyond the segment\n");
        return self;
    }

    if (_remaining <= 1) {
        IOLog("PnPArgStack: stack is full, can't push pointer\n");
        return self;
    }

    [self push:_selector];
    [self push:(unsigned short)offset];

    return self;
}

@end
