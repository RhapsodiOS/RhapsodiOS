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
 * PnP Argument Stack Implementation
 */

#import "PnPArgStack.h"
#import <driverkit/generalFuncs.h>

/* External globals for PnP argument passing */
extern int PnPEntry_argStackBase;
extern int PnPEntry_numArgs;

@implementation PnPArgStack

/*
 * Initialize with data buffer and selector
 */
- initWithData:(void *)data Selector:(unsigned short)selector
{
    /* Call superclass init */
    [super init];

    /* Reset the stack */
    [self reset];

    /* Store data pointer and selector */
    _data = data;
    _selector = selector;

    return self;
}

/*
 * Reset the stack
 */
- reset
{
    /* Reset global PnP entry points */
    PnPEntry_argStackBase = 0;
    PnPEntry_numArgs = 0;

    /* Initialize stack counter to 20 (0x14) entries */
    _stackCount = 0x14;

    return self;
}

/*
 * Push a value onto the stack
 */
- push:(unsigned short)value
{
    /* Check if stack is full */
    if (_stackCount == 0) {
        IOLog("PnPArgStack: stack is full, can't push %d\n", value);
        return;
    }

    /* Decrement stack counter (stack grows downward) */
    _stackCount--;

    /* Store value in stack at current position */
    _stack[_stackCount] = value;

    /* Update global PnP entry base pointer to current stack position */
    PnPEntry_argStackBase = (int)&_stack[_stackCount];

    /* Update number of arguments on stack */
    PnPEntry_numArgs = 0x14 - _stackCount;
}

/*
 * Push a far pointer onto the stack (segment:offset)
 */
- pushFarPtr:(void *)ptr
{
    int offset;

    /* Calculate offset from data base */
    offset = (int)ptr - (int)_data;

    /* Check if address is within segment (< 64K + 1) */
    if (offset < 0x10001) {
        /* Check if we have room for 2 pushes (segment and offset) */
        if (_stackCount < 2) {
            IOLog("PnPArgStack: stack is full, can't push pointer\n");
        } else {
            /* Push selector (segment) */
            [self push:_selector];

            /* Push offset within segment (cast to short for proper calculation) */
            [self push:(unsigned short)((short)ptr - (short)_data)];
        }
    } else {
        IOLog("PnPArgStack: trying to push an address beyond the segment\n");
    }
}

@end
