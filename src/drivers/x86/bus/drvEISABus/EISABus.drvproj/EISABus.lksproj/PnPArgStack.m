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
 * PnP BIOS Argument Stack Builder Implementation
 */

#import "PnPArgStack.h"
#import <driverkit/generalFuncs.h>
#import <string.h>

/*
 * Global variables for PnP entry point argument tracking
 * These track the current state of the argument stack
 */
int PnPEntry_argStackBase = 0;  /* Pointer to base of argument stack */
int PnPEntry_numArgs = 0;       /* Number of arguments pushed */

@implementation PnPArgStack

/*
 * Initialize with data segment base and selector
 *
 * Sets up the argument stack with DS segment information.
 * Calls reset to initialize the stack to empty state (top = 20).
 *
 * @param data      Pointer to DS segment base
 * @param selector  DS segment selector
 * @return          Initialized object or nil on failure
 */
- initWithData:(void *)data Selector:(unsigned short)selector
{
    [super init];

    /* Reset stack to empty state */
    [self reset];

    /* Store DS segment base and selector */
    DSBase = data;
    DS = selector;

    return self;
}

/*
 * Reset the stack to initial state
 *
 * Sets top to 20 (empty downward-growing stack) and clears
 * the global argument tracking variables.
 */
- (void)reset
{
    /* Clear global tracking variables */
    PnPEntry_argStackBase = 0;
    PnPEntry_numArgs = 0;

    /* Initialize stack to empty (top = 20 = full stack pointer) */
    top = 20;
}

/*
 * Push a 16-bit value onto the stack
 *
 * Decrements the top index (downward-growing stack) and writes the value.
 * Updates global pointers to track the current stack state.
 * If stack is full (top = 0), logs an error.
 *
 * @param value  The 16-bit value to push
 */
- (void)push:(unsigned short)value
{
    /* Check if stack is full (top = 0 means no more space) */
    if (top == 0) {
        IOLog("PnPArgStack: stack is full, can't push %d\n", value);
        return;
    }

    /* Pre-decrement top (downward-growing stack) */
    top--;

    /* Write value to stack */
    args[top] = value;

    /* Update global tracking variables */
    PnPEntry_argStackBase = (int)&args[top];
    PnPEntry_numArgs = 20 - top;
}

/*
 * Push a far pointer onto the stack
 *
 * Validates that the pointer is within the DS segment bounds (< 64KB offset),
 * calculates the offset relative to DSBase, and pushes as segment:offset.
 * Pushes DS selector first, then the offset (both as 16-bit values).
 *
 * @param ptr  Pointer to push as a far pointer
 */
- (void)pushFarPtr:(void *)ptr
{
    int offset;

    /* Calculate offset relative to DSBase */
    offset = (int)ptr - (int)DSBase;

    /* Validate that offset is within segment bounds (16-bit offset, 0-64K) */
    if (offset > 0x10000) {
        IOLog("PnPArgStack: trying to push an address beyond the segment\n");
        return;
    }

    /* Check if we have space for 2 words (segment + offset) */
    if (top <= 1) {
        IOLog("PnPArgStack: stack is full, can't push pointer\n");
        return;
    }

    /* Push segment selector first */
    [self push:DS];

    /* Push offset (relative to DSBase) */
    [self push:(unsigned short)offset];
}

@end
