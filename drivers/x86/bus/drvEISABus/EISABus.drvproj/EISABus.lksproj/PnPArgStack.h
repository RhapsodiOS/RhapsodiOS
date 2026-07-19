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
 * PnPArgStack.h
 * PnP BIOS Argument Stack Builder
 *
 * This class manages a downward-growing stack for building argument structures
 * to pass to PnP BIOS calls. The stack grows from index 19 down to 0.
 * It maintains global pointers to the current stack base and argument count.
 */

#ifndef _PNPARGSTACK_H_
#define _PNPARGSTACK_H_

#import <objc/Object.h>

/*
 * Global variables for PnP entry point argument tracking
 * These are updated by push operations to point to the current stack state
 */
extern int PnPEntry_argStackBase;   /* Pointer to base of argument stack */
extern int PnPEntry_numArgs;        /* Number of arguments pushed */

@interface PnPArgStack : Object
{
    @private
    unsigned short args[20];    /* Argument stack buffer (40 bytes) */
    int top;                    /* Stack pointer (index into args array) */
    void *DSBase;               /* DS segment base pointer */
    unsigned short DS;          /* DS segment selector */
}

/*
 * Initialize with data segment base and selector
 *
 * @param data      Pointer to DS segment base
 * @param selector  DS segment selector
 * @return          Initialized object or nil on failure
 */
- initWithData:(void *)data Selector:(unsigned short)selector;

/*
 * Reset the stack to initial state
 * Sets top to 20 (empty stack) and clears global counters
 */
- (void)reset;

/*
 * Push a 16-bit value onto the stack
 *
 * @param value  The 16-bit value to push
 */
- (void)push:(unsigned short)value;

/*
 * Push a far pointer onto the stack
 * Validates that the pointer is within the DS segment, calculates the offset
 * relative to DSBase, and pushes segment:offset
 *
 * @param ptr  Pointer to push as a far pointer
 */
- (void)pushFarPtr:(void *)ptr;

@end

#endif /* _PNPARGSTACK_H_ */
